#!/bin/bash
set -o pipefail
# 499_course_winner (Finder 2026-11-07, queue item 356, Finder's own, source d; engine from jobs/499_horse_last_run.sh, course parser from jobs/499_course_trip.sh): course form at BSP. Rule pushed in the queue before any price. Read only, no tables written. History is the part of racing on the box, so states are noisy, as item 81.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,re,time,psycopg2,pandas as pd,numpy as np
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
def course(h):
    s=re.sub(r'^[A-Z]+\s*/\s*','',str(h)).strip()
    return re.sub(r'\s+\d{1,2}(st|nd|rd|th)\s+\w+$','',s).strip()
def form(rows):
    """rows: (selection,day,course,win_lose) in any order. Returns state per row, from EARLIER dates only: CW won here, CR ran here without a win, NEW ran elsewhere only, None no history. A dead heat (2) counts as a win here."""
    o=sorted(range(len(rows)),key=lambda i:(rows[i][0],rows[i][1])); out=[None]*len(rows); i=0
    while i<len(o):
        j=i
        while j<len(o) and rows[o[j]][0]==rows[o[i]][0]: j+=1
        won=set(); ran=set(); k=i
        while k<j:
            m=k
            while m<j and rows[o[m]][1]==rows[o[k]][1]: m+=1
            for q in o[k:m]:
                c=rows[q][2]; out[q]='CW' if c in won else 'CR' if c in ran else 'NEW' if ran else None
            for q in o[k:m]:
                c=rows[q][2]; ran.add(c)
                if rows[q][3] in (1,2): won.add(c)
            k=m
        i=j
    return out
# known answers, worked by hand
assert course('GB / Uttoxeter 31st Dec')=='Uttoxeter' and course('IRE / Listowel 22nd Sep')=='Listowel' and course('Kempton 14th Jan')=='Kempton'
assert back_px(11.2)==11.0 and lay_px(2.0)==2.02 and abs(pnl_back(3.0,1)-19.6)<1e-9 and pnl_lay(3.0,1)==-10 and abs(pnl_lay(3.0,0)-4.9)<1e-9 and pnl_lay(3.0,2)==-2.5
_f=form([(7,1,'A',0),(7,2,'B',1),(7,2,'A',0),(7,3,'B',0),(7,4,'A',0),(8,2,'B',0),(7,5,'C',1),(7,6,'C',0)])
assert _f==[None,'NEW','CR','CW','CR',None,'NEW','CW']
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
W=pd.read_sql("SELECT event_id,event_dt,menu_hint,selection_id,win_lose,bsp::float bsp,morningwap::float mw FROM racing_bsp WHERE market='win' AND bsp IS NOT NULL AND bsp>1",con); con.close()
W['day']=pd.to_datetime(W.event_dt,utc=True).dt.tz_convert('Europe/London').dt.date; W['course']=W.menu_hint.map(course)
print(f"win runners {len(W)} races {W.event_id.nunique()} courses {W.course.nunique()}; {W.day.min()} to {W.day.max()}; {time.time()-T0:.0f}s",flush=True)
W['st']=form(list(zip(W.selection_id,W.day,W.course,W.win_lose)))
print("states",W.st.value_counts(dropna=False).to_dict(),flush=True)
med=W.day.sort_values().iloc[len(W)//2]; print("halves split at",med)
BANDS={'all':lambda m:m>0,'<=5':lambda m:(m>0)&(m<=5),'5-15':lambda m:(m>5)&(m<=15),'>15':lambda m:m>15}
rows=[]
for st,base in list(W[W.st.notna()].groupby('st'))+[('CONTROL',W[W.st.notna()])]:
    for b,fn in BANDS.items():
        x=base[fn(base.mw)]
        if len(x)<30: continue
        for side in ('BACK','LAY'):
            a=back_px(x.bsp.values) if side=='BACK' else lay_px(x.bsp.values)
            keep=a>1.01; y=x[keep]; a=a[keep]
            v=pnl_back(a,y.win_lose.values) if side=='BACK' else pnl_lay(a,y.win_lose.values)
            h=(y.day.values<=med); by=pd.Series(v).groupby(y.event_id.values).sum()
            n1,n2=int(h.sum()),int((~h).sum()); m1=v[h].mean() if n1 else np.nan; m2=v[~h].mean() if n2 else np.nan; t=tstat(v); tr=tstat(by.values)
            rows.append(dict(state=st,band=b,side=side,n=len(v),races=len(by),per10=round(v.mean(),3),t=round(t,2),t_race=round(tr,2),h1=round(m1,3),h2=round(m2,3),maxwin=round(v.max(),1),won=round(float((y.win_lose==1).mean()),3),imp=round(float((1/y.bsp).mean()),3),PASS=bool(st!='CONTROL' and passes(len(v),n1,n2,t,m1,m2,v.mean()) and tr>=3.5)))
L=pd.DataFrame(rows); A=L[L.state!='CONTROL'].sort_values('t',ascending=False)
print(f"\nlines {len(A)} of a possible 24, at n>=300 {(A.n>=300).sum()}\n",A.to_string(index=False)); print("\n-- control\n",L[L.state=='CONTROL'].to_string(index=False))
P=A[A.PASS]; print(f"\n== SURVIVORS: {len(P)}\n",P.to_string(index=False) if len(P) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
