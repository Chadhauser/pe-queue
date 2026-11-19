# 662 — 2026-11-19 07:02 UTC
```
-rw-r--r-- 1 root root 0 Nov 16 17:12 /root/REAL_MONEY_OFF
== started by 661
    892    20:46:55 /bin/bash /root/pe-hist/keepalive_hist.sh
    893    20:46:55 /bin/bash ./duka_loop.sh
    899    20:46:55 python3 sports_team.py
    903    20:46:55 python3 duka_daemon.py
1600364       01:58 /bin/bash /root/pe-brain/run_stats_collector.sh
1600379       01:58 python3 desk.py
1600386       01:58 /root/pe-brain/venv/bin/python -u brain/stats_collector.py
-- /root/pe-sports/desk/desk.py
import sys, os, re, time, json, datetime, traceback, subprocess, requests, psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
STAKE=2.0; COMM=0.02; FADE_OFFSET=120; FADE_MAX=6.0; FADE_HOLD=600; POLL=20
LOG='/root/pe-sports/desk/desk.log'; CALLS_DIR='/root/pe-queue/calls'
def log(m):
    with open(LOG,'a') as f: f.write(f"{datetime.datetime.utcnow():%Y-%m-%d %H:%M:%S} {m}\n")
-- /root/pe-sports/team/sports_team.py
# SPORTS TEAM — continuous background loop on the trading server (Peter, 5 Nov 2026).
# Proposer = pre-registered hypotheses.json (THE ONE JOB: fair price first, then the resting-order bookie bot; no named strategies).
# Critics = mechanical pre-run checks. Builder runs the script. Verifier applies the gates and is the ONLY writer of
# /root/pe-sports/team/scoreboard.{json,md}. Every cycle opens with a DATA HEALTH block over both databases (Railway live tape,
# local history); the five live jobs get one status line each from the tables themselves. The scoreboard is mirrored into
# Railway job_results (job='SPORTS_SCOREBOARD') so the chat can read it from anywhere.
== test scripts
book_recorder.py | 2026-11-18 | 655 THE recorder (one machine, step 1): the real Betfair order book for every football market from 3 h before the off to the end of
cells_tradable.py | 2026-11-16 | WITH p AS (SELECT DISTINCT ON (o.market_id,o.sel) o.market_id,o.sel,o.market_time,o.ltp FROM bf_hist_other o
coherence.py | 2026-11-17 | 652 Cross-market coherence: price Betfair's THIN football markets from its own DEEP ones. No outside data.
coherence_paper.py | 2026-11-17 | 654 Coherence FORWARD paper on the REAL order book. 652 found big edges pricing thin markets from deep ones, but it used the last traded
execution_methods.py | 2026-11-16 | 
fade_forward.py | 2026-11-05 | 
fairprice_country.py | 2026-11-12 | 
fairprice_inplay.py | 2026-11-12 | 
fairprice_v0.py | 2026-11-15 | 
friday_email.py | 2026-11-14 | median £ available at the touch on the rule's own markets around its entries (liq_sample back_sz/lay_sz).
goal_alert_mail.py | 2026-11-13 | 
ht_reprice.py | 2026-11-17 | 637 Re-price every half-time goal-signal alert (goal_alerts, 25 Oct - 7 Nov) at the REAL Betfair back price recorded on the in-play
loser_autopsy.py | 2026-11-17 | 629 Loser autopsy. Peter: 
model_v2.py | 2026-11-16 | WITH mk AS (SELECT DISTINCT market_id FROM bf_hist_result WHERE sport=%s AND market_type=%s ORDER BY market_id LIMIT %s),
model_v3.py | 2026-11-17 | 648 Fair price v3: Pinnacle as the fair price, Betfair as the place to bet. What the solo winners do.
model_v3b.py | 2026-11-17 | 651 Fair price v3b: the MARKET AVERAGE (football-data AvgC*, margin removed) as the fair price - Pinnacle closing left football-data in Jan 
real_money_guard.py | 2026-11-16 | 
replay_fills.py | 2026-11-10 | SELECT market_id, sport, mkt, min(ts_recv), max(ts_recv) FROM stream_ticks
replay_fills_hist.py | 2026-11-10 | 
replay_inplay_xx.py | 2026-11-13 | rows: list of (ts, sel, bb, bs, bl, ls) for one market window. Quote at each offset (seconds from window start) on every runner,
sb_resettle.py | 2026-11-18 | 
small_bites.py | 2026-11-16 | Small bites: in-and-out trades on the tape, no holding to settlement. Model-free.
small_bites_live.py | 2026-11-18 | Small bites, FORWARD paper (626). The cells that passed both halves on the tape (reports/small_bites.md, 16 Nov), traded forward on
sports_team.py | 2026-11-14 | PROOF GATE (Peter, 12 Nov): per rule, settled n/100, £ after commission, each half of the settled run, PASS or n more.
tape_replay.py | 2026-11-16 | 
team_news.py | 2026-11-17 | 653 Team news: does knowing which regular players are missing (line-ups come out ~60 min before kick-off) predict how the Betfair
v3_recorder.py | 2026-11-17 | 649 v3 forward paper, part 1: record the Betfair match-odds touch about 2 minutes before every kick-off in the football-data divisions'
v3_settle.py | 2026-11-17 | 649 v3 forward paper, part 2 (daily). Refresh this season's football-data files (Pinnacle closing odds and results appear there a few days
verifier_cells.py | 2026-11-10 | CREATE TABLE IF NOT EXISTS fair_price_passed (sport TEXT, market_type TEXT, band_lo NUMERIC, band_hi NUMERIC, side TEXT, fair_factor NUMERIC
verifier_cells_inplay.py | 2026-11-10 | CREATE TABLE IF NOT EXISTS fair_price_passed_inplay (market_type TEXT, minute_lo INT, minute_hi INT, band_lo NUMERIC, band_hi NUMERIC, side 
bookie_paper (992873 rows): id:bigint, ts:timestamp with time zone, market_id:text, event_name:text, mkt:text, sel:text, side:text, price:numeric, fair:numeric, mkt_back:numeric, mkt_lay:numeric, stake:numeric, status:text, fill_ts:timestamp with time zone, fill_price:numeric, fill_kind:text, won:integer, pnl:numeric, settled_ts:timestamp with time zone, start_ts:timestamp with time zone, version:text, exchange:text, bf_market_id:text
small_bites_paper (1763 rows): id:integer, cell:text, market_id:text, sel_id:text, sport:text, mkt:text, liq:text, side:text, k:integer, h:integer, entry_min:timestamp with time zone, entry_px:numeric, mv_ticks:numeric, exit_min:timestamp with time zone, exit_px:numeric, status:text, pnl:numeric, created:timestamp with time zone
coherence_paper (23 rows): market_id:text, sel_id:bigint, cell:text, side:text, event_name:text, start_ts:timestamp with time zone, placed_ts:timestamp with time zone, price:numeric, size_avail:numeric, fair:numeric, edge:numeric, rate_h:numeric, rate_a:numeric, status:text, won:boolean, pnl:numeric
v3_paper (0 rows): market_id:text, rule:text, event_name:text, start_ts:timestamp with time zone, side:text, price:numeric, fair:numeric, edge:numeric, home_goals:integer, away_goals:integer, won:boolean, pnl:numeric, settled_at:timestamp with time zone
v3_snap (27 rows): market_id:text, sel_id:bigint, runner:text, event_name:text, country:text, competition:text, start_ts:timestamp with time zone, snap_ts:timestamp with time zone, secs_to_off:integer, back_px:numeric, back_sz:numeric, lay_px:numeric, lay_sz:numeric, ltp:numeric, total_matched:numeric
fair_price_passed (20 rows): sport:text, market_type:text, band_lo:numeric, band_hi:numeric, side:text, fair_factor:numeric, n_is:integer, n_oos:integer, edge_is:numeric, edge_oos:numeric, source:text, passed_at:timestamp with time zone
fair_price_blocked (6 rows): sport:text, market_type:text, band_lo:numeric, band_hi:numeric, side:text, blocked_at:timestamp with time zone, why:text
goal_alerts (1301 rows): id:bigint, sent_at:timestamp with time zone, watchlist_id:bigint, strategy_id:text, alert_type:text, severity:text, fixture:text, minute:integer, score:text, action:text, target_price_min:numeric, target_price_max:numeric, stake_gbp:numeric, stop_loss_minute:integer, green_up_target:numeric, p_success:numeric, expected_value:numeric, full_text:text, user_action_taken:boolean, settled:boolean, settled_at:timestamp with time zone, ft_score:text, ft_total:integer, outcome:text, pnl_paper:numeric, real_price:numeric, real_lay_price:numeric, real_price_ts:timestamp with time zone, real_event:text
goal_live_predictions (2348044 rows): id:bigint, captured_at:timestamp with time zone, watchlist_id:bigint, minute:integer, score_home:integer, score_away:integer, xg_home:numeric, xg_away:numeric, p_goal_next_5:numeric, p_goal_next_10:numeric, p_goal_next_15:numeric, p_goal_rest_of_match:numeric, p_home_scores_next:numeric, p_away_scores_next:numeric, alert_sent:boolean, alert_text:text, fav_price:numeric, under25_price:numeric, signal_direction:text, strategy_signals:jsonb, fixture_id:bigint, settled:boolean, goal_within_5:boolean, goal_within_10:boolean, goal_within_15:boolean, next_goal_minute:integer, home_sot:integer, away_sot:integer, home_da:integer, away_da:integer, home_red:integer, away_red:integer, stats_json:jsonb
paper-ish tables: ['fin_paper_positions', 'fin_paper_daily', 'preoff_scalp_paper', 'paper_ledger', 'bookie_paper', 'paper_settlements', 'ht_family_v1', 'ltd_inplay_paper', 'cs_trade_paper', 'cs_q_paper', 'late_over_paper', 'clv_paper', 'paper_trades', 'tennis_dog_paper', 'racing_swing_paper', 'cs_late_paper', 't2_paper', 'tennis_lay_paper', 'cs_qgreen_paper', 'tb_paper_trades', 'sport_paper_trades', 'racing_mm_paper', 'xg_paper', 'cricket_fav_paper', 'daily_paper_pnl', 'inplay_paper', 'cs_dutch_paper', 's6_paper', 'racing_bsp_paper', 's9_paper', 'small_bites_paper', 'v3_paper', 'coherence_paper']
small_bites sample: [(3, 'STEAM_FOLLOW k5 H10', '1.265636087', '47973', 'football', 'OU25', '<5k', 'back', 5, 10, datetime.datetime(2026, 11, 17, 10, 55, tzinfo=datetime.timezone.utc), Decimal('3.05'), Decimal('-5.0'), datetime.datetime(2026, 11, 17, 11, 5, tzinfo=datetime.timezone.utc), Decimal('3.45'), 'closed', Decimal('-0.2319'), datetime.datetime(2026, 11, 17, 10, 56, 2, 764754, tzinfo=datetime.timezone.utc)), (4, 'STEAM_FOLLOW k2 H10', '1.265636087', '47973', 'football', 'OU25', '<5k', 'back', 2, 10, datetime.datetime(2026, 11, 17, 10, 58, tzinfo=datetime.timezone.utc), Decimal('3.1'), Decimal('-2.5'), datetime.datetime(2026, 11, 17, 11, 8, tzinfo=datetime.timezone.utc), Decimal('1.91'), 'closed', Decimal('1.2212'), datetime.datetime(2026, 11, 17, 10, 59, 3, 13594, tzinfo=datetime.timezone.utc))]
bookie sample: [(992894, datetime.datetime(2026, 11, 19, 5, 29, 1, 993269, tzinfo=datetime.timezone.utc), '1.265691365', 'Mornington (AUS) 19th Nov', 'WIN', '98959951', 'LAY', Decimal('1.98'), Decimal('2.085'), Decimal('1.97'), Decimal('1.98'), Decimal('2.0'), 'settled', datetime.datetime(2026, 11, 19, 5, 29, 1, 993269, tzinfo=datetime.timezone.utc), Decimal('1.98'), 'taker', 0, Decimal('1.96'), datetime.datetime(2026, 11, 19, 5, 33, 7, 992319, tzinfo=datetime.timezone.utc), datetime.datetime(2026, 11, 19, 5, 30, tzinfo=datetime.timezone.utc), 'v2.2', 'betfair', '1.265691365')]
```
