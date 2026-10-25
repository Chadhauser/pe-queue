#!/bin/bash
# 165: GOAL DETECTION MISSED EQUALISERS. A goal was "the draw price jumping >= 20%" — true for a goal that breaks a tie, but an
# EQUALISER makes the draw price FALL sharply, so every analysis built on this file (goal_capture, the sweep's GOAL triggers, LTD's
# 'first goal') only saw tie-breaking goals. 164's test exposed it (home 1-0, away 1-1 -> only one goal found). Fix: a goal is a
# >= 20% draw move in EITHER direction before 91'; scorer = side whose price fell most across it. 164's unit test is re-run here and
# must pass. The sweep is restarted; 166 reports. Note for the record: the STEAM-15 "draw steam" cell was probably catching late
# equalisers — it is now barred as a goal minute and will be re-measured honestly.
cd /root/pe-factory/v4 && pkill -f sport_sweep.py; sleep 1
python3 - <<'PY'
p='sport_sweep.py'; s=open(p).read(); n=0
old="    goals=[int(dm[i]) for i in range(1,len(dv)) if dv[i]>=dv[i-1]*1.20 and 2<=dm[i]<=92]"
new="    goals=[int(dm[i]) for i in range(1,len(dv)) if (dv[i]>=dv[i-1]*1.20 or dv[i]<=dv[i-1]/1.20) and 2<=dm[i]<=90]"
assert old in s; s=s.replace(old,new); n+=1
open(p,'w').write(s); print("patches:",n)
PY
python3 -m py_compile sport_sweep.py || exit 1
python3 - <<'PY'
import numpy as np, pandas as pd
src=open('/root/pe-factory/v4/sport_sweep.py').read().split("def main():")[0].replace("from bot_core import DB","DB=''"); ns={}; exec(src,ns)
rows=[]
for m in range(0,96):   # home 1-0 at 20', away equalises 60', drawn; draw price never collapses below 1.3 (would have been 'undecided')
    h=2.0 if m<20 else (1.4 if m<60 else 2.6); d=3.4 if m<20 else (5.0 if m<60 else max(1.3,2.4-0.03*(m-60))); a=3.5 if m<20 else (8.0 if m<60 else 4.5)
    for sel,p in (('HOME',h),('DRAW',d),('AWAY',a)): rows.append(dict(event_id='e',m=pd.Timestamp('2025-01-01'),minute=m,sel=sel,ltp=p))
g=pd.DataFrame(rows); P,LP,gl,sc,w=ns['parse_game'](g); print("goals",gl,"scorers",sc,"winner",w,"| price-decided:",ns['AGREE'][-1][1])
assert gl==[20,60] and sc==['HOME','AWAY'] and w=='DRAW' and ns['AGREE'][-1][1] is None; print("equaliser detection + result-from-goals PASS")
PY
(nohup timeout 10000 python3 sport_sweep.py > sport_sweep.log 2>&1 &); echo "sweep restarted"
cd /root/pe-factory && python3 - <<'PY'
p='goal_capture.py'; s=open(p).read()
old="        goals=[int(dm[i]) for i in range(1,len(dv)) if dv[i]>=dv[i-1]*1.20 and dm[i]>=2]"
new="        goals=[int(dm[i]) for i in range(1,len(dv)) if (dv[i]>=dv[i-1]*1.20 or dv[i]<=dv[i-1]/1.20) and 2<=dm[i]<=90]"
assert old in s; s=s.replace(old,new); open(p,'w').write(s); print("goal_capture detection patched (re-run in 166)")
PY
python3 -m py_compile /root/pe-factory/goal_capture.py
