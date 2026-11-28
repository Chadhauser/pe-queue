# 732 the bot that asks first (28 Nov 2026, UK times)
Tier one (trading data). Money: £0. The asker earns nothing itself. It keeps the recorders that the T1 dry runner and the paper trials need writing.

**WATCHED:** 58 things in `asker.things`, plus 11 it found itself (watch only). Each has plain words, its output, a fresh limit for events on and off, its restart and who depends on it. It checks output, not processes: quick checks every 5 min from the mechanic, a full pass every 10 min from its own loop (one lock, about 50 MB). The page is `asked_first.md`.

**FIXES ALONE:**
- 29 things: restart the python child, or run the listed restart. Then it re-checks; if that fails it puts things back, then starts a repair session (60 min, brief, archive first, proof in result.md).
- One re-run for a job that died on a passing database error.
- Limits: 1 session at a time, 2 tries per thing per day, 8 sessions a day.
- Never: orders, the money switch, the placer, the dry runner, deletes, trial or paper rules, spending. 20 things are watch only.

**PROOFS:**
- **Database sessions closed:** 13 recorders' sessions closed 18:02:10. All 13 back and fresh by 18:04:40 (12 reconnected in place, mb_volume's wrapper restarted it). The asker logged it for 11 at 18:05:02. espn and xgstats reconnect every cycle, so they are not tracked that way.
- **Side collector:** mbvol stopped 17:20:28. The asker restarted it 17:29:09 (it confirms over two checks first); fresh 17:30:03.
- **Planted job error:** planted 15:45:11, caught 15:45:12.
- **Asker killed:** 15:42:50; the mechanic restarted it 15:45:02. The asker checks the mechanic's heartbeat (OK).
- **coherence_paper, v3_recorder, desk:** listed and OK; wrote at 18:11, after their sessions were closed.
- **Kick-offs on the widened stream (18:15-20:00):** 26 of 26 matches were held and priced at the off, and 25 of 26 had a tick in the last 30 s. The one without (Villarroel v Potosi, 19:00) was suspended by Betfair from 18:57, so it had no price to send. Thin T1 markets: 10 of 11 ticked in the last 30 s (the 11th is that suspended match). Before the switch, the 15:00 block had 2 of 59 thin markets ticked. **Not yet proven:** tonight's biggest block was 7 matches. The real test is the next 50+ match block (Sunday afternoon). The asker logs every kick-off in `asker.kickoff` and the page shows it.
- **Real fixes:** tennis scores (broke 16:45, fixed 16:58 by a restart). Repair sessions fixed the one-placer false alarm, Smarkets basketball silent since 10:02, and tennis Smarkets 429s (calls now 0.5 s apart).

**FIRST FULL PASS FOUND BROKEN:**
1. The mechanic had been blind for 25 h; a child held its lock. Fixed.
2. Job 728 ended exit 0 with a syntax error; already replaced by 731.
3. The stream held 0 of about 50 pre-off matches in busy blocks. In the 15:00 block, 36 of 91 were priced at the off and 2 of 59 thin T1 markets had a tick in the last 30 s. The widened recorder went live 18:05: 6 connections, about 300 markets. To put the old one back: `stream/rollback.sh`.
4. The xx recorder would not survive a database restart; patched. The other 27 database programs were checked and are safe.
5. The player recorder is dead (KeyError); it is paused on purpose (543).
6. Smarkets 429s in the cricket, tennis and xx collectors.
7. The push watchdog and af_daily were writing unlisted; both now listed.

**COULD NOT FIX:** Smarkets 429 is one limit shared by 5 programs here. The cricket session (17:49-18:47) proved that, could not prove its fix (Smarkets refused nearly everything from 18:30), and put the original back.
- Cricket's Smarkets prices have been stale since 18:29. Its Betfair and Matchbook prices and the main Smarkets tape are fine.
- Sessions on this are off until 29 Nov 10:00. I stopped a third one after 3 min; nothing changed.
- It needs one shared Smarkets rate budget: a builder order.

**MISTAKES AND LIMITS:**
- At 16:32 a repair session restarted the writing xx recorder, before your 17:15 rule, and about 48 s of xx tape was lost. My brief lacked the rule; every brief now carries it.
- At 15:35 it once restarted the paused player child, before the paused rule existed. No effect: it crash-loops exactly as before.
- A Smarkets login outage on their side (17:22-18:04) was held and not restarted; that rule is new (tests 12-14).
- It cannot fix code bugs without a session, or exchange outages. Smarkets, Matchbook and live-facts coverage is information only.
- The Betfair docs fetch was refused; the connection limit came from the stream's own login reply.
- The widened stream feeds the dry runner more thin markets. The runner itself is untouched.
- Tests: `test_asker.py` 16/16 pass, `stream/test_shards.py` 10/10 pass.
