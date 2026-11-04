#!/bin/bash
set -o pipefail
# 499_racing_fade_wide_target (Finder 2026-11-04, queue item 53): RACING PRE-OFF FADE WITH A TARGET WIDE ENOUGH TO PAY. stream_ticks racing WIN, whole rolling table, from jobs/479 part C. PILOT. The number 499 is reused with a new slug: 450-499 are all taken.
# TRIGGER as 479 FADE: T-600 to T-30, price 2-8, gap <= 2 ticks, market matched >= £50k, mean touch weight over 30 s (at least 5 ticks) >= 0.65 and the last 3 traded prices not lengthening: LAY; <= 0.35 and not shortening: BACK. Touch only: no size at levels 2-3 on this box. FOLLOW = the same trigger unflipped, the control.
# CHANGED FROM 479, as the item says: one entry per runner per race, no 60 s exit, no cap of 3 open positions (a shared signal for all variants needs it; the cap would otherwise differ by variant).
# FILL: touch on the runner's NEXT tick. Back at back_px, lay at lay_px.
# EXITS: target T ticks (4, 6, 10) when a fresh print trades strictly through it, at the target level; stop S ticks (3, 5) at the real touch when the touch reaches it; else the real touch at the first tick at or under T-30, or on the first in-play or suspended tick. A position with no later tick closes at its last known touch, counted as stale, never dropped. HOLD = no target, no stop.
# COST: k = 1 (house), 0 and 3 ticks adverse each way on every entry and exit, 2% on profit, back stake £10, lay liability £10. One tick off a 4-tick target leaves 2 ticks. Halves: median entry time. FIRST = first trade per race, the line for t, as runners in a race are correlated.
python3 -W ignore - <<'PY' 2>&1
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import deque,defaultdict
from datetime import datetime,timedelta
pd.set_option('display.width',240); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',40)
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LADA=np.array(LAD)
def pos(p): return int(np.searchsorted(LADA,round(float(p),2)-1e-9))
def up(p,k=1): return float(LADA[min(pos(p)+k,len(LADA)-1)])
def dn(p,k=1): return float(LADA[max(pos(p)-k,0)])
def pnl(side,p,q,k=1):
    if side=='BACK':
        a=dn(p,k); b=up(q,k); r=10*(a/b-1)
    else:
        a=up(p,k); b=dn(q,k); r=10/(a-1)*(1-a/b)
    return r*0.98 if r>0 else r
def tstat(v):
    v=np.asarray(v,dtype=float); n=len(v)
    if n<2: return 0.0
    s=v.std(ddof=1); return float(v.mean()/(s/np.sqrt(n))) if s>0 else 0.0
class Sim:
    def __init__(s,name,flip,T,S):
        s.name,s.flip,s.T,s.S=name,flip,T,S; s.open={}; s.pend={}; s.seen=set(); s.closed=[]; s.stale=0
    def close(s,k,o,q,why):
        del s.open[k]
        s.closed.append(dict(sim=s.name,market_id=k[0],sel_id=k[1],ts=o['t'],side=o['side'],px=o['px'],q=q,why=why,sto=o['sto'],hold=(o['last_ts']-o['t']).total_seconds(),x0=pnl(o['side'],o['px'],q,0),x=pnl(o['side'],o['px'],q,1),x3=pnl(o['side'],o['px'],q,3)))
    def step(s,r,st):
        mid,sid,ts,bp,bs,lp,ls,ltp,tv,sto,inplay,status=r; k=(mid,sid); tvv=tv or 0.0
        o=s.open.get(k)
        if o:
            o['last_ts']=ts
            if bp and lp: o['bp'],o['lp']=bp,lp
            live=(not inplay) and status=='OPEN'; bk=o['side']=='BACK'
            if s.T and live and ltp and tvv>o['tv0']:
                tg=dn(o['px'],s.T) if bk else up(o['px'],s.T)
                if (ltp<tg if bk else ltp>tg): s.close(k,o,tg,'target'); return
            if bp and lp:
                ex=lp if bk else bp
                if not live: s.close(k,o,ex,'off')
                elif s.S and ((lp>=up(o['px'],s.S)) if bk else (bp<=dn(o['px'],s.S))): s.close(k,o,ex,'stop')
                elif sto is not None and sto<=30: s.close(k,o,ex,'T-30')
            return
        p=s.pend.pop(k,None)
        if p and not inplay and status=='OPEN' and bp and lp and sto is not None and sto>30:
            s.open[k]=dict(side=p,px=bp if p=='BACK' else lp,t=ts,last_ts=ts,tv0=tvv,sto=sto,bp=bp,lp=lp); return
        if p or k in s.seen or inplay or status!='OPEN': return
        if not (bp and lp and bs and ls and sto is not None and 30<sto<=600 and 2.0<=bp<=8.0): return
        if pos(lp)-pos(bp)>2 or sum(st['mv'][mid].values())<50000: return
        h=st['wom'][k]
        if len(h)<5: return
        wom=sum(x[1] for x in h)/len(h); l3=st['tr3'][k]
        if len(l3)<3: return
        ln=l3[0]<l3[1]<l3[2]; sh=l3[0]>l3[1]>l3[2]; side=None
        if wom>=0.65 and not ln: side='BACK'
        elif wom<=0.35 and not sh: side='LAY'
        if not side: return
        s.seen.add(k); s.pend[k]=({'BACK':'LAY','LAY':'BACK'}[side] if s.flip else side)
    def flush(s):
        for k,o in list(s.open.items()):
            s.stale+=1; s.close(k,o,o['lp'] if o['side']=='BACK' else o['bp'],'stale')
        s.pend={}
