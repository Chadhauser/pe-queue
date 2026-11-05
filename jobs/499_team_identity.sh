#!/bin/bash
set -o pipefail
# 499_team_identity (Finder 2026-11-05, queue items 117, 118, Finder's own, sources c and a): is a team's own price error persistent, and is its own late-goal record priced in-play? Rules written in the queue before any price was read. The number 499 is reused with a new slug: 450-499 are all taken.
# DATA af_fixtures, af_events, af_price_map, bf_hist_price (MO, OU15, OU25, OU35); fd_matches for 117's proxy. League identity is league_id. Cups 2, 3 excluded.
# 117 ENTRY earliest real print in tape minutes 0..2; lag outside -5..+20 min v the af kick-off dropped, a goal before the print minute dropped, as jobs/499_new_division.sh. Team error = mean(won - 1/print) on 2024. Cuts across all teams with 25+ games, top and bottom 20% and 10%. Trades on 2025 ONLY; halves by 2025 median date, so the bar's season split is replaced by the date split.
# 117 PROXY fd_matches Pinnacle closes, every season: each team's error on the previous season in that div, the same cuts, one tick adverse on the Pinnacle close. Not a tradeable fill: this cannot pass, only support or not.
# 118 ENTRY first real print at tape minute T..T+4 on the line open at that score. Tape minute is match clock (checked on 33356436). A goal at the print minute or the two before: game dropped from that T, counted, as the print may be before or after it. Goals after the print stay, so nothing is selected on the future. Hold to the result, so a passed line settles at the result, never dropped. Halves by season.
# 118 HISTORY L from the last 30 earlier games, at least 15; games at the same kick-off are not history. Cuts from games before 1 Jul 2024 only, so season 2024 does not see itself.
# ALL LTP, one tick adverse, 2%, £10 risk, so a pass is an upper bound. One entry per game per line, except 117's team lines, where both teams of a game can appear: t by game is required as well.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,deque,Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks()
pd.set_option('display.width',260); pd.set_option('display.max_rows',500); pd.set_option('display.max_columns',40)
T0=time.time()
def bk(x,won):
    a=step(x,-1); return None if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)
def cuts(err):
    """err: {key:error}. Returns {key:[labels]}: TOP20, BOT20, TOP10, BOT10 by rank, ties by key order, needing 10+ keys."""
    k=sorted(err,key=lambda z:(err[z],str(z))); n=len(k); o=defaultdict(list)
    if n<10: return o
    for pct,tg in ((.2,'20'),(.1,'10')):
        m=int(n*pct)
        for z in k[:m]: o[z].append('BOT'+tg)
        for z in k[n-m:]: o[z].append('TOP'+tg)
    return o
def line_for(g):
    """Over/under line for total goals g at T: the line on the tape needing the fewest goals."""
    return {0:('OU15',1.5),1:('OU15',1.5),2:('OU25',2.5),3:('OU35',3.5)}.get(g)
def late_score(a,b,mn=15):
    """a,b: per-game late-goal counts of the two teams, last 30. None unless both have mn."""
    if len(a)<mn or len(b)<mn: return None
    return (float(np.mean(a))+float(np.mean(b)))/2
def guard(goals,pm):
    """Total goals known strictly before pm-2, or None if a goal sits at pm-2, pm-1 or pm."""
    if any(pm-2<=g<=pm for g in goals): return None
    return sum(g<pm-2 for g in goals)
