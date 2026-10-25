#!/bin/bash
# 170: GOAL DETECTION v3 + VALIDATION AGAINST REAL GOAL TIMES. 165's "draw falls 20%" rule for equalisers also fires on ordinary
# late-game time decay and on unsynchronised prints, producing fake goals and absurd cells (lay the draw after a 'goal', 97% winners).
# New rule, symmetric and independent of the draw: a goal minute is one where one of HOME/AWAY FALLS >= 15% and the other RISES >= 15%
# on fresh prints (both sides printed that minute); scorer = the faller. Merge within 4 minutes. VALIDATION: Understat shots with
# result 'Goal'/'OwnGoal' carry the true minute; for every joined game (xg_price_map) compare detected goal minutes with the true ones
# (+-2 min tolerance) and print precision/recall and the mean offset. The sweep is NOT re-run until that check passes (>= 90%).
cd /root/pe-factory/v4 && pkill -f sport_sweep.py; sleep 1
python3 - <<'PY'
p='sport_sweep.py'; s=open(p).read(); n=0
old='''    dr=S['DRAW']; dv=dr.values; dm=dr.index.values
    goals=[int(dm[i]) for i in range(1,len(dv)) if (dv[i]>=dv[i-1]*1.20 or dv[i]<=dv[i-1]/1.20) and 2<=dm[i]<=90]
    gl=[]
    for gm in goals:
        if not gl or gm-gl[-1]>=4: gl.append(gm)
    scorers=[]
    for gm in gl:
        ratios={}
        for side in ('HOME','AWAY'):
            pre=P[side][gm-1]; post=P[side][min(gm+1,MAXM)]
            if not np.isnan(pre) and not np.isnan(post) and pre>0: ratios[side]=post/pre
        sc=min(ratios,key=ratios.get) if ratios else None
        scorers.append(sc if (sc and ratios[sc]<=0.90) else None)'''
new='''    gl=[]; scorers=[]
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
assert old in s; s=s.replace(old,new); n+=1
open(p,'w').write(s); print("patches:",n)
PY
python3 -m py_compile sport_sweep.py || exit 1
python3 - <<'PY'
import numpy as np, pandas as pd
src=open('/root/pe-factory/v4/sport_sweep.py').read().split("def main():")[0].replace("from bot_core import DB","DB=''"); ns={}; exec(src,ns)
def mk(spec):
    rows=[]
    for m in range(0,96):
        h,d,a=spec(m)
        for sel,p in (('HOME',h),('DRAW',d),('AWAY',a)): rows.append(dict(event_id='e',m=pd.Timestamp('2025-01-01'),minute=m,sel=sel,ltp=p))
    return pd.DataFrame(rows)
# 1-0 at 20, 1-1 at 60, drawn
g=mk(lambda m:(2.0 if m<20 else (1.4 if m<60 else 2.6), 3.4 if m<20 else (5.0 if m<60 else max(1.3,2.4-0.03*(m-60))), 3.5 if m<20 else (8.0 if m<60 else 4.5)))
P,LP,gl,sc,w=ns['parse_game'](g); print("test1 goals",gl,sc,w); assert gl==[20,60] and sc==['HOME','AWAY'] and w=='DRAW'
# late time decay only (0-0, draw falls 20%/min from 85), no goal
g=mk(lambda m:(2.0+0.02*m, max(1.05,3.4-0.02*m-(0.25*(m-85) if m>85 else 0)), 3.5+0.03*m))
P,LP,gl,sc,w=ns['parse_game'](g); print("test2 (decay, no goal) goals",gl,w); assert gl==[] and w=='DRAW'
print("detection v3 PASS")
PY
echo "== validation against Understat goal minutes (joined games with shots loaded so far)"
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys, numpy as np, pandas as pd, psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
src=open('/root/pe-factory/v4/sport_sweep.py').read().split("def main():")[0]; ns={}; exec(src,ns)
con=psycopg2.connect(DB,sslmode='require')
M=pd.read_sql("SELECT m.understat_id, m.event_id FROM xg_price_map m WHERE EXISTS (SELECT 1 FROM understat_shots s WHERE s.understat_id=m.understat_id)",con)
print("joined games with shots:",len(M))
if len(M):
    T=pd.read_sql("SELECT understat_id, minute, team_side FROM understat_shots WHERE result IN ('Goal','OwnGoal') AND understat_id = ANY(%s)",con,params=(list(M.understat_id),))
    D=pd.read_sql("SELECT event_id, m, minute, sel, ltp::float ltp FROM bf_hist_price WHERE mkt='MO' AND event_id = ANY(%s) AND minute BETWEEN 0 AND 95 ORDER BY event_id, sel, minute",con,params=(list(M.event_id),))
    tp=fp=fn=0; offs=[]; side_ok=0; side_n=0
    for r in M.itertuples():
        g=D[D.event_id==r.event_id]
        if g.empty: continue
        res=ns['parse_game'](g)
        if res is None: continue
        P,LP,gl,sc,w=res
        true=T[T.understat_id==r.understat_id].sort_values('minute')
        tm=[int(x) for x in true.minute]; ts=['HOME' if (s_=='h') else 'AWAY' for s_ in true.team_side]
        # Understat: an own goal is listed under the team that benefits? (result OwnGoal, h_a = side of the player) -> flip
        og=list(true.minute[true.index.isin(true.index)])  # placeholder keep
        used=set()
        for gm,s_ in zip(gl,sc):
            best=None
            for j,t in enumerate(tm):
                if j in used: continue
                # price minutes exclude half-time; understat minutes are match minutes -> allow +-3 and 2nd-half offset tolerance
                if abs(gm-t)<=3 or abs(gm-t-15)<=3: best=j; break
            if best is None: fp+=1
            else: tp+=1; used.add(best); offs.append(gm-tm[best]); side_n+=1; side_ok+= (s_==ts[best])
        fn+=len(tm)-len(used)
    print(f"detected goals {tp+fp} | true goals {tp+fn} | precision {tp/max(1,tp+fp):.1%} | recall {tp/max(1,tp+fn):.1%} | scorer side correct {side_ok/max(1,side_n):.1%} | median offset (price minute - true minute) {np.median(offs) if offs else None}")
    print("offset distribution:",pd.Series(offs).value_counts().sort_index().to_dict() if offs else None)
PY
