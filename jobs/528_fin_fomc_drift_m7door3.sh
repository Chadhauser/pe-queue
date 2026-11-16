#!/bin/bash
# 528: (1) the announcement-drift column, owed since Thu 13 Nov: scheduled FOMC decision dates 1994->now scraped from
# federalreserve.gov (minutes file names = scheduled meetings only), and the published pre-FOMC drift (Lucca & Moench) copied as
# written on SPY, QQQ, TLT, GLD daily since 1994 — control = random ordinary days, so it must beat a normal day, not just drift up.
# (2) M7 door 3 (last door): last-hour momentum on SPY, IWM and pooled by day. If neither clears, M7b stays WORKS AT SMALL SIZE on
# QQQ only and gets no more doors.
mkdir -p /root/pe-data/events && cd /root/pe-fin/team || exit 1
cat > fomc_dates.py <<'PY'
# Scheduled FOMC decision dates 1994 -> now, scraped from federalreserve.gov. Scheduled meetings are the ones with minutes, so the
# decision date = the date in the minutes / meeting-transcript file names (second day of a two-day meeting). Conference calls and
# unscheduled moves have no minutes and are excluded. Writes /root/pe-data/events/fomc.csv and prints a per-year count check.
import re, requests, datetime as dt, pandas as pd, os
OUT='/root/pe-data/events'; os.makedirs(OUT,exist_ok=True); UA={'User-Agent':'Mozilla/5.0 (research; PE Trading)'}
def grab(url):
    r=requests.get(url,headers=UA,timeout=60); return r.text if r.status_code==200 else ''
dates=set()
for y in range(1994,dt.date.today().year+1):
    html=grab(f'https://www.federalreserve.gov/monetarypolicy/fomchistorical{y}.htm')
    for d in re.findall(r'(?:fomcminutes|minutes/)(\d{8})',html)+re.findall(r'FOMC(\d{8})meeting',html):
        if d.startswith(str(y)): dates.add(d)
cur=grab('https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm')
for d in re.findall(r'fomcminutes(\d{8})',cur)+re.findall(r'monetary(\d{8})a\.htm',cur): dates.add(d)
D=sorted(pd.to_datetime(list(dates),format='%Y%m%d'))
D=[d for d in D if d.date()<=dt.date.today()]
s=pd.Series(D); cnt=s.dt.year.value_counts().sort_index()
print("per-year counts:",dict(cnt)); bad=[int(y) for y,c in cnt.items() if c<6 or c>12]
print("years outside 6-12 (check):",bad)
pd.DataFrame({'date':[d.date() for d in D]}).to_csv(f'{OUT}/fomc.csv',index=False); print("fomc dates",len(D),D[0].date() if D else None,"->",D[-1].date() if D else None)
PY
cat > mech_events.py <<'PY'
# MECH-EVENTS — announcement drift. Daily consolidated bars (Yahoo) from 1994 so event samples clear n>=200.
# E1x: pre-FOMC drift (Lucca & Moench 2015): LONG close(day before) -> close(decision day). Published effect, copied as written,
# no parameter fitting. Cost 2 bps round trip (ETFs). Control = the same number of randomly chosen NON-FOMC days, long (tests that
# the FOMC days beat an ordinary day, not just that the market drifts up). Usage: python3 -I mech_events.py <id> | list
import sys, json, math, numpy as np, pandas as pd
F=pd.to_datetime(pd.read_csv('/root/pe-data/events/fomc.csv').date)
_c={}
def daily(sym):
    if sym not in _c:
        import yfinance as yf
        d=yf.download(sym,start='1993-01-01',auto_adjust=True,progress=False)
        if isinstance(d.columns,pd.MultiIndex): d.columns=d.columns.get_level_values(0)
        _c[sym]=d[['Open','Close']].dropna()
    return _c[sym]
def pre_fomc(sym,cost=2.0):
    d=daily(sym); r=d.Close.pct_change()*1e4
    ev=r.reindex(F).dropna()-cost; other=r.drop(F,errors='ignore').dropna()-cost
    return ev, other
H={}
def reg(i,doc):
    def w(f): f.__doc__=doc; H[i]=f; return f
    return w
@reg('E1s','Pre-FOMC drift, SPY: LONG close(day before) -> close(FOMC decision day). Lucca-Moench, copied as written.')
def E1s(): return pre_fomc('SPY')
@reg('E1q','Pre-FOMC drift, QQQ (same rule).')
def E1q(): return pre_fomc('QQQ')
@reg('E1t','Pre-FOMC drift, TLT (bonds; same rule, long).')
def E1t(): return pre_fomc('TLT')
@reg('E1g','Pre-FOMC drift, GLD (gold; same rule, long).')
def E1g(): return pre_fomc('GLD')
def st(s):
    s=s.dropna(); n=len(s); h=n//2; t=lambda a:a.mean()/(a.std(ddof=1)/math.sqrt(len(a))) if len(a)>5 and a.std(ddof=1)>0 else 0
    return dict(n=n,mean=float(s.mean()) if n else 0,t=float(t(s)),is_mean=float(s[:h].mean()) if h else 0,is_t=float(t(s[:h])),oos_mean=float(s[h:].mean()) if n else 0,oos_t=float(t(s[h:])))
