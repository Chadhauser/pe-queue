#!/bin/bash
set -o pipefail
# 473 (Finder 2026-11-03, queue item 19, last survivor of job 471; first written as 472, renumbered after another lane took 472): LAY BTTS YES AT 0-0, 75'+, HOLD TO RESULT. The line passes on LTP +1 tick, but liq_sample shows the real lay touch sits a median 17 ticks
# from LTP on this market at 10-30, so the LTP may be a stale print nobody can lay at.
# KNOWN DEFECT IN PART A (found by jobs 474/475, left as run): bf_hist_price holds duplicate rows per minute for BTTS, so "the next print" here is usually the duplicate and the worse-of fill does not bite. Its +0.724 is too generous; 474 rebuilds the same rule at +0.565. Part B does not use this tape.
# PART A, two seasons (bf_hist_price, af): first real print at minutes 75-90 at 0-0, as 470/471 (state = goals at minutes <= print - 1, fill = worse of the print and the next within 2 min, one tick adverse, £10 liability, 2%
#   commission, settle at result, season halves). Split by entry LTP band and by print age (minutes since the previous real print of this selection). Hit rate v the price: a stale-print artefact shows as the profit sitting in low, old prints.
# PART B, real touch (liq_sample x goal_timeline by name match, London day): first sample at minute >= 75 with the feed at 0-0 (feed row <= 300 s old). The SAME games are laid three ways: LTP +1 tick, real lay_px, real lay_px +1 tick.
#   Settled on the last feed row; a fixture whose feed does not reach minute 88 or FT is unknown: shown known-only and unknown = loss. lay_sz at the touch shown (the liability needs stake 10/(p-1)). Halves by date median. n is small: a sanity check, not a pass test.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,unicodedata,bisect,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LADA=np.array(LAD)
def up(p,k=1): return float(LADA[min(int(np.searchsorted(LADA,round(p,2)-1e-9))+k,len(LADA)-1)])
def lay_settle(a,won):   # a = the price actually laid at, already adverse; liability £10
    return -10.0 if won else 10/(a-1)*0.98
# known answers, worked by hand: lay 21 -> stake 10/20 = 0.50, keep 0.49 after 2%; loses the £10 liability if YES wins; 20 steps up to 21, 21 to 22, 19.5 to 20
assert abs(lay_settle(21.0,False)-0.49)<1e-9 and lay_settle(21.0,True)==-10.0 and up(20.0)==21.0 and up(21.0)==22.0 and up(19.5)==20.0 and up(1000.0)==1000.0
print("P&L unit checks: OK",flush=True)
def tstat(x):
    x=np.asarray(x,dtype=float); s=x.std(ddof=1) if len(x)>1 else 0
    return x.mean()/(s/len(x)**0.5) if s>0 else 0.0
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s';")
# ---- PART A
G=pd.read_sql("""SELECT m.event_id, f.fixture_id, f.season, f.hg, f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint
 WHERE f.status='FT' AND f.hg IS NOT NULL AND f.ht_hg=0 AND f.ht_ag=0""",con)
EV=pd.read_sql("SELECT fixture_id, min(coalesce(minute,0)) AS first_goal FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') GROUP BY 1",con,params=(list(map(int,G.fixture_id)),))
fg=dict(zip(EV.fixture_id,EV.first_goal)); rows=[]
for i in range(0,len(G),2000):
    sub=G.iloc[i:i+2000]
    P=pd.read_sql("SELECT event_id, minute, ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='BTTS' AND sel='YES' AND minute BETWEEN 40 AND 95 AND ltp>=1.01 AND ltp<1000",con,params=(list(sub.event_id),))
    by={k:v.sort_values('minute') for k,v in P.groupby('event_id')}
    for g in sub.itertuples():
        v=by.get(g.event_id)
        if v is None: continue
        ms=v.minute.values; ls=v.ltp.values; f=fg.get(g.fixture_id,999)
        for j,m in enumerate(ms):
            if 75<=m<=90 and f>=m:          # 0-0 known at this print (no goal at minutes <= m-1); a goal AT m is kept, as 470/471
                if ls[j]>50: break
                nxt=ls[j+1] if j+1<len(ms) and ms[j+1]<=m+2 else ls[j]
                p=max(ls[j],nxt); won=int(g.hg)>0 and int(g.ag)>0
                rows.append(dict(m=m,ltp=ls[j],p=p,age=m-ms[j-1] if j else 99,won=won,season=int(g.season),pnl=lay_settle(up(p),won)))
                break
A=pd.DataFrame(rows); A['pxb']=pd.cut(A.ltp,[1,8,12,16,20,30,50],labels=['<8','8-12','12-16','16-20','20-30','30-50']); A['ageb']=pd.cut(A.age,[-1,1,3,10,1000],labels=['1 min','2-3 min','4-10 min','>10 min'])
def tab(df,by):
    out=[]
    for k,x in df.groupby(by,observed=True):
        a=x[x.season==2024].pnl; b=x[x.season==2025].pnl
        out.append(dict(cell=k,n=len(x),hit=x.won.mean(),fair=1/x.won.mean() if x.won.mean()>0 else np.inf,mean_ltp=x.ltp.mean(),per10=x.pnl.mean(),t=tstat(x.pnl),h1=a.mean() if len(a) else np.nan,h2=b.mean() if len(b) else np.nan))
    return pd.DataFrame(out).round(3).to_string(index=False)
