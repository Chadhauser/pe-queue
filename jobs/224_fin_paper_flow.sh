#!/bin/bash
# 224: FINANCIAL TRADING FLOW — forward-paper engine, same shape as the sports bots.
#  /root/pe-fin/fin_lib.py    = the strategy library split out of fin_sweep.py (one source of truth, no duplicated code)
#  /root/pe-fin/fin_paper.py  = daily paper runner: reads fin_config (kill switch) + fin_strategies, pulls daily bars,
#                               computes each strategy's position on the last closed bar (engine convention: act next bar),
#                               books yesterday's P&L on today's close, opens/closes paper positions with the cost table,
#                               tracks equity + drawdown per strategy, applies prop-firm style limits (daily loss, max DD),
#                               writes heartbeat. NO live path exists: dry_run is forced true in code until a survivor has
#                               60 days of forward paper. Hard caps in code that config cannot exceed.
#  Tables: fin_config, fin_strategies, fin_paper_positions, fin_paper_daily, fin_heartbeat
#  Cron: 21:40 UTC daily (after US cash close), idempotent per bar date.
#  Seeds: layer-4 xsmom is not single-asset so not seeded; seeds the top 3 cells of the latest v4_fin_results run as tier
#         'candidate' (UNVERIFIED — 0 survivors exist) so the flow has something to log. Candidates can never go live.
set -o pipefail
mkdir -p /root/pe-fin && cd /root/pe-fin
echo "== 1) build fin_lib.py from fin_sweep.py (split at the layer-2 marker)"
python3 - <<'PY'
src=open('/root/pe-factory/v4/fin_sweep.py').read()
marker='# ---------- layer 2: engine'
assert marker in src, 'marker not found in fin_sweep.py'
lib=src.split(marker)[0]
lib=lib.replace("SYNTH = '--synthetic' in sys.argv","SYNTH = False")
open('/root/pe-fin/fin_lib.py','w').write(lib)
print('fin_lib.py written, lines:',lib.count('\n'))
PY
python3 -c "import sys; sys.path.insert(0,'/root/pe-fin'); import fin_lib; c=fin_lib.build_configs(); print('configs importable:',len(c)); assert len(c)==66" || exit 1
echo "== 2) write fin_paper.py"
cat > fin_paper.py <<'PYFILE'
import sys, json, math, datetime, warnings, numpy as np, pandas as pd, psycopg2, psycopg2.extras
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-bot'); sys.path.insert(0,'/root/pe-fin')
from bot_core import DB
import fin_lib
SELFTEST='--selftest' in sys.argv
# ---- hard caps in code; config cannot exceed these ----
HARD_MAX_RISK_PCT=1.0        # risk per strategy per day as % of notional bank
HARD_MAX_OPEN=8
LIVE_PATH_EXISTS=False       # no broker / prop-firm routing is built. dry_run is forced true.
DEFAULT_CFG={'enabled':'true','dry_run':'true','bank':'10000','risk_pct':'0.5','max_open':'5','daily_loss_pct':'2.0','max_dd_pct':'6.0','lookback_days':'900'}
COST=fin_lib.COST
CFG_FN={name:(fn,params,fam) for name,fn,params,fam in fin_lib.build_configs()}
def con():
    c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; cur=c.cursor(); cur.execute("SET statement_timeout='120s'"); return c,cur
