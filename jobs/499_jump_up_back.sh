#!/bin/bash
set -o pipefail
# 499_jump_up_back (Finder 2026-11-07, queue item 414, Finder's own, source a; entry from jobs/499_flip_flow.sh, touch from jobs/499_fade_jump_touch.sh): back an MO runner whose first in-play print sits 2 to 4 implied points over its last pre-off print. Audit on months that chose it, so it cannot pass. Rule pushed in the queue before this job read a price. Read only, no tables written.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step,back_settle,tstat
from lib_official import bk,ly,fill,last_in,first_in,secs,checks,group,load_results
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
def gap_pts(pre,ip): return 100*(1/pre-1/ip)
def state(g):
    """g points: UP24, UP12, DN24, or None."""
    a=abs(g)
    if 2<=a<4: return 'UP24' if g>0 else 'DN24'
    if 1<=a<2 and g>0: return 'UP12'
    return None
def bk3(x,won):
    """Back three ticks adverse; None at the bottom of the ladder."""
    a=step(x,-3); return None if a<=1.01 else back_settle(a,won)
def next_only(ts,px,i,nxt=120):
    """The next print within nxt seconds, never the signal print; None if there is none."""
    return float(px[i+1]) if i+1<len(ts) and ts[i+1]-ts[i]<=nxt else None
def winner(last):
    w=[k for k,v in last.items() if v<=1.10]
    return w[0] if len(w)==1 else None
def value(px,last,s):
    """(back pnl, resolved) at px, one tick adverse. Unresolved at last-print odds, overround removed."""
    win,lose=bk(px,True),bk(px,False)
    if win is None: return None,False
    w=winner(last)
    if w is not None: return (win if w==s else lose),True
    t=sum(1/v for v in last.values()); p=(1/last[s])/t
    return p*win+(1-p)*lose,False
# known answers, worked by hand
assert abs(gap_pts(2.0,2.1)-2.38095)<1e-4 and state(gap_pts(2.0,2.1))=='UP24'       # 50 v 47.62
assert state(gap_pts(2.0,1.9))=='DN24' and state(gap_pts(2.0,2.06))=='UP12' and state(gap_pts(2.0,1.95)) is None and state(gap_pts(2.0,2.5)) is None   # -2.63; 1.46; -1.28 not read; 10
assert state(2.0)=='UP24' and state(3.999)=='UP24' and state(4.0) is None and state(1.0)=='UP12' and state(0.99) is None
assert abs(bk3(2.06,True)-9.8)<1e-9 and bk3(2.06,False)==-10.0 and bk3(1.03,True) is None     # 2.06 less 3 ticks is 2.0: 10 profit, 9.80 after 2%
assert next_only(np.array([0.,60.,300.]),np.array([2.,2.2,3.]),0)==2.2 and next_only(np.array([0.,60.,300.]),np.array([2.,2.2,3.]),1) is None and next_only(np.array([0.,60.]),np.array([2.,2.2]),1) is None
assert winner({'A':1.05,'B':30.})=='A' and winner({'A':1.5,'B':3.}) is None
assert abs(value(2.04,{'A':1.05,'B':30.},'A')[0]-9.996)<1e-9 and value(2.04,{'A':1.05,'B':30.},'B')==(-10.0,True)
print("checks: OK",flush=True); T0=time.time()
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
RS,dr=load_results(con,['MATCH_ODDS']); print("official markets",len(RS),"dropped",dr,f"{time.time()-T0:.0f}s",flush=True)
C=Counter(); rows=[]
def month_chunks():
    for y,ms in ((2023,range(6,13)),(2024,range(1,12)),(2026,range(5,11))):
        for m in ms:
            a=pd.Timestamp(y,m,1); e=a+pd.offsets.MonthBegin(1)
            if (y,m)>=(2026,8):
                while a<e:
                    b=min(a+pd.Timedelta(days=5),e); yield str(a.date()),str(b.date()); a=b
            else: yield str(a.date()),str(e.date())
