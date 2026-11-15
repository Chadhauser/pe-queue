import subprocess, re, py_compile
R = '/root/pe-queue/'
def sh(c): return subprocess.run(c, shell=True, capture_output=True, text=True, cwd=R)
for j in ['499_inplay_map_unseen', '499_inplay_map_maker', '499_inplay_follow_move']:
    p = R + 'jobs/' + j + '.sh'
    r = sh('bash -n ' + p)
    s = open(p).read(); a = s.index("<<'PY'"); b = s.rindex('\nPY')
    open(R + '.v_' + j + '.py', 'w').write(s[s.index('\n', a) + 1:b])
    py_compile.compile(R + '.v_' + j + '.py', doraise=True)
    print(j, 'bash -n rc', r.returncode, '| py_compile OK | has SURVIVORS section', 'SURVIVORS' in s)
q = open(R + 'watchman/FINDER_QUEUE.md').read()
for n in ('488', '489', '490', '491'):
    m = re.search(r'\n' + n + r'\. (\S+ \S+)', q); print('queue', n, m.group(1) if m else 'MISSING')
print('report lines', len(open(R + 'reports/finder_2026-11-09_items488-490.md').read().splitlines()))
h = open(R + 'watchman/HYPOTHESES.md').read()
print('ledger 488-491 rows', sum(('(' + n + ')') in h for n in ('488', '489', '490', '491')))
print('fetch', sh('git fetch -q origin main').returncode)
print('local HEAD in origin/main:', sh('git branch -r --contains f3e245d').stdout.strip())
print('tracked changes not committed:', sh('git status --porcelain jobs/499_inplay_* reports/finder_2026-11-09_items488-490.md watchman/FINDER_QUEUE.md watchman/HYPOTHESES.md').stdout.strip() or 'none')
for f in ['jobs/499_inplay_map_unseen.sh', 'jobs/499_inplay_map_maker.sh', 'jobs/499_inplay_follow_move.sh', 'reports/finder_2026-11-09_items488-490.md']:
    t = open(R + f).read()
    print(f, 'secret-like strings:', len(re.findall(r'postgres(ql)?://|password=|app_key', t, re.I)))
