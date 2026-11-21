# What is still on Railway - 2026-11-21 16:16 UTC

## Can this server control Railway itself?
- railway command installed: no
- a Railway login or token on this server: 

## What on THIS server still talks to the Railway database (host names only)
- creds.pg_local() points at host: 127.0.0.1
- creds.pg_railway() points at host: 127.0.0.1
- creds.pg_railway_remote() points at host: 127.0.0.1
- files on this server that name a Railway address: 60
  - /root/pe-scan/scan.py
  - /root/pe-scan/poisson.py
  - /root/pe-scan/bf_hist_load_v2.py
  - /root/pe-scan/backtest.py
  - /root/pe-scan/bf_hist_load.py
  - /root/pe-scan/hist_scan.py
  - /root/pe-brain/repo/scripts/racing_pre_race_scanner.py
  - /root/pe-brain/repo/scripts/understat_import.py
  - /root/pe-brain/repo/server/server_price_logger.py
  - /root/pe-brain/repo/brain/active_positions.py
  - /root/pe-brain/repo/brain/cs_scanner.py
  - /root/pe-brain/repo/brain/stats_collector.py
  - /root/pe-brain/repo/brain/test_position_monitor.py
  - /root/pe-brain/repo/brain/pattern_predictor.py
  - /root/pe-brain/repo/brain/morning_review.py
  - /root/pe-brain/repo/brain/position_monitor.py
  - /root/pe-brain/repo/brain/position_monitor_service.py
  - /root/pe-brain/repo/brain/replay_copilot.py
  - /root/pe-brain/repo/brain/monitor_ht.py
  - /root/pe-brain/repo/brain/tonight_preview.py
  - /root/pe-brain/repo/brain/xg_model.py
  - /root/pe-brain/repo/brain/backfill_replay.py
  - /root/pe-brain/repo/brain/goal_signal_service.py
  - /root/pe-brain/repo/brain/copilot_app.py
  - /root/pe-brain/repo/brain/startup_check.py
  - /root/pe-brain/repo/brain/historical_backtest.py
  - /root/pe-brain/repo/brain/team_stats_puller.py
  - /root/pe-brain/repo/brain/match_stats_puller.py
  - /root/pe-brain/repo/brain/hist_goals_backfill.py
  - /root/pe-brain/repo/brain/railway.json
  - /root/pe-brain/repo/brain/racing_scanner.py
  - /root/pe-brain/repo/brain/betfair_probe.py
  - /root/pe-brain/repo/brain/racing_morning_brief.py
  - /root/pe-brain/repo/brain/baseline_refresher.py
  - /root/pe-brain/repo/brain/betfair_probe_v3.py
  - /root/pe-brain/repo/brain/calibrate_goal_model.py
  - /root/pe-brain/repo/brain/pattern_matcher.py
  - /root/pe-brain/repo/brain/betfair_probe_v2.py
  - /root/pe-brain/repo/brain/full_audit.py
  - /root/pe-brain/repo/brain/season_phase_backfill.py

## Is the old Railway database still being written, and by what
- ways to reach the OLD Railway database from creds: ['pg_railway_remote']
  busiest tables (rows ever inserted): [('bf_hist_other', 46434647), ('stream_ticks', 28740142), ('liq_sample', 22129119), ('bf_price_log', 21081468), ('liq_sample', 13615544), ('xx_tape', 11432574), ('book_snap', 11047040), ('bf_racing_log', 10772118), ('ip_tape', 9375486), ('grid_agg', 9122074), ('bf_tennis_log', 7474015), ('bf_hist_result', 3393453), ('goal_timeline', 3222976), ('goal_live_predictions', 2263999), ('racing_tape', 1020382)]
  connected right now (program, remote?, state, count): [('batch_queue', True, 'idle', 10), ('', True, 'idle', 9), ('batch_queue', True, 'active', 3), ('', True, 'active', 1)]
  size: 142 GB

## Earlier findings on record
- railway_672.md
- railway_673.md
- railway_674.md
- railway_709.md
