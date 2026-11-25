# Audit - 2026-11-25 03:40 UTC

15 claims checked: 10 MATCH, 1 MISMATCH, 4 SWITCHED OFF (expected, job 698).

| claim | checked against | verdict | auditor found |
|---|---|---|---|
| the map is rebuilt nightly | map_slices | **SWITCHED OFF** | sports team loop switched off 21 Nov 2026 (job 698); this file is written only by that loop |
| scoreboard was rewritten in the last 30 minutes | scoreboard.md | **SWITCHED OFF** | sports team loop switched off 21 Nov 2026 (job 698); this file is written only by that loop |
| small bites DRIFT_FADE k3 H10 marked PASS | gate_history.json | **MISMATCH** | history test £-0.85 per £100: paper is not in line with it |
| machine_nightly.md written in the last 26 hours | /root/pe-queue/reports/machine_nightly.md | **SWITCHED OFF** | sports team loop switched off 21 Nov 2026 (job 698); this file is written only by that loop |
| map_latest.md written in the last 26 hours | /root/pe-queue/reports/map_latest.md | **SWITCHED OFF** | sports team loop switched off 21 Nov 2026 (job 698); this file is written only by that loop |
| desk.py is running | crontab keepalive | **MATCH** |  |
| v3_recorder.py is running | crontab keepalive | **MATCH** |  |
| coherence_paper.py is running | crontab keepalive | **MATCH** |  |
| book_recorder.py is running | crontab keepalive | **MATCH** |  |
| run_settle_15m.sh is running | crontab keepalive | **MATCH** |  |
| rule factory loop is off (698) | processes | **MATCH** |  |
| old sports team loop is off (698) | processes | **MATCH** |  |
| old paper book (bookie paper orders) is off (698) | processes | **MATCH** |  |
| watchman runs four times a day, not hourly (698) | crontab | **MATCH** |  |
| the recorder wrote prices in the last 6 hours | book_snap | **MATCH** | 144093 |