for lo,hi in month_chunks():
    X=pd.read_sql("SELECT market_id,event_name ev,market_time mt,sel,inplay,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '11 minutes' AND ts<=market_time+interval '6 minutes' AND market_time>=%s AND market_time<%s",con,params=(lo,hi))
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
            pb=fill(c,d,i,'B'); pl=fill(c,d,i,'L'); nx=next_only(c,d,i); won=RS[mk][s]
            rows.append(dict(st=st,r=r,ev=ev,off=off,g=abs(g),px=float(d[i]),pb=pb,pl=pl,nx=nx,won=won,age=float(c[i]-a[pre]),delay=float(c[i]-off)))
    print(lo,"rows",len(X),"cands",len(rows),f"{time.time()-T0:.0f}s",flush=True); del X
print("counts",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows); T['era']=np.where(T.off<pd.Timestamp('2024-01-01',tz='UTC').timestamp(),'2023','chose')
T=T[T.pb<=50]
med=T.off.median(); T['h']=np.where(T.off<=med,1,2)
def row(nm,x,col='vb',tt=None):
    x=x.dropna(subset=[col]); v=x[col].astype(float).values
    if len(v)<2: return dict(line=nm,n=len(v))
    d=line(v,x.h.values); gm=x[['ev','off']].drop_duplicates().shape[0]
    return dict(line=nm,n=d['n'],games=gm,per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],no_top=round(np.delete(v,v.argmax()).mean(),3),won=round(x.won.astype(float).mean(),3),imp=round((1/x.px).mean(),3))
T['vb']=[bk(p,w) for p,w in zip(T.pb,T.won)]
T['v3']=[bk3(p,w) for p,w in zip(T.pb,T.won)]
T['vn']=[None if n is None or n!=n or n>50 else bk(n,w) for n,w in zip(T.nx,T.won)]
T['vp']=[bk(p,w) for p,w in zip(T.px,T.won)]
U=T[T.st=='UP24'].copy()
ONE=U.sort_values(['g','r'],ascending=[False,True]).drop_duplicates(['ev','off']).sort_values('off')   # one bet per game, the largest gap
o=[row('ONE E1 worse of print and next',ONE),row('ONE E2 next print only',ONE,'vn'),row('ONE E3 worse, 3 ticks',ONE,'v3'),row('ONE E0 signal print',ONE,'vp')]
for r_ in ('FAV','OUT','DRAW'):
    x=U[U.r==r_]; o+= [row(f'{r_} E1',x),row(f'{r_} E2 next print only',x,'vn')]
for e in ('2023','chose'):
    x=ONE[ONE.era==e]; o+= [row(f'ONE {e} E1',x),row(f'ONE {e} E2',x,'vn')]
for y in (2023,2024,2026):   # added after the first run, a print only: item 415's stream is Nov 2026, so does the tape hold nearest to it?
    x=ONE[pd.to_datetime(ONE.off,unit='s').dt.year==y]; o+= [row(f'ONE year {y} E1',x),row(f'ONE year {y} E2',x,'vn')]
for lab,a,b in (('px<3',0,3),('px 3-8',3,8),('px 8-50',8,51)):
    x=ONE[(ONE.px>=a)&(ONE.px<b)]; o+= [row(f'ONE {lab} E1',x),row(f'ONE {lab} E2',x,'vn')]
for lab,a,b in (('pre print <60s',0,60),('pre print 60-300s',60,300),('pre print 300s+',300,1e9)):
    x=ONE[(ONE.age>=a)&(ONE.age<b)]; o+= [row(f'ONE {lab} E2',x,'vn')]
for lab,a,b in (('first print before off',-1e9,0),('first print 0-60s',0,60),('first print 60s+',60,1e9)):
    x=ONE[(ONE.delay>=a)&(ONE.delay<b)]; o+= [row(f'ONE {lab} E2',x,'vn')]
print(f"\n== ITEM 414, audit, cannot pass; pre-print age median {ONE.age.median():.0f}s, first print median {ONE.delay.median():.0f}s after market time; next print exists on {ONE.nx.notna().mean():.3f}; median next print less signal in ticks")
print(pd.DataFrame(o).to_string(index=False))
c=[]
for st,lab in (('UP12','CONTROL UP 1-2 back'),('DN24','CONTROL DOWN 2-4 back')):
    x=T[T.st==st].sort_values('g',ascending=False).drop_duplicates(['ev','off'])
    c+= [row(lab+' E1',x),row(lab+' E2',x,'vn')]
