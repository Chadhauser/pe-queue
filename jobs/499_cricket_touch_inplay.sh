#!/bin/bash
set -o pipefail
# 499_cricket_touch_inplay (Finder 2026-11-07, queue items 397 and 177, Finder's own; from jobs/499_cricket_own_error.sh and jobs/499_cricket_shock.sh; table cricket_fav_tape, 30 s rows with the real back and lay since 24 Oct 2026). Rules pushed in the queue before any price. Read only, no tables written. 14 days, so n is far under the bar: it reads the real cost.
# ITEM 397 pre-off outsider (first in-play ltp over 2.0) first touching 1.5: lay the NEXT row's lay_px, at most 120 s later, one tick adverse, 2%, GBP 10 liability, lays under 1.10 not traded, held to the result.
# ITEM 177 X20 shock as job 499_cricket_shock: first per market, ltp >= 1.2 x own ltp at most 180 s earlier, earlier ltp <= 5, then only earlier < 1.5 is read. Entry next row at most 120 s later: FADE backs at back_px, FOLLOW lays at lay_px, one tick adverse. Exit first row at +10 min at the opposite touch, one tick adverse; no such row: the result.
# FIX 2026-11-07, the one fix: replay rows dropped. This REST tape replays old book states, total_matched falling under the market's earlier high, 17% of in-play rows; job 497 found the same on ip_tape. A row is kept only if total_matched is at or above 0.999 of the market's high so far. The first run did not do this; its numbers are in the report.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
import lib_cand
from lib_cand import line,step,back_hedge,lay_hedge,LD
from lib_official import bk,ly,secs,checks
lib_cand._checks(); checks()
def ticks(a,b): return int(np.searchsorted(LD,round(float(b),2)-1e-9))-int(np.searchsorted(LD,round(float(a),2)-1e-9))
def infer(last,lo_=1.10,hi_=5.0):
    lo=[k for k,v in last.items() if v<=lo_]
    if len(lo)!=1 or len(last)!=2: return None
    return lo[0] if all(v>=hi_ for k,v in last.items() if k!=lo[0]) else None
def q_last(a,b): x,y=1/a,1/b; return x/(x+y)
def ev(f,p,q): return q*f(p,True)+(1-q)*f(p,False)
def touch(px,T):
    if not len(px) or px[0]<=T: return None
    w=np.nonzero(np.asarray(px)<=T)[0]
    return int(w[0]) if len(w) else None
def first_shock(ts,p,X,win=180.0,cap=5.0):
    for i in range(1,len(p)):
        j=i-1
        while j>=0 and ts[i]-ts[j]<=win:
            if p[j]<=cap and p[i]>=(1+X)*p[j]-1e-9: return i,j
            j-=1
    return None
# known answers, worked by hand
assert ticks(1.4,1.42)==2 and ticks(1.5,1.52)==2 and ticks(2.0,2.02)==1 and touch([2.0,1.6,1.5,1.4],1.5)==2 and touch([1.5,1.2],1.5) is None and touch([2.0,1.6],1.5) is None
assert first_shock(np.array([0.,30.,60.]),[1.2,1.2,1.5],0.2)==(2,1) and first_shock(np.array([0.,200.]),[1.2,1.5],0.2) is None and first_shock(np.array([0.,30.]),[6.0,9.0],0.2) is None
assert abs(ly(1.4,False)-10/.41*.98)<1e-9 and ly(1.4,True)==-10.0 and abs(ev(ly,1.4,.5)-(0.5*-10+0.5*10/.41*.98))<1e-9   # 1.4 one tick adverse is 1.41
assert abs(back_hedge(1.5,1.4)-10*(1.5/1.41-1)*.98)<1e-9 and abs(lay_hedge(1.5,1.4)-(10/.5*(1-1.5/1.39)))<1e-9
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require'); rc.autocommit=True; rc.cursor().execute("SET statement_timeout='300s'")
A=pd.read_sql("WITH t AS (SELECT *,total_matched::float8 tm0,max(total_matched::float8) OVER (PARTITION BY market_id ORDER BY ts ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) hi FROM cricket_fav_tape), c AS (SELECT * FROM t WHERE hi IS NULL OR tm0 IS NULL OR tm0>=hi*0.999) SELECT ts,market_id,event_name ev,start_time mt,sel_name sel,ltp::float8 ltp,back_px::float8 bp,lay_px::float8 lp FROM c WHERE inplay ORDER BY market_id,sel_name,ts",rc); rc.close()
A['tt']=secs(A.ts); A['off']=secs(A.mt); TE=float(A.tt.max()); print(f"in-play rows {len(A):,}, markets {A.market_id.nunique()}, {time.time()-T0:.0f}s",flush=True)
C=Counter(); rows=[]; sh=[]; seen=set()
for m,g in A.groupby('market_id',sort=True):
    ev_=g.ev.iloc[0]; o=float(g.off.iloc[0])
    if (ev_,o) in seen: C['second id']+=1; continue
    seen.add((ev_,o)); run={s:y for s,y in g.groupby('sel',sort=False)}
    if len(run)!=2: C['not two runners']+=1; continue
    last={s:float(y.ltp.values[-1]) for s,y in run.items()}; win=infer(last); end=max(float(y.tt.values[-1]) for y in run.values())
    if win is None and end>TE-43200: C['unresolved and under 12 h old, left out']+=1; continue
    C['resolved' if win else 'unresolved, last-print odds']+=1
    a,b=list(run)
    for s,y in run.items():
        o_=[k for k in run if k!=s][0]; q=q_last(last[s],last[o_]); ts,px,bp,lp=y.tt.values,y.ltp.values,y.bp.values,y.lp.values
        # item 397
        if px[0]>2.0:
            i=touch(px,1.5)
            if i is not None:
                if i+1>=len(px) or ts[i+1]-ts[i]>120: C['397 no next row']+=1
                elif lp[i+1]!=lp[i+1]: C['397 no lay on the book']+=1
                elif step(float(lp[i+1]),1)<1.10: C['397 lay fills under 1.10']+=1
                else:
                    L=float(lp[i+1]); P=float(px[i+1])
                    if P<1.09: P=1.09
                    v=ly(L,win==s) if win else ev(ly,L,q); vp=ly(P,win==s) if win else ev(ly,P,q)
                    rows.append((m,ev_,o,s,L,float(bp[i+1]) if bp[i+1]==bp[i+1] else np.nan,P,win==s if win else np.nan,v,vp,ev(ly,P,1/P)-ev(ly,L,1/P)))
    # item 177: first shock per market across both runners, as job 499_cricket_shock
    zs=[]
    for s,y in run.items():
        z=first_shock(y.tt.values,y.ltp.values,0.20)
        if z is not None: zs.append((float(y.tt.values[z[0]]),s,z))
    if zs:
        _,s,(i,j)=min(zs,key=lambda u:u[0]); y=run[s]; o_=[k for k in run if k!=s][0]; q=q_last(last[s],last[o_]); ts,px,bp,lp=y.tt.values,y.ltp.values,y.bp.values,y.lp.values
        band='<1.5' if px[j]<1.5 else '1.5-2.5' if px[j]<2.5 else '2.5-5'; k=i+1
        if k>=len(px) or ts[k]-ts[i]>120: C['177 no next row']+=1; continue
        if lp[k]!=lp[k] or bp[k]!=bp[k]: C['177 no two-sided book']+=1; continue
        e=int(np.searchsorted(ts,ts[k]+600,side='left'))
        ex=e<len(ts) and bp[e]==bp[e] and lp[e]==lp[e]
        ab=step(float(bp[k]),-1); al=step(float(lp[k]),1)
        if ab<=1.01 or al<1.10: C['177 ladder end']+=1; continue
        if ex: fa=back_hedge(ab,float(lp[e])); fo=lay_hedge(al,float(bp[e])); C['177 exit at the touch']+=1
        else: fa=bk(float(bp[k]),win==s) if win else ev(bk,float(bp[k]),q); fo=ly(float(lp[k]),win==s) if win else ev(ly,float(lp[k]),q); C['177 settled']+=1
        sh.append((m,o,s,band,float(px[j]),float(px[k]),float(bp[k]),float(lp[k]),fa,fo,ticks(bp[k],lp[k]),ex))
