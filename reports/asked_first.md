BROKEN NOW: tennisscore (last output 33 min ago (limit 30 min while events are on)); fast stream is not recording 43 of 44 football markets starting in the next 120 min; order book is not recording 7 of 61 football markets starting in the next 180 min
As of 28 Nov 16:48 UK. The asker checks 55 things every 5 min (output, not process) and looks 3 hours ahead every 10 min.

FIXED WITHOUT YOU (last 24 h)
- input:28b2893197: broke ?, noticed ?, fixed 28 Nov 16:47.  (repair session: Thing: /root/pe-xx/xx_recorder.py, which writes the xx_tape table. Smarket)
- input:e44a1a37ad: broke ?, noticed ?, fixed 28 Nov 16:47.  (repair session: Found: the 16:10 one-placer break was a false alarm. Line 33 of /root/pe-a)
- cover:football:order book: broke ?, noticed ?, fixed 28 Nov 16:40.  (no longer found)
- Before the asker: coherence_paper, v3_recorder and desk wrote nothing 27 Nov 05:47 to 28 Nov 14:12 (32 h, the database restart). Fixed 14:12-14:16 by session 730. Lost: 32 h of their paper rows.

COULD NOT FIX
- none
- fast stream: being fixed, not by a session: the stream holds 200 markets on 1 connection; the widening to 6 connections (tested side by side 15:32-15:40: 50 of 50 upcoming matches) is switched on at about 18:05 UK, after the 17:15 no-restart time and between kick-off blocks
- Warnings, output still flowing (a repair session starts if one lasts 2 h): cricketrec (187 of its last 200 log lines are the same error: "sm quotes HTTPError); tenniscoll (160 of its last 200 log lines are the same error: "sm quotes HTTPError); xx_matchbook (189 of its last 200 log lines are the same error: "quotes chunk error ); xx_smarkets (189 of its last 200 log lines are the same error: "quotes chunk error )
- Paused on purpose and silent (not acted on): player

NEXT 3 HOURS
- football: 61 events start (first 17:00). Recorded now, of those inside each feed's window: fast stream 1/44 MISSING St Pryve St Hilaire v Selongey 17:00, Hradec Kralove v Bohemians 1905 17:00, Grasshoppers Zurich v FC Basel 17:00; order book 54/61 MISSING Nice v ESTAC Troyes 19:45, Charleroi v Waasland-Beveren 19:45, Paris St-G v Lorient 19:45; extra market types 25/25
- racing: 1 events start (first 17:00). Recorded now, of those inside each feed's window: fast stream 1/1; racing recorder 1/1
- tennis: 5 events start (first 17:00). Recorded now, of those inside each feed's window: tennis prices 5/5
- In play now (football match odds): fast stream 37/39; order book 39/39
- For information (they do not list every match): Smarkets 1/61; Matchbook 17/61; live facts 40/40
- Kick-offs in the last 3 h: 91 of 160 football matches had a stream price at the off (46 with a tick in the last 30 s). Not priced, e.g.: Norrby IF v Lunds BK, Epinal v Amiens, SKU Amstetten v St Polten, Podbeskidzie B-B v Pogon Grodzisk Mazowiecki
- All covered: NO

Checks: database 37/100 connections, up since 27 Nov 05:47; disk 781 GB free; memory 14.2 GB free; clock synced yes (+0.4 s v Betfair); Betfair login 16:48.
Watchman/breaks lines read this pass: 7; checked; ack; ack; ack; ack; ack; ack
