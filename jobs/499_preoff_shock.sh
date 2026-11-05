#!/bin/bash
set -o pipefail
# 499_preoff_shock (Finder 2026-11-05, queue item 126, Finder's own, source d): pre-off price shock, cricket (the toss) and tennis, follow or fade, closed before the off.
# Rule written in the queue before any price was read. The number 499 is reused with a new slug: 450-499 are all taken.
# DATA bf_hist_other MATCH_ODDS, read-only, local DB. No test tables. Real prints only, never forward-filled.
# LIMIT last-traded prints, no spread on the box, so one tick adverse each way is a floor on cost, not a measure of it. A pass is an upper bound and needs the real touch.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_hedge,lay_hedge,tstat,passes
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',40)
T0=time.time()
XS=(3,5,10); MIN=60.0
PLO,PHI=1.10,20.0
WINS=(('T90-45',-90,-45),('T45-15',-45,-15),('T15-5',-15,-5))
BANDS=(('P<1.5',PLO,1.5),('P1.5-2.5',1.5,2.5),('P2.5-20',2.5,PHI))

def fill(side,trig,nxt):
    """Worse of trigger and next print, then one tick adverse. Back wants high, lay wants low."""
    return step(min(trig,nxt),-1) if side=='BACK' else step(max(trig,nxt),1)
def pnl(side,a,x):
    """a is the fill (tick already taken); the hedge functions take the raw exit print and apply its tick."""
    return back_hedge(a,x) if side=='BACK' else lay_hedge(a,x)
def scan(ts,px,flag,sched,x,win_lo=-90,win_hi=-5):
    """One runner, ts seconds ascending, flag True = in-play. Returns first trigger index or None. Reference = latest print 30 s to 5 min earlier, real, never carried past 5 min."""
    for i in range(len(ts)):
        if flag[i]: break
        m=(ts[i]-sched)/MIN
        if m<win_lo: continue
        if m>win_hi: break
        j=i-1
        while j>=0 and ts[i]-ts[j]<30: j-=1
        if j<0 or ts[i]-ts[j]>300: continue
        if abs(px[i]/px[j]-1)*100>=x: return i,(1 if px[i]<px[j] else -1)
    return None
def exit_print(ts,px,flag,e):
    """Index of exit after entry index e: first pre-off print 10+ min on, else last pre-off print after entry, else first in-play print."""
    last=None
    for k in range(e+1,len(ts)):
        if flag[k]: return last if last is not None else k
        if ts[k]-ts[e]>=600: return k
        last=k
    return last

# known answers, worked by hand
assert fill('BACK',3.0,3.1)==2.98 and fill('LAY',3.0,3.1)==3.15 and fill('BACK',2.0,1.9)==1.89 and fill('LAY',2.0,1.9)==2.02
# back fill 2.98, exit print 2.0 -> lay out 2.02: 10*(2.98/2.02-1)=4.752475, net of 2% 4.657426. Lay fill 3.05, exit 5.0 -> back out 4.9: 10/2.05*(1-3.05/4.9)=1.841667, net 1.804878.
assert abs(pnl('BACK',2.98,2.0)-4.657426)<1e-5 and abs(pnl('LAY',3.05,5.0)-1.804878)<1e-5
# losing green takes no commission: back fill 2.0, exit 2.5 -> lay out 2.52: 10*(2/2.52-1)=-2.063492
assert abs(pnl('BACK',2.0,2.5)+2.063492)<1e-5
# trigger: 2.0 at -40 min, 2.0 at -39, 1.9 at -38 = -5% against the print 60 s before; X=5 fires on index 2, X=10 does not; a gap over 5 min does not fire; the 30 s floor skips a print 10 s back; in-play stops the scan
s=0.0; t_=np.array([-40,-39,-38])*60.0; p_=np.array([2.0,2.0,1.9]); f_=np.array([False]*3)
assert scan(t_,p_,f_,s,5)==(2,1) and scan(t_,p_,f_,s,10) is None
assert scan(np.array([-40,-30])*60.0,np.array([2.0,1.5]),np.array([False,False]),s,5) is None
assert scan(np.array([-2440.,-2400.,-2390.]),np.array([2.0,2.0,1.5]),f_,s,5)==(2,1)     # reference skips the print 10 s back, uses the one 50 s back
assert scan(np.array([-2410.,-2400.,-2390.]),np.array([2.0,2.0,1.5]),f_,s,5) is None    # nothing 30 s back at all
assert scan(np.array([-1800.,-1790.]),np.array([2.0,2.0]),np.array([False,False]),s,5) is None
assert scan(t_,p_,np.array([True,True,True]),s,5) is None
assert scan(np.array([-100,-99])*60.0,np.array([2.0,1.5]),np.array([False,False]),s,5) is None   # before the window
# exit: 10+ min print wins; else last pre-off; else first in-play
T=np.array([0.,60.,700.,800.]); P=np.array([2,2,2,2.]); assert exit_print(T,P,np.array([False]*4),0)==2
assert exit_print(T,P,np.array([False,False,True,True]),0)==1 and exit_print(T,P,np.array([False,True,True,True]),0)==1 and exit_print(T[:1],P[:1],np.array([False]),0) is None
print("checks: OK",flush=True)

