#!/bin/bash
set -o pipefail
# 499_tennis_format (Finder 2026-11-06, queue items 215, 216, Finder's own, sources c, b): match format and player type; Barnett and Clarke serve-return model; both at the last pre-off print. Rules pushed before any price was read. The number 499 is reused: 450-499 are all taken.
# TAPE, ENTRY, MATCH, RETIREMENTS as jobs/499_tennis_switch_rust.sh: T-20 to T-2, worse of the print and the next within 120 s, one tick, <= 50, 2%, £10 risk, to the result, last-traded prints so an upper bound; unique match on both names, tournament start -2 to +21 days; a line must also clear +£0.15 with retirements removed.
# WALK tennis_results_2026 (Railway, this table read only), walkovers out, tournament date then round order, so dates are coarse. Model inputs use earlier rows only.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_800_000_000,1_800_000_000))  # this job only
import sys,re,time,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict,deque
from functools import lru_cache
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,line,back_settle,lay_settle
pd.set_option('display.width',240); pd.set_option('display.max_rows',150); pd.set_option('display.max_columns',30)
T0=time.time(); BUDGET=2100; WINDOW=60; MINM=15
RANK={'Q1':0,'Q2':1,'Q3':2,'Q4':2.5,'ER':3,'RR':4,'R128':5,'R64':6,'R32':7,'R16':8,'QF':9,'SF':10,'BR':10.5,'F':11,
      '1st Round':5,'2nd Round':6,'3rd Round':7,'4th Round':8,'Round Robin':4,'Quarterfinals':9,'Semifinals':10,'The Final':11}
ROUND={'SF':'SF','Semifinals':'SF','F':'F','The Final':'F'}
def fold(s): return re.sub(r"[^a-z]","",unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower())
def walkover(score): return bool(re.search(r"W/O|WO|WALK",str(score).upper()))
def retired(score): return bool(re.search(r"RET|ABD|ABN|DEF",str(score).upper()))
def entry(ts,p,mt):
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
# --- Barnett-Clarke: exact point, game, tiebreak, set, match
@lru_cache(maxsize=None)
def game(p):
    """Server holds, p = server's point win. Deuce closed form p^2/(p^2+q^2)."""
    q=1-p; d=p*p/(p*p+q*q) if p*p+q*q>0 else 0.0
    return p**4*(1+4*q+10*q*q)+20*p**3*q**3*d
