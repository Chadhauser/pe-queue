#!/bin/bash
# 117: MORNING REPORT 07:20 daily (server-side, so it exists even when Peter's laptop — our only read path from the chat — is off).
# Writes /root/pe-report/morning.txt and emails it to Peter if SMTP/Resend creds exist (automated report to his own address is allowed).
mkdir -p /root/pe-report && cat > /root/pe-report/morning.py <<'PYFILE'
import sys, os, datetime, psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor()
L=[f"PE TRADING — MORNING REPORT {datetime.datetime.now():%a %d %b %H:%M}"]
def q(sql,label,fmt=None):
    try:
        cur.execute(sql); rows=cur.fetchall(); L.append(f"\n== {label} =="); 
        for r in rows: L.append("  "+(fmt(r) if fmt else " | ".join(str(x) for x in r)))
        if not rows: L.append("  (none)")
    except Exception as e: L.append(f"\n== {label} == ERROR {repr(e)[:120]}"); con.rollback()
q("SELECT sport, strategy, band, n, per100_1, t1, per100_2, t2 FROM strategy_results WHERE run_date>=current_date-1 AND survivor ORDER BY per100_2 DESC","FACTORY SURVIVORS (both halves +, t>=2)")
q("SELECT sport, strategy, band, n, per100_1, per100_2 FROM strategy_results WHERE run_date>=current_date-1 AND NOT survivor AND per100_1>0 AND per100_2>0 ORDER BY per100_2 DESC LIMIT 12","FACTORY near misses (both halves +)")
q("SELECT sport, strategy, band, n, per100_1, per100_2 FROM strategy_results WHERE run_date>=current_date-1 AND per100_1<-3 AND per100_2<-3 AND t1<=-2 AND t2<=-2 ORDER BY per100_all LIMIT 10","FACTORY strongly negative (opposite side = candidate)")
q("SELECT count(*) cells, string_agg(DISTINCT sport,', ') FROM strategy_results WHERE run_date>=current_date-1","FACTORY coverage")
q("""SELECT 'scorer' leg, count(*) n, round(sum(CASE WHEN exit_px>0 THEN (1-entry_px/exit_px)*10 END)::numeric,2) pnl10 FROM m1_alerts WHERE entry_sent IS NOT NULL AND exit_px IS NOT NULL AND competition IN (SELECT DISTINCT competition FROM m1_alerts WHERE reason IN ('card','big','SHADOW','tier12'))
     UNION ALL SELECT leg, count(*), round(sum(CASE WHEN exit_px>0 THEN (1-entry_px/exit_px)*10 END)::numeric,2) FROM m1_variants WHERE exit_px IS NOT NULL GROUP BY leg""","M1 SHADOW BOOK (per £10): scorer vs conceder vs draw")
q("SELECT competition, count(*) n, round(sum(CASE WHEN exit_px>0 THEN (1-entry_px/exit_px)*10 END)::numeric,2) pnl10 FROM m1_alerts WHERE entry_sent IS NOT NULL AND exit_px IS NOT NULL GROUP BY 1 ORDER BY 2 DESC LIMIT 12","M1 shadow by league")
q("SELECT to_char(entry_sent,'Dy HH24:MI'), event_name, minute, team, entry_px, exit_px, exit_reason, actual_pnl FROM m1_alerts WHERE entry_sent>=now()-interval '36 hours' ORDER BY entry_sent","M1 last 36h")
q("SELECT count(*) trades, count(*) FILTER (WHERE pnl>0) wins, round(sum(pnl)::numeric,2) pnl FROM pg_trades WHERE status='CLOSED' AND entered_at>='2026-10-15 12:25'","PG BOT filtered run (since 15 Oct)")
q("SELECT count(*), count(*) FILTER (WHERE pnl>0), round(sum(pnl)::numeric,2) FROM pg_trades WHERE status='CLOSED' AND entered_at>=current_date-1","PG BOT yesterday")
q("SELECT tier, count(DISTINCT market_id) games, round(sum(pnl)::numeric,2) pnl FROM cs_qgreen_paper GROUP BY 1","CSM Q-GREEN paper")
q("SELECT trigger, count(*), round(sum(profit_per_10)::numeric,2) FROM game_autopsy WHERE run_at>=current_date-1 GROUP BY 1 ORDER BY 2 DESC","AUTOPSY yesterday: windows by trigger")
q("SELECT event_name, mkt, sel, kind, entry_min, entry_px, exit_min, exit_px, profit_per_10, trigger FROM game_autopsy WHERE run_at>=current_date-1 AND trigger NOT LIKE 'hindsight%' ORDER BY profit_per_10 DESC LIMIT 8","AUTOPSY yesterday: triggered windows")
q("SELECT to_char(max(last_seen),'Dy HH24:MI'), max(live_markets) FROM liq_heartbeat","ladder recorder heartbeat")
q("SELECT count(*) FILTER (WHERE minute>95), count(*) FROM liq_goal_depth WHERE offset_s=0 AND goal_ts>=current_date-1","goal rows minute>95 since fix (should be ~0)")
q("SELECT round(pg_database_size(current_database())/1e9,1)","DB GB")
q("SELECT job, status FROM job_results WHERE job >= '112' ORDER BY job","jobs 112+")
q("""SELECT round(sum(profit)::numeric,2) profit, round(sum(commission)::numeric,2) commission, round((100*sum(commission)/nullif(sum(CASE WHEN profit>0 THEN profit END),0))::numeric,1) comm_pct_of_wins FROM bf_cleared WHERE settled_date>now()-interval '30 days'""","BETFAIR commission check (30d): commission as % of winning markets")
txt="\n".join(L); open('/root/pe-report/morning.txt','w').write(txt); print(txt)
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
python3 -m py_compile /root/pe-report/morning.py || exit 1
( crontab -l 2>/dev/null | grep -v morning.py ; echo "CRON_TZ=Europe/London" ; echo "20 7 * * * cd /root/pe-report && python3 morning.py >> morning.log 2>&1" ) | crontab -
cd /root/pe-report && python3 morning.py
