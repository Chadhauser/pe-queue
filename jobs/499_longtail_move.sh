#!/bin/bash
set -o pipefail
# 499_longtail_move (Finder 2026-11-05, queue item 158, Finder's own, source c; from jobs/499_longtail_senior.sh): the pre-match move in the long tail, official results. Rule pushed in the queue before any price was read. Read only.
# MO only, FAV, DOG, DRAW by the entry print. Early = last real print T-180 to T-60 min; entry = last print T-20 to T-2, worse of it and the next non-in-play print within 120 s, one tick adverse, 2%, £10 risk, hold to the official result. No early print = not traded, counted: never forward-filled. Move = entry print / early print, both raw prints. SHORT <= 0.90, DRIFT >= 1.10, the middle not traded. Over 50 not traded.
# GROUPS as jobs/499_longtail_other_markets.sh. 60 lines, one bet per selection per game; FAV, DOG and DRAW of one game are correlated. Prints only: a pass is an upper bound and only earns an unseen-months test.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,norm,jac
from lib_official import group,bk,ly,fill,last_in,secs,load_results,checks
import lib_cand; lib_cand._checks(); checks()
C1,C2=6,14
def mo_pair(home,away,runners):
    """As jobs/499_longtail_senior.sh."""
    r=[x for x in runners if str(x).strip().lower()!='the draw']
    if len(r)!=2: return None
    H,A,a,b=norm(home),norm(away),norm(r[0]),norm(r[1])
    s1,s2=jac(a,H)+jac(b,A),jac(a,A)+jac(b,H)
    if s1==s2: return None
    x,y=(r[0],r[1]) if s1>s2 else (r[1],r[0])
    if not (norm(x)&H and norm(y)&A): return None
    return x,y
def grp_of(x,liqv): return x if isinstance(x,str) else ('S_THIN' if liqv<=C1 else 'S_MID' if liqv<=C2 else 'S_DEEP')
def mv(entry,early):
    r=entry/early
    return 'SHORT' if r<=0.90 else 'DRIFT' if r>=1.10 else None
# known answers: the band edges, and no forward fill from before the early window
assert mv(1.8,2.0)=='SHORT' and mv(1.82,2.0) is None and mv(2.2,2.0)=='DRIFT' and mv(2.18,2.0) is None and mv(2.0,2.0) is None
_t=np.array([0.,100.,500.]); assert last_in(_t,200,400) is None and last_in(_t,50,400)==1
print("checks: OK",flush=True)
pd.set_option('display.width',250); pd.set_option('display.max_rows',100); pd.set_option('display.max_columns',40)
T0=time.time(); con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
RS,bad=load_results(con,['MATCH_ODDS']); print(f"MO markets with one WINNER {len(RS)}, dropped {bad}",flush=True)
cur.execute("SELECT DISTINCT market_id,event_id,event_name,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s)",(list(RS),))
MK=pd.DataFrame(cur.fetchall(),columns='market_id event_id ev mt'.split()); MK['off']=secs(MK.mt); MK=MK.sort_values('market_id').drop_duplicates('event_id')
print(f"events {len(MK)}, by month",MK.groupby(pd.to_datetime(MK.mt,utc=True).dt.strftime('%Y-%m')).size().to_dict(),flush=True)
mkts=list(MK.market_id); parts=[]
for i in range(0,len(mkts),2000):
    parts.append(pd.read_sql("SELECT market_id,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '180 minutes'",con,params=(mkts[i:i+2000],)))
con.close(); P=pd.concat(parts,ignore_index=True); P['tt']=secs(P.ts); P=P.drop_duplicates(['market_id','sel','tt']).sort_values('tt',kind='stable')
print(f"pre-off rows {len(P)}, {time.time()-T0:.0f}s",flush=True)
PX={k:g for k,g in P.groupby('market_id')}; SK=Counter(); rows=[]
for r in MK.itertuples():
    x=PX.get(r.market_id)
    if x is None: SK['no pre-off print']+=1; continue
    o=float(r.off); home,_x,away=r.ev.partition(' v '); pr=mo_pair(home,away,list(x.sel.unique()))
    if pr is None: SK['runners not matched']+=1; continue
    grp=grp_of(group(r.ev),int(((x.tt>=o-3600)&(x.tt<o-1200)).sum())); ent={}
    for s,y in x.groupby('sel',sort=False):
        if s not in RS[r.market_id]: continue
        ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-1200,o-120)
        if i is None: SK['no entry print']+=1; continue
        j=last_in(ts,o-10800,o-3600)
        ent[s]=(ts,px,i,None if j is None else float(px[j]),bool(RS[r.market_id][s]))
    if pr[0] not in ent or pr[1] not in ent: SK['fewer than two teams priced']+=1; continue
    fh=float(ent[pr[0]][1][ent[pr[0]][2]])<=float(ent[pr[1]][1][ent[pr[1]][2]])
    sel=[('FAV',pr[0] if fh else pr[1]),('DOG',pr[1] if fh else pr[0])]+([('DRAW','The Draw')] if 'The Draw' in ent else [])
    for nm,s in sel:
        ts,px,i,early,won=ent[s]
        if early is None: SK['no early print']+=1; continue
        m=mv(float(px[i]),early)
        if m is None: SK['middle, no trade']+=1; continue
        for side in 'BL':
            p=fill(ts,px,i,side)
            if p>50: SK['over 50, not traded']+=1; continue
            v=bk(p,won) if side=='B' else ly(p,won)
            if v is None: SK['bottom of ladder, no back']+=1; continue
            rows.append((r.event_id,grp,o,nm,m,side,p,won,v))
print("counted:",dict(sorted(SK.items())),flush=True)
R=pd.DataFrame(rows,columns='e g off nm m side p won v'.split()); md=np.median(R.off.values); R['h']=np.where(R.off<md,1,2); assert not R.duplicated(['e','nm','side']).any()
print("games traded by group:",R.drop_duplicates('e').groupby('g').size().to_dict(),"median date",pd.to_datetime(md,unit='s'),flush=True)
out=[]
for k,x in R.groupby(['g','nm','m','side']):
    l=line(x.v.values,x.h.values); out.append(dict(g=k[0],sel=k[1],move=k[2],side=k[3],n=l['n'],games=x.e.nunique(),per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),imp=(1/x.p).mean(),PASS=l['PASS']))
O=pd.DataFrame(out).sort_values('t',ascending=False)
print(f"\n== lines {len(O)} of 60, n>=300 {int((O.n>=300).sum())}; by chance about {len(O)*0.05:.0f} reach t>=1.65. Top 15 by t, n>=50"); print(O[O.n>=50].head(15).drop(columns=['n1','n2']).round(3).to_string(index=False))
print("worst 3"); print(O[O.n>=50].tail(3).drop(columns=['n1','n2']).round(3).to_string(index=False))
A=R.groupby(['m','nm','side']).agg(n=('v','size'),per10=('v','mean'),won=('won','mean')).round(3); print("\nall groups pooled, for context:"); print(A.to_string())
S=O[O.PASS]; print(f"\n== SURVIVORS: {len(S)} of {len(O)}\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
