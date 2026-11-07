#!/bin/bash
set -o pipefail
# 499_ip_low_print_all (Finder 2026-11-07, queue item 383, Finder's own, source a, from item 380): the first in-play print at a low level on the 25-month racing tape, results from racing_bsp. Rule pushed before any price was scored. Read only. Cross-check only: minute prints, and one can fall after the post, so no line can pass.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))  # this job only
import sys,re,time,psycopg2,warnings,pandas as pd,numpy as np
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,lay_settle,tstat
from lib_wom import tgame
pd.set_option('display.width',230); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',30)
T0=time.time()
def nm(s): return re.sub(r'[^a-z0-9]','',re.sub(r'^\s*\d+\.\s*','',re.sub(r'\([^)]*\)','',str(s))).lower())
def first_cross(px,q):
    """index of the first print <= q after an earlier print > q, else None"""
    px=np.asarray(px,float)
    if len(px)<2 or px[0]<=q: return None
    h=np.where(px<=q)[0]
    return int(h[0]) if len(h) else None
def bk(p,w):
    a=step(p,-1); return np.nan if a<=1.01 else back_settle(a,w)
def ly(p,w): return lay_settle(step(p,1),w)
assert nm('1. Wine Dark Sea (IRE)')=='winedarksea' and first_cross([3,2.5,1.9,1.5],2)==2 and first_cross([1.9,1.5],2) is None and first_cross([3,2.5],2) is None and first_cross([3],2) is None
assert abs(bk(1.2,True)-10*.19*.98)<1e-9 and bk(1.2,False)==-10.0 and np.isnan(bk(1.02,True)) and ly(1.2,True)==-10.0
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
R=pd.read_sql("SELECT menu_hint course,event_id,event_dt,selection_name,win_lose,bsp::float8 bsp FROM racing_bsp WHERE market='win' AND win_lose IS NOT NULL AND bsp>1",con)
R['ts']=pd.to_datetime(R.event_dt).dt.tz_localize('Europe/London',ambiguous='NaT',nonexistent='NaT'); R=R[R.ts.notna()]; R['t']=(R.ts-pd.Timestamp('1970-01-01',tz='UTC'))/pd.Timedelta(seconds=1); R['n']=R.selection_name.map(nm)
key={(c,round(t),n):(w,b,e) for c,t,n,w,b,e in zip(R.course,R.t,R.n,R.win_lose,R.bsp,R.event_id)}; print(f"racing_bsp rows {len(R):,}, {time.time()-T0:.0f}s",flush=True)
cur.execute("""SELECT event_name,extract(epoch from market_time)::float8,sel,extract(epoch from ts)::float8,ltp::float8 FROM bf_hist_other o JOIN (SELECT DISTINCT market_id,sel FROM bf_hist_other WHERE sport='Horse Racing' AND market_type='WIN' AND country IN ('GB','IE') AND inplay AND ltp>=1.01 AND ltp<=3) x USING (market_id,sel) WHERE o.sport='Horse Racing' AND o.market_type='WIN' AND o.country IN ('GB','IE') AND o.inplay AND o.ltp>=1.01 AND o.ltp<1000""")   # only runners that print at 3 or under, the only ones that can enter, as the full pull is too large
P=pd.DataFrame(cur.fetchall(),columns='course mt sel ts ltp'.split()); con.close(); print(f"in-play prints {len(P):,}, races {P.groupby(['course','mt']).ngroups:,}, {time.time()-T0:.0f}s",flush=True)
print("prints per runner, median",P.groupby(['course','mt','sel']).size().median(),"seconds from the off of the first print, median",(P.ts-P.mt).groupby([P.course,P.mt,P.sel]).min().median(),flush=True)
rows=[]; hit=miss=0
for (c,mt,s),x in P.sort_values('ts',kind='stable').groupby(['course','mt','sel'],sort=False):
    k=key.get((c,round(mt),nm(s)))
    if k is None: miss+=1; continue
    hit+=1; px=x.ltp.values; tt=x.ts.values; w=k[0]; won=w==1
    if w==2: continue
    for q in (3,2,1.5,1.3,1.2,1.1):
        i=first_cross(px,q)
        if i is None: continue
        pb=px[i]; pl=px[i]
        if i+1<len(px) and tt[i+1]-tt[i]<=120: pb=min(pb,px[i+1]); pl=max(pl,px[i+1])
        v=bk(pb,won)
        if v==v: rows.append((q,'back',k[2],mt,pb,won,v,k[1]))
        rows.append((q,'lay',k[2],mt,pl,won,ly(pl,won),k[1]))
print(f"runners joined {hit:,}, not joined {miss:,}",flush=True)
A=pd.DataFrame(rows,columns='q side race t px won v bsp'.split()); out=[]
for (q,s),x in A.groupby(['q','side']):
    v=x.v.values; md=np.median(x.t.values); h=x.t.values<md
    out.append(dict(q=q,side=s,n=len(v),races=x.race.nunique(),per10=v.mean(),t=tstat(v),tr=tgame(v,x.race.values),h1=v[h].mean(),h2=v[~h].mean(),won=x.won.mean(),med_px=x.px.median(),imp=(1/x.px).mean()))
print("\n== ITEM 383, cross-check, cannot pass\n",pd.DataFrame(out).round(3).to_string(index=False))
print("\n== SURVIVORS: none can pass here, minute prints"); print(f"total {time.time()-T0:.0f}s")
PY
