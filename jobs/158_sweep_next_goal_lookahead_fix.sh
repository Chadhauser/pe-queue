#!/bin/bash
# 158: SPORT SWEEP — LOOK-AHEAD IN THE "NEXT GOAL" EXIT. First shelf (156) showed "back the draw at kick-off, exit at next goal"
# making +£5 per £10 over 23,189 trades — impossible, and the mirror cell (lay the draw) lost the same. Cause: the NG exit priced the
# hedge at the minute BEFORE the next goal, i.e. it knew the goal was coming. Honest NG = the trade is hit BY the goal: exit at the
# first real print at/after goal+2 (post-suspension price). Same hindsight existed in goal_capture's "next goal before exit" branch.
# Also: cells with zero variance produced NaN t (CLOCK family mean_t NaN) — now dropped. Re-runs the sweep in the background; 159 reports.
cd /root/pe-factory/v4 && pkill -f sport_sweep.py; sleep 1
python3 - <<'PY'
p='sport_sweep.py'; s=open(p).read(); n=0
old='''            elif ex=='NG':
                nxt=[g for g in gl if g>m]
                if nxt:
                    x=px(side,nxt[0]-1)
                    if x is None or nxt[0]-1<=m: continue
                    p=pnl_back(e,x) if direction=='back' else pnl_lay(e,x)'''
new='''            elif ex=='NG':
                nxt=[g for g in gl if g>m]
                if nxt:
                    xm=nxt[0]+2
                    if xm>MAXM or LP[side][xm]<=nxt[0]: continue      # need a real print AFTER the goal (market resumed)
                    x=px(side,xm)
                    if x is None: continue
                    p=pnl_back(e,x) if direction=='back' else pnl_lay(e,x)'''
assert old in s; s=s.replace(old,new); n+=1
old2='''            else:
                h=int(ex[1:]); xm=m+h
                if xm>MAXM-3: continue
                x=px(side,xm)
                if x is None: continue
                p=pnl_back(e,x) if direction=='back' else pnl_lay(e,x)'''
new2='''            else:
                h=int(ex[1:]); xm=m+h
                if xm>MAXM-3: continue
                nxt=[g for g in gl if m<g<xm]
                if nxt:                                               # a goal lands before the fixed exit: we are hit by it, exit after it
                    xm=nxt[0]+2
                    if xm>MAXM or LP[side][xm]<=nxt[0]: continue
                x=px(side,xm)
                if x is None: continue
                p=pnl_back(e,x) if direction=='back' else pnl_lay(e,x)'''
assert old2 in s; s=s.replace(old2,new2); n+=1
old3="    C=G.p.agg(n='size',mean='mean',sd='std').reset_index(); C['t']=C['mean']/(C.sd/np.sqrt(C.n))"
new3="    C=G.p.agg(n='size',mean='mean',sd='std').reset_index(); C=C[(C.sd>0)&C.sd.notna()]; C['t']=C['mean']/(C.sd/np.sqrt(C.n))"
assert old3 in s; s=s.replace(old3,new3); n+=1
open(p,'w').write(s); print("patches:",n)
PY
python3 -m py_compile sport_sweep.py || exit 1
python3 - <<'PY'
import numpy as np, pandas as pd
src=open('/root/pe-factory/v4/sport_sweep.py').read().split("def main():")[0].replace("from bot_core import DB","DB=''"); ns={}; exec(src,ns)
rows=[]
for m in range(0,96):
    h=2.0 if m<20 else (1.4 if m<60 else 1.2); d=3.4 if m<20 else (5.0 if m<60 else 8.0); a=3.5 if m<20 else (8.0 if m<60 else 20.0)
    if 10<=m<20: d=3.4-0.05*(m-9)          # draw shortens 3.4 -> 2.9 before the goal at 20
    if m>=93: h,d,a=1.01,50.0,100.0
    for sel,p in (('HOME',h),('DRAW',d),('AWAY',a)): rows.append(dict(event_id='e',m=pd.Timestamp('2025-01-01'),minute=m,sel=sel,ltp=p))
g=pd.DataFrame(rows); P,LP,gl,sc,w=ns['parse_game'](g)
T=ns['game_trades'](P,LP,gl,sc,w,pd.Timestamp('2025-01-01').date()); R=pd.DataFrame(T,columns=['trig','role','dir','exit','band','d','p'])
ng=R[(R.trig=='CLOCK1g0')&(R.role=='draw')&(R.dir=='back')&(R.exit=='NG')].p.iloc[0]
exp=10*(3.4*0.98/(5.0*1.02)-1); print("back draw at 1', hit by goal at 20 -> exit at 22' price 5.0:",round(ng,3),"expected",round(exp,3))
f15=R[(R.trig=='CLOCK15g0')&(R.role=='draw')&(R.dir=='back')&(R.exit=='+10')].p.iloc[0]
e15=P['DRAW'][15]; exp2=10*(e15*0.98/(5.0*1.02)-1); print("back draw at 15' exit +10 but goal at 20 -> exit at 22':",round(f15,3),"expected",round(exp2,3))
assert abs(ng-exp)<0.01 and abs(f15-exp2)<0.01; print("look-ahead fix PASS")
PY
(nohup timeout 10000 python3 sport_sweep.py > sport_sweep.log 2>&1 &); echo "sweep restarted"
cd /root/pe-factory && python3 - <<'PY'
p='goal_capture.py'; s=open(p).read()
old="                xm2,x2=(px_at(s,nxt-1) if nxt<=xm else (xm,x))"
new="                xm2,x2=(px_at(s,nxt+1) if nxt<=xm else (xm,x))   # hit by the next goal: exit AFTER it, not before"
assert old in s; s=s.replace(old,new); open(p,'w').write(s); print("goal_capture patched")
PY
python3 -m py_compile goal_capture.py && echo "goal_capture re-run tonight via 159"
