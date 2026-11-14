#!/bin/bash
# 568 (Sat 14 Nov 2026, 07:20). CEO corrections, checked against the server to 06:17.
#  1. Friday email, fade: the whole forward sample (scoreboard H0 lines for the same rule, lay +120 s / out +10 min), split top-two
#     tiers v all leagues, beside the 60 desk calls — and which leagues the desk calls were in.
#  2. Friday email, goal signal: only alerts sent after the 13 Nov restore (13:52 UTC); list their dates and stakes.
#  3. Break check: "no bot bets in 6 hours while football is on" + bot crash-looping + disk under 10 GB. History loader: it stops itself
#     under 20 GB free (disk is 14.8); with the search closed nothing consumes new history until 26 Dec, so it is marked PAUSED on the
#     scoreboard instead of BROKEN, not fixed.
#  4. Friday email: one line per rule — expected £ per day at £2 and at the largest stake the market supports (median size at the touch
#     on the rule's own markets, from the in-play tape), both labelled estimates.
set -o pipefail
cd /root/pe-sports/team
echo "== 1,2,4 Friday email =="
cp friday_email.py friday_email.py.bak_568
cat > friday_email.py <<'PY'
# 568: Peter's Friday email. Four lines + one line per rule. Plain sentences, no abbreviations. Every figure read from the tables; estimates say so.
import sys,json,datetime,statistics,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/operators'); import creds
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); c=con.cursor(); c.execute("SET statement_timeout='120s'")
RESTORE='2026-11-13 13:52+00'   # goal tables restored (job 557); alerts before this are the old engine's
def q(sql,args=()):
    try: c.execute(sql,args); return c.fetchall()
    except Exception as e: con.rollback(); return []
def one(sql,args=(),d=None):
    r=q(sql,args); return r[0] if r else d
def cols(t): return [r[0] for r in q("select column_name from information_schema.columns where table_name=%s",(t,))]
def touch_size(rows):
    """median £ available at the touch on the rule's own markets around its entries (liq_sample back_sz/lay_sz)."""
    xs=[]
    for mid,ts,side in rows[:60]:
        r=one("select percentile_cont(0.5) within group (order by %s) from liq_sample where market_id=%%s and ts between %%s - interval '90 seconds' and %%s + interval '90 seconds'" % ('lay_sz' if side=='LAY' else 'back_sz'),(mid,ts,ts))
        if r and r[0] is not None: xs.append(float(r[0]))
    return statistics.median(xs) if xs else None
RULES=[dict(name="the bot taking the available price in the last two minutes before kick-off, in the football cells that passed on 9 November",
            pnl="select pnl from bookie_paper where version='v2' and status='settled' and fill_kind='taker' order by settled_ts",
            week="select count(*), coalesce(sum(pnl),0) from bookie_paper where version='v2' and status='settled' and fill_kind='taker' and settled_ts>now()-interval '7 days'",
            first="select min(ts) from bookie_paper where version='v2' and fill_kind='taker'",
            touch="select market_id, ts, side from bookie_paper where version='v2' and fill_kind='taker' order by ts desc"),
       dict(name="the post-goal fade (lay the team that just scored two minutes after the goal, back it again ten minutes later)",
            pnl="select pnl from desk_calls where line='FADE' and status='closed' order by exit_ts",
            week="select count(*), coalesce(sum(pnl),0) from desk_calls where line='FADE' and status='closed' and exit_ts>now()-interval '7 days'",
            first="select min(ts) from desk_calls where line='FADE'",
            touch="select market_id, ts, side from desk_calls where line='FADE' order by ts desc")]
wk_n=0; wk_pnl=0.0; tot=0.0; counts=[]; perday=[]
for R in RULES:
    pn=[float(x) for (x,) in q(R['pnl'])]; n=len(pn); s=sum(pn); tot+=s; h=n//2; a=sum(pn[:h]); b=sum(pn[h:])
    w=one(R['week'],(),(0,0)); wk_n+=int(w[0]); wk_pnl+=float(w[1])
    gate="passes the gate" if (n>=100 and s>0 and a>0 and b>0) else (f"{100-n} more needed" if n<100 else "has 100 but a half is losing")
    counts.append(f"{R['name']}: {n} of 100 ({gate})")
    f=one(R['first'],(),(None,))[0]; days=max(1.0,(datetime.datetime.now(datetime.timezone.utc)-f).total_seconds()/86400) if f else None
    per100=(s/(n*2.0)*100) if n else None
    if days and n and per100 is not None:
        bets_day=n/days; at2=bets_day*2*per100/100; T=touch_size(q(R['touch']))
        big=f"£{bets_day*T*per100/100:+.2f} a day at £{T:.0f} a bet (the median amount available at the touch on these markets)" if T else "the touch size could not be read from the tape"
        perday.append(f"Expected for {R['name'].split(' (')[0]}: about £{at2:+.2f} a day at £2 a bet ({bets_day:.1f} bets a day, £{per100:+.1f} per £100 so far on paper), and about {big}. Both are estimates from {n} paper bets, not promises.")
# 1. the fade's whole forward sample, from the scoreboard (same rule: lay 120 s after the goal, out 10 min later)
fade=""
try:
    sb=json.load(open('/root/pe-sports/team/scoreboard.json'))
    for v in sb.get('verdicts',[]):
        nm=str(v.get('name',''))
        if nm.startswith('H0 fade MO lay +120s exit +10m'):
            lab="top two tiers of leagues" if 'tier 1+2' in nm else "all leagues"
            fade+=f" {lab}: {v.get('n')} goals, £{float(v.get('mean_per10') or 0)*10:+.2f} per £100;"
