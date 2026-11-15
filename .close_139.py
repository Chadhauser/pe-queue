import os, re
R = 'reports/finder_2026-11-07_items139-406.md'
p = 'watchman/FINDER_QUEUE.md'
L = open(p).read().rstrip('\n').split('\n')
done = {
 '139': "DONE 2026-11-07 — nothing passes; two Augusts n 717 -0.714 t -0.45 h1 -3.329 h2 +1.684, won 0.053 v 0.065, Septembers control n 887 -1.053; Aug 2025 still LISTFAIL; first read void, look-ahead in the goal filter; jobs/499_fh3_augs.sh",
 '184': "DONE 2026-11-07 — nothing passes; G0 Y23 lay n 861 +0.020 t 0.13 h1 -0.128 h2 +0.187, won 0.172 v 0.176; in the break n 713 +0.100 t 0.56; first read +0.353 t 2.27 void, look-ahead in the goal filter; next door item 406; jobs/499_ht_cards_unseen.sh",
 '185': "DONE 2026-11-07 — nothing passes; PEN Over 2.5 back E10 n 338 -0.481 t -0.79 h1 -0.924 h2 -0.005, won 0.544 v 0.524; E5 n 443 +0.333 t 0.56; jobs/499_goal_type_unseen.sh",
 '403': "DONE 2026-11-07 — under n, cannot pass; n 57 -0.413 t -0.27 h1 -4.616 h2 +3.370; only 25 first missed penalties on season 2023 games, so item 86's missing rows go wider than 2025; jobs/499_goal_type_unseen.sh",
 '404': "DONE 2026-11-07 — nothing passes; OPP lay level n 282 +0.323 t 0.67 h1 +0.985 h2 -0.330, won 0.245 v 0.259, +0.056 less its largest win; jobs/499_var_off_unseen.sh",
 '405': "DONE 2026-11-07 — nothing passes; all 15 months n 5,489 +0.060 t 1.07 h1 +0.090 h2 +0.028, won 0.058 v 0.060; 11 unread months n 3,885 +0.083 t 1.12; first read +0.166 t 2.92 void, look-ahead in the goal filter; jobs/499_fh3_lay_older.sh",
}
notes = {
 '342': "(UPDATE 2026-11-07: Aug 2023 n 5, all lost; jobs/499_aug23_rereads.sh, " + R + ") ",
 '352': "(UPDATE 2026-11-07: Aug 2023 BOTH home lay n 32 -0.093 t -0.06, RALLY under 2.0 n 4 -4.747; jobs/499_aug23_rereads.sh, " + R + ") ",
 '86': "(NOTE 2026-11-07: season 2023 is short as well, 25 first missed penalties on matched unmapped games, against 2,412 penalty goals across all season 2023 fixtures, item 403) ",
 '124': "(NOTE 2026-11-07: older months read flat, item 405 n 5,489 +0.060 t 1.07) ",
}
seen = set()
for i, l in enumerate(L):
    m = re.match(r'(\d+)\. (RUNNING 2026-11-07|TODO)', l)
    if not m: continue
    n = m.group(1)
    if n in done and (m.group(2).startswith('RUNNING') or n in ('404', '405')):
        L[i] = f"{n}. {done[n]} ({R}) —" + l[len(m.group(0)):]
        seen.add(n)
    elif n in notes:
        L[i] = f"{n}. TODO {notes[n]}" + l[len(m.group(0)):].lstrip()
        seen.add(n)
    elif n == '70' and 'recurring' in l:
        k = l.index(' — ') + 3
        L[i] = l[:k] + f"2026-11-07 about 14:38 UTC: 15,729 files in the last hour, disk free 64 GB, local DB 56 GB; Soccer 2023-08 DONE, 18 months Nov 2024 to Apr 2026 still LISTFAIL ({R}). " + l[k:]
        seen.add('70')
assert seen == set(done) | set(notes) | {'70'}, seen
assert not any(re.match(r'406\. ', l) for l in L)
L.append("406. TODO (first read when Soccer 2023-05 reads DONE, about 8 Nov, then 14 Nov as older seasons load; about 60 to 80 trades a season, so n 300 needs about four more seasons; Finder's own, source a, from item 184; tables af_events, af_fixtures, bf_hist_other; job 499_ht_cards_unseen unchanged except the window) **Back Over 2.5 at 0-0 at half-time after four or more first-half yellows, older seasons.** Rationale: item 181's mapped games G0 Y4 back n 182 +0.483 t 0.26 h1 +0.634 h2 +0.325; item 184's unseen games n 138 +2.796 t 1.34 h1 +5.518 h2 +0.075, won 0.246 v 0.193, largest win £98; item 184's lay side is flat, so this is the one card state still leaning. Post hoc from 6 lines, so likely chance. Rule fixed now, no new cuts: RULE read, first in-play print 60 to 71 min after kick-off, no second-half goal at or before the print, no cushion, worse of it and the next print within 120 s, one tick adverse, 2%, £10, held to the result, first-half red out, no substitution row out, games kicked off before Aug 2023 only, standard bar, halves by date, also read without the largest win. A pass earns a real-touch read on liq_sample, not a stake.")
open(p, 'w').write('\n'.join(L) + '\n')
led = 'watchman/HYPOTHESES.md'
t = open(led).read().rstrip('\n')
t += """
2026-11-07 | c structural (bf_hist_other, af_events) | back FH25 Over at 15 min at 0-0, two Augusts (499_fh3_augs, item 139) | DONE | nothing passes; n 717 -0.714 t -0.45
2026-11-07 | d (af_events, bf_hist_other) | lay Over 2.5 at 0-0 HT after 2-3 yellows, unseen (499_ht_cards_unseen, item 184) | DONE | nothing passes; n 861 +0.020 t 0.13; first read void, look-ahead
2026-11-07 | a (af_events, bf_hist_other) | back Over 2.5 ten minutes after a first-goal penalty, unseen (499_goal_type_unseen, item 185) | DONE | nothing passes; n 338 -0.481 t -0.79
2026-11-07 | a (af_events, bf_hist_other, from 84) | back Over 2.5 after a missed penalty, unseen (499_goal_type_unseen, item 403) | DONE | under n; n 57 -0.413; af_events short of missed penalties in season 2023 too
2026-11-07 | a (af_events, bf_hist_other, from 84) | lay opponent after a VAR goal off at level, unseen (499_var_off_unseen, item 404) | DONE | nothing passes; n 282 +0.323 t 0.67, h2 negative
2026-11-07 | c (bf_hist_other, from 124, 138, 139) | lay FH25 Over at 15 min at 0-0, 15 older months (499_fh3_lay_older, item 405) | DONE | nothing passes; n 5,489 +0.060 t 1.07; first read void, look-ahead
2026-11-07 | a (af_events, bf_hist_other, from 184) | back Over 2.5 at 0-0 HT after 4+ first-half yellows, older seasons, rule fixed | TODO (item 406, first read about 8 Nov) | -
"""
open(led, 'w').write(t)
for j in ('499_ht_cards_unseen', '499_goal_type_unseen', '499_fh3_augs', '499_fh3_lay_older', '499_var_off_unseen', '499_aug23_rereads'):
    a, b = f'jobs/{j}.sh.wip', f'jobs/{j}.sh'
    assert not os.path.exists(b), b
    os.rename(a, b)
print('closed', sorted(seen, key=int))