def new_state(): return dict(mv=defaultdict(dict),wom=defaultdict(deque),tr3=defaultdict(lambda:deque(maxlen=3)),tv=defaultdict(float))
def absorb(st,r):
    mid,sid,ts,bp,bs,lp,ls,ltp,tv,sto,inplay,status=r; k=(mid,sid)
    if tv is not None: st['mv'][mid][sid]=tv
    h=st['wom'][k]
    if bs and ls: h.append((ts,bs/(bs+ls)))
    while h and (ts-h[0][0]).total_seconds()>30: h.popleft()
    if ltp and tv is not None and tv>st['tv'][k]: st['tr3'][k].append(ltp)
    if tv is not None: st['tv'][k]=max(tv,st['tv'][k])
# known answers, worked by hand
assert up(4.0,4)==4.4 and dn(4.0,4)==3.8 and up(3.0,6)==3.3 and dn(3.0,3)==2.94
assert abs(pnl('LAY',3.0,3.2,0)-(10/2)*(1-3/3.2)*0.98)<1e-9 and abs(pnl('BACK',4.0,3.8,0)-10*(4/3.8-1)*0.98)<1e-9 and abs(pnl('BACK',4.0,4.2,0)-10*(4/4.2-1))<1e-9
assert abs(pnl('LAY',3.0,3.2,1)-(10/2.05)*(1-3.05/3.15)*0.98)<1e-9                       # stake 4.878, a 4-tick lay target less one tick each way
assert abs(pnl('BACK',4.0,3.8,1)-10*(3.95/3.85-1)*0.98)<1e-9                              # a 4-tick back target nets 2 ticks
def tk(sec,bp,lp,ltp,tv,sto,bs=70.,ls=30.,ip=False,status='OPEN'): return ('m','r',T00+timedelta(seconds=sec),bp,bs,lp,ls,ltp,tv,sto,ip,status)
T00=datetime(2026,11,1,12,0,0)
def warmed():
    st=new_state()
    for i,p in enumerate((3.0,3.0,3.0,3.0,3.0,3.0)): absorb(st,tk(i,3.0,3.05,p,50000.+1000*i,400.))
    return st
