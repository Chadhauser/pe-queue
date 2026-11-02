#!/bin/bash
set -o pipefail
# 321: THE PRESSURE SCALP — can live stats get us in and out quickly, ahead of the price? Every football game since 27 Oct where the
# goal engine logged minute-by-minute stats (goal_live_predictions: SOT, dangerous attacks, p_goal_next_10) AND the recorder has the
# real touch (liq_sample, every market). Entry triggers, evaluated every minute with no look-ahead:
#   PRESS   : dangerous attacks in the last 5 min >= 8 and shots on target in the last 5 min >= 2 (either side) at 0-0 or 1-goal game
#   PJUMP   : model p_goal_next_10 rose by >= 0.10 over the last 3 minutes
#   MOMO    : Over 2.5 back price shortened >= 4 ticks over the last 3 minutes (price-only momentum, for comparison)
# Trades at the REAL touch: back Over 2.5 (take the lay side price); back the pressing team on Match Odds. Exits: +5 min, +10 min
# (at the real touch, one tick adverse) or first real print >= 2 min after a goal; also "target": lay out as soon as 5% better.
# Reports ticks captured, % of entries that reached the 5% target within 10 min, P&L per £10, by trigger x market x exit; halves by date.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,unicodedata,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET statement_timeout='2400s'")
S=pd.read_sql("""SELECT fixture_id, captured_at, minute, score_home, score_away, home_sot, away_sot, home_da, away_da, p_goal_next_10::float p10
 FROM goal_live_predictions WHERE captured_at>='2026-10-27' AND minute BETWEEN 1 AND 88 ORDER BY fixture_id, captured_at""",con)
FX=pd.read_sql("SELECT DISTINCT ON (fixture_id) fixture_id, home_team, away_team FROM goal_timeline WHERE captured_at>='2026-10-27' ORDER BY fixture_id, captured_at DESC",con)
L=pd.read_sql("""SELECT ts, event_name, mkt, sel, minute, back_px::float back_px, lay_px::float lay_px FROM liq_sample
 WHERE ts>='2026-10-27' AND mkt IN ('MO','OU25') AND event_name LIKE '%% v %%' AND back_px>1.01 AND lay_px<100""",con)
