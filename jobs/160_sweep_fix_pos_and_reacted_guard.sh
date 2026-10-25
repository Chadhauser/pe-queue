#!/bin/bash
# 160: (a) sweep crashed at the summary (pos column computed on the unfiltered groupby after zero-variance cells were dropped) — pos now
#     computed in the same agg. (b) "scorer priced >2.5 two minutes after scoring, back, +5 min: +£5 per £10" survives the exit fix.
#     Most likely artefact left: the historical file carries a selection's LAST price forward minute by minute, so an illiquid scorer can
#     still show its PRE-goal price at goal+2 (the draw has jumped, the scorer's own series hasn't moved yet) — a back at 6.0 that is
#     really 3.0. Guard: a GOAL-trigger entry on the scorer/conceder requires that side's own price to have moved >= 10% from its
#     pre-goal level by the entry minute (reacted). goal_capture gets the same guard and prints how many entries it removes.
cd /root/pe-factory/v4 && pkill -f sport_sweep.py; sleep 1
python3 - <<'PY'
p='sport_sweep.py'; s=open(p).read(); n=0
old="    C=G.p.agg(n='size',mean='mean',sd='std').reset_index(); C=C[(C.sd>0)&C.sd.notna()]; C['t']=C['mean']/(C.sd/np.sqrt(C.n))"
new="    C=G.p.agg(n='size',mean='mean',sd='std',pos=lambda s:(s>0).mean()).reset_index(); C=C[(C.sd>0)&C.sd.notna()]; C['t']=C['mean']/(C.sd/np.sqrt(C.n))"
assert old in s; s=s.replace(old,new); n+=1
old2="    C['pos']=G.p.apply(lambda s:(s>0).mean()).values\n"
assert old2 in s; s=s.replace(old2,""); n+=1
old3='''    def emit(trig,role,side,m,after=None):
        if m in barred or m<1 or m>88: return
        if LP[side][m]<m-2: return                    # no real print in the last 2 minutes: stale, skip
        if after is not None and LP[side][m]<=after: return   # GOAL entry needs a print AFTER the goal minute
        e=px(side,m)
        if e is None: return'''
new3='''    def emit(trig,role,side,m,after=None):
        if m in barred or m<1 or m>88: return
        if LP[side][m]<m-2: return                    # no real print in the last 2 minutes: stale, skip
        if after is not None and LP[side][m]<=after: return   # GOAL entry needs a print AFTER the goal minute
        e=px(side,m)
        if e is None: return
        if after is not None and role in ('scorer','conceder'):
            pre=P[side][after-1]
            if np.isnan(pre) or abs(e/pre-1)<0.10: return   # that side's own price has not reacted to the goal yet: stale, skip'''
assert old3 in s; s=s.replace(old3,new3); n+=1
open(p,'w').write(s); print("patches:",n)
PY
python3 -m py_compile sport_sweep.py || exit 1
python3 - <<'PY'
import numpy as np, pandas as pd
src=open('/root/pe-factory/v4/sport_sweep.py').read().split("def main():")[0].replace("from bot_core import DB","DB=''"); ns={}; exec(src,ns)
def game(stale):
    rows=[]
    for m in range(0,96):
        h=2.0 if m<20 else (1.4 if m<60 else 1.2); d=3.4 if m<20 else (5.0 if m<60 else 8.0); a=3.5 if m<20 else (8.0 if m<60 else 20.0)
        if stale and 20<=m<=23: h=2.0            # scorer's series lags the draw jump by 4 minutes
        if m>=93: h,d,a=1.01,50.0,100.0
        for sel,p in (('HOME',h),('DRAW',d),('AWAY',a)): rows.append(dict(event_id='e',m=pd.Timestamp('2025-01-01'),minute=m,sel=sel,ltp=p))
    g=pd.DataFrame(rows); P,LP,gl,sc,w=ns['parse_game'](g); T=ns['game_trades'](P,LP,gl,sc,w,pd.Timestamp('2025-01-01').date())
    R=pd.DataFrame(T,columns=['trig','role','dir','exit','band','d','p']); return R[(R.trig=='GOAL1+2')&(R.role=='scorer')]
print("fresh scorer series: GOAL1+2 scorer trades",len(game(False)),"| stale scorer series:",len(game(True)),"(must be 0)")
assert len(game(False))>0 and len(game(True))==0; print("reacted guard PASS")
PY
(nohup timeout 10000 python3 sport_sweep.py > sport_sweep.log 2>&1 &); echo "sweep restarted"
cd /root/pe-factory && python3 - <<'PY'
p='goal_capture.py'; s=open(p).read()
old="            if e is None or e<=1.01 or em>gm+4: continue"
new="            if e is None or e<=1.01 or em>gm+4: continue\n            if abs(e/pres[scorer]-1)<0.10: stale_n[0]+=1; continue   # scorer's own price has not reacted: stale print"
assert old in s; s=s.replace(old,new); s=s.replace("rows=[]\ndef px_at","rows=[]; stale_n=[0]\ndef px_at",1)
s=s.replace('print(f"\\n=== EVERY GOAL','print("entries removed as stale (scorer price unchanged at goal+2):",stale_n[0]); print(f"\\n=== EVERY GOAL',1)
open(p,'w').write(s); print("goal_capture guard added")
PY
python3 -m py_compile goal_capture.py || exit 1
timeout 1500 python3 goal_capture.py 2>&1 | grep -v -E "UserWarning|pd.read_sql| processed" | sed -n '/entries removed/,/FIRST goal/p;/scorer > 2.5/,/goal before/p'
