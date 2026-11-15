#!/bin/bash
set -o pipefail
# 499_xx_stale (Finder 2026-11-08, queue item 339, Finder's own, source a, from jobs/499_xx_lead.sh and jobs/499_xx_arb_ip.sh): Betfair moves, the thin book has not: take the stale price.
# Rule fixed in the queue before any price was read: football match odds, each book alone, T-30 to T-2 and minute 5 to 85 as separate lines.
# SIGNAL: Betfair mid (liq_sample) moved 5% or more between consecutive two-sided rows of one runner up to 120 s apart, and the other book's mid
#   (its last row at or before each Betfair row, within 60 s, no look-ahead) moved under 0.5% over the same span. CONTROL: other book moved 2% or more, cannot pass.
# Trade: at the other book's NEXT row after the signal (within 120 s, else no trade, counted), take its touch toward Betfair's new mid, one tick adverse:
#   Betfair mid up, lay there at lay+1 tick (liability £10); Betfair mid down, back there at back-1 tick (stake £10).
#   Hedge on Betfair at its first row at or after that fill (within 120 s, else no trade, counted), one tick adverse, greened; worse outcome per £10, 2% on each book's win.
# Size: at least £10 on the other leg where the tape has sizes (pre-off copy xx_pre_329); the in-play copy xx_ip_331 has none, so in play is read without it and says so.
# Ticks on both books from the Betfair ladder (Smarkets and Matchbook ladders not modelled). Replay guard: Betfair rows kept only if total_matched >= 0.999 of the market high so far.
# First signal per class per runner per game per phase. Halves by date median per line; one number per game too. Reads local tables only; writes nothing.
# Run by hand: bash jobs/499_xx_stale.sh trade. With no argument (cron's runner) it runs the known-answer checks only.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,tstat,passes
from lib_official import secs
from lib_xx import pair,side_of,pick,median_gap,LABS
import lib_xx; lib_xx.checks()
pd.set_option('display.width',240); pd.set_option('display.max_columns',30)
def green_back_other(a,lb,c=0.02):
    """Backed £10 at a on the other book, laid 10*a/lb at lb on Betfair. Worse of the two outcomes, c on each book's win."""
    s=10*a/lb
    return min(10*(a-1)*(1-c)-s*(lb-1), -10+s*(1-c))
def green_lay_other(l,bb,c=0.02):
    """Laid at l on the other book for £10 liability (stake 10/(l-1)), backed s=stake*l/bb at bb on Betfair. Worse outcome."""
    k=10/(l-1); s=k*l/bb
    return min(-10+s*(bb-1)*(1-c), k*(1-c)-s)
def klass(bm0,bm1,om0,om1):
    """Betfair mid bm0->bm1, other mid om0->om1. Returns class or None."""
    if abs(bm1/bm0-1)<0.05: return None
    mo=abs(om1/om0-1)
    if mo<0.005: return 'STALE'
    if mo>=0.02: return 'CONTROL'
    return None
