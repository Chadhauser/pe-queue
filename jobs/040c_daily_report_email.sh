#!/bin/bash
# 043: DAILY 8PM REPORT FROM THE SERVER ITSELF — does not depend on Peter's laptop or on Claude being awake. Cron 19:50 London
# (server is Europe/Berlin -> 20:50 local; guard on London hour). Writes /root/pe-report/latest.txt and emails it to Peter using
# whatever mail credentials the operators already use on this box (Resend / SMTP). If none found, says so in the job log.
mkdir -p /root/pe-report && cat > /root/pe-report/pg_report.py <<'PYFILE'
import os, re, sys, glob, json, datetime, requests, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
sys.path.insert(0,'/root/pe-queue/runner'); import creds
E=creds.all_vars()
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
def q(sql,args=()):
    cur.execute(sql,args); return cur.fetchall()
L=[]; A=L.append
now=datetime.datetime.now(datetime.timezone.utc).astimezone(datetime.timezone(datetime.timedelta(hours=1)))
A(f"PE TRADING DAILY REPORT — {now:%a %d %b %Y %H:%M} London"); A("")
# PG bot
r=q("SELECT * FROM pg_control WHERE id=1")
if r: A(f"POST-GOAL BOT (PG): enabled={r[0]['enabled']} stake=£{r[0]['stake']} dry_run={r[0]['dry_run']} daily_stop=£{r[0]['max_daily_loss']}")
hb=q("SELECT * FROM pg_heartbeat WHERE id=1")
if hb: A(f"  heartbeat {hb[0]['last_seen']:%H:%M} UTC | open {hb[0]['open_positions']} | today P&L £{hb[0]['today_pnl']}")
t=q("""SELECT count(*) FILTER (WHERE status IN ('OPEN','CLOSED','SETTLED_BY_MARKET')) entered, count(*) FILTER (WHERE status='UNMATCHED') unmatched,
       count(*) FILTER (WHERE status='CLOSED') closed, round(coalesce(sum(pnl),0)::numeric,2) pnl, count(*) FILTER (WHERE pnl>0) wins,
       round(avg(entry_matched)::numeric,2) avg_entry FROM pg_trades WHERE entered_at::date=current_date""")[0]
A(f"  TODAY: entered {t['entered']} | unmatched {t['unmatched']} | closed {t['closed']} | wins {t['wins']} | P&L £{t['pnl']}")
for r in q("SELECT sel, exit_reason, count(*) n, round(sum(pnl)::numeric,2) pnl FROM pg_trades WHERE entered_at::date=current_date AND status='CLOSED' GROUP BY 1,2 ORDER BY 1,2"):
    A(f"    {r['sel']:6} {r['exit_reason'] or '':6} n={r['n']:3} P&L £{r['pnl']}")
for r in q("SELECT entered_at::date d, count(*) n, round(sum(pnl)::numeric,2) pnl FROM pg_trades WHERE status='CLOSED' GROUP BY 1 ORDER BY 1"):
    A(f"  {r['d']}: {r['n']} closed, £{r['pnl']}")
tot=q("SELECT count(*) n, round(coalesce(sum(pnl),0)::numeric,2) pnl FROM pg_trades WHERE status='CLOSED'")[0]
A(f"  SINCE START: {tot['n']} closed trades, £{tot['pnl']} (VERIFIED live, Betfair statement is the final word)")
A("")
# recorder
g=q("SELECT count(DISTINCT goal_ts) goals, count(DISTINCT event_name) matches FROM liq_goal_depth WHERE goal_ts::date=current_date")[0]
A(f"LIQUIDITY RECORDER: today {g['goals']} goals captured in {g['matches']} matches")
d=q("""SELECT mkt, CASE WHEN ltp<1.5 THEN '<1.5' WHEN ltp<2.5 THEN '1.5-2.5' WHEN ltp<5 THEN '2.5-5' ELSE '5+' END band, count(*) n,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY lay_sz)::numeric) med_lay_best, round(percentile_cont(0.5) WITHIN GROUP (ORDER BY lay3_sz)::numeric) med_lay3
       FROM liq_goal_depth WHERE offset_s=60 AND goal_ts > now()-interval '7 days' GROUP BY 1,2 ORDER BY 1,2""")
