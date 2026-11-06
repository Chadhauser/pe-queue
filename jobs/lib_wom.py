# lib_wom (Finder 2026-11-06, items 194-197): trade and report helpers for the weight-of-money jobs. Run this file directly for its known-answer checks. No database access, no secrets.
import numpy as np,pandas as pd
from lib_cand import step,back_settle,lay_settle,back_hedge,lay_hedge,tstat,passes,LD

def ticks(a,b):
    """Ladder ticks from a up to b, element-wise."""
    return np.searchsorted(LD,np.round(np.asarray(b,float),2)-1e-9)-np.searchsorted(LD,np.round(np.asarray(a,float),2)-1e-9)
def last_result(p):
    """Runner's result from the last print: None when it does not say."""
    return True if p<=1.1 else False if p>=11 else None
def two_sided(b,l):
    return b>1 and l>1 and b==b and l==l
def pnl_exit(side,a,a0,q):
    """Real exit at touch q. (pnl with costs, exact with none). a has the entry tick in it, a0 does not."""
    if side=='back': return back_hedge(a,q),10*(a0/q-1)
    return lay_hedge(a,q),(10/(a0-1))*(1-a0/q)
def pnl_settle(side,a,a0,won):
    if side=='back': return back_settle(a,won),(10*(a0-1) if won else -10.0)
    return lay_settle(a,won),(-10.0 if won else 10/(a0-1))
def entry_px(side,bp,lp):
    """(price with one tick adverse, touch)."""
    return (step(bp,-1),bp) if side=='back' else (step(lp,1),lp)
def rest_fill(side,t,ltp,i,P,win):
    """First row after i, within win seconds, with a NEW print strictly through resting price P: above P for a resting back, below for a resting lay. None = cancelled."""
    for j in range(i+1,len(t)):
        if t[j]-t[i]>win: return None
        v=ltp[j]
        if v==v and v!=ltp[j-1] and (v>P if side=='back' else v<P): return j
    return None
def trade_rest(side,t,bp,lp,ltp,k,H,P):
    """Filled at row k at resting price P, one tick adverse, then out as trade_h."""
    return trade_h(side,t,bp,lp,ltp,k,H,(step(P,-1),P) if side=='back' else (step(P,1),P))
def trade_h(side,t,bp,lp,ltp,k,H,fill=None):
    """Enter at row k, out at the first two-sided row H minutes on; no such row = settle from the last print.
    Returns (pnl,exact,how,wide): how is exit, settled, unresolved. wide = exit spread over 4 ticks. fill = (price with the adverse tick, price without), else the touch at k."""
    a,a0=fill if fill else entry_px(side,bp[k],lp[k])
    j=int(np.searchsorted(t,t[k]+H*60,side='left'))
    while j<len(t) and not two_sided(bp[j],lp[j]): j+=1
    if j<len(t):
        p,e=pnl_exit(side,a,a0,lp[j] if side=='back' else bp[j])
        return p,e,'exit',bool(ticks(bp[j],lp[j])>4)
    v=ltp[~np.isnan(ltp)]
    r=last_result(v[-1]) if len(v) else None
    if r is None: return None,None,'unresolved',False
    p,e=pnl_settle(side,a,a0,r)
    return p,e,'settled',False
def tgame(x,g):
    """t on per-game sums: same bet size, correlated entries in a game counted once."""
    return tstat(pd.DataFrame(dict(x=np.asarray(x,float),g=np.asarray(g))).groupby('g').x.sum().values)
