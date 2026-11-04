#!/bin/bash
set -o pipefail
# 499_cand_c3c4c5 (Finder 2026-11-04, queue item 58c). Selected on bf_hist_price seasons 2024-25, 2025-26.
# C3 BTTS No lay at the first print (job 491): (a) by league and season on the selection tape, reference, one entry per game; (b) UNTOUCHED: bf_hist_other BOTH_TEAMS_TO_SCORE, loader 347, all leagues the feed can name, KO and T15; print-exists bias reported; (c) real lay touch on liq_sample, in-play minute 0..2. One tick adverse, 2%, £10 liability, held to the score. x110 = excluding prints under 1.10, where a 1.01 lay wins £490 on £10.
# C4 back the draw at 2-2 late, item 37's FRESH rule: 2-2 known 2+ min, minute 75..89, one entry per game. UNTOUCHED: bf_hist_other MATCH_ODDS Jul-Sep 2026; clock is wall time from goal_timeline. Entry first print within 180 s. CEIL print <= 1.25 x the median of the same 5-minute band among entries whose last goal is 20+ min old; PRE print < 0.8 x the last print 2-6 min before the last goal, none = kept. k=1 and k=4 ticks (item 37: real back touch a median 3 ticks under LTP). Exit settle, and goal +8 at the first print. Then the real back touch on liq_sample.
# C5 lay BTTS Yes at 0-0 75'+, favourite 2-3, real lay touch only, liq_sample: LTP prints there are stale (item 19: LTP 5.6 v real lay 17), so no tape test is run. Favourite = shorter of HOME, AWAY at the earliest snapshot at minute <= 2.
# Result: af_fixtures FT if held, else the feed's last row if FT or minute>=88; unknown = excluded and counted.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks()
pd.set_option('display.width',240); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',30)
T0=time.time(); E0=pd.Timestamp('1970-01-01',tz='UTC'); FIN=('FT','AET','PEN','Match Finished','FINISHED')
def ep(s): return (pd.to_datetime(s,utc=True)-E0).dt.total_seconds()
def signal_known(t,mn,h,a,sh,sa,lo,hi,known=120):
    """Index of the first row with minute in lo..hi where the score has been sh-sa for at least `known` seconds, else None."""
    st=None
    for i in range(len(t)):
        if (h[i],a[i])!=(sh,sa): st=None; continue
        if st is None: st=t[i]
        if t[i]-st>=known and mn[i]==mn[i] and lo<=mn[i]<=hi: return i
    return None
def pre_ok(p,pre): return pre is None or p<0.8*pre
assert signal_known([0,60,120,180],[70,76,77,78],[2,2,2,2],[2,2,2,2],2,2,75,89)==2 and signal_known([0,60],[76,77],[2,2],[2,2],2,2,75,89) is None and signal_known([0,120,180],[76,77,78],[2,2,2],[1,2,2],2,2,75,89) is None
assert signal_known([0,120,240],[60,70,80],[0,0,0],[0,0,0],0,0,75,89)==2 and pre_ok(3.0,4.0) and not pre_ok(3.2,4.0) and pre_ok(8.0,None)
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
SV=[]
def final(fid,AFD,st,mn,h,a):
    """(hg,ag) from af if held, else the feed if finished, else None."""
    if fid in AFD: return AFD[fid]
    return (int(h),int(a)) if (str(st) in FIN or (mn==mn and mn>=88)) else None
