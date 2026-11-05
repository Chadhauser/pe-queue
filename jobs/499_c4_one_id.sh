#!/bin/bash
set -o pipefail
# 499_c4_one_id (Finder 2026-11-05, queue item 155; check, rule unchanged from the C4 tape section of jobs/499_cand_c3c4c5.sh): item 151 said that section loses games held under two MO ids. Read only.
# But that section already keeps one candidate per normalised name pair before lib_cand.loose (its lines 92-95), so the claim may be wrong. Read three ways on today's tape, same rule, same fills:
# AS_WRITTEN that code. TIE_LOST the same with the name filter removed, which is what item 151 described. ONE_ID lowest market id per event id, then the same name filter.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks()
pd.set_option('display.width',240); pd.set_option('display.max_rows',100); pd.set_option('display.max_columns',30)
T0=time.time(); E0=pd.Timestamp('1970-01-01',tz='UTC'); FIN=('FT','AET','PEN','Match Finished','FINISHED')
def ep(s): return (pd.to_datetime(s,utc=True)-E0).dt.total_seconds()
def signal_known(t,mn,h,a,sh,sa,lo,hi,known=120):
    st=None
    for i in range(len(t)):
        if (h[i],a[i])!=(sh,sa): st=None; continue
        if st is None: st=t[i]
        if t[i]-st>=known and mn[i]==mn[i] and lo<=mn[i]<=hi: return i
    return None
def pre_ok(p,pre): return pre is None or p<0.8*pre
def final(fid,AFD,st,mn,h,a):
    if fid in AFD: return AFD[fid]
    return (int(h),int(a)) if (str(st) in FIN or (mn==mn and mn>=88)) else None
def pick(cands,name_filter):
    """The candidates passed to loose. With the filter, the first of each normalised name pair."""
    if not name_filter: return list(cands)
    seen={}
    for c in cands: seen.setdefault((c[0],c[1]),c)
    return list(seen.values())
# known answers: the same as the job's, and two ids tie to None without the filter and match with it
assert signal_known([0,60,120,180],[70,76,77,78],[2,2,2,2],[2,2,2,2],2,2,75,89)==2 and signal_known([0,60],[76,77],[2,2],[2,2],2,2,75,89) is None
assert pre_ok(3.0,4.0) and not pre_ok(3.2,4.0) and pre_ok(8.0,None)
assert final(1,{1:(2,1)},'1H',10,0,0)==(2,1) and final(2,{},'2H',70,1,0) is None
_h,_a=norm('Leeds'),norm('Hull'); _c=[(_h,_a,'x'),(_h,_a,'y')]
assert loose(_h,_a,pick(_c,False)) is None and loose(_h,_a,pick(_c,True))=='x'
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
AF=pd.read_sql("SELECT fixture_id,hg,ag FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND season>=2026",con); AFD={f:(int(h),int(a)) for f,h,a in zip(AF.fixture_id,AF.hg,AF.ag)}
Fx=pd.read_sql("""SELECT DISTINCT fixture_id FROM goal_timeline WHERE captured_at>='2026-07-01' AND captured_at<'2026-10-02' AND score_home=2 AND score_away=2 AND minute::text ~ '^[0-9]+$' AND minute::int>=70""",con).fixture_id.tolist()
Gd=pd.read_sql("SELECT fixture_id,home_team,away_team,captured_at,minute,score_home h,score_away a,status FROM goal_timeline WHERE fixture_id=ANY(%s) AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at",con,params=(list(map(int,Fx)),))
Gd['t']=ep(Gd.captured_at); Gd['mn']=pd.to_numeric(Gd.minute,errors='coerce')
M0=pd.read_sql("SELECT DISTINCT market_id,event_id,event_name,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND sel='The Draw' AND market_time>='2026-07-01' AND market_time<'2026-10-02'",con); M0['mt']=ep(M0.market_time); M0=M0.sort_values('mt')
K1=set(M0.sort_values('market_id').drop_duplicates('event_id').market_id)
print(f"2-2 late fixtures {len(Fx)}, MO markets {len(M0)}, events {M0.event_id.nunique()}, name pairs at one time with 2+ ids {int(M0.groupby(['event_name','mt']).market_id.nunique().gt(1).sum())}, {time.time()-T0:.0f}s",flush=True)
GR=list(Gd.groupby('fixture_id',sort=False)); res={}; sigs={}
for mode,Mm,nf in (('AS_WRITTEN',M0,True),('TIE_LOST',M0,False),('ONE_ID',M0[M0.market_id.isin(K1)],True)):
    mts=Mm.mt.values; cand=[(norm(e.partition(' v ')[0]),norm(e.partition(' v ')[2]),m) for e,m in zip(Mm.event_name,Mm.market_id)]
    sig=[]; S={}
    for fid,g in GR:
        t=g.t.values; h=g.h.astype(int).values; a=g.a.astype(int).values; mn=g.mn.values; i=signal_known(t,mn,h,a,2,2,75,89)
        if i is None: S['no signal']=S.get('no signal',0)+1; continue
        f=final(fid,AFD,g.status.iloc[-1],mn[-1],h[-1],a[-1])
        if f is None: S['result unknown']=S.get('result unknown',0)+1; continue
        t1=t[0]-(mn[0]*60 if mn[0]==mn[0] else 0); x,y=np.searchsorted(mts,t1-1800),np.searchsorted(mts,t1+1800)
        m=loose(norm(g.home_team.iloc[0]),norm(g.away_team.iloc[0]),pick(cand[x:y],nf))
        if m is None: S['unmatched']=S.get('unmatched',0)+1; continue
        sig.append(dict(fid=fid,m=m,t0=t[i],mn=mn[i],draw=f[0]==f[1],gts=goal_times(list(t),list(h+a))))
    print(mode,"signals",len(sig),"skips",S,flush=True); sigs[mode]=sig
