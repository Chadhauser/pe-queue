#!/bin/bash
# 228: FINANCIAL LINE — morning report per the 25 Oct brief cadence, server-side, emailed via the same route as 117 (automated
# report to Peter's own address is allowed). 07:25 London daily. Sections: engine health (did nightly runs write rows), the shelf
# (cells / survivors per engine against chance), forward paper (per strategy: tier, enabled, equity, drawdown, open position,
# auto-disable reason), yesterday's bar P&L, and the last financial jobs. Writes /root/pe-report/fin_morning.txt too.
mkdir -p /root/pe-report && cat > /root/pe-report/fin_morning.py <<'PYFILE'
import sys, datetime, math, psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET statement_timeout='60s'")
L=[f"PE FINANCIAL — MORNING REPORT {datetime.datetime.now():%a %d %b %H:%M}"]
def q(sql,label,fmt=None):
    try:
        cur.execute(sql); rows=cur.fetchall(); L.append(f"\n== {label} ==")
        for r in rows: L.append("  "+(fmt(r) if fmt else " | ".join(str(x) for x in r)))
        if not rows: L.append("  (none)")
    except Exception as e: L.append(f"\n== {label} == ERROR {repr(e)[:120]}")
from math import erf,sqrt
pn=lambda x:0.5*(1+erf(x/sqrt(2)))
def shelf(table,label,thr):
    try:
        cur.execute(f"SELECT max(run_date), count(*) FILTER (WHERE run_date=(SELECT max(run_date) FROM {table})), count(*) FILTER (WHERE run_date=(SELECT max(run_date) FROM {table}) AND oos_t>={thr} AND is_sharpe>0) FROM {table}")
        d,n,s=cur.fetchone(); L.append(f"  {label}: last run {d} | cells {n} | survivors t>={thr} & IS>0: {s} | chance {n*(1-pn(thr)):.1f}")
    except Exception as e: L.append(f"  {label}: ERROR {repr(e)[:80]}")
L.append("\n== ENGINE HEALTH / SHELF =="); shelf('v4_fin_results','daily-bar indicators (66 cfg x 55 inst)',3.5); shelf('v4_intraday','intraday crypto 5m',3.0); shelf('v4_session','intraday session effects 1h',3.0)
q("SELECT lookback, oos_sharpe, oos_t FROM v4_fin_xsmom WHERE run_date=(SELECT max(run_date) FROM v4_fin_xsmom)","cross-sectional momentum (layer 4, not a tradable line yet)")
q("SELECT last_run, n_strategies, n_open, book_pnl_pct, status FROM fin_heartbeat","FORWARD PAPER heartbeat (runs 21:40 UTC Mon-Fri)")
q("SELECT id, config, asset, tier, enabled, last_bar, last_pos, equity, round((equity/peak-1)*100,2) dd_pct, disabled_reason FROM fin_strategies ORDER BY id","forward paper strategies (all UNVERIFIED candidates until a survivor exists)")
q("SELECT bar, config, asset, pos_held, ret_pct, pnl_pct, equity FROM fin_paper_daily WHERE bar>=current_date-3 ORDER BY bar DESC, strategy_id","paper P&L last 3 bars")
q("SELECT config, asset, side, entry_bar, entry_px, status FROM fin_paper_positions WHERE status='OPEN' ORDER BY id","open paper positions")
q("SELECT config, asset, count(*) n, round(sum(net_pct)::numeric,3) net_pct FROM fin_paper_positions WHERE status='CLOSED' GROUP BY 1,2 ORDER BY 4 DESC","closed paper trades per strategy")
q("SELECT key, value FROM fin_config ORDER BY key","fin_config (dry_run is forced true in code — no live path)")
q("SELECT job, status, exit_code FROM job_results WHERE job ~ '^(151|157|223|224_fin|226_fin|227|228)' ORDER BY job","financial jobs")
L.append("\nNEXT TEST: per the brief order — session effects (227) -> Dukascopy tick FX families -> carry/seasonality/event -> passive fill model -> prop-firm constraint layer. Nothing goes live before a survivor has 60 days of forward paper.")
txt="\n".join(L); open('/root/pe-report/fin_morning.txt','w').write(txt); print(txt)
E=creds.all_vars(); sent=False
try:
    if E.get('RESEND_API_KEY'):
        import requests; r=requests.post("https://api.resend.com/emails",headers={"Authorization":"Bearer "+E['RESEND_API_KEY']},json={"from":E.get('MAIL_FROM','reports@edwardsbros.co.uk'),"to":["peter@edwardsbros.co.uk"],"subject":L[0],"text":txt},timeout=20); print("resend:",r.status_code); sent=r.status_code<300
    elif E.get('SMTP_HOST') and E.get('SMTP_USER'):
        import smtplib, ssl; from email.message import EmailMessage
        m=EmailMessage(); m['Subject']=L[0]; m['From']=E.get('MAIL_FROM',E['SMTP_USER']); m['To']='peter@edwardsbros.co.uk'; m.set_content(txt)
        with smtplib.SMTP(E['SMTP_HOST'],int(E.get('SMTP_PORT','587'))) as s: s.starttls(context=ssl.create_default_context()); s.login(E['SMTP_USER'],E.get('SMTP_PASS') or E.get('SMTP_PASSWORD')); s.send_message(m)
        print("smtp: sent"); sent=True
except Exception as e: print("mail error",repr(e)[:120])
if not sent: print("NO MAIL ROUTE — report on disk only")
PYFILE
python3 -m py_compile /root/pe-report/fin_morning.py || exit 1
( crontab -l 2>/dev/null | grep -v fin_morning.py ; echo "25 7 * * * cd /root/pe-report && python3 fin_morning.py >> fin_morning.log 2>&1" ) | crontab -
crontab -l | grep -c fin_morning && echo "cron installed 07:25 London (CRON_TZ line already present from 117)"
cd /root/pe-report && python3 fin_morning.py