assert final(1,{1:(2,1)},'1H',10,0,0)==(2,1) and final(2,{},'FT',float('nan'),1,1)==(1,1) and final(2,{},'2H',89,1,0)==(1,0) and final(2,{},'2H',70,1,0) is None
AF=pd.read_sql("SELECT fixture_id,hg,ag FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND season>=2026",con); AFD={f:(int(h),int(a)) for f,h,a in zip(AF.fixture_id,AF.hg,AF.ag)}
# ---- C3 a
G=pd.read_sql("SELECT m.event_id,f.league,f.season,f.kickoff,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL",con)
P=pd.read_sql("SELECT event_id,minute,m,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='BTTS' AND sel='NO' AND minute BETWEEN 0 AND 2 AND ltp>=1.01 AND ltp<1000",con,params=(list(G.event_id),))
P=P.sort_values(['event_id','minute','m']).drop_duplicates('event_id').merge(G,on='event_id'); P['lag']=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True)).dt.total_seconds()/60; P=P[(P.lag>=-5)&(P.lag<=20)]
P['won']=~((P.hg>0)&(P.ag>0)); P['v']=[lay_settle(step(p,1),w) for p,w in zip(P.ltp,P.won)]
print(f"\n== C3a selection tape reference: n {len(P)} mean {P.v.mean():+.3f} t {tstat(P.v):.2f} | excl <1.10 n {(P.ltp>=1.1).sum()} mean {P[P.ltp>=1.1].v.mean():+.3f} (job 491: n 5,891 +0.262)")
L_=P.groupby(['league','season']).v.agg(['size','mean']).unstack(); L_.columns=[f"{a}_{b}" for a,b in L_.columns]; L_['both_pos']=(L_['mean_2024']>0)&(L_['mean_2025']>0)
print(f"leagues {len(L_)}, positive both seasons {int(L_.both_pos.sum())}, top by mean:"); print(L_.sort_values('mean_2024',ascending=False).round(2).head(8).to_string())
# ---- C3 b
B=pd.read_sql("SELECT market_id,event_name,market_time,sel,ts,ltp::float ltp,inplay FROM bf_hist_other WHERE sport='Soccer' AND market_type='BOTH_TEAMS_TO_SCORE' AND ltp>=1.01 AND ltp<1000 ORDER BY market_id,sel,ts",con)
B['t']=ep(B.ts); B['mt']=ep(B.market_time); lo=pd.to_datetime(B.ts,utc=True).min()-pd.Timedelta(hours=3); hi=pd.to_datetime(B.ts,utc=True).max()+pd.Timedelta(hours=3)
Gf=pd.read_sql("""SELECT fixture_id,max(home_team) home,max(away_team) away,min(captured_at) first_t,min(captured_at) FILTER (WHERE score_home+score_away>=1) goal_t,(array_agg(score_home ORDER BY captured_at DESC))[1] h,(array_agg(score_away ORDER BY captured_at DESC))[1] a,(array_agg(status ORDER BY captured_at DESC))[1] st,(array_agg(minute ORDER BY captured_at DESC))[1] mn,(array_agg(minute ORDER BY captured_at))[1] mn0 FROM goal_timeline WHERE captured_at>=%s AND captured_at<=%s AND score_home IS NOT NULL AND score_away IS NOT NULL GROUP BY 1""",con,params=(lo,hi))
Gf['t1']=ep(Gf.first_t)-pd.to_numeric(Gf.mn0,errors='coerce').fillna(0)*60; Gf['gt']=ep(Gf.goal_t); Gf['mn']=pd.to_numeric(Gf.mn,errors='coerce')
meta=B.groupby('market_id',sort=False).agg(ev=('event_name','first'),mt=('mt','first')).reset_index().sort_values('mt'); mts=meta.mt.values; cand=[(norm(e.partition(' v ')[0]),norm(e.partition(' v ')[2]),m) for e,m in zip(meta.ev,meta.market_id)]
gr={k:g for k,g in B.groupby('market_id',sort=False)}; rows=[]; S={}; agree=[]; has=[]
for r in Gf.itertuples():
    a,b=np.searchsorted(mts,r.t1-1800),np.searchsorted(mts,r.t1+1800)
    if a==b: continue
    m=loose(norm(r.home),norm(r.away),cand[a:b])
    if m is None: S['unmatched']=S.get('unmatched',0)+1; continue
    f=final(r.fixture_id,AFD,r.st,r.mn,r.h,r.a)
    if f is None: S['result unknown']=S.get('result unknown',0)+1; continue
    won=not (f[0]>0 and f[1]>0); g=gr[m]; no=g[g.sel=='No']; ye=g[g.sel=='Yes']; has.append((len(no)>0,won))
    # gate reads either side: BTTS seems to stop printing once both have scored, so Yes alone may never reach 1.05. A check on the match only, never used to settle.
    if len(ye[ye.inplay]) and ye[ye.inplay].ltp.iloc[-1]<=1.05: agree.append(not won)
    if len(no[no.inplay]) and no[no.inplay].ltp.iloc[-1]<=1.05: agree.append(won)
    if not len(no): continue
    mt=no.mt.iloc[0]; pre=no[(~no.inplay)&(no.t>=mt-900)&(no.t<mt)]
    if len(pre): rows.append(dict(entry='T15',fid=r.fixture_id,d=mt,p=float(pre.ltp.iloc[0]),won=won))
    ip=no[no.inplay]
    if len(ip):
        t0=ip.t.iloc[0]
        if t0-mt<=1200 and not (r.gt==r.gt and r.gt<=t0): rows.append(dict(entry='KO',fid=r.fixture_id,d=mt,p=float(ip.ltp.iloc[0]),won=won))
        else: S['KO dropped']=S.get('KO dropped',0)+1
