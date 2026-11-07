#!/bin/bash
set -o pipefail
# 499_tick_touch_level (Finder 2026-11-07, queue item 380, Finder's own, source a, from items 372, 379): item 379 again on stream_ticks, every tick, as ip_tape's clean frames are about 34 s apart in a race. Rule pushed before any price was scored. Read only.
# ENTRY first in-play tick with back_px <= Q after an in-play tick with back_px > Q; fill at the first tick of that runner at least D seconds later, D 1 and 3, with a touch on that side, one tick adverse. No later tick, no trade, counted. Result racing_results, one winner only; races with none not scored, counted. 2%, £10 risk. Clock pt, the exchange's own time.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))  # this job only
import sys,time,psycopg2,warnings,pandas as pd,numpy as np
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,lay_settle,tstat,passes
from lib_wom import tgame
pd.set_option('display.width',230); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',30)
T0=time.time()
SQL_TOUCH="""WITH f AS (SELECT DISTINCT ON (market_id,sel_id) market_id,sel_id,back_px st FROM {tab} WHERE back_px IS NOT NULL ORDER BY market_id,sel_id,t),
  h AS (SELECT market_id,sel_id,min(t) tt FROM {tab} WHERE back_px<=%(q)s GROUP BY 1,2)
SELECT h.market_id,h.sel_id,f.st,b.t,b.back_px,l.t,l.lay_px FROM h JOIN f USING (market_id,sel_id)
  LEFT JOIN LATERAL (SELECT x.t,x.back_px FROM {tab} x WHERE x.market_id=h.market_id AND x.sel_id=h.sel_id AND x.t>=h.tt+%(d)s AND x.back_px IS NOT NULL ORDER BY x.t LIMIT 1) b ON true
  LEFT JOIN LATERAL (SELECT x.t,x.lay_px FROM {tab} x WHERE x.market_id=h.market_id AND x.sel_id=h.sel_id AND x.t>=h.tt+%(d)s AND x.lay_px IS NOT NULL ORDER BY x.t LIMIT 1) l ON true
WHERE f.st>%(q)s"""
def bk(p,w):
    a=step(p,-1); return np.nan if a<=1.01 else back_settle(a,w)
def ly(p,w): return lay_settle(step(p,1),w)
# known answers, worked by hand
assert abs(bk(2.0,True)-10*.99*.98)<1e-9 and ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9 and np.isnan(bk(1.02,True))
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
# In SQL on a temp table: the first run hit this job's 1.5 GB cap fetching the ticks, on a box with about 1 GB free. Checked first on a small table worked by hand.
cur.execute("CREATE TEMP TABLE tmp_k (market_id text,sel_id bigint,t float8,back_px float8,lay_px float8)")
_r=[('m',1,0.,3.0,3.1),('m',1,.5,2.5,2.6),('m',1,1.,2.0,2.1),('m',1,2.,1.9,None),('m',1,4.,None,1.9),('m',1,6.,1.7,1.8),('m',2,0.,1.5,1.6),('m',2,5.,1.4,1.5)]
cur.executemany("INSERT INTO tmp_k VALUES (%s,%s,%s,%s,%s)",_r)
def kq(q,d):
    cur.execute(SQL_TOUCH.format(tab='tmp_k'),dict(q=q,d=d)); return cur.fetchall()
