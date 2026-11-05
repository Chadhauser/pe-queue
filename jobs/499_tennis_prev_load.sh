#!/bin/bash
set -o pipefail
# 499_tennis_prev_load (Finder 2026-11-05, queue item 107): is the previous match's load in the pre-off price? Read only.
# TAPE: bf_hist_other Tennis singles MATCH_ODDS, prints only, no book, so a pass is an upper bound. TRUTH: tennis_results_2026, unique match on both player names, tournament start -2 to +21 days from the market, as jobs/499_tennis_late_outsider.sh. Walkovers in THIS match void and excluded, counted. Retirements kept, winner as recorded.
# ENTRY: last pre-off print of that runner in the 60 minutes before the market's first in-play print (none = no trade, counted). One tick adverse. Back stake 10, lay liability 10, 2%, to the real result.
# PREVIOUS MATCH, no look-ahead: only the same player's match in the same tourney_id at an EARLIER round, by round order R128 R64 R32 R16 QF SF F. RR events are not used. Tournaments and rounds are finished facts before this match starts. tourney_date is a week start, so a CHAMP match's tourney starts 3 to 10 days after the final's tourney.
# GROUPS, fixed before any price is read. One side per match, except BYE and CHAMP where both could qualify (dropped if both do):
#   LONG    prior match >= 150 min (best of 3) or >= 240 (best of 5), opponent's prior under that and known
#   GAP60   prior match at least 60 min longer than the opponent's
#   THREE   prior match went the full distance, opponent's did not; same best_of on both
#   BYE     no earlier round here, not R128 or first round of the draw, opponent has one. Runner is the fresh player
#   EASY    prior match was a walkover or retirement, opponent's prior was neither
#   CHAMP   first match here, won the final of a tourney 3 to 10 days earlier
#   FINAL   first match here, lost the final of a tourney 3 to 10 days earlier
# CUTS: tour ALL, MAIN (ATP/WTA), CH (Challenger) x position ALL, FAV, DOG (shorter or longer of the two last prints). Back and lay. Control: every runner in that tour x position.
# Halves: median market date.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,re,time,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
warnings.filterwarnings('ignore')
pd.set_option('display.width',230); pd.set_option('display.max_rows',80); pd.set_option('display.max_columns',30)
sys.path.insert(0,'/root/pe-queue/runner'); import creds
T0=time.time()
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LADA=np.array(LAD)
def rpos(p): return int(np.searchsorted(LADA,round(float(p),2)-1e-9))
def dn(p): return float(LADA[max(rpos(p)-1,0)])
def up(p): return float(LADA[min(rpos(p)+1,len(LADA)-1)])
def back_settle(p,won):
    a=dn(p)
    if a<=1.01: return np.nan
    return 10*(a-1)*0.98 if won else -10.0
def lay_settle(p,won):
    a=up(p); return -10.0 if won else 10/(a-1)*0.98
def tstat(v):
    v=np.asarray(v,dtype=float); v=v[np.isfinite(v)]
    if len(v)<2: return 0.0
    s=v.std(ddof=1); return float(v.mean()/(s/len(v)**0.5)) if s>0 else 0.0
def fold(s): return re.sub(r"[^a-z]","",unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower())
def walkover(score): return bool(re.search(r"W/O|WO|WALK",str(score).upper()))
def retired(score): return bool(re.search(r"RET|DEF|ABD",str(score).upper()))
def n_sets(score): return len(re.findall(r"\d+-\d+",str(score)))
RO={'R128':1,'R64':2,'R32':3,'R16':4,'QF':5,'SF':6,'F':7}
def gate(v,when):
    m=np.isfinite(v); v=v[m]; when=when[m]
    if len(v)==0: return dict(n=0,mean=np.nan,t=0.0,n1=0,h1=np.nan,n2=0,h2=np.nan,PASS=False)
    md=np.median(when); a=v[when<md]; b=v[when>=md]; t=tstat(v)
    return dict(n=len(v),mean=v.mean(),t=t,n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,
                PASS=bool(len(v)>=300 and len(a)>=150 and len(b)>=150 and t>=3.5 and a.mean()>0 and b.mean()>0 and v.mean()>=0.15))
