# Audit - 2026-11-21 03:40 UTC

20 claims checked: 16 MATCH, 4 MISMATCH.

| claim | checked against | verdict | auditor found |
|---|---|---|---|
| map was built in the last 26 hours (2026-11-19) | map_slices.run_date | **MISMATCH** |  |
| small bites DRIFT_FADE k3 H10 marked PASS | gate_history.json | **MISMATCH** | history test £-0.85 per £100: paper is not in line with it |
| grid_history.py is running | crontab keepalive | **MISMATCH** |  |
| map_latest.md written in the last 26 hours | /root/pe-queue/reports/map_latest.md | **MISMATCH** | 43 hours old |
| map #1 CORRECT_SCORE | in-play 60 | BACK | price 0.10-0.20 | everywhere: 40 bets, £817.63, £+58.52 per £100 | map_bets | **MATCH** | auditor: 40 bets, £817.63, 0 bets with a wrong profit |
| map #2 CORRECT_SCORE | pre60 | BACK | price 0.05-0.10 | thin (<£2k matched): 141 bets, £374.93, £+22.51 per £100 | map_bets | **MATCH** | auditor: 141 bets, £374.93, 0 bets with a wrong profit |
| map #3 MATCH_ODDS | pre60 | BACK | price 0.20-0.35 | everywhere: 37 bets, £280.78, £+26.46 per £100 | map_bets | **MATCH** | auditor: 37 bets, £280.78, 0 bets with a wrong profit |
| 60 random map bets: result and price exist in the recorder | book_result, book_snap | **MATCH** | 0 do not |
| scoreboard was rewritten in the last 30 minutes | scoreboard.md | **MATCH** | 4 minutes old |
| bot v2.2 TAKER (blocklist + filters, from 17 Nov): 91 settled, £-7.65 | bookie_paper | **MATCH** | table now: 91 settled, £-7.65 |
| small bites forward paper (all cells): 2157 settled, £-114.54 | small_bites_paper | **MATCH** | table now: 2157 settled, £-114.54 |
| coherence forward paper, real order book (all cells): 67 settled, £-16.86 | coherence_paper | **MATCH** | table now: 67 settled, £-16.86 |
| sports_team.py is running | crontab keepalive | **MATCH** |  |
| desk.py is running | crontab keepalive | **MATCH** |  |
| bookie_v2.py is running | crontab keepalive | **MATCH** |  |
| v3_recorder.py is running | crontab keepalive | **MATCH** |  |
| coherence_paper.py is running | crontab keepalive | **MATCH** |  |
| book_recorder.py is running | crontab keepalive | **MATCH** |  |
| machine_nightly.md written in the last 26 hours | /root/pe-queue/reports/machine_nightly.md | **MATCH** | 2 hours old |
| the recorder wrote prices in the last 6 hours | book_snap | **MATCH** | 318057 |
