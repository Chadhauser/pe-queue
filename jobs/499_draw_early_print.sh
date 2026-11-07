#!/bin/bash
set -o pipefail
# 499_draw_early_print (Finder 2026-11-07, queue item 425, Finder's own, source c, from item 342's unexplained control): lay the Draw at its first in-play print within 5 minutes of kick-off, Allsvenskan, J1 League, Eliteserien. May to Oct 2023 chose this and is an audit; scored on later months. Rule pushed in the queue before this read. Read only, no tables written. LTP only, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_000_000_000,2_000_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,norm,loose
from lib_official import bk,ly,secs,group,checks
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',230); pd.set_option('display.max_rows',80); pd.set_option('display.max_columns',30)
T0=time.time()
THREE=('Allsvenskan','J1 League','Eliteserien')
WINS=(('2023-05-01','2023-11-01','CHOSE'),('2023-11-01','2024-11-01','UNSEEN'),('2026-05-01','2026-10-01','UNSEEN'))
def fill_lay(ts,px,ko):
    """(index, price): first print ko-300..ko+300, the higher of it and the next within 120 s. None if no print; never a fill forward."""
    i=np.where((ts>=ko-300)&(ts<=ko+300))[0]
    if not len(i): return None
    i=int(i[0]); p=float(px[i])
    if i+1<len(ts) and ts[i+1]-ts[i]<=120: p=max(p,float(px[i+1]))
    return i,p
def fill_back(ts,px,ko):
    i=np.where((ts>=ko-300)&(ts<=ko+300))[0]
    if not len(i): return None
    i=int(i[0]); p=float(px[i])
    if i+1<len(ts) and ts[i+1]-ts[i]<=120: p=min(p,float(px[i+1]))
    return i,p
# known answers, worked by hand
_t=np.array([100.,700.,760.,2000.]); _p=np.array([3.0,2.5,2.6,9.0])
assert fill_lay(_t,_p,1000.)==(1,2.6) and fill_back(_t,_p,1000.)==(1,2.5) and fill_lay(_t,_p,3000.) is None and fill_lay(np.array([800.,1000.]),np.array([2.0,3.0]),800.)==(0,2.0)
_l=ly(4.0,False); assert _l>0 and ly(4.0,True)==-10.0   # liability £10 loses all if the Draw wins
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=pd.read_sql("SELECT fixture_id,league_id,league,season,kickoff,home,away,hg,ag FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND ag IS NOT NULL AND kickoff>='2023-05-01' AND kickoff<'2026-10-01'",con)
F['k']=pd.to_datetime(F.kickoff,utc=True); F=F.sort_values('k').reset_index(drop=True); F['H']=F.home.map(norm); F['A']=F.away.map(norm); kt=F.k.dt.tz_convert(None).values.astype('datetime64[ns]')
print("af fixtures",len(F),"three leagues",int(F.league.isin(THREE).sum()),F[F.league.isin(THREE)].groupby('league').league_id.unique().to_dict(),flush=True)
FI=F.set_index('fixture_id'); rows=[]; C=Counter(); gr=[]
for lo,hi,era in WINS:
    MK=pd.read_sql("SELECT DISTINCT market_id,event_name,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_time>=%s AND market_time<%s",con,params=(lo,hi))
    MK=MK[[group(str(e)) is None for e in MK.event_name]].copy(); MK['mt']=pd.to_datetime(MK.market_time,utc=True); fx=[]
    for r in MK.itertuples():
        h,_x,a=str(r.event_name).partition(' v '); l=np.searchsorted(kt,np.datetime64((r.mt-pd.Timedelta(minutes=20)).tz_convert(None))); u=np.searchsorted(kt,np.datetime64((r.mt+pd.Timedelta(minutes=20)).tz_convert(None)),side='right')
        fx.append(loose(norm(h),norm(a),[(q.H,q.A,int(q.fixture_id)) for q in F.iloc[l:u].itertuples()]))
    MK['fx']=fx; MK=MK[MK.fx.notna()].copy(); MK['fx']=MK.fx.astype(int); MK=MK.drop_duplicates('fx',keep=False)
    ids=list(MK.market_id); PX={}
    for c in range(0,len(ids),500):
        P=pd.read_sql("SELECT market_id,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_id=ANY(%s) AND sel='The Draw' AND inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '30 minutes' AND ts<=market_time+interval '30 minutes'",con,params=(ids[c:c+500],))
        if len(P):
            P['tt']=secs(P.ts); P=P.sort_values(['market_id','tt'],kind='stable').drop_duplicates(['market_id','tt'])
            for m,x in P.groupby('market_id',sort=False): PX[m]=(x.tt.values,x.ltp.values)
    print(lo,era,"matched",len(MK),"tapes",len(PX),f"{time.time()-T0:.0f}s",flush=True)
    for r in MK.itertuples():
        f=FI.loc[r.fx]; ko=f.k.timestamp(); won=bool(f.hg==f.ag); three=f.league in THREE; t=PX.get(r.market_id)
        z=None if t is None else fill_lay(t[0],t[1],ko)
        gr.append((era,three,z is not None,won,ko,f.league))
        if z is None: C['no print within 5 minutes']+=1; continue
        i,L=z; _,B=fill_back(t[0],t[1],ko)
        if L>50: C['over 50']+=1; continue
        vb=bk(B,won)
        rows.append((era,three,ko,r.fx,f.league,ly(L,won),vb,won,1/float(t[1][i]),(t[0][i]-ko)/60))
