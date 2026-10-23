#!/bin/bash
# 140: (a) M1: in 'europe' mode any UEFA competition qualifies regardless of the £500k size test (Europa games were all skipped as
#     "not card/£500k"); and a +60s lay price >=100 means the market has not properly reopened — wait up to 90s more for a sane
#     price instead of skipping (four Europa goals were skipped at "1000.0").
#     (b) liq_recorder: CORRECT_SCORE rows still 0 after 137. Root causes visible in the code: the catalogue loop labels every market
#     with the loop's market type (so CS markets fetched alongside MATCH_ODDS were labelled MO or dropped), and the selection
#     mapper has no CS branch. Fix: label from the market's own description.marketType; CS selections keep their score name.
echo "== (a) M1"
python3 - <<'PY'
p='/root/pe-push/m1_alert.py'; s=open(p).read(); n=0
old="why='card' if ev[:40].strip() in CARD else ('big' if tm>=BIG else None)"
new="why='card' if ev[:40].strip() in CARD else ('big' if tm>=BIG else ('europe' if (MODE=='europe' and (comp or '').upper().startswith('UEFA')) else None))"
if old in s: s=s.replace(old,new); n+=1
old2="""            if not r:
                if (now-p['due']).total_seconds()<30: continue
                px=None
            else: px=float(r['lay_px'])"""
new2="""            if not r or float(r['lay_px'])>=100:
                if (now-p['due']).total_seconds()<90: continue
                px=None if not r else float(r['lay_px'])
            else: px=float(r['lay_px'])"""
if old2 in s: s=s.replace(old2,new2); n+=1
open(p,'w').write(s); print("m1 patches applied:",n,"of 2")
PY
grep -n "MODE" /root/pe-push/m1_alert.py | head -5
python3 -m py_compile /root/pe-push/m1_alert.py && pkill -f m1_alert.py; echo "m1 restarts via keepalive"
echo "== (b) liq_recorder"
sed -n 30,60p /root/pe-liq/liq_recorder.py
python3 - <<'PY'
import re
p='/root/pe-liq/liq_recorder.py'; s=open(p).read(); orig=s
# 1. marketProjection must include MARKET_DESCRIPTION
if 'MARKET_DESCRIPTION' not in s:
    s=re.sub(r'("marketProjection"\s*:\s*\[)', r'\1"MARKET_DESCRIPTION",', s, count=1); print("added MARKET_DESCRIPTION to projection")
# 2. label from the market's own type
MAP="{'MATCH_ODDS':'MO','CORRECT_SCORE':'CS','OVER_UNDER_25':'OU25','OVER_UNDER_15':'OU15','OVER_UNDER_35':'OU35','BOTH_TEAMS_TO_SCORE':'BTTS'}"
s2=re.sub(r"'mkt':\{[^}]*\}\[mt\]", "'mkt':"+MAP+".get((m.get('description') or {}).get('marketType'), "+MAP+"[mt])", s, count=1)
if s2!=s: s=s2; print("market label now taken from description.marketType")
# 3. CS selection names: keep the score text
anchor="    if meta['mkt'] in ('OU25','OU15','OU35'): return 'OVER' if low.startswith('over') else 'UNDER'"
if anchor in s and "meta['mkt']=='CS'" not in s:
    s=s.replace(anchor,"    if meta['mkt']=='CS': return low.replace(' ','').upper()\n"+anchor); print("CS selection branch added")
if s!=orig: open(p,'w').write(s)
else: print("NO CHANGES MADE — inspect the sed output above")
PY
python3 -m py_compile /root/pe-liq/liq_recorder.py && pkill -f liq_recorder.py; sleep 120; pgrep -af liq_recorder.py; tail -5 /root/pe-liq/*.log 2>/dev/null | tail -8
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor(); c.execute("SELECT mkt, count(*) FROM liq_sample WHERE ts>now()-interval '3 minutes' GROUP BY 1"); print("rows last 3 min by market:",c.fetchall())
PY
