#!/bin/bash
set -o pipefail
# 499_dead_rubber (Finder 2026-11-05, queue item 88, Finder's own, source c): is what a team has left to play for priced? Rule written in the queue before any price was read. Entry and guards from jobs/499_team_form_stage.sh. The number 499 is reused with a new slug: 450-499 are all taken.
# TAPE af_fixtures (finished, seasons 2024, 2025), af_price_map, bf_hist_price, af_events. Earliest real print in tape minutes 0..2, ltp >= 1.01; lag outside -5..+20 min v the af kick-off dropped, counted; a goal with af minute strictly before the print minute dropped. One tick adverse, 2% commission, £10 risk, hold to FT. LTP only, so a pass is an upper bound.
# TABLE from finished games before kick-off, 3 points a win, goal difference ignored. Games at the same time are not history for each other. 20+ games a team, 10+ teams; normal length = the mode of team game counts; a game past it (play-off) is dropped; R = games left including this one, R <= 5.
# LIMIT the 6th place and 3rd-from-bottom lines are a generic stand-in for each league's real European and relegation places; split-season leagues (Apertura, Clausura) under one league-season key have a false table. Read a near miss with that in mind.
# PROXY fd_matches Betfair closes (BFEC), 2024-25 onwards, book 0.98-1.04, halves by date median: it can contradict a tape line, it cannot pass one.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time()
def classify(pts,R,table):
    """pts team's points, R games left including today, table: all teams' points. Returns a set of states."""
    t=sorted(table,reverse=True); n=len(t); p1,p6,pb=t[0],t[5],t[n-3]; s=set()
    if pts+3*R<pb: s.add('DOOMED'); return s
    if pts+3*R<p6 and pts>pb+3*R: s.add('DEAD')
    if abs(pts-pb)<=3: s.add('FIGHT')
    if p1-pts<=3: s.add('TITLE')
    return s
def build(fx):
    """fx: (id,seconds,home,away,hg,ag,lg). {id:(home states, away states, R)} for league games, last 5 rounds."""
    by=defaultdict(list)
    for r in fx: by[r[6]].append(r)
    out={}; skip=Counter()
    for lg,g in by.items():
        c=Counter()
        for r in g: c[r[2]]+=1; c[r[3]]+=1
        if len(c)<10: skip['few_teams']+=1; continue
        L=Counter(c.values()).most_common(1)[0][0]
        if L<20: skip['short']+=1; continue
        g=sorted(g,key=lambda z:z[1]); pts=defaultdict(int); pl=defaultdict(int); i=0
        while i<len(g):
            j=i
            while j<len(g) and g[j][1]==g[i][1]: j+=1
            for f,k,h,a,hg,ag,_ in g[i:j]:
                Rh,Ra=L-pl[h],L-pl[a]
                if Rh<=0 or Ra<=0: skip['past_length']+=1; continue
                if Rh>5 or Ra>5: continue
                tb=[pts[t] for t in c]
                out[f]=(classify(pts[h],Rh,tb),classify(pts[a],Ra,tb),max(Rh,Ra))
            for f,k,h,a,hg,ag,_ in g[i:j]:
                pl[h]+=1; pl[a]+=1
                if hg>ag: pts[h]+=3
                elif ag>hg: pts[a]+=3
                else: pts[h]+=1; pts[a]+=1
            i=j
    return out,skip
def bk(x,won):
    a=step(x,-1); return None if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)
def trades(g,pr,res,over,S,hf):
    sh,sa,R=S; out=[]
    def both(name,role,sel,won):
        if sel in pr:
            b=bk(pr[sel],won)
            if b is not None: out.append((name,role,'BACK',sel,hf,g,b))
            out.append((name,role,'LAY',sel,hf,g,ly(pr[sel],won)))
    tags=['R5']+(['R2'] if R<=2 else [])
    for tg in tags:
        for sel in ('HOME','DRAW','AWAY'): both('LAST5',tg,sel,res==sel)
        both('LAST5',tg,'OVER',over); both('LAST5',tg,'UNDER',not over)
        if 'DEAD' in sh and 'DEAD' in sa:
            for sel in ('HOME','DRAW','AWAY'): both('DEADvDEAD',tg,sel,res==sel)
            both('DEADvDEAD',tg,'OVER',over); both('DEADvDEAD',tg,'UNDER',not over)
        for me,op,sel,osel in ((sh,sa,'HOME','AWAY'),(sa,sh,'AWAY','HOME')):
            for st,cond in (('FIGHTvDEAD','FIGHT' in me and 'DEAD' in op),('TITLEvDEAD','TITLE' in me and 'DEAD' in op),('DOOMEDvLIVE','DOOMED' in me and 'DEAD' not in op and 'DOOMED' not in op)):
                if cond: both(st,tg,sel,res==sel)
    return out
