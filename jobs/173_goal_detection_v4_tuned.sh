#!/bin/bash
# 173: GOAL DETECTION v4 — TUNED ON TRUE GOAL MINUTES. 60 joined games pulled locally and the detector tuned against Understat's
# goal minutes. Findings from the raw paths: the file's minute is match minute (no half-time offset); a goal's move is spread over
# TWO prints (sides lag each other by a minute); prints are missing in the goal minute itself; and the noise that caused false goals
# lives at the price extremes (a 1.02 favourite's opponent flapping 13 <-> 8). Rule v4: over two consecutive prints, the scorer's
# price falls to <= 0.7x OR its implied probability rises >= 0.08, AND the other side rises >= 15% or the draw moves >= 15%, AND
# both sides were priced 1.08-30 beforehand (market live). Local result on 120 tradeable goals: precision 91%, recall 93%,
# scorer side 93% (vs 83% / 31% for v3). Own goals: Understat tags the player's side, so the beneficiary is the other team.
# This job installs v4, re-validates on every joined game loaded so far, and restarts the sweep only if precision and recall >= 85%.
cd /root/pe-factory/v4 && pkill -f sport_sweep.py; sleep 1
python3 - <<'PY'
p='sport_sweep.py'; s=open(p).read(); n=0
old='''    gl=[]; scorers=[]
    for i in range(2,91):
        if LP['HOME'][i]!=i or LP['AWAY'][i]!=i: continue             # both sides must have printed this minute
        h0,h1=P['HOME'][i-1],P['HOME'][i]; a0,a1=P['AWAY'][i-1],P['AWAY'][i]
        if np.isnan(h0) or np.isnan(a0) or h0<=0 or a0<=0: continue
        rh,ra=h1/h0,a1/a0; sc=None
        if rh<=0.85 and ra>=1.15: sc='HOME'
        elif ra<=0.85 and rh>=1.15: sc='AWAY'
        if sc is None: continue
        if gl and i-gl[-1]<4: continue
        gl.append(i); scorers.append(sc)'''
new='''    gl=[]; scorers=[]
    Q={sel:S[sel].to_dict() for sel in SIDES}
    ms=sorted(set(Q['HOME'])&set(Q['AWAY'])&set(Q['DRAW']))
    for i in range(2,len(ms)):
        a,b=ms[i-2],ms[i]
        if b-a>5 or b>92: continue
        if not (1.08<=Q['HOME'][a]<=30 and 1.08<=Q['AWAY'][a]<=30): continue
        rh=Q['HOME'][b]/Q['HOME'][a]; ra=Q['AWAY'][b]/Q['AWAY'][a]; rd=Q['DRAW'][b]/Q['DRAW'][a]
        ph=1/Q['HOME'][b]-1/Q['HOME'][a]; pa=1/Q['AWAY'][b]-1/Q['AWAY'][a]; sc=None
        if (rh<=0.7 or ph>=0.08) and (ra>=1.15 or abs(rd-1)>=0.15): sc='HOME'
        elif (ra<=0.7 or pa>=0.08) and (rh>=1.15 or abs(rd-1)>=0.15): sc='AWAY'
        if sc is None or (gl and b-gl[-1]<3): continue
        gl.append(b); scorers.append(sc)'''
assert old in s; s=s.replace(old,new); n+=1
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
# home scores 20 (no print at 20, away lags to 22), away equalises 60
g=mk(lambda m:(2.0 if m<20 else (1.4 if m<60 else 2.6), 3.4 if m<20 else (5.0 if m<60 else 2.4), 3.5 if m<22 else (8.0 if m<60 else 4.5)),skip=(20,))
P,LP,gl,sc,w=ns['parse_game'](g); print("goals",gl,sc,w); assert gl[0] in (21,22) and sc==['HOME','AWAY'] and w=='DRAW'
g=mk(lambda m:(2.0+0.02*m, max(1.05,3.4-0.02*m-(0.25*(m-85) if m>85 else 0)), 3.5+0.03*m))
P,LP,gl,sc,w=ns['parse_game'](g); print("decay-only goals",gl); assert gl==[]
print("v4 unit tests PASS")
PY
echo "== validation on all joined games with shots loaded so far"
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys, numpy as np, pandas as pd, psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
src=open('/root/pe-factory/v4/sport_sweep.py').read().split("def main():")[0]; ns={}; exec(src,ns)
con=psycopg2.connect(DB,sslmode='require')
M=pd.read_sql("SELECT m.understat_id, m.event_id FROM xg_price_map m WHERE EXISTS (SELECT 1 FROM understat_shots s WHERE s.understat_id::text=m.understat_id)",con)
T=pd.read_sql("SELECT understat_id::text understat_id, minute, team_side, result FROM understat_shots WHERE result IN ('Goal','OwnGoal') AND understat_id::text = ANY(%s)",con,params=(list(M.understat_id),))
T['side']=np.where((T.team_side=='h')^(T.result=='OwnGoal'),'HOME','AWAY')
print("joined games with shots:",len(M),"true goals:",len(T))
tp=fp=fn=0; offs=[]; side_ok=0
for b in range(0,len(M),400):
    sub=M.iloc[b:b+400]
    D=pd.read_sql("SELECT event_id, m, minute, sel, ltp::float ltp FROM bf_hist_price WHERE mkt='MO' AND event_id = ANY(%s) AND minute BETWEEN 0 AND 95 ORDER BY event_id, sel, minute",con,params=(list(sub.event_id),))
    for r in sub.itertuples():
        g=D[D.event_id==r.event_id]
        if g.empty: continue
        res=ns['parse_game'](g)
        if res is None: continue
        P,LP,gl,sc,w=res
        tg=[]
        for t_ in T[T.understat_id==r.understat_id].itertuples():
            t=int(t_.minute); pre=[m for m in range(0,t+1) if LP['HOME'][min(m,95)]==m and LP['AWAY'][min(m,95)]==m]
            if not pre or t>90: continue
            m=max(pre)
            if 1.08<=P['HOME'][m]<=30 and 1.08<=P['AWAY'][m]<=30: tg.append((t,t_.side))
        used=set()
        for gm,s_ in zip(gl,sc):
            best=next((j for j,(t,sd) in enumerate(tg) if j not in used and -3<=gm-t<=6),None)
            if best is None:
                if any(-3<=gm-int(t)<=6 for t in T[T.understat_id==r.understat_id].minute): continue
                fp+=1
            else: tp+=1; used.add(best); offs.append(gm-tg[best][0]); side_ok+=(s_==tg[best][1])
        fn+=len(tg)-len(used)
prec=tp/max(1,tp+fp); rec=tp/max(1,tp+fn)
print(f"tradeable true goals {tp+fn} | detected {tp+fp} | precision {prec:.1%} | recall {rec:.1%} | scorer side correct {side_ok/max(1,tp):.1%} | median offset {np.median(offs) if offs else None}")
open('/root/pe-factory/v4/detection_ok','w').write('1' if (prec>=0.85 and rec>=0.85) else '0')
PY
if [ "$(cat /root/pe-factory/v4/detection_ok)" = "1" ]; then (nohup timeout 10000 python3 sport_sweep.py > sport_sweep.log 2>&1 &); echo "detection passed -> sweep restarted"; else echo "detection below 85/85 -> sweep NOT restarted"; fi
