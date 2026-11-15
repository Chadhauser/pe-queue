import re, subprocess, os, time, glob
lines = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read().split('\n')
for n in (317, 361, 451, 469, 524, 527, 528, 529):
    print(n, lines[n-1][:3500])
    print()
print('--- tail of file')
for l in lines[-6:]:
    print(l[:300])
print('--- wip')
now = time.time()
for f in sorted(glob.glob('/root/pe-queue/jobs/499_ht*')):
    print(f, int((now-os.path.getmtime(f))/60), 'min ago', os.path.getsize(f))
print('--- latest in repo root')
fs = sorted(glob.glob('/root/pe-queue/.*.py'), key=os.path.getmtime)[-8:]
for f in fs:
    print(f, int((now-os.path.getmtime(f))/60), 'min ago')
print(subprocess.run(['ps', '-eo', 'pid,etimes,cmd'], capture_output=True, text=True).stdout[:0])
for l in subprocess.run(['ps', '-eo', 'pid,etimes,cmd'], capture_output=True, text=True).stdout.split('\n'):
    if re.search(r'jobs/|claude|heredoc|tmp/.*py', l) and 'read_q' not in l:
        print(l[:180])
