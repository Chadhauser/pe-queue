import re
p = 'watchman/FINDER_QUEUE.md'
L = open(p).read().split('\n')
notes = {
 '139': " (2026-11-07 claim: Soccer 2023-08 and 2023-09 DONE, so two Augusts are on the box; Aug 2025 stays LISTFAIL; rule unchanged, job 499_fh3_augs, fixtures by name for 2023 and 2024)",
 '184': " (2026-11-07 claim: af_events covers season 2023 and bf_hist_other Aug 2023 on, so unseen games exist now; rule unchanged, job 499_ht_cards_unseen, games not in af_price_map, Aug 2023 to Sep 2026; first print 60 to 71 min after kick-off, tape 47 being about KO+66, jobs/499_goal_timing.sh line 6)",
 '185': " (2026-11-07 claim: as item 184; rule unchanged, job 499_goal_type_unseen, E10 only is scored, tape minute to clock: first half +0, second half +19, jobs/499_goal_timing.sh line 6; a CLOCK check is printed)",
}
done = set()
for i, l in enumerate(L):
    m = re.match(r'(\d+)\. TODO', l)
    if m and m.group(1) in notes:
        n = m.group(1)
        L[i] = f"{n}. RUNNING 2026-11-07{notes[n]} —" + l[len(m.group(0)):]
        done.add(n)
assert done == set(notes), done
open(p, 'w').write('\n'.join(L))
print('claimed', sorted(done))
