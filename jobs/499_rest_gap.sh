#!/bin/bash
set -o pipefail
# 499_rest_gap (Finder 2026-11-04, queue item 77, Finder's own, source d): is a rest-day gap priced at the first real print? Rule written in the queue before any price was read. The number 499 is reused with a new slug: 450-499 are all taken.
# DATA af_fixtures (rest from every finished fixture on the box, 27 competitions including UEFA, not domestic cups, so some tired sides are missed), af_price_map, bf_hist_price, af_events.
# ENTRY and guards as jobs/499_league_goal_error.sh: earliest real print in tape minutes 0..2, ltp >= 1.01; lag outside -5..+20 min v the af kick-off dropped, counted; a goal with af minute strictly before the print minute dropped. One tick adverse, 2% commission, £10 risk, hold to FT.
# REST days since the team's previous finished fixture, gap over 14 days = unknown (season start, break). Games on the same kick-off time are not history.
# MATCH ODDS gap >= 2/3/4 days, tired side on <= 4 days: BACK rested, LAY tired, and BACK tired as the control, also split by rested side home or away.
# OVER/UNDER 2.5: both on <= 3 days, against both on >= 5 as a control: back and lay each side. Halves are seasons 2024 v 2025. LTP only, so a pass is an upper bound.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks()
pd.set_option('display.width',260); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time()
def rests(fx):
    """fx: list of (fixture_id,kickoff_seconds,home,away). Returns {fixture_id:(rest_home,rest_away)} in days; None if no earlier game or the gap is over 14 days. Fixtures at the same kick-off are not history for each other."""
    last={}; out={}; fx=sorted(fx,key=lambda z:z[1]); i=0
    while i<len(fx):
        j=i
        while j<len(fx) and fx[j][1]==fx[i][1]: j+=1
        for f,k,h,a in fx[i:j]:
            r=[(k-last[t])/86400 if t in last else None for t in (h,a)]
            out[f]=tuple(None if (v is None or v>14) else v for v in r)
        for f,k,h,a in fx[i:j]: last[h]=k; last[a]=k
        i=j
    return out
def rested(rh,ra,gap,tired_max=4):
    """'H' if home is the rested side at this gap and the tired side has <= tired_max days; 'A' the mirror; else None."""
    if rh is None or ra is None: return None
    if rh-ra>=gap and ra<=tired_max: return 'H'
    if ra-rh>=gap and rh<=tired_max: return 'A'
    return None
def bk(x,won):
    a=step(x,-1); return None if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)
