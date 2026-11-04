#!/bin/bash
set -o pipefail
# 489 (Finder 2026-11-04, item 48): RACING RESIDUAL MODEL ON BSP. racing_bsp UK/IE, WIN and PLACE, settled at result at BSP.
# Fit: everything before 2025-07-01 (F1), and the item's own window 2024-01..2025-06 (F2, ALL bands only, sensitivity).
# Hold-out: 2025-07-01 onwards, never seen by a model; h1/h2 split at the hold-out's median date.
# Two signals, because a BSP order is placed BEFORE the BSP is known:
#   CLEAN   features known in the morning only (morning WAP, morning volume, field, course, distance, race type, hour).
#           GBM regression of residual = outcome - 1/BSP. Margin = predicted residual x morning WAP (share of implied).
#           Bands use the morning WAP. These lines CAN pass: the signal is known before the bet and BSP is the real fill.
#   AS_ITEM the item as written: features add pre-play WAP/min/max/volume and BSP itself. Margin = model p x BSP - 1.
#           These lines CANNOT pass: the signal uses the price it bets at. Near-off proxy, reported for reading only.
# P&L: £10 risk, one tick adverse (back below BSP, lay above), 2% commission on profit. mean0 = exact BSP, no adverse tick.
# Dead heats: WIN races with k winners pay price/k. PLACE dead heats cannot be identified here (treated as full winners).
# Void: races with no winner at all are removed and counted. No stall or going on this table, so neither is a feature.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,time,psycopg2,pandas as pd,numpy as np
from sklearn.ensemble import HistGradientBoostingClassifier as HGC, HistGradientBoostingRegressor as HGR
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',250); pd.set_option('display.max_columns',40)
T0=time.time()
def tick(p):
    p=np.asarray(p,dtype=float)
    return np.select([p<2,p<3,p<4,p<6,p<10,p<20,p<30,p<50,p<100],[0.01,0.02,0.05,0.1,0.2,0.5,1,2,5],10.0)
def comm(x): return np.where(x>0,x*0.98,x)
def back_pl(p,won,k=1,adv=1):
    # a back fill one tick below the price: the step down from a ladder boundary is the smaller tick (2.0 -> 1.99)
    p=np.asarray(p,dtype=float); a=np.maximum(1.01,p-adv*tick(p*(1-1e-9)))
    return comm(10*np.where(won,a/k-1,-1.0))
def lay_pl(p,won,k=1,adv=1):
    p=np.asarray(p,dtype=float); a=p+adv*tick(p); s=10/(a-1)
    return comm(np.where(won,-s*(a/k-1),s))
def passes(n,n1,n2,t,h1,h2,mean):
    return bool(n>=300 and n1>=150 and n2>=150 and t>=3.5 and h1>0 and h2>0 and mean>=0.15)
A=lambda v: np.array([v],dtype=float); W=A(1)==1; L=A(0)==1
# known answers. Back 5.0: fill 4.9, win 39*0.98=38.22, lose -10.
assert abs(back_pl(A(5.0),W)[0]-38.22)<1e-9 and back_pl(A(5.0),L)[0]==-10
# Lay 5.0: fill 5.1, stake 10/4.1=2.439024, win 2.390244 after commission, lose exactly -10 (liability).
assert abs(lay_pl(A(5.0),L)[0]-2.390244)<1e-6 and abs(lay_pl(A(5.0),W)[0]+10)<1e-9
# Boundary: back 2.0 fills 1.99, not 1.98. Win 9.9*0.98=9.702.
assert abs(back_pl(A(2.0),W)[0]-9.702)<1e-9
# Floor: back 1.02 fills 1.01, win 0.1*0.98=0.098. Exact BSP back 5.0: 40*0.98=39.2.
assert abs(back_pl(A(1.02),W)[0]-0.098)<1e-9 and abs(back_pl(A(5.0),W,adv=0)[0]-39.2)<1e-9
# Dead heat k=2, back 5.0: 10*(4.9/2-1)=14.5, *0.98=14.21. Lay: 2.439024*(5.1/2-1)=3.780488 lost.
assert abs(back_pl(A(5.0),W,k=2)[0]-14.21)<1e-9 and abs(lay_pl(A(5.0),W,k=2)[0]+3.780488)<1e-6
# Dead heat below evens: back 1.5 k=2 fill 1.49: 10*(0.745-1)=-2.55, a loss, so no commission. Lay gains.
assert abs(back_pl(A(1.5),W,k=2)[0]+2.55)<1e-9 and lay_pl(A(1.5),W,k=2)[0]>0
# Pass rule at its thresholds.
assert passes(300,150,150,3.5,0.01,0.01,0.15) and not passes(299,150,149,9,1,1,1) and not passes(300,149,151,9,1,1,1)
assert not passes(300,150,150,3.49,1,1,1) and not passes(300,150,150,9,0,1,1) and not passes(300,150,150,9,1,0,1) and not passes(300,150,150,9,1,1,0.149)
print("P&L and pass-rule checks: OK",flush=True)

