p='/root/pe-queue/watchman/FINDER_QUEUE.md'
s=open(p).read()
R='reports/finder_2026-11-08_item456.md'
a="458. RUNNING 2026-11-08 (lane A, 14:08 UTC)"
assert s.count(a)==1
s=s.replace(a,"458. DONE 2026-11-08 — nothing passes; 0 of 30; 42,930 games, 158,556 trades; best W24 1.01-1.6 lay n 769 +0.132 t 0.66 h1 +0.122 h2 +0.141; Overs do not shorten into the off (W24 OVER lay n 3,029 -0.018); short-price lay folded into item 457 as a sub-line; jobs/499_ou25_premarket_drift.sh, "+R+" (lane A, 14:08 UTC)")
b="**Rest a lay on an 8-20 MO runner hours before kick-off, out at the last pre-off touch.**"
assert s.count(b)==1
s=s.replace(b,b+" Sub-line from item 458: the same resting lay on OU2.5 runners priced 1.01-1.6 at KO-24 h (taker n 769 +0.132 t 0.66).")
open(p,'w').write(s)
h='/root/pe-queue/watchman/HYPOTHESES.md'
t=open(h).read()
c="(499_ou25_premarket_drift, item 458) | RUNNING | -"
assert t.count(c)==1
t=t.replace(c,"(499_ou25_premarket_drift, item 458) | DONE | nothing passes; 0 of 30; best W24 1.01-1.6 lay n 769 +0.132 t 0.66; Overs do not shorten into the off")
open(h,'w').write(t)
print('ok')
