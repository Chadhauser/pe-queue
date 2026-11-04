#!/bin/bash
set -o pipefail
# 488 (Finder 2026-11-04, queue item 46 atlas): FOOTBALL IN-PLAY CALIBRATION ATLAS. bf_hist_price (MO, OU15, OU25, OU35, BTTS, FH05, FH15) x af_events. Fit on season 2024 ONLY, score on season 2025 ONLY.
# SAMPLE: bf_hist_price served about 1.2 s per game on 4 Nov with four lanes on the database, so all 12,255 games would take hours. Games are drawn in a fixed random order (seed 488) until FETCH_SECS runs out; raw prints are cached in /root/pe-queue-logs/488_cache, so a later run carries on from there.
# ROWS: first real print per game x selection x 5-minute band x known score, tape minutes 3..92 (FH markets 3..44), 1.03 <= ltp <= 50, duplicates per minute = earliest row. A market already settled by the known score is not entered.
# CLOCK: probe on 100 games: price jump minus af goal minute, 5th pct -4, median +1, 95th +3, 5.7% at +3 or later, none at +5. So a goal counts as known only 5 tape minutes after its af minute (+ stoppage), and a row with a goal in the last 5 minutes is skipped. Skipping looks only backwards. Rows are NEVER dropped for a goal that comes later (the bias of item 14).
# OWN GOALS: af_events.is_home already credits the benefiting team, no flip (job 471). Games whose event goals differ from the FT score are dropped and counted.
# TARGET: residual = outcome - implied. implied = (1/ltp) / sum(1/ltp) over the market's selections printing in the last 2 minutes; raw 1/ltp where a selection has no print (flagged, feature only, no price is carried into a trade).
# RULES: per selection, one tree on the actual residual and one on the GBM's prediction, both fitted on 2024; rank leaves by |mean residual| x n; top 40 become rules, back if residual > 0, lay if < 0. Plus the GBM itself at its 2024 1% and 5% tails.
# SCORE: 2025 only, first row in the rule per game (one entry per game, so t is not inflated by repeats), one tick adverse, 2% commission, £10 risk. Exits: settle, and next goal +8 first real print (settled market or no print = result, never dropped). x3 = three ticks adverse at entry. Halves: 2025 by median date.
FETCH_SECS=${FETCH_SECS:-1800} OMP_NUM_THREADS=3 python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import os,sys,time,glob,pickle,threading,warnings,psycopg2,pandas as pd,numpy as np
from concurrent.futures import ThreadPoolExecutor
from functools import lru_cache
warnings.filterwarnings('ignore')
pd.set_option('display.width',240); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',40); pd.set_option('display.max_colwidth',150)
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LADA=np.array(LAD)
@lru_cache(maxsize=None)
def ti(p): return int(np.searchsorted(LADA,round(float(p),2)-1e-9))
def dn(p,k=1): return float(LADA[max(ti(p)-k,0)])
def up(p,k=1): return float(LADA[min(ti(p)+k,len(LADA)-1)])
def pnl(side,p,q,won,k=1):
    """£10 risk. side B: back £10 at p-k ticks. side L: lay for £10 liability at p+k ticks. q None = settle on won; else green at q, one tick adverse. 2% commission on profit."""
    if side=='B':
        a=dn(p,k); r=(10*(a-1) if won else -10.0) if q is None else 10*(a/up(q)-1)
    else:
        a=up(p,k); s=10/(a-1); r=(s if not won else -10.0) if q is None else s*(1-a/dn(q))
    return r*0.98 if r>0 else r
MK={'MO':('HOME','DRAW','AWAY'),'OU15':('OVER','UNDER'),'OU25':('OVER','UNDER'),'OU35':('OVER','UNDER'),'BTTS':('YES','NO'),'FH05':('OVER','UNDER'),'FH15':('OVER','UNDER')}
LINE={'OU15':1.5,'OU25':2.5,'OU35':3.5,'FH05':0.5,'FH15':1.5}
MS=[(m,s) for m,ss in MK.items() for s in ss]; MSC={x:i for i,x in enumerate(MS)}; MSN=[f"{m} {s}" for m,s in MS]
KNOW=5
def result(mkt,sel,hg,ag,hh,ha):
    if mkt=='MO': return hg==ag if sel=='DRAW' else (hg>ag if sel=='HOME' else hg<ag)
    if mkt=='BTTS': return (hg>0 and ag>0)==(sel=='YES')
    if mkt in('FH05','FH15'): return (hh+ha>LINE[mkt])==(sel=='OVER')
    return (hg+ag>LINE[mkt])==(sel=='OVER')
