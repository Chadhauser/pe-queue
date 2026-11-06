#!/bin/bash
set -o pipefail
# 499_ladder_slot (Finder 2026-11-06, queue items 260, 261, Finder's own, source c): ladder steps and crowded kick-off slots v the official result. Rules pushed in the queue (7bf813f) before any price was read. Read only.
# ENTRY last non-in-play print T-20 to T-2 min, never earlier; worse of it and the next pre-off print within 120 s, one tick adverse, 2%, £10 risk, hold to the official result. A market without exactly one WINNER is dropped, counted. One market per event per type.
# Prints only: a pass is an upper bound and earns only a real-touch check. Halves by date median, which fell at 19 Aug 2024 as most official results are 2024 months. Lines share games, so read them as correlated; tg is t on per-game sums.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(2_000_000_000,2_000_000_000))  # this job only
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line,step,tstat
from lib_official import bk,ly,fill,last_in,secs,load_results,checks
import lib_cand; lib_cand._checks(); checks()
pd.set_option('display.width',240); pd.set_option('display.max_columns',30); pd.set_option('display.max_rows',200)
BS=(2.0,3.0,4.0,6.0,10.0)
def ladder_state(q):
    """(B,'AT'|'BELOW'|'ABOVE') for a raw print within two ticks of a step, else None."""
    q=round(float(q),2)
    for B in BS:
        if q==B: return B,'AT'
        if q in (step(B,-1),step(B,-2)): return B,'BELOW'
        if q in (step(B,1),step(B,2)): return B,'ABOVE'
    return None
def welch(a,b):
    a=np.asarray(a,float); b=np.asarray(b,float)
    if len(a)<2 or len(b)<2: return float('nan')
    s=(a.var(ddof=1)/len(a)+b.var(ddof=1)/len(b))**0.5
    return float((a.mean()-b.mean())/s) if s>0 else float('nan')
def slot_class(s,lo,hi): return 'CROWD' if s>=hi else 'LONE' if s<=lo else 'MID'
def is_draw(s): return str(s).strip().lower()=='the draw'
def legs(p1,p2):
    """Prints of the two non-draw runners -> [(leg,'a' or 'b')]; a=first runner. Ties no bet."""
    if p1==p2: return []
    f,d,fp,dp=('a','b',p1,p2) if p1<p2 else ('b','a',p2,p1)
    o=[]
    if fp<=1.5: o.append(('FAV <=1.5',f))
    elif fp<=2.5: o.append(('FAV 1.5-2.5',f))
    if 2.5<dp<=4: o.append(('DOG 2.5-4',d))
    elif 4<dp<=10: o.append(('DOG 4-10',d))
    return o
