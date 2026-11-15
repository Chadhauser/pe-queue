import sys
H = open('watchman/HYPOTHESES.md').read().lower()
Q = open('watchman/FINDER_QUEUE.md').read().lower()
for k in sys.argv[1:]:
    print(f"{k}: hyp {H.count(k.lower())} queue {Q.count(k.lower())}")
