#!/bin/bash
set -o pipefail
# 499_equaliser_draw_unseen (Finder 2026-11-07, queue item 432, Finder's own, source a, from item 430; copied from jobs/499_equaliser_unseen.sh): BACK THE DRAW AFTER A LATE EQUALISER TO 1-1, games not in af_price_map. Rule in the queue before this read. Read only, no tables written.
# SIGNAL: goals 1 and 2 by different sides, the second (1-1) at af minute E 66-80 (ITEM), 46-65 (CONTROL_H2) or 10-40 (CONTROL_H1); controls cannot pass; no third goal at or before E+3.
# ENTRY: back 'The Draw' at its first in-play MATCH_ODDS print in match minutes E+4..E+6 (clock: lib_afmatch.clock_min, second half +19 min after kick-off), worse of it and the next print within 120 s, one tick adverse (lib_afmatch.entry). PRICED: that raw print <= 0.8 x the Draw's last print in match minutes E-6..E-1. Raw print 1.01-50.
# EXIT: held to the af FT score, never dropped. £10 stake, 2% on profit. One bet a game. Halves by the date median. LTP only.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
import lib_cand,lib_official,lib_afmatch; lib_cand._checks(); lib_official.checks(); lib_afmatch.checks()
from lib_afmatch import *
from lib_official import secs
pd.set_option('display.width',230); pd.set_option('display.max_rows',80); pd.set_option('display.max_columns',30)
T0=time.time(); A,B='2023-04-01','2026-10-01'
def eq_signal(gl):
    """gl sorted [(minute,is_home)]. (E, first scorer is_home) if goals 1 and 2 are by different sides and no third goal by E+3, else None."""
    if len(gl)<2 or gl[0][1]==gl[1][1]: return None
    E=gl[1][0]
    if len(gl)>2 and gl[2][0]<=E+3: return None
    return E,gl[0][1]
def last_before(ts,px,t0,t1):
    k=np.where((ts>=t0)&(ts<t1))[0]
    return None if not len(k) else float(px[k[-1]])