# known answers, worked by hand. Ticks: 1.99 and 1.98 under 2; 2.02, 2.04 over; 2.98, 2.96 under 3; 3.05, 3.10 over; 9.8, 9.6 under 10; 10.5, 11 over.
assert ladder_state(2.0)==(2.0,'AT') and ladder_state(1.98)==(2.0,'BELOW') and ladder_state(2.04)==(2.0,'ABOVE') and ladder_state(2.06) is None
assert ladder_state(2.96)==(3.0,'BELOW') and ladder_state(3.10)==(3.0,'ABOVE') and ladder_state(9.6)==(10.0,'BELOW') and ladder_state(11.0)==(10.0,'ABOVE') and ladder_state(12.0) is None
assert slot_class(40,3,30)=='CROWD' and slot_class(3,3,30)=='LONE' and slot_class(10,3,30)=='MID'
assert legs(1.4,8.0)==[('FAV <=1.5','a'),('DOG 4-10','b')] and legs(3.0,2.0)==[('FAV 1.5-2.5','b'),('DOG 2.5-4','a')] and legs(2.5,2.5)==[]
assert legs(1.6,15.0)==[('FAV 1.5-2.5','a')] and legs(2.6,2.7)==[('DOG 2.5-4','b')]
assert abs(welch([1,3],[0,0,0])-2.0)<1e-9
# epoch: pandas 3 microsecond trap
assert secs(pd.Series(pd.to_datetime(['2026-01-01 00:00:00+00:00']))).iloc[0]==1767225600.0
print("checks: OK",flush=True); T0=time.time()
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
# slots from the whole MO tape, no price read
cur.execute("SELECT DISTINCT event_name,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_time>='2024-03-01' AND market_time<'2026-10-01'")
EV=pd.DataFrame(cur.fetchall(),columns=['ev','mt']); EV['slot']=EV.groupby('mt').ev.transform('size')
LO,HI=float(EV.slot.quantile(0.20)),float(EV.slot.quantile(0.80))
print(f"games {len(EV):,}; slot size game-weighted p20 {LO:.0f}, p50 {EV.slot.median():.0f}, p80 {HI:.0f}, max {EV.slot.max()}; CROWD >= {HI:.0f}, LONE <= {LO:.0f}",flush=True)
SLOT=dict(zip(zip(EV.ev,EV.mt),EV.slot))
RS,bad=load_results(con,['MATCH_ODDS','OVER_UNDER_25']); print(f"markets with one WINNER {len(RS):,}, dropped {bad:,}, {time.time()-T0:.0f}s",flush=True)
cur.execute("SELECT DISTINCT market_id,event_id,event_name,market_type,market_time FROM bf_hist_other WHERE sport='Soccer' AND market_type IN ('MATCH_ODDS','OVER_UNDER_25') AND market_time>='2024-03-01' AND market_time<'2026-10-01' AND market_id=ANY(%s)",(list(RS),))
MK=pd.DataFrame(cur.fetchall(),columns='market_id event_id ev mty mt'.split()); MK['off']=secs(MK.mt); n0=len(MK)
MK=MK.sort_values('market_id').drop_duplicates(['event_id','mty']).drop_duplicates(['ev','mt','mty'])
print(f"markets on the tape {n0:,}, second ids dropped {n0-len(MK):,}; games by month {MK[MK.mty=='MATCH_ODDS'].groupby(pd.to_datetime(MK.mt,utc=True).dt.strftime('%Y-%m')).size().to_dict()}",flush=True)
SK=Counter(); LAD=[]; SL=[]
ms=list(MK.market_id); META={r.market_id:r for r in MK.itertuples()}
def trade(ts,px,i,won):
    pb,pl=fill(ts,px,i,'B'),fill(ts,px,i,'L')
    return bk(pb,won),ly(pl,won),pb,pl
for c0 in range(0,len(ms),3000):
    ch=ms[c0:c0+3000]
    P=pd.read_sql("SELECT market_id,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '20 minutes'",con,params=(ch,))
    P['tt']=secs(P.ts); P=P.drop_duplicates(['market_id','sel','tt']).sort_values('tt',kind='stable')
    for m,x in P.groupby('market_id',sort=False):
        r=META[m]; o=float(r.off); ent={}
        for s,y in x.groupby('sel',sort=False):
            if s not in RS[m]: SK['print on a runner with no result']+=1; continue
            ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-1200,o-120)
            if i is None: SK['no print in window']+=1; continue
            ent[s]=(ts,px,i,bool(RS[m][s]))
        kind='MO' if r.mty=='MATCH_ODDS' else 'OU25'
        for s,(ts,px,i,won) in ent.items():
            st=ladder_state(px[i])
            if st is None: continue
            vb,vl,pb,pl=trade(ts,px,i,won)
            if vb is None: SK['bottom of ladder, no back']+=1
            LAD.append((kind,st[0],st[1],r.event_id,o,won,vb,vl,pb,pl))
        cl=SLOT.get((r.ev,r.mt))
        if cl is None: SK['no slot']+=1; continue
        cl=slot_class(cl,LO,HI)
        if kind=='MO':
            rr=[s for s in ent if not is_draw(s)]
            if len(rr)!=2: SK['MO without two non-draw prints']+=1; continue
            for lg,w in legs(float(ent[rr[0]][1][ent[rr[0]][2]]),float(ent[rr[1]][1][ent[rr[1]][2]])):
                s=rr[0] if w=='a' else rr[1]; ts,px,i,won=ent[s]; vb,vl,pb,pl=trade(ts,px,i,won)
                SL.append((cl,lg,r.event_id,o,won,vb,vl,pb,pl))
        else:
            for s,(ts,px,i,won) in ent.items():
                k=str(s).strip().lower()
                lg='OVER' if k.startswith('over') else 'UNDER' if k.startswith('under') else None
                if lg is None: SK['OU runner not read']+=1; continue
                vb,vl,pb,pl=trade(ts,px,i,won); SL.append((cl,lg,r.event_id,o,won,vb,vl,pb,pl))
    del P; print(f"  chunk {c0:,}/{len(ms):,} {time.time()-T0:.0f}s",flush=True)
