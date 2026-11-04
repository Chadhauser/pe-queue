#!/bin/bash
set -o pipefail
# 491 (Finder 2026-11-04, queue item 35): LAY THE OVERBACKED SIDE AT KICK-OFF. af_price_map x bf_hist_price x af_fixtures. Same entry and guards as job 472.
# ENTRY: earliest real print in tape minutes 0..2 (ltp >= 1.01). The tape has no pre-kick-off rows; prints land just after kick-off. Lag outside -5..+20 min v the af kick-off = dropped, blind to the result, counted. A goal with af minute strictly before the print minute = dropped; same minute stays.
# TRADE: LAY every BTTS / OU15 / OU25 / OU35 / FH15 selection, one tick adverse, £10 liability, 2% commission, hold to settle on af_fixtures FT (FH15 on the HT score). x3 = three ticks adverse. Back lines are shown beside them for scale.
# LIQUIDITY: does a print exist at all? For BTTS, outcome rate in games with and without a NO print. On liq_sample, the real lay and back touch at minutes 0..2 v ltp, since an LTP lay is not a fill; the two-season tape holds no touch, so any pass here is an upper bound.
# Halves: season 2024 v 2025. One entry per game per selection. No tables written. x110 = mean without entries under 1.10, where a lay wins many times its liability; max_win = the largest single trade.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,warnings,psycopg2,pandas as pd,numpy as np
from functools import lru_cache
from statistics import NormalDist
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
def dn(p,k=1): return float(LADA[max(pos(p)-k,0)])
@lru_cache(maxsize=None)
def up(p,k=1): return float(LADA[min(pos(p)+k,len(LADA)-1)])
def pnl(side,p,won,k=1):
    if side=='B':
        a=dn(p,k)
        if a<=1.01: return None
        r=10*(a-1) if won else -10.0
    else:
        a=up(p,k); r=-10.0 if won else 10/(a-1)
    return r*0.98 if r>0 else r
def band(p):
    if p>=10: return '10+'
    lo=int((p+1e-9)*4)/4
    return f"{lo:.2f}-{lo+0.25:.2f}"
LINE={'OU15':1.5,'OU25':2.5,'OU35':3.5}
def won(mkt,sel,hg,ag,hh,ha):
    if mkt=='BTTS': return (hg>0 and ag>0)==(sel=='YES')
    if mkt=='FH15': return (hh+ha>1.5)==(sel=='OVER')
    return (hg+ag>LINE[mkt])==(sel=='OVER')
def tstat(v):
    v=np.asarray(v,dtype=float); n=len(v)
    if n<2: return 0.0
    sd=v.std(ddof=1)
    return float(v.mean()/(sd/np.sqrt(n))) if sd>0 else 0.0
# known answers, worked by hand
assert dn(2.0)==1.99 and up(2.0)==2.02 and up(1.99)==2.0 and up(3.0)==3.05 and up(2.0,3)==2.06
assert abs(pnl('L',3.0,False)-10/2.05*0.98)<1e-9 and pnl('L',3.0,True)==-10.0                              # lay 3.0 fills 3.05: wins 10/2.05 less 2%, loses the £10 liability
assert abs(pnl('L',1.01,False)-10/0.02*0.98)<1e-6                                                         # lay 1.01 fills 1.02, stake £500, wins £490 on £10 liability: why x110 is shown
assert abs(pnl('B',2.0,True)-9.702)<1e-9 and pnl('B',2.0,False)==-10.0 and pnl('B',1.02,True) is None
assert won('BTTS','NO',0,0,0,0) and not won('BTTS','NO',1,1,0,0) and won('BTTS','NO',2,0,0,0) and won('BTTS','YES',1,1,0,0)
assert won('OU25','UNDER',1,1,0,0) and won('OU25','OVER',2,1,0,0) and not won('OU35','OVER',2,1,0,0) and won('OU15','OVER',1,1,0,0)
assert won('FH15','OVER',5,0,1,1) and not won('FH15','OVER',5,0,1,0)                                       # FH15 reads the HT score only
assert band(3.24)=='3.00-3.25' and band(3.25)=='3.25-3.50' and band(10.0)=='10+' and abs(tstat([1,3])-2.0)<1e-9
print("known-answer checks: OK",flush=True)

