#!/bin/bash
set -o pipefail
# 499_national_teams (Finder 2026-11-06, queue item 290, Finder's own, source c; entry from jobs/499_cup_ties.sh): senior national sides before the off, and the finals. Rule pushed in the queue before any price. Read only. No tables written. Prints only, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_500_000_000,2_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
from lib_official import bk,ly,fill,last_in,secs,checks,group,load_results
import lib_cand; lib_cand._checks(); checks()
BIG={'Argentina','Brazil','England','France','Germany','Italy','Netherlands','Portugal','Spain'}
NAT=BIG|set("""Albania|Algeria|Andorra|Angola|Armenia|Australia|Austria|Azerbaijan|Bahrain|Belarus|Belgium|Bolivia|Bosnia|Bosnia and Herzegovina|Bosnia-Herzegovina|Bulgaria|Burkina Faso|Cameroon|Canada|Cape Verde|Chile|China|Colombia|Costa Rica|Croatia|Curacao|Cyprus|Czech Republic|Czechia|DR Congo|Denmark|Ecuador|Egypt|El Salvador|Estonia|Faroe Islands|Finland|Georgia|Ghana|Gibraltar|Greece|Guatemala|Haiti|Honduras|Hungary|Iceland|Indonesia|Iran|Iraq|Israel|Ivory Coast|Jamaica|Japan|Jordan|Kazakhstan|Kosovo|Kuwait|Latvia|Lebanon|Liechtenstein|Lithuania|Luxembourg|Malta|Mali|Mexico|Moldova|Montenegro|Morocco|New Zealand|Nigeria|North Macedonia|Northern Ireland|Norway|Oman|Palestine|Panama|Paraguay|Peru|Poland|Qatar|Rep of Ireland|Republic of Ireland|Romania|Russia|San Marino|Saudi Arabia|Scotland|Senegal|Serbia|Slovakia|Slovenia|South Africa|South Korea|Sweden|Switzerland|Syria|Thailand|Trinidad and Tobago|Tunisia|Turkey|Turkiye|UAE|USA|Ukraine|Uruguay|Uzbekistan|Venezuela|Vietnam|Wales""".split('|'))
FIN=((pd.Timestamp('2024-06-14',tz='UTC').timestamp(),pd.Timestamp('2024-07-15',tz='UTC').timestamp()),(pd.Timestamp('2026-06-11',tz='UTC').timestamp(),pd.Timestamp('2026-07-20',tz='UTC').timestamp()))
def finals(t): return any(a<=t<b for a,b in FIN)
assert finals(pd.Timestamp('2024-07-14 20:00',tz='UTC').timestamp()) and not finals(pd.Timestamp('2024-07-15 01:00',tz='UTC').timestamp()) and finals(pd.Timestamp('2026-06-11',tz='UTC').timestamp()) and not finals(pd.Timestamp('2025-06-20',tz='UTC').timestamp())
assert 'Wales' in NAT and 'Leeds' not in NAT and len(NAT)>100
assert secs(pd.Series([pd.Timestamp('2024-01-01',tz='UTC')])).iloc[0]==1704067200
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',100)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
TY=['MATCH_ODDS','OVER_UNDER_25']; parts=[]; MON=pd.date_range('2024-01-01','2024-12-01',freq='MS').tolist()+pd.date_range('2026-05-01','2026-11-01',freq='MS').tolist()
for a_,b_ in zip(MON[:-1],MON[1:]):
    if (b_-a_).days>31: continue
    X=pd.read_sql("SELECT market_id,event_name ev,market_type ty,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type=ANY(%s) AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '20 minutes' AND ts<=market_time AND market_time>=%s AND market_time<%s AND event_name LIKE '%% v %%'",con,params=(TY,a_,b_))
    if X.empty: print(a_.date(),"no prints",flush=True); continue
    sp=X.ev.str.split(' v ',n=1,expand=True); X=X[sp[0].isin(NAT)&sp[1].isin(NAT)]; parts.append(X)
    print(a_.date(),"prints kept",len(X),"events",X.ev.nunique(),f"{time.time()-T0:.0f}s",flush=True)
