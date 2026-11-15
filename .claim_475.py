q='/root/pe-queue/watchman/FINDER_QUEUE.md'; h='/root/pe-queue/watchman/HYPOTHESES.md'
item=("475. RUNNING 2026-11-08 23:00 UTC (Finder, same run as 473-474; unseen games: bf_hist_other events not in af_price_map, Oct 2022 to Oct 2024 and May to Sep 2026, all countries) "
"(Finder's own, source a moves, from item 474's in-sample line G76+ g1 n 253 +0.786 t 4.44 h1 +0.522 h2 +1.075, won 0.941 v implied 0.851, after both bias fixes; "
"tables bf_hist_other (MATCH_ODDS, OVER_UNDER_05, OVER_UNDER_15 in play), bf_hist_result (official MO winner, market ids); job 499_late_lead_unseen) "
"**Back the leader at 1-0 three to six minutes after a first goal at about minute 76 or later, held to the result.** Rule fixed now, before any unseen price is read: "
"kick-off = first in-play MO print; first goal g1 = last in-play OU0.5 print, OU1.5 printing after g1 + 60 s; scorer = the side whose MO implied rose > 0.05 from its last print in [g1-600, g1-60] to its first in [g1, g1+180], the other not; "
"LATE = g1 at 93-106 min wall clock after kick-off (about 76-89 of game time with a 15 min break and 2 min of stoppage, an approximation), CTRL = 65-93 min; "
"entry = first leader print in [g1+180, g1+360] below its pre-goal print; second goal g2 = last OU1.5 print if the MO book prints 300 s past it: before entry-120 skip (known), within 120 s of entry the lowest leader print in [entry-180, entry+120]; "
"else the lower of the entry print and the next within 120 s; one tick adverse, GBP 10 back, 2% on profit, official MO result, never dropped; one entry per game; women and youth out; halves by date median; standard bar; scored line LATE ALL.")
s=open(q).read(); assert '\n475.' not in s
open(q,'w').write(s.rstrip('\n')+'\n'+item+'\n')
line="2026-11-08 | a moves (bf_hist_other, bf_hist_result, from 474) | back the leader at 1-0 3-6 min after a first goal at about 76'+, on games no af read has seen (499_late_lead_unseen, item 475) | RUNNING | -\n"
t=open(h).read(); open(h,'w').write(t.rstrip('\n')+'\n'+line); print('ok')