# known answers, worked by hand
assert abs(bk(2.04,True)-9.996)<1e-9 and bk(2.04,False)==-10.0 and ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9 and bk(1.02,True) is None
_c=cuts({i:i for i in range(10)}); assert _c[0]==['BOT20','BOT10'] and _c[1]==['BOT20'] and _c[9]==['TOP20','TOP10'] and _c[8]==['TOP20'] and _c[5]==[]
assert len(cuts({i:i for i in range(9)}))==0
assert line_for(0)==('OU15',1.5) and line_for(1)==('OU15',1.5) and line_for(2)==('OU25',2.5) and line_for(3)==('OU35',3.5) and line_for(4) is None
assert late_score([1]*14,[1]*30) is None and late_score([1]*15,[0]*15)==0.5
assert guard([10,40],70)==2 and guard([68],70) is None and guard([69],70) is None and guard([70],70) is None and guard([71],70)==0 and guard([67,71],70)==1
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=pd.read_sql("SELECT fixture_id,league_id,season,kickoff,home,away,hg,ag FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND ag IS NOT NULL AND kickoff IS NOT NULL AND season>=2023 AND league_id NOT IN (2,3)",con)
F['ks']=pd.to_datetime(F.kickoff,utc=True).map(lambda t:int(t.timestamp())); F=F.sort_values(['ks','fixture_id']).reset_index(drop=True)
EV=pd.read_sql("SELECT fixture_id,coalesce(minute,0) mn FROM af_events WHERE type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')",con)
GL=defaultdict(list)
for a,b in zip(EV.fixture_id,EV.mn): GL[int(a)].append(int(b))
print(f"fixtures {len(F)}, season {F.season.value_counts().to_dict()}, goal rows {len(EV)}, {time.time()-T0:.0f}s",flush=True)
# walk forward: games at one kick-off see only earlier kick-offs. A game whose events do not add up to the score is no history and no 118 trade.
HIST=defaultdict(lambda:deque(maxlen=30)); LS={}; rec=list(F.itertuples(index=False)); i=0; badg=0; GOOD=set()
while i<len(rec):
    j=i
    while j<len(rec) and rec[j].ks==rec[i].ks: j+=1
    for r in rec[i:j]: LS[r.fixture_id]=late_score(HIST[r.home],HIST[r.away])
    for r in rec[i:j]:
        g=GL.get(int(r.fixture_id),[])
        if len(g)!=r.hg+r.ag: badg+=1; continue
        GOOD.add(int(r.fixture_id)); n=sum(x>75 for x in g); HIST[r.home].append(n); HIST[r.away].append(n)
    i=j
