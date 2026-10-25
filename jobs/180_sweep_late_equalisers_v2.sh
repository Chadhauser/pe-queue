#!/bin/bash
# 180: (178 failed its own unit test — rule A fired on a 1.14->1.05 clock-decay move; now a short-price drop needs rh<=0.85 as well.) Also: when the file ends early with a side already <=1.10 after 60', that side is the price-decided winner. SWEEP — LATE EQUALISERS WERE INVISIBLE. "Lay the draw at 5+ with a one-goal lead at 75', hold to FT: 98.9% winners" is
# impossible (equalisers after 75' happen ~12% of the time). Two causes, both systematic: (1) the detector switches off when a side is
# priced < 1.08 — exactly the state of a late leader — so late equalisers were never goals; (2) prices were read only to minute 95,
# but the file's minute includes stoppage time, so the final whistle (and the draw's price collapse) often sits at 96-100 and the
# price-decided result was missing for draws. Fixes: rule B for goals when a side is short: draw price halves over two prints AND the
# short side's price rises >= 50% -> equaliser by the other side; results read from the LAST print (minutes to 120), trading still
# limited to 0-95. Unit test: 1-0 leader at 1.05, equaliser at 89 -> goal found, result DRAW. Validation against Understat re-run.
cd /root/pe-factory/v4 && pkill -f sport_sweep.py; sleep 1
python3 - <<'PY'
p='sport_sweep.py'; s=open(p).read(); n=0
old='''        if not (1.08<=Q['HOME'][a]<=30 and 1.08<=Q['AWAY'][a]<=30): continue
        rh=Q['HOME'][b]/Q['HOME'][a]; ra=Q['AWAY'][b]/Q['AWAY'][a]; rd=Q['DRAW'][b]/Q['DRAW'][a]
        ph=1/Q['HOME'][b]-1/Q['HOME'][a]; pa=1/Q['AWAY'][b]-1/Q['AWAY'][a]; sc=None
        if (rh<=0.7 or ph>=0.08) and (ra>=1.15 or abs(rd-1)>=0.15): sc='HOME'
        elif (ra<=0.7 or pa>=0.08) and (rh>=1.15 or abs(rd-1)>=0.15): sc='AWAY'
        if sc is None or (gl and b-gl[-1]<3): continue
        gl.append(b); scorers.append(sc)'''
new='''        rh=Q['HOME'][b]/Q['HOME'][a]; ra=Q['AWAY'][b]/Q['AWAY'][a]; rd=Q['DRAW'][b]/Q['DRAW'][a]
        ph=1/Q['HOME'][b]-1/Q['HOME'][a]; pa=1/Q['AWAY'][b]-1/Q['AWAY'][a]; sc=None
        if 1.08<=Q['HOME'][a]<=30 and 1.08<=Q['AWAY'][a]<=30:            # rule A: live market, scorer shortens hard
            if (rh<=0.7 or (ph>=0.08 and rh<=0.85)) and (ra>=1.15 or abs(rd-1)>=0.15): sc='HOME'
            elif (ra<=0.7 or (pa>=0.08 and ra<=0.85)) and (rh>=1.15 or abs(rd-1)>=0.15): sc='AWAY'
        elif Q['HOME'][a]<1.08 and rd<=0.5 and rh>=1.5: sc='AWAY'       # rule B: short leader drifts, draw halves -> equaliser
        elif Q['AWAY'][a]<1.08 and rd<=0.5 and ra>=1.5: sc='HOME'
        if sc is None or (gl and b-gl[-1]<3): continue
        gl.append(b); scorers.append(sc)'''
