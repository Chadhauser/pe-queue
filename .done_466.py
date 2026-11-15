Q = '/root/pe-queue/watchman/FINDER_QUEUE.md'
H = '/root/pe-queue/watchman/HYPOTHESES.md'
L = open(Q).read().rstrip('\n').split('\n')
i = [k for k, l in enumerate(L) if l.startswith('466. RUNNING 2026-11-08')]
assert len(i) == 1
res = ("466. DONE 2026-11-08 — nothing passes; 0 of 1,431 (1,244 at n>=300, 102 positive, none t over 1.9); take-profit loses in every code and trip: win BACK_TP0.5 n 130,903 -3.696 fill 0.331, CHASE LONG BACK_TP0.67 -2.513 fill 0.521 v FLAT SPRINT -4.212 fill 0.405, LAY_TP2.0 n 128,391 -0.312; "
       "winners nearly always trade through the resting lay, losers less than a fair path implies (fill 0.331 v about 0.5), item 372's asymmetry again, sent to item 467; best lines are BSP to result: place HURDLE SHORT 12-30 back n 753 +3.077 t 1.86, win CHASE 3-6 lay n 3,204 +0.159 t by race 2.15; "
       "place fields thin (fill 1-8%, 5,941 of 12,519 place markets matched to a race); first run dropped every place market ('To Be Placed' has no trip), fixed once; jobs/499_race_trip_tp.sh, reports/finder_2026-11-08_item466.md — ")
L[i[0]] = res + L[i[0]][len('466. RUNNING 2026-11-08 '):]
L.append("467. TODO (from 10 Nov with item 382, stream_ticks racing after 7 Nov 09:00 UTC, every 3 days as the table rolls; Finder's own, source a, next door of item 466; tables stream_ticks, racing_results, racing_bsp or the stream's own pre-off last trade as the BSP stand-in; job 499_half_bsp_touch to write from jobs/499_tick_touch_level.sh) "
         "**Back a horse a second after its first in-play trade at or under half its pre-off price, on races the test has not seen.** Rationale: item 466, on 130,903 UK/IE win runners a resting lay at BSP x 0.5 is traded through on 0.331 of runners against about 0.5 a fair price path would give, and winners nearly always trade through, so a horse that has halved in running wins well above 1/price; item 380 found the same at the fixed levels 1.1 and 1.2 (Q 1.1 n 99 +0.742 t by race 4.93) but never read a level relative to the pre-off price, where most runners pass. "
         "Rule fixed now: item 380's engine unchanged (first in-play tick at or under the level, back at the real best back 1 s later, delay 3 s as the stress, one tick adverse only where the engine adds it, £10, 2%, official result, never dropped), level = 0.5 x the last pre-off traded price, and 0.67 x and 0.33 x printed beside it; bands on the pre-off price <=3, 3-6, 6-12, 12-30; one entry per runner; t clustered by race; standard bar; entries saved to finder_touch_entries.")
open(Q, 'w').write('\n'.join(L) + '\n')
HL = open(H).read().rstrip('\n').split('\n')
j = [k for k, l in enumerate(HL) if '(499_race_trip_tp, item 466) | RUNNING' in l]
assert len(j) == 1
HL[j[0]] = HL[j[0]].replace('| RUNNING | -', '| DONE | nothing passes; 0 of 1,431; take-profit loses in every code and trip, BACK_TP0.5 -3.696 fill 0.331 v about 0.5 fair; best BSP to result place HURDLE SHORT 12-30 back n 753 +3.077 t 1.86')
HL.append("2026-11-08 | a moves (stream_ticks, from 466) | back a horse 1 s after its first in-play trade at or under half its pre-off price, unseen races (item 467) | TODO (from 10 Nov with 382) | item 466 BACK_TP0.5 fill 0.331 v about 0.5 fair, winners nearly always trade through")
open(H, 'w').write('\n'.join(HL) + '\n')
print('ok')
