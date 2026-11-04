#!/bin/bash
set -o pipefail
# 499_tired_side (Finder 2026-11-04, queue item 78, Finder's own, source a; from jobs/499_rest_gap.sh): is the tired side underpriced on seasons that did not suggest it? Rule fixed in the queue before these seasons were read.
# REST as jobs/499_rest_gap.sh, from every finished fixture in af_fixtures, season >= 2016. Gap >= 3 and >= 4, tired side <= 4 days. BACK the tired side at close -1 tick (BFEC, else Pinnacle, else Bet365), £10, 2%, hold to FT, one bet per game. LAY the tired side at close +1 tick is shown as the other side of it, not a separate claim.
# BAR on 2017-18 to 2023-24 only, halves to 2020-21 v after. 2024-25, 2025-26 suggested the idea or sit inside its source, shown only. 2026-27 alone. Close is a proxy, so a pass is an upper bound.
# JOIN fd game to af fixture: date within 1 day, loose names, score must agree. Gate: at least 80% of fd games in the mapped divisions matched, by season, or that season is not counted.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks()
pd.set_option('display.width',240); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',30)
T0=time.time()
def num(x):
    try: v=float(x)
    except (TypeError,ValueError): return np.nan
    return v if 1<v<=1000 else np.nan
def rests(fx):
    """As jobs/499_rest_gap.sh: days since the previous kick-off, None if none or over 14 days; the same kick-off is not history."""
    last={}; out={}; fx=sorted(fx,key=lambda z:z[1]); i=0
    while i<len(fx):
        j=i
        while j<len(fx) and fx[j][1]==fx[i][1]: j+=1
        for f,k,h,a in fx[i:j]:
            r=[(k-last[t])/86400 if t in last else None for t in (h,a)]
            out[f]=tuple(None if (v is None or v>14) else v for v in r)
        for f,k,h,a in fx[i:j]: last[h]=k; last[a]=k
        i=j
    return out
def tired(rh,ra,gap,tired_max=4):
    if rh is None or ra is None: return None
    if rh-ra>=gap and ra<=tired_max: return 'A'
    if ra-rh>=gap and rh<=tired_max: return 'H'
    return None
def px(r):
    for src,k in (('BFEC','BFEC'),('PSC','PSC'),('B365C','B365C')):
        v=[num(r.get(k+s)) for s in 'HDA']
        if not np.isnan(v).any(): return dict(zip('HDA',v)),src
    return None,None
assert tired(7.,3.,3)=='A' and tired(3.,7.,3)=='H' and tired(7.,5.,2) is None and tired(None,3.,2) is None
D_=86400; _r=rests([(1,0,'A','B'),(2,3*D_,'A','C'),(3,6*D_,'A','B'),(4,30*D_,'A','B')]); assert _r[2]==(3.0,None) and _r[3]==(3.0,6.0) and _r[4]==(None,None)
assert px({'BFECH':'2','BFECD':'3','BFECA':'4','PSCH':'9','PSCD':'9','PSCA':'9'})[1]=='BFEC' and px({'BFECH':'','PSCH':'2','PSCD':'3','PSCA':'4'})[1]=='PSC' and px({})[0] is None
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='900s'")
F=pd.read_sql("SELECT fixture_id,kickoff,home,away,hg,ag,league,season FROM af_fixtures WHERE status='FT' AND kickoff IS NOT NULL AND season>=2016",con)
F['ko']=pd.to_datetime(F.kickoff,utc=True); F['ks']=F.ko.map(lambda t:int(t.timestamp())); F['day']=F.ko.dt.date
RS=rests(list(zip(F.fixture_id,F.ks,F.home,F.away))); print(f"fixtures {len(F)} {F.groupby('season').size().to_dict()}",flush=True)
by=defaultdict(list)
for x in F.itertuples(): by[x.day].append((norm(x.home),norm(x.away),(x.fixture_id,x.hg,x.ag)))
M=pd.read_sql("SELECT div,season,date,home,away,fthg,ftag,raw FROM fd_matches WHERE fthg IS NOT NULL AND season>='1718' AND season<'9000'",con); con.close()
M['dt']=pd.to_datetime(M.date); rows=[]; st=defaultdict(lambda:[0,0,0])
for g in M.itertuples():
    H,A=norm(g.home),norm(g.away); c=[]
    for d in (g.dt.date(),(g.dt+pd.Timedelta(days=1)).date(),(g.dt-pd.Timedelta(days=1)).date()): c+=by.get(d,[])
    p=loose(H,A,c); st[g.season][0]+=1
    if p is None: continue
    st[g.season][1]+=1
    if p[1]!=g.fthg or p[2]!=g.ftag: continue
    st[g.season][2]+=1; rh,ra=RS.get(p[0],(None,None)); pr,src=px(g.raw)
    if pr is None: continue
    res='H' if g.fthg>g.ftag else 'A' if g.ftag>g.fthg else 'D'
    for gap in (3,4):
        t=tired(rh,ra,gap)
        if t is None: continue
        a=step(pr[t],-1)
        if a>1.01: rows.append((gap,'BACK_TIRED',t,g.season,g.div,src,pr[t],res==t,back_settle(a,res==t)))
        rows.append((gap,'LAY_TIRED',t,g.season,g.div,src,pr[t],res==t,lay_settle(step(pr[t],1),res==t)))
G=pd.DataFrame([dict(season=k,fd=v[0],name_match=v[1],score_ok=v[2],rate=v[2]/v[0]) for k,v in sorted(st.items())]); print("\n== join by season (all fd divisions, some are not on af, so the mapped rate is below)"); print(G.round(3).to_string(index=False))
R=pd.DataFrame(rows,columns=['gap','line','tired','season','div','src','x','won','v']); print(f"trades {len(R)} {time.time()-T0:.0f}s",flush=True)
print("divisions in the signal, with n:",R[(R.gap==3)&(R.line=='BACK_TIRED')].groupby('div').size().sort_values(ascending=False).head(25).to_dict())
BAR={'1718','1819','1920','2021','2122','2223','2324'}; H1={'1718','1819','1920','2021'}; o=[]
for k,x in R.groupby(['gap','line']):
    a=x[x.season.isin(BAR)]; l=line(a.v.values,np.where(a.season.isin(H1),1,2)); d=dict(gap=k[0],line=k[1],n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=a.won.mean(),imp=(1/a.x).mean(),PASS=l['PASS'])
    for s in ('2425','2526','2627'):
        y=x[x.season==s]; d['n'+s]=len(y); d['p'+s]=y.v.mean() if len(y) else np.nan
    o.append(d)
O=pd.DataFrame(o); print("\n== bar seasons 2017-18 to 2023-24; later seasons shown"); print(O.round(3).to_string(index=False))
print("\n-- by tired side home or away, bar seasons"); a=R[R.season.isin(BAR)]; print(a.groupby(['gap','line','tired']).agg(n=('v','size'),per10=('v','mean'),won=('won','mean')).round(3).to_string())
print("\n-- by season, gap 4, back tired"); b=R[(R.gap==4)&(R.line=='BACK_TIRED')]; print(b.groupby('season').agg(n=('v','size'),per10=('v','mean'),won=('won','mean'),src=('src','first')).round(3).to_string())
print("\n== SURVIVORS (bar: n>=300, n>=150 per half, both halves > 0, t>=3.5, mean>=+0.15, proxy upper bound)"); S=O[O.PASS]; print(S.round(3).to_string(index=False) if len(S) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