def prior(hist,tid,rnd):
    """hist[player] = list of (tid, round order, minutes, score, best_of). The latest earlier-round match in this tourney, or None."""
    c=[h for h in hist.get(tid,[]) if h[1]<rnd]
    return max(c,key=lambda h:h[1]) if c else None
def is_long(mins,bo): return mins is not None and mins>=(240 if bo==5 else 150)
def groups(pa,pb,bo_now,first_round):
    """Groups for runner a against b, from each player's prior match. pa, pb are prior() results. first_round: this is the draw's earliest round."""
    g=[]
    ma=pa[2] if pa else None; mb=pb[2] if pb else None
    ok=lambda m:m is not None and not np.isnan(m)
    if pa and pb and ok(ma) and ok(mb):
        if is_long(ma,pa[4]) and not is_long(mb,pb[4]): g.append('LONG')
        if ma-mb>=60: g.append('GAP60')
    if pa and pb and pa[4]==pb[4] and not (walkover(pa[3]) or walkover(pb[3]) or retired(pa[3]) or retired(pb[3])):
        if n_sets(pa[3])==pa[4] and n_sets(pb[3])<pb[4]: g.append('THREE')
    if not pa and pb and not first_round: g.append('BYE')
    if pa and pb and (walkover(pa[3]) or retired(pa[3])) and not (walkover(pb[3]) or retired(pb[3])): g.append('EASY')
    return g
# known answers, worked by hand
assert dn(1.5)==1.49 and up(1.5)==1.51 and dn(2.0)==1.99 and up(2.0)==2.02
assert abs(back_settle(1.30,True)-10*0.29*0.98)<1e-9 and back_settle(1.30,False)==-10.0 and np.isnan(back_settle(1.02,True))
assert abs(lay_settle(1.30,False)-10/0.31*0.98)<1e-9 and lay_settle(1.30,True)==-10.0
assert walkover('W/O') and not walkover('6-1 3-2 RET') and retired('6-1 3-2 RET') and not retired('6-1 6-4') and n_sets('6-7(2) 7-5 7-6(1)')==3 and n_sets('6-1 6-4')==2
_h={'T':[('T',3,100.0,'6-1 6-4',3),('T',4,155.0,'4-6 7-6(5) 6-4',3)]}
assert prior(_h,'T',5)[1]==4 and prior(_h,'T',4)[1]==3 and prior(_h,'T',3) is None and prior(_h,'X',5) is None      # latest earlier round only; a later round is never seen
_a=('T',4,155.0,'4-6 7-6(5) 6-4',3); _b=('T',4,90.0,'6-1 6-4',3)
assert groups(_a,_b,3,False)==['LONG','GAP60','THREE'] and groups(_b,_a,3,False)==[]                                   # one side only
assert 'LONG' not in groups(('T',4,149.0,'6-1 6-4',3),_b,3,False)                                                      # 149 is under the threshold
assert 'LONG' in groups(('T',4,150.0,'6-1 6-4',3),_b,3,False)                                                          # 150 is at the threshold
assert 'GAP60' in groups(('T',4,150.0,'6-1 6-4',3),_b,3,False) and 'GAP60' not in groups(('T',4,149.0,'6-1 6-4',3),_b,3,False)  # gap of 60 counts, 59 does not
assert groups(None,_b,3,False)==['BYE'] and groups(None,_b,3,True)==[] and groups(_b,None,3,False)==[]                 # bye: the fresh player only, never in the first round
assert 'EASY' in groups(('T',4,20.0,'6-1 RET',3),_b,3,False) and 'EASY' not in groups(('T',4,20.0,'6-1 RET',3),('T',4,20.0,'W/O',3),3,False)
assert not groups(('T',4,float('nan'),'6-1 6-4',3),_b,3,False)                                                         # minutes unknown: no minute group, two sets: no THREE
_g=gate(np.array([1.0,0.5]*200),np.arange(400.0)); assert _g['PASS'] is True and abs(_g['mean']-0.75)<1e-9
_g=gate(np.array([1.0]*300+[0.0]*300),np.arange(600.0)); assert _g['PASS'] is False and _g['h2']==0.0
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)

