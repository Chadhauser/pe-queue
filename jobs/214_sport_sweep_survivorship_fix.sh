#!/bin/bash
# 214: PRICE-ONLY SWEEP — REMOVE THE SURVIVORSHIP. CLOCK cells were emitted only when the detected goal count equalled the TRUE full-time
# total, which silently drops every game with a hard-to-detect late goal — exactly the games where lay-the-draw / lay-to-FT lose. The
# true-goal engine (206/208) showed the resulting +£2.2 LTD cell is really −£1.7 to −£2.3. Fix: condition only on information available
# at the trigger — for triggers from 46' require the detected first-half count to equal the true HT count (known at 46'); for earlier
# triggers no detection filter at all. Detection errors after the trigger become noise (biases toward zero), not selection.
# Re-runs the sweep in the background (~1 h); 215 reports when done.
cd /root/pe-factory/v4 && cp sport_sweep.py sport_sweep.py.bak214 && python3 - <<'PY'
p='sport_sweep.py'; s=open(p).read(); n=0
old="    for m in ((1,15,30,46,60,75) if clock_ok else ()):\n        n=sum(1 for g in gl if g<m); st='0' if n==0 else ('1' if n==1 else '2+')\n"
new="    for m in (1,15,30,46,60,75):\n        if m>=46 and not clock_ok: continue                 # 214: HT-count agreement only, known at the trigger\n        n=sum(1 for g in gl if g<m); st='0' if n==0 else ('1' if n==1 else '2+')\n"
assert old in s, "loop anchor"; s=s.replace(old,new,1); n+=1
old2="clock_ok=(len(gl_)==hg+ag) and (ht is None or sum(1 for g in gl_ if g<46)==ht)"
new2="clock_ok=(ht is None or sum(1 for g in gl_ if g<46)==ht)   # 214: no full-time count condition"
assert old2 in s, "clock anchor"; s=s.replace(old2,new2,1); n+=1
open(p,'w').write(s); print("patches:",n)
PY
python3 -m py_compile sport_sweep.py || { cp sport_sweep.py.bak214 sport_sweep.py; echo RESTORED; exit 1; }
pgrep -f sport_sweep.py >/dev/null && echo "sweep already running" || (nohup timeout 7000 python3 sport_sweep.py > sport_sweep_214.log 2>&1 &)
sleep 5; pgrep -af sport_sweep.py | head -1; echo started
