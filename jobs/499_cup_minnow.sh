#!/bin/bash
set -o pipefail
# 499_cup_minnow (Finder 2026-11-06, queue item 287, Finder's own, source c; from jobs/499_cup_ties.sh): a side on the league tables against a side below them, Sep to May, before the off. Rule pushed in the queue before any price. Read only. No tables written. Prints only, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,re,time,bisect,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
from lib_official import bk,ly,fill,last_in,secs,checks,group,load_results
import lib_cand; lib_cand._checks(); checks()
TIER={39:('GB',1),40:('GB',2),41:('GB',3),42:('GB',4),78:('DE',1),79:('DE',2),61:('FR',1),62:('FR',2),135:('IT',1),136:('IT',2),140:('ES',1),141:('ES',2)}
UEFA={2,3}; DAY=86400.0
RES=re.compile(r"( II| B| Reserves?)$|^Jong ")
def nearest(lst,t,w=60*DAY):
    if not lst: return None
    i=bisect.bisect_left(lst,(t,-1)); best=None
    for j in (i-1,i):
        if 0<=j<len(lst) and (best is None or abs(lst[j][0]-t)<abs(best[0]-t)): best=lst[j]
    return best[1] if abs(best[0]-t)<=w else None
def role(s,h,a): return 'DRAW' if s=='The Draw' else 'H' if s==h else 'A' if s==a else None
assert nearest([(0.,39),(100*DAY,40)],10*DAY)==39 and nearest([(0.,39)],61*DAY) is None and role('The Draw','X','Y')=='DRAW' and role('X','X','Y')=='H' and role('Z','X','Y') is None
assert RES.search('Espanyol B') and not RES.search('Leeds') and secs(pd.Series([pd.Timestamp('2024-01-01',tz='UTC')])).iloc[0]==1704067200
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=pd.read_sql("SELECT fixture_id,league_id,kickoff,home,away FROM af_fixtures WHERE season>=2023",con); F['tt']=secs(F.kickoff)
M=pd.read_sql("SELECT DISTINCT ON (p.event_id) p.event_id,p.event_name,substr(m.understat_id,3)::bigint fixture_id FROM af_price_map m JOIN bf_hist_price p ON p.event_id=m.event_id AND p.mkt='MO' AND p.sel='HOME' AND p.minute=1",con)
BADMAP=re.compile(r"U-?(1[5-9]|2[0-3])\b|\(W\)|\bWomen\b| II\b| B( v |$)| Reserves?( v |$)|^Jong | v Jong ")   # about 1% of af_price_map names a youth, women's or reserve game but points at a senior fixture, found 2026-11-06; first run tied such names to the wrong club
assert BADMAP.search("Dag and Red v Nottingham Forest U21") and BADMAP.search("Espanyol B v Hull") and not BADMAP.search("Hull v Leeds")
fx=F.set_index('fixture_id'); NM={}
for r in M.itertuples():
    if r.fixture_id not in fx.index or ' v ' not in r.event_name or BADMAP.search(r.event_name): continue
    h,a=r.event_name.split(' v ',1); f=fx.loc[r.fixture_id]; NM[h]=f.home; NM[a]=f.away
HIST=defaultdict(list); ALL=defaultdict(list)
for r in F.itertuples():
    ALL[r.home].append(r.tt); ALL[r.away].append(r.tt)
    if r.league_id not in UEFA: HIST[r.home].append((r.tt,r.league_id)); HIST[r.away].append((r.tt,r.league_id))
for k in HIST: HIST[k].sort()
print("BF names tied",len(NM),f"{time.time()-T0:.0f}s",flush=True)
TY=['MATCH_ODDS','OVER_UNDER_25']; parts=[]
for lo,hi in (('2024-01-01','2024-04-01'),('2024-04-01','2024-06-01'),('2024-09-01','2024-12-01'),('2026-05-01','2026-06-01'),('2026-09-01','2026-11-01')):
    X=pd.read_sql("SELECT market_id,event_name ev,country,market_type ty,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type=ANY(%s) AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '20 minutes' AND ts<=market_time AND market_time>=%s AND market_time<%s AND country=ANY(%s)",con,params=(TY,lo,hi,['GB','DE','FR','IT','ES']))
    sp=X.ev.str.split(' v ',n=1,expand=True); X=X[sp[0].isin(NM)^sp[1].isin(NM)]; parts.append(X); print(lo,"prints kept",len(X),f"{time.time()-T0:.0f}s",flush=True)
