#!/bin/bash
set -o pipefail
# 499_cand_c1c6_laliga (Finder 2026-11-04, queue item 56c): C1 La Liga 0-0 back Over 1.5 T35 exit goal +5, lay Under 1.5 T30 exit goal +8; C6 same family at other windows. Rules fixed by jobs/489_laliga_00_audit.sh; selected on bf_hist_price seasons 2024 and 2025, so nothing here reads those prices except to state what the market implied.
# A RESULTS: 0-0 at T (no af goal at minute <= T), then 2+ goals at FT? La Liga by season: 2023 and 2026 are untouched. Controls Segunda, Serie A, Premier League, Bundesliga, Ligue 1.
# B RESULTS: HT 0-0 then 2+ second-half goals, fd_matches 2006-07 on: 18 seasons nobody selected on, against 2024-25 and 2025-26.
# C PRICES: bf_hist_other OVER_UNDER_15 (loader 347, Sep 2026 so far, still growing): untouched. Clock is wall time from goal_timeline, as the feed gives it live: signal = first feed row at minute T..T+5 at 0-0; entry = first print within 180 s, the worse of it and the next print within 120 s (as 489), one tick adverse. Phantom goals: a goal counts only if the next row agrees. Result: af_fixtures FT if held, else last feed row if FT or minute>=88; unknown = reported and excluded. Scores are matched by name and time, gate on final prints, read before P&L. LTP only, so a pass is an upper bound.
# D REAL TOUCH: liq_sample, whatever La Liga games it still holds.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks(); print("checks: OK",flush=True)
pd.set_option('display.width',240); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',30)
T0=time.time()
LG={140:'La Liga',141:'Segunda',135:'Serie A',39:'Premier League',78:'Bundesliga',61:'Ligue 1'}
TS=(15,30,35,46,60,70)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
# ---- A
F=pd.read_sql("SELECT fixture_id,league_id,season,kickoff,home,away,hg,ag FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND season>=2023 AND league_id=ANY(%s)",con,params=(list(LG),))
E=pd.read_sql("SELECT fixture_id,coalesce(minute,0) mn FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')",con,params=(list(map(int,F.fixture_id)),))
first=E.groupby('fixture_id').mn.min(); F['fg']=F.fixture_id.map(first); F['ft']=F.hg+F.ag
cnt=E.groupby('fixture_id').size(); F['ev']=F.fixture_id.map(cnt).fillna(0); print(f"A: {len(F)} games; event goals differ from FT in {(F.ev!=F.ft).sum()}; those excluded",flush=True); F=F[F.ev==F.ft]
# what the market implied in the selection seasons, La Liga 0-0 at T: mean 1/print at T+1..T+3, read only for the implied rate
M=pd.read_sql("SELECT m.event_id,f.fixture_id FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.league_id=140 AND f.season IN (2024,2025)",con)
P=pd.read_sql("SELECT event_id,minute,m,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='OU15' AND sel='OVER' AND minute BETWEEN 16 AND 73 AND ltp>=1.01 AND ltp<1000",con,params=(list(M.event_id),))
P=P.sort_values('m').drop_duplicates(['event_id','minute']).merge(M,on='event_id'); IMP={}
for T in TS:
    q=P[(P.minute>T)&(P.minute<=T+3)].sort_values('minute').drop_duplicates('fixture_id')
    q=q.merge(F[['fixture_id','fg','ft']],on='fixture_id'); q=q[~(q.fg<=T)]; IMP[T]=float((1/q.ltp).mean()) if len(q) else np.nan
print("La Liga implied Over 1.5 at 0-0, 2024-25 tape:",{k:round(v,3) for k,v in IMP.items()})
o=[]
for T in TS:
    for lg,nm in LG.items():
        for s in (2023,2024,2025,2026):
            x=F[(F.league_id==lg)&(F.season==s)&~(F.fg<=T)]
            if len(x): o.append(dict(T=T,league=nm,season=s,n=len(x),won=(x.ft>=2).mean()))