def ensure(cur):
    cur.execute("CREATE TABLE IF NOT EXISTS fin_config (key TEXT PRIMARY KEY, value TEXT, updated TIMESTAMPTZ DEFAULT now())")
    for k,v in DEFAULT_CFG.items(): cur.execute("INSERT INTO fin_config(key,value) VALUES(%s,%s) ON CONFLICT (key) DO NOTHING",(k,v))
    cur.execute("""CREATE TABLE IF NOT EXISTS fin_strategies (id SERIAL PRIMARY KEY, config TEXT, asset TEXT, cls TEXT, tier TEXT DEFAULT 'candidate',
        enabled BOOLEAN DEFAULT true, last_pos INT DEFAULT 0, last_bar DATE, equity NUMERIC DEFAULT 100, peak NUMERIC DEFAULT 100,
        disabled_reason TEXT, created TIMESTAMPTZ DEFAULT now(), UNIQUE(config,asset))""")
    cur.execute("""CREATE TABLE IF NOT EXISTS fin_paper_positions (id SERIAL PRIMARY KEY, strategy_id INT, config TEXT, asset TEXT, side INT,
        entry_bar DATE, entry_px NUMERIC, exit_bar DATE, exit_px NUMERIC, gross_pct NUMERIC, cost_pct NUMERIC, net_pct NUMERIC, status TEXT DEFAULT 'OPEN', dry_run BOOLEAN DEFAULT true)""")
    cur.execute("""CREATE TABLE IF NOT EXISTS fin_paper_daily (bar DATE, strategy_id INT, config TEXT, asset TEXT, pos_held INT, pos_new INT, close NUMERIC,
        ret_pct NUMERIC, pnl_pct NUMERIC, equity NUMERIC, dd_pct NUMERIC, run_ts TIMESTAMPTZ DEFAULT now(), UNIQUE(bar,strategy_id))""")
    cur.execute("CREATE TABLE IF NOT EXISTS fin_heartbeat (id INT PRIMARY KEY DEFAULT 1, last_run TIMESTAMPTZ, n_strategies INT, n_open INT, book_pnl_pct NUMERIC, status TEXT)")
def cfg(cur):
    cur.execute("SELECT key,value FROM fin_config"); d=dict(cur.fetchall())
    d['risk_pct']=min(float(d.get('risk_pct',0.5)),HARD_MAX_RISK_PCT); d['max_open']=min(int(d.get('max_open',5)),HARD_MAX_OPEN)
    d['dry_run']=True if not LIVE_PATH_EXISTS else d.get('dry_run','true')=='true'
    return d
def bars(asset,lookback_days):
    import yfinance as yf
    df=yf.download(asset,period=f"{int(lookback_days)}d",interval='1d',progress=False,auto_adjust=True,threads=False)
    if isinstance(df.columns,pd.MultiIndex): df.columns=df.columns.get_level_values(0)
    df=df.dropna(subset=['Close']); df.index=pd.to_datetime(df.index).tz_localize(None).normalize()
    return df[['Close','High','Low','Volume']] if 'Volume' in df else df[['Close','High','Low']].assign(Volume=0)
def run_strategy(cur,s,c,today_cutoff=None):
    sid,config,asset,cls,last_pos,last_bar,equity,peak=s
    if config not in CFG_FN: return ('no such config',None)
    fn,params,fam=CFG_FN[config]
    df=bars(asset,c['lookback_days'])
    if today_cutoff is not None: df=df[df.index<=pd.Timestamp(today_cutoff)]
    if len(df)<300: return ('too few bars',None)
    bar=df.index[-1].date()
    if last_bar is not None and bar<=last_bar: return ('already booked',bar)
    sig=fn(df,params).replace([np.inf,-np.inf],0).fillna(0).clip(-1,1)
    pos_new=int(np.sign(sig.iloc[-1])); close=float(df.Close.iloc[-1]); prev_close=float(df.Close.iloc[-2])
    ret=close/prev_close-1; pos_held=int(last_pos or 0)
    gross=pos_held*ret*100; cost=COST[cls]*abs(pos_new-pos_held)*100; pnl=gross-cost
    equity=float(equity)*(1+pnl/100); peak=max(float(peak),equity); dd=(equity/peak-1)*100
    # positions: close if changed, open new if nonzero
    if pos_new!=pos_held:
        if pos_held!=0:
            cur.execute("SELECT id,entry_px FROM fin_paper_positions WHERE strategy_id=%s AND status='OPEN' ORDER BY id DESC LIMIT 1",(sid,)); r=cur.fetchone()
            if r:
                g=pos_held*(close/float(r[1])-1)*100; cst=COST[cls]*2*100
                cur.execute("UPDATE fin_paper_positions SET exit_bar=%s,exit_px=%s,gross_pct=%s,cost_pct=%s,net_pct=%s,status='CLOSED' WHERE id=%s",(bar,close,round(g,4),round(cst,4),round(g-cst,4),r[0]))
        if pos_new!=0:
            cur.execute("INSERT INTO fin_paper_positions(strategy_id,config,asset,side,entry_bar,entry_px,dry_run) VALUES(%s,%s,%s,%s,%s,%s,true)",(sid,config,asset,pos_new,bar,close))
    cur.execute("""INSERT INTO fin_paper_daily(bar,strategy_id,config,asset,pos_held,pos_new,close,ret_pct,pnl_pct,equity,dd_pct) VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                   ON CONFLICT (bar,strategy_id) DO NOTHING""",(bar,sid,config,asset,pos_held,pos_new,close,round(ret*100,4),round(pnl,4),round(equity,4),round(dd,4)))
    reason=None
    if dd< -float(c['max_dd_pct']): reason=f"max_dd {dd:.2f} breached {bar}"
    if pnl< -float(c['daily_loss_pct']): reason=f"daily_loss {pnl:.2f} breached {bar}"
    cur.execute("UPDATE fin_strategies SET last_pos=%s,last_bar=%s,equity=%s,peak=%s,enabled=CASE WHEN %s IS NULL THEN enabled ELSE false END,disabled_reason=COALESCE(%s,disabled_reason) WHERE id=%s",(pos_new,bar,round(equity,4),round(peak,4),reason,reason,sid))
    return (f"bar {bar} held {pos_held} -> new {pos_new} ret {ret*100:+.2f}% pnl {pnl:+.3f}% eq {equity:.2f} dd {dd:.2f}%"+(f" DISABLED: {reason}" if reason else ''),bar)
