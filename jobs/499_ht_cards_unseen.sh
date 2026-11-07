#!/bin/bash
set -o pipefail
# 499_ht_cards_unseen (Finder 2026-11-07, queue item 184, Finder's own, source d; rule from jobs/499_ht_cards.sh, match from jobs/499_foul_draw_unseen.sh through jobs/lib_afmatch.py): lay Over 2.5 at 0-0 at half-time after two or three first-half yellows, games not in af_price_map only. Rule in the queue before this read. Read only, no tables written. LTP only, so a pass is an upper bound.
# FIX 2026-11-07, first run dropped goals AFTER the print through a 3-minute cushion, 242 games, look-ahead that flatters the lay: first read G0 Y23 lay n 783 +0.353 t 2.27 is void. Three reads now: RULE no cushion, scored; NODROP every game at its first print, none dropped; BREAK first print 54 to 60 min after kick-off, inside the break, where 0-0 is known with no goal check.
# STATE as item 181. ENTRY first in-play print 60 to 71 min after kick-off (tape 47..52 is about KO+66..71, and 60 is the floor set by jobs/499_goal_timing.sh), worse of it and the next within 120 s, one tick adverse. No trade if a second-half goal has come by the print, the match minute being clock less 19, no cushion. Held to the result, 2%, £10 risk, one bet per game per line. Halves by date median.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
import lib_cand,lib_official,lib_afmatch; lib_cand._checks(); lib_official.checks(); lib_afmatch.checks()
from lib_afmatch import *
pd.set_option('display.width',230); pd.set_option('display.max_rows',80); pd.set_option('display.max_columns',30)
T0=time.time(); A,B='2023-08-01','2026-10-01'
def yb(n): return 'Y01' if n<=1 else 'Y23' if n<=3 else 'Y4'
def first_half(m): return m<=45
def h2_goal_by(goals,el):
    """Any af goal after minute 45 at or before the print, el minutes after kick-off. Never a goal after the print."""
    return any(45<m<=match_minute(el) for m in goals)
assert yb(1)=='Y01' and yb(2)=='Y23' and yb(3)=='Y23' and yb(4)=='Y4' and first_half(45) and not first_half(46)
assert h2_goal_by([46],63) is True and h2_goal_by([47],63) is False     # el 63 reads 46
assert h2_goal_by([30],70) is False and h2_goal_by([51],70) is True and h2_goal_by([52],70) is False   # el 70 = 51
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=fixtures(con,A,B); F=F[F.ht_hg.notna()&F.ht_ag.notna()].reset_index(drop=True); print(f"unmapped FT fixtures {len(F):,}, by season {F.season.value_counts().sort_index().to_dict()}, {time.time()-T0:.0f}s",flush=True)
MK=match(con,'OVER_UNDER_25',A,B,F); print(f"OU25 markets matched to one fixture {len(MK):,}, {time.time()-T0:.0f}s",flush=True)
FI=F.set_index('fixture_id'); ids=list(map(int,MK.fx))
EV=pd.read_sql("SELECT fixture_id,coalesce(minute,0) AS minute,is_home,type,detail FROM af_events WHERE fixture_id=ANY(%s) AND (type IN ('Card','subst','Subst') OR (type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')))",con,params=(ids,))
YL=defaultdict(lambda:[0,0]); RED=set(); COV=set(); GO=defaultdict(list)
for r in EV.itertuples():
    t=str(r.type).lower()
    if t=='subst': COV.add(r.fixture_id)
    elif t=='goal': GO[r.fixture_id].append(int(r.minute))
    elif first_half(r.minute):
        if r.detail in ('Red Card','Second Yellow Card'): RED.add(r.fixture_id)
        elif r.detail=='Yellow Card' and r.is_home is not None and r.is_home==r.is_home: YL[r.fixture_id][0 if r.is_home else 1]+=1
keep=[]
SK=Counter()
for r in MK.itertuples():
    f=FI.loc[r.fx]
    if r.fx not in COV: SK['no substitution row, not covered']+=1; continue
    if r.fx in RED: SK['first-half red']+=1; continue
    if f.ht_hg+f.ht_ag!=0: SK['not 0-0 at half-time']+=1; continue
    keep.append(r)
