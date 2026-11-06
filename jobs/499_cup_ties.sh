#!/bin/bash
set -o pipefail
# 499_cup_ties (Finder 2026-11-06, queue item 284, Finder's own, source c; entry from jobs/499_reserve_sides.sh): games outside the league tables: ties between divisions, same-league cup games, other countries, summer friendlies. Rule pushed in the queue (8b1a00f) before any price. Read only. No tables written. Prints only, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,bisect,zlib,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
from lib_official import bk,ly,fill,last_in,secs,checks,group,load_results
import lib_cand; lib_cand._checks(); checks()
TIER={39:('ENG',1),40:('ENG',2),41:('ENG',3),42:('ENG',4),78:('GER',1),79:('GER',2),61:('FRA',1),62:('FRA',2),135:('ITA',1),136:('ITA',2),140:('ESP',1),141:('ESP',2)}
UEFA={2,3}; DAY=86400.0
def klass(lh,la,ts):
    """lh, la league ids, ts market time in secs. Returns the class of a game outside af_fixtures."""
    d=pd.Timestamp(ts,unit='s',tz='UTC'); md=(d.month,d.day)
    if (6,15)<=md<=(8,20): return 'SUMMER'
    if d.month in (6,7,8): return None
    if lh==la: return 'SAME'
    a,b=TIER.get(lh),TIER.get(la)
    if a and b and a[0]==b[0]: return 'DIVS'
    return 'OTHERS'
J=pd.Timestamp('2024-07-01',tz='UTC').timestamp(); O=pd.Timestamp('2024-10-01',tz='UTC').timestamp(); A=pd.Timestamp('2024-08-20',tz='UTC').timestamp(); A2=pd.Timestamp('2024-08-21',tz='UTC').timestamp(); JN=pd.Timestamp('2024-06-10',tz='UTC').timestamp()
assert klass(39,39,J)=='SUMMER' and klass(39,40,O)=='DIVS' and klass(39,39,O)=='SAME' and klass(39,78,O)=='OTHERS' and klass(135,71,O)=='OTHERS' and klass(39,40,A)=='SUMMER' and klass(39,40,A2) is None and klass(39,40,JN) is None
def nearest(lst,t,w=60*DAY):
    """lst sorted (secs,league). League of the game nearest t, within w, else None."""
    if not lst: return None
    i=bisect.bisect_left(lst,(t,-1)); best=None
    for j in (i-1,i):
        if 0<=j<len(lst) and (best is None or abs(lst[j][0]-t)<abs(best[0]-t)): best=lst[j]
    return best[1] if abs(best[0]-t)<=w else None
assert nearest([(0.,39),(100*DAY,40)],10*DAY)==39 and nearest([(0.,39),(100*DAY,40)],90*DAY)==40 and nearest([(0.,39)],61*DAY) is None and nearest([],0.) is None
assert secs(pd.Series([pd.Timestamp('2024-01-01',tz='UTC')])).iloc[0]==1704067200
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=pd.read_sql("SELECT fixture_id,league_id,kickoff,home,away FROM af_fixtures WHERE season>=2023",con); F['tt']=secs(F.kickoff)
M=pd.read_sql("SELECT DISTINCT ON (p.event_id) p.event_id,p.event_name,substr(m.understat_id,3)::bigint fixture_id FROM af_price_map m JOIN bf_hist_price p ON p.event_id=m.event_id AND p.mkt='MO' AND p.sel='HOME' AND p.minute=1",con)
print("mapped games",len(M),f"{time.time()-T0:.0f}s",flush=True)
import re
BADMAP=re.compile(r"U-?(1[5-9]|2[0-3])\b|\(W\)|\bWomen\b| II\b| B( v |$)| Reserves?( v |$)|^Jong | v Jong ")   # about 1% of af_price_map names a youth, women's or reserve game but points at a senior fixture, found 2026-11-06; first run tied such names to the wrong club
assert BADMAP.search("Dag and Red v Nottingham Forest U21") and BADMAP.search("Espanyol B v Hull") and not BADMAP.search("Hull v Leeds")
fx=F.set_index('fixture_id'); NM={}; clash=Counter()
for r in M.itertuples():
    if r.fixture_id not in fx.index or ' v ' not in r.event_name or BADMAP.search(r.event_name): continue
    h,a=r.event_name.split(' v ',1); f=fx.loc[r.fixture_id]
    for bf,af in ((h,f.home),(a,f.away)):
        if bf in NM and NM[bf]!=af: clash[bf]+=1
        NM[bf]=af
print("BF names tied",len(NM),"names with two af names",len(clash),flush=True)
HIST=defaultdict(list); PAIR=defaultdict(list)
for r in F.itertuples():
    if r.league_id not in UEFA:
        HIST[r.home].append((r.tt,r.league_id)); HIST[r.away].append((r.tt,r.league_id))
    PAIR[frozenset((r.home,r.away))].append(r.tt)
for k in HIST: HIST[k].sort()
TY=['MATCH_ODDS','OVER_UNDER_25']; parts=[]
for lo,hi in (('2024-01-01','2024-04-01'),('2024-04-01','2024-07-01'),('2024-07-01','2024-10-01'),('2024-10-01','2024-12-01'),('2026-05-01','2026-08-01'),('2026-08-01','2026-09-01'),('2026-09-01','2026-11-01')):
    X=pd.read_sql("SELECT market_id,event_name ev,market_type ty,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type=ANY(%s) AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '20 minutes' AND ts<=market_time AND market_time>=%s AND market_time<%s",con,params=(TY,lo,hi))
    # keep only events whose two sides are both tied to an af name
    sp=X.ev.str.split(' v ',n=1,expand=True)
    if sp.shape[1]==2: X=X[sp[0].isin(NM)&sp[1].isin(NM)]
    parts.append(X); print(lo,"prints kept",len(X),f"{time.time()-T0:.0f}s",flush=True)
