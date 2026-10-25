#!/bin/bash
# 176: SWEEP — HIDDEN GOALS. The validated detector still misses ~7% of goals (and anything scored while a side was outside 1.08-30).
# When a goal is missed, the goal-count result is wrong and the 'g0' state is wrong, and the shelf fills with impossibilities:
# "lay a 1.3 favourite at 75' in a 0-0 game, 95% winners" — the price says someone scored, the state says nobody did. Rules:
# (1) result = price-decided winner when the final price collapsed (<= 1.15); goal-count only when it did not; if both exist and
#     disagree the game is dropped from FT/NG settles. (2) a CLOCK trigger whose state says 0-0 while a side is priced < 1.30 after
# 30' (or any state where the detected goal count disagrees with a side priced < 1.10 before 60') is skipped as a hidden goal.
# The AGREE line prints how often goal-count and price agree so this is measured, not assumed. Sweep restarted; 177 reports.
cd /root/pe-factory/v4 && pkill -f sport_sweep.py; sleep 1
python3 - <<'PY'
p='sport_sweep.py'; s=open(p).read(); n=0
old='''    if any(sc is None for sc in scorers): winner=pwin                  # a goal we could not attribute: fall back to price
    else:
        hg=sum(1 for sc in scorers if sc=='HOME'); ag=sum(1 for sc in scorers if sc=='AWAY')
        winner='HOME' if hg>ag else ('AWAY' if ag>hg else 'DRAW')
    AGREE.append((winner,pwin))'''
new='''    hg=sum(1 for sc in scorers if sc=='HOME'); ag=sum(1 for sc in scorers if sc=='AWAY')
    gwin='HOME' if hg>ag else ('AWAY' if ag>hg else 'DRAW')
    AGREE.append((gwin,pwin))
    if pwin is not None and pwin!=gwin: winner=None       # price and goal count disagree: a goal was missed -> no FT/NG settles for this game
    else: winner=pwin if pwin is not None else gwin'''
assert old in s; s=s.replace(old,new); n+=1
old2='''    # CLOCK triggers
    for m in (1,15,30,46,60,75):
        n=sum(1 for g in gl if g<m); st='0' if n==0 else ('1' if n==1 else '2+')
        for side in SIDES: emit(f'CLOCK{m}g{st}',side.lower(),side,m)'''
new2='''    # CLOCK triggers (skipped when the price contradicts the detected score: a hidden goal)
    for m in (1,15,30,46,60,75):
        n=sum(1 for g in gl if g<m); st='0' if n==0 else ('1' if n==1 else '2+')
        lo_px=min(P['HOME'][m] if not np.isnan(P['HOME'][m]) else 99, P['AWAY'][m] if not np.isnan(P['AWAY'][m]) else 99)
        if n==0 and m>=30 and lo_px<1.30: continue
        if m<60 and lo_px<1.10: continue
        for side in SIDES: emit(f'CLOCK{m}g{st}',side.lower(),side,m)'''
assert old2 in s; s=s.replace(old2,new2); n+=1
open(p,'w').write(s); print("patches:",n)
PY
python3 -m py_compile sport_sweep.py || exit 1
python3 - <<'PY'
import numpy as np, pandas as pd
src=open('/root/pe-factory/v4/sport_sweep.py').read().split("def main():")[0].replace("from bot_core import DB","DB=''"); ns={}; exec(src,ns)
def mk(spec,skip=()):
    rows=[]
    for m in range(0,96):
        if m in skip: continue
        h,d,a=spec(m)
        for sel,p in (('HOME',h),('DRAW',d),('AWAY',a)): rows.append(dict(event_id='e',m=pd.Timestamp('2025-01-01'),minute=m,sel=sel,ltp=p))
    return pd.DataFrame(rows)
# hidden goal: home at 1.05 from minute 1 (goal before data starts), never detected; price-decided HOME, goal count DRAW -> winner None, CLOCK skipped
g=mk(lambda m:(1.05, 20.0, 40.0)); P,LP,gl,sc,w=ns['parse_game'](g); print("hidden goal: goals",gl,"winner",w,"agree",ns['AGREE'][-1])
assert gl==[] and w is None
T=ns['game_trades'](P,LP,gl,sc,w,pd.Timestamp('2025-01-01').date()); R=pd.DataFrame(T,columns=['trig','role','dir','exit','band','d','p'])
print("CLOCK trades on the hidden-goal game:",len(R[R.trig.str.startswith('CLOCK')])); assert len(R[R.trig.str.startswith('CLOCK')])==0
# normal game: home scores 20, wins; price-decided HOME, goals HOME -> agree
g=mk(lambda m:(2.0 if m<20 else (1.4 if m<90 else 1.02), 3.4 if m<20 else 5.0, 3.5 if m<22 else 8.0),skip=(20,)); P,LP,gl,sc,w=ns['parse_game'](g); print("normal:",gl,sc,w,ns['AGREE'][-1]); assert w=='HOME' and ns['AGREE'][-1]==('HOME','HOME')
print("consistency tests PASS")
PY
(nohup timeout 10000 python3 sport_sweep.py > sport_sweep.log 2>&1 &); echo "sweep restarted"