print(f"\n== C3b untouched BTTS No, bf_hist_other {pd.to_datetime(B.ts,utc=True).min()} .. {pd.to_datetime(B.ts,utc=True).max()}; markets {len(meta)}; skips {S}",flush=True)
ga=np.mean(agree) if agree else float('nan'); h_=pd.DataFrame(has,columns=['print','no_won']); print(f"GATE final print <= 1.05 on either side agrees on {ga:.3f} of {len(agree)} (bar 0.95); BTTS No rate by whether a No print exists: {h_.groupby('print').no_won.agg(['size','mean']).round(3).to_dict('index')}")
if ga>=0.95 and rows:
    R=pd.DataFrame(rows); R['v']=[lay_settle(step(p,1),w) for p,w in zip(R.p,R.won)]; R['v3']=[lay_settle(step(p,3),w) for p,w in zip(R.p,R.won)]; o=[]
    for en,x in R.groupby('entry'):
        h=np.where(x.d<=x.d.median(),1,2); o.append(dict(line=f"C3 lay BTTS No {en}",**line(x.v.values,h),x3=x.v3.mean(),x110=x[x.p>=1.1].v.mean(),no_won=x.won.mean(),implied=(1/x.p).mean()))
    T=pd.DataFrame(o); print(T.round(3).to_string(index=False)); SV.append(T[T.PASS])
else: print("GATE FAILED or no rows: not scored")
# ---- C4 tape
print(f"\n== C4 tape, {time.time()-T0:.0f}s",flush=True)
Fx=pd.read_sql("""SELECT DISTINCT fixture_id FROM goal_timeline WHERE captured_at>='2026-07-01' AND captured_at<'2026-10-02' AND score_home=2 AND score_away=2 AND minute::text ~ '^[0-9]+$' AND minute::int>=70""",con).fixture_id.tolist()
Gd=pd.read_sql("SELECT fixture_id,home_team,away_team,captured_at,minute,score_home h,score_away a,status FROM goal_timeline WHERE fixture_id=ANY(%s) AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at",con,params=(list(map(int,Fx)),))
Gd['t']=ep(Gd.captured_at); Gd['mn']=pd.to_numeric(Gd.minute,errors='coerce')
Mm=pd.read_sql("SELECT DISTINCT market_id,event_name,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND sel='The Draw' AND market_time>='2026-07-01' AND market_time<'2026-10-02'",con); Mm['mt']=ep(Mm.market_time); Mm=Mm.sort_values('mt'); print(f"2-2 late fixtures {len(Fx)}, MO markets {len(Mm)}, {time.time()-T0:.0f}s",flush=True)
mts=Mm.mt.values; cand=[(norm(e.partition(' v ')[0]),norm(e.partition(' v ')[2]),m) for e,m in zip(Mm.event_name,Mm.market_id)]
sig=[]; S={}
for fid,g in Gd.groupby('fixture_id',sort=False):
    t=g.t.values; h=g.h.astype(int).values; a=g.a.astype(int).values; mn=g.mn.values; i=signal_known(t,mn,h,a,2,2,75,89)
    if i is None: S['no signal']=S.get('no signal',0)+1; continue
    f=final(fid,AFD,g.status.iloc[-1],mn[-1],h[-1],a[-1])
    if f is None: S['result unknown']=S.get('result unknown',0)+1; continue
    t1=t[0]-(mn[0]*60 if mn[0]==mn[0] else 0); x,y=np.searchsorted(mts,t1-1800),np.searchsorted(mts,t1+1800)
    # the same game can hold two market ids (old loader v 347): both names equal, so take the one with the first candidate and de-duplicate names before loose
    seen={}
    for c in cand[x:y]: seen.setdefault((c[0],c[1]),c)
    m=loose(norm(g.home_team.iloc[0]),norm(g.away_team.iloc[0]),list(seen.values()))
    if m is None: S['unmatched']=S.get('unmatched',0)+1; continue
    sig.append(dict(fid=fid,m=m,t0=t[i],mn=mn[i],draw=f[0]==f[1],gts=goal_times(list(t),list(h+a))))