def table(rows):
    T=pd.DataFrame(rows,columns=['state','R','side','sel','h','g','v']); o=[]
    # the team lines pool home and away; a game can be in both only if both sides qualify, which the states exclude
    T['sel2']=np.where(T.state.isin(['FIGHTvDEAD','TITLEvDEAD','DOOMEDvLIVE']),'team',T.sel)
    for k,x in T.groupby(['state','R','side','sel2']):
        d=line(x.v.values,x.h.values); o.append(dict(state=k[0],R=k[1],side=k[2],sel=k[3],n=d['n'],games=x.g.nunique(),per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],PASS=d['PASS']))
    return pd.DataFrame(o)
# known answers, worked by hand. Table of 20 teams: first 80, sixth 60, third from bottom 30.
_tb=[80,75,70,65,62,60,58,55,52,50,48,46,44,42,40,38,35,30,28,20]
assert sorted(_tb,reverse=True)[5]==60 and sorted(_tb,reverse=True)[17]==30
assert classify(45,3,_tb)=={'DEAD'}          # 45+9=54 < 60 and 45 > 30+9=39
assert classify(39,3,_tb)==set()             # 39 is not > 39: not safe, and 9 clear of 30, so not a fight
assert classify(32,3,_tb)=={'FIGHT'}         # 2 above the line
assert classify(20,3,_tb)=={'DOOMED'}        # 20+9=29 < 30
assert classify(26,1,_tb)=={'DOOMED'} and classify(28,1,_tb)=={'FIGHT'} and classify(28,3,_tb)=={'FIGHT'}    # 26+3=29 < 30; 28+3=31 is not
assert classify(78,3,_tb)=={'TITLE'} and classify(80,1,_tb)=={'TITLE'} and classify(70,1,_tb)==set()
_T=7*86400
_g=[]; _id=0; _names=[f"T{i}" for i in range(12)]
for w in range(22):           # 12 teams, 6 games a week, 22 rounds, T0 beats everyone, T1 loses to everyone
    for i in range(6):
        h,a=_names[(i+w)%12],_names[(i+w+6)%12]; _id+=1
        hg,ag=(1,0) if h=='T0' or a=='T1' else (0,1) if a=='T0' or h=='T1' else (1,1)
        _g.append((_id,w*_T,h,a,hg,ag,'L'))
