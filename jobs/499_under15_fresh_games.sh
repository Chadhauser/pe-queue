#!/bin/bash
set -o pipefail
# 499_under15_fresh_games (Finder 2026-11-04, queue item 55): BACK UNDER 1.5 IN GAMES PRICED FOR FEW GOALS, LEAGUE CHOSEN BEFORE THE SEASON. bf_hist_price x af_events x af_fixtures, then liq_sample. The number 499 is reused with a new slug: 450-499 are all taken.
# RULE, fixed from jobs/488 on 2,953 games (R18): favourite first print <= 2.79, Over 2.5 first print > 2.07 (first prints in tape minutes 0..2), kick-off hour >= 16 UTC (the tree split at 15.5 on a whole hour), league in the list below.
# LEAGUE LIST, season 2024 only: first-entry residual of Under 1.5 (won - 1/price) above 0 with n >= 50. Chosen before 2025 is looked at.
# FRESH GAMES: 2025 games NOT in the first 60 chunks of 488's fixed order (seed 488, 50 per chunk), as those chose the rule. The chosen games are also shown, as a reproduction, not as a test.
# ENTRY as 488: first real print from tape minute 3, price 1.03..50, no goal in the last 5 tape minutes, no more than one goal known 5 minutes ago (else Under 1.5 is settled), one per game. Back £10, one tick adverse, 2% commission.
# EXITS: settle on the FT score; next goal +8 first real print, unless a second goal has closed the market or no print = result. Halves: median date of the fresh games. x3 = three ticks adverse.
# FORWARD: liq_sample since it began, real back touch one tick adverse, same price rule at the first touch in minutes 0..10, no league filter (league names do not map), result from goal_timeline's last row at 85'+, unknown = -£10. Small: read the touch cost.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,time,unicodedata,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',240); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',40)
T0=time.time(); KNOW=5
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LADA=np.array(LAD)
def ti(p): return int(np.searchsorted(LADA,round(float(p),2)-1e-9))
def dn(p,k=1): return float(LADA[max(ti(p)-k,0)])
def up(p,k=1): return float(LADA[min(ti(p)+k,len(LADA)-1)])
def net(x): return x*0.98 if x>0 else x
def back(a,won): return net(10*(a-1)) if won else -10.0
def hedge(a,q): return net(10*(a/up(q)-1))
def rule_ok(fav,o25,hour): return fav<=2.79 and o25>2.07 and hour>=16
def entry(arr,goals):
    """First t >= 3 with a real print 1.03..50, no goal in (t-5,t], no more than one goal at or before t-5."""
    for t in np.flatnonzero(~np.isnan(arr)):
        t=int(t)
        if t<3 or t>92: continue
        if not 1.03<=arr[t]<=50: continue
        if any(t-KNOW<g<=t for g in goals): continue
        if sum(1 for g in goals if g<=t-KNOW)>1: return None
        return t
    return None
def exit_g8(arr,goals,t):
    g=[x for x in goals if x>t]
    if not g or g[0]+8>=len(arr): return None
    w=np.flatnonzero(~np.isnan(arr[g[0]+8:]))
    if not len(w): return None
    q=g[0]+8+int(w[0])
    return None if sum(1 for x in goals if x<=q)>1 else float(arr[q])