need=sorted({s['m'] for v in sigs.values() for s in v})
Dr=pd.read_sql("SELECT market_id,ts,ltp::float ltp FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND sel='The Draw' AND ltp>=1.01 AND ltp<1000 ORDER BY market_id,ts",con,params=(need,)); con.close(); Dr['t']=ep(Dr.ts); dg={k:g for k,g in Dr.groupby('market_id')}
out=[]
for mode,sig in sigs.items():
    e4=[]
    for s in sig:
        g=dg.get(s['m'])
        if g is None: continue
        ts=g.t.values; px=g.ltp.values; i=first_idx(ts,s['t0'],s['t0']+180)
        if i is None: continue
        p=float(px[i]); gl=[x for x in s['gts'] if x<=s['t0']]; last=gl[-1] if gl else None
        pre=None
        if last is not None:
            w=np.where((ts>=last-360)&(ts<=last-120))[0]; pre=float(px[w[-1]]) if len(w) else None
        later=[x for x in s['gts'] if x>s['t0']]; d=dict(fid=s['fid'],d=s['t0'],p=p,draw=s['draw'],age=(s['t0']-last)/60 if last else 99,pre=pre,pre_ok=pre_ok(p,pre),b=int(s['mn']//5*5))
        for k in (1,4):
            a=step(p,-k)
            if a<=1.01: d[f's{k}']=np.nan; d[f'g{k}']=np.nan; continue
            st=back_settle(a,s['draw']); d[f's{k}']=st; ex=st
            if later:
                j=first_idx(ts,max(later[0]+480,ts[i]+1))
                if j is not None: ex=back_hedge(a,px[j])
            d[f'g{k}']=ex
        e4.append(d)
    R=pd.DataFrame(e4); assert R.fid.is_unique; C=R[R.age>=20].groupby('b').p.median(); C=C.reindex(sorted(set(R.b)|set(C.index))).ffill(); R['ceil']=R.p<=1.25*R.b.map(C).fillna(np.inf); R['fresh']=R.ceil&R.pre_ok
    R['h']=np.where(R.d<=R.d.median(),1,2); res[mode]=R
    for nm,x in (('ALL',R),('FRESH',R[R.fresh])):
        for c in ('s1','g1','s4','g4'):
            y=x.dropna(subset=[c]); l=line(y[c].values,y.h.values); out.append(dict(mode=mode,line=f"C4 {nm} {c}",n=l['n'],games=y.fid.nunique(),per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],won=y.draw.mean(),imp=(1/y.p).mean(),PASS=l['PASS']))
O=pd.DataFrame(out); print("\n"+O.round(3).to_string(index=False))
A=res['AS_WRITTEN']
for mode in ('TIE_LOST','ONE_ID'):
    B=res[mode]; a,b=set(A.fid),set(B.fid); j=A.merge(B,on='fid',suffixes=('_a','_b')); print(f"\n{mode} v AS_WRITTEN: trades {len(b)} v {len(a)}; only in {mode} {len(b-a)}, only in AS_WRITTEN {len(a-b)}; shared {len(j)}, entry print differs on {int((j.p_a!=j.p_b).sum())}, s1 P&L differs on {int((j.s1_a.fillna(0)!=j.s1_b.fillna(0)).sum())}")
print("\nstated on 4 Nov (reports/finder_2026-11-04_items55c-58c.md): C4 FRESH s1 n 529 -0.389 t -1.09")
S=O[O.PASS&(O['mode']=='ONE_ID')]; print(f"\n== SURVIVORS: {len(S)}\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
