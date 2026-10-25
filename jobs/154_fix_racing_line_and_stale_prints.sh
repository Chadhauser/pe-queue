#!/bin/bash
# 154: (a) RACING RECORDER — 147 broke it: the WOM_T edit inserted a '#' comment mid-line, commenting out WOM_SECS/TGT/STOP/LAST_ENTRY/
#     FLAT_AT/STAKE/COMM -> NameError every loop since 16:32 Sat. Restore the full constants line (WOM rule still off), restart, prove it.
# (b) SPORT SWEEP STALE PRINTS — the grammar forward-fills prices by minute, so a GOAL entry at goal+2 in a market still suspended used
#     the PRE-goal price (the exact artefact that produced the oracle's fake +£23). Fix: track the minute of the last real print; a GOAL
#     entry needs a print after the goal; any entry needs a print within the last 2 minutes. Kill the running sweep, patch, restart.
# (c) goal_capture: fix the R.drop name clash (DataFrame.drop) and re-run so the drop-size buckets print.
echo "== (a) racing"
python3 - <<'PY'
p='/root/pe-race/race_swing.py'; s=open(p).read(); lines=s.splitlines()
for i,l in enumerate(lines):
    if l.startswith('WOM_T='):
        lines[i]="WOM_T=1.01; WOM_SECS=20; TGT=3; STOP=3; LAST_ENTRY=30; FLAT_AT=20; STAKE=10.0; COMM=0.02   # WOM_T 1.01 = WOM rule OFF (24 Oct), tape continues"
        print("restored:",lines[i]); break
open(p,'w').write("\n".join(lines)+"\n")
PY
python3 -m py_compile /root/pe-race/race_swing.py || exit 1
pkill -9 -f race_swing.py; sleep 2; /root/pe-race/keepalive.sh; sleep 45; pgrep -af race_swing.py; tail -3 /root/pe-race/race.log
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor(); c.execute("SELECT last_seen, now()-last_seen AS age, live_markets FROM racing_heartbeat"); print("racing heartbeat:",c.fetchall())
PY
echo "== (b) sport sweep stale-print fix"
cd /root/pe-factory/v4 && pkill -f sport_sweep.py; sleep 1
python3 - <<'PY'
p='sport_sweep.py'; s=open(p).read(); n=0
old='''def dense(s):   # minute-indexed series -> array[0..MAXM] forward-filled, NaN before first print
    a=np.full(MAXM+1,np.nan); m=s.index.values.astype(int); v=s.values; ok=(m>=0)&(m<=MAXM); a[m[ok]]=v[ok]
    last=np.nan
    for i in range(MAXM+1):
        if np.isnan(a[i]): a[i]=last
        else: last=a[i]
    return a'''
new='''def dense(s):   # minute-indexed series -> (prices forward-filled, minute of last real print) arrays [0..MAXM]
    a=np.full(MAXM+1,np.nan); m=s.index.values.astype(int); v=s.values; ok=(m>=0)&(m<=MAXM); a[m[ok]]=v[ok]
    lp=np.full(MAXM+1,-1); last=np.nan; lm=-1
    for i in range(MAXM+1):
        if np.isnan(a[i]): a[i]=last
        else: last=a[i]; lm=i
        lp[i]=lm
    return a,lp'''
assert old in s; s=s.replace(old,new); n+=1
old2="    P={sel:dense(S[sel]) for sel in SIDES}"
new2="    DD={sel:dense(S[sel]) for sel in SIDES}; P={k:v[0] for k,v in DD.items()}; LP={k:v[1] for k,v in DD.items()}"
assert old2 in s; s=s.replace(old2,new2); n+=1
s=s.replace("    return P,gl,scorers,winner","    return P,LP,gl,scorers,winner"); n+=1
s=s.replace("def game_trades(P,gl,scorers,winner,date):","def game_trades(P,LP,gl,scorers,winner,date):"); n+=1
old3='''    def emit(trig,role,side,m):
        if m in barred or m<1 or m>88: return
        e=px(side,m)
        if e is None: return'''
new3='''    def emit(trig,role,side,m,after=None):
        if m in barred or m<1 or m>88: return
        if LP[side][m]<m-2: return                    # no real print in the last 2 minutes: stale, skip
        if after is not None and LP[side][m]<=after: return   # GOAL entry needs a print AFTER the goal minute
        e=px(side,m)
        if e is None: return'''
assert old3 in s; s=s.replace(old3,new3); n+=1
old4="                emit(f'GOAL{kk}+{d}',role,side,g+d)"
new4="                emit(f'GOAL{kk}+{d}',role,side,g+d,after=g)"
assert old4 in s; s=s.replace(old4,new4); n+=1
# exits must also be real prints: px for exits -> require print within 2 min of the exit minute
old5='''    def px(side,m):
        if m>MAXM: return None
        v=P[side][m]; return None if (np.isnan(v) or v<=1.01) else float(v)'''
new5='''    def px(side,m):
        if m>MAXM or LP[side][m]<m-2: return None
        v=P[side][m]; return None if (np.isnan(v) or v<=1.01) else float(v)'''
assert old5 in s; s=s.replace(old5,new5); n+=1
open(p,'w').write(s); print("patches applied:",n)
PY
python3 -m py_compile sport_sweep.py || exit 1
python3 - <<'PY'
import numpy as np, pandas as pd
src=open('/root/pe-factory/v4/sport_sweep.py').read().split("def main():")[0].replace("from bot_core import DB","DB=''"); ns={}; exec(src,ns)
rows=[]
for m in range(0,96):
    if 21<=m<=23: continue                         # goal print at 20, then no prints for 3 minutes (suspension): +2 entry must be skipped
    h=2.0 if m<20 else (1.4 if m<60 else 1.2); d=3.4 if m<20 else (5.0 if m<60 else 8.0); a=3.5 if m<20 else (8.0 if m<60 else 20.0)
    if m>=93: h,d,a=1.01,50.0,100.0
    for sel,p in (('HOME',h),('DRAW',d),('AWAY',a)): rows.append(dict(event_id='e',m=pd.Timestamp('2025-01-01'),minute=m,sel=sel,ltp=p))
g=pd.DataFrame(rows); P,LP,gl,sc,w=ns['parse_game'](g); print("goals",gl,"scorers",sc,"winner",w)
T=ns['game_trades'](P,LP,gl,sc,w,pd.Timestamp('2025-01-01').date()); R=pd.DataFrame(T,columns=['trig','role','dir','exit','band','d','p'])
g2=R[(R.trig=='GOAL1+2')]; g5=R[(R.trig=='GOAL1+5')&(R.role=='scorer')&(R.dir=='back')&(R.exit=='+5')]
print("goal at",gl[0],"| GOAL1+2 trades (must be 0, no print since the goal):",len(g2),"| GOAL1+5 back scorer +5:",g5.p.round(3).tolist(),"(expected -0.392 = spread at flat 1.4)")
assert len(g2)==0 and abs(g5.p.iloc[0]+0.392)<0.01; print("stale-print test PASS")
PY
(nohup timeout 10000 python3 sport_sweep.py > sport_sweep.log 2>&1 &); echo "sport sweep restarted"
echo "== (c) goal_capture re-run with drop buckets"
cd /root/pe-factory && sed -i "s/R\[R.drop<=0.6\]/R[R['drop']<=0.6]/; s/R\[R.drop>0.75\]/R[R['drop']>0.75]/" goal_capture.py && python3 -m py_compile goal_capture.py && timeout 1500 python3 goal_capture.py 2>&1 | grep -v -E "UserWarning|pd.read_sql" | sed -n '/big drop/,$p'