A=pd.DataFrame(o); print("\n== A: won rate, 2+ goals at FT given 0-0 at T")
print(A.pivot_table(index=['T','league'],columns='season',values='won').round(3).to_string()); print(A.pivot_table(index=['T','league'],columns='season',values='n').astype(int).to_string())
print("\n-- La Liga, untouched seasons v the implied of the selection seasons")
for T in TS:
    for s in (2023,2026):
        x=A[(A['T']==T)&(A.league=='La Liga')&(A.season==s)]
        if len(x): k=int(round(x.won.iloc[0]*x.n.iloc[0])); print(f"  T{T} season {s}: {k} of {int(x.n.iloc[0])} = {x.won.iloc[0]:.3f} v implied {IMP[T]:.3f}, z {zscore(k,int(x.n.iloc[0]),IMP[T]):+.2f}")
# ---- B
FD=pd.read_sql("SELECT div,season,fthg,ftag,hthg,htag FROM fd_matches WHERE div=ANY(%s) AND fthg IS NOT NULL AND hthg IS NOT NULL",con,params=(['SP1','SP2','I1','E0','D1','F1'],))
FD=FD[(FD.hthg==0)&(FD.htag==0)]; FD['o']=(FD.fthg+FD.ftag)>=2; FD['grp']=np.where(FD.season.isin(['2425','2526']),'2 selection seasons',np.where(FD.season=='2627','2026-27','2006-24, untouched'))
print("\n== B: HT 0-0 then 2+ goals, won rate (n), fd_matches"); print(FD.groupby(['div','grp']).o.agg(['size','mean']).round(3).unstack().to_string())
print("-- SP1 by season:",FD[FD['div']=='SP1'].groupby('season').o.mean().round(2).to_dict())
# ---- C
Mk=pd.read_sql("SELECT market_id,event_name,market_time,sel,ts,ltp::float ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='OVER_UNDER_15' AND ltp>=1.01 AND ltp<1000 AND inplay ORDER BY market_id,sel,ts",con)
Mk['t']=(pd.to_datetime(Mk.ts,utc=True)-pd.Timestamp('1970-01-01',tz='UTC')).dt.total_seconds()
Mk['mt']=(pd.to_datetime(Mk.market_time,utc=True)-pd.Timestamp('1970-01-01',tz='UTC')).dt.total_seconds()
mk={k:g for k,g in Mk.groupby('market_id')}; meta=[(k,g.mt.iloc[0],g.event_name.iloc[0]) for k,g in mk.items()]; print(f"\nC: OU15 markets with in-play prints {len(meta)}, {Mk.ts.min()} .. {Mk.ts.max()}, {time.time()-T0:.0f}s",flush=True)
lo=pd.to_datetime(Mk.ts,utc=True).min()-pd.Timedelta(hours=3); hi=pd.to_datetime(Mk.ts,utc=True).max()+pd.Timedelta(hours=3)
G=pd.read_sql("SELECT fixture_id,league_id,home_team,away_team,captured_at,minute,score_home,score_away,status FROM goal_timeline WHERE captured_at>=%s AND captured_at<=%s AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at",con,params=(lo,hi))
G['t']=(pd.to_datetime(G.captured_at,utc=True)-pd.Timestamp('1970-01-01',tz='UTC')).dt.total_seconds(); G['mn']=pd.to_numeric(G.minute,errors='coerce'); G['tot']=G.score_home.astype(int)+G.score_away.astype(int)
AF=pd.read_sql("SELECT fixture_id,hg+ag ft FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND season>=2026",con); AFD=dict(zip(AF.fixture_id,AF.ft))
print(f"feed rows {len(G)}, fixtures {G.fixture_id.nunique()}, {time.time()-T0:.0f}s",flush=True)
meta.sort(key=lambda z:z[1]); mts=np.array([z[1] for z in meta]); cand=[(norm(z[2].partition(' v ')[0]),norm(z[2].partition(' v ')[2]),z[0]) for z in meta]
rows=[]; S={'unmatched fixture':0,'result unknown':0,'matched':0}; agree=[]
for fid,g in G.groupby('fixture_id',sort=False):
    t=g.t.values; mn=g.mn.values; tot=g.tot.values; km=g.mn.iloc[0] if g.mn.notna().iloc[0] else 0; ko=t[0]-km*60
    a,b=np.searchsorted(mts,ko-1800),np.searchsorted(mts,ko+1800)
    if a==b: continue
    mid=loose(norm(g.home_team.iloc[0]),norm(g.away_team.iloc[0]),cand[a:b])
    if mid is None: S['unmatched fixture']+=1; continue
    S['matched']+=1; ft=AFD.get(fid); src='af'
    if ft is None:
        src='feed'
        if str(g.status.iloc[-1]) in ('FT','AET','PEN','Match Finished','FINISHED') or (pd.notna(mn[-1]) and mn[-1]>=88): ft=int(tot[-1])
        else: S['result unknown']+=1; continue
    x=mk[mid]; ov=x[x.sel=='Over 1.5 Goals']; un=x[x.sel=='Under 1.5 Goals']
    if len(ov) and ov.ltp.iloc[-1]<=1.05: agree.append(ft>=2)
    if len(un) and un.ltp.iloc[-1]<=1.05: agree.append(ft<2)
    gts=goal_times(list(t),list(tot)); lg=g.league_id.iloc[0]
    for T in TS:
        i=signal_row(list(mn),T)
        if i is None or tot[i]!=0: continue
        t0=t[i]
        for side,y in (('B',ov),('L',un)):
            if not len(y): continue
            ts=y.t.values; px=y.ltp.values; e=entry_px(ts,px,t0,side)
            if e is None: S[f'no print {side}']=S.get(f'no print {side}',0)+1; continue
            ei,p=e; f1=step(p,-1) if side=='B' else step(p,1)
            if side=='B' and f1<=1.01: continue
            for ex,k in (('G5',5),('G8',8),('SETTLE',None)):
                rows.append(dict(fid=fid,lg=lg,T=T,side=side,ex=ex,p=p,v=run_exit(side,f1,ts,px,ei,gts,t0,k,ft>=2),over=ft>=2,src=src,t0=t0))
