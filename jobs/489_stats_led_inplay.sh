#!/bin/bash
set -o pipefail
# 489_stats_led (Finder 2026-11-04, queue item 49, "what the shots actually predict"). 450-499 is full, so the number is shared, as 472, 478, 487, 488 are; the runner keys on the whole name.
# FIT goal_stats_live rows before liq_sample begins (3 Oct onwards); no prices needed. SCORE only rows from liq_sample's first ts on, so the two never overlap. The item said first half v second half of the range; this keeps the fit clean and larger.
# FEATURES at a stats row, look-back only: minute, score, SOT, shots, shots in box ("home_da"), corners, possession, per side and summed, rises over 5 and 10 min (earlier row at most 3 min older than the target time), minutes since the last goal. Pre-match price is NOT a feature: the recorder holds no price for the fit window.
# TARGETS P10 = feed total at t+10 min above total at t; PFT = final total above total at t. Models: logistic regression and small GBM, both reported.
# MARKET next Over line (total 1: OU15, 2: OU25, 3: OU35). OU05 is not recorded, so 0-0 and total >= 4 are not traded (counted). Implied p(goal by FT) = 1/mid. P10 implied = 1-(1-p)^(min(10,rem)/rem), rem = max(95-minute,3); this assumes a flat goal rate, which is crude.
# TRADE back Over if model - market >= 10/15/20 points, lay Over if <= -that. Entry = first sample at or after the row, within 90 s, one tick adverse, £10 risk, 2% commission, one entry per fixture per line per 15 min. Rows whose stats score disagrees with the timeline at entry are skipped and counted.
# EXITS P10 = first sample at or after +10 min at the other touch, one tick adverse; SETTLE. The next goal passes the next line, so "next goal +8" would equal SETTLE and is not run. A line passed before the exit, or no later sample, settles at the result. Unknown result = -£10 on both sides, and known-only is shown.
# Halves by median entry time in the scoring window. tc = t on per-fixture means. FIRST = first qualifying entry per fixture.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,time,unicodedata,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
from sklearn.ensemble import HistGradientBoostingClassifier as HGC
from sklearn.linear_model import LogisticRegression
from sklearn.impute import SimpleImputer
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import make_pipeline
from sklearn.metrics import roc_auc_score,brier_score_loss
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',240); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',30)
T0=time.time()
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LADA=np.array(LAD)
def ti(p): return int(np.searchsorted(LADA,round(p,2)-1e-9))
def dn(p): return float(LADA[max(ti(p)-1,0)])
def up(p): return float(LADA[min(ti(p)+1,len(LADA)-1)])
def cm(r): return r*0.98 if r>0 else r
def back(bp,lp_exit,won):
    a=dn(bp)
    if a<=1.01: return None
    return cm((10*(a-1) if won else -10.0) if lp_exit is None else 10*(a/up(lp_exit)-1))
def lay(lp,bp_exit,won):
    a=up(lp); s=10/(a-1)
    return cm((-10.0 if won else s) if bp_exit is None else s*(1-a/dn(bp_exit)))
def line_for(total): return {1:'OU15',2:'OU25',3:'OU35'}.get(total)
def over_won(mkt,total): return total>{'OU15':1.5,'OU25':2.5,'OU35':3.5}[mkt]
def p10_mkt(p,minute):
    rem=np.maximum(95-minute,3.0); return 1-(1-p)**(np.minimum(10.0,rem)/rem)
