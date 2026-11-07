#!/bin/bash
set -o pipefail
# 499_race_distance (Finder 2026-11-07, queue items 363, 364, Finder's own, sources d and c; engine from jobs/499_course_winner.sh): race distance by price band, and bank-holiday cards, at BSP. Rules pushed in the queue before any price. Read only, no tables written. The box holds part of racing only.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,re,time,datetime as dtm,psycopg2,pandas as pd,numpy as np
from dateutil.easter import easter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import LD,tstat,passes
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',100); pd.set_option('display.max_columns',40)
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
def furlongs(name):
    """'1m3f Hcap' -> 11; '6f Hcap' -> 6; '2m Hcap Hrd' -> 16; no leading distance -> None."""
    m=re.match(r'^\s*(?:(\d+)m)?\s*(?:(\d+)(?:\.\d+)?f)?(?=\s|$)',str(name))
    if not m or (m.group(1) is None and m.group(2) is None): return None
    return 8*int(m.group(1) or 0)+int(m.group(2) or 0)
def jump(name): return bool(re.search(r'\b(Hrd|Chs|NHF|Hurdle|Chase)\b',str(name)))
def dist_group(name):
    f=furlongs(name)
    if f is None: return None
    if jump(name): return 'JUMP <2m4f' if f<20 else 'JUMP 2m4f-2m7f' if f<24 else 'JUMP 3m+'
    return 'FLAT <=6f' if f<=6 else 'FLAT 7f-1m' if f<=8 else 'FLAT 1m1f-1m4f' if f<=12 else 'FLAT 1m5f+'
def nth_mon(y,m,n):
    d=dtm.date(y,m,1); d+=dtm.timedelta(days=(7-d.weekday())%7); return d+dtm.timedelta(days=7*(n-1))
def last_mon(y,m):
    d=dtm.date(y,m+1,1)-dtm.timedelta(days=1); return d-dtm.timedelta(days=d.weekday())
def holidays(y,ctry):
    e=easter(y); h={dtm.date(y,12,26),dtm.date(y,12,27),dtm.date(y,1,1),e-dtm.timedelta(days=2),e+dtm.timedelta(days=1),nth_mon(y,5,1),last_mon(y,5)}
    if ctry=='ire': h|={nth_mon(y,8,1),nth_mon(y,6,1),last_mon(y,10)}
    else: h|={last_mon(y,8)}
    return h
# known answers, worked by hand
assert furlongs('1m3f Hcap')==11 and furlongs('6f Hcap')==6 and furlongs('2m Hcap Hrd')==16 and furlongs('2m4f Hcap Chs')==20 and furlongs('3m Hcap Chs')==24 and furlongs('Hcap')is None and furlongs('1m Mdn Stks')==8
assert dist_group('5f Hcap')=='FLAT <=6f' and dist_group('7f Nov Stks')=='FLAT 7f-1m' and dist_group('1m Hcap')=='FLAT 7f-1m' and dist_group('1m1f Hcap')=='FLAT 1m1f-1m4f' and dist_group('1m4f Hcap')=='FLAT 1m1f-1m4f' and dist_group('1m6f Hcap')=='FLAT 1m5f+' and dist_group('2m Hcap')=='FLAT 1m5f+'
assert dist_group('2m Mdn Hrd')=='JUMP <2m4f' and dist_group('2m NHF')=='JUMP <2m4f' and dist_group('2m4f Mdn Hrd')=='JUMP 2m4f-2m7f' and dist_group('3m Hcap Chs')=='JUMP 3m+' and dist_group('To Be Placed') is None
assert easter(2025)==dtm.date(2025,4,20) and dtm.date(2025,4,18) in holidays(2025,'gb') and dtm.date(2025,4,21) in holidays(2025,'gb')
assert nth_mon(2025,5,1)==dtm.date(2025,5,5) and last_mon(2025,5)==dtm.date(2025,5,26) and last_mon(2025,8)==dtm.date(2025,8,25) and nth_mon(2025,8,1)==dtm.date(2025,8,4) and last_mon(2025,10)==dtm.date(2025,10,27)
assert dtm.date(2025,8,25) in holidays(2025,'gb') and dtm.date(2025,8,25) not in holidays(2025,'ire') and dtm.date(2025,8,4) in holidays(2025,'ire') and dtm.date(2025,8,4) not in holidays(2025,'gb')
assert back_px(11.2)==11.0 and lay_px(2.0)==2.02 and abs(pnl_back(3.0,1)-19.6)<1e-9 and pnl_lay(3.0,1)==-10 and abs(pnl_lay(3.0,0)-4.9)<1e-9 and pnl_lay(3.0,2)==-2.5
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
W=pd.read_sql("SELECT country,event_id,event_dt,menu_hint,event_name,selection_id,win_lose,bsp::float bsp,morningwap::float mw FROM racing_bsp WHERE market='win' AND bsp IS NOT NULL AND bsp>1",con); con.close()
W['day']=pd.to_datetime(W.event_dt,utc=True).dt.tz_convert('Europe/London').dt.date
print(f"win runners {len(W):,} races {W.event_id.nunique():,}; {W.day.min()} to {W.day.max()}; countries {W.country.value_counts().to_dict()}; {time.time()-T0:.0f}s",flush=True)
names=W.event_name.drop_duplicates(); g=dict(zip(names,names.map(dist_group))); W['dg']=W.event_name.map(g)
print("no distance read: races",W[W.dg.isna()].event_id.nunique(),"e.g.",W[W.dg.isna()].event_name.drop_duplicates().head(6).tolist(),flush=True)
print("races by group",W.drop_duplicates('event_id').dg.value_counts().to_dict(),flush=True)
HOL={}
for y in sorted({d.year for d in W.day}):
    for c in W.country.unique(): HOL[(y,c)]=holidays(y,c)
