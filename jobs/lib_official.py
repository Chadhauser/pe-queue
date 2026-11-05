# lib_official (Finder 2026-11-05, items 141-143): feed-wide settlement from bf_hist_result (job 520). Run directly for the known-answer checks. No secrets; read-only.
import re
import numpy as np
import pandas as pd
from lib_cand import step,back_settle,lay_settle

WOMEN=re.compile(r"\(W\)|\bwomen\b|\bladies\b|\bfemenin",re.I)
YOUTH=re.compile(r"\bU-?(1[5-9]|2[0-3])\b|\byouth\b",re.I)
def group(ev):
    """WOMEN first, so a U20 (W) game is WOMEN. None = senior, split by liquidity later."""
    if WOMEN.search(ev): return 'WOMEN'
    if YOUTH.search(ev): return 'YOUTH'
    return None
def bk(x,won):
    """Back at the print one tick adverse; a print at the bottom of the ladder cannot be improved on, no trade."""
    a=step(x,-1); return None if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)
def fill(ts,px,i,side,nxt=120):
    """Worse of print i and the next print within nxt seconds. ts and px hold prints of one state only (pre-off or in-play)."""
    p=float(px[i])
    if i+1<len(ts) and ts[i+1]-ts[i]<=nxt:
        p=max(p,float(px[i+1])) if side=='L' else min(p,float(px[i+1]))
    return p
def last_in(ts,lo,hi):
    """Index of the last print with lo<=ts<=hi, else None. ts sorted. Never forward-fills from before lo."""
    i=int(np.searchsorted(ts,hi,side='right'))-1
    return i if i>=0 and ts[i]>=lo else None
def first_in(ts,lo,hi):
    """Index of the first print with lo<=ts<=hi, else None."""
    i=int(np.searchsorted(ts,lo,side='left'))
    return i if i<len(ts) and ts[i]<=hi else None
def secs(col): return (pd.to_datetime(col,utc=True)-pd.Timestamp('1970-01-01',tz='UTC'))/pd.Timedelta(seconds=1)
def load_results(con,types):
    """market_id -> {sel: won} for markets with exactly one WINNER. Returns (results, dropped_count)."""
    R=pd.read_sql("SELECT market_id,sel,status FROM bf_hist_result WHERE sport='Soccer' AND market_type=ANY(%s)",con,params=(list(types),))
    w=R[R.status=='WINNER'].groupby('market_id').size()
    ok=set(w[w==1].index); out={}
    for m,g in R[R.market_id.isin(ok)].groupby('market_id'): out[m]=dict(zip(g.sel,g.status=='WINNER'))
    return out,int(R.market_id.nunique()-len(out))
def checks():
    assert group('China U20 (W) v Nigeria U20 (W)')=='WOMEN' and group('Barcelona U19 v Feyenoord Youth')=='YOUTH'
    assert group('Arsenal Women v Spurs Women')=='WOMEN' and group('Leeds v Hull') is None and group('Hull U21 v Leeds')=='YOUTH'
    assert group('Union Berlin v Ulm') is None and group('Wolves v Burnley') is None
    # Back 2.04 -> 2.02: 10.2 profit, 9.996 after 2%. Lay 2.0 -> 2.02: stake 10/1.02, wins 9.6078 after 2%, loses 10.
    assert abs(bk(2.04,True)-9.996)<1e-9 and bk(2.04,False)==-10.0
    assert ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9
    assert bk(1.02,True) is None and bk(1.01,True) is None
    # Lay 1.10 -> 1.11: stake 10/0.11 = 90.909, wins 89.09 after 2%; back 1.10 -> 1.09: wins 0.882, loses 10.
    assert abs(ly(1.10,False)-10/0.11*.98)<1e-6 and abs(bk(1.10,True)-0.882)<1e-9
    t=np.array([0.,60.,300.]); p=np.array([2.0,2.2,3.0])
    assert fill(t,p,0,'L')==2.2 and fill(t,p,0,'B')==2.0 and fill(t,p,1,'L')==2.2 and fill(t,p,2,'B')==3.0
    assert last_in(t,0,100)==1 and last_in(t,100,200) is None and last_in(t,-50,-1) is None and last_in(t,250,1000)==2
    assert first_in(t,30,100)==1 and first_in(t,100,200) is None and first_in(t,400,500) is None
    return True
if __name__=='__main__':
    checks(); print("lib_official known-answer checks: OK")
