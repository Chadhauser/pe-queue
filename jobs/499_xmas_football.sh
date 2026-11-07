#!/bin/bash
set -o pipefail
# 499_xmas_football (Finder 2026-11-07, queue item 365, Finder's own, source c; entry and guards from jobs/499_clock_calendar.sh): the Christmas football programme, 26 Dec to 2 Jan, on the tape and at Pinnacle closes. Rule pushed in the queue before any price. Read only, no tables written. LTP only, so a pass is an upper bound.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,lay_settle,tstat,passes,line
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time()
def is_xmas(m,d): return (m==12 and d>=26) or (m==1 and d<=2)
def is_ctl(m,d): return m in (12,1,2) and not is_xmas(m,d)
def bk(x,won):
    a=step(x,-1); return None if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)
assert is_xmas(12,26) and is_xmas(1,2) and not is_xmas(12,25) and not is_xmas(1,3) and is_ctl(12,25) and is_ctl(1,3) and is_ctl(2,1) and not is_ctl(12,31) and not is_ctl(3,1)
assert abs(bk(2.04,True)-9.996)<1e-9 and bk(2.04,False)==-10.0 and ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9 and bk(1.01,True) is None
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.league,f.season,f.kickoff,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.kickoff IS NOT NULL AND f.season IN (2024,2025)""",con)
K=pd.to_datetime(G.kickoff,utc=True); G=G[[is_xmas(a,b) or is_ctl(a,b) for a,b in zip(K.dt.month,K.dt.day)]].reset_index(drop=True)
print(f"mapped Dec-Feb games {len(G):,}",flush=True)
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND coalesce(minute,0)<=2 GROUP BY 1",con,params=(list(map(int,G.fixture_id)),))
first_goal=dict(zip(EV.fixture_id,EV.gm)); parts=[]
for i in range(0,len(G),1000):
    P=pd.read_sql("SELECT event_id,mkt,sel,minute,m,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt IN ('MO','OU25') AND sel IN ('HOME','DRAW','AWAY','UNDER','OVER') AND minute>=0 AND minute<=2 AND ltp>=1.01 AND ltp<1000",con,params=(list(G.event_id.iloc[i:i+1000]),))
    parts.append(P.sort_values(['event_id','mkt','sel','minute','m']).drop_duplicates(['event_id','mkt','sel']))
F=pd.read_sql("SELECT div,season,date,fthg,ftag,psch::float h,pscd::float d,psca::float a,raw->>'PC>2.5' o,raw->>'PC<2.5' u FROM fd_matches WHERE psch IS NOT NULL AND fthg IS NOT NULL",con)
con.close()
P=pd.concat(parts,ignore_index=True).merge(G,on='event_id')
P['lag']=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True)).dt.total_seconds()/60
bad=(P.lag<-5)|(P.lag>20); gm=P.fixture_id.map(first_goal); kn=gm.notna()&(gm<P.minute)
print(f"games with a print {P.event_id.nunique():,}; rows dropped, lag {int(bad.sum())}, goal known before the print {int(kn.sum())}; {time.time()-T0:.0f}s",flush=True); P=P[~bad&~kn]
rows=[]
for (e,lg,s,ko,hg,ag),x in P.groupby(['event_id','league','season','kickoff','hg','ag']):
    k=pd.to_datetime(ko,utc=True); st='XMAS' if is_xmas(k.month,k.day) else 'REST'
    res='HOME' if hg>ag else 'AWAY' if ag>hg else 'DRAW'; over=hg+ag>2.5; d=dict(zip(x.sel,x.ltp))
    fav=(min(('HOME','AWAY'),key=lambda c:d[c]) if 'HOME' in d and 'AWAY' in d else None)
    for sel,px in d.items():
        if sel in('HOME','AWAY') and fav is None: continue
        lab={'DRAW':'DRAW','OVER':'OVER','UNDER':'UNDER'}.get(sel) or ('FAV' if sel==fav else 'DOG')
        won=(sel==res) if sel in('HOME','DRAW','AWAY') else (over if sel=='OVER' else not over)
        b=bk(px,won); l=ly(px,won); h=1 if s==2024 else 2
        if b is not None: rows.append((st,lab,'BACK',h,e,lg,b,won,1/px))
        rows.append((st,lab,'LAY',h,e,lg,l,won,1/px))
T=pd.DataFrame(rows,columns='st lab side h g lg v won imp'.split()); out=[]
print("Christmas games by season",T[(T.st=='XMAS')&(T.lab=='DRAW')&(T.side=='LAY')].groupby('h').g.nunique().to_dict(),"leagues",T[T.st=='XMAS'].lg.nunique(),flush=True)
for k,x in T.groupby(['st','lab','side']):
    l=line(x.v.values,x.h.values); out.append(dict(st=k[0],line=k[1],side=k[2],n=l['n'],games=x.g.nunique(),per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],maxwin=l['maxwin'],won=x.won.mean(),imp=x.imp.mean(),PASS=l['PASS']))
R=pd.DataFrame(out); A=R[R.st=='XMAS'].sort_values('t',ascending=False)
print(f"\n== item 365, tape, {len(A)} lines by t\n",A.drop(columns='st').round(3).to_string(index=False))
print("\n-- control, every other game of Dec-Feb\n",R[R.st=='REST'].drop(columns=['st','PASS']).sort_values('t',ascending=False).round(3).to_string(index=False))
# second read, Pinnacle closes, cannot pass alone
F['dt']=pd.to_datetime(F.date); F=F[F.dt.dt.year<2024]; F['x']=[is_xmas(a,b) for a,b in zip(F.dt.dt.month,F.dt.dt.day)]; F['c']=[is_ctl(a,b) for a,b in zip(F.dt.dt.month,F.dt.dt.day)]; F=F[F.x|F.c]
F['o']=pd.to_numeric(F.o,errors='coerce'); F['u']=pd.to_numeric(F.u,errors='coerce')
print(f"\nfd_matches Dec-Feb to 2023 with closes {len(F):,}, Christmas {int(F.x.sum()):,}, with O/U closes {int((F.x&F.o.notna()).sum()):,}; divs {F[F.x]['div'].nunique()}",flush=True)
rr=[]
for r in F.itertuples():
    res='H' if r.fthg>r.ftag else 'A' if r.ftag>r.fthg else 'D'; fav='H' if r.h<=r.a else 'A'; dog='A' if fav=='H' else 'H'; px={'H':r.h,'A':r.a,'D':r.d}
    pairs=[('FAV',px[fav],res==fav),('DOG',px[dog],res==dog),('DRAW',r.d,res=='D')]
    if r.o==r.o and r.u==r.u: pairs+=[('OVER',r.o,r.fthg+r.ftag>2.5),('UNDER',r.u,r.fthg+r.ftag<2.5)]
    for lab,p,w in pairs:
        if not p or p<=1.01: continue
        rr.append(('XMAS' if r.x else 'REST',lab,'BACK',r.dt,back_settle(float(p),w),w)); rr.append(('XMAS' if r.x else 'REST',lab,'LAY',r.dt,lay_settle(float(p),w),w))
Z=pd.DataFrame(rr,columns='st lab side dt v won'.split()); md=Z[Z.st=='XMAS'].dt.median(); oo=[]
for k,x in Z.groupby(['st','lab','side']):
    l=line(x.v.values,np.where(x.dt<md,1,2)); oo.append(dict(st=k[0],line=k[1],side=k[2],n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],won=x.won.mean()))
Q=pd.DataFrame(oo); print(f"halves split at {md}\n",Q.sort_values(['st','t'],ascending=[True,False]).round(3).to_string(index=False))
S=A[A.PASS]; print(f"\n== SURVIVORS: {len(S)} of {len(A)}\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
