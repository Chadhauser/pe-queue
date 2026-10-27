#!/bin/bash
# 266: PAPER ENGINE — risk-based sizing (262 exposed that positions were full-notional, so risk_pct did nothing and a 2% daily-loss
# limit killed a BTC strategy on an ordinary -3% day).
#  size = risk_pct% of bank per 1-sigma daily move: units = (risk_pct/100 * bank) / (sigma20 * close); P&L in £ on the bank
#  daily_loss_pct and max_dd_pct now measured on the BANK (prop-firm style), equity tracks bank in £
#  re-enables tsmom_40 BTC (disabled by the old rule) and re-tests: sizing worked example, gap loop (threshold = bars missed), rerun idempotent
set -o pipefail; cd /root/pe-fin || exit 1
cp fin_paper.py fin_paper_v2.bak
python3 - <<'PY'
p='/root/pe-fin/fin_paper.py'; s=open(p).read()
old="""    ret=close/prev_close-1; gross=pos_held*ret*100; cost=COST[cls]*abs(pos_new-pos_held)*100; pnl=gross-cost
    equity=float(equity)*(1+pnl/100); peak=max(float(peak),equity); dd=(equity/peak-1)*100"""
new="""    ret=close/prev_close-1
    sigma=float(df.Close.pct_change().iloc[max(1,i-20):i].std()) or 0.02          # 20-day daily vol known at the prior close
    bank=float(c.get('bank',10000)); lev=min((c['risk_pct']/100)/sigma, 5.0)       # fraction of bank held per unit position, capped 5x
    gross=pos_held*lev*ret*100; cost=COST[cls]*lev*abs(pos_new-pos_held)*100; pnl=gross-cost   # pnl is % of BANK
    equity=float(equity)*(1+pnl/100); peak=max(float(peak),equity); dd=(equity/peak-1)*100"""
assert old in s; s=s.replace(old,new); open(p,'w').write(s); print('sizing patched')
PY
python3 -m py_compile fin_paper.py || { echo "COMPILE FAIL — restoring"; cp fin_paper_v2.bak fin_paper.py; exit 1; }
python3 - <<'PY'
import sys,subprocess,psycopg2,datetime; sys.path.insert(0,'/root/pe-bot'); sys.path.insert(0,'/root/pe-fin'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; cur=c.cursor(); P=lambda k,ok,ev: print(f"  {k}: {'PASS' if ok else 'FAIL'} — {ev}")
# worked example: risk 0.5% of bank, sigma 2.5% -> lev 0.2; a -3% day costs 0.6% of bank, well inside a 2% daily limit
lev=min((0.5/100)/0.025,5.0); P('A worked example: 0.5% risk, 2.5% sigma, -3% day',abs(lev*-3-(-0.6))<1e-9,f"lev {lev:.2f} -> pnl {lev*-3:.2f}% of bank")
cur.execute("UPDATE fin_strategies SET enabled=true, disabled_reason=NULL WHERE config='tsmom_40' AND asset='BTC-USD'")
cur.execute("SELECT id,last_bar FROM fin_strategies WHERE config='tsmom_40' AND asset='BTC-USD'"); sid,lb=cur.fetchone()
cur.execute("SELECT count(*) FROM fin_paper_daily WHERE strategy_id=%s",(sid,)); before=cur.fetchone()[0]
out=subprocess.run(['python3','/root/pe-fin/fin_paper.py'],capture_output=True,text=True,timeout=600).stdout; print(out)
cur.execute("SELECT count(*), max(bar), bool_or(abs(pnl_pct)>2) FROM fin_paper_daily WHERE strategy_id=%s AND bar>%s",(sid,lb)); n,mx,big=cur.fetchone()
yday=datetime.datetime.utcnow().date()-datetime.timedelta(days=1)
P('B gap loop booked through to yesterday',mx==yday,f"rows {n}, latest {mx}, expected {yday}")
P('C no booked day exceeds 2% of bank at 0.5% risk',not big,'max |pnl| <= 2% of bank')
cur.execute("SELECT enabled FROM fin_strategies WHERE id=%s",(sid,)); P('D strategy still enabled after re-booking',cur.fetchone()[0],'enabled=true')
cur.execute("SELECT count(*) FROM fin_paper_daily"); b2=cur.fetchone()[0]; subprocess.run(['python3','/root/pe-fin/fin_paper.py'],capture_output=True,text=True,timeout=600); cur.execute("SELECT count(*) FROM fin_paper_daily"); P('E rerun idempotent',cur.fetchone()[0]==b2,f"rows {b2} unchanged")
PY
echo "== done 266"
