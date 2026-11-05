#!/bin/bash
set -o pipefail
# 499_racing_range (Finder 2026-11-05, queue item 108): ppmax and ppmin have never been used. Does a runner's pre-play price range say anything the BSP does not? Read only.
# TABLE: racing_bsp, WIN and PLACE, local DB. BET: at BSP, one tick adverse, to win_lose, 2% commission, back stake 10, lay liability 10. win_lose not 0/1 (2 marks a dead heat, item 48) is not traded and is counted.
# LINES, fixed before any price is read: market x ppwap band (<=3, 3-6, 6-12, 12-30) x feature x back and lay.
#   WHIP15, WHIP2, WHIP3 = ppmax/ppmin at or above 1.5, 2, 3. TIGHT = ppmax/ppmin under 1.15.
#   POS = where ppwap sits in its own range on a log scale: (ln ppwap - ln ppmin) / (ln ppmax - ln ppmin). POSHI >= 0.7, POSLO <= 0.3, only where ppmax/ppmin >= 1.15.
#   ALL = every runner in the band, the control.
# FIRST RUN VOID: it dropped runners with ppwap outside ppmin..ppmax, 44% of rows. ppmax 1 and ppmin 1001 are "no trade" markers, about 40% of 2025-26 place rows; on win, ppwap is below ppmin on about 13% of rows and never above ppmax, so the columns do not share one window, and the window is not documented on the box. Only the markers are excluded now.
# NO LOOK-AHEAD: the selector uses ppmax, ppmin, ppwap only, never BSP (item 48: a selector on the BSP you bet at cannot pass) and never ip*. Band is on ppwap. BSP is taken at the off, so the rule is an SP bet placed just before.
# Halves: date median. Runners per race are correlated in the lay and back of a whole band: t by race is reported.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,warnings,psycopg2,pandas as pd,numpy as np
warnings.filterwarnings('ignore')
pd.set_option('display.width',230); pd.set_option('display.max_rows',80); pd.set_option('display.max_columns',30)
sys.path.insert(0,'/root/pe-queue/runner'); import creds
T0=time.time()
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LADA=np.array(LAD)
def adverse(p,side):
    """BSP is not always on the ladder. Back: the rung at or under p, then one down. Lay: the rung at or over p, then one up."""
    p=np.round(np.asarray(p,dtype=float),6)
    up_i=np.searchsorted(LADA,p-1e-9,side='left')             # first rung >= p
    dn_i=np.searchsorted(LADA,p+1e-9,side='right')-1          # last rung <= p
    return LADA[np.clip(dn_i-1,0,len(LADA)-1)] if side=='B' else LADA[np.clip(up_i+1,0,len(LADA)-1)]
def pnl_back(p,won):
    a=adverse(p,'B'); v=np.where(won,10*(a-1)*0.98,-10.0); return np.where(a<=1.01,np.nan,v)
def pnl_lay(p,won):
    a=adverse(p,'L'); return np.where(won,-10.0,10/(a-1)*0.98)
def tstat(v):
    v=np.asarray(v,dtype=float); v=v[np.isfinite(v)]
    if len(v)<2: return 0.0
    s=v.std(ddof=1); return float(v.mean()/(s/len(v)**0.5)) if s>0 else 0.0
def gate(v,when,race):
    m=np.isfinite(v); v=v[m]; when=when[m]; race=race[m]
    if len(v)==0: return dict(n=0,races=0,mean=np.nan,t=0.0,t_race=0.0,n1=0,h1=np.nan,n2=0,h2=np.nan,PASS=False)
    md=np.median(when); a=v[when<md]; b=v[when>=md]; t=tstat(v)
    tr=tstat(pd.Series(v).groupby(race).sum().values) if len(v)>1 else 0.0
    return dict(n=len(v),races=len(set(race)),mean=v.mean(),t=t,t_race=tr,n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,
                PASS=bool(len(v)>=300 and len(a)>=150 and len(b)>=150 and t>=3.5 and a.mean()>0 and b.mean()>0 and v.mean()>=0.15))
def pos(w,lo,hi):
    return (np.log(w)-np.log(lo))/(np.log(hi)-np.log(lo))
# known answers, worked by hand
assert adverse(2.0,'B')==1.99 and adverse(2.0,'L')==2.02 and adverse(5.13,'B')==5.0 and adverse(5.13,'L')==5.3   # 5.13 is off ladder: 5.1 is at or under, one down 5.0; 5.2 at or over, one up 5.3
assert abs(float(pnl_back(3.0,True))-10*1.98*0.98)<1e-9 and float(pnl_back(3.0,False))==-10.0                    # 3.0 fills 2.98
assert np.isnan(float(pnl_back(1.02,True)))                                                                      # 1.02 fills 1.01: no bet
assert abs(float(pnl_lay(3.0,False))-10/2.05*0.98)<1e-9 and float(pnl_lay(3.0,True))==-10.0                      # 3.0 fills 3.05
assert abs(pos(4.0,2.0,8.0)-0.5)<1e-9 and abs(pos(2.0,2.0,8.0))<1e-9 and abs(pos(8.0,2.0,8.0)-1.0)<1e-9
_g=gate(np.array([1.0,0.5]*200),np.arange(400.0),np.arange(400)); assert _g['PASS'] is True and abs(_g['mean']-0.75)<1e-9
_g=gate(np.array([1.0]*300+[0.0]*300),np.arange(600.0),np.arange(600)); assert _g['PASS'] is False and _g['h2']==0.0   # second half at zero is not positive
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)

