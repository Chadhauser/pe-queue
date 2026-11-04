#!/bin/bash
set -o pipefail
# 488 (Finder 2026-11-04, queue item 47): PRICE-PATH SIGNATURES. bf_hist_price MO and OU25 only. Does the last 10 minutes of price alone say which way the next 5/10/15 minutes go?
# SAMPLE CUT: 100 games took 104 s on the loaded box, so games are pulled in chunks of 100, 2024 and 2025 in turn, in a fixed hash order, until 1500 s are used. The n pulled is printed.
# ENTRY: tape minutes 15,20,...,80, only on a real print AT that minute, ltp 1.10..15 (below 1.10 a lay at £10 liability is a huge stake on a near-settled market). One tick adverse each way, 2% on profit, back stake £10, lay liability £10.
# FEATURES, strictly from prints in [t-10,t), at least 5 of them, none forward-filled: drift over 10 and over 3 minutes, range, acceleration, distance from the tape's first print, price level, selection. tape has no volume, so the item's volume feature is missing. "Time since last goal" is left out, as the item also says no game-state inputs.
# EXIT: first real print at or after t+h. No later print (for example Over 2.5 once a third goal closes it) = settled at the FT result, never dropped.
# LEARN on 2024 only: (a) STATES, tercile cells cut at 2024 values, top 10 back and top 10 lay by 2024 t, n >= 100; (b) GBM, probability the next print is shorter, back the top 2024-threshold decile and lay the bottom one.
# SCORE on 2025 only. Halves are the two sides of the 2025 date median, because 2024 chose the line and so is not a hold-out. Many entries per game, so FIRST = first entry per game per line is shown beside each.
python3 -W ignore - <<'PY' 2>&1
import sys,time,hashlib,psycopg2,pandas as pd,numpy as np
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
def green(side,p,q):
    if side=='BACK': a=dn(p); b=up(q); r=10*(a/b-1)
    else: a=up(p); b=dn(q); r=10/(a-1)*(1-a/b)
    return r*0.98 if r>0 else r
def settle(side,p,won):
    """won: did the selection win. BACK stake £10, LAY liability £10."""
    if side=='BACK': a=dn(p); return 10*(a-1)*0.98 if won else -10.0
    a=up(p); return -10.0 if won else 10/(a-1)*0.98
def sel_won(mkt,sel,hg,ag):
    if mkt=='MO': return {'HOME':hg>ag,'AWAY':ag>hg,'DRAW':hg==ag}[sel]
    return (hg+ag>2.5) if sel=='OVER' else (hg+ag<2.5)
def tstat(v):
    v=np.asarray(v,dtype=float); n=len(v)
    if n<2: return 0.0
    s=v.std(ddof=1)
    return float(v.mean()/(s/np.sqrt(n))) if s>0 else 0.0
# known answers, worked by hand
assert dn(3.0)==2.98 and up(3.0)==3.05 and dn(4.0)==3.95 and up(4.0)==4.1 and dn(2.0)==1.99
assert abs(green('BACK',3.0,2.5)-10*(2.98/2.52-1)*0.98)<1e-9              # +1.789
assert abs(green('BACK',3.0,3.5)-10*(2.98/3.55-1))<1e-9                   # -1.606, no commission
assert abs(green('LAY',3.0,3.5)-(10/2.05)*(1-3.05/3.45)*0.98)<1e-9        # stake 4.878
assert abs(green('LAY',3.0,2.5)-(10/2.05)*(1-3.05/2.48))<1e-9
assert abs(settle('BACK',3.0,True)-10*1.98*0.98)<1e-9 and settle('BACK',3.0,False)==-10.0
assert settle('LAY',3.0,True)==-10.0 and abs(settle('LAY',3.0,False)-10/2.05*0.98)<1e-9
assert sel_won('MO','HOME',2,1) and sel_won('MO','DRAW',1,1) and not sel_won('MO','AWAY',2,1)
assert sel_won('OU25','OVER',2,1) and sel_won('OU25','UNDER',1,1) and not sel_won('OU25','UNDER',2,1)
print("known-answer checks: OK",flush=True)
HS=(5,10,15); GRID=range(15,81,5)
def build(g,hg,ag,ev,mkt,sel):
    """One selection's prints. Features only from prints strictly before t. Exit at first print >= t+h, else the result."""
    mn=g.minute.values; lt=g.ltp.values; out=[]; p0=lt[0]; won=sel_won(mkt,sel,hg,ag)
    for t in GRID:
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
        for h in HS:
            e=np.searchsorted(mn,t+h)
            if e<len(mn):
                q=lt[e]; r[f'xb{h}']=green('BACK',p,q); r[f'xl{h}']=green('LAY',p,q); r[f'sh{h}']=int(q<p); r[f'st{h}']=0
            else:
                r[f'xb{h}']=settle('BACK',p,won); r[f'xl{h}']=settle('LAY',p,won); r[f'sh{h}']=int(won); r[f'st{h}']=1
        out.append(r)
    return out