s=Sim('t',True,4,3); st=warmed()                                                          # heavy touch, not lengthening: BACK, flipped to LAY
s.step(tk(6,3.0,3.05,3.0,56000.,394.),st); assert s.pend.get(('m','r'))=='LAY'
s.step(tk(7,3.0,3.05,3.0,56000.,393.),st); o=s.open[('m','r')]; assert o['px']==3.05 and o['side']=='LAY' and not s.pend
s.step(tk(8,3.0,3.05,3.25,56000.,392.),st); assert s.open                                 # through 3.25 but no volume: a stale ltp
s.step(tk(9,3.2,3.25,up(3.05,4),57000.,391.),st); assert s.open                           # AT the target is not through
s.step(tk(10,3.3,3.35,3.3,58000.,390.),st); assert not s.open and s.closed[-1]['why']=='target' and s.closed[-1]['q']==up(3.05,4)
s.step(tk(11,3.0,3.05,3.0,59000.,389.),st); assert not s.pend and not s.open              # one entry per runner per race
s=Sim('t',True,4,3); st=warmed(); s.step(tk(6,3.0,3.05,3.0,56000.,394.),st); s.step(tk(7,3.0,3.05,3.0,56000.,393.),st)
s.step(tk(8,dn(3.05,3),2.96,2.96,56000.,392.),st); assert s.closed[-1]['why']=='stop' and s.closed[-1]['q']==dn(3.05,3)   # a lay's stop: touch shortens 3 ticks, back out at the touch
s=Sim('t',True,None,None); st=warmed(); s.step(tk(6,3.0,3.05,3.0,56000.,394.),st); s.step(tk(7,3.0,3.05,3.0,56000.,393.),st)
s.step(tk(8,2.5,2.52,2.5,57000.,300.),st); assert s.open                                  # HOLD ignores a big move
s.step(tk(9,2.6,2.62,2.6,57000.,30.),st); assert s.closed[-1]['why']=='T-30' and s.closed[-1]['q']==2.6
s=Sim('t',False,6,5); st=warmed(); s.step(tk(6,3.0,3.05,3.0,56000.,394.),st); assert s.pend[('m','r')]=='BACK'; s.step(tk(7,3.0,3.05,3.0,56000.,393.),st); assert s.open[('m','r')]['px']==3.0
s.step(tk(8,3.0,3.05,3.0,56000.,392.),st); s.flush(); assert s.stale==1 and s.closed[-1]['why']=='stale' and s.closed[-1]['q']==3.05   # no later tick: last touch, not dropped
s=Sim('t',True,4,3); st=warmed(); s.step(tk(6,3.0,3.05,3.0,56000.,700.),st); assert not s.pend  # outside T-600
assert abs(tstat([1,3])-2.0)<1e-9
print("known-answer checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SELECT min(ts_recv),max(ts_recv) FROM stream_ticks"); lo,hi=cur.fetchone(); print(f"stream_ticks {lo} .. {hi}",flush=True)
SIMS=[Sim(f"FADE T{a} S{b}",True,a,b) for a in (4,6,10) for b in (3,5)]+[Sim("FADE HOLD",True,None,None),Sim("FOLLOW T6 S3",False,6,3),Sim("FOLLOW HOLD",False,None,None)]
day=pd.Timestamp(lo).tz_convert('UTC').normalize(); end=pd.Timestamp(hi).tz_convert('UTC'); t0=time.time()
while day<=end:
    a=day+pd.Timedelta(hours=9); b=day+pd.Timedelta(hours=23)
    con2=psycopg2.connect(DB,sslmode='require'); c3=con2.cursor(); c3.execute("SET LOCAL work_mem='64MB'; SET LOCAL statement_timeout='2400s'"); c2=con2.cursor(name='rt'); c2.itersize=50000
    c2.execute("""SELECT market_id,sel_id,ts_recv,back_px::float,back_sz::float,lay_px::float,lay_sz::float,ltp::float,tv::float,secs_to_off,inplay,status FROM stream_ticks
       WHERE ts_recv>=%s AND ts_recv<%s AND sport='racing' AND mkt='WIN' AND secs_to_off>=-1800 AND secs_to_off<=1200 ORDER BY ts_recv""",(a,b))
    st=new_state(); n=0
    for r in c2:
        n+=1
        for s in SIMS: s.step(r,st)   # the signal sees this tick only from the next tick on
        absorb(st,r)
    c2.close(); con2.close()
    for s in SIMS: s.flush()
    print(f"  {day.date()}: {n} ticks, trades {len(SIMS[0].closed)}, {int(time.time()-t0)}s",flush=True)
    day+=pd.Timedelta(days=1)
print("stale exits, closed at the last touch:",{s.name:s.stale for s in SIMS})
C=pd.DataFrame([x for s in SIMS for x in s.closed])
if C.empty: print("ERROR: no trades, so no verdict"); sys.exit(1)
med=C[C.sim=='FADE HOLD'].ts.sort_values().iloc[len(C[C.sim=='FADE HOLD'])//2]; C['late']=C.ts>=med; print("halves at",med)
C['band']=pd.cut(C.px,[0,3,5,1000],labels=['2-3','3-5','5-8'],right=False).astype(str)
def line(name,d,col='x'):
    f=d.sort_values('ts').drop_duplicates('market_id'); v=f[col]; a=f[~f.late][col]; c=f[f.late][col]
    r=dict(line=name,all_n=len(d),all_=d[col].mean(),all_t=tstat(d[col]),no_cost=d.x0.mean(),x3=d.x3.mean(),hit=(d.x>0).mean(),n=len(v),races=f.market_id.nunique(),per10=v.mean(),t=tstat(v),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(c),h2=c.mean() if len(c) else np.nan)
    r['PASS']=bool(r['n']>=300 and r['n1']>=150 and r['n2']>=150 and r['t']>=3.5 and r['h1']>0 and r['h2']>0 and r['per10']>=0.15); return r
O=[]
for nm,d in C.groupby('sim'):
    O.append(line(nm,d))
    for c in ('side','band'):
        for v,e in d.groupby(c): O.append(line(f"{nm} {c}={v}",e))
R=pd.DataFrame(O).sort_values('t',ascending=False)
print("\n== LINES (per10, t, n, h1, h2 = FIRST per race, what PASS reads; all_ = every runner, one tick)\n",R.drop(columns=['PASS']).round(3).head(45).to_string(index=False))
print("\nexit reasons, every trade:\n",C.groupby(['sim','why']).x.agg(['size','mean']).round(3).to_string())
W=R[R.PASS]; print(f"\n== SURVIVORS: {len(W)} of {len(R)} lines, pilot on a few days"); print(W.round(3).to_string(index=False) if len(W) else "none"); print(f"total {time.time()-t0:.0f}s")
PY
