#!/bin/bash
set -o pipefail
# 499_second_leg_check (Finder 2026-11-06, queue item 317, from jobs/499_rest_gap.sh): what item 310's first-leg LOSER back is made of, and its one unseen read, Soccer 2023-12 as loaded. Audit tables are context, not scored. Margin comes from the first leg's official CORRECT_SCORE winner, wider than goal_timeline, which the rule named. Read only. Prints only.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,re,time,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
from lib_official import bk,ly,fill,last_in,secs,checks,group,load_results
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',240); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
DAY=86400.0
def first_leg(games,t):
    best=None
    for x,m,e in games:
        if 3*DAY<=t-x<=21*DAY: best=(x,m,e)
    return best
def cs_margin(sel):
    """'2 - 1' gives 1. Any other or unreadable gives None."""
    m=re.fullmatch(r"\s*(\d+)\s*-\s*(\d+)\s*",str(sel))
    return None if not m else abs(int(m[1])-int(m[2]))
def pband(p): return '<2' if p<2 else '2-3' if p<3 else '3-5' if p<5 else '5+'
G=[(0.,'a','x'),(10*DAY,'b','y')]
assert first_leg(G,13*DAY)[1]=='b' and first_leg(G,12*DAY)[1]=='a' and first_leg(G,40*DAY) is None
assert cs_margin('2 - 1')==1 and cs_margin('0 - 3')==3 and cs_margin('1 - 1')==0 and cs_margin('Any Other Home Win') is None
assert pband(1.99)=='<2' and pband(2.0)=='2-3' and pband(3.0)=='3-5' and pband(5.0)=='5+'
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
RS,_=load_results(con,['MATCH_ODDS']); CS,_=load_results(con,['CORRECT_SCORE']); print("official MO",len(RS),"CS",len(CS),f"{time.time()-T0:.0f}s",flush=True)
cur.execute("SELECT DISTINCT market_id,event_name,extract(epoch from market_time)::float8,country FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_time>='2023-12-01' AND market_time<'2026-10-01'")
SC=[(m,e,float(t),c) for m,e,t,c in cur.fetchall() if ' v ' in e and group(e) is None]
cur.execute("SELECT DISTINCT market_id,event_name,extract(epoch from market_time)::float8 FROM bf_hist_other WHERE sport='Soccer' AND market_type='CORRECT_SCORE' AND market_time>='2023-12-01' AND market_time<'2026-10-01'")
CSID={}
for m,e,t in cur.fetchall():
    if m in CS: CSID[(e,float(t))]=m
FX=defaultdict(list)
for m,e,t,c in SC:
    h,a=e.split(' v ',1); FX[(h,a)].append((t,m,e))
for k in FX: FX[k].sort()
L=[]; C=Counter()
for m,e,t,c in SC:
    if m not in RS: continue
    h,a=e.split(' v ',1); f=first_leg(FX.get((a,h),[]),t)
    if f is None or f[1] not in RS: continue
    r=RS[f[1]]; w=[s for s,x in r.items() if x][0]
    if w not in (h,a): C['first leg not a team win']+=1; continue
    loser=a if w==h else h; cm=CSID.get((f[2],f[0])); mg=None
    if cm:
        ws=[s for s,x in CS[cm].items() if x]
        mg=cs_margin(ws[0]) if ws else None
    L.append(dict(mid=m,ev=e,off=t,loser=loser,days=(t-f[0])/DAY,margin=mg,country=c,loser_home=loser==h))
print("second-leg markets with a first-leg team win, official",len(L),dict(C),f"{time.time()-T0:.0f}s",flush=True)
L_=pd.DataFrame(L); ids=L_.mid.tolist(); rows=[]
for i in range(0,len(ids),500):
    X=pd.read_sql("SELECT market_id,sel,ts,market_time mt,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_id=ANY(%s) AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '20 minutes' AND ts<=market_time+interval '6 minutes'",con,params=(ids[i:i+500],))
    if X.empty: continue
    X['tt']=secs(X.ts); X['o']=secs(X.mt); X=X.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt'])
    for mk,g in X.groupby('market_id',sort=False): rows.append((mk,g))
print("markets with prints",len(rows),f"{time.time()-T0:.0f}s",flush=True)
ix=L_.set_index('mid').to_dict('index'); T=[]
for mk,g in rows:
    I=ix[mk]; s=g[g.sel==I['loser']]; off=float(g.o.iloc[0])
    if s.empty: C['loser no prints']+=1; continue
    a,b=s.tt.values,s.ltp.values; i=last_in(a,off-300,off-120)
    if i is None: C['no entry print']+=1; continue
    won=bool(RS[mk].get(I['loser'],False)); Bp=fill(a,b,i,'B')
    if Bp>50: continue
    v=bk(Bp,won)
    if v is None: continue
    T.append(dict(ev=I['ev'],off=off,v=float(v),won=won,px=Bp,days=I['days'],margin=I['margin'],country=I['country'],lh=I['loser_home']))
R=pd.DataFrame(T); R['when']=pd.to_datetime(R.off,unit='s')
print("counts",dict(C),"trades",len(R),flush=True)
print("sample names",R.sort_values('off').ev.iloc[::max(1,len(R)//25)].tolist(),flush=True)
A=R[R.when>='2024-01-01']; D=R[R.when<'2024-01-01']
def tb(x,lab):
    if len(x)<2: return dict(cut=lab,n=len(x))
    m=x.off.median(); l=line(x.v.values,np.where(x.off<=m,1,2)); return dict(cut=lab,n=l['n'],per10=round(l['per10'],3),t=round(l['t'],2),h1=round(l['h1'],3),h2=round(l['h2'],3),won=round(x.won.mean(),3),implied=round((1/x.px).mean(),3),no_top=round(np.delete(x.v.values,x.v.values.argmax()).mean(),3))
o=[tb(A,'item 310 games, ALL: should read n 175 +2.960 t 1.93')]
for lab,m_ in (('days 3-7',A.days<=7),('days 8-21',A.days>7),('loser home',A.lh),('loser away',~A.lh),('margin 1',A.margin==1),('margin 2+',A.margin>=2),('margin unknown',A.margin.isna())): o.append(tb(A[m_],lab))
for b,x in A.groupby(A.px.map(pband)): o.append(tb(x,'price '+b))
print("\n== AUDIT, context, not scored\n",pd.DataFrame(o).to_string(index=False),flush=True)
print("\n== by country, n >= 8\n",pd.DataFrame([tb(x,c) for c,x in A.groupby('country') if len(x)>=8]).sort_values('n',ascending=False).to_string(index=False),flush=True)
print("\n== UNSEEN, Soccer 2023-12 as loaded, LOSER back\n",pd.DataFrame([tb(D,'Dec 2023')]).to_string(index=False),flush=True)
# Name audit for 499_rest_gap's 'MO team not priced or name differs'
cur.execute("SELECT DISTINCT event_name,sel FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_time>='2024-09-01' AND market_time<'2024-09-08'")
E=defaultdict(set)
for e,s in cur.fetchall():
    if ' v ' in e: E[e].add(s)
bad=[e for e,s in E.items() if not set(e.split(' v ',1))<=s]
print("name audit, Sep 2024 first week: events",len(E),"event's two names not both runners",len(bad),bad[:6],flush=True)
con.close()
print("\n== SURVIVORS: audit and a small unseen read, none can pass here"); print(f"total {time.time()-T0:.0f}s")
PY
