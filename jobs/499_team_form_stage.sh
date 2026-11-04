#!/bin/bash
set -o pipefail
# 499_team_form_stage (Finder 2026-11-04, queue items 82 and 83, Finder's own, sources d and c): are form streaks and season stage priced? Rules written in the queue before any price was read. One job as both use the same prices. The number 499 is reused with a new slug: 450-499 are all taken.
# TAPE af_fixtures (finished, seasons 2023+, history), af_price_map, bf_hist_price, af_events. Entry and guards as jobs/499_rest_gap.sh: earliest real print in tape minutes 0..2, ltp >= 1.01; lag outside -5..+20 min v the af kick-off dropped, counted; a goal with af minute strictly before the print minute dropped. One tick adverse, 2% commission, £10 risk, hold to FT. Halves are seasons 2024 v 2025. LTP only, so a pass is an upper bound.
# PROXY fd_matches Betfair closes (BFEC), 2024-25 onwards, history from 2023-24, book 0.98-1.04, halves by date median. A close is not a print and overlaps the tape's games, so it can only contradict a tape line, it cannot pass one. fd holds league games only, so its AFTER12D and streaks miss cups.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,deque
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time(); D=86400
def team_states(h):
    """h: a team's finished games oldest first, each (goals for, goals against)."""
    s=set(); w=[a>b for a,b in h]; l=[a<b for a,b in h]
    if len(h)>=3 and all(w[-3:]): s.add('W3')
    if len(h)>=5 and all(w[-5:]): s.add('W5')
    if len(h)>=3 and all(l[-3:]): s.add('L3')
    if len(h)>=5 and all(l[-5:]): s.add('L5')
    if len(h)>=5 and not any(w[-5:]): s.add('NOWIN5')
    if h and h[-1][0]-h[-1][1]>=4: s.add('BIGWIN')
    if h and h[-1][1]-h[-1][0]>=4: s.add('BIGLOSS')
    return s
def goal_state(h,a):
    """Both teams' last k games all Over or all Under 2.5."""
    s=set()
    for k in (3,5):
        if len(h)>=k and len(a)>=k:
            t=[x+y for x,y in h[-k:]]+[x+y for x,y in a[-k:]]
            if all(v>=3 for v in t): s.add(f'BOTH_O{k}')
            if all(v<=2 for v in t): s.add(f'BOTH_U{k}')
    return s
def build(fx):
    """fx: (id,seconds,home,away,hg,ag,lg). Returns {id:(home states,away states,goal states,stage states)}. Games at the same time are not history for each other. History clears after a gap over 45 days. Stage counts use games in that lg key, 20+ per team; the fixture list is known in advance."""
    fx=sorted(fx,key=lambda z:z[1]); hist=defaultdict(lambda:deque(maxlen=5)); last={}; out={}
    games=defaultdict(list)
    for f,k,h,a,_,_,lg in fx:
        if lg is not None:
            games[(lg,h)].append(k); games[(lg,a)].append(k)
    i=0
    while i<len(fx):
        j=i
        while j<len(fx) and fx[j][1]==fx[i][1]: j+=1
        for f,k,h,a,hg,ag,lg in fx[i:j]:
            for t in (h,a):
                if t in last and k-last[t]>45*D: hist[t].clear()
            H,A=list(hist[h]),list(hist[a]); sh,sa=team_states(H),team_states(A)
            if 'W3' in sh and 'L3' in sa: sh=sh|{'W3vL3'}
            if 'W3' in sa and 'L3' in sh: sa=sa|{'W3vL3'}
            st=set(); gh,ga=games.get((lg,h),[]),games.get((lg,a),[])
            if len(gh)>=20 and len(ga)>=20:
                ph,pa=gh.index(k),ga.index(k)
                if ph<3 and pa<3: st.add('OPEN3')
                if len(gh)-1-ph<=2 and len(ga)-1-pa<=2: st.add('CLOSE3')
                if ph>=1 and pa>=1 and h in last and a in last and k-last[h]>=12*D and k-last[a]>=12*D: st.add('AFTER12D')
            out[f]=(sh,sa,goal_state(H,A),st)
        for f,k,h,a,hg,ag,lg in fx[i:j]:
            hist[h].append((hg,ag)); hist[a].append((ag,hg)); last[h]=k; last[a]=k
        i=j
    return out
def bk(x,won):
    a=step(x,-1); return None if a<=1.01 else back_settle(a,won)