print("state counts",dict(SK),"G0 games",len(keep),flush=True)
PX=tape(con,'OVER_UNDER_25',[r.market_id for r in keep],'over'); OF=official_over(con,[r.market_id for r in keep]); con.close(); print(f"tapes {len(PX):,}, official {len(OF):,}, {time.time()-T0:.0f}s",flush=True)
rows=[]; chk=[]; SK=Counter()
for r in keep:
    f=FI.loc[r.fx]; ko=f.k.timestamp(); won=(f.hg+f.ag)>2.5; Y=yb(sum(YL[r.fx])); x=PX.get(r.market_id)
    if x is None: SK['no in-play Over tape']+=1; continue
    chk.append((won,OF.get(r.market_id)))
    for side in 'BL':
        for var,lo,hi,gc in (('RULE',60,71,True),('NODROP',60,71,False),('BREAK',54,60,False)):
            e=entry(x[0],x[1],ko,lo,hi,side)
            if e is None: SK[f'{var} {side} no print or no bet']+=1; continue
            i,a=e
            if gc and h2_goal_by(GO.get(r.fx,[]),(x[0][i]-ko)/60): SK[f'{var} {side} second-half goal by entry']+=1; continue
            rows.append((var,Y,'BACK' if side=='B' else 'LAY',ko,int(f.season),r.fx,pnl(side,a,won),won,1/a,a))
print("trade counts",dict(SK),flush=True)
ag,ck=agreement(chk); print(f"af score v official Over result: {ag} of {ck} agree, {ag/max(ck,1):.3f}",flush=True)
T=pd.DataFrame(rows,columns='var Y side off season g v won imp a'.split()); assert not T.duplicated(['var','Y','side','g']).any()
o=[]
Nv={k:x.v.values for k,x in T[T.Y=='Y01'].groupby(['var','side'])}
for (V,Y,s),x in T.groupby(['var','Y','side']):
    l=line(x.v.values,half(x.off.values)); nv=Nv.get((V,s)); dt=np.nan if Y=='Y01' else (x.v.mean()-nv.mean())/np.sqrt(x.v.var(ddof=1)/len(x)+nv.var(ddof=1)/len(nv))
    o.append(dict(line=f'{V} OU25 G0 {Y} {s}',n=l['n'],games=x.g.nunique(),per10=round(l['per10'],3),t=round(l['t'],2),h1=round(l['h1'],3),h2=round(l['h2'],3),n1=l['n1'],n2=l['n2'],won=round(x.won.mean(),3),imp=round(x.imp.mean(),3),medpx=round(x.a.median(),2),maxwin=round(l['maxwin'],2),t_v_Y01=round(dt,2) if dt==dt else np.nan,PASS=l['PASS'] and V=='RULE' and Y=='Y23' and s=='LAY'))
L=pd.DataFrame(o).sort_values('t',ascending=False); print(f"\nlines {len(L)}, {time.time()-T0:.0f}s"); print(L.to_string(index=False))
Z=T[(T['var']=='RULE')&(T.Y=='Y23')&(T.side=='LAY')]
print("\nSCORED line by season:"); print(Z.groupby('season').v.agg(['size','mean']).round(3).to_string())
print(f"\nSCORED line less its largest win: {(Z.v.sum()-Z.v.max())/max(len(Z)-1,1):.3f}")
G=T[T.side=='LAY'].groupby(['var','g']).agg(off=('off','first'),v=('v','first')).reset_index()
print('\nAll G0 lay, every yellow bucket, for reading, not scored:')
for V,x in G.groupby('var'):
    l=line(x.v.values,half(x.off.values)); print(' ',V,'n',l['n'],'per10',round(l['per10'],3),'t',round(l['t'],2),'h1',round(l['h1'],3),'h2',round(l['h2'],3))
S=L[L.PASS==True]; print(f"\n== SURVIVORS: {len(S)}"); print(S.to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
