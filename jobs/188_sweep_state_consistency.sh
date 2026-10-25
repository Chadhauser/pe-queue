#!/bin/bash
# 188: SWEEP — SCORE STATE MUST AGREE WITH THE MARKET. The true-results shelf (185) was topped by "lay the draw at 1.5-2.5 at 75'
# with one goal scored": inspection shows those are 0-0 games where the only goal came AFTER 75' — a false early detection plus a
# missed late goal gave the right total by coincidence, and the cell is pure selection on detection errors. Two guards:
# (1) state from detected scorers, checked against the market: if the detected score is a lead but the draw is < 2.5, or level but
#     the draw is > 6.0, the state is wrong -> no CLOCK trigger at that minute; (2) where half-time scores exist (football_matches),
#     detected goals before 46' must equal the HT total, else no CLOCK triggers for the game. Sweep restarted; 189 reports.
cd /root/pe-factory/v4 && pkill -f sport_sweep.py; sleep 1
python3 - <<'PY'
p='sport_sweep.py'; s=open(p).read(); n=0
old='''    for m in ((1,15,30,46,60,75) if clock_ok else ()):
        n=sum(1 for g in gl if g<m); st='0' if n==0 else ('1' if n==1 else '2+')
        lo_px=min(P['HOME'][m] if not np.isnan(P['HOME'][m]) else 99, P['AWAY'][m] if not np.isnan(P['AWAY'][m]) else 99)
        if n==0 and m>=30 and lo_px<1.30: continue
        if m<60 and lo_px<1.10: continue
        for side in SIDES: emit(f'CLOCK{m}g{st}',side.lower(),side,m)'''
new='''    for m in ((1,15,30,46,60,75) if clock_ok else ()):
        n=sum(1 for g in gl if g<m); st='0' if n==0 else ('1' if n==1 else '2+')
        dh=sum(1 for g,sc in zip(gl,scorers) if g<m and sc=='HOME'); da=sum(1 for g,sc in zip(gl,scorers) if g<m and sc=='AWAY')
        lo_px=min(P['HOME'][m] if not np.isnan(P['HOME'][m]) else 99, P['AWAY'][m] if not np.isnan(P['AWAY'][m]) else 99)
        dpx=P['DRAW'][m] if not np.isnan(P['DRAW'][m]) else None
        if n==0 and m>=30 and lo_px<1.30: continue
        if m<60 and lo_px<1.10: continue
        if dpx is None: continue
        if dh!=da and dpx<2.5: continue                      # market says level, detection says a lead: state wrong
        if dh==da and dpx>6.0: continue                      # market says a lead, detection says level: state wrong
        for side in SIDES: emit(f'CLOCK{m}g{st}',side.lower(),side,m)'''
assert old in s; s=s.replace(old,new); n+=1
old2='''            if res is None: w_=None; clock_ok=True; STAT['no_result']+=1
            else:
                hg,ag=res; w_='HOME' if hg>ag else ('AWAY' if ag>hg else 'DRAW'); clock_ok=(len(gl_)==hg+ag); STAT['with_result']+=1; STAT['count_match']+=int(clock_ok)'''
new2='''            if res is None: w_=None; clock_ok=True; STAT['no_result']+=1
            else:
                hg,ag,ht=res; w_='HOME' if hg>ag else ('AWAY' if ag>hg else 'DRAW'); clock_ok=(len(gl_)==hg+ag) and (ht is None or sum(1 for g in gl_ if g<46)==ht); STAT['with_result']+=1; STAT['count_match']+=int(clock_ok)'''
assert old2 in s; s=s.replace(old2,new2); n+=1
old3='''    cur.execute("SELECT event_id, fthg, ftag FROM event_results"); RESULTS.update({r[0]:(int(r[1]),int(r[2])) for r in cur.fetchall()}); print("true results available for",len(RESULTS),"events",flush=True)'''
new3='''    cur.execute("SELECT event_id, fthg, ftag, hthg, htag FROM event_results"); RESULTS.update({r[0]:(int(r[1]),int(r[2]),(int(r[3])+int(r[4]) if r[3] is not None and r[4] is not None else None)) for r in cur.fetchall()}); print("true results available for",len(RESULTS),"events",flush=True)'''
assert old3 in s; s=s.replace(old3,new3); n+=1
open(p,'w').write(s); print("patches:",n)
PY
python3 -m py_compile sport_sweep.py || exit 1
python3 - <<'PY'
import numpy as np, pandas as pd
src=open('/root/pe-factory/v4/sport_sweep.py').read().split("def main():")[0].replace("from bot_core import DB","DB=''"); ns={}; exec(src,ns)
# 0-0 game with a FALSE detected goal injected: simulate by passing gl/scorers manually; draw at 75' is 1.8 (level market)
rows=[]
for m in range(0,96):
    h,d,a=3.0+0.02*m, max(1.5,4.0-0.03*m), 3.2+0.02*m
    for sel,p in (('HOME',h),('DRAW',d),('AWAY',a)): rows.append(dict(event_id='e',m=pd.Timestamp('2025-01-01'),minute=m,sel=sel,ltp=p))
g=pd.DataFrame(rows); P,LP,gl,sc,w=ns['parse_game'](g)
T=ns['game_trades'](P,LP,[40],['HOME'],None,pd.Timestamp('2025-01-01').date(),True); R=pd.DataFrame(T,columns=['trig','role','dir','exit','band','d','p'])
late=R[R.trig.isin(['CLOCK46g1','CLOCK60g1','CLOCK75g1'])]; print("CLOCK cells after a false goal with a level market:",len(late),"(must be 0)"); assert len(late)==0
T=ns['game_trades'](P,LP,[],[],None,pd.Timestamp('2025-01-01').date(),True); R=pd.DataFrame(T,columns=['trig','role','dir','exit','band','d','p'])
print("CLOCK75g0 cells with level market and no goals:",len(R[R.trig=='CLOCK75g0']),"(must be >0)"); assert len(R[R.trig=='CLOCK75g0'])>0
print("state-consistency PASS")
PY
(nohup timeout 10000 python3 sport_sweep.py > sport_sweep.log 2>&1 &); echo "sweep restarted"