con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SET work_mem='64MB'"); cur.execute("SET statement_timeout='2400s'")
parts=[]
for y in range(2021,2027):
    parts.append(pd.read_sql(f"""SELECT lower(country) country, lower(market) market, event_id, menu_hint, event_name, event_dt, selection_id, win_lose won,
      bsp::float bsp, NULLIF(ppwap,0)::float ppwap, NULLIF(morningwap,0)::float mwap, NULLIF(ppmax,0)::float ppmax, NULLIF(ppmin,0)::float ppmin,
      morning_vol::float mv, pp_vol::float ppv FROM racing_bsp
      WHERE lower(country) IN ('uk','ire') AND event_dt>='{y}-01-01' AND event_dt<'{y+1}-01-01'""",con))
    print(f"fetched {y}: {len(parts[-1])} rows, {time.time()-T0:.0f}s",flush=True)
con.close()
D=pd.concat(parts,ignore_index=True); del parts
print("raw rows",len(D),"| market values",D.market.value_counts().to_dict(),"| win_lose values",D.won.value_counts(dropna=False).to_dict())
D=D.drop_duplicates(['market','event_id','selection_id'])
D=D[D.market.isin(['win','place'])&D.won.notna()].copy()
# defects found on the first run: win_lose=2 marks a dead heat (20 rows, 2022-01..2023-02, both horses carry it), so a winner is won>=1;
# and a few 'win' rows are really place markets named "2 TBP" / "To Be Placed"
tbp=(D.market=='win')&D.event_name.fillna('').str.contains(r'\bTBP\b|To Be Placed',case=False,regex=True)
print("win rows relabelled place:",int(tbp.sum()),"| races",D[tbp].event_id.nunique(),"| of which in hold-out:",int((tbp&(D.event_dt>=pd.Timestamp('2025-07-01'))).sum()),"| dead-heat rows win_lose=2:",int((D.won==2).sum()))
D.loc[tbp,'market']='place'
D['won']=(D.won>=1).astype(int)
assert D.won.isin([0,1]).all()
D['rid']=D.market+'_'+D.event_id.astype(str)
print("after dedupe",len(D),"| event_ids in both markets:",len(set(D[D.market=='win'].event_id)&set(D[D.market=='place'].event_id)))
# void/no-result races, and dead heats on WIN
w=D.groupby('rid').won.transform('sum'); D['nwin']=w
print("races",D.rid.nunique(),"| no winner, removed:",D[w==0].rid.nunique(),"| WIN races by winners:",D[D.market=='win'].groupby('rid').nwin.first().value_counts().to_dict())
D=D[w>0].copy()
D['k']=np.where(D.market=='win',D.nwin,1).astype(float); D.loc[D.k<1,'k']=1
# field is counted on every row of the race, before any BSP filter, so it does not leak who ran at the off
D['field']=D.groupby('rid').selection_id.transform('size')
D['course']=D.menu_hint.fillna('').str.replace(r'\s+\d.*','',regex=True).str.strip()
D['hour']=D.event_dt.dt.hour; D['dow']=D.event_dt.dt.dayofweek; D['month']=D.event_dt.dt.month
# race type and distance from the WIN market's name, carried to PLACE by course and time
def dist(s):
    mm=re.search(r'\b(\d+)m(\d+)f\b|\b(\d+)m\b|\b(\d+)f\b',str(s))
    if not mm: return np.nan
    a,b,c,d=mm.groups()
    return (int(a)*8+int(b)) if a else (int(c)*8 if c else int(d))
wn=D[D.market=='win'].drop_duplicates(['course','event_dt'])[['course','event_dt','event_name']].copy()
wn['furlongs']=wn.event_name.map(dist)
for name,pat in dict(hrd=r'Hrd|Hurdle',chs=r'Chs|Chase',nhf=r'NHF|INHF',hcap=r'Hcap|Handicap',mdn=r'Mdn|Maiden',nov=r'Nov',stks=r'Stks|Stakes',grp=r'Grp|Group|Gd|Listed',claim=r'Claim|Sell').items():
    wn[name]=wn.event_name.str.contains(pat,case=False,regex=True).astype(float)
