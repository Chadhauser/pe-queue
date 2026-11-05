#!/bin/bash
set -o pipefail
# 499_new_division (Finder 2026-11-05, queue items 96-99, Finder's own, sources c and d): four states known before kick-off, read at the first real in-play print. Rules written in the queue before any price was read.
# 96 promoted/relegated, 97 red card last game, 98 stand-alone game v the pack, 99 xG luck over the last 5. The number 499 is reused with a new name, 450-499 being full.
# DATA af_fixtures, af_events, af_stats, af_price_map, bf_hist_price (MO, OU25). History from season 2023, trades on 2024 and 2025. League identity is league_id, as "Serie A" and "Premiership" name more than one league.
# ENTRY and guards as jobs/499_rest_gap.sh: earliest real print in tape minutes 0..2; lag outside -5..+20 min v the af kick-off dropped, counted; a goal before the print minute dropped, counted. One tick adverse, 2%, £10 risk, hold to FT so nothing can settle before the exit. One entry per game per line. LTP only, so a pass is an upper bound.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks()
pd.set_option('display.width',260); pd.set_option('display.max_rows',500); pd.set_option('display.max_columns',40)
T0=time.time()
LADDERS=[[39,40,41,42],[140,141],[135,136],[78,79],[61,62]]
TOP5={39,140,135,78,61}
DOMESTIC_EXCL={2,3}

def division_state(team,lid,season,members):
    """members: {(league_id,season):set(teams)}. 'PROM', 'RELEG' or None for a team in ladder league lid in this season."""
    lad=next((l for l in LADDERS if lid in l),None)
    if lad is None or (lid,season-1) not in members or team in members[(lid,season-1)]: return None
    for up in lad[:lad.index(lid)]:
        if team in members.get((up,season-1),set()): return 'RELEG'
    return 'PROM'
# German clubs change spelling between 2023 and 2024 on af_fixtures, which reads as promotion unless mapped. Listed by hand from the table's new and gone names.
ALIAS={'Bayern Munich':'Bayern München','Borussia Monchengladbach':'Borussia Mönchengladbach','FC Heidenheim':'1. FC Heidenheim','Vfl Bochum':'VfL Bochum','FC Kaiserslautern':'1. FC Kaiserslautern','FC Magdeburg':'1. FC Magdeburg','FC Nurnberg':'1. FC Nürnberg','Fortuna Dusseldorf':'Fortuna Düsseldorf','Hertha Berlin':'Hertha BSC','SpVgg Greuther Furth':'SpVgg Greuther Fürth','Jahn Regensburg':'SSV Jahn Regensburg'}
def build_members(lid,season,home,away,min_games=20):
    """{(league_id,season):set(teams)}, a team needing min_games there, so a play-off tie is not membership. 2023 names mapped to 2024 spelling."""
    c={}
    for l,s,h,a in zip(lid,season,home,away):
        for t in (h,a):
            k=(l,s,ALIAS.get(t,t) if s<=2023 else t); c[k]=c.get(k,0)+1
    m={}
    for (l,s,t),n in c.items():
        m.setdefault((l,s),set())
        if n>=min_games: m[(l,s)].add(t)
    return m
def windows(n):
    """n = the team's game number in that league-season, 1-based."""
    return [w for w,ok in (('G5',n<=5),('G10',n<=10),('LATE',n>=20)) if ok]
def others_near(ks,lids):
    """Same-league games within 90 minutes either side, not counting the game itself."""
    ks=np.asarray(ks); lids=np.asarray(lids); out=np.zeros(len(ks),dtype=int)
    for l in np.unique(lids):
        ix=np.where(lids==l)[0]; s=np.sort(ks[ix])
        out[ix]=np.searchsorted(s,ks[ix]+5400,side='right')-np.searchsorted(s,ks[ix]-5400,side='left')-1
    return out
def luck(hist):
    """hist: list of (gd,xgd,goals,xg) for up to 5 earlier games, oldest first. (L,T), None unless 5 are held."""
    if len(hist)<5: return None
    h=np.array(hist[-5:],dtype=float); return float((h[:,0]-h[:,1]).mean()),float((h[:,2]-h[:,3]).mean())
def bk(x,won):
    a=step(x,-1); return None if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)

