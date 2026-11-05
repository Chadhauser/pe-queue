# lib_inplay (Finder 2026-11-05, items 179-181): minute-tape entry and exit for bf_hist_price arrays, from jobs/499_let_off.sh. Run directly for the known-answer checks. No database access, no secrets.
# TAPE MINUTE: first half 0..46, second half about the match clock from 47 (jobs/499_goal_timing.sh): tape 46 is still the first half, tape 47 is about 20 minutes later.
import numpy as np
from lib_cand import step,back_settle,lay_settle,back_hedge,lay_hedge
def first_print(arr,a,b):
    """First minute in a..b holding a real print, else None. Never forward-fills."""
    for m in range(max(a,0),min(b,95)+1):
        if arr[m]==arr[m]: return m
    return None
def fill(arr,m,side):
    """Worse of the print at m and the next print within 2 minutes: back takes the lower, lay the higher."""
    p=arr[m]
    for k in (m+1,m+2):
        if k<=95 and arr[k]==arr[k]:
            p=min(p,arr[k]) if side=='B' else max(p,arr[k]); break
    return float(p)
def enter(arr,lo,hi,side):
    """(print minute, fill one tick adverse), or None if no print in the window or a back at the bottom of the ladder."""
    d=first_print(arr,lo,hi)
    if d is None: return None
    a=step(fill(arr,d,side),-1 if side=='B' else 1)
    if side=='B' and a<=1.01: return None
    return d,a
def settle(side,a,won): return back_settle(a,won) if side=='B' else lay_settle(a,won)
def exit_later(side,a,arr,d,won,k=10,settles_at=None):
    """Out at the first print k or more minutes after d. No print, or the market settled by that print = settled at the result, never dropped."""
    x=first_print(arr,d+k,95)
    if x is None or (settles_at is not None and settles_at<=x): return settle(side,a,won)
    return back_hedge(a,float(arr[x])) if side=='B' else lay_hedge(a,float(arr[x]))
def checks():
    a=np.full(96,np.nan); a[12]=2.0; a[13]=2.1; a[25]=3.0
    assert first_print(a,12,14)==12 and first_print(a,14,16) is None and first_print(a,90,200) is None
    assert fill(a,12,'B')==2.0 and fill(a,12,'L')==2.1 and fill(a,25,'L')==3.0
    # Back: worse print 2.0, one tick adverse 1.99. Wins 10*0.99*0.98=9.702, loses -10. Out at 3.0: lay at 3.05, 10*(1.99/3.05-1)=-3.47541, a loss, no commission.
    assert enter(a,12,14,'B')==(12,1.99) and abs(settle('B',1.99,True)-9.702)<1e-9 and settle('B',1.99,False)==-10
    assert abs(exit_later('B',1.99,a,12,False)+3.475410)<1e-5
    # Lay: worse print 2.1, one tick adverse 2.12, stake 10/1.12=8.928571. Selection loses: +8.75 after 2%. Out at 3.0: back at 2.98, 8.928571*(1-2.12/2.98)*0.98=2.5250.
    assert enter(a,12,14,'L')==(12,2.12) and abs(settle('L',2.12,False)-8.75)<1e-6 and settle('L',2.12,True)==-10
    assert abs(exit_later('L',2.12,a,12,False)-8.928571*(1-2.12/2.98)*.98)<1e-4
    assert enter(a,14,16,'B') is None                                # no print, no trade, never a fill from minute 13
    assert abs(exit_later('B',1.99,a,12,True,settles_at=20)-9.702)<1e-9   # market settled before the exit print: at the result
    assert exit_later('B',1.99,a,12,False,settles_at=20)==-10
    b=np.full(96,np.nan); b[12]=2.0
    assert abs(exit_later('B',1.99,b,12,True)-9.702)<1e-9            # no exit print: at the result
    c=np.full(96,np.nan); c[50]=1.02
    assert enter(c,47,52,'B') is None and enter(c,47,52,'L')==(50,1.03)   # back at 1.01 cannot be improved on, no trade; a lay can
    return True
if __name__=='__main__':
    checks(); print("lib_inplay known-answer checks: OK")