assert kq(2.0,1.0)==[('m',1,3.0,2.0,1.9,4.0,1.9)]      # touched at t=1; back at t=2, 1.9; t=2 has no lay, so lay at t=4; runner 2 started under Q
assert kq(2.0,3.0)==[('m',1,3.0,6.0,1.7,4.0,1.9)]      # at least 3 s on: t=4 has no back, so back at t=6
assert kq(1.0,1.0)==[] and kq(3.0,1.0)==[]              # never touched; already there at the first tick
assert kq(2.0,9.0)==[('m',1,3.0,None,None,None,None)]   # no later tick
cur.execute("DROP TABLE tmp_k"); print("sql checks: OK",flush=True)
cur.execute("""CREATE TEMP TABLE tmp_t AS SELECT market_id,sel_id,extract(epoch from pt)::float8 t,back_px::float8 back_px,lay_px::float8 lay_px,back_sz::float8 back_sz FROM stream_ticks WHERE sport='racing' AND mkt='WIN' AND inplay AND status='OPEN' AND pt IS NOT NULL""")
cur.execute("CREATE INDEX ON tmp_t (market_id,sel_id,t)"); cur.execute("ANALYZE tmp_t")
cur.execute("SELECT count(*),count(DISTINCT market_id),min(t),max(t) FROM tmp_t"); nt,nm,t_lo,t_hi=cur.fetchone(); print(f"ticks {nt:,}, markets {nm}, {pd.to_datetime(t_lo,unit='s')} to {pd.to_datetime(t_hi,unit='s')}, {time.time()-T0:.0f}s",flush=True)
cur.execute("SELECT DISTINCT market_id FROM tmp_t"); MK=[r[0] for r in cur.fetchall()]
rc=psycopg2.connect(creds.pg_railway(),sslmode='require'); k=rc.cursor(); k.execute("SET statement_timeout='300s'"); k.execute("SELECT market_id,selection_id FROM racing_results WHERE won AND market_id=ANY(%s)",(MK,)); W={}
for m,s in k.fetchall(): W.setdefault(m,[]).append(int(s))
rc.close(); truth={m:v[0] for m,v in W.items() if len(v)==1}; print(f"one winner {len(truth)}, dead heats {sum(len(v)>1 for v in W.values())}, no result {nm-len(W)}",flush=True)
cur.execute("SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY g),percentile_cont(0.9) WITHIN GROUP (ORDER BY g) FROM (SELECT t-lag(t) OVER (PARTITION BY market_id,sel_id ORDER BY t) g FROM tmp_t) z WHERE g IS NOT NULL"); print("seconds between ticks of one runner, median and p90",[round(x,2) for x in cur.fetchone()],flush=True)
rows=[]; nof=0
for q in (3,2,1.5,1.3,1.2,1.1):
    for d in (1.0,3.0):
        cur.execute(SQL_TOUCH.format(tab='tmp_t'),dict(q=q,d=d)); got=cur.fetchall(); print(f"  q {q} d {d}: touched {len(got)} | {time.time()-T0:.0f}s",flush=True)
        for m,sel,st,tb,pb,tl,pl in got:
            if m not in truth: continue
            won=truth[m]==int(sel); mv=st>=1.5*q
            if pb is None and pl is None: nof+=1
            if pb is not None:
                v=bk(pb,won)
                if v==v: rows.append((m,tb,q,d,'back',pb,won,v,mv,int(sel)))
            if pl is not None: rows.append((m,tl,q,d,'lay',pl,won,ly(pl,won),mv,int(sel)))
R=pd.DataFrame(rows,columns='m t q d side px won v mv sel'.split()); print(f"entries {len(R):,}; touched with no later tick {nof}",flush=True)
def tab(x,**k):
    v=x.v.values; md=np.median(x.t.values); h=x.t.values<md; a,b=v[h],v[~h]; tr=tgame(v,x.m.values)
    return dict(**k,n=len(v),races=x.m.nunique(),per10=v.mean(),t=tstat(v),tr=tr,n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,won=x.won.mean(),fill=x.px.median(),imp=(1/x.px).mean(),maxwin=v.max(),PASS=passes(len(v),len(a),len(b),tr,a.mean() if len(a) else 0,b.mean() if len(b) else 0,v.mean()))
out=[]
for (q,d,s),x in R.groupby(['q','d','side']):
    out.append(tab(x,q=q,delay=d,side=s,start='ALL')); y=x[x.mv]
    if len(y)>=30: out.append(tab(y,q=q,delay=d,side=s,start='MOVE'))