# known answers, worked by hand
_m={(40,2023):{'A','B'},(39,2023):{'C'},(41,2023):{'D'},(40,2024):{'A','C','D','E'}}
assert division_state('A',40,2024,_m) is None and division_state('C',40,2024,_m)=='RELEG' and division_state('D',40,2024,_m)=='PROM' and division_state('E',40,2024,_m)=='PROM'
assert division_state('X',253,2024,_m) is None and division_state('A',40,2023,_m) is None    # no ladder; no previous season on the box
_bm=build_members([1]*22+[1]*2,[2023]*22+[2024]*2,['Bayern Munich']*11+['X']*11+['Bayern München','Y'],['X']*11+['Bayern Munich']*11+['Y','Bayern München'])
assert _bm[(1,2023)]=={'Bayern München','X'} and _bm[(1,2024)]==set()    # spelling mapped; 2 games in 2024 is not membership
assert windows(1)==['G5','G10'] and windows(6)==['G10'] and windows(11)==[] and windows(20)==['LATE']
assert list(others_near([0,5400,5401,0],[1,1,1,2]))==[1,2,1,0]
assert luck([(1,0,1,1)]*4) is None
_l=luck([(9,9,9,9)]+[(2,1,3,2),(0,1,1,2),(1,0,3,1),(-1,0,1,2),(3,1,5,3)]); assert abs(_l[0]-0.4)<1e-9 and abs(_l[1]-0.6)<1e-9    # L (1-1+1-1+2)/5, T (1-1+2-1+2)/5
assert abs(bk(2.04,True)-9.996)<1e-9 and bk(2.04,False)==-10.0 and ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9
print("checks: OK",flush=True)

con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=pd.read_sql("SELECT fixture_id,league_id,league,season,kickoff,home,away,hg,ag FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND ag IS NOT NULL AND kickoff IS NOT NULL AND season>=2023 AND league_id NOT IN (2,3)",con)
F['ks']=pd.to_datetime(F.kickoff,utc=True).map(lambda t:int(t.timestamp()))
assert F.ks.between(1.6e9,1.9e9).all(),"kick-off seconds out of range"
F=F.sort_values(['ks','fixture_id']).reset_index(drop=True)
members=build_members(F.league_id.values,F.season.values,F.home.values,F.away.values)
# known answers from the real tables: English and Spanish promotions, relegations, and the 2024 German and French cases this job first got wrong
_new=lambda l,s:{t for t in members[(l,s)] if division_state(t,l,s,members)=='PROM'}
_rel=lambda l,s:{t for t in members[(l,s)] if division_state(t,l,s,members)=='RELEG'}
assert _new(39,2024)=={'Ipswich','Leicester','Southampton'} and _new(39,2025)=={'Burnley','Leeds','Sunderland'} and _new(140,2024)=={'Espanyol','Leganes','Valladolid'}
assert _rel(40,2024)=={'Burnley','Luton','Sheffield Utd'} and _new(40,2024)=={'Derby','Oxford United','Portsmouth'}
assert _new(78,2024)=={'FC St. Pauli','Holstein Kiel'} and _new(78,2025)=={'1. FC Köln','Hamburger SV'}, _new(78,2024)
assert _rel(79,2024)=={'1. FC Köln','SV Darmstadt 98'} and 'Saint Etienne' in _new(61,2024) and 'Metz' in _new(61,2025) and 'SV Elversberg' not in members[(78,2024)]
print("real-table checks: OK",{k:len(_new(*k)) for k in ((39,2024),(78,2024),(79,2024),(61,2024),(61,2025))},flush=True)
F['near']=others_near(F.ks.values,F.league_id.values)
F['dow']=pd.to_datetime(F.kickoff,utc=True).dt.tz_convert('Europe/London').dt.dayofweek
RED=pd.read_sql("SELECT fixture_id,is_home,min(coalesce(minute,0)) rm FROM af_events WHERE type='Card' AND detail='Red Card' AND is_home IS NOT NULL GROUP BY 1,2",con)
red={(int(a),bool(b)):int(c) for a,b,c in zip(RED.fixture_id,RED.is_home,RED.rm)}
XG=pd.read_sql("SELECT fixture_id,is_home,xg::float xg FROM af_stats WHERE xg IS NOT NULL",con)
xg={(int(a),bool(b)):float(c) for a,b,c in zip(XG.fixture_id,XG.is_home,XG.xg)}
print(f"fixtures {len(F)}, red rows {len(red)}, xg rows {len(xg)}, {time.time()-T0:.0f}s",flush=True)

