#!/bin/bash
# 113: EXACT LEAGUE FILTERS + GOAL DEDUPE. M1 and PG matched leagues by substring ("Serie A" caught Brazil/Ecuador, "Premier League"
# caught Estonia/Jamaica/U21). Replace with an exact competition list (Betfair names). M1: ignore a second reopen within 4 min of
# a recorded goal on the same market (Fiorentina/Groningen/NEC/Gremio were double-counted).
python3 - <<'PY'
TIER12=["English Premier League","Spanish La Liga","Italian Serie A","German Bundesliga","French Ligue 1","UEFA Champions League","UEFA Europa League","UEFA Europa Conference League","English Championship","Dutch Eredivisie","Portuguese Primeira Liga","Belgian Pro League","Belgian First Division A","Turkish Super League","Scottish Premiership","Spanish Segunda Division","Italian Serie B","German Bundesliga 2","French Ligue 2","English League 1","English League 2","Austrian Bundesliga","Swiss Super League","Danish Superliga","Greek Super League","FA Cup","EFL Cup","Copa del Rey","Coppa Italia","DFB Pokal","Coupe de France"]
p='/root/pe-push/m1_alert.py'; s=open(p).read()
import re
s=re.sub(r"TIER12=_re\.compile\([^\n]*\)\n", "TIER12_SET=set(%r)\nclass _T:\n    def search(self,c): return (c or '').strip() in TIER12_SET\nTIER12=_T()\n" % TIER12, s, count=1)
if 'DEDUPE' not in s:
    s=s.replace("            cur.execute(\"SELECT 1 FROM m1_alerts WHERE market_id=%s AND goal_ts=%s\",(mid,gts))\n            if cur.fetchone(): continue\n",
                "            cur.execute(\"SELECT 1 FROM m1_alerts WHERE market_id=%s AND goal_ts=%s\",(mid,gts))\n            if cur.fetchone(): continue\n            cur.execute(\"SELECT 1 FROM m1_alerts WHERE market_id=%s AND goal_ts BETWEEN %s - interval '4 minutes' AND %s AND reason NOT LIKE 'SKIP%%'\",(mid,gts,gts))  # DEDUPE reopen bursts\n            if cur.fetchone(): continue\n")
open(p,'w').write(s); print("m1 patched: exact list", 'TIER12_SET' in s, "dedupe", 'DEDUPE' in s)
# PG bot whitelist: show current filter so the same exact list replaces it
import subprocess; print(subprocess.run("grep -n -i 'TIER12\\|whitelist\\|league' /root/pe-pg/pg_bot.py | head -20",shell=True,capture_output=True,text=True).stdout)
pb='/root/pe-pg/pg_bot.py'; b=open(pb).read()
m=re.search(r"TIER12\s*=\s*\{[^}]*\}", b, re.S) or re.search(r"TIER12\s*=\s*\[[^\]]*\]", b, re.S)
if m:
    b=b[:m.start()]+"TIER12="+repr(set(x.lower() for x in TIER12))+b[m.end():]; open(pb,'w').write(b); print("pg_bot TIER12 replaced with exact lower-case set")
else: print("pg_bot: TIER12 structure not found — unchanged (report)")
PY
python3 -m py_compile /root/pe-push/m1_alert.py /root/pe-pg/pg_bot.py && pkill -f m1_alert.py; pkill -f pg_bot.py; sleep 75; pgrep -af "m1_alert|pg_bot"
