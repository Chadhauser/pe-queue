#!/bin/bash
set -o pipefail
# 499_dead_rubber_old (Finder 2026-11-05, queue item 91, Finder's own, from jobs/499_dead_rubber.sh): item 88's team lines have n 28-79 on the tape, far under the bar, so the same states are read on fd_matches seasons the tape never saw. Rule fixed before this job read a price: no new states, no new cuts.
# DATA fd_matches, seasons 2012-13 to 2023-24. Pinnacle closing prices (PSCH, PSCD, PSCA), or Pinnacle's earlier quote (PSH, PSD, PSA) where the close is missing. One tick adverse on the Betfair ladder, 2%, £10 risk, to result. Book 1.00-1.08.
# CANNOT PASS a bookmaker quote is not an exchange print, and lays at Pinnacle collect its margin (item 76: lay all +0.165 at Pinnacle v -0.072 at the exchange), so read each lay against the ALL control. Halves by date median.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time()
def classify(pts,R,table):
    t=sorted(table,reverse=True); n=len(t); p1,p6,pb=t[0],t[5],t[n-3]; s=set()
    if pts+3*R<pb: s.add('DOOMED'); return s
    if pts+3*R<p6 and pts>pb+3*R: s.add('DEAD')
    if abs(pts-pb)<=3: s.add('FIGHT')
    if p1-pts<=3: s.add('TITLE')
    return s
def build(fx):
    by=defaultdict(list)
    for r in fx: by[r[6]].append(r)
    out={}
    for lg,g in by.items():
        c=Counter()
        for r in g: c[r[2]]+=1; c[r[3]]+=1
        if len(c)<10: continue
        L=Counter(c.values()).most_common(1)[0][0]
        if L<20: continue
        g=sorted(g,key=lambda z:z[1]); pts=defaultdict(int); pl=defaultdict(int); i=0
        while i<len(g):
            j=i
            while j<len(g) and g[j][1]==g[i][1]: j+=1
            for f,k,h,a,hg,ag,_ in g[i:j]:
                Rh,Ra=L-pl[h],L-pl[a]
                if Rh<=0 or Ra<=0 or Rh>5 or Ra>5: continue
                tb=[pts[t] for t in c]
                out[f]=(classify(pts[h],Rh,tb),classify(pts[a],Ra,tb),max(Rh,Ra))
            for f,k,h,a,hg,ag,_ in g[i:j]:
                pl[h]+=1; pl[a]+=1
                if hg>ag: pts[h]+=3
                elif ag>hg: pts[a]+=3
                else: pts[h]+=1; pts[a]+=1
            i=j
    return out
def num(x):
    try: v=float(x)
    except (TypeError,ValueError): return np.nan
    return v if 1<v<=1000 else np.nan
def quote(r):
    """Pinnacle close, else Pinnacle earlier. All three must come from the same set."""
    for a,b,c in (('PSCH','PSCD','PSCA'),('PSH','PSD','PSA')):
        h,d,w=num(r.get(a)),num(r.get(b)),num(r.get(c))
        if h==h and d==d and w==w: return h,d,w
    return None
def bk(x,won):
    a=step(x,-1); return None if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)
# known answers, same hand-worked table as item 88
_tb=[80,75,70,65,62,60,58,55,52,50,48,46,44,42,40,38,35,30,28,20]
assert classify(45,3,_tb)=={'DEAD'} and classify(39,3,_tb)==set() and classify(32,3,_tb)=={'FIGHT'} and classify(20,3,_tb)=={'DOOMED'} and classify(78,3,_tb)=={'TITLE'} and classify(26,1,_tb)=={'DOOMED'}
assert quote({'PSCH':'2.0','PSCD':'3.5','PSCA':'4.0','PSH':'9','PSD':'9','PSA':'9'})==(2.0,3.5,4.0) and quote({'PSCH':'2.0','PSCD':None,'PSCA':'4.0','PSH':'2.1','PSD':'3.4','PSA':'3.9'})==(2.1,3.4,3.9) and quote({'PSH':'2.1'}) is None
assert abs(bk(2.04,True)-9.996)<1e-9 and ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True
R=pd.read_sql("SELECT div,season,date,home,away,fthg,ftag,raw FROM fd_matches WHERE fthg IS NOT NULL AND season IN ('1213','1314','1415','1516','1617','1718','1819','1920','2021','2122','2223','2324')",con); con.close()
R['id']=range(len(R)); R['ks']=pd.to_datetime(R.date).map(lambda t:int(t.timestamp())); R['lg']=R['div']+'|'+R.season
S=build(list(zip(R.id,R.ks,R.home,R.away,R.fthg,R.ftag,R.lg)))
Q=R[R.id.isin(S)]; med=Q.date.sort_values().iloc[len(Q)//2]; print(f"games {len(R)}, league keys {R.lg.nunique()}, last 5 rounds {len(Q)}, split {med}; states {Counter(x for v in S.values() for x in v[0]|v[1])}; {time.time()-T0:.0f}s",flush=True)
rows=[]; noq=0
for i,d,hg,ag,raw in zip(Q.id,Q.date,Q.fthg,Q.ftag,Q.raw):
    q=quote(raw)
    if q is None or not 1.0<=1/q[0]+1/q[1]+1/q[2]<=1.08: noq+=1; continue
    sh,sa,Rr=S[i]; hf=1 if d<=med else 2; res='H' if hg>ag else 'A' if ag>hg else 'D'
    def add(st,tg,sd,sel,p,won):
        v=bk(p,won) if sd=='BACK' else ly(p,won)
        if v is not None: rows.append((st,tg,sd,sel,hf,i,v))
    for tg in ['R5']+(['R2'] if Rr<=2 else []):
        for sd in ('BACK','LAY'):
            for sel,p,w in (('HOME',q[0],res=='H'),('DRAW',q[1],res=='D'),('AWAY',q[2],res=='A')):
                add('ALL',tg,sd,sel,p,w)
                if 'DEAD' in sh and 'DEAD' in sa: add('DEADvDEAD',tg,sd,sel,p,w)
            for me,op,sel,p,w in ((sh,sa,'team',q[0],res=='H'),(sa,sh,'team',q[2],res=='A')):
                for st,cond in (('FIGHTvDEAD','FIGHT' in me and 'DEAD' in op),('TITLEvDEAD','TITLE' in me and 'DEAD' in op),('DOOMEDvLIVE','DOOMED' in me and 'DEAD' not in op and 'DOOMED' not in op)):
                    if cond: add(st,tg,sd,sel,p,w)
print(f"no usable quote {noq}",flush=True)
T=pd.DataFrame(rows,columns=['state','R','side','sel','h','g','v']); o=[]
for k,x in T.groupby(['state','R','side','sel']):
    d=line(x.v.values,x.h.values); o.append(dict(zip(['state','R','side','sel'],k))|dict(n=d['n'],games=x.g.nunique(),per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3)))
print(pd.DataFrame(o).sort_values(['state','R','side','sel']).to_string(index=False))
print("\nSURVIVORS: none can pass, a Pinnacle quote is not an exchange print"); print(f"done {time.time()-T0:.0f}s")
PY
