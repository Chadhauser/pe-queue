#!/bin/bash
set -o pipefail
# 472 (Finder 2026-11-03, queue item 20): PRE-MATCH BAND SWEEP, every mapped league. af_price_map x bf_hist_price x af_fixtures.
# ENTRY: for each game and selection, the earliest REAL print in tape minutes 0..2 (ltp >= 1.01). The tape has no pre-kick-off rows and its minute-0 prints come
#   AFTER the af kick-off (census on 400 games: median +1.6 min, p95 +10.6, p99 +15.5), so this is a "just after kick-off" price, the nearest thing on the box.
# GUARDS: print more than 5 min before or 20 min after the af kick-off = suspected wrong mapping or rescheduled game, dropped blind to the result and counted. A goal
#   with af minute strictly BEFORE the print minute was known at the print, so that entry is not pre-match and is dropped. A goal in the SAME minute stays (dropping it is look-ahead).
# EXIT: hold to settle, on af_fixtures FT (FH15 on the af HT score). No early exit, so nothing can settle before the exit and nothing is dropped for that reason.
# COST: one tick adverse on the exact ladder, 2% commission on profit, £10 risk (back stake 10, lay liability 10). Halves: season 2024 v 2025.
# One entry per game per selection, so games in a cell are independent; across cells they are not. Bonferroni t printed for the number of cells tested.
# Leagues are keyed on league_id: 'Serie A' (Italy 135 / Brazil 71) and 'Bundesliga' (Germany 78 / Austria 218) are ambiguous by name.
# Table prematch_bands_v1 holds the full code x league x band x season table.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,warnings,psycopg2,psycopg2.extras,pandas as pd,numpy as np
from functools import lru_cache
from statistics import NormalDist
warnings.filterwarnings('ignore')
pd.set_option('display.width',240); pd.set_option('display.max_rows',400); pd.set_option('display.max_columns',40)
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LADA=np.array(LAD)
@lru_cache(maxsize=None)
def dn(p,k=1): return float(LADA[max(int(np.searchsorted(LADA,round(p,2)-1e-9))-k,0)])
@lru_cache(maxsize=None)
def up(p,k=1): return float(LADA[min(int(np.searchsorted(LADA,round(p,2)-1e-9))+k,len(LADA)-1)])
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
    if mkt=='MO': return (hg>ag) if sel=='HOME' else (hg<ag) if sel=='AWAY' else hg==ag
    if mkt=='BTTS': return (hg>0 and ag>0)==(sel=='YES')
    if mkt=='FH15': return (hh+ha>1.5)==(sel=='OVER')
    return (hg+ag>LINE[mkt])==(sel=='OVER')
def tstat(v):
    v=np.asarray(v,dtype=float); n=len(v)
    if n<2: return 0.0
    sd=v.std(ddof=1)
    return float(v.mean()/(sd/np.sqrt(n))) if sd>0 else 0.0
# known answers, worked by hand. Ladder edges:
assert dn(2.0)==1.99 and up(2.0)==2.02 and up(1.99)==2.0 and dn(1.01)==1.01 and dn(3.0)==2.98 and up(3.0)==3.05 and up(2.0,3)==2.06 and dn(4.0,3)==3.85
# back 2.0 fills 1.99: win 10*.99*.98 = 9.702; lose -10. Back 1.02 fills 1.01: no bet.
assert abs(pnl('B',2.0,True)-9.702)<1e-9 and pnl('B',2.0,False)==-10.0 and pnl('B',1.02,True) is None
# lay 3.0 fills 3.05, stake 10/2.05 = 4.878049: selection loses +4.780488 after 2%; selection wins = exactly the £10 liability
assert abs(pnl('L',3.0,False)-10/2.05*0.98)<1e-9 and pnl('L',3.0,True)==-10.0
# bands: edges fall in the upper band; 10 and above lump together
assert band(3.0)=='3.00-3.25' and band(3.24)=='3.00-3.25' and band(3.25)=='3.25-3.50' and band(9.99)=='9.75-10.00' and band(10.0)=='10+' and band(1.01)=='1.00-1.25'
# results: 0-0 edge, exact line edges, BTTS, FH15 on the HT score only
assert won('MO','DRAW',0,0,0,0) and won('OU25','UNDER',1,1,0,0) and won('OU25','OVER',2,1,0,0) and not won('OU35','OVER',2,1,0,0) and won('OU15','OVER',1,1,0,0)
assert won('BTTS','NO',0,0,0,0) and not won('BTTS','YES',2,0,0,0) and won('BTTS','YES',1,1,0,0) and won('FH15','OVER',5,0,1,1) and not won('FH15','OVER',5,0,1,0)
# t: [1,3] mean 2, sd sqrt2, se 1, t 2
assert abs(tstat([1,3])-2.0)<1e-9 and tstat([1,1])==0.0
print("known-answer checks: OK",flush=True)

