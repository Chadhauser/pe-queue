#!/bin/bash
set -o pipefail
# 499_tennis_late_outsider (Finder 2026-11-04, queue item 71): a final print <= 1.05 appears for 88.5% of winning favourites but 73.2% of winning outsiders (jobs/499_final_print_bias.sh). Are late outsiders priced differently from late favourites?
# TAPE: bf_hist_other Tennis singles MATCH_ODDS, in-play LTP only, no book, so a pass is an upper bound. TRUTH: tennis_results_2026, unique match on both player names, tournament start -2 to +21 days from the market. Walkovers void on Betfair: excluded and counted. Retirements kept, winner as recorded.
# GROUPS: OUT = runner whose first in-play print is above 2.00. FAV = the runner with the shorter first in-play print (control). A runner counts for threshold T only if its first print is above T.
# ENTRY: first print at or under T (1.50, 1.30, 1.15), then fill at the NEXT print of that runner, never the trigger's own, one tick adverse. No next print = no trade, counted: the runner stopped trading, so it cannot be filled. One entry per match per cell.
# BACK is the item's rule. LAY is the mirror. Hold to the real result. 2% commission, £10 risk. Halves: median market date.
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
def pos(p): return int(np.searchsorted(LADA,round(float(p),2)-1e-9))
def dn(p): return float(LADA[max(pos(p)-1,0)])
def up(p): return float(LADA[min(pos(p)+1,len(LADA)-1)])
def comm(x): return x*0.98 if x>0 else x
def back_settle(p,won):
    a=dn(p)
    if a<=1.01: return np.nan
    return comm(10*(a-1)) if won else -10.0
def lay_settle(p,won):
    a=up(p); return -10.0 if won else comm(10/(a-1))
def tstat(v):
    v=np.asarray(v,dtype=float); v=v[np.isfinite(v)]
    if len(v)<2: return 0.0
    s=v.std(ddof=1); return float(v.mean()/(s/len(v)**0.5)) if s>0 else 0.0
def fold(s): return re.sub(r"[^a-z]","",unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower())
def walkover(score): return bool(re.search(r"W/O|WO|WALK",str(score).upper()))
def entry(p,T):
    """p: one runner's prints in time order. Returns (state, fill price): 'none' never reached T or started at or under it, 'nofill' reached T with no later print, 'ok' filled at the next print."""
    if len(p)==0 or p[0]<=T: return 'none',None
    for i in range(1,len(p)):
        if p[i]<=T+1e-9: return ('ok',float(p[i+1])) if i+1<len(p) else ('nofill',None)
    return 'none',None
def gate(v,when):
    m=np.isfinite(v); v=v[m]; when=when[m]
    if len(v)==0: return dict(n=0,mean=np.nan,t=0.0,n1=0,h1=np.nan,n2=0,h2=np.nan,PASS=False)
    md=np.median(when); a=v[when<md]; b=v[when>=md]; t=tstat(v)
    return dict(n=len(v),mean=v.mean(),t=t,n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,
                PASS=bool(len(v)>=300 and len(a)>=150 and len(b)>=150 and t>=3.5 and a.mean()>0 and b.mean()>0 and v.mean()>=0.15))
# known answers, worked by hand
assert dn(1.5)==1.49 and up(1.5)==1.51 and dn(2.0)==1.99
assert abs(back_settle(1.30,True)-10*0.29*0.98)<1e-9 and back_settle(1.30,False)==-10.0 and np.isnan(back_settle(1.02,True))      # 1.30 fills 1.29; 1.02 fills 1.01: no bet
assert abs(lay_settle(1.30,False)-10/0.31*0.98)<1e-9 and lay_settle(1.30,True)==-10.0                                              # 1.30 fills 1.31
assert entry([3.0,2.0,1.5,1.4],1.5)==('ok',1.4) and entry([3.0,2.0,1.5],1.5)==('nofill',None) and entry([3.0,2.0],1.5)==('none',None)  # at the level counts; next print only
assert entry([1.4,1.2,1.1],1.5)==('none',None) and entry([],1.5)==('none',None)                                                    # started under T: not a late move
assert entry([3.0,1.2,5.0],1.5)==('ok',5.0)                                                                                        # the next print is the real fill, even if it went against us
assert walkover('W/O') and not walkover('6-1 3-2 RET') and not walkover('6-1 6-4') and fold('Jiří Lehečka')=='jirilehecka'
_g=gate(np.array([1.0,0.5]*200),np.arange(400.0)); assert _g['PASS'] is True and abs(_g['mean']-0.75)<1e-9
_g=gate(np.array([1.0]*300+[0.0]*300),np.arange(600.0)); assert _g['PASS'] is False and _g['h2']==0.0
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)

