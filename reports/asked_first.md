ALL RECORDING, nothing needs you
As of 28 Nov 19:05 UK. The asker checks 58 things every 5 min, plus 11 it found itself (watch only). It checks output, not processes, and looks 3 hours ahead every 10 min.

FIXED WITHOUT YOU (last 24 h)
- Tennis prices on all three exchanges before the start: broke 28 Nov 17:25, noticed 28 Nov 17:25, fixed 28 Nov 17:35 by a repair session. Lost: nothing recorded lost.
- Matchbook traded volume recorder: broke 28 Nov 17:20, noticed 28 Nov 17:29, fixed 28 Nov 17:30 by a restart. Lost: no output from 28 Nov 17:20 to 28 Nov 17:30.
- Tennis live scores: broke 28 Nov 16:45, noticed 28 Nov 16:55, fixed 28 Nov 16:58 by a restart. Lost: no output from 28 Nov 16:45 to 28 Nov 16:58.
- breaks.md 2026-11-28T16:20: basketball silent 6 hours on xx_tape: broke 28 Nov 16:30, noticed 28 Nov 16:30, fixed 28 Nov 16:47 by a repair session. Lost: nothing recorded lost.
- breaks.md 2026-11-28T16:10: ONE-PLACER CHECK FAILED - order-sending ca: broke 28 Nov 16:20, noticed 28 Nov 16:20, fixed 28 Nov 16:47 by a repair session. Lost: nothing recorded lost.
- 4 short alarms cleared by themselves without action (not listed).
- Before the asker: coherence_paper, v3_recorder and desk wrote nothing 27 Nov 05:47 to 28 Nov 14:12 (32 h, the database restart). Fixed 14:12-14:16 by session 730. Lost: 32 h of their paper rows.

COULD NOT FIX
- No more repair sessions tonight for cricketrec, tenniscoll, xx_matchbook, xx_smarkets: Smarkets 429 Too Many Requests is one limit shared by 5 programs on this server (cricket session 17:49-18:47 found it; one-recorder sessions cannot fix it and each restart adds calls). Needs one shared Smarkets rate budg
- cricketrec: a repair session could not fix it: the error is still repeating. Smarkets refuses nearly every call from this server since 18:30 (5 programs share one Smarkets limit); cricket's Smarkets prices (cricket.sm_snap) stale since 18:29; Betfair and Matchbook cricket fine. Needs one shared Smarkets rate budget across golf, tennis, racing,
- xx_matchbook: a repair session could not fix it: the error is still repeating. The repeating "quotes chunk error" is the Smarkets 429 limit shared by 5 programs on this server (cricket session 17:49-18:47); one-recorder sessions cannot fix it. Needs one shared Smarkets rate budget (a builder order). (full: /root/pe-asker/sessions/20261128_1852_x
- Warnings, output still flowing (a repair session starts after 2 h): cricketrec repeat "sm quotes HTTPError('# Client Error: Too Many"; xx_matchbook, xx_smarkets repeat "quotes chunk error RuntimeError('smarkets mar"
- Paused on purpose and silent (not acted on): player

NEXT 3 HOURS
- football: 31 events start (first 19:15). Recorded now, of those inside each feed's window: fast stream 25/25; order book 30/30; extra market types 16/16
- racing: 1 events start (first 19:30). Recorded now, of those inside each feed's window: racing recorder 1/1
- tennis: 2 events start (first 20:00). Recorded now, of those inside each feed's window: tennis prices 2/2
- cricket: 4 events start (first 21:30). Recorded now, of those inside each feed's window: cricket prices 4/4
- In play now (football match odds): fast stream 33/33; order book 33/33
- For information (they do not list every match): Smarkets 0/31; Matchbook 11/31; live facts 16/16
- Kick-offs in the last 3 h: 58 of 61 football matches had a stream price at the off (49 with a tick in the last 30 s). Not priced, e.g.: Univ Catolica (Ecu) v Independiente (Ecu), Pergolettese v Giana Erminio, Sorrento v Cosenza
- Next 3 hours all covered on our feeds: yes

Checks: database 37/100 connections, up since 27 Nov 05:47; disk 780 GB free; memory 3.3 GB free; clock synced yes (+1.0 s v Betfair); Betfair login 18:55.
Watchman/breaks lines read this pass: 4; ack; ack; ack; ack
