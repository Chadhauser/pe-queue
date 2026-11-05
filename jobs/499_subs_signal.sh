#!/bin/bash
set -o pipefail
# 499_subs_signal (Finder 2026-11-05, queue item 87, Finder's own, source d): do substitutions tell the market anything? Rule written in the queue before any price was read. Engine from jobs/499_let_off.sh. The number 499 is reused with a new slug: 450-499 are all taken.
# DATA af_events (subst, Goal, Card), af_fixtures, af_price_map, bf_hist_price (MO, OU25), seasons 2024 and 2025. One entry per team per game per state.
# ENTRY first real print in the state's window, filled at the worse of it and the next print within 2 min, one tick adverse. No print: no trade, never a forward fill. A goal logged by the print minute: no trade, counted, as the state has changed by then.
# EXIT settle, or first print at +10 minutes or later to 95, one tick adverse; no print = settled at the result. Over 2.5: third goal by the exit minute = settled at the result, never dropped. 2% commission, £10 risk.
# OWN GOALS are not flipped (item 38): is_home on a goal row is the team credited. Scores at HT come from af_fixtures, at 70 from those rows.
# CLOCK the tape clock can differ from the af minute (item 19). A FORCED line good at E2 and not at E5 is read as look-ahead.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks()
pd.set_option('display.width',250); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
T0=time.time()
def first_print(arr,a,b):
    for m in range(max(a,0),min(b,95)+1):
        if arr[m]==arr[m]: return m
    return None
def fill(arr,m,side):
    p=arr[m]
    for k in (m+1,m+2):
        if k<=95 and arr[k]==arr[k]:
            p=min(p,arr[k]) if side=='B' else max(p,arr[k]); break
    return float(p)
def trade(side,arr,lo,hi,won,exit10,third,goals_m):
    """(P&L, reason). Window lo..hi. third: minute of the third goal or None. goals_m: all goal minutes. A goal in lo'..print, where lo' is the state's start, voids the trade."""
    d=first_print(arr,lo,hi)
    if d is None: return None,'noprint'
    if any(lo-1<=g<=d for g in goals_m): return None,'goal'
    a=step(fill(arr,d,side),-1 if side=='B' else 1)
    if side=='B' and a<=1.01: return None,'floor'
    settle=back_settle(a,won) if side=='B' else lay_settle(a,won)
    if not exit10: return settle,'ok'
    x=first_print(arr,d+10,95)
    if x is None or (third is not None and third<=x): return settle,'ok'
    return (back_hedge(a,float(arr[x])) if side=='B' else lay_hedge(a,float(arr[x]))),'ok'
def states(gl,subs,reds,ht):
    """gl [(min,is_home)], subs {is_home:[minutes]}, reds {is_home:[minutes]}, ht (h,a). Returns [(state,is_home,lo,hi)]."""
    out=[]; hh,aa=ht
    for ih in (True,False):
        me,op=(hh,aa) if ih else (aa,hh); s=sorted(subs.get(ih,[])); n46=sum(1 for m in s if m==46)
        if me==op-1: out.append((f"HT_TRAIL1_CH{min(n46,2)}",ih,47,50))
        if me==op and n46>=2: out.append(("HT_LEVEL_CH2",ih,47,50))
        if s and s[0]<=35 and not any(r<=s[0] for r in reds.get(ih,[])):
            c=s[0]
            h_,a_=sum(1 for g in gl if g[0]<=c and g[1]),sum(1 for g in gl if g[0]<=c and not g[1])
            for ent,lo,hi in (('E2',2,4),('E5',5,7)):
                out.append((f"FORCED_{ent}",ih,c+lo,c+hi))
                if h_==a_: out.append((f"FORCED_LEVEL_{ent}",ih,c+lo,c+hi))
        h70,a70=sum(1 for g in gl if g[0]<=70 and g[1]),sum(1 for g in gl if g[0]<=70 and not g[1])
        m70,o70=(h70,a70) if ih else (a70,h70)
        if m70==o70-1:
            k=sum(1 for m in s if m<=70)
            if k<=1: out.append(("TRAIL70_S01",ih,71,73))
            elif k>=3: out.append(("TRAIL70_S3",ih,71,73))
    return out
