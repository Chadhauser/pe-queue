p = '/root/pe-queue/reports/finder_2026-11-07_items17-393.md'
s = open(p).read()
a = "Rule fixes for items 390-393 follow item 129's prints only where the item says so; 391 and 393 were written after seeing 129's and 392's results, so a pass would have needed unseen games."
assert a in s
s = s.replace(a, "Item 390's rule was fixed before any price. Items 391, 392 and 393 were fixed after I had seen items 17, 129 and 172's results, and 393 after 392's audit, so a pass on 391 or 393 would have needed unseen games.")
open(p, 'w').write(s)
print('report lines', s.count('\n'))
f = '/root/pe-queue/.finish_388.py'
t = open(f).read()
a = "nothing passes; 0 of 12 scored, every R<0.5 ALL line negative"
assert a in t
open(f, 'w').write(t.replace(a, "nothing passes; 0 of 20 scored, every R<0.5 ALL line negative"))
