#!/bin/bash
set -o pipefail
# 499_xx_unconfirmed (Finder 2026-11-08, queue item 436, Finder's own, source a, from item 339, jobs/499_xx_stale.sh): fade a Betfair in-play jump the other book does not confirm.
# Rule fixed in the queue before any price was read: football match odds, minute 5 to 85, each other book alone.
# Betfair mid (liq_sample) moved 5% or more between consecutive two-sided rows of one runner up to 120 s apart. Other book's mid: last row at or before each Betfair row, within 60 s.
# UNCONFIRMED: other moved under 0.5% over that span AND its next row (within 120 s) is still within 0.5%. CONFIRMED (control, cannot pass): other moved 2% or more the same way by its next row.
# Entry on Betfair at its first row at or after the other book's next row, so nothing is read before it is known. FADE: mid rose, back at back-1 tick; mid fell, lay at lay+1 tick. FOLLOW: the reverse.
# Exit at the first Betfair row at or after entry+300 s, one tick adverse, greened; no later row, settled at the last prints. Over 50 not traded. 2%, £10 risk.
# Replay guard: Betfair rows kept only if total_matched >= 0.999 of the market high so far. First signal per class per runner per game. Halves by date median, t by game. Reads local tables only.
# Run by hand: bash jobs/499_xx_unconfirmed.sh trade. With no argument (cron's runner) it runs the known-answer checks only.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_hedge,lay_hedge,back_settle,lay_settle,tstat,passes
from lib_official import secs
from lib_xx import pair,side_of,pick,median_gap,LABS
import lib_xx; lib_xx.checks()
pd.set_option('display.width',240); pd.set_option('display.max_columns',30)
def klass(bm0,bm1,om0,om1,om2):
    """Betfair mid bm0->bm1; other mid om0 at the start, om1 at Betfair's move row, om2 at the other book's next row."""
    mv=bm1/bm0-1
    if abs(mv)<0.05: return None
    if abs(om1/om0-1)<0.005 and abs(om2/om0-1)<0.005: return 'UNCONFIRMED'
    if (om2/om0-1)*np.sign(mv)>=0.02: return 'CONFIRMED'
    return None
def trade(kind,up,b,l,bx,lx):
    """kind FADE/FOLLOW, up: Betfair mid rose. Back at b-1 tick then lay out at lx+1, or lay at l+1 then back out at bx-1. None at the ladder floor."""
    back=(kind=='FADE')==up
    if back:
        a=step(b,-1); return None if a<=1.01 else back_hedge(a,lx)
    return lay_hedge(step(l,1),bx)
def settle_last(back,b,l,last,s):
    a=step(b,-1) if back else step(l,1)
    if back and a<=1.01: return None
    f=(lambda w: back_settle(a,w)) if back else (lambda w: lay_settle(a,w))
    w=[k for k,v in last.items() if v<=1.10]
    if len(w)==1: return f(w[0]==s)
    t=sum(1/v for v in last.values()); p=(1/last[s])/t
    return p*f(True)+(1-p)*f(False)