def settled(mkt,h,a,fh):
    """h,a: goals so far; fh: first-half goals so far."""
    if mkt=='MO': return False
    if mkt=='BTTS': return h>0 and a>0
    if mkt in('FH05','FH15'): return fh>LINE[mkt]
    return h+a>LINE[mkt]
def exit_print(mkt,t,goals,arr):
    """First real print at or after next goal +8, or None = settle at the result. goals: sorted (gt,is_home,first_half)."""
    ng=next((g for g in goals if g[0]>t),None)
    if ng is None: return None
    fhm=mkt in('FH05','FH15')
    if fhm and not ng[2]: return None
    tq=ng[0]+8; hi=46 if fhm else len(arr)-1
    if tq>hi: return None
    w=np.flatnonzero(~np.isnan(arr[tq:hi+1]))
    if not len(w): return None
    q=tq+int(w[0]); h=sum(1 for g in goals if g[0]<=q and g[1]); a=sum(1 for g in goals if g[0]<=q and not g[1]); fh=sum(1 for g in goals if g[0]<=q and g[2])
    return None if settled(mkt,h,a,fh) else float(arr[q])
def norm_p(mkt,sel,t,book):
    """(implied, flag). Other selections must have printed in t-2..t."""
    own=1/book[(mkt,sel)][t]; tot=own
    for s in MK[mkt]:
        if s==sel: continue
        a=book.get((mkt,s))
        if a is None: return own,0
        w=a[max(t-2,0):t+1]; w=w[~np.isnan(w)]
        if not len(w): return own,0
        tot+=1/w[-1]
    return own/tot,1