# walk forward: every state uses only games with an earlier kick-off, and games at the same kick-off are not history
played={}; last={}; xh={}; ST={}; i=0; rec=list(F.itertuples(index=False))
while i<len(rec):
    j=i
    while j<len(rec) and rec[j].ks==rec[i].ks: j+=1
    for r in rec[i:j]:
        d={}
        for side,t in (('H',r.home),('A',r.away)):
            k=(t,r.league_id,r.season); played[k]=played.get(k,0)+1
            prev=last.get((t,r.league_id)); rs=None
            if prev is not None and r.ks-prev['ks']<=14*86400: rs=prev
            hist=[z[1] for z in xh.get((t,r.league_id),[]) if r.ks-z[0]<=120*86400]
            d[side]=dict(team=t,no=played[k],div=division_state(t,r.league_id,r.season,members),red=rs,luck=luck(hist))
        ST[r.fixture_id]=d
    for r in rec[i:j]:
        rh,ra=red.get((r.fixture_id,True)),red.get((r.fixture_id,False))
        last[(r.home,r.league_id)]=dict(ks=r.ks,rm=rh,lost=r.hg<r.ag); last[(r.away,r.league_id)]=dict(ks=r.ks,rm=ra,lost=r.ag<r.hg)
        xa,xb=xg.get((r.fixture_id,True)),xg.get((r.fixture_id,False))
        if xa is not None and xb is not None:
            tot=r.hg+r.ag
            xh.setdefault((r.home,r.league_id),[]).append((r.ks,(r.hg-r.ag,xa-xb,tot,xa+xb)))
            xh.setdefault((r.away,r.league_id),[]).append((r.ks,(r.ag-r.hg,xb-xa,tot,xa+xb)))
        else:   # a game with no xg breaks the run of 5, so the team's window restarts
            xh[(r.home,r.league_id)]=[]; xh[(r.away,r.league_id)]=[]
    i=j

