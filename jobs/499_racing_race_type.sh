#!/bin/bash
set -o pipefail
# 499_racing_race_type (Finder 2026-11-06, queue items 204, 205, Finder's own, source c): race type by price band, and festival days, at BSP. Rules pushed before any price was read. The number 499 is reused: 450-499 are all taken.
# DATA racing_bsp win markets, UK/IE. A race is used only if every runner has a BSP, a ppwap and a pp_vol and the 1/ppwap book is 1.00-1.40, as jobs/499_racing_money_share.sh.
# ENTRY BSP, one tick adverse, 2% on profit, £10 risk, to result, nothing dropped; dead heats as jobs/499_race_shape.sh. Bands on ppwap, never BSP.
# LIMIT ppwap runs to the off, so a live rule needs the last minutes' figures: read a pass as an upper bound. The box holds part of each year's racing. Item 90 read HCAP, MDN_NOV and NHF for FAV, SECOND and LONG30 only; this is finer, so it partly overlaps.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))  # this job only: MemoryError rather than the box's OOM killer
import sys,time,re,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import LD,tstat,passes
from lib_wom import tgame
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time()
def back_px(p):
    p=np.asarray(p,dtype=float); return LD[np.clip(np.searchsorted(LD,p-1e-9,side='left')-1,0,len(LD)-1)]
def lay_px(p):
    p=np.asarray(p,dtype=float); return LD[np.clip(np.searchsorted(LD,p+1e-9,side='right'),0,len(LD)-1)]
def pnl_back(a,wl):
    a=np.asarray(a,dtype=float); wl=np.asarray(wl); g=np.where(wl==1,10*(a-1),np.where(wl==2,5*(a-1)-5,-10.0))
    return np.where(g>0,g*.98,g)
def pnl_lay(a,wl):
    a=np.asarray(a,dtype=float); wl=np.asarray(wl); s=10/(a-1); g=np.where(wl==1,-10.0,np.where(wl==2,-5+s/2,s))
    return np.where(g>0,g*.98,g)
BANDS=[(0,3,'<=3'),(3,6,'3-6'),(6,12,'6-12'),(12,30,'12-30'),(30,1e9,'30+')]
def band(p):
    p=np.asarray(p,dtype=float); o=np.empty(len(p),dtype=object)
    for lo,hi,n in BANDS: o[(p>lo)&(p<=hi)]=n
    return o
def race_type(name):
    s=str(name)
    w=lambda pat:re.search(r'(?i)\b(?:'+pat+r')\b',s) is not None
    d='NHF' if w('nhf|inhf') else 'CHS' if w('chs|chase') else 'HRD' if w('hrd|hurdle') else 'FLAT'
    if d=='NHF': return 'NHF'
    c='HCAP' if w('hcap') else 'MDN' if w(r'mdn\w*|nov\w*') else 'OTHER'
    return d+'_'+c
FEST=[('Cheltenham',(3,10),(3,20)),('Aintree',(4,1),(4,15)),('Punchestown',(4,20),(5,10)),('Epsom',(6,1),(6,10)),('Ascot',(6,14),(6,25)),('Goodwood',(7,25),(8,6)),('Galway',(7,25),(8,6)),('York',(8,15),(8,30)),('Doncaster',(9,8),(9,16)),('Kempton',(12,26),(12,27)),('Leopardstown',(12,26),(12,29))]
def is_fest(hint,month,day):
    c=str(hint).split(' / ')[-1]; md=(month,day)
    return any(c.startswith(k) and a<=md<=b for k,a,b in FEST)
