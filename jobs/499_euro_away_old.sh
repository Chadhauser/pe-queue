#!/bin/bash
set -o pipefail
# 499_euro_away_old (Finder 2026-11-06, queue item 190, Finder's own, source c, from jobs/499_euro_hangover.sh): an away side fresh from an away UEFA trip, at Pinnacle closes on seasons the tape test did not use. Rule and bar pushed before prices were read (commit a311b2a). The number 499 is reused: 450-499 are all taken.
# STATE af_fixtures, every finished fixture for the sequence, seasons 2016 to 2023 scored: as item 188, home side not in that state. CONTROL away sides with a UEFA fixture that season, in neither state.
# JOIN fd_matches by date +/-1 day and team names (lib_cand.loose), unique or dropped, counted. fd holds 20 divisions, so states from other leagues are out.
# PRICE Pinnacle close, exact, 2%, £10 risk. Not an exchange fill, cannot pass. Bar: lay positive in both periods split at the median date, z <= -2.5 on won v de-vigged implied, z of state v control <= -2.0.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import back_settle,lay_settle,line,norm,loose
pd.set_option('display.width',200); pd.set_option('display.max_columns',30)
T0=time.time(); D=86400; UEFA=('UEFA Champions League','UEFA Europa League')
def states(rows,days=4):
    """As jobs/499_euro_hangover.sh. rows: (fixture,seconds,home,away,is_uefa)."""
    by={}
    for f,t,h,a,u in rows:
        by.setdefault(h,[]).append((t,f,u,True)); by.setdefault(a,[]).append((t,f,u,False))
    out={}
    for team,s in by.items():
        s.sort(key=lambda z:z[0])
        for i,(t,f,u,home) in enumerate(s):
            if u: continue
            st=set()
            if i>0 and s[i-1][2] and t-s[i-1][0]<=days*D:
                st.add('AFTER')
                if not s[i-1][3]: st.add('AFTER_AWAY')
            if i+1<len(s) and s[i+1][2] and s[i+1][0]-t<=days*D: st.add('BEFORE')
            out[(f,team)]=st
    return out
def devig(pa,pd_,ph): return (1/pa)/((1/pa)+(1/pd_)+(1/ph))
def zsum(won,imp):
    """z of total wins against the sum of independent implied probabilities."""
    won,imp=np.asarray(won,float),np.asarray(imp,float); v=(imp*(1-imp)).sum()
    return float((won.sum()-imp.sum())/v**0.5) if v>0 else 0.0
def zdiff(wa,ia,wb,ib):
    """z of mean(won-implied) in a less the same in b."""
    a,b=np.asarray(wa,float)-np.asarray(ia,float),np.asarray(wb,float)-np.asarray(ib,float)
    return float((a.mean()-b.mean())/(a.var(ddof=1)/len(a)+b.var(ddof=1)/len(b))**0.5)
