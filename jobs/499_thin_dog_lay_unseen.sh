#!/bin/bash
set -o pipefail
# 499_thin_dog_lay_unseen (Finder 2026-11-05, queue item 153, Finder's own, source c; from jobs/499_longtail_senior.sh): lay the underdog in a thin senior game, on games with no official result. Rule pushed in the queue before any of these prices was read. Read only.
# ENTRY as item 144: last non-in-play MO print T-20 to T-2 on each team, dog is the longer of the two at those prints, worse of the print and the next print within 120 s, one tick adverse, 2%, £10 liability, hold to the result. Over 50 not traded. One bet per event, on one MO id per event (the tape holds Sep MO twice; the lowest id sorts real ids first and does not look at the outcome).
# SENIOR: lib_official.group is None. THIN: MO prints T-60 to T-20 at or under 6, item 144's cut. Control: the same lay in other senior games. UNSEEN: event has no row in bf_hist_result for any of item 144's six market types.
# NOTE after the run: goal_timeline holds only 1H, HT, 2H and ET in this window, never FT, so every settle is the last row at minute 88+ and the "FT rows only" lines are empty by construction. They are left in so the code matches the logged run.
# SETTLE on goal_timeline finished rows as jobs/499_ou35_under_mid.sh; no score match dropped, counted. Before trusting it, the same settle is compared with the official MO winner on the seen games, and the line is re-read on FT-status rows only (a row at minute 88+ can miss a late goal, which matters more for MO than for totals).
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import norm,jac,loose,line
from lib_official import group,ly,fill,last_in,secs,load_results,checks
import lib_cand; lib_cand._checks(); checks()
TYPES=['MATCH_ODDS','OVER_UNDER_15','OVER_UNDER_25','OVER_UNDER_35','BOTH_TEAMS_TO_SCORE','FIRST_HALF_GOALS_05']
FT=['FT','Match Finished','FINISHED']
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
def band(n): return 'THIN' if n<=6 else 'OTHER'
def team_won(is_home,h,a): return h>a if is_home else a>h
# known answers: the cut at 6; a draw is a lay win on either team; home dog and away dog both ways; lay 5.0 fills 5.1, stake 10/4.1, wins 2.3902 after 2%, loses 10
assert band(0)=='THIN' and band(6)=='THIN' and band(7)=='OTHER'
assert not team_won(True,1,1) and not team_won(False,1,1) and not team_won(True,0,0)
assert team_won(True,2,1) and not team_won(True,1,2) and team_won(False,1,2) and not team_won(False,2,1)
assert abs(ly(5.0,False)-10/4.1*.98)<1e-9 and ly(5.0,True)==-10.0
assert mo_pair('Hull','Leeds',['Leeds','The Draw','Hull'])==('Hull','Leeds') and mo_pair('Hull','Leeds',['Derby','Stoke','The Draw']) is None
print("checks: OK",flush=True); T0=time.time()
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
HAS=set(pd.read_sql("SELECT DISTINCT event_id FROM bf_hist_result WHERE sport='Soccer' AND market_type=ANY(%s)",con,params=(TYPES,)).event_id)
RS,bad=load_results(con,['MATCH_ODDS']); print(f"official MO markets with one WINNER {len(RS)}, dropped {bad}, seen events {len(HAS)}",flush=True)
X=pd.read_sql("SELECT market_id,event_id,event_name ev,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_time>='2026-05-01' AND market_time<'2026-10-02' AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '60 minutes'",con)
GT=pd.read_sql("SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,captured_at,minute,score_home,score_away,status FROM goal_timeline WHERE captured_at>='2026-05-01' AND captured_at<'2026-10-03' AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at DESC",con); con.close()
print(f"MO rows {len(X)}, events {X.event_id.nunique()}, markets {X.market_id.nunique()}, {time.time()-T0:.0f}s",flush=True)
GT['t']=secs(GT.captured_at); GT['mn']=pd.to_numeric(GT.minute,errors='coerce'); GT['isft']=GT.status.isin(FT)
GT=GT[GT.isft|((GT.mn>=88)&~GT.status.isin(['AET','PEN','ET']))].sort_values('t').reset_index(drop=True); GT['H']=GT.home_team.map(norm); GT['A']=GT.away_team.map(norm); tt=GT.t.values
print(f"finished goal_timeline rows {len(GT)}, FT status {int(GT.isft.sum())}",flush=True)
def settle_row(ev,o):
    h,_x,a=ev.partition(' v '); lo,hi=np.searchsorted(tt,o),np.searchsorted(tt,o+14400)
    return loose(norm(h),norm(a),[(x.H,x.A,x.Index) for x in GT.iloc[lo:hi].itertuples()])