D=86400
_r=rests([(1,0,'A','B'),(2,3*D,'A','C'),(3,3*D,'B','D'),(4,6*D,'A','B'),(5,30*D,'A','B')])
assert _r[1]==(None,None) and _r[2]==(3.0,None) and _r[3]==(3.0,None) and _r[4]==(3.0,3.0) and _r[5]==(None,None)
assert rests([(1,0,'A','B'),(2,0,'A','C')])[2]==(None,None)    # same kick-off is not history
assert rested(7.,3.,3)=='H' and rested(3.,7.,3)=='A' and rested(7.,5.,2) is None and rested(5.,3.,3) is None and rested(None,3.,2) is None and rested(6.,4.,2)=='H'
assert abs(bk(2.04,True)-9.996)<1e-9 and bk(2.04,False)==-10.0 and ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=pd.read_sql("SELECT fixture_id,kickoff,home,away,season FROM af_fixtures WHERE status='FT' AND kickoff IS NOT NULL AND season>=2023",con)
F['ks']=pd.to_datetime(F.kickoff,utc=True).map(lambda t:int(t.timestamp()))
assert F.ks.between(1.6e9,1.9e9).all(),"kick-off seconds out of range"
RS=rests(list(zip(F.fixture_id,F.ks,F.home,F.away))); print(f"fixtures {len(F)}, rest known both sides {sum(1 for v in RS.values() if v[0] is not None and v[1] is not None)}",flush=True)
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.league,f.season,f.kickoff,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.season IN (2024,2025)""",con)
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND coalesce(minute,0)<=2 GROUP BY 1",con,params=(list(map(int,G.fixture_id)),))
first_goal=dict(zip(EV.fixture_id,EV.gm)); parts=[]
for i in range(0,len(G),1000):
    P=pd.read_sql("SELECT event_id,mkt,sel,minute,m,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt IN ('MO','OU25') AND sel IN ('HOME','DRAW','AWAY','UNDER','OVER') AND minute>=0 AND minute<=2 AND ltp>=1.01 AND ltp<1000",con,params=(list(G.event_id.iloc[i:i+1000]),))
    parts.append(P.sort_values(['event_id','mkt','sel','minute','m']).drop_duplicates(['event_id','mkt','sel']))
    print(f"  {min(i+1000,len(G))}/{len(G)} {time.time()-T0:.0f}s",flush=True)
con.close()
P=pd.concat(parts,ignore_index=True).merge(G,on='event_id')
P['lag']=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True)).dt.total_seconds()/60
bad=(P.lag<-5)|(P.lag>20); gm=P.fixture_id.map(first_goal); kn=gm.notna()&(gm<P.minute)
print(f"games with a print {P.event_id.nunique()}; rows dropped, lag {int(bad.sum())}, goal known before the print {int(kn.sum())}",flush=True); P=P[~bad&~kn]
rows=[]
for (e,fx,lg,s,hg,ag),x in P.groupby(['event_id','fixture_id','league','season','hg','ag']):
    rh,ra=RS.get(fx,(None,None))
    if rh is None or ra is None: continue
    pr={(a,b):c for a,b,c in zip(x.mkt,x.sel,x.ltp)}; res='HOME' if hg>ag else 'AWAY' if ag>hg else 'DRAW'; over=hg+ag>2.5
    for gap in (2,3,4):
        w=rested(rh,ra,gap)
        if w is None: continue
        rs,ti=('HOME','AWAY') if w=='H' else ('AWAY','HOME')
        if ('MO',rs) in pr:
            v=bk(pr[('MO',rs)],res==rs)
            if v is not None: rows.append(('MO',f'gap{gap}','BACK_RESTED',w,s,fx,lg,pr[('MO',rs)],res==rs,v))
        if ('MO',ti) in pr:
            rows.append(('MO',f'gap{gap}','LAY_TIRED',w,s,fx,lg,pr[('MO',ti)],res==ti,ly(pr[('MO',ti)],res==ti)))
            v=bk(pr[('MO',ti)],res==ti)
            if v is not None: rows.append(('MO',f'gap{gap}','CTRL_BACK_TIRED',w,s,fx,lg,pr[('MO',ti)],res==ti,v))
    st='both<=3' if max(rh,ra)<=3 else 'both>=5' if min(rh,ra)>=5 else None
    if st:
        for sel,won in (('OVER',over),('UNDER',not over)):
            if ('OU25',sel) in pr:
                p=pr[('OU25',sel)]; v=bk(p,won)
                if v is not None: rows.append(('OU25',st,'BACK_'+sel,'-',s,fx,lg,p,won,v))
                rows.append(('OU25',st,'LAY_'+sel,'-',s,fx,lg,p,won,ly(p,won)))
R=pd.DataFrame(rows,columns=['mkt','state','line','rested','season','fixture','league','x','won','v']); print(f"trades {len(R)} games {R.fixture.nunique()} {time.time()-T0:.0f}s",flush=True)
assert not R.duplicated(['fixture','mkt','state','line']).any(),"more than one entry per game per line"
def tb(k,x,names):
    h=np.where(x.season==2024,1,2); l=line(x.v.values,h); return dict(zip(names,k),n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),imp=(1/x.x).mean(),maxwin=l['maxwin'],PASS=l['PASS'])
o=[tb(k+('ALL',),x,['mkt','state','line','rested']) for k,x in R.groupby(['mkt','state','line'])]
o+=[tb(k,x,['mkt','state','line','rested']) for k,x in R[R.mkt=='MO'].groupby(['mkt','state','line','rested'])]
O=pd.DataFrame(o); print("\n== every line"); print(O.sort_values(['mkt','state','line','rested']).round(3).to_string(index=False))
print("\n== SURVIVORS (bar: n>=300, n>=150 per half, both halves > 0, t>=3.5, mean>=+0.15, LTP upper bound)"); S=O[O.PASS]; print(S.round(3).to_string(index=False) if len(S) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