G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.league_id,f.season,f.kickoff,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.season IN (2024,2025) AND f.league_id NOT IN (2,3)""",con)
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

near=dict(zip(F.fixture_id,F.near)); dow=dict(zip(F.fixture_id,F.dow)); rows=[]
def add(item,state,leg,side,s,fx,lg,x,won):
    v=bk(x,won) if side=='BACK' else ly(x,won)
    if v is not None: rows.append((item,state,leg,side,s,fx,lg,x,won,v))
def team_legs(item,state,side,pr,res,s,fx,lg):
    me,op=('HOME','AWAY') if side=='H' else ('AWAY','HOME')
    for leg,sel in (('team',me),('opp',op)):
        if ('MO',sel) in pr:
            for b in ('BACK','LAY'): add(item,state,leg,b,s,fx,lg,pr[('MO',sel)],res==sel)
def goal_legs(item,state,pr,over,s,fx,lg):
    for sel,won in (('OVER',over),('UNDER',not over)):
        if ('OU25',sel) in pr:
            for b in ('BACK','LAY'): add(item,state,sel,b,s,fx,lg,pr[('OU25',sel)],won)
n_gm=0
for (e,fx,lg,s,hg,ag),x in P.groupby(['event_id','fixture_id','league_id','season','hg','ag']):
    d=ST.get(fx)
    if d is None: continue
    n_gm+=1
    pr={(a,b):c for a,b,c in zip(x.mkt,x.sel,x.ltp)}; res='HOME' if hg>ag else 'AWAY' if ag>hg else 'DRAW'; over=hg+ag>2.5
    # item 96
    for side,o in (('H','A'),('A','H')):
        a,b=d[side],d[o]
        if a['div'] and a['div']!=b['div']:
            for w in windows(a['no']):
                st=f"{a['div']}_{w}"; team_legs(96,st,side,pr,res,s,fx,lg); goal_legs(96,st,pr,over,s,fx,lg)
    # item 97
    for side,o in (('H','A'),('A','H')):
        a,b=d[side]['red'],d[o]['red']
        if a and a['rm'] is not None and not (b and b['rm'] is not None):
            sts=['RED']+(['RED_LOST'] if a['lost'] else [])+(['RED_EARLY'] if a['rm']<=45 else [])
            for st in sts: team_legs(97,st,side,pr,res,s,fx,lg); goal_legs(97,st,pr,over,s,fx,lg)
    # item 98
    sts=[]
    if near[fx]==0: sts+=['SOLO']+(['SOLO_TOP5'] if lg in TOP5 else [])
    if near[fx]>=3: sts+=['PACK']+(['PACK_TOP5'] if lg in TOP5 else [])
    if dow[fx]==4: sts.append('FRI')
    if dow[fx]==0: sts.append('MON')
    mo={k[1]:v for k,v in pr.items() if k[0]=='MO'}
    for st in sts:
        for sel in mo:
            for b in ('BACK','LAY'): add(98,st,sel,b,s,fx,lg,mo[sel],res==sel)
        if len(mo)==3:
            fav=min(mo,key=mo.get)
            for b in ('BACK','LAY'): add(98,st,'FAV',b,s,fx,lg,mo[fav],res==fav)
        goal_legs(98,st,pr,over,s,fx,lg)
    # item 99
    lh,la=d['H']['luck'],d['A']['luck']
    if lh and la:
        for side,me,op in (('H',lh,la),('A',la,lh)):
            for cut in (0.5,1.0):
                if me[0]<=-cut and op[0]>me[0]: team_legs(99,f'DUE_{cut}',side,pr,res,s,fx,lg)
                if me[0]>=cut and op[0]<me[0]: team_legs(99,f'HOT_{cut}',side,pr,res,s,fx,lg)
        T=(lh[1]+la[1])/2
        if T>=0.5: goal_legs(99,'ROAR',pr,over,s,fx,lg)
        if T<=-0.5: goal_legs(99,'QUIET',pr,over,s,fx,lg)
        goal_legs(99,'XG_ALL_CTRL',pr,over,s,fx,lg)
R=pd.DataFrame(rows,columns=['item','state','leg','side','season','fixture','league','x','won','v']); print(f"games in {n_gm}; trades {len(R)} games {R.fixture.nunique()} {time.time()-T0:.0f}s",flush=True)
# the RED guard allows one team per game, so a repeat on a line means the guard failed
dupe=R[R.state.isin(['RED','RED_LOST','RED_EARLY'])].duplicated(['fixture','state','leg','side']).sum()
print("duplicates in RED lines (must be 0):",int(dupe),flush=True); assert dupe==0
def tb(k,x):
    h=np.where(x.season==2024,1,2); l=line(x.v.values,h)
    # t by game as well as by trade: the bar asks for both
    byg=x.groupby('fixture').v.sum();
    return dict(item=k[0],state=k[1],leg=k[2],side=k[3],n=l['n'],games=x.fixture.nunique(),per10=l['per10'],t=l['t'],t_game=tstat(byg.values),n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),imp=(1/x.x).mean(),maxwin=l['maxwin'],PASS=l['PASS'] and tstat(byg.values)>=3.5)
O=pd.DataFrame([tb(k,x) for k,x in R.groupby(['item','state','leg','side'])])
for it,x in O.groupby('item'):
    big=x[x.n>=300]
    print(f"\n== item {it}: lines {len(x)}, n>=300 {len(big)}, positive there {int((big.per10>0).sum())}, pass {int(x.PASS.sum())}. Top 15 by t, n>=150"); print(x[x.n>=150].sort_values('t',ascending=False).head(15).round(3).to_string(index=False))
    print("worst 4"); print(x[x.n>=150].sort_values('t').head(4).round(3).to_string(index=False))
print("\n== every line"); print(O.sort_values(['item','state','leg','side']).round(3).to_string(index=False))
print("\n== SURVIVORS (bar: n>=300, n>=150 per half, both halves > 0, t and t by game >= 3.5, mean >= +0.15, LTP upper bound)"); S=O[O.PASS]; print(S.round(3).to_string(index=False) if len(S) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