def ly(x,won): return lay_settle(step(x,1),won)
def trades(g,pr,res,over,S,hf):
    """Rows for one game. pr: {'HOME':..,'DRAW':..,'AWAY':..,'OVER':..,'UNDER':..} missing if no print."""
    sh,sa,gs,st=S; r=[]
    def both(name,role,sel,won):
        if sel in pr:
            b=bk(pr[sel],won); r.append((name,role,'BACK',sel_lab(sel,role),hf,g,b)) if b is not None else None
            r.append((name,role,'LAY',sel_lab(sel,role),hf,g,ly(pr[sel],won)))
    for side,ss,sel in (('home',sh,'HOME'),('away',sa,'AWAY')):
        for s in ss:
            for role in ('all',side): both(s,role,sel,res==sel)
    for s in gs|st:
        both(s,'-','OVER',over); both(s,'-','UNDER',not over)
    for s in st:
        for sel in ('HOME','DRAW','AWAY'): both(s,'-',sel,res==sel)
    return r
def sel_lab(sel,role): return 'team' if role in('all','home','away') else sel
def table(rows):
    T=pd.DataFrame(rows,columns=['state','role','side','sel','h','g','v']); T=T[T.v.notna()]; o=[]
    for k,x in T.groupby(['state','role','side','sel']):
        v=x.v.values; d=line(v,x.h.values); o.append(dict(state=k[0],role=k[1],side=k[2],sel=k[3],n=d['n'],games=x.g.nunique(),per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],PASS=d['PASS']))
    return pd.DataFrame(o)
