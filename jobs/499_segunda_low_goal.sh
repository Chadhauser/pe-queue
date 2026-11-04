#!/bin/bash
set -o pipefail
# 499 (Finder 2026-11-04, queue item 45): SEGUNDA DIVISION, IS THE LOW-GOAL SIDE OVERPRICED AT KICK-OFF? af_price_map x bf_hist_price x af_fixtures. Entry and guards copied from job 491 so its lines reproduce.
# ENTRY: earliest real print in tape minutes 0..2 (ltp >= 1.01). Lag outside -5..+20 min v the af kick-off = dropped, counted. A goal with af minute strictly before the print minute = dropped; same minute stays.
# TRADE: lay BTTS No, Under 2.5, Under 3.5, one tick adverse, £10 liability, 2% commission, hold to settle on the FT score. x3 = three ticks adverse.
# ONE BET PER GAME (the item): ONE_AVG = mean of the lines that printed in that game, no line chosen. ONE_U25 = U2.5, else BTTS No, else U3.5 (U2.5 first as it has the most prints and was not the best line in 491). ONE_BTTS = BTTS No first, shown as it is the line selected as best in 491, so it carries that selection.
# CONTROLS: the other second tiers on the box: Championship, Ligue 2, 2. Bundesliga, Serie B (ids 40, 62, 79, 136; names checked below). Halves: season 2024 v 2025.
# GOALS v IMPLIED: where UNDER and OVER 2.5 both print, p = (1/u)/(1/u+1/o), removing the overround. Implied total = the Poisson mean giving that p. Football goals are not exactly Poisson, so read league v league, not the level.
# FORWARD: Segunda on liq_sample since 27 Oct at the real lay touch, results from goal_timeline's last row at 85'+ (it has no FT status). A handful of games at most: read the touch cost, not the P&L. liq_sample has no index, so this is one filtered scan, last, and a failure does not lose the tape result.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,warnings,psycopg2,pandas as pd,numpy as np
from functools import lru_cache
warnings.filterwarnings('ignore')
pd.set_option('display.width',240); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',40)
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LADA=np.array(LAD)
def pos(p): return int(np.searchsorted(LADA,round(float(p),2)-1e-9))
@lru_cache(maxsize=None)
def up(p,k=1): return float(LADA[min(pos(p)+k,len(LADA)-1)])
def lay(p,won,k=1):
    a=up(p,k); return -10.0 if won else 10/(a-1)*0.98
def won(line,hg,ag):
    if line=='BTTS_NO': return not (hg>0 and ag>0)
    if line=='U25': return hg+ag<2.5
    if line=='U35': return hg+ag<3.5
    raise ValueError(line)
GRID=np.arange(0.3,7.0,0.005); PU=np.exp(-GRID)*(1+GRID+GRID**2/2)   # P(N<=2), falling in lambda
def implied_total(p): return float(np.interp(-p,-PU,GRID))
def one_bet(d,order):
    """d: line -> pnl for one game. First line in order that printed, or None."""
    for x in order:
        if x in d: return d[x]
    return None
def tstat(v):
    v=np.asarray(v,dtype=float); n=len(v)
    if n<2: return 0.0
    sd=v.std(ddof=1)
    return float(v.mean()/(sd/np.sqrt(n))) if sd>0 else 0.0
def z_of(under,p):
    """Actual v priced wins: (wins - expected) / sqrt(sum p(1-p))."""
    under=np.asarray(under,dtype=float); p=np.asarray(p,dtype=float)
    return float((under.sum()-p.sum())/np.sqrt((p*(1-p)).sum()))
def final_row(status,minute):
    """goal_timeline never records FT, so the last row stands for the result only if it is at 85' or later in 2H or ET."""
    return status in ('2H','ET') and minute is not None and minute>=85
def toks(s): return {w for w in re.sub(r'[^a-z ]','',s.lower().replace('é','e').replace('ó','o').replace('á','a').replace('í','i').replace('ñ','n').replace('ú','u')).split() if len(w)>2 and w not in ('real','club','deportivo','union','cultural','racing','sporting','and')}
# known answers, worked by hand
assert up(2.0)==2.02 and up(1.99)==2.0 and up(3.0)==3.05 and up(2.0,3)==2.06
assert abs(lay(3.0,False)-10/2.05*0.98)<1e-9 and lay(3.0,True)==-10.0 and abs(lay(1.01,False)-490.0)<1e-6
assert won('BTTS_NO',2,0) and not won('BTTS_NO',1,1) and won('BTTS_NO',0,0) and won('U25',1,1) and not won('U25',2,1) and won('U35',2,1) and not won('U35',2,2)
assert abs(np.exp(-2.5)*(1+2.5+3.125)-0.5438)<1e-3 and abs(implied_total(0.5438)-2.5)<0.01 and implied_total(0.7)<implied_total(0.4)
assert one_bet({'U25':1,'U35':2},['BTTS_NO','U25','U35'])==1 and one_bet({'U35':2},['U25','BTTS_NO','U35'])==2 and one_bet({},['U25']) is None
assert abs(z_of([1]*60+[0]*40,[0.5]*100)-2.0)<1e-9
assert final_row('2H',90) and final_row('ET',120) and final_row('2H',85) and not final_row('2H',84) and not final_row('HT',45) and not final_row('2H',None)
assert abs(tstat([1,3])-2.0)<1e-9 and {'alcorcon'}==toks('Alcorcón') and 'gijon' in toks('Sporting Gijón')
print("known-answer checks: OK",flush=True)