COLS=['fix','season','date','ms','t','h','a','tot','diff','ltp','logp','imp','normed','since','rh','ra','last','favp','favhome','drawp','o25p','league','hour','dow','res','pb_s','pl_s','pb_g','pl_g','pb_s3','pl_s3']
def rows_for_game(fx,season,date,lg,hour,dow,goals,reds,book,hg,ag,hh,ha):
    """goals: sorted (gt,is_home,first_half). reds: (gt,is_home). book: (mkt,sel)->array by tape minute, nan where no print."""
    pre=lambda k:(lambda a:float(a[0:3][~np.isnan(a[0:3])][0]) if a is not None and (~np.isnan(a[0:3])).any() else np.nan)(book.get(k))
    H,D,A,O=pre(('MO','HOME')),pre(('MO','DRAW')),pre(('MO','AWAY')),pre(('OU25','OVER'))
    fav=np.nanmin([H,A]) if not(np.isnan(H) and np.isnan(A)) else np.nan; fh_=(1.0 if H<=A else 0.0) if not(np.isnan(H) or np.isnan(A)) else np.nan
    out=[]
    for (mkt,sel),arr in book.items():
        won=result(mkt,sel,hg,ag,hh,ha); seen=set(); fhm=mkt in('FH05','FH15')
        for t in np.flatnonzero(~np.isnan(arr)):
            t=int(t)
            if t<3 or t>(44 if fhm else 92): continue
            p=float(arr[t])
            if p<1.03 or p>50: continue
            if any(t-KNOW<g[0]<=t for g in goals): continue
            kn=[g for g in goals if g[0]<=t-KNOW]; h=sum(1 for g in kn if g[1]); a=len(kn)-h; fh=sum(1 for g in kn if g[2])
            if settled(mkt,h,a,fh): continue
            key=(t//5,h,a)
            if key in seen: continue
            seen.add(key)
            imp,fl=norm_p(mkt,sel,t,book); q=exit_print(mkt,t,goals,arr)
            out.append((fx,season,date,MSC[(mkt,sel)],t,h,a,h+a,h-a,p,np.log(p),imp,fl,t-kn[-1][0] if kn else np.nan,sum(1 for r in reds if r[0]<=t-KNOW and r[1]),sum(1 for r in reds if r[0]<=t-KNOW and not r[1]),
                (1 if kn[-1][1] else 2) if kn else 0,fav,fh_,D,O,lg,hour,dow,float(won)-imp,pnl('B',p,None,won),pnl('L',p,None,won),pnl('B',p,q,won),pnl('L',p,q,won),pnl('B',p,None,won,3),pnl('L',p,None,won,3)))
    return out
def tstat(v):
    v=np.asarray(v,dtype=float); n=len(v)
    if n<2: return 0.0
    s=v.std(ddof=1)
    return float(v.mean()/(s/np.sqrt(n))) if s>0 else 0.0
def passes(n,n1,n2,t,h1,h2,m): return bool(n>=300 and n1>=150 and n2>=150 and t>=3.5 and h1>0 and h2>0 and m>=0.15)
# ---- known answers, worked by hand
assert dn(2.0)==1.99 and up(2.0)==2.02 and up(3.0)==3.05 and dn(3.0)==2.98 and up(2.0,3)==2.06
assert abs(pnl('B',2.0,None,True)-9.702)<1e-9 and pnl('B',2.0,None,False)==-10.0          # 10*(1.99-1)*0.98
assert abs(pnl('L',6.0,None,False)-10/5.2*0.98)<1e-9 and pnl('L',6.0,None,True)==-10.0     # lay at 6.2, stake 10/5.2
assert abs(pnl('B',3.0,2.0,None)-10*(2.98/2.02-1)*0.98)<1e-9 and abs(pnl('B',2.0,3.0,None)-10*(1.99/3.05-1))<1e-9   # green; a loss pays no commission
assert abs(pnl('L',2.0,3.0,None)-(10/1.02)*(1-2.02/2.98)*0.98)<1e-9
assert result('OU25','OVER',2,1,0,0) and not result('OU25','OVER',1,1,0,0) and result('BTTS','NO',2,0,0,0) and result('FH05','OVER',0,0,1,0) and result('FH15','UNDER',3,3,1,0) and result('MO','DRAW',1,1,0,0) and result('MO','AWAY',0,1,0,0)
assert settled('OU25',2,1,0) and not settled('OU25',1,1,0) and settled('BTTS',1,1,0) and not settled('BTTS',2,0,0) and settled('FH05',1,0,1) and not settled('FH05',1,0,0) and not settled('MO',9,0,0)
_a=np.full(100,np.nan); _a[[10,30,41,60]]=[2.0,3.0,1.5,1.2]
assert exit_print('MO',10,[(20,True,True)],_a)==3.0 and exit_print('MO',10,[],_a) is None and exit_print('MO',10,[(33,True,True)],_a)==1.5   # goal 20: g+8 = 28, first print 30; goal 33: g+8 = 41, print 41
_b=np.full(100,np.nan); _b[[10,28,30]]=[2.0,3.0,1.5]
assert exit_print('MO',10,[(20,True,True)],_b)==3.0                          # goal 20 -> first print at 28
assert exit_print('OU15',10,[(20,True,True),(25,False,True)],_b) is None     # second goal settles OU15 before the exit print: result, not the print
assert exit_print('OU25',10,[(20,True,True),(25,False,True)],_b)==3.0        # still open at 2 goals
assert exit_print('FH05',10,[(50,True,False)],_b) is None                    # next goal is second half, FH market settles at HT
assert exit_print('MO',10,[(95,True,False)],_b) is None
_bk={('MO','HOME'):np.full(100,np.nan),('MO','DRAW'):np.full(100,np.nan),('MO','AWAY'):np.full(100,np.nan)}
_bk[('MO','HOME')][5]=2.0; _bk[('MO','DRAW')][4]=4.0; _bk[('MO','AWAY')][3]=4.0
assert abs(norm_p('MO','HOME',5,_bk)[0]-0.5)<1e-9 and norm_p('MO','HOME',5,_bk)[1]==1
_bk[('MO','AWAY')][3]=np.nan; assert norm_p('MO','HOME',5,_bk)==(0.5,0)
_c=np.full(100,np.nan); _c[[1,4,6,11,22,30,50]]=[1.8,1.8,1.9,1.9,1.7,1.5,1.2]
_r=rows_for_game(1,2024,0,0,15,1,[(20,True,True)],[],{('OU25','OVER'):_c},1,1,1,0)
_R=pd.DataFrame(_r,columns=COLS)
assert list(_R.t)==[4,6,11,30,50],list(_R.t)                                    # 1 is before minute 3; 22 is within 5 of the goal at 20; bands 0,1,2,6,10
assert list(_R.h)==[0,0,0,1,1] and _R.since.iloc[3]==10 and _R['last'].iloc[3]==1
assert abs(_R.res.iloc[0]-(0-1/1.8))<1e-9                                       # 1-1 is under 2.5, Over lost
assert abs(_R.pl_s.iloc[0]-10/(1.81-1)*0.98)<1e-9 and _R.pb_s.iloc[0]==-10.0
assert abs(_R.pb_g.iloc[0]-10*(1.79/1.51-1)*0.98)<1e-9                          # next goal 20 -> first print at 28+ = 30, price 1.5
_r2=rows_for_game(1,2024,0,0,15,1,[(20,True,True),(21,True,True),(22,True,True)],[],{('OU25','OVER'):_c},3,0,3,0); _R2=pd.DataFrame(_r2,columns=COLS)
assert list(_R2.t)==[4,6,11] and abs(_R2.pb_g.iloc[0]-pnl('B',1.8,None,True))<1e-9   # market settled by the goals, so rows after are not entered and the exit is the result
assert abs(tstat([1,3])-2.0)<1e-9
assert passes(300,150,150,3.5,.1,.1,.15) and not passes(299,150,149,4,.1,.1,.2) and not passes(400,200,200,4,-.1,.1,.2) and not passes(400,200,200,3.4,.1,.1,.2) and not passes(400,200,200,4,.1,.1,.14)
print("known-answer checks: OK",flush=True)
# ---- games
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.season,f.league,f.kickoff,f.hg,f.ag,f.ht_hg,f.ht_ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint
  WHERE f.status='FT' AND f.hg IS NOT NULL AND f.ht_hg IS NOT NULL AND f.season IN (2024,2025) ORDER BY m.event_id""",con)
G=G.drop_duplicates('event_id'); order=np.random.RandomState(488).permutation(len(G)); G=G.iloc[order].reset_index(drop=True)
print("games on the map:",G.groupby('season').size().to_dict(),flush=True)
CACHE='/root/pe-queue-logs/488_cache'; os.makedirs(CACHE,exist_ok=True); CH=50; ids=[list(G.event_id.iloc[i:i+CH]) for i in range(0,len(G),CH)]
FETCH=float(os.environ.get('FETCH_SECS','1700')); T0=time.time(); tl=threading.local(); fails=[]; done=[0]
SQL="SELECT event_id,mkt,sel,minute,m,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt IN ('MO','OU15','OU25','OU35','BTTS','FH05','FH15') AND minute BETWEEN 0 AND 100 AND ltp>=1.01 AND ltp<1000"
def fetch(i):
    f=f"{CACHE}/c{i:04d}.pkl"
    if os.path.exists(f) or time.time()-T0>FETCH: return
    try:
        if not hasattr(tl,'con'):
            tl.con=psycopg2.connect(DB,sslmode='require'); tl.con.autocommit=True; tl.con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
        P=pd.read_sql(SQL,tl.con,params=(ids[i],)).sort_values(['event_id','mkt','sel','minute','m'])
        first=P.groupby('event_id').m.min().to_dict()
        P=P.drop_duplicates(['event_id','mkt','sel','minute'])[['event_id','mkt','sel','minute','ltp']]; P['minute']=P.minute.astype('int16'); P['ltp']=P.ltp.astype('float32')
        for c in('mkt','sel'): P[c]=P[c].astype('category')
        pickle.dump((P,first),open(f+'.tmp','wb')); os.replace(f+'.tmp',f); done[0]+=1
        if done[0]%10==0: print(f"  fetched {done[0]} chunks in this run, {time.time()-T0:.0f}s",flush=True)
    except Exception as e:
        fails.append(i); print("fetch failed",i,type(e).__name__,str(e)[:120],flush=True)
with ThreadPoolExecutor(3) as ex: list(ex.map(fetch,range(len(ids))))
print(f"fetch phase {time.time()-T0:.0f}s, chunks this run {done[0]}, failures {len(fails)}",flush=True)
files=sorted(glob.glob(f"{CACHE}/c*.pkl")); have=[int(os.path.basename(f)[1:5]) for f in files]
GI=G.set_index('event_id'); fxs=[int(x) for i in have for x in GI.loc[ids[i]].fixture_id]
EV=pd.read_sql("SELECT fixture_id,coalesce(minute,0) AS minute,coalesce(extra,0) AS extra,is_home,type,detail FROM af_events WHERE fixture_id=ANY(%s) AND ((type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')) OR (type='Card' AND detail='Red Card'))",con,params=(fxs,))
EV['gm']=EV.minute+np.where(EV.minute.isin([45,90]),EV.extra,0); EV['fh']=EV.minute<=45
gl={k:sorted(zip(d.gm.astype(int),d.is_home.astype(bool),d.fh.astype(bool))) for k,d in EV[EV.type=='Goal'].groupby('fixture_id')}
rd={k:list(zip(d.gm.astype(int),d.is_home.astype(bool))) for k,d in EV[EV.type=='Card'].groupby('fixture_id')}
LGS=sorted(G.league.unique()); LGC={l:i for i,l in enumerate(LGS)}; KO=pd.to_datetime(G.kickoff,utc=True); G['ko']=KO; GI=G.set_index('event_id')
rows=[]; n_game=0; bad_lag=0; bad_goal=0; no_book=0
for f in files:
    P,first=pickle.load(open(f,'rb')); P['mkt']=P.mkt.astype(str); P['sel']=P.sel.astype(str); by={k:d for k,d in P.groupby('event_id',sort=False)}
    for eid,d in by.items():
        g=GI.loc[eid]
        lag=(pd.Timestamp(first[eid]).tz_convert('UTC')-g.ko).total_seconds()/60
        if lag<-5 or lag>20: bad_lag+=1; continue
        gg=gl.get(g.fixture_id,[]); hg,ag,hh,ha=int(g.hg),int(g.ag),int(g.ht_hg),int(g.ht_ag)
        if sum(1 for x in gg if x[1])!=hg or sum(1 for x in gg if not x[1])!=ag: bad_goal+=1; continue
        book={}
        for (m,s),x in d.groupby(['mkt','sel'],sort=False):
            if (m,s) not in MSC: continue
            a=np.full(101,np.nan,dtype=float); a[x.minute.values]=x.ltp.values; a=np.round(a,2); book[(m,s)]=a
        if not book: no_book+=1; continue
        rows.extend(rows_for_game(int(g.fixture_id),int(g.season),g.ko.value//10**9,LGC[g.league],g.ko.hour,g.ko.dayofweek,gg,rd.get(g.fixture_id,[]),book,hg,ag,hh,ha)); n_game+=1
print(f"games used {n_game}; dropped kick-off lag {bad_lag}, event goals differ from FT {bad_goal}, no book {no_book}; rows {len(rows)}",flush=True)
R=pd.DataFrame(rows,columns=COLS); del rows
for c in R.columns:
    if c not in('fix','date'): R[c]=R[c].astype('float32')
print("games by season:",R.groupby('season').fix.nunique().to_dict(),"rows:",R.groupby('season').size().to_dict(),flush=True)
assert R.res.notna().all() and R.pb_s.notna().all() and R.pl_g.notna().all()
A=R[R.season==2024].copy(); B=R[R.season==2025].copy(); MED=B.drop_duplicates('fix').date.median(); B['half']=(B.date>MED).astype(int)
# ---- atlas: stability by selection and by minute band
def tab(key):
    a=A.groupby(key).agg(n24=('res','size'),res24=('res','mean')); b=B.groupby(key).agg(n25=('res','size'),res25=('res','mean'),back25=('pb_s','mean'),lay25=('pl_s','mean')); return a.join(b)
T=tab('ms'); T.index=[MSN[int(i)] for i in T.index]; print("\n== ATLAS by selection: residual = outcome - implied, per row; back25, lay25 = £ per £10 at settle, all rows (rows share games)\n",T.round(4).to_string(),flush=True)
A['b5']=A.t//5*5; B['b5']=B.t//5*5; print("\n== ATLAS by 5-min band\n",tab('b5').round(4).to_string(),flush=True)
for nm,k in (('score',['h','a']),):
    x=A[(A.h<=3)&(A.a<=3)].groupby(k).res.agg(['size','mean']); y=B[(B.h<=3)&(B.a<=3)].groupby(k).res.agg(['size','mean']); z=x.join(y,lsuffix='24',rsuffix='25'); print("\n== ATLAS by known score\n",z.round(4).to_string(),flush=True)
# ---- models on 2024
from sklearn.ensemble import HistGradientBoostingRegressor as HGB
from sklearn.tree import DecisionTreeRegressor as DT
from scipy.stats import spearmanr
FE=['ms','t','h','a','tot','diff','logp','imp','normed','since','rh','ra','last','favp','favhome','drawp','o25p','league','hour','dow']
t0=time.time(); M=HGB(max_iter=200,learning_rate=0.05,max_leaf_nodes=31,min_samples_leaf=1000,l2_regularization=1.0,early_stopping=False,categorical_features=[FE.index('ms'),FE.index('league')],random_state=488)
M.fit(A[FE],A.res); A['pred']=M.predict(A[FE]); B['pred']=M.predict(B[FE]); print(f"\nGBM fit {time.time()-t0:.0f}s on {len(A)} rows of 2024",flush=True)
print("corr(pred,residual): 2024 %.4f (in sample), 2025 %.4f (hold-out); spearman 2025 %.4f"%(np.corrcoef(A.pred,A.res)[0,1],np.corrcoef(B.pred,B.res)[0,1],spearmanr(B.pred,B.res)[0]))
B['dec']=pd.qcut(B.pred,10,labels=False,duplicates='drop'); print("\n== 2025 by GBM prediction decile (hold-out calibration)\n",B.groupby('dec').agg(n=('res','size'),pred=('pred','mean'),actual=('res','mean'),back=('pb_s','mean'),lay=('pl_s','mean')).round(4).to_string(),flush=True)
# league target encoding, 2024 only, per selection
te=A.groupby(['ms','league']).res.mean().rename('lte').reset_index(); A=A.merge(te,on=['ms','league'],how='left'); B=B.merge(te,on=['ms','league'],how='left')
TF=[c for c in FE if c not in('ms','league')]+['lte']
FILL=lambda d:d[TF].fillna(-1)
def describe(tree,leaf):
    tr=tree.tree_; ch_l,ch_r=tr.children_left,tr.children_right; path=[]
    def walk(n,acc):
        if n==leaf: path.extend(acc); return True
        if ch_l[n]==-1: return False
        f=TF[tr.feature[n]]; th=tr.threshold[n]
        return walk(ch_l[n],acc+[(f,'<=',th)]) or walk(ch_r[n],acc+[(f,'>',th)])
    walk(0,[]); lo={};hi={}
    for f,o,th in path:
        if o=='<=': hi[f]=min(hi.get(f,9e9),th)
        else: lo[f]=max(lo.get(f,-9e9),th)
    return ' '.join(f"{lo[f]:.2f}<{f}" if f in lo and f not in hi else f"{f}<={hi[f]:.2f}" if f not in lo else f"{lo[f]:.2f}<{f}<={hi[f]:.2f}" for f in sorted(set(lo)|set(hi)))
LEAF=[]; idxA={}; idxB={}; trees={}
for ms in sorted(A.ms.unique()):
    a=A[A.ms==ms]; b=B[B.ms==ms]
    if len(a)<2000: continue
    for kind,y in (('R',a.res),('G',a.pred)):
        tr=DT(max_leaf_nodes=24,min_samples_leaf=300,random_state=488).fit(FILL(a),y); trees[(int(ms),kind)]=tr
        la=tr.apply(FILL(a)); lb=tr.apply(FILL(b)) if len(b) else np.array([],dtype=int)
        for l in np.unique(la):
            sa=a[la==l];
            if sa.fix.nunique()<100: continue
            LEAF.append(dict(ms=int(ms),kind=kind,leaf=int(l),n24=len(sa),games24=sa.fix.nunique(),res24=sa.res.mean(),score=abs(sa.res.mean())*len(sa)))
            idxA[(int(ms),kind,int(l))]=sa.index.values; idxB[(int(ms),kind,int(l))]=b.index.values[lb==l]
L=pd.DataFrame(LEAF)
L['res25']=[B.res.loc[idxB[(r.ms,r.kind,r.leaf)]].mean() if len(idxB[(r.ms,r.kind,r.leaf)]) else np.nan for r in L.itertuples()]; L['n25']=[len(idxB[(r.ms,r.kind,r.leaf)]) for r in L.itertuples()]
Ls=L[L.n25>=200]; print(f"\n== Does the error map persist? leaves with 2025 n>=200: {len(Ls)}; spearman res24 v res25 {spearmanr(Ls.res24,Ls.res25)[0]:.3f}; same sign {(np.sign(Ls.res24)==np.sign(Ls.res25)).mean():.3f}; mean|res24| {Ls.res24.abs().mean():.4f}, mean|res25| {Ls.res25.abs().mean():.4f}",flush=True)
for kind in('R','G'):
    x=Ls[Ls.kind==kind]; print(f"  tree {kind}: leaves {len(x)}, spearman {spearmanr(x.res24,x.res25)[0]:.3f}, same sign {(np.sign(x.res24)==np.sign(x.res25)).mean():.3f}",flush=True)
TOP=L.sort_values('score',ascending=False).head(40)
def score(df,side,exit_):
    c={'S':'pb_s' if side=='B' else 'pl_s','G':'pb_g' if side=='B' else 'pl_g','X3':'pb_s3' if side=='B' else 'pl_s3'}[exit_]; return df[c].values
def line(name,side,dA,dB,cond):
    dA=dA.sort_values(['fix','t','ms']).drop_duplicates('fix'); dB=dB.sort_values(['fix','t','ms']).drop_duplicates('fix'); out=[]
    for ex in('S','G'):
        v=score(dB,side,ex); h=dB.half.values
        if len(v)<2: continue
        n1,n2=int((h==0).sum()),int((h==1).sum()); m1=v[h==0].mean() if n1 else np.nan; m2=v[h==1].mean() if n2 else np.nan; t_=tstat(v)
        out.append(dict(rule=name,side=side,exit=ex,n=len(v),px=np.median(dB.ltp),per10=v.mean(),t=t_,n1=n1,h1=m1,n2=n2,h2=m2,x3=score(dB,side,'X3').mean() if ex=='S' else np.nan,in24=score(dA,side,ex).mean() if len(dA) else np.nan,n24=len(dA),max_win=v.max(),PASS=passes(len(v),n1,n2,t_,m1 if n1 else -1,m2 if n2 else -1,v.mean()),cond=cond))
    return out
OUT=[]
for rk,r in enumerate(TOP.itertuples(),1):
    side='B' if r.res24>0 else 'L'; nm=f"#{rk} {MSN[r.ms]} {r.kind}{r.leaf}"; cond=describe(trees[(r.ms,r.kind)],r.leaf)
    OUT+=line(nm,side,A.loc[idxA[(r.ms,r.kind,r.leaf)]],B.loc[idxB[(r.ms,r.kind,r.leaf)]],f"res24 {r.res24:+.3f} n24 {r.n24}: {cond}")
for q,side in ((0.99,'B'),(0.95,'B'),(0.01,'L'),(0.05,'L')):
    th=float(np.quantile(A.pred,q)); sa=A[A.pred>=th] if side=='B' else A[A.pred<=th]; sb=B[B.pred>=th] if side=='B' else B[B.pred<=th]
    OUT+=line(f"GBM {'top' if side=='B' else 'bottom'} {int(round((1-q if side=='B' else q)*100))}%",side,sa,sb,f"pred {'>=' if side=='B' else '<='} {th:+.4f}")
O=pd.DataFrame(OUT).sort_values('t',ascending=False); C=['rule','side','exit','n','px','per10','t','n1','h1','n2','h2','x3','in24','n24','max_win','PASS']
print(f"\n== HOLD-OUT 2025, one entry per game, per £10; lines {len(O)}, of which n>=300: {(O.n>=300).sum()}; median date {pd.Timestamp(MED,unit='s').date()}; in24 = same rule on the fit season (in sample)\n",O[C].head(20).round(3).to_string(index=False),flush=True)
print("\nhold-out mean of all lines %.3f, median %.3f; in-sample mean %.3f; share of lines positive %.3f"%(O.per10.mean(),O.per10.median(),O.in24.mean(),(O.per10>0).mean()))
print("\n== RULE WORDING, top 10 lines by t\n",O[['rule','exit','cond']].head(10).to_string(index=False),flush=True)
print("\n== top 8 leaves by 2024 score: residual 2024 v 2025 (shrinkage)\n",TOP.head(8)[['ms','kind','leaf','n24','games24','res24','n25','res25']].round(4).to_string(index=False))
O.to_pickle('/root/pe-queue-logs/488_lines.pkl')
W=O[O.PASS]; print(f"\n== SURVIVORS: {len(W)} of {len(O)} lines (games used {n_game} of {len(G)}; LTP-based, so a pass is an upper bound and then needs the real touch on liq_sample)"); print(W[C+['cond']].round(3).to_string(index=False) if len(W) else "none")
PY
