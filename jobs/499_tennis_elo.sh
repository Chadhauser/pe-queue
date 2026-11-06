#!/bin/bash
set -o pipefail
# 499_tennis_elo (Finder 2026-11-06, queue item 187, Finder's own, source b): walk-forward tennis Elo (Kovalchik 2016, FiveThirtyEight, formula from memory, not checked) against the last pre-off print. Rule pushed before prices were read (commit 91a70c9). The number 499 is reused: 450-499 are all taken.
# ELO tennis_results_2026 (Railway, this table read only, as is tennis_matches): men's pool ATP plus Challenger from 2008, WTA from 2021, walkovers out, ordered by tournament date then round. K=250/(m+5)^0.4, m the player's earlier matches, overall and per surface. Rating is the mean of the two. No fit. WTA and ATP history start 2021, so the ratings are warm but not deep, and a men's rating has no ATP match before 2021.
# TAPE and ENTRY as jobs/499_tennis_preoff_flb.sh: T-20 to T-2 by market time, worse of the print and the next within 120 s, one tick, <= 50, 2%, £10 risk, last-traded prints so an upper bound. Unique match on both names, tournament start -2 to +21 days. Retirements stand; a line must also clear +£0.15 with them removed, as the Betfair retirement rule is from memory.
# SUPPORT ATP Elo on tennis_matches' own history, 2023-01 to 2024-08 at Pinnacle closes, exact price, 2%, not a fill, cannot pass.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(3_500_000_000,3_500_000_000))  # this job only
import sys,re,time,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,line,back_settle,lay_settle
pd.set_option('display.width',230); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',30)
T0=time.time(); BUDGET=2400; MINM=20; CUTS=(0.03,0.05,0.08)
RANK={'Q1':0,'Q2':1,'Q3':2,'Q4':2.5,'ER':3,'RR':4,'R128':5,'R64':6,'R32':7,'R16':8,'QF':9,'SF':10,'BR':10.5,'F':11,
      '1st Round':5,'2nd Round':6,'3rd Round':7,'4th Round':8,'Round Robin':4,'Quarterfinals':9,'Semifinals':10,'The Final':11}
def fold(s): return re.sub(r"[^a-z]","",unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower())
def walkover(score): return bool(re.search(r"W/O|WO|WALK",str(score).upper()))
def retired(score): return bool(re.search(r"RET|ABD|ABN|DEF",str(score).upper()))
def k_of(m): return 250/(m+5)**0.4
def pwin(ra,rb): return 1/(1+10**((rb-ra)/400))
class Elo:
    def __init__(s): s.r=defaultdict(lambda:1500.0); s.m=Counter()
    def rating(s,p,surf): return (s.r[p]+s.r[(p,surf)])/2
    def pre(s,w,l,surf):
        """(p of w, matches w, matches l) before this match."""
        return pwin(s.rating(w,surf),s.rating(l,surf)),s.m[w],s.m[l]
    def update(s,w,l,surf):
        for kw,kl in ((w,l),((w,surf),(l,surf))):
            e=pwin(s.r[kw],s.r[kl]); dw=k_of(s.m[kw])*(1-e); dl=k_of(s.m[kl])*(1-e); s.r[kw]+=dw; s.r[kl]-=dl; s.m[kw]+=1; s.m[kl]+=1
def entry(ts,p,mt):
    """As jobs/499_tennis_preoff_flb.sh. (print, next print within 120 s or None), or None. Window T-20 to T-2."""
    k=None
    for i in range(len(ts)):
        if mt-1200<=ts[i]<=mt-120: k=i
    if k is None: return None
    nx=float(p[k+1]) if k+1<len(ts) and ts[k+1]-ts[k]<=120 else None
    return float(p[k]),nx
def value(side,e,won):
    if e[0]>50: return None
    if side=='B':
        x=min(e[0],e[1]) if e[1] is not None else e[0]; a=step(x,-1)
        return None if a<=1.01 else back_settle(a,won)
    x=max(e[0],e[1]) if e[1] is not None else e[0]; a=step(x,1)
    return lay_settle(a,won)
def edges(p,xa,xb):
    """Model p of a less the market's normalised p of a."""
    return p-(1/xa)/((1/xa)+(1/xb))
