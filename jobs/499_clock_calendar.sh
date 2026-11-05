#!/bin/bash
set -o pipefail
# 499_clock_calendar (Finder 2026-11-05, queue item 127, Finder's own, source c): are kick-off hour, weekday, month and an unusual slot priced? Rule written in the queue before any price was read. The number 499 is reused with a new slug: 450-499 are all taken.
# TAPE af_fixtures, af_price_map, bf_hist_price, af_events. Read-only, local DB. Entry and guards as jobs/499_team_form_stage.sh: earliest real print in tape minutes 0..2, ltp >= 1.01; lag outside -5..+20 min v the af kick-off dropped, counted; a goal with af minute strictly before the print minute dropped, counted. One tick adverse, 2% commission, £10 risk, hold to FT. Halves are seasons 2024 v 2025. LTP only, so a pass is an upper bound.
# LIMIT hours are UTC, not local, so HOUR mixes countries; SLOT is the local-time-free cut.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,lay_settle,tstat,passes
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time()
def hour_state(h): return 'H<12' if h<12 else 'H12-14' if h<15 else 'H15-17' if h<18 else 'H18-19' if h<20 else 'H20+'
def dow_state(w): return {0:'D_MON',1:'D_TUE-THU',2:'D_TUE-THU',3:'D_TUE-THU',4:'D_FRI',5:'D_SAT',6:'D_SUN'}[w]
def month_state(m): return {8:'M_AUG-SEP',9:'M_AUG-SEP',10:'M_OCT-NOV',11:'M_OCT-NOV',12:'M_DEC-FEB',1:'M_DEC-FEB',2:'M_DEC-FEB',3:'M_MAR-MAY',4:'M_MAR-MAY',5:'M_MAR-MAY',6:'M_JUN-JUL',7:'M_JUN-JUL'}[m]
def hdist(a,b):
    d=abs(a-b)%24; return min(d,24-d)
def slot_state(h,mode):
    """h hour with fraction, mode the league's commonest hour last season, None if under 50 games then."""
    if mode is None: return None
    d=hdist(h,mode); return 'S_ODD3' if d>=3 else 'S_USUAL' if d<1 else None
def bk(x,won):
    a=step(x,-1); return None if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)
# known answers
assert [hour_state(h) for h in (0,11.99,12,14.5,15,17.9,18,19.5,20,23)]==['H<12','H<12','H12-14','H12-14','H15-17','H15-17','H18-19','H18-19','H20+','H20+']
assert dow_state(0)=='D_MON' and dow_state(2)=='D_TUE-THU' and dow_state(4)=='D_FRI' and dow_state(6)=='D_SUN' and month_state(1)=='M_DEC-FEB' and month_state(7)=='M_JUN-JUL' and month_state(10)=='M_OCT-NOV'
assert hdist(23,1)==2 and hdist(1,23)==2 and hdist(15,15)==0 and hdist(12,0)==12
assert slot_state(18,15)=='S_ODD3' and slot_state(17.5,15) is None and slot_state(15.5,15)=='S_USUAL' and slot_state(16,15) is None and slot_state(1,23) is None and slot_state(2,23)=='S_ODD3' and slot_state(15,None) is None
assert abs(bk(2.04,True)-9.996)<1e-9 and bk(2.04,False)==-10.0 and ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9 and bk(1.01,True) is None
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=pd.read_sql("SELECT league,season,kickoff FROM af_fixtures WHERE status='FT' AND kickoff IS NOT NULL AND season IN (2023,2024)",con)
F['hr']=pd.to_datetime(F.kickoff,utc=True).dt.hour; MODE={}
for (l,s),x in F.groupby(['league','season']):
    if len(x)>=50: MODE[(l,s)]=int(x.hr.mode().iloc[0])
