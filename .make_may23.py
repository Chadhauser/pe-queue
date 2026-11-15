"""Build tonight's three re-reads from their parent jobs, changing the window only. Fails loudly if a target text is not found."""
import re, os
J = '/root/pe-queue/jobs/'
CHUNK = "[(2023,x) for x in range(6,13)]+[(2024,x) for x in range(1,12)]+[(2026,x) for x in range(5,11)]"
NEW = "[(2023,5)]"

def build(src, dst, subs):
    s = open(J + src).read()
    for a, b in subs:
        assert s.count(a) == 1, (src, a, s.count(a))
        s = s.replace(a, b)
    assert not os.path.exists(J + dst.replace('.wip', '')), dst
    open(J + dst, 'w').write(s)
    print('wrote', dst, len(s))

build('499_ht_identity_audit.sh', '499_ht_identity_may23.sh.wip', [
    (CHUNK, NEW),
    ("# 499_ht_identity_audit (Finder 2026-11-07, queue item 410, audit of item 407): HT/FT v MO at the break, on the first qualifying print, not the largest gap in the window.",
     "# 499_ht_identity_may23 (Finder 2026-11-07, queue item 420, first read): job 499_ht_identity_audit unchanged except the window, May 2023 only, unseen by item 407. Scored line HTFT G2 CHEAP back; every other line is for reading only."),
    ('print("SURVIVORS\\nnone by construction, the months chose this line; numeric passes above read PASS True",flush=True)',
     'print("SURVIVORS\\nnone possible yet, scored line is under n 300 on one month",flush=True)'),
])
build('499_ht_women_youth.sh', '499_ht_youth_may23.sh.wip', [
    (CHUNK, NEW),
    ("# 499_ht_women_youth (Finder 2026-11-07, queue item 409, Finder's own, source c): women's and youth goal lines at the half-time break, state from the official half-time score.",
     "# 499_ht_youth_may23 (Finder 2026-11-07, queue item 421, first read): job 499_ht_women_youth unchanged except the window, May 2023 only, unseen by item 409. Scored line YOUTH G1 25 lay; every other line is for reading only."),
])
build('499_ht_cards_unseen.sh', '499_ht_cards_older.sh.wip', [
    ("A,B='2023-08-01','2026-10-01'", "A,B='2023-05-01','2023-08-01'"),
    ("PASS=l['PASS'] and V=='RULE' and Y=='Y23' and s=='LAY'", "PASS=l['PASS'] and V=='RULE' and Y=='Y4' and s=='BACK'"),
    ("Z=T[(T['var']=='RULE')&(T.Y=='Y23')&(T.side=='LAY')]", "Z=T[(T['var']=='RULE')&(T.Y=='Y4')&(T.side=='BACK')]"),
    ("# 499_ht_cards_unseen (Finder 2026-11-07, queue item 184, Finder's own, source d;",
     "# 499_ht_cards_older (Finder 2026-11-07, queue item 406, first read: job 499_ht_cards_unseen unchanged except the window May to Jul 2023 and the scored line, RULE OU25 G0 Y4 back; parent: queue item 184, Finder's own, source d;"),
])

# claim in the queue, RUNNING with an honest note
Q = '/root/pe-queue/watchman/FINDER_QUEUE.md'
q = open(Q).read().split('\n')
n = 0
for i, l in enumerate(q):
    m = re.match(r'^(406|420|421)\. TODO ', l)
    if m:
        q[i] = l.replace(m.group(1) + '. TODO ', m.group(1) + '. RUNNING 2026-11-07 (first read, Soccer 2023-05 holds 47,356 of 47,357 files, PARTIAL with 1 left) TODO-after ', 1)
        n += 1
assert n == 3, n
open(Q, 'w').write('\n'.join(q))
print('claimed', n)