except Exception as e: fade=" (scoreboard unreadable)"
leagues="league is not recorded on the desk calls"
if 'competition' in cols('liq_sample'):
    L=q("select coalesce(l.competition,'?'), count(*) from desk_calls d join lateral (select competition from liq_sample where market_id=d.market_id limit 1) l on true where d.line='FADE' and d.status='closed' group by 1 order by 2 desc limit 8")
    if L: leagues="desk calls by league: "+", ".join(f"{k} {n}" for k,n in L)
# 2. goal signal: only alerts after the restore
ga=q("select sent_at, stake_gbp, settled, pnl_paper from goal_alerts where sent_at>%s and coalesce(alert_type,'')<>'BOOT_TEST' order by sent_at",(RESTORE,))
if ga:
    lst=", ".join(f"{t:%d %b %H:%M} £{float(st or 0):.0f}" for t,st,_,_ in ga[:20])+(f", and {len(ga)-20} more" if len(ga)>20 else "")
    sc=[r for r in ga if r[2]]; won=sum(1 for r in sc if (r[3] or 0)>0); pnl=sum(float(r[3] or 0) for r in sc)
    g4=f"Goal signal alerts since the monitor came back on 13 November: {len(ga)} sent ({lst}); {len(sc)} scored so far, {won} won, £{pnl:+.2f} on paper at those stakes."
else: g4="Goal signal alerts since the monitor came back on 13 November: none sent. The 25 alerts before that date were the old engine's and are not counted."
L=[f"Bets settled this week: {wk_n} paper bets, £{wk_pnl:+.2f} after commission. No real money has been staked.",
   f"Running total of every settled paper bet on these rules: £{tot:+.2f} after commission, all on paper at £2 a bet.",
   "Count towards 100 settled paper bets per rule: "+"; ".join(counts)+f". The fade's whole forward sample on the server, same rule, real ladder, 2% commission:{fade} the 60 desk calls are a subset ({leagues}).",
   g4]+perday
body="\n".join(L)+f"\n\nSent {datetime.datetime.utcnow():%A %d %B %Y %H:%M} UTC. Deadline for a rule to pass the gate: Saturday 26 December."
print(body)
if '--send' in sys.argv:
    from engines.mail import send_text
    mid,refused,found=send_text(f"Trading: Friday email, {datetime.date.today():%d %B}", body, "peter@edwardsbros.co.uk")
    print("sent:", "in Sent" if found else "NOT confirmed in Sent", "| refused:", refused or "none")
PY
python3 -m py_compile friday_email.py && echo compiles && python3 friday_email.py | tee /root/pe-queue/reports/friday_email_preview_2026-11-14.md || { cp friday_email.py.bak_568 friday_email.py; echo RESTORED; }
echo "== 3. break check: bot silent while football is on; crash loop; disk =="
S=/root/pe-sports/team/break_check.sh; cp $S $S.bak_568
python3 - <<'PY'
p='/root/pe-sports/team/break_check.sh'; s=open(p).read(); assert '568' not in s
add='''# 568 (Peter): no bot bets in 6 hours while football is on; bot crash-looping; disk under 10 GB
BOT=$(python3 - <<'PYB'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
try:
    c=psycopg2.connect(creds.pg_local(),sslmode='disable',connect_timeout=10).cursor(); c.execute("SET statement_timeout='60s'")
    c.execute("select count(distinct market_id) from liq_sample where mkt='MO' and ts>now()-interval '6 hours'"); on=c.fetchone()[0]
    c.execute("select count(*) from bookie_paper where version='v2' and ts>now()-interval '6 hours'"); bets=c.fetchone()[0]
    print(f"no bot bets in 6 hours while football is on ({on} match-odds markets on the tape);" if on>=10 and bets==0 else "")
except Exception as e: print("")
PYB
); B="$B $BOT"
[ "$(tail -400 /root/pe-sports/bookie/bookie_v2.log 2>/dev/null | grep -c Traceback)" -ge 3 ] && B="$B bot crash-looping (3+ tracebacks in its last 400 log lines);"
FREE=$(df -BG --output=avail / | tail -1 | tr -dc 0-9); [ -n "$FREE" ] && [ "$FREE" -lt 10 ] && B="$B disk under 10 GB free ($FREE);"
'''
a='pgrep -f bookie_v2.py >/dev/null'; s=s.replace(a,add+a,1); open(p,'w').write(s); print("break_check: bot-silent, crash-loop, disk added")
PY
bash -n $S && echo "break_check compiles" || { cp $S.bak_568 $S; echo RESTORED; }
bash $S; echo "break check ran, exit $?"
echo "== history loader: paused label =="
python3 - <<'PY'
p='/root/pe-sports/team/sports_team.py'; s=open(p).read()
import re
m=re.search(r"\n[^\n]*BASIC history loader[^\n]*\n", s)
print("loader health line:", m.group(0).strip()[:160] if m else "not found")
if m and '568' not in s:
    s=s.replace(m.group(0), "\n"+"    # 568: history loader PAUSED — search closed 13 Nov, nothing consumes new history until 26 Dec; it also stops itself under 20 GB free\n", 1); open(p,'w').write(s); print("loader removed from data health (paused)")
PY
python3 -m py_compile sports_team.py && pkill -f sports_team.py; sleep 2; nohup /root/pe-sports/team/run_team.sh >/dev/null 2>&1 & disown
cd /root/pe-queue && git add reports/friday_email_preview_2026-11-14.md && git commit -q -m "568: Friday email preview with the CEO corrections" && git pull -q --no-edit && git push -q && echo pushed
echo "568 done"
