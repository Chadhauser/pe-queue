#!/bin/bash
set -o pipefail
# 461 (Finder 2026-11-03, own item 13): RACING PLACE vs WIN mispricing. racing_bsp UK/IE; WIN and PLACE markets joined per runner
# (selection_id, off time within 15 min). Fair place probability from the WIN market by Harville (Plackett-Luce, Monte Carlo 6,000 orders per
# race, fixed seed) over the FULL win field; places k = number of place-market winners in that race (realised; k is fixed before the off
# except when non-runners change it — small look-ahead, flagged). Races kept only when every place runner has a win price and k in 2..4.
# Signal ratio r = place odds / Harville-fair place odds.
#   SIG=MWAP : win and place MORNING WAPs (known hours before the off — the clean, tradable signal)
#   SIG=BSP  : win BSP and place BSP (known only at the off — near-off proxy, NEVER PASS)
# Trades (risk £10; 2% commission on profit; ONE TICK ADVERSE on the BSP fill, as 451): BACK place at BSP when r >= 1+e; LAY place at BSP
# when r <= 1/(1+e); e in 5/10/20%. Hold to result (a race always settles). Halves by event-date median. Distinct races per cell reported
# (one runner per race per side would be the clean count — several runners per race in a cell are correlated).
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
def tick(p):
    p=np.asarray(p,dtype=float)
    return np.select([p<2,p<3,p<4,p<6,p<10,p<20,p<30,p<50,p<100],[0.01,0.02,0.05,0.1,0.2,0.5,1,2,5],10.0)
def comm(x): return np.where(x>0,x*0.98,x)
def back(p,won):
    q=p-tick(p); return np.where(q>1.01,comm(np.where(won,10*(q-1),-10.0)),np.nan)
def lay(p,won):
    q=p+tick(p); s=10/(q-1); return comm(np.where(won,-10.0,s))
b=lambda v: np.array([v],dtype=float)
# known answers: back 2.5 -> 2.48: win 14.8*0.98=14.504; lay 2.5 -> 2.52, stake 10/1.52=6.578947, unplaced 6.447368, placed -10
assert abs(back(b(2.5),b(1)==1)[0]-14.504)<1e-9 and back(b(2.5),b(0)==1)[0]==-10
assert abs(lay(b(2.5),b(0)==1)[0]-10/1.52*0.98)<1e-9 and lay(b(2.5),b(1)==1)[0]==-10
rng=np.random.default_rng(461)
def harville(p,k,N=6000):
    # P(runner in top k) under Plackett-Luce with win probs p (Gumbel-max trick)
    g=np.log(p)[None,:]+rng.gumbel(size=(N,len(p)))
    top=np.argsort(-g,axis=1)[:,:k]
    c=np.bincount(top.ravel(),minlength=len(p)); return c/N
# exact check: 3 runners p=(.5,.3,.2), k=2: P(i top2)=p_i+sum_j p_j p_i/(1-p_j)
pp=np.array([.5,.3,.2]); ex=[pp[i]+sum(pp[j]*pp[i]/(1-pp[j]) for j in range(3) if j!=i) for i in range(3)]
assert np.allclose(harville(pp,2,200000),ex,atol=0.01), (harville(pp,2,200000),ex)
print("P&L and Harville unit checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET statement_timeout='1200s'")
W=pd.read_sql("""SELECT event_id wid, event_dt, selection_id, bsp::float wbsp, NULLIF(morningwap,0)::float wm, win_lose won_w
  FROM racing_bsp WHERE market='win' AND lower(country) IN ('uk','ire') AND bsp>1.0""",con)
P=pd.read_sql("""SELECT event_id pid, event_dt pdt, menu_hint course, selection_id, bsp::float pbsp, NULLIF(morningwap,0)::float pm, win_lose placed
  FROM racing_bsp WHERE market='place' AND lower(country) IN ('uk','ire') AND bsp>1.0 AND win_lose IS NOT NULL""",con)
