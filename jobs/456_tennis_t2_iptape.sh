#!/bin/bash
set -o pipefail
# 456 (Finder 2026-11-03, queue item 7): TENNIS T2 ON ip_tape. MATCH_ODDS, two-runner markets only.
# Pre-match price = back_px at the LAST sample before the off (secs_since_start<=0); markets with no pre-off sample use the first
# sample within 10 min of the off (= what t2_nightly calls p0) and are reported as a separate source. Favourite = lower pre price, band 1.30-2.00.
# ENTRY: first OPEN in-play sample where the favourite's back_px (the real touch) > threshold (2.0 = item rule; also 1.6 x p0 = t2 rule),
# filled at back_px minus one tick. A real print = OPEN, back_px not null, back_sz > 0. No forward-fill.
# EXITS: settle at the inferred result; or hedge +20 min at the first OPEN sample at/after entry+20m (any later time) at lay_px plus one tick,
# no such sample -> settled at result. RESULT: winner = runner whose back_px or ltp <= 1.05 on an OPEN sample in the last 15 min of the
# market's tape (and the other runner >= 8). Markets with no inferable result are NOT dropped silently: counted, and the line is reported
# twice - "known" (result inferable) and "worst" (unknown = full loss at settle). 2% commission on profits, £10 back stake.
# Halves = entry ts before/after the median. One entry per market by construction.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
def tick(p): return 0.01 if p<2 else 0.02 if p<3 else 0.05 if p<4 else 0.1 if p<6 else 0.2 if p<10 else 0.5 if p<20 else 1 if p<30 else 2 if p<50 else 5 if p<100 else 10
def pnl(p,q,won):
    p=p-tick(p)
    if p<=1.01: return None
    if q is None: r=10*(p-1) if won else -10.0
    else: q=q+tick(q); r=10*(p/q-1)
    return r*0.98 if r>0 else r
assert abs(pnl(2.2,None,True)-10*1.18*0.98)<1e-9 and pnl(2.2,None,False)==-10.0
assert abs(pnl(2.5,2.0,False)-10*(2.48/2.02-1)*0.98)<1e-9 and abs(pnl(2.1,3.0,True)-10*(2.08/3.05-1))<1e-9
print("P&L unit checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET statement_timeout='2400s'")
T=pd.read_sql("""SELECT market_id, event_name, competition, ts, secs_since_start s, status, sel_id, back_px::float bp, back_sz::float bs,
 lay_px::float lp, ltp::float ltp FROM ip_tape WHERE sport='tennis' AND market_type='MATCH_ODDS' ORDER BY market_id, ts""",con)