P=pd.concat(parts,ignore_index=True); del parts
RS,dropped=load_results(con,TY); con.close(); print("markets with one winner",len(RS),flush=True)
P['tt']=secs(P.ts); P['off']=secs(P.mt); P=P.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt'])
C=Counter(); rows=[]; seen=set()
for m,g in P.groupby('market_id',sort=True):
    ev,ty,cn=g.ev.iloc[0],g.ty.iloc[0],g.country.iloc[0]; o=float(g.off.iloc[0])
    if (ev,ty,o) in seen: C['second id']+=1; continue
    seen.add((ev,ty,o))
    if group(ev): C['women or youth']+=1; continue
    h,a=ev.split(' v ',1)
    if RES.search(h) or RES.search(a): C['reserve name']+=1; continue
    kn,other=(h,a) if h in NM else (a,h)
    af=NM[kn]
    if any(abs(t-o)<=DAY for t in ALL.get(af,[])): C['known side has an af game within 1 day']+=1; continue
    lg=nearest(HIST[af],o)
    if lg not in TIER: C['known league not in the tier list']+=1; continue
    if TIER[lg][0]!=cn: C['country does not match the league']+=1; continue
    if m not in RS: C['no official result, '+ty]+=1; continue
    R=RS[m]; side='KNOWN_HOME' if kn==h else 'KNOWN_AWAY'; top=TIER[lg][1]==1
    for s,y in g.groupby('sel',sort=False):
        if s not in R: C['runner not in result']+=1; continue
        ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-1200,o-120)
        if i is None: C['no print']+=1; continue
        pb,pl=fill(ts,px,i,'B'),fill(ts,px,i,'L')
        if ty=='MATCH_ODDS':
            w=role(s,h,a)
            if w is None: C['MO name mismatch']+=1; continue
            who='DRAW' if w=='DRAW' else 'KNOWN' if (w=='H')==(kn==h) else 'MINNOW'
        else: who='OVER' if s.startswith('Over') else 'UNDER'
        rows.append((side,top,ty,who,o,R[s],pb,pl,None if pb>50 else bk(pb,R[s]),None if pl>50 else ly(pl,R[s]),ev))
print("counted:",dict(sorted(C.items())),flush=True)
D=pd.DataFrame(rows,columns='side top ty who off won pb pl vb vl ev'.split())
mo=D[D.ty=='MATCH_ODDS']; print("games MO",mo.groupby('side').ev.nunique().to_dict(),"by month",mo.drop_duplicates(['ev','off']).assign(m=lambda z:pd.to_datetime(z.off,unit='s').dt.strftime('%Y-%m')).groupby('m').size().to_dict(),flush=True)
print("sample KNOWN_AWAY:",mo[mo.side=='KNOWN_AWAY'].ev.drop_duplicates().head(14).tolist(),flush=True)
print("sample KNOWN_HOME:",mo[mo.side=='KNOWN_HOME'].ev.drop_duplicates().head(14).tolist(),flush=True)
md=float(np.median(D.off)); print("halves split at",pd.Timestamp(md,unit='s',tz='UTC'),flush=True); out=[]
def add(nm,x):
    for sd,c,pc in (('back','vb','pb'),('lay','vl','pl')):
        z=x[x[c].notna()]
        if len(z)<30: out.append(dict(line=nm+' '+sd,n=len(z),PASS=False)); continue
        l=line(z[c].astype(float).values,np.where(z.off<md,1,2)); out.append(dict(line=nm+' '+sd,n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],maxwin=l['maxwin'],won=z.won.astype(float).mean(),imp=(1/z[pc]).mean(),PASS=l['PASS']))
for s_ in ('KNOWN_AWAY','KNOWN_HOME'):
    for w in ('KNOWN','MINNOW','DRAW'):
        add(f"{s_} {w}",mo[(mo.side==s_)&(mo.who==w)]); add(f"{s_} top tier {w}",mo[(mo.side==s_)&mo.top&(mo.who==w)])
    for w in ('OVER','UNDER'): add(f"{s_} {w}",D[(D.side==s_)&(D.who==w)])
L=pd.DataFrame(out); print(f"\nlines {len(L)}, passing {int(L.PASS.sum())}"); print(L.sort_values('t',ascending=False).round(3).to_string(index=False))
print("\nthe line that answers 284:"); print(L[L.line=='KNOWN_AWAY KNOWN back'].round(3).to_string(index=False))
S=L[L.PASS==True]; print(f"\n== SURVIVORS: {len(S)} of {len(L)} scored\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
