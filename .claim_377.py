p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
t = open(p).read().rstrip('\n').split('\n')
assert not any(l.startswith(('377. ', '378. ')) for l in t)
t.extend([
 "377. RUNNING 2026-11-07 (Finder's own, source d; tables greyhound_racecards_today, bf_hist_other; job 499_greyhound_sex_sire, engine from jobs/499_greyhound_card_form.sh; items 233-235 read form, time, class, age and trainer, and sex, colour, reserve, sire and dam appear in no greyhound job) **A greyhound's sex, colour, reserve flag and breeding against the T-5 price.** Rationale: a punter reads the form and trap, not the breeding, and a bitch or a reserve may be priced on the same numbers as the rest. Rule fixed before any price: T-5 entry, bands <3, 3-6, 6-12, costs, join and bar as item 233, one row per dog per race. SEX each value with 300+ runners, COLOUR the five commonest, RESERVE the flag; back and lay by band; every runner in the band the control, which cannot pass. SIRE and DAM as item 238: error won minus 1/print, 100+ runners up to the date median, top ten back and bottom ten lay after it.",
 "378. RUNNING 2026-11-07 (Finder's own, source d; tables bf_hist_other, bf_hist_result; job 499_corner_lines; OVER_UNDER_85_CORNR, OVER_UNDER_105_CORNR and every corner line, OVER_UNDER_85 and FIRST_HALF_GOALS_35 appear in no job; a census pass, pre-off, official results) **Corner lines, Over 8.5 goals and first-half 3.5, before the off.** Rationale: thin lines nobody prices closely can carry a wider bias. Rule fixed before any price: first print T-15 to the off, one tick adverse, 2%, £10, official WINNER or LOSER, over 200 not traded. Over and Under, back and lay, each market type with 300+ priced runners, halves by date median, standard bar.",
])
open(p, 'w').write('\n'.join(t) + '\n')
print('ok')