_g=pd.DataFrame(dict(minute=[0,1,2,3,4,5,6,7,8,9,10,14,15,20],ltp=[3.0]*5+[3.0,3.0,3.0,3.0,3.0,3.0,2.8,2.5,2.0]))
GRID_SAVE=GRID; GRID=[15]
_r=build(_g,1,0,'x','MO','HOME')[0]
assert _r['p']==2.5 and abs(_r['d10']-np.log(2.8/3.0))<1e-9 and abs(_r['d3']-0.0)<1e-9     # the 2.5 entry print itself is not a feature; window 5..14, last 2.8; only 14 is in the last 3 minutes
assert abs(_r['xb5']-green('BACK',2.5,2.0))<1e-9 and abs(_r['xb10']-settle('BACK',2.5,True))<1e-9 and _r['sh10']==1   # no print at 25+, settled at the result
GRID=GRID_SAVE
print("feature and exit checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.season,f.kickoff,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.season IN (2024,2025)""",con)
G['h']=[hashlib.md5(str(e).encode()).hexdigest() for e in G.event_id]; G=G.sort_values('h').drop_duplicates('event_id')
A=G[G.season==2024]; B=G[G.season==2025]; rows=[]; T0=time.time(); done=0; i=0; used={2024:0,2025:0}
while time.time()-T0<1500 and i*100<max(len(A),len(B)):
    for D,sn in ((A,2024),(B,2025)):
        c=D.iloc[i*100:(i+1)*100]
        if not len(c): continue
        P=pd.read_sql("SELECT event_id,mkt,sel,minute,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt IN ('MO','OU25') AND minute>=0 AND minute<=130 AND ltp>=1.01 AND ltp<1000",con,params=(list(c.event_id),))
        P=P.sort_values(['event_id','mkt','sel','minute']).drop_duplicates(['event_id','mkt','sel','minute']); res=c.set_index('event_id')
        for (ev,mk,se),g in P.groupby(['event_id','mkt','sel'],sort=False):
            if (mk=='MO' and se in('HOME','AWAY','DRAW')) or (mk=='OU25' and se in('OVER','UNDER')):
                rows+=build(g,res.hg[ev],res.ag[ev],ev,mk,se)
        used[sn]+=len(c); done+=len(c); print(f"  games {done} (2024 {used[2024]}, 2025 {used[2025]}) entries {len(rows)} {int(time.time()-T0)}s",flush=True)
    i+=1