print("\n-- controls, one bet per game\n",pd.DataFrame(c).to_string(index=False),flush=True)
# ---- real touch, local liq_sample
cur=con.cursor()
F=pd.read_sql("SELECT market_id,min(ts) FILTER (WHERE minute>=1) t1 FROM liq_sample WHERE mkt='MO' GROUP BY 1",con).dropna()
FIRST=dict(zip(F.market_id,secs(F.t1)))
Pre=pd.read_sql("SELECT DISTINCT ts,market_id,event_name ev,sel,ltp::float8 ltp FROM liq_sample WHERE mkt='MO' AND minute=0 AND ltp>=1.01 AND ltp<1000",con)
Fi=pd.read_sql("SELECT DISTINCT ON (market_id,sel) market_id,sel,minute,ts,ltp::float8 ltp,back_px::float8 b,lay_px::float8 l FROM liq_sample WHERE mkt='MO' AND minute>=1 ORDER BY market_id,sel,ts",con)
La=pd.read_sql("SELECT DISTINCT ON (market_id,sel) market_id,sel,ltp::float8 ltp FROM liq_sample WHERE mkt='MO' AND ltp>=1.01 AND ltp<1000 ORDER BY market_id,sel,ts DESC",con)
con.close()
Pre['tt']=secs(Pre.ts); Fi['tt']=secs(Fi.ts); LAST={m:dict(zip(g.sel,g.ltp)) for m,g in La.groupby('market_id')}; FI={m:g for m,g in Fi.groupby('market_id')}
print(f"\ntouch: dates {pd.to_datetime(Pre.tt.min(),unit='s')} to {pd.to_datetime(Pre.tt.max(),unit='s')}, pre rows {len(Pre):,}, {time.time()-T0:.0f}s",flush=True)
C=Counter(); tr=[]
for (m,ev),g in Pre.groupby(['market_id','ev'],sort=False):
    if m not in FI or m not in LAST or m not in FIRST: C['no in-play']+=1; continue
    t1=FIRST[m]; g=g[g.tt<=t1-120]
    if not len(g): C['no pre row 120 s before']+=1; continue
    if g.duplicated(['sel','tt']).any(): C['two rows one label']+=1; continue
    if set(LAST[m])!={'HOME','DRAW','AWAY'}: C['labels']+=1; continue
    pr=g.sort_values('tt').groupby('sel').tail(1).set_index('sel').ltp.to_dict(); best=None
    for r in FI[m].itertuples():
        if not 1<=r.minute<=3 or r.sel not in pr or r.ltp!=r.ltp or r.ltp<1.01 or r.b!=r.b or r.l!=r.l or r.b<1.01 or r.l<=r.b: continue
        j=gap_pts(pr[r.sel],r.ltp)
        if 2<=j<4 and (best is None or j>best[0]): best=(j,r)
    if best is None: C['no UP 2-4']+=1; continue
    j,r=best
    if r.b>50: C['over 50']+=1; continue
    v,rs=value(r.b,LAST[m],r.sel)
    if v is not None: tr.append((m,ev,r.tt,v,rs,r.ltp,r.b,r.l,100*(1/r.b-1/r.l)))
print("touch counts",dict(C),flush=True)
if tr:
    Z=pd.DataFrame(tr,columns='m ev tt v res ltp b l sp'.split()); h=np.where(Z.tt<=Z.tt.median(),1,2); d=line(Z.v.values,h)
    print(f"TOUCH UP 2-4 back at back_px, one tick: n {d['n']} per10 {d['per10']:+.3f} t {d['t']:.2f} h1 {d['h1']:+.3f} h2 {d['h2']:+.3f} resolved {Z.res.mean():.3f} resolved-only {Z[Z.res].v.mean() if Z.res.any() else float('nan'):+.3f}; spread median {Z.sp.median():.2f} points; share of rows with back_px at or over the print {(Z.b>=Z.ltp).mean():.3f}; median back_px less print implied {(100*(1/Z.b-1/Z.ltp)).median():+.2f} points")
print("\n== SURVIVORS: audit, cannot pass; a pass can only come on months no read has used",flush=True); print(f"total {time.time()-T0:.0f}s")
PY
