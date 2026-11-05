#!/bin/bash
set -o pipefail
# 499_thin_short_dog_official (Finder 2026-11-05, queue item 156, Finder's own, source c; from jobs/499_thin_long_dog.sh): lay the shorter underdog in a thin senior game, official-result games only. Rule pushed in the queue before this read. Read only.
# As jobs/499_longtail_senior.sh: last MO print T-20 to T-2 on each team, worse of print and next non-in-play print within 120 s, one tick adverse, 2%, £10 liability, hold to Betfair's own WINNER. Women and youth out. THIN: MO prints T-60 to T-20 at or under 6, that job's output cut. Dog: the longer team at the entry print, home is favourite on a tie. Scored: fill under 5.0. Over 50 not traded.
# One bet per event, lowest id if an event holds two. Item 144 read these games at all dog prices, so only the band is new and a pass earns a test on later months, nothing more. ALL and LONG shown for context, not scored. ALL must sit near item 144's n 646 +0.272; it can move only if bf_hist_result has grown.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import norm,jac,line
from lib_official import group,ly,fill,last_in,secs,load_results,checks
import lib_cand; lib_cand._checks(); checks()
THIN=6; CUT=5.0
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
def band(p): return 'SHORT' if p<CUT else 'LONG'
def dog_of(ph,pa): return 'A' if ph<=pa else 'H'
# known answers: the band edge, the favourite on a tie, the lay at the scored edge (fill 4.9 -> 5.0, stake 2.5, wins 2.45 after 2%, loses 10)
assert band(4.9)=='SHORT' and band(5.0)=='LONG' and band(1.5)=='SHORT' and band(50)=='LONG'
assert dog_of(2.0,3.0)=='A' and dog_of(3.0,2.0)=='H' and dog_of(2.5,2.5)=='A'
assert abs(ly(4.9,False)-2.45)<1e-9 and ly(4.9,True)==-10.0
print("checks: OK",flush=True); T0=time.time()
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
RS,bad=load_results(con,['MATCH_ODDS']); print(f"MO markets with one WINNER {len(RS)}, dropped {bad}",flush=True)
cur.execute("SELECT DISTINCT market_id,event_id,event_name,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s)",(list(RS),))
MK=pd.DataFrame(cur.fetchall(),columns='market_id event_id ev mt'.split()); MK['off']=secs(MK.mt)
n0=len(MK); MK=MK.sort_values('market_id').drop_duplicates('event_id'); print(f"MO markets on the tape {n0}, events {len(MK)}, second ids dropped {n0-len(MK)}, dates {MK.mt.min()} to {MK.mt.max()}",flush=True)
print("events by month:",MK.groupby(pd.to_datetime(MK.mt,utc=True).dt.strftime('%Y-%m')).size().to_dict(),flush=True)
mkts=list(MK.market_id); parts=[]
for i in range(0,len(mkts),2000):
    parts.append(pd.read_sql("SELECT market_id,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND NOT inplay AND ltp>=1.01 AND ltp<1000",con,params=(mkts[i:i+2000],)))
con.close(); P=pd.concat(parts,ignore_index=True); P['tt']=secs(P.ts); P=P.drop_duplicates(['market_id','sel','tt']).sort_values('tt',kind='stable')
print(f"pre-off rows {len(P)}, {time.time()-T0:.0f}s",flush=True)
PX={k:g for k,g in P.groupby('market_id')}; C=Counter(); rows=[]
for r in MK.itertuples():
    if group(r.ev) is not None: C['women or youth']+=1; continue
    g=PX.get(r.market_id)
    if g is None: C['no pre-off print']+=1; continue
    o=float(r.off); hm,_x,aw=r.ev.partition(' v '); pr=mo_pair(hm,aw,list(g.sel.unique()))
    if pr is None: C['runners not matched']+=1; continue
    if int(((g.tt>=o-3600)&(g.tt<o-1200)).sum())>THIN: C['not thin']+=1; continue
    ent={}
    for s in pr:
        if s not in RS[r.market_id]: continue
        y=g[g.sel==s]; ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-1200,o-120)
        if i is not None: ent[s]=(ts,px,i)
    if len(ent)<2: C['no print on both teams']+=1; continue
    d=dog_of(float(ent[pr[0]][1][ent[pr[0]][2]]),float(ent[pr[1]][1][ent[pr[1]][2]])); dog=pr[1] if d=='A' else pr[0]
    ts,px,i=ent[dog]; p=fill(ts,px,i,'L')
    if p>50: C['over 50']+=1; continue
    won=bool(RS[r.market_id][dog]); rows.append((r.event_id,o,band(p),won,1/p,p,ly(p,won)))
print("counted:",dict(sorted(C.items())),flush=True)
R=pd.DataFrame(rows,columns='e off b won imp p v'.split()); md=np.median(R.off.values); R['h']=np.where(R.off<md,1,2); assert R.e.is_unique
print(f"thin traded games {len(R)}, median date {pd.to_datetime(md,unit='s')}",flush=True)
out=[]
for nm,x in (('THIN SHORT, dog under 5.0 (scored)',R[R.b=='SHORT']),('THIN LONG, dog 5.0+ (context)',R[R.b=='LONG']),('THIN ALL (regression, 144 n 646 +0.272)',R)):
    l=line(x.v.values,x.h.values); out.append(dict(line=nm,n=l['n'],games=x.e.nunique(),per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),imp=x.imp.mean(),PASS=l['PASS']))
O=pd.DataFrame(out); pd.set_option('display.width',220); pd.set_option('display.max_columns',30); print("\n"+O.round(3).to_string(index=False))
S=O[O.PASS&O.line.str.contains('scored')]; print(f"\n== SURVIVORS: {len(S)} of 1\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
