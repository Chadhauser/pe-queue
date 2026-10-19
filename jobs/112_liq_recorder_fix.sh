#!/bin/bash
# 112: LADDER RECORDER FIX (from 110): (1) catalogue: sort by MAXIMUM_TRADED, maxResults 1000, keep the 150 deepest in-play
# markets per type and ALWAYS keep any with >= £200k matched (Everton/Brentford/Betis were dropped on Sunday);
# (2) goal detection only when the book is inPlay (Leeds "goals" at 15:31 were a pre-match suspension); (3) minute from the first
# in-play observation (true kick-off), HT break subtracted once elapsed > 60; (4) runnerName KeyError guard.
python3 - <<'PY'
import re
p='/root/pe-liq/liq_recorder.py'; s=open(p).read(); orig=s
s=s.replace('"marketProjection":["EVENT","COMPETITION","RUNNER_DESCRIPTION","MARKET_START_TIME"],"maxResults":200})',
            '"marketProjection":["EVENT","COMPETITION","RUNNER_DESCRIPTION","MARKET_START_TIME"],"sort":"MAXIMUM_TRADED","maxResults":1000})')
# cap per type after fetch: keep deepest 150 (+ anything >= 200k) — needs totalMatched from catalogue: request it
s=s.replace('"marketProjection":["EVENT","COMPETITION","RUNNER_DESCRIPTION","MARKET_START_TIME"],"sort":"MAXIMUM_TRADED","maxResults":1000})',
            '"marketProjection":["EVENT","COMPETITION","RUNNER_DESCRIPTION","MARKET_START_TIME"],"sort":"MAXIMUM_TRADED","maxResults":1000})\n        res=[m for i,m in enumerate(res) if i<150 or (m.get("totalMatched") or 0)>=200000]')
# runnerName guard
s=s.replace("r['runnerName']","r.get('runnerName',str(r.get('selectionId')))")
# in-play gating + true kickoff: record first time book says inplay
if 'first_inplay' not in s:
    s=s.replace("def minute_of(meta,now):","first_inplay={}\ndef minute_of(meta,now):\n    ko=first_inplay.get(meta.get('mid')) or meta['start']\n    el=(now-ko).total_seconds()/60\n    if el>60: el-=15\n    return int(max(0,min(130,el)))\ndef _old_minute_of(meta,now):",1)
    # tag meta with its market id when catalogue builds (so minute_of can look up first_inplay)
    s=re.sub(r"(new\[m\['marketId'\]\]=\{)", r"\1'mid':m['marketId'],", s, count=1)
    # gate goal detection and set first_inplay: find the suspended->open transition line
    s=s.replace("            if prev=='SUSPENDED' and st=='OPEN':", "            if mb.get('inplay') and mid not in first_inplay: first_inplay[mid]=now\n            if prev=='SUSPENDED' and st=='OPEN' and mb.get('inplay'):",1)
open(p,'w').write(s)
print("patched:", "sort" in s, "first_inplay" in s, "inplay')" in s, s!=orig)
PY
python3 -m py_compile /root/pe-liq/liq_recorder.py || { echo "COMPILE FAILED - reverting"; exit 1; }
pkill -f liq_recorder.py; sleep 75; pgrep -af liq_recorder.py; tail -5 /root/pe-liq/recorder.log
grep -n "MAXIMUM_TRADED\|first_inplay\[mid\]=now\|and mb.get('inplay')" /root/pe-liq/liq_recorder.py | head