# known answers, worked by hand
# Back other 2.2 £10, lay Betfair 2.0 stake 11. Wins: 12*.98=11.76-11=0.76. Loses: -10+11*.98=0.78. Worse 0.76.
assert abs(green_back_other(2.2,2.0)-0.76)<1e-9
# Lay other 1.8 liability 10, stake 12.5; back Betfair 2.0 stake 11.25. Wins: -10+11.25*.98=1.025. Loses: 12.25-11.25=1.0. Worse 1.0.
assert abs(green_lay_other(1.8,2.0)-1.0)<1e-9
# No move: back 2.0 lay 2.0 loses commission, wins 10*.98-10=-0.2, loses -10+9.8=-0.2
assert abs(green_back_other(2.0,2.0)+0.2)<1e-9 and green_lay_other(2.0,2.0)<0
assert klass(2.0,2.1,3.0,3.01)=='STALE' and klass(2.0,2.1,3.0,3.1)=='CONTROL' and klass(2.0,2.09,3.0,3.0) is None and klass(2.0,2.1,3.0,3.03) is None
assert klass(2.1,2.0,3.0,3.0) is None and klass(2.1,1.995,3.0,3.0)=='STALE'   # 2.0/2.1-1 = -4.76%, under 5%; 1.995/2.1-1 = -5.0%
assert step(2.0,1)==2.02 and step(2.0,-1)==1.99
print("checks: OK",flush=True); T0=time.time()
MODE=sys.argv[1] if len(sys.argv)>1 else 'asserts-only'
if MODE!='trade': print("== SURVIVORS: not run, asserts only"); sys.exit(0)
L=psycopg2.connect(creds.pg_local()); L.autocommit=True; lc=L.cursor(); lc.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
B=pd.read_sql("SELECT DISTINCT ts,market_id,event_name,sel,minute,back_px::float8 b,lay_px::float8 l,total_matched::float8 tm FROM liq_sample WHERE mkt='MO'",L)
B['tt']=secs(B.ts); B=B.sort_values(['market_id','tt']); C=Counter()
hi=B.groupby('market_id').tm.cummax(); keep=B.tm.isna()|(B.tm>=0.999*hi); C['betfair rows replay dropped']=int((~keep).sum()); B=B[keep]
print(f"Betfair rows {len(B):,}, markets {B.market_id.nunique():,}, {B.ts.min()} to {B.ts.max()}; {time.time()-T0:.0f}s",flush=True)
BM={m:g for m,g in B.groupby('market_id')}
SPAN={m:(g.tt.min(),g.tt.max()) for m,g in BM.items()}
PAIRS=[(pair(ev),m) for m,ev in B[['market_id','event_name']].drop_duplicates().itertuples(index=False) if pair(ev)]
def games(X,ph):
    X=X.copy(); X['tt']=secs(X.ts); X['st']=secs(X.start_ts)
    mok=(lambda s:s==0) if ph=='PRE' else (lambda s:(s>=5)&(s<=85))
    for (ex,xm,ev,st),gx in X.groupby(['exchange','market_id','event_name','st'],sort=False):
        C[f'{ex} {ph} markets']+=1
        got=pick(pair(ev),[(q,m) for q,m in PAIRS if SPAN[m][0]<=st+7200 and SPAN[m][1]>=st-1800])
        if got is None: C[f'{ex} {ph} no Betfair market']+=1; continue
        m,how=got; gb=BM[m]
        if set(gb.sel.unique())!=LABS: C[f'{ex} {ph} Betfair labels not as expected']+=1; continue
        if gb.duplicated(['sel','tt']).any(): C[f'{ex} {ph} two rows one label one time']+=1; continue
        gx=gx.assign(side=[side_of(s,ev) for s in gx.sel_name])
        if gx.side.isna().any() or set(gx.side.unique())!=LABS: C[f'{ex} {ph} runner names not matched']+=1; continue
        bad=False
        for s,bs in gb.groupby('sel'):
            o=gx[(gx.side==s)].sort_values('tt'); v=bs[bs.b.notna()&bs.l.notna()&mok(bs.minute)]
            mg=median_gap(o.tt.values,((o.back_px+o.lay_px)/2).values,v.tt.values,((v.b+v.l)/2).values)
            if mg is not None and mg>0.15: bad=True
        if bad: C[f'{ex} {ph} wrong pairing, gap over 15%']+=1; continue
        C[f'{ex} {ph} matched']+=1
        yield ex,m,how,ev,st,gx,gb
rows=[]
def run(X,ph,sized):
    for ex,m,how,ev,st,gx,gb in games(X,ph):
        for s,bs in gb.groupby('sel'):
            o=gx[(gx.side==s)&(gx.lay_px>gx.back_px)&(gx.back_px>=1.01)].sort_values('tt')
            v=bs[bs.b.notna()&bs.l.notna()&(bs.l>bs.b)&(bs.b>=1.01)]
            if len(o)<2 or len(v)<2: continue
            ot=o.tt.values; ob=o.back_px.values; ol=o.lay_px.values; om=(ob+ol)/2
            obs=o.back_sz.values if sized else None; ols=o.lay_sz.values if sized else None
            vt=v.tt.values; vb=v.b.values; vl=v.l.values; vm=(vb+vl)/2; vmin=v.minute.values
            inph=((vt>=st-1800)&(vt<=st-120)&(vmin==0)) if ph=='PRE' else ((vmin>=5)&(vmin<=85))
            done=set()
            for i in range(1,len(vt)):
                if len(done)==2: break
                if not (inph[i] and inph[i-1]) or vt[i]-vt[i-1]>120: continue
                if abs(vm[i]/vm[i-1]-1)<0.05: continue
                j0=int(np.searchsorted(ot,vt[i-1],side='right'))-1; j1=int(np.searchsorted(ot,vt[i],side='right'))-1
                if j0<0 or ot[j0]<vt[i-1]-60 or ot[j1]<vt[i]-60: C[f'{ex} {ph} move, no other mid in 60 s']+=1; continue
                k=klass(vm[i-1],vm[i],om[j0],om[j1])
                if k is None or k in done: continue
                done.add(k); up=vm[i]>vm[i-1]; t=vt[i]
                f=j1+1
                if f>=len(ot) or ot[f]>t+120: C[f'{ex} {ph} {k} no next other row in 120 s']+=1; continue
                if up:
                    a=step(ol[f],1); szok=(not sized) or (ols[f]>=10)
                else:
                    a=step(ob[f],-1); szok=(not sized) or (obs[f]>=10)
                if a>50 or a<=1.01: C[f'{ex} {ph} {k} price out of range']+=1; continue
                if not szok: C[f'{ex} {ph} {k} under £10 at the touch']+=1; continue
                q=np.where(vt>=ot[f])[0]
                if not len(q) or vt[q[0]]>ot[f]+120: C[f'{ex} {ph} {k} no Betfair hedge row in 120 s']+=1; continue
                e=q[0]
                if up: h=step(vb[e],-1); val=green_lay_other(a,h) if h>1.01 else None
                else: h=step(vl[e],1); val=green_back_other(a,h)
                if val is None: C[f'{ex} {ph} {k} hedge at ladder floor']+=1; continue
                stale_at_fill=abs(om[f]/om[j1]-1)<0.005
                rows.append((ex,ph,k,'LAY' if up else 'BACK',m,ev,s,t,val,abs(vm[i]/vm[i-1]-1),vm[i],stale_at_fill,a,h,ot[f]-t,vt[e]-ot[f],vmin[i]))
