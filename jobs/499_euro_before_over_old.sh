#!/bin/bash
set -o pipefail
# 499_euro_before_over_old (Finder 2026-11-06, queue item 193, Finder's own, source c, from jobs/499_euro_hangover.sh at 5 days): Over 2.5 when exactly one side has Europe within 5 days, at Pinnacle closes on seasons the tape test did not use. Rule and bar pushed before prices were read (commit 4549e1c). The number 499 is reused: 450-499 are all taken.
# JOIN fd_matches by date +/-1 day and team names (lib_cand.loose), unique or dropped, counted. PC>2.5 starts about 2019. PRICE close, exact, 2%, £10 risk. Not an exchange fill, cannot pass.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import back_settle,line,norm,loose
T0=time.time(); D=86400; UEFA=('UEFA Champions League','UEFA Europa League')
def states(rows,days=5):
    """As jobs/499_euro_hangover.sh. rows: (fixture,seconds,home,away,is_uefa)."""
    by={}
    for f,t,h,a,u in rows:
        by.setdefault(h,[]).append((t,f,u)); by.setdefault(a,[]).append((t,f,u))
    out={}
    for team,s in by.items():
        s.sort(key=lambda z:z[0])
        for i,(t,f,u) in enumerate(s):
            if u: continue
            st=set()
            if i>0 and s[i-1][2] and t-s[i-1][0]<=days*D: st.add('AFTER')
            if i+1<len(s) and s[i+1][2] and s[i+1][0]-t<=days*D: st.add('BEFORE')
            out[(f,team)]=st
    return out
def zsum(won,imp):
    won,imp=np.asarray(won,float),np.asarray(imp,float); v=(imp*(1-imp)).sum()
    return float((won.sum()-imp.sum())/v**0.5) if v>0 else 0.0
def zdiff(wa,ia,wb,ib):
    a,b=np.asarray(wa,float)-np.asarray(ia,float),np.asarray(wb,float)-np.asarray(ib,float)
    return float((a.mean()-b.mean())/(a.var(ddof=1)/len(a)+b.var(ddof=1)/len(b))**0.5)
# known answers, worked by hand
_s=states([(1,0,'A','B',False),(2,5*D,'A','Q',True),(3,11*D,'R','A',False)])
assert _s[(1,'A')]=={'BEFORE'} and _s[(1,'B')]==set() and _s[(3,'A')]==set()      # exactly 5 days counts; game 3 is 6 days after
assert abs(zsum([1,1,1,1],[.5]*4)-2.0)<1e-12 and abs(zdiff([1,0],[.5,.5],[1,0],[.5,.5]))<1e-12 and abs(back_settle(2.0,True)-9.8)<1e-9
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=pd.read_sql("SELECT fixture_id,kickoff,home,away,league,season FROM af_fixtures WHERE kickoff IS NOT NULL AND status IN ('FT','AET','PEN')",con)
F['ks']=pd.to_datetime(F.kickoff,utc=True).map(lambda t:int(t.timestamp())); F['u']=F.league.isin(UEFA)
ST=states(list(zip(F.fixture_id,F.ks,F.home,F.away,F.u))); UT={(int(s),t) for s,x in F[F.u].groupby('season') for t in set(x.home)|set(x.away)}
Fd=pd.read_sql("SELECT date,home,away,fthg,ftag,raw->>'PC>2.5' pco,raw->>'PC<2.5' pcu FROM fd_matches WHERE fthg IS NOT NULL AND ftag IS NOT NULL",con); con.close()
Fd['pco']=pd.to_numeric(Fd.pco,errors='coerce'); Fd['pcu']=pd.to_numeric(Fd.pcu,errors='coerce'); Fd=Fd[(Fd.pco>1)&(Fd.pcu>1)]
Fd['d']=pd.to_datetime(Fd.date).dt.date; ix=defaultdict(list)
for r in Fd.itertuples(): ix[r.d].append((norm(r.home),norm(r.away),r))
print(f"fd rows with PC closes {len(Fd)}, {Fd.d.min()}..{Fd.d.max()}",flush=True)
SK=Counter(); rows=[]
for r in F[(~F.u)&(F.season.between(2019,2023))].itertuples():
    sh=ST.get((r.fixture_id,r.home),set()); sa=ST.get((r.fixture_id,r.away),set())
    if ('BEFORE' in sh)!=('BEFORE' in sa): kind='STATE'
    elif not sh and not sa and ((int(r.season),r.home) in UT or (int(r.season),r.away) in UT): kind='CTRL'
    else: continue
    SK[kind]+=1; day=pd.Timestamp(r.kickoff).date(); c=[x for k in (-1,0,1) for x in ix.get(day+pd.Timedelta(days=k),[])]
    m=loose(norm(r.home),norm(r.away),c)
    if m is None: SK[kind+' no fd match']+=1; continue
    won=m.fthg+m.ftag>2.5; rows.append((kind,m.d,won,m.pco,(1/m.pco)/((1/m.pco)+(1/m.pcu)),back_settle(m.pco,won)))
print("counts",dict(sorted(SK.items())),flush=True)
R=pd.DataFrame(rows,columns='kind d won px imp back'.split()); S=R[R.kind=='STATE']; C=R[R.kind=='CTRL']; md=S.d.astype('datetime64[ns]').median()
for nm,x in (('STATE',S),('CTRL',C)):
    l=line(x.back.values,np.where(x.d.astype('datetime64[ns]')<md,1,2))
    print(f"{nm}: n {l['n']} back {l['per10']:+.3f} t {l['t']:.2f} h1 {l['h1']:+.3f} (n {l['n1']}) h2 {l['h2']:+.3f} (n {l['n2']}); won {x.won.mean():.3f} v de-vigged {x.imp.mean():.3f}, z {zsum(x.won,x.imp):.2f}; {x.d.min()}..{x.d.max()}")
l=line(S.back.values,np.where(S.d.astype('datetime64[ns]')<md,1,2)); zs=zsum(S.won,S.imp); zv=zdiff(S.won,S.imp,C.won,C.imp)
ok=l['h1']>0 and l['h2']>0 and zs>=2.5 and zv>=2.0
print(f"\n== SURVIVORS: not a fill, none can pass. Bar: back both periods > 0 ({l['h1']:+.3f}, {l['h2']:+.3f}), z >= 2.5 ({zs:.2f}), z v control >= 2.0 ({zv:.2f}): {'HOLDS' if ok else 'DOES NOT HOLD'}")
print(f"total {time.time()-T0:.0f}s")
PY
