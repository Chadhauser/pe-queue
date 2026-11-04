#!/bin/bash
set -o pipefail
# 489_cross_market (Finder 2026-11-04, queue item 51): CROSS-MARKET RESIDUALS INSIDE A GAME. liq_sample x goal_timeline. 450-499 is full, so the number is shared. Item 0e's exact arbitrage generalised to relative value.
# CONSENSUS at a snapshot: from the score at that moment, two independent Poisson rates for remaining goals (home, away) on a 0.05 grid, fitted by least squares to overround-removed mids of every open market in MO, OU15, OU25, OU35, BTTS. Needs >= 3 markets; fits with RMSE > 0.06 skipped and counted. AH and CS are NOT used: the fit is on the five markets with one clean selection set. The line being traded is in its own fit, which shrinks its residual.
# SIGNAL back if model p - 1/back_px >= 3/5/10 points; lay if 1/lay_px - model p >= that, so the edge must survive the actual touch. Spread filter: lay/back <= 1.25 on the traded selection.
# ENTRY the same snapshot's touch, one tick adverse, £10 risk, 2% commission. One snapshot per game per 5 min; one entry per game x selection x line per 15 min; FIRST = first per game. Score from goal_timeline at or before the snapshot, so a goal the feed has not shown yet is a real risk here, and QUIET = no feed goal in the last 3 min.
# EXITS P10 first sample at or after +10 min at the other touch, one tick adverse; SETTLE. The next-goal +8 exit in the item is P10 with a goal inside, as a passed market settles at the result; it is not run apart. A market passed before the exit, or with no later sample, settles at the result. Unknown result (feed not reaching 88' or FT) = -£10. Games with a mislabelled MO are dropped, counted.
# Halves by median entry time. tc = per-game means. Prices 1.01-1.50 on lays pay many times liability, so results are shown by price band and without the top win.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,time,math,unicodedata,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
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
SEL=['MO_HOME','MO_DRAW','MO_AWAY','OU15_OVER','OU15_UNDER','OU25_OVER','OU25_UNDER','OU35_OVER','OU35_UNDER','BTTS_YES','BTTS_NO']
MKS={'MO':[0,1,2],'OU15':[3,4],'OU25':[5,6],'OU35':[7,8],'BTTS':[9,10]}
IDX={s:i for i,s in enumerate(SEL)}
def won_sel(s,h,a):
    m,x=s.split('_'); t=h+a
    if m=='MO': return (h>a) if x=='HOME' else (a>h) if x=='AWAY' else h==a
    if m=='BTTS': return (h>0 and a>0)==(x=='YES')
    return (t>{'OU15':1.5,'OU25':2.5,'OU35':3.5}[m])==(x=='OVER')
def decided(m,h,a):
    t=h+a
    return (m=='OU15' and t>1.5) or (m=='OU25' and t>2.5) or (m=='OU35' and t>3.5) or (m=='BTTS' and h>0 and a>0)
LG=np.arange(0,4.001,0.05); MAXG=10
_po=np.array([[math.exp(-l)*l**k/math.factorial(k) for k in range(MAXG)] for l in LG])
_po=_po/_po.sum(axis=1,keepdims=True)
_cache={}
def table(sh,sa):
    k=(sh,sa)
    if k not in _cache:
        out=np.zeros((len(SEL),len(LG),len(LG)))
        for i in range(MAXG):
            for j in range(MAXG):
                w=np.outer(_po[:,i],_po[:,j]); h,a=sh+i,sa+j
                for s,ix in IDX.items():
                    if won_sel(s,h,a): out[ix]+=w
        _cache[k]=out
    return _cache[k]
def fit(sh,sa,target):
    # target: {market: normalised p array in that market's order}
    T=table(sh,sa); sse=0; c=0
    for m,p in target.items():
        for ix,v in zip(MKS[m],p): sse=sse+(T[ix]-v)**2; c+=1
    i,j=np.unravel_index(np.argmin(sse),sse.shape)
    return i,j,math.sqrt(sse[i,j]/c),T[:,i,j]