Xp=pd.read_sql("SELECT DISTINCT ts,exchange,event_name,market_id,start_ts,sel_name,back_px,back_sz,lay_px,lay_sz FROM xx_pre_329 WHERE back_px IS NOT NULL AND lay_px IS NOT NULL",L)
print("pre-off other rows",len(Xp),dict(Xp.exchange.value_counts()),flush=True); run(Xp,'PRE',True); del Xp
for bk in ('matchbook','smarkets'):
    X=pd.read_sql("SELECT ts,exchange,event_name,market_id,start_ts,sel_name,back_px,lay_px FROM xx_ip_331 WHERE exchange=%s AND back_px IS NOT NULL AND lay_px IS NOT NULL",L,params=(bk,))
    print("in-play other rows",bk,len(X),"markets",X.market_id.nunique(),f"{time.time()-T0:.0f}s",flush=True); run(X,'IP',False); del X
L.close()
print("counts",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows,columns=['ex','ph','k','side','m','ev','s','tt','v','bmove','mid','stale_fill','a','h','fill_lag','hedge_lag','minute'])
if not len(T): print("no trades"); print("== SURVIVORS: none"); sys.exit(0)
out=[]
def rd(name,d,can=True):
    if not len(d): return
    med=d.tt.median(); h=np.where(d.tt<=med,1,2)
    n=len(d); a=d.v[h==1]; b=d.v[h==2]; mean=d.v.mean(); t=tstat(d.v); tg=tstat(d.groupby('m').v.sum())
    ok=can and passes(n,len(a),len(b),t,a.mean() if len(a) else -1,b.mean() if len(b) else -1,mean) and tg>=3.5
    out.append(dict(line=name,n=n,per10=round(mean,3),t=round(t,2),t_game=round(tg,2),h1=round(a.mean(),3) if len(a) else None,n1=len(a),h2=round(b.mean(),3) if len(b) else None,n2=len(b),
        games=d.m.nunique(),win=round((d.v>0).mean(),3),stale_fill=round(d.stale_fill.mean(),3),fill_lag=round(d.fill_lag.median(),0),PASS='PASS' if ok else ''))
for (ex,ph),E in T.groupby(['ex','ph']):
    for k in ('STALE','CONTROL'):
        K=E[E.k==k]; can=k=='STALE'; tag=f"{ex} {ph} {k}"
        rd(tag+" ALL",K,can); rd(tag+" BACK other",K[K.side=='BACK'],can); rd(tag+" LAY other",K[K.side=='LAY'],can)
    K=E[E.k=='STALE']
    for lo,hi_ in ((1,2),(2,4),(4,10),(10,50)): rd(f"{ex} {ph} ctx STALE mid {lo}-{hi_}",K[(K.mid>=lo)&(K.mid<hi_)],False)
    rd(f"{ex} {ph} ctx STALE move 5-10%",K[K.bmove<0.10],False); rd(f"{ex} {ph} ctx STALE move 10%+",K[K.bmove>=0.10],False)
    rd(f"{ex} {ph} ctx STALE still stale at fill",K[K.stale_fill],False); rd(f"{ex} {ph} ctx STALE other moved by fill",K[~K.stale_fill],False)
R=pd.DataFrame(out).sort_values('t',ascending=False); print(R.to_string(index=False),flush=True)
print("trades per game: median",T.groupby(['ex','ph','k','m']).size().median(),"max",T.groupby(['ex','ph','k','m']).size().max())
print("halves split at the median entry time of each line; stale_fill: other book's mid at the fill row still within 0.5% of the stale mid")
print(f"run {time.time()-T0:.0f}s")
print("== SURVIVORS:",[r for r in R[R.PASS=='PASS'].line] or 'none')
PY