con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.league_id,f.league,f.season,f.kickoff,f.hg,f.ag,f.ht_hg,f.ht_ag FROM af_price_map m
  JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.ht_hg IS NOT NULL""",con)
print("games",len(G),"seasons",G.season.value_counts().to_dict(),flush=True)
EV=pd.read_sql("""SELECT fixture_id,min(minute) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND coalesce(minute,0)<=2 GROUP BY 1""",con,params=(list(map(int,G.fixture_id)),))
first_goal=dict(zip(EV.fixture_id,EV.gm))
MK=['OU15','OU25','OU35','BTTS','FH15']; parts=[]
for i in range(0,len(G),1500):
    ids=list(G.event_id.iloc[i:i+1500])
    P=pd.read_sql("SELECT event_id,mkt,sel,minute,m,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt=ANY(%s) AND minute>=0 AND minute<=2 AND ltp>=1.01 AND ltp<1000",con,params=(ids,MK))
    parts.append(P.sort_values(['event_id','mkt','sel','minute','m']).drop_duplicates(['event_id','mkt','sel'])); print(f"  {min(i+1500,len(G))}/{len(G)} rows {len(parts[-1])}",flush=True)
P=pd.concat(parts,ignore_index=True).merge(G,on='event_id')
P['lag']=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True)).dt.total_seconds()/60
bad=(P.lag<-5)|(P.lag>20); print(f"dropped, lag outside -5..+20: {int(bad.sum())} of {len(P)}",flush=True); P=P[~bad]
gm=P.fixture_id.map(first_goal); kn=gm.notna()&(gm<P.minute); print(f"dropped, goal known before the print: {int(kn.sum())}",flush=True); P=P[~kn]
print("games with a print:",P.groupby(['mkt','sel']).event_id.nunique().to_dict(),flush=True)
print("ltp 1.01-1.05 share of lay entries, by mkt/sel:",P.assign(low=P.ltp<=1.05).groupby(['mkt','sel']).low.mean().round(4).to_dict(),flush=True)
rows=[]
for r in P.itertuples():
    w=bool(won(r.mkt,r.sel,r.hg,r.ag,r.ht_hg,r.ht_ag))
    for side in 'LB':
        x=pnl(side,r.ltp,w)
        if x is None: continue
        x3=pnl(side,r.ltp,w,3)
        rows.append((f"{r.mkt}_{r.sel}_{side}",side,r.event_id,f"{r.league_id} {r.league}",r.season,r.ltp,band(r.ltp),r.lag,w,x,x3 if x3 is not None else np.nan))
T=pd.DataFrame(rows,columns=['code','side','event_id','lg','season','p','band','lag','won','x','x3'])
assert not T.duplicated(['code','event_id']).any()
print("trades",len(T),"games",T.event_id.nunique(),"of",len(G),flush=True)
def summ(d):
    a=d[d.season==2024].x; c=d[d.season==2025].x; e=d[d.lag<=5].x
    return dict(n=len(d),games=d.event_id.nunique(),sel_won=d.won.mean(),px=d.p.median(),mean=d.x.mean(),t=tstat(d.x),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(c),h2=c.mean() if len(c) else np.nan,x3=d.x3.mean(),lag5=e.mean() if len(e) else np.nan,x110=d[d.p>=1.10].x.mean() if (d.p>=1.10).any() else np.nan,max_win=d.x.max())
out=[]
for lv,keys in {'ALL':['code'],'BAND':['code','band'],'LEAGUE':['code','lg'],'LEAGUE_BAND':['code','lg','band']}.items():
    for k,d in T[T.side=='L'].groupby(keys) if lv!='ALL' else T.groupby(keys):
        k=k if isinstance(k,tuple) else (k,)
        out.append(dict(level=lv,side=k[0][-1],cell=' | '.join(map(str,k)),**summ(d)))
R=pd.DataFrame(out)
R['PASS']=(R.side=='L')&(R.n>=300)&(R.n1>=150)&(R.n2>=150)&(R.h1>0)&(R.h2>0)&(R.t>=3.5)&(R['mean']>=0.15)
E=R[(R.n>=300)&(R.side=='L')]; bonf=NormalDist().inv_cdf(1-0.05/max(len(E),1))
print(f"\n== lay cells {len(R[R.side=='L'])}, at n>=300: {len(E)} (one-sided Bonferroni 5% t = {bonf:.2f})")
print("\n== ALL selections, back and lay\n",R[R.level=='ALL'].drop(columns=['level','side','PASS']).round(3).to_string(index=False))
print("\n== top 15 lay cells by t, n>=300\n",E.sort_values('t',ascending=False).head(15).drop(columns=['side']).round(3).to_string(index=False))
# print exists as a proxy for liquidity
pb=set(P[(P.mkt=='BTTS')&(P.sel=='NO')].event_id); py=set(P[(P.mkt=='BTTS')&(P.sel=='YES')].event_id); gg=G.assign(btts_no=~((G.hg>0)&(G.ag>0)),has_no=G.event_id.isin(pb),has_yes=G.event_id.isin(py))
print("\n== BTTS print v outcome\n",gg.groupby(['has_no','has_yes']).agg(games=('btts_no','size'),btts_no_rate=('btts_no','mean')).round(3).to_string(),flush=True)
print("BTTS NO print, by season:",gg.groupby('season').has_no.mean().round(3).to_dict())
# real touch v ltp, recorder only
L=pd.read_sql("""SELECT DISTINCT ON (market_id,sel) market_id,mkt,sel,minute,ltp::float ltp,back_px::float bp,back_sz::float bs,lay_px::float lp,lay_sz::float ls FROM liq_sample
   WHERE ts>=now()-interval '14 days' AND mkt=ANY(%s) AND minute>=0 AND minute<=2 AND ltp IS NOT NULL ORDER BY market_id,sel,ts""",con,params=(MK,))
print("\nliq_sample first sample, markets:",L.groupby('mkt').market_id.nunique().to_dict(),"sels:",L.sel.drop_duplicates().head(14).tolist())
if len(L):
    L['has_lay']=L.lp.notna()&(L.lp<1000); V=L[L.has_lay&(L.ltp>=1.01)].copy()
    V['gap']=[pos(a)-pos(b) for a,b in zip(V.lp,V.ltp)]; V['spr']=[pos(a)-pos(b) if pd.notna(b) and b>1 else np.nan for a,b in zip(V.lp,V.bp)]; V['sz']=V.ls>=10/(V.lp-1)
    print("== real lay touch v ltp, ticks: gap = lay_px above ltp (one tick is what the tape line charges beyond ltp+0)\n",V.groupby(['mkt','sel']).agg(n=('gap','size'),gap_med=('gap','median'),gap_mean=('gap','mean'),gap_p90=('gap',lambda s:s.quantile(.9)),spread_med=('spr','median'),size_ok=('sz','mean')).round(2).to_string())
    print("share with a real lay under 1000:",L.groupby('mkt').has_lay.mean().round(3).to_dict())
S=R[R.PASS].sort_values('t',ascending=False)
print(f"\n== SURVIVORS: {len(S)} of {len(E)} lay cells at n>=300 (LTP-based, upper bound; read t against Bonferroni {bonf:.2f})")
print(S.drop(columns=['PASS','side']).round(3).to_string(index=False) if len(S) else "none")
PY
