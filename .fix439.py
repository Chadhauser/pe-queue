r='reports/finder_2026-11-08_item439.md'
s=open(r).read()
old="Win rates match implied within about 0.5 points in every cell (for example W80 50-200, won 0.010 against 0.010 implied), so there is no favourite-longshot bias here to collect. The lays come out about break-even after the tick and commission, which is the expected result, not an edge."
new=("On the lay side, win rates sit within 0.5 points of implied (for example W80 50-200, won 0.010 against 0.010), so laying collects nothing after the tick and 2%. "
"Backs win up to 1.1 points less than implied (ONE W80 10-20, 0.061 against 0.072), a small long-shot bias, but it is smaller than the spread a taker pays, so the lays still come out at about zero.")
assert s.count(old)==1; s=s.replace(old,new); open(r,'w').write(s)
q='watchman/FINDER_QUEUE.md'; t=open(q).read()
o2="win rates match implied in every cell, so no long-shot bias in running; "
assert t.count(o2)==1
t=t.replace(o2,"lay win rates within 0.5 points of implied, backs up to 1.1 points under, smaller than the taker's cost; "); open(q,'w').write(t)
h='watchman/HYPOTHESES.md'; u=open(h).read(); o3="won equals implied in every cell"
assert u.count(o3)==1; open(h,'w').write(u.replace(o3,"lay won within 0.5 points of implied, backs up to 1.1 under")); print('ok')
