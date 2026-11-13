#!/bin/bash
# 561 (Fri 13 Nov 2026, 08:50). Peter's 13 November orders. The search is CLOSED, not paused.
#  A. Universe frozen: the football cells that passed on 9 November, the post-goal fade, the goal signal. Everything else off:
#     in-play map, country map, fan-bias verdict, resting-order replays, other-sport engine runs, the Verifier re-run (the passed list
#     must not change), desk CELL and HT11 lines. Passed-cells table: non-football rows moved to fair_price_passed_frozen_out.
#  B. Goal signal restored (monitor_ht + stats_collector keepalives back, STOPPED marker gone). Every alert goes to Peter's phone as an
#     email the minute it is written (goal_alert_mail.py, every 2 min) and is scored by the monitor whether he acts or not (settled/pnl_paper).
#  C. Friday email, four lines, no abbreviations: friday_email.py, cron Friday 07:00 UTC, sent through the operators' mailer. The first
#     one is sent NOW so Peter can see it; its text is also written to reports/friday_email_first.md.
#  D. Break check every hour (break_check.sh): database, both tapes, bot process, goal monitor, failed jobs. One email per break per day.
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
cd /root/pe-sports/team
echo "== A. freeze =="
cp /dev/null /tmp/cron_before_561; crontab -l > /root/pe-queue/inventory/.crontab_before_561 2>/dev/null
crontab -l | sed -E 's/^([^#].*(fairprice_inplay|fairprice_country|fan_bias|verifier_cells_inplay|replay_fills|replay_fills_hist|fairprice_v0|verifier_cells\.py).*)$/#FROZEN-561 \1/' | crontab -
echo "frozen cron lines: $(crontab -l | grep -c '^#FROZEN-561')"; crontab -l | grep '^#FROZEN-561' | cut -c1-120
pkill -f "fairprice_inplay|fairprice_country|fan_bias_verdict|verifier_cells_inplay|replay_fills|replay_inplay_xx|fairprice_v0" 2>/dev/null; true
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); con.autocommit=True; c=con.cursor()
c.execute("create table if not exists fair_price_passed_frozen_out as select * from fair_price_passed where false")
c.execute("insert into fair_price_passed_frozen_out select * from fair_price_passed where sport<>'Soccer'"); print("moved out (non-football):",c.rowcount)
c.execute("delete from fair_price_passed where sport<>'Soccer'")
c.execute("select sport, count(*) from fair_price_passed group by 1"); print("passed cells now:",c.fetchall())
c.execute("comment on table fair_price_passed is 'FROZEN 13 Nov 2026 (Peter): the football cells that passed on 9 November. No re-run until 26 December.'")
PY
# desk: CELL and HT11 off, FADE stays
cp /root/pe-sports/desk/desk.py /root/pe-sports/desk/desk.py.bak_561
python3 - <<'PY'
p='/root/pe-sports/desk/desk.py'; s=open(p).read(); n=0
if "if CELLS:" in s and "if False and CELLS:" not in s: s=s.replace("if CELLS:","if False and CELLS:   # 561: CELL line off, universe frozen",1); n+=1
a="for k,v in list(af_live().items()):\n            if v['status']!='HT'"
if a in s and "FROZEN561" not in s: s=s.replace(a,"for k,v in list(af_live().items()) if False else []:   # FROZEN561: HT11 off\n            if v['status']!='HT'",1); n+=1
open(p,'w').write(s); print("desk patched lines:",n)
PY
python3 -m py_compile /root/pe-sports/desk/desk.py && { pkill -f desk.py; echo "desk restarts under its keepalive with FADE only"; } || { cp /root/pe-sports/desk/desk.py.bak_561 /root/pe-sports/desk/desk.py; echo "DESK PATCH FAILED — restored"; }
echo "== B. goal signal =="
rm -f /root/pe-brain/STOPPED
crontab -l | sed 's/^#PAUSED-543 \(.*pe-brain\/run_\(monitor_ht\|stats_collector\).*\)$/\1/' | crontab -
crontab -l | grep -c "pe-brain/run_" ; nohup /root/pe-brain/run_monitor_ht.sh >/dev/null 2>&1 & disown; nohup /root/pe-brain/run_stats_collector.sh >/dev/null 2>&1 & disown
sleep 20; pgrep -fa "brain/monitor_ht.py|brain/stats_collector.py" | cut -c1-120
cat > /root/pe-sports/team/goal_alert_mail.py <<'PY'
# 561: every new goal_alerts row -> one plain email to Peter (his phone). State: last id sent. Scoring stays with the monitor (settled, pnl_paper).
import sys,os,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/operators'); import creds
ST='/root/pe-sports/team/goal_alert_mail.last'; primed=os.path.exists(ST); last=int(open(ST).read() or 0) if primed else 0
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); c=con.cursor()
c.execute("select column_name from information_schema.columns where table_name='goal_alerts'"); cols=[r[0] for r in c.fetchall()]
if 'id' not in cols: sys.exit(0)
c.execute("select max(id) from goal_alerts"); mx=c.fetchone()[0] or 0
if not primed: open(ST,'w').write(str(mx)); sys.exit(0)   # first run: do not mail history
want=[k for k in ('sent_at','fixture','minute','score','action','target_price_min','target_price_max','stake_gbp','strategy_id') if k in cols]
c.execute(f"select id,{','.join(want)} from goal_alerts where id>%s and coalesce(alert_type,'')<>'BOOT_TEST' order by id",(last,)); rows=c.fetchall()
if rows:
    from engines.mail import send_text
    for r in rows:
        d=dict(zip(['id']+want,r))
        body=(f"Goal signal alert at {d.get('sent_at')} (UTC).\nMatch: {d.get('fixture')}. Minute {d.get('minute')}, score {d.get('score')}.\n"
              f"Suggested action: {d.get('action')} between {d.get('target_price_min')} and {d.get('target_price_max')}; paper stake £{d.get('stake_gbp')}.\n"
              f"This alert is scored on the final result whether or not you act on it. Rule reference {d.get('strategy_id')}.")
        try: send_text(f"Goal signal: {d.get('fixture')} {d.get('minute')}' {d.get('score')}", body, "peter@edwardsbros.co.uk")
        except Exception as e: print("mail failed",str(e)[:120])
    open(ST,'w').write(str(rows[-1][0]))