# known answers
assert team_states([(1,0),(2,1),(3,0)])=={'W3'} and team_states([(0,1),(1,2),(0,4)])=={'L3','BIGLOSS'} and team_states([(5,0)])=={'BIGWIN'} and team_states([(1,1),(0,1),(2,2),(0,0),(1,3)])=={'NOWIN5'} and team_states([(1,0),(1,0)])==set()
assert team_states([(1,0)]*5)=={'W3','W5'} and team_states([(0,1)]*5)=={'L3','L5','NOWIN5'}
assert goal_state([(2,1)]*3,[(3,0)]*3)=={'BOTH_O3'} and goal_state([(1,1)]*5,[(0,0)]*5)=={'BOTH_U3','BOTH_U5'} and goal_state([(2,1)]*3,[(1,0)]*3)==set() and goal_state([(2,1)]*2,[(3,0)]*3)==set()
_x=[(i,i*7*D,'A','B',1,0,None) for i in range(1,4)]+[(9,4*7*D,'A','C',0,0,None),(10,4*7*D,'B','D',0,0,None)]
_b=build(_x); assert _b[1][0]==set() and _b[3][0]==set() and _b[9][0]=={'W3'} and _b[10][0]=={'L3'}          # streak needs 3 finished games, and the loser carries L3
_y=[(1,7*D,'A','B',1,0,None),(2,14*D,'A','C',1,0,None),(3,21*D,'A','D',1,0,None),(4,28*D,'A','E',0,0,None),(5,28*D,'E','F',9,0,None),(6,28*D+1,'E','F',0,0,None)]
_b=build(_y); assert 'W3' in _b[4][0] and 'W3' not in _b[3][0]
_z=[(1,7*D,'A','B',1,0,None),(2,14*D,'A','C',1,0,None),(3,21*D,'A','D',1,0,None),(4,(21+46)*D,'A','E',0,0,None)]
assert 'W3' not in build(_z)[4][0]                                                                      # summer gap clears history
_l=[(100+r,r*7*D,'A' if r%2 else 'B','B' if r%2 else 'A',1,1,'L') for r in range(1,24)]; _b=build(_l)
assert 'OPEN3' in _b[101][3] and 'OPEN3' in _b[103][3] and 'OPEN3' not in _b[104][3] and 'CLOSE3' in _b[121][3] and 'CLOSE3' not in _b[120][3] and 'CLOSE3' in _b[123][3]
_l2=[(100+r,r*7*D,'A','B',1,1,'L') for r in range(1,10)]; assert build(_l2)[101][3]==set()                  # under 20 games: a cup, no stage state
assert abs(bk(2.04,True)-9.996)<1e-9 and bk(2.04,False)==-10.0 and ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9 and bk(1.01,True) is None
_t=trades(5,{'HOME':2.04,'AWAY':3.0,'OVER':2.0,'UNDER':1.9},'HOME',True,({'W3'},set(),{'BOTH_O3'},set()),1)
assert len(_t)==8 and ('W3','all','BACK','team',1,5,bk(2.04,True)) in _t and ('W3','home','LAY','team',1,5,ly(2.04,True)) in _t and ('BOTH_O3','-','LAY','UNDER',1,5,ly(1.9,False)) in _t
_u=table([('S','all','BACK','team',1,1,5.),('S','all','BACK','team',2,2,-1.)]); assert _u.n[0]==2 and _u.h1[0]==5. and _u.h2[0]==-1. and _u.games[0]==2
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
# ---- TAPE
F=pd.read_sql("SELECT fixture_id,kickoff,home,away,hg,ag,league,season FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND kickoff IS NOT NULL AND season>=2023",con)
F['ks']=pd.to_datetime(F.kickoff,utc=True).map(lambda t:int(t.timestamp())); F['lg']=F.league+'|'+F.season.astype(str)
print("fixtures",len(F),"largest league keys",F.groupby('lg').size().sort_values().tail(3).to_dict(),flush=True)
S=build(list(zip(F.fixture_id,F.ks,F.home,F.away,F.hg,F.ag,F.lg)))
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.league,f.season,f.kickoff,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.season IN (2024,2025)""",con)
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND coalesce(minute,0)<=2 GROUP BY 1",con,params=(list(map(int,G.fixture_id)),))
first_goal=dict(zip(EV.fixture_id,EV.gm)); parts=[]
for i in range(0,len(G),1000):
    P=pd.read_sql("SELECT event_id,mkt,sel,minute,m,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt IN ('MO','OU25') AND sel IN ('HOME','DRAW','AWAY','UNDER','OVER') AND minute>=0 AND minute<=2 AND ltp>=1.01 AND ltp<1000",con,params=(list(G.event_id.iloc[i:i+1000]),))
    parts.append(P.sort_values(['event_id','mkt','sel','minute','m']).drop_duplicates(['event_id','mkt','sel']))
    if (i//1000)%4==0: print(f"  {min(i+1000,len(G))}/{len(G)} {time.time()-T0:.0f}s",flush=True)
P=pd.concat(parts,ignore_index=True).merge(G,on='event_id')
P['lag']=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True)).dt.total_seconds()/60
bad=(P.lag<-5)|(P.lag>20); gm=P.fixture_id.map(first_goal); kn=gm.notna()&(gm<P.minute)
print(f"games with a print {P.event_id.nunique()}; rows dropped, lag {int(bad.sum())}, goal known before the print {int(kn.sum())}",flush=True); P=P[~bad&~kn]
rows=[]
for (e,fx,s,hg,ag),x in P.groupby(['event_id','fixture_id','season','hg','ag']):
    if fx not in S: continue
    pr=dict(zip(x.sel,x.ltp)); res='HOME' if hg>ag else 'AWAY' if ag>hg else 'DRAW'
    rows+=trades(e,pr,res,hg+ag>2.5,S[fx],1 if s==2024 else 2)
TAPE=table(rows); print(f"tape trades {len(rows)}, lines {len(TAPE)}, {time.time()-T0:.0f}s",flush=True)
# ---- PROXY
def num(x):
    try: v=float(x)
    except (TypeError,ValueError): return np.nan
    return v if 1<v<=1000 else np.nan
R=pd.read_sql("SELECT div,season,date,home,away,fthg,ftag,raw FROM fd_matches WHERE fthg IS NOT NULL AND season IN ('2324','2425','2526','2627')",con); con.close()
R['id']=range(len(R)); R['ks']=pd.to_datetime(R.date).map(lambda t:int(t.timestamp())); R['lg']=R['div']+'|'+R.season
SF=build(list(zip(R.id,R.ks,R.home,R.away,R.fthg,R.ftag,R.lg)))
Q=R[R.season!='2324']; med=Q.date.sort_values().iloc[len(Q)//2]; rows=[]; book=[0,0,0]
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
PX=table(rows); print(f"proxy games {book[2]} of {len(Q)}, books outside 0.98-1.04 MO {book[0]} OU {book[1]}, split {med}, {time.time()-T0:.0f}s",flush=True)
J=TAPE.merge(PX[['state','role','side','sel','n','per10','t','h1','h2']].rename(columns=dict(n='px_n',per10='px_10',t='px_t',h1='px_h1',h2='px_h2')),on=['state','role','side','sel'],how='left')
E=J[J.n>=300].sort_values('t',ascending=False)
FORM={'W3','W5','L3','L5','NOWIN5','BIGWIN','BIGLOSS','W3vL3','BOTH_O3','BOTH_O5','BOTH_U3','BOTH_U5'}
print(f"\nlines {len(J)}, at n>=300 {len(E)}, positive {(E.per10>0).sum()}, passing {int(J.PASS.sum())}; item 82 lines {J.state.isin(FORM).sum()}, item 83 lines {(~J.state.isin(FORM)).sum()}")
cols=['state','role','side','sel','n','games','per10','t','h1','h2','px_n','px_10','px_t','px_h1','px_h2','PASS']
print("\nITEM 82 TOP 15 by t, n>=300"); print(E[E.state.isin(FORM)][cols].head(15).to_string(index=False))
print("\nITEM 83 TOP 12 by t, n>=300"); print(E[~E.state.isin(FORM)][cols].head(12).to_string(index=False))
print("\nBOTTOM 8 by t, n>=300"); print(E[cols].tail(8).to_string(index=False))
print("\nPROXY ONLY, best 8 by t, n>=300 on the closes (cannot pass)"); print(PX[PX.n>=300].sort_values('t',ascending=False).head(8).drop(columns='PASS').to_string(index=False))
print("\nSURVIVORS"); P=J[J.PASS]
print(P[cols].to_string(index=False) if len(P) else "none")
print(f"done {time.time()-T0:.0f}s")
PY