con.close(); print("counts",dict(C),flush=True)
G=pd.DataFrame(gr,columns='era three near won off league'.split())
print("\nDraw share by whether the Draw printed within 5 min of kick-off (every matched game)")
print(G.groupby(['era','three','near']).won.agg(['size','mean']).round(3).to_string())
G['yr']=pd.to_datetime(G.off,unit='s',utc=True).dt.year
print("\nthree leagues by year"); print(G[G.three].groupby(['yr','near']).won.agg(['size','mean']).round(3).to_string())
T=pd.DataFrame(rows,columns='era three off g league vl vb won imp el'.split()); assert not T.duplicated(['era','g']).any()
o=[]
def rd(nm,x,col='vl',scored=False):
    x=x.dropna(subset=[col]); v=x[col].astype(float).values
    if len(v)<2: o.append(dict(line=nm,n=len(v))); return
    d=line(v,np.where(x.off.values<=np.median(x.off.values),1,2))
    o.append(dict(line=nm,n=d['n'],games=x.g.nunique(),per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],no_top=round(np.delete(v,v.argmax()).mean(),3),won=round(x.won.mean(),3),imp=round(x.imp.mean(),3),PASS=bool(d['PASS'] and scored)))
U=T[T.era=='UNSEEN']; Ch=T[T.era=='CHOSE']
rd('UNSEEN THREE lay *',U[U.three],scored=True)
rd('UNSEEN THREE back, mirror',U[U.three],'vb')
for l in THREE: rd(f'UNSEEN {l} lay',U[U.league==l])
rd('CHOSE THREE lay, audit',Ch[Ch.three]); rd('CONTROL UNSEEN other leagues lay',U[~U.three]); rd('CONTROL CHOSE other leagues lay',Ch[~Ch.three])
for y,x in U[U.three].groupby(pd.to_datetime(U[U.three].off,unit='s',utc=True).dt.year): rd(f'UNSEEN THREE lay {y}',x)
L=pd.DataFrame(o); print("\n== ITEM 425"); print(L.to_string(index=False))
print(f"\nfirst print, minutes from kick-off, median {T.el.median():.1f}")
S=L[L.PASS==True]; print("\n== SURVIVORS:",len(S)); print(S.to_string(index=False) if len(S) else "none",flush=True); print(f"total {time.time()-T0:.0f}s")
PY
