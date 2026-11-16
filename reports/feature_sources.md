<stdin>:7: DeprecationWarning: datetime.datetime.utcnow() is deprecated and scheduled for removal in a future version. Use timezone-aware objects to represent datetimes in UTC: datetime.datetime.now(datetime.UTC).
# Feature sources for the fair-price model — 2026-11-16 16:44 UTC

- **bf_hist_result** (1997 MB, 10106770 rows): sport, market_id, event_id, market_type, sel, status, settled_time, market_status
- **bf_tennis_log** (1760 MB, 6718240 rows): id, market_id, event_name, competition, market_start, selection_id, player, back_price, lay_price, last_traded, total_matched, inplay, captured_at, back_size, lay_size
- **goal_timeline** (584 MB, 3321851 rows): id, captured_at, fixture_id, league_id, league_name, home_team, away_team, minute, score_home, score_away, status
- **goal_live_predictions** (547 MB, 2333180 rows): id, captured_at, watchlist_id, minute, score_home, score_away, xg_home, xg_away, p_goal_next_5, p_goal_next_10, p_goal_next_15, p_goal_rest_of_match, p_home_scores_next, p_away_scores_next, alert_sent, alert_text, fav_price, under25_price, signal_direction, strategy_signals, fixture_id, settled, goal_within_5, goal_within_10, goal_within_15, next_goal_minute, home_sot, away_sot, home_da, away_da, home_red, away_red, stats_json
- **bookie_paper** (437 MB, 992813 rows): id, ts, market_id, event_name, mkt, sel, side, price, fair, mkt_back, mkt_lay, stake, status, fill_ts, fill_price, fill_kind, won, pnl, settled_ts, start_ts, version, exchange, bf_market_id
- **fd_matches** (222 MB, 149555 rows): div, season, date, home, away, fthg, ftag, hthg, htag, hs, as_, hst, ast, hc, ac, hy, ay, hr, ar, b365h, b365d, b365a, psh, psd, psa, psch, pscd, psca, b365o25, b365u25, p_o25, p_u25, ahh, b365ahh, b365aha, raw
- **liq_goal_depth** (172 MB, 766542 rows): id, market_id, event_name, competition, mkt, sel, goal_ts, offset_s, ts, pre_ltp, ltp, back_px, back_sz, lay_px, lay_sz, back3_sz, lay3_sz, total_matched, matched_since_goal, minute
- **af_events** (146 MB, 1504779 rows): fixture_id, minute, extra, team, is_home, type, detail, player
- **runners** (129 MB, 324102 rows): id, race_date, track, going, race_type, distance, race_class, horse, betfair_sp, ip_min_price, place, runners, stall, created_at, race_name, race_time, jockey, trainer, jockey_id, trainer_id, or_rating, rpr, tsr, sire, dam
- **af_stats** (108 MB, 195454 rows): fixture_id, is_home, team, shots, sot, poss, corners, xg, raw
- **state_snap** (65 MB, 397265 rows): fixture_id, m, minute, hw, aw, league_id, goals_on, margin, goal_at
- **football_matches** (61 MB, 216418 rows): id, season, league_code, league, date, home_team, away_team, fthg, ftag, ftr, hthg, htag, htr, hs, as_, hst, ast, referee, b365h, b365d, b365a, bwh, bwd, bwa, maxh, maxd, maxa, avgh, avgd, avga, bfeh, bfed, bfea, psh, psd, psa, over25, under25, max_over25, max_under25 ...
- **af_player_stats** (56 MB, 323230 rows): fixture_id, team, player_id, player, minutes, shots, shots_on, goals, assists, position, rating
- **racing_bsp** (51 MB, 256792 rows): country, market, event_id, menu_hint, event_name, event_dt, selection_id, selection_name, win_lose, bsp, ppwap, morningwap, ppmax, ppmin, ipmax, ipmin, morning_vol, pp_vol, ip_vol
- **racing_form_features** (45 MB, 203365 rows): race_date, event_id, selection_id, horse, course, bsp, won, runs_before, won_last, days_since_last, prev_bsp, career_wins, career_runs, career_strike, avg_prev_bsp, best_prev_bsp, runs_at_course, wins_at_course, bsp_vs_prev, field_size, built_at
- **fts_advanced_results** (45 MB, 47927 rows): match_date, ko_time, season, competition, home_team, away_team, iso3, goal_ratio_all, goal_ratio_ha, home_rank, away_rank, hf_gp, hf_w, hf_d, hf_l, hf_pts, hf_ave, af_gp, af_w, af_d, af_l, af_pts, af_ave, home_colour, away_colour, cs_top1, cs_top2, cs_top3, p6_hxg45, p6_axg45, p6_fh_xg, p6_fh_o05, p6_hxg, p6_axg, p6_match_xg, p6_h_supremacy, p6_home, p6_draw, p6_away, p6_o15 ...
- **tennis_results_2026** (27 MB, 66310 rows): id, tour, tourney_id, tourney_name, surface, draw_size, tourney_level, indoor, tourney_date, match_num, winner_id, winner_name, winner_norm, winner_hand, winner_ioc, winner_age, winner_rank, loser_id, loser_name, loser_norm, loser_hand, loser_ioc, loser_age, loser_rank, score, best_of, round, minutes, w_ace, w_df, w_svpt, w_1stin, w_1stwon, w_2ndwon, w_svgms, w_bpsaved, w_bpfaced, l_ace, l_df, l_svpt ...
- **fts_newmodel** (26 MB, 47979 rows): match_dt, league, home, away, xg_h, xg_a, xg_tot, supremacy, fh_xg_h, fh_xg_a, fh_xg_tot, goals_rank_lg, goals_rank_all, fh_rank_lg, fh_rank_all, mismatch_rank, fair_h, fair_d, fair_a, fair_o15, fair_o25, fair_o35, fair_o45, fair_btts, fair_fh05, fair_fh15, wm_h1, wm_h2, wm_a1, wm_a2, p_00at25_1hgoal, p_goalby10_2nd, p_00at20_goal, p_home_first, p_goal_after70, p_goal_after80, tier, ab_agree, games, mo_vol ...
- **racecards_today** (26 MB, 72215 rows): id, race_date, track, race_time, race_name, race_class, distance, going, runners_count, country, cloth_number, draw_number, horse, age, weight, jockey, trainer, or_rating, best_odds_fractional, best_odds_decimal, bookmaker, fetched_at
- **understat_shots** (21 MB, 87165 rows): id, understat_id, shot_id, minute, team_side, player, xg, result, situation, shot_type, collected_at, x, y, last_action, h_goals, a_goals
- **af_fixtures** (21 MB, 109151 rows): fixture_id, league_id, league, season, kickoff, home, away, hg, ag, ht_hg, ht_ag, status, events_done, stats_done, referee
- **greyhound_racecards_today** (19 MB, 51318 rows): id, race_date, track, race_time, race_id, race_class, distance, prizes, race_stage, trap_number, cloth_number, greyhound, colour, age, birth_date, sex, dam, sire, owner, trainer, form_summary, best_run_time, finish_position, run_status, reserve, fetched_at
- **match_events** (16 MB, 76444 rows): fixture_id, match_date, league, home_team, away_team, minute, extra, team_side, type, detail, player
- **espn_stats** (15 MB, 62905 rows): ts, espn_id, league, event_name, market_id, clock, minute, period, hs, as, h_shots, a_shots, h_sot, a_sot, h_poss, a_poss, h_corn, a_corn, h_fouls, a_fouls
- **tb_match_events** (15 MB, 46334 rows): id, captured_at, sport, fixture_id, tennis_match_id, cricket_match_id, golf_tour_id, event_type, minute, actor, score_a, score_b, score_text, odds_home, odds_draw, odds_away, odds_o25, market_volume, extra_jsonb
- **goal_events** (14 MB, 113281 rows): fixture_id, goal_at, goals_before, goals_after, minute
- **goal_backfill_predictions** (14 MB, 71065 rows): id, created_at, fixture_id, league_id, league_name, home_team, away_team, minute, score_home, score_away, home_sot, away_sot, xg_home, xg_away, p_goal_next_5, p_goal_next_10, p_goal_next_15, intensity, next_goal_minute, goal_within_5, goal_within_10, goal_within_15, source
- **fts_matches** (13 MB, 22624 rows): league_type, season, match_date, ko_time, league, home_team, away_team, h_gp, h_w, h_d, h_l, h_pts, h_ave, a_gp, a_w, a_d, a_l, a_pts, a_ave, h_form, a_form, early_home, early_draw, early_away, book_pct, px2_home, px2_draw, px2_away, mv_home, mv_draw, mv_away, c31, h_rating, a_rating, rating_diff, fair_home, fair_draw, fair_away, edge_home, edge_draw ...
- **fts_ultimate** (13 MB, 22624 rows): c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15, c16, c17, c18, c19, c20, c21, c22, c23, c24, c25, c26, c27, c28, c29, c30, c31, c32, c33, c34, c35, c36, c37, c38, c39 ...
- **wta_matches** (11 MB, 58484 rows): id, year, tournament, date, surface, round, best_of, series, winner, loser, wrank, lrank, w1, l1, w2, l2, w3, l3, wsets, lsets, b365w, b365l, maxw, maxl, avgw, avgl
- **runner_snapshots** (10 MB, 48878 rows): id, snapshot_at, market_id, market_start_time, track, race_name, selection_id, horse, stall, best_back, best_lay, last_traded, total_matched, inplay, market_status, minutes_to_off
- **ip_stats** (8 MB, 39623 rows): ts, sofa_id, event_name, league, market_id, minute, hs, as, h_xg, a_xg, h_shots, a_shots, h_sot, a_sot, h_poss, a_poss, h_dang, a_dang, h_corn, a_corn
- **goal_stats_live** (6 MB, 25135 rows): id, fixture_id, league_id, captured_at, minute, score_home, score_away, home_sot, away_sot, home_shots, away_shots, home_da, away_da, home_corners, away_corners, home_poss, away_poss
- **hist_goals** (6 MB, 39899 rows): fixture_id, minute, extra, team, side, score_home, score_away
- **ipl_matches** (4 MB, 21458 rows): id, match_id, season, date, team1, team2, venue, toss_winner, toss_decision, winner, win_by_runs, win_by_wickets, player_of_match, innings1_total, innings1_wickets, innings2_total, innings2_wickets, pp1_runs, pp1_wickets, pp2_runs, pp2_wickets, death1_runs, death1_wickets, death2_runs, death2_wickets
- **racing_results** (4 MB, 22956 rows): market_id, selection_id, runner, venue, market_name, market_start, won, bsp, settled_at
- **liq_runners** (4 MB, 33073 rows): market_id, sel_id, name
- **finder_rresults** (4 MB, 22309 rows): market_id, selection_id, runner, venue, market_name, market_start, won, bsp, settled_at
- **goal_capture** (4 MB, 33087 rows): run_date, event_id, country, mt, gm, goal_no, scorer, entry, drop, b5, b10, b15, l5, l10, l15
- **af_shots** (4 MB, 54560 rows): understat_id, minute, team_side, xg, result
- **af_lineups** (4 MB, 37171 rows): fixture_id, team, is_home, formation, player_id, player, pos, grid, starter
- **tennis_matches_sackmann** (3 MB, 7998 rows): id, tour, tourney_id, tourney_name, surface, draw_size, tourney_level, tourney_date, match_num, winner_id, winner_seed, winner_entry, winner_name, winner_hand, winner_ht, winner_ioc, winner_age, winner_rank, winner_rank_points, loser_id, loser_seed, loser_entry, loser_name, loser_hand, loser_ht, loser_ioc, loser_age, loser_rank, loser_rank_points, score, best_of, round, minutes, w_ace, w_df, w_svpt, w_1stin, w_1stwon, w_2ndwon, w_svgms ...
- **match_shots** (3 MB, 21462 rows): id, date, season, league, league_code, home_team, away_team, home_goals, away_goals, home_shots, away_shots, home_sot, away_sot, home_corners, away_corners, home_fouls, away_fouls, home_xg_proxy, away_xg_proxy
- **tennis_matches** (3 MB, 13476 rows): id, tour, year, tournament, date, surface, round, best_of, series, winner, loser, wrank, lrank, w1, l1, w2, l2, w3, l3, w4, l4, w5, l5, wsets, lsets, b365w, b365l, psw, psl, maxw, maxl, avgw, avgl, score, tournament_level
- **tb_fixtures** (3 MB, 9456 rows): id, external_id, source, sport, league, league_tier, season, event_date, kickoff_utc, home_team, away_team, venue, referee, status, pulled_at
- **job_results** (3 MB, 964 rows): job, started, finished, status, exit_code, log
- **cricket_matches** (2 MB, 7862 rows): id, match_date, competition, match_format, team1, team2, winner, venue, city, toss_winner, toss_decision, season, source, created_at, team1_price, team2_price
- **hist_fixtures** (2 MB, 15047 rows): fixture_id, league_id, league_name, season, kickoff, home_team, away_team, ft_home, ft_away, ht_home, ht_away, status, events_fetched
- **race_fingerprints** (2 MB, 5069 rows): fingerprint_id, captured_at, market_id, course, country, race_time_utc, market_name, race_class, race_type, distance_furlongs, race_subtype, field_size, field_size_band, day_of_week, hour_of_day, time_to_race_min, selection_id, runner_name, stall_draw, last_price, favourite_price, second_fav_price, is_favourite, is_2nd_fav, rank_in_market, price_band, settled, won, bsp, settled_at, is_qualifier, matched_strategies, trainer, jockey, horse_age, captured_price_open
- **goal_xg_predictions** (2 MB, 3593 rows): id, predicted_at, fixture_id, league_id, league_name, home_team, away_team, ht_score, ht_total, home_baseline_gf, away_baseline_gf, home_baseline_ga, away_baseline_ga, pre_match_expected_total, h1_combined_shots, h1_combined_shots_on_target, h1_combined_xg, h1_dominance_index, remaining_half_lambda, p_o15, p_o25, p_o35, p_u25, p_u35, best_market, best_p, best_fair_price, reasoning, settled, settled_at, ft_score, ft_total, outcome, pnl_paper, prediction_type, real_back_price, real_price_source, real_price_captured_at, real_pnl, mkt_raw_odds ...
- **event_results** (2 MB, 12683 rows): event_id, fthg, ftag, hthg, htag, hs, as_, hst, ast, source, score
- **state_scan_v1** (2 MB, 12991 rows): season, mkt, sel, minute, score, prematch, tier, n, implied, actual, back_per100, lay_per100
- **matches** (2 MB, 8758 rows): id, fd_id, date, season, league, league_code, home_team, away_team, home_id, away_id, referee, status, home_goals, away_goals, ht_home, ht_away, home_odds, draw_odds, away_odds, matchday, stage
- **af_price_map** (1 MB, 12288 rows): understat_id, event_id, score, league
- **goal_poisson** (1 MB, 2480 rows): id, sent_at, fixture, league, league_id, ht_score, ht_total, remaining_lambda, p_o15, p_o25, p_o35, p_o45, p_o55, p_u25, p_u35, p_u45, best_market, best_p, best_fair_price, reasoning, settled, settled_at, ft_score, ft_total, outcome, pnl_paper
- **backtest_results** (1 MB, 10472 rows): strategy, season, league, event_id, minute, entry, exit_px, goal_in, net
- **betfair_probe_results** (1 MB, 1170 rows): id, probed_at, endpoint, url, status, verdict, body_snippet, elapsed_s, error
- **tennis_lay_paper** (1 MB, 3772 rows): id, play_date, market_id, selection_id, event_name, competition, player, entry_at, lay_at, green_target, stop_level, outcome, exit_price, mins_held, pnl_per_1_liability, recorded_at, surface, surface_form, form_matches, best_of, pnl_hedged_per_stake
- **state_scan_v2** (1 MB, 8353 rows): season, mkt, sel, minute, score, prematch, tier, n, implied, actual, back_per100, lay_per100
- **state_scan_v4** (1 MB, 7305 rows): season, mkt, sel, minute, score, prematch, tier, n, implied, actual, back_per100, lay_per100, t_back, t_lay
- **state_scan_v3** (1 MB, 7305 rows): season, mkt, sel, minute, score, prematch, tier, n, implied, actual, back_per100, lay_per100, t_back, t_lay
- **events_backfill_state** (1 MB, 8861 rows): fixture_id, match_date, home_team, away_team, league, done, n_events, fetched
- **racing_bsp_files** (1 MB, 7053 rows): fname, rows, loaded_at
- **matches_fdco** (1 MB, 7136 rows): id, date, season, league, home_team, away_team, fthg, ftag, hthg, htag, referee, b365h, b365d, b365a, o25, u25, result
- **strategy_results** (1 MB, 3852 rows): run_date, sport, strategy, band, n, n1, per100_1, t1, n2, per100_2, t2, per100_all, survivor, months
- **tennis_dog_paper** (1 MB, 3286 rows): id, ts, market_id, event_name, competition, start_time, sel_id, sel_name, back_px, lay_px, band, total_matched, result, pnl_per_10, settled_at
- **prematch_bands_v1** (1 MB, 9103 rows): code, league_id, league, band, season, n, s, ss
- **goal_backtest_results** (1 MB, 2936 rows): id, run_id, league_id, league_name, season, fixture_id, fixture_date, home_team, away_team, ht_home, ht_away, ft_home, ft_away, ht_total, ft_total, ht_pattern, pattern_n_samples, predicted_market, predicted_prob, fair_price, outcome, pnl_paper, stake, created_at
- **af_player_stats_done** (1 MB, 7914 rows): fixture_id, n, fetched_at
- **match_shots_rich** (1 MB, 2173 rows): id, source, league, season, match_date, home_team, away_team, home_goals, away_goals, home_xg, away_xg, notes, ingested_at
- **understat_matches** (1 MB, 3476 rows): understat_id, league, season, match_date, home_team, away_team, home_goals, away_goals, home_xg, away_xg, forecast_w, forecast_d, forecast_l, collected_at
- **season_phase_matches** (1 MB, 2239 rows): fixture_id, created_at, updated_at, league_id, league_name, season, round, kickoff, match_date, month, phase, midweek, home_id, home_team, away_id, away_team, ft_home, ft_away, home_shots, away_shots, home_sot, away_sot, home_xg, away_xg, stats_pulled, stats_attempts
- **goal_team_baselines** (1 MB, 2455 rows): team, league, venue, n_games, goals_for_avg, goals_against_avg, pct_over_25, pct_btts, attack_strength, defence_strength, last_refreshed
- **fts_live** (1 MB, 1903 rows): id, match_date, ko_time, league, home_team, away_team, event_id, early_home, early_draw, early_away, early_home_ly, early_draw_ly, early_away_ly, early_u15, early_o15, early_u25, early_o25, early_u35, early_o35, cl_home, cl_draw, cl_away, cl_o25, cl_u25, ft_home, ft_away, ht_home, ht_away, captured_at, settled_at
- **goal_alerts** (0 MB, 1301 rows): id, sent_at, watchlist_id, strategy_id, alert_type, severity, fixture, minute, score, action, target_price_min, target_price_max, stake_gbp, stop_loss_minute, green_up_target, p_success, expected_value, full_text, user_action_taken, settled, settled_at, ft_score, ft_total, outcome, pnl_paper, real_price, real_lay_price, real_price_ts, real_event
- **understat_seen** (0 MB, 5001 rows): understat_id, league, season, ok
- **v4_fin_results** (0 MB, 3564 rows): run_date, config, family, asset, cls, is_sharpe, oos_sharpe, oos_t, oos_cagr, oos_maxdd, years_pos, trades_oos
- **v4_sport_results** (0 MB, 3124 rows): run_date, trig, role, dir, exit, band, n, mean, t, h1, h2, pos, survivor
- **goal_match_stats** (0 MB, 1260 rows): fixture_id, captured_at, capture_point, league_id, home_team, away_team, ht_score, ft_score, minute, home_shots_total, away_shots_total, home_shots_on_target, away_shots_on_target, home_shots_off_target, away_shots_off_target, home_shots_inside_box, away_shots_inside_box, home_possession_pct, away_possession_pct, home_corners, away_corners, home_xg, away_xg, home_attacks, away_attacks, home_dangerous_attacks, away_dangerous_attacks, combined_xg_proxy
- **v4_sport_results_sub** (0 MB, 2984 rows): run_date, trig, role, dir, exit, band, n, mean, t, h1, h2, pos, survivor
- **understat_shots_done** (0 MB, 3476 rows): understat_id, n, status, ts
- **v4_stats_minute** (0 MB, 2999 rows): run_date, fam, sel, dir, exit, band, minute, n, mean, t
- **xg_price_map** (0 MB, 3446 rows): understat_id, event_id, score
- **goal_advisories** (0 MB, 424 rows): id, sent_at, advisory_id, fixture, league, league_id, ht_score, ht_total, suggested_action, target_market, target_price_min, target_price_max, reasoning, settled, settled_at, ft_score, ft_total, outcome, pnl_paper, promotion_eligible
- **goal_team_baselines_v2** (0 MB, 633 rows): team_id, team_name, league_id, league_name, season, games_played, games_played_home, games_played_away, gf_per_game_total, gf_per_game_home, gf_per_game_away, ga_per_game_total, ga_per_game_home, ga_per_game_away, xg_for_per_game, xg_against_per_game, form, clean_sheet_pct, failed_to_score_pct, last_refreshed
- **team_profiles** (0 MB, 927 rows): team, league, matches_played, avg_goals_per_match, avg_shots, avg_sot, pct_over_25, pct_no_goal, pct_under_15, game_style, last_updated
- **fair_price_results** (0 MB, 1612 rows): level, model, side, sel, m, league, n, per10, t, h1, h2, n2
- **v4_stats_results** (0 MB, 846 rows): run_date, fam, sel, dir, exit, band, n, mean, t, h1, h2, pos, survivor
- **racing_bsp_paper** (0 MB, 450 rows): id, race_date, event_id, selection_id, course, race, runner, morningwap, ppwap, drift_pct, bsp, pptradedvol, won, pnl_1, settled_at
- **elo_ratings** (0 MB, 1198 rows): id, calculated_at, league, team, season, elo, games_played
- **v4_af_minute** (0 MB, 1201 rows): run_date, fam, sel, dir, exit, band, minute, n, mean, t
- **goal_signal_watchlist** (0 MB, 71 rows): id, generated_at, fixture_date, kickoff_utc, league, home_team, away_team, referee, expected_home_goals, expected_away_goals, expected_total, p_over_25, p_over_15, p_btts, p_ht_0_0, p_ht_1_1, p_ht_1_0_home, p_ht_2_0_home, home_price_pre, draw_price_pre, away_price_pre, over25_price_pre, market_implied_total, edge_pct, qualifying_strategies, tier, primary_strategy_id, action_summary, live_status, fh_goals_home, fh_goals_away, ht_score, ft_score, trigger_fired_at, notes
- **tennis_orders** (0 MB, 229 rows): id, placed_at, action, market_id, selection_id, event_name, competition, player, side, stake, requested_price, matched_price, matched_size, bet_id, status, reason, dry_run
- **af_lineups_done** (0 MB, 890 rows): fixture_id, n, loaded_at
- **goal_engine_learning_log** (0 MB, 10 rows): id, predicted_at, fixture_date, kickoff_utc, league, home_team, away_team, pred_expected_home_goals, pred_expected_away_goals, pred_expected_total, pred_p_over_25, pred_p_over_15, pred_p_btts, pred_p_ht_0_0, pred_p_ht_1_1, pred_confidence, pred_qualifying_strategies, pred_tier, actual_home_goals, actual_away_goals, actual_total, actual_ht_home, actual_ht_away, actual_over_25, actual_over_15, actual_btts, actual_ht_0_0, actual_ht_1_1, settled, settled_at, strategy_outcomes, total_goals_error, over25_correct, o25_brier_score
- **goal_backtest_patterns_cs** (0 MB, 218 rows): id, run_id, ht_pattern, ft_pattern, n_pattern_samples, ft_count, cs_probability, rank_at_ht, fair_back_price, created_at
- **fd_files** (0 MB, 420 rows): path, rows, loaded_at
- **hist_scan_results** (0 MB, 492 rows): hold, mkt, sel, side, goals_on, lead, phase, n, ret_pct, ret_2024, ret_2025, win_pct, goal_pct, t, verified
- **tb_prematch_features** (0 MB, 138 rows): fixture_id, snapshot_at, home_form_w, home_form_d, home_form_l, home_form_gf, home_form_ga, away_form_w, away_form_d, away_form_l, away_form_gf, away_form_ga, home_gpg_home, home_ga_home, away_gpg_away, away_ga_away, league_gpg_avg, league_o25_pct, home_elo, away_elo, elo_margin, h2h_n, h2h_avg_goals, h2h_btts_pct, h2h_o25_pct, ref_name, ref_gpg, ref_cards_per_game, bf_home_back, bf_home_lay, bf_draw_back, bf_draw_lay, bf_away_back, bf_away_lay, bf_o25_back, bf_o25_lay, bf_btts_back, bf_btts_lay, bf_total_matched, implied_home_pct ...
- **trainer_stats** (0 MB, 355 rows): id, trainer, runners, wins, top3, win_pct, top3_pct, avg_bsp, back_roi
- **xg_paper** (0 MB, 56 rows): id, rule, market_id, event_name, competition, entry_ts, minute, mkt, sel, lay_px, lay_sz, hs, as, h_xg, a_xg, goal_ts, exit_ts, exit_px, exit_reason, pnl_per_10
- **tennis_positions** (0 MB, 70 rows): id, opened_at, market_id, selection_id, event_name, competition, player, lay_price, stake, green_target, stop_level, entry_bet_id, exit_bet_id, closed_at, exit_price, outcome, pnl, dry_run
- **goal_alerts_real** (0 MB, 108 rows): alert_id, strategy_id, sent_at, fixture, event_name, sample_ts, back_px, lay_px, real_price, real_price_pre, in_band, won, pnl_real, pnl_real_pre, paper_per10, status
- **v4_af_results** (0 MB, 350 rows): run_date, fam, sel, dir, exit, band, n, mean, t, h1, h2, pos, survivor
- **jockey_stats** (0 MB, 302 rows): id, jockey, rides, wins, places, win_pct, place_pct, avg_bsp, back_roi
- **robustness_results** (0 MB, 239 rows): run_date, book, line, n, total, per_trade, p5, p50, p95, worst_dd, pct_positive, flag
- **tb_results** (0 MB, 125 rows): fixture_id, settled_at, ht_home, ht_away, ft_home, ft_away, total_goals, over_05, over_15, over_25, over_35, btts, result_1x2, home_shots, away_shots, home_shots_on_target, away_shots_on_target, home_corners, away_corners, home_xg, away_xg, home_goal_minutes, away_goal_minutes, extra_jsonb
- **goal_league_calibration** (0 MB, 198 rows): league_id, raw_p, calib_p, fitted_at
- **cricket_matches_today** (0 MB, 19 rows): id, series, series_id, event_id, event_name, short_name, description, match_type, match_date, start_time, venue, venue_city, venue_country, team_home, team_home_abbr, team_home_score, team_away, team_away_abbr, team_away_score, toss_winner, toss_decision, match_status, status_detail, winner_team, win_margin, fetched_at
- **xg_heartbeat** (0 MB, 1 rows): id, last_seen, candidates, with_xg, open_trades
- **bookie_heartbeat** (0 MB, 3 rows): id, last_seen, open_orders, fills
- **referee_stats** (0 MB, 225 rows): referee, referee, season, season, league, league, matches, matches, total_goals, total_goals, gpg, gpg, home_wins, home_wins, draws, draws, away_wins, away_wins, home_win_pct, home_win_pct, draw_pct, draw_pct, avg_cards, avg_cards
- **player_heartbeat** (0 MB, 1 rows): id, last_seen, live_markets, goals_seen
- **boring_results** (0 MB, 166 rows): level, pattern, fav, league, n, per10, t, goal_hit, h1, h2
- **boring_results_v3** (0 MB, 131 rows): level, pattern, fav, league, n, per10, t, goal_hit, h1, h2
- **goal_backtest_patterns** (0 MB, 28 rows): id, run_id, ht_pattern, n_samples, mean_total, p_u15, p_u25, p_u35, p_o15, p_o25, p_o35, created_at
- **boring_results_v2** (0 MB, 129 rows): level, pattern, fav, league, n, per10, t, goal_hit, h1, h2
- **summer_match_results** (0 MB, 2 rows): event_id, league, match_date, home_team, away_team, ft_home, ft_away, ht_home, ht_away, collected_at
- **af_pull_log** (0 MB, 68 rows): ts, note
- **daily_fixtures** (0 MB, 0 rows): id, pulled_at, event_date, sport, league, home_team, away_team, race_name, course, runners, kickoff_utc, home_price, draw_price, away_price, over25_price, btts_price, volume, elo_margin, extra_json
- **golf_pre_match_odds** (0 MB, 0 rows): id, captured_at, event_id, event_name, competition, market_id, market_type, market_name, market_start_time, selection_id, selection_name, best_back_price, best_back_size, best_lay_price, best_lay_size, last_traded_price, total_matched, minutes_to_start, is_pre_match, source
- **cricket_pre_match_odds** (0 MB, 0 rows): id, captured_at, event_id, event_name, competition, market_id, market_type, market_name, market_start_time, selection_id, selection_name, best_back_price, best_back_size, best_lay_price, best_lay_size, last_traded_price, total_matched, minutes_to_start, is_pre_match, source
- **tennis_pre_match_odds** (0 MB, 0 rows): id, captured_at, event_id, event_name, competition, market_id, market_type, market_name, market_start_time, selection_id, selection_name, best_back_price, best_back_size, best_lay_price, best_lay_size, last_traded_price, total_matched, minutes_to_start, is_pre_match, source
- **pe_backtest_results** (0 MB, 21 rows): strategy_id, strategy_id, encoded_signals, encoded_signals, encoded_wins, encoded_wins, encoded_pnl, encoded_pnl, encoded_roi_pct, encoded_roi_pct, claimed_n_trades, claimed_n_trades, claimed_roi_pct, claimed_roi_pct, verdict, verdict, notes, notes, computed_at, computed_at
- **bot_status** (0 MB, 2 rows): bot, status, since, reason
- **tb_tennis_matches** (0 MB, 0 rows): id, external_id, source, tournament, round, surface, is_atp, is_wta, best_of, event_date, scheduled_utc, player_a, player_b, rank_a, rank_b, seed_a, seed_b, status, pulled_at
- **tennis_config** (0 MB, 11 rows): key, value, note, updated_at
- **goal_prematch_prior** (0 MB, 27 rows): fixture_id, prior_factor, fetched_at
- **goal_strategies** (0 MB, 18 rows): strategy_id, name, family, type, side, target_market, target_selection, trigger_condition, qualifier_sql, stake_pct, mode, backtest_n, backtest_roi_pct, backtest_win_rate, last_review_date, notes
- **tb_cricket_matches** (0 MB, 0 rows): id, external_id, source, tournament, format, event_date, scheduled_utc, team_a, team_b, venue, toss_winner, toss_decision, status, pulled_at
- **goal_league_alias** (0 MB, 29 rows): today_competition, baseline_league
- **watchdog_alert_state** (0 MB, 10 rows): check_name, is_firing, last_alerted_at, last_message, updated_at
- **goal_team_alias** (0 MB, 28 rows): source_name, canonical_name, league, note, created_at
- **prematch_config** (0 MB, 4 rows): key, value
- **prematch_rules** (0 MB, 4 rows): name, enabled, leagues, bet, side, price_min, price_max, version, evidence
- **greyhound_pre_race_odds** (0 MB, 0 rows): id, captured_at, event_id, event_name, competition, market_id, market_type, market_name, market_start_time, selection_id, selection_name, best_back_price, best_back_size, best_lay_price, best_lay_size, last_traded_price, total_matched, minutes_to_start, is_pre_race, source
- **goal_league_baselines** (0 MB, 22 rows): league, n_matches, avg_home_goals, avg_away_goals, avg_total, pct_over_25, pct_btts, pct_ht_0_0, pct_ht_1_1, home_attack_lambda, home_defence_lambda, away_attack_lambda, away_defence_lambda, last_refreshed, phase_1_multiplier, phase_2_multiplier, phase_3_multiplier, phase_4_multiplier
- **tennis_market_results** (0 MB, 0 rows): id, settled_at, event_id, event_name, competition, market_id, market_type, selection_id, selection_name, win_lose, final_bsp, winner_name
- **tennis_dog_heartbeat** (0 MB, 1 rows): id, last_seen, recorded_today
- **cricket_market_results** (0 MB, 0 rows): id, market_id, event_id, event_name, market_type, settled_at, winning_selection_id, winning_selection_name, notes
- **prematch_positions** (0 MB, 0 rows): id, rule_name, match_date, league, home_team, away_team, bet, side, price, stake, dry_run, placed_at, bet_id, result, pnl, settled_at
- **golf_players** (0 MB, 0 rows): id, tournament_id, player, pre_tournament_sp, finish_position, won, created_at
- **golf_market_results** (0 MB, 0 rows): id, settled_at, event_id, event_name, competition, market_id, market_type, selection_id, selection_name, win_lose, final_bsp, final_position, tournament_status
- **stats_heartbeat** (0 MB, 1 rows): id, last_seen, live, matched, http_status
- **tb_golf_player_rounds** (0 MB, 0 rows): id, tournament_id, player, world_rank, round_num, score_to_par, total_strokes, position, made_cut
- **poisson_gap_results** (0 MB, 50 rows): season, sel, side, gap_bin, n, ret_pct, win_pct
- **pe_backtest_all_runners** (0 MB, 21 rows): strategy_id, strategy_id, side, side, encoded_signals, encoded_signals, encoded_wins, encoded_wins, encoded_pnl, encoded_pnl, encoded_roi_pct, encoded_roi_pct, claimed_n_trades, claimed_n_trades, claimed_roi_pct, claimed_roi_pct
- **player_liq** (0 MB, 0 rows): ts, market_id, event_name, competition, mkt, sel, minute, ltp, back_px, back_sz, lay_px, lay_sz, back3_sz, lay3_sz, total_matched
- **tb_tennis_results** (0 MB, 0 rows): match_id, winner, sets_a, sets_b, games_a, games_b, aces_a, aces_b, df_a, df_b, bp_won_a, bp_won_b, first_serve_won_pct_a, first_serve_won_pct_b, set_scores, settled_at
- **tb_cricket_results** (0 MB, 0 rows): match_id, winner, margin, inn1_team, inn1_runs, inn1_wickets, inn1_overs, inn1_run_rate, inn2_team, inn2_runs, inn2_wickets, inn2_overs, inn2_run_rate, total_runs, total_wickets, settled_at
- **fts_ultimate_raw** (0 MB, 0 rows): c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15, c16, c17, c18, c19, c20, c21, c22, c23, c24, c25, c26, c27, c28, c29, c30, c31, c32, c33, c34, c35, c36, c37, c38, c39 ...