# known answers, worked by hand
_a=np.full(96,np.nan); _a[47]=2.0; _a[48]=2.1; _a[60]=3.0
assert first_print(_a,47,50)==47 and first_print(_a,49,50) is None and fill(_a,47,'B')==2.0 and fill(_a,47,'L')==2.1
# Back: 2.0 -> 1.99. Win 9.702; lose -10; out at 3.0 -> lay 3.05: 10*(1.99/3.05-1) = -3.47541.
assert abs(trade('B',_a,47,50,True,False,None,[])[0]-9.702)<1e-9 and trade('B',_a,47,50,False,False,None,[])[0]==-10 and abs(trade('B',_a,47,50,False,True,None,[])[0]+3.475410)<1e-5
# Lay: 2.1 -> 2.12, stake 8.928571, selection loses +8.75; wins -10.
assert abs(trade('L',_a,47,50,False,False,None,[])[0]-8.75)<1e-6 and trade('L',_a,47,50,True,False,None,[])[0]==-10
assert trade('B',_a,70,72,True,False,None,[])==(None,'noprint') and trade('B',_a,47,50,True,False,None,[47])==(None,'goal') and trade('B',_a,47,50,True,False,None,[30])[1]=='ok'
assert abs(trade('B',_a,47,50,True,True,55,[])[0]-9.702)<1e-9                                            # third goal before the exit print: settled, a win
assert trade('B',_a,47,50,True,False,None,[46])==(None,'goal')                                             # goal at the restart: state gone
_s=states([(10,False)],{True:[46,46,60],False:[20]},{},(0,1))
assert ('HT_TRAIL1_CH2',True,47,50) in _s and ('FORCED_E2',False,22,24) in _s and ('FORCED_LEVEL_E5',False,25,27) not in _s and ('TRAIL70_S01',True,71,73) not in _s    # away lead 1-0 at the sub, so not level; home 3 subs by 70, so not S01
_s=states([(30,False)],{False:[20]},{},(0,1)); assert ('FORCED_LEVEL_E5',False,25,27) in _s and ('FORCED_E2',False,22,24) in _s    # goal after the sub: level when it happened
_s=states([(10,False)],{True:[60],False:[]},{},(0,1)); assert ('HT_TRAIL1_CH0',True,47,50) in _s and ('TRAIL70_S01',True,71,73) in _s
_s=states([],{True:[20]},{True:[15]},(0,0)); assert not [x for x in _s if x[0].startswith('FORCED')]    # a sub after his own side's red is not forced
_s=states([],{True:[46,46]},{},(1,1)); assert ('HT_LEVEL_CH2',True,47,50) in _s
_s=states([(10,False),(50,False)],{True:[60,65,70]},{},(0,1)); assert not [x for x in _s if x[0].startswith('TRAIL70')]    # two down at 70: no state
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.season,f.hg,f.ag,f.ht_hg,f.ht_ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.ht_hg IS NOT NULL AND f.season IN (2024,2025)""",con)
ids=list(map(int,G.fixture_id))
EV=pd.read_sql("SELECT fixture_id,coalesce(minute,0) AS minute,is_home,type,detail FROM af_events WHERE fixture_id=ANY(%s) AND is_home IS NOT NULL AND (type='subst' OR (type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')) OR (type='Card' AND detail='Red Card'))",con,params=(ids,))
goals=defaultdict(list); subs=defaultdict(lambda:defaultdict(list)); reds=defaultdict(lambda:defaultdict(list))
for r in EV.itertuples():
    ih=bool(r.is_home); m=int(r.minute)
    if r.type=='Goal': goals[r.fixture_id].append((m,ih))
    elif r.type=='subst': subs[r.fixture_id][ih].append(m)
    else: reds[r.fixture_id][ih].append(m)
print(f"games {len(G)}, with subs {len(subs)}; {time.time()-T0:.0f}s",flush=True)
EID=list(G.event_id.unique()); px=defaultdict(dict); cal=[]
for i in range(0,len(EID),1000):
    P=pd.read_sql("SELECT event_id,minute,mkt,sel,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND ((mkt='MO' AND sel IN ('HOME','AWAY')) OR (mkt='OU25' AND sel='OVER')) AND minute BETWEEN 0 AND 95 AND ltp>=1.01 AND ltp<1000",con,params=(EID[i:i+1000],))
    for (e,mk,s),g in P.groupby(['event_id','mkt','sel'],sort=False):
        a=np.full(96,np.nan); a[g.minute.values]=g.ltp.values; px[e][(mk,s)]=a
    if (i//1000)%4==0: print(f"  {min(i+1000,len(EID))}/{len(EID)} {time.time()-T0:.0f}s",flush=True)
print(f"with prices {len(px)}, {time.time()-T0:.0f}s",flush=True)
c=pd.read_sql("SELECT calibrated,count(*) n FROM (SELECT DISTINCT event_id,calibrated FROM bf_hist_price WHERE event_id=ANY(%s)) x GROUP BY 1",con,params=(EID[:2000],)); print("calibrated, sample of 2,000 games\n"+c.to_string(index=False),flush=True); con.close()
rows=[]; why=defaultdict(int)
for r in G.itertuples():
    b=px.get(r.event_id)
    if not b: continue
    gl=sorted(goals.get(r.fixture_id,[])); gm=[g[0] for g in gl]; third=gm[2] if len(gm)>=3 else None; h=1 if r.season==2024 else 2
    hw,aw=r.hg>r.ag,r.ag>r.hg
    for st,ih,lo,hi in states(gl,subs.get(r.fixture_id,{}),reds.get(r.fixture_id,{}),(r.ht_hg,r.ht_ag)):
        sofar=sum(1 for g in gm if g<lo)
        legs=[('TEAM',b.get(('MO','HOME' if ih else 'AWAY')),hw if ih else aw,None),('OPP',b.get(('MO','AWAY' if ih else 'HOME')),aw if ih else hw,None)]
        if sofar<3: legs.append(('OVER',b.get(('OU25','OVER')),r.hg+r.ag>2.5,third))
        for leg,arr,won,tg in legs:
            if arr is None: continue
            for ex,e10 in (('settle',False),('+10',True)):
                for side in 'BL':
                    v,w=trade(side,arr,lo,hi,won,e10,tg,gm); why[w]+=1
                    if v is not None: rows.append((st,leg,'BACK' if side=='B' else 'LAY',ex,h,r.event_id,v))
T=pd.DataFrame(rows,columns=['state','leg','side','exit','h','g','v']); o=[]
print("trade attempts",dict(why),flush=True)
for k,x in T.groupby(['state','leg','side','exit']):
    d=line(x.v.values,x.h.values); o.append(dict(zip(['state','leg','side','exit'],k))|dict(n=d['n'],games=x.g.nunique(),per10=round(d['per10'],3),t=round(d['t'],2),h1=round(d['h1'],3),h2=round(d['h2'],3),n1=d['n1'],n2=d['n2'],PASS=d['PASS']))
L=pd.DataFrame(o); E=L[L.n>=300].sort_values('t',ascending=False)
print(f"\nlines {len(L)}, at n>=300 {len(E)}, positive {(E.per10>0).sum()}, passing {int(L.PASS.sum())}, {time.time()-T0:.0f}s")
print("\nSTATE SIZES, team back settle"); print(L[(L.leg=='TEAM')&(L.side=='BACK')&(L.exit=='settle')][['state','n','games','per10','t','h1','h2']].to_string(index=False))
print("\nTOP 15 by t, n>=300"); print(E.head(15).drop(columns=['n1','n2']).to_string(index=False))
print("\nBOTTOM 5 by t, n>=300"); print(E.tail(5).drop(columns=['n1','n2']).to_string(index=False))
print("\nSURVIVORS"); P=L[L.PASS]
print(P.to_string(index=False) if len(P) else "none")
print(f"done {time.time()-T0:.0f}s")
PY
