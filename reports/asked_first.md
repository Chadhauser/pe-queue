BROKEN NOW: fast stream is not recording 51 of 51 football markets starting in the next 120 min; order book is not recording 1 of 60 football markets starting in the next 180 min
As of 28 Nov 16:20 UK. The asker checks 54 things every 5 min (output, not process) and looks 3 hours ahead every 10 min.

FIXED WITHOUT YOU (last 24 h)
- none
- Before the asker: coherence_paper, v3_recorder and desk wrote nothing 27 Nov 05:47 to 28 Nov 14:12 (32 h, the database restart). Fixed 14:12-14:16 by session 730. Lost: 32 h of their paper rows.

COULD NOT FIX
- input:e44a1a37ad: breaks.md 2026-11-28T16:10: ONE-PLACER CHECK FAILED - order-sending call in /root/pe-asker/test_asker.py (line 33: Betfair operation passed to a call) (since 28 Nov 16:20). Tried: session_started: repair session started (pid 3903700, 60 min, brief /root/pe-asker/sessions/20261. Needs: a repair session is on it now.
- fast stream: being fixed, not by a session: the stream holds 200 markets on 1 connection; the widening to 6 connections (tested side by side 15:32-15:40: 50 of 50 upcoming matches) is switched on at about 18:05 UK, after the 17:15 no-restart time and between kick-off blocks
- Warnings, output still flowing (a repair session starts if one lasts 2 h): cricketrec (186 of its last 200 log lines are the same error: "sm quotes HTTPError); tenniscoll (158 of its last 200 log lines are the same error: "sm quotes HTTPError); xx_matchbook (187 of its last 200 log lines are the same error: "quotes chunk error ); xx_smarkets (187 of its last 200 log lines are the same error: "quotes chunk error )
- Paused on purpose and silent (not acted on): player

NEXT 3 HOURS
- football: 60 events start (first 16:30). Recorded now, of those inside each feed's window: fast stream 0/51 MISSING Lumezzane v Desenzano Calvina 16:30, Mura v NK Maribor 16:30, Slask Wroclaw v GKS Katowice 16:30; order book 59/60 MISSING Wisla Krakow v LKP Motor Lublin 19:15; extra market types 24/24
- racing: 1 events start (first 16:30). Recorded now, of those inside each feed's window: fast stream 1/1; racing recorder 1/1
- tennis: 5 events start (first 17:00). Recorded now, of those inside each feed's window: tennis prices 5/5
- In play now (football match odds): fast stream 114/121; order book 121/121
- For information (they do not list every match): Smarkets 0/60; Matchbook 22/60; live facts 34/34
- Kick-offs in the last 3 h: 90 of 160 football matches had a stream price at the off (45 with a tick in the last 30 s). Not priced, e.g.: Amazulu v Milford, Chippa Utd v Kaizer Chiefs, Gubbio v FC Vado, Novara v ASD Alcione
- All covered: NO

Checks: database 37/100 connections, up since 27 Nov 05:47; disk 782 GB free; memory 14.2 GB free; clock synced yes (+1.0 s v Betfair); Betfair login 16:10.
Watchman/breaks lines read this pass: 6; checked; ack; ack; ack; ack; open
