#!/bin/bash
set -o pipefail
# 458 (Finder 2026-11-03, queue item 9): OTHER SPORTS ON ip_tape (everything except tennis and football/soccer).
# 1) CENSUS per sport x market_type: rows, markets, events, date range, in-play snapshots per market, and how many markets have an
#    INFERABLE result = on the market's LAST OPEN in-play snapshot exactly one runner has back_px (or ltp) <= 1.05.
# 2) For sport x market_type with >= 150 inferable markets: snapshot = distinct ts of OPEN in-play rows (secs_since_start > 0).
#    GRID: back AND lay every runner at the first in-play snapshot and at 25/50/75% of the market's snapshots, by price band (back_px),
#    held to the result. MOMENTUM: first snapshot k>=20 where a runner's back_px shortened >= 15% vs snapshot k-20; back at back_px,
#    exit at snapshot k+20 at lay_px (no print for that runner there -> next snapshot with one; none -> settle at result).
#    Real touch, +1 tick adverse both ends, 2% commission, £10 back stake / £10 lay liability. No forward-fill.
#    Unknown result (no runner <= 1.05 at the last OPEN snapshot): "known" drops them (DIAGNOSTIC, never eligible to PASS; that is the
#    bias found in 457), "worst" counts the trade as a full -£10. Halves = market_start before/after the median.
#    One entry per runner per market per entry point (correlated: the opposite runner of a 2-way market is the mirror image).
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
def tick(p): return 0.01 if p<2 else 0.02 if p<3 else 0.05 if p<4 else 0.1 if p<6 else 0.2 if p<10 else 0.5 if p<20 else 1 if p<30 else 2 if p<50 else 5 if p<100 else 10
def pnl(side,p,q,res):
    if side=='B':
        p=p-tick(p)
        if p<=1.01: return None
        if q is None: r=10*(p-1) if res==1 else -10.0
        else: q=q+tick(q); r=10*(p/q-1)
    else:
        p=p+tick(p); s=10/(p-1)
        if q is None: r=s if res==-1 else -10.0
        else: q=max(1.01,q-tick(q)); r=s*(1-p/q)
    return r*0.98 if r>0 else r
assert abs(pnl('B',3.05,None,1)-10*2.0*0.98)<1e-9 and pnl('B',3.0,None,-1)==-10.0 and abs(pnl('L',4.9,None,-1)-10/4.0*0.98)<1e-9
assert pnl('L',2.0,None,1)==-10.0 and abs(pnl('B',2.5,2.0,1)-10*(2.48/2.02-1)*0.98)<1e-9
print("P&L unit checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET statement_timeout='2400s'")
t0=time.time()
C=pd.read_sql("""SELECT sport, market_type, count(*) n_rows, count(DISTINCT market_id) markets, count(DISTINCT event_name) events,
  min(ts)::date d0, max(ts)::date d1 FROM ip_tape WHERE sport NOT ILIKE 'tennis' AND sport NOT ILIKE '%%soccer%%' AND sport NOT ILIKE 'football'
  GROUP BY 1,2 ORDER BY 4 DESC""",con)