O=pd.DataFrame(out).sort_values('tr',ascending=False); print(f"\n== ITEM 380: {len(O)} lines, by t per race\n",O.round(3).to_string(index=False))
Z=O[O.PASS==True]; print(f"\n== SURVIVORS: {len(Z)}\n",Z.round(3).to_string(index=False) if len(Z) else "none"); # ITEM 382: stream_ticks rolls, so every run saves its entries to a local table, one row per race, runner, level, delay and side, and pools them. Only rows after the rule date are unseen. Re-running adds no duplicates.
from psycopg2.extras import execute_values
cur.execute("CREATE TABLE IF NOT EXISTS finder_touch_entries (market_id text,sel bigint,q float8,d float8,side text,t float8,px float8,won boolean,v float8,mv boolean,PRIMARY KEY (market_id,sel,q,d,side))")
execute_values(cur,"INSERT INTO finder_touch_entries VALUES %s ON CONFLICT DO NOTHING",[(r.m,int(r.sel),float(r.q),float(r.d),r.side,float(r.t),float(r.px),bool(r.won),float(r.v),bool(r.mv)) for r in R.itertuples()])
RULE=pd.Timestamp('2026-11-07 09:00',tz='UTC').timestamp()
P_=pd.read_sql("SELECT market_id m,q,d,side,t,px,won,v,mv FROM finder_touch_entries",con)
print(f"\n== ITEM 382: saved entries {len(P_):,}, races {P_.m.nunique()}, unseen races since the rule {P_[P_.t>=RULE].m.nunique()}",flush=True)
pk=[]
for (q,d) in ((1.1,1.0),(1.2,1.0),(1.1,3.0),(1.2,3.0)):
    x=P_[(P_.q==q)&(P_.d==d)&(P_.side=='back')]
    for lab,y in (('ALL',x),('UNSEEN',x[x.t>=RULE])):
        if len(y)>=2: pk.append(tab(y,q=q,delay=d,side='back',start=lab))
print(pd.DataFrame(pk).round(3).to_string(index=False) if pk else "none yet",flush=True)
# ITEM 381: can the two best lines be sized, and who lost. No new line, no new price rule: same entries as item 380, delay 1 s.
print("\n== ITEM 381: the back at Q 1.1 and 1.2, delay 1 s: size on show at the fill, time left, losers",flush=True)
SZ="""WITH f AS (SELECT DISTINCT ON (market_id,sel_id) market_id,sel_id,back_px st FROM tmp_t WHERE back_px IS NOT NULL ORDER BY market_id,sel_id,t),
  h AS (SELECT market_id,sel_id,min(t) tt FROM tmp_t WHERE back_px<=%(q)s GROUP BY 1,2), e AS (SELECT market_id,max(t) te FROM tmp_t GROUP BY 1)
SELECT h.market_id,h.sel_id,f.st,h.tt,b.t,b.back_px,b.back_sz,e.te FROM h JOIN f USING (market_id,sel_id) JOIN e USING (market_id)
  JOIN LATERAL (SELECT x.t,x.back_px,x.back_sz FROM tmp_t x WHERE x.market_id=h.market_id AND x.sel_id=h.sel_id AND x.t>=h.tt+1.0 AND x.back_px IS NOT NULL ORDER BY x.t LIMIT 1) b ON true
WHERE f.st>%(q)s"""
for q in (1.1,1.2):
    cur.execute(SZ,dict(q=q)); E=pd.DataFrame(cur.fetchall(),columns='m sel st tt tb pb sz te'.split()); E=E[E.m.isin(truth)].copy(); E['won']=[truth[m]==int(x) for m,x in zip(E.m,E.sel)]
    E['v']=[bk(p,w) for p,w in zip(E.pb,E.won)]; E=E[E.v==E.v]; E['left']=E.te-E.tb
    print(f"  Q {q}: n {len(E)}, won {E.won.mean():.3f}, median fill {E.pb.median():.2f}; size on show: known {E.sz.notna().mean():.2f}, median £{E.sz.median():.0f}, share >= £10 {(E.sz>=10).mean():.2f}, >= £50 {(E.sz>=50).mean():.2f}, >= £200 {(E.sz>=200).mean():.2f}; seconds to the race's last tick, median {E.left.median():.0f}; start price median {E.st.median():.1f}",flush=True)
    print("  losers:",E[~E.won][['st','pb','left','sz']].round(1).to_dict('records'),flush=True)
    v10=np.minimum(E.sz.fillna(0),10)/10*E.v; print(f"  per £10 taking the lesser of £10 and the size on show, mean {v10.mean():+.3f}; up to £100 at the size on show, sum over the sample {(np.minimum(E.sz.fillna(0),100)/10*E.v).sum():+.0f}",flush=True)
con.close()
print(f"total {time.time()-T0:.0f}s")
PY
