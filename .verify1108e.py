import subprocess, re
def run(c):
    p = subprocess.run(c, shell=True, capture_output=True, text=True, cwd='/root/pe-queue')
    return p.returncode, (p.stdout + p.stderr).strip()
for j in ('jobs/499_bsp_loc.sh', 'jobs/499_bsp_loc_unseen.sh'):
    print('bash -n', j, run(f'bash -n {j}'))
    print('asserts', j, run(f'timeout 120 bash {j} asserts-only'))
print('local v origin', run('git fetch -q origin && git rev-parse HEAD origin/main'))
print('tracked', run('git ls-files jobs/499_bsp_loc.sh jobs/499_bsp_loc_unseen.sh reports/finder_2026-11-08_items468-469.md'))
print('report lines', len(open('/root/pe-queue/reports/finder_2026-11-08_items468-469.md').read().splitlines()))
q = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read()
for n in ('468', '469', '470', '471'):
    m = re.search(r'\n' + n + r'\. (\w+) ', q); print('queue', n, m.group(1) if m else None)
print('RUNNING left for 468-471', len(re.findall(r'\n(46[89]|47[01])\. RUNNING', q)))
print('creds/FINDER untouched by my commits', run('git log --format=%h -3 -- runner/creds.py watchman/FINDER.md | head -3'))
print('secret scan of my files', run("grep -l -i -E 'postgres(ql)?://|password=' jobs/499_bsp_loc.sh jobs/499_bsp_loc_unseen.sh reports/finder_2026-11-08_items468-469.md || echo none"))