print("signals",len(sig),"skips",S,flush=True)
Dr=pd.read_sql("SELECT market_id,ts,ltp::float ltp FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND sel='The Draw' AND ltp>=1.01 AND ltp<1000 ORDER BY market_id,ts",con,params=([s['m'] for s in sig],)); Dr['t']=ep(Dr.ts); dg={k:g for k,g in Dr.groupby('market_id')}
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
if e4:
    R=pd.DataFrame(e4); C=R[R.age>=20].groupby('b').p.median(); print("fresh-pool n by band:",R[R.age>=20].groupby('b').size().to_dict(),"entries by band:",R.groupby('b').size().to_dict())
    C=C.reindex(sorted(set(R.b)|set(C.index))).ffill(); print("fresh-pool medians by band, an empty band takes the band before it:",C.round(2).to_dict()); R['ceil']=R.p<=1.25*R.b.map(C).fillna(np.inf); R['fresh']=R.ceil&R.pre_ok
    R['h']=np.where(R.d<=R.d.median(),1,2); o=[]
    for nm,x in (('ALL',R),('FRESH',R[R.fresh])):
        for c in ('s1','g1','s4','g4'):
            y=x.dropna(subset=[c]); o.append(dict(line=f"C4 {nm} {c}",**line(y[c].values,y.h.values),won=y.draw.mean(),implied=(1/y.p).mean()))
    T4=pd.DataFrame(o); print(T4.drop(columns='maxwin').round(3).to_string(index=False)); SV.append(T4[T4.PASS])
