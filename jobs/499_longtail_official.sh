#!/bin/bash
set -o pipefail
# 499_longtail_official (Finder 2026-11-05, queue item 141, Finder's own, source c): the long tail before the off, settled on Betfair's own WINNER/LOSER (bf_hist_result, job 520). Rule pushed in the queue before any price was read. Read only. The number 499 is reused: 450-499 are all taken.
# ENTRY last non-in-play print T-20 to T-2 min, worse of it and the next non-in-play print within 120 s, one tick adverse, 2%, £10 risk, hold to the official result. Over 50 not traded, counted. Market without exactly one WINNER dropped, counted.
# GROUPS WOMEN, YOUTH by event name; other games SENIOR THIN, MID, DEEP by MO prints T-60 to T-20, tertile cuts from the first half by date only. 130 lines. One bet per game per line, but lines share games. Prints only: a pass is an upper bound and only earns an unseen-months test, as this is one part-loaded month.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import tstat,line,norm,loose
from lib_official import group,bk,ly,fill,last_in,secs,load_results,checks
import lib_cand; lib_cand._checks(); checks(); print("checks: OK",flush=True)
pd.set_option('display.width',250); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time()
TYPES={'MATCH_ODDS':'MO','OVER_UNDER_15':'OU15','OVER_UNDER_25':'OU25','OVER_UNDER_35':'OU35','BOTH_TEAMS_TO_SCORE':'BTTS','FIRST_HALF_GOALS_05':'FH05'}
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
RS,bad=load_results(con,list(TYPES)); print(f"markets with one WINNER {len(RS)}, dropped {bad}",flush=True)
cur.execute("SELECT DISTINCT market_id,event_id,event_name,market_type,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s)",(list(RS),))
MK=pd.DataFrame(cur.fetchall(),columns='market_id event_id ev mty mt'.split()); MK['off']=secs(MK.mt)
print(f"markets on the tape {len(MK)}, events {MK.event_id.nunique()}, dates {MK.mt.min()} to {MK.mt.max()}",flush=True)
# == settlement audit: official MO and OU25 against goal_timeline, an independent score feed, finished games only
GT=pd.read_sql("SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,captured_at,minute,score_home,score_away,status FROM goal_timeline WHERE captured_at>=%s AND captured_at<%s AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at DESC",con,params=(str(MK.mt.min())[:10],str(MK.mt.max()+pd.Timedelta(days=2))[:10]))
# AET and PEN left out of the audit: MO and OU settle at 90 min
GT=GT[GT.status.isin(['FT','Match Finished','FINISHED'])].copy(); GT['t']=secs(GT.captured_at); GT['H']=GT.home_team.map(norm); GT['A']=GT.away_team.map(norm); GT=GT.sort_values('t'); tt=GT.t.values
A=Counter()
for r in MK[MK.mty.isin(['MATCH_ODDS','OVER_UNDER_25'])].itertuples():
    h,_x,a=r.ev.partition(' v '); lo,hi=np.searchsorted(tt,r.off),np.searchsorted(tt,r.off+14400)
    fx=loose(norm(h),norm(a),[(x.H,x.A,x.Index) for x in GT.iloc[lo:hi].itertuples()])
    if fx is None: A[r.mty+' no score']+=1; continue
    g=GT.loc[fx]; sh,sa=int(g.score_home),int(g.score_away); w=[k for k,v in RS[r.market_id].items() if v][0]
    if r.mty=='MATCH_ODDS':
        want='The Draw' if sh==sa else (h if sh>sa else a); ok=(w==want)
    else: ok=(w.startswith('Over'))==(sh+sa>2.5)
    A[r.mty+(' agree' if ok else ' DISAGREE')]+=1
print("settlement audit v goal_timeline:",dict(sorted(A.items())),f"{time.time()-T0:.0f}s",flush=True)
mkts=list(MK.market_id); parts=[]
for i in range(0,len(mkts),2000):
    parts.append(pd.read_sql("SELECT market_id,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND NOT inplay AND ltp>=1.01 AND ltp<1000",con,params=(mkts[i:i+2000],)))
