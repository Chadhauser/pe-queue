#!/bin/bash
# 162: SWEEP — BOOK-SANITY GUARD. Inspected the "+£5 per £10" scorer>2.5 trades minute by minute: around goals the three selections'
# minute prices are NOT synchronised (e.g. 67': AWAY 1.29, DRAW 1.27, HOME 30 -> implied book 1.60; 71': book 0.63). Each selection's
# LTP is the last trade in that minute, so an illiquid side lags by a minute or two and a back at 5.2 "then" 1.27 is a price that
# never co-existed. Entries at 75-330 (no real liquidity) were also in the bucket. Guard: an entry minute is valid only if the three
# prices form a book between 0.92 and 1.12 (all three fresh) and the entry price is <= 12; exits use the same book check (else the
# next sane minute within 3). goal_capture gets the same rule. Sweep restarted; 163 reports.
cd /root/pe-factory/v4 && pkill -f sport_sweep.py; sleep 1
python3 - <<'PY'
p='sport_sweep.py'; s=open(p).read(); n=0
old='''    def px(side,m):
        if m>MAXM or LP[side][m]<m-2: return None
        v=P[side][m]; return None if (np.isnan(v) or v<=1.01) else float(v)'''
new='''    def sane(m):
        if m>MAXM: return False
        b=0.0
        for sd in SIDES:
            v=P[sd][m]
            if np.isnan(v) or v<=1.0 or LP[sd][m]<m-2: return False
            b+=1.0/v
        return 0.92<=b<=1.12
    def px(side,m):
        if m>MAXM or LP[side][m]<m-2: return None
        if not sane(m):
            m2=next((k for k in (m+1,m+2,m+3) if k<=MAXM and sane(k)),None)
            if m2 is None: return None
            m=m2
        v=P[side][m]; return None if (np.isnan(v) or v<=1.01) else float(v)'''
assert old in s; s=s.replace(old,new); n+=1
old2='''        e=px(side,m)
        if e is None: return
        if after is not None and role in ('scorer','conceder'):'''
new2='''        if not sane(m): return                        # entry minute must have a synchronised book
        e=px(side,m)
        if e is None or e>12: return
        if after is not None and role in ('scorer','conceder'):'''
assert old2 in s; s=s.replace(old2,new2); n+=1
open(p,'w').write(s); print("patches:",n)
PY
python3 -m py_compile sport_sweep.py || exit 1
python3 - <<'PY'
import numpy as np, pandas as pd
src=open('/root/pe-factory/v4/sport_sweep.py').read().split("def main():")[0].replace("from bot_core import DB","DB=''"); ns={}; exec(src,ns)
def game(lag):
    rows=[]
    for m in range(0,96):
        h=2.0 if m<20 else (1.4 if m<60 else 1.2); d=3.4 if m<20 else (5.0 if m<60 else 8.0); a=3.5 if m<20 else (8.0 if m<60 else 20.0)
        if lag and 20<=m<=22: a=3.5                   # away side lags the goal by 3 minutes -> book at 20-22 is ~1.5 (insane)
        if m>=93: h,d,a=1.01,50.0,100.0
        for sel,p in (('HOME',h),('DRAW',d),('AWAY',a)): rows.append(dict(event_id='e',m=pd.Timestamp('2025-01-01'),minute=m,sel=sel,ltp=p))
    g=pd.DataFrame(rows); P,LP,gl,sc,w=ns['parse_game'](g); T=ns['game_trades'](P,LP,gl,sc,w,pd.Timestamp('2025-01-01').date())
    R=pd.DataFrame(T,columns=['trig','role','dir','exit','band','d','p']); return R
R0=game(False); R1=game(True)
a=len(R0[(R0.trig=='GOAL1+2')]); b=len(R1[(R1.trig=='GOAL1+2')]); print("GOAL1+2 entries: synchronised",a,"| lagging side",b,"(must be 0)")
print("book at 1' synthetic:",round(1/2.0+1/3.4+1/3.5,3),"-> CLOCK1 entries",len(R0[R0.trig=='CLOCK1g0']))
assert a>0 and b==0 and len(R0[R0.trig=='CLOCK1g0'])>0; print("book-sanity PASS")
PY
(nohup timeout 10000 python3 sport_sweep.py > sport_sweep.log 2>&1 &); echo "sweep restarted"
cd /root/pe-factory && python3 - <<'PY'
p='goal_capture.py'; s=open(p).read()
old="            if abs(e/pres[scorer]-1)<0.10: stale_n[0]+=1; continue   # scorer's own price has not reacted: stale print"
new='''            if abs(e/pres[scorer]-1)<0.10: stale_n[0]+=1; continue   # scorer's own price has not reacted: stale print
            try:
                bk=sum(1.0/float(S[sd][em]) for sd in ('HOME','DRAW','AWAY') if em in S[sd].index)
            except Exception: bk=0
            if not (0.92<=bk<=1.12) or e>12: stale_n[0]+=1; continue      # unsynchronised book or no real liquidity'''
assert old in s; s=s.replace(old,new); open(p,'w').write(s); print("goal_capture book guard added")
PY
python3 -m py_compile goal_capture.py || exit 1
timeout 1500 python3 goal_capture.py 2>&1 | grep -v -E "UserWarning|pd.read_sql| processed" | sed -n '/entries removed/,/FIRST goal/p;/scorer > 2.5/,/goal before/p'
