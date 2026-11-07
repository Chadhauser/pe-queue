#!/bin/bash
set -o pipefail
# 499_goal_type_unseen (Finder 2026-11-07, queue items 185 and 403, Finder's own; rules from jobs/499_goal_type.sh and jobs/499_let_off.sh, match from jobs/lib_afmatch.py): games not in af_price_map only. Rules in the queue before this read. Read only, no tables written. LTP only, so a pass is an upper bound.
# 185 PEN first goal, back Over 2.5 E10 settle: af minute c 1-34 or 46-80; first print c+10..c+12 as match minutes, second half on the clock +19; worse of it and the next within 120 s, one tick adverse; no trade if a second goal has come by that print; held to the result. Goal rows must agree with the score. NORMAL and OG read beside it, E5 printed for reading, neither scored.
# 403 MISSED PEN, back Over 2.5 E5 settle: first missed penalty of the game, minute <= 85, under three goals by then (from jobs/499_let_off.sh); first print c+5..c+7. No second-goal rule, as in item 84. Held to the result. Scored only for seasons where af_events holds the rows.
# CLOCK prints where the largest jump in the Over price sits against the af minute, on the clock mapping used here, as a late or early clock would make an entry look ahead.
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
TYPE={'Normal Goal':'NORMAL','Penalty':'PEN','Own Goal':'OG'}
def ok_minute(c,lag): return 1<=c<=44-lag or 46<=c<=80
def first_goal(rows):
    r=sorted(rows,key=lambda x:(x[0],x[1])); return r[0],(r[1][0] if len(r)>1 else None)
def consistent(rows,hg,ag): return sum(1 for r in rows if r[2])==hg and sum(1 for r in rows if not r[2])==ag
def win(c,lo,hi):
    """Clock minutes after kick-off for the entry window c+lo..c+hi in match minutes."""
    return clock_min(c+lo),clock_min(c+hi)
assert ok_minute(34,10) and not ok_minute(35,10) and ok_minute(46,10) and ok_minute(80,10) and not ok_minute(81,10) and ok_minute(39,5) and not ok_minute(40,5)
_r=[(46,0,True,'NORMAL'),(45,2,False,'PEN'),(70,0,True,'OG')]
assert first_goal(_r)==((45,2,False,'PEN'),46) and consistent(_r,2,1) and not consistent(_r,1,2)
assert win(20,10,12)==(30,32) and win(50,10,12)==(79,81) and win(40,5,7)==(45,66)
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=fixtures(con,A,B); print(f"unmapped FT fixtures {len(F):,}, by season {F.season.value_counts().sort_index().to_dict()}, {time.time()-T0:.0f}s",flush=True)
MK=match(con,'OVER_UNDER_25',A,B,F); print(f"OU25 markets matched to one fixture {len(MK):,}, {time.time()-T0:.0f}s",flush=True)
FI=F.set_index('fixture_id'); ids=list(map(int,MK.fx))
EV=pd.read_sql("SELECT fixture_id,coalesce(minute,0) AS minute,coalesce(extra,0) AS extra,is_home,detail FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal','Missed Penalty') AND is_home IS NOT NULL",con,params=(ids,))
GL=defaultdict(list); MP={}
for r in EV.sort_values(['fixture_id','minute','extra']).itertuples():
    if r.detail=='Missed Penalty': MP.setdefault(r.fixture_id,int(r.minute))
    else: GL[r.fixture_id].append((int(r.minute),int(r.extra),bool(r.is_home),TYPE[r.detail]))
