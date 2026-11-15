# Results coverage by sport — 2026-11-15 15:54 UTC (job 585)

```
Traceback (most recent call last):
  File "<stdin>", line 3, in <module>
psycopg2.errors.UndefinedColumn: column "market_time" does not exist
LINE 1: ...t sport, count(*), count(distinct market_id), min(market_tim...
                                                             ^
HINT:  Perhaps you meant to reference the column "bf_hist_result.market_type".

```
## loader code
```
/root/pe-fin/team/repo/.probe1109d.py
/root/pe-fin/team/repo/.cen1108f.py
/root/pe-fin/team/repo/.add_456.py
/root/pe-fin/team/repo/.finish_372.py
/root/pe-fin/team/repo/.v_499_inplay_map_maker.py
/root/pe-fin/team/repo/.add_479.py
/root/pe-fin/team/repo/.add_481.py
/root/pe-fin/team/repo/.cen1108p.py
/root/pe-fin/team/repo/jobs/lib_afmatch.py
/root/pe-fin/team/repo/jobs/lib_official.py
---
### /root/pe-fin/team/repo/.probe1109d.py
16:cur.execute("select indexname, indexdef from pg_indexes where tablename in ('bf_hist_other','bf_hist_result')")
### /root/pe-fin/team/repo/.cen1108f.py
6:cur.execute("select sport, market_type, count(distinct market_id) n from bf_hist_result group by 1,2 order by 3 desc")
### /root/pe-fin/team/repo/.add_456.py
3:assert '\n456. ' not in s and s.rstrip().splitlines()[-1].startswith('455. ')
5:"tables bf_hist_other, bf_hist_result; job 499_mo_premarket_drift from jobs/499_ou05_late_full.sh) **Match Odds pre-match drift: enter hours before kick-off, trade out at the last pre-off print.** "
15:t=t.rstrip('\n')+'\n'+("2026-11-08 | c/d (bf_hist_other, bf_hist_result) | MO pre-match drift, enter 24/6/2 h before KO by price band, trade out at the last pre-off print, rule fixed (499_mo_premar
```
## raw files on disk
```
/root/pe-hist:
348K	/root/pe-hist
/root/pe-hist
/root/pe-hist/__pycache__
/root/pe-data:
1.8G	/root/pe-data
/root/pe-data
/root/pe-data/yf1m
/root/pe-data/alpaca
/root/pe-data/alpaca/GM
/root/pe-data/alpaca/ADBE
/root/pe-data/alpaca/RIOT
/root/pe-data/alpaca/LLY
/root/pe-data/alpaca/SOFI
/root/pe-data/alpaca/UNH
/root/pe-data/alpaca/KO
/root/pe-data/alpaca/CVNA
/root/pe-data/alpaca/CSCO
/root/pe-data/alpaca/IWM
/root/pe-data/alpaca/MSFT
/root/pe-data/alpaca/TQQQ
/root/pe-data/alpaca/TMUS
/root/pe-data/alpaca/NFLX
/root/pe-data/alpaca/ORCL
/root/pe-data/alpaca/RCL
/root/pe-data/alpaca/ABBV
@reboot nohup /root/pe-hist/keepalive_hist.sh >/dev/null 2>&1 &
*/10 * * * * pgrep -f keepalive_hist.sh >/dev/null || nohup /root/pe-hist/keepalive_hist.sh >/dev/null 2>&1 &
15 * * * * cd /root/pe-hist && timeout 72000 /usr/bin/python3 loader_adv.py >> loader_adv.log 2>&1
```
## loader state
```
2026-11-15_16:46 /root/pe-hist/loader.log
2026-11-15_16:15 /root/pe-hist/loader_adv.log
```
## bot now
```
2552475 /bin/bash /root/pe-sports/bookie/run_bookie_v2.sh
3996807 python3 bookie_v2.py
2026-11-15 15:30:39 passed cells 18 over types [('1', 'BOTH_TEAMS_TO_SCORE'), ('1', 'CORRECT_SCORE'), ('1', 'DRAW_NO_BET'), ('1', 'FIRST_HALF_GOALS_05'), ('1', 
2026-11-15 15:40:42 passed cells 18 over types [('1', 'BOTH_TEAMS_TO_SCORE'), ('1', 'CORRECT_SCORE'), ('1', 'DRAW_NO_BET'), ('1', 'FIRST_HALF_GOALS_05'), ('1', 
2026-11-15 15:50:49 passed cells 18 over types [('1', 'BOTH_TEAMS_TO_SCORE'), ('1', 'CORRECT_SCORE'), ('1', 'DRAW_NO_BET'), ('1', 'FIRST_HALF_GOALS_05'), ('1', 
```
