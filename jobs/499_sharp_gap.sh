#!/bin/bash
set -o pipefail
# 499_sharp_gap (Finder 2026-11-04, queue item 75, Finder's own, source b, Trademate-style value): is the exchange longer or shorter than a sharp price, and does that pay? Rule written in the queue before any price was read. The number 499 is reused with a new slug: 450-499 are all taken.
# DATA fd_matches 2024-25 to 2026-27. Exchange: BFEC* (close), BFE* (earlier snapshot). Benchmarks: Pinnacle (PSC*, PC*; PS*, P*), to about mid 2025 only; bookmaker average (AvgC*, Avg*), all three seasons. Fair = benchmark de-vigged within its own book (1X2 or Over/Under 2.5).
# TRADE: back at x -1 tick where x >= fair odds x (1+m); lay at x +1 tick where x <= fair odds / (1+m); m 1/2/3/5%. £10 risk, 2% commission, held to FT. One trade per selection per game; a game can give several, so t_game is t on per-game means.
# TIGHT = exchange book 1/x sums to 0.98-1.06, the guard against a stale or empty book; lines are split tight True v False, a pass on False alone is a stale book.
# A close is not a print and the snapshots may not be simultaneous, and whether BFEC is a back price is not documented on the box: a lay at BFEC +1 tick may understate the spread. A PASS IS AN UPPER BOUND ON A PROXY. All lines picked from many, so read the fit-on-2024-25 column: lines passing are named on 2024-25 first and read on later games.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks()
pd.set_option('display.width',260); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time()
def num(x):
    try: v=float(x)
    except (TypeError,ValueError): return np.nan
    return v if 1<v<=1000 else np.nan
def fair_odds(book):
    """Book of quoted odds -> de-vigged fair odds; NaN if any quote is missing."""
    b=np.asarray(book,dtype=float)
    if np.isnan(b).any(): return [np.nan]*len(b)
    q=1/b; return list(q.sum()/q)
def decide(x,f,m):
    """B if the exchange is at least m longer than fair, L if at least m shorter, else None."""
    if x!=x or f!=f: return None
    return 'B' if x>=f*(1+m) else 'L' if x<=f/(1+m) else None
def pnl(side,x,won):
    if side=='B':
        a=step(x,-1); return None if a<=1.01 else back_settle(a,won)
    return lay_settle(step(x,1),won)
# known answers. Book 2.0/2.0: fair 2.0 each. Book 1.5/3.0 sums 1.0: fair unchanged. Book 1.9/1.9: overround removed, fair 2.0.
assert all(abs(a-b)<1e-9 for a,b in zip(fair_odds([1.9,1.9]),[2.0,2.0])) and all(abs(a-b)<1e-9 for a,b in zip(fair_odds([1.5,3.0]),[1.5,3.0])) and np.isnan(fair_odds([2.0,np.nan])[0])
# boundaries of m: 2.04 v fair 2.0 at 2% is B; 2.03 is none; 2.0/1.02=1.9608, so 1.96 is L, 1.97 is none.
assert decide(2.04,2.0,.02)=='B' and decide(2.03,2.0,.02) is None and decide(1.96,2.0,.02)=='L' and decide(1.97,2.0,.02) is None and decide(np.nan,2.0,.02) is None
# back 2.04 -> 2.02 wins 10.2*0.98=9.996; lay 1.96 -> 1.97 stake 10/.97=10.309278 net 10.103093 if it loses; -10 if it wins.
assert abs(pnl('B',2.04,True)-9.996)<1e-9 and pnl('B',2.04,False)==-10.0 and abs(pnl('L',1.96,False)-10/.97*.98)<1e-9 and pnl('L',1.96,True)==-10.0 and pnl('B',1.02,True) is None
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='600s'")
D=pd.read_sql("SELECT div,season,date,home,away,fthg,ftag,raw FROM fd_matches WHERE fthg IS NOT NULL AND season IN ('2425','2526','2627')",con); con.close()
D['dt']=pd.to_datetime(D.date); print(f"games {len(D)} {D.groupby('season').size().to_dict()} {D.dt.min().date()} to {D.dt.max().date()}",flush=True)
MO=('H','D','A'); OU=('>2.5','<2.5')
SRC={('CLOSE','PIN'):(('BFEC',''),('PSC',''),('BFEC',''),('PC','')),('CLOSE','AVG'):(('BFEC',''),('AvgC',''),('BFEC',''),('AvgC','')),('OPEN','PIN'):(('BFE',''),('PS',''),('BFE',''),('P','')),('OPEN','AVG'):(('BFE',''),('Avg',''),('BFE',''),('Avg',''))}
rows=[]; cal=[]
for g in D.itertuples():
    r=g.raw; tot=g.fthg+g.ftag; res='H' if g.fthg>g.ftag else 'A' if g.ftag>g.fthg else 'D'
    for (snap,bn),(ex,be,ex2,be2) in SRC.items():
        for sels,exk,bek,mk in ((MO,ex[0],be[0],'MO'),(OU,ex2[0],be2[0],'OU')):
            xs=[num(r.get(exk+s)) for s in sels]; bs=[num(r.get(bek+s)) for s in sels]; fs=fair_odds(bs)
            if np.isnan(xs).any() or np.isnan(fs).any(): continue
            tight=0.98<=sum(1/x for x in xs)<=1.06
            for s,x,f in zip(sels,xs,fs):
                won=(s==res) if mk=='MO' else ((tot>2.5)==(s=='>2.5'))
                cal.append((snap,bn,mk,s,g.season,1/x,1/f,won,tight))
                for m in (.01,.02,.03,.05):
                    d=decide(x,f,m)
                    if d is None: continue
                    v=pnl(d,x,won)
                    if v is not None: rows.append((snap,bn,mk,s,m,d,tight,g.season,g.dt,g.Index,x,won,v))
