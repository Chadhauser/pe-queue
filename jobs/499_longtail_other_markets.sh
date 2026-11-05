#!/bin/bash
set -o pipefail
# 499_longtail_other_markets (Finder 2026-11-05, queue item 157, Finder's own, source c; from jobs/499_longtail_senior.sh): the official-result markets item 144 never read, before the off. Rule pushed in the queue before these prices were read. Read only.
# ENTRY last non-in-play print T-20 to T-2 min, worse of it and the next non-in-play print within 120 s, one tick adverse, 2%, £10 risk, hold to the official result. Over 50 not traded, counted. Lowest id per event per market. Market without exactly one WINNER dropped, counted.
# GROUPS WOMEN, YOUTH by event name; other games S_THIN, S_MID, S_DEEP by MO prints T-60 to T-20 at item 144's cuts of 6 and 14. No MO market = dropped, counted. 130 lines, one bet per game per line, lines share games. Prints only: a pass is an upper bound and only earns an unseen-months test.
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
assert mo_pair('Menemen Bld','Bursaspor',['Bursaspor','The Draw','Menemen Belediyespor'])==('Menemen Belediyespor','Bursaspor')
assert mo_pair('Hull','Leeds',['Leeds','Hull'])==('Hull','Leeds') and mo_pair('Hull','Leeds',['Hull','The Draw']) is None
assert grp_of(float('nan'),6)=='S_THIN' and grp_of(float('nan'),7)=='S_MID' and grp_of(float('nan'),14)=='S_MID' and grp_of(float('nan'),15)=='S_DEEP' and grp_of(None,15)=='S_DEEP' and grp_of('YOUTH',1)=='YOUTH'
print("checks: OK",flush=True)
pd.set_option('display.width',250); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time()
LINES={'OVER_UNDER_05':'OU05','OVER_UNDER_45':'OU45','FIRST_HALF_GOALS_15':'FH15','FIRST_HALF_GOALS_25':'FH25'}
TEAMS={'HALF_TIME':'HT','DRAW_NO_BET':'DNB'}
TYPES={**LINES,**TEAMS}
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
RS,bad=load_results(con,list(TYPES)+['MATCH_ODDS']); print(f"markets with one WINNER {len(RS)}, dropped {bad}",flush=True)
cur.execute("SELECT DISTINCT market_id,event_id,event_name,market_type,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s)",(list(RS),))
MK=pd.DataFrame(cur.fetchall(),columns='market_id event_id ev mty mt'.split()); MK['off']=secs(MK.mt)
n0=len(MK); MK=MK.sort_values('market_id').drop_duplicates(['event_id','mty']); print(f"markets on the tape {n0}, second ids dropped {n0-len(MK)}, events {MK.event_id.nunique()}, dates {MK.mt.min()} to {MK.mt.max()}",flush=True)
E1=MK.drop_duplicates('event_id'); print("events by month:",E1.groupby(pd.to_datetime(E1.mt,utc=True).dt.strftime('%Y-%m')).size().to_dict(),flush=True)
print("markets by type:",MK.groupby('mty').size().to_dict(),flush=True)
parts=[]
for mset,cols in ((list(MK[MK.mty.isin(TYPES)].market_id),'all'),(list(MK[MK.mty=='MATCH_ODDS'].market_id),'mo')):
    for i in range(0,len(mset),2000):
        parts.append(pd.read_sql("SELECT market_id,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '60 minutes'",con,params=(mset[i:i+2000],)))
con.close(); P=pd.concat(parts,ignore_index=True); P['tt']=secs(P.ts); P=P.drop_duplicates(['market_id','sel','tt']).sort_values('tt',kind='stable')
print(f"pre-off rows {len(P)}, {time.time()-T0:.0f}s",flush=True)
PX={k:g for k,g in P.groupby('market_id')}; SK=Counter(); rows=[]
for e,g in MK.groupby('event_id'):
    ev=g.ev.iloc[0]; off=float(g.off.iloc[0]); home,_x,away=ev.partition(' v '); mo=g[g.mty=='MATCH_ODDS']
    if not len(mo): SK['no MO market, game dropped']+=1; continue
    x0=PX.get(mo.market_id.iloc[0]); o0=float(mo.off.iloc[0])
    liqv=int(((x0.tt>=o0-3600)&(x0.tt<o0-1200)).sum()) if x0 is not None else 0
    grp=grp_of(group(ev),liqv)
    for r in g.itertuples():
        if r.mty=='MATCH_ODDS': continue
        x=PX.get(r.market_id); k=TYPES[r.mty]; o=float(r.off)
        if x is None: SK[k+' no pre-off print']+=1; continue
        ent={}
        for s,y in x.groupby('sel',sort=False):
            if s not in RS[r.market_id]: SK['print on a runner with no result']+=1; continue
            ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-1200,o-120)
            if i is None: SK[k+' no print in window']+=1; continue
            ent[s]=(ts,px,i,bool(RS[r.market_id][s]))
        def add(nm,key):
            ts,px,i,won=ent[key]
            for side in 'BL':
                p=fill(ts,px,i,side)
                if p>50: SK['over 50, not traded']+=1; continue
                v=bk(p,won) if side=='B' else ly(p,won)
                if v is None: SK['bottom of ladder, no back']+=1; continue
                rows.append((e,grp,off,nm,side,p,won,v))
        if r.mty in LINES:
            for s in ent:
                sl=str(s).strip().lower()
                if sl.startswith('over') or sl.startswith('under'): add(f"{k} {sl.split()[0].title()}",s)
        else:
            pair=mo_pair(home,away,list(ent))
            if pair:
                fh=float(ent[pair[0]][1][ent[pair[0]][2]])<=float(ent[pair[1]][1][ent[pair[1]][2]]); add(k+' FAV',pair[0] if fh else pair[1]); add(k+' DOG',pair[1] if fh else pair[0])
            elif len([s for s in ent if str(s).strip().lower()!='the draw'])==2: SK[k+' two teams priced, names not matched']+=1
            else: SK[k+' fewer than two teams priced']+=1
            if 'The Draw' in ent: add(k+' DRAW','The Draw')
print("counted:",dict(sorted(SK.items())),flush=True)
R=pd.DataFrame(rows,columns='e g off nm side p won v'.split()); md=np.median(R.off.values); R['h']=np.where(R.off<md,1,2)
print("games by group:",R.drop_duplicates('e').groupby('g').size().to_dict(),"median date",pd.to_datetime(md,unit='s'),flush=True)
assert not R.duplicated(['e','nm','side']).any()
out=[]
for k,x in R.groupby(['g','nm','side']):
    l=line(x.v.values,x.h.values); out.append(dict(g=k[0],sel=k[1],side=k[2],n=l['n'],games=x.e.nunique(),per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),imp=(1/x.p).mean(),PASS=l['PASS']))
O=pd.DataFrame(out).sort_values('t',ascending=False)
print(f"\n== lines {len(O)}, n>=300 {int((O.n>=300).sum())}; by chance about {len(O)*0.05:.0f} reach t>=1.65. Top 15 by t, n>=100"); print(O[O.n>=100].head(15).drop(columns=['n1','n2']).round(3).to_string(index=False))
print("worst 3"); print(O[O.n>=100].tail(3).drop(columns=['n1','n2']).round(3).to_string(index=False))
A=R.groupby(['nm','side']).agg(n=('v','size'),per10=('v','mean'),won=('won','mean')).round(3); print("\nall groups pooled, for context:"); print(A.to_string())
S=O[O.PASS]; print(f"\n== SURVIVORS: {len(S)} of {len(O)}\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