con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.league_id,f.league,f.season,f.kickoff,f.hg,f.ag,f.ht_hg,f.ht_ag FROM af_price_map m
  JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.ht_hg IS NOT NULL""",con)
print("games",len(G),"seasons",G.season.value_counts().to_dict(),flush=True)
EV=pd.read_sql("""SELECT fixture_id,min(minute) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND coalesce(minute,0)<=2 GROUP BY 1""",con,params=(list(map(int,G.fixture_id)),))
first_goal=dict(zip(EV.fixture_id,EV.gm))
MK=('MO','OU15','OU25','OU35','BTTS','FH15')
parts=[]; neg=0
for i in range(0,len(G),1500):
    ids=list(G.event_id.iloc[i:i+1500])
    P=pd.read_sql("SELECT event_id,mkt,sel,minute,m,ltp::float ltp,country FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt=ANY(%s) AND minute<=2 AND ltp>=1.01 AND ltp<1000",con,params=(ids,list(MK)))
    neg+=int((P.minute<0).sum())
    P=P[P.minute>=0].sort_values(['event_id','mkt','sel','minute','m']).drop_duplicates(['event_id','mkt','sel'])
    parts.append(P); print(f"  {min(i+1500,len(G))}/{len(G)} rows {len(P)}",flush=True)
P=pd.concat(parts,ignore_index=True)
print(f"rows with tape minute < 0 in the whole mapped set: {neg}",flush=True)
P=P.merge(G,on='event_id')
P['lag']=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True)).dt.total_seconds()/60
print("print lag v af kick-off, min:",P.lag.describe(percentiles=[.01,.5,.95,.99]).round(1).to_dict(),flush=True)
print(f"prints with lag<0: {int((P.lag<0).sum())} of {len(P)}; of those within -5..0: {int(((P.lag<0)&(P.lag>=-5)).sum())}",flush=True)
n0=len(P); g0=P.event_id.nunique(); badlag=(P.lag<-5)|(P.lag>20); P=P[~badlag]
print(f"games with no print at all in minutes 0..2: {len(G)-g0}. Dropped, lag outside -5..+20: {int(badlag.sum())} of {n0} prints, {g0-P.event_id.nunique()} games lost entirely by this guard",flush=True)
gm=P.fixture_id.map(first_goal); known=gm.notna()&(gm<P.minute); P=P[~known]
print(f"dropped, goal known before the print: {int(known.sum())} prints",flush=True)
print("league_id x country check:",P[P.mkt=='MO'].drop_duplicates('event_id').groupby(['league_id','league']).country.agg(lambda s:s.value_counts().index[0]).to_dict(),flush=True)
print("games with a print, by market/sel:",P.groupby(['mkt','sel']).event_id.nunique().to_dict(),flush=True)
# favourite = shorter of HOME/AWAY first prints; equal prices skipped
W=P[P.mkt=='MO'].pivot_table(index='event_id',columns='sel',values='ltp',aggfunc='first')
favsel=np.where(W.HOME<W.AWAY,'HOME',np.where(W.AWAY<W.HOME,'AWAY',None)); FAV=dict(zip(W.index,favsel))
HP=W.HOME.to_dict()
SPEC=[('MO','DRAW','L'),('MO','HOME','L'),('MO','AWAY','L'),('MO','DRAW','B'),('MO','HOME','B'),('MO','AWAY','B'),
      ('OU15','OVER','B'),('OU15','UNDER','B'),('OU25','OVER','B'),('OU25','UNDER','B'),('OU35','OVER','B'),('OU35','UNDER','B'),('BTTS','YES','B'),('BTTS','NO','B'),('FH15','OVER','B')]
rows=[]
for r in P.itertuples():
    w=won(r.mkt,r.sel,r.hg,r.ag,r.ht_hg,r.ht_ag)
    for side in ('B','L'):
        codes=[f"{r.mkt}_{r.sel}_{side}"] if (r.mkt,r.sel,side) in SPEC else []
        if r.mkt=='MO' and FAV.get(r.event_id)==r.sel: codes.append(f"FAV_{side}")
        for code in codes:
            x=pnl(side,r.ltp,w)
            if x is None: continue
            x3=pnl(side,r.ltp,w,3)
            rows.append((code,r.event_id,r.league_id,r.league,r.season,r.ltp,band(r.ltp),r.lag,w,x,x3 if x3 is not None else np.nan))
T=pd.DataFrame(rows,columns=['code','event_id','league_id','league','season','p','band','lag','won','x','x3'])
assert not T.duplicated(['code','event_id']).any()
T['lg']=T.league_id.astype(str)+' '+T.league
print("trades",len(T),"games",T.event_id.nunique(),"of",len(G),flush=True)
print("share of prints by lag: <=3 min {:.3f}, 3-6 {:.3f}, >6 {:.3f}".format((T.lag<=3).mean(),((T.lag>3)&(T.lag<=6)).mean(),(T.lag>6).mean()),flush=True)
def summ(d):
    a=d[d.season==2024].x; c=d[d.season==2025].x; e=d[d.lag<=5].x
    return dict(n=len(d),games=d.event_id.nunique(),sel_won=round(d.won.mean(),3),mean=d.x.mean(),t=tstat(d.x),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(c),h2=c.mean() if len(c) else np.nan,
                t3=d.x3.mean(),lag5=e.mean() if len(e) else np.nan,n5=len(e))
LV={'ALL':['code'],'BAND':['code','band'],'LEAGUE':['code','lg'],'LEAGUE_BAND':['code','lg','band']}
out=[]
for lv,keys in LV.items():
    for k,d in T.groupby(keys):
        k=k if isinstance(k,tuple) else (k,)
        out.append(dict(level=lv,cell=' | '.join(map(str,k)),**summ(d)))
R=pd.DataFrame(out)
R['PASS']=(R.n>=300)&(R.n1>=150)&(R.n2>=150)&(R.h1>0)&(R.h2>0)&(R.t>=3.5)&(R['mean']>=0.15)
E=R[R.n>=300]; ncell=len(E); bonf=NormalDist().inv_cdf(1-0.05/max(ncell,1))
print(f"\n== cells: {len(R)} total, {ncell} at n>=300 (one-sided Bonferroni 5% t = {bonf:.2f})",flush=True)
print("cells at n>=300 by level:",E.level.value_counts().to_dict())
print("\n== ALL codes\n",R[R.level=='ALL'].drop(columns=['level','PASS']).round(3).to_string(index=False))
print("\n== BAND level, n>=300, every band (the all-league band table)\n",R[(R.level=='BAND')&(R.n>=300)].drop(columns=['level','PASS']).round(3).to_string(index=False))
print("\n== top 15 by t, n>=300\n",E.sort_values('t',ascending=False).head(15).drop(columns=['games']).round(3).to_string(index=False))
print("\n== top 15 LEAGUE_BAND by t, n>=100 (below the sample test, for leads only)\n",R[(R.level=='LEAGUE_BAND')&(R.n>=100)].sort_values('t',ascending=False).head(15).drop(columns=['games','level']).round(3).to_string(index=False))
# ---- named strategies
LOWER=[40,41,42,136,79,62,141]
def code(c): return T[T.code==c]
def line(name,d,claim=''):
    if len(d)==0: print(f"{name}: no games"); return
    s=summ(d); ok=s['n']>=300 and s['n1']>=150 and s['n2']>=150 and s['h1']>0 and s['h2']>0 and s['t']>=3.5 and s['mean']>=0.15
    print(f"{name}: n {s['n']} sel_won {s['sel_won']} per£10 {s['mean']:+.2f} t {s['t']:.2f} h1 {s['h1']:+.2f} (n {s['n1']}) h2 {s['h2']:+.2f} (n {s['n2']}) | +2 ticks {s['t3']:+.2f} | lag<=5 {s['lag5']:+.2f} | claim {claim or 'n/a'} | {'PASS' if ok else 'fail'}")
print("\n== NAMED STRATEGIES")
dl=code('MO_DRAW_L'); hl=code('MO_HOME_L')
line("S7 Championship lay draw 3.0-3.5",dl[(dl.league_id==40)&(dl.p>=3.0)&(dl.p<=3.5)],"10.1% ROI")
line("S8 Primeira Liga lay draw >=5.5",dl[(dl.league_id==94)&(dl.p>=5.5)],"47.8% ROI")
line("S8 all mapped leagues lay draw >=5.5",dl[dl.p>=5.5])
print("S8 Czech: no Czech league in af_price_map (19 mapped leagues), not testable on settled results here")
line("S9 Serie A (Italy) lay home >=4.0",hl[(hl.league_id==135)&(hl.p>=4.0)],"34% ROI")
line("S9 all mapped leagues lay home >=4.0",hl[hl.p>=4.0])
line("S16 lower leagues lay home >=4.0",hl[hl.league_id.isin(LOWER)&(hl.p>=4.0)])
La=T[T.league_id==140]
line("S17 proxy La Liga back UNDER 2.5",La[La.code=='OU25_UNDER_B'],"18% ROI (on the CS dutch)")
line("S17 proxy La Liga back BTTS NO",La[La.code=='BTTS_NO_B'])
g=G[G.league_id==140]; hit=(((g.hg==0)&(g.ag==0))|((g.hg==0)&(g.ag==1))|((g.hg==1)&(g.ag==1)))
print(f"S17 outcome rate La Liga 0-0/0-1/1-1: {hit.mean():.4f} of {len(g)}, so the CS dutch needs a combined price > {1/hit.mean():.3f} before cost. No CS prices on the two-season tape, so the dutch itself is NOT tested")
fh=T[(T.code=='FH15_OVER_B')&(T.league_id==39)].copy(); fh['hp']=fh.event_id.map(HP)
line("S18 Premier League back FH O1.5, home >=3.15",fh[fh.hp>=3.15],"13.7% ROI")
line("S18 same with FH O1.5 <=3.30 (job 228's filter)",fh[(fh.hp>=3.15)&(fh.p<=3.30)])
print("\nCLOSING-LINE TEST: not available. bf_hist_price has no rows with tape minute < 0 and almost no print before the af kick-off (counts above); a -60 min price needs the Betfair files or a forward recorder.")
Tb=T.groupby(['code','league_id','league','band','season']).agg(n=('x','size'),s=('x','sum'),ss=('x',lambda v:float((v*v).sum()))).reset_index()
cur.execute("DROP TABLE IF EXISTS prematch_bands_v1; CREATE TABLE prematch_bands_v1 (code TEXT, league_id INT, league TEXT, band TEXT, season INT, n INT, s DOUBLE PRECISION, ss DOUBLE PRECISION)")
psycopg2.extras.execute_values(cur,"INSERT INTO prematch_bands_v1 VALUES %s",[(a,int(b),c,d,int(e),int(f),float(g_),float(h)) for a,b,c,d,e,f,g_,h in Tb.itertuples(index=False)],page_size=5000)
print(f"stored prematch_bands_v1: {len(Tb)} rows, {int(Tb.n.sum())} trades (must equal {len(T)})")
assert int(Tb.n.sum())==len(T)
gl=G.groupby(['league_id','league']).event_id.nunique().rename('mapped').to_frame().join(T.groupby(['league_id','league']).event_id.nunique().rename('traded')).fillna(0).astype(int)
gl['lag_median']=T.groupby(['league_id','league']).lag.median().round(1)
print("\n== games by league: mapped v traded, median print lag\n",gl.to_string())
# same pass test on prints within 5 min of the af kick-off only (MLS mostly falls out: its prints land later than that)
T5=T[T.lag<=5]; p5=0; c5=0
for lv,keys in LV.items():
    for k,d in T5.groupby(keys):
        if len(d)<300: continue
        c5+=1; s=summ(d)
        if s['n1']>=150 and s['n2']>=150 and s['h1']>0 and s['h2']>0 and s['t']>=3.5 and s['mean']>=0.15:
            p5+=1; print("lag<=5 pass:",lv,k,round(s['mean'],3),round(s['t'],2),s['n'])
print(f"lag<=5 sensitivity: {p5} passes of {c5} cells at n>=300")
S=R[R.PASS].sort_values('t',ascending=False)
print(f"\n== SURVIVORS: {len(S)} of {ncell} cells at n>=300; expected false passes are not zero, so read t against Bonferroni {bonf:.2f}")
print(S.drop(columns=['PASS']).round(3).to_string(index=False) if len(S) else "none")
PY