print(f"events disagree with score: {badg} of {len(rec)}",flush=True)
F['L']=F.fixture_id.map(LS); pre=F[(F.ks<pd.Timestamp('2024-07-01',tz='UTC').timestamp())&F.L.notna()]
lo,hi=pre.L.quantile(1/3),pre.L.quantile(2/3); print(f"118 cuts from {len(pre)} games before 1 Jul 2024: LOW <= {lo:.3f}, HIGH >= {hi:.3f}",flush=True)
assert len(pre)>=500 and lo<hi
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.league_id,f.season,f.kickoff,f.home,f.away,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.season IN (2024,2025) AND f.league_id NOT IN (2,3)""",con)
print(f"mapped games {len(G)} {G.season.value_counts().to_dict()}",flush=True)
# ---- 117 first-print
parts=[]
for i in range(0,len(G),1000):
    P=pd.read_sql("SELECT event_id,mkt,sel,minute,m,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt IN ('MO','OU25') AND sel IN ('HOME','DRAW','AWAY','UNDER','OVER') AND minute>=0 AND minute<=2 AND ltp>=1.01 AND ltp<1000",con,params=(list(G.event_id.iloc[i:i+1000]),))
    parts.append(P.sort_values(['event_id','mkt','sel','minute','m']).drop_duplicates(['event_id','mkt','sel']))
P=pd.concat(parts,ignore_index=True).merge(G,on='event_id')
P['lag']=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True)).dt.total_seconds()/60
bad=(P.lag<-5)|(P.lag>20); kn=np.array([any(g<mn for g in GL.get(int(fx),[])) for fx,mn in zip(P.fixture_id,P.minute)])
print(f"117 games with a print {P.event_id.nunique()}; rows dropped, lag {int(bad.sum())}, goal before the print {int(kn.sum())}; {time.time()-T0:.0f}s",flush=True); P=P[~bad&~kn]
T=[]; OE=[]
for (e,fx,lg,s,h,a,hg,ag),x in P.groupby(['event_id','fixture_id','league_id','season','home','away','hg','ag']):
    pr={(u,v):w for u,v,w in zip(x.mkt,x.sel,x.ltp)}; ks=pd.Timestamp(x.kickoff.iloc[0]).timestamp()
    for ven,t,sel,won in (('H',h,'HOME',hg>ag),('A',a,'AWAY',ag>hg)):
        if ('MO',sel) in pr: T.append((fx,lg,s,ks,t,ven,pr[('MO',sel)],won))
    if ('OU25','OVER') in pr: OE.append((fx,lg,s,ks,h,a,pr[('OU25','OVER')],pr.get(('OU25','UNDER')),hg+ag>2.5))
T=pd.DataFrame(T,columns=['fx','lg','season','ks','team','ven','x','won']); T['e']=T.won.astype(float)-1/T.x
O=pd.DataFrame(OE,columns=['fx','lg','season','ks','home','away','ov','un','over'])
A=T[T.season==2024]; C=T[T.season==2025].copy(); md=C.ks.median(); C['h']=np.where(C.ks<md,1,2)
rows=[]
for scope,flt in (('ALL',None),('H','H'),('A','A')):
    src=A if flt is None else A[A.ven==flt]; mn=25 if flt is None else 12
    g=src.groupby(['team','lg']).e.agg(['mean','count']); err={k:v for k,v in g[g['count']>=mn]['mean'].items()}
    lab=cuts(err); print(f"117 {scope}: teams {len(err)}; bottom {[k[0] for k in sorted(err,key=err.get)[:5]]}, top {[k[0] for k in sorted(err,key=err.get)[-5:]]}",flush=True)
    tr=C if flt is None else C[C.ven==flt]
    for r in tr.itertuples():
        for tg in ['ANY']+lab.get((r.team,r.lg),[]) if (r.team,r.lg) in err else []:
            for side,v in (('BACK',bk(r.x,r.won)),('LAY',ly(r.x,r.won))):
                if v is not None: rows.append((117,scope,tg,side,r.fx,r.h,r.x,r.won,v))
# goals error: mean over minus implied over each team's 2024 games, terciles across teams with 25+
long=pd.concat([O[O.season==2024].rename(columns={'home':'team'})[['team','lg','ov','over']],O[O.season==2024].rename(columns={'away':'team'})[['team','lg','ov','over']]])
long['e']=long.over.astype(float)-1/long.ov; g=long.groupby(['team','lg']).e.agg(['mean','count']); ge=g[g['count']>=25]['mean']; a1,a2=ge.quantile(1/3),ge.quantile(2/3)
print(f"117 goals: teams {len(ge)}, tercile cuts {a1:.3f} {a2:.3f}",flush=True); ged=ge.to_dict()
O5=O[O.season==2025].copy(); O5['h']=np.where(O5.ks<O5.ks.median(),1,2)
for r in O5.itertuples():
    x,y=ged.get((r.home,r.lg)),ged.get((r.away,r.lg))
    if x is None or y is None: continue
    st='BOTH_OVERRUN' if x>=a2 and y>=a2 else 'BOTH_UNDERRUN' if x<=a1 and y<=a1 else None
    if st is None: continue
    for sel,px,won in (('OVER',r.ov,r.over),('UNDER',r.un,not r.over)):
        if px is None or px!=px: continue
        for side,v in (('BACK',bk(px,won)),('LAY',ly(px,won))):
            if v is not None: rows.append((117,'GOALS',st+'_'+sel,side,r.fx,r.h,px,won,v))
print(f"117 rows {len(rows)} {time.time()-T0:.0f}s",flush=True)
# ---- 117 proxy, Pinnacle closes
D=pd.read_sql("SELECT div,season,date,home,away,fthg,ftag,psch::float psch,psca::float psca FROM fd_matches WHERE psch>1 AND psca>1 AND fthg IS NOT NULL AND ftag IS NOT NULL",con)
print(f"fd_matches with Pinnacle close {len(D)}, seasons {D.season.nunique()}",flush=True)
L2=pd.concat([D.assign(team=D.home,x=D.psch,won=D.fthg>D.ftag),D.assign(team=D.away,x=D.psca,won=D.ftag>D.fthg)]); L2['e']=L2.won.astype(float)-1/L2.x
sv=sorted(L2.season.unique()); px=[]
for a,b in zip(sv,sv[1:]):
    g=L2[L2.season==a].groupby(['div','team']).e.agg(['mean','count']); err=g[g['count']>=25]['mean'].to_dict(); lab=cuts(err)
    for r in L2[L2.season==b].itertuples():
        k=(r.div,r.team)
        if k not in err: continue
        for tg in ['ANY']+lab.get(k,[]):
            for side,v in (('BACK',bk(r.x,r.won)),('LAY',ly(r.x,r.won))):
                if v is not None: px.append((tg,side,b,v))
PX=pd.DataFrame(px,columns=['tg','side','season','v'])
print("\n== 117 PROXY, Pinnacle closes, previous season's error, cannot pass; seasons positive of all")
print(pd.DataFrame([dict(tg=k[0],side=k[1],n=len(x),per10=x.v.mean(),t=tstat(x.v.values),pos=f"{int((x.groupby('season').v.mean()>0).sum())}/{x.season.nunique()}") for k,x in PX.groupby(['tg','side'])]).round(3).to_string(index=False),flush=True)
# ---- 118
parts=[]; GG=G[G.fixture_id.isin(GOOD)&G.fixture_id.map(LS).notna()].reset_index(drop=True)
print(f"118 games with goals that add up and L known: {len(GG)} of {len(G)}, {GG.season.value_counts().to_dict()}",flush=True)
for i in range(0,len(GG),500):
    Q=pd.read_sql("SELECT event_id,mkt,sel,minute,m,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt IN ('OU15','OU25','OU35') AND sel IN ('OVER','UNDER') AND minute>=70 AND minute<=84 AND ltp>=1.01 AND ltp<1000",con,params=(list(GG.event_id.iloc[i:i+500]),))
    parts.append(Q)
con.close()
Q=pd.concat(parts,ignore_index=True).sort_values(['event_id','mkt','sel','minute','m'])
print(f"118 price rows {len(Q)} {time.time()-T0:.0f}s",flush=True)
PQ={k:(v.minute.values,v.ltp.values) for k,v in Q.groupby(['event_id','mkt','sel'])}
SK=Counter()
for r in GG.itertuples():
    goals=GL.get(int(r.fixture_id),[]); Lv=LS[r.fixture_id]; tot=r.hg+r.ag
    grp=['ALLCTRL']+(['HIGH'] if Lv>=hi else ['LOW'] if Lv<=lo else [])
    for Tm in (70,75,80):
        for sel in ('OVER','UNDER'):
            # the line depends on the score, so read the score from the earliest print on any line, per candidate line, and keep the line the score says is open
            for mk,ln,gs in (('OU15',1.5,(0,1)),('OU25',2.5,(2,)),('OU35',3.5,(3,))):
                z=PQ.get((r.event_id,mk,sel))
                if z is None: continue
                mm,pp=z; k=np.searchsorted(mm,Tm,side='left')
                if k>=len(mm) or mm[k]>Tm+4: continue
                pm=int(mm[k]); gv=guard(goals,pm)
                if gv is None: SK['goal at print, dropped']+=1; continue
                if gv not in gs: continue
                assert line_for(gv)==(mk,ln)
                won=(tot>ln) if sel=='OVER' else (tot<ln)
                for gp in grp:
                    for side,v in (('BACK',bk(pp[k],won)),('LAY',ly(pp[k],won))):
                        if v is None: SK['back at 1.01, no bet']+=1; continue
                        rows.append((118,f'T{Tm} G{gv} {sel}',gp,side,r.fixture_id,1 if r.season==2024 else 2,pp[k],won,v))
print("118 counts:",dict(SK),flush=True)
R=pd.DataFrame(rows,columns=['item','a','b','side','fx','h','x','won','v'])
def tb(k,x):
    l=line(x.v.values,x.h.values); tg=tstat(x.groupby('fx').v.sum().values)
    return dict(item=k[0],a=k[1],b=k[2],side=k[3],n=l['n'],games=x.fx.nunique(),per10=l['per10'],t=l['t'],t_game=tg,n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),imp=(1/x.x).mean(),maxwin=l['maxwin'],PASS=l['PASS'] and tg>=3.5)
O=pd.DataFrame([tb(k,x) for k,x in R.groupby(['item','a','b','side'])])
for it,x in O.groupby('item'):
    big=x[x.n>=300]
    print(f"\n== item {it}: lines {len(x)}, n>=300 {len(big)}, positive there {int((big.per10>0).sum())}, pass {int(x.PASS.sum())}. Top 15 by t, n>=150"); print(x[x.n>=150].sort_values('t',ascending=False).head(15).drop(columns=['n1','n2']).round(3).to_string(index=False))
    print("worst 4"); print(x[x.n>=150].sort_values('t').head(4).drop(columns=['n1','n2']).round(3).to_string(index=False))
print("\n== 118 HIGH v LOW v ALLCTRL by state, n and per10, BACK and LAY")
x=O[O.item==118]; print(x.pivot_table(index=['a','side'],columns='b',values=['n','per10']).round(3).to_string())
print("\n== 117 every line"); print(O[O.item==117].sort_values(['a','b','side']).drop(columns=['n1','n2']).round(3).to_string(index=False))
S=O[O.PASS]; print(f"\n== SURVIVORS: {len(S)} of {len(O)} (bar: n>=300, n>=150 per half, both halves > 0, t and t by game >= 3.5, mean >= +0.15, LTP upper bound)\n",S.round(3).to_string(index=False) if len(S) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