# known answers, worked by hand
assert abs(k_of(0)-250/5**0.4)<1e-12 and abs(k_of(0)-131.3)<0.1 and abs(k_of(95)-250/100**0.4)<1e-12 and abs(k_of(95)-39.6)<0.1
assert abs(pwin(1500,1500)-0.5)<1e-12 and abs(pwin(1700,1500)-1/(1+10**(-0.5)))<1e-12 and abs(pwin(1700,1500)-0.7597)<1e-3
_e=Elo(); assert _e.pre('a','b','Clay')==(0.5,0,0)
_e.update('a','b','Clay'); _d=k_of(0)*0.5
assert abs(_e.r['a']-1500-_d)<1e-9 and abs(_e.r['b']-1500+_d)<1e-9 and abs(_e.r[('a','Clay')]-1500-_d)<1e-9 and _e.m['a']==1 and _e.m[('b','Clay')]==1
assert abs(_e.rating('a','Grass')-(1500+_d+1500)/2)<1e-9 and _e.r[('a','Grass')]==1500.0      # a grass rating has no clay match in it
_e=Elo(); _e.m['a']=95; _e.m['b']=0; _e.update('a','b','Clay'); assert abs(_e.r['a']-1500-k_of(95)*.5)<1e-9 and abs(_e.r['b']-1500+k_of(0)*.5)<1e-9      # K is each player's own, not zero sum
assert abs(edges(0.6,2.0,2.0)-0.1)<1e-12 and abs(edges(0.5,1.5,3.0)-(0.5-2/3))<1e-12
assert entry([0.,100.,110.],[2.,3.,4.],1300.)==(4.0,None) and entry([100.,1170.,1250.],[2.,3.,4.],1300.)==(3.0,4.0) and entry([1250.],[2.],1300.) is None
assert abs(value('B',(2.0,1.9),True)-8.722)<1e-9 and value('B',(2.0,1.9),False)==-10.0 and abs(value('L',(2.0,2.2),False)-10/1.22*0.98)<1e-9 and value('L',(2.0,2.2),True)==-10.0 and value('B',(51.0,None),True) is None
assert walkover('W/O') and not walkover('6-1 3-2 RET') and retired('6-1 3-2 RET') and not retired('6-1 6-2') and fold('Jiří Lehečka')=='jirilehecka'
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require')
TR=pd.read_sql("SELECT tourney_date,winner_norm,loser_norm,score,tour,surface,round,match_num FROM tennis_results_2026",rc)
TM=pd.read_sql("SELECT date,surface,round,winner,loser,psw::float8 psw,psl::float8 psl,wsets,lsets FROM tennis_matches WHERE tour='ATP' ORDER BY date",rc); rc.close()
TR['tour']=TR.tour.astype(str).str.upper(); TR['rk']=TR['round'].map(RANK); print("rounds with no rank",TR[TR.rk.isna()]['round'].value_counts().to_dict(),flush=True); TR['rk']=TR.rk.fillna(4)
TR=TR.sort_values(['tourney_date','rk','match_num'],kind='stable'); EL={'M':Elo(),'W':Elo()}; ix=defaultdict(list); nw=0
for r in TR.itertuples():
    if walkover(r.score): nw+=1; continue
    w,l=fold(r.winner_norm),fold(r.loser_norm); E=EL['W' if r.tour=='WTA' else 'M']; p,mw,ml=E.pre(w,l,r.surface)
    ix[frozenset((w,l))].append((r.tourney_date,w,r.score,r.tour,p,mw,ml)); E.update(w,l,r.surface)