print(f"league-seasons with a last-season mode: {len(MODE)}",flush=True)
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.league,f.season,f.kickoff,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.kickoff IS NOT NULL AND f.season IN (2024,2025)""",con)
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND coalesce(minute,0)<=2 GROUP BY 1",con,params=(list(map(int,G.fixture_id)),))
first_goal=dict(zip(EV.fixture_id,EV.gm)); parts=[]
for i in range(0,len(G),1000):
    P=pd.read_sql("SELECT event_id,mkt,sel,minute,m,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt IN ('MO','OU25') AND sel IN ('HOME','DRAW','AWAY','UNDER','OVER') AND minute>=0 AND minute<=2 AND ltp>=1.01 AND ltp<1000",con,params=(list(G.event_id.iloc[i:i+1000]),))
    parts.append(P.sort_values(['event_id','mkt','sel','minute','m']).drop_duplicates(['event_id','mkt','sel']))
con.close()
P=pd.concat(parts,ignore_index=True).merge(G,on='event_id')
P['lag']=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True)).dt.total_seconds()/60
bad=(P.lag<-5)|(P.lag>20); gm=P.fixture_id.map(first_goal); kn=gm.notna()&(gm<P.minute)
print(f"games with a print {P.event_id.nunique()}; rows dropped, lag {int(bad.sum())}, goal known before the print {int(kn.sum())}; {time.time()-T0:.0f}s",flush=True); P=P[~bad&~kn]
rows=[]; slotted=0; unslotted=0
for (e,lg,s,ko,hg,ag),x in P.groupby(['event_id','league','season','kickoff','hg','ag']):
    k=pd.to_datetime(ko,utc=True); hf=k.hour+k.minute/60; res='HOME' if hg>ag else 'AWAY' if ag>hg else 'DRAW'; over=hg+ag>2.5
    st=[hour_state(hf),dow_state(k.dayofweek),month_state(k.month),'ALL']
    sl=slot_state(hf,MODE.get((lg,s-1)))
    if (lg,s-1) in MODE: slotted+=1
    else: unslotted+=1
    if sl: st.append(sl)
    for sel,px in zip(x.sel,x.ltp):
        won=(sel==res) if sel in('HOME','DRAW','AWAY') else (over if sel=='OVER' else not over)
        b=bk(px,won); l=ly(px,won); h=1 if s==2024 else 2
        for z in st:
            if b is not None: rows.append((z,sel,'BACK',h,e,b,won,1/px))
            rows.append((z,sel,'LAY',h,e,l,won,1/px))
print(f"games with a slot mode {slotted}, without {unslotted}; rows {len(rows):,}",flush=True)
T=pd.DataFrame(rows,columns=['state','sel','side','h','g','v','won','imp']); out=[]
for k,x in T.groupby(['state','sel','side']):
    v=x.v.values; a=v[x.h.values==1]; b=v[x.h.values==2]; t=tstat(v)
    out.append(dict(state=k[0],sel=k[1],side=k[2],n=len(v),games=x.g.nunique(),per10=v.mean(),t=t,n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,won=x.won.mean(),imp=x.imp.mean(),
                    PASS=passes(len(v),len(a),len(b),t,a.mean() if len(a) else -1,b.mean() if len(b) else -1,v.mean())))
R=pd.DataFrame(out); C=R[R.state=='ALL']; R=R[R.state!='ALL'].sort_values('t',ascending=False)
print(f"lines tested {len(R)}; by chance about {len(R)*0.05:.0f} would reach t>=1.65",flush=True)
print("== control: every game, not counted as a line"); print(C.round(3).to_string(index=False))
print("== games per state"); print(T[(T.sel=='OVER')&(T.side=='LAY')].groupby('state').g.nunique().to_string())
print("== top 15 by t"); print(R.head(15).round(3).to_string(index=False))
print("== bottom 5 by t"); print(R.tail(5).round(3).to_string(index=False))
print("== SURVIVORS"); S=R[R.PASS]; print(S.round(3).to_string(index=False) if len(S) else "  none")
print(f"done {time.time()-T0:.0f}s")
PY
