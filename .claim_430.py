p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
s = open(p).read()
assert '\n430. ' not in s
line = ("430. RUNNING 2026-11-07 (lane A; Finder's own, source a; tables af_events, af_fixtures, af_price_map, bf_hist_price; job 499_equaliser_side) "
        "**After a second-half equaliser to 1-1, back or lay the side that equalised, the side that scored first, or the Draw.** "
        "Rationale: no read in the ledger splits a level score by who just came back; the 2-2 and late-equaliser reads asked about the Draw or about goal detection only. "
        "Rule fixed before any price: second goal of the game makes it 1-1 at af minute E in 46-80, signal t = E+3, entry the first real MO print in tape minutes t+1..t+3, one tick adverse, "
        "£10 back stake or £10 lay liability, 2% on profit, held to the af FT score, never dropped; prices 1.01-50 only; one bet a game per line; splits E 46-65 v 66-80 and equaliser by the pre-match favourite v underdog; "
        "CONTROL first-half equalisers E 10-40, cannot pass; halves by season 2024 v 2025, standard bar.")
s = s.rstrip('\n') + '\n' + line + '\n'
open(p, 'w').write(s)
print('ok')
