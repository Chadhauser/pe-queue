import re, sys
txt = open('watchman/HYPOTHESES.md').read() + open('watchman/FINDER_QUEUE.md').read()
for k in sys.argv[1:]:
    hits = [m.start() for m in re.finditer(re.escape(k), txt, re.I)]
    print(k, len(hits))
    for h in hits[:4]:
        print('   ', txt[max(0, h-120):h+160].replace('\n', ' '))