wn=wn.drop(columns='event_name')
D=D.merge(wn,how='left',on=['course','event_dt'])
print("distance parsed on",round(D.furlongs.notna().mean()*100,1),"% of rows; PLACE",round(D[D.market=='place'].furlongs.notna().mean()*100,1),"%")
# morning race structure
D['mok']=D.mwap.between(1.01,1000,inclusive='neither')
D['q0']=np.where(D.mok,1/D.mwap,np.nan)
g=D.groupby('rid')
D['or_m']=g.q0.transform('sum'); D['q']=D.q0/D.or_m
D['mv']=D.mv.where(D.mv>0); D['mv_tot']=g.mv.transform('sum'); D['s']=D.mv/D.mv_tot; D['R']=D.s/D.q
D['rank_m']=g.mwap.rank(method='min'); D['fav_m']=g.mwap.transform('min')
D['lmwap']=np.log(D.mwap.where(D.mok)); D['lmv']=np.log1p(D.mv); D['lmv_tot']=np.log1p(D.mv_tot)
# the other market's morning price on the same horse (same race time)
oth=D[['event_dt','selection_id','market','mwap','bsp']].copy(); oth['market']=oth.market.map({'win':'place','place':'win'})
oth=oth.drop_duplicates(['event_dt','selection_id','market']).rename(columns={'mwap':'x_mwap','bsp':'x_bsp'})
D=D.merge(oth,how='left',on=['event_dt','selection_id','market'])
D['lx_mwap']=np.log(D.x_mwap.where(D.x_mwap>1))
D['mkt']=(D.market=='place').astype(float); D['ire']=(D.country=='ire').astype(float); D['course_c']=D.course.astype('category').cat.codes.astype(float)
# trades need a real BSP
D['tr']=D.bsp.between(1.01,1000,inclusive='neither')
print("runners",len(D),"| with BSP",int(D.tr.sum()),"| with morning WAP",int(D.mok.sum()),"| both",int((D.tr&D.mok).sum()),"| dates",D.event_dt.min(),"->",D.event_dt.max(),flush=True)
print("mean morning overround: win",round(D[D.market=='win'].groupby('rid').or_m.first().mean(),3),"place",round(D[D.market=='place'].groupby('rid').or_m.first().mean(),3))
CUT=pd.Timestamp('2025-07-01')
D['y']=np.where(D.won==1,1/D.k,0.0)
D['res']=D.y-1/D.bsp.where(D.tr)
CLEAN_X=['mkt','ire','course_c','field','hour','dow','month','furlongs','hrd','chs','nhf','hcap','mdn','nov','stks','grp','claim','lmwap','q','or_m','rank_m','fav_m','lmv','lmv_tot','s','R','lx_mwap']
D['lbsp']=np.log(D.bsp.where(D.tr)); D['lpp']=np.log(D.ppwap.where(D.ppwap>1)); D['lppv']=np.log1p(D.ppv.where(D.ppv>0))
D['steam_m']=D.lmwap-D.lbsp; D['steam_p']=D.lpp-D.lbsp; D['pprange']=np.log(D.ppmax.where(D.ppmax>1))-np.log(D.ppmin.where(D.ppmin>1)); D['lx_bsp']=np.log(D.x_bsp.where(D.x_bsp>1))
D['rank_b']=D[D.tr].groupby('rid').bsp.rank(method='min')
ITEM_X=CLEAN_X+['lbsp','lpp','lppv','steam_m','steam_p','pprange','lx_bsp','rank_b']
cat=lambda X:[X.index('course_c')]
HO=D[(D.event_dt>=CUT)&D.tr].copy(); MED=HO.event_dt.median(); HO['h2']=HO.event_dt>MED
FIT={'F1':D[(D.event_dt<CUT)&D.tr],'F2':D[(D.event_dt>=pd.Timestamp('2024-01-01'))&(D.event_dt<CUT)&D.tr]}
print(f"hold-out {HO.event_dt.min()} -> {HO.event_dt.max()} | {len(HO)} runners, {HO.rid.nunique()} markets | median {MED}")
for k_,f in FIT.items(): print(f"fit {k_}: {len(f)} runners, {f.rid.nunique()} markets, {f.event_dt.min()} -> {f.event_dt.max()}",flush=True)
assert FIT['F1'].event_dt.max()<HO.event_dt.min()
kw=dict(learning_rate=0.05,max_iter=300,max_leaf_nodes=15,min_samples_leaf=200,l2_regularization=1.0,early_stopping=False,random_state=48)
BANDS=[1,3,6,12,30,1000]; BL=['<3','3-6','6-12','12-30','30+']
# F3: same window as F1, far simpler trees. Added AFTER the first run showed in-sample +4 to +10 v hold-out about 0, to ask whether overfitting hid an edge.
# Chosen after seeing that hold-out, so a pass on F3 alone would be suspect.
kw3=dict(learning_rate=0.03,max_iter=100,max_leaf_nodes=6,min_samples_leaf=2000,l2_regularization=10.0,early_stopping=False,random_state=48)
def models(F,tag,kw=kw):
    t=time.time(); F=F.copy(); O=HO.copy()
    Fc=F[F.mok]; rc=HGR(categorical_features=cat(CLEAN_X),**kw).fit(Fc[CLEAN_X],Fc.res)
    ci=HGC(categorical_features=cat(ITEM_X),**kw).fit(F[ITEM_X],(F.won==1).astype(int))
    for X_ in (F,O):
        X_['m_CLEAN']=np.where(X_.mok,rc.predict(X_[CLEAN_X])*X_.mwap.where(X_.mok),np.nan)
        X_['p_ITEM']=ci.predict_proba(X_[ITEM_X])[:,1]; X_['m_ITEM']=X_.p_ITEM*X_.bsp-1
    print(f"models {tag}: {time.time()-t:.0f}s",flush=True)
    return F,O
