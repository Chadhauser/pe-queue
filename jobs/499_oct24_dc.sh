#!/bin/bash
set -o pipefail
# 499_oct24_dc (Finder 2026-11-05, queue item 164, the double-chance part; from jobs/499_oct24_lines.sh): that job lost every DOUBLE_CHANCE market, as lib_official.load_results keeps markets with exactly one WINNER and a double-chance market has two. Same rule, pushed before any price was read (commit e987e9e). Read only.
# RULE last non-in-play print T-20 to T-2, worse of it and the next within 120 s, one tick adverse, 2%, £10 risk, official result, over 50 not traded. Lowest id per event. Runners mapped by the MO favourite at entry. A market without exactly two WINNERs and one LOSER is dropped, counted. Fit from 1 May 2026, test Oct 2024. Six lines, so all six are read; the 10-line limit does not bind.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(3_000_000_000,3_000_000_000))  # this job only
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,norm,jac
from lib_official import bk,ly,fill,last_in,secs,load_results,checks
import lib_cand; lib_cand._checks(); checks()
def mo_pair(home,away,runners):
    r=[x for x in runners if str(x).strip().lower()!='the draw']
    if len(r)!=2: return None
    H,A,a,b=norm(home),norm(away),norm(r[0]),norm(r[1])
    s1,s2=jac(a,H)+jac(b,A),jac(a,A)+jac(b,H)
    if s1==s2: return None
    x,y=(r[0],r[1]) if s1>s2 else (r[1],r[0])
    if not (norm(x)&H and norm(y)&A): return None
    return x,y
def dc(sel,home_fav):
    s=str(sel).strip().lower()
    if s=='home or away': return 'FAV_DOG'
    if s=='home or draw': return 'FAV_DRAW' if home_fav else 'DOG_DRAW'
    if s=='draw or away': return 'DOG_DRAW' if home_fav else 'FAV_DRAW'
    return None
def dc_ok(st):
    """status list for one market: exactly two WINNER and one LOSER."""
    return sorted(st)==['LOSER','WINNER','WINNER']
assert dc('Home or Draw',True)=='FAV_DRAW' and dc('Draw or Away',True)=='DOG_DRAW' and dc('Draw or Away',False)=='FAV_DRAW' and dc('Home or Away',False)=='FAV_DOG'
assert dc_ok(['WINNER','LOSER','WINNER']) and not dc_ok(['WINNER','LOSER','LOSER']) and not dc_ok(['WINNER','WINNER'])
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',230); pd.set_option('display.max_columns',30)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
D=pd.read_sql("SELECT market_id,sel,status FROM bf_hist_result WHERE sport='Soccer' AND market_type='DOUBLE_CHANCE'",con)
ok=D.groupby('market_id').status.apply(lambda s:dc_ok(list(s))); print("DC markets",len(ok),"two winners and one loser",int(ok.sum()),flush=True)
RD={m:dict(zip(g.sel,g.status=='WINNER')) for m,g in D[D.market_id.isin(set(ok[ok].index))].groupby('market_id')}
RM,bad=load_results(con,['MATCH_ODDS'])
cur.execute("SELECT DISTINCT market_id,event_id,event_name,market_type,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_type IN ('MATCH_ODDS','DOUBLE_CHANCE') AND (market_time>='2026-05-01' OR (market_time>='2024-10-01' AND market_time<'2024-11-01'))")
MK=pd.DataFrame(cur.fetchall(),columns='market_id event_id ev mty mt'.split()); MK['off']=secs(MK.mt)
MK=MK[[(m in RD) if t=='DOUBLE_CHANCE' else (m in RM) for m,t in zip(MK.market_id,MK.mty)]].sort_values('market_id').drop_duplicates(['event_id','mty']); print("markets",MK.groupby('mty').size().to_dict(),flush=True)
mk=list(MK.market_id); parts=[]
for i in range(0,len(mk),2000): parts.append(pd.read_sql("SELECT market_id,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '21 min'",con,params=(mk[i:i+2000],)))
con.close(); P=pd.concat(parts,ignore_index=True); P['tt']=secs(P.ts); P=P.drop_duplicates(['market_id','sel','tt']).sort_values('tt',kind='stable'); PX={k:g for k,g in P.groupby('market_id')}; del P
SK=Counter(); rows=[]; split=pd.Timestamp('2025-01-01',tz='UTC').timestamp()
for e,g in MK.groupby('event_id'):
    a=g[g.mty=='MATCH_ODDS']; b=g[g.mty=='DOUBLE_CHANCE']
    if not len(a) or not len(b): SK['no MO or DC market']+=1; continue
    ev=a.ev.iloc[0]; home,_x,away=ev.partition(' v '); o=float(b.off.iloc[0]); xm=PX.get(a.market_id.iloc[0]); xd=PX.get(b.market_id.iloc[0])
    if xm is None or xd is None: SK['no pre-off print']+=1; continue
    em={}
    for s,y in xm.groupby('sel',sort=False):
        i=last_in(y.tt.values,o-1200,o-120)
        if i is not None: em[s]=float(y.ltp.values[i])
    pr=mo_pair(home,away,list(em))
    if pr is None: SK['no MO favourite at entry']+=1; continue
    hf=em[pr[0]]<=em[pr[1]]; R=RD[b.market_id.iloc[0]]
    for s,y in xd.groupby('sel',sort=False):
        lab=dc(s,hf)
        if lab is None or s not in R: SK['runner not mapped']+=1; continue
        ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-1200,o-120)
        if i is None: SK['no print in window']+=1; continue
        for side in 'BL':
            p=fill(ts,px,i,side)
            if p>50: SK['over 50']+=1; continue
            v=bk(p,R[s]) if side=='B' else ly(p,R[s])
            if v is None: SK['bottom of ladder, no back']+=1; continue
            rows.append(('T' if o<split else 'F',e,o,lab,side,p,bool(R[s]),v))
print("counted:",dict(sorted(SK.items())),flush=True)
X=pd.DataFrame(rows,columns='w e off nm side p won v'.split()); assert not X.duplicated(['e','nm','side']).any(); out=[]
for k,x in X.groupby(['w','nm','side']):
    l=line(x.v.values,np.where(x.off<np.median(x.off.values),1,2)); out.append(dict(w=k[0],sel=k[1],side=k[2],n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],won=x.won.mean(),imp=(1/x.p).mean(),PASS=l['PASS']))
O=pd.DataFrame(out); print(O.sort_values(['w','t'],ascending=[True,False]).round(3).to_string(index=False))
S=O[(O.w=='T')&O.PASS]; print(f"\n== SURVIVORS: {len(S)} of {int((O.w=='T').sum())} on Oct 2024\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