rc=psycopg2.connect(creds.pg_railway(),sslmode='require')
TR=pd.read_sql("SELECT tourney_id,tourney_date,tourney_name,tour,round,best_of,minutes,winner_norm,loser_norm,score FROM tennis_results_2026 WHERE tourney_date>='2024-06-01'",rc); rc.close()
TR['w']=TR.winner_norm.map(fold); TR['l']=TR.loser_norm.map(fold); TR['ro']=TR['round'].map(RO); TR['mins']=pd.to_numeric(TR.minutes,errors='coerce').astype(float)
print(f"results {len(TR)}, {TR.tourney_date.min()} to {TR.tourney_date.max()}, {time.time()-T0:.0f}s",flush=True)
ix=defaultdict(list); HIST=defaultdict(lambda:defaultdict(list)); FIRST=TR.groupby('tourney_id').ro.min().to_dict(); FINALS=defaultdict(list)
for r in TR.itertuples():
    ix[frozenset((r.w,r.l))].append(r)
    if pd.notna(r.ro):
        for p in (r.w,r.l): HIST[p][r.tourney_id].append((r.tourney_id,int(r.ro),r.mins,r.score,int(r.best_of) if pd.notna(r.best_of) else 3))
    if r.ro==7 and not walkover(r.score):
        FINALS[r.w].append((r.tourney_date,'CHAMP')); FINALS[r.l].append((r.tourney_date,'FINAL'))
def last_week(player,tdate):
    out=[]
    for d,k in FINALS.get(player,[]):
        if 3<=(tdate-d).days<=10: out.append(k)
    return out
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SELECT DISTINCT market_id,event_name,market_time FROM bf_hist_other WHERE sport='Tennis' AND market_type='MATCH_ODDS' AND event_name LIKE '%% v %%' AND event_name NOT LIKE '%%/%%'")
ALLM=cur.fetchall(); MID=[r[0] for r in ALLM]
print(f"singles MATCH_ODDS markets {len(MID)}, {time.time()-T0:.0f}s",flush=True)
SK=Counter(); rows=[]; BUDGET=2600
for c_ in range(0,len(MID),1000):
    if time.time()-T0>BUDGET: SK['chunks not pulled, budget']+=1; break
    cur.execute("""SELECT market_id,market_time,sel,extract(epoch from ts)::float8,ltp::float8,inplay FROM bf_hist_other WHERE sport='Tennis' AND market_id=ANY(%s) AND market_type='MATCH_ODDS' AND ltp>=1.01 AND ltp<=1000""",(MID[c_:c_+1000],))
    d=pd.DataFrame(cur.fetchall(),columns=['mid','mt','sel','ts','ltp','ip'])
    if d.empty: continue
    d=d.drop_duplicates(['mid','sel','ts']).sort_values(['mid','ts'],kind='stable')
    for mk,g in d.groupby('mid',sort=False):
        SK['market']+=1; ipts=g.ts[g.ip.values.astype(bool)]
        if len(ipts)==0: SK['no in-play print, off unknown']+=1; continue
        off=ipts.iloc[0]; pre=g[(~g.ip.values.astype(bool))&(g.ts<off)&(g.ts>=off-3600)]
        lp=pre.groupby('sel').ltp.last().to_dict()
        if len(lp)!=2: SK['not two runners with a pre-off print']+=1; continue
        names={fold(s):s for s in lp}; day=pd.Timestamp(g.mt.iloc[0]).date()
        hits=[h for h in ix.get(frozenset(names),[]) if -2<=(day-h.tourney_date).days<=21]
        if len(hits)!=1: SK['no unique results match']+=1; continue
        h=hits[0]
        if walkover(h.score): SK['walkover, void']+=1; continue
        tw=h.w
        if tw not in names: SK['winner not a runner']+=1; continue
        SK['scored']+=1
        if pd.isna(h.ro): SK['RR or unknown round, no prior']+=1; rnd=None
        else: rnd=int(h.ro)
        a,b=list(names)
        fav=a if lp[names[a]]<=lp[names[b]] else b
        pa=prior(HIST.get(a,{}),h.tourney_id,rnd) if rnd else None; pb=prior(HIST.get(b,{}),h.tourney_id,rnd) if rnd else None
        first=rnd is not None and rnd==FIRST.get(h.tourney_id)
        ga=groups(pa,pb,h.best_of,first) if rnd else []; gb=groups(pb,pa,h.best_of,first) if rnd else []
        if rnd and not pa: ga=ga+last_week(a,h.tourney_date)
        if rnd and not pb: gb=gb+last_week(b,h.tourney_date)
        for grp in ('BYE','CHAMP','FINAL'):
            if grp in ga and grp in gb: ga.remove(grp); gb.remove(grp); SK[f'{grp} both sides, dropped']+=1
        tourg='CH' if str(h.tour).upper().startswith('CH') else 'MAIN'
        for p,gs in ((a,ga),(b,gb)):
            rows.append((mk,day,tourg,'FAV' if p==fav else 'DOG',lp[names[p]],p==tw,','.join(gs)))