con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
MONTHS=pd.date_range('2024-08-01','2026-10-01',freq='MS')
trades=[]; ctrl=[]; stats=dict(markets=0,no_next=0,no_exit=0,out_band=0)
for sport in ('Cricket','Tennis'):
    st0=dict(stats)
    for a,b in zip(MONTHS[:-1],MONTHS[1:]):
        # pre-off from T-100, and in-play prints only up to T+6 h: enough for the first in-play print of each runner, as an exit of last resort.
        d=pd.read_sql("""SELECT market_id,event_id,sel,EXTRACT(EPOCH FROM ts)::float8 tt,EXTRACT(EPOCH FROM market_time)::float8 sch,ltp::float8 ltp,inplay
                         FROM bf_hist_other WHERE sport=%s AND market_type='MATCH_ODDS' AND market_time>=%s AND market_time<%s
                           AND ts>=market_time-interval '100 minutes' AND ts<market_time+interval '6 hours' AND ltp>1""",con,params=(sport,a,b))
        if d.empty: continue
        d=d[~d.sel.astype(str).str.lower().str.contains('draw')]
        for mid,g in d.groupby('market_id',sort=False):
            stats['markets']+=1
            sch=float(g.sch.iloc[0]); run={}
            for sel,h in g.groupby('sel',sort=False):
                h=h.sort_values('tt'); run[sel]=(h.tt.values,h.ltp.values,h.inplay.values.astype(bool))
            # control: first pre-off print after T-30 of the first runner by name, both sides, same exit rule, no trigger
            for sel in sorted(run):
                ts,px,fl=run[sel]; idx=np.where((~fl)&(ts>=sch-1800)&(ts<=sch-300))[0]
                if len(idx)>=2 and PLO<=px[idx[1]]<=PHI:
                    i=idx[0]; e=idx[1]; k=exit_print(ts,px,fl,e)
                    if k is not None:
                        for side in ('BACK','LAY'):
                            ctrl.append(dict(sport=sport,side=side,mid=mid,tt=ts[e],pl=pnl(side,fill(side,px[i],px[e]),px[k])))
                    break
            for X in XS:
                best=None
                for sel in sorted(run):
                    ts,px,fl=run[sel]; r=scan(ts,px,fl,sch,X)
                    if r and (best is None or ts[r[0]]<best[0]): best=(ts[r[0]],sel,r[0],r[1])
                if best is None: continue
                _,sel,i,dirn=best; ts,px,fl=run[sel]
                e=i+1
                if e>=len(ts) or fl[e] or ts[e]-ts[i]>120: stats['no_next']+=1; continue
                if not (PLO<=px[e]<=PHI): stats['out_band']+=1; continue
                k=exit_print(ts,px,fl,e)
                if k is None: stats['no_exit']+=1; continue
                m=(ts[i]-sch)/MIN; win=next((w for w,lo,hi in WINS if lo<=m<hi),None); band=next((n for n,lo,hi in BANDS if lo<=px[e]<hi),BANDS[-1][0])
                for rule in ('FOLLOW','FADE'):
                    side=('BACK' if dirn==1 else 'LAY') if rule=='FOLLOW' else ('LAY' if dirn==1 else 'BACK')
                    trades.append(dict(sport=sport,X=X,rule=rule,side=side,sel=sel,win=win,band=band,mid=mid,ev=g.event_id.iloc[0],tt=ts[e],hold=ts[k]-ts[e],exit_ip=bool(fl[k]),dirn=dirn,trig=px[i],nxt=px[e],ext=px[k],tentry=ts[e],pl=pnl(side,fill(side,px[i],px[e]),px[k])))
        print(f"  {sport} {a:%Y-%m} rows {len(d):,}; trades so far {len(trades):,}; {time.time()-T0:.0f}s",flush=True)
    print(f"{sport}: "+str({k:stats[k]-st0[k] for k in stats}),flush=True)
