#!/bin/bash
set -o pipefail
# 499_season_open (Finder 2026-11-07, queue items 427, 428, Finder's own, source c): a league's opening round, all sides, at Pinnacle and Betfair closes on fd_matches, then at real pre-off prints on bf_hist_other. Rule pushed in the queue before any price. Read only. No tables written. Prints only, so a pass is an upper bound.
# NOTE 2026-11-07: crashes at the top-five print, before the tape section. Y.div is the DataFrame method, not the column. Fix for the next run: Y['div'].isin(TOP). Item 427's 20 scored lines print before this line.
# 410 (watchman fix of 499_season_open): Y.div at the top-five print is the DataFrame method, not the column, so AttributeError at heredoc line 79 (file line 84) before any tape price. Y['div'] there, nothing else changed.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,datetime as dtm,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,tstat,passes,norm,loose,zscore,back_settle,lay_settle
from lib_official import bk,ly,fill,last_in,secs,checks,group,load_results
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',230); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
DAY=86400.0
def played(rows):
    """rows (id, date, home, away) of one div and season. {id: (home games before, away games before)}. A same-date game is not history."""
    seen=Counter(); out={}; by=defaultdict(list)
    for r in rows: by[r[1]].append(r)
    for d in sorted(by):
        for i,_,h,a in by[d]: out[i]=(seen[h],seen[a])
        for i,_,h,a in by[d]: seen[h]+=1; seen[a]+=1
    return out
def state(gh,ga):
    if gh==0 and ga==0: return 'G1'
    if 1<=gh<=2 and 1<=ga<=2: return 'G2_3'
    if gh>=10 and ga>=10: return 'CONTROL'
    return None
def num(x):
    try: v=float(x)
    except (TypeError,ValueError): return np.nan
    return v if v>1 else np.nan
def devig(ps):
    """Prices of one book. Each runner's share of the summed reciprocals."""
    r=[1/p for p in ps]; t=sum(r); return [x/t for x in r]
# known answers, worked by hand
P=played([(1,1,'A','B'),(2,1,'C','D'),(3,2,'A','C'),(4,3,'E','A'),(5,3,'B','D')])
assert P=={1:(0,0),2:(0,0),3:(1,1),4:(0,2),5:(1,1)}
assert state(0,0)=='G1' and state(0,2) is None and state(1,2)=='G2_3' and state(3,1) is None and state(10,12)=='CONTROL' and state(9,12) is None
assert num('2.5')==2.5 and num(None)!=num(None) and num('1.0')!=num('1.0') and num('x')!=num('x')
assert abs(devig([2.0,2.0])[0]-.5)<1e-9 and abs(sum(devig([1.9,3.5,4.2]))-1)<1e-9
# a back at 2.04 becomes 2.02: wins 10.2 less 2%; a lay at 2.0 becomes 2.02: stake 10/1.02, wins 9.6078, loses 10
assert abs(back_settle(step(2.04,-1),True)-9.996)<1e-9 and back_settle(step(2.04,-1),False)==-10
assert abs(lay_settle(step(2.0,1),False)-10/1.02*.98)<1e-9 and lay_settle(step(2.0,1),True)==-10
assert passes(300,150,150,3.5,.1,.1,.15) and not passes(299,150,149,9,1,1,1) and not passes(300,150,150,3.49,1,1,1) and not passes(300,150,150,9,1,-.01,1) and not passes(300,150,150,9,1,1,.14)
assert secs(pd.Series([pd.Timestamp('2024-01-01',tz='UTC')])).iloc[0]==1704067200
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
T0=time.time()
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
D=pd.read_sql("""SELECT div,season,date,home,away,fthg,ftag,psch::float8 psch,pscd::float8 pscd,psca::float8 psca,raw->>'PC>2.5' pco,raw->>'PC<2.5' pcu,raw->>'BFECH' bh,raw->>'BFECD' bd,raw->>'BFECA' ba,raw->>'BFEC>2.5' bo,raw->>'BFEC<2.5' bu
   FROM fd_matches WHERE fthg IS NOT NULL AND ftag IS NOT NULL AND season<'9000'""",con)
print("fd rows",len(D),f"{time.time()-T0:.0f}s",flush=True)
D=D.reset_index(drop=True); D['id']=D.index; D['st']=None; G={}
for k,g in D.groupby(['div','season']):
    G.update(played(list(zip(g.id,g.date,g.home,g.away))))