print(f"results {len(TR)}, walkovers out {nw}, {TR.tourney_date.min()}..{TR.tourney_date.max()} | {time.time()-T0:.0f}s",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SELECT DISTINCT market_id FROM bf_hist_other WHERE sport='Tennis' AND market_type='MATCH_ODDS'")
MID=sorted(r[0] for r in cur.fetchall() if r[0].startswith('MATCH_ODDS|') and '/' not in r[0])
print(f"singles markets {len(MID)} | {time.time()-T0:.0f}s",flush=True)
SK=Counter(); rows=[]; seen=set(); CAL=[]
for c_ in range(0,len(MID),800):
    if time.time()-T0>BUDGET: SK['chunks not pulled, budget']+=1; continue
    cur.execute("""SELECT market_id,extract(epoch from market_time)::float8,market_time,sel,extract(epoch from ts)::float8,ltp::float8 FROM bf_hist_other
                   WHERE sport='Tennis' AND market_id=ANY(%s) AND market_type='MATCH_ODDS' AND NOT inplay AND ltp>=1.01 AND ltp<=1000 AND ts>=market_time-interval '25 minutes'""",(MID[c_:c_+800],))
    d=pd.DataFrame(cur.fetchall(),columns='mid mts mt sel ts ltp'.split())
    if d.empty: continue
    d=d.drop_duplicates(['mid','sel','ts']).sort_values(['mid','ts'],kind='stable')
    for mk,g in d.groupby('mid',sort=False):
        SK['market']+=1; run={s:x for s,x in g.groupby('sel',sort=False)}
        if len(run)!=2: SK['not two runners with prints']+=1; continue
        names={fold(s):s for s in run}; day=pd.Timestamp(g.mt.iloc[0]).date(); mt=float(g.mts.iloc[0]); pair=frozenset(names)
        hits=[h for h in ix.get(pair,[]) if -2<=(day-h[0]).days<=21]
        if len(hits)!=1: SK['no unique results match or walkover']+=1; continue
        hd,win_k,score,tour,pw,mw,ml=hits[0]
        if (pair,hd) in seen: SK['second market on one result row, skipped']+=1; continue
        if mw<MINM or ml<MINM: SK['under 20 matches']+=1; continue
        win=names[win_k]; lose=[names[k] for k in names if k!=win_k][0]; ew=entry(run[win].ts.values,run[win].ltp.values,mt); el=entry(run[lose].ts.values,run[lose].ltp.values,mt)
        if ew is None or el is None: SK['no entry print both runners']+=1; continue
        seen.add((pair,hd)); SK['scored']+=1; ret=retired(score); ed=edges(pw,ew[0],el[0]); CAL.append((tour,pw,1/ew[0]/(1/ew[0]+1/el[0])))
        for c in CUTS:
            if ed>=c:   # winner is model-cheap: the back hits, the lay of the other runner wins
                rows.append((c,'BACK',tour,day,mk,ret,True,ew[0],value('B',ew,True)))
                rows.append((c,'LAY',tour,day,mk,ret,False,el[0],value('L',el,False)))
            elif ed<=-c:  # loser is model-cheap: the back loses, the lay of the winner loses
                rows.append((c,'BACK',tour,day,mk,ret,False,el[0],value('B',el,False)))
                rows.append((c,'LAY',tour,day,mk,ret,True,ew[0],value('L',ew,True)))
    print(f"  {min(c_+800,len(MID))}/{len(MID)}, rows {len(rows)} | {time.time()-T0:.0f}s",flush=True)
con.close(); print("counts:",dict(sorted(SK.items())),flush=True)
R=pd.DataFrame(rows,columns='cut side tour day m ret won px v'.split())
if R.empty: print("ERROR: no entries, no verdict"); sys.exit(1)
nb=R.v.isna().sum(); R=R.dropna(subset=['v']); R['v']=R.v.astype(float); R['when']=pd.to_datetime(R.day).astype('int64')
print(f"dates {R.day.min()}..{R.day.max()}; matches {R.m.nunique()}; no bet at the ladder ends {nb}",flush=True)
Cc=pd.DataFrame(CAL,columns=['tour','model','mkt']); print("\n== log loss, winner's p, lower is better (entry-print market v Elo)")
print(Cc.assign(lm=-np.log(Cc.model),lk=-np.log(Cc.mkt)).groupby('tour').agg(n=('lm','size'),elo=('lm','mean'),market=('lk','mean')).round(4).to_string())
out=[]
for (c,side),A in R.groupby(['cut','side']):
    for tour in ('ATP','WTA','CHALLENGER','ALL'):
        x=A if tour=='ALL' else A[A.tour==tour]
        if not len(x): continue
        md=np.median(x.when.values); l=line(x.v.values,np.where(x.when.values<md,1,2)); xr=x[~x.ret].v
        ok=bool(l['PASS'] and len(xr)>0 and xr.mean()>=0.15)
        out.append(dict(cut=c,tour=tour,side=side,n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],x_ret=xr.mean() if len(xr) else np.nan,won=x.won.mean(),implied=(1/x.px).mean(),maxwin=l['maxwin'],PASS=ok))
S=pd.DataFrame(out).sort_values('t',ascending=False); print(f"\n== ALL {len(S)} LINES, per £10, by t\n",S.round(3).to_string(index=False))
# support: tennis_matches' own ATP Elo at Pinnacle closes
TM['d']=pd.to_datetime(TM.date); TM['rk']=TM['round'].map(RANK).fillna(4); TM=TM.sort_values(['d','rk'],kind='stable'); Ea=Elo(); rows=[]; LL=[]
for r in TM.itertuples():
    if r.wsets==0 and r.lsets==0: continue
    p,mw,ml=Ea.pre(r.winner,r.loser,r.surface)
    if pd.Timestamp('2023-01-01')<=r.d<pd.Timestamp('2024-09-01') and mw>=MINM and ml>=MINM and r.psw and r.psl and r.psw>1 and r.psl>1:
        ed=edges(p,r.psw,r.psl); LL.append((-np.log(p),-np.log((1/r.psw)/(1/r.psw+1/r.psl))))
        for c in CUTS:
            if ed>=c: rows+=[(c,'BACK',r.d,back_settle(r.psw,True)),(c,'LAY',r.d,lay_settle(r.psl,False))]
            elif ed<=-c: rows+=[(c,'BACK',r.d,back_settle(r.psl,False)),(c,'LAY',r.d,lay_settle(r.psw,True))]
    Ea.update(r.winner,r.loser,r.surface)
Q=pd.DataFrame(rows,columns='cut side d v'.split()); LL=np.array(LL); md=Q.d.median(); out=[]
print(f"\n== SUPPORT ATP Elo at Pinnacle closes, 2023-01 to 2024-08, {len(LL)} matches, exact price, 2%: log loss Elo {LL[:,0].mean():.4f}, Pinnacle {LL[:,1].mean():.4f}; a lay here collects Pinnacle's margin")
for k,x in Q.groupby(['cut','side']):
    l=line(x.v.values,np.where(x.d<md,1,2)); out.append(dict(cut=k[0],side=k[1],n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2']))
print(pd.DataFrame(out).round(3).to_string(index=False))
W=S[S.PASS]; print(f"\n== SURVIVORS: {len(W)} of {len(S)}\n",W.round(3).to_string(index=False) if len(W) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
