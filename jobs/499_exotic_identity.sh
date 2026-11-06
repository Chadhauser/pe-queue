#!/bin/bash
set -o pipefail
# 499_exotic_identity (Finder 2026-11-06, queue item 267, Finder's own, source c; from jobs/499_derivative_gap.sh): exact price identities on Sep 2026. Rule pushed in the queue (ae1146f) before any price. Read only. No tables written.
# IDENTITIES P(T) = P(T -1) + P(T by exactly 1) on team handicap 1, one per side; P(A) = P(A/Yes) + P(A/No) and P(A/Over) + P(A/Under), for A = home, draw, away. gap = implied of both legs minus implied of MO, in points, prints all T-20 to T-2.
# THE LEG TRADED: the shorter of the two, the queue line leaves this open and it is fixed here before prices: fewer very long lays, and the side more likely to have a real touch. The largest absolute gap per game per family; G2, G4; CHEAP back, DEAR lay. Swapped sides and NEAR (gap under 1) are controls, not scored. Fills, costs and settlement as item 266. Prints are not synchronous, so a gap may be a stale print; a pass only earns a real-touch check.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
from lib_official import bk,ly,fill,last_in,checks
import lib_cand,lib_exotic as X; lib_cand._checks(); checks(); X.checks()
def gap(a,b,m): return 100*(1/a+1/b-1/m)
assert abs(gap(4,4,2))<1e-9 and abs(gap(2,2,1.25)-20)<1e-9 and abs(gap(5,5,2)+10)<1e-9   # by hand: .25+.25-.5=0; .5+.5-.8=.2; .2+.2-.5=-.1
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',30)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
E=X.load(con,['TEAM_A_1','TEAM_B_1','MATCH_ODDS_AND_BTTS','MATCH_ODDS_AND_OU_25','MATCH_ODDS']); SC,nsc=X.scores(con); con.close()
print(f"games with a pre-off print {len(E):,}; goal_timeline rows {nsc:,}; {time.time()-T0:.0f}s",flush=True)
C=Counter(); cand=[]
def last(en,off):
    if en is None: return None
    i=last_in(en[0],off-1200,off-120); return None if i is None else i
for (ev,off),M in E.items():
    home,_x,away=ev.partition(' v '); mo=M.get('MATCH_ODDS')
    if not mo: C['no MO print']+=1; continue
    mp={'H':mo.get(home),'A':mo.get(away),'D':mo.get('The Draw')}
    for fam,mty,two in (('MOBTTS','MATCH_ODDS_AND_BTTS',('yes','no')),('MOOU25','MATCH_ODDS_AND_OU_25',('over','under'))):
        S=M.get(mty)
        if not S: continue
        L={}
        for s,en in S.items():
            p=X.combo_parse(s,home,away)
            if p and p[1] in two: L[p]=en
        for r in 'HAD':
            a,b,m=L.get((r,two[0])),L.get((r,two[1])),mp[r]
            ia,ib,im=last(a,off),last(b,off),last(m,off)
            if None in (ia,ib,im): C[fam+' a leg not priced']+=1; continue
            pa,pb,pm=float(a[1][ia]),float(b[1][ib]),float(m[1][im]); leg=(r,two[0]) if pa<=pb else (r,two[1]); en=L[leg]
            cand.append((ev,off,fam,gap(pa,pb,pm),en,last(en,off),('C',)+leg))
    for mty,hh in (('TEAM_A_1',1),('TEAM_B_1',-1)):   # the side giving the goal: away in TEAM_A_1, home in TEAM_B_1
        S=M.get(mty)
        if not S: continue
        r='A' if hh==1 else 'H'; nm=(away if r=='A' else home)+' -1'; a,b,m=S.get(nm),S.get('Draw'),mp[r]
        ia,ib,im=last(a,off),last(b,off),last(m,off)
        if None in (ia,ib,im): C['H1 a leg not priced']+=1; continue
        pa,pb,pm=float(a[1][ia]),float(b[1][ib]),float(m[1][im]); d=pb<pa
        cand.append((ev,off,'H1',gap(pa,pb,pm),b if d else a,ib if d else ia,('D' if d else 'H',r,hh)))
print("gaps read:",Counter(c[2] for c in cand),"counted:",dict(C),flush=True)
G=pd.Series([c[3] for c in cand]); print("gap points, p5 p25 p50 p75 p95:",G.quantile([.05,.25,.5,.75,.95]).round(2).tolist(),flush=True)
def won_of(tag,sc):
    sh,sa=sc
    if tag[0]=='C': return X.combo_won(tag[1],tag[2],sh,sa)
    return X.hc_draw_won(tag[2],sh,sa) if tag[0]=='D' else X.hc_won(tag[1],-1,sh,sa)
assert won_of(('C','H','yes'),(2,1)) and won_of(('D','A',1),(0,1)) and won_of(('H','H',-1),(2,0)) and won_of(('H','A',1),(0,2)) and not won_of(('H','A',1),(0,1)) and won_of(('D','H',-1),(1,0))
# the largest absolute gap per game per family, one bet; NEAR is the smallest instead
rows=[]; byk={}
for c in cand: byk.setdefault((c[0],c[1],c[2]),[]).append(c)
drop=0
for k,v in byk.items():
    big=max(v,key=lambda z:abs(z[3])); small=min(v,key=lambda z:abs(z[3]))
    sc=SC(k[0],k[1])
    if sc is None: drop+=1; continue
    def rec(c,lab,side):
        ts,px=c[4]; i=c[5]; p=fill(ts,px,i,side)
        if p>50: C['over 50, not traded']+=1; return
        w=won_of(c[6],sc); v_=bk(p,w) if side=='B' else ly(p,w)
        if v_ is None: C['bottom of ladder, no back']+=1; return
        rows.append((k[0],k[1],k[2],lab,side,p,w,v_))
    g=big[3]
    for th in (2,4):
        if g<=-th: rec(big,f"G{th} CHEAP",'B'); rec(big,f"G{th} CHEAP swapped",'L')
        if g>=th: rec(big,f"G{th} DEAR",'L'); rec(big,f"G{th} DEAR swapped",'B')
    if abs(small[3])<1: rec(small,"NEAR control",'B'); rec(small,"NEAR control",'L')
print("games by family with no score match, dropped:",drop,"counted:",dict(C),flush=True)
R=pd.DataFrame(rows,columns='e off fam lab side p won v'.split()); md=np.median(R.off.values); print("halves split at",pd.Timestamp(md,unit='s',tz='UTC'),flush=True)
out=[]
for k,x in R.groupby(['fam','lab','side']):
    l=line(x.v.values,np.where(x.off<md,1,2)); out.append(dict(fam=k[0],lab=k[1],side=k[2],n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],maxwin=l['maxwin'],won=x.won.mean(),imp=(1/x.p).mean(),PASS=l['PASS']))
O=pd.DataFrame(out); print("\n== all lines"); print(O.sort_values(['fam','lab','side']).round(3).to_string(index=False))
S=O[(O.PASS==True)&~O.lab.str.contains('swapped|control')]
print(f"\n== SURVIVORS: {len(S)} of {int((~O.lab.str.contains('swapped|control')).sum())} scored\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
