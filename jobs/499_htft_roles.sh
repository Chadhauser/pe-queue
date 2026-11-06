#!/bin/bash
set -o pipefail
# 499_htft_roles (Finder 2026-11-06, queue item 288, Finder's own, source d): HT/FT by favourite and outsider role, every month, official results. Rule pushed in the queue before any price. Read only. No tables written. Prints only, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
from lib_official import bk,ly,fill,last_in,secs,checks,group,load_results
import lib_cand; lib_cand._checks(); checks()
def htft_role(s,h,a,fav):
    """Runner name half-time/full-time -> role letters from F, O, D. None if the name is neither side's. fav is 'H' or 'A'."""
    f,o=(h,a) if fav=='H' else (a,h); L={f:'F',o:'O','Draw':'D'}
    for x,cx in L.items():
        for y,cy in L.items():
            if s==f"{x}/{y}": return cx+cy
    return None
assert htft_role('Leeds/Leeds','Leeds','Hull','H')=='FF' and htft_role('Hull/Leeds','Leeds','Hull','H')=='OF' and htft_role('Leeds/Hull','Leeds','Hull','H')=='FO'
assert htft_role('Draw/Draw','Leeds','Hull','A')=='DD' and htft_role('Leeds/Draw','Leeds','Hull','A')=='OD' and htft_role('Draw/Leeds','Leeds','Hull','A')=='DO' and htft_role('Spurs/Hull','Leeds','Hull','H') is None
assert abs(bk(4.0,True)-(3.95-1)*10*.98)<1e-9 and secs(pd.Series([pd.Timestamp('2024-01-01',tz='UTC')])).iloc[0]==1704067200
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
RS,dropped=load_results(con,['HALF_TIME_FULL_TIME']); print("markets with one winner",len(RS),"dropped, not one winner",dropped,flush=True)
C=Counter(); rows=[]; seen=set()
MON=pd.date_range('2024-01-01','2024-12-01',freq='MS').tolist()+pd.date_range('2026-05-01','2026-11-01',freq='MS').tolist()
for a_,b_ in zip(MON[:-1],MON[1:]):
    if (b_-a_).days>31: continue
    A=pd.read_sql("SELECT event_name ev,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '20 minutes' AND ts<=market_time-interval '2 minutes' AND market_time>=%s AND market_time<%s",con,params=(a_,b_))
    A['off']=secs(A.mt); A['tt']=secs(A.ts); LAST=A.sort_values('tt',kind='stable').groupby(['ev','off','sel']).ltp.last().to_dict(); del A
    X=pd.read_sql("SELECT market_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='HALF_TIME_FULL_TIME' AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '20 minutes' AND ts<=market_time AND market_time>=%s AND market_time<%s",con,params=(a_,b_))
    X['tt']=secs(X.ts); X['off']=secs(X.mt); X=X.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt'])
    for m,g in X.groupby('market_id',sort=True):
        ev=g.ev.iloc[0]; o=float(g.off.iloc[0])
        if (ev,o) in seen: C['second id']+=1; continue
        seen.add((ev,o))
        if ' v ' not in ev: C['no H v A']+=1; continue
        if group(ev): C['women or youth']+=1; continue
        if m not in RS: C['no official result']+=1; continue
        h,a=ev.split(' v ',1); ph,pa=LAST.get((ev,o,h)),LAST.get((ev,o,a))
        if ph is None or pa is None: C['MO not priced']+=1; continue
        if ph==pa: C['MO level']+=1; continue
        fav='H' if ph<pa else 'A'; R=RS[m]
        for s,y in g.groupby('sel',sort=False):
            if s not in R: C['runner not in result']+=1; continue
            r=htft_role(s,h,a,fav)
            if r is None: C['name mismatch']+=1; continue
            ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-1200,o-120)
            if i is None: C['no print']+=1; continue
            pb,pl=fill(ts,px,i,'B'),fill(ts,px,i,'L')
            rows.append((r,o,R[s],float(px[i]),pb,pl,None if pb>50 else bk(pb,R[s]),None if pl>50 else ly(pl,R[s])))
    print(a_.date(),"rows",len(rows),f"{time.time()-T0:.0f}s",flush=True)
con.close(); print("counted:",dict(sorted(C.items())),flush=True)
D=pd.DataFrame(rows,columns='r off won p pb pl vb vl'.split()); md=float(np.median(D.off)); print("trades",D.r.value_counts().to_dict(),"split at",pd.Timestamp(md,unit='s',tz='UTC'),flush=True)
OLD=pd.Timestamp('2024-10-01',tz='UTC').timestamp(); OLD2=pd.Timestamp('2024-11-01',tz='UTC').timestamp(); N1=pd.Timestamp('2026-08-01',tz='UTC').timestamp()
out=[]
def add(nm,x):
    for sd,c,pc in (('back','vb','pb'),('lay','vl','pl')):
        z=x[x[c].notna()]
        if len(z)<30: out.append(dict(line=nm+' '+sd,n=len(z),PASS=False)); continue
        l=line(z[c].astype(float).values,np.where(z.off<md,1,2)); fresh=z[~(((z.off>=OLD)&(z.off<OLD2))|(z.off>=N1))]; f=fresh[c].astype(float)
        out.append(dict(line=nm+' '+sd,n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],maxwin=l['maxwin'],won=z.won.astype(float).mean(),imp=(1/z[pc]).mean(),fresh_n=len(f),fresh=f.mean() if len(f) else np.nan,PASS=l['PASS']))
for r in ('FF','OO','DD','DF','DO','FD','OD','FO','OF'): add(r,D[D.r==r])
for r in ('FO','OF'):
    add(r+' under 30',D[(D.r==r)&(D.p<30)]); add(r+' 30-50',D[(D.r==r)&(D.p>=30)&(D.p<=50)])
L=pd.DataFrame(out); print(f"\nlines {len(L)}, passing {int(L.PASS.sum())}"); print(L.sort_values('t',ascending=False).round(3).to_string(index=False))
S=L[L.PASS==True]; print(f"\n== SURVIVORS: {len(S)} of {len(L)} scored\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
