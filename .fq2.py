import re,sys
L=open('watchman/FINDER_QUEUE.md').read().split('\n')
for i,l in enumerate(L):
    m=re.match(r'\s*(\d+)\.\s+(TODO|RUNNING)',l)
    if m:
        print(i+1,l[:int(sys.argv[1]) if len(sys.argv)>1 else 330])
        print()