PY
cat > /root/pe-sports/team/goal_alert_mail.sh <<'SH'
#!/bin/bash
cd /root/operators && set -a && . ./.env && set +a && /usr/bin/python3 /root/pe-sports/team/goal_alert_mail.py >> /root/pe-sports/team/goal_alert_mail.log 2>&1
SH
chmod +x /root/pe-sports/team/goal_alert_mail.sh; python3 -m py_compile /root/pe-sports/team/goal_alert_mail.py && /root/pe-sports/team/goal_alert_mail.sh && echo "goal alert mailer primed (last id $(cat /root/pe-sports/team/goal_alert_mail.last))"
( crontab -l | grep -v goal_alert_mail.sh; echo "*/2 * * * * /root/pe-sports/team/goal_alert_mail.sh" ) | crontab -
echo "== C. Friday email =="
cat > /root/pe-sports/team/friday_email.py <<'PY'
# 561: Peter's Friday email. Exactly four lines, no abbreviations, every rule in one plain sentence. Reads the tables, invents nothing.
import sys,datetime,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/operators'); import creds
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); c=con.cursor(); c.execute("SET statement_timeout='120s'")
def q(sql):
    try: c.execute(sql); return c.fetchall()
    except Exception as e: con.rollback(); return []
def one(sql,d=(0,0)):
    r=q(sql); return r[0] if r else d
RULES=[("the bot taking the available price in the last two minutes before kick-off, in the football cells that passed on 9 November",
        "select pnl from bookie_paper where version='v2' and status='settled' and fill_kind='taker' order by settled_ts"),
       ("the post-goal fade (lay the team that just scored two minutes after the goal, back it again ten minutes later)",
        "select pnl from desk_calls where line='FADE' and status='closed' order by exit_ts")]
wk_n=0; wk_pnl=0.0; tot=0.0; counts=[]
for name,sql in RULES:
    pn=[float(x) for (x,) in q(sql)]; n=len(pn); tot+=sum(pn); h=n//2; a=sum(pn[:h]); b=sum(pn[h:])
    w=sql.replace('select pnl','select count(*), coalesce(sum(pnl),0)').split(' order by')[0]+(" and settled_ts>now()-interval '7 days'" if 'settled_ts' in sql else " and exit_ts>now()-interval '7 days'")
    r=one(w); wk_n+=int(r[0]); wk_pnl+=float(r[1])
    gate="passes the gate" if (n>=100 and sum(pn)>0 and a>0 and b>0) else (f"{100-n} more needed" if n<100 else "has 100 but a half is losing")
    counts.append(f"{name}: {n} of 100 ({gate})")
ga=one("select count(*), count(*) filter (where settled), coalesce(sum(pnl_paper) filter (where settled),0), count(*) filter (where settled and pnl_paper>0) from goal_alerts where sent_at>now()-interval '7 days' and coalesce(alert_type,'')<>'BOOT_TEST'",(0,0,0,0))
L=[f"Bets settled this week: {wk_n} paper bets, £{wk_pnl:+.2f} after commission. No real money has been staked.",
   f"Running total since the proof gate opened on 12 November: £{tot:+.2f} after commission, all on paper at £2 a bet.",
   "Count towards 100 settled paper bets per rule: "+"; ".join(counts)+".",
   f"Goal signal alerts this week: {ga[0]} sent, {ga[1]} scored so far, {ga[3]} of those won, £{float(ga[2]):+.2f} on paper." if ga[0] else "Goal signal alerts this week: none sent (the monitor was switched back on today, 13 November)."]
