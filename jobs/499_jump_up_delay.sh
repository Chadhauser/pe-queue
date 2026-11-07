#!/bin/bash
set -o pipefail
# 499_jump_up_delay (Finder 2026-11-07, queue items 422, 423, Finder's own, source a; signal from jobs/499_jump_up_back.sh, unchanged): item 414's signal on May 2023, unseen, and the same signal entered minutes later at a print whose side the signal did not choose. Rules pushed in the queue before this job read a price. Read only, no tables written. Prints only, so a pass is an upper bound.
# FIX 2026-11-07, first run: the three-tick column v3 was overwritten by the D=3 column, so E3 printed D3's numbers (n 116 -0.177). Renamed vt3; no rule changed, nothing else moves.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step,back_settle
from lib_official import bk,fill,last_in,first_in,secs,checks,group,load_results
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
DS=(3,5,10,15); WIDTH=300
def gap_pts(pre,ip): return 100*(1/pre-1/ip)
def state(g):
    """g points: UP24, UP12, DN24, FLAT under 1 point either way, or None. Item 414's three, plus FLAT as a control."""
    a=abs(g)
    if 2<=a<4: return 'UP24' if g>0 else 'DN24'
    if 1<=a<2 and g>0: return 'UP12'
    if a<1: return 'FLAT'
    return None
def bk3(x,won):
    a=step(x,-3); return None if a<=1.01 else back_settle(a,won)
def next_only(ts,px,i,nxt=120):
    return float(px[i+1]) if i+1<len(ts) and ts[i+1]-ts[i]<=nxt else None
def delayed(ts,px,t0,D):
    """Index of the first print from t0+D min to t0+D min+WIDTH s, else None. Never a print before t0+D min, never one past the window: no forward fill."""
    return first_in(ts,t0+D*60,t0+D*60+WIDTH)
# known answers, worked by hand
assert state(gap_pts(2.0,2.1))=='UP24' and state(gap_pts(2.0,1.9))=='DN24' and state(gap_pts(2.0,2.06))=='UP12' and state(gap_pts(2.0,2.02))=='FLAT' and state(gap_pts(2.0,1.95)) is None   # +2.38, -2.63, +1.46, +0.50, -1.28
assert state(0.5)=='FLAT' and state(-0.99)=='FLAT' and state(1.0)=='UP12' and state(-1.5) is None and state(2.0)=='UP24' and state(-3.9)=='DN24' and state(4.0) is None
_t=np.array([0.,100.,300.,700.,1000.]); _p=np.array([2.,2.1,2.2,2.3,2.4])
assert delayed(_t,_p,0.,5)==2 and delayed(_t,_p,100.,5)==3 and delayed(_t,_p,1000.,3) is None and delayed(_t,_p,0.,15)==4    # 300 s is inside; 400 to 700 reaches 700; none after 1180; 900 to 1200 holds 1000
assert delayed(np.array([0.,950.]),np.array([2.,2.1]),0.,15)==1 and delayed(np.array([0.,1201.]),np.array([2.,2.1]),0.,15) is None
assert abs(bk(2.04,True)-9.996)<1e-9 and bk(2.04,False)==-10.0     # 2.04 less a tick is 2.02: 10.2 profit, 9.996 after 2%
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
RS,dr=load_results(con,['MATCH_ODDS']); print("official markets",len(RS),"dropped",dr,f"{time.time()-T0:.0f}s",flush=True)
C=Counter(); rows=[]
def month_chunks():
    for y,ms in ((2023,range(5,13)),(2024,range(1,12)),(2026,range(5,11))):
        for m in ms:
            a=pd.Timestamp(y,m,1); e=a+pd.offsets.MonthBegin(1)
            if (y,m)>=(2026,8):
                while a<e:
                    b=min(a+pd.Timedelta(days=5),e); yield str(a.date()),str(b.date()); a=b
            else: yield str(a.date()),str(e.date())
