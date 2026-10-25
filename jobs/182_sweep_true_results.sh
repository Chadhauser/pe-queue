#!/bin/bash
# 182: SWEEP — SETTLE FROM TRUE RESULTS. FT and next-goal settles now use event_results (181) only; games without a true result get
# hedged exits only. Where the detected goal count differs from the true total the game's state is unknown, so CLOCK (score-state)
# triggers are skipped for it; GOAL/DRIFT/STEAM triggers (each anchored on a real detected move) still run with hedged exits.
# Prints: share of games with true results, share where detected goals == true goals, then restarts the sweep. 183 reports.
cd /root/pe-factory/v4 && pkill -f sport_sweep.py; sleep 1
python3 - <<'PY'
p='sport_sweep.py'; s=open(p).read(); n=0
old="def game_trades(P,LP,gl,scorers,winner,date):"
new="def game_trades(P,LP,gl,scorers,winner,date,clock_ok=True):"
assert old in s; s=s.replace(old,new); n+=1
old2='''    # CLOCK triggers (skipped when the price contradicts the detected score: a hidden goal)
    for m in (1,15,30,46,60,75):'''
new2='''    # CLOCK triggers (skipped when the price contradicts the detected score, or the true goal count disagrees with detection)
    for m in ((1,15,30,46,60,75) if clock_ok else ()):'''
assert old2 in s; s=s.replace(old2,new2); n+=1
old3='''        T=[]
        for eid,g in D.groupby('event_id',sort=False):
            r=parse_game(g)
            if r is None: continue
            games+=1; T.extend(game_trades(*r,pd.Timestamp(g.m.iloc[0]).date()))'''
new3='''        T=[]
        for eid,g in D.groupby('event_id',sort=False):
            r=parse_game(g)
            if r is None: continue
            P_,LP_,gl_,sc_,w_=r; res=RESULTS.get(eid)
            if res is None: w_=None; clock_ok=True; STAT['no_result']+=1
            else:
                hg,ag=res; w_='HOME' if hg>ag else ('AWAY' if ag>hg else 'DRAW'); clock_ok=(len(gl_)==hg+ag); STAT['with_result']+=1; STAT['count_match']+=int(clock_ok)
            games+=1; T.extend(game_trades(P_,LP_,gl_,sc_,w_,pd.Timestamp(g.m.iloc[0]).date(),clock_ok))'''
assert old3 in s; s=s.replace(old3,new3); n+=1
old4='''    cur.execute("SELECT DISTINCT event_id FROM bf_hist_price WHERE mkt='MO'"); evs=[r[0] for r in cur.fetchall()]; print("games:",len(evs),flush=True)'''
new4='''    cur.execute("SELECT DISTINCT event_id FROM bf_hist_price WHERE mkt='MO'"); evs=[r[0] for r in cur.fetchall()]; print("games:",len(evs),flush=True)
    cur.execute("SELECT event_id, fthg, ftag FROM event_results"); RESULTS.update({r[0]:(int(r[1]),int(r[2])) for r in cur.fetchall()}); print("true results available for",len(RESULTS),"events",flush=True)'''
assert old4 in s; s=s.replace(old4,new4); n+=1
s=s.replace("AGREE=[]; SIDES=","RESULTS={}; STAT={'no_result':0,'with_result':0,'count_match':0}; AGREE=[]; SIDES=",1); n+=1
old5='''    R=pd.concat(parts,ignore_index=True)'''
new5='''    R=pd.concat(parts,ignore_index=True)
    print(f"games with true result {STAT['with_result']} | without {STAT['no_result']} | detected goal count == true total in {STAT['count_match']/max(1,STAT['with_result']):.1%} of games with results (CLOCK cells use only those)")'''
assert old5 in s; s=s.replace(old5,new5); n+=1
open(p,'w').write(s); print("patches:",n)
PY
python3 -m py_compile sport_sweep.py || exit 1
python3 - <<'PY'
import numpy as np, pandas as pd
src=open('/root/pe-factory/v4/sport_sweep.py').read().split("def main():")[0].replace("from bot_core import DB","DB=''"); ns={}; exec(src,ns)
rows=[]
for m in range(0,96):
    if m==20: continue
    h=2.0 if m<20 else 1.4; d=3.4 if m<20 else 5.0; a=3.5 if m<22 else 8.0
    for sel,p in (('HOME',h),('DRAW',d),('AWAY',a)): rows.append(dict(event_id='e',m=pd.Timestamp('2025-01-01'),minute=m,sel=sel,ltp=p))
g=pd.DataFrame(rows); P,LP,gl,sc,w=ns['parse_game'](g)
T1=ns['game_trades'](P,LP,gl,sc,'HOME',pd.Timestamp('2025-01-01').date(),True); T2=ns['game_trades'](P,LP,gl,sc,None,pd.Timestamp('2025-01-01').date(),False)
R1=pd.DataFrame(T1,columns=['trig','role','dir','exit','band','d','p']); R2=pd.DataFrame(T2,columns=['trig','role','dir','exit','band','d','p'])
print("with result+clock:",len(R1),"FT cells",int((R1.exit=='FT').sum()),"| no result, no clock:",len(R2),"FT cells",int((R2.exit=='FT').sum()),"CLOCK",int(R2.trig.str.startswith('CLOCK').sum()))
assert (R1.exit=='FT').sum()>0 and (R2.exit=='FT').sum()==0 and R2.trig.str.startswith('CLOCK').sum()==0; print("PASS")
PY
(nohup timeout 10000 python3 sport_sweep.py > sport_sweep.log 2>&1 &); echo "sweep restarted with true results"
