p = '/root/pe-queue/reports/finder_2026-11-07_item430.md'
s = open(p).read()
a = s.index("\n## Item 70 (recurring)\n"); b = s.index("Scratch files from this run")
s = s[:a] + "\nItem 70 (recurring): as the data health line above; 25 stale months. New hypotheses (appetite rule): 430, 431, 432, all tested above, and 433, TODO from 8 Nov.\n" + s[b:]
s = s.replace("\n\n## ", "\n## ")
s = s.replace("Nothing passes. Same sign as item 430, a quarter of the size, inside noise.", "Nothing passes. Same sign as item 430 and both halves positive, but under half the size and inside noise.")
open(p, 'w').write(s)
print(len(s.split('\n')))
