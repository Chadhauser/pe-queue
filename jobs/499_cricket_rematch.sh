#!/bin/bash
set -o pipefail
# 499_cricket_rematch (Finder 2026-11-07, queue item 370, Finder's own, source c; engine from jobs/499_cricket_women.sh): cricket, the same two teams again within 3 days. Rule pushed in the queue before any price. Read only, no tables written. Same months as item 268, so a re-slice and not unseen.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,re,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,norm
from lib_official import bk,ly,fill,last_in,secs,checks
import lib_cand; lib_cand._checks(); checks()
def infer(last):
    lo=[k for k,v in last.items() if v<=1.10]
    if len(lo)!=1 or len(last)<2: return None
    return lo[0] if all(v>=5.0 for k,v in last.items() if k!=lo[0]) else None
def clean(name): return norm(re.sub(r'\s*\(game\s*\d+\)','',str(name),flags=re.I))
def q_last(last,s): t=sum(1/v for v in last.values()); return (1/last[s])/t
def state(prev,team):
    """prev = dict(w=winner key, up=winner was longer before its off). Team key -> labels for this row."""
    out=['WINNER' if team==prev['w'] else 'LOSER']
    if prev['up']: out.append('UPSET WINNER' if team==prev['w'] else 'BEATEN FAV')
    return out
assert clean('Indonesia (Game 1)')==clean('Indonesia') and clean('Sweden (game 2)')==clean('Sweden') and clean('Canada')!=clean('USA')
assert state(dict(w='a',up=False),'a')==['WINNER'] and state(dict(w='a',up=False),'b')==['LOSER'] and state(dict(w='a',up=True),'a')==['WINNER','UPSET WINNER'] and state(dict(w='a',up=True),'b')==['LOSER','BEATEN FAV']
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_rows',100); pd.set_option('display.max_columns',30)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
Q0="sport='Cricket' AND market_type='MATCH_ODDS' AND ltp>=1.01 AND ltp<1000 AND market_time>='2024-09-01'"
A=pd.read_sql("SELECT market_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp,inplay FROM bf_hist_other WHERE "+Q0+" AND NOT inplay AND ts>=market_time-interval '60 minutes'",con)
B=pd.read_sql("SELECT DISTINCT ON (market_id,sel) market_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp,inplay FROM bf_hist_other WHERE "+Q0+" AND inplay AND ts<=market_time+interval '12 hours' ORDER BY market_id,sel,ts DESC",con); con.close()
P=pd.concat([A,B],ignore_index=True); del A,B
P['tt']=secs(P.ts); P['off']=secs(P.mt); P=P.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt','inplay'])
G=[]; seen=set()
for m,g in P.groupby('market_id',sort=True):
    ev=g.ev.iloc[0]; o=float(g.off.iloc[0])
    if (ev,o) in seen or g.sel.nunique()!=2: continue
    seen.add((ev,o)); pre=g[~g.inplay]; ip=g[g.inplay]; last=ip.groupby('sel').ltp.last().to_dict()
    en={}
    for s,y in pre.groupby('sel',sort=False):
        i=last_in(y.tt.values,o-3600,o-120)
        if i is not None: en[s]=(y.tt.values,y.ltp.values,i,float(y.ltp.values[i]))
    G.append(dict(m=m,ev=ev,off=o,last=last,w=infer(last) if len(last)==2 else None,end=float(ip.tt.max()) if len(ip) else None,en=en,key=frozenset(clean(s) for s in g.sel.unique())))
G.sort(key=lambda z:z['off']); print(f"two-runner games {len(G):,}, {time.time()-T0:.0f}s",flush=True)
by=defaultdict(list); rows=[]; n_rem=0; n_prev_un=0
for g in G:
    pv=[h for h in by[g['key']] if 0<g['off']-h['off']<=3*86400]
    by[g['key']].append(g)
    if not pv: continue
    h=pv[-1]; n_rem+=1
    if h['w'] is None or h['end'] is None or h['end']>=g['off']-120: n_prev_un+=1; continue
    wk=clean(h['w']); loser=[s for s in h['en'] if s!=h['w']]
    up=bool(h['w'] in h['en'] and loser and h['en'][h['w']][3]>h['en'][loser[0]][3]); prev=dict(w=wk,up=up)
    for s,(ts,px,i,_) in g['en'].items():
        for side in 'BL':
            p=fill(ts,px,i,side)
            if p>20: continue
            f=(lambda won:bk(p,won)) if side=='B' else (lambda won:ly(p,won))
            vw,vl=f(True),f(False)
            if vw is None or vl is None: continue
            if g['w'] is not None: v=vw if s==g['w'] else vl; lp=v; won=(s==g['w'])
            elif len(g['last'])==2: q=q_last(g['last'],s); lp=q*vw+(1-q)*vl; v=np.nan; won=np.nan
            else: lp=np.nan; v=np.nan; won=np.nan
            for lab in state(prev,clean(s)): rows.append((g['m'],g['off'],lab,side,p,won,v,lp))
print(f"rematches {n_rem:,}, previous unresolved or still in play at entry, skipped {n_prev_un:,}",flush=True)
R=pd.DataFrame(rows,columns='m off lab side p won v lp'.split()); md=float(np.median(R.off)); print("halves split at",pd.Timestamp(md,unit='s',tz='UTC'),flush=True); out=[]
for (lab,side),x in R.groupby(['lab','side']):
    r=x[x.v.notna()]; y=x[x.lp.notna()]; l=line(r.v.values,np.where(r.off<md,1,2)); o=line(y.lp.values,np.where(y.off<md,1,2)); w=line(x.v.fillna(-10.0).values,np.where(x.off<md,1,2))
    out.append(dict(line=lab,side=side,n=l['n'],games=r.m.nunique(),unres=int(x.v.isna().sum()),per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],won=r.won.astype(float).mean(),imp=(1/r.p).mean(),maxwin=l['maxwin'],lp_per10=o['per10'],lp_t=o['t'],lp_h1=o['h1'],lp_h2=o['h2'],worst_per10=w['per10'],worst_t=w['t'],PASS=bool(l['PASS'] and o['PASS'] and w['PASS'])))
O=pd.DataFrame(out).sort_values('t',ascending=False); print(f"\n== item 370, {len(O)} lines by t\n",O.round(3).to_string(index=False))
S=O[O.PASS]; print(f"\n== SURVIVORS: {len(S)} of {len(O)}\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