# known answers, worked by hand
_y=[(1,0,'P','A',True),(2,3*D,'H','A',False),(3,7*D,'A','Q',True),(4,9*D,'R','A',False)]; _s=states(_y)
assert 'AFTER_AWAY' in _s[(2,'A')] and 'AFTER_AWAY' not in _s[(4,'A')] and 'AFTER' in _s[(4,'A')]      # game 3 was at home, two days before game 4
assert abs(devig(2.0,4.0,4.0)-0.5)<1e-12 and abs(zsum([1,0,1,0],[.5,.5,.5,.5]))<1e-12 and abs(zsum([1,1,1,1],[.5,.5,.5,.5])-2.0)<1e-12
assert abs(zdiff([1,0],[.5,.5],[1,0],[.5,.5]))<1e-12
assert abs(back_settle(3.0,True)-19.6)<1e-9 and lay_settle(3.0,True)==-10.0 and abs(lay_settle(3.0,False)-4.9)<1e-9
assert loose(norm('Wolverhampton Wanderers'),norm('Arsenal'),[(norm('Wolves'),norm('Arsenal'),1)]) is None and loose(norm('Paris Saint Germain'),norm('Lyon'),[(norm('Paris SG'),norm('Lyon'),7),(norm('Lens'),norm('Metz'),8)])==7
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=pd.read_sql("SELECT fixture_id,kickoff,home,away,league,season FROM af_fixtures WHERE kickoff IS NOT NULL AND status IN ('FT','AET','PEN')",con)
F['ks']=pd.to_datetime(F.kickoff,utc=True).map(lambda t:int(t.timestamp())); F['u']=F.league.isin(UEFA); R_=list(zip(F.fixture_id,F.ks,F.home,F.away,F.u))
for d in (4,5): print(f"team-game states at <= {d} days:",pd.Series([x for v in states(R_,d).values() for x in v]).value_counts().to_dict(),flush=True)
ST=states(R_); UT={(int(s),t) for s,x in F[F.u].groupby('season') for t in set(x.home)|set(x.away)}
Fd=pd.read_sql("SELECT date,home,away,fthg,ftag,psch::float psch,pscd::float pscd,psca::float psca FROM fd_matches WHERE fthg IS NOT NULL AND psch>1 AND pscd>1 AND psca>1",con); con.close()
Fd['d']=pd.to_datetime(Fd.date).dt.date; ix=defaultdict(list)
for r in Fd.itertuples(): ix[r.d].append((norm(r.home),norm(r.away),r))
SK=Counter(); rows=[]
for r in F[(~F.u)&(F.season.between(2016,2023))].itertuples():
    sh=ST.get((r.fixture_id,r.home),set()); sa=ST.get((r.fixture_id,r.away),set())
    if 'AFTER_AWAY' in sa and 'AFTER_AWAY' not in sh: kind='STATE'
    elif (int(r.season),r.away) in UT and not sa: kind='CTRL'
    else: continue
    SK[kind]+=1; day=pd.Timestamp(r.kickoff).date(); c=[x for k in (-1,0,1) for x in ix.get(day+pd.Timedelta(days=k),[])]
    m=loose(norm(r.home),norm(r.away),c)
    if m is None: SK[kind+' no fd match']+=1; continue
    won=m.fthg<m.ftag; rows.append((kind,m.d,won,m.psca,devig(m.psca,m.pscd,m.psch),lay_settle(m.psca,won),back_settle(m.psca,won)))
print("counts",dict(sorted(SK.items())),flush=True)
R=pd.DataFrame(rows,columns='kind d won px imp lay back'.split()); S=R[R.kind=='STATE']; C=R[R.kind=='CTRL']; md=S.d.astype('datetime64[ns]').median()
for nm,x in (('STATE',S),('CTRL',C)):
    h=np.where(x.d.astype('datetime64[ns]')<md,1,2); l=line(x.lay.values,h); b=line(x.back.values,h)
    print(f"{nm}: n {l['n']} lay {l['per10']:+.3f} t {l['t']:.2f} h1 {l['h1']:+.3f} (n {l['n1']}) h2 {l['h2']:+.3f} (n {l['n2']}); back {b['per10']:+.3f} t {b['t']:.2f}; won {x.won.mean():.3f} v de-vigged {x.imp.mean():.3f}, z {zsum(x.won,x.imp):.2f}; {x.d.min()}..{x.d.max()}")
zv=zdiff(S.won,S.imp,C.won,C.imp); h=np.where(S.d.astype('datetime64[ns]')<md,1,2); l=line(S.lay.values,h); zs=zsum(S.won,S.imp)
print(f"z state v control {zv:.2f}")
ok=l['h1']>0 and l['h2']>0 and zs<=-2.5 and zv<=-2.0
print(f"\n== SURVIVORS: not a fill, none can pass. Bar: lay both periods > 0 ({l['h1']:+.3f}, {l['h2']:+.3f}), z <= -2.5 ({zs:.2f}), z v control <= -2.0 ({zv:.2f}): {'HOLDS' if ok else 'DOES NOT HOLD'}")
print(f"total {time.time()-T0:.0f}s")
PY
