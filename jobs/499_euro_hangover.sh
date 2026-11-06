#!/bin/bash
set -o pipefail
# 499_euro_hangover (Finder 2026-11-06, queue item 188, Finder's own, source c): domestic game just after, or just before, a UEFA game. Rule pushed before prices were read (commit 91a70c9). The number 499 is reused: 450-499 are all taken.
# STATE from af_fixtures, every finished fixture: AFTER previous fixture UEFA within 4 days; AFTER_AWAY the same and away in it; BEFORE next fixture UEFA within 4 days. Both teams in a state = out of that state. Conference League and domestic cups are not on the box, so a side fresh from one counts as neither.
# LOOK-AHEAD the next UEFA game of a side is on the fixture list before the domestic game, except a knockout draw that depends on a tie not yet finished; a tie's result is decided in UEFA games, not domestic ones, so a domestic result does not select a BEFORE state.
# ENTRY and guards as jobs/499_rest_gap.sh: earliest real print tape minutes 0..2; lag outside -5..+20 min dropped; a goal with af minute before the print minute dropped. One tick adverse, 2%, £10 risk, hold to FT. Halves seasons 2024 v 2025. LTP only, so a pass is an upper bound.
# CONTROL t_v v the same line on domestic games of sides with a UEFA fixture that season, in neither state. A control game with two such sides gives two team rows, one game row.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,lay_settle,line
pd.set_option('display.width',240); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',30)
T0=time.time(); D=86400; UEFA=('UEFA Champions League','UEFA Europa League')
def bk(x,won):
    a=step(x,-1); return None if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)
def states(rows,days=4):
    """rows: (fixture,seconds,home,away,is_uefa). {(fixture,team):set of states} for domestic games only."""
    by={}
    for f,t,h,a,u in rows:
        by.setdefault(h,[]).append((t,f,u,True)); by.setdefault(a,[]).append((t,f,u,False))
    out={}
    for team,s in by.items():
        s.sort(key=lambda z:z[0])
        for i,(t,f,u,home) in enumerate(s):
            if u: continue
            st=set()
            if i>0 and s[i-1][2] and t-s[i-1][0]<=days*D:
                st.add('AFTER')
                if not s[i-1][3]: st.add('AFTER_AWAY')
            if i+1<len(s) and s[i+1][2] and s[i+1][0]-t<=days*D: st.add('BEFORE')
            out[(f,team)]=st
    return out
def game_state(sh,sa,st):
    """Which team a state belongs to in a game: 'H', 'A', or None if neither or both."""
    h,a=st in sh,st in sa
    return 'H' if h and not a else 'A' if a and not h else None
def welch(a,b):
    a,b=np.asarray(a,float),np.asarray(b,float)
    if len(a)<2 or len(b)<2: return 0.0
    return float((a.mean()-b.mean())/(a.var(ddof=1)/len(a)+b.var(ddof=1)/len(b))**0.5)
