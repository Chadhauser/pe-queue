#!/bin/bash
set -o pipefail
# 499_h2h_bogey (Finder 2026-11-05, queue item 121, Finder's own, source c): is the head-to-head priced? Rule written in the queue before any price was read. The number 499 is reused with a new slug: 450-499 are all taken.
# DATA af_fixtures seasons 2016 on for the meetings, league games only (cups 2, 3 excluded), af_price_map, bf_hist_price MO and OU25; fd_matches for the proxy. Meetings are those with an earlier kick-off, at either venue, within 6 years, last 5, 4+ held. A pair is keyed by the two team names as spelled in that source: a renamed club loses its history, so states run slightly thin, not wrong.
# ENTRY earliest real print in tape minutes 0..2; lag outside -5..+20 v the af kick-off dropped, a goal before the print minute dropped, as jobs/499_new_division.sh. One tick adverse, 2%, £10 risk, to the result. Halves by season. LTP only, a pass is an upper bound.
# PROXY Pinnacle closes on fd_matches, same states built from fd_matches' own history: not a tradeable fill, cannot pass.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',40)
T0=time.time()
SIX=6*365.25*86400
def bk(x,won):
    a=step(x,-1); return None if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)
def h2h(hist,me,when):
    """hist: earlier meetings of this pair, oldest first, (ks,winner name or None,total goals). Returns (held,me_wins,opp_wins,over,under) on the last 5 within 6 years, or None if under 4."""
    h=[z for z in hist if when-z[0]<=SIX and z[0]<when][-5:]
    if len(h)<4: return None
    w=sum(z[1]==me for z in h); dr=sum(z[1] is None for z in h)
    return len(h),w,len(h)-w-dr,sum(z[2]>2.5 for z in h),sum(z[2]<2.5 for z in h)
def team_states(s,price_me,price_op):
    """Team states for one team given its h2h tuple and the two prices."""
    o=[]
    if s[1]>=4: o.append('BOGEY')
    if s[1]>=4 and price_me>price_op: o.append('BOGEY_DOG')
    if s[1]==0 and price_me<price_op: o.append('HOODOO_FAV')
    return o
def goal_states(s):
    o=[]
    if s[3]==s[0]: o.append('ALL_OVER')
    if s[4]==s[0]: o.append('ALL_UNDER')
    return o