## Odds columns found (bookmaker / Pinnacle / closing)

- bf_hist_other_files: ['path'] ; dates ?
- fd_matches: ['b365h', 'b365d', 'b365a', 'psh', 'psd', 'psa', 'psch', 'pscd', 'psca', 'b365ahh', 'b365aha'] ; dates [(datetime.date(2006, 7, 28), datetime.date(2026, 11, 2))]
- football_matches: ['b365h', 'b365d', 'b365a', 'bwh', 'bwd', 'bwa', 'maxh', 'maxd', 'maxa', 'avgh', 'avgd', 'avga', 'psh', 'psd', 'psa', 'b365ahh', 'b365aha'] ; dates [('1993-07-23', '2026-05-24')]
- football_overnight: ['b365h', 'b365d', 'b365a', 'maxh', 'maxd', 'maxa', 'avgh', 'avgd', 'avga'] ; dates [('01/02/11', '31/10/2022')]
- matches_fdco: ['b365h', 'b365d', 'b365a'] ; dates [('01/01/2023', '31/12/2023')]
- goal_backtest_results: ['pattern_n_samples'] ; dates ?
- season_phase_matches: ['phase'] ; dates ?
- fd_files: ['path'] ; dates ?
- hist_scan_results: ['phase'] ; dates ?
- goal_alerts_real: ['paper_per10'] ; dates ?
- fair_price_passed: ['passed_at'] ; dates ?
- boring_results: ['pattern'] ; dates ?
- boring_results_v3: ['pattern'] ; dates ?
- newsletter_subscribers: ['payhip_order_id'] ; dates ?
- tb_golf_tournaments: ['par'] ; dates ?
- boring_results_v2: ['pattern'] ; dates ?
- el_subscribers: ['payhip_payload', 'payhip_payload'] ; dates ?
- tb_alerts: ['payload'] ; dates ?
- goal_league_baselines: ['phase_1_multiplier', 'phase_2_multiplier', 'phase_3_multiplier', 'phase_4_multiplier'] ; dates ?
- fair_price_passed_inplay: ['passed_at'] ; dates ?
- scan_price_moves: ['phase'] ; dates ?
- digest_log: ['part'] ; dates ?
- v4_trend_portfolio: ['maxdd'] ; dates ?
- v4_trend_rollfree: ['maxdd'] ; dates ?
- fair_price_passed_frozen_out: ['passed_at'] ; dates ?