con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
d=pd.read_sql("SELECT market,event_id,event_dt,selection_id,win_lose,bsp::float8 bsp,ppwap::float8 ppwap,ppmax::float8 ppmax,ppmin::float8 ppmin FROM racing_bsp",con); con.close()
print(f"rows {len(d)}, market values {d.market.value_counts().to_dict()}, {d.event_dt.min()} to {d.event_dt.max()}",flush=True)
SK={}
for name,mask in (('no bsp',d.bsp.isna()|(d.bsp<1.01)),('no ppwap/ppmax/ppmin',d.ppwap.isna()|d.ppmax.isna()|d.ppmin.isna()|(d.ppmin<1.01)),('win_lose not 0/1',~d.win_lose.isin([0,1]))):
    SK[name]=int(mask.sum()); d=d[~mask]
bad=(d.ppmax<=1.0)|(d.ppmin>=1000)|(d.ppmax<d.ppmin); SK['no traded range: ppmax 1, ppmin 1001 or inverted']=int(bad.sum()); d=d[~bad]
print("excluded, counted:",SK,f"kept {len(d)}",flush=True)
print("ppwap outside ppmin..ppmax, kept and counted (the columns do not share one window):",d.assign(o=(d.ppwap<d.ppmin-1e-9)|(d.ppwap>d.ppmax+1e-9)).groupby('market').o.mean().round(3).to_dict(),flush=True)
d['R']=d.ppmax/d.ppmin
d['POS']=np.where(d.R>=1.15,pos(d.ppwap.values,d.ppmin.values,np.where(d.R>1,d.ppmax.values,d.ppmin.values*1.01)),np.nan)   # not clipped: under 0 means ppwap below ppmin, and counts as POSLO
d['when']=pd.to_datetime(d.event_dt,utc=True).astype('int64').astype(float)
d['B']=pnl_back(d.bsp.values,d.win_lose.values==1); d['L']=pnl_lay(d.bsp.values,d.win_lose.values==1)
BANDS=(('<=3',0,3),('3-6',3,6),('6-12',6,12),('12-30',12,30))
FEAT=(('ALL',lambda x:np.ones(len(x),bool)),('WHIP15',lambda x:x.R>=1.5),('WHIP2',lambda x:x.R>=2),('WHIP3',lambda x:x.R>=3),('TIGHT',lambda x:x.R<1.15),('POSHI',lambda x:x.POS>=0.7),('POSLO',lambda x:x.POS<=0.3))
print("\n== feature shares of runners, by band (WIN)")
W=d[d.market.astype(str).str.upper().str.startswith('WIN')]
for b,lo,hi in BANDS:
    x=W[(W.ppwap>lo)&(W.ppwap<=hi)]; print(f"  {b:6s} n {len(x):6d} "+" ".join(f"{f} {np.mean(np.asarray(fn(x),dtype=bool)):.3f}" for f,fn in FEAT[1:]))
out=[]
for mk,gm in d.groupby('market'):
    for b,lo,hi in BANDS:
        gb=gm[(gm.ppwap>lo)&(gm.ppwap<=hi)]
        for f,fn in FEAT:
            x=gb[np.asarray(fn(gb),dtype=bool)]
            for side in 'BL':
                r=gate(x[side].values,x.when.values,x.event_id.values)
                out.append(dict(mkt=mk,band=b,feat=f,side=side,**r,won=x.win_lose.eq(1).mean() if len(x) else np.nan,imp=(1/x.bsp).mean() if len(x) else np.nan))
S=pd.DataFrame(out)
base=S[S.feat=='ALL'][['mkt','band','side','mean']].rename(columns={'mean':'ctl'}); S=S.merge(base,on=['mkt','band','side']); S['v_ctl']=S['mean']-S.ctl
print(f"\nlines {len(S)}, of which at n>=300: {(S.n>=300).sum()}, {time.time()-T0:.0f}s")
print("\n== ALL controls\n",S[S.feat=='ALL'].drop(columns=['ctl','v_ctl','PASS','n1','n2']).round(3).to_string(index=False))
print("\n== TOP 15 by t at n>=300, excluding controls\n",S[(S.n>=300)&(S.feat!='ALL')].sort_values('t',ascending=False).head(15).drop(columns=['n1','n2']).round(3).to_string(index=False))
print("\n== TOP 8 by the feature's gain on its control, n>=300\n",S[(S.n>=300)&(S.feat!='ALL')].sort_values('v_ctl',ascending=False).head(8).drop(columns=['n1','n2']).round(3).to_string(index=False))
Y=S[S.PASS&(S.feat!='ALL')]; print(f"\n== SURVIVORS: {len(Y)} of {(S.feat!='ALL').sum()}\n",Y.round(3).to_string(index=False) if len(Y) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
