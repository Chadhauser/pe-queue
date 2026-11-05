#!/bin/bash
set -o pipefail
# 499_greyhound_meeting_trap (Finder 2026-11-05, queue item 175; from jobs/499_greyhound_results.sh): is what has already happened at tonight's meeting priced? Rule pushed before prices were read (commit 8773b44).
# TAPE: bf_hist_other Greyhound WIN, pre-off last-traded prints, so a pass is an upper bound. TRUTH: greyhound_racecards_today (Railway, this one table read). Join and gate as item 61: London date, track, dog name; >= 80% of card races with a winner must join to one market with one winner, else BLOCKED. Dead heats out, counted. A race with a tape runner missing from the card goes, counted.
# ENTRY: last print 5 to 20 min before the scheduled off, one tick adverse, over 50 not traded, settled at the result, 2%, £10.
# NO LOOK-AHEAD: an earlier race counts only if its scheduled off is at least 5 min before this entry print, and only if it is scored; so "the race before" means the last scored race, and an unscored race between is skipped.
# TRAP STATES, needing k >= 4 such races: HOT w >= 3 and w/k >= 0.40; COLD w = 0 and k >= 6; REPEAT1 won the race before; REPEAT2 won the two before. By band and ALL, back and lay, lowest trap if two qualify in a race.
# FAVOURITE STATES, shortest entry price, unique: FAVHOT last three favourites all won; FAVCOLD last four all lost. CONTROL: every runner by band, not scored. Halves by median date; about five months only, so both halves share a season.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(3_500_000_000,3_500_000_000))  # this job only
import sys,re,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,line,back_settle,lay_settle,tstat
pd.set_option('display.width',230); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',30)
T0=time.time()
def dog(s): return re.sub(r'[^a-z0-9]','',re.sub(r'^\s*\d+\.\s*','',str(s)).lower())
def track(e):
    m=re.match(r'^(.*?)\s+\d+(st|nd|rd|th)\s+\w+$',str(e)); return (m.group(1) if m else str(e)).strip().lower()
def band(p): return '<3' if p<3 else '3-6' if p<6 else '6-12' if p<12 else '12-50' if p<=50 else None
def trap_states(wins,trap):
    """wins: winning traps of the counted earlier races, oldest first. States this trap is in."""
    k=len(wins); w=sum(1 for x in wins if x==trap); out=[]
    if k<4: return out
    if w>=3 and w/k>=0.40-1e-9: out.append('HOT')
    if w==0 and k>=6: out.append('COLD')
    if wins[-1]==trap: out.append('REPEAT1')
    if wins[-2:]==[trap,trap]: out.append('REPEAT2')
    return out
def fav_states(flags):
    """flags: did the favourite win, counted earlier races with a unique favourite, oldest first."""
    out=[]
    if len(flags)>=3 and all(flags[-3:]): out.append('FAVHOT')
    if len(flags)>=4 and not any(flags[-4:]): out.append('FAVCOLD')
    return out
def value(side,x,won):
    if x>50: return None
    if side=='B':
        a=step(x,-1)
        return None if a<=1.01 else back_settle(a,won)
    return lay_settle(step(x,1),won)
