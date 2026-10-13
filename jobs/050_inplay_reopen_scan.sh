#!/bin/bash
# 050: IN-PLAY REOPEN OVERSHOOT SCAN — tennis, racing, greyhounds, cricket, basketball — the same machine as football, run on
# the tape job 049 records. Question per sport x market type x price band x move size: after a suspension that moved a runner
# 5pct+, does the market OVERSHOOT (fade it: lay the shortener at the post-reopen lay price / back the drifter at the post back
# price, close at the tape mid +60s, +180s, +600s) or CONTINUE (ride it)? 2pct spread each way on the close, 2pct comm.
# Split by time halves of the sample. WAITS (exit 75, retried every 2 min, does not block the queue) until ip_reopen holds
# 7 days or 3,000 reopens. Survivor rule as always: positive both halves, t>=2 both, n>=150/60.
cd /root/pe-scan && cat > inplay_reopen_scan.py <<'PYFILE'
import sys, math, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
SPREAD=0.02; COMM=0.02
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor()
cur.execute("SELECT to_regclass('ip_reopen')");
if cur.fetchone()[0] is None: print("WAITING: ip_reopen does not exist yet (job 049 recorder)"); sys.exit(75)
cur.execute("SELECT count(*), min(ts), max(ts), count(DISTINCT sport) FROM ip_reopen"); n,t0,t1,ns=cur.fetchone()
print("reopens",n,"from",t0,"to",t1,"sports",ns,flush=True)
if n<3000 and (t1 is None or (t1-t0).days<7): print("WAITING: need 7 days or 3,000 reopens"); sys.exit(75)
R=pd.read_sql("SELECT * FROM ip_reopen WHERE pre_ltp>1.01 AND post_ltp>1.01 AND post_back_px IS NOT NULL AND post_lay_px IS NOT NULL",con)
R['move']=R.post_ltp.astype(float)/R.pre_ltp.astype(float)-1
R=R[R.move.abs()>=0.05].copy()
print("runner-level reopen moves 5pct+:",len(R),flush=True)
# closes: tape mid at +60/+180/+600s for the same runner (nearest row within +-20s)
T=pd.read_sql("SELECT ts, market_id, sel_id, back_px, lay_px, ltp FROM ip_tape WHERE back_px IS NOT NULL AND lay_px IS NOT NULL AND status='OPEN'",con)
T['mid']=(T.back_px.astype(float)+T.lay_px.astype(float))/2; T=T.sort_values('ts')
TK={k:g for k,g in T.groupby(['market_id','sel_id'])}
def mid_at(mid,sid,when,tol=20):
    g=TK.get((mid,sid))
    if g is None: return None
    i=g.ts.searchsorted(when); best=None
    for j in (i-1,i):
        if 0<=j<len(g):
            dt=abs((g.ts.iloc[j]-when).total_seconds())
            if dt<=tol and (best is None or dt<best[0]): best=(dt,float(g.mid.iloc[j]))
    return None if best is None else best[1]
for off in (60,180,600):
    R[f'mid{off}']=[mid_at(m,s,t+pd.Timedelta(seconds=off)) for m,s,t in zip(R.market_id,R.sel_id,R.ts)]
R=R[R.mid60.notna()].copy(); print("with a +60s close:",len(R),flush=True)
def fade(r,off):   # against the move: shortened -> lay at post lay, close by backing at mid; drifted -> back at post back, close by laying at mid
    x=r[f'mid{off}']
    if x is None or pd.isna(x): return np.nan
    if r.move<0:
        e=float(r.post_lay_px); p=1-(e*(1+SPREAD))/(x*(1-SPREAD))
    else:
        e=float(r.post_back_px); p=(e*(1-SPREAD))/(x*(1+SPREAD))-1
    return p*(1-COMM) if p>0 else p
for off in (60,180,600): R[f'fade{off}']=[fade(r,off) for r in R.itertuples()]
R['pband']=pd.cut(R.post_ltp.astype(float),[1,1.3,1.6,2,3,5,10,1000],labels=['<1.3','1.3-1.6','1.6-2','2-3','3-5','5-10','10+'])
R['mband']=pd.cut(R.move,[-9,-0.3,-0.15,-0.05,0.05,0.15,0.3,9],labels=['short30+','short15-30','short5-15','flat','drift5-15','drift15-30','drift30+'])
R['when']=pd.cut(R.secs_since_start.fillna(0)/60,[-1e9,0,20,45,90,180,1e9],labels=['pre-start','0-20m','20-45m','45-90m','90-180m','180m+'])
med=R.ts.median(); R['split']=np.where(R.ts<med,'half 1','half 2')
pd.set_option('display.width',260); pd.set_option('display.max_rows',500)
def tstat(x): x=x.dropna(); return float(x.mean()/(x.std(ddof=1)/math.sqrt(len(x)))) if len(x)>2 and x.std(ddof=1)>0 else 0.0
def survivors(cols,measures,title,min_a=150,min_b=60):
    rows=[]
    for key,g in R.groupby(cols,observed=True):
        a=g[g.split=='half 1']; b=g[g.split=='half 2']
        if len(a)<min_a or len(b)<min_b: continue
        for m in measures:
            rows.append((*(key if isinstance(key,tuple) else (key,)),m,len(a),round(a[m].mean()*100,1),round(tstat(a[m]),1),len(b),round(b[m].mean()*100,1),round(tstat(b[m]),1)))
    S=pd.DataFrame(rows,columns=[*cols,'measure','n1','per100_1','t1','n2','per100_2','t2'])
    ok=S[(S.per100_1>1)&(S.per100_2>1)&(S.t1>=2)&(S.t2>=2)]
    print(f"\n=== {title}: cells {len(S)} | SURVIVORS both halves {len(ok)} ===")
    if len(ok): print(ok.sort_values('per100_2',ascending=False).head(40).to_string(index=False))
    print("-- biggest half-1 effects (top 15, sign = fade; negative means RIDE the move pays):")
    print(S.reindex(S.per100_1.abs().sort_values(ascending=False).index).head(15).to_string(index=False))
print("\n=== 0. Sample by sport x market type ==="); print(R.groupby(['sport','market_type'],observed=True).size().to_string())
survivors(['sport','market_type','mband'],['fade60','fade180','fade600'],'1. FADE the reopen move by sport x market x move size')
survivors(['sport','pband','mband'],['fade60','fade180'],'2. by sport x post price band x move')
survivors(['sport','when','mband'],['fade60','fade180'],'3. by sport x time into event x move')
print("\n=== 4. Raw continuation: median pct change of LTP from post-reopen to +60/+180/+600s by sport x move band ===")
for off in (60,180,600): R[f'cont{off}']=(R[f'mid{off}']/R.post_ltp.astype(float)-1)*100
print(R.groupby(['sport','mband'],observed=True)[['cont60','cont180','cont600']].median().round(2).to_string())
print("\nVERDICT RULE: candidates = positive both halves, t>=2 both. Fade cells go to the resting-order bot at £2; ride cells to a momentum entry at £2. Each must survive a second fortnight before scaling.")
PYFILE
python3 inplay_reopen_scan.py
