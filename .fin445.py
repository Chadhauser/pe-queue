R='reports/finder_2026-11-08_item456.md'
p='/root/pe-queue/'+R
s=open(p).read()
def sub(a,b):
    global s
    assert s.count(a)==1, a[:60]
    s=s.replace(a,b)
sub("""- All three are interim; none can reach n 300 on one month.
""","""- All three are interim; none can reach n 300 on one month.
- Item 445 (jobs/499_jump_down_lay.sh, unchanged, 1,078 s, exit 0): its UNSEEN window (before Mar 2023) now holds Nov 2022 (part-loaded) to Feb 2023.
  - Scored UNSEEN MO ONE lay: n 556, +0.578, t 1.42, h1 +0.945, h2 +0.212. Up from n 219 +0.090 on Jan-Feb, so the Nov-Dec games read about +0.90.
  - For reading: OU25 OVER lay n 188 +0.457 (h2 -0.469); MO FAV lay n 286 +1.127 t 1.58. The audit, months that chose the signal, is MO ONE n 1,946 +0.076. It fails t, so it stays TODO.
""")
sub("""- Halves split at the game median, so n1 and n2 are uneven on W24; the part-loaded Nov 2022 is in, which does not bias a drift read.
""","""- Halves split at the game median (n1, n2 uneven on W24). Part-loaded Nov 2022 sits in 456, 458 and 445; once it is DONE, the 445 read must be re-run.
""")
sub(".add_458.py, .fin458.py.", ".add_458.py, .fin458.py, .trim456.py, .trim456b.py, .fin445.py.")
sub("""- The first run was killed by my own background timeout. The re-run covers every chunk (87 chunk lines, total 710 s).
""","")
open(p,'w').write(s); print('report lines',len(s.splitlines()))
q='/root/pe-queue/watchman/FINDER_QUEUE.md'
t=open(q).read()
a="445. TODO ("
assert t.count(a)==1
t=t.replace(a,"445. TODO (UPDATE 2026-11-08 14:40 UTC: UNSEEN now Nov 2022 (part-loaded) to Feb 2023, MO ONE lay n 556 +0.578 t 1.42 h1 +0.945 h2 +0.212, n clears 300 but t does not; MO FAV lay n 286 +1.127; OU25 OVER lay n 188 +0.457; re-run when Nov 2022 reads DONE and as each older month loads; jobs/499_jump_down_lay.sh unchanged, "+R+") (")
open(q,'w').write(t)
h='/root/pe-queue/watchman/HYPOTHESES.md'
u=open(h).read().rstrip('\n')+'\n'+"2026-11-08 | re-read (bf_hist_other, bf_hist_result, item 445) | jump-down lay with Nov-Dec 2022 in the unseen window (499_jump_down_lay unchanged) | DONE, interim | nothing passes; MO ONE lay n 556 +0.578 t 1.42, both halves positive; stays TODO\n"
open(h,'w').write(u)
print('ok')
