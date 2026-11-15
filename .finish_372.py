import os
os.chdir('/root/pe-queue')
for j in ('rest_inplay', 'last_race', 'payday', 'alt_line_arb', 'rank_trend', 'greyhound_sex_sire', 'corner_lines', 'ip_touch_level', 'tick_touch_level', 'ip_low_print_all'):
    a, b = f'jobs/499_{j}.sh.wip', f'jobs/499_{j}.sh'
    assert os.path.exists(a) and not os.path.exists(b), j
    os.rename(a, b)
R = 'reports/finder_2026-11-07_items372-383.md'
D = {
 '372': f"DONE 2026-11-07 — nothing passes, 0 of 258; a resting lay fills on nearly every winner, win LAY 2.0 n 18,817 -3.887 t by race -106.52, won 0.688 v 0.495; win LAY 5 n 22,671 -1.699; win BACK 20 n 66,364 -5.327; jobs/499_rest_inplay.sh ({R})",
 '373': f"DONE 2026-11-07 — nothing passes, 0 of 36; LAST_MEET 30+ back n 1,782 -4.361 t by race -3.08, won 0.010 v 0.014, against MID 30+ back -1.706, so the published lean shows, but its lay is only +0.029 t 1.24; LAST_MEET <=3 back n 319 +0.799 t 1.21; jobs/499_last_race.sh ({R})",
 '374': f"DONE 2026-11-07 — nothing passes, racing 0 of 12, football 0 of 12; GB, 15 PAY Saturdays, 3-6 back n 977 +0.729 t by race 1.43 h1 +0.516 h2 +0.941; football 619 games, DOG 3-4 back n 249 +0.974 t 0.97; jobs/499_payday.sh ({R})",
 '375': f"DONE 2026-11-07 — nothing passes; 26.4M rows, 8 days, order holds 0.94-0.99; 99 crossed episodes across 34 markets, 1 still crossed 5 s on, £1.05; these ladders do not cross at the touch; jobs/499_alt_line_arb.sh ({R})",
 '376': f"DONE 2026-11-07 — not supported, 0 of 8 at z 2, ATP only as the table holds; best FALLER 3-6 lay n 208 z 1.08, +0.594 t 1.54; RISER <1.5 z -1.41 against the idea; jobs/499_rank_trend.sh ({R})",
 '377': f"DONE 2026-11-07 — nothing passes, 0 of 42; 5,638 races; black <3 lay n 1,813 +0.555 t by race 2.61 h1 +0.855 h2 +0.255, against every runner <3 lay +0.331 t 2.13; sire 18 with 100+ runners and dam 0, under the 20 needed, no lines; reserves 0 in bands; the first run's t 8 was a code fault, fixed before use; jobs/499_greyhound_sex_sire.sh ({R})",
 '378': f"BLOCKED 2026-11-07 — bf_hist_result holds none of these market types, no price read; corner lines also exist on Sep 2026 only, 198 and 196 markets, under n 300; needs the loader to keep their results and earlier months; jobs/499_corner_lines.sh ({R})",
 '379': f"DONE 2026-11-07 — cannot read the idea, 0 of 22; 270 races with one winner, 49.7% of rows replays, clean frames a median 33.7 s apart, longer than the run-in; so item 380 on ticks; jobs/499_ip_touch_level.sh ({R})",
 '380': f"DONE 2026-11-07 — nothing passes, 0 of 48, a lead under n; 166 races, 2-6 Nov; Q 1.1 back delay 1 s n 99 +0.742 t by race 4.93 h1 +0.756 h2 +0.729, won 0.990 v 0.918; Q 1.2 back n 126 +0.898 t 3.79 h1 +1.289 h2 +0.507; delay 3 s +0.520 t 2.69 and +0.606 t 1.93; item 382 re-reads it unseen; jobs/499_tick_touch_level.sh ({R})",
 '381': f"DONE 2026-11-07 — a description; at the fill, Q 1.1 median £47 on show, 80% at £10+, 22% at £200+, 16 s from the race's last tick, 1 loser in 99; Q 1.2 median £35, 72% at £10+, 8 losers in 126; taking the lesser of £10 and the size on show +0.567 and +0.764; jobs/499_tick_touch_level.sh ({R})",
 '383': f"DONE 2026-11-07 — no read; minute prints, median low print 1.01, 5,448 entries at Q 1.1, of which 187 can be backed; the first low print is nearly always the post; neither supports nor weakens item 380; jobs/499_ip_low_print_all.sh ({R})",
}
p = 'watchman/FINDER_QUEUE.md'
t = open(p).read().rstrip('\n').split('\n')
done = set()
for i, l in enumerate(t):
    for k, v in D.items():
        pre = f'{k}. RUNNING 2026-11-07 '
        if l.startswith(pre):
            t[i] = f'{k}. {v} — ' + l[len(pre):]
            done.add(k)
    if l.startswith('382. TODO (needs data — stream_ticks racing after 7 Nov 09:00 UTC, about 33 races a day;'):
        t[i] = l.replace('382. TODO (needs data — stream_ticks racing after 7 Nov 09:00 UTC, about 33 races a day;', "382. TODO (needs data — the stream restarted first: its market list has been frozen since 21:20 UTC 6 Nov, Peter's yes outstanding, so no new race reaches stream_ticks and the dates here move day for day until it is fixed; then stream_ticks racing after 7 Nov 09:00 UTC, about 33 races a day;", 1)
        done.add('382')