# known answers, worked by hand
_x=[(1,0,'A','X',True),(2,3*D,'A','B',False),(3,6*D,'B','A',True),(4,12*D,'A','C',False),(5,14*D,'C','A',True),(6,20*D,'A','D',False)]
_s=states(_x)
assert _s[(2,'A')]=={'AFTER','BEFORE'}                        # home in UEFA 3 days before, UEFA 3 days after; not away in game 1
assert _s[(4,'A')]=={'BEFORE'}                                # game 3 is 6 days earlier, game 5 is 2 days later
assert _s[(6,'A')]==set()                                     # game 5 is 6 days earlier, nothing after
assert _s[(2,'B')]=={'BEFORE'} and (1,'A') not in _s           # B has UEFA 3 days later; a UEFA game itself has no state
_y=[(1,0,'P','A',True),(2,4*D,'A','B',False),(3,5*D-1+D,'B','A',False)]
assert states(_y)[(2,'A')]=={'AFTER','AFTER_AWAY'}            # away in UEFA, exactly 4 days counts
assert states(_y)[(3,'A')]==set()                             # previous fixture is domestic
assert game_state({'AFTER'},set(),'AFTER')=='H' and game_state(set(),{'AFTER'},'AFTER')=='A' and game_state({'AFTER'},{'AFTER'},'AFTER') is None and game_state(set(),set(),'AFTER') is None
assert abs(welch([1,3],[0,2])-1.0/(2/2+2/2)**0.5)<1e-12
assert abs(bk(2.04,True)-9.996)<1e-9 and bk(2.04,False)==-10.0 and ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=pd.read_sql("SELECT fixture_id,kickoff,home,away,league,season,status FROM af_fixtures WHERE kickoff IS NOT NULL AND season>=2023 AND status IN ('FT','AET','PEN')",con)
F['ks']=pd.to_datetime(F.kickoff,utc=True).map(lambda t:int(t.timestamp())); F['u']=F.league.isin(UEFA)
print(f"fixtures {len(F)}, UEFA {int(F.u.sum())}, by status {F.status.value_counts().to_dict()}",flush=True)
DAYS=int(sys.argv[1]) if len(sys.argv)>1 else 4   # item 192 runs this job at 5; no argument is item 188's rule
ST=states(list(zip(F.fixture_id,F.ks,F.home,F.away,F.u)),DAYS); print("days",DAYS,flush=True)
print("team-game states",pd.Series([x for v in ST.values() for x in v]).value_counts().to_dict(),flush=True)
UT={(int(s),t) for s,x in F[F.u].groupby('season') for t in set(x.home)|set(x.away)}
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.league,f.season,f.kickoff,f.home,f.away,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.season IN (2024,2025) AND f.league NOT LIKE 'UEFA%%'""",con)
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND coalesce(minute,0)<=2 GROUP BY 1",con,params=(list(map(int,G.fixture_id)),))
first_goal=dict(zip(EV.fixture_id,EV.gm)); parts=[]
for i in range(0,len(G),1000):
    P=pd.read_sql("SELECT event_id,mkt,sel,minute,m,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt IN ('MO','OU25') AND sel IN ('HOME','AWAY','OVER') AND minute>=0 AND minute<=2 AND ltp>=1.01 AND ltp<1000",con,params=(list(G.event_id.iloc[i:i+1000]),))
    parts.append(P.sort_values(['event_id','mkt','sel','minute','m']).drop_duplicates(['event_id','mkt','sel']))
    print(f"  {min(i+1000,len(G))}/{len(G)} {time.time()-T0:.0f}s",flush=True)
con.close(); P=pd.concat(parts,ignore_index=True).merge(G,on='event_id')
P['lag']=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True)).dt.total_seconds()/60
bad=(P.lag<-5)|(P.lag>20); gm=P.fixture_id.map(first_goal); kn=gm.notna()&(gm<P.minute)
print(f"games with a print {P.event_id.nunique()}; rows dropped, lag {int(bad.sum())}, goal known before the print {int(kn.sum())}",flush=True); P=P[~bad&~kn]
rows=[];ctrl=[]
for (e,fx,s,h,a,hg,ag),x in P.groupby(['event_id','fixture_id','season','home','away','hg','ag']):
    pr={(m,t):v for m,t,v in zip(x.mkt,x.sel,x.ltp)}; sh=ST.get((fx,h),set()); sa=ST.get((fx,a),set()); res='HOME' if hg>ag else 'AWAY' if ag>hg else 'DRAW'; over=hg+ag>2.5
    def team(sel,tag,st,ven,bucket):
        if ('MO',sel) not in pr: return
        p=pr[('MO',sel)]; won=res==sel; v=bk(p,won)
        for ve in ('ALL',ven):
            if v is not None: bucket.append(('TEAM',st,ve,'BACK',s,fx,tag,p,won,v))
            bucket.append(('TEAM',st,ve,'LAY',s,fx,tag,p,won,ly(p,won)))
    def game(st,bucket):
        if ('OU25','OVER') not in pr: return
        p=pr[('OU25','OVER')]; v=bk(p,over)
        if v is not None: bucket.append(('OVER',st,'ALL','BACK',s,fx,'-',p,over,v))
        bucket.append(('OVER',st,'ALL','LAY',s,fx,'-',p,over,ly(p,over)))
    for st in ('AFTER','AFTER_AWAY','BEFORE'):
        w=game_state(sh,sa,st)
        if w=='H': team('HOME',h,st,'HOME',rows)
        if w=='A': team('AWAY',a,st,'AWAY',rows)
        if w: game(st,rows)
    cn=False
    if (int(s),h) in UT and not sh: team('HOME',h,'CTRL','HOME',ctrl); cn=True
    if (int(s),a) in UT and not sa: team('AWAY',a,'CTRL','AWAY',ctrl); cn=True
    if cn: game('CTRL',ctrl)
C='kind state venue side season fx team x won v'.split()
R=pd.DataFrame(rows,columns=C); K=pd.DataFrame(ctrl,columns=C); assert not R.duplicated(['kind','state','venue','side','fx']).any(),"more than one bet per game per line"
print(f"trades {len(R)} games {R.fx.nunique()}; control rows {len(K)} {time.time()-T0:.0f}s",flush=True)
out=[]
for k,x in K.groupby(['kind','venue','side']):
    l=line(x.v.values,np.where(x.season==2024,1,2)); out.append(dict(kind=k[0],venue=k[1],side=k[2],n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2']))
print("\n== control, sides with a UEFA fixture that season, neither state, not counted"); print(pd.DataFrame(out).round(3).to_string(index=False))
out=[]
for k,x in R.groupby(['kind','state','venue','side']):
    l=line(x.v.values,np.where(x.season==2024,1,2)); c=K[(K.kind==k[0])&(K.venue==k[2])&(K.side==k[3])].v.values
    out.append(dict(kind=k[0],state=k[1],venue=k[2],side=k[3],n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],won=x.won.mean(),implied=(1/x.x).mean(),t_v=welch(x.v.values,c),maxwin=l['maxwin'],PASS=l['PASS']))
O=pd.DataFrame(out).sort_values('t',ascending=False); print(f"\n== ALL {len(O)} LINES, per £10, by t"); print(O.round(3).to_string(index=False))
S=O[O.PASS]; print("\n== SURVIVORS (bar: n>=300, n>=150 per half, both halves > 0, t>=3.5, mean>=+0.15, LTP upper bound)"); print(S.round(3).to_string(index=False) if len(S) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