print(f"trades {len(rows)} {time.time()-T0:.0f}s",flush=True)
R=pd.DataFrame(rows,columns=['snap','bench','mkt','sel','m','side','tight','season','dt','game','x','won','v']); C=pd.DataFrame(cal,columns=['snap','bench','mkt','sel','season','qx','qf','won','tight'])
print("\n== share of books TIGHT, and 1/x mean by snapshot"); print(C.groupby(['snap','bench','mkt']).agg(n=('won','size'),tight=('tight','mean')).round(3).to_string())
c2=C.groupby(['snap','bench','mkt','sel']).apply(lambda x:pd.Series(dict(n=len(x),won=x.won.mean(),q_exch=x.qx.mean(),q_fair=x.qf.mean(),brier_exch=((x.qx-x.won)**2).mean(),brier_bench=((x.qf-x.won)**2).mean()))).round(4)
print("\n== calibration: who is nearer the result (lower Brier)"); print(c2.to_string())
def tbl(x):
    med=x.dt.median(); h=np.where(x.dt<=med,1,2); l=line(x.v.values,h); gm=x.groupby('game').v.mean().values
    d=dict(n=l['n'],games=len(gm),per10=l['per10'],t=l['t'],t_game=tstat(gm),n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),imp=(1/x.x).mean(),PASS=l['PASS'])
    for s in ('2425','2526','2627'):
        y=x[x.season==s]; d['n'+s]=len(y); d['p'+s]=y.v.mean() if len(y) else np.nan
    return d
o=[]
for keys,x in R.groupby(['snap','bench','side','m','tight']):
    o.append(dict(zip(['snap','bench','side','m','tight'],keys),sel='ALL',**tbl(x)))
    for s,y in x.groupby('sel'):
        if len(y)>=30: o.append(dict(zip(['snap','bench','side','m','tight'],keys),sel=s,**tbl(y)))
O=pd.DataFrame(o)
print(f"\n== lines {len(O)}, at n>=300 {int((O.n>=300).sum())}, PASS {int(O.PASS.sum())}")
A=O[(O.sel=='ALL')]; print("\n== ALL selections, every line"); print(A.sort_values(['snap','bench','side','m','tight']).drop(columns=['sel','PASS','n1','n2']).round(3).to_string(index=False))
print("\n== TOP 15 by t, n>=300"); print(O[O.n>=300].sort_values('t',ascending=False).head(15).drop(columns=['n1','n2']).round(3).to_string(index=False))
print("\n== chosen on 2024-25 only: the best 10 with n2425>=150 by p2425, read on 2025-26 and 2026-27"); print(O[O.n2425>=150].sort_values('p2425',ascending=False).head(10)[['snap','bench','side','m','tight','sel','n2425','p2425','n2526','p2526','n2627','p2627']].round(3).to_string(index=False))
print(f"\n-- numeric passes on non-tight books, VOID, stale quotes, see jobs/499_sharp_gap_open_check.sh: {int((O.PASS&~O.tight).sum())}")
print("\n== SURVIVORS, tight books only (bar: n>=300, n>=150 per half, both halves > 0, t>=3.5, mean>=+0.15, proxy upper bound)"); S=O[O.PASS&O.tight]; print(S.drop(columns=['n1','n2']).round(3).to_string(index=False) if len(S) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
