#!/bin/bash
set -o pipefail
# 499_gbm_85_loses (Finder 2026-11-04, queue item 54): WHY DOES AN 85% DIRECTION CALL LOSE MONEY? bf_hist_price MO and OU25. Entries, features, model and exit as jobs/488_price_path_signatures.sh, +5 only. The number 499 is reused with a new slug: 450-499 are all taken.
# SAMPLE CUT: games in the same hash order as 488, 100 at a time per season, until 900 s are used. n printed.
# BREAKDOWN on 2025, model fit on 2024: top and bottom 2024-threshold deciles by selection and minute band: shorter %, mean win, mean loss, P&L at k = 0, 1, 3 ticks adverse each way, each side.
# GOALS ARE KNOWN TO THE TEST ONLY, never a feature: goal in the hold = af goal with t < minute <= exit minute. Settled at result = goal in hold unknown from the exit, so it counts as its own group.
# THE ONE STATE LEFT: on 2024, best (selection x minute band) per side at k = 1, n >= 100; scored on 2025 only, halves at the 2025 median kick-off, FIRST = one entry per game, the line PASS reads. In-sample deciles pick the state, so 2024's figure flatters it.
python3 -W ignore - <<'PY' 2>&1
import sys,time,hashlib,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
from sklearn.ensemble import HistGradientBoostingClassifier as HGB
pd.set_option('display.width',240); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',40)
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LADA=np.array(LAD)
def pos(p): return int(np.searchsorted(LADA,round(float(p),2)-1e-9))
def up(p,k=1): return float(LADA[min(pos(p)+k,len(LADA)-1)])
def dn(p,k=1): return float(LADA[max(pos(p)-k,0)])
def net(r): return r*0.98 if r>0 else r
def green(side,p,q,k):
    if side=='BACK': return net(10*(dn(p,k)/up(q,k)-1))
    a=up(p,k); b=dn(q,k); return net(10/(a-1)*(1-a/b))
def settle(side,p,won,k):
    if side=='BACK': return net(10*(dn(p,k)-1)) if won else -10.0
    return -10.0 if won else net(10/(up(p,k)-1))
def sel_won(mkt,sel,hg,ag):
    if mkt=='MO': return {'HOME':hg>ag,'AWAY':ag>hg,'DRAW':hg==ag}[sel]
    return (hg+ag>2.5) if sel=='OVER' else (hg+ag<2.5)
def tstat(v):
    v=np.asarray(v,dtype=float); n=len(v)
    if n<2: return 0.0
    s=v.std(ddof=1); return float(v.mean()/(s/np.sqrt(n))) if s>0 else 0.0
def goal_in(goals,t,ex): return any(t<g<=ex for g in goals)
def mband(t): return '15-30' if t<30 else '30-45' if t<45 else '45-60' if t<60 else '60-70' if t<70 else '70-80'
KS=(0,1,3); H=5; GRID=range(15,81,5)
def build(g,hg,ag,ev,mkt,sel,grid=GRID):
    mn=g.minute.values; lt=g.ltp.values; out=[]; p0=lt[0]; won=sel_won(mkt,sel,hg,ag)
    for t in grid:
        i=np.searchsorted(mn,t)
        if i>=len(mn) or mn[i]!=t: continue
        p=lt[i]
        if not 1.10<=p<=15: continue
        j=np.searchsorted(mn,t-10); w=lt[j:i]; wm=mn[j:i]
        if len(w)<5: continue
        k3=np.searchsorted(wm,t-3)
        if k3>=len(w): continue
        d10=np.log(w[-1]/w[0]); d3=np.log(w[-1]/w[k3]); d7=np.log(w[k3]/w[0]) if k3>0 else 0.0
        r=dict(event_id=ev,mkt=mkt,sel=sel,t=int(t),p=p,d10=d10,d3=d3,acc=d3-d7*3/7,rng=np.log(w.max()/w.min()),dist=np.log(w[-1]/p0),lvl=np.log(w[-1]),np_=len(w))
        e=np.searchsorted(mn,t+H)
        if e<len(mn):
            q=lt[e]; r['sh']=int(q<p); r['st']=0; r['ex']=int(mn[e]); r['q']=q
            for k in KS: r[f'b{k}']=green('BACK',p,q,k); r[f'l{k}']=green('LAY',p,q,k)
        else:
            r['sh']=int(won); r['st']=1; r['ex']=999; r['q']=np.nan
            for k in KS: r[f'b{k}']=settle('BACK',p,won,k); r[f'l{k}']=settle('LAY',p,won,k)
        out.append(r)
    return out
