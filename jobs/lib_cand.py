# lib_cand (Finder 2026-11-04, items 56c-58c): shared engine for the candidate hold-out jobs, wall-clock version of jobs/489_laliga_00_audit.sh.
# Run this file directly to run its known-answer checks. No database access, no secrets.
import re,unicodedata
import numpy as np

LD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    v=lo
    while v<hi-1e-9: LD.append(round(v,2)); v+=st
LD.append(1000.0); LD=np.array(LD)
def step(p,k):
    i=int(np.searchsorted(LD,round(float(p),2)-1e-9)); return float(LD[min(max(i+k,0),len(LD)-1)])
def net(x): return x*0.98 if x>0 else x
def back_settle(a,won): return net(10*(a-1) if won else -10.0)
def lay_settle(a,sel_won): return net(-10.0 if sel_won else 10/(a-1))
def back_hedge(a,q): return net(10*(a/step(q,1)-1))      # backed at a, out by laying at q, one tick adverse
def lay_hedge(a,q): s=10/(a-1); return net(s*(1-a/step(q,-1)))   # laid at a, out by backing at q, one tick adverse
def tstat(x):
    x=np.asarray(x,dtype=float); x=x[~np.isnan(x)]
    if len(x)<2: return 0.0
    s=x.std(ddof=1)
    return float(x.mean()/(s/len(x)**0.5)) if s>0 else 0.0
def passes(n,n1,n2,t,h1,h2,m): return bool(n>=300 and n1>=150 and n2>=150 and t>=3.5 and h1>0 and h2>0 and m>=0.15)
def zscore(k,n,p):
    if n==0 or p<=0 or p>=1: return 0.0
    return (k/n-p)/(p*(1-p)/n)**0.5

