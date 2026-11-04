#!/bin/bash
set -o pipefail
# 499_cand_c2_segunda (Finder 2026-11-04, queue item 57c): C2 Segunda Under 2.5 / BTTS No overpriced, lay at kick-off. Selected on bf_hist_price seasons 2024-25 and 2025-26 (jobs 491, item 45), so those are shown only as reference.
# A RESULTS AND CLOSING ODDS: fd_matches SP2, seasons nobody selected on. Fair Under = de-vigged closing price, Betfair exchange close (BFEC) if the file has it, else Pinnacle close (PC), else Bet365 close. Under won v fair, z. PROXY P&L: lay Under at that closing price + 1 tick, 2%, held to FT, one bet per game: a close is not a print and a bookmaker price cannot be laid, so this tests the price level, and a pass is an upper bound. Controls: other second tiers and SP1. Halves by season.
# B EXCHANGE PRINTS: bf_hist_other OVER_UNDER_25 and BOTH_TEAMS_TO_SCORE on the 2026-27 season, Segunda and control second tiers from af_fixtures. KO = first print in the 2 min after the market's first in-play print; T15 = first print in the 15 min before the scheduled off. One tick adverse, 2%, £10 liability, held to the FT score, one bet per game per line. A KO entry after a goal is dropped, counted (as job 491). Item 66 already scored Jul-Sep OU25 at T15; shown again because the loader has grown it.
# C REAL TOUCH: liq_sample, Segunda: lay touch at in-play minute 0..2, one tick adverse.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks()
pd.set_option('display.width',240); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',30)
T0=time.time(); E0=pd.Timestamp('1970-01-01',tz='UTC')
def fair_under(u,o):
    """De-vigged Under probability from Under and Over decimal prices, or nan."""
    if not (u and o and u>1 and o>1): return np.nan
    return (1/u)/(1/u+1/o)
def num(x):
    try: v=float(x)
    except (TypeError,ValueError): return np.nan
    return v if v>1 else np.nan
def close(raw):
    """(under,over,source) closing price from a raw fd row, best source first."""
    for src,a,b in (('BFEC','BFEC<2.5','BFEC>2.5'),('PC','PC<2.5','PC>2.5'),('B365C','B365C<2.5','B365C>2.5')):
        u,o=num(raw.get(a)),num(raw.get(b))
        if u==u and o==o: return u,o,src
    return np.nan,np.nan,None