# known answers, worked by hand
assert dn(3.0)==2.98 and up(3.0)==3.05 and dn(3.0,3)==2.94 and up(2.0,3)==2.06
assert abs(green('BACK',3.0,2.5,1)-10*(2.98/2.52-1)*0.98)<1e-9 and abs(green('BACK',3.0,2.5,0)-10*(3/2.5-1)*0.98)<1e-9 and abs(green('BACK',3.0,3.5,0)-10*(3/3.5-1))<1e-9
assert abs(green('LAY',3.0,3.5,0)-(10/2)*(1-3/3.5)*0.98)<1e-9 and abs(green('LAY',3.0,2.5,1)-(10/2.05)*(1-3.05/2.48))<1e-9 and green('BACK',2.0,2.0,0)==0
assert abs(settle('BACK',3.0,True,1)-10*1.98*0.98)<1e-9 and settle('BACK',3.0,False,1)==-10.0 and settle('LAY',3.0,True,1)==-10.0 and abs(settle('LAY',3.0,False,0)-5*0.98)<1e-9
assert sel_won('MO','DRAW',1,1) and sel_won('OU25','OVER',2,1) and not sel_won('OU25','UNDER',2,1)
assert goal_in([20,40],15,20) and not goal_in([20],20,25) and not goal_in([26],20,25) and goal_in([26],20,999) and mband(15)=='15-30' and mband(45)=='45-60' and mband(80)=='70-80' and abs(tstat([1,3])-2.0)<1e-9
_g=pd.DataFrame(dict(minute=[0,1,2,3,4,5,6,7,8,9,10,14,15,20],ltp=[3.0]*11+[2.8,2.5,2.0]))
_r=build(_g,1,0,'x','MO','HOME',[15])[0]
assert _r['p']==2.5 and abs(_r['d10']-np.log(2.8/3.0))<1e-9 and _r['ex']==20 and _r['sh']==1 and abs(_r['b1']-green('BACK',2.5,2.0,1))<1e-9
_r=build(_g.iloc[:-1],1,0,'x','MO','HOME',[15])[0]; assert _r['st']==1 and _r['ex']==999 and abs(_r['b1']-settle('BACK',2.5,True,1))<1e-9   # no print at 20+: settled, won
print("known-answer checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.season,f.kickoff,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.season IN (2024,2025)""",con)
G['h']=[hashlib.md5(str(e).encode()).hexdigest() for e in G.event_id]; G=G.sort_values('h').drop_duplicates('event_id')
A=G[G.season==2024]; B=G[G.season==2025]; rows=[]; T0=time.time(); i=0; used={2024:0,2025:0}
while time.time()-T0<900 and i*100<max(len(A),len(B)):
    for D,sn in ((A,2024),(B,2025)):
        c=D.iloc[i*100:(i+1)*100]
        if not len(c): continue
        P=pd.read_sql("SELECT event_id,mkt,sel,minute,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt IN ('MO','OU25') AND minute>=0 AND minute<=130 AND ltp>=1.01 AND ltp<1000",con,params=(list(c.event_id),))
        P=P.sort_values(['event_id','mkt','sel','minute']).drop_duplicates(['event_id','mkt','sel','minute']); res=c.set_index('event_id')
        for (ev,mk,se),g in P.groupby(['event_id','mkt','sel'],sort=False):
            if (mk=='MO' and se in('HOME','AWAY','DRAW')) or (mk=='OU25' and se in('OVER','UNDER')): rows+=build(g,res.hg[ev],res.ag[ev],ev,mk,se)
        used[sn]+=len(c)
    i+=1
    if i%5==0: print(f"  games {used} entries {len(rows)} {int(time.time()-T0)}s",flush=True)
X=pd.DataFrame(rows).merge(G[['event_id','fixture_id','season','kickoff']],on='event_id'); X['ms']=X.mkt+'_'+X.sel; X['mb']=X.t.map(mband)
E=pd.read_sql("SELECT fixture_id,coalesce(minute,0) mn FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')",con,params=(list(map(int,X.fixture_id.unique())),)); con.close()
gm=defaultdict(list)
for r in E.itertuples(): gm[r.fixture_id].append(int(r.mn))
X['goal']=[goal_in(gm[f],t,e) for f,t,e in zip(X.fixture_id,X.t,X.ex)]
print(f"sample {used} games of {len(A)}/{len(B)}, entries {X.groupby('season').size().to_dict()}, settled share {X.st.mean():.3f}, goal in hold {X.goal.mean():.3f}",flush=True)
TR=X[X.season==2024].copy(); TE=X[X.season==2025].copy()
F=['d10','d3','acc','rng','dist','lvl','np_']; ms=pd.Categorical(TR.ms); XT=TR[F].assign(ms=ms.codes); XE=TE[F].assign(ms=pd.Categorical(TE.ms,categories=ms.categories).codes)
m=HGB(max_iter=150,learning_rate=0.05,max_leaf_nodes=15,min_samples_leaf=200,random_state=0).fit(XT,TR.sh)
TR['pm']=m.predict_proba(XT)[:,1]; TE['pm']=m.predict_proba(XE)[:,1]; hi,lo=np.quantile(TR.pm,.9),np.quantile(TR.pm,.1)
print(f"2025 base shorter {TE.sh.mean():.3f}; top decile {TE[TE.pm>=hi].sh.mean():.3f} (n {(TE.pm>=hi).sum()}) [488: 0.846, n 4,527]; bottom decile {TE[TE.pm<=lo].sh.mean():.3f} (n {(TE.pm<=lo).sum()}) [488: 0.130, n 4,685]",flush=True)
def brk(d,col):
    w=d[d[col]>0][col]; l=d[d[col]<=0][col]
    return dict(n=len(d),win_rate=(d[col]>0).mean(),mean_win=w.mean() if len(w) else np.nan,mean_loss=l.mean() if len(l) else np.nan,worst=d[col].min(),per10=d[col].mean(),t=tstat(d[col]))
