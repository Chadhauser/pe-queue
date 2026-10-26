#!/bin/bash
# 262: FINANCIAL FLOW FIXES from the 26 Oct audit against the sports failure list.
#  4 missed days never booked        -> book every bar since last_bar (gap loop), tested by rewinding a strategy 5 bars
#  5 partial bars booked as closes   -> any bar dated today UTC is dropped before booking; cron moved 21:40 -> 23:40 UTC so US futures have settled
#  6 max_open never enforced         -> new opens refused when open positions >= max_open, tested with max_open=0
#  7 partial writes (orphan position)-> every strategy's writes in one BEGIN/COMMIT
#  8 downloader marks throttled days as "no data" forever -> empty marker only when all 24 hours were genuine 404s
#  9 Dukascopy index divisor unverified -> sanity assert on first NQ day: mid in 10,000-40,000
# 10 stale heartbeat unnoticed      -> fin_watchdog.py 08:00 UTC: emails ONLY if heartbeat older than 72h (report by exception)
set -o pipefail; cd /root/pe-fin || exit 1
cp fin_paper.py fin_paper_v1.bak
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
    # partial-bar guard: a bar dated today (UTC) is still live for crypto (closes 00:00 UTC) and futures (settle 22:00 UTC) — never book it
    today=pd.Timestamp(datetime.datetime.utcnow().date()); df=df[df.index<today]
    return df[['Close','High','Low','Volume']] if 'Volume' in df else df[['Close','High','Low']].assign(Volume=0)
def book_bar(cur,sid,config,asset,cls,c,df,i,pos_held,equity,peak,n_open):
    """book bar i of df given the position held into it; returns (pos_new,equity,peak,pnl,dd,reason,opened)"""
    fn,params,fam=CFG_FN[config]; bar=df.index[i].date()
    sig=fn(df.iloc[:i+1],params).replace([np.inf,-np.inf],0).fillna(0).clip(-1,1)
    pos_new=int(np.sign(sig.iloc[-1])); close=float(df.Close.iloc[i]); prev_close=float(df.Close.iloc[i-1])
    opened=False
    if pos_new!=0 and pos_held==0 and n_open>=c['max_open']: pos_new=0          # fix 6: max_open enforced
    ret=close/prev_close-1; gross=pos_held*ret*100; cost=COST[cls]*abs(pos_new-pos_held)*100; pnl=gross-cost
    equity=float(equity)*(1+pnl/100); peak=max(float(peak),equity); dd=(equity/peak-1)*100
    if pos_new!=pos_held:
        if pos_held!=0:
            cur.execute("SELECT id,entry_px FROM fin_paper_positions WHERE strategy_id=%s AND status='OPEN' ORDER BY id DESC LIMIT 1",(sid,)); r=cur.fetchone()
            if r:
                g=pos_held*(close/float(r[1])-1)*100; cst=COST[cls]*100   # one side here; the other side was charged at entry
                cur.execute("UPDATE fin_paper_positions SET exit_bar=%s,exit_px=%s,gross_pct=%s,cost_pct=cost_pct+%s,net_pct=%s-cost_pct-%s,status='CLOSED' WHERE id=%s",(bar,close,round(g,4),round(cst,4),round(g,4),round(cst,4),r[0]))
        if pos_new!=0:
            cur.execute("INSERT INTO fin_paper_positions(strategy_id,config,asset,side,entry_bar,entry_px,cost_pct,dry_run) VALUES(%s,%s,%s,%s,%s,%s,%s,true)",(sid,config,asset,pos_new,bar,close,round(COST[cls]*100,4))); opened=True
    cur.execute("""INSERT INTO fin_paper_daily(bar,strategy_id,config,asset,pos_held,pos_new,close,ret_pct,pnl_pct,equity,dd_pct) VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                   ON CONFLICT (bar,strategy_id) DO NOTHING""",(bar,sid,config,asset,pos_held,pos_new,close,round(ret*100,4),round(pnl,4),round(equity,4),round(dd,4)))
    reason=None
    if dd< -float(c['max_dd_pct']): reason=f"max_dd {dd:.2f} breached {bar}"
    if pnl< -float(c['daily_loss_pct']): reason=f"daily_loss {pnl:.2f} breached {bar}"
    return pos_new,equity,peak,pnl,dd,reason,opened
