#!/bin/bash
set -o pipefail
# 499_home_dog (Finder 2026-11-06, queue items 207, 208, 209, Finder's own, sources b, c): home underdog at the first print; the Saturday 3pm favourite; a count of two-leg second legs. Rules pushed before any price was read. The number 499 is reused: 450-499 are all taken.
# ENTRY and guards as jobs/499_euro_hangover.sh: earliest real print tape minutes 0..2 on MO; lag outside -5..+20 min dropped; a goal with af minute before the print minute dropped. One tick adverse, 2%, £10 risk, hold to FT. Halves seasons 2024 v 2025. LTP only, so a pass is an upper bound. UEFA left out. One bet per game per line.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))  # this job only
import sys,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,lay_settle,line
import lib_cand; lib_cand._checks()
pd.set_option('display.width',240); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',30)
T0=time.time(); DAY=86400; UK=(39,40,41,42,179,180)
def bk(x,won):
    a=step(x,-1); return None if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)
def dog_band(p): return '2-3' if 2<=p<3 else '3-4' if 3<=p<4 else '4-6' if 4<=p<6 else '6-12' if 6<=p<12 else None
def fav_band(p): return '<=1.5' if p<=1.5 else '1.5-2' if p<=2 else None
def sides(h,a):
    """(fav,dog) as 'HOME'/'AWAY' by the shorter print; a tie is no bet."""
    return None if h==a else ('HOME','AWAY') if h<a else ('AWAY','HOME')
def sat1500(ts_utc):
    t=pd.Timestamp(ts_utc).tz_convert('Europe/London'); return t.dayofweek==5 and t.hour==15 and t.minute==0
def second_legs(rows):
    """rows (fixture,sec,home,away), UEFA only. Fixtures that have a swapped meeting 5-21 days before."""
    last={}; out=[]
    for f,t,h,a in sorted(rows,key=lambda r:r[1]):
        p=last.get((a,h))
        if p is not None and 5*DAY<=t-p<=21*DAY: out.append(f)
        last[(h,a)]=t
    return out