Top=TE[TE.pm>=hi]; Bot=TE[TE.pm<=lo]
for nm,d,sides in (('TOP decile (model says shorter)',Top,(('BACK','b'),('LAY','l'))),('BOTTOM decile (model says not shorter)',Bot,(('LAY','l'),('BACK','b')))):
    print(f"\n==== {nm}: n {len(d)}, shorter {d.sh.mean():.3f}, goal in hold {d.goal.mean():.3f}, settled {d.st.mean():.3f}, median price {d.p.median():.2f}")
    print("who is in it:\n",d.groupby(['ms','mb']).agg(n=('sh','size'),sh=('sh','mean'),goal=('goal','mean'),p=('p','median')).sort_values('n',ascending=False).head(12).round(3).to_string())
    for sd,c in sides:
        print(f"\n{sd} by cost:\n",pd.DataFrame([dict(k=k,**brk(d,f'{c}{k}')) for k in KS]).round(3).to_string(index=False))
        print(f"{sd}, k=1, by goal in the hold (known to the test only):\n",pd.DataFrame([dict(goal=g_,**brk(x,f'{c}1')) for g_,x in d.groupby('goal')]).round(3).to_string(index=False))
        print(f"{sd} by selection:\n",pd.DataFrame([dict(sel=s_,k0=x[f'{c}0'].mean(),**brk(x,f'{c}1')) for s_,x in d.groupby('ms')]).round(3).to_string(index=False),flush=True)
med=pd.to_datetime(TE.kickoff,utc=True).sort_values().iloc[len(TE)//2]; TE['half']=np.where(pd.to_datetime(TE.kickoff,utc=True)<med,'h1','h2')
def score(name,d,col):
    v=d[col]; a=d[d.half=='h1'][col]; c=d[d.half=='h2'][col]; f=d.sort_values(['kickoff','t']).drop_duplicates('event_id'); fa=f[f.half=='h1'][col]; fb=f[f.half=='h2'][col]; fv=f[col]
    r=dict(line=name,n_all=len(v),all_=v.mean(),t_all=tstat(v),h1_all=a.mean() if len(a) else np.nan,h2_all=c.mean() if len(c) else np.nan,n=len(fv),games=f.event_id.nunique(),per10=fv.mean(),t=tstat(fv),n1=len(fa),h1=fa.mean() if len(fa) else np.nan,n2=len(fb),h2=fb.mean() if len(fb) else np.nan,no_goal=d[~d.goal][col].mean(),goal=d[d.goal][col].mean())
    r['PASS']=bool(r['n']>=300 and r['n1']>=150 and r['n2']>=150 and r['t']>=3.5 and r['h1']>0 and r['h2']>0 and r['per10']>=0.15); return r
OUT=[]
for nm,c,mask in (('BACK top','b1',TR.pm>=hi),('LAY bottom','l1',TR.pm<=lo),('LAY top','l1',TR.pm>=hi),('BACK bottom','b1',TR.pm<=lo)):
    L=TR[mask].groupby(['ms','mb'])[c].agg(['size','mean']); L=L[L['size']>=100].sort_values('mean',ascending=False)
    print(f"\n2024 best cells, {nm}:\n",L.head(4).round(3).to_string())
    (a,b),row=next(L.iterrows()); d=TE[(TE.pm>=hi if 'top' in nm else TE.pm<=lo)&(TE.ms==a)&(TE.mb==b)]
    if len(d): OUT.append(dict(score(f"{nm} {a} {b}",d,c),per24=row['mean'],n24=int(row['size']),k3=d[c.replace('1','3')].mean()))
R=pd.DataFrame(OUT).sort_values('t',ascending=False)
print("\n== THE STATE LEFT, chosen on 2024, scored on 2025 (per10, t, n, h1, h2 = first entry per game; PASS reads those)\n",R.round(3).to_string(index=False))
W=R[R.PASS]; print(f"\n== SURVIVORS: {len(W)} of {len(R)} (LTP-based, an upper bound; sample {used})"); print(W.round(3).to_string(index=False) if len(W) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
