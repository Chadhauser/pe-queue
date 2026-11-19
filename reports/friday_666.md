```
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
        perday.append(f"Expected for {R['name'].split(' (')[0]}: about £{at2:+.2f} a day at £2 a bet ({bets_day:.1f} bets a day, £{per100:+.1f} per £100 so far on paper), and about {big}. Both are estimates from {n} paper bets, not prom
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
    L=q("select coalesce(l.competition,'?'), count(*) from desk_calls d join lateral (select competition from liq_sample where market_id=d.market_id limit 1) l on true where d.line='FADE' and d.status='closed' group by 1 order by 2 desc lim
    if L: leagues="desk calls by league: "+", ".join(f"{k} {n}" for k,n in L)
# 2. goal signal: only alerts after the restore
ga=q("select sent_at, stake_gbp, settled, pnl_paper from goal_alerts where sent_at>%s and coalesce(alert_type,'')<>'BOOT_TEST' order by sent_at",(RESTORE,))
if ga:
    lst=", ".join(f"{t:%d %b %H:%M} £{float(st or 0):.0f}" for t,st,_,_ in ga[:20])+(f", and {len(ga)-20} more" if len(ga)>20 else "")
    sc=[r for r in ga if r[2]]; won=sum(1 for r in sc if (r[3] or 0)>0); pnl=sum(float(r[3] or 0) for r in sc)
    g4=f"Goal signal alerts since the monitor came back on 13 November: {len(ga)} sent ({lst}); {len(sc)} scored so far, {won} won, £{pnl:+.2f} on paper at those stakes."
else: g4="Goal signal alerts since the monitor came back on 13 November: none sent. The 25 alerts before that date were the old engine's and are not counted."
O=opener()
L=[O[0],O[1],f"Bets settled this week: {wk_n} paper bets, £{wk_pnl:+.2f} after commission. No real money has been staked.",
   f"Running total of every settled paper bet on these rules: £{tot:+.2f} after commission, all on paper at £2 a bet.",
   "Count towards 100 settled paper bets per rule: "+"; ".join(counts)+f". The fade's whole forward sample on the server, same rule, real ladder, 2% commission:{fade} the 60 desk calls are a subset ({leagues}).",
   g4]+perday
body="\n".join(L)+f"\n\nSent {datetime.datetime.utcnow():%A %d %B %Y %H:%M} UTC. Deadline for a rule to pass the gate: Saturday 26 December."
print(body)
if '--send' in sys.argv:
    from engines.mail import send_text
    mid,refused,found=send_text(f"Trading: Friday email, {datetime.date.today():%d %B}", body, "peter@edwardsbros.co.uk")
    print("sent:", "in Sent" if found else "NOT confirmed in Sent", "| refused:", refused or "none")
----
#!/bin/bash
cd /root/operators && set -a && . ./.env && set +a && /usr/bin/python3 /root/pe-sports/team/friday_email.py --send >> /root/pe-sports/team/friday_email.log 2>&1
```
