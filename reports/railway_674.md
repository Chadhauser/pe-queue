# 674 - 2026-11-19 15:18 UTC
```
process:
log tail:
/root/pe-migrate/final_copy.py:8: DeprecationWarning: datetime.datetime.utcnow() is deprecated and scheduled for removal in a future version. Use timezone-aware objects to represent datetimes in UTC: datetime.datetime.now(datetime.UTC).
  out=[f"# Railway final copy - started {datetime.datetime.utcnow():%F %H:%M} UTC",""]
/root/pe-migrate/final_copy.py:33: DeprecationWarning: datetime.datetime.utcnow() is deprecated and scheduled for removal in a future version. Use timezone-aware objects to represent datetimes in UTC: datetime.datetime.now(datetime.UTC).
  out+=["",f"Finished {datetime.datetime.utcnow():%F %H:%M} UTC. Tables not matching: {bad}. "+("EVERYTHING on Railway is now on this server: Railway can be switched off." if bad==0 else "Do NOT switch Railway off yet.")]; save()
disk:
/dev/sda1       968G  170G  799G  18% /
```

# Railway final copy - started 2026-11-19 14:28 UTC

| table | rows on Railway | rows copied | check |
|---|---|---|---|
| bf_price_log | 21,082,312 | 21,081,468 | MISMATCH  |
| bf_racing_log | 10,773,001 | 10,772,118 | MISMATCH  |
| bf_tennis_log | 7,474,167 | 7,474,015 | MISMATCH  |
| liq_sample | 22,129,119 | 22,129,119 | MATCH |
| racing_tape | 1,020,382 | 1,020,382 | MATCH |
| cricket_fav_tape | 513,840 | 513,840 | MATCH |
| racecards_today | 74,796 | 74,796 | MATCH |
| greyhound_racecards_today | 53,820 | 53,820 | MATCH |
| goal_stats_live | 30,539 | 30,539 | MATCH |
| clv_tape | 10,458 | 10,458 | MATCH |
| golf_leaderboards_today | 7,195 | 7,195 | MATCH |
| football_today | 7,449 | 7,449 | MATCH |
| tennis_dog_paper | 4,503 | 4,503 | MATCH |
| live_signals | 3,592 | 3,592 | MATCH |
| clv_paper | 841 | 841 | MATCH |
| tb_universal_signals | 16,400 | 16,400 | MATCH |
| racing_signals | 14,857 | 14,857 | MATCH |
| bot_orders | 699 | 699 | MATCH |
| racing_mm_paper | 450 | 450 | MATCH |
| paper_settlements | 4,649 | 4,649 | MATCH |
| golf_tournaments_today | 61 | 61 | MATCH |
| racing_bsp_paper | 477 | 477 | MATCH |
| api_call_budget | 48 | 48 | MATCH |
| cricket_fav_paper | 35 | 35 | MATCH |
| el_email_captures | 7 | 7 | MATCH |
| goal_live_predictions | 2,263,999 | 2,263,999 | MATCH |
| goal_timeline | 3,222,976 | 3,222,976 | MATCH |
| espn_stats | 60,033 | 60,033 | MATCH |
| brain_heartbeat | 221,111 | 221,110 | MATCH |

Finished 2026-11-19 14:45 UTC. Tables not matching: 3. Do NOT switch Railway off yet.

```
copies on this server so far:
   ('api_call_budget', 48, '8192 bytes')
   ('bf_price_log', 21079668, '2962 MB')
   ('bf_racing_log', 10771684, '1590 MB')
   ('bf_tennis_log', 7473048, '1283 MB')
   ('bot_orders', 699, '176 kB')
   ('brain_heartbeat', 221110, '30 MB')
   ('clv_paper', 841, '288 kB')
   ('clv_tape', 10458, '1712 kB')
   ('cricket_fav_paper', 35, '16 kB')
   ('cricket_fav_tape', 513840, '83 MB')
   ('el_email_captures', 7, '16 kB')
   ('espn_stats', 60033, '9960 kB')
   ('football_today', 7449, '1048 kB')
   ('goal_live_predictions', 2264282, '312 MB')
   ('goal_stats_live', 30539, '3496 kB')
   ('goal_timeline', 3223033, '366 MB')
   ('golf_leaderboards_today', 7195, '904 kB')
   ('golf_tournaments_today', 61, '48 kB')
   ('greyhound_racecards_today', 53820, '14 MB')
   ('liq_sample', 22134196, '3675 MB')
   ('live_signals', 3592, '712 kB')
   ('paper_settlements', 4649, '752 kB')
   ('racecards_today', 74796, '18 MB')
   ('racing_bsp_paper', 477, '176 kB')
   ('racing_mm_paper', 450, '160 kB')
   ('racing_signals', 14857, '3112 kB')
   ('racing_tape', 1020382, '205 MB')
   ('tb_universal_signals', 16400, '2792 kB')
   ('tennis_dog_paper', 4503, '856 kB')
```