_o,_ = build(_g)
assert min(_o)==(22-5)*6+1 and len(_o)==5*6, (min(_o),len(_o))          # only rounds with R<=5 are in; 22 rounds so R=5 is round index 17
_ext=_g+[(999,23*_T,'T0','T1',1,0,'L')]; _o2,_s2=build(_ext); assert 999 not in _o2 and _s2['past_length']==1      # a game past the normal length is dropped
_p={'HOME':2.04,'DRAW':3.5,'AWAY':3.0,'OVER':2.0,'UNDER':1.9}
_t=trades(5,_p,'HOME',True,({'FIGHT'},{'DEAD'},2),1)
assert ('FIGHTvDEAD','R2','BACK','HOME',1,5,bk(2.04,True)) in _t and ('FIGHTvDEAD','R5','LAY','HOME',1,5,ly(2.04,True)) in _t and not [x for x in _t if x[0] in ('DEADvDEAD','TITLEvDEAD','DOOMEDvLIVE')]
_t=trades(5,_p,'DRAW',False,({'DOOMED'},{'FIGHT'},4),2); assert ('DOOMEDvLIVE','R5','BACK','HOME',2,5,-10.0) in _t and not [x for x in _t if x[1]=='R2']
_t=trades(5,_p,'DRAW',False,({'DOOMED'},{'DEAD'},4),2); assert not [x for x in _t if x[0]=='DOOMEDvLIVE']    # both have nothing on: not a live opponent
_u=table([('FIGHTvDEAD','R5','BACK','HOME',1,1,5.),('FIGHTvDEAD','R5','BACK','AWAY',2,2,-1.)]); assert _u.n[0]==2 and _u.sel[0]=='team' and _u.h1[0]==5. and _u.h2[0]==-1.
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=pd.read_sql("SELECT fixture_id,kickoff,home,away,hg,ag,league,league_id,season FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND kickoff IS NOT NULL AND season IN (2024,2025)",con)
F['ks']=pd.to_datetime(F.kickoff,utc=True).map(lambda t:int(t.timestamp())); F['lg']=F.league_id.astype(str)+'|'+F.season.astype(str)
S,sk=build(list(zip(F.fixture_id,F.ks,F.home,F.away,F.hg,F.ag,F.lg)))
print(f"fixtures {len(F)}, league keys {F.lg.nunique()}, games in the last 5 rounds {len(S)}, skipped {dict(sk)}",flush=True)
print("states",Counter(x for v in S.values() for x in v[0]|v[1]),flush=True)
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.season,f.kickoff,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.season IN (2024,2025)""",con)
G=G[G.fixture_id.isin(S)]; print(f"mapped in the last 5 rounds {len(G)}",flush=True)
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND coalesce(minute,0)<=2 GROUP BY 1",con,params=(list(map(int,G.fixture_id)),))
first_goal=dict(zip(EV.fixture_id,EV.gm)); parts=[]
for i in range(0,len(G),1000):
    P=pd.read_sql("SELECT event_id,mkt,sel,minute,m,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt IN ('MO','OU25') AND sel IN ('HOME','DRAW','AWAY','UNDER','OVER') AND minute>=0 AND minute<=2 AND ltp>=1.01 AND ltp<1000",con,params=(list(G.event_id.iloc[i:i+1000]),))
    parts.append(P.sort_values(['event_id','mkt','sel','minute','m']).drop_duplicates(['event_id','mkt','sel']))
P=pd.concat(parts,ignore_index=True).merge(G,on='event_id')
P['lag']=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True)).dt.total_seconds()/60
bad=(P.lag<-5)|(P.lag>20); gm=P.fixture_id.map(first_goal); kn=gm.notna()&(gm<P.minute)
print(f"games with a print {P.event_id.nunique()}; rows dropped, lag {int(bad.sum())}, goal known before the print {int(kn.sum())}; {time.time()-T0:.0f}s",flush=True); P=P[~bad&~kn]
rows=[]
for (e,fx,s,hg,ag),x in P.groupby(['event_id','fixture_id','season','hg','ag']):
    pr=dict(zip(x.sel,x.ltp)); res='HOME' if hg>ag else 'AWAY' if ag>hg else 'DRAW'
    rows+=trades(e,pr,res,hg+ag>2.5,S[fx],1 if s==2024 else 2)
TAPE=table(rows); print(f"tape trades {len(rows)}, lines {len(TAPE)}, {time.time()-T0:.0f}s",flush=True)
def num(x):
    try: v=float(x)
    except (TypeError,ValueError): return np.nan
    return v if 1<v<=1000 else np.nan
R=pd.read_sql("SELECT div,season,date,home,away,fthg,ftag,raw FROM fd_matches WHERE fthg IS NOT NULL AND season IN ('2425','2526')",con); con.close()
R['id']=range(len(R)); R['ks']=pd.to_datetime(R.date).map(lambda t:int(t.timestamp())); R['lg']=R['div']+'|'+R.season
SF,skf=build(list(zip(R.id,R.ks,R.home,R.away,R.fthg,R.ftag,R.lg)))
Q=R[R.id.isin(SF)]; med=Q.date.sort_values().iloc[len(Q)//2]; rows=[]; book=[0,0,0]
for i,d,hg,ag,r in zip(Q.id,Q.date,Q.fthg,Q.ftag,Q.raw):
    pr={}
    h,dr,a=num(r.get('BFECH')),num(r.get('BFECD')),num(r.get('BFECA')); o,u=num(r.get('BFEC>2.5')),num(r.get('BFEC<2.5'))
    if h==h and dr==dr and a==a:
        if .98<=1/h+1/dr+1/a<=1.04: pr.update(HOME=h,DRAW=dr,AWAY=a)
        else: book[0]+=1
    if o==o and u==u:
        if .98<=1/o+1/u<=1.04: pr.update(OVER=o,UNDER=u)
        else: book[1]+=1
    if pr:
        book[2]+=1; res='HOME' if hg>ag else 'AWAY' if ag>hg else 'DRAW'
        rows+=trades(i,pr,res,hg+ag>2.5,SF[i],1 if d<=med else 2)
if rows:
    PX=table(rows); print(f"proxy games {book[2]} of {len(Q)}, books outside MO {book[0]} OU {book[1]}, split {med}, {time.time()-T0:.0f}s",flush=True)
else:
    PX=pd.DataFrame(columns=['state','R','side','sel','n','per10','t','h1','h2']); print("proxy: no closes",flush=True)
J=TAPE.merge(PX[['state','R','side','sel','n','per10','t','h1','h2']].rename(columns=dict(n='px_n',per10='px_10',t='px_t',h1='px_h1',h2='px_h2')),on=['state','R','side','sel'],how='left')
E=J[J.n>=300].sort_values('t',ascending=False); cols=['state','R','side','sel','n','games','per10','t','h1','h2','px_n','px_10','px_t','px_h1','px_h2','PASS']
print(f"\nlines {len(J)}, at n>=300 {len(E)}, positive {(E.per10>0).sum()}, passing {int(J.PASS.sum())}")
print("\nALL TEAM LINES, any n"); print(J[J.sel=='team'].sort_values('t',ascending=False)[cols].to_string(index=False))
print("\nCONTROL LAST5, R5"); print(J[(J.state=='LAST5')&(J.R=='R5')][cols].to_string(index=False))
print("\nTOP 15 by t, n>=300"); print(E[cols].head(15).to_string(index=False))
print("\nBOTTOM 5 by t, n>=300"); print(E[cols].tail(5).to_string(index=False))
print("\nSURVIVORS"); P=J[J.PASS]; print(P[cols].to_string(index=False) if len(P) else "none")
print(f"done {time.time()-T0:.0f}s")
PY
