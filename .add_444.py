p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
t = open(p).read()
assert '\n444. ' not in t
item = ("444. RUNNING 2026-11-08 (Finder's own, source a, from item 414; tables bf_hist_other, bf_hist_result; job 499_jump_up_ou25) "
        "**Item 414's jump-up back on Over/Under 2.5, a market the signal never read.** Rationale: item 414 found an MO runner whose first in-play print sits 2-4 implied points over its last pre-off print wins more than the price says, "
        "n 1,500 +1.321 t 3.21, every year positive bar 2026; that was chosen on MO, so OVER_UNDER_25 is a sample the rule has not seen (no OU read of this gap in the queue, HYPOTHESES.md or jobs, checked 8 Nov). "
        "Rule fixed now, before any OU price is read, item 414's code unchanged except the market: OVER_UNDER_25, 'Over 2.5 Goals' and 'Under 2.5 Goals'; last pre-off print from T-10 min to the first in-play print; first in-play print T-5 to T+3 min; "
        "UP24 = the in-play print 2 to under 4 implied points over the pre-off print; back at the worse of it and the next print within 120 s, one tick adverse, 2%, GBP 10, over 50 not traded; one bet a game, the larger gap; "
        "official bf_hist_result winner, never dropped; women and youth out; months Apr 2023 to Nov 2024 and May to Oct 2026 as loaded (Mar 2023 partial, out). "
        "Scored line ONE E1, standard bar, halves by date median. Printed, not scored: E2 next print, E3 three ticks, OVER and UNDER apart, by year, controls UP 1-2 and DOWN 2-4. A pass earns a real-touch read on liq_sample OU25, not a stake.")
if not t.endswith('\n'):
    t += '\n'
t += item + '\n'
open(p, 'w').write(t)
h = '/root/pe-queue/watchman/HYPOTHESES.md'
s = open(h).read()
if not s.endswith('\n'):
    s += '\n'
s += "2026-11-08 | a (bf_hist_other, bf_hist_result, from 414) | item 414's jump-up back on Over/Under 2.5 at the off, a market the signal never read (499_jump_up_ou25, item 444) | RUNNING | -\n"
open(h, 'w').write(s)
print('ok')