con.close(); print("counts:",dict(sorted(SK.items())),f"| {time.time()-T0:.0f}s",flush=True)
R=pd.DataFrame(rows,columns=['mk','day','tour','pos','p','won','grp'])
if R.empty: print("ERROR: no entries, so no verdict"); sys.exit(1)
R['when']=pd.to_datetime(R.day).astype('int64').astype(float)
R['B']=[back_settle(p,w) for p,w in zip(R.p,R.won)]; R['L']=[lay_settle(p,w) for p,w in zip(R.p,R.won)]
print(f"dates {R.day.min()}..{R.day.max()}, matches {R.mk.nunique()}, runners {len(R)}")
GR=('LONG','GAP60','THREE','BYE','EASY','CHAMP','FINAL'); out=[]
for tour in ('ALL','MAIN','CH'):
    x=R if tour=='ALL' else R[R.tour==tour]
    for ps in ('ALL','FAV','DOG'):
        y=x if ps=='ALL' else x[x.pos==ps]
        for side in 'BL':
            ctl=gate(y[side].values.astype(float),y.when.values)
            out.append(dict(grp='CONTROL',tour=tour,pos=ps,side=side,**ctl,won=y.won.mean(),imp=(1/y.p).mean(),ctl=ctl['mean']))
            for grp in GR:
                z=y[y.grp.str.split(',').map(lambda s:grp in s)]
                r=gate(z[side].values.astype(float),z.when.values)
                out.append(dict(grp=grp,tour=tour,pos=ps,side=side,**r,won=z.won.mean() if len(z) else np.nan,imp=(1/z.p).mean() if len(z) else np.nan,ctl=ctl['mean']))
S=pd.DataFrame(out); S['v_ctl']=S['mean']-S.ctl
print("\n== CONTROLS\n",S[S.grp=='CONTROL'].drop(columns=['PASS','n1','n2','ctl','v_ctl']).round(3).to_string(index=False))
print("\n== ALL x ALL, every group, both sides\n",S[(S.grp!='CONTROL')&(S.tour=='ALL')&(S.pos=='ALL')].drop(columns=['n1','n2']).round(3).to_string(index=False))
L=S[(S.grp!='CONTROL')]; print(f"\nlines {len(L)}, at n>=300: {(L.n>=300).sum()}")
print("\n== TOP 15 by t, n>=100\n",L[L.n>=100].sort_values('t',ascending=False).head(15).drop(columns=['n1','n2']).round(3).to_string(index=False))
Y=L[L.PASS]; print(f"\n== SURVIVORS: {len(Y)} of {len(L)}\n",Y.round(3).to_string(index=False) if len(Y) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