pd.set_option('display.width',230); pd.set_option('display.max_rows',300)
print(f"== CENSUS ({int(time.time()-t0)}s): sport x market_type, all non-tennis non-football rows"); print(C.head(60).to_string(index=False),flush=True)
print("sports:",C.groupby('sport').markets.sum().sort_values(ascending=False).to_dict(),flush=True)
def band(p): return '<1.5' if p<1.5 else '1.5-2' if p<2 else '2-3' if p<3 else '3-5' if p<5 else '5-10' if p<10 else '10-50'
CEN=[]; rows=[]; SK=defaultdict(int)
for (sport,mt),cc in C.groupby(['sport','market_type']):
    # v2: winner markets only (run 1 was OOM-killed loading basketball COMBINED_TOTAL, 7.7M rows; line markets have many runners and
    # no single-runner result anyway); horse racing excluded (not in the item; racing is covered by racing_bsp)
    if int(cc.markets.iloc[0])<150 or mt not in ('MATCH_ODDS','MONEY_LINE','RT_MATCH_ODDS') or sport=='horse_racing': continue
    T=pd.read_sql("""SELECT market_id, event_name, market_start, ts, status, secs_since_start s, sel_id, ltp::float ltp, back_px::float bp, back_sz::float bs,
      lay_px::float lp, lay_sz::float ls FROM ip_tape WHERE sport=%s AND market_type=%s AND status='OPEN' AND secs_since_start>0 ORDER BY market_id, ts""",con,params=(sport,mt))
    inf=0; snaps=[]; mk=[]
    for mid,g in T.groupby('market_id',sort=False):
        ts=np.sort(g.ts.unique()); snaps.append(len(ts))
        last=g[g.ts==ts[-1]]; lo=last[['bp','ltp']].min(axis=1)
        w=last.sel_id[lo<=1.05].unique(); win=w[0] if len(w)==1 else None
        inf+=win is not None; mk.append((mid,g,ts,win))
    CEN.append(dict(sport=sport,market_type=mt,markets=len(mk),inferable=inf,snaps_median=int(np.median(snaps)) if snaps else 0,
                    snaps_p10=int(np.percentile(snaps,10)) if snaps else 0))
    if inf<150: continue
    for mid,g,ts,win in mk:
        if len(ts)<8: SK[f'{sport}/{mt}: <8 snapshots']+=1; continue
        ms=g.market_start.iloc[0]; ev=g.event_name.iloc[0]
        by={s:d.drop_duplicates('ts').set_index('ts') for s,d in g.groupby('sel_id')}
        def at(s,k,col):
            d=by[s]
            for kk in range(k,len(ts)):
                if ts[kk] in d.index:
                    r=d.loc[ts[kk]]
                    if col=='bp' and pd.notna(r.bp) and r.bs>0: return kk,r.bp
                    if col=='lp' and pd.notna(r.lp) and r.ls>0: return kk,r.lp
            return None
        for s in by:
            res=None if win is None else (1 if s==win else -1)
            for ep,k in (('first',0),('25%',len(ts)//4),('50%',len(ts)//2),('75%',3*len(ts)//4)):
                for side,col in (('B','bp'),('L','lp')):
                    e=at(s,k,col)
                    if e is None or e[0]>k+2 or e[1]>50: continue     # entry must be a real print at (or within 2 snapshots of) the point
                    for rv in ('known','worst'):
                        if res is None and rv=='known': continue
                        r=-10.0 if res is None else pnl(side,e[1],None,res)
                        if r is None: continue
                        rows.append(dict(sport=sport,mt=mt,test='grid',ep=ep,side=side,band=band(e[1]),rv=rv,mid=mid,ms=ms,pnl=r))
            d=by[s]; bpser=[(d.loc[t].bp if t in d.index else np.nan) for t in ts]
            for k in range(20,len(ts)):
                a,b=bpser[k-20],bpser[k]
                if pd.notna(a) and pd.notna(b) and b<=a*0.85 and b<=50 and d.loc[ts[k]].bs>0:
                    x=at(s,k+20,'lp') if k+20<len(ts) else None
                    for rv in ('known','worst'):
                        if x is None and res is None:
                            if rv=='known': continue
                            r=-10.0
                        else: r=pnl('B',b,None if x is None else x[1],res)
                        if r is None: continue
                        rows.append(dict(sport=sport,mt=mt,test='momentum',ep='-',side='B',band=band(b),rv=rv,mid=mid,ms=ms,pnl=r))
                    break
    print(f"  done {sport}/{mt}: markets {len(mk)} inferable {inf} | {int(time.time()-t0)}s",flush=True)
print("\n== CENSUS of in-play snapshots and inferable results (market types with >= 150 markets)"); print(pd.DataFrame(CEN).to_string(index=False) if CEN else "none")
print("skips:",dict(SK))
R=pd.DataFrame(rows)
if R.empty: print("\n== SURVIVORS: 0\nnone (no sport/market type with >= 150 inferable markets)"); sys.exit()
med=R.ms.median(); R['half']=np.where(R.ms<med,'H1','H2'); print("half split at",med)
def tstat(x): return x.mean()/(x.std(ddof=1)/len(x)**0.5) if len(x)>1 and x.std(ddof=1)>0 else 0.0
out=[]
for dims in (['sport','mt','test','side','rv'],['sport','mt','test','ep','side','rv'],['sport','mt','test','ep','side','band','rv'],['sport','mt','test','side','band','rv']):
    for k,gg in R.groupby(dims):
        a=gg[gg.half=='H1'].pnl; b=gg[gg.half=='H2'].pnl
        out.append(dict(cell=' / '.join(map(str,k)),n=len(gg),markets=gg.mid.nunique(),per10=gg.pnl.mean(),t=tstat(gg.pnl),n1=len(a),h1=a.mean() if len(a) else np.nan,
                        n2=len(b),h2=b.mean() if len(b) else np.nan))
S=pd.DataFrame(out).drop_duplicates('cell').round(3)
S['PASS']=(S.cell.str.endswith('/ worst'))&(S.n>=300)&(S.n1>=150)&(S.n2>=150)&(S.t>=3.5)&(S.h1>0)&(S.h2>0)&(S.per10>=0.15)
print("\n== headline cells"); print(S[S.cell.str.count(' / ')==4].to_string(index=False))
print(f"\n== cells: {len(S)}, at n>=300: {(S.n>=300).sum()}")
print("\n== top 15 by t (n>=100, worst)"); print(S[(S.n>=100)&S.cell.str.endswith('worst')].sort_values('t',ascending=False).head(15).to_string(index=False))
print("\n== top 15 by t (n>=100, known — diagnostic)"); print(S[(S.n>=100)&S.cell.str.endswith('known')].sort_values('t',ascending=False).head(15).to_string(index=False))
W=S[S.PASS].sort_values('t',ascending=False)
print(f"\n== SURVIVORS: {len(W)}"); print(W.head(30).to_string(index=False) if len(W) else "none")
PY