W['hol']=[d in HOL[(d.year,c)] for d,c in zip(W.day,W.country)]
print("holiday races",W[W.hol].event_id.nunique(),"days",W[W.hol].day.nunique(),"by day",W[W.hol].drop_duplicates('event_id').groupby('day').size().sort_values(ascending=False).head(8).to_dict(),flush=True)
med=W.day.sort_values().iloc[len(W)//2]; print("halves split at",med,flush=True)
BANDS={'all':lambda m:m>0,'<=5':lambda m:(m>0)&(m<=5),'5-15':lambda m:(m>5)&(m<=15),'>15':lambda m:m>15}
def rows(state,base,tag):
    out=[]
    for b,fn in BANDS.items():
        x=base[fn(base.mw)]
        if len(x)<30: continue
        for side in ('BACK','LAY'):
            a=back_px(x.bsp.values) if side=='BACK' else lay_px(x.bsp.values)
            keep=a>1.01; y=x[keep]; a=a[keep]
            v=pnl_back(a,y.win_lose.values) if side=='BACK' else pnl_lay(a,y.win_lose.values)
            h=(y.day.values<=med); by=pd.Series(v).groupby(y.event_id.values).sum()
            n1,n2=int(h.sum()),int((~h).sum()); m1=v[h].mean() if n1 else np.nan; m2=v[~h].mean() if n2 else np.nan; t=tstat(v); tr=tstat(by.values)
            out.append(dict(tag=tag,state=state,band=b,side=side,n=len(v),races=len(by),per10=round(v.mean(),3),t=round(t,2),t_race=round(tr,2),h1=round(m1,3),h2=round(m2,3),maxwin=round(v.max(),1),won=round(float((y.win_lose==1).mean()),3),imp=round(float((1/y.bsp).mean()),3),PASS=bool(passes(len(v),n1,n2,t,m1,m2,v.mean()) and tr>=3.5)))
    return out
D=[]
for s,x in W[W.dg.notna()].groupby('dg'): D+=rows(s,x,'363')
D+=rows('CONTROL',W[W.dg.notna()],'ctl')
H=rows('HOLIDAY',W[W.hol],'364')+rows('OTHER DAYS',W[~W.hol],'ctl')
A=pd.DataFrame(D); B=pd.DataFrame(H)
print(f"\n== item 363, {int((A.tag=='363').sum())} lines by t\n",A[A.tag=='363'].sort_values('t',ascending=False).drop(columns='tag').to_string(index=False))
print("\n-- control\n",A[A.tag=='ctl'].drop(columns='tag').to_string(index=False))
print(f"\n== item 364, {int((B.tag=='364').sum())} lines by t\n",B[B.tag=='364'].sort_values('t',ascending=False).drop(columns='tag').to_string(index=False))
print("\n-- control\n",B[B.tag=='ctl'].drop(columns='tag').to_string(index=False))
P=pd.concat([A[(A.tag=='363')&A.PASS],B[(B.tag=='364')&B.PASS]])
print(f"\n== SURVIVORS: {len(P)}\n",P.to_string(index=False) if len(P) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
