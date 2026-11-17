# Goal signal and post-goal fade — 2026-11-17 06:46 UTC

## How the Friday email counts them (friday_email.py, queries only)
```
4:RESTORE='2026-11-13 13:52+00'   # goal tables restored (job 557); alerts before this are the old engine's
29:    fade=q("select count(*), coalesce(sum(pnl),0), coalesce(sum(stake),0), min(ts), max(ts) from desk_calls where line='FADE' and status='closed'")
30:    if fade and fade[0][0]:
31:        n,pnl,stk,t0,t1=fade[0]; days=max(1.0,(t1-t0).total_seconds()/86400); per100=float(pnl)/float(stk)*100
36:            "This week to close the gap: the fair-price engine runs on every sport Sunday 01:00 and every cell that passes both halves goes onto forward paper from Monday; the bot and the fade keep counting towards 100.")
43:       dict(name="the post-goal fade (lay the team that just scored two minutes after the goal, back it again ten minutes later)",
60:# 1. the fade's whole forward sample, from the scoreboard (same rule: lay 120 s after the goal, out 10 min later)
61:fade=""
66:        if nm.startswith('H0 fade MO lay +120s exit +10m'):
68:            fade+=f" {lab}: {v.get('n')} goals, £{float(v.get('mean_per10') or 0)*10:+.2f} per £100;"
69:except Exception as e: fade=" (scoreboard unreadable)"
74:# 2. goal signal: only alerts after the restore
75:ga=q("select sent_at, stake_gbp, settled, pnl_paper from goal_alerts where sent_at>%s and coalesce(alert_type,'')<>'BOOT_TEST' order by sent_at",(RESTORE,))
79:    g4=f"Goal signal alerts since the monitor came back on 13 November: {len(ga)} sent ({lst}); {len(sc)} scored so far, {won} won, £{pnl:+.2f} on paper at those stakes."
80:else: g4="Goal signal alerts since the monitor came back on 13 November: none sent. The 25 alerts before that date were the old engine's and are not counted."
84:   "Count towards 100 settled paper bets per rule: "+"; ".join(counts)+f". The fade's whole forward sample on the server, same rule, real ladder, 2% commission:{fade} the 60 desk calls are a subset ({leagues}).",
```
## goal_alert_mail.py (what it reads)
```
```
## Tables
```
alert_throttle: 0 rows; last_sent_at max None
goal_advisories: 424 rows; sent_at max 2026-11-15 00:19:35.396555+00:00
goal_alerts: 1301 rows; sent_at max 2026-11-07 19:04:00.562343+00:00
goal_alerts_real: 108 rows; sent_at max 2026-11-02 23:53:08.985662+00:00
goal_backfill_predictions: 71065 rows; created_at max 2026-07-28 05:01:59.973949+00:00
goal_backtest_patterns: 28 rows; created_at max 2026-06-23 07:34:04.576366+00:00
goal_backtest_patterns_cs: 218 rows; created_at max 2026-06-23 08:04:17.656292+00:00
goal_backtest_results: 2936 rows; created_at max 2026-06-23 07:34:04.815729+00:00
goal_capture: 33087 rows; mt max 2026-06-29 02:04:05.990000+00:00
goal_engine_learning_log: 10 rows; predicted_at max 2026-05-24 22:00:37.907615+00:00
goal_events: 113281 rows; goal_at max 2026-11-08 03:29:03.811970+00:00
goal_league_alias: 29 rows; 
goal_league_baselines: 22 rows; last_refreshed max 2026-06-01 23:22:26.651354+00:00
goal_league_calibration: 198 rows; fitted_at max 2026-09-04 16:43:31.131355+00:00
goal_live_predictions: 2335863 rows; captured_at max 2026-11-17 06:45:30.088477+00:00
goal_match_stats: 1260 rows; captured_at max 2026-11-08 21:18:38.855555+00:00
goal_poisson: 2480 rows; sent_at max 2026-11-15 00:19:35.440579+00:00
goal_prematch_prior: 27 rows; fetched_at max 2026-08-10 19:01:17.315413+00:00
goal_signal_watchlist: 71 rows; generated_at max 2026-05-20 16:58:51.929533+00:00
goal_stats_live: 25551 rows; captured_at max 2026-11-17 06:43:56.747112+00:00
goal_strategies: 18 rows; 
goal_team_alias: 28 rows; created_at max 2026-05-22 13:30:37.113534+00:00
goal_team_baselines: 2455 rows; last_refreshed max 2026-06-01 23:22:26.651354+00:00
goal_team_baselines_v2: 633 rows; last_refreshed max 2026-11-09 03:06:01.110154+00:00
goal_timeline: 3325903 rows; captured_at max 2026-11-17 06:45:29.979919+00:00
goal_xg_predictions: 3593 rows; predicted_at max 2026-11-08 21:18:51.315960+00:00
hist_goals: 39899 rows; 
liq_goal_depth: 768820 rows; goal_ts max 2026-11-17 02:54:45.291448+00:00
m1_alerts: 9162 rows; goal_ts max 2026-11-09 02:52:14.672313+00:00
m1_variants: 174 rows; goal_ts max 2026-11-08 21:27:37.262220+00:00
monitor_alerts: 6 rows; last_fired_at max 2026-10-04 15:13:07.716337+00:00
tb_alerts: 0 rows; sent_at max None
watchdog_alert_state: 10 rows; last_alerted_at max 2026-05-23 17:47:02.162580+00:00
```