rc=psycopg2.connect(creds.pg_railway(),sslmode='require'); TR=pd.read_sql("SELECT tourney_date,winner_norm,loser_norm,score,tour FROM tennis_results_2026 WHERE tourney_date>='2024-08-01'",rc); rc.close()
ix=defaultdict(list)
for r in TR.itertuples(): ix[frozenset((fold(r.winner_norm),fold(r.loser_norm)))].append((r.tourney_date,fold(r.winner_norm),walkover(r.score),r.tour))
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("""WITH RECURSIVE t AS ((SELECT market_id FROM bf_hist_other WHERE sport='Tennis' ORDER BY market_id LIMIT 1)
  UNION ALL SELECT (SELECT market_id FROM bf_hist_other WHERE sport='Tennis' AND market_id>t.market_id ORDER BY market_id LIMIT 1) FROM t WHERE t.market_id IS NOT NULL)
  SELECT market_id FROM t WHERE market_id IS NOT NULL""")
MID=[r[0] for r in cur.fetchall() if r[0].startswith('MATCH_ODDS|') and '/' not in r[0]]
print(f"singles MATCH_ODDS markets {len(MID)} | {time.time()-T0:.0f}s",flush=True)
SK=Counter(); rows=[]; BUDGET=2400
for c_ in range(0,len(MID),500):
    if time.time()-T0>BUDGET: SK['chunks not pulled, budget']+=1; break
    cur.execute("""SELECT market_id,market_time,sel,extract(epoch from ts)::float8,ltp::float8 FROM bf_hist_other WHERE sport='Tennis' AND market_id=ANY(%s) AND market_type='MATCH_ODDS' AND inplay AND ltp>=1.01 AND ltp<=1000""",(MID[c_:c_+500],))
    d=pd.DataFrame(cur.fetchall(),columns=['mid','mt','sel','ts','ltp'])
    if d.empty: continue
    d=d.drop_duplicates(['mid','sel','ts']).sort_values(['mid','ts'],kind='stable')
    for mk,g in d.groupby('mid',sort=False):
        SK['market']+=1; run={s:x.ltp.values for s,x in g.groupby('sel',sort=False)}
        if len(run)!=2: SK['not two runners with prints']+=1; continue
        names={fold(s):s for s in run}; day=pd.Timestamp(g.mt.iloc[0]).date()
        hits=[h for h in ix.get(frozenset(names),[]) if -2<=(day-h[0]).days<=21]
        if len(hits)!=1: SK['no unique results match']+=1; continue
        if hits[0][2]: SK['walkover, void']+=1; continue
        tw=names[hits[0][1]]; SK['scored']+=1
        a,b=list(run); fav=a if run[a][0]<=run[b][0] else b
        for s,p in run.items():
            groups=(['OUT'] if p[0]>2.0 else [])+(['FAV'] if s==fav else [])
            for grp in groups:
                for T in (1.50,1.30,1.15):
                    st,x=entry(p,T)
                    if st=='none': continue
                    SK[f'{grp} {T} {st}']+=1
                    rows.append((grp,T,mk,day,st,x,s==tw))
con.close(); print("counts:",dict(sorted(SK.items())),f"| {time.time()-T0:.0f}s",flush=True)
R=pd.DataFrame(rows,columns=['grp','T','mk','day','st','x','won'])
if R.empty: print("ERROR: no entries, so no verdict"); sys.exit(1)
R['when']=pd.to_datetime(R.day).astype('int64')
print(f"dates {R.day.min()}..{R.day.max()}, matches with an entry {R.mk.nunique()}")
print("\n== triggered runners, including those with no later print to fill at (won = real result):")
print(R.groupby(['grp','T','st']).agg(n=('won','size'),won=('won','mean')).round(3).to_string(),flush=True)
F=R[R.st=='ok'].copy(); F['x']=F.x.astype(float)
F['B']=[back_settle(p,w) for p,w in zip(F.x,F.won)]; F['L']=[lay_settle(p,w) for p,w in zip(F.x,F.won)]
out=[]
for (grp,T),d in F.groupby(['grp','T']):
    for side,col in (('BACK','B'),('LAY','L')):
        r=gate(d[col].values.astype(float),d.when.values.astype(float))
        fill=d.x.map(dn) if side=='BACK' else d.x.map(up)
        out.append(dict(grp=grp,T=T,side=side,**r,won=d.won.mean(),implied=(1/fill).mean(),med_fill=d.x.median(),max_win=d[col].max(),top1pct=(np.sort(d[col].dropna().values)[-max(1,len(d)//100):].sum()/max(d[col].sum(),1e-9)) if d[col].sum()>0 else np.nan))
S=pd.DataFrame(out).sort_values('t',ascending=False)
print("\n== ALL LINES, per £10, sorted by t (back and lay of one cell are the same bets reversed)\n",S.round(3).to_string(index=False))
print("\n== OUT minus FAV, won minus implied at the back fill:")
for T in (1.50,1.30,1.15):
    a=S[(S.grp=='OUT')&(S['T']==T)&(S.side=='BACK')].iloc[0]; b=S[(S.grp=='FAV')&(S['T']==T)&(S.side=='BACK')].iloc[0]
    print(f"  T {T}: OUT {a.won-a.implied:+.4f} (n {a.n}) v FAV {b.won-b.implied:+.4f} (n {b.n})")
W=S[S.PASS]; print(f"\n== SURVIVORS: {len(W)} of {len(S)}\n",W.round(3).to_string(index=False) if len(W) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