# known answers, worked by hand
assert klass(2.0,2.1,3.0,3.0,3.01)=='UNCONFIRMED' and klass(2.0,2.1,3.0,3.0,3.02) is None and klass(2.0,2.1,3.0,3.0,3.06)=='CONFIRMED'
assert klass(2.0,2.1,3.0,3.0,2.94) is None and klass(2.1,1.995,3.0,3.0,2.94)=='CONFIRMED' and klass(2.0,2.09,3.0,3.0,3.0) is None
# FADE a rise: back 2.10 touch at 2.08, lay out at 2.00 touch at 2.02: 10*(2.08/2.02-1)=0.29703, after 2% 0.29109
assert abs(trade('FADE',True,2.10,2.12,1.98,2.00)-10*(2.08/2.02-1)*.98)<1e-9
# FOLLOW a rise: lay 2.12 touch at 2.14, back out at 2.20 touch at 2.18: 10/1.14*(1-2.14/2.18)=0.16095, after 2% 0.15773
assert abs(trade('FOLLOW',True,2.10,2.12,2.20,2.22)-10/1.14*(1-2.14/2.18)*.98)<1e-9
# FADE a fall = lay; price keeps falling, back out lower: loss
assert trade('FADE',False,1.90,1.92,1.80,1.82)<0 and trade('FOLLOW',False,1.90,1.92,1.80,1.82)>0
assert settle_last(True,2.10,2.12,{'A':1.05,'B':30.},'A')==back_settle(2.08,True)
print("checks: OK",flush=True); T0=time.time()
MODE=sys.argv[1] if len(sys.argv)>1 else 'asserts-only'
if MODE!='trade': print("== SURVIVORS: not run, asserts only"); sys.exit(0)
L=psycopg2.connect(creds.pg_local()); L.autocommit=True; lc=L.cursor(); lc.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
B=pd.read_sql("SELECT DISTINCT ts,market_id,event_name,sel,minute,back_px::float8 b,lay_px::float8 l,ltp::float8 ltp,total_matched::float8 tm FROM liq_sample WHERE mkt='MO'",L)
B['tt']=secs(B.ts); B=B.sort_values(['market_id','tt']); C=Counter()
hi=B.groupby('market_id').tm.cummax(); keep=B.tm.isna()|(B.tm>=0.999*hi); C['betfair rows replay dropped']=int((~keep).sum()); B=B[keep]
print(f"Betfair rows {len(B):,}, markets {B.market_id.nunique():,}; {time.time()-T0:.0f}s",flush=True)
BM={m:g for m,g in B.groupby('market_id')}
LAST={m:g.dropna(subset=['ltp']).groupby('sel').ltp.last().to_dict() for m,g in BM.items()}
SPAN={m:(g.tt.min(),g.tt.max()) for m,g in BM.items()}
PAIRS=[(pair(ev),m) for m,ev in B[['market_id','event_name']].drop_duplicates().itertuples(index=False) if pair(ev)]
rows=[]
def run(X):
    X=X.copy(); X['tt']=secs(X.ts); X['st']=secs(X.start_ts)
    for (ex,xm,ev,st),gx in X.groupby(['exchange','market_id','event_name','st'],sort=False):
        C[ex+' markets']+=1
        got=pick(pair(ev),[(q,m) for q,m in PAIRS if SPAN[m][0]<=st+7200 and SPAN[m][1]>=st-1800])
        if got is None: C[ex+' no Betfair market']+=1; continue
        m,how=got; gb=BM[m]
        if set(gb.sel.unique())!=LABS or gb.duplicated(['sel','tt']).any(): C[ex+' Betfair labels or rows not as expected']+=1; continue
        gx=gx.assign(side=[side_of(s,ev) for s in gx.sel_name])
        if gx.side.isna().any() or set(gx.side.unique())!=LABS: C[ex+' runner names not matched']+=1; continue
        bad=False
        for s,bs in gb.groupby('sel'):
            o=gx[gx.side==s].sort_values('tt'); v=bs[bs.b.notna()&bs.l.notna()&(bs.minute>=5)&(bs.minute<=85)]
            mg=median_gap(o.tt.values,((o.back_px+o.lay_px)/2).values,v.tt.values,((v.b+v.l)/2).values)
            if mg is not None and mg>0.15: bad=True
        if bad: C[ex+' wrong pairing, gap over 15%']+=1; continue
        C[ex+' matched']+=1; last=LAST.get(m,{})
        for s,bs in gb.groupby('sel'):
            o=gx[(gx.side==s)&(gx.lay_px>gx.back_px)&(gx.back_px>=1.01)].sort_values('tt')
            v=bs[bs.b.notna()&bs.l.notna()&(bs.l>bs.b)&(bs.b>=1.01)]
            if len(o)<2 or len(v)<2: continue
            ot=o.tt.values; om=((o.back_px+o.lay_px)/2).values
            vt=v.tt.values; vb=v.b.values; vl=v.l.values; vm=(vb+vl)/2; vmin=v.minute.values
            inph=(vmin>=5)&(vmin<=85); done=set()
            for i in range(1,len(vt)):
                if len(done)==2: break
                if not (inph[i] and inph[i-1]) or vt[i]-vt[i-1]>120 or abs(vm[i]/vm[i-1]-1)<0.05: continue
                j0=int(np.searchsorted(ot,vt[i-1],side='right'))-1; j1=int(np.searchsorted(ot,vt[i],side='right'))-1
                if j0<0 or ot[j0]<vt[i-1]-60 or ot[j1]<vt[i]-60: C[ex+' move, no other mid in 60 s']+=1; continue
                f=j1+1
                if f>=len(ot) or ot[f]>vt[i]+120: C[ex+' move, no next other row in 120 s']+=1; continue
                k=klass(vm[i-1],vm[i],om[j0],om[j1],om[f])
                if k is None or k in done: continue
                done.add(k); up=vm[i]>vm[i-1]
                q=np.where(vt>=ot[f])[0]
                if not len(q): C[ex+' '+k+' no Betfair entry row']+=1; continue
                e=q[0]
                if vt[e]>ot[f]+120: C[ex+' '+k+' Betfair entry row over 120 s late']+=1; continue
                if max(vb[e],vl[e])>50: C[ex+' '+k+' over 50']+=1; continue
                x=np.where(vt>=vt[e]+300)[0]
                for kind in ('FADE','FOLLOW'):
                    back=(kind=='FADE')==up
                    if len(x): val=trade(kind,up,vb[e],vl[e],vb[x[0]],vl[x[0]]); settled=0
                    else: val=settle_last(back,vb[e],vl[e],last,s) if s in last and len(last)==3 else None; settled=1
                    if val is None: C[ex+' '+k+' '+kind+' no fill']+=1; continue
                    rows.append((ex,k,kind,'BACK' if back else 'LAY',m,s,vt[e],val,abs(vm[i]/vm[i-1]-1),vm[e],settled,vmin[e],(vm[x[0]]/vm[e]-1)*(1 if up else -1) if len(x) else np.nan))