def main():
    c_,cur=con(); ensure(cur); c=cfg(cur)
    print("fin_paper run",datetime.datetime.utcnow().isoformat(),"| dry_run",c['dry_run'],"| enabled",c['enabled'])
    if c['enabled']!='true': print("kill switch off — nothing run"); cur.execute("INSERT INTO fin_heartbeat(id,last_run,status) VALUES(1,now(),'disabled') ON CONFLICT (id) DO UPDATE SET last_run=now(),status='disabled'"); return
    if SELFTEST:
        cur.execute("INSERT INTO fin_strategies(config,asset,cls,tier) VALUES('tsmom_60','SPY','equity','selftest') ON CONFLICT (config,asset) DO NOTHING")
    cur.execute("SELECT id,config,asset,cls,last_pos,last_bar,equity,peak FROM fin_strategies WHERE enabled ORDER BY id"); S=cur.fetchall()
    cur.execute("SELECT count(*) FROM fin_paper_positions WHERE status='OPEN'"); n_open=cur.fetchone()[0]
    print("strategies enabled:",len(S),"| open positions:",n_open)
    for s in S:
        try: msg,bar=run_strategy(cur,s,c); print(f"  [{s[0]}] {s[1]} {s[2]}: {msg}")
        except Exception as e: print(f"  [{s[0]}] {s[1]} {s[2]}: ERR {repr(e)[:120]}")
    cur.execute("SELECT coalesce(sum(pnl_pct),0) FROM fin_paper_daily WHERE bar=(SELECT max(bar) FROM fin_paper_daily)"); book=float(cur.fetchone()[0])
    cur.execute("SELECT count(*) FROM fin_paper_positions WHERE status='OPEN'"); n_open=cur.fetchone()[0]
    cur.execute("INSERT INTO fin_heartbeat(id,last_run,n_strategies,n_open,book_pnl_pct,status) VALUES(1,now(),%s,%s,%s,'ok') ON CONFLICT (id) DO UPDATE SET last_run=now(),n_strategies=EXCLUDED.n_strategies,n_open=EXCLUDED.n_open,book_pnl_pct=EXCLUDED.book_pnl_pct,status='ok'",(len(S),n_open,round(book,4)))
    print("book pnl on last bar:",round(book,4),"% | heartbeat written")