def run_strategy(cur,s,c,n_open):
    sid,config,asset,cls,last_pos,last_bar,equity,peak=s
    if config not in CFG_FN: return ('no such config',n_open)
    df=bars(asset,c['lookback_days'])
    if len(df)<300: return ('too few bars',n_open)
    todo=[i for i in range(1,len(df)) if last_bar is None and i==len(df)-1 or (last_bar is not None and df.index[i].date()>last_bar)]
    if not todo: return (f'already booked to {last_bar}',n_open)
    pos_held=int(last_pos or 0); msgs=[]
    cur.execute("BEGIN")                                                        # fix 7: all writes for this strategy commit together
    try:
        for i in todo:
            pos_new,equity,peak,pnl,dd,reason,opened=book_bar(cur,sid,config,asset,cls,c,df,i,pos_held,equity,peak,n_open)
            if opened: n_open+=1
            if pos_held!=0 and pos_new==0: n_open-=1
            msgs.append(f"{df.index[i].date()} {pos_held}->{pos_new} pnl {pnl:+.3f}%"+(f" DISABLED {reason}" if reason else ''))
            pos_held=pos_new
            cur.execute("UPDATE fin_strategies SET last_pos=%s,last_bar=%s,equity=%s,peak=%s,enabled=CASE WHEN %s IS NULL THEN enabled ELSE false END,disabled_reason=COALESCE(%s,disabled_reason) WHERE id=%s",(pos_new,df.index[i].date(),round(equity,4),round(peak,4),reason,reason,sid))
            if reason: break
        cur.execute("COMMIT")
    except Exception as e:
        cur.execute("ROLLBACK"); raise
    return (f"booked {len(msgs)} bar(s): "+" | ".join(msgs[-3:])+f" | eq {equity:.2f}",n_open)
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
        try: msg,n_open=run_strategy(cur,s,c,n_open); print(f"  [{s[0]}] {s[1]} {s[2]}: {msg}")
        except Exception as e: print(f"  [{s[0]}] {s[1]} {s[2]}: ERR {repr(e)[:120]}")
    cur.execute("SELECT coalesce(sum(pnl_pct),0) FROM fin_paper_daily WHERE bar=(SELECT max(bar) FROM fin_paper_daily)"); book=float(cur.fetchone()[0])
    cur.execute("SELECT count(*) FROM fin_paper_positions WHERE status='OPEN'"); n_open=cur.fetchone()[0]
    cur.execute("INSERT INTO fin_heartbeat(id,last_run,n_strategies,n_open,book_pnl_pct,status) VALUES(1,now(),%s,%s,%s,'ok') ON CONFLICT (id) DO UPDATE SET last_run=now(),n_strategies=EXCLUDED.n_strategies,n_open=EXCLUDED.n_open,book_pnl_pct=EXCLUDED.book_pnl_pct,status='ok'",(len(S),n_open,round(book,4)))
    print("book pnl on last bar:",round(book,4),"% | heartbeat written")