body="\n".join(L)+f"\n\nSent {datetime.datetime.utcnow():%A %d %B %Y %H:%M} UTC. Deadline for a rule to pass the gate: Saturday 26 December."
print(body)
if '--send' in sys.argv:
    from engines.mail import send_text
    mid,refused,found=send_text(f"Trading: Friday email, {datetime.date.today():%d %B}", body, "peter@edwardsbros.co.uk")
    print("sent:", "in Sent" if found else "NOT confirmed in Sent", "| refused:", refused or "none")
PY
cat > /root/pe-sports/team/friday_email.sh <<'SH'
#!/bin/bash
cd /root/operators && set -a && . ./.env && set +a && /usr/bin/python3 /root/pe-sports/team/friday_email.py --send >> /root/pe-sports/team/friday_email.log 2>&1
SH
chmod +x /root/pe-sports/team/friday_email.sh; python3 -m py_compile /root/pe-sports/team/friday_email.py && echo compiles
( crontab -l | grep -v friday_email.sh; echo "0 7 * * 5 /root/pe-sports/team/friday_email.sh" ) | crontab -
/root/pe-sports/team/friday_email.sh; tail -8 /root/pe-sports/team/friday_email.log | tee /root/pe-queue/reports/friday_email_first.md
echo "== D. hourly break check =="
cat > /root/pe-sports/team/break_check.sh <<'SH'
#!/bin/bash
# 561: one email per break per day. Checks: database, Betfair tapes, bot process, goal monitor, failed jobs in the last hour.
D=/root/pe-sports/team/break_sent; mkdir -p $D; T=$(date -u +%F); B=""
pg_isready -q || B="$B database not answering;"
if pg_isready -q; then
  python3 - <<'PY' > /tmp/break_check.out 2>&1
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local(),sslmode='disable',connect_timeout=10).cursor(); c.execute("SET statement_timeout='60s'")
c.execute("select count(*) from stream_ticks where ts_recv>now()-interval '30 minutes'"); a=c.fetchone()[0]
c.execute("select count(*) from liq_sample where ts>now()-interval '30 minutes'"); b=c.fetchone()[0]
c.execute("select string_agg(job,', ') from job_results where status='failed' and finished>now()-interval '70 minutes'"); f=c.fetchone()[0]
print("stream tape stopped;" if a==0 else "", "in-play tape stopped;" if b==0 else "", f"failed jobs {f};" if f else "")
PY
  B="$B $(cat /tmp/break_check.out | tr -s ' ')"
fi
pgrep -f bookie_v2.py >/dev/null || B="$B bot process not running;"
pgrep -f brain/monitor_ht.py >/dev/null || B="$B goal monitor not running;"
B=$(echo $B | sed 's/^ *//'); [ -z "$B" ] && exit 0
K=$(echo "$B" | md5sum | cut -c1-8); [ -f $D/$T-$K ] && exit 0
cd /root/operators && set -a && . ./.env && set +a && PYTHONPATH=/root/operators python3 - "$B" <<'PY' && touch $D/$T-$K
import sys,datetime; from engines.mail import send_text
send_text(f"Trading estate: break today, {datetime.date.today():%d %B}", f"Break found at {datetime.datetime.utcnow():%H:%M} UTC: {sys.argv[1]} No real money is at risk. Details go to reports/ in the repository.", "peter@edwardsbros.co.uk")
PY
SH
chmod +x /root/pe-sports/team/break_check.sh; bash -n /root/pe-sports/team/break_check.sh && ( crontab -l | grep -v break_check.sh; echo "20 * * * * /root/pe-sports/team/break_check.sh >> /root/pe-sports/team/break_check.log 2>&1" ) | crontab -
echo "crontab now has: friday $(crontab -l | grep -c friday_email) | goal mail $(crontab -l | grep -c goal_alert_mail) | break $(crontab -l | grep -c break_check) | brain $(crontab -l | grep -c '^\*/5.*pe-brain')"
for j in 560 561; do grep -q "^$j" /root/pe-queue/watchman/REPORT_JOBS.txt || echo $j >> /root/pe-queue/watchman/REPORT_JOBS.txt; done
cd /root/pe-queue && git add reports/friday_email_first.md watchman/REPORT_JOBS.txt inventory/.crontab_before_561 && git commit -q -m "561: 13 Nov orders — universe frozen, goal signal back with alert emails, Friday email (first one), hourly break check" && git pull -q --rebase && git push -q && echo pushed
echo "561 done"