else: print("no C4 entries")
# ---- real touch: C3c, C4 forward, C5
print(f"\n== real touch, liq_sample, {time.time()-T0:.0f}s",flush=True)
try:
    Rw=psycopg2.connect(creds.pg_railway()); Rw.autocommit=True; rc=Rw.cursor(); rc.execute("SET work_mem='64MB'; SET statement_timeout='900s'")
    Q=pd.read_sql("""SELECT ts,event_name,mkt,sel,minute,ltp::float ltp,back_px::float bp,back_sz::float bs,lay_px::float lp,lay_sz::float lz FROM liq_sample WHERE back_px>1 AND lay_px>back_px AND minute::text ~ '^[0-9]+$' AND (
        (mkt='BTTS' AND minute::int<=2) OR (mkt='BTTS' AND sel='YES' AND minute::int>=75) OR (mkt='MO' AND minute::int<=2) OR (mkt='MO' AND sel='DRAW' AND minute::int>=75))""",Rw); Rw.close()
    Q['t']=ep(Q.ts); Q['mn']=pd.to_numeric(Q.minute); ta,tb=pd.to_datetime(Q.ts,utc=True).min(),pd.to_datetime(Q.ts,utc=True).max(); print(f"rows {len(Q)}, {ta} .. {tb}, {Q.event_name.nunique()} events, {time.time()-T0:.0f}s",flush=True)
    Tl=pd.read_sql("SELECT fixture_id,home_team,away_team,captured_at,minute,score_home h,score_away a,status FROM goal_timeline WHERE captured_at>=%s AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at",con,params=(ta-pd.Timedelta(hours=3),))
    print(f"local feed to {pd.to_datetime(Tl.captured_at,utc=True).max()}: later games have no result here and are excluded",flush=True)
    Tl['t']=ep(Tl.captured_at); Tl['mn']=pd.to_numeric(Tl.minute,errors='coerce'); evn=Q.groupby('event_name').t.agg(['min','max']); ev_c=[(norm(e.partition(' v ')[0]),norm(e.partition(' v ')[2]),e) for e in evn.index]; ev_mn=evn['min'].values; ev_mx=evn['max'].values
    by={k:g for k,g in Q.groupby(['event_name','mkt','sel'])}; c3=[]; c4=[]; c5=[]; fav={}
    for e in evn.index:
        hh=by.get((e,'MO','HOME')); aa=by.get((e,'MO','AWAY'))
        if hh is not None and aa is not None:
            fp=[x.ltp.iloc[0] for x in (hh,aa) if x.ltp.iloc[0]==x.ltp.iloc[0]]
            if fp: fav[e]=min(fp)
    med=dict(C) if e4 else {}
    for fid,g in Tl.groupby('fixture_id',sort=False):
        t=g.t.values; mn=g.mn.values; h=g.h.astype(int).values; a=g.a.astype(int).values
        keep=[c for c,x,y in zip(ev_c,ev_mn,ev_mx) if x<=t[-1] and y>=t[0]]
        e=loose(norm(g.home_team.iloc[0]),norm(g.away_team.iloc[0]),keep)
        if e is None: continue
        f=final(fid,AFD,g.status.iloc[-1],mn[-1],h[-1],a[-1])
        if f is None: continue
        bn=not (f[0]>0 and f[1]>0)
        x=by.get((e,'BTTS','NO'))
        if x is not None:
            q=x.iloc[0]; c3.append(dict(d=q.t,lp=q.lp,ltp=q.ltp,lz=q.lz,won=bn,v=lay_settle(step(q.lp,1),bn),vl=lay_settle(step(q.ltp,1),bn) if q.ltp==q.ltp else np.nan))
        i=signal_known(t,mn,h,a,2,2,75,89)
        x=by.get((e,'MO','DRAW'))
        if i is not None and x is not None:
            w=x[(x.t>=t[i])&(x.t<=t[i]+120)]
            if len(w):
                q=w.iloc[0]; b=int(mn[i]//5*5); a1=step(q.bp,-1)
                if a1>1.01: c4.append(dict(d=q.t,bp=q.bp,bs=q.bs,draw=f[0]==f[1],ceil=q.bp<=1.25*med.get(b,np.inf),v=back_settle(a1,f[0]==f[1])))
        i=signal_known(t,mn,h,a,0,0,75,89)
        x=by.get((e,'BTTS','YES'))
        if i is not None and x is not None:
            w=x[(x.t>=t[i])&(x.t<=t[i]+120)]
            if len(w):
                q=w.iloc[0]; c5.append(dict(d=q.t,lp=q.lp,lz=q.lz,ltp=q.ltp,fav=fav.get(e,np.nan),won=not bn,v=lay_settle(step(q.lp,1),not bn)))
    def show(name,W,col='v'):
        if not len(W): print(f"{name}: no entries"); return
        W=W.dropna(subset=[col]); h=np.where(W.d<=W.d.median(),1,2); l=line(W[col].values,h); print(f"{name}: n {l['n']} {l['per10']:+.3f} t {l['t']:.2f} h1 {l['h1']:+.3f} (n {l['n1']}) h2 {l['h2']:+.3f} (n {l['n2']}) PASS {l['PASS']}")
    W3=pd.DataFrame(c3); show("C3c lay BTTS No real touch",W3); show("C3c same games at LTP + 1 tick",W3,'vl')
    if len(W3): print(f"   No won {W3.won.mean():.3f} v implied at touch {(1/W3.lp).mean():.3f}; lay size >= £10 on {(W3.lz>=10).mean():.3f}; median touch minus LTP {(W3.lp-W3.ltp).median():.3f}"); show("C3c excl touch > 2 x LTP",W3[W3.lp<=2*W3.ltp]); W3['q']=pd.qcut(1/W3.lp,3,labels=['low','mid','high'],duplicates='drop'); print("   match check, No won by implied tercile (wrong matches would flatten this):",W3.groupby('q',observed=True).agg(implied=('lp',lambda s:(1/s).mean()),won=('won','mean')).round(3).to_dict('index'))
    W4=pd.DataFrame(c4); show("C4 back draw real touch, all",W4)
    if len(W4): show("C4 CEIL",W4[W4.ceil]); print(f"   draw won {W4.draw.mean():.3f} v implied {(1/W4.bp).mean():.3f}")
    W5=pd.DataFrame(c5); show("C5 lay BTTS Yes 0-0 75+, all",W5)
    if len(W5):
        F5=W5[(W5.fav>=2)&(W5.fav<=3)]; show("C5 favourite 2-3",F5); print(f"   Yes won {W5.won.mean():.3f}, median lay touch {W5.lp.median():.1f}, median ltp {W5.ltp.median():.1f}, lay size >= stake on {(W5.lz>=10/(W5.lp.clip(lower=1.02)-1)).mean():.3f}")
except psycopg2.Error as e_:
    print("REAL TOUCH UNAVAILABLE",type(e_).__name__,str(e_).splitlines()[0][:150],flush=True)
con.close()
print("\n== SURVIVORS (bar: n>=300, both halves > 0, t>=3.5, mean>=+0.15)")
S_=[x for x in SV if len(x)]
print(pd.concat(S_).drop(columns='maxwin').round(3).to_string(index=False) if S_ else "none")
print(f"total {time.time()-T0:.0f}s")
PY