P=pd.concat(parts,ignore_index=True); del parts
RS,dropped=load_results(con,TY); con.close(); print("markets with one winner",len(RS),"dropped, not one winner",dropped,flush=True)
P['tt']=secs(P.ts); P['off']=secs(P.mt); P=P.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt'])
C=Counter(); rows=[]; seen=set(); rng=np.random.default_rng(7)
for m,g in P.groupby('market_id',sort=True):
    ev,ty=g.ev.iloc[0],g.ty.iloc[0]; o=float(g.off.iloc[0])
    if (ev,ty,o) in seen: C['second id']+=1; continue
    seen.add((ev,ty,o))
    if group(ev): C['women or youth']+=1; continue
    h,a=ev.split(' v ',1); ah,aa=NM[h],NM[a]
    lg=any(abs(t-o)<=2*DAY for t in PAIR.get(frozenset((ah,aa)),[]))
    lh,la=nearest(HIST[ah],o),nearest(HIST[aa],o)
    if not lg and (lh is None or la is None): C['league not known within 60 days']+=1; continue
    if lg: k='LEAGUE' if zlib.crc32(ev.encode())%10==0 else None
    else: k=klass(lh,la,o)
    if k is None: C['league sample out' if lg else 'Jun to Aug out of class']+=1; continue
    if m not in RS: C['no official result, '+ty]+=1; continue
    R=RS[m]; tl,tr=(TIER.get(lh,(None,0))[1],TIER.get(la,(None,0))[1]) if k=='DIVS' else (0,0)
    for s,y in g.groupby('sel',sort=False):
        if s not in R: C['runner not in result']+=1; continue
        ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-1200,o-120)
        if i is None: C['no print']+=1; continue
        pb,pl=fill(ts,px,i,'B'),fill(ts,px,i,'L')
        if ty=='MATCH_ODDS':
            who='DRAW' if s=='The Draw' else 'H' if s==h else 'A' if s==a else None
            if who is None: C['MO name mismatch']+=1; continue
        else: who='OVER' if s.startswith('Over') else 'UNDER'
        rows.append((k,ty,who,o,tl,tr,R[s],pb,pl,None if pb>50 else bk(pb,R[s]),None if pl>50 else ly(pl,R[s]),ev))
print("counted:",dict(sorted(C.items())),flush=True)
D=pd.DataFrame(rows,columns='k ty who off tl tr won pb pl vb vl ev'.split()); print("trades",D.groupby(['k','ty']).size().to_dict(),flush=True)
print("games by class, MO:",D[D.ty=='MATCH_ODDS'].groupby('k').ev.nunique().to_dict(),flush=True)
print("DIVS sample:",D[D.k=='DIVS'].ev.drop_duplicates().head(12).tolist(),flush=True); print("SAME sample:",D[D.k=='SAME'].ev.drop_duplicates().head(8).tolist(),flush=True); print("SUMMER sample:",D[D.k=='SUMMER'].ev.drop_duplicates().head(12).tolist(),flush=True)
# halves by date over the scored games, not the control
md=float(np.median(D[D.k!='LEAGUE'].off)); print("halves split at",pd.Timestamp(md,unit='s',tz='UTC'),flush=True); out=[]
def add(nm,x):
    for sd,c,pc in (('back','vb','pb'),('lay','vl','pl')):
        z=x[x[c].notna()]
        if len(z)<30: out.append(dict(line=nm+' '+sd,n=len(z),PASS=False)); continue
        l=line(z[c].astype(float).values,np.where(z.off<md,1,2)); out.append(dict(line=nm+' '+sd,n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],maxwin=l['maxwin'],won=z.won.astype(float).mean(),imp=(1/z[pc]).mean(),PASS=l['PASS']))
MO=D[D.ty=='MATCH_ODDS']; DV=MO[MO.k=='DIVS'].copy(); DV=DV[DV.tl!=DV.tr]
DV['low_home']=DV.tl>DV.tr; DV['gap']=(DV.tl-DV.tr).abs()
DV['role']=np.where(DV.who=='DRAW','DRAW',np.where((DV.who=='H')==DV.low_home,'LOWER','HIGHER'))
for nm,x in (('DIVS',DV),('DIVS gap2+',DV[DV.gap>=2]),('DIVS lower at home',DV[DV.low_home])):
    for r_ in ('LOWER','HIGHER','DRAW'): add(f"{nm} {r_}",x[x.role==r_])
for k in ('SAME','SUMMER','OTHERS','LEAGUE'):
    for w,nm in (('H','HOME'),('DRAW','DRAW'),('A','AWAY')): add(f"{k} {nm}",MO[(MO.k==k)&(MO.who==w)])
for k in ('DIVS','SAME','SUMMER','OTHERS','LEAGUE'):
    for w in ('OVER','UNDER'): add(f"{k} {w}",D[(D.k==k)&(D.ty=='OVER_UNDER_25')&(D.who==w)])
L=pd.DataFrame(out); print(f"\nlines {len(L)}, passing {int(L.PASS.sum())}")
print(L.sort_values('t',ascending=False).head(20).round(3).to_string(index=False))
print("\nCONTROL, league games sample"); print(L[L.line.str.startswith('LEAGUE')].round(3).to_string(index=False))
S=L[(L.PASS==True)&~L.line.str.startswith('LEAGUE')]
print(f"\n== SURVIVORS: {len(S)} of {int((~L.line.str.startswith('LEAGUE')).sum())} scored\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
