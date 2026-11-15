import subprocess, re
R = '/root/pe-queue/'
jobs = ['499_equaliser_side', '499_equaliser_stress', '499_equaliser_unseen', '499_equaliser_draw_unseen', '499_goal_type_guard', '499_pen_other_unseen']
print('1. syntax')
for j in jobs:
    p = R + 'jobs/' + j + '.sh'; s = open(p).read()
    b = subprocess.run(['bash', '-n', p], capture_output=True, text=True).returncode
    body = s.split("<<'PY'", 1)[1].split('\n', 1)[1].rsplit('\nPY', 1)[0]
    try: compile(body, j, 'exec'); c = 'OK'
    except SyntaxError as e: c = 'FAIL ' + str(e)
    print(f'  {j}: bash -n rc {b}, python compile {c}, set -o pipefail {"set -o pipefail" in s}, SURVIVORS {"SURVIVORS" in s}')
print('2. queue statuses')
q = open(R + 'watchman/FINDER_QUEUE.md').read().split('\n')
for n in ('430', '431', '432', '433', '434', '435'):
    l = [x for x in q if x.startswith(n + '. ')]
    print(f'  {n}: count {len(l)} status {l[0].split()[1] if l else None}')
print('  RUNNING left by this run:', [x[:5] for x in q if re.match(r'^43\d\. RUNNING', x)])
print('3. report lengths')
for f in ('finder_2026-11-07_item430.md', 'finder_2026-11-07_items433-434.md'):
    print(f'  {f}: {len(open(R + "reports/" + f).read().splitlines())} lines')
print('4. secrets scan of committed files')
pat = re.compile(r'postgres(ql)?://|password\s*=|sk-[A-Za-z0-9]{20}|railway\.app', re.I)
files = [R + 'jobs/' + j + '.sh' for j in jobs] + [R + 'reports/finder_2026-11-07_item430.md', R + 'reports/finder_2026-11-07_items433-434.md']
hits = [f for f in files if pat.search(open(f).read())]
print('  hits:', hits)
print('5. hypotheses lines for 430-435:', sum(1 for l in open(R + 'watchman/HYPOTHESES.md') if re.search(r'item 43[0-5]', l)))
print('6. git')
print(subprocess.run(['git', '-C', R, 'status', '-sb'], capture_output=True, text=True).stdout.split('\n')[0])
print(subprocess.run(['git', '-C', R, 'log', '--oneline', '-1', 'origin/main'], capture_output=True, text=True).stdout.strip())
print(subprocess.run(['git', '-C', R, 'log', '--oneline', '-1'], capture_output=True, text=True).stdout.strip())
print('  tracked changes:', subprocess.run(['git', '-C', R, 'status', '--short', '-uno'], capture_output=True, text=True).stdout.strip())