for bk in ('matchbook','smarkets'):
    X=pd.read_sql("SELECT ts,exchange,event_name,market_id,start_ts,sel_name,back_px,lay_px FROM xx_ip_331 WHERE exchange=%s AND back_px IS NOT NULL AND lay_px IS NOT NULL",L,params=(bk,))
    print("in-play other rows",bk,len(X),f"{time.time()-T0:.0f}s",flush=True); run(X); del X
L.close()
print("counts",dict(sorted(C.items())),flush=True)
T=pd.DataFrame(rows,columns=['ex','k','kind','side','m','s','tt','v','bmove','mid','settled','minute','cont'])
if not len(T): print("no trades"); print("== SURVIVORS: none"); sys.exit(0)
out=[]
def rd(name,d,can=True):
    if not len(d): return
    med=d.tt.median(); h=np.where(d.tt<=med,1,2)
    n=len(d); a=d.v[h==1]; b=d.v[h==2]; mean=d.v.mean(); t=tstat(d.v); tg=tstat(d.groupby('m').v.sum())
    ok=can and passes(n,len(a),len(b),t,a.mean() if len(a) else -1,b.mean() if len(b) else -1,mean) and tg>=3.5
    out.append(dict(line=name,n=n,per10=round(mean,3),t=round(t,2),t_game=round(tg,2),h1=round(a.mean(),3) if len(a) else None,n1=len(a),h2=round(b.mean(),3) if len(b) else None,n2=len(b),
        games=d.m.nunique(),win=round((d.v>0).mean(),3),cont_pct=round(100*d.cont.mean(),2),settled=int(d.settled.sum()),PASS='PASS' if ok else ''))
for ex,E in T.groupby('ex'):
    for k in ('UNCONFIRMED','CONFIRMED'):
        for kind in ('FADE','FOLLOW'):
            K=E[(E.k==k)&(E.kind==kind)]; can=k=='UNCONFIRMED'; tag=f"{ex} {k} {kind}"
            rd(tag+" ALL",K,can); rd(tag+" BACK",K[K.side=='BACK'],can); rd(tag+" LAY",K[K.side=='LAY'],can)
    for kind in ('FADE','FOLLOW'):
        K=E[(E.k=='UNCONFIRMED')&(E.kind==kind)]
        for lo,hi_ in ((1,2),(2,4),(4,10),(10,50)): rd(f"{ex} ctx UNC {kind} mid {lo}-{hi_}",K[(K.mid>=lo)&(K.mid<hi_)],False)
        rd(f"{ex} ctx UNC {kind} move 10%+",K[K.bmove>=0.10],False)
# both books unmoved: the same Betfair move seen unconfirmed by each book alone
U=T[(T.k=='UNCONFIRMED')]; both=U.groupby(['m','s','kind']).ex.nunique(); bk=set(both[both==2].index)
for kind in ('FADE','FOLLOW'):
    D=U[(U.ex=='matchbook')&(U.kind==kind)]; D=D[[(a,b,kind) in bk for a,b in zip(D.m,D.s)]]; rd(f"ctx BOTH books unmoved {kind}, Matchbook entry",D,False)
R=pd.DataFrame(out).sort_values('t',ascending=False); print(R.to_string(index=False),flush=True)
print("cont_pct: Betfair mid over the hold, signed in the direction of the jump (positive = it kept going)")
print(f"run {time.time()-T0:.0f}s")
print("== SURVIVORS:",[r for r in R[R.PASS=='PASS'].line] or 'none')
PY
