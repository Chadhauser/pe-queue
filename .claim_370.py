p = '/root/pe-queue/watchman/FINDER_QUEUE.md'
t = open(p).read().rstrip('\n').split('\n')
i = max(k for k, l in enumerate(t) if l.startswith('368. '))
assert not any(l.startswith(('369. ', '370. ')) for l in t)
new = [
 "369. TODO (needs data — Cricket MATCH_ODDS after 30 Sep 2026, loader 347, tape stops there; about 12 W 6-20 and 45 W <1.5 games a month, so n 300 on the back about 7 months on, re-check 1 Dec 2026 with item 272; a real pre-off touch needs item 129's recorder; Finder's own, source c; table bf_hist_other, cricket_matches; job 499_cricket_women_stress unchanged except the window) **Women's cricket favourite under 1.5, and the 6-20 outsider lay, months the test has not seen.** Rationale: item 366's lean, on the same months that chose it; men show nothing on the same cuts, item 368, so it reads as women's and not thinness. Rule fixed now, no new cuts: as item 367, W <1.5 back and W 6-20 lay, one tick and five ticks, standard bar, official winner where matched.",
 "370. RUNNING 2026-11-07 (Finder's own, source c; table bf_hist_other; job 499_cricket_rematch, engine from jobs/499_cricket_women.sh; item 354 read a team's own error and item 318 a tennis rematch, a cricket series rematch was never read; same months as item 268, so a re-slice) **Cricket, the same two teams again within 3 days.** Rationale: associate and franchise series play back to back, sometimes twice a day, and the side that won yesterday may be overbet. Rule fixed before any price: two-runner games, the same two teams, previous game off 3 days or less earlier and its last in-play print before this entry window closes, previous result inferred as item 268, unresolved previous game skipped. Lines: previous WINNER and LOSER, back and lay; previous UPSET winner, the side priced longer at its last pre-off print, and its beaten favourite, back and lay; 8 lines, one row per side per game. Entry, costs and three ways of scoring as item 366; price at or under 20. Standard bar on all three scorings.",
]
t[i+1:i+1] = new
open(p, 'w').write('\n'.join(t) + '\n')
print('ok', i)
