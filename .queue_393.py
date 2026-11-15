p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
assert '\n393. ' not in s
if not s.endswith('\n'): s += '\n'
s += ("393. RUNNING 2026-11-07 — (Finder's own, source a; tables stream_ticks, finder_rresults; job 499_touch_collapse; from item 392's audit, table finder_rlog) "
      "**A horse at 1.1 whose back price then collapses past 2.0: real, or a dead book?** Rationale: item 392's audit, of 31 runners seen at 1.1 or under whose next 30 s row had a back above 2.0, 27 won, e.g. 1.10 then back 27 lay 140; the log has no market status and no size, so these may be unfillable. Rule fixed now, before any tick is read: stream_ticks racing WIN, in play, status OPEN only; first tick back <= 1.1 after a first in-play back above 1.1; then the first OPEN tick within 120 s with back >= 2.0. Print n touches, n collapsed, won, seconds from the touch, the back price and the size on show at it, and the lay on the same tick. P&L at that back, one tick adverse, 2%, £10 at most the size shown, to result, one winner only. About 5 days of ticks, so this reads whether the thing exists; it cannot reach n 300.\n")
open(p, 'w').write(s)
j = '/root/pe-queue/jobs/499_touch_log_pull.sh.wip'
t = open(j).read()
a = "START, END = dt.date(2026, 9, 7), dt.date(2026, 11, 7)"
assert t.count(a) == 1
t = t.replace(a, "END = dt.datetime.now(dt.timezone.utc).date()   # whole days only\n"
    "def start_of(tgt):\n"
    "    lc.execute(f\"select max(captured_at) from {tgt}\"); m = lc.fetchone()[0]\n"
    "    return m.astimezone(dt.timezone.utc).date() if m else dt.date(2026, 9, 7)   # top up from the last day held, so a re-run does not re-copy everything")
b = "    d = START; tot = 0; t0 = time.time()"
assert t.count(b) == 1
t = t.replace(b, "    d = start_of(tgt); tot = 0; t0 = time.time()")
open(j, 'w').write(t)
print('ok')