if __name__=='__main__':
    a=sys.argv[1] if len(sys.argv)>1 else 'list'
    if a=='list': [print(k,'—',f.__doc__) for k,f in H.items()]; sys.exit(0)
    ev,other=H[a](); R=st(ev); g=np.random.default_rng(29); ctrl=pd.Series(g.choice(other.values,len(ev),replace=False)); C=st(ctrl)
    diff=ev.mean()-other.mean()
    print(a,H[a].__doc__); print('event',R); print('control (random ordinary days)',C); print(f'event minus ordinary day: {diff:+.1f} bps')
    print("RESULT "+json.dumps(dict(name=f"{a} {H[a].__doc__[:60]} | vs ordinary day {diff:+.1f} bps",n=R['n'],mean_bps=f"{R['mean']:+.1f} bps/event",t=round(R['t'],2),is_mean=R['is_mean'],is_t=round(R['is_t'],2),oos_mean=R['oos_mean'],oos_t=round(R['oos_t'],2),control_t=round(C['t'],2))))
PY
cat > mech_m7door3.py <<'PY'
# M7 door 3 (last door): last-hour momentum on the sibling instruments. QQQ version (M7b) is WORKS AT SMALL SIZE on n=189; the same
# rule on SPY and IWM tests whether it is a market effect (more sample, same sign) or a QQQ accident. Same threshold, no fitting.
# Control = random sign (as mech2). Usage: python3 -I mech_m7door3.py M7S|M7I|M7P
import sys, json, numpy as np, pandas as pd
sys.path.insert(0,'/root/pe-fin'); sys.path.insert(0,'/root/pe-fin/team')
from mech2 import ret, move, st
def m7(sym,thr=0.015):
    m=move(sym,0,330); return ret(sym,330,390,lambda d: abs(m.get(d,0))>=thr, lambda d: int(np.sign(m[d])))
DOC={'M7S':'Last-hour momentum on SPY: 09:30->15:00 move >=1.5% -> WITH it 15:00->close (M7 door 3).',
     'M7I':'Last-hour momentum on IWM: same rule (M7 door 3).',
     'M7P':'Last-hour momentum POOLED QQQ+SPY+IWM (each day-instrument a trade; clustered by day).'}
if __name__=='__main__':
    a=sys.argv[1] if len(sys.argv)>1 else 'list'
    if a=='list': [print(k,'—',v) for k,v in DOC.items()]; sys.exit(0)
    if a=='M7P':
        s=pd.concat([m7('QQQ'),m7('SPY'),m7('IWM')]); s=s.groupby(level=0).mean()   # one number per day = clustered by day
    else: s=m7({'M7S':'SPY','M7I':'IWM'}[a])
    R=st(s); g=np.random.default_rng(31); C=st(s*g.choice([-1,1],len(s)))   # control: random sign
    print(a,DOC[a]); print('real',R); print('control',C)
    print("RESULT "+json.dumps(dict(name=f"{a} {DOC[a][:70]}",n=R['n'],mean_bps=f"{R['mean']:+.2f} bps/trade",t=round(R['t'],2),is_mean=R['is_mean'],is_t=round(R['is_t'],2),oos_mean=R['oos_mean'],oos_t=round(R['oos_t'],2),control_t=round(C['t'],2))))
PY
python3 -m py_compile fomc_dates.py mech_events.py mech_m7door3.py || exit 1
python3 fomc_dates.py || exit 1
[ $(wc -l < /root/pe-data/events/fomc.csv) -gt 200 ] || { echo "FOMC calendar too short — not registering event tests"; exit 1; }
python3 - <<'PY'
import json, subprocess; reg=json.load(open('hypotheses.json')); have={h['id'] for h in reg['hypotheses']}; n=0
for script,ids in (('mech_events.py',['E1s','E1q','E1t','E1g']),('mech_m7door3.py',['M7S','M7I','M7P'])):
    docs={l.split(' — ',1)[0]:l.split(' — ',1)[1] for l in subprocess.run(['python3','-I',script,'list'],capture_output=True,text=True).stdout.splitlines() if ' — ' in l}
    for i in ids:
        if i in have: continue
        reg['hypotheses'].append({"id":i,"script":f"/root/pe-fin/team/{script}","args":[i],"status":"proposed","pre_registered_sign":docs.get(i,'+'),
            "next_door":"E1: post-statement 14:00-16:00 continuation; M7: none (door 3 was the last)","timeout":1800}); n+=1
json.dump(reg,open('hypotheses.json','w'),indent=1); print('registered',n)
PY