print("match:",S,flush=True); ga=np.mean(agree) if agree else float('nan'); print(f"\n== C GATE: final print <= 1.05 agrees with the matched result on {ga:.3f} of {len(agree)} (bar 0.95)")
if not ga>=0.95: print("GATE FAILED: section C results not used")
elif rows:
    R=pd.DataFrame(rows); med=R.t0.median(); R['h']=np.where(R.t0<=med,1,2)
    def tab(d,nm):
        o=[]
        for (T,sd,ex),x in d.groupby(['T','side','ex']):
            o.append(dict(group=nm,T=T,side=sd,exit=ex,games=x.fid.nunique(),**line(x.v.values,x.h.values),won=x.over.mean(),implied=(1/x.p).mean() if sd=='B' else (1-1/x.p).mean()))
        return pd.DataFrame(o)
    print("result source:",R.drop_duplicates('fid').src.value_counts().to_dict())
    ALL=pd.concat([tab(R,'ALL')]+[tab(R[R.lg==l],n) for l,n in LG.items()]); PRE=ALL[(ALL.group=='La Liga')]
    print("\n-- La Liga on the untouched tape, every line"); print(PRE.drop(columns=['group','PASS','maxwin']).round(3).to_string(index=False))
    print("\n-- the two preset C1 lines, La Liga and controls"); print(ALL[((ALL['T']==35)&(ALL.side=='B')&(ALL.exit=='G5'))|((ALL['T']==30)&(ALL.side=='L')&(ALL.exit=='G8'))].drop(columns=['PASS','maxwin']).round(3).to_string(index=False))
    print("\n-- ALL leagues"); print(ALL[ALL.group=='ALL'].drop(columns=['group','maxwin']).round(3).to_string(index=False))
    print("\n-- top 15 by t, n>=20"); print(ALL[ALL.n>=20].sort_values('t',ascending=False).head(15).drop(columns=['maxwin']).round(3).to_string(index=False))
    SV=ALL[ALL.PASS]