# known answers, worked by hand
_h=[(100,'A',3),(200,'A',1),(300,None,2),(400,'A',4),(500,'A',5)]
assert h2h(_h,'A',600)==(5,4,0,3,2) and h2h(_h,'B',600)==(5,0,4,3,2) and h2h(_h[:3],'A',600) is None and h2h(_h,'A',500)==(4,3,0,2,2)    # 500 sees only the four earlier
assert h2h([(0,'A',3)]*4+[(SIX+100,'A',3)],'A',SIX+200) is None     # old meetings fall out of the 6 years, leaving one
assert h2h(_h+[(600,'B',3),(700,'B',3)],'A',800)==(5,2,2,4,1)        # last 5 only: None,A,A,B,B
assert team_states((5,4,0,3,2),3.0,2.0)==['BOGEY','BOGEY_DOG'] and team_states((5,4,0,3,2),2.0,3.0)==['BOGEY'] and team_states((5,0,4,3,2),2.0,3.0)==['HOODOO_FAV'] and team_states((5,0,4,3,2),3.0,2.0)==[] and team_states((5,2,2,3,2),3.0,2.0)==[]
assert goal_states((4,1,1,4,0))==['ALL_OVER'] and goal_states((4,1,1,0,4))==['ALL_UNDER'] and goal_states((4,1,1,3,1))==[]
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=pd.read_sql("SELECT fixture_id,season,kickoff,home,away,hg,ag FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND ag IS NOT NULL AND kickoff IS NOT NULL AND league_id NOT IN (2,3)",con)
F['ks']=pd.to_datetime(F.kickoff,utc=True).map(lambda t:t.timestamp()); F=F.sort_values('ks').reset_index(drop=True)
print(f"meetings source: {len(F)}, seasons {F.season.min()}-{F.season.max()}, {time.time()-T0:.0f}s",flush=True)
H=defaultdict(list); ST={}
for r in F.itertuples():
    k=frozenset((r.home,r.away)); ST[r.fixture_id]=(h2h(H[k],r.home,r.ks),h2h(H[k],r.away,r.ks))
    H[k].append((r.ks,r.home if r.hg>r.ag else r.away if r.ag>r.hg else None,r.hg+r.ag))
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.season,f.kickoff,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.season IN (2024,2025) AND f.league_id NOT IN (2,3)""",con)
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND coalesce(minute,0)<=2 GROUP BY 1",con,params=(list(map(int,G.fixture_id)),))
fg=dict(zip(EV.fixture_id,EV.gm)); parts=[]
for i in range(0,len(G),1000):
    P=pd.read_sql("SELECT event_id,mkt,sel,minute,m,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt IN ('MO','OU25') AND sel IN ('HOME','AWAY','UNDER','OVER') AND minute>=0 AND minute<=2 AND ltp>=1.01 AND ltp<1000",con,params=(list(G.event_id.iloc[i:i+1000]),))
    parts.append(P.sort_values(['event_id','mkt','sel','minute','m']).drop_duplicates(['event_id','mkt','sel']))
P=pd.concat(parts,ignore_index=True).merge(G,on='event_id')
P['lag']=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True)).dt.total_seconds()/60
gm=P.fixture_id.map(fg); bad=(P.lag<-5)|(P.lag>20); kn=gm.notna()&(gm<P.minute); print(f"games with a print {P.event_id.nunique()}; dropped lag {int(bad.sum())}, goal {int(kn.sum())}; {time.time()-T0:.0f}s",flush=True); P=P[~bad&~kn]
rows=[]; nst=0
def put(st,lg,side,s,fx,x,won):
    v=bk(x,won) if side=='BACK' else ly(x,won)
    if v is not None: rows.append((st,lg,side,1 if s==2024 else 2,fx,x,won,v))
for (fx,s,hg,ag),x in P.groupby(['fixture_id','season','hg','ag']):
    z=ST.get(fx)
    if z is None or z[0] is None: continue
    nst+=1; pr={(a,b):c for a,b,c in zip(x.mkt,x.sel,x.ltp)}; ph,pa=pr.get(('MO','HOME')),pr.get(('MO','AWAY'))
    if ph is not None and pa is not None:
        for me,op,sm,pm,po,wm,wo in ((z[0],z[1],'H',ph,pa,hg>ag,ag>hg),(z[1],z[0],'A',pa,ph,ag>hg,hg>ag)):
            for st in team_states(me,pm,po):
                for side in ('BACK','LAY'):
                    put(st,'team',side,s,fx,pm,wm); put(st,'opp',side,s,fx,po,wo)
    over=hg+ag>2.5
    for st in goal_states(z[0]):
        for sel,won in (('OVER',over),('UNDER',not over)):
            if ('OU25',sel) in pr:
                for side in ('BACK','LAY'): put(st,sel,side,s,fx,pr[('OU25',sel)],won)
R=pd.DataFrame(rows,columns=['st','leg','side','h','fx','x','won','v']); print(f"games with a head-to-head state {nst}; rows {len(R)}; {time.time()-T0:.0f}s",flush=True)
def tb(k,x):
    l=line(x.v.values,x.h.values); tg=tstat(x.groupby('fx').v.sum().values)
    return dict(state=k[0],leg=k[1],side=k[2],n=l['n'],games=x.fx.nunique(),per10=l['per10'],t=l['t'],t_game=tg,n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),imp=(1/x.x).mean(),maxwin=l['maxwin'],PASS=l['PASS'] and tg>=3.5)
O=pd.DataFrame([tb(k,x) for k,x in R.groupby(['st','leg','side'])])
print("\n== every line\n",O.sort_values('t',ascending=False).round(3).to_string(index=False),flush=True)
# ---- proxy
D=pd.read_sql("SELECT div,season,date,home,away,fthg,ftag,psch::float psch,psca::float psca,raw->>'PC>2.5' pco,raw->>'PC<2.5' pcu FROM fd_matches WHERE fthg IS NOT NULL AND ftag IS NOT NULL ORDER BY date",con); con.close()
D['ks']=pd.to_datetime(D.date,utc=True).map(lambda t:t.timestamp()); H=defaultdict(list); px=[]
for r in D.itertuples():
    k=frozenset((r.home,r.away)); a,b=h2h(H[k],r.home,r.ks),h2h(H[k],r.away,r.ks)
    if a is not None and r.psch==r.psch and r.psca==r.psca and r.psch>1 and r.psca>1:
        for me,pm,po,wm,wo in ((a,r.psch,r.psca,r.fthg>r.ftag,r.ftag>r.fthg),(b,r.psca,r.psch,r.ftag>r.fthg,r.fthg>r.ftag)):
            for st in team_states(me,pm,po):
                for lg,x,w in (('team',pm,wm),('opp',po,wo)):
                    for side,v in (('BACK',bk(x,w)),('LAY',ly(x,w))):
                        if v is not None: px.append((st,lg,side,r.season,v))
    # goal states at the Pinnacle closing 2.5 line, held from 2019-20 on (raw PC>2.5, PC<2.5); blank or unreadable: not traded
    if a is not None:
        try: pco,pcu=float(r.pco),float(r.pcu)
        except (TypeError,ValueError): pco=pcu=None
        if pco and pcu and pco>1 and pcu>1:
            over=r.fthg+r.ftag>2.5
            for st in goal_states(a):
                for lg,x,w in (('OVER',pco,over),('UNDER',pcu,not over)):
                    for side,v in (('BACK',bk(x,w)),('LAY',ly(x,w))):
                        if v is not None: px.append((st,lg,side,r.season,v))
    H[k].append((r.ks,r.home if r.fthg>r.ftag else r.away if r.ftag>r.fthg else None,r.fthg+r.ftag))
PX=pd.DataFrame(px,columns=['st','leg','side','season','v'])
print("\n== PROXY, Pinnacle closes, cannot pass\n",pd.DataFrame([dict(state=k[0],leg=k[1],side=k[2],n=len(x),per10=x.v.mean(),t=tstat(x.v.values),seasons_pos=f"{int((x.groupby('season').v.mean()>0).sum())}/{x.season.nunique()}") for k,x in PX.groupby(['st','leg','side'])]).round(3).to_string(index=False))
Y=O[O.PASS]; print(f"\n== SURVIVORS: {len(Y)} of {len(O)} (bar: n>=300, n>=150 per half, both > 0, t and t by game >= 3.5, mean >= +0.15, LTP upper bound)\n",Y.round(3).to_string(index=False) if len(Y) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