P=pd.concat(parts,ignore_index=True); del parts
RS,dropped=load_results(con,TY); con.close(); print("markets with one winner",len(RS),flush=True)
P['tt']=secs(P.ts); P['off']=secs(P.mt); P=P.sort_values('tt',kind='stable').drop_duplicates(['market_id','sel','tt'])
# favourite, from the MO prints only
FAV={}
for (ev,o),g in P[P.ty=='MATCH_ODDS'].groupby(['ev','off']):
    h,a=ev.split(' v ',1); L={}
    for s in (h,a):
        y=g[g.sel==s]
        if len(y):
            i=last_in(y.tt.values,o-1200,o-120)
            if i is not None: L[s]=float(y.ltp.values[i])
    if len(L)==2 and L[h]!=L[a]: FAV[(ev,o)]=h if L[h]<L[a] else a
C=Counter(); rows=[]; seen=set()
for m,g in P.groupby('market_id',sort=True):
    ev,ty=g.ev.iloc[0],g.ty.iloc[0]; o=float(g.off.iloc[0])
    if (ev,ty,o) in seen: C['second id']+=1; continue
    seen.add((ev,ty,o))
    if group(ev): C['women or youth']+=1; continue
    if m not in RS: C['no official result, '+ty]+=1; continue
    R=RS[m]; fav=FAV.get((ev,o)); fi=finals(o); big=fav in BIG
    if ty=='MATCH_ODDS' and fav is None: C['MO favourite not known']+=1; continue
    h,a=ev.split(' v ',1)
    for s,y in g.groupby('sel',sort=False):
        if s not in R: C['runner not in result']+=1; continue
        ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-1200,o-120)
        if i is None: C['no print']+=1; continue
        pb,pl=fill(ts,px,i,'B'),fill(ts,px,i,'L')
        if ty=='MATCH_ODDS':
            if s=='The Draw': who='DRAW'
            elif s==fav: who='FAV'
            elif s in (h,a): who='OUT'
            else: C['MO name mismatch']+=1; continue
        else: who='OVER' if s.startswith('Over') else 'UNDER'
        rows.append((ev,ty,who,o,fi,big,R[s],pb,pl,None if pb>50 else bk(pb,R[s]),None if pl>50 else ly(pl,R[s])))
print("counted:",dict(sorted(C.items())),flush=True)
if not rows: print("\n== SURVIVORS: 0, no market with both a national side's prices and an official result; BLOCKED, item 290"); sys.exit(0)
D=pd.DataFrame(rows,columns='ev ty who off fi big won pb pl vb vl'.split()); mo=D[D.ty=='MATCH_ODDS'].drop_duplicates(['ev','off'])
print("games",len(mo),"finals",int(mo.fi.sum()),"big favourite",int(mo.big.sum()),"by month",mo.assign(m=lambda z:pd.to_datetime(z.off,unit='s').dt.strftime('%Y-%m')).groupby('m').size().to_dict(),flush=True)
print("sample:",mo.ev.head(10).tolist(),flush=True)
md=float(np.median(D.off)); print("halves split at",pd.Timestamp(md,unit='s',tz='UTC'),flush=True); out=[]
def add(nm,x):
    for sd,c,pc in (('back','vb','pb'),('lay','vl','pl')):
        z=x[x[c].notna()]
        if len(z)<30: out.append(dict(line=nm+' '+sd,n=len(z),PASS=False)); continue
        l=line(z[c].astype(float).values,np.where(z.off<md,1,2)); out.append(dict(line=nm+' '+sd,n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],maxwin=l['maxwin'],won=z.won.astype(float).mean(),imp=(1/z[pc]).mean(),PASS=l['PASS']))
M=D[D.ty=='MATCH_ODDS']; O=D[D.ty=='OVER_UNDER_25']
for nm,x in (('ALL',M),('FINALS',M[M.fi]),('BIG',M[M.big])):
    for w in ('FAV','OUT','DRAW'): add(f"{nm} {w}",x[x.who==w])
for nm,x in (('ALL',O),('FINALS',O[O.fi])):
    for w in ('OVER','UNDER'): add(f"{nm} {w}",x[x.who==w])
L=pd.DataFrame(out); print(f"\nlines {len(L)}, passing {int(L.PASS.sum())}"); print(L.sort_values('t',ascending=False).round(3).to_string(index=False))
S=L[L.PASS==True]; print(f"\n== SURVIVORS: {len(S)} of {len(L)} scored\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
