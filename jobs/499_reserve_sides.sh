#!/bin/bash
set -o pipefail
# 499_reserve_sides (Finder 2026-11-06, queue item 274, Finder's own, source c): reserve sides (II, B, Reserves, Jong) before the off, held to the official result. Read only. No tables written. Rule is in the queue, fixed before prices.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,re,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
from lib_official import bk,ly,fill,last_in,secs,checks,group,load_results
import lib_cand; lib_cand._checks(); checks()
RES=re.compile(r"( II| B| Reserves?)$|^Jong ")
def cls(ev):
    """Reserve class of an event name, from the home and away sides. None if not 'H v A'."""
    if ' v ' not in ev: return None,None,None
    h,a=ev.split(' v ',1); rh,ra=bool(RES.search(h)),bool(RES.search(a))
    return ('BOTH' if rh and ra else 'HOME' if rh else 'AWAY' if ra else 'NONE'),h,a
assert cls('Espanyol B v UE Sant Andreu')[0]=='HOME' and cls('De Graafschap v Jong FC Utrecht')[0]=='AWAY' and cls('Jong Ajax Amsterdam v Jong AZ Alkmaar')[0]=='BOTH'
assert cls('Schalke 04 II v FC Koln II')[0]=='BOTH' and cls('Leeds v Hull')[0]=='NONE' and cls('Bayern Munich v Union Berlin')[0]=='NONE' and cls('Arsenal')[0] is None and cls('Club Brugge B v FC Liege')[1]=='Club Brugge B'
assert secs(pd.Series([pd.Timestamp('2024-01-01',tz='UTC')])).iloc[0]==1704067200
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
TY=['MATCH_ODDS','OVER_UNDER_25','BOTH_TEAMS_TO_SCORE']
RX=r"( II| B| Reserves?)( v |$)|(^| v )Jong "
P=pd.read_sql("SELECT market_id,event_id,event_name ev,market_type ty,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type=ANY(%s) AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '20 minutes' AND ts<=market_time AND market_time>='2024-01-01' AND market_time<'2026-11-01' AND (event_name ~ %s OR abs(hashtext(event_id))%%8=0)",con,params=(TY,RX))
print("rows",len(P),f"{time.time()-T0:.0f}s",flush=True)
RS,dropped=load_results(con,TY); con.close(); print("markets with one winner",len(RS),"dropped, not one winner",dropped,flush=True)
P['tt']=secs(P.ts); P['off']=secs(P.mt); P=P.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt'])
C=Counter(); rows=[]; seen=set()
for m,g in P.groupby('market_id',sort=True):
    ev,ty=g.ev.iloc[0],g.ty.iloc[0]; o=float(g.off.iloc[0])
    if (ev,ty,o) in seen: C['second id']+=1; continue
    seen.add((ev,ty,o))
    k,h,a=cls(ev)
    if k is None: C['no H v A']+=1; continue
    if group(ev): C['women or youth']+=1; continue
    if m not in RS: C['no official result, '+ty]+=1; continue
    R=RS[m]
    for s,y in g.groupby('sel',sort=False):
        if s not in R: C['runner not in result']+=1; continue
        ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-1200,o-120)
        if i is None: C['no print']+=1; continue
        pb,pl=fill(ts,px,i,'B'),fill(ts,px,i,'L')
        if ty=='MATCH_ODDS':
            who='DRAW' if s=='The Draw' else 'H' if s==h else 'A' if s==a else None
            if who is None: C['MO name mismatch']+=1; continue
        elif ty=='OVER_UNDER_25': who='OVER' if s.startswith('Over') else 'UNDER'
        else: who=s.upper()
        vb=bk(pb,R[s]) if pb<=50 else None; vl=ly(pl,R[s]) if pl<=50 else None
        rows.append((k,ty,who,o,vb,vl))
print("counted:",dict(sorted(C.items())),flush=True)
D=pd.DataFrame(rows,columns='k ty who off vb vl'.split()); md=float(np.median(D[D.k!='NONE'].off)); print("trades",len(D),"by class",D.groupby(['k','ty']).size().to_dict(),"halves split at",pd.Timestamp(md,unit='s',tz='UTC'),flush=True)
out=[]
def add(nm,x):
    for sd,c in (('back','vb'),('lay','vl')):
        z=x[x[c].notna()]
        if len(z)<30: continue
        l=line(z[c].astype(float).values,np.where(z.off<md,1,2)); out.append(dict(line=nm+' '+sd,n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],PASS=l['PASS']))
for k,mask in (('ANY',D.k.isin(['HOME','AWAY','BOTH'])),('HOME',D.k=='HOME'),('AWAY',D.k=='AWAY'),('BOTH',D.k=='BOTH'),('CONTROL',D.k=='NONE')):
    for ty,w in (('OVER_UNDER_25','OVER'),('OVER_UNDER_25','UNDER'),('BOTH_TEAMS_TO_SCORE','YES'),('BOTH_TEAMS_TO_SCORE','NO')):
        add(f"{k} {w}",D[mask&(D.ty==ty)&(D.who==w)])
for k,lab in (('HOME',{'H':'reserve','A':'opponent','DRAW':'draw'}),('AWAY',{'A':'reserve','H':'opponent','DRAW':'draw'})):
    for w,nm in lab.items(): add(f"{k} MO {nm}",D[(D.k==k)&(D.ty=='MATCH_ODDS')&(D.who==w)])
for w,nm in (('H','home'),('A','away'),('DRAW','draw')): add(f"CONTROL MO {nm}",D[(D.k=='NONE')&(D.ty=='MATCH_ODDS')&(D.who==w)])
L=pd.DataFrame(out); print(f"\nlines {len(L)}, passing {int(L.PASS.sum())}")
print(L.sort_values('t',ascending=False).head(15).round(3).to_string(index=False))
print("\nCONTROL lines"); print(L[L.line.str.startswith('CONTROL')].round(3).to_string(index=False))
print("\n== SURVIVORS"); S=L[L.PASS&~L.line.str.startswith('CONTROL')]; print(S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