for lo,hi in month_chunks():
    X=pd.read_sql("SELECT market_id,event_name ev,market_time mt,sel,inplay,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '11 minutes' AND ts<=market_time+interval '27 minutes' AND market_time>=%s AND market_time<%s",con,params=(lo,hi))
    if X.empty: print(lo,"no rows",flush=True); continue
    X['tt']=secs(X.ts); X['off']=secs(X.mt); X=X.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt'])
    for (ev,off),G_ in X.groupby(['ev','off'],sort=False):
        ids=sorted(G_.market_id.unique()); mk=ids[0]
        if ' v ' not in ev: C['no H v A']+=1; continue
        if group(ev): C['women or youth']+=1; continue
        if mk not in RS: C['no official']+=1; continue
        g0=G_[G_.market_id==mk]; legs={}
        for s,y in g0.groupby('sel',sort=False):
            pm=y[~y.inplay]; ip=y[y.inplay]
            legs[s]=(pm.tt.values,pm.ltp.values,ip.tt.values,ip.ltp.values)
        last={}
        for s,(a,b,_,_) in legs.items():
            i=last_in(a,off-600,off+360)
            if i is not None: last[s]=float(b[i])
        ru=[s for s in last if s!='The Draw']
        if len(ru)<2 or last[ru[0]]==last[ru[1]]: C['roles unknown']+=1; continue
        roles={min(ru,key=lambda s:last[s]):'FAV',max(ru,key=lambda s:last[s]):'OUT'}
        if 'The Draw' in last: roles['The Draw']='DRAW'
        for s,r in roles.items():
            if s not in RS[mk]: continue
            a,b,c,d=legs[s]; i=first_in(c,off-300,off+180)
            if i is None: continue
            pre=last_in(a,off-600,float(c[i]))
            if pre is None: continue
            g=gap_pts(float(b[pre]),float(d[i])); st=state(g)
            if st is None: continue
            won=RS[mk][s]; t0=float(c[i])
            rec=dict(st=st,r=r,ev=ev,off=off,g=abs(g),px=float(d[i]),pb=fill(c,d,i,'B'),nx=next_only(c,d,i),won=won,delay=t0-off)
            for D in DS:
                j=delayed(c,d,t0,D)
                if j is None: rec[f'p{D}']=np.nan; rec[f'm{D}']=np.nan; continue
                rec[f'p{D}']=fill(c,d,j,'B'); rec[f'm{D}']=float(d[j])
            rows.append(rec)
    print(lo,"rows",len(X),"cands",len(rows),f"{time.time()-T0:.0f}s",flush=True); del X
con.close(); print("counts",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows); T=T[T.pb<=50].copy()
T['dt']=pd.to_datetime(T.off,unit='s',utc=True); T['era']=np.where(T.dt<pd.Timestamp('2023-06-01',tz='UTC'),'MAY23','CHOSE')
T['vb']=[bk(p,w) for p,w in zip(T.pb,T.won)]
T['vn']=[None if n is None or n!=n or n>50 else bk(n,w) for n,w in zip(T.nx,T.won)]
T['vt3']=[bk3(p,w) for p,w in zip(T.pb,T.won)]
for D in DS:
    T[f'v{D}']=[None if p!=p or p>50 else bk(p,w) for p,w in zip(T[f'p{D}'],T.won)]
    T[f'r{D}']=100*(1/T[f'm{D}']-1/T.px)    # points the runner has shortened since the signal, at the delayed print; positive is back in the backer's favour already
assert not T['vt3'].equals(T['v3'])
def row(nm,x,col):
    x=x.dropna(subset=[col]); v=x[col].astype(float).values
    if len(v)<2: return dict(line=nm,n=len(v))
    med=x.off.median(); h=np.where(x.off<=med,1,2); d=line(v,h); px=x[f'p{col[1:]}'] if col[1:] in map(str,DS) else x.pb
    return dict(line=nm,n=d['n'],games=x[['ev','off']].drop_duplicates().shape[0],per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],no_top=round(np.delete(v,v.argmax()).mean(),3),won=round(x.won.astype(float).mean(),3),imp=round((1/px).mean(),3),PASS=d['PASS'])
