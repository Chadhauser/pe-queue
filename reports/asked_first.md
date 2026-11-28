BROKEN NOW: fast stream is not recording 44 of 44 football markets starting in the next 120 min; order book is not recording 3 of 54 football markets starting in the next 180 min
As of 28 Nov 16:30 UK. The asker checks 57 things every 5 min (output, not process) and looks 3 hours ahead every 10 min.

FIXED WITHOUT YOU (last 24 h)
- none
- Before the asker: coherence_paper, v3_recorder and desk wrote nothing 27 Nov 05:47 to 28 Nov 14:12 (32 h, the database restart). Fixed 14:12-14:16 by session 730. Lost: 32 h of their paper rows.

COULD NOT FIX
- input:e44a1a37ad: breaks.md 2026-11-28T16:10: ONE-PLACER CHECK FAILED - order-sending call in /root/pe-asker/test_asker.py (line 33: Betfair operation passed to a call) (since 28 Nov 16:20). Tried: session_started: repair session started (pid 3903700, 60 min, brief /root/pe-asker/sessions/20261. Needs: a repair session is on it now.
- watchdog_py: process not running (since 28 Nov 16:30). Tried: nothing yet. Needs: watch only (not ours to touch): needs Peter or its own session.
- input:28b2893197: breaks.md 2026-11-28T16:20: basketball silent 6 hours on xx_tape (since 28 Nov 16:30). Tried: session_started: repair session started (pid 3926071, 60 min, brief /root/pe-asker/sessions/20261. Needs: a repair session is on it now.
- cover:football:order book: order book is not recording 3 of 54 football markets inside its window: Houston Dynamo v San Jose Earthquakes 19:30, VfL Osnabruck v Hannover 19:30, S (since 28 Nov 16:30). Tried: nothing yet. Needs: waiting for a repair session slot.
- fast stream: being fixed, not by a session: the stream holds 200 markets on 1 connection; the widening to 6 connections (tested side by side 15:32-15:40: 50 of 50 upcoming matches) is switched on at about 18:05 UK, after the 17:15 no-restart time and between kick-off blocks
- Warnings, output still flowing (a repair session starts if one lasts 2 h): cricketrec (185 of its last 200 log lines are the same error: "sm quotes HTTPError); tenniscoll (159 of its last 200 log lines are the same error: "sm quotes HTTPError); xx_matchbook (189 of its last 200 log lines are the same error: "quotes chunk error ); xx_smarkets (189 of its last 200 log lines are the same error: "quotes chunk error )
- Paused on purpose and silent (not acted on): player

NEXT 3 HOURS
- football: 54 events start (first 17:00). Recorded now, of those inside each feed's window: fast stream 0/44 MISSING St Pryve St Hilaire v Selongey 17:00, Hradec Kralove v Bohemians 1905 17:00, Grasshoppers Zurich v FC Basel 17:00; order book 51/54 MISSING Houston Dynamo v San Jose Earthquakes 19:30, VfL Osnabruck v Hannover 19:30, Servette v Lausanne 19:30; extra market types 15/15
- racing: 1 events start (first 17:00). Recorded now, of those inside each feed's window: none inside a window yet
- tennis: 5 events start (first 17:00). Recorded now, of those inside each feed's window: tennis prices 5/5
- In play now (football match odds): fast stream 116/130; order book 130/130
- For information (they do not list every match): Smarkets 1/54; Matchbook 17/54; live facts 32/32
- Kick-offs in the last 3 h: 86 of 152 football matches had a stream price at the off (45 with a tick in the last 30 s). Not priced, e.g.: Norrby IF v Lunds BK, Epinal v Amiens, SKU Amstetten v St Polten, Podbeskidzie B-B v Pogon Grodzisk Mazowiecki
- All covered: NO

Checks: database 38/100 connections, up since 27 Nov 05:47; disk 781 GB free; memory 13.7 GB free; clock synced yes (+0.5 s v Betfair); Betfair login 16:30.
Watchman/breaks lines read this pass: 7; checked; ack; ack; open; ack; open; ack
