BROKEN NOW: xx_smarkets (last output 15 min ago (limit 10 min while events are on)); smarkets login errors in the recorder log: "SMARKETS LOGIN FAILED: {'data': None, 'error_type': 'AUTH_UNAVAILABLE'}"
As of 28 Nov 17:36 UK. The asker checks 58 things every 5 min (output, not process) and looks 3 hours ahead every 10 min.

FIXED WITHOUT YOU (last 24 h)
- Tennis prices on all three exchanges before the start: broke 28 Nov 17:25, noticed 28 Nov 17:25, fixed 28 Nov 17:35 by a repair session. Lost: nothing recorded lost.
- Matchbook traded volume recorder: broke 28 Nov 17:20, noticed 28 Nov 17:29, fixed 28 Nov 17:30 by a restart. Lost: no output from 28 Nov 17:20 to 28 Nov 17:30.
- Tennis live scores: broke 28 Nov 16:45, noticed 28 Nov 16:55, fixed 28 Nov 16:58 by a restart. Lost: no output from 28 Nov 16:45 to 28 Nov 16:58.
- breaks.md 2026-11-28T16:20: basketball silent 6 hours on xx_tape: broke 28 Nov 16:30, noticed 28 Nov 16:30, fixed 28 Nov 16:47 by a repair session. Lost: nothing recorded lost.
- breaks.md 2026-11-28T16:10: ONE-PLACER CHECK FAILED - order-sending ca: broke 28 Nov 16:20, noticed 28 Nov 16:20, fixed 28 Nov 16:47 by a repair session. Lost: nothing recorded lost.
- 3 short alarms cleared by themselves without action (not listed).
- Before the asker: coherence_paper, v3_recorder and desk wrote nothing 27 Nov 05:47 to 28 Nov 14:12 (32 h, the database restart). Fixed 14:12-14:16 by session 730. Lost: 32 h of their paper rows.

COULD NOT FIX
- af_daily_py: process not running (since 28 Nov 17:25). Tried: nothing yet. Needs: watch only (not ours to touch): needs Peter or its own session.
- sys:smarkets_login: smarkets login errors in the recorder log: "SMARKETS LOGIN FAILED: {'data': None, 'error_type': 'AUTH_UNAVAILABLE'}" (since 28 Nov 17:25). Tried: nothing yet. Needs: waiting for a repair session slot.
- xx_smarkets: last output 15 min ago (limit 10 min while events are on); 188 of its last 200 log lines are the same error: "quotes chunk error RuntimeError('smarket (since 28 Nov 17:35). Tried: nothing yet. Needs: waiting for a repair session slot.
- Warnings, output still flowing (a repair session starts after 2 h): xx_matchbook repeat "quotes chunk error RuntimeError('smarkets mar"
- Paused on purpose and silent (not acted on): player

NEXT 3 HOURS
- football: 42 events start (first 17:45). Recorded now, of those inside each feed's window: fast stream 29/29; order book 41/41; extra market types 19/19
- racing: 1 events start (first 18:00). Recorded now, of those inside each feed's window: racing recorder 1/1
- tennis: 5 events start (first 18:00). Recorded now, of those inside each feed's window: tennis prices 5/5
- In play now (football match odds): fast stream 45/48; order book 48/48
- For information (they do not list every match): Smarkets 0/42; Matchbook 10/42; live facts 19/19
- Kick-offs in the last 3 h: 94 of 156 football matches had a stream price at the off (57 with a tick in the last 30 s). Not priced, e.g.: Cumnock Juniors v Arbroath, Radcliffe Borough v Chester, Threave Rovers v Alloa, Peterhead v Edinburgh City
- Next 3 hours all covered on our feeds: yes

Checks: database 41/100 connections, up since 27 Nov 05:47; disk 781 GB free; memory 9.3 GB free; clock synced yes (+0.7 s v Betfair); Betfair login 17:36.
Watchman/breaks lines read this pass: 7; checked; ack; ack; ack; ack; ack; ack