else: print("no entries"); SV=pd.DataFrame()
con.close()
# ---- D
print(f"\n== D real touch, liq_sample, {time.time()-T0:.0f}s",flush=True)
fr=[]
try:
    R_=psycopg2.connect(creds.pg_railway()); R_.autocommit=True; r=R_.cursor(); r.execute("SET work_mem='64MB'; SET statement_timeout='600s'")
    L=pd.read_sql("SELECT ts,event_name,sel,back_px::float bp,lay_px::float lp FROM liq_sample WHERE mkt='OU15' AND competition='Spanish La Liga' AND back_px>1 AND lay_px>back_px ORDER BY ts",R_)
    Gl=pd.read_sql("SELECT fixture_id,home_team,away_team,captured_at,minute,score_home,score_away,status FROM goal_timeline WHERE league_id=140 AND captured_at>=(SELECT min(ts)-interval '3 hours' FROM liq_sample) AND score_home IS NOT NULL ORDER BY fixture_id,captured_at",R_)
    n26=pd.read_sql("SELECT count(DISTINCT fixture_id) n,min(captured_at) a,max(captured_at) b FROM goal_timeline WHERE league_id=140 AND captured_at>='2026-08-01'",R_).iloc[0]
    R_.close(); E0=pd.Timestamp('1970-01-01',tz='UTC')
    L['t']=(pd.to_datetime(L.ts,utc=True)-E0).dt.total_seconds(); L['s']=L.sel.str.upper().str.split().str[0]; Gl['t']=(pd.to_datetime(Gl.captured_at,utc=True)-E0).dt.total_seconds(); Gl['mn']=pd.to_numeric(Gl.minute,errors='coerce'); Gl['tot']=Gl.score_home.astype(int)+Gl.score_away.astype(int)
    evs={e:g for e,g in L.groupby('event_name')}; c_=[(norm(e.partition(' v ')[0]),norm(e.partition(' v ')[2]),e) for e in evs]
    for fid,g in Gl.groupby('fixture_id'):
        e=loose(norm(g.home_team.iloc[0]),norm(g.away_team.iloc[0]),c_)
        if e is None: continue
        x=evs[e]; t=g.t.values; mn=g.mn.values; tot=g.tot.values; gts=goal_times(list(t),list(tot))
        known=str(g.status.iloc[-1]) in ('FT','AET','PEN','Match Finished','FINISHED') or (pd.notna(mn[-1]) and mn[-1]>=88); ft=int(tot[-1])
        for T,side,k in ((35,'B',5),(30,'L',8)):
            i=signal_row(list(mn),T)
            if i is None or tot[i]!=0: continue
            y=x[x.s==('OVER' if side=='B' else 'UNDER')].sort_values('t'); ts=y.t.values
            j=first_idx(ts,t[i],t[i]+90)
            if j is None: continue
            f1=step(y.bp.values[j],-1) if side=='B' else step(y.lp.values[j],1)
            # exit touch: lay the Over at its lay touch, back the Under at its back touch; run_exit adds the adverse tick
            ex_px=y.lp.values if side=='B' else y.bp.values
            fr.append(dict(game=e[:30],T=T,side=side,touch=y.bp.values[j] if side=='B' else y.lp.values[j],ft=ft,known=known,v=run_exit(side,f1,ts,ex_px,j,gts,t[i],k,ft>=2) if known else np.nan))
    if fr: W=pd.DataFrame(fr); print(W.round(3).to_string(index=False)); print(W.groupby(['T','side']).v.agg(['count','mean']).round(3).to_string())
    else: print("no La Liga entries on the real touch")
    wk=((n26.b-n26.a).total_seconds()/86400/7); print(f"La Liga feed since Aug: {int(n26.n)} fixtures over {wk:.1f} weeks")
except psycopg2.Error as e_:
    print("D UNAVAILABLE",type(e_).__name__,flush=True)
print(f"\n== SURVIVORS (bar: n>=300, both halves > 0, t>=3.5, mean>=+0.15)")
print(SV.drop(columns=['maxwin']).round(3).to_string(index=False) if len(SV) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