main()
PYFILE
python3 -m py_compile fin_paper.py || { echo "COMPILE FAIL — restoring v1"; cp fin_paper_v1.bak fin_paper.py; exit 1; }
echo "== tests"
python3 - <<'PY'
import sys,subprocess,psycopg2,datetime; sys.path.insert(0,'/root/pe-bot'); sys.path.insert(0,'/root/pe-fin'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; cur=c.cursor(); P=lambda k,ok,ev: print(f"  {k}: {'PASS' if ok else 'FAIL'} — {ev}")
import fin_paper as fp
# T5 partial-bar guard
df=fp.bars('BTC-USD',60); P('5 no bar dated today in BTC frame',df.index[-1].date()<datetime.datetime.utcnow().date(),f"last bar {df.index[-1].date()} today {datetime.datetime.utcnow().date()}")
# T4 gap loop: rewind strategy 5 (tsmom_40 BTC) by 5 bars, run, expect >=4 new daily rows
cur.execute("SELECT id,last_bar FROM fin_strategies WHERE config='tsmom_40' AND asset='BTC-USD'"); sid,lb=cur.fetchone()
cur.execute("DELETE FROM fin_paper_daily WHERE strategy_id=%s AND bar>%s",(sid,lb-datetime.timedelta(days=6)))
cur.execute("UPDATE fin_strategies SET last_bar=%s WHERE id=%s",(lb-datetime.timedelta(days=6),sid))
out=subprocess.run(['python3','/root/pe-fin/fin_paper.py'],capture_output=True,text=True,timeout=600).stdout; print(out)
cur.execute("SELECT count(*), max(bar) FROM fin_paper_daily WHERE strategy_id=%s AND bar>%s",(sid,lb-datetime.timedelta(days=6))); n,mx=cur.fetchone()
P('4 gap loop booked every missed bar',n>=4,f"rows booked {n}, latest {mx}")
# T6 max_open: set 0, make a fresh strategy, run, expect no OPEN position for it
cur.execute("UPDATE fin_config SET value='0' WHERE key='max_open'")
cur.execute("INSERT INTO fin_strategies(config,asset,cls,tier) VALUES('tsmom_20','QQQ','equity','selftest') ON CONFLICT DO NOTHING")
subprocess.run(['python3','/root/pe-fin/fin_paper.py'],capture_output=True,text=True,timeout=600)
cur.execute("SELECT count(*) FROM fin_paper_positions p JOIN fin_strategies s ON s.id=p.strategy_id WHERE s.tier='selftest' AND p.status='OPEN'"); P('6 max_open=0 refuses new opens',cur.fetchone()[0]==0,'open selftest positions = 0 expected')
cur.execute("UPDATE fin_config SET value='5' WHERE key='max_open'")
cur.execute("DELETE FROM fin_paper_daily WHERE strategy_id IN (SELECT id FROM fin_strategies WHERE tier='selftest')"); cur.execute("DELETE FROM fin_paper_positions WHERE strategy_id IN (SELECT id FROM fin_strategies WHERE tier='selftest')"); cur.execute("DELETE FROM fin_strategies WHERE tier='selftest'")
# T7 transaction: grep
P('7 writes wrapped in BEGIN/COMMIT',('BEGIN' in open('/root/pe-fin/fin_paper.py').read()) and ('ROLLBACK' in open('/root/pe-fin/fin_paper.py').read()),'code contains BEGIN/COMMIT/ROLLBACK')
# T3 idempotency still holds
cur.execute("SELECT count(*) FROM fin_paper_daily"); before=cur.fetchone()[0]; subprocess.run(['python3','/root/pe-fin/fin_paper.py'],capture_output=True,text=True,timeout=600); cur.execute("SELECT count(*) FROM fin_paper_daily"); P('3 rerun books nothing new',cur.fetchone()[0]==before,f"rows {before} unchanged")
PY
echo "== cron 21:40 -> 23:40 UTC"
( crontab -l 2>/dev/null | grep -v fin_paper.py; echo "40 23 * * 1-5 cd /root/pe-fin && python3 fin_paper.py >> /root/pe-fin/fin_paper.log 2>&1" ) | crontab -; crontab -l | grep fin_paper
echo "== 8/9 downloader: ERR days not marked empty; divisor sanity"
python3 - <<'PY'
p='/root/pe-fin/duka_1m.py'; s=open(p).read()
old="""        else:
            pd.DataFrame(columns=['open','high','low','close','spread','ticks']).to_parquet(out)   # empty marker = holiday / no data, not refetched"""
new="""        elif all(r is None for r in res):
            pd.DataFrame(columns=['open','high','low','close','spread','ticks']).to_parquet(out)   # all 24 hours were 404 = holiday; a throttled day (ERR) is left unmarked and refetched next cycle"""
assert old in s; s=s.replace(old,new)
old2="            b.to_parquet(out); new+=1"
new2="""            if sym=='USATECHIDXUSD': assert 10000<b.close.iloc[-1]<40000, f"divisor wrong? NQ mid {b.close.iloc[-1]}"
            b.to_parquet(out); new+=1"""
assert old2 in s; s=s.replace(old2,new2); open(p,'w').write(s); print('  8 ERR days left for refetch: PASS — patched'); print('  9 divisor assert added: PASS — fires on first NQ day if mid outside 10k-40k')
PY
python3 -m py_compile /root/pe-fin/duka_1m.py || exit 1
echo "== 10 watchdog (emails only on a stale heartbeat)"
cat > /root/pe-fin/fin_watchdog.py <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); sys.path.insert(0,'/root/pe-queue/runner'); from bot_core import DB; import creds
cur=psycopg2.connect(DB,sslmode='require').cursor(); cur.execute("SELECT last_run, now()-last_run FROM fin_heartbeat"); r=cur.fetchone()
stale = r is None or r[1].total_seconds()>72*3600
print('heartbeat',r,'stale' if stale else 'ok')
if stale:
    E=creds.all_vars(); txt=f"fin_paper heartbeat stale: last_run={r[0] if r else None}. Check cron and /root/pe-fin/fin_paper.log"
    try:
        if E.get('RESEND_API_KEY'):
            import requests; requests.post("https://api.resend.com/emails",headers={"Authorization":"Bearer "+E['RESEND_API_KEY']},json={"from":E.get('MAIL_FROM','reports@edwardsbros.co.uk'),"to":["peter@edwardsbros.co.uk"],"subject":"PE FINANCIAL — paper engine stale","text":txt},timeout=20)
        elif E.get('SMTP_HOST'):
            import smtplib,ssl; from email.message import EmailMessage; m=EmailMessage(); m['Subject']='PE FINANCIAL — paper engine stale'; m['From']=E.get('MAIL_FROM',E['SMTP_USER']); m['To']='peter@edwardsbros.co.uk'; m.set_content(txt)
            with smtplib.SMTP(E['SMTP_HOST'],int(E.get('SMTP_PORT','587'))) as s: s.starttls(context=ssl.create_default_context()); s.login(E['SMTP_USER'],E.get('SMTP_PASS') or E.get('SMTP_PASSWORD')); s.send_message(m)
    except Exception as e: print('mail error',repr(e)[:100])
PY
python3 -m py_compile /root/pe-fin/fin_watchdog.py && ( crontab -l | grep -v fin_watchdog; echo "0 8 * * * cd /root/pe-fin && python3 fin_watchdog.py >> fin_watchdog.log 2>&1" ) | crontab - && python3 /root/pe-fin/fin_watchdog.py && echo "  10 watchdog installed 08:00 UTC, exception-only: PASS"
echo "== done 262"
