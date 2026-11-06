#!/bin/bash
set -o pipefail
# 499_dnb_touch (Finder 2026-11-06, queue item 264, Finder's own, source a; from jobs/499_derivative_gap.sh): item 263's DNB gap at the real touch on liq_sample, local copy. A pilot on about 6 days: it cannot pass, it asks whether the gap can be taken. Rule pushed in the queue before these prices were read. Read only.
# Recorder: MO runners read HOME, DRAW, AWAY; DNB runners read team names in capitals. Exact duplicate rows dropped; a market with two rows for one label at one time is out, counted (item 202).
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))  # this job only
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,norm,jac,step,back_settle,lay_settle
from lib_official import secs
import lib_cand; lib_cand._checks()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30)
def name_map(ev,sels):
    """DNB runner names -> (home,away) by event name; None if unsure."""
    home,_x,away=str(ev).partition(' v '); s=list(sels)
    if len(s)!=2 or not away: return None
    H,A,a,b=norm(home),norm(away),norm(s[0]),norm(s[1]); s1,s2=jac(a,H)+jac(b,A),jac(a,A)+jac(b,H)
    if s1==s2: return None
    x,y=(s[0],s[1]) if s1>s2 else (s[1],s[0])
    return (x,y) if norm(x)&H and norm(y)&A else None
def fair_dnb(h,d,a):
    """(fair home, fair away) from MO mids; None outside book 0.98-1.08."""
    b=1/h+1/d+1/a
    if not 0.98<=b<=1.08: return None
    return (1/h)/(1/h+1/a),(1/a)/(1/h+1/a)
def winner(last):
    """{label: last ltp} -> the one runner at <=1.1, else None."""
    w=[k for k,v in last.items() if v is not None and v==v and v<=1.1]
    return w[0] if len(w)==1 else None
