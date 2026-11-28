READY: every recorder is writing. The 3 dead side recorders are fixed and proved. One known gap was left alone: the stream cannot hold every 15:00 match (see the end)
Final 28 Nov, 14:28 UK. The first snapshot was pushed at 14:12.

FIXED (step 2): coherence_paper, v3_recorder and desk had written nothing since 27 Nov 05:47 ("cursor already closed").
- Same reconnect as book_recorder: after a database error, open a new connection and carry on. Originals archived first in /root/pe-archive/pre3pm_28nov/ (checksums match). All 3 compile.
- Restarted one at a time, only their own python process; each wrapper relaunched it. v3 14:12:39, coherence 14:13:45, desk 14:14:25.
- Proof the fix works: I closed each one's database session on purpose. Each logged "database reconnected" by itself: v3 14:15:10, desk 14:15:21, coherence 14:15:36. Fresh heartbeats followed at 14:16:20, 14:16:12 and 14:16:26.
- Real rows again:
  - desk wrote call 732 at 14:16:32 (Peterborough v Cambridge, paper lay 1.14), its first since 27 Nov 03:03.
  - v3_recorder wrote 12 rows at 14:27:01, the 14:30 German matches, 3 min before the off. Its last rows before this were for the 26 Nov games.
  - coherence wrote 10 paper rows, the last at 14:25:10. Its last rows before this were for the 27 Nov 01:00 games.

STATUS (row times are UK, checked 14:10-14:12):
- Betfair price stream: 14:10:54 OK
- Order book recorder: 14:10:46 OK (4,080 markets)
- In-play tape: 14:10:54 OK
- Smarkets tape: 14:11:05 OK
- Matchbook tape: 14:11:05 OK
- Extra 38 market types: 14:10:31 OK
- Match facts: shots 14:08:39, ESPN 14:09:37 OK. Goal signal v3 scores 14:09:52 OK.
- Results and settling: 14:05:03 OK
- Trial loop: trial_today.md written 14:04, OK. 76 T1 rows in today's file.
- Dry runner: not touched. Alive, pid 2912525. Last decision 13:58 (Slaven Belupo 2.48). 75 dry rows today, all refused by the off switch as designed. Heartbeat 14:09.
- Mechanic: running every 5 min, OK.
- Memory and disk: 13 GB available of 17, so nothing was paused. The database is the big user; then signal_v2 250 MB, signal_2b 200 MB, signal_v3 190 MB. No research sessions running. Disk 731 GB free.

15:00: 91 football matches kick off 14:55-15:05. LEFT ALONE: no change to the stream in the last hour before kick-off.
- Before the off, the stream takes only the 40 most-traded pre-off match odds markets. That is a catalogue limit of 40, not the 200 cap. So about 51 of the 91 get no stream price. The order book recorder still has all 91, but every 2 min only, so T1 will skip some of them ("no quote in the 30 s before").
- After 15:00 the cap of 200 bites. About 130 matches will be in play, which is about 260 in-play markets. Dropped first: all in-play tennis, then the matches that kicked off earliest (13:30-14:00 games). The 15:00 games stay on. The order book recorder and in-play tape cover all of them anyway.
- Worth fixing after 17:00: raise the pre-off 40, or give the stream a second connection.

Not changed: REAL_MONEY_OFF, placer.py, dry runner, stream, cap, mechanic watch list (these 3 are not in it; their own wrapper loops restart them).
