# lib_xx (Finder 2026-11-07, items 329-331): match another exchange's football markets to Betfair liq_sample markets. Run directly for the known-answer checks. No database access, no secrets.
import numpy as np
import pandas as pd
from lib_cand import norm,loose

LABS={'HOME','DRAW','AWAY'}
def pair(ev):
    """Normalised (home,away) or None. Betfair writes 'A v B', the others 'A vs B'."""
    s=str(ev).replace(' vs ',' v ').split(' v ')
    if len(s)!=2: return None
    h,a=norm(s[0]),norm(s[1])
    return (h,a) if h and a else None
def side_of(sel,ev):
    """HOME/AWAY/DRAW from the other exchange's own event name, or None."""
    p=pair(ev)
    if p is None: return None
    if 'draw' in str(sel).lower(): return 'DRAW'
    n=norm(sel)
    return 'HOME' if n==p[0] else 'AWAY' if n==p[1] else None
def pick(p,cands):
    """cands: [(pair,market_id)] already alive at the kick-off. Returns (market_id,'exact'|'loose') or None. Home and away stay in order; two exact matches is no match."""
    if p is None: return None
    ex=[m for q,m in cands if q==p]
    if len(ex)==1: return ex[0],'exact'
    if len(ex)>1: return None
    m=loose(p[0],p[1],[(q[0],q[1],m) for q,m in cands])
    return (m,'loose') if m is not None else None
def median_gap(xt,xm,bt,bm,tol=60):
    """Median |other mid/Betfair mid-1| over Betfair rows with an other row at or before within tol s. A high value means a wrong pairing, not an edge."""
    if not len(xt) or not len(bt): return None
    i=np.searchsorted(xt,bt,side='right')-1; ok=(i>=0)
    if not ok.any(): return None
    i=np.where(ok,i,0); ok=ok&(bt-xt[i]<=tol)
    return float(np.median(np.abs(xm[i[ok]]/bm[ok]-1))) if ok.any() else None
def checks():
    assert pair('Smouha SC vs El Minya')==pair('Smouha v El Minya') and pair('no separator') is None
    assert side_of('Draw','Smouha SC vs El Minya')=='DRAW' and side_of('Smouha SC','Smouha SC vs El Minya')=='HOME' and side_of('El Minya','Smouha SC vs El Minya')=='AWAY' and side_of('Other','Smouha SC vs El Minya') is None
    assert side_of('Atlético Tucumán','Banfield vs Atlético Tucumán')=='AWAY'
    a=pair('Everton vs Coventry City'); b=pair('Everton v Coventry'); c=pair('Coventry v Everton'); d=pair('Everton v Hull')
    assert pick(a,[(a,'X')])==('X','exact') and pick(a,[(a,'X'),(a,'Y')]) is None
    assert pick(a,[(b,'X'),(d,'Y')])==('X','loose')
    assert pick(a,[(c,'X')]) is None and pick(a,[(d,'Y')]) is None and pick(None,[(a,'X')]) is None
    xt=np.array([0.,30.,300.]); xm=np.array([2.,2.,3.]); bt=np.array([40.,100.,310.]); bm=np.array([2.,2.,2.])
    assert median_gap(xt,xm,bt,bm)==0.25           # 100 has no row in 60 s, 40 reads 2.0, 310 reads 3.0: median of 0 and 0.5 is 0.25
if __name__=='__main__':
    checks(); print("lib_xx checks OK")
