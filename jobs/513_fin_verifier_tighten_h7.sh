#!/bin/bash
# 513: (1) Verifier bug: "WORKS AT SMALL SIZE" ignored the control; it now requires |control t|<=2 like WORKS, so H6/H2 are re-graded.
# (2) H7 diagnostic (pre-registered): the stocks ORB/fade controls come out POSITIVE (t 3.4) with RANDOM direction, which is impossible
# for a fair simulation of a driftless price. Re-run the stocks ORB with REALISTIC fills: stop and target filled at the NEXT bar's open
# after the breach (not at the level), costs doubled, and report real vs random-side. If the random side is still >0 the data or the
# sim is at fault and both stock verdicts are withdrawn; if it drops to ~0 the earlier fills were the artefact.
cd /root/pe-fin/team || exit 1
python3 - <<'PY'
s=open('fin_team.py').read()
s=s.replace("if not ok and r.get('n',0)>=60 and r.get('t',0)>=1.5 and r.get('oos_mean',0)>0:","if not ok and r.get('n',0)>=60 and r.get('t',0)>=1.5 and r.get('oos_mean',0)>0 and abs(r.get('control_t',0))<=GATE['control_abs_max']:")
open('fin_team.py','w').write(s)
PY
cat > orb_stocks_realfill.py <<'PY'
import sys, os, math, json, numpy as np, pandas as pd
sys.path.insert(0,'/root/pe-fin'); from alpaca_load import load
BASE='/root/pe-data/alpaca'; N=20
syms=[s for s in os.listdir(BASE) if os.path.isdir(f"{BASE}/{s}") and s not in ('QQQ','SPY','IWM','TLT','GLD','USO','TQQQ','SQQQ')]
def run(control):
    recs=[]; rng=np.random.default_rng(7)
    for sym in syms:
        b=load(sym)
        if len(b)<50000: continue
        ny=b.index.tz_convert('America/New_York'); b=b.assign(d=ny.date, mi=ny.hour*60+ny.minute-570); b=b[(b.mi>=0)&(b.mi<390)]
        day=b.groupby('d').agg(o=('open','first'),h=('high','max'),l=('low','min'),c=('close','last'),v=('volume','sum'))
        f5=b[b.mi<5].groupby('d').agg(o5=('open','first'),c5=('close','last'),h5=('high','max'),l5=('low','min'),v5=('volume','sum')); day=day.join(f5); day['prev']=day.c.shift(1)
        tr=np.maximum(day.h-day.l,np.maximum((day.h-day.prev).abs(),(day.l-day.prev).abs())); day['atr14']=tr.rolling(14).mean().shift(1)
        day['relvol']=day.v5/day.v5.rolling(14).mean().shift(1); day['dollar']=(day.c*day.v).rolling(14).mean().shift(1); g=b.groupby('d')
        for d,r in day.iterrows():
            if not (r.relvol>0 and r.dollar>5e7 and r.o>5 and r.atr14>0 and r.h5>r.l5): continue
            if abs(r.c5-r.o5)<0.05*(r.h5-r.l5): continue
            side=1 if r.c5>r.o5 else -1
            if control: side=rng.choice([-1,1])
            rest=g.get_group(d); rest=rest[rest.mi>=5]
            if len(rest)<100: continue
            o=rest.open.values; hi=rest.high.values; lo=rest.low.values; cl=rest.close.values
            entry=o[0]; R=max(abs(entry-(r.l5 if side>0 else r.h5)),0.1*r.atr14); stop=entry-side*R; target=entry+side*10*R
            breach_s=np.where((lo<=stop) if side>0 else (hi>=stop))[0]; breach_t=np.where((hi>=target) if side>0 else (lo<=target))[0]
            i_s=breach_s[0] if len(breach_s) else 10**9; i_t=breach_t[0] if len(breach_t) else 10**9
            i=min(i_s,i_t)
            if i<10**9 and i+1<len(o): ex=o[i+1]          # filled at the NEXT bar's open after the breach, whichever came first
            else: ex=cl[-1]
            cost=2*(0.02+0.00005*entry)
            recs.append(dict(date=pd.Timestamp(d),relvol=r.relvol,r_mult=(side*(ex-entry)-cost)/R))
    A=pd.DataFrame(recs).sort_values(['date','relvol'],ascending=[True,False]); A['rank']=A.groupby('date').cumcount()+1; P=A[A['rank']<=N]
    return P.groupby('date').r_mult.mean()
def st(s):
    n=len(s); h=n//2; t=lambda a:a.mean()/(a.std(ddof=1)/math.sqrt(len(a))) if len(a)>5 else 0
    return dict(n=n,mean=float(s.mean()),t=float(t(s)),is_mean=float(s[:h].mean()),is_t=float(t(s[:h])),oos_mean=float(s[h:].mean()),oos_t=float(t(s[h:])))
real=st(run(False)); ctrl=st(run(True)); print("real",real); print("control",ctrl)
print("RESULT "+json.dumps(dict(name="H7 stocks ORB, realistic fills (next-bar open, 2x cost)",n=real['n'],mean_bps=f"{real['mean']:+.3f} R/day",t=round(real['t'],2),is_mean=real['is_mean'],is_t=round(real['is_t'],2),oos_mean=real['oos_mean'],oos_t=round(real['oos_t'],2),control_t=round(ctrl['t'],2))))
PY
python3 -m py_compile fin_team.py orb_stocks_realfill.py || exit 1
python3 - <<'PY'
import json; reg=json.load(open('hypotheses.json'))
reg['hypotheses']=[h for h in reg['hypotheses'] if not h['id'].startswith('H7')]
reg['hypotheses'].append({"id":"H7 realfill","script":"/root/pe-fin/team/orb_stocks_realfill.py","status":"proposed","pre_registered_sign":"diagnostic: control must be ~0","next_door":"if control ~0 and real >0: stocks ORB stands with these fills; else withdraw both stock verdicts","timeout":10800})
# re-grade: mark H1-5 and H6 proposed again so the tightened Verifier re-scores them from fresh runs
for h in reg['hypotheses']:
    if h['id'].startswith('H6'): h['status']='proposed'
json.dump(reg,open('hypotheses.json','w'),indent=1); print([(h['id'],h['status']) for h in reg['hypotheses']])
PY
pkill -f 'fin_team.py'; sleep 1; nohup /root/pe-fin/team/run_team.sh & disown; sleep 3; pgrep -f fin_team.py >/dev/null && echo "daemon restarted" || { echo "DAEMON NOT RUNNING"; exit 1; }