pd.set_option('display.width',240); pd.set_option('display.max_columns',30)
print(f"\n== PART A, two seasons: n {len(A)}, YES won {A.won.sum()} ({A.won.mean():.2%}, fair price {1/A.won.mean():.1f}), mean LTP {A.ltp.mean():.1f}, per £10 {A.pnl.mean():+.3f}, t {tstat(A.pnl):.2f}, h1 {A[A.season==2024].pnl.mean():+.3f}, h2 {A[A.season==2025].pnl.mean():+.3f}")
print("\nby entry LTP"); print(tab(A,'pxb')); print("\nby print age"); print(tab(A,'ageb'))
# ---- PART B
cur.execute("SELECT min(ts),max(ts) FROM liq_sample WHERE mkt='BTTS' AND sel='YES'"); L0,L1=cur.fetchone(); print(f"\n== PART B, real touch: liq_sample BTTS YES {L0} .. {L1}",flush=True)
L=pd.read_sql("""SELECT ts, event_name, minute, ltp::float ltp, back_px::float bp, lay_px::float lp, lay_sz::float ls FROM liq_sample WHERE mkt='BTTS' AND sel='YES' AND minute BETWEEN 75 AND 95 AND lay_px>1 AND event_name LIKE '%% v %%' ORDER BY ts""",con)
T=pd.read_sql("""SELECT fixture_id, captured_at, home_team, away_team, minute, score_home, score_away, status FROM goal_timeline WHERE captured_at>=%s AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id, captured_at""",con,params=(L0-pd.Timedelta(hours=3),))
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|club|de|the|athletic|atletico|sporting|real|cd|ud|sd|rcd|calcio|women|w|u21|u23|ii|b|if|bk|ff|aif|is|kv|sk|fsv)\b"," ",s)
    return set(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def sim(A,B): return len(A&B)/max(1,len(A|B))
fx=[]
for fid,g in T.groupby('fixture_id'):
    fx.append(dict(fid=fid,h=norm(g.home_team.iloc[0]),a=norm(g.away_team.iloc[0]),t0=g.captured_at.iloc[0],t1=g.captured_at.iloc[-1],ts=g.captured_at.values,sh=g.score_home.astype(int).values,sa=g.score_away.astype(int).values,minute=g.minute.values,status=g.status.values))
res=[]; SK=defaultdict(int)
for ev,g in L.groupby('event_name'):
    h_,_,a_=ev.partition(' v '); H_,A_=norm(h_),norm(a_); t=g.ts.iloc[0]; best=None; bs=0
    for f in fx:
        if f['t0']-pd.Timedelta(hours=1)<=t<=f['t1']+pd.Timedelta(hours=1):
            s_=min(sim(H_,f['h']),sim(A_,f['a']))
            if s_>bs: bs,best=s_,f
    if best is None or bs<0.3: SK['no fixture match']+=1; continue
    tsv=best['ts']; done=False
    for r in g.itertuples():
        j=np.searchsorted(tsv,np.datetime64(r.ts.tz_convert('UTC').tz_localize(None)),side='right')-1
        if j<0: continue
        age=(np.datetime64(r.ts.tz_convert('UTC').tz_localize(None))-tsv[j])/np.timedelta64(1,'s')
        if age>300: continue
        if best['sh'][j]==0 and best['sa'][j]==0:
            known=str(best['status'][-1]) in ('FT','AET','PEN','Match Finished','FINISHED') or (pd.notna(best['minute'][-1]) and best['minute'][-1]>=88)
            won=best['sh'][-1]>0 and best['sa'][-1]>0
            res.append(dict(ev=ev,ts=r.ts,minute=r.minute,ltp=r.ltp,bp=r.bp,lp=r.lp,ls=r.ls,known=known,won=won)); done=True; break
        else: break
    if not done: SK['not 0-0 at first usable sample']+=1
print("games with BTTS YES samples at 75+:",L.event_name.nunique(),"| skipped:",dict(SK),flush=True)
B=pd.DataFrame(res)
if B.empty: print("\n== PART B: no entries")
else:
    B['ltp_x']=[l if l>1 else np.nan for l in B.ltp]
    B['ticks']=np.searchsorted(LADA,B.lp.round(2)-1e-9)-np.searchsorted(LADA,B.ltp.round(2)-1e-9)
    print(f"entries {len(B)}, known result {int(B.known.sum())}, YES won {int((B.known&B.won).sum())}; median LTP {B.ltp.median()}, median real lay {B.lp.median()}, median gap {B.ticks.median():.0f} ticks, median lay_sz £{B.ls.median():.2f}; share of LTP-fills that were lower than the real lay touch {(B.ltp<B.lp).mean():.0%}")
    K=B[B.known]; K_=K.sort_values('ts'); med=K_.ts.median(); rows2=[]
    for nm,price in (('LTP +1 tick (engine)',K.ltp.map(lambda v:up(v))),('real lay_px',K.lp),('real lay_px +1 tick',K.lp.map(lambda v:up(v)))):
        pn=np.array([lay_settle(a,w) for a,w in zip(price,K.won)]); unk=len(B)-len(K)
        rows2.append(dict(fill=nm,n=len(K),per10=pn.mean(),t=tstat(pn),h1=pn[(K.ts<med).values].mean() if (K.ts<med).any() else np.nan,h2=pn[(K.ts>=med).values].mean(),per10_unknown_as_loss=(pn.sum()-10*unk)/len(B),mean_stake=np.mean(10/(price-1))))
    print(pd.DataFrame(rows2).round(3).to_string(index=False))
A['p1']=A.p.map(lambda v:up(v))
print(f"\n== SURVIVORS: judged on the real touch in the report; two-season line on LTP: n {len(A)}, {A.pnl.mean():+.3f}, t {tstat(A.pnl):.2f}")
PY
