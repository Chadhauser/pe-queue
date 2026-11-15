import os, time
boot = float(open('/proc/stat').read().split('btime ')[1].split()[0])
hz = os.sysconf('SC_CLK_TCK')
now = time.time()
for p in os.listdir('/proc'):
    if not p.isdigit():
        continue
    try:
        c = open(f'/proc/{p}/cmdline').read().replace('\0', ' ')
        st = open(f'/proc/{p}/stat').read().rsplit(')', 1)[1].split()
        start = boot + int(st[19]) / hz
    except OSError:
        continue
    if ('claude -p' in c or 'jobs/' in c or '.wip' in c or 'Finder' in c[:200]) and 'procs.py' not in c:
        print(p, os.getppid() if False else st[1], f'{(now-start)/60:.0f}min', c[:90])
print('self parent chain', os.getppid())
for l in open('/proc/meminfo').read().split('\n')[:3]:
    print(l)