W=W.drop_duplicates(['wid','selection_id']); P=P.drop_duplicates(['pid','selection_id'])
J=P.merge(W,on='selection_id'); J=J[(J.pdt-J.event_dt).abs()<=pd.Timedelta('15min')]
J=J.drop_duplicates(['pid','selection_id'])
pid2wid=J.groupby('pid').wid.agg(lambda x:x.mode().iat[0])
J=J[J.wid==J.pid.map(pid2wid)]
psize=P.groupby('pid').size(); J['pfield']=J.pid.map(psize); jn=J.groupby('pid').size()
full=jn[jn==psize.reindex(jn.index)].index; J=J[J.pid.isin(full)]
K=P.groupby('pid').placed.sum(); J['k']=J.pid.map(K)
J=J[J.k.between(2,4)]
print(f"place runners joined to a win price, full races, k 2..4: {len(J)} runners | {J.pid.nunique()} races | {J.event_dt.min()} -> {J.event_dt.max()}",flush=True)
Wg={wid:g for wid,g in W[W.wid.isin(J.wid.unique())].groupby('wid')}
out=[]
for pid,g in J.groupby('pid'):
    wf=Wg[g.wid.iat[0]]; k=int(g.k.iat[0])
    if len(wf)<=k: continue
    res={}
    for sig,col in (('BSP','wbsp'),('MWAP','wm')):
        x=wf[col].values
        if np.isnan(x).any() or (x<=1).any(): continue
        q=(1/x); q=q/q.sum(); h=harville(q,k)
        res[sig]=dict(zip(wf.selection_id.values,h))
    for r in g.itertuples():
        out.append((pid,r.event_dt,r.course,r.selection_id,k,len(wf),r.pbsp,r.pm,int(r.placed),res.get('BSP',{}).get(r.selection_id,np.nan),res.get('MWAP',{}).get(r.selection_id,np.nan)))
D=pd.DataFrame(out,columns=['pid','dt','course','sel','k','field','pbsp','pm','placed','h_bsp','h_mwap'])
med=D.dt.median(); D['half']=D.dt>med
print(f"runners priced {len(D)} | races {D.pid.nunique()} | date median {med} | with MWAP signal {D.h_mwap.notna().sum()}",flush=True)
won=D.placed.values==1
D['pb']=back(D.pbsp.values,won); D['pl']=lay(D.pbsp.values,won)
D['band']=pd.cut(D.pbsp,[1,1.5,2.5,5,1000],labels=['<1.5','1.5-2.5','2.5-5','5+'])
print("\n== calibration: Harville(BSP) place prob vs actual place rate, and place-BSP implied (deciles of Harville)")
D['dec']=pd.qcut(D.h_bsp,10,duplicates='drop')
print(D.groupby('dec',observed=True).agg(n=('placed','size'),harville=('h_bsp','mean'),bsp_implied=('pbsp',lambda x:(1/x).mean()),actual=('placed','mean')).round(3).to_string())
rows=[]
def cell(name,m,pn):
    E=D[m & D[pn].notna()]
    if len(E)==0: return
    x=E[pn]; n=len(x); mu=x.mean(); sd=x.std(ddof=0) or 1e-9
    a=E[~E.half][pn]; c=E[E.half][pn]
    rows.append(dict(cell=name,n=n,races=E.pid.nunique(),mean=mu,t=mu/(sd/np.sqrt(n)),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(c),h2=c.mean() if len(c) else np.nan))
for sig,hc,pc in (('MWAP','h_mwap','pm'),('BSP','h_bsp','pbsp')):
    D['r']=D[pc]/(1/D[hc])
    for e in (0.05,0.10,0.20):
        for bd in ['ALL']+list(D.band.cat.categories):
            mb=(D.band==bd) if bd!='ALL' else pd.Series(True,index=D.index)
            cell(f"{sig} BACK r>={1+e:.2f} band {bd}",mb&(D.r>=1+e),'pb')
            cell(f"{sig} LAY  r<={1/(1+e):.3f} band {bd}",mb&(D.r<=1/(1+e)),'pl')
        for kk in (2,3,4):
            cell(f"{sig} BACK r>={1+e:.2f} k={kk}",(D.k==kk)&(D.r>=1+e),'pb')
            cell(f"{sig} LAY  r<={1/(1+e):.3f} k={kk}",(D.k==kk)&(D.r<=1/(1+e)),'pl')
for bd in D.band.cat.categories:
    cell(f"baseline BACK all band {bd}",D.band==bd,'pb'); cell(f"baseline LAY all band {bd}",D.band==bd,'pl')
R=pd.DataFrame(rows)
R['PASS']=(R.n>=300)&(R.n1>=150)&(R.n2>=150)&(R.t>=3.5)&(R.h1>0)&(R.h2>0)&(R['mean']>=0.15)&R.cell.str.startswith('MWAP')
print(f"\n== {len(R)} cells; top 15 by t (n>=300)")
print(R[R.n>=300].sort_values('t',ascending=False).head(15).round(3).to_string(index=False))
print("\n== MWAP (clean signal) ALL-band lines")
print(R[R.cell.str.contains('MWAP') & R.cell.str.contains('band ALL')].round(3).to_string(index=False))
print("\n== baselines")
print(R[R.cell.str.startswith('baseline')].round(3).to_string(index=False))
S=R[R.PASS].sort_values('t',ascending=False)
print(f"\n== SURVIVORS: {len(S)} (BSP-signal cells can never pass: look-ahead)")
print(S.round(3).to_string(index=False) if len(S) else "none")
PY