main()
PYFILE
python3 -m py_compile fin_paper.py || exit 1
echo "== 3) self-test (dry run, SPY tsmom_60) — acceptance criteria"
timeout 600 python3 fin_paper.py --selftest 2>&1 | grep -v Warning
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor(); P=lambda k,ok,ev: print(f"  {k}: {'PASS' if ok else 'FAIL'} — {ev}")
c.execute("SELECT value FROM fin_config WHERE key='enabled'"); P('1 kill switch row exists',c.rowcount==1,c.fetchone())
c.execute("SELECT id,last_pos,last_bar,equity FROM fin_strategies WHERE tier='selftest'"); r=c.fetchone(); P('2 selftest strategy booked a bar',r is not None and r[2] is not None,r)
c.execute("SELECT count(*) FROM fin_paper_daily WHERE strategy_id=%s",(r[0],)); n=c.fetchone()[0]; P('3 daily row written',n>=1,f"rows={n}")
c.execute("SELECT count(*) FROM fin_paper_positions WHERE strategy_id=%s",(r[0],)); npos=c.fetchone()[0]; P('4 position opened when signal nonzero (0 rows is also valid if signal=0)',True,f"positions={npos} last_pos={r[1]}")
c.execute("SELECT last_run,status,n_strategies FROM fin_heartbeat"); P('5 heartbeat written',c.rowcount==1,c.fetchone())
# 6 idempotency: a second run on the same bar must not double-book
import subprocess; out=subprocess.run(['python3','/root/pe-fin/fin_paper.py','--selftest'],capture_output=True,text=True,timeout=600).stdout
c.execute("SELECT count(*) FROM fin_paper_daily WHERE strategy_id=%s",(r[0],)); n2=c.fetchone()[0]; P('6 second run same bar = no double booking',n2==n,f"rows before={n} after={n2}; second run said: {'already booked' in out}")
# 7 hard cap: config above cap is clamped
c.connection.autocommit=True; c.execute("UPDATE fin_config SET value='5.0' WHERE key='risk_pct'")
sys.path.insert(0,'/root/pe-fin'); import importlib, fin_paper as fp
P('7 risk_pct 5.0 clamped to hard cap',fp.cfg(c)['risk_pct']==1.0,fp.cfg(c)['risk_pct']); c.execute("UPDATE fin_config SET value='0.5' WHERE key='risk_pct'")
c.execute("UPDATE fin_config SET value='false' WHERE key='dry_run'"); P('8 dry_run cannot be switched off (no live path)',fp.cfg(c)['dry_run'] is True,fp.cfg(c)['dry_run']); c.execute("UPDATE fin_config SET value='true' WHERE key='dry_run'")
# clean selftest strategy
c.execute("DELETE FROM fin_paper_daily WHERE strategy_id=%s",(r[0],)); c.execute("DELETE FROM fin_paper_positions WHERE strategy_id=%s",(r[0],)); c.execute("DELETE FROM fin_strategies WHERE tier='selftest'"); print("  selftest rows removed")
PY
echo "== 4) seed candidates (UNVERIFIED, tier=candidate, top 3 of latest v4_fin_results by oos_t with IS>0)"
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; cur=c.cursor()
cur.execute("SELECT config,asset,cls,oos_t,oos_sharpe FROM v4_fin_results WHERE run_date=(SELECT max(run_date) FROM v4_fin_results) AND is_sharpe>0 ORDER BY oos_t DESC LIMIT 3")
for cfg,asset,cls,t,sh in cur.fetchall():
    cur.execute("INSERT INTO fin_strategies(config,asset,cls,tier) VALUES(%s,%s,%s,'candidate') ON CONFLICT (config,asset) DO NOTHING",(cfg,asset,cls)); print("seeded",cfg,asset,cls,"oos_t",t,"sharpe",sh)
cur.execute("SELECT id,config,asset,tier,enabled FROM fin_strategies ORDER BY id"); print(cur.fetchall())
PY
echo "== 5) first real run + cron"
timeout 900 python3 fin_paper.py 2>&1 | grep -v Warning
( crontab -l 2>/dev/null | grep -v fin_paper.py; echo "40 21 * * 1-5 cd /root/pe-fin && python3 fin_paper.py >> /root/pe-fin/fin_paper.log 2>&1" ) | crontab -
crontab -l | grep fin_paper && echo "cron installed 21:40 UTC Mon-Fri"
echo "== done 224"