# known answers, worked by hand
assert dog('1. Insane View')==dog('Insane  View') and track('Central Park 15th Sep')=='central park'
assert band(2.99)=='<3' and band(3)=='3-6' and band(12)=='12-50' and band(50)=='12-50' and band(51) is None
assert trap_states([1,2,3],1)==[]                                  # k=3: no state
assert trap_states([1,1,1,2,3],1)==['HOT']                         # w 3 of 5 = 0.6, last winner is 3
assert trap_states([1,1,2,3,4,5,6,2],1)==[]                        # w 2: not HOT, not COLD
assert trap_states([1,1,1,2,3,4,5,6],1)==[]                        # w 3 of 8 = 0.375: not HOT
assert trap_states([2,3,4,5,6,2],1)==['COLD'] and trap_states([2,3,4,5,6],1)==[]   # COLD needs k >= 6
assert trap_states([2,3,4,1],1)==['REPEAT1'] and trap_states([2,3,1,1],1)==['REPEAT1','REPEAT2']
assert fav_states([True,True,True])==['FAVHOT'] and fav_states([False,True,True,True])==['FAVHOT'] and fav_states([True,True])==[]
assert fav_states([False]*4)==['FAVCOLD'] and fav_states([False]*3)==[] and fav_states([True,False,False,False,False])==['FAVCOLD']
assert abs(value('B',3.0,True)-19.404)<1e-9 and value('B',3.0,False)==-10.0 and abs(value('L',3.0,False)-10/2.05*.98)<1e-9 and value('L',3.0,True)==-10.0 and value('B',51.,True) is None and value('B',1.02,True) is None
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require')
C=pd.read_sql("SELECT race_date,track,race_id,race_time,greyhound,trap_number,finish_position FROM greyhound_racecards_today",rc); rc.close()
C['tk']=C.track.str.strip().str.lower(); C['d']=C.greyhound.map(dog); C['date']=pd.to_datetime(C.race_date).dt.date; C=C.drop_duplicates(['race_id','d'])
print(f"card rows {len(C)}, races {C.race_id.nunique()}, dates {C.date.min()} to {C.date.max()} | {time.time()-T0:.0f}s",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=[]
for a,b in (('2026-05-01','2026-06-01'),('2026-06-01','2026-07-01'),('2026-07-01','2026-08-01'),('2026-08-01','2026-09-01'),('2026-09-01','2026-10-01'),('2026-10-01','2026-11-05')):
    cur.execute("""SELECT market_id,event_name,market_time,sel,ts,ltp::float8 FROM bf_hist_other WHERE sport='Greyhound Racing' AND market_type='WIN' AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND market_time>=%s AND market_time<%s""",(a,b))
    x=pd.DataFrame(cur.fetchall(),columns='market_id event_name market_time sel ts ltp'.split()); F.append(x); print(f"  {a} rows {len(x)} | {time.time()-T0:.0f}s",flush=True)
con.close(); P=pd.concat(F,ignore_index=True); P['mt']=pd.to_datetime(P.market_time,utc=True); P['t']=pd.to_datetime(P.ts,utc=True); P['mins']=(P.mt-P.t)/pd.Timedelta(minutes=1)
P=P.sort_values(['market_id','sel','t'],kind='stable')
Mk=P.drop_duplicates(['market_id','sel'])[['market_id','event_name','mt','sel']].copy(); Mk['tk']=Mk.event_name.map(track); Mk['d']=Mk.sel.map(dog); Mk['date']=Mk.mt.dt.tz_convert('Europe/London').dt.date
J=Mk.merge(C[['date','tk','d','race_id','trap_number','finish_position']],on=['date','tk','d'],how='left')
first,last=Mk.date.min(),Mk.date.max(); Cw=C[(C.date>=first)&(C.date<=last)]; cards_w=Cw[Cw.finish_position==1].race_id.unique()
hit=J.dropna(subset=['race_id']); rc_per=hit.groupby('market_id').race_id.nunique(); hit=hit[hit.market_id.isin(rc_per[rc_per==1].index)]
wn=hit[hit.finish_position==1].groupby('market_id').d.nunique(); one=wn[wn==1].index; dead=int((wn>1).sum()); joined=hit[hit.market_id.isin(one)].race_id.nunique(); rate=joined/max(1,len(cards_w))
print(f"card races with a winner in the tape's dates {len(cards_w)}; joined {joined}; dead heats {dead}; GATE {rate:.3f} v 0.80; tape markets {Mk.market_id.nunique()}",flush=True)
if rate<0.80: print("\n== SURVIVORS: none; join gate SHUT, item BLOCKED"); sys.exit(0)
miss=set(J[J.market_id.isin(one)&J.race_id.isna()].market_id.unique()); use=[m for m in one if m not in miss]; print(f"races removed, tape runner not on the card {len(miss)}; scored races {len(use)}",flush=True)
_h=hit[hit.market_id.isin(use)].groupby('race_id').market_id.nunique(); print(f"card races joined to more than one scored market: {int((_h>1).sum())} of {len(_h)}",flush=True)
R0=J[J.market_id.isin(use)].copy(); R0['won']=R0.finish_position==1; R0['trap']=pd.to_numeric(R0.trap_number,errors='coerce')
W=P[P.market_id.isin(use)&(P.mins>=5)&(P.mins<=20)].groupby(['market_id','sel'],sort=False).tail(1)[['market_id','sel','t','ltp']]   # sorted by time above, so tail = last print in the window
R0=R0.merge(W,on=['market_id','sel'],how='left'); SK=Counter(); rows=[]; ctrl=[]; RACES=0
for (tk,dt),G in R0.groupby(['tk','date'],sort=False):
    races=[]
    for m,g in G.groupby('market_id',sort=False):
        pr=g.dropna(subset=['ltp']); fav=None
        if len(pr):
            lo=pr.ltp.min(); c=pr[pr.ltp==lo]
            if len(c)==1: fav=c.d.iloc[0]
        w=g[g.won]; races.append((g.mt.iloc[0],m,g,fav,int(w.trap.iloc[0]) if len(w)==1 and pd.notna(w.trap.iloc[0]) else None,None if fav is None else bool(g[g.d==fav].won.iloc[0])))
    races.sort(key=lambda z:z[0])
    for ri,(mt,m,g,fav,wt,fw) in enumerate(races):
        RACES+=1
        for r in g.itertuples():
            if pd.isna(r.ltp): SK['runner no print 5 to 20 min before the off']+=1; continue
            b=band(r.ltp)
            if b is None: SK['runner over 50']+=1; continue
            for side in 'BL':
                v=value(side,float(r.ltp),bool(r.won))
                if v is None: continue
                ctrl.append((b,side,m,v,mt))
            if pd.isna(r.trap): SK['runner no trap']+=1; continue
            lim=r.t-pd.Timedelta(minutes=5); E=[z for z in races[:ri] if z[0]<=lim]
            wins=[z[4] for z in E if z[4] is not None]; st=trap_states(wins,int(r.trap))
            for s in st:
                for side in 'BL':
                    v=value(side,float(r.ltp),bool(r.won))
                    if v is not None: rows.append((s,b,side,m,int(r.trap),v,mt,bool(r.won),float(r.ltp)))
            if r.d==fav:
                for s in fav_states([z[5] for z in E if z[5] is not None]):
                    for side in 'BL':
                        v=value(side,float(r.ltp),bool(r.won))
                        if v is not None: rows.append((s,'ALL',side,m,int(r.trap),v,mt,bool(r.won),float(r.ltp)))
print(f"races {RACES}; counts {dict(sorted(SK.items()))} | {time.time()-T0:.0f}s",flush=True)
D=pd.DataFrame(rows,columns='state bd side m trap v mt won px'.split())
if D.empty: print("ERROR: no entries, no verdict"); sys.exit(1)
D['when']=[x.value for x in D.mt]; D=D.sort_values('trap',kind='stable'); out=[]
def add(x,bd):
    x=x.drop_duplicates('m'); md=np.median(x.when.values); l=line(x.v.values,np.where(x.when.values<md,1,2))
    out.append(dict(state=x.state.iloc[0],band=bd,side=x.side.iloc[0],n=l['n'],races=x.m.nunique(),per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],won=x.won.mean(),implied=(1/x.px).mean(),maxwin=l['maxwin'],PASS=l['PASS']))
for (s,side),A in D.groupby(['state','side']):
    if s.startswith('FAV'): add(A,'ALL'); continue
    add(A,'ALL')
    for bd in ('<3','3-6','6-12','12-50'):
        x=A[A.bd==bd]
        if len(x): add(x,bd)
S=pd.DataFrame(out).sort_values('t',ascending=False); print(f"\n== ALL {len(S)} LINES, per £10, by t\n",S.round(3).to_string(index=False))
Cc=pd.DataFrame(ctrl,columns='bd side m v mt'.split()); print("\n== CONTROL every runner by band, not scored")
for (b,side),x in Cc.groupby(['bd','side']): print(f"  {b} {side} n {len(x)} per10 {x.v.mean():+.3f} t by race {tstat(x.groupby('m').v.sum().values):.2f}")
Wn=S[S.PASS]; print(f"\n== SURVIVORS: {len(Wn)} of {len(S)}\n",Wn.round(3).to_string(index=False) if len(Wn) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
