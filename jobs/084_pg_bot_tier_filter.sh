#!/bin/bash
# 084: PG bot: restrict the fade to tier 1+2 competitions. One week of real ladder data (job 080) shows the lay-the-Over fade is
# positive at +60/+120s in top-5/UCL and other-European leagues and heavily negative in the rest (spread eats it). Adds a TIER
# set to pg_bot.py and skips anything outside it; stake and everything else unchanged. Restart via keepalive.
python3 - <<'PY'
p='/root/pe-pg/pg_bot.py'; s=open(p).read()
if 'TIER12=' not in s:
    s=s.replace("WL={str(x).lower() for x in LEAGUES}","""WL={str(x).lower() for x in LEAGUES}
TIER12={x.lower() for x in ['English Premier League','Spanish La Liga','Italian Serie A','German Bundesliga','French Ligue 1','UEFA Champions League','English Championship','Dutch Eredivisie','Portuguese Primeira Liga','Belgian Pro League','Turkish Super League','Scottish Premiership','Spanish Segunda Division','Italian Serie B','German Bundesliga 2','French Ligue 2','UEFA Europa League','Spanish La Liga 2','Belgian Pro League','English Championship']}
WL=WL & TIER12 if WL & TIER12 else TIER12
print('PG whitelist now tier 1+2 only:',len(WL),flush=True)""")
    open(p,'w').write(s); print("patched")
else: print("already")
PY
python3 -m py_compile /root/pe-pg/pg_bot.py && pkill -f pg_bot.py; sleep 70; tail -3 /root/pe-pg/bot.log