LG={141:'Segunda División',40:'Championship',62:'Ligue 2',79:'2. Bundesliga',136:'Serie B'}
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.league_id,f.league,f.season,f.kickoff,f.hg,f.ag FROM af_price_map m
  JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.ht_hg IS NOT NULL AND f.league_id=ANY(%s)""",con,params=(list(LG),))
assert all(G[G.league_id==k].league.eq(v).all() for k,v in LG.items()),"league id does not match its name"
print("games",G.groupby(['league','season']).size().to_dict(),flush=True)
EV=pd.read_sql("""SELECT fixture_id,min(minute) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND coalesce(minute,0)<=2 GROUP BY 1""",con,params=(list(map(int,G.fixture_id)),))
first_goal=dict(zip(EV.fixture_id,EV.gm)); parts=[]
for i in range(0,len(G),800):
    ids=list(G.event_id.iloc[i:i+800])
    P=pd.read_sql("SELECT event_id,mkt,sel,minute,m,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt IN ('OU25','OU35','BTTS') AND minute>=0 AND minute<=2 AND ltp>=1.01 AND ltp<1000",con,params=(ids,))
    parts.append(P.sort_values(['event_id','mkt','sel','minute','m']).drop_duplicates(['event_id','mkt','sel'])); print(f"  {min(i+800,len(G))}/{len(G)} rows {len(parts[-1])}",flush=True)
P=pd.concat(parts,ignore_index=True).merge(G,on='event_id')
P['lag']=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True)).dt.total_seconds()/60
bad=(P.lag<-5)|(P.lag>20); print(f"dropped, lag outside -5..+20: {int(bad.sum())} of {len(P)}",flush=True); P=P[~bad]
gm=P.fixture_id.map(first_goal); kn=gm.notna()&(gm<P.minute); print(f"dropped, goal known before the print: {int(kn.sum())}",flush=True); P=P[~kn]
CODE={('BTTS','NO'):'BTTS_NO',('OU25','UNDER'):'U25',('OU35','UNDER'):'U35'}
rows=[]
for r in P.itertuples():
    c=CODE.get((r.mkt,r.sel))
    if c: w=bool(won(c,r.hg,r.ag)); rows.append((c,r.event_id,r.league,r.season,r.kickoff,r.ltp,lay(r.ltp,w),lay(r.ltp,w,3)))
T=pd.DataFrame(rows,columns=['line','event_id','league','season','kickoff','p','x','x3'])
assert not T.duplicated(['line','event_id']).any()
ORD={'ONE_U25':['U25','BTTS_NO','U35'],'ONE_BTTS':['BTTS_NO','U25','U35']}
one=[]
for (ev,lgn,sn),g in T.groupby(['event_id','league','season'],sort=False):
    dx=dict(zip(g.line,g.x)); d3=dict(zip(g.line,g.x3))
    one.append(('ONE_AVG',ev,lgn,sn,g.kickoff.iloc[0],g.p.mean(),g.x.mean(),g.x3.mean()))
    for nm,o in ORD.items(): one.append((nm,ev,lgn,sn,g.kickoff.iloc[0],g.p.mean(),one_bet(dx,o),one_bet(d3,o)))
A=pd.concat([T,pd.DataFrame(one,columns=T.columns)],ignore_index=True)
out=[]
for (lgn,ln),d in A.groupby(['league','line']):
    a=d[d.season==2024].x; c=d[d.season==2025].x; v=d.x; pp=d.p>=1.10
    r=dict(league=lgn,line=ln,n=len(v),games=d.event_id.nunique(),px=d.p.median(),per10=v.mean(),t=tstat(v),n1=len(a),h1=a.mean(),n2=len(c),h2=c.mean(),x3=d.x3.mean(),x110=d[pp].x.mean() if pp.any() else np.nan,max_win=v.max())
    r['PASS']=bool(r['n']>=300 and r['n1']>=150 and r['n2']>=150 and r['t']>=3.5 and r['h1']>0 and r['h2']>0 and r['per10']>=0.15)
    out.append(r)
R=pd.DataFrame(out).sort_values(['league','line'])
print("\n== LAY THE LOW-GOAL SIDE, per £10, league x line (one tick adverse; x3 = three ticks)\n",R.round(3).to_string(index=False))
chk=R[(R.league=='Segunda División')&(R.line=='BTTS_NO')].iloc[0]
print(f"\nreproduction of job 491, Segunda BTTS No: n {chk.n} (491: 355), per10 {chk.per10:.3f} (491: +1.598), t {chk.t:.2f} (491: 3.09), U2.5 and U3.5 in the table above (491: n 911 +0.746, n 723 +1.05)",flush=True)
# goals v implied
Q=P[P.mkt=='OU25'].pivot_table(index=['event_id','league','season','kickoff','hg','ag'],columns='sel',values='ltp').reset_index()
Q=Q.dropna(subset=['UNDER','OVER']); Q['p_under']=(1/Q.UNDER)/(1/Q.UNDER+1/Q.OVER); Q['goals']=Q.hg+Q.ag; Q['under']=(Q.goals<2.5).astype(float); Q['imp']=[implied_total(x) for x in Q.p_under]
def gv(d): return pd.Series(dict(games=len(d),goals=d.goals.mean(),implied=d.imp.mean(),under=d.under.mean(),imp_under=d.p_under.mean(),diff=d.under.mean()-d.p_under.mean(),z=z_of(d.under,d.p_under)))
print("\n== GOALS v IMPLIED TOTAL, OU25 first prints, both sides printed. diff<0 = Under won less often than priced\n",Q.groupby(['league','season']).apply(gv).round(3).to_string())
S=Q[Q.league=='Segunda División'].copy(); S['month']=pd.to_datetime(S.kickoff,utc=True).dt.strftime('%Y-%m')
print("\n== SEGUNDA by month\n",S.groupby('month').apply(gv).round(3).to_string(),flush=True)
# forward
try:
    L=pd.read_sql("""SELECT DISTINCT ON (market_id,sel) market_id,event_name,competition,ts,mkt,sel,minute,ltp::float ltp,lay_px::float lp,lay_sz::float ls FROM liq_sample
       WHERE ts>='2026-10-27' AND mkt IN ('BTTS','OU25','OU35') AND minute>=0 AND minute<=2 AND competition ILIKE '%%segunda%%' ORDER BY market_id,sel,ts""",con)
    print("\n== FORWARD liq_sample rows",len(L),"| competitions:",L.competition.value_counts().to_dict() if len(L) else {},flush=True)
    L=L[L.competition.fillna('').str.contains('Spanish|Spain',case=False,regex=True)&L.sel.isin(['NO','UNDER'])&L.lp.notna()&(L.lp>1)&(L.lp<1000)]
    Gt=pd.read_sql("""SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,score_home,score_away,status,minute,captured_at FROM goal_timeline WHERE league_id=141 AND captured_at>='2026-10-26' AND score_home IS NOT NULL ORDER BY fixture_id,captured_at DESC""",con)
    n_all=len(Gt); Gt=Gt[[final_row(a,None if pd.isna(b) else b) for a,b in zip(Gt.status,Gt.minute)]]; print(f"goal_timeline Segunda games {n_all}, last row at 85'+ {len(Gt)} (a proxy: goal_timeline has no FT status, so a later goal or a phantom one can mislabel)",flush=True); fw=[]; miss=0
    Tc=L[L.ltp.notna()&(L.ltp>=1.01)].copy(); Tc['gap']=[pos(a)-pos(b) for a,b in zip(Tc.lp,Tc.ltp)]; Tc['size_ok']=Tc.ls.fillna(0)>=10/(Tc.lp-1)
    print("real lay touch v ltp, ticks, whether or not a result matched:\n",Tc.groupby(['mkt','sel']).agg(n=('gap','size'),gap_med=('gap','median'),gap_mean=('gap','mean'),gap_max=('gap','max'),size_ok=('size_ok','mean')).round(2).to_string(),flush=True)
    for r in L.itertuples():
        h,_,a=r.event_name.partition(' v '); best=None
        for g in Gt.itertuples():
            if abs((pd.Timestamp(g.captured_at)-pd.Timestamp(r.ts)).total_seconds())<6*3600 and toks(h)&toks(g.home_team) and toks(a)&toks(g.away_team): best=g
        if best is None: miss+=1; continue
        c=CODE[(r.mkt,r.sel)]; w=bool(won(c,best.score_home,best.score_away))
        fw.append((c,r.event_name,r.ltp,r.lp,pos(r.lp)-pos(r.ltp) if pd.notna(r.ltp) and r.ltp>=1.01 else np.nan,r.ls>=10/(r.lp-1) if pd.notna(r.ls) else False,w,lay(r.lp,w)))
    print("forward rows unmatched to a result:",miss)
    if fw:
        F=pd.DataFrame(fw,columns=['line','event','ltp','lay_px','gap_ticks','size_ok','won','x'])
        print(F.groupby('line').agg(n=('x','size'),games=('event','nunique'),per10=('x','mean'),sel_won=('won','mean'),gap_med=('gap_ticks','median'),gap_mean=('gap_ticks','mean'),size_ok=('size_ok','mean')).round(3).to_string())
    else: print("no forward trades")
except Exception as e:
    print("FORWARD SECTION FAILED, tape result stands:",type(e).__name__,str(e)[:200],flush=True)
W=R[R.PASS]; print(f"\n== SURVIVORS: {len(W)} of {len(R)} lines (LTP-based, so an upper bound); Segunda one-bet lines are the test, others are controls"); print(W.round(3).to_string(index=False) if len(W) else "none")
PY