print("counted:",dict(sorted(C.items())),flush=True)
R=pd.DataFrame(rows,columns='m ev off s L B P won v vp mc'.split())
print("\n== ITEM 397, games",R.m.nunique() if len(R) else 0)
if len(R):
    R['sp']=[ticks(b,l) if b==b else np.nan for b,l in zip(R.B,R.L)]
    print(f"spread at entry, ticks: median {R.sp.median()}, share <=1 {float((R.sp<=1).mean()):.3f}, <=2 {float((R.sp<=2).mean()):.3f}, <=5 {float((R.sp<=5).mean()):.3f}; lay above the print, ticks, median {np.median([ticks(p,l) for p,l in zip(R.P,R.L)])}; model cost per GBP 10, EV at the print's implied, mean {R.mc.mean():.3f} median {R.mc.median():.3f}; lean to beat: official +1.283, +0.144 without the 10 largest wins")
    md=float(np.median(R.off)); out=[]
    for nm,c in (('LAY at the real touch','v'),('Same at the print, control','vp')):
        l=line(R[c].values,np.where(R.off<md,1,2)); out.append(dict(line=nm,n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],maxwin=l['maxwin'],won=R.won.astype(float).mean(),imp=(1/R.L).mean(),PASS=l['PASS']))
    k=int(np.argmax(R.v.values)); l=line(np.delete(R.v.values,k),np.delete(np.where(R.off<md,1,2),k)); out.append(dict(line='touch, without the largest win',n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],PASS=False))
    print(pd.DataFrame(out).round(3).to_string(index=False))
    print("by lay price:",R.groupby(pd.cut(R.L,[1,1.3,1.5,1.7,100])).agg(n=('v','size'),touch=('v','mean'),print_=('vp','mean'),cost=('mc','mean')).round(3).to_dict('index'))
S=pd.DataFrame(sh,columns='m off s band ep kp B L fa fo sp ex'.split())
print("\n== ITEM 177, X20, all bands by earlier print")
if len(S):
    print("median spread in ticks at entry by band",S.groupby('band').sp.median().to_dict(),"share exit at the touch",round(float(S.ex.mean()),3),"; rule: a touch wider than the two ticks charged closes it")
    md=float(np.median(S.off)); out=[]
    for b_,x in S.groupby('band'):
        for nm,c in (('FADE','fa'),('FOLLOW','fo')):
            l=line(x[c].values,np.where(x.off<md,1,2)); out.append(dict(line=f'{b_} {nm}',n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],spread=x.sp.median(),PASS=bool(l['PASS'] and b_=='<1.5')))
    print(pd.DataFrame(out).round(3).to_string(index=False))
print("\n== SURVIVORS: none can pass at this n"); print(f"total {time.time()-T0:.0f}s")
PY
