#!/bin/bash
set -o pipefail
# 499_tick_touch_racing_clean (Finder 2026-11-07, queue item 388, Finder's own, source a, from items 380, 385): item 380's four back lines with the signal also needing lay_px <= Q x 1.05 on the same tick. Rule pushed before this job read a price. Same 166 races; cannot pass, item 382 is the test. Read only, temp tables.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))  # this job only
import sys,time,psycopg2,warnings,pandas as pd,numpy as np
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,tstat
from lib_wom import tgame
pd.set_option('display.width',230); pd.set_option('display.max_columns',30)
T0=time.time()
SQL="""WITH f AS (SELECT DISTINCT ON (market_id,sel_id) market_id,sel_id,back_px st FROM {tab} WHERE back_px IS NOT NULL ORDER BY market_id,sel_id,t),
  h AS (SELECT market_id,sel_id,min(t) tt FROM {tab} WHERE back_px<=%(q)s {clean} GROUP BY 1,2)
SELECT h.market_id,h.sel_id,b.t,b.back_px,b.back_sz FROM h JOIN f USING (market_id,sel_id)
  JOIN LATERAL (SELECT x.t,x.back_px,x.back_sz FROM {tab} x WHERE x.market_id=h.market_id AND x.sel_id=h.sel_id AND x.t>=h.tt+%(d)s AND x.back_px IS NOT NULL ORDER BY x.t LIMIT 1) b ON true
WHERE f.st>%(q)s"""
CLEAN="AND lay_px<=%(q)s*1.05+1e-9"
def bk(p,w):
    a=step(p,-1); return np.nan if a<=1.01 else back_settle(a,w)
assert abs(bk(2.0,True)-10*.99*.98)<1e-9 and bk(2.0,False)==-10.0 and np.isnan(bk(1.02,True))
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
# hand-worked: runner 1 junk touch t=1 (lay 30), real touch t=5; D 1 from the real touch fills t=6 at 1.09, from the junk touch fills t=2 at 1.01.
cur.execute("CREATE TEMP TABLE tmp_k (market_id text,sel_id bigint,t float8,back_px float8,back_sz float8,lay_px float8)")
cur.executemany("INSERT INTO tmp_k VALUES (%s,%s,%s,%s,%s,%s)",[('m',1,0.,3.,5,3.1),('m',1,1.,1.01,5,30.),('m',1,2.,1.01,5,30.),('m',1,5.,1.1,5,1.12),('m',1,6.,1.09,5,1.1)])
cur.execute(SQL.format(tab='tmp_k',clean=CLEAN),dict(q=1.1,d=1.0)); _a=cur.fetchall(); assert _a==[('m',1,6.0,1.09,5.0)],_a
cur.execute(SQL.format(tab='tmp_k',clean=''),dict(q=1.1,d=1.0)); _a=cur.fetchall(); assert _a==[('m',1,2.0,1.01,5.0)],_a
cur.execute("DROP TABLE tmp_k"); print("sql checks: OK",flush=True)
cur.execute("""CREATE TEMP TABLE tmp_t AS SELECT market_id,sel_id,extract(epoch from pt)::float8 t,back_px::float8 back_px,back_sz::float8 back_sz,lay_px::float8 lay_px FROM stream_ticks WHERE sport='racing' AND mkt='WIN' AND inplay AND status='OPEN' AND pt IS NOT NULL""")
cur.execute("CREATE INDEX ON tmp_t (market_id,sel_id,t)"); cur.execute("ANALYZE tmp_t")
cur.execute("SELECT DISTINCT market_id FROM tmp_t"); MK=[r[0] for r in cur.fetchall()]
rc=psycopg2.connect(creds.pg_railway(),sslmode='require'); k=rc.cursor(); k.execute("SET statement_timeout='300s'"); k.execute("SELECT market_id,selection_id FROM racing_results WHERE won AND market_id=ANY(%s)",(MK,)); W={}
for m,s in k.fetchall(): W.setdefault(m,[]).append(int(s))
rc.close(); truth={m:v[0] for m,v in W.items() if len(v)==1}; print(f"races {len(MK)}, one winner {len(truth)}, {time.time()-T0:.0f}s",flush=True)
out=[]
for q in (1.1,1.2):
    for d in (1.0,3.0):
        for lab,cl in (('ITEM380',''),('REAL',CLEAN)):
            cur.execute(SQL.format(tab='tmp_t',clean=cl),dict(q=q,d=d)); rows=[]; drop=0
            for m,sel,t,p,sz in cur.fetchall():
                if m not in truth: continue
                won=truth[m]==int(sel); v=bk(p,won)
                if v==v: rows.append((m,t,p,sz,won,v))
                else: drop+=1
            x=pd.DataFrame(rows,columns='m t px sz won v'.split()); v=x.v.values; md=np.median(x.t.values); h=x.t.values<md
            out.append(dict(q=q,delay=d,sig=lab,n=len(v),races=x.m.nunique(),dropped_low=drop,per10=v.mean(),tr=tgame(v,x.m.values),h1=v[h].mean(),h2=v[~h].mean(),won=x.won.mean(),losers=int((~x.won).sum()),fill=x.px.median(),imp=(1/x.px).mean(),sz=x.sz.median()))
print("\n== ITEM 388, item 380's lines v the same with a real book at the signal\n",pd.DataFrame(out).round(3).to_string(index=False))
con.close(); print(f"\n== SURVIVORS: none possible, same races\ntotal {time.time()-T0:.0f}s")
PY