assert old in s; s=s.replace(old,new); n+=1
old2="        if b-a>5 or b>92: continue"
new2="        if b-a>5 or b>100: continue"
assert old2 in s; s=s.replace(old2,new2); n+=1
old3='''    finals={s:P[s][MAXM] for s in SIDES}; finals={k:v for k,v in finals.items() if not np.isnan(v)}'''
new3='''    finals={sel:float(S[sel].iloc[-1]) for sel in SIDES if len(S[sel]) and S[sel].index.max()>=60}'''
assert old3 in s; s=s.replace(old3,new3); n+=1
old4='''        D=pd.read_sql("SELECT event_id, m, minute, sel, ltp::float ltp FROM bf_hist_price WHERE mkt='MO' AND event_id = ANY(%s) AND minute BETWEEN 0 AND 95 ORDER BY event_id, sel, minute",con,params=(evs[b:b+1500],))'''
new4='''        D=pd.read_sql("SELECT event_id, m, minute, sel, ltp::float ltp FROM bf_hist_price WHERE mkt='MO' AND event_id = ANY(%s) AND minute BETWEEN 0 AND 120 ORDER BY event_id, sel, minute",con,params=(evs[b:b+1500],))'''
assert old4 in s; s=s.replace(old4,new4); n+=1
open(p,'w').write(s); print("patches:",n)
PY
python3 -m py_compile sport_sweep.py || exit 1
python3 - <<'PY'
import numpy as np, pandas as pd
src=open('/root/pe-factory/v4/sport_sweep.py').read().split("def main():")[0].replace("from bot_core import DB","DB=''"); ns={}; exec(src,ns)
rows=[]
for m in range(0,99):   # home scores 20 (1.05 by 85), away equalises 89; whistle at 97 with draw 1.01
    if m<20: h,d,a=2.0,3.4,3.5
    elif m<85: h,d,a=1.4-0.004*(m-20),5.0+0.1*(m-20),8.0+0.2*(m-20)
    elif m<89: h,d,a=1.05,15.0,30.0
    elif m<97: h,d,a=2.4,1.4,9.0
    else: h,d,a=50.0,1.01,100.0
    if m==20: continue
    for sel,p in (('HOME',h),('DRAW',d),('AWAY',a)): rows.append(dict(event_id='e',m=pd.Timestamp('2025-01-01'),minute=m,sel=sel,ltp=p))
g=pd.DataFrame(rows); P,LP,gl,sc,w=ns['parse_game'](g); print("goals",gl,sc,"winner",w,"agree",ns['AGREE'][-1])
assert sc==['HOME','AWAY'] and w=='DRAW' and ns['AGREE'][-1]==('DRAW','DRAW'); print("late-equaliser test PASS")
PY
echo "== re-validate detection against Understat (all joined games with shots)"
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys, numpy as np, pandas as pd, psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
src=open('/root/pe-factory/v4/sport_sweep.py').read().split("def main():")[0]; ns={}; exec(src,ns)
con=psycopg2.connect(DB,sslmode='require')
M=pd.read_sql("SELECT m.understat_id, m.event_id FROM xg_price_map m WHERE EXISTS (SELECT 1 FROM understat_shots s WHERE s.understat_id::text=m.understat_id)",con)
T=pd.read_sql("SELECT understat_id::text understat_id, minute, team_side, result FROM understat_shots WHERE result IN ('Goal','OwnGoal') AND understat_id::text = ANY(%s)",con,params=(list(M.understat_id),))
T['side']=np.where((T.team_side=='h')^(T.result=='OwnGoal'),'HOME','AWAY')
tp=fp=fn=0; side_ok=0; res_ok=0; res_n=0; late_tp=late_fn=0
for b in range(0,len(M),400):
    sub=M.iloc[b:b+400]
    D=pd.read_sql("SELECT event_id, m, minute, sel, ltp::float ltp FROM bf_hist_price WHERE mkt='MO' AND event_id = ANY(%s) AND minute BETWEEN 0 AND 120 ORDER BY event_id, sel, minute",con,params=(list(sub.event_id),))
    for r in sub.itertuples():
        g=D[D.event_id==r.event_id]
        if g.empty: continue
        res=ns['parse_game'](g)
        if res is None: continue
        P,LP,gl,sc,w=res; tg=[(int(t.minute),t.side) for t in T[T.understat_id==r.understat_id].itertuples()]
        used=set()
        for gm,s_ in zip(gl,sc):
            best=next((j for j,(t,sd) in enumerate(tg) if j not in used and -3<=gm-t<=8),None)
            if best is None: fp+=1
            else:
                tp+=1; used.add(best); side_ok+=(s_==tg[best][1])
                if tg[best][0]>=80: late_tp+=1
        for j,(t,sd) in enumerate(tg):
            if j not in used:
                fn+=1
                if t>=80: late_fn+=1
        hg=sum(1 for t,sd in tg if sd=='HOME'); ag=sum(1 for t,sd in tg if sd=='AWAY'); truth='HOME' if hg>ag else ('AWAY' if ag>hg else 'DRAW')
        if w is not None: res_n+=1; res_ok+=(w==truth)
print(f"ALL goals (<=95'): true {tp+fn} detected {tp+fp} | precision {tp/max(1,tp+fp):.1%} recall {tp/max(1,tp+fn):.1%} side {side_ok/max(1,tp):.1%} | late goals (80'+) recall {late_tp/max(1,late_tp+late_fn):.1%} | RESULT correct {res_ok/max(1,res_n):.1%} of {res_n} settled games ({res_n/len(M):.0%} of games settle)")
PY
echo "sweep NOT restarted here — 182 restarts it with true results"