assert eq_signal([(20,True),(60,False)])==(60,True) and eq_signal([(20,True),(60,True)]) is None and eq_signal([(20,True),(60,False),(62,True)]) is None and eq_signal([(20,True),(60,False),(64,True)])==(60,True)
assert clock_min(50)==69 and clock_min(46)==46 and clock_min(40)==40
_t=np.array([0.,10.,20.]); _p=np.array([1.5,1.6,4.0]); assert last_before(_t,_p,0,20)==1.6 and last_before(_t,_p,30,40) is None
assert abs(pnl('B',1.69,True)-6.9*.98)<1e-6 and pnl('B',1.69,False)==-10
print("known-answer checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=fixtures(con,A,B); MK=match(con,'MATCH_ODDS',A,B,F); print(f"fixtures {len(F):,}, MO markets matched {len(MK):,}, {time.time()-T0:.0f}s",flush=True)
FI=F.set_index('fixture_id')
EV=pd.read_sql("SELECT fixture_id,coalesce(minute,0) AS minute,is_home FROM af_events WHERE fixture_id=ANY(%s) AND is_home IS NOT NULL AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')",con,params=(list(map(int,MK.fx)),))
GL=defaultdict(list)
for r in EV.sort_values(['fixture_id','minute']).itertuples(): GL[r.fixture_id].append((int(r.minute),bool(r.is_home)))
SK=Counter(); SIG={}
for r in MK.itertuples():
    f=FI.loc[r.fx]; gl=GL.get(r.fx,[])
    if sum(1 for _,h in gl if h)!=f.hg or sum(1 for _,h in gl if not h)!=f.ag: SK['goal events do not match FT']+=1; continue
    s=eq_signal(gl)
    if s is None: continue
    grp='ITEM' if 66<=s[0]<=80 else ('CONTROL_H2' if 46<=s[0]<=65 else ('CONTROL_H1' if 10<=s[0]<=40 else None))
    if grp: SIG[r.market_id]=(grp,)+s
print("signals",Counter(v[0] for v in SIG.values()),flush=True)
mids=list(SIG); PX={}
for c in range(0,len(mids),500):
    P=pd.read_sql("SELECT market_id,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_id=ANY(%s) AND inplay AND ltp>=1.01 AND ltp<1000",con,params=(mids[c:c+500],))
    if not len(P): continue
    P['tt']=secs(P.ts); P=P.drop_duplicates(['market_id','sel','tt']).sort_values('tt',kind='stable')
    for k,x in P.groupby(['market_id','sel'],sort=False): PX[k]=(x.tt.values,x.ltp.values)
con.close(); print(f"tapes {len(PX):,}, {time.time()-T0:.0f}s",flush=True)
rows=[]
for r in MK[MK.market_id.isin(SIG)].itertuples():
    grp,E,fh=SIG[r.market_id]; f=FI.loc[r.fx]; ko=f.k.timestamp()
    h,_x,a=str(r.event_name).partition(' v '); nm={True:h.strip(),False:a.strip()}
    won=bool(f.hg==f.ag)
    x=PX.get((r.market_id,'The Draw'))
    if x is None: SK[f'{grp} no tape by name']+=1; continue
    e=entry(x[0],x[1],ko,clock_min(E+4),clock_min(E+7),'B')
    if e is None: SK[f'{grp} no print']+=1; continue
    p=float(x[1][e[0]])
    if not 1.01<=p<=50: SK[f'{grp} print outside 1.01-50']+=1; continue
    pre=last_before(x[0],x[1],ko+clock_min(E-6)*60,ko+clock_min(E)*60)
    rows.append(dict(grp=grp,g=r.fx,off=ko,season=int(f.season),E=E,p=p,a=e[1],pre=pre,priced=(pre is not None and p<=0.8*pre),won=won,v=pnl('B',e[1],won)))
print("counts",dict(SK),flush=True)
T=pd.DataFrame(rows); assert not T.duplicated(['grp','g']).any(); o=[]
T['half']=half(T.off.values)
def L(x,name,scored=False):
    l=line(x.v.values,x.half.values)
    q=x.v.quantile(0.99) if len(x) else 0
    return dict(line=name,scored=scored,n=l['n'],games=x.g.nunique(),per10=round(l['per10'],3),t=round(l['t'],2),h1=round(l['h1'],3),h2=round(l['h2'],3),n1=l['n1'],n2=l['n2'],px=x.p.median(),won=round(x.won.mean(),3),imp=round((1/x.p).mean(),3),less_top1=round(x.v[x.v<q].mean(),3),max_win=round(x.v.max(),2),PASS=bool(l['PASS'] and scored))
for grp,x in T.groupby('grp'):
    o.append(L(x[x.priced],f'{grp} DRAW BACK PRICED',grp=='ITEM'))
    o.append(L(x,f'{grp} DRAW BACK all prints'))
    o.append(L(x[~x.priced&x.pre.notna()],f'{grp} DRAW BACK NOT_PRICED'))
R=pd.DataFrame(o).sort_values('t',ascending=False); print(R.to_string(index=False))
Z=T[(T.grp=='ITEM')&T.priced].copy(); Z['pb']=pd.cut(Z.p,[1,1.5,1.8,2.2,3,50])
print("\nScored line by season:"); print(Z.groupby('season').v.agg(['size','mean']).round(3).to_string())
print("\nScored line by entry print band:"); print(Z.groupby('pb',observed=True).agg(n=('v','size'),per10=('v','mean'),won=('won','mean'),imp=('p',lambda s:(1/s).mean())).round(3).to_string())
S=R[R.PASS==True]; print(f"\n== SURVIVORS: {len(S)} of 1 scored line"); print(S.to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
