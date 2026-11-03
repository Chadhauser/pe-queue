#!/bin/bash
set -o pipefail
# 462 (Finder 2026-11-03, own item 14): FIRST-HALF OVER 0.5 / 1.5 by minute and state — FH05/FH15 were excluded from every earlier grid.
# Data: bf_hist_price (FH05, FH15, MO, OU25) joined to af_fixtures/af_events via af_price_map (as 315). Season 2024 = h1, 2025 = h2.
# Entry at minute e in {10,15,20,25,30,35,40}: state from af goals with minute <= e (first-half goal = af minute <= 45, stoppage counted);
# entry price = first REAL print in tape minutes e+1..e+3 (never forward-filled; none -> no entry). af minute m covers tape minute m-1, so a
# goal at af minute e+1..e+3 may come before the entry print. Variant A (honest): keep those entries; for FH05 a post-goal print (<=1.05) is
# taken at that price (back blocked at <=1.01, lay pays). Variant B (look-ahead buffer, NEVER PASS): drop entries with a goal af minute <= e+3.
# Trades: BACK and LAY the OVER selection, risk £10, one tick adverse, 2% commission on profit.
# Exits: SETTLE at HT result (always — FH market cannot be dropped); T10 = first real print in tape minutes x..x+2 with x=e+11, and if the
# line has been passed by then (goal(s) scored) the trade settles at the RESULT; if no print and not settled -> held to HT result (never dropped).
# One entry per game per (market, state, minute) cell — cells are independent within a cell, but cells at different minutes share games.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
def tick(p): return 0.01 if p<2 else 0.02 if p<3 else 0.05 if p<4 else 0.1 if p<6 else 0.2 if p<10 else 0.5 if p<20 else 1 if p<30 else 2 if p<50 else 5 if p<100 else 10
def pnl(side,p,q,won):
    if side=='B':
        p=p-tick(p)
        if p<=1.01: return None
        r=(10*(p-1) if won else -10.0) if q is None else 10*(p/(q+tick(q))-1)
    else:
        p=p+tick(p); s=10/(p-1)
        r=(s if not won else -10.0) if q is None else s*(1-p/max(1.01,q-tick(q)))
    return r*0.98 if r>0 else r
