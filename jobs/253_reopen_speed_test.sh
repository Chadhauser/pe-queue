#!/bin/bash
# 253: CAN WE WIN ON SPEED? Measures, on the streaming tape (after 252), whether the FIRST price shown when a football market
# re-opens after a goal is systematically wrong versus the price 20 s / 120 s later. If the re-open price moves in a
# predictable direction, a sub-second bot at the re-open earns it; if not, speed buys nothing on Betfair's own suspension.
# Waits (exit 75) until 40+ goal re-opens with a book have been taped. Reports per-£10 both ways, both halves.
python3 - <<'PY'
import sys,psycopg2,pandas as pd; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require')
q="""WITH d AS (
 SELECT market_id, sel, ts_recv, status, back_px, lay_px, lag(status) OVER w pstatus,
        max(CASE WHEN status='OPEN' THEN back_px END) OVER (PARTITION BY market_id, sel ORDER BY ts_recv ROWS BETWEEN 60 PRECEDING AND 1 PRECEDING) prev_open_back
 FROM stream_ticks WHERE sport='football' AND mkt='MO' AND inplay AND sel='The Draw' AND back_px IS NOT NULL AND lay_px IS NOT NULL AND lay_px<=back_px*1.25
 WINDOW w AS (PARTITION BY market_id, sel ORDER BY ts_recv)),
reopen AS (SELECT market_id, ts_recv r_ts, back_px r_back, lay_px r_lay, prev_open_back FROM d
           WHERE status='OPEN' AND pstatus='SUSPENDED' AND prev_open_back IS NOT NULL AND back_px>=1.25*prev_open_back)
SELECT r.*,
 (SELECT back_px FROM stream_ticks s WHERE s.market_id=r.market_id AND s.sel='The Draw' AND s.status='OPEN' AND s.back_px IS NOT NULL AND s.ts_recv>=r.r_ts+interval '20 seconds' ORDER BY s.ts_recv LIMIT 1) b20,
 (SELECT lay_px FROM stream_ticks s WHERE s.market_id=r.market_id AND s.sel='The Draw' AND s.status='OPEN' AND s.lay_px IS NOT NULL AND s.ts_recv>=r.r_ts+interval '20 seconds' ORDER BY s.ts_recv LIMIT 1) l20,
 (SELECT back_px FROM stream_ticks s WHERE s.market_id=r.market_id AND s.sel='The Draw' AND s.status='OPEN' AND s.back_px IS NOT NULL AND s.ts_recv>=r.r_ts+interval '120 seconds' ORDER BY s.ts_recv LIMIT 1) b120,
 (SELECT lay_px FROM stream_ticks s WHERE s.market_id=r.market_id AND s.sel='The Draw' AND s.status='OPEN' AND s.lay_px IS NOT NULL AND s.ts_recv>=r.r_ts+interval '120 seconds' ORDER BY s.ts_recv LIMIT 1) l120
FROM reopen r"""
df=pd.read_sql(q,con); df=df.dropna(subset=['b120']); n=len(df); print("goal re-opens with a book:",n)
if n<40: print("waiting for 40"); sys.exit(75)
for c in ['r_back','r_lay','b20','l20','b120','l120','prev_open_back']: df[c]=df[c].astype(float)
df['lay_reopen_hedge120']=10*(df.b120/df.r_lay-1)        # lay draw at re-open lay price, back out at 120 s back price
df['back_reopen_hedge120']=10*(1-df.l120/df.r_back)       # back draw at re-open back price, lay off at 120 s lay price
df['lay_reopen_hedge20']=10*(df.b20/df.r_lay-1); df['back_reopen_hedge20']=10*(1-df.l20/df.r_back)
h=n//2
for c in ['lay_reopen_hedge20','back_reopen_hedge20','lay_reopen_hedge120','back_reopen_hedge120']:
    x=df[c]; t=x.mean()/(x.std(ddof=1)/n**0.5) if x.std(ddof=1)>0 else 0
    print(f"{c:22s} n {n} mean/£10 {x.mean():+.2f} win {100*(x>0).mean():.0f}% t {t:.2f} H1 {x.iloc[:h].mean():+.2f} H2 {x.iloc[h:].mean():+.2f}")
print("mean re-open spread % :",round(100*(df.r_lay/df.r_back-1).mean(),1),"| mean spread at 120 s % :",round(100*(df.l120/df.b120-1).mean(),1))
print("re-open back vs 120 s back: higher after", int((df.b120>df.r_back).sum()), "lower after", int((df.b120<df.r_back).sum()), "same", int((df.b120==df.r_back).sum()))
PY