def one(st): return T[T.st==st].sort_values(['g','r'],ascending=[False,True]).drop_duplicates(['ev','off']).sort_values('off')
ONE=one('UP24')
print(f"\n== ITEM 422 May 2023, unseen, scored ONE E1; all else for reading")
M=ONE[ONE.era=='MAY23']
print(pd.DataFrame([row('MAY23 ONE E1 worse of print and next *',M,'vb'),row('MAY23 ONE E2 next print',M,'vn'),row('MAY23 ONE E3 three ticks',M,'vt3')]+[row(f'MAY23 {r_} E1',M[M.r==r_],'vb') for r_ in ('FAV','OUT','DRAW')]).to_string(index=False))
print("\n== item 414 reproduced on its own months, must read n 1,500 +1.321")
Ch=ONE[ONE.era=='CHOSE']; R0=row('CHOSE ONE E1',Ch,'vb'); print(R0)
print("\n== ITEM 423 delayed entry. Scored: MAY23 D5, cannot reach n tonight. CHOSE is an audit: those months chose the signal, the delay is new")
o=[]
for era,x in (('MAY23',M),('CHOSE',Ch),('ALL',ONE)):
    for D in DS: o.append(row(f'{era} ONE D{D}'+(' *' if era=='MAY23' and D==5 else ''),x,f'v{D}'))
print(pd.DataFrame(o).to_string(index=False))
print("\nmedian points shortened since the signal at the delayed print, and share with a print at all, ONE all months")
for D in DS: print(f"  D{D}: median {ONE[f'r{D}'].median():+.2f} mean {ONE[f'r{D}'].mean():+.2f}, has a print {ONE[f'p{D}'].notna().mean():.3f}")
o=[]
for r_ in ('FAV','OUT','DRAW'):
    x=ONE[ONE.r==r_]
    for D in (5,10): o.append(row(f'{r_} D{D} all months',x,f'v{D}'))
for lab,a,b in (('first print 0-60s',-1e9,60),('first print 60s+',60,1e9)):
    x=ONE[(ONE.delay>=a)&(ONE.delay<b)]
    for D in (5,10): o.append(row(f'{lab} D{D} all months',x,f'v{D}'))
for lab,a,b in (('px<3',0,3),('px 3-8',3,8),('px 8-50',8,51)):
    x=ONE[(ONE.px>=a)&(ONE.px<b)]; o.append(row(f'{lab} D5 all months',x,'v5'))
for y in (2023,2024,2026):
    x=ONE[ONE.dt.dt.year==y]; o.append(row(f'year {y} D5',x,'v5'))
print("\nfor reading, not cut on, all months"); print(pd.DataFrame(o).to_string(index=False))
c=[]
for st,lab in (('UP12','CONTROL UP 1-2'),('DN24','CONTROL DOWN 2-4')):
    x=one(st)
    for D in (5,10): c.append(row(f'{lab} D{D}',x,f'v{D}'))
for r_ in ('FAV','OUT','DRAW'):
    x=T[(T.st=='FLAT')&(T.r==r_)]
    for D in (5,10): c.append(row(f'CONTROL FLAT {r_} D{D}',x,f'v{D}'))
print("\n-- controls, not scored"); print(pd.DataFrame(c).to_string(index=False),flush=True)
print("\n== SURVIVORS"); S=[row('MAY23 ONE E1',M,'vb'),row('MAY23 ONE D5',M,'v5')]; S=[s for s in S if s.get('PASS')]; print(S if S else "none",flush=True); print(f"total {time.time()-T0:.0f}s")
PY