assert done == set(D) | {'382'}, done
open(p, 'w').write('\n'.join(t) + '\n')
L = """2026-11-07 | b (racing_bsp) | rest a bet in running, lay the field low, back it high (499_rest_inplay, item 372) | DONE | nothing passes; 0 of 258; win LAY 2.0 n 18,817 -3.887, fills on nearly every winner
2026-11-07 | b (racing_bsp, bf_hist_other) | the last race of the card, full card (499_last_race, item 373) | DONE | nothing passes; 0 of 36; LAST_MEET 30+ lay n 1,782 +0.029 t 1.24
2026-11-07 | c (racing_bsp, af_fixtures, bf_hist_price) | the Saturday after UK payday (499_payday, item 374) | DONE | nothing passes; 0 of 24; PAY 3-6 back n 977 +0.729 t by race 1.43
2026-11-07 | c (ip_tape) | riskless cross between neighbouring alternative lines, other sports (499_alt_line_arb, item 375) | DONE | nothing passes; 99 episodes in 26.4M rows, 1 lasted 5 s
2026-11-07 | d (tennis_matches) | ranking rise or fall at Pinnacle closes, ATP (499_rank_trend, item 376) | DONE | not supported; 0 of 8; FALLER 3-6 z 1.08
2026-11-07 | d (greyhound_racecards_today, bf_hist_other) | greyhound sex, colour, reserve, sire, dam (499_greyhound_sex_sire, item 377) | DONE | nothing passes; 0 of 42; black <3 lay n 1,813 +0.555 t by race 2.61 v control +0.331
2026-11-07 | d (bf_hist_other) | corner lines, OU8.5, FH3.5 before the off (499_corner_lines, item 378) | BLOCKED | no official results; corners Sep 2026 only
2026-11-07 | a (ip_tape, racing_results) | first in-play touch of a level, frames (499_ip_touch_level, item 379) | DONE | cannot read; clean frames 33.7 s apart
2026-11-07 | a (stream_ticks, racing_results) | first in-play touch of a level, ticks (499_tick_touch_level, item 380) | DONE | a lead under n; 0 of 48; Q 1.1 back n 99 +0.742 t by race 4.93; Q 1.2 back n 126 +0.898 t 3.79
2026-11-07 | a (stream_ticks) | size and losers on item 380's two lines (499_tick_touch_level, item 381) | DONE | median £47 and £35 on show; 1 and 8 losers
2026-11-07 | a (stream_ticks, finder_touch_entries) | back at the first touch of 1.1 and 1.2, unseen races, rule fixed | TODO (item 382, needs the stream restarted) | -
2026-11-07 | a (bf_hist_other, racing_bsp) | first low print on the minute tape (499_ip_low_print_all, item 383) | DONE | no read; the low print is nearly always the post, median 1.01
"""
h = 'watchman/HYPOTHESES.md'
s = open(h).read()
if not s.endswith('\n'):
    s += '\n'
open(h, 'w').write(s + L)
print('ok')
