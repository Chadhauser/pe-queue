2026-11-14T11:20 BREAK: no bot bets in 6 hours while football is on (90 match-odds markets on the tape);
2026-11-14T12:20 BREAK: no bot bets in 6 hours while football is on (95 match-odds markets on the tape);
2026-11-14T13:20 BREAK: no bot bets in 6 hours while football is on (133 match-odds markets on the tape);
2026-11-14T14:20 BREAK: no bot bets in 6 hours while football is on (148 match-odds markets on the tape);
2026-11-14T15:20 BREAK: no bot bets in 6 hours while football is on (166 match-odds markets on the tape);
2026-11-14T16:20 BREAK: no bot bets in 6 hours while football is on (171 match-odds markets on the tape);
2026-11-14T18:20 BREAK: failed jobs 523_fin_crumbs_smallcaps;
2026-11-15T05:20 BREAK: stream tape stopped;
2026-11-15T06:20 BREAK: stream tape stopped;
2026-11-15T09:20 BREAK: failed jobs 579_archive_offbox;
2026-11-15T10:20 HEALED:  pushed local commits;
2026-11-15T10:20 BREAK: failed jobs 579_archive_offbox;
2026-11-15T11:20 BREAK: queue cannot pull (Merge with strategy ort failed.);
2026-11-15T12:20 BREAK: queue cannot pull (Merge with strategy ort failed.);
2026-11-15T13:20 BREAK: queue cannot pull (Merge with strategy ort failed.);
2026-11-15T14:20 HEALED:  aborted a stuck rebase/merge;
2026-11-15T14:20 BREAK: queue cannot pull (Merge with strategy ort failed.);
2026-11-15T15:20 HEALED:  runner clone was behind origin (jobs 499_jump_up_delay_touch.sh.wip 499_late_state_census.py lib_afmatch.py  unseen) - pulled; restarted the bot (heartbeat -1 min old);
2026-11-15T15:20 BREAK: bot process not running;
2026-11-15T16:20 HEALED:  runner clone was behind origin (jobs 499_ht_state_thin.sh.wip 499_jump_up_delay_touch.sh.wip 499_late_state_census.py  unseen) - pulled; restarted the bot (heartbeat -1 min old);
2026-11-15T16:20 BREAK: bot process not running;
2026-11-15T16:46 BREAK: jobs on origin older than 30 min not run and not waiting: 499_ht_state_thin.sh.wip 499_jump_up_delay_touch.sh.wip 499_late_state_census.py ;
2026-11-15T18:20 HEALED:  committed stray edits and pulled;
2026-11-16T03:20 HEALED:  committed stray edits and pulled;
2026-11-16T06:20 BREAK: in-play tape stopped;
2026-11-16T08:20 HEALED:  committed stray edits and pulled;
2026-11-16T09:20 HEALED:  committed stray edits and pulled; pushed local commits;
2026-11-16T10:20 BREAK: job runner not cycling for 16 min (lock held or hung);
2026-11-16T11:20 HEALED:  runner clone was behind origin (jobs 528_fin_fomc_drift_m7door3 529_fin_mt5_bridge 530_fin_ig_client  unseen) - pulled;
2026-11-16T11:20 BREAK: job runner not cycling for 76 min (lock held or hung);
2026-11-16T12:20 HEALED:  runner clone was behind origin (jobs 528_fin_fomc_drift_m7door3 529_fin_mt5_bridge 530_fin_ig_client  unseen) - pulled;
2026-11-16T12:20 BREAK: job runner not cycling for 136 min (lock held or hung);
2026-11-16T13:20 BREAK: failed jobs 527_fin_mt5_install, 533_fin_mt5_python_fallback;
2026-11-16T14:20 HEALED:  committed stray edits and pulled;
2026-11-16T14:20 BREAK: disk under 10 GB free (9);
2026-11-16T15:20 BREAK: failed jobs 540_fin_mt5_wine_staging; goal monitor not running;
2026-11-16T16:20 BREAK: goal monitor not running;
2026-11-16T17:20 BREAK: goal monitor not running;

## 2026-11-16 21:15 UTC | fin paper bots | settle counted a stray QQQ trade
- What: tonight's settle booked ORB -$51.51 / 1 trade. That QQQ trade was the OLD bot's (relaunched by job 537 this morning, flattened by 541), not the new tick, which missed today's ORB window (deployed 10:02 NY).
- Fix: settle and bots.md now count ORB/ORB_SPY/ORB_IWM/M7B only when the tick itself entered that day. Two new offline tests (I1, I2) fail on the old code and pass on the new: 23/23 PASS. Sports untouched.