def passes(n,n1,n2,t,h1,h2,m): return bool(n>=300 and n1>=150 and n2>=150 and t>=3.5 and h1>0 and h2>0 and m>=0.15)
def tstat(x):
    x=np.asarray(x,dtype=float); s=x.std(ddof=1) if len(x)>1 else 0
    return x.mean()/(s/len(x)**0.5) if s>0 else 0.0
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|club|de|the|athletic|atletico|sporting|real|cd|ud|sd|rcd|calcio|women|w|u21|u23|ii|b|if|bk|ff|aif|is|kv|sk|fsv)\b"," ",s)
    return set(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def sim(A,B): return len(A&B)/max(1,len(A|B))
# known answers by hand. Grid index for rate r = r/0.05.
ii=lambda r:int(round(r/0.05))
T00=table(0,0); T10=table(1,0)
assert abs(T00[IDX['OU25_OVER'],ii(1.25),ii(1.25)]-(1-math.exp(-2.5)*(1+2.5+3.125)))<1e-4    # P(total>=3), total rate 2.5 = .456187
assert abs(T00[IDX['MO_HOME'],ii(1.0),0]-(1-math.exp(-1)))<1e-4 and abs(T00[IDX['MO_DRAW'],ii(1.0),0]-math.exp(-1))<1e-4        # home rate 1, away 0: .632121, .367879
assert abs(T10[IDX['BTTS_YES'],0,ii(1.0)]-(1-math.exp(-1)))<1e-4                                                                  # 1-0, away rate 1: .632121
assert T10[IDX['MO_HOME'],0,0]==1.0 and T10[IDX['OU15_OVER'],0,0]==0.0                                                            # 1-0 no more goals
assert np.allclose(T00[0]+T00[1]+T00[2],1.0) and np.allclose(T00[5]+T00[6],1.0)
# the fit must recover known rates from prices built with them
_t=table(1,1); _p=_t[:,ii(1.2),ii(0.8)]
i_,j_,rm,pm=fit(1,1,{m:_p[ix] for m,ix in MKS.items()}); assert i_==ii(1.2) and j_==ii(0.8) and rm<1e-9
assert not decided('OU25',1,1) and decided('OU25',2,1) and decided('BTTS',1,1) and not decided('BTTS',1,0) and not decided('MO',5,0)
assert abs(back(3.0,None,True)-19.404)<1e-9 and back(3.0,None,False)==-10.0 and abs(back(3.0,2.5,None)-1.788889)<1e-5 and back(1.02,None,True) is None
assert abs(lay(2.5,None,False)-6.447368)<1e-5 and lay(2.5,None,True)==-10.0 and abs(lay(2.5,3.0,None)-0.995231)<1e-5
assert passes(300,150,150,3.5,.01,.01,.15) and not passes(299,150,150,9,1,1,1) and not passes(300,149,151,9,1,1,1) and not passes(300,150,150,3.49,1,1,1) and not passes(300,150,150,9,0,1,1) and not passes(300,150,150,9,1,0,1) and not passes(300,150,150,9,1,1,.149)
print("Poisson, fit recovery, settlement, P&L and pass-rule checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'"); cur.execute("SET statement_timeout='2400s'")
cur.execute("SELECT min(ts),max(ts) FROM liq_sample"); L0,L1=cur.fetchone(); print("liq_sample",L0,"..",L1,flush=True)
T=pd.read_sql("""SELECT fixture_id, captured_at, home_team, away_team, minute, score_home, score_away, status FROM goal_timeline WHERE captured_at>=%s AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id, captured_at""",con,params=(L0-pd.Timedelta(hours=3),))
parts=[]
for a in pd.date_range(pd.Timestamp(L0).floor('D'),pd.Timestamp(L1),freq='1D'):
    parts.append(pd.read_sql("""SELECT ts, event_name, mkt, sel, back_px::float bp, lay_px::float lp FROM liq_sample WHERE ts>=%s AND ts<%s AND mkt IN ('MO','OU15','OU25','OU35','BTTS') AND event_name LIKE '%% v %%' AND back_px>1 AND lay_px>back_px""",con,params=(a,a+pd.Timedelta(days=1))))
    print(f"liq {a.date()}: {len(parts[-1])} rows, {time.time()-T0:.0f}s",flush=True)
con.close()
L=pd.concat(parts,ignore_index=True); del parts
L['side']=L.sel.str.upper().str.split().str[0]; L['code']=L.mkt+'_'+L.side; L=L[L.code.isin(SEL)]
L['day']=pd.to_datetime(L.ts,utc=True).dt.tz_convert('Europe/London').dt.date; L['t']=pd.to_datetime(L.ts,utc=True).dt.tz_localize(None); T['t']=pd.to_datetime(T.captured_at,utc=True).dt.tz_localize(None)
print(f"liq rows {len(L)}, games {L.event_name.nunique()}, timeline fixtures {T.fixture_id.nunique()}",flush=True)
SK=defaultdict(int)
fx={}
for fid,g in T.groupby('fixture_id'):
    h=g.score_home.astype(int).values; a=g.score_away.astype(int).values; last=g.minute.iloc[-1]; st=str(g.status.iloc[-1])
    fx[fid]=dict(H=norm(g.home_team.iloc[0]),A=norm(g.away_team.iloc[0]),ts=g.t.values,h=h,a=a,mn=pd.to_numeric(g.minute,errors='coerce').values,st=g.status.astype(str).values,fh=int(h[-1]),fa=int(a[-1]),t0=g.t.iloc[0],t1=g.t.iloc[-1],known=st in ('FT','AET','PEN','Match Finished','FINISHED') or (pd.notna(last) and last>=88))
gx=[]
for (ev,day),g in L.groupby(['event_name','day'],sort=False):
    mo=g[g.mkt=='MO']
    if len(mo) and mo.groupby(['t','side']).size().max()>1: SK['MO label defect, game dropped']+=1; continue
    h_,_,a_=ev.partition(' v '); gx.append(dict(H=norm(h_),A=norm(a_),t0=g.t.min(),t1=g.t.max(),g=g))
used={};
for e in gx:
    best=None; bs=0
    for fid,f in fx.items():
        if f['t0']-pd.Timedelta(hours=1)<=e['t1'] and e['t0']<=f['t1']+pd.Timedelta(hours=1):
            s_=min(sim(e['H'],f['H']),sim(e['A'],f['A']))
            if s_>bs: bs,best=s_,fid
    if best is not None and bs>=0.3: used[best]=e
print(f"recorder games {len(gx)}, mapped {len(used)}, {time.time()-T0:.0f}s",flush=True)
rows=[]; rm_all=[]; nsnap=0
INPLAY=('1H','2H','HT','ET','LIVE')
for fid,e in used.items():
    f=fx[fid]; g=e['g']
    bk={c:(x.t.values,x.bp.values,x.lp.values) for c,x in g.sort_values('t').groupby('code')}
    g5=g[g.t>=f['t0']];
    if not len(g5): SK['no prices in the feed window']+=1; continue
    snaps=g5.groupby(g5.t.dt.floor('5min')).t.min().values
    for ts_ in snaps:
        snap=g5[g5.t==ts_]; j=int(np.searchsorted(f['ts'],ts_,side='right'))
        if j==0: continue
        sh,sa=int(f['h'][j-1]),int(f['a'][j-1]); mn=f['mn'][j-1]
        if f['st'][j-1] not in INPLAY and not (pd.notna(mn) and 0<mn<=120 and f['st'][j-1] not in ('FT','NS','AET','PEN')): SK['snapshot not in play']+=1; continue
        if sh+sa>6: SK['total > 6']+=1; continue
        tp=snap.drop_duplicates('code').set_index('code'); target={}
        for m,ix in MKS.items():
            if decided(m,sh,sa): continue
            cs=[SEL[i] for i in ix]
            if all(c in tp.index for c in cs):
                q=np.array([2/(tp.bp[c]+tp.lp[c]) for c in cs]); target[m]=q/q.sum()
        if len(target)<3: SK['fewer than 3 open markets']+=1; continue
        nsnap+=1; i_,j_,rm,pm=fit(sh,sa,target); rm_all.append(rm)
        if rm>0.06: SK['fit RMSE > 0.06']+=1; continue
        back_goal=np.flatnonzero((f['h'][:j]+f['a'][:j])==sh+sa)[0]; since=(ts_-f['ts'][back_goal])/np.timedelta64(60,'s') if sh+sa>0 else 999.0
        for m in target:
            for ix in MKS[m]:
                c=SEL[ix]; b0,l0=float(tp.bp[c]),float(tp.lp[c])
                if l0/b0>1.25: continue
                eb=pm[ix]-1/b0; el=1/l0-pm[ix]
                if eb<0.03 and el<0.03: continue
                side='B' if eb>=el else 'L'; edge=max(eb,el)
                ts,bp,lp=bk[c]; won=won_sel(c,f['fh'],f['fa'])
                tgt=ts_+np.timedelta64(600,'s'); jj=int(np.searchsorted(f['ts'],tgt,side='right'))
                gone=jj>0 and decided(m,int(f['h'][jj-1]),int(f['a'][jj-1]))
                k=int(np.searchsorted(ts,tgt)); i0=int(np.searchsorted(ts,ts_)); qb=ql=None
                if not gone and k<len(ts) and k>i0: qb,ql=float(bp[k]),float(lp[k])
                if side=='B':
                    p1=back(b0,ql,won); p2=back(b0,None,won)
                    if p1 is None or p2 is None: SK['back at 1.01']+=1; continue
                else: p1=lay(l0,qb,won); p2=lay(l0,None,won)
                if not f['known']: p1=p2=-10.0; SK['unknown result = -10']+=1
                rows.append(dict(fid=fid,t=ts_,code=c,mkt=m,side=side,edge=edge,px=b0 if side=='B' else l0,minute=mn,since=since,rm=rm,known=f['known'],P10=p1,SETTLE=p2,real_exit=qb is not None))
print(f"snapshots fitted {nsnap}; median RMSE {np.median(rm_all):.4f}, p90 {np.quantile(rm_all,.9):.4f}; skips {dict(SK)}; candidate rows {len(rows)}, {time.time()-T0:.0f}s",flush=True)
R=pd.DataFrame(rows)
if R.empty: print("\n== SURVIVORS: 0\nnone (no entries)"); sys.exit()
R['ts_']=pd.to_datetime(R.t); med=R.ts_.median(); R['h2']=R.ts_>=med
R['mb']=pd.cut(R.minute,[-1,30,45,60,75,130],labels=['0-30','30-45','45-60','60-75','75+']).astype(str)
R['pb']=pd.cut(R.px,[1,1.5,3,1001],labels=['<=1.5','1.5-3','3+']).astype(str)
print(f"entry span {R.ts_.min()} .. {R.ts_.max()}, median {med}, games {R.fid.nunique()}, real exit share {R.real_exit.mean():.1%}, by market {R.mkt.value_counts().to_dict()}")
def spaced(x):
    keep=[]
    for _,g in x.sort_values('ts_').groupby(['fid','code','side']):
        last=None
        for i_,t_ in zip(g.index,g.ts_):
            if last is None or (t_-last).total_seconds()>=900: keep.append(i_); last=t_
    return x.loc[keep]
out=[]
def score(x,**k):
    if len(x)<20: return
    for ex in ('P10','SETTLE'):
        v=x[ex]; a=v[~x.h2]; b=v[x.h2]; per=x.groupby('fid')[ex].mean()
        d=dict(k); d.update(exit=ex,n=len(v),games=x.fid.nunique(),px=x.px.mean(),mean=v.mean(),t=tstat(v),tc=tstat(per),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,maxwin=v.max(),ex_top=(v.sum()-v.max())/max(len(v)-1,1)); out.append(d)
for side in 'BL':
    Rs=R[R.side==side]
    for thr in (.03,.05,.10):
        x=Rs[Rs.edge>=thr]
        if not len(x): continue
        sp=spaced(x); fi=x.sort_values('ts_').groupby('fid').head(1); qu=spaced(x[x.since>=3])
        score(sp,side=side,edge=thr,sel='ALL',cut='all'); score(fi,side=side,edge=thr,sel='FIRST',cut='all'); score(qu,side=side,edge=thr,sel='QUIET',cut='all')
        for col in ('mkt','mb','pb','code'):
            for val,y in qu.groupby(col): score(y,side=side,edge=thr,sel='QUIET',cut=f'{col}={val}')
O=pd.DataFrame(out); O['PASS']=[passes(a,b,c,d,e,f,g) for a,b,c,d,e,f,g in zip(O.n,O.n1,O.n2,O.t,O.h1,O.h2,O['mean'])]
show=['side','edge','sel','cut','exit','n','games','px','mean','t','tc','h1','h2','maxwin','ex_top','PASS']
print(f"\n== {len(O)} lines scored")
print("\n== headline lines"); print(O[O.cut=='all'].sort_values(['side','edge','sel','exit'])[show].round(3).to_string(index=False))
print("\n== by market, QUIET, edge .05"); print(O[(O.edge==.05)&O.cut.str.startswith('mkt=')].sort_values(['side','cut','exit'])[show].round(3).to_string(index=False))
print("\n== by minute band, QUIET, edge .05"); print(O[(O.edge==.05)&O.cut.str.startswith('mb=')].sort_values(['side','cut','exit'])[show].round(3).to_string(index=False))
print("\n== by price band, QUIET, edge .05"); print(O[(O.edge==.05)&O.cut.str.startswith('pb=')].sort_values(['side','cut','exit'])[show].round(3).to_string(index=False))
print("\n== TOP 15 by t, n>=100"); print(O[O.n>=100].sort_values('t',ascending=False).head(15)[show].round(3).to_string(index=False))
S=O[O.PASS].sort_values('t',ascending=False)
print(f"\n== SURVIVORS: {len(S)}"); print(S[show].round(3).to_string(index=False) if len(S) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