# known answers (tick at 3.0 = 0.05, at 4.0 = 0.1): back 3.0 (fill 2.95) settle won 19.5*0.98=19.11; lay 3.0 (fill 3.05) lost -10; lay won s=10/2.05=4.878049*0.98;
# back 3.0 -> exit 4.0 (fill 4.1): 10*(2.95/4.1-1)=-2.804878
assert abs(pnl('B',3.0,None,True)-19.11)<1e-9 and pnl('L',3.0,None,True)==-10.0 and abs(pnl('L',3.0,None,False)-10/2.05*0.98)<1e-9
assert abs(pnl('B',3.0,4.0,False)+2.804878)<1e-6
print("P&L unit checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id, f.fixture_id, f.season, f.league FROM af_price_map m
 JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL""",con)
EV=pd.read_sql("""SELECT fixture_id, coalesce(minute,0) AS minute FROM af_events
 WHERE fixture_id = ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')""",con,params=(list(map(int,G.fixture_id)),))
goals=defaultdict(list)
for r in EV.itertuples(): goals[r.fixture_id].append(int(r.minute))
print("games mapped:",len(G),"| seasons:",G.season.value_counts().to_dict(),flush=True)
ENTRY=(10,15,20,25,30,35,40); rows=[]; ng=0
for i in range(0,len(G),2000):
    sub=G.iloc[i:i+2000]
    P=pd.read_sql("""SELECT event_id, minute, mkt, sel, avg(ltp)::float ltp FROM bf_hist_price WHERE event_id = ANY(%s) AND minute BETWEEN 0 AND 60
      AND ((mkt IN ('FH05','FH15') AND sel='OVER') OR (mkt='MO' AND sel IN ('HOME','AWAY')) OR (mkt='OU25' AND sel='OVER')) AND ltp>=1.01 AND ltp<1000
      GROUP BY 1,2,3,4""",con,params=(list(sub.event_id),))
    px=defaultdict(dict)
    for (eid,mkt,sel),g in P.groupby(['event_id','mkt','sel']):
        a=np.full(62,np.nan); a[g.minute.values]=g.ltp.values; px[eid][(mkt,sel)]=a
    for g in sub.itertuples():
        bk=px.get(g.event_id)
        if not bk: continue
        h=bk.get(('MO','HOME')); a=bk.get(('MO','AWAY')); o=bk.get(('OU25','OVER'))
        def first(arr,lo,hi):
            if arr is None: return None
            for mm in range(lo,hi+1):
                if mm<62 and not np.isnan(arr[mm]): return mm
            return None
        hm=first(h,0,2); am=first(a,0,2); om=first(o,0,2)
        if hm is None or am is None: continue
        fav=min(h[hm],a[am]); fb='<1.5' if fav<1.5 else '1.5-2' if fav<2 else '2-3' if fav<3 else '3+'
        ob='na' if om is None else '<1.7' if o[om]<1.7 else '1.7-2.0' if o[om]<2.0 else '2.0-2.4' if o[om]<2.4 else '2.4+'
        fh=sorted(m for m in goals.get(g.fixture_id,[]) if m<=45); nfh=len(fh); ng+=1
        for mkt,line in (('FH05',0),('FH15',1)):
            arr=bk.get((mkt,'OVER'))
            if arr is None: continue
            won=nfh>line
            for e in ENTRY:
                st=sum(1 for m in fh if m<=e)
                if st>line: continue
                if mkt=='FH05' and st!=0: continue
                em=first(arr,e+1,e+3)
                if em is None: continue
                p=arr[em]
                if p>50: continue
                buf=any(e<m<=e+3 for m in fh)
                x=e+11; xm=first(arr,x,x+2)
                passed=sum(1 for m in fh if m<=(xm if xm is not None else x+2)+1)>line
                q10=None if passed or xm is None else arr[xm]
                for side in 'BL':
                    for ex,q in (('SETTLE',None),('T10',q10)):
                        r=pnl(side,p,q,won)
                        if r is None: continue
                        rows.append((g.event_id,int(g.season),g.league,mkt,st,e,side,ex,fb,ob,buf,r))
print("games with FH prices:",ng,"| trade rows:",len(rows),flush=True)
D=pd.DataFrame(rows,columns=['eid','season','league','mkt','st','e','side','ex','fb','ob','buf','pnl'])
def agg(E,keys):
    out=[]
    for k,x in E.groupby(keys,observed=True):
        n=len(x); mu=x.pnl.mean(); sd=x.pnl.std(ddof=0) or 1e-9
        a=x[x.season==2024].pnl; c=x[x.season==2025].pnl
        out.append(dict(zip(keys,k if isinstance(k,tuple) else (k,)),n=n,games=x.eid.nunique(),mean=mu,t=mu/(sd/np.sqrt(n)),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(c),h2=c.mean() if len(c) else np.nan))
    return pd.DataFrame(out)
R=[]
for var,E in (('A',D),('B',D[~D.buf])):
    for keys in (['mkt','st','e','side','ex'],['mkt','st','e','side','ex','fb'],['mkt','st','e','side','ex','ob']):
        A=agg(E,keys); A['var']=var; A['level']='+'.join(keys); R.append(A)
R=pd.concat(R,ignore_index=True)
for c in ('fb','ob'):
    if c not in R: R[c]='*'
R[['fb','ob']]=R[['fb','ob']].fillna('*')
R['PASS']=(R['var']=='A')&(R.n>=300)&(R.n1>=150)&(R.n2>=150)&(R.t>=3.5)&(R.h1>0)&(R.h2>0)&(R['mean']>=0.15)
cols=['var','mkt','st','e','side','ex','fb','ob','n','games','mean','t','n1','h1','n2','h2','PASS']
base=R[(R['var']=='A')&(R.level=='mkt+st+e+side+ex')]
print("\n== variant A, base cells (state x minute x side x exit), SETTLE exit")
print(base[base.ex=='SETTLE'].sort_values(['mkt','st','side','e'])[cols].round(3).to_string(index=False))
print("\n== top 15 by t, variant A, n>=300")
print(R[(R['var']=='A')&(R.n>=300)].sort_values('t',ascending=False).head(15)[cols].round(3).to_string(index=False))
print("\n== top 5 by t, variant B (look-ahead buffer; for comparison only)")
print(R[(R['var']=='B')&(R.n>=300)].sort_values('t',ascending=False).head(5)[cols].round(3).to_string(index=False))
S=R[R.PASS].sort_values('t',ascending=False)
print(f"\n== SURVIVORS: {len(S)} of {int(((R['var']=='A')&(R.n>=300)).sum())} variant-A cells at n>=300")
print(S[cols].round(3).to_string(index=False) if len(S) else "none")
PY