con.close()
A=pd.DataFrame(trades); C=pd.DataFrame(ctrl)
print(f"trade rows {len(A):,}, markets traded {A.mid.nunique():,}, events {A.ev.nunique():,}; exits in-play share {A.exit_ip.mean():.3f}; median hold {A.hold.median():.0f}s",flush=True)
def line(d,name):
    v=d.pl.values; med=MEDS[d.sport.iloc[0]]; a=v[d.tt.values<med]; b=v[d.tt.values>=med]
    q=np.quantile(np.abs(v),.99); tr=v[np.abs(v)<=q]
    return dict(line=name,n=len(v),games=d.mid.nunique(),per10=v.mean(),t=tstat(v),h1=a.mean() if len(a) else np.nan,h2=b.mean() if len(b) else np.nan,n1=len(a),n2=len(b),win=(v>0).mean(),trim99=tr.mean(),best=v.max(),
                PASS=passes(len(v),len(a),len(b),tstat(v),a.mean() if len(a) else -1,b.mean() if len(b) else -1,v.mean()))
MEDS={s:A[A.sport==s].tt.median() for s in A.sport.unique()}
out=[]
for (sp,X,ru),d in A.groupby(['sport','X','rule']):
    out.append(line(d,f"{sp} X{X} {ru} all"))
    for w,_,_ in WINS:
        x=d[d.win==w]
        if len(x): out.append(line(x,f"{sp} X{X} {ru} {w}"))
    for b,_,_ in BANDS:
        x=d[d.band==b]
        if len(x): out.append(line(x,f"{sp} X{X} {ru} {b}"))
R=pd.DataFrame(out).sort_values('t',ascending=False)
print(f"lines tested {len(R)}; by chance about {len(R)*0.05:.0f} would reach t>=1.65",flush=True)
print("== all windows, every X (the headline lines)"); print(R[R.line.str.endswith(' all')].sort_values('line').round(3).to_string(index=False))
print("== top 15 by t"); print(R.head(15).round(3).to_string(index=False))
print("== bottom 5 by t"); print(R.tail(5).round(3).to_string(index=False))
print("== control: first print after T-30, no trigger, same exit rule")
for (sp,si),d in C.groupby(['sport','side']):
    print(f"  {sp} {si} n {len(d):,} per10 {d.pl.mean():+.3f} t {tstat(d.pl.values):.2f}")
print("== cricket window split v control: is the toss window different?")
print(R[R.line.str.startswith('Cricket')&R.line.str.contains('T45-15')].sort_values('line').round(3).to_string(index=False))
print("== reversion: (FADE - FOLLOW)/2 per £10 at the same entries; FADE + FOLLOW is the round-trip cost. Last-traded prints bounce between back and lay, so part of this is the spread, not a move a trader could collect")
for (sp,X),d in A.groupby(['sport','X']):
    f=d[d.rule=='FADE'].pl.mean(); g=d[d.rule=='FOLLOW'].pl.mean(); print(f"  {sp} X{X}: reversion {(f-g)/2:+.3f}, round-trip cost {f+g:+.3f}")
F_=A[A.rule=='FADE'].pl; ne=stats['no_exit']
print(f"== unexited entries: {ne} across all sports and X, v {len(F_):,} entries. FADE, all entries {F_.mean():+.3f}; with each unexited entry charged the full -£10 {(F_.sum()-10*ne)/(len(F_)+ne):+.3f}")
print("== three trades to hand-check against the raw prints")
for _,r in A[(A.rule=='FADE')&(A.X==5)].sample(3,random_state=7).iterrows():
    print(f"  {r.sport} market {r.mid} sel {r.sel!r} entry at {pd.to_datetime(r.tentry,unit='s')} UTC trig {r.trig} next {r.nxt} exit print {r.ext} side {r.side} pl {r.pl:+.3f}")
print("== SURVIVORS"); S=R[R.PASS]; print(S.round(3).to_string(index=False) if len(S) else "  none")
print(f"done {time.time()-T0:.0f}s")
PY
