#!/bin/bash
set -o pipefail
# 489_prematch (Finder 2026-11-04, queue item 50): PRE-MATCH CLOSING-LINE RESIDUALS. af_price_map x bf_hist_price x af_fixtures. 450-499 is full, so the number is shared.
# ENTRY and guards exactly as jobs/472: earliest real print in tape minutes 0..2, dropped if more than 5 min before or 20 min after the af kick-off, or if a goal with af minute before the print was known.
# The tape has NO pre-kick-off rows, and minute 0 is about +2 min after kick-off, so this is a just-after-kick-off price. "Line movement from first print to KO" and "does the pre-match move continue in-play" CANNOT be tested and are not.
# STATES known at the entry: league, day, kick-off hour, favourite band, MO overround band, Over 2.5 band, and league/hour/day x favourite. Favourite, overround and O2.5 come from the first prints of other selections, up to 2 tape minutes apart, as in 472.
# METHOD A cells: on season 2024 pick (selection, state, side) with n >= 100, mean > 0 after costs, t >= 2. Score on 2025 only: each cell, and all picks of one dimension together.
# METHOD B GBM per selection, fit on 2024, target outcome - 1/price; margin = predicted residual x price; back if >= 5/10/20%, lay if <= -that; score on 2025 only.
# COST one tick adverse, 2% commission, £10 risk, hold to settle. h1/h2 = 2025 split at its median kick-off. One entry per game per selection; lines across selections share games, tc = t on per-game means.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,warnings,psycopg2,pandas as pd,numpy as np
from functools import lru_cache
from scipy.stats import spearmanr,norm as ND
from sklearn.ensemble import HistGradientBoostingRegressor as HGR
warnings.filterwarnings('ignore')
pd.set_option('display.width',240); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',40)
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
T0=time.time()
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
        if a<=1.01: return np.nan
        r=10*(a-1) if won else -10.0
    else:
        a=up(p,k); r=-10.0 if won else 10/(a-1)
    return r*0.98 if r>0 else r
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
def passes(n,n1,n2,t,h1,h2,m): return bool(n>=300 and n1>=150 and n2>=150 and t>=3.5 and h1>0 and h2>0 and m>=0.15)
# known answers by hand. Back 2.0 fills 1.99: 9.702 / -10. Back 1.02 fills 1.01: no bet. Lay 3.0 fills 3.05, stake 10/2.05, +4.780488 / -10. Three ticks: back 4.0 -> 3.85.
assert abs(pnl('B',2.0,True)-9.702)<1e-9 and pnl('B',2.0,False)==-10.0 and np.isnan(pnl('B',1.02,True))
assert abs(pnl('L',3.0,False)-10/2.05*0.98)<1e-9 and pnl('L',3.0,True)==-10.0 and dn(4.0,3)==3.85 and up(2.0,3)==2.06
assert won('MO','DRAW',0,0,0,0) and won('OU25','UNDER',1,1,0,0) and won('OU25','OVER',2,1,0,0) and not won('OU35','OVER',2,1,0,0) and won('OU15','OVER',1,1,0,0)
assert won('BTTS','NO',0,0,0,0) and not won('BTTS','YES',2,0,0,0) and won('FH15','OVER',5,0,1,1) and not won('FH15','OVER',5,0,1,0)
assert abs(tstat([1,3])-2.0)<1e-9 and tstat([1,1])==0.0
assert passes(300,150,150,3.5,.01,.01,.15) and not passes(299,150,150,9,1,1,1) and not passes(300,149,151,9,1,1,1) and not passes(300,150,150,3.49,1,1,1) and not passes(300,150,150,9,0,1,1) and not passes(300,150,150,9,1,0,1) and not passes(300,150,150,9,1,1,.149)
print("known-answer checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'"); cur.execute("SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.league_id,f.league,f.season,f.kickoff,f.hg,f.ag,f.ht_hg,f.ht_ag FROM af_price_map m
  JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.ht_hg IS NOT NULL""",con)
print("games",len(G),"seasons",G.season.value_counts().to_dict(),flush=True)
EV=pd.read_sql("""SELECT fixture_id,min(minute) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND coalesce(minute,0)<=2 GROUP BY 1""",con,params=(list(map(int,G.fixture_id)),))
first_goal=dict(zip(EV.fixture_id,EV.gm))
MK=('MO','OU15','OU25','OU35','BTTS','FH15'); parts=[]
for i in range(0,len(G),1500):
    ids=list(G.event_id.iloc[i:i+1500])
    P=pd.read_sql("SELECT event_id,mkt,sel,minute,m,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt=ANY(%s) AND minute>=0 AND minute<=2 AND ltp>=1.01 AND ltp<1000",con,params=(ids,list(MK)))
    P=P.sort_values(['event_id','mkt','sel','minute','m']).drop_duplicates(['event_id','mkt','sel']); parts.append(P)
    print(f"  {min(i+1500,len(G))}/{len(G)} rows {len(P)} {time.time()-T0:.0f}s",flush=True)
con.close()
P=pd.concat(parts,ignore_index=True).merge(G,on='event_id')
P['lag']=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True)).dt.total_seconds()/60
bad=(P.lag<-5)|(P.lag>20); print(f"dropped, lag outside -5..+20: {int(bad.sum())} of {len(P)}",flush=True); P=P[~bad]
gm=P.fixture_id.map(first_goal); kn=gm.notna()&(gm<P.minute); print(f"dropped, goal known before the print: {int(kn.sum())}",flush=True); P=P[~kn]
P=P[~((P.mkt=='FH15')&(P.sel!='OVER'))&P.sel.isin(['HOME','AWAY','DRAW','OVER','UNDER','YES','NO'])].copy()
P['code']=P.mkt+'_'+P.sel
# game states from first prints
W=P.pivot_table(index='event_id',columns='code',values='ltp',aggfunc='first')
St=pd.DataFrame(index=W.index)
St['fav']=W[['MO_HOME','MO_AWAY']].min(axis=1); St['draw']=W['MO_DRAW']; St['or_mo']=1/W['MO_HOME']+1/W['MO_AWAY']+1/W['MO_DRAW']; St['o25']=W['OU25_OVER']; St['btts']=W['BTTS_YES']
Gm=G.set_index('event_id'); ko=pd.to_datetime(Gm.kickoff,utc=True)
St['league_id']=Gm.league_id; St['lg']=Gm.league_id.astype(str)+' '+Gm.league; St['season']=Gm.season; St['ko']=ko.dt.tz_localize(None)
St['dow']=St.ko.dt.day_name().str[:3]; St['hr']=St.ko.dt.hour
St['hrb']=pd.cut(St.hr,[-1,12,15,18,24],labels=['<=12','13-15','16-18','19+']).astype(str)
St['favb']=pd.cut(St.fav,[1,1.5,2,2.5,1000],labels=['<=1.5','1.5-2','2-2.5','2.5+']).astype(str)
St['orb']=pd.cut(St.or_mo,[0,0.99,1.01,1.03,1.06,100],labels=['<.99','.99-1.01','1.01-1.03','1.03-1.06','1.06+']).astype(str)
St['o25b']=pd.cut(St.o25,[1,1.6,1.9,2.2,1000],labels=['<=1.6','1.6-1.9','1.9-2.2','2.2+']).astype(str)
St['lg_fav']=St.lg+'|'+St.favb; St['hr_fav']=St.hrb+'|'+St.favb; St['dow_fav']=St.dow+'|'+St.favb
DIMS=['lg','dow','hrb','favb','orb','o25b','lg_fav','hr_fav','dow_fav']
P=P.merge(St[DIMS+['fav','draw','or_mo','o25','btts','hr','ko']],left_on='event_id',right_index=True)
assert 'league_id' in P.columns
w_=[won(a,b,c,d,e,f) for a,b,c,d,e,f in zip(P.mkt,P.sel,P.hg,P.ag,P.ht_hg,P.ht_ag)]
P['won']=np.array(w_,dtype=bool); P['res']=P.won.astype(float)-1/P.ltp
for s in 'BL':
    P['x'+s]=[pnl(s,p,w) for p,w in zip(P.ltp,P.won)]; P['y'+s]=[pnl(s,p,w,3) for p,w in zip(P.ltp,P.won)]
F=P[P.season==2024]; H=P[P.season==2025].copy(); med=H.ko.median(); H['h2']=H.ko>med
print(f"fit prints {len(F)}, games {F.event_id.nunique()} | scoring prints {len(H)}, games {H.event_id.nunique()}, {H.ko.min()} .. {H.ko.max()}, median {med} | {time.time()-T0:.0f}s",flush=True)
assert F.ko.max()<=H.ko.max() and set(F.season)=={2024} and set(H.season)=={2025}
overlap=(F.ko>H.ko.min()).mean(); print(f"share of 2024-season prints later than the first 2025-season print: {overlap:.3f}")
rows=[]
def score(x,col,**k):
    x=x[x[col].notna()]
    if len(x)<30: return
    v=x[col]; a=v[~x.h2]; b=v[x.h2]; y=x['y'+col[1]]
    per=x.groupby('event_id')[col].mean()
    d=dict(k); d.update(n=len(v),games=x.event_id.nunique(),px=x.ltp.mean(),mean=v.mean(),t=tstat(v),tc=tstat(per),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,x3=y.mean(),maxwin=v.max(),ex_top=(v.sum()-v.max())/max(len(v)-1,1)); rows.append(d)
print("\n== controls, 2025, no selection")
ctl=[]
for c,x in H.groupby('code'):
    for s in 'BL':
        v=x['x'+s].dropna(); ctl.append(dict(code=c,side=s,n=len(v),mean=v.mean(),t=tstat(v),h1=x[~x.h2]['x'+s].mean(),h2=x[x.h2]['x'+s].mean()))
print(pd.DataFrame(ctl).round(3).to_string(index=False))
# rank persistence of league errors
print("\n== league error persistence: Spearman of mean(outcome - 1/price) 2024 v 2025 across leagues, n>=100 each")
pers=[]
for c,x in P.groupby('code'):
    a=x[x.season==2024].groupby('lg').res.agg(['mean','size']); b=x[x.season==2025].groupby('lg').res.agg(['mean','size']); j=a.join(b,lsuffix='a',rsuffix='b',how='inner'); j=j[(j.sizea>=100)&(j.sizeb>=100)]
    if len(j)>=5: r_,p_=spearmanr(j.meana,j.meanb); pers.append(dict(code=c,leagues=len(j),rho=r_,p=p_))
print(pd.DataFrame(pers).round(3).to_string(index=False))
# A: cells chosen on 2024
npick=0
for dim in DIMS:
    picks=[]
    for (c,val),x in F.groupby(['code',dim]):
        for s in 'BL':
            v=x['x'+s].dropna()
            if len(v)>=100 and v.mean()>0 and tstat(v)>=2: picks.append((c,val,s,len(v),v.mean(),tstat(v)))
    npick+=len(picks); port={'B':[],'L':[]}
    for c,val,s,n_,m_,t_ in picks:
        x=H[(H.code==c)&(H[dim]==val)]; score(x,'x'+s,method='A',dim=dim,cell=f'{c} {val}',side=s,in_n=n_,in_mean=m_,in_t=t_)
        port[s].append(x)
    for s in 'BL':
        if port[s]: score(pd.concat(port[s]),'x'+s,method='A_ALL',dim=dim,cell=f'{len(port[s])} cells',side=s,in_n=np.nan,in_mean=np.nan,in_t=np.nan)
print(f"\nmethod A: {npick} cells chosen on 2024, {time.time()-T0:.0f}s",flush=True)
# B: GBM residual
X=['league_id','hr','fav','draw','or_mo','o25','btts','ltp']
kw=dict(learning_rate=0.03,max_iter=150,max_leaf_nodes=6,min_samples_leaf=100,l2_regularization=5.0,early_stopping=False,random_state=50)
allH=[]
for c,x in F.groupby('code'):
    h=H[H.code==c].copy()
    if len(x)<500 or len(h)<100: continue
    m=HGR(**kw).fit(x[X],x.res); h['mg']=m.predict(h[X])*h.ltp; fm=m.predict(x[X])*x.ltp; allH.append(h)
    for thr in (.05,.10,.20):
        score(h[h.mg>=thr],'xB',method='B',dim='gbm',cell=f'{c} {thr}',side='B',in_n=int((fm>=thr).sum()),in_mean=x[fm>=thr].xB.mean(),in_t=np.nan)
        score(h[h.mg<=-thr],'xL',method='B',dim='gbm',cell=f'{c} {thr}',side='L',in_n=int((fm<=-thr).sum()),in_mean=x[fm<=-thr].xL.mean(),in_t=np.nan)
A_=pd.concat(allH)
for thr in (.05,.10,.20):
    score(A_[A_.mg>=thr],'xB',method='B_ALL',dim='gbm',cell=f'all {thr}',side='B',in_n=np.nan,in_mean=np.nan,in_t=np.nan)
    score(A_[A_.mg<=-thr],'xL',method='B_ALL',dim='gbm',cell=f'all {thr}',side='L',in_n=np.nan,in_mean=np.nan,in_t=np.nan)
R=pd.DataFrame(rows); R['PASS']=[passes(a,b,c,d,e,f,g) for a,b,c,d,e,f,g in zip(R.n,R.n1,R.n2,R.t,R.h1,R.h2,R['mean'])]
print(f"\n== {len(R)} lines scored on 2025; Bonferroni z about {abs(ND.ppf(0.025/len(R))):.2f}. Mean of chosen cells: 2024 {R[R.method=='A'].in_mean.mean():+.3f}, 2025 {R[R.method=='A']['mean'].mean():+.3f}")
show=['method','dim','cell','side','n','games','px','mean','t','tc','h1','h2','x3','maxwin','ex_top','in_mean','PASS']
print("\n== combined lines, every dimension"); print(R[R.method.isin(['A_ALL','B_ALL'])].sort_values('t',ascending=False)[show].round(3).to_string(index=False))
print("\n== TOP 15 by t, n>=300"); print(R[R.n>=300].sort_values('t',ascending=False).head(15)[show].round(3).to_string(index=False))
print("\n== TOP 10 by t, n<300"); print(R[R.n<300].sort_values('t',ascending=False).head(10)[show].round(3).to_string(index=False))
S=R[R.PASS].sort_values('t',ascending=False)
print(f"\n== SURVIVORS: {len(S)}"); print(S[show].round(3).to_string(index=False) if len(S) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
