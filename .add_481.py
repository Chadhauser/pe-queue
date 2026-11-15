p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
assert '\n481. ' not in s
s = s.rstrip('\n') + '\n' + (
    "481. RUNNING 2026-11-09 04:30 UTC (Finder's own, source c structural, from tonight's market census: CS 0-0 and Under 0.5 before the off were never read as a pair, only at half-time (item 408) and in play (item 106); tables bf_hist_other, bf_hist_result; job 499_cs00_u05_preoff) "
    "**When CS 0-0 and Under 0.5 disagree before the off, lay the dearer one or back the cheaper one, whichever printed later.** "
    "Rationale: they are the same event in two markets, CS is the thinner book, so a gap of a point or more may be one book lagging. "
    "Rule fixed now: last pre-off print of each within 30 min of market_time, at most 300 s apart; trade only the market whose print is the later one, so the other's print was already public and nothing is forward-filled; "
    "gap = 100*(1/p_cs - 1/p_u); scored LAY_RICH |gap|>=1 (later one is dearer, lay it) and BACK_CHEAP |gap|>=1 (later one is cheaper, back it); one bet a game, one tick adverse, £10 stake or liability, 2% on profit, held to the market's own official result, never dropped; women and youth out; halves by date median; standard bar.\n")
open(p, 'w').write(s)
h = '/root/pe-queue/watchman/HYPOTHESES.md'
t = open(h).read()
t = t.rstrip('\n') + '\n' + "2026-11-09 | c structural (bf_hist_other, bf_hist_result, market census) | CS 0-0 v Under 0.5 before the off, trade the later print: lay if dearer, back if cheaper (499_cs00_u05_preoff, item 481) | RUNNING | -\n"
open(h, 'w').write(t)
print('ok')