# known answers, worked by hand
assert back_px(11.2)==11.0 and lay_px(11.2)==11.5 and back_px(2.0)==1.99 and lay_px(2.0)==2.02
assert abs(pnl_back(3.0,1)-19.6)<1e-9 and pnl_back(3.0,0)==-10 and abs(pnl_back(3.0,2)-4.9)<1e-9
assert abs(pnl_lay(3.0,0)-4.9)<1e-9 and pnl_lay(3.0,1)==-10 and pnl_lay(3.0,2)==-2.5
assert list(band([3,3.01,6,12,30,30.5]))==['<=3','3-6','3-6','6-12','12-30','30+']
assert race_type('2m Hcap Hrd')=='HRD_HCAP' and race_type('2m4f Nov Chs')=='CHS_MDN' and race_type('1m6f NHF')=='NHF' and race_type('6f Hcap')=='FLAT_HCAP' and race_type('1m Mdn Stks')=='FLAT_MDN' and race_type('7f Grp3')=='FLAT_OTHER' and race_type('2m Grd1 Hrd')=='HRD_OTHER' and race_type('2m INHF')=='NHF'
assert race_type('5f Novice Stks')=='FLAT_MDN' and race_type('5f Maiden Stks')=='FLAT_OTHER'   # Nov as a word start, as the rule; "Maiden" spelled out is not Mdn, counted below
assert is_fest('GB / Cheltenham 12th Mar',3,12) and not is_fest('GB / Cheltenham 12th Apr',4,12) and is_fest('GB / York 15th Aug',8,15) and is_fest('GB / York 30th Aug',8,30) and not is_fest('GB / York 31st Aug',8,31) and not is_fest('IRE / Galway 1st Sep',9,1) and is_fest('IRE / Galway 1st Aug',8,1) and is_fest('GB / Kempton 26th Dec',12,26) and not is_fest('GB / Kempton 28th Dec',12,28) and not is_fest('GB / Ascot 26th Jun',6,26)
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
R=pd.read_sql("SELECT country,event_id,event_name,menu_hint,event_dt,selection_id,win_lose,bsp::float8 bsp,ppwap::float8 ppwap,pp_vol::float8 pp_vol FROM racing_bsp WHERE market='win'",con); con.close()
print(f"win rows {len(R):,}, races {R.event_id.nunique():,}, countries {R.country.value_counts().to_dict()}, dates {R.event_dt.min()} to {R.event_dt.max()}, win_lose {R.win_lose.value_counts(dropna=False).to_dict()}, {time.time()-T0:.0f}s",flush=True)
bad=R.bsp.isna()|(R.bsp<=1)|R.ppwap.isna()|(R.ppwap<=1)|R.pp_vol.isna()|R.win_lose.isna()
W=R[~R.event_id.isin(set(R.event_id[bad]))].copy(); bk=(1/W.ppwap).groupby(W.event_id).sum(); ok=bk[(bk>=1.0)&(bk<=1.40)].index; W=W[W.event_id.isin(ok)]
print(f"complete races {len(bk):,}, book 1.00-1.40 {len(ok):,}, runners {len(W):,}",flush=True)
names=W.drop_duplicates('event_id')
TY={n:race_type(n) for n in names.event_name.unique()}; W['ty']=W.event_name.map(TY); W['bd']=band(W.ppwap.values)
dt=pd.to_datetime(W.event_dt); W['ts']=dt.astype('int64')/1e9
key=pd.DataFrame(dict(h=W.menu_hint,m=dt.dt.month,d=dt.dt.day)).drop_duplicates(); key['f']=[is_fest(a,b,c) for a,b,c in zip(key.h,key.m,key.d)]
FE={(a,b,c):f for a,b,c,f in zip(key.h,key.m,key.d,key.f)}; W['fest']=[FE[k] for k in zip(W.menu_hint,dt.dt.month,dt.dt.day)]
r=W.groupby('event_id').ppwap.rank(method='min'); tie=W.groupby('event_id').ppwap.transform(lambda s:(s==s.min()).sum())>1; W['fav']=(r==1)&(~tie)
print("races by type:",W.drop_duplicates('event_id').ty.value_counts().to_dict(),flush=True)
print("race names with the word Maiden spelled out, left in OTHER, counted, not moved:",int(names.event_name.str.contains(r'(?i)\bmaiden\b',regex=True).sum()),flush=True)
F=W.drop_duplicates('event_id'); F2=F[F.fest]; print(f"festival races {len(F2):,}, by course {F2.menu_hint.str.split(' / ').str[-1].str.split(' ').str[0].value_counts().to_dict()}",flush=True)
W['vb']=pnl_back(back_px(W.bsp.values),W.win_lose.values); W['vl']=pnl_lay(lay_px(W.bsp.values),W.win_lose.values)
def tab(x,col,**k):
    v=x[col].values; md=np.median(x.ts.values); h=x.ts.values<md; a,b=v[h],v[~h]
    return dict(**k,n=len(v),races=x.event_id.nunique(),per10=v.mean(),t=tstat(v),tr=tgame(v,x.event_id.values),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,won=(x.win_lose==1).mean(),imp=(1/x.bsp).mean(),maxwin=v.max(),PASS=passes(len(v),len(a),len(b),tstat(v),a.mean() if len(a) else 0,b.mean() if len(b) else 0,v.mean()))
CTL={}
for (bd,),x in W.groupby(['bd']):
    for s,c in (('back','vb'),('lay','vl')): CTL[(bd,s)]=x[c].mean()
out=[]
for (ty,bd),x in W.groupby(['ty','bd']):
    for s,c in (('back','vb'),('lay','vl')): out.append(tab(x,c,ty=ty,band=bd,side=s,ctrl=CTL[(bd,s)]))
A=pd.DataFrame(out).sort_values('t',ascending=False); print(f"\n== ITEM 204 race type by band: {len(A)} lines, top 15 by t, then worst 3; ctrl = same band and side, all races"); print(A.head(15).round(3).to_string(index=False)); print(A.tail(3).round(3).to_string(index=False))
print("-- all races by band, the control:"); print(pd.DataFrame([tab(x,c,band=bd,side=s) for bd,x in W.groupby('bd') for s,c in (('back','vb'),('lay','vl'))]).drop(columns=['PASS']).round(3).to_string(index=False))
out=[]
for f,xf in W.groupby('fest'):
    lab='FEST' if f else 'NOT'
    for bd,x in xf.groupby('bd'):
        for s,c in (('back','vb'),('lay','vl')): out.append(tab(x,c,state=lab,line=bd,side=s))
    x=xf[xf.fav]
    for s,c in (('back','vb'),('lay','vl')): out.append(tab(x,c,state=lab,line='FAV',side=s))
B=pd.DataFrame(out); T=B[B.state=='FEST'].sort_values('t',ascending=False); C=B[B.state=='NOT'].sort_values('t',ascending=False)
print(f"\n== ITEM 205 festival days: {len(T)} lines by t"); print(T.round(3).to_string(index=False)); print("-- control, other races, cannot pass"); print(C.round(3).to_string(index=False))
S=pd.concat([A[A.PASS==True],T[T.PASS==True]]); print(f"\n== SURVIVORS: {len(S)}"); print(S.round(3).to_string(index=False) if len(S) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
