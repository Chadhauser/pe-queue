q='/root/pe-queue/watchman/FINDER_QUEUE.md'; h='/root/pe-queue/watchman/HYPOTHESES.md'
item=("474. RUNNING 2026-11-08 22:50 UTC (Finder, same run as 473; IN-SAMPLE read on 473's two seasons, so it cannot pass, it only sizes the lead for an unseen read) "
"(Finder's own, source a moves, from item 473's control C5 BACK_M T>60 n 754 +1.023 t 3.41 h1 +0.748 h2 +1.293; tables bf_hist_price, af_events, af_price_map; job 499_post_goal_back) "
"**Back the current Match Odds result 3-6 min after a goal, any Under price.** Rationale: 473's late lean sat in its controls, not the bound, so it may be a post-goal under-reaction, not an Under signal; "
"every goal leaving 1-4 goals, first fresh MO print of the current result in goal+3..+6 (same guard as 473), back to the af result; lines by goal minute band, LEVEL/LEAD, goals, and 473's GAP class; scored line G61+ ALL.")
s=open(q).read(); assert '\n474.' not in s
open(q,'w').write(s.rstrip('\n')+'\n'+item+'\n')
line="2026-11-08 | a moves (bf_hist_price, af_events, from 473) | back the current MO result 3-6 min after a goal, any Under price, in-sample sizing of 473's late control lean (499_post_goal_back, item 474) | RUNNING | -\n"
t=open(h).read(); open(h,'w').write(t.rstrip('\n')+'\n'+line); print('ok')