## Join test: Betfair MATCH_ODDS markets (last 2 years) to fd_matches by date + team names

fd_matches columns: ['div', 'season', 'date', 'home', 'away', 'fthg', 'ftag', 'hthg', 'htag', 'hs', 'as_', 'hst', 'ast', 'hc', 'ac', 'hy', 'ay', 'hr', 'ar', 'b365h', 'b365d', 'b365a', 'psh', 'psd', 'psa', 'psch', 'pscd', 'psca', 'b365o25', 'b365u25', 'p_o25', 'p_u25', 'ahh', 'b365ahh', 'b365aha', 'raw']
Betfair match-odds markets since Jul 2024 sampled: 58564; joined to fd_matches by date + normalised names: 8437

## Same-event cross-market coverage (for coherence features)

[(115342,)]

## Project data files on disk (racing/tennis/FTS)

/root/pe-data ['.arch.lock', '__pycache__', 'af_daily.log', 'af_daily.py', 'alpaca', 'archive.log', 'bsp_daily.log', 'bsp_daily.py', 'crumbs', 'duka', 'events', 'integrity.log', 'integrity_suite.py', 'integrity_suite.py.bak_411', 'ledger.log', 'oanda', 'paper_ledger.py', 'tape_archive.py', 'yf1m']
/root/pe-hist ['.adv.lock', '__pycache__', 'keepalive_hist.sh', 'loader.log', 'loader.py', 'loader_adv.log', 'loader_adv.py', 'loader_adv.py.bak_579', 'loader_core.py', 'loader_core.py.bak_353', 'loader_core.py.bak_406', 'loader_core.py.bak_520', 'loader_core.py.bak_521', 'results_backfill.log', 'results_backfill.py', 'results_backfill_summary.txt', 'results_backfill_tennis2.log']
