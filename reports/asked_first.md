ALL RECORDING, nothing needs you
As of 28 Nov 17:08 UK. The asker checks 58 things every 5 min (output, not process) and looks 3 hours ahead every 10 min.

FIXED WITHOUT YOU (last 24 h)
- tennisscore: broke 28 Nov 16:45, noticed 28 Nov 16:55, fixed 28 Nov 16:58. Lost: no output from 28 Nov 16:45 to 28 Nov 16:58 (Tennis live scores: output fresh again after stopped its python process [1056709] so its o)
- input:28b2893197: broke ?, noticed ?, fixed 28 Nov 16:47.  (repair session: Thing: /root/pe-xx/xx_recorder.py, which writes the xx_tape table. Smarket)
- input:e44a1a37ad: broke ?, noticed ?, fixed 28 Nov 16:47.  (repair session: Found: the 16:10 one-placer break was a false alarm. Line 33 of /root/pe-a)
- cover:football:order book: broke ?, noticed ?, fixed 28 Nov 16:40.  (no longer found)
- Before the asker: coherence_paper, v3_recorder and desk wrote nothing 27 Nov 05:47 to 28 Nov 14:12 (32 h, the database restart). Fixed 14:12-14:16 by session 730. Lost: 32 h of their paper rows.

COULD NOT FIX
- fvt_nq_py: no output found (table public.fvt_trades not found); process not running (since 28 Nov 16:58). Tried: nothing yet. Needs: watch only (not ours to touch): needs Peter or its own session.
- report_py: process not running (since 28 Nov 17:05). Tried: nothing yet. Needs: watch only (not ours to touch): needs Peter or its own session.
- Warnings, output still flowing (a repair session starts if one lasts 2 h): cricketrec (184 of its last 200 log lines are the same error: "sm quotes HTTPError); tenniscoll (160 of its last 200 log lines are the same error: "sm quotes HTTPError); xx_matchbook (193 of its last 200 log lines are the same error: "quotes chunk error ); xx_smarkets (193 of its last 200 log lines are the same error: "quotes chunk error )
- Paused on purpose and silent (not acted on): player

NEXT 3 HOURS
- football: 52 events start (first 17:15). Recorded now, of those inside each feed's window: fast stream 36/36; order book 47/47; extra market types 26/26
- racing: 1 events start (first 17:30). Recorded now, of those inside each feed's window: racing recorder 1/1
- tennis: 5 events start (first 17:35). Recorded now, of those inside each feed's window: tennis prices 5/5
- In play now (football match odds): fast stream 48/50; order book 50/50
- For information (they do not list every match): Smarkets 1/52; Matchbook 14/52; live facts 28/28
- Kick-offs in the last 3 h: 95 of 162 football matches had a stream price at the off (52 with a tick in the last 30 s). Not priced, e.g.: SKU Amstetten v St Polten, Podbeskidzie B-B v Pogon Grodzisk Mazowiecki, Rapid Vienna (Am) v KSV 1919, Dukla Banska Bystrica v Ruzomberok
- All covered: yes

Checks: database 38/100 connections, up since 27 Nov 05:47; disk 781 GB free; memory 14.2 GB free; clock synced yes (+0.2 s v Betfair); Betfair login 16:58.
Watchman/breaks lines read this pass: 7; checked; ack; ack; ack; ack; ack; ack
