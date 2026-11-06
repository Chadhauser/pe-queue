#!/bin/bash
set -o pipefail
# 499_cricket_touch (Finder 2026-11-06, queue item 271's touch question, Finder's own, source a): how wide is the real book on a cricket outsider at 3-20? ip_tape on Railway, live tape, read only, one short query, no tables written. No pre-off book exists on the box (item 129), so this is the FIRST IN-PLAY rows, a proxy and not the entry itself. A pilot on the tape's rolling window, cannot pass.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step
def ticks(b,l):
    """Ticks from the back touch up to the lay touch. By hand: 3.0 to 3.2 is 4 ticks at 0.05; 2.0 to 2.02 is 1; 5.0 to 5.0 is 0."""
    n=0; x=b
    while x<l-1e-9 and n<200: x=step(x,1); n+=1
    return n
assert ticks(3.0,3.2)==4 and ticks(2.0,2.02)==1 and ticks(5.0,5.0)==0
print("checks: OK",flush=True)
pd.set_option('display.width',200); pd.set_option('display.max_columns',30)
con=psycopg2.connect(creds.pg_railway()); con.autocommit=True; con.cursor().execute("SET statement_timeout='300s'")
P=pd.read_sql("SELECT event_name ev,sel_name s,ltp::float8 ltp,back_px::float8 b,lay_px::float8 l,ts FROM ip_tape WHERE sport IN ('Cricket','cricket') AND market_type='MATCH_ODDS' AND ts>now()-interval '3 days'",con); con.close()
print("rows",len(P),"games",P.ev.nunique(),"range",P.ts.min(),P.ts.max(),flush=True)
P=P[P.b.notna()&P.l.notna()&(P.l>P.b)&(P.b>=1.01)&(P.l<1000)].sort_values('ts',kind='stable')
out=[]; first=P.groupby('ev').ts.transform('min'); Q=P[(P.ts-first)<=pd.Timedelta(minutes=10)]
F=Q.drop_duplicates(['ev','s'])
F=F.assign(n=F.groupby('ev').s.transform('size')); F=F[F.n==2]
Fo=F.sort_values('b').groupby('ev').tail(1); Fo=Fo[(Fo.b>=3)&(Fo.l<20)]
if not len(Fo): print("no game with an outsider at 3-20 in its first 10 in-play minutes")
else:
    t=[ticks(a,c) for a,c in zip(Fo.b,Fo.l)]
    print(f"games with an outsider at 3-20, first row: {len(Fo)}; spread in ticks p25 p50 p75 {np.percentile(t,25):.0f} {np.percentile(t,50):.0f} {np.percentile(t,75):.0f}; lay touch p50 {Fo.l.median():.2f}, back p50 {Fo.b.median():.2f}")
    h=Fo[Fo.ltp.notna()]; k=[ticks(a,c) if c>=a else 0 for a,c in zip(h.ltp,h.l)]
    print(f"lay touch above the last print, ticks, p25 p50 p75: {np.percentile(k,25):.0f} {np.percentile(k,50):.0f} {np.percentile(k,75):.0f}; share within 1 tick {np.mean(np.array(k)<=1):.3f}, within 3 {np.mean(np.array(k)<=3):.3f}, within 5 {np.mean(np.array(k)<=5):.3f}" if len(h) else "no ltp on these rows")
print("\n== SURVIVORS: a pilot, cannot pass, none")
PY