def tiebreak(pa,pb):
    """A serves point 1, then two each. 7 clear by two; 6-6 onward closed form."""
    @lru_cache(maxsize=None)
    def go(a,b):
        if a>=7 and a-b>=2: return 1.0
        if b>=7 and b-a>=2: return 0.0
        if a==6 and b==6: return _deuce(pa,pb)
        n=a+b; a_serves=n==0 or ((n-1)//2)%2==1
        pw=pa if a_serves else 1-pb
        return pw*go(a+1,b)+(1-pw)*go(a,b+1)
    return go(0,0)
def _deuce(pa,pb):
    """At 6-6, pairs of points, one serve each: win both, lose both, or split and repeat."""
    w=pa*(1-pb); l=(1-pa)*pb
    return w/(w+l) if w+l>0 else 0.5
def set_win(pa,pb):
    """A serves first. Tie-break at 6-6, A serves first in it, as the player due."""
    ga,gb=game(pa),game(pb); tb=tiebreak(pa,pb)
    @lru_cache(maxsize=None)
    def go(a,b):
        if a>=6 and a-b>=2: return 1.0
        if b>=6 and b-a>=2: return 0.0
        if a==6 and b==6: return tb
        w=ga if (a+b)%2==0 else 1-gb
        return w*go(a+1,b)+(1-w)*go(a,b+1)
    return go(0,0)
@lru_cache(maxsize=None)
def match_cached(pa,pb,best_of):
    # who serves first is unknown: mean of the two
    s=(set_win(pa,pb)+(1-set_win(pb,pa)))/2; need=2 if best_of==3 else 3
    @lru_cache(maxsize=None)
    def go(a,b):
        if a==need: return 1.0
        if b==need: return 0.0
        return s*go(a+1,b)+(1-s)*go(a,b+1)
    return go(0,0)
def match_prob(fij,fji,best_of):
    r=lambda x:round(min(max(float(x),0.40),0.90)*200)/200
    return match_cached(r(fij),r(fji),int(best_of))
def serve_est(fi,gi,fj,gj,ft):
    """f_ij = ft + (fi-ft) - (gj-gt), gt = 1-ft: i's serve points against j."""
    gt=1-ft; return ft+(fi-ft)-(gj-gt),ft+(fj-ft)-(gi-gt)
def fav_band(p): return '<1.2' if p<1.2 else '1.2-1.5' if p<1.5 else '1.5-2' if p<2 else None
def young(ax,bx,gap=6.0):
    """Age gap in years: 'a' if a is younger by >= gap, 'b' if b is."""
    if ax is None or bx is None or ax!=ax or bx!=bx: return None
    return 'a' if bx-ax>=gap else 'b' if ax-bx>=gap else None
# known answers, worked by hand
assert abs(game(0.5)-0.5)<1e-12 and abs(game(0.6)-0.7357)<5e-4 and abs(game(0.7)-0.9008)<5e-4        # published hold table
assert abs(tiebreak(0.5,0.5)-0.5)<1e-12 and abs(set_win(0.5,0.5)-0.5)<1e-12 and abs(match_cached(0.5,0.5,3)-0.5)<1e-12
assert abs(match_cached(0.6,0.6,3)-0.5)<1e-9 and abs(match_cached(0.6,0.6,5)-0.5)<1e-9                # equal players, by symmetry, whatever the serve order
assert match_cached(0.65,0.60,5)>match_cached(0.65,0.60,3)>0.5                                         # the better player gains from a longer match
assert abs(match_cached(0.65,0.60,3)+match_cached(0.60,0.65,3)-1)<1e-9                                 # two sides sum to 1
assert all(abs(a-b)<1e-12 for a,b in zip(serve_est(.65,.35,.60,.40,.62),(.65-(.40-.38),.60-(.35-.38))))   # j returns 2 points above tour; i returns 3 below
assert abs(match_prob(0.625,0.625,3)-0.5)<1e-9 and match_prob(0.99,0.1,3)==match_cached(0.90,0.40,3)   # clipped, not extrapolated
assert fav_band(1.19)=='<1.2' and fav_band(1.2)=='1.2-1.5' and fav_band(1.5)=='1.5-2' and fav_band(2.0) is None
assert young(20.,26.)=='a' and young(26.,20.)=='b' and young(20.,25.9) is None and young(None,20.) is None and young(float('nan'),20.) is None
assert entry([100.,1170.,1250.],[2.,3.,4.],1300.)==(3.0,4.0) and entry([1250.],[2.],1300.) is None
assert abs(value('B',(2.0,1.9),True)-8.722)<1e-9 and value('B',(2.0,1.9),False)==-10.0 and abs(value('L',(2.0,2.2),False)-10/1.22*0.98)<1e-9 and value('L',(2.0,2.2),True)==-10.0 and value('B',(51.0,None),True) is None
assert walkover('W/O') and retired('6-1 3-2 RET') and not retired('6-1 6-2')
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require')
TR=pd.read_sql("""SELECT tourney_date,winner_norm,loser_norm,score,tour,surface,round,match_num,best_of,tourney_level,indoor,winner_hand,loser_hand,winner_age::float8 winner_age,loser_age::float8 loser_age,winner_rank,loser_rank,
  w_svpt,w_1stwon,w_2ndwon,l_svpt,l_1stwon,l_2ndwon FROM tennis_results_2026""",rc); rc.close()
TR['tour']=TR.tour.astype(str).str.upper(); TR['rk']=TR['round'].map(RANK).fillna(4)
TR=TR.sort_values(['tourney_date','rk','match_num'],kind='stable')
print(f"results {len(TR)}, {TR.tourney_date.min()}..{TR.tourney_date.max()}; tours {TR.tour.value_counts().to_dict()}; best_of {TR.best_of.value_counts(dropna=False).to_dict()}; levels {TR.tourney_level.value_counts().head(12).to_dict()}; indoor {TR.indoor.value_counts(dropna=False).to_dict()}; hand {TR.winner_hand.value_counts(dropna=False).to_dict()}; rows with serve stats {int((TR.w_svpt.fillna(0)>0).sum())}",flush=True)
hist=defaultdict(lambda:deque(maxlen=WINDOW)); tm=defaultdict(lambda:[0.,0.]); ix=defaultdict(list); nw=0
for r in TR.itertuples():
    if walkover(r.score): nw+=1; continue
    w,l=fold(r.winner_norm),fold(r.loser_norm)
    M=None
    hw,hl=hist[w],hist[l]; tt=tm[r.tour]
    if len(hw)>=MINM and len(hl)>=MINM and tt[1]>=2000 and r.best_of in (3,5):
        ft=tt[0]/tt[1]; fw=np.mean([x[0] for x in hw]); gw=np.mean([x[1] for x in hw]); fl=np.mean([x[0] for x in hl]); gl=np.mean([x[1] for x in hl])
        fij,fji=serve_est(fw,gw,fl,gl,ft); M=match_prob(fij,fji,r.best_of)
    ix[frozenset((w,l))].append(dict(date=r.tourney_date,w=w,l=l,score=r.score,tour=r.tour,round=r.round,bo=r.best_of,lev=r.tourney_level,ind=r.indoor,hw=r.winner_hand,hl=r.loser_hand,aw=r.winner_age,al=r.loser_age,rw=r.winner_rank,rl=r.loser_rank,m_w=M))
    if pd.notna(r.w_svpt) and pd.notna(r.l_svpt) and r.w_svpt>=20 and r.l_svpt>=20:
        fw_=float(r.w_1stwon+r.w_2ndwon)/float(r.w_svpt); fl_=float(r.l_1stwon+r.l_2ndwon)/float(r.l_svpt)
        if 0<fw_<1 and 0<fl_<1:
            hist[w].append((fw_,1-fl_)); hist[l].append((fl_,1-fw_)); tt[0]+=fw_+fl_; tt[1]+=2
_m=np.array([h['m_w'] for v_ in ix.values() for h in v_ if h['m_w'] is not None and pd.Timestamp(h['date']).year>=2024],dtype=float)
print(f"model skill, no prices, 2024 on: n {len(_m)}, picks the winner {(_m>0.5).mean():.3f}, Brier {((1-_m)**2).mean():.4f} v 0.25 for a coin, mean abs distance from 0.5 {np.abs(_m-.5).mean():.3f}",flush=True)
print(f"walkovers out {nw}; tour serve means { {k:round(v[0]/v[1],3) for k,v in tm.items() if v[1]>0} } | {time.time()-T0:.0f}s",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SELECT DISTINCT market_id FROM bf_hist_other WHERE sport='Tennis' AND market_type='MATCH_ODDS'")
MID=sorted(r[0] for r in cur.fetchall() if r[0].startswith('MATCH_ODDS|') and '/' not in r[0]); print(f"singles markets {len(MID)} | {time.time()-T0:.0f}s",flush=True)
SK=Counter(); rows=[]; seen=set()
def emit(item,state,cut,k,won,e,tour,day,mk,ret):
    for side in 'BL':
        v=value(side,e,won)
        if v is None: SK['no bet at the ladder ends']+=1; continue
        rows.append((item,state,cut,side,tour,day,mk,ret,won,e[0],v))
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
        hits=[h for h in ix.get(pair,[]) if -2<=(day-h['date']).days<=21]
        if len(hits)!=1: SK['no unique results match or walkover']+=1; continue
        h=hits[0]; hd=h['date']
        if (pair,hd) in seen: SK['second market on one result row, skipped']+=1; continue
        seen.add((pair,hd)); SK['matched']+=1
        w,l=h['w'],h['l']; ew=entry(run[names[w]].ts.values,run[names[w]].ltp.values,mt); el=entry(run[names[l]].ts.values,run[names[l]].ltp.values,mt)
        if ew is None or el is None: SK['no entry print on both']+=1; continue
        SK['scored']+=1; ret=retired(h['score']); T=h['tour']
        args=lambda k: (k,k==w,ew if k==w else el,T,day,mk,ret)
        pw,pl=ew[0],el[0]
        # item 215
        if pw!=pl:
            fav=w if pw<pl else l; pf=min(pw,pl); b=fav_band(pf)
            if b:
                if T=='ATP' and h['bo'] in (3,5): emit(215,'BO5' if h['bo']==5 else 'ATP_BO3',b,*args(fav))
                if T=='WTA': emit(215,'WSLAM' if h['lev']=='G' else 'WTA_OTHER',b,*args(fav))
                if h['ind'] in ('I','O'): emit(215,'INDOOR' if h['ind']=='I' else 'OUTDOOR',b,*args(fav))
                rn=ROUND.get(h['round'])
                emit(215,rn if rn else 'OTHER_ROUND',b,*args(fav))
        hw,hl=h['hw'],h['hl']
        if hw in ('L','R') and hl in ('L','R') and hw!=hl:
            k=w if hw=='L' else l; p=pw if k==w else pl; emit(215,'LEFTY','<2' if p<2 else '>=2',*args(k))
        y=young(h['aw'],h['al'])
        if y:
            k=w if y=='a' else l; p=pw if k==w else pl; emit(215,'YOUNG','<2' if p<2 else '>=2',*args(k))
        rw,rl=h['rw'],h['rl']
        if pd.notna(rw) and pd.notna(rl) and rw!=rl:
            k=w if rw<rl else l; p=pw if k==w else pl
            if p>2.0: emit(215,'RANKDOG','>2',*args(k))
        # item 216: one line per threshold; model known before the match, prints for the edge only
        if h['m_w'] is not None:
            imp_w=(1/pw)/(1/pw+1/pl); ed=h['m_w']-imp_w
            up,dn=(w,l) if ed>0 else (l,w)
            for X in (0.05,0.08,0.12):
                if abs(ed)>=X:
                    for c in ('ALL',T):
                        if c=='ALL' or T in ('ATP','WTA','CHALLENGER'):
                            k_,won_,e_,*_=args(up); v=value('B',e_,won_)
                            if v is not None: rows.append((216,f'EDGE{X}',c,'BACK_UP',T,day,mk,ret,won_,e_[0],v))
                            k_,won_,e_,*_=args(dn); v=value('L',e_,won_); rows.append((216,f'EDGE{X}',c,'LAY_DN',T,day,mk,ret,won_,e_[0],v)) if v is not None else None
    print(f"  {min(c_+800,len(MID))}/{len(MID)}, rows {len(rows)} | {time.time()-T0:.0f}s",flush=True)
con.close(); print("counts:",dict(sorted(SK.items())),flush=True)
R=pd.DataFrame(rows,columns='item state cut side tour day m ret won px v'.split())
if R.empty: print("ERROR: no entries, no verdict"); sys.exit(1)
assert not R.duplicated(['item','state','cut','side','m']).any(),"more than one bet per match per line"
R['when']=pd.to_datetime(R.day).astype('int64'); print(f"dates {R.day.min()}..{R.day.max()}; markets {R.m.nunique()}",flush=True)
def tab(x,**k):
    md=np.median(x.when.values); l=line(x.v.values,np.where(x.when.values<md,1,2)); xr=x[~x.ret].v
    return dict(**k,n=l['n'],per10=l['per10'],t=l['t'],h1=l['h1'],h2=l['h2'],n1=l['n1'],n2=l['n2'],x_ret=xr.mean() if len(xr) else np.nan,won=x.won.mean(),implied=(1/x.px).mean(),maxwin=l['maxwin'],PASS=bool(l['PASS'] and len(xr)>0 and xr.mean()>=0.15))
CTRL={'ATP_BO3','WTA_OTHER','OUTDOOR','OTHER_ROUND'}
out=[tab(x,item=k[0],state=k[1],cut=k[2],side=k[3]) for k,x in R.groupby(['item','state','cut','side'])]
S=pd.DataFrame(out).sort_values('t',ascending=False); S['ctrl']=S.state.isin(CTRL)
A=S[(S.item==215)&~S.ctrl]; B=S[(S.item==216)]; C=S[S.ctrl]
print(f"\n== ITEM 215, {len(A)} lines, by t\n",A.round(3).to_string(index=False))
print(f"\n-- controls, cannot pass\n",C.round(3).to_string(index=False))
print(f"\n== ITEM 216, {len(B)} lines, by t\n",B.round(3).to_string(index=False))
W=S[S.PASS&~S.ctrl]; print(f"\n== SURVIVORS: {len(W)} of {len(A)+len(B)}\n",W.round(3).to_string(index=False) if len(W) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