def stats(x,col_h='h2'):
    v=x.v.values; n=len(v); mu=v.mean(); sd=v.std(ddof=0) or 1e-9
    gr=x.groupby('rid').v.sum(); nr=len(gr); tc=mu*n/(gr.std(ddof=0)*np.sqrt(nr)) if nr>1 and gr.std(ddof=0)>0 else 0.0
    return n,nr,mu,mu/(sd/np.sqrt(n)),tc
rows=[]
def cells(F,O,tag,bands_all_only):
    for sig,mc,bc in (('CLEAN','m_CLEAN','mwap'),('AS_ITEM','m_ITEM','bsp')):
        for X_,name in ((O,'o'),(F,'f')):
            X_['bb_'+sig]=pd.cut(X_[bc],BANDS,labels=BL).astype(object)
        for shape,pl in (('BACK',back_pl),('LAY',lay_pl)):
            for X_ in (O,F):
                won=X_.won.values==1
                X_['v1']=pl(X_.bsp.values,won,k=X_.k.values,adv=1); X_['v0']=pl(X_.bsp.values,won,k=X_.k.values,adv=0)
            for mkt in ('win','place'):
                Om=O[O.market==mkt]; Fm=F[F.market==mkt]
                for thr in (0.05,0.10,0.20):
                    so=Om[Om[mc]>=thr] if shape=='BACK' else Om[Om[mc]<=-thr]
                    sf=Fm[Fm[mc]>=thr] if shape=='BACK' else Fm[Fm[mc]<=-thr]
                    for sel in ('ALL','TOP1'):
                        if sel=='TOP1':
                            pick=lambda s:s.loc[(s.groupby('rid')[mc].idxmax() if shape=='BACK' else s.groupby('rid')[mc].idxmin())] if len(s) else s
                            so_,sf_=pick(so),pick(sf)
                        else: so_,sf_=so,sf
                        for band in (['ALL'] if bands_all_only else ['ALL']+BL):
                            a=so_ if band=='ALL' else so_[so_['bb_'+sig]==band]
                            b=sf_ if band=='ALL' else sf_[sf_['bb_'+sig]==band]
                            if len(a)<20: continue
                            x=a.assign(v=a.v1); n,nr,mu,t,tc=stats(x)
                            a1=x[~x.h2].v; a2=x[x.h2].v
                            rows.append(dict(fit=tag,sig=sig,shape=shape,mkt=mkt,m=thr,sel=sel,band=band,n=n,markets=nr,mean=mu,t=t,tc=tc,n1=len(a1),h1=a1.mean() if len(a1) else np.nan,n2=len(a2),h2=a2.mean() if len(a2) else np.nan,mean0=a.v0.mean(),maxwin=x.v.max(),ex_top=(x.v.sum()-x.v.max())/max(n-1,1),in_n=len(b),in_mean=b.v1.mean() if len(b) else np.nan))