def passes(n,n1,n2,t,h1,h2,m): return bool(n>=300 and n1>=150 and n2>=150 and t>=3.5 and h1>0 and h2>0 and m>=0.15)
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|club|de|the|athletic|atletico|sporting|real|cd|ud|sd|rcd|calcio|women|w|u21|u23|ii|b|if|bk|ff|aif|is|kv|sk|fsv)\b"," ",s)
    return set(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def sim(A,B): return len(A&B)/max(1,len(A|B))
def tstat(x):
    x=np.asarray(x,dtype=float); s=x.std(ddof=1) if len(x)>1 else 0
    return x.mean()/(s/len(x)**0.5) if s>0 else 0.0
# known answers, by hand. Back 3.0 -> 2.98: wins 19.8 less 2% = 19.404, loses -10; out at lay 2.5 -> 2.52: 10*(2.98/2.52-1)=1.825397, less 2% = 1.788889; flat book 2.00/2.02: 1.99/2.04 = -0.245098; 1.02 fills at 1.01, no trade.
assert abs(back(3.0,None,True)-19.404)<1e-9 and back(3.0,None,False)==-10.0 and abs(back(3.0,2.5,None)-1.788889)<1e-5 and abs(back(2.0,2.02,None)+0.245098)<1e-5 and back(1.02,None,True) is None
# Lay 2.5 -> 2.52, stake 10/1.52=6.578947: not won +6.447368, won -10; out at back 3.0 -> 2.98: 6.578947*(1-2.52/2.98)=1.015542, less 2% = 0.995231; drift against, out at back 2.2 -> 2.18: 6.578947*(1-2.52/2.18)=-1.026, no commission.
assert abs(lay(2.5,None,False)-6.447368)<1e-5 and lay(2.5,None,True)==-10.0 and abs(lay(2.5,3.0,None)-0.995231)<1e-5 and abs(lay(2.5,2.2,None)+1.026072)<1e-5
# Implied: p .5 with 10 min left = .5; with 20 left = 1-.5^.5 = .292893; at or past 92' rem floors at 3 and the exponent at 1, so p itself.
assert abs(p10_mkt(0.5,85)-0.5)<1e-9 and abs(p10_mkt(0.5,75)-0.292893)<1e-5 and abs(p10_mkt(0.5,93)-0.5)<1e-9
assert line_for(0) is None and line_for(1)=='OU15' and line_for(3)=='OU35' and line_for(4) is None and over_won('OU15',2) and not over_won('OU15',1) and not over_won('OU35',3)
assert passes(300,150,150,3.5,.01,.01,.15) and not passes(299,150,150,9,1,1,1) and not passes(300,149,151,9,1,1,1) and not passes(300,150,150,3.49,1,1,1) and not passes(300,150,150,9,0,1,1) and not passes(300,150,150,9,1,-1,1) and not passes(300,150,150,9,1,1,.149)
print("P&L, implied, line and pass-rule checks: OK",flush=True)

con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'"); cur.execute("SET statement_timeout='2400s'")
cur.execute("SELECT min(ts),max(ts) FROM liq_sample"); L0,L1=cur.fetchone(); print("liq_sample",L0,"..",L1,flush=True)
S=pd.read_sql("""SELECT fixture_id, league_id, captured_at, minute, score_home, score_away, home_sot, away_sot, home_shots, away_shots, home_da, away_da, home_corners, away_corners, home_poss, away_poss FROM goal_stats_live ORDER BY fixture_id, captured_at""",con)
S0=S.captured_at.min()
T=pd.read_sql("""SELECT fixture_id, captured_at, home_team, away_team, minute, score_home, score_away, status FROM goal_timeline WHERE captured_at>=%s AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id, captured_at""",con,params=(S0-pd.Timedelta(hours=3),))
print(f"stats rows {len(S)}, fixtures {S.fixture_id.nunique()}, {S0} .. {S.captured_at.max()}; timeline rows {len(T)}, fixtures {T.fixture_id.nunique()}, {time.time()-T0:.0f}s",flush=True)
parts=[]
for a in pd.date_range(pd.Timestamp(L0).floor('D'),pd.Timestamp(L1),freq='1D'):
    parts.append(pd.read_sql("""SELECT ts, event_name, mkt, sel, back_px::float bp, lay_px::float lp FROM liq_sample WHERE ts>=%s AND ts<%s AND mkt IN ('OU15','OU25','OU35') AND upper(sel) LIKE 'OVER%%' AND event_name LIKE '%% v %%' AND back_px>1 AND lay_px>back_px""",con,params=(a,a+pd.Timedelta(days=1))))
    print(f"liq {a.date()}: {len(parts[-1])} rows, {time.time()-T0:.0f}s",flush=True)
con.close()
L=pd.concat(parts,ignore_index=True); del parts; print(f"liq rows {len(L)}, games {L.event_name.nunique()}, markets {L.mkt.value_counts().to_dict()}",flush=True)
def naive(c): return pd.to_datetime(c,utc=True).dt.tz_localize(None)
S['t']=naive(S.captured_at); T['t']=naive(T.captured_at); L['day']=pd.to_datetime(L.ts,utc=True).dt.tz_convert('Europe/London').dt.date; L['t']=naive(L.ts)
CUT=pd.Timestamp(L0).tz_convert('UTC').tz_localize(None)
SK=defaultdict(int)
fx={}
for fid,g in T.groupby('fixture_id'):
    tot=(g.score_home.astype(int)+g.score_away.astype(int)).values; last=g.minute.iloc[-1]; st=str(g.status.iloc[-1])
    fx[fid]=dict(H=norm(g.home_team.iloc[0]),A=norm(g.away_team.iloc[0]),ts=g.t.values,tot=tot,ft=int(tot[-1]),t0=g.t.iloc[0],t1=g.t.iloc[-1],known=st in ('FT','AET','PEN','Match Finished','FINISHED') or (pd.notna(last) and last>=88))
# features, look-back only
S=S[S.fixture_id.isin(fx)&S.minute.notna()].sort_values(['t','fixture_id']).reset_index(drop=True)
print(f"stats rows with a timeline {len(S)}, fixtures {S.fixture_id.nunique()}, known results {np.mean([fx[f]['known'] for f in S.fixture_id.unique()]):.1%}",flush=True)
BASE=['sot','shots','da','corners']
for c in BASE: S['sum_'+c]=S['home_'+c]+S['away_'+c]
S['tot']=S.score_home.fillna(0).astype(int)+S.score_away.fillna(0).astype(int); S['gd']=(S.score_home.fillna(0)-S.score_away.fillna(0)).astype(int); S['poss_d']=S.home_poss-S.away_poss
DC=[f'{p}_{c}' for p in ('home','away','sum') for c in BASE]
for W in (5,10):
    q=S[['fixture_id','t']+DC].sort_values('t').rename(columns={c:c+'_o' for c in DC}); q['t_o']=q.t
    q=q.drop(columns='t')
    l=S[['fixture_id','t']].copy(); l['key']=l.t-pd.Timedelta(minutes=W); l['_i']=l.index
    m=pd.merge_asof(l.sort_values('key'),q,left_on='key',right_on='t_o',by='fixture_id',direction='backward',tolerance=pd.Timedelta(minutes=3)).set_index('_i').sort_index()
    assert (m.t_o.dropna()<S.t.loc[m.t_o.dropna().index]).all()
    for c in DC: S[f'{c}_d{W}']=S[c]-m[c+'_o']
def since_goal(r):
    f=fx[r.fixture_id]; j=int(np.searchsorted(f['ts'],np.datetime64(r.t),side='right'))
    if j==0: return np.nan,np.nan
    tt=f['tot'][j-1]; rise=np.flatnonzero(f['tot'][:j]==tt)[0]
    return (np.datetime64(r.t)-f['ts'][rise])/np.timedelta64(60,'s') if tt>0 else r.minute, tt
sg=[since_goal(r) for r in S.itertuples()]
S['since_goal']=[a for a,_ in sg]; S['tl_tot']=[b for _,b in sg]
def after(r,sec):
    f=fx[r.fixture_id]; tgt=np.datetime64(r.t)+np.timedelta64(sec,'s')
    if tgt>f['ts'][-1] and not f['known']: return np.nan
    j=int(np.searchsorted(f['ts'],tgt,side='right')); return f['tot'][j-1] if j>0 else np.nan
S['tot10']=[after(r,600) for r in S.itertuples()]
S['y10']=np.where(S.tot10.notna()&S.tl_tot.notna(),(S.tot10>S.tl_tot).astype(float),np.nan)
S['ft']=[fx[f]['ft'] if fx[f]['known'] else np.nan for f in S.fixture_id]
S['yft']=np.where(S.ft.notna()&S.tl_tot.notna(),(S.ft>S.tl_tot).astype(float),np.nan)
X=['minute','tot','gd','home_poss','poss_d','since_goal']+DC+[f'{c}_d{W}' for c in DC for W in (5,10)]
FIT=S[S.t<CUT]; HO=S[S.t>=CUT].copy()
assert FIT.t.max()<HO.t.min()
print(f"fit rows {len(FIT)}, fixtures {FIT.fixture_id.nunique()}, {FIT.t.min()} .. {FIT.t.max()} | scoring rows {len(HO)}, fixtures {HO.fixture_id.nunique()}, {HO.t.min()} .. {HO.t.max()}",flush=True)
print(f"goal in next 10 min: fit {FIT.y10.mean():.4f} n {int(FIT.y10.notna().sum())}, scoring {HO.y10.mean():.4f} n {int(HO.y10.notna().sum())}; goal by FT: fit {FIT.yft.mean():.4f}, scoring {HO.yft.mean():.4f}",flush=True)
MOD={'LR':lambda:make_pipeline(SimpleImputer(strategy='median'),StandardScaler(),LogisticRegression(C=0.1,max_iter=2000)),
     'GBM':lambda:HGC(learning_rate=0.03,max_iter=150,max_leaf_nodes=6,min_samples_leaf=100,l2_regularization=5.0,early_stopping=False,random_state=49)}
for tg in ('y10','yft'):
    F=FIT[FIT[tg].notna()]
    for mn,mk in MOD.items():
        mdl=mk().fit(F[X],F[tg].astype(int)); HO[f'p_{mn}_{tg}']=mdl.predict_proba(HO[X])[:,1]
        F_p=mdl.predict_proba(F[X])[:,1]; h=HO[HO[tg].notna()]
        print(f"{mn} {tg}: fit AUC {roc_auc_score(F[tg],F_p):.3f}, hold-out AUC {roc_auc_score(h[tg],h[f'p_{mn}_{tg}']):.3f}, Brier {brier_score_loss(h[tg],h[f'p_{mn}_{tg}']):.4f} v base {brier_score_loss(h[tg],np.full(len(h),F[tg].mean())):.4f}",flush=True)
print("\n== what the stats predict, hold-out, goal in next 10 min, by decile of GBM p")
h=HO[HO.y10.notna()].copy(); h['d']=pd.qcut(h.p_GBM_y10,10,duplicates='drop',labels=False)
print(h.groupby('d').agg(n=('y10','size'),model=('p_GBM_y10','mean'),actual=('y10','mean'),fixtures=('fixture_id','nunique')).round(4).to_string())
# map fixtures to recorder games
gx=[]
for (ev,day),g in L.groupby(['event_name','day'],sort=False):
    h_,_,a_=ev.partition(' v '); gx.append(dict(H=norm(h_),A=norm(a_),t0=g.t.min(),t1=g.t.max(),g=g))
want=set(HO.fixture_id); mp={}
for e in gx:
    best=None; bs=0
    for fid in want:
        f=fx[fid]
        if f['t0']-pd.Timedelta(hours=1)<=e['t1'] and e['t0']<=f['t1']+pd.Timedelta(hours=1):
            s_=min(sim(e['H'],f['H']),sim(e['A'],f['A']))
            if s_>bs: bs,best=s_,fid
    if best is not None and bs>=0.3: mp[best]=e
print(f"\nscoring fixtures {len(want)}, mapped to recorder games {len(mp)}, {time.time()-T0:.0f}s",flush=True)
books={}
def book(fid,mkt):
    k=(fid,mkt)
    if k not in books:
        x=mp[fid]['g']; x=x[x.mkt==mkt].sort_values('t'); books[k]=(x.t.values,x.bp.values,x.lp.values)
    return books[k]
rows=[]
for r in HO.itertuples():
    if r.fixture_id not in mp: SK['fixture not mapped']+=1; continue
    if pd.isna(r.tl_tot) or int(r.tl_tot)!=int(r.tot): SK['stats score v timeline disagree']+=1; continue
    ml=line_for(int(r.tot))
    if ml is None: SK['total 0 or >= 4, no next line']+=1; continue
    ts,bp,lp=book(r.fixture_id,ml)
    if len(ts)==0: SK['no book']+=1; continue
    t=np.datetime64(r.t); i=int(np.searchsorted(ts,t))
    if i>=len(ts) or ts[i]-t>np.timedelta64(90,'s'): SK['no sample within 90 s']+=1; continue
    f=fx[r.fixture_id]; won=over_won(ml,f['ft']); e=ts[i]; b0,l0=float(bp[i]),float(lp[i])
    # the goal may land between the stats row and the entry sample: then the line is gone
    j0=int(np.searchsorted(f['ts'],e,side='right'))
    if j0>0 and over_won(ml,int(f['tot'][j0-1])): SK['line passed before entry']+=1; continue
    # P10 exit
    tgt=e+np.timedelta64(600,'s'); jj=int(np.searchsorted(f['ts'],tgt,side='right')); gone=jj>0 and over_won(ml,int(f['tot'][jj-1]))
    k=int(np.searchsorted(ts,tgt)); q_b=q_l=None
    if not gone and k<len(ts) and k>i: q_b,q_l=float(bp[k]),float(lp[k])
    pb=back(b0,q_l,won); pb_s=back(b0,None,won)
    if pb is None or pb_s is None: SK['back at 1.01']+=1; continue
    pmk=1/((b0+l0)/2)
    rows.append(dict(fid=r.fixture_id,t=r.t,ts=e,minute=r.minute,mkt=ml,px=b0,spread=l0/b0,known=f['known'],pmk=pmk,p10k=p10_mkt(pmk,float(r.minute)),
        BACK_P10=pb,BACK_SETTLE=pb_s,LAY_P10=lay(l0,q_b,won),LAY_SETTLE=lay(l0,None,won),exit_real=q_b is not None,
        **{c:getattr(r,c) for c in ('p_LR_y10','p_GBM_y10','p_LR_yft','p_GBM_yft','y10','yft')}))
R=pd.DataFrame(rows); print(f"priced rows {len(R)}, fixtures {R.fid.nunique() if len(R) else 0}, skips {dict(SK)}, P10 exit at a real sample {R.exit_real.mean():.1%}, {time.time()-T0:.0f}s",flush=True)
if R.empty: print("\n== SURVIVORS: 0\nnone (no priced rows)"); sys.exit()
R['ts_']=pd.to_datetime(R.ts); med=R.ts_.median(); R['h2']=R.ts_>=med
print(f"entry times {R.ts_.min()} .. {R.ts_.max()}, median {med}; mean spread (lay/back) {R.spread.mean():.3f}")
hr=R[R.y10.notna()]
print("\n== model v market on the priced rows")
for nm,c,y in (('market P10','p10k','y10'),('LR P10','p_LR_y10','y10'),('GBM P10','p_GBM_y10','y10'),('market FT','pmk','yft'),('LR FT','p_LR_yft','yft'),('GBM FT','p_GBM_yft','yft')):
    x=R[R[y].notna()]; print(f"{nm:11s} n {len(x)} mean p {x[c].mean():.4f} actual {x[y].mean():.4f} AUC {roc_auc_score(x[y],x[c]):.3f} Brier {brier_score_loss(x[y],x[c].clip(0,1)):.4f}")
def spaced(x):
    keep=[]
    for _,g in x.sort_values('ts_').groupby('fid'):
        last=None
        for i_,t_ in zip(g.index,g.ts_):
            if last is None or (t_-last).total_seconds()>=900: keep.append(i_); last=t_
    return x.loc[keep]
out=[]
def score(x,**k):
    if len(x)<10: return
    v=x[k['col']].where(x.known,-10.0); a=v[~x.h2]; b=v[x.h2]; per=pd.DataFrame(dict(f=x.fid,v=v)).groupby('f').v.mean()
    d=dict(k); d.pop('col')
    d.update(n=len(x),games=x.fid.nunique(),px=x.px.mean(),per10=v.mean(),known_only=x[x.known][k['col']].mean(),t=tstat(v),tc=tstat(per),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan)
    out.append(d)
for sh in ('BACK','LAY'):
    for ex in ('P10','SETTLE'):
        score(spaced(R),line='CONTROL',shape=sh,exit=ex,margin=0,sel='ALL',col=f'{sh}_{ex}')
for mn in MOD:
    for hz,c,mkc in (('P10',f'p_{mn}_y10','p10k'),('FT',f'p_{mn}_yft','pmk')):
        e_=R[c]-R[mkc]
        print(f"{mn} {hz}: model minus market, mean {e_.mean():+.4f}, p5 {e_.quantile(.05):+.4f}, p95 {e_.quantile(.95):+.4f}, rows >= +10 points {int((e_>=.10).sum())}, <= -10 points {int((e_<=-.10).sum())}")
        for sh in ('BACK','LAY'):
            for m_ in (0.10,0.15,0.20):
                s_=R[e_>=m_] if sh=='BACK' else R[e_<=-m_]
                if not len(s_): continue
                sp=spaced(s_); fi=s_.sort_values('ts_').groupby('fid').head(1)
                for ex in ('P10','SETTLE'):
                    score(sp,line=f'{mn}_{hz}',shape=sh,exit=ex,margin=m_,sel='ALL',col=f'{sh}_{ex}')
                    score(fi,line=f'{mn}_{hz}',shape=sh,exit=ex,margin=m_,sel='FIRST',col=f'{sh}_{ex}')
O=pd.DataFrame(out); O['PASS']=[l!='CONTROL' and passes(a,b,c,d,e,f,g) for l,a,b,c,d,e,f,g in zip(O.line,O.n,O.n1,O.n2,O.t,O.h1,O.h2,O.per10)]
print(f"\n== {int((O.line!='CONTROL').sum())} lines scored (unknown result = -£10)")
print("\n== CONTROLS: every priced row, spaced 15 min"); print(O[O.line=='CONTROL'].drop(columns=['line','margin','sel','PASS']).round(3).to_string(index=False))
print("\n== TOP 15 by t"); print(O[O.line!='CONTROL'].sort_values('t',ascending=False).head(15).round(3).to_string(index=False))
print("\n== TOP 10 one per fixture by t"); print(O[(O.line!='CONTROL')&(O.sel=='FIRST')].sort_values('t',ascending=False).head(10).round(3).to_string(index=False))
print(f"\nlargest line n {int(O[O.line!='CONTROL'].n.max())}; accrual about {len(spaced(R))/max((R.ts_.max()-R.ts_.min()).total_seconds()/86400,0.01):.0f} spaced priced rows a day")
W_=O[O.PASS].sort_values('t',ascending=False)
print(f"\n== SURVIVORS: {len(W_)}"); print(W_.round(3).to_string(index=False) if len(W_) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
