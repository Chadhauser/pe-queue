#!/bin/bash
set -o pipefail
# 499_cricket_toss (Finder 2026-11-06, queue item 286, Finder's own, source a; from jobs/499_cricket_truth.sh): the T20 toss at the price just before the off, official winners. Rule pushed in the queue (8b1a00f) before any price. Read only. No tables written. cricket_matches is read from Railway, that one table.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_000_000_000,2_000_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,norm
from lib_official import bk,ly,fill,last_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
def bats_second(tw,other,dec):
    """Who bats second: the toss winner if it chose to field, the other side if it chose to bat."""
    return tw if dec=='field' else other if dec=='bat' else None
assert bats_second('A','B','field')=='A' and bats_second('A','B','bat')=='B' and bats_second('A','B',None) is None
assert abs(bk(2.04,True)-9.996)<1e-9 and ly(2.0,True)==-10.0
assert secs(pd.Series([pd.Timestamp('2024-01-01',tz='UTC')])).iloc[0]==1704067200
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require')
CM=pd.read_sql("SELECT match_date,team1,team2,winner,toss_winner,toss_decision,competition FROM cricket_matches WHERE match_date>='2024-08-25' AND match_format='T20' AND toss_winner IS NOT NULL",rc); rc.close()
ix=defaultdict(list)
for r in CM.itertuples(): ix[frozenset((norm(r.team1),norm(r.team2)))].append(r)
print("official T20 with a toss",len(CM),CM.match_date.min(),CM.match_date.max(),"winner NULL",int(CM.winner.isna().sum()),flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
P=pd.read_sql("SELECT market_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Cricket' AND market_type='MATCH_ODDS' AND ltp>=1.01 AND ltp<1000 AND market_time>='2024-09-01' AND market_time<'2026-05-01' AND NOT inplay AND ts>=market_time-interval '120 minutes'",con); con.close()
P['tt']=secs(P.ts); P['off']=secs(P.mt); P=P.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt'])
print("prints",len(P),f"{time.time()-T0:.0f}s",flush=True)
C=Counter(); rows=[]; seen=set()
for m,g in P.groupby('market_id',sort=True):
    ev=g.ev.iloc[0]; o=float(g.off.iloc[0])
    if (ev,o) in seen: C['second id']+=1; continue
    seen.add((ev,o)); runners=list(g.sel.unique())
    if len(runners)!=2: C['not two runners with prints']+=1; continue
    h_,_,a_=str(ev).partition(' v '); day=pd.Timestamp(g.mt.iloc[0]).date()
    hits=[r for r in ix.get(frozenset((norm(h_),norm(a_))),[]) if abs((r.match_date-day).days)<=1]
    if len(hits)!=1: C['no unique official match']+=1; continue
    r=hits[0]; tw=[s for s in runners if norm(s)==norm(r.toss_winner)]
    if len(tw)!=1: C['toss name no match']+=1; continue
    tw=tw[0]; ot=[s for s in runners if s!=tw][0]
    if pd.isna(r.winner): win=None; C['no official winner']+=1
    else:
        w_=[s for s in runners if norm(s)==norm(r.winner)]
        if len(w_)!=1: C['winner name no match']+=1; continue
        win=w_[0]
    b2=bats_second(tw,ot,r.toss_decision)
    if b2 is None: C['no toss decision']+=1
    en={}
    for s,y in g.groupby('sel',sort=False):
        ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-1200,o-120)
        if i is None: continue
        j=last_in(ts,o-7200,o-2700)
        en[s]=(fill(ts,px,i,'B'),fill(ts,px,i,'L'),float(px[i]),None if j is None else float(px[j]))
    if tw not in en and ot not in en: C['no print in window']+=1; continue
    def rec(lab,s):
        if s is None or s not in en: return
        pb,pl,last_,pre=en[s]
        vb=None if pb>50 or win is None else bk(pb,s==win)
        vl=None if pl>50 or win is None else ly(pl,s==win)
        rows.append((lab,o,last_,pre,win is None,None if win is None else s==win,vb,vl))
    rec('TOSS winner',tw); rec('TOSS loser, context',ot)
    if r.toss_decision=='field': rec('TOSS winner who fielded',tw)
    if r.toss_decision=='bat': rec('TOSS winner who batted',tw)
    rec('BATS second',b2)
    if b2 is not None: rec('BATS first',ot if b2==tw else tw)
    C['games scored' if win is not None else 'games no winner']+=1
print("counted:",dict(sorted(C.items())),flush=True)
D=pd.DataFrame(rows,columns='lab off p pre nores won vb vl'.split()); md=float(np.median(D[D.lab=='TOSS winner'].off)); print("halves split at",pd.Timestamp(md,unit='s',tz='UTC'),flush=True)
out=[]
for lab,x in D.groupby('lab'):
    for sd,c in (('back','vb'),('lay','vl')):
        z=x[x[c].notna()]
        if len(z)<30: continue
        v=z[c].astype(float).values; l=line(v,np.where(z.off<md,1,2)); n0=int(x.nores.sum())
        t0=v.sum()/(len(v)+n0)
        out.append(dict(line=lab+' '+sd,n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],maxwin=l['maxwin'],won=z.won.astype(float).mean(),imp=(1/z.p).mean(),per10_void0=t0,PASS=l['PASS']))
L=pd.DataFrame(out); print("\n"+L.sort_values('t',ascending=False).round(3).to_string(index=False))
x=D[D.pre.notna()&(D.lab.isin(['TOSS winner','TOSS winner who fielded','TOSS winner who batted','BATS second']))].copy(); x['mv']=(x.p/x.pre-1)*100
print("\ncontext, not tradable: price move T-120..T-45 to T-20..T-2, % (negative = shortened)"); print(x.groupby('lab').mv.agg(['size','mean','median','std']).round(2).to_string())
y=D[(D.lab=='TOSS winner')&~D.nores&(D.p<=50)]; v=np.array([np.nan if (q:=bk(p,bool(w))) is None else q for p,w in zip(y.p,y.won)],dtype=float); v=v[np.isfinite(v)]
print(f"\ndiagnostic, not scored, breaks the fill rule: TOSS winner back at the last print, one tick, no worse-of-two: n {len(v)} per10 {v.mean():+.3f} t {v.mean()/(v.std(ddof=1)/np.sqrt(len(v))):.2f}")
S=L[L.PASS&~L.line.str.contains('context')]
print(f"\n== SURVIVORS: {len(S)} of {int((~L.line.str.contains('context')).sum())} scored\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