print("counted:",dict(sorted(SK.items())),flush=True); con.close()
cols='e off won vb vl pb pl'.split()
A=pd.DataFrame(LAD,columns=['kind','B','pos']+cols); S=pd.DataFrame(SL,columns=['cl','leg']+cols)
assert len(A) and len(S)
MD=pd.concat([A[['e','off']],S[['e','off']]]).drop_duplicates('e').off.median()
def score(name,x,side):
    x=x[x['v'+('b' if side=='B' else 'l')].notna()]; v=x['v'+('b' if side=='B' else 'l')].values.astype(float)
    p=(x.pb if side=='B' else x.pl).map(lambda q:step(q,-1 if side=='B' else 1)).values
    l=line(v,np.where(x.off.values<MD,1,2)); tg=tstat(x.assign(v_=v).groupby('e').v_.sum().values)
    return dict(line=name,side=side,n=l['n'],games=x.e.nunique(),per10=l['per10'],t=l['t'],tg=tg,n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),imp=(1/p).mean(),maxwin=l['maxwin'],PASS=bool(l['PASS'] and tg>=3.5))
print(f"\nhalves split at {pd.Timestamp(MD,unit='s',tz='UTC')}")
out=[]
for (k,B),g in A.groupby(['kind','B']):
    for pos in ('AT','BELOW','ABOVE'):
        x=g[g.pos==pos]
        if not len(x): continue
        for side in 'BL':
            d=score(f"260 {k} {B:g} {pos}",x,side); c='v'+side.lower()
            d['t_v_near']=welch(x[c].dropna().values.astype(float),g[g.pos!='AT'][c].dropna().values.astype(float)) if pos=='AT' else float('nan')
            out.append(d)
O=pd.DataFrame(out); print(f"\n== item 260, {len(O)} lines, top 15 by t"); print(O.sort_values('t',ascending=False).head(15).round(3).to_string(index=False))
print("\nAT lines, every step"); print(O[O.line.str.endswith('AT')].sort_values('line').round(3).to_string(index=False))
out=[]
for (cl,lg),x in S.groupby(['cl','leg']):
    for side in 'BL': out.append(score(f"261 {cl} {lg}",x,side))
Q=pd.DataFrame(out); Q['scored']=~Q.line.str.contains('MID')
print(f"\n== item 261, {int(Q.scored.sum())} scored lines, top 15 by t, MID is the control"); print(Q[Q.scored].sort_values('t',ascending=False).head(15).drop(columns='scored').round(3).to_string(index=False))
print("\nMID control"); print(Q[~Q.scored].sort_values('t',ascending=False).drop(columns=['scored','PASS']).round(3).to_string(index=False))
R=pd.concat([O[O.PASS],Q[Q.scored&Q.PASS].drop(columns='scored')])
print(f"\n== SURVIVORS: {len(R)} of {len(O)+int(Q.scored.sum())}"); print(R.round(3).to_string(index=False) if len(R) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
