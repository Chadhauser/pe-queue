NOT READY: 3 side recorders dead since 27 Nov (coherence, goal signal v3 snapshots, desk); stream cannot cover all 91 matches at 15:00
Snapshot 28 Nov 14:15 UK. Final update below by 14:50.

- Betfair price stream: last row 14:10:54, OK. Already 128 markets left out at the cap of 200.
- Betfair order book recorder: last row 14:10:46, OK (4,080 markets, all football, every 1-2 min).
- In-play tape: last row 14:10:54, OK.
- Smarkets tape: last row 14:11:05, OK (13,651 rows in 10 min; some quote-chunk errors in its log).
- Matchbook tape: last row 14:11:05, OK (13,800 rows in 10 min; volume recorder 14:10:10).
- Second recorder, 38 extra football market types: last row 14:10:31, OK.
- Live match facts: shots 14:08:39, ESPN 14:09:37, OK. Goal signal v3 scores 14:09:52, OK.
- Goal signal v3 snapshot recorder (v3_recorder): FAILING, nothing since 27 Nov 05:47 ("cursor already closed").
- Coherence paper and desk: FAILING, nothing since 27 Nov 05:47, same fault.
- Results and settling: last settle 14:05:03, OK.
- Trial loop: trial_today.md written 14:04 (11 min old), OK. T1 rows in today's file: 76.
- Dry runner: alive (pid 2912525, up 8 h), heartbeat 14:09. Last decision 13:58 (Slaven Belupo 2.48). 75 dry rows today, all refused by the off switch as designed.
- Mechanic: running every 5 min (lock touched 14:05), OK.
- Memory: 13 GB available of 17 (5 GB fully free). Biggest user is the database (about 1.6 GB per busy connection, mostly shared). Then signal_v2 250 MB, signal_2b 200 MB, signal_v3 190 MB. No research sessions running. Disk: 731 GB free (25% used).
- 15:00 kick-offs: 91 football matches start 14:55-15:05.
- Stream gap 1 (before kick-off): pre-off match odds are capped at the 40 most-traded markets (catalogue limit of 40, not the 200 cap). So about 51 of the 91 get no stream price before the off. The order book recorder still has all 91, but only every 2 min, so the trial skips many with "no quote in the 30 s before".
- Stream gap 2 (after 15:00): about 130 matches in play means about 260 in-play markets (match odds plus over/under 2.5) against 200 slots. The ones that kicked off earliest (13:30-14:00 games) and all in-play tennis get dropped. The 15:00 games themselves stay on.
