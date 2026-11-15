p='/root/pe-queue/reports/finder_2026-11-08_item456.md'
s=open(p).read()
a="646 had no exit and no result, so they are unscored.\n- Runtime 433 s, exit 0.\n"
assert s.count(a)==1
s=s.replace(a,"646 had no exit and no result, so they are unscored. Runtime 433 s, exit 0.\n")
open(p,'w').write(s); print(len(s.splitlines()))