# known answers: evens both ways = 0.5; 1.5 v 3.0 = (2/3)/(2/3+1/3) = 2/3; missing = nan
assert fair_under(2,2)==0.5 and abs(fair_under(1.5,3)-2/3)<1e-9 and fair_under(None,2)!=fair_under(None,2)
assert close({'BFEC<2.5':'1.52','BFEC>2.5':'2.84','PC<2.5':'1.53','PC>2.5':'2.62'})==(1.52,2.84,'BFEC') and close({'PC<2.5':'1.53','PC>2.5':'2.62'})[2]=='PC' and close({})[2] is None and close({'BFEC<2.5':'','BFEC>2.5':'','B365C<2.5':'1.5','B365C>2.5':'2.5'})[2]=='B365C'
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
D=pd.read_sql("SELECT div,season,date,home,away,fthg,ftag,raw FROM fd_matches WHERE div=ANY(%s) AND fthg IS NOT NULL",con,params=(['SP2','SP1','I2','E1','D2','F2'],))
c=[close(r) for r in D.raw]; D['u']=[x[0] for x in c]; D['o']=[x[1] for x in c]; D['src']=[x[2] for x in c]; D=D.drop(columns='raw')
D['under']=(D.fthg+D.ftag)<2.5; D['btts_no']=~((D.fthg>0)&(D.ftag>0)); D['fair']=[fair_under(u,o) for u,o in zip(D.u,D.o)]
print("\n== A results only, every season: Under 2.5 rate and BTTS No rate")
print(D[D['div']=='SP2'].groupby('season').agg(n=('under','size'),under=('under','mean'),btts_no=('btts_no','mean'),priced=('fair','count'),fair=('fair','mean'),src=('src',lambda s:s.dropna().mode().iloc[0] if s.notna().any() else '-')).round(3).to_string())
SEL=('2425','2526'); P=D[D.fair.notna()].copy(); P['grp']=np.where(P.season.isin(SEL),'selection',np.where(P.season=='2627','2026-27','untouched'))
P['v']=[lay_settle(step(u,1),w) for u,w in zip(P.u,P.under)]
o=[]
for (dv,g),x in P.groupby(['div','grp']):
    k=int(x.under.sum()); n=len(x); p=x.fair.mean(); ss=sorted(x.season.unique()); h=np.where(x.season.isin(ss[:(len(ss)+1)//2]),1,2)
    o.append(dict(div=dv,grp=g,seasons=f"{ss[0]}-{ss[-1]}",**{a:b for a,b in line(x.v.values,h).items() if a!='maxwin'},under=x.under.mean(),fair=p,z=zscore(k,n,p),neg_seasons=int((x.groupby('season').apply(lambda y:y.under.mean()-y.fair.mean(),include_groups=False)<0).sum()),of=len(ss)))
A=pd.DataFrame(o); print("\n== A closing price, lay Under 2.5 + 1 tick PROXY, one bet per game; h1/h2 = earlier and later seasons of the group"); print(A.round(3).to_string(index=False))
print("-- SP2 by season, under minus fair, points:",((P[P['div']=='SP2'].groupby('season').under.mean()-P[P['div']=='SP2'].groupby('season').fair.mean())*100).round(1).to_dict())
SV=A[(A['div']=='SP2')&(A.grp=='untouched')&A.PASS]
# ---- B
LG={141:'Segunda',40:'Championship',136:'Serie B',79:'Bundesliga 2',62:'Ligue 2',140:'La Liga'}
F=pd.read_sql("SELECT fixture_id,league_id,kickoff,home,away,hg,ag FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND season=2026 AND league_id=ANY(%s) AND kickoff>='2026-07-01'",con,params=(list(LG),))
F['ko']=(pd.to_datetime(F.kickoff,utc=True)-E0).dt.total_seconds(); F['H']=F.home.map(norm); F['A']=F.away.map(norm)
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) fg FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') GROUP BY 1",con,params=(list(map(int,F.fixture_id)),)); FG=dict(zip(EV.fixture_id,EV.fg))
rows=[]; S={}
for mt,want,lab in (('OVER_UNDER_25','Under 2.5 Goals','U25'),('BOTH_TEAMS_TO_SCORE','No','BTTSNO')):
    B=pd.read_sql("SELECT market_id,event_name,market_time,sel,ts,ltp::float ltp,inplay FROM bf_hist_other WHERE sport='Soccer' AND market_type=%s AND ltp>=1.01 AND ltp<1000 AND market_time>='2026-07-01' AND sel=%s ORDER BY market_id,ts",con,params=(mt,want))
    B['t']=(pd.to_datetime(B.ts,utc=True)-E0).dt.total_seconds(); B['mt']=(pd.to_datetime(B.market_time,utc=True)-E0).dt.total_seconds()
    meta=B.groupby('market_id',sort=False).agg(ev=('event_name','first'),mt=('mt','first')).reset_index().sort_values('mt'); mts=meta.mt.values; cand=[(norm(e.partition(' v ')[0]),norm(e.partition(' v ')[2]),m) for e,m in zip(meta.ev,meta.market_id)]
    gr={k:g for k,g in B.groupby('market_id',sort=False)}; print(f"\nB {lab}: markets {len(meta)}, {pd.to_datetime(B.ts,utc=True).min()} .. {pd.to_datetime(B.ts,utc=True).max()}",flush=True)
    for r in F.itertuples():
        a,b=np.searchsorted(mts,r.ko-1800),np.searchsorted(mts,r.ko+1800)
        if a==b: continue
        m=loose(r.H,r.A,cand[a:b])
        if m is None: S[lab+' unmatched']=S.get(lab+' unmatched',0)+1; continue
        g=gr[m]; won=(r.hg+r.ag<2.5) if lab=='U25' else not (r.hg>0 and r.ag>0)
        pre=g[(~g.inplay)&(g.t>=r.ko-900)&(g.t<r.ko)]
        if len(pre): rows.append(dict(lg=r.league_id,mk=lab,entry='T15',d=r.ko,p=float(pre.ltp.iloc[0]),won=won,fid=r.fixture_id))
        ip=g[g.inplay]
        if len(ip):
            t0=ip.t.iloc[0]; lag=(t0-r.ko)/60; mins=(t0-r.ko)/60
            if -5<=lag<=20 and not (FG.get(r.fixture_id,999)<=max(mins,0)): rows.append(dict(lg=r.league_id,mk=lab,entry='KO',d=r.ko,p=float(ip.ltp.iloc[0]),won=won,fid=r.fixture_id))
            else: S[lab+' KO dropped']=S.get(lab+' KO dropped',0)+1
print("skips:",S,flush=True); R=pd.DataFrame(rows)
if len(R):
    R['v']=[lay_settle(step(p,1),w) for p,w in zip(R.p,R.won)]; R['v3']=[lay_settle(step(p,3),w) for p,w in zip(R.p,R.won)]
    o=[]
    for (lg,mk,en),x in R.groupby(['lg','mk','entry']):
        h=np.where(x.d<=x.d.median(),1,2); o.append(dict(league=LG[lg],mk=mk,entry=en,**line(x.v.values,h),x3=x.v3.mean(),sel_won=x.won.mean(),implied=(1/x.p).mean()))
    B_=pd.DataFrame(o); print("\n== B exchange prints, 2026-27, lay, held to FT"); print(B_.drop(columns='maxwin').sort_values(['mk','entry','league']).round(3).to_string(index=False))
    SV=pd.concat([SV,B_[(B_.league=='Segunda')&B_.PASS]])
con.close()
# ---- C
print("\n== C real touch, Segunda, liq_sample",flush=True)
try:
    Rw=psycopg2.connect(creds.pg_railway()); Rw.autocommit=True; rc=Rw.cursor(); rc.execute("SET work_mem='64MB'; SET statement_timeout='600s'")
    L=pd.read_sql("SELECT ts,event_name,mkt,sel,minute,ltp::float ltp,lay_px::float lp,lay_sz::float lz,back_px::float bp FROM liq_sample WHERE competition='Spanish Segunda Division' AND ((mkt='OU25' AND upper(sel) LIKE 'UNDER%%') OR (mkt='BTTS' AND sel='NO')) AND lay_px>back_px AND back_px>1 ORDER BY ts",Rw)
    Gl=pd.read_sql("SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,minute,score_home,score_away,status FROM goal_timeline WHERE league_id=141 AND captured_at>=(SELECT min(ts)-interval '3 hours' FROM liq_sample) AND score_home IS NOT NULL ORDER BY fixture_id,captured_at DESC",Rw)
    Rw.close(); L['mn']=pd.to_numeric(L.minute,errors='coerce'); L['t']=pd.to_datetime(L.ts,utc=True); out=[]; c_=[(norm(a),norm(b),(int(h),int(g),st,m)) for a,b,h,g,st,m in zip(Gl.home_team,Gl.away_team,Gl.score_home,Gl.score_away,Gl.status,Gl.minute)]
    for (ev,mk),g in L[(L.mn>=0)&(L.mn<=2)].groupby(['event_name','mkt']):
        r=loose(norm(ev.partition(' v ')[0]),norm(ev.partition(' v ')[2]),c_)
        if r is None: continue
        hs,gs,st,m=r
        if not (str(st) in ('FT','AET','PEN','Match Finished','FINISHED') or (pd.to_numeric(m,errors='coerce')>=88)): continue
        q=g.iloc[0]; won=(hs+gs<2.5) if mk=='OU25' else not (hs>0 and gs>0)
        out.append(dict(game=ev[:30],mk=mk,lay=q.lp,ltp=q.ltp,gap=int(np.searchsorted(LD,round(q.lp,2)-1e-9)-np.searchsorted(LD,round(q.ltp,2)-1e-9)) if q.ltp==q.ltp else np.nan,sz=q.lz,won=won,v=lay_settle(step(q.lp,1),won)))
    if out: W=pd.DataFrame(out); print(W.round(2).to_string(index=False)); print(W.groupby('mk').agg(n=('v','size'),mean=('v','mean'),t=('v',tstat),won=('won','mean'),gap=('gap','median')).round(3).to_string())
    else: print("no entries")
except psycopg2.Error as e_:
    print("C UNAVAILABLE",type(e_).__name__,flush=True)
print("\n== SURVIVORS (bar: n>=300, both halves > 0, t>=3.5, mean>=+0.15; A is a proxy, not exchange prints)")
print(SV.drop(columns=[c for c in ('maxwin',) if c in SV]).round(3).to_string(index=False) if len(SV) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