def tstat(v):
    v=np.asarray(v,dtype=float); n=len(v)
    if n<2: return 0.0
    s=v.std(ddof=1); return float(v.mean()/(s/np.sqrt(n))) if s>0 else 0.0
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|club|de|the|athletic|atletico|real|cd|ud|sd|rcd|ca)\b"," ",s)
    return set(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def sim(A,B): return len(A&B)/max(1,len(A|B))
def final_row(status,minute): return status in ('2H','ET') and minute is not None and minute>=85
# known answers, worked by hand
assert dn(3.0)==2.98 and up(3.0)==3.05 and dn(3.0,3)==2.94 and abs(back(2.98,True)-19.404)<1e-9 and back(2.98,False)==-10.0 and abs(hedge(2.98,2.0)-10*(2.98/2.02-1)*.98)<1e-9
assert rule_ok(2.79,2.08,16) and not rule_ok(2.80,2.08,16) and not rule_ok(2.5,2.07,16) and not rule_ok(2.5,2.5,15)
A_=np.full(101,np.nan); A_[2]=3.0; A_[3]=3.0; A_[4]=2.9; A_[20]=5.0; A_[40]=1.5
assert entry(A_,[])==3 and entry(A_,[1])==20 and entry(A_,[0,1]) is None and entry(np.full(101,np.nan),[]) is None   # a goal at 1 blocks minutes 3 and 4 (within 5); at 20 one goal is known
assert entry(A_,[3])==20                                                                  # goal at 3 blocks minutes 3,4; next print at 20, one goal known
assert exit_g8(A_,[30],3)==1.5 and exit_g8(A_,[],3) is None and exit_g8(A_,[35],3) is None and exit_g8(A_,[30,35],3) is None   # 30: print at 40; 35: none from 43; two goals by 40: closed
B_=np.full(101,np.nan); B_[50]=2.0
assert exit_g8(B_,[10,40],3) is None and exit_g8(B_,[10,60],3)==2.0 and exit_g8(B_,[42],3)==2.0   # a second goal by the exit closes the market; one after it does not
assert abs(tstat([1,3])-2.0)<1e-9 and final_row('2H',85) and not final_row('2H',80)
print("known-answer checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.season,f.league,f.kickoff,f.hg,f.ag,f.ht_hg,f.ht_ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint
  WHERE f.status='FT' AND f.hg IS NOT NULL AND f.ht_hg IS NOT NULL AND f.season IN (2024,2025) ORDER BY m.event_id""",con)
G=G.drop_duplicates('event_id'); order=np.random.RandomState(488).permutation(len(G)); G=G.iloc[order].reset_index(drop=True); G['chosen']=G.index<60*50; G['ko']=pd.to_datetime(G.kickoff,utc=True)
print("games",G.groupby(['season','chosen']).size().to_dict(),flush=True)
EV=pd.read_sql("SELECT fixture_id,coalesce(minute,0) mn,coalesce(extra,0) ex FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')",con,params=(list(map(int,G.fixture_id)),))
gl=defaultdict(list)
for r in EV.itertuples(): gl[r.fixture_id].append(int(r.mn+(r.ex if r.mn in (45,90) else 0)))
for k in gl: gl[k].sort()
rows=[]; c=defaultdict(int)
for i in range(0,len(G),1000):
    sub=G.iloc[i:i+1000]
    P=pd.read_sql("SELECT event_id,mkt,sel,minute,m,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND ((mkt='OU15' AND sel='UNDER' AND minute BETWEEN 0 AND 100) OR (mkt='MO' AND sel IN ('HOME','AWAY') AND minute BETWEEN 0 AND 2) OR (mkt='OU25' AND sel='OVER' AND minute BETWEEN 0 AND 2)) AND ltp>=1.01 AND ltp<1000",con,params=(list(sub.event_id),))
    P=P.sort_values(['event_id','mkt','sel','minute','m']).drop_duplicates(['event_id','mkt','sel','minute'])
    by={k:d for k,d in P.groupby('event_id',sort=False)}
    for g in sub.itertuples():
        d=by.get(g.event_id)
        if d is None: c['no prints']+=1; continue
        goals=gl.get(g.fixture_id,[])
        if len(goals)!=int(g.hg)+int(g.ag): c['goals do not match FT']+=1; continue
        lag=(pd.to_datetime(d.m.min(),utc=True)-g.ko).total_seconds()/60
        if not -5<=lag<=20: c['kick-off lag']+=1; continue
        u=d[(d.mkt=='OU15')]; h=d[(d.mkt=='MO')&(d.sel=='HOME')]; a=d[(d.mkt=='MO')&(d.sel=='AWAY')]; o=d[d.mkt=='OU25']
        if not len(u): c['no Under 1.5 prints']+=1; continue
        if not len(h) or not len(a) or not len(o): c['no first prints']+=1; continue
        arr=np.full(101,np.nan); arr[u.minute.values]=u.ltp.values; arr=np.round(arr,2)
        t=entry(arr,goals)
        if t is None: c['no entry']+=1; continue
        p=float(arr[t]); won=int(g.hg)+int(g.ag)<2; a1=dn(p); a3=dn(p,3)
        if a1<=1.01 or a3<=1.01: c['too short']+=1; continue
        q=exit_g8(arr,goals,t)
        rows.append(dict(event_id=g.event_id,league=g.league,season=int(g.season),chosen=g.chosen,ko=g.ko,t=t,p=p,won=won,fav=min(h.ltp.iloc[0],a.ltp.iloc[0]),o25=o.ltp.iloc[0],hour=g.ko.hour,s=back(a1,won),s3=back(a3,won),g8=(back(a1,won) if q is None else hedge(a1,q))))
    print(f"  {min(i+1000,len(G))}/{len(G)} {time.time()-T0:.0f}s",flush=True)
print("counts:",dict(c),flush=True)
R=pd.DataFrame(rows); assert not R.event_id.duplicated().any(); R['res']=R.won.astype(float)-1/R.p; R['rule']=[rule_ok(a,b,x) for a,b,x in zip(R.fav,R.o25,R.hour)]
L24=R[R.season==2024].groupby('league').res.agg(['size','mean']); OK=sorted(L24[(L24['size']>=50)&(L24['mean']>0)].index)
print(f"\nleagues positive on 2024, n >= 50: {len(OK)} of {(L24['size']>=50).sum()}:",OK,flush=True); R['lg_ok']=R.league.isin(OK)
def line(name,d,c='s'):
    d=d.sort_values('ko'); med=d.ko.iloc[len(d)//2] if len(d) else None; a=d[d.ko<med][c] if len(d) else d[c]; b=d[d.ko>=med][c] if len(d) else d[c]; v=d[c]
    r=dict(line=name,exit=c,n=len(v),leagues=d.league.nunique(),px=d.p.median(),won=d.won.mean(),imp=(1/d.p).mean(),per10=v.mean(),t=tstat(v),n1=len(a),h1=a.mean(),n2=len(b),h2=b.mean(),s3=d.s3.mean(),best=v.max() if len(v) else np.nan)
    r['PASS']=bool(r['n']>=300 and r['n1']>=150 and r['n2']>=150 and r['t']>=3.5 and r['h1']>0 and r['h2']>0 and r['per10']>=0.15); return r
F=R[(R.season==2025)&~R.chosen]; Ch=R[(R.season==2025)&R.chosen]; N=R[R.season==2024]
sets=[('FRESH 2025: rule + leagues',F[F.rule&F.lg_ok]),('FRESH, prices <= 10',F[F.rule&F.lg_ok&(F.p<=10)]),('FRESH, rule, no league filter',F[F.rule]),('FRESH, every game (control)',F),('FRESH, rule, leagues NOT chosen',F[F.rule&~F.lg_ok]),('chosen games 2025 (reproduction, not a test)',Ch[Ch.rule&Ch.lg_ok]),('2024, in sample (leagues fitted here)',N[N.rule&N.lg_ok]),('2025 all games: rule + leagues',R[(R.season==2025)&R.rule&R.lg_ok])]
O=[line(n_,d,c_) for n_,d in sets for c_ in ('s','g8') if len(d)>1]; T=pd.DataFrame(O)
print("\n== LINES, back Under 1.5, per £10, one entry per game\n",T.drop(columns=['PASS']).round(3).to_string(index=False))
X=F[F.rule&F.lg_ok]
if len(X):
    print("\nby league\n",X.groupby('league').s.agg(['size','mean',tstat]).round(3).sort_values('mean',ascending=False).to_string()); print("\nby entry minute band\n",X.groupby(pd.cut(X.t,[2,5,10,30,100])).s.agg(['size','mean']).round(3).to_string()); print("\nby price\n",X.groupby(pd.cut(X.p,[1,2.5,3,3.5,4,6,10,60])).s.agg(['size','mean','max']).round(3).to_string(),flush=True)
try:
    print("\n== FORWARD liq_sample x goal_timeline")
    Lq=pd.read_sql("SELECT ts,event_name,mkt,sel,minute,ltp::float ltp,back_px::float bp,back_sz::float bs,lay_px::float lp FROM liq_sample WHERE minute>=0 AND minute<=10 AND ((mkt='OU15' AND sel='UNDER 1.5 GOALS') OR (mkt='MO' AND sel IN ('HOME','AWAY')) OR (mkt='OU25' AND sel='OVER')) AND back_px>1 AND lay_px>back_px ORDER BY ts",con)
    Tl=pd.read_sql("SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,score_home h,score_away a,status,minute,captured_at FROM goal_timeline WHERE captured_at>=(SELECT min(ts)-interval '3 hours' FROM liq_sample) AND score_home IS NOT NULL ORDER BY fixture_id,captured_at DESC",con)
    Tl['H']=Tl.home_team.map(norm); Tl['A']=Tl.away_team.map(norm); Tl['t']=pd.to_datetime(Tl.captured_at,utc=True); fw=[]; un=0
    for ev,d in Lq.groupby('event_name'):
        u=d[d.mkt=='OU15']; h=d[(d.mkt=='MO')&(d.sel=='HOME')]; a=d[(d.mkt=='MO')&(d.sel=='AWAY')]; o=d[d.mkt=='OU25']
        if not (len(u) and len(h) and len(a) and len(o)): continue
        ts=pd.to_datetime(u.ts.iloc[0],utc=True)
        if not rule_ok(min(h.bp.iloc[0],a.bp.iloc[0]),o.bp.iloc[0],ts.hour): continue
        hn,_,an=ev.partition(' v '); H,A=norm(hn),norm(an); best=None; bs=0
        for g in Tl[(Tl.t>ts)&(Tl.t<ts+pd.Timedelta(hours=4))].itertuples():
            s=min(sim(H,g.H),sim(A,g.A))
            if s>bs: bs,best=s,g
        if best is None or bs<0.3: un+=1; continue
        mn=None if pd.isna(best.minute) else float(best.minute); kn=final_row(best.status,mn); w=(best.h+best.a<2) if kn else False; q=u.iloc[0]; a1=dn(q.bp)
        if a1<=1.01: continue
        fw.append(dict(event=ev,bp=q.bp,lp=q.lp,gap=ti(q.lp)-ti(q.bp),ltp_gap=(ti(q.ltp)-ti(q.bp)) if pd.notna(q.ltp) and q.ltp>=1.01 else np.nan,size_ok=q.bs>=10,known=kn,won=w,s=back(a1,w) if kn else -10.0))
    W=pd.DataFrame(fw); print(f"traded {len(W)}, unmatched {un}")
    if len(W): K=W[W.known]; print(f"unknown = -£10: per10 {W.s.mean():+.3f} t {tstat(W.s):.2f} | known only n {len(K)} per10 {K.s.mean():+.3f} t {tstat(K.s):.2f} won {K.won.astype(float).mean():.3f} implied {(1/K.bp).mean():.3f} | back to lay ticks median {W.gap.median()} | ltp above back ticks median {W.ltp_gap.median()} | size >= £10 {W.size_ok.mean():.2f}")
except Exception as e:
    print("FORWARD SECTION FAILED, tape result stands:",type(e).__name__,str(e)[:300],flush=True)
W2=T[T.PASS&T.line.str.startswith('FRESH 2025')]; print(f"\n== SURVIVORS: {len(W2)} (fresh games only, LTP-based, an upper bound)"); print(W2.round(3).to_string(index=False) if len(W2) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