A("  £ available to LAY 60s after a goal, last 7 days (median best / within 3 ticks):")
for r in d: A(f"    {r['mkt']:5} {r['band']:8} n={r['n']:4}  £{r['med_lay_best']} / £{r['med_lay3']}")
A("")
# tennis (one line, his rule: £5 only after 100 trades)
tn=q("SELECT count(*) n, round(coalesce(sum(pnl),0)::numeric,2) pnl FROM tennis_positions WHERE NOT dry_run AND closed_at IS NOT NULL")[0]
A(f"TENNIS: {tn['n']} completed live trades, £{tn['pnl']} (bot ledger; £5 stakes at 100 trades if positive ex best day)")
A("")
# queue
A("QUEUE (last 24h):")
for r in q("SELECT job, status, to_char(finished AT TIME ZONE 'Europe/London','HH24:MI') f FROM job_results WHERE coalesce(finished,started) > now()-interval '24 hours' ORDER BY job"):
    A(f"  {r['job']:40} {r['status']:8} {r['f'] or ''}")
rep="\n".join(L)
open('/root/pe-report/latest.txt','w').write(rep); print(rep)
# ---- email ----
TO="peter@edwardsbros.co.uk"; subj=f"PE trading report {now:%a %d %b %H:%M}"
sent=False
key=E.get('RESEND_API_KEY')
if key:
    frm=E.get('REPORT_FROM') or E.get('RESEND_FROM') or E.get('MAIL_FROM') or 'reports@edwardsbros.co.uk'
    r=requests.post("https://api.resend.com/emails",headers={"Authorization":"Bearer "+key},json={"from":frm,"to":[TO],"subject":subj,"text":rep},timeout=30)
    print("resend:",r.status_code,r.text[:120]); sent=r.status_code<300
if not sent and (E.get('SMTP_HOST') or E.get('SMTP_SERVER')):
    import smtplib, ssl; from email.message import EmailMessage
    m=EmailMessage(); m['From']=E.get('SMTP_FROM') or E.get('SMTP_USER'); m['To']=TO; m['Subject']=subj; m.set_content(rep)
    host=E.get('SMTP_HOST') or E.get('SMTP_SERVER'); port=int(E.get('SMTP_PORT') or 587)
    with smtplib.SMTP(host,port,timeout=30) as s:
        s.starttls(context=ssl.create_default_context()); s.login(E.get('SMTP_USER'),E.get('SMTP_PASS') or E.get('SMTP_PASSWORD')); s.send_message(m)
    print("smtp: sent"); sent=True
if not sent: print("NO MAIL CREDENTIALS FOUND (looked for RESEND_API_KEY / SMTP_*) — report written to /root/pe-report/latest.txt only")
PYFILE
python3 -m py_compile /root/pe-report/pg_report.py || exit 1
echo "== mail-related env names on this box (names only) =="
grep -rhoE '^(export )?[A-Z_]*(RESEND|SMTP|SENDGRID|MAILGUN|POSTMARK|MAIL)[A-Z_]*=' /root/operators/.env* /root/pe-*/.env /etc/environment 2>/dev/null | sort -u | sed 's/=.*//'
# cron: 19:50 London every day (server clock Europe/Berlin: try 20:50 and 19:50 with a London-hour guard)
( crontab -l 2>/dev/null | grep -v pe-report/pg_report ; echo '50 19,20 * * * [ "$(TZ=Europe/London date +\%H)" = "19" ] && cd /root/pe-report && python3 pg_report.py >> report.log 2>&1' ) | crontab -
echo "== test run now =="; cd /root/pe-report && python3 pg_report.py 2>&1 | tail -25