print(f"rows {len(T)} | markets {T.market_id.nunique()} | events {T.event_name.nunique()} | ts {T.ts.min()} .. {T.ts.max()}",flush=True)
gap=T.groupby(['market_id','sel_id']).ts.diff().dt.total_seconds()
print(f"sample gap per runner (s): median {gap.median():.0f}, p90 {gap.quantile(.9):.0f}",flush=True)
SK=defaultdict(int); rows=[]
for mid,g in T.groupby('market_id',sort=False):
    sels=g.sel_id.unique()
    if len(sels)!=2: SK['not 2 runners']+=1; continue
    ok=g[(g.status=='OPEN')&g.bp.notna()&(g.bs>0)]
    pre=ok[ok.s<=0]; src='pre-off'
    if pre.groupby('sel_id').size().size<2: pre=ok[(ok.s>0)&(ok.s<=600)]; src='first10m'
    if pre.groupby('sel_id').size().size<2: SK['no pre/early price both runners']+=1; continue
    last=pre.sort_values('ts').groupby('sel_id').tail(1).set_index('sel_id').bp
    fav=last.idxmin(); p0=last[fav]
    if not (1.30<=p0<=2.00): SK['fav outside 1.30-2.00']+=1; continue
    tend=g.ts.max(); tail=g[(g.status=='OPEN')&(g.ts>=tend-pd.Timedelta(minutes=15))]
    lo=pd.concat([tail.bp,tail.ltp],axis=1).min(axis=1); tail=tail.assign(lo=lo)
    winner=None
    for s in sels:
        o=[x for x in sels if x!=s][0]
        if (tail[tail.sel_id==s].lo<=1.05).any() and (tail[tail.sel_id==o].bp>=8).any(): winner=s
    f=ok[(ok.sel_id==fav)&(ok.s>0)&(ok.s>(0 if src=='pre-off' else pre.s.max()))].sort_values('ts')
    for rule,thr in (('>2.0',2.0),('>=1.6xp0',1.6*p0)):
        e=f[(f.bp>thr)&(f.bp<=15)] if rule=='>2.0' else f[(f.bp>=thr)&(f.bp<=15)]
        if e.empty: SK[rule+': never drifted']+=1; continue
        r0=e.iloc[0]
        x=g[(g.sel_id==fav)&(g.status=='OPEN')&g.lp.notna()&(g.ts>=r0.ts+pd.Timedelta(minutes=20))]
        q=None if x.empty else x.iloc[0].lp
        for res in ('known','worst'):
            if winner is None and res=='known': SK[rule+': result not inferable']+=1; continue
            won=(winner==fav)
            for ex,qq in (('settle',None),('hedge+20',q)):
                if ex=='hedge+20' and qq is None and winner is None: r=-10.0 if res=='worst' else None
                else: r=pnl(r0.bp,qq,won)
                if r is None: SK['unfillable']+=1; continue
                rows.append(dict(rule=rule,res=res,exit=ex,mid=mid,event=g.event_name.iloc[0],comp=g.competition.iloc[0],src=src,ts=r0.ts,p0=p0,
                     entry=r0.bp,mins=int(r0.s//60),won=won,pnl=r,hedge_print=qq is not None))
R=pd.DataFrame(rows); print("skips/counts (not hidden):",dict(SK),flush=True)
if R.empty: print("\n== SURVIVORS: 0\nnone (no entries)"); sys.exit()
med=R.ts.median(); R['half']=np.where(R.ts<med,'H1','H2'); print("half split at",med)
R['pband']=pd.cut(R.p0,[1.29,1.5,1.7,2.0]).astype(str); R['ebandd']=pd.cut(R.entry,[2,2.5,3.5,6,15]).astype(str)
R['tour']=np.where(R.comp.str.contains('ITF|W15|W35|W50|W75|M15|M25',case=False,na=False),'ITF',np.where(R.comp.str.contains('Challenger',case=False,na=False),'Challenger','ATP/WTA/other'))
def tstat(x): return x.mean()/(x.std(ddof=1)/len(x)**0.5) if len(x)>1 and x.std(ddof=1)>0 else 0.0
out=[]
for dims in (['rule','res','exit'],['rule','res','exit','src'],['rule','res','exit','pband'],['rule','res','exit','ebandd'],['rule','res','exit','tour']):
    for k,gg in R.groupby(dims):
        a=gg[gg.half=='H1'].pnl; b=gg[gg.half=='H2'].pnl
        out.append(dict(dim='+'.join(dims[3:]) or 'all',line=' / '.join(map(str,k)),n=len(gg),events=gg.event.nunique(),per10=gg.pnl.mean(),t=tstat(gg.pnl),
             n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,fav_won=gg.won.mean(),avg_entry=gg.entry.mean()))
S=pd.DataFrame(out).round(3)
S['PASS']=(S.n>=300)&(S.n1>=150)&(S.n2>=150)&(S.t>=3.5)&(S.h1>0)&(S.h2>0)&(S.per10>=0.15)
pd.set_option('display.width',230); pd.set_option('display.max_rows',300)
print("\n== headline (per £10; fav_won = favourite won after the drift)"); print(S[S.dim=='all'].to_string(index=False))
for d in ('src','pband','ebandd','tour'): print(f"\n== by {d}"); print(S[S.dim==d].to_string(index=False))
print("\n== top 15 by t (n>=20)"); print(S[S.n>=20].sort_values('t',ascending=False).head(15).to_string(index=False))
k=R[(R.rule=='>=1.6xp0')&(R.res=='known')]
print(f"\nhedge+20 had a real exit print in {k[k.exit=='hedge+20'].hedge_print.mean():.0%} of entries")
P=pd.read_sql("SELECT count(*) n, avg(p_settle)::float settle, avg(p_hedge)::float hedge, min(ts) t0, max(ts) t1 FROM t2_paper",con)
print("\n== t2_paper as stored (drops unknown results, 2% slippage, p0 = first sample <=10 min in-play):"); print(P.round(3).to_string(index=False))
W=S[S.PASS].sort_values('t',ascending=False)
print(f"\n== SURVIVORS: {len(W)}"); print(W.to_string(index=False) if len(W) else "none")
PY