mps=pd.Series({k:FI.loc[k].season for k in MP}).value_counts().sort_index().to_dict() if MP else {}
print(f"first missed penalties by season {mps}, goal games {len(GL):,}",flush=True)
PX=tape(con,'OVER_UNDER_25',list(MK.market_id),'over',log=lambda s:print(s,f"| {time.time()-T0:.0f}s",flush=True)); OF=official_over(con,list(MK.market_id)); con.close()
rows=[]; chk=[]; off=defaultdict(list); SK=Counter()
for r in MK.itertuples():
    f=FI.loc[r.fx]; ko=f.k.timestamp(); tot=int(f.hg+f.ag); won=tot>2.5; x=PX.get(r.market_id); gl=GL.get(r.fx,[])
    if x is None: SK['no in-play Over tape']+=1; continue
    ts,px=x; chk.append((won,OF.get(r.market_id)))
    # 403
    c=MP.get(r.fx)
    if c is not None:
        if c>85: SK['missed pen after 85']+=1
        elif sum(1 for g in gl if g[0]<=c)>=3: SK['missed pen, three goals already']+=1
        else:
            lo,hi=win(c,5,7); e=entry(ts,px,ko,lo,hi,'B')
            if e is None: SK['missed pen no print']+=1
            else: rows.append(('MISSED_PEN','E5',ko,int(f.season),r.fx,pnl('B',e[1],won),won,1/e[1],e[1]))
    # 185
    if tot==0 or not gl: SK['no goal']+=1; continue
    if not consistent(gl,f.hg,f.ag): SK['goal rows disagree with the score']+=1; continue
    fg,sec=first_goal(gl); c=fg[0]; kind=fg[3]
    # CLOCK: largest jump in the Over price within 6 min before to 14 min after the mapped minute. No outcome is read.
    t0=ko+clock_min(c)*60; i0=np.where((ts>=t0-360)&(ts<=t0+840))[0]
    if len(i0)>=2:
        js=np.abs(np.diff(np.log(px[i0]))); off['H1' if c<=45 else 'H2'].append((ts[i0[1:]][int(js.argmax())]-t0)/60)
    for ent,lag in (('E5',5),('E10',10)):
        if not ok_minute(c,lag): SK[f'{ent} minute out']+=1; continue
        lo,hi=win(c,lag,lag+2); e=entry(ts,px,ko,lo,hi,'B')
        if e is None: SK[f'{ent} no print or no bet']+=1; continue
        i,a=e
        if sec is not None and sec<=match_minute((ts[i]-ko)/60): SK[f'{ent} second goal by entry']+=1; continue
        rows.append((kind,ent,ko,int(f.season),r.fx,pnl('B',a,won),won,1/a,a))
print("counts",dict(SK),flush=True)
ag,ck=agreement(chk); print(f"af score v official Over result: {ag} of {ck} agree, {ag/max(ck,1):.3f}",flush=True)
print("\n== CLOCK largest Over jump, minutes after the mapped af minute (no outcome is read)")
for k,v in off.items(): print(' ',k,'n',len(v),'pct10/50/90',np.percentile(v,[10,50,90]).round(1).tolist())
T=pd.DataFrame(rows,columns='kind ent off season g v won imp a'.split()); assert not T.duplicated(['kind','ent','g']).any(); o=[]
N={e:x.v.values for e,x in T[T.kind=='NORMAL'].groupby('ent')}
for (k,e),x in T.groupby(['kind','ent']):
    l=line(x.v.values,half(x.off.values)); nv=N.get(e); dt=np.nan
    if k!='NORMAL' and nv is not None and len(x)>1: dt=(x.v.mean()-nv.mean())/np.sqrt(x.v.var(ddof=1)/len(x)+nv.var(ddof=1)/len(nv))
    sc=(k=='PEN' and e=='E10') or (k=='MISSED_PEN' and e=='E5')
    o.append(dict(line=f'{k} OVER25 back {e} settle',scored=sc,n=l['n'],per10=round(l['per10'],3),t=round(l['t'],2),h1=round(l['h1'],3),h2=round(l['h2'],3),n1=l['n1'],n2=l['n2'],won=round(x.won.mean(),3),imp=round(x.imp.mean(),3),medpx=round(x.a.median(),2),ex_top=round((x.v.sum()-x.v.max())/max(len(x)-1,1),3),t_v_NORMAL=round(dt,2) if dt==dt else np.nan,PASS=l['PASS'] and sc))
L=pd.DataFrame(o).sort_values('t',ascending=False); print(f"\nlines {len(L)}, {time.time()-T0:.0f}s"); print(L.to_string(index=False))
print("\nScored lines by season:")
print(T[((T.kind=='PEN')&(T.ent=='E10'))|((T.kind=='MISSED_PEN')&(T.ent=='E5'))].groupby(['kind','season']).v.agg(['size','mean']).round(3).to_string())
S=L[L.PASS==True]; print(f"\n== SURVIVORS: {len(S)}"); print(S.to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