def table(R,keys,title,top=15,control=None):
    """R has pnl, exact, ev, ts, plus keys. Halves by each line's median time. Prints top lines by t and returns passes. control: column value marking lines that cannot pass."""
    out=[]
    for k,x in R.groupby(keys,observed=True):
        k=k if isinstance(k,tuple) else (k,)
        md=x.ts.median(); a=x.pnl.values; h1=a[x.ts.values<md]; h2=a[x.ts.values>=md]
        out.append(k+(len(a),a.mean(),tstat(a),tgame(a,x.ev.values),h1.mean() if len(h1) else 0.,h2.mean() if len(h2) else 0.,len(h1),len(h2),x.exact.mean(),x.ev.nunique()))
    C=pd.DataFrame(out,columns=list(keys)+'n per10 t tg h1 h2 n1 n2 exact games'.split())
    C['pass']=[passes(r.n,r.n1,r.n2,r.t,r.h1,r.h2,r.per10) for r in C.itertuples()]
    ctrl=C[C[control[0]]==control[1]] if control else C.iloc[0:0]
    test=C[C[control[0]]!=control[1]] if control else C
    print(f"\n== {title}: {len(test)} lines; top {top} by t",flush=True)
    print(test.sort_values('t',ascending=False).head(top).round(3).to_string(index=False),flush=True)
    if len(ctrl):
        print("-- control, cannot pass",flush=True); print(ctrl.sort_values('t',ascending=False).head(8).round(3).to_string(index=False),flush=True)
    return test[test['pass']]

if __name__=='__main__':
    assert ticks(2.0,2.1)==5 and ticks(1.5,1.54)==4 and ticks(3.0,3.0)==0
    t=np.array([0,60,120,180.]); b=np.array([2.,2.,1.8,1.8]); l=np.array([2.02,2.02,1.82,1.82]); p=np.array([2.,2.,1.8,1.8])
    # back at 2.00, one tick adverse 1.99; 2 min on lay touch 1.82, one tick adverse 1.83; profit 10*(1.99/1.83-1) less 2%
    r=trade_h('back',t,b,l,p,0,2); assert r[2]=='exit' and abs(r[0]-0.98*10*(1.99/1.83-1))<1e-9 and abs(r[1]-10*(2/1.82-1))<1e-9 and not r[3]
    # lay at 2.02, adverse 2.04; stake 10/1.04; 2 min on back touch 1.80, adverse 1.79; loss stake*(1-2.04/1.79), no commission on a loss
    r=trade_h('lay',t,b,l,p,0,2); assert abs(r[0]-(10/1.04)*(1-2.04/1.79))<1e-9 and r[0]<0
    # no row left: settled from the last print
    r=trade_h('back',t,b,l,np.array([2,2,1.8,1.05]),0,9); assert r[2]=='settled' and abs(r[0]-0.98*10*0.99)<1e-9
    r=trade_h('lay',t,b,l,np.array([2,2,1.8,20.]),0,9); assert r[2]=='settled' and abs(r[0]-0.98*10/1.04)<1e-9
    r=trade_h('lay',t,b,l,np.array([2,2,1.8,1.05]),0,9); assert r[2]=='settled' and abs(r[0]+10)<1e-9
    r=trade_h('back',t,b,l,p,0,9); assert r[2]=='unresolved' and r[0] is None
    # a one-sided row at the exit minute is skipped, never filled
    r=trade_h('back',t,b,np.array([2.02,2.02,np.nan,1.9]),p,0,2); assert r[2]=='exit' and abs(r[0]-0.98*10*(1.99/step(1.9,1)-1))<1e-9
    assert abs(tgame([1,1,2,2],['a','a','b','b'])-3.0)<1e-9     # game sums 2 and 4: mean 3, sd 1.414, se 1, t 3
    # resting: a print AT the price is no fill, a stale print is no fill, a new print through is; outside the window is cancelled
    tt=np.array([0,10,20,30,400.]); lt=np.array([2.1,2.1,2.0,2.04,2.06])
    assert rest_fill('back',tt,lt,0,2.02,300)==3 and rest_fill('back',tt,lt,0,2.04,300) is None and rest_fill('lay',tt,lt,0,2.04,300)==2
    assert rest_fill('back',np.array([0,10.]),np.array([2.1,2.1]),0,2.02,300) is None      # 2.1 is stale, never printed again
    # back rested at 2.02, adverse 2.00; 2 min on lay touch 1.82, adverse 1.83: 10*(2.00/1.83-1) less 2%; exact 10*(2.02/1.82-1)
    r=trade_rest('back',t,b,l,p,0,2,2.02); assert abs(r[0]-0.98*10*(2.0/1.83-1))<1e-9 and abs(r[1]-10*(2.02/1.82-1))<1e-9
    print('lib_wom checks: OK')