D['gh']=[G[i][0] for i in D.id]; D['ga']=[G[i][1] for i in D.id]; D['st']=[state(a,b) for a,b in zip(D.gh,D.ga)]
print("states by season, G1:",D[D.st=='G1'].groupby('season').size().to_dict(),flush=True)
D['tt']=secs(pd.to_datetime(D.date)); D['total']=D.fthg+D.ftag
WON=dict(Home=D.fthg>D.ftag,Draw=D.fthg==D.ftag,Away=D.fthg<D.ftag,Over=D.total>2.5,Under=D.total<2.5)
for c in ('pco','pcu','bh','bd','ba','bo','bu','psch','pscd','psca'): D[c]=D[c].map(num)
SRC={'PIN':dict(Home='psch',Draw='pscd',Away='psca',Over='pco',Under='pcu'),'BFEC':dict(Home='bh',Draw='bd',Away='ba',Over='bo',Under='bu')}
BOOK={'Home':('Home','Draw','Away'),'Draw':('Home','Draw','Away'),'Away':('Home','Draw','Away'),'Over':('Over','Under'),'Under':('Over','Under')}
def stats(v,tt,won=None,px=None):
    v=np.asarray(v,dtype=float); md=np.median(tt); h=np.asarray(tt)<md; a,b=v[h],v[~h]
    return dict(n=len(v),per10=v.mean(),t=tstat(v),n1=len(a),h1=a.mean() if len(a) else 0.,n2=len(b),h2=b.mean() if len(b) else 0.,maxwin=v.max(),no_top=np.delete(v,v.argmax()).mean())
out=[]; Y=D[D.st.notna()]
for src,mp in SRC.items():
    for r,c in mp.items():
        cols=[mp[x] for x in BOOK[r]]; z=Y.dropna(subset=cols)
        fair=[devig([getattr(q,x) for x in cols])[cols.index(c)] for q in z.itertuples()]; z=z.assign(fair=fair,won=WON[r].reindex(z.index))
        vb=[back_settle(step(p,-1),w) for p,w in zip(z[c],z.won)]; vl=[lay_settle(step(p,1),w) for p,w in zip(z[c],z.won)]
        z=z.assign(vb=vb,vl=vl)
        for st in ('G1','G2_3','CONTROL'):
            x=z[z.st==st]
            if len(x)<30: continue
            for sd,col in (('back','vb'),('lay','vl')):
                out.append(dict(src=src,st=st,r=r,side=sd,**stats(x[col].values,x.tt.values),won=x.won.mean(),fair=x.fair.mean(),pts=100*(x.won.mean()-x.fair.mean()),z=zscore(int(x.won.sum()),len(x),x.fair.mean())))
L=pd.DataFrame(out); C=L[L.st=='CONTROL'].set_index(['src','r','side']).per10
L['ctl']=[C.get((a,b,c),np.nan) for a,b,c in zip(L.src,L.r,L.side)]; L['excess']=L.per10-L.ctl
L['PASS']=[(s=='G1' and passes(n,a,b,t,h1,h2,m) and x>=.15) for s,n,a,b,t,h1,h2,m,x in zip(L.st,L.n,L.n1,L.n2,L.t,L.h1,L.h2,L.per10,L.excess)]
print("\n== ITEM 427 G1, scored, 20 lines, best t first"); print(L[L.st=='G1'].sort_values('t',ascending=False).drop(columns=['st']).round(3).to_string(index=False))
print("\n== G2_3, printed, not scored"); print(L[L.st=='G2_3'].sort_values('t',ascending=False).head(10).drop(columns=['st','PASS']).round(3).to_string(index=False))
print("\n== CONTROL, cannot pass"); print(L[L.st=='CONTROL'].drop(columns=['st','PASS','excess','ctl']).round(3).to_string(index=False))
TOP={'E0','SP1','I1','D1','F1'}; x=Y[(Y.st=='G1')&Y['div'].isin(TOP)]; o=[]
for r,c in SRC['PIN'].items():
    cols=[SRC['PIN'][q] for q in BOOK[r]]; z=x.dropna(subset=cols)
    if len(z)<30: continue
    w=WON[r].reindex(z.index); fr=np.mean([devig([getattr(q,y) for y in cols])[cols.index(c)] for q in z.itertuples()])
    o.append(dict(r=r,n=len(z),won=w.mean(),fair=fr,pts=100*(w.mean()-fr),z=zscore(int(w.sum()),len(z),fr)))
