import sys
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local()); cur = c.cursor(); cur.execute("SET statement_timeout='300s'")
cur.execute("select market_type, count(*) from (select market_type from bf_hist_other where sport='Horse Racing' and market_time between '2025-03-01' and '2025-03-03' limit 200000) x group by 1")
mt = dict(cur.fetchall()); print(mt)
if 'PLACE' not in mt: print('NO PLACE, not claimed'); sys.exit(1)
Q = '/root/pe-queue/watchman/FINDER_QUEUE.md'; H = '/root/pe-queue/watchman/HYPOTHESES.md'
q = open(Q).read(); assert '\n470. ' not in q
item = ("470. RUNNING 2026-11-08 (lane A, about 20:42 UTC; Finder's own, source c, third door of items 468-469; tables bf_hist_other Horse Racing PLACE GB/IE, Railway bfsp_history market_type place (read only); "
 "job 499_bsp_loc_place, item 469's code with the market switched; item 246 swept place BSP by band, never conditional on BSP against the last print) "
 "**Limit-on-close on the PLACE market: back if place BSP >= k x the last pre-off place print, lay if <= print / k, held to the place result.** "
 "Rationale: each-way and place money is SP-heavy and thin, so the place BSP may be pushed further from fair than the win BSP, which items 468-469 found fair in every band. "
 "Rule fixed now, before any place price is read: item 468's engine unchanged (p T-5 to T-1, bands <3 3-6 6-12 12-20 20-50 ALL, k 1.0 1.1 1.25, BSP one tick adverse, GBP 10, 2%, held to win_lose, t the smaller of trade and race, halves by date median) "
 "on PLACE markets, BSP and win_lose from bfsp_history place on date and folded name, unique, within 2 h; all 36 lines gated, standard bar; best line read on its own halves; full fill assumed, an upper bound.")
open(Q, 'w').write(q.rstrip('\n') + '\n' + item + '\n')
h = open(H).read().rstrip('\n') + '\n' + "2026-11-08 | c structural (bf_hist_other PLACE, bfsp_history, from 468-469) | limit-on-close at BSP on the PLACE market (499_bsp_loc_place, item 470) | RUNNING | rule fixed before prices\n"
open(H, 'w').write(h); print('claimed')
