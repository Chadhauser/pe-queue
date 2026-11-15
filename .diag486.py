# Reading only, item 486: OU4.5 tail cells and the other 18 passed cells by month on the unseen markets (finder_unseen_mk_1109).
import sys, math, numpy as np, pandas as pd, psycopg2
sys.path.insert(0, '/root/pe-queue/runner'); import creds
con = psycopg2.connect(creds.pg_local()); cur = con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='1200s'")
cur.execute("SELECT market_id FROM finder_unseen_mk_1109 WHERE market_id IS NOT NULL"); ids = [r[0] for r in cur.fetchall()]
cur.execute("""
WITH pre AS (SELECT DISTINCT ON (market_id, sel) market_id, sel, market_time, country, ltp::float8 AS close_ltp, ts
             FROM bf_hist_other WHERE sport='Soccer' AND market_id = ANY(%s) AND market_type='OVER_UNDER_45' AND NOT inplay AND ltp>1 AND ltp<1000
             ORDER BY market_id, sel, ts DESC)
SELECT pre.market_id, pre.sel, pre.market_time, pre.country, pre.close_ltp, extract(epoch from pre.market_time-pre.ts)/60 AS mins_before,
       (r.status='WINNER')::int won
FROM pre JOIN bf_hist_result r USING (market_id, sel) WHERE r.status IN ('WINNER','LOSER')""", (ids,))
df = pd.DataFrame(cur.fetchall(), columns=['mk','sel','mt','country','ltp','mins','won'])
n = df.groupby('mk').sel.transform('size'); df = df[n == 2].copy()
df['p'] = (1/df.ltp)/df.groupby('mk').ltp.transform(lambda s: (1/s).sum())
df['month'] = pd.to_datetime(df.mt, utc=True).dt.strftime('%Y-%m')
ov = df[df.sel.str.contains('Over')].copy()
ov = ov[(ov.p >= 0.03) & (ov.p < 0.10)]
print('Over 4.5 at p 0.03-0.10 (both OU45 tail cells live here), unseen:')
print(ov.groupby('month').agg(n=('won','size'), won=('won','mean'), imp=('p','mean'), med_mins=('mins','median'), med_ltp=('ltp','median')).round(4).to_string())
print('by country (n>=50):')
g = ov.groupby('country').agg(n=('won','size'), won=('won','mean'), imp=('p','mean')).round(4)
print(g[g.n >= 50].sort_values('n', ascending=False).to_string())
print('last print age: share over 60 min before the off', round(float((ov.mins > 60).mean()), 3))
fresh = ov[ov.mins <= 10]; stale = ov[ov.mins > 60]
print(f"fresh (<=10 min) n {len(fresh)} won {fresh.won.mean():.4f} v imp {fresh.p.mean():.4f}; stale (>60 min) n {len(stale)} won {stale.won.mean():.4f} v imp {stale.p.mean():.4f}")