X['tt']=secs(X.ts); X['off']=secs(X.mt); X=X.sort_values('tt',kind='stable')
ids=X.drop_duplicates('market_id')[['market_id','event_id']]; print("events held under more than one MO id:",int((ids.groupby('event_id').size()>1).sum()),flush=True)
keep=ids.sort_values('market_id').drop_duplicates('event_id').market_id
X=X[X.market_id.isin(set(keep))].drop_duplicates(['market_id','sel','tt'])
C=Counter(); rows=[]; agree=Counter()
for e,g in X.groupby('event_id'):
    ev=g.ev.iloc[0]; o=float(g.off.iloc[0]); m=g.market_id.iloc[0]; seen=e in HAS
    if seen and m in RS and group(ev) is None:
        # settlement check only, no price is scored on these games
        hm,_x,aw=ev.partition(' v '); pr=mo_pair(hm,aw,list(RS[m]))
        if pr:
            fx=settle_row(ev,o)
            if fx is None: agree['no score match']+=1
            else:
                sh,sa=int(GT.score_home[fx]),int(GT.score_away[fx]); off=('home' if RS[m][pr[0]] else 'away' if RS[m][pr[1]] else 'draw'); gt='home' if sh>sa else 'away' if sa>sh else 'draw'
                agree[('FT ' if GT.isft[fx] else '88+ ')+('agree' if off==gt else 'DISAGREE')]+=1
    if seen: C['seen, excluded']+=1; continue
    if group(ev) is not None: C['women or youth']+=1; continue
    hm,_x,aw=ev.partition(' v '); pr=mo_pair(hm,aw,list(g.sel.unique()))
    if pr is None: C['runners not matched']+=1; continue
    ent={}
    for s in pr:
        y=g[g.sel==s]; ts,px=y.tt.values,y.ltp.values; i=last_in(ts,o-1200,o-120)
        if i is not None: ent[s]=(ts,px,i)
    if len(ent)<2: C['no print on both teams in window']+=1; continue
    hf=ent[pr[0]][1][ent[pr[0]][2]]<=ent[pr[1]][1][ent[pr[1]][2]]; dog=pr[1] if hf else pr[0]; dog_home=not hf   # tie: home is favourite, as item 144
    ts,px,i=ent[dog]; p=fill(ts,px,i,'L')
    if p>50: C['over 50']+=1; continue
    liq=int(((g.tt>=o-3600)&(g.tt<o-1200)).sum()); b=band(liq); fx=settle_row(ev,o)
    if fx is None: C['no score match, dropped']+=1; rows.append((e,o,b,None,1/p,np.nan,False)); continue
    won=team_won(dog_home,int(GT.score_home[fx]),int(GT.score_away[fx])); rows.append((e,o,b,won,1/p,ly(p,won),bool(GT.isft[fx])))
print("counted:",dict(sorted(C.items())),flush=True); print("settle v official MO winner, seen senior games:",dict(sorted(agree.items())),flush=True)
A=pd.DataFrame(rows,columns='e off b won imp v ft'.split()); D=A[A.v.isna()]; R=A[A.v.notna()].copy(); R['won']=R.won.astype(bool); md=np.median(R.off.values); R['h']=np.where(R.off<md,1,2)
print("trades by month:",pd.to_datetime(R.off,unit='s').dt.strftime('%Y-%m').value_counts().sort_index().to_dict(),"median",pd.to_datetime(md,unit='s'))
print("dropped, no score match, by band: n, mean implied:",D.groupby('b').imp.agg(['size','mean']).round(3).to_dict('index'),"; kept:",R.groupby('b').imp.agg(['size','mean']).round(3).to_dict('index'))
out=[]
def add(nm,x):
    l=line(x.v.values,x.h.values); out.append(dict(line=nm,n=l['n'],games=x.e.nunique(),per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],won=x.won.mean(),imp=x.imp.mean(),PASS=l['PASS']))
for k,x in R.groupby('b'): add(f"{k} MO Dog lay",x); add(f"{k} MO Dog lay, FT rows only",x[x.ft])
O=pd.DataFrame(out); pd.set_option('display.width',200); print("\n"+O.round(3).to_string(index=False))
S=O[O.PASS&(O.line=='THIN MO Dog lay')]; print(f"\n== SURVIVORS: {len(S)} of 1\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