print("\n== top five divisions, G1, win rate v de-vigged Pinnacle close, not scored"); print(pd.DataFrame(o).round(3).to_string(index=False)); sys.stdout.flush()
# ITEM 428: real prints
WIN=[('2023-07-01','2023-09-15'),('2024-07-01','2024-09-15'),('2026-07-01','2026-09-15'),('2023-10-01','2023-11-01'),('2024-10-01','2024-11-01'),('2026-09-15','2026-10-01')]
TY=['MATCH_ODDS','OVER_UNDER_25']; Q=D[D.st.isin(['G1','CONTROL'])]
CAND=defaultdict(list)
for r in Q.itertuples(): CAND[r.date].append((norm(r.home),norm(r.away),r.st))
parts=[]
for lo,hi in WIN:
    X=pd.read_sql("SELECT market_id,event_name ev,market_type ty,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type=ANY(%s) AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '20 minutes' AND ts<=market_time AND market_time>=%s AND market_time<%s",con,params=(TY,lo,hi))
    X['off']=secs(X.mt); evs=X[['ev','off']].drop_duplicates(); keep={}
    for ev,o in zip(evs.ev,evs.off):
        if ' v ' not in ev or group(ev): continue
        h,a=ev.split(' v ',1); d=pd.Timestamp(o,unit='s',tz='UTC').date(); H,A=norm(h),norm(a)
        for dd in (d,d-dtm.timedelta(days=1)):
            s=loose(H,A,CAND.get(dd,[]))
            if s is not None: keep[(ev,o)]=s; break
    X['st']=[keep.get(z) for z in zip(X.ev,X.off)]; X=X[X.st.notna()]
    parts.append(X); print(lo,"prints kept",len(X),"events tied",len(keep),f"{time.time()-T0:.0f}s",flush=True)
Pz=pd.concat(parts,ignore_index=True); del parts
RS,dropped=load_results(con,TY); con.close(); print("markets with one winner",len(RS),"dropped",dropped,flush=True)
Pz['tt']=secs(Pz.ts); Pz=Pz.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt'])
c=Counter(); rows=[]; seen=set()
for m,g in Pz.groupby('market_id',sort=True):
    ev,ty,o,st=g.ev.iloc[0],g.ty.iloc[0],float(g.off.iloc[0]),g.st.iloc[0]
    if (ev,ty,o) in seen: c['second id']+=1; continue
    seen.add((ev,ty,o))
    if m not in RS: c['no official result '+ty]+=1; continue
    R=RS[m]; h,a=ev.split(' v ',1)
    for s,y in g.groupby('sel',sort=False):
        if s not in R: c['runner not in result']+=1; continue
        ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-1200,o-120)
        if i is None: c['no print']+=1; continue
        pb,pl=fill(ts,px,i,'B'),fill(ts,px,i,'L')
        if ty=='MATCH_ODDS': who='Draw' if s=='The Draw' else 'Home' if s==h else 'Away' if s==a else None
        else: who='Over' if s.startswith('Over') else 'Under' if s.startswith('Under') else None
        if who is None: c['name mismatch']+=1; continue
        rows.append((st,who,o,R[s],pb,pl,None if pb>50 else bk(pb,R[s]),None if pl>50 else ly(pl,R[s]),ev))
print("counted:",dict(sorted(c.items())),flush=True)
T=pd.DataFrame(rows,columns='st who off won pb pl vb vl ev'.split())
g1=T[T.st=='G1']; print("tape G1 games",g1.ev.nunique(),"by year",pd.to_datetime(g1.drop_duplicates('ev').off,unit='s').dt.year.value_counts().sort_index().to_dict(),"CONTROL games",T[T.st=='CONTROL'].ev.nunique(),flush=True)
print("tied sample:",g1.ev.drop_duplicates().sample(min(14,g1.ev.nunique()),random_state=7).tolist(),flush=True)
out=[]
for st in ('G1','CONTROL'):
    for r in ('Home','Draw','Away','Over','Under'):
        for sd,col,pc in (('back','vb','pb'),('lay','vl','pl')):
            z=T[(T.st==st)&(T.who==r)&T[col].notna()]
            if len(z)<30: out.append(dict(st=st,r=r,side=sd,n=len(z),PASS=False)); continue
            q=stats(z[col].astype(float).values,z.off.values)
            out.append(dict(st=st,r=r,side=sd,**q,won=z.won.astype(float).mean(),imp=(1/z[pc]).mean(),PASS=(st=='G1' and passes(q['n'],q['n1'],q['n2'],q['t'],q['h1'],q['h2'],q['per10']))))
K=pd.DataFrame(out)
print("\n== ITEM 428 G1, scored, 10 lines, real prints"); print(K[K.st=='G1'].sort_values('t',ascending=False).drop(columns='st').round(3).to_string(index=False))
print("\n== CONTROL, cannot pass"); print(K[K.st=='CONTROL'].drop(columns=['st','PASS']).round(3).to_string(index=False))
S1=L[L.PASS==True]; S2=K[K.PASS==True]
print(f"\n== SURVIVORS: closes {len(S1)} of 20 scored, tape {len(S2)} of 10 scored\n",S1.round(3).to_string(index=False) if len(S1) else "closes none","\n",S2.round(3).to_string(index=False) if len(S2) else "tape none"); print(f"total {time.time()-T0:.0f}s")
PY