con.close(); P=pd.concat(parts,ignore_index=True); P['tt']=secs(P.ts); P=P.drop_duplicates(['market_id','sel','tt']).sort_values('tt',kind='stable')
print(f"pre-off rows {len(P)}, {time.time()-T0:.0f}s",flush=True)
EV=MK.drop_duplicates('event_id').set_index('event_id'); EVM={e:g for e,g in MK.groupby('event_id')}; PX={k:g for k,g in P.groupby('market_id')}
SK=Counter(); rows=[]; liq={}
for e,g in EVM.items():
    ev=EV.ev[e]; off=float(EV.off[e]); home,_x,away=ev.partition(' v '); grp=group(ev); ent={}
    for r in g.itertuples():
        x=PX.get(r.market_id);
        if x is None: SK[TYPES[r.mty]+' no pre-off print']+=1; continue
        o=float(r.off); k=TYPES[r.mty]
        if k=='MO': liq[e]=int(((x.tt>=o-3600)&(x.tt<o-1200)).sum())
        for s,y in x.groupby('sel',sort=False):
            if s not in RS[r.market_id]: SK['print on a runner with no result']+=1; continue
            ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-1200,o-120)
            if i is None: SK[k+' no print in window']+=1; continue
            ent[(k,s)]=(ts,px,i,RS[r.market_id][s])
    def add(nm,key):
        ts,px,i,won=ent[key]
        for side in 'BL':
            p=fill(ts,px,i,side)
            if p>50: SK['over 50, not traded']+=1; continue
            v=bk(p,won) if side=='B' else ly(p,won)
            if v is None: SK['bottom of ladder, no back']+=1; continue
            rows.append((e,grp,off,nm,side,p,won,v))
    h,a=('MO',home),('MO',away)
    if h in ent and a in ent:
        fh=ent[h][1][ent[h][2]]<=ent[a][1][ent[a][2]]; add('MO FAV',h if fh else a); add('MO DOG',a if fh else h)
    if ('MO','The Draw') in ent: add('MO DRAW',('MO','The Draw'))
    for key in ent:
        k,s=key
        if k=='MO': continue
        sl=str(s).strip().lower()
        if k=='BTTS' and sl in('yes','no'): add(f"BTTS {sl.title()}",key)
        elif k!='BTTS' and (sl.startswith('over') or sl.startswith('under')): add(f"{k} {sl.split()[0].title()}",key)
print("counted:",dict(sorted(SK.items())),flush=True)
R=pd.DataFrame(rows,columns='e grp off nm side p won v'.split()); md=np.median(R.off.values); R['h']=np.where(R.off<md,1,2)
ks=pd.Series({e:liq.get(e,0) for e in EVM}); first=[e for e in EVM if EV.off[e]<md and group(EV.ev[e]) is None]; c1,c2=np.quantile(ks[first],[1/3,2/3]); print(f"MO prints T-60 to T-20, senior first half: cuts {c1:.0f}, {c2:.0f}",flush=True)
R['g']=[x if x else ('S_THIN' if liq.get(e,0)<=c1 else 'S_MID' if liq.get(e,0)<=c2 else 'S_DEEP') for x,e in zip(R.grp,R.e)]
print("games by group:",R.drop_duplicates('e').groupby('g').size().to_dict(),"median date",pd.to_datetime(md,unit='s'),flush=True)
out=[]
for k,x in R.groupby(['g','nm','side']):
    l=line(x.v.values,x.h.values); out.append(dict(g=k[0],sel=k[1],side=k[2],n=l['n'],games=x.e.nunique(),per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),imp=(1/x.p).mean(),PASS=l['PASS']))
O=pd.DataFrame(out).sort_values('t',ascending=False)
print(f"\n== lines {len(O)}, n>=300 {int((O.n>=300).sum())}; by chance about {len(O)*0.05:.0f} reach t>=1.65. Top 15 by t, n>=100"); print(O[O.n>=100].head(15).drop(columns=['n1','n2']).round(3).to_string(index=False))
print("worst 3"); print(O[O.n>=100].tail(3).drop(columns=['n1','n2']).round(3).to_string(index=False))
S=O[O.PASS]; print(f"\n== SURVIVORS: {len(S)} of {len(O)}\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