def half_pts(b,l): return (1/b-1/l)*100
# known answers, worked by hand: mids 2,4,4 give 2/3, 1/3. Back 1.6 is 0.625, gap +0.0417; lay 1.6 v fair 1/3 ... lay 2.8 is 0.357, gap +0.024. Back fill after one tick 1.6->1.59: win 5.9*0.98=5.782.
_f=fair_dnb(2.,4.,4.); assert abs(_f[0]-2/3)<1e-9 and abs(_f[1]-1/3)<1e-9 and fair_dnb(1.5,3.,4.) is None
assert abs(_f[0]-1/1.6-0.041667)<1e-5 and abs(1/2.8-_f[1]-0.02381)<1e-4
assert abs(back_settle(step(1.6,-1),True)-5.782)<1e-9 and abs(lay_settle(step(2.8,1),False)-10/1.82*0.98)<1e-9
assert winner({'HOME':1.02,'DRAW':90.,'AWAY':200.})=='HOME' and winner({'HOME':1.5,'DRAW':4.,'AWAY':6.}) is None and winner({'HOME':1.05,'DRAW':1.05}) is None
assert name_map('Leeds v Hull',['HULL','LEEDS'])==('LEEDS','HULL') and name_map('Leeds v Hull',['HULL']) is None
assert abs(half_pts(2.0,2.04)-(50-49.0196))<1e-3
assert secs(pd.Series(pd.to_datetime(['2026-01-01 00:00:00+00:00']))).iloc[0]==1767225600.0
print("checks: OK",flush=True); T0=time.time()
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
P=pd.read_sql("SELECT DISTINCT ts,event_name ev,mkt,sel,back_px::float8 b,lay_px::float8 l FROM liq_sample WHERE mkt IN ('MO','DNB') AND minute=0 AND back_px>=1.01 AND lay_px>back_px AND lay_px<1000",con)
F=pd.read_sql("SELECT event_name ev,min(ts) t1,max(ts) t2 FROM liq_sample WHERE mkt='MO' AND minute>=1 GROUP BY 1",con)
L=pd.read_sql("SELECT DISTINCT ON (event_name,sel) event_name ev,sel,ltp::float8 ltp,ts FROM liq_sample WHERE mkt='MO' AND ltp IS NOT NULL ORDER BY event_name,sel,ts DESC",con); con.close()
P['tt']=secs(P.ts); F['t1s']=secs(F.t1); F['t2s']=secs(F.t2); FIRST=dict(zip(F.ev,F.t1s))
LAST={e:dict(zip(g.sel,g.ltp)) for e,g in L.groupby('ev')}; print(f"prematch rows {len(P):,}, events {P.ev.nunique()}, with in-play {len(F)}, {time.time()-T0:.0f}s",flush=True)
SK=Counter(); rows=[]; spreads=[]; midgap=[]; touchgap=[]; games=0
for ev,g in P.groupby('ev',sort=False):
    t1=FIRST.get(ev)
    if t1 is None: SK['no in-play row']+=1; continue
    g=g[g.tt<=t1-120]
    mo=g[g.mkt=='MO']; dn=g[g.mkt=='DNB']
    if not len(mo) or not len(dn): SK['no MO or DNB row 120 s before']+=1; continue
    def last(x):
        if x.duplicated(['sel','tt']).any(): return 'dup'
        return x.sort_values('tt').groupby('sel').tail(1).set_index('sel')
    m=last(mo); d=last(dn)
    if isinstance(m,str) or isinstance(d,str): SK['two rows, one label, one time']+=1; continue
    if set(m.index)!={'HOME','DRAW','AWAY'}: SK['MO labels not HOME DRAW AWAY']+=1; continue
    nm=name_map(ev,list(d.index))
    if nm is None: SK['DNB names not mapped']+=1; continue
    ts=list(m.tt)+list(d.tt)
    if max(ts)-min(ts)>120: SK['rows over 120 s apart']+=1; continue
    mid={k:(m.b[k]+m.l[k])/2 for k in m.index}; f=fair_dnb(mid['HOME'],mid['DRAW'],mid['AWAY'])
    if f is None: SK['MO book outside']+=1; continue
    games+=1; hn,an=nm; o=float(t1)
    w=winner(LAST.get(ev,{}))
    for s,fp,lab in ((hn,f[0],'HOME'),(an,f[1],'AWAY')):
        spreads.append(half_pts(d.b[s],d.l[s])); midgap.append(abs(fp-2/(d.b[s]+d.l[s])))
    best={}
    for s,fp,lab in ((hn,f[0],'HOME'),(an,f[1],'AWAY')):
        gc=fp-1/d.b[s]; gd=1/d.l[s]-fp
        if 0.02<=gc<=0.10 and gc>best.get('CHEAP',(0,))[0]: best['CHEAP']=(gc,s,lab,d.b[s])
        if 0.02<=gd<=0.10 and gd>best.get('DEAR',(0,))[0]: best['DEAR']=(gd,s,lab,d.l[s])
    for k,(gp,s,lab,px) in best.items():
        if w is None: SK['unresolved, not scored']+=1; continue
        won=None if w=='DRAW' else (w==lab)
        if k=='CHEAP': v=0.0 if won is None else back_settle(step(px,-1),won)
        else: v=0.0 if won is None else lay_settle(step(px,1),won)
        rows.append((ev,o,k,gp,px,won,v))
print("counted:",dict(sorted(SK.items())),flush=True)
sp=np.array(spreads); mg=np.array(midgap)
print(f"games read {games}; DNB spread in points, median {np.median(sp):.2f}, p25 {np.percentile(sp,25):.2f}, p75 {np.percentile(sp,75):.2f}; runners with mid gap >= 0.02: {(mg>=0.02).sum()} of {len(mg)}")
R=pd.DataFrame(rows,columns='ev off k g px won v'.split())
print(f"games with a 2-point gap at the touch: {R.ev.nunique() if len(R) else 0} of {games}")
if len(R):
    md=np.median(R.off.values); out=[]
    for k,x in list(R.groupby('k'))+[('BOTH',R)]:
        l=line(x.v.values,np.where(x.off.values<md,1,2)); out.append(dict(line='264 '+k,n=l['n'],games=x.ev.nunique(),per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],voids=int(x.won.isna().sum()),won=x.won.dropna().astype(float).mean(),gap=x.g.mean()))
    print(pd.DataFrame(out).round(3).to_string(index=False))
print("\n== SURVIVORS: none possible, pilot on 6 days, bar needs n >= 300"); print(f"total {time.time()-T0:.0f}s")
PY