X=pd.DataFrame(rows).merge(G[['event_id','season','kickoff']],on='event_id'); X['ms']=X.mkt+'_'+X.sel
print(f"sample: {used} games of {len(A)}/{len(B)}, entries {X.groupby('season').size().to_dict()}; settled at the result, share of entries: +5 {X.st5.mean():.3f}, +10 {X.st10.mean():.3f}, +15 {X.st15.mean():.3f}",flush=True)
TR=X[X.season==2024].copy(); TE=X[X.season==2025].copy()
med=pd.to_datetime(TE.kickoff,utc=True).sort_values().iloc[len(TE)//2]; TE['half']=np.where(pd.to_datetime(TE.kickoff,utc=True)<med,'h1','h2')
def score(name,d,col):
    v=d[col]; a=d[d.half=='h1'][col]; c=d[d.half=='h2'][col]; f=d.sort_values(['kickoff','t']).drop_duplicates('event_id')[col]
    r=dict(line=name,n=len(v),games=d.event_id.nunique(),per10=v.mean(),t=tstat(v),n1=len(a),h1=a.mean(),n2=len(c),h2=c.mean(),first_n=len(f),first=f.mean(),first_t=tstat(f))
    r['PASS']=bool(r['n']>=300 and r['n1']>=150 and r['n2']>=150 and r['t']>=3.5 and r['h1']>0 and r['h2']>0 and r['per10']>=0.15)
    return r
Q={c:np.quantile(TR[c],[1/3,2/3]) for c in ('d10','d3','dist')}; Q2=np.median(TR.rng)
for D in (TR,TE):
    for c in Q: D['b_'+c]=np.digitize(D[c],Q[c])
    D['b_rng']=(D.rng>Q2).astype(int)
    D['cell']=D.ms+'|d10='+D.b_d10.astype(str)+'|d3='+D.b_d3.astype(str)+'|rng='+D.b_rng.astype(str)+'|dist='+D.b_dist.astype(str)
OUT=[]; ALL=[]
for h in HS:
    for side,col in (('BACK',f'xb{h}'),('LAY',f'xl{h}')):
        L=TR.groupby('cell')[col].agg(['size','mean',tstat]); L=L[L['size']>=100].sort_values('tstat',ascending=False).head(10)
        for cell,row in L.iterrows():
            d=TE[TE.cell==cell]
            if len(d): OUT.append(dict(score(f"{side} +{h} {cell}",d,col),n24=int(row['size']),per24=row['mean'],t24=row['tstat']))
        ALL.append(score(f"ALL {side} +{h} (control, no selection)",TE,col))
    F=['d10','d3','acc','rng','dist','lvl','np_']; ms=pd.Categorical(TR.ms); XT=TR[F].assign(ms=ms.codes); XE=TE[F].assign(ms=pd.Categorical(TE.ms,categories=ms.categories).codes)
    m=HGB(max_iter=150,learning_rate=0.05,max_leaf_nodes=15,min_samples_leaf=200,random_state=0).fit(XT,TR[f'sh{h}'])
    pt=m.predict_proba(XT)[:,1]; pe=m.predict_proba(XE)[:,1]; hi,lo=np.quantile(pt,.9),np.quantile(pt,.1); y=TE[f'sh{h}'].values
    print(f"GBM +{h}: 2025 base rate {y.mean():.3f}, top decile {y[pe>=hi].mean():.3f} (n {(pe>=hi).sum()}), bottom decile {y[pe<=lo].mean():.3f} (n {(pe<=lo).sum()})",flush=True)
    OUT.append(score(f"GBM BACK +{h} top decile",TE[pe>=hi],f'xb{h}')); OUT.append(score(f"GBM LAY +{h} bottom decile",TE[pe<=lo],f'xl{h}'))
R=pd.DataFrame(OUT).sort_values('t',ascending=False)
print("\n== CONTROLS, every entry in 2025\n",pd.DataFrame(ALL).round(3).to_string(index=False))
print(f"\n== HOLD-OUT 2025, {len(R)} lines chosen on 2024, sorted by 2025 t\n",R.head(25).round(3).to_string(index=False))
print(f"\nlines positive in 2025: {(R.per10>0).sum()} of {len(R)}; lines chosen on 2024 mean 2024 per £10 {R.per24.mean():.3f}, mean 2025 per £10 {R.per10.mean():.3f}")
W=R[R.PASS]; print(f"\n== SURVIVORS: {len(W)} of {len(R)} (2025 only, LTP-based so an upper bound)"); print(W.round(3).to_string(index=False) if len(W) else "none")
PY