def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|club|de|the|cd|ud|sd|rcd|calcio|ii|b|if|bk|ff|aif|sk|fsv)\b"," ",s)
    return frozenset(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def jac(X,Y): return len(X&Y)/max(1,len(X|Y))
def loose(H,A,cands):
    """cands: (H,A,payload). Both sides must share a word, summed Jaccard >= 1.0, lead >= 0.3 over the next candidate."""
    sc=[]
    for c in cands:
        a,b=jac(H,c[0]),jac(A,c[1])
        if a>0 and b>0: sc.append((a+b,c[2]))
    sc.sort(key=lambda z:-z[0])
    if not sc or sc[0][0]<1.0 or (len(sc)>1 and sc[0][0]-sc[1][0]<0.3): return None
    return sc[0][1]

def goal_times(t,total):
    """Wall times of confirmed goals from feed rows sorted by time. A goal counts only if the next row agrees (or it is the last row): the feed flashes phantom goals (item 0g). A score that goes back down (VAR) is not un-counted."""
    out=[]; cur=0; n=len(t)
    for i in range(n):
        v=total[i] if i==n-1 else min(total[i],total[i+1])
        while cur<v: out.append(t[i]); cur+=1
    return out
def signal_row(mn,T,slack=5):
    """Index of the first feed row at or after minute T, if no later than T+slack, else None (a feed gap is no signal, never a forward fill)."""
    for i,m in enumerate(mn):
        if m is None or m!=m: continue
        if m>=T: return i if m<=T+slack else None
    return None
def first_idx(ts,lo,hi=None):
    """First print with ts in [lo,hi]; ts sorted."""
    i=int(np.searchsorted(ts,lo,side='left'))
    if i>=len(ts) or (hi is not None and ts[i]>hi): return None
    return i
def entry_px(ts,px,t0,side,window=180,nxt=120):
    """First print within window s of the signal, filled at the worse of it and the next print within nxt s, as job 489. side 'B' or 'L'. Returns (print_index,price) or None."""
    i=first_idx(ts,t0,t0+window)
    if i is None: return None
    p=float(px[i])
    if i+1<len(ts) and ts[i+1]<=ts[i]+nxt: p=max(p,float(px[i+1])) if side=='L' else min(p,float(px[i+1]))
    return i,p
def run_exit(side,a,ts,px,ent_i,gts,t0,k,over_won):
    """P&L for Over-backed (B) or Under-laid (L) at fill a; goals gts wall times; 0-0 at t0. k None = settle. A second goal by the exit print settles at the result, a market that has passed is never dropped."""
    settle=back_settle(a,over_won) if side=='B' else lay_settle(a,not over_won)
    later=[g for g in gts if g>t0]
    if k is None or not later: return settle
    tgt=later[0]+k*60
    i=first_idx(ts,max(tgt,ts[ent_i]+1))
    if i is None: return settle
    if len(later)>=2 and later[1]<=ts[i]: return settle
    return back_hedge(a,px[i]) if side=='B' else lay_hedge(a,px[i])
def line(v,h):
    """Line dict for P&L array v, half labels h (1 or 2)."""
    v=np.asarray(v,dtype=float); h=np.asarray(h); a=v[h==1]; b=v[h==2]
    d=dict(n=len(v),per10=v.mean() if len(v) else np.nan,t=tstat(v),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,maxwin=v.max() if len(v) else np.nan)
    d['PASS']=passes(d['n'],d['n1'],d['n2'],d['t'],d['h1'],d['h2'],d['per10']); return d

def _checks():
    assert step(2.0,-1)==1.99 and step(3.0,1)==3.05 and step(3.0,-1)==2.98 and step(2.0,3)==2.06
    # Same hand-worked figures as job 489. Lay Under fill 3.05: stake 4.878049; loses +4.780488; out at 5.0->4.9 net 1.804878; out at 2.0->1.99 -2.598358.
    assert abs(lay_settle(3.05,False)-4.780488)<1e-5 and lay_settle(3.05,True)==-10.0 and abs(lay_hedge(3.05,5.0)-1.804878)<1e-5 and abs(lay_hedge(3.05,2.0)+2.598358)<1e-5
    # Back Over fill 2.98: win 19.404; lose -10; out at 2.0->2.02 net 4.657426.
    assert abs(back_settle(2.98,True)-19.404)<1e-9 and back_settle(2.98,False)==-10.0 and abs(back_hedge(2.98,2.0)-4.657426)<1e-5
    assert abs(tstat([1,3])-2.0)<1e-9 and abs(zscore(60,100,0.5)-2.0)<1e-9
    assert passes(300,150,150,3.5,.01,.01,.15) and not passes(299,150,150,9,1,1,1) and not passes(300,149,151,9,1,1,1) and not passes(300,150,150,3.49,1,1,1) and not passes(300,150,150,9,0,1,1) and not passes(300,150,150,9,1,0,1) and not passes(300,150,150,9,1,1,.149)
    # Feed: real goal at row 2; phantom at row 4 (total 2 then back to 1) is ignored; second real goal at row 6 on the last row.
    assert goal_times([0,60,120,180,240,300,360],[0,0,1,1,2,1,2])==[120,360]
    # Two goals on one row count as two; VAR: 1 for two rows then 0 keeps the count at 1.
    assert goal_times([0,60,120],[0,2,2])==[60,60] and goal_times([0,60,120,180],[0,1,1,0])==[60]
    assert signal_row([10,29,31,40],30)==2 and signal_row([10,29,36],30) is None and signal_row([10],30) is None and signal_row([None,float('nan'),30],30)==2
    T=np.array([100.,160.,400.,800.]); P=np.array([2.0,2.1,3.0,5.0])
    assert first_idx(T,150)==1 and first_idx(T,900) is None and first_idx(T,500,600) is None
    # Entry: first print at 100, next within 120 s, so lay takes the higher, back the lower. No print in the window: no entry, never a forward fill.
    assert entry_px(T,P,90,'L')==(0,2.1) and entry_px(T,P,90,'B')==(0,2.0)
    assert entry_px(T,P,450,'L') is None and entry_px(T,P,300,'L')==(2,3.0)   # 450: nothing by 630; 300: print at 400, next at 800 is too late to count
    # Exits with 1 goal at 200, k 5 -> target 500 -> print 800 at 5.0.
    a=2.98
    assert abs(run_exit('B',a,T,P,0,[200.],150,5,False)-back_hedge(a,5.0))<1e-9
    assert run_exit('B',a,T,P,0,[200.,600.],150,5,True)==back_settle(a,True)       # second goal before the exit print: settled, a win
    assert run_exit('B',a,T,P,0,[],150,5,False)==-10.0 and run_exit('B',a,T,P,0,[900.],150,5,False)==back_settle(a,False)   # no goal; goal with no print after it
    assert run_exit('B',a,T,P,0,[200.],150,None,False)==-10.0
    assert run_exit('L',3.05,T,P,0,[200.],150,5,False)==lay_hedge(3.05,5.0) and run_exit('L',3.05,T,P,0,[],150,8,False)==-10.0
    assert run_exit('L',3.05,T,P,0,[100.],150,5,False)==-10.0    # a goal before the signal is not the next goal
    _n=norm
    assert loose(_n('Man Utd'),_n('Roma'),[(_n('Man Utd'),_n('AS Roma'),'x')])=='x' and loose(_n('Leeds'),_n('Hull'),[(_n('Leeds'),_n('Stoke'),'x')]) is None
    assert loose(_n('Real Oviedo'),_n('Real Madrid'),[(_n('Real Oviedo'),_n('Real Madrid'),'a'),(_n('Real Oviedo'),_n('Real Madrid'),'b')]) is None
    l=line([1.,3.,-1.,5.],[1,1,2,2]); assert l['n']==4 and l['h1']==2.0 and l['h2']==2.0 and not l['PASS']
    return True
if __name__=='__main__':
    _checks(); print("lib_cand known-answer checks: OK")