print("stat rows:",len(S),"fixtures:",S.fixture_id.nunique(),"| recorder rows:",len(L),"games:",L.event_name.nunique(),flush=True)
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|club|de|the|athletic|atletico|sporting|real|cd|ud|sd|rcd|calcio|women|w|u21|u23|ii|b|if|bk|ff|aif|is|kv|sk|fsv)\b"," ",s)
    return set(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def sim(a,b): A,B=norm(a),norm(b); return len(A&B)/max(1,len(A|B))
ev=L.groupby('event_name').ts.agg(['min','max']).reset_index(); ev['h']=ev.event_name.str.split(' v ').str[0]; ev['a']=ev.event_name.str.split(' v ').str[1]
first=S.groupby('fixture_id').captured_at.min(); FX=FX.merge(first.rename('t0'),left_on='fixture_id',right_index=True)
m={}
for f in FX.itertuples():
    cand=ev[(ev['min']<f.t0+pd.Timedelta(hours=2))&(ev['max']>f.t0-pd.Timedelta(hours=1))]
    best=None; bs=0; b2=0
    for c in cand.itertuples():
        sc=sim(f.home_team,c.h)+sim(f.away_team,c.a)
        if sc>bs: b2=bs; bs=sc; best=c.event_name
        elif sc>b2: b2=sc
    if best and bs>=1.0 and bs-b2>=0.3: m[f.fixture_id]=best
print("fixtures matched to recorder:",len(m),flush=True)
L=L.sort_values('ts'); books={}
for en,g in L.groupby('event_name'):
    if en not in set(m.values()): continue
    d={}
    for (mk,sl),gg in g.groupby(['mkt','sel']): d[(mk,sl)]=(gg.ts.values,gg.back_px.values,gg.lay_px.values)
    books[en]=d
def touch(book,key,t,after=True,tol=90):
    # nearest sample at/after t (within tol s) -> (back,lay); after=False: at/before
    if key not in book: return None
    ts,b,l=book[key]; t64=np.datetime64(t)
    if after:
        i=np.searchsorted(ts,t64)
        if i<len(ts) and (ts[i]-t64)/np.timedelta64(1,'s')<=tol: return b[i],l[i]
    else:
        i=np.searchsorted(ts,t64,side='right')-1
        if i>=0 and (t64-ts[i])/np.timedelta64(1,'s')<=tol: return b[i],l[i]
    return None
def tick(p): return 0.01 if p<2 else 0.02 if p<3 else 0.05 if p<4 else 0.1 if p<6 else 0.2 if p<10 else 0.5
def back_then_lay(p_in,q_out):  # back at lay-side price p_in (what we get), exit by laying at the back-side price q_out
    p=p_in-tick(p_in); q=q_out+tick(q_out); r=10*(p/q-1); return r*0.98 if r>0 else r
rows=[]
for fid,g in S.groupby('fixture_id'):
    en=m.get(fid)
    if not en: continue
    book=books.get(en)
    if not book: continue
    g=g.sort_values('captured_at').reset_index(drop=True)
    g['tot']=g.score_home+g.score_away
    goals=[(r.captured_at,r.tot) for r in g.itertuples()]
    # goal times = first row where tot increases
    gt=[]; prev=None
    for t,tt in goals:
        if prev is not None and tt>prev: gt.append(t)
        prev=tt
    def next_goal_after(t): return next((x for x in gt if x>t),None)
    hist=[]
    for i,r in g.iterrows():
        hist.append(r)
        if len(hist)<6: continue
        w5=[h for h in hist[-6:-1]]; w3=hist[-4:-1]
        da5=(r.home_da or 0)-(w5[0].home_da or 0)+((r.away_da or 0)-(w5[0].away_da or 0)); sot5=(r.home_sot or 0)-(w5[0].home_sot or 0)+((r.away_sot or 0)-(w5[0].away_sot or 0))
        side='H' if ((r.home_da or 0)-(w5[0].home_da or 0))>=((r.away_da or 0)-(w5[0].away_da or 0)) else 'A'
        trig=[]
        if da5>=8 and sot5>=2 and r.tot<=1: trig.append('PRESS')
        if r.p10 is not None and w3[0].p10 is not None and r.p10-w3[0].p10>=0.10: trig.append('PJUMP')
        o_now=touch(book,('OU25','OVER'),r.captured_at,after=False); o_3=touch(book,('OU25','OVER'),w3[0].captured_at,after=False)
        if o_now and o_3 and (o_3[0]-o_now[0])>=4*tick(o_now[0]): trig.append('MOMO')
        if not trig: continue
        if r.minute>80: continue
        t=r.captured_at; ng=next_goal_after(t)
        for tr in trig:
            for mk,sel in (('OU25','OVER'),('MO','HOME' if side=='H' else 'AWAY')):
                e=touch(book,(mk,sel),t+pd.Timedelta(seconds=15))
                if not e: continue
                p_in=e[1]
                if p_in>20: continue
                for exname,secs in (('+5m',300),('+10m',600)):
                    tx=t+pd.Timedelta(seconds=secs)
                    if ng is not None and ng<tx: tx=ng+pd.Timedelta(seconds=120)
                    x=touch(book,(mk,sel),tx,after=True,tol=180)
                    if not x: continue
                    # target exit: first sample within the window with back price <= p_in*0.95
                    ts_,b_,l_=book[(mk,sel)]; i0=np.searchsorted(ts_,np.datetime64(t)); i1=np.searchsorted(ts_,np.datetime64(tx)); hit=None
                    for k in range(i0,min(i1,len(ts_))):
                        if b_[k]<=p_in*0.95: hit=b_[k]; break
                    pnl=back_then_lay(p_in,x[0]); pnl_t=back_then_lay(p_in,hit) if hit is not None else pnl
                    rows.append((tr,mk,exname,fid,t,r.minute,p_in,x[0],round(pnl,2),hit is not None,round(pnl_t,2),ng is not None and ng<t+pd.Timedelta(seconds=secs)))
R=pd.DataFrame(rows,columns=['trigger','mkt','exit','fixture_id','t','minute','p_in','p_out','pnl','target_hit','pnl_target','goal_in_window'])
print("entries:",len(R),"| fixtures:",R.fixture_id.nunique())
if len(R)==0: sys.exit(0)
R['half']=R.t>R.t.median()
def t_(x): return x.mean()/(x.std(ddof=1)/len(x)**0.5) if len(x)>1 and x.std(ddof=1)>0 else 0
g=R.groupby(['trigger','mkt','exit']).agg(n=('pnl','size'),games=('fixture_id','nunique'),per10_fixed=('pnl','mean'),t=('pnl',t_),per10_target=('pnl_target','mean'),target_hit_pct=('target_hit','mean'),goal_in_window=('goal_in_window','mean'),h1=('pnl',lambda x:x[~R.loc[x.index,'half']].mean()),h2=('pnl',lambda x:x[R.loc[x.index,'half']].mean())).round(3)
print("\n== in-and-out at the real touch, per £10 (fixed = exit on the clock/goal; target = out as soon as 5% better, else clock)"); print(g.to_string())
cur.execute("DROP TABLE IF EXISTS pressure_scalp; CREATE TABLE pressure_scalp (trigger TEXT, mkt TEXT, exit TEXT, n INT, games INT, per10_fixed NUMERIC, t NUMERIC, per10_target NUMERIC, target_hit_pct NUMERIC, goal_in_window NUMERIC, h1 NUMERIC, h2 NUMERIC)")
for k,x in g.reset_index().iterrows(): cur.execute("INSERT INTO pressure_scalp VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",tuple(None if (isinstance(v,float) and np.isnan(v)) else (v.item() if hasattr(v,'item') else v) for v in x.values))
con.commit()
S_=g.reset_index(); S_=S_[(S_.n>=100)&(S_.t>=3.5)&(S_.h1>0)&(S_.h2>0)&(S_.per10_fixed>=0.15)]
print(f"\n== SURVIVORS: {len(S_)}"); print(S_.to_string(index=False) if len(S_) else "none")
PY
