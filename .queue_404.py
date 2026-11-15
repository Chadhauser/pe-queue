p = 'watchman/FINDER_QUEUE.md'
t = open(p).read()
assert '\n404. ' not in t
item = ("404. TODO (Finder's own, source a, from item 84; tables af_events, af_fixtures, bf_hist_other; job 499_var_off_unseen) "
        "**Lay the opponent after a goal cancelled by VAR at a level score, on games item 84 never read.** Rationale: item 84's best line, VAR_GOAL_OFF lay opponent E5 settle level n 348 +0.759 t 1.18 h1 +1.029 h2 +0.522, VAR rows even across seasons; best of 288, so likely chance, but an unseen read costs one job now. "
        "Rule fixed now, no new cuts: first Var / Goal cancelled row of the game at minute 85 or before, level on goals at that minute, games not in af_price_map, Aug 2023 to Sep 2026; lay the side opposite is_home on the MO, first print match minute c+5 to c+7, second half +19 on the clock, worse of it and the next within 120 s, one tick adverse, held to the result, 2%, £10 liability. Standard bar, halves by date. is_home's meaning on a VAR row is not checked, so TEAM and BACK lines are printed beside it, not scored.")
open(p, 'w').write(t.rstrip('\n') + '\n' + item + '\n')
print('added')
