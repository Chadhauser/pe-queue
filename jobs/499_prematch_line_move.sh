#!/bin/bash
set -o pipefail
# 499_prematch_line_move (Finder 2026-11-04, queue item 64): does a pre-match line move continue or revert into the off? bf_hist_other Soccer, text market ids only (the 491 numeric ids are an earlier load of the same weeks). The number 499 is reused: 450-499 are all taken.
# NO LOOK-AHEAD: at signal time S (minutes before the off) the signal print is the last print in [S, S+30); the reference is the last print in [S+L, S+L+60). The fill is the first print after S, within 30 min and not in play. No print, no trade (counted). Nothing is forward-filled.
# EXIT: PRE = the last pre-off print after the fill; if there is none, the first in-play print after it; if none, -10 on both sides, counted. RES = held to the result, from the real final score in goal_timeline by exact team-name match. The first version inferred results from a final print <= 1.05: jobs/499_line_move_result_check.sh shows that rule fires on 86.6% of Under wins v 5.1% of Over wins, and 74.9% of draws v 93.9% of other results, so it was dropped. Markets with no score match are left out of RES only; the match does not depend on the result, but it does lean to the leagues the feed covers.
# COST: k ticks adverse at entry and at a PRE exit, k=1 by rule, k=3 reported; 2% commission on profit; back stake 10, lay liability 10.
# CELLS: market x S x L x threshold x SHORT/DRIFT x back/lay x exit x price band; one entry per market per cell, largest move kept; control = same S, L, band, side with |move| < 1%. Halves by median market date. All one season, about 3 months.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,unicodedata,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|club|de|the|cd|ud|sd|rcd|calcio|ii|b|if|bk|ff|aif|sk|fsv)\b"," ",s)
    return frozenset(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def true_winner(mk,ev,hs,as_):
    h,_,a=ev.partition(' v ')
    if mk=='OU25': return 'Over 2.5 Goals' if hs+as_>=3 else 'Under 2.5 Goals'
    return 'The Draw' if hs==as_ else (h.strip() if hs>as_ else a.strip())
assert true_winner('OU25','A v B',2,1)=='Over 2.5 Goals' and true_winner('OU25','A v B',1,1)=='Under 2.5 Goals'
assert true_winner('MO','Leeds v Hull',1,1)=='The Draw' and true_winner('MO','Leeds v Hull',2,0)=='Leeds' and true_winner('MO','Leeds v Hull',0,1)=='Hull'
pd.set_option('display.width',240); pd.set_option('display.max_rows',100); pd.set_option('display.max_columns',30)
T0=time.time()
LD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    v=lo
    while v<hi-1e-9: LD.append(round(v,2)); v+=st
LD.append(1000.0); LD=np.array(LD)
def ix(p): return int(np.searchsorted(LD,round(float(p),2)-1e-9))
def step(p,k): return float(LD[min(max(ix(p)+k,0),len(LD)-1)])
def net(x): return x*0.98 if x>0 else x
def back_green(p,q,k):
    a=step(p,-k)
    return np.nan if a<=1.01 else net(10*(a/step(q,k)-1))
def lay_green(p,q,k):
    a=step(p,k); b=step(q,-k)
    return np.nan if b<=1.0 else net(10/(a-1)*(1-a/b))
def back_res(p,won,k):
    a=step(p,-k)
    if a<=1.01: return np.nan
    if won is None: return -10.0
    return net(10*(a-1)) if won else -10.0
def lay_res(p,won,k):
    a=step(p,k)
    if won is None: return -10.0
    return -10.0 if won else net(10/(a-1))
def tstat(x):
    x=np.asarray(x,dtype=float); x=x[~np.isnan(x)]; s=x.std(ddof=1) if len(x)>1 else 0
    return x.mean()/(s/len(x)**0.5) if s>0 else 0.0
def signal(mins,px,inpl,S,L):
    # mins falling through time. Returns (move, fill index) or None; uses only prints at or before S for the move
    ref=None; sig=None; fill=None
    for i,(m,p,ip) in enumerate(zip(mins,px,inpl)):
        if ip: break
        if S+L<=m<S+L+60: ref=p
        elif S<=m<S+30: sig=p
        elif m<S:
            if m>=max(S-30,0) and ref is not None and sig is not None: fill=i
            break
    if ref is None or sig is None or fill is None: return None
    return float(np.log(sig/ref)),fill
def exit_idx(fill,inpl):
    n=len(inpl); j=fill+1
    if j>=n: return None
    if inpl[j]: return j
    while j+1<n and not inpl[j+1]: j+=1
    return j
# known answers, worked by hand
assert step(2.0,-1)==1.99 and step(3.0,1)==3.05 and step(1.99,1)==2.0
assert abs(back_green(3.0,2.5,1)-10*(2.98/2.52-1)*0.98)<1e-9                # back 2.98, lay 2.52: 10*(0.18254)=1.8254, less 2%
assert back_green(2.0,2.0,0)==0.0 and back_green(2.0,2.2,1)<0 and np.isnan(back_green(1.02,1.5,1))
assert abs(lay_green(2.5,3.0,1)-(10/1.52)*(1-2.52/2.98)*0.98)<1e-9          # lay 2.52, back 2.98: stake 6.579, x 0.15436, less 2%
assert lay_green(2.0,1.8,1)<0
assert abs(back_res(3.0,True,1)-19.404)<1e-9 and back_res(3.0,False,1)==-10.0 and back_res(3.0,None,1)==-10.0
assert abs(lay_res(3.0,False,1)-10/2.05*0.98)<1e-9 and lay_res(3.0,True,1)==-10.0 and lay_res(3.0,None,1)==-10.0
# signal: ref at 130 (in 120-180 for S60,L60), sig at 70 (in 60-90), fill at 50
assert abs(signal([130,70,50,3],[2.0,1.8,1.7,1.6],[0,0,0,0],60,60)[0]-np.log(0.9))<1e-9 and signal([130,70,50,3],[2.0,1.8,1.7,1.6],[0,0,0,0],60,60)[1]==2
assert signal([130,50,3],[2,1.7,1.6],[0,0,0],60,60) is None          # no signal print
assert signal([70,50],[1.8,1.7],[0,0],60,60) is None                 # no reference
assert signal([130,70,20],[2,1.8,1.7],[0,0,0],60,60) is None         # next print too late, no forward fill
assert signal([130,70,50],[2,1.8,1.7],[0,0,1],60,60) is None         # in play first
assert exit_idx(1,[0,0,0,0,1,1])==3 and exit_idx(3,[0,0,0,0,1,1])==4 and exit_idx(5,[0,0,0,0,1,1]) is None
print("checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'"); cur.execute("SET statement_timeout='2400s'")
def scan(lo,hi):
    cur.execute("""WITH RECURSIVE t AS ((SELECT market_id FROM bf_hist_other WHERE sport='Soccer' AND market_id>=%s AND market_id<%s ORDER BY market_id LIMIT 1)
     UNION ALL SELECT (SELECT market_id FROM bf_hist_other WHERE sport='Soccer' AND market_id>t.market_id AND market_id<%s ORDER BY market_id LIMIT 1) FROM t WHERE t.market_id IS NOT NULL) SELECT market_id FROM t WHERE market_id IS NOT NULL""",(lo,hi,hi))
    return [r[0] for r in cur.fetchall()]
GT=pd.read_sql("""SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,captured_at,minute,score_home,score_away,status FROM goal_timeline WHERE captured_at>='2026-06-30' AND captured_at<'2026-10-02' AND score_home IS NOT NULL ORDER BY fixture_id,captured_at DESC""",con)
GT['t']=pd.to_datetime(GT.captured_at,utc=True); GT['mn']=pd.to_numeric(GT.minute,errors='coerce')
GT=GT[GT.status.isin(['FT','AET','PEN','Match Finished','FINISHED'])|(GT.mn>=88)].copy()
SC={}
for r in GT.itertuples(): SC.setdefault((norm(r.home_team),norm(r.away_team)),[]).append((r.t,int(r.score_home),int(r.score_away)))
print(f"goal_timeline finished fixtures {len(GT)}, {time.time()-T0:.0f}s",flush=True)
def score_of(ev,mt):
    h,_,a=ev.partition(' v '); hits=[x for x in SC.get((norm(h),norm(a)),[]) if 0<=(x[0]-mt).total_seconds()/60<=240]
    return hits[0][1:] if len(hits)==1 else None
SL=[(180,60),(180,180),(60,60),(60,180),(15,60),(15,180)]; KS=(1,3); out=[]; seen=0; stats=dict(mk=0,known=0,noexit=0,winner_missing=0,wins=dict(),n=dict())
for MK,lo,hi in (('MO','MATCH_ODDS','MATCH_ODDT'),('OU25','OVER_UNDER_25','OVER_UNDER_26')):  # the collation ignores punctuation, so a '|~' upper bound sorts before the team names and finds nothing
    ids=[i for i in scan(lo,hi) if '|' in i]; print(f"{MK}: {len(ids)} markets {time.time()-T0:.0f}s",flush=True)
    if len(ids)<1000: sys.exit(f"{MK}: only {len(ids)} markets, census found over 12,000; stopping")
    for c in range(0,len(ids),400):
        P=pd.read_sql("SELECT market_id,event_name,market_time,sel,ts,ltp::float ltp,inplay FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND ltp>=1.01",con,params=(ids[c:c+400],))
        if not len(P): continue
        P['mt']=pd.to_datetime(P.market_time,utc=True); P['t']=pd.to_datetime(P.ts,utc=True); P['mins']=(P.mt-P.t).dt.total_seconds()/60; P=P.sort_values(['market_id','sel','t'])
        for mid,G in P.groupby('market_id',sort=False):
            stats['mk']+=1; runners={}
            for sel,g in G.groupby('sel',sort=False):
                runners[sel]=(g.mins.values,g.ltp.values,g.inplay.values.astype(bool))
            d=G.mt.iloc[0]; ev=G.event_name.iloc[0]; sc=score_of(ev,d); tw=true_winner(MK,ev,*sc) if sc else None
            h_,_,a_=ev.partition(' v ')
            if tw is not None and (tw not in runners or (MK=='MO' and not set(runners)<={h_.strip(),a_.strip(),'The Draw'})): stats['winner_missing']+=1; tw=None   # a runner whose name differs from the event name cannot be settled, whichever way the game went; testing only the winner would keep it when it lost and drop it when it won
            known=tw is not None; stats['known']+=known
            for sel,(m,p,ip) in runners.items():
                won=(sel==tw) if known else None
                for S,L in SL:
                    r=signal(m,p,ip,S,L)
                    if r is None: continue
                    mv,f=r; pe=p[f]
                    if not (1.1<=pe<=50): continue
                    e=exit_idx(f,ip); rec=dict(mk=MK,mid=mid,sel=sel,S=S,L=L,mv=mv,p=pe,d=d,known=known)
                    for k in KS:
                        rec[f'br{k}']=back_res(pe,won,k) if known else np.nan; rec[f'lr{k}']=lay_res(pe,won,k) if known else np.nan
                        rec[f'bp{k}']=back_green(pe,p[e],k) if e is not None else -10.0
                        rec[f'lp{k}']=lay_green(pe,p[e],k) if e is not None else -10.0
                    stats['noexit']+=e is None
                    rec['q']=p[e] if e is not None else np.nan; rec['won']=won if known else np.nan
                    out.append(rec)
        print(f"  {MK} {min(c+400,len(ids))}/{len(ids)} entries {len(out)} {time.time()-T0:.0f}s",flush=True)
con.close()
R=pd.DataFrame(out); print(f"markets {stats['mk']}, score matched {stats['known']/max(1,stats['mk']):.3f}, score matched but runner name not found {stats['winner_missing']}; candidate entries {len(R)}, entries with no exit print (-10 on PRE) {stats['noexit']}; {time.time()-T0:.0f}s",flush=True)
R['band']=pd.cut(R.p,[1,2,3,5,10,51],labels=['<=2','2-3','3-5','5-10','10+']).astype(str)
med=R.d.median(); R['h']=np.where(R.d<=med,1,2); print(f"dates {R.d.min():%Y-%m-%d} to {R.d.max():%Y-%m-%d}, median {med:%Y-%m-%d}")
print("\n== move size: share of candidates by |move|"); print(R.groupby(['mk','S']).mv.agg(n='size',abs_ge3=lambda s:(s.abs()>=.03).mean(),abs_ge5=lambda s:(s.abs()>=.05).mean(),abs_ge10=lambda s:(s.abs()>=.10).mean()).round(3).to_string())
print("\n== calibration on the fill print against real scores: GATE, won must sit near implied or the results are wrong")
K=R[(R.known)&(R.S==15)&(R.L==60)].copy(); K['imp']=1/K.p; K['won']=K.won.astype(float)
print(K.groupby(['mk','band']).agg(n=('p','size'),implied=('imp','mean'),won=('won','mean')).round(3).to_string())
print(K.groupby('mk').agg(n=('p','size'),implied=('imp','mean'),won=('won','mean')).round(3).to_string())
def cell(x,col):
    v=x[col].dropna(); a=x[x.h==1][col].dropna(); b=x[x.h==2][col].dropna()
    return dict(n=len(v),per10=v.mean() if len(v) else np.nan,t=tstat(v),h1=a.mean() if len(a) else np.nan,n1=len(a),h2=b.mean() if len(b) else np.nan,n2=len(b))
rows=[]
for (mk,S,L),X in R.groupby(['mk','S','L']):
    ctl=X[X.mv.abs()<0.01]
    for th in (.03,.05,.10):
        for dr,Y in (('SHORT',X[X.mv<=-th]),('DRIFT',X[X.mv>=th])):
            Y=Y.reindex(Y.mv.abs().sort_values(ascending=False).index)
            for bd in ('all','<=2','2-3','3-5','5-10','10+'):
                Z=Y if bd=='all' else Y[Y.band==bd]; Z=Z.drop_duplicates('mid'); C=ctl if bd=='all' else ctl[ctl.band==bd]; C=C.drop_duplicates('mid')
                if len(Z)<30: continue
                for side,sc in (('BACK','b'),('LAY','l')):
                    for ex,ec in (('PRE','p'),('RES','r')):
                        col=f'{sc}{ec}1'; d=cell(Z,col); cc=C[col].dropna()
                        d.update(mk=mk,S=S,L=L,th=th,dir=dr,band=bd,side=side,exit=ex,ctl=cc.mean() if len(cc) else np.nan,ctl_n=len(cc),x3=Z[f'{sc}{ec}3'].dropna().mean(),follow=(dr=='SHORT')==(side=='BACK'))
                        rows.append(d)
C=pd.DataFrame(rows)
C['PASS']=(C.n>=300)&(C.n1>=150)&(C.n2>=150)&(C.t>=3.5)&(C.h1>0)&(C.h2>0)&(C.per10>=0.15)
show=['mk','S','L','th','dir','band','side','exit','follow','n','per10','t','h1','h2','ctl','x3','PASS']
print(f"\n== {len(C)} cells, {int((C.n>=300).sum())} at n>=300, {int(C.PASS.sum())} numeric passes; a Bonferroni t on all cells is about {abs(__import__('scipy.stats',fromlist=['norm']).norm.ppf(0.025/len(C))):.2f}")
print("\n== base lines, all prices, threshold 5%, T-60, L 60"); print(C[(C.S==60)&(C.L==60)&(C.th==.05)&(C.band=='all')][show].round(3).to_string(index=False))
print("\n== top 15 by t at n>=300"); print(C[C.n>=300].sort_values('t',ascending=False).head(15)[show].round(3).to_string(index=False))
print("\n== top 15 by t at n>=300, PRE exits only, no result used"); print(C[(C.n>=300)&(C.exit=='PRE')].sort_values('t',ascending=False).head(15)[show].round(3).to_string(index=False))
print("\n== top 15 by t at n>=300, RES exits only, real scores"); print(C[(C.n>=300)&(C.exit=='RES')].sort_values('t',ascending=False).head(15)[show].round(3).to_string(index=False))
print("\n== mean log(exit print / fill print), all prices, by threshold: + means the price lengthened after the fill, so short + is reversion and drift + is continuation")
Q=R[R.q.notna()].copy(); Q['later']=np.log(Q.q/Q.p)
for th in (.03,.05,.10):
    print(f"  th {th}: "+" | ".join(f"{mk} T-{S}: short {Q[(Q.mk==mk)&(Q.S==S)&(Q.mv<=-th)].later.mean():+.4f} drift {Q[(Q.mk==mk)&(Q.S==S)&(Q.mv>=th)].later.mean():+.4f} flat {Q[(Q.mk==mk)&(Q.S==S)&(Q.mv.abs()<.01)].later.mean():+.4f}" for mk in ('MO','OU25') for S in (180,60,15)))
print("\n== SURVIVORS")
S_=C[C.PASS].sort_values('t',ascending=False)
print(S_[show].round(3).to_string(index=False) if len(S_) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