F1,O1=models(FIT['F1'],'F1'); cells(F1,O1,'F1',False)
F2,O2=models(FIT['F2'],'F2'); cells(F2,O2,'F2',True)
F3,O3=models(FIT['F1'],'F3',kw3); cells(F3,O3,'F3',False)
R=pd.DataFrame(rows)
R['PASS']=[passes(r.n,r.n1,r.n2,r.t,r.h1,r.h2,r.mean) for r in R.itertuples()]
print(f"\n== {len(R)} lines scored on the hold-out, {time.time()-T0:.0f}s. Bonferroni for this many lines: z about {abs(__import__('scipy.stats').stats.norm.ppf(0.025/len(R))):.2f}")
print("\n== CONTROLS, hold-out, no model")
ctl=[]
for mkt in ('win','place'):
    x=HO[HO.market==mkt]; won=x.won.values==1
    for sh,pl in (('BACK',back_pl),('LAY',lay_pl)):
        v1=pl(x.bsp.values,won,k=x.k.values,adv=1); v0=pl(x.bsp.values,won,k=x.k.values,adv=0)
        ctl.append(dict(mkt=mkt,shape=sh,n=len(x),mean=v1.mean(),mean0=v0.mean(),t=v1.mean()/(v1.std()/np.sqrt(len(v1))),h1=v1[~x.h2.values].mean(),h2=v1[x.h2.values].mean()))
print(pd.DataFrame(ctl).round(3).to_string(index=False))
print("\n== CALIBRATION, hold-out, AS_ITEM model p and BSP-implied v actual, by decile of model p (F1)")
for mkt in ('win','place'):
    x=O1[O1.market==mkt].copy(); x['d']=pd.qcut(x.p_ITEM,10,duplicates='drop',labels=False)
    print(mkt); print(x.groupby('d',observed=True).agg(n=('y','size'),p_model=('p_ITEM','mean'),p_bsp=('bsp',lambda s:(1/s).mean()),actual=('y','mean')).round(4).to_string())
print("\n== CLEAN margin decile v realised return at exact BSP, hold-out (F1). ret = mean(y x BSP - 1), and the same without BSP > 30")
for mkt in ('win','place'):
    x=O1[(O1.market==mkt)&O1.mok].copy(); x['d']=pd.qcut(x.m_CLEAN,10,duplicates='drop',labels=False); x['ret']=x.y*x.bsp-1
    print(mkt); print(x.groupby('d',observed=True).agg(n=('y','size'),margin=('m_CLEAN','mean'),ret=('ret','mean'),ret_u30=('ret',lambda s:s[x.loc[s.index,'bsp']<=30].mean())).round(4).to_string())
print("\n== CLEAN in-sample v hold-out, F1, ALL bands")
print(R[(R.fit=='F1')&(R.sig=='CLEAN')&(R.band=='ALL')&(R.sel=='ALL')][['shape','mkt','m','n','mean','t','h1','h2','mean0','in_n','in_mean']].round(3).to_string(index=False))
show=['fit','sig','shape','mkt','m','sel','band','n','markets','mean','t','tc','h1','h2','mean0','maxwin','ex_top','in_mean','PASS']
print("\n== CLEAN in-sample v hold-out, F3 (simple trees), ALL bands")
print(R[(R.fit=='F3')&(R.sig=='CLEAN')&(R.band=='ALL')&(R.sel=='ALL')][['shape','mkt','m','n','mean','t','h1','h2','mean0','in_n','in_mean']].round(3).to_string(index=False))
print("\n== TOP 15 CLEAN by t, n>=300"); print(R[(R.sig=='CLEAN')&(R.n>=300)].sort_values('t',ascending=False).head(15)[show].round(3).to_string(index=False))
print("\n== TOP 15 CLEAN one per race by t, n>=150"); print(R[(R.sig=='CLEAN')&(R.sel=='TOP1')&(R.n>=150)].sort_values('t',ascending=False).head(15)[show].round(3).to_string(index=False))
print("\n== TOP 15 AS_ITEM by t, n>=300 (signal uses BSP: cannot pass)"); print(R[(R.sig=='AS_ITEM')&(R.n>=300)].sort_values('t',ascending=False).head(15)[show].round(3).to_string(index=False))
print(f"\n== AS_ITEM numeric passes (not tradable as tested): {int((R.PASS&(R.sig=='AS_ITEM')).sum())}")
print(R[R.PASS&(R.sig=='AS_ITEM')].sort_values('t',ascending=False).head(15)[show].round(3).to_string(index=False))
S=R[R.PASS&(R.sig=='CLEAN')].sort_values('t',ascending=False)
print(f"\n== SURVIVORS (CLEAN only): {len(S)}")
print(S[show].round(3).to_string(index=False) if len(S) else "none")
print(f"\ntotal {time.time()-T0:.0f}s")
PY