# known answers, worked by hand
assert dog_band(1.99) is None and dog_band(2)=='2-3' and dog_band(3)=='3-4' and dog_band(4)=='4-6' and dog_band(6)=='6-12' and dog_band(12) is None
assert fav_band(1.5)=='<=1.5' and fav_band(1.51)=='1.5-2' and fav_band(2)=='1.5-2' and fav_band(2.01) is None
assert sides(2.,3.)==('HOME','AWAY') and sides(3.,2.)==('AWAY','HOME') and sides(2.5,2.5) is None
assert sat1500('2026-11-07 15:00:00+00:00') and not sat1500('2026-11-07 14:00:00+00:00') and not sat1500('2026-11-08 15:00:00+00:00')
assert sat1500('2026-08-15 14:00:00+00:00') and not sat1500('2026-08-15 15:00:00+00:00')    # BST: 15:00 London is 14:00 UTC
assert second_legs([(1,0,'A','B'),(2,7*DAY,'B','A')])==[2] and second_legs([(1,0,'A','B'),(2,4*DAY,'B','A')])==[] and second_legs([(1,0,'A','B'),(2,22*DAY,'B','A')])==[] and second_legs([(1,0,'A','B'),(2,7*DAY,'A','B')])==[]
assert abs(bk(2.04,True)-9.996)<1e-9 and bk(2.04,False)==-10.0 and ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.league_id,f.league,f.season,f.kickoff,f.home,f.away,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.season IN (2024,2025)""",con)
U=G[G.league.str.startswith('UEFA')]
rows=[(f,pd.Timestamp(k).timestamp(),h,a) for f,k,h,a in zip(U.fixture_id,U.kickoff,U.home,U.away)]; L2=second_legs(rows)
print(f"item 209: mapped UEFA games {len(U)}, second legs {len(L2)}: {'under 300, not priced' if len(L2)<300 else 'can reach n, queue a test'}",flush=True)
G=G[~G.league.str.startswith('UEFA')]; print(f"mapped games {len(G)}, UK ids {G[G.league_id.isin(UK)].groupby(['league_id','league']).size().to_dict()}",flush=True)
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND coalesce(minute,0)<=2 GROUP BY 1",con,params=(list(map(int,G.fixture_id)),))
first_goal=dict(zip(EV.fixture_id,EV.gm)); parts=[]
for i in range(0,len(G),1000):
    P=pd.read_sql("SELECT event_id,sel,minute,m,ltp::float8 ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='MO' AND sel IN ('HOME','AWAY') AND minute>=0 AND minute<=2 AND ltp>=1.01 AND ltp<1000",con,params=(list(G.event_id.iloc[i:i+1000]),))
    parts.append(P.sort_values(['event_id','sel','minute','m']).drop_duplicates(['event_id','sel']))
con.close(); P=pd.concat(parts,ignore_index=True).merge(G,on='event_id'); print(f"games with a print {P.event_id.nunique()}, {time.time()-T0:.0f}s",flush=True)
P['lag']=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True)).dt.total_seconds()/60
bad=(P.lag<-5)|(P.lag>20); gm=P.fixture_id.map(first_goal); kn=gm.notna()&(gm<P.minute)
print(f"rows dropped, lag {int(bad.sum())}, goal known before the print {int(kn.sum())}",flush=True); P=P[~bad&~kn]
R=[];n_tie=0;n_one=0
for (e,fx,s,lid,ko,hg,ag),x in P.groupby(['event_id','fixture_id','season','league_id','kickoff','hg','ag']):
    pr=dict(zip(x.sel,x.ltp))
    if len(pr)<2: n_one+=1; continue
    sd=sides(pr['HOME'],pr['AWAY'])
    if sd is None: n_tie+=1; continue
    fav,dog=sd; res='HOME' if hg>ag else 'AWAY' if ag>hg else 'DRAW'
    d=pr[dog]; b=dog_band(d)
    if b:
        w=res==dog; lab=dog+'_DOG'; v=bk(d,w)
        if v is not None: R.append((207,lab,b,'BACK',s,fx,d,w,v))
        R.append((207,lab,b,'LAY',s,fx,d,w,ly(d,w)))
    f=pr[fav]; b=fav_band(f)
    if b and lid in UK:
        w=res==fav; lab='SAT1500' if sat1500(pd.Timestamp(ko).tz_convert('UTC')) else 'ELSE'; v=bk(f,w)
        if v is not None: R.append((208,lab,b,'BACK',s,fx,f,w,v))
        R.append((208,lab,b,'LAY',s,fx,f,w,ly(f,w)))
print(f"no pair {n_one}, ties {n_tie}",flush=True)
R=pd.DataFrame(R,columns='item state band side season fx x won v'.split()); assert not R.duplicated(['item','state','band','side','fx']).any(),"more than one bet per game per line"
out=[]
for k,x in R.groupby(['item','state','band','side']):
    l=line(x.v.values,np.where(x.season==2024,1,2)); out.append(dict(item=k[0],state=k[1],band=k[2],side=k[3],n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),implied=(1/x.x).mean(),maxwin=l['maxwin'],PASS=l['PASS']))
O=pd.DataFrame(out).sort_values('t',ascending=False)
print(f"\n== ITEM 207: {int((O.item==207).sum())} lines by t"); print(O[O.item==207].round(3).to_string(index=False))
print(f"\n== ITEM 208: SAT1500 lines, ELSE is the control and cannot pass"); print(O[O.item==208].round(3).to_string(index=False))
S=O[(O.PASS==True)&(O.state!='ELSE')]; print(f"\n== SURVIVORS: {len(S)} (bar: n>=300, n>=150 per half, both halves > 0, t>=3.5, mean>=+0.15, LTP upper bound)"); print(S.round(3).to_string(index=False) if len(S) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
