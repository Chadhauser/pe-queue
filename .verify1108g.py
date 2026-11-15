import re, subprocess, py_compile
R = '/root/pe-queue/'
for j in ('jobs/499_nogoal_move.sh', 'jobs/499_nogoal_move_wide.sh'):
    s = open(R + j).read()
    body = s.split("<<'PY'", 1)[1].split('\n', 1)[1].rsplit('\nPY', 1)[0]
    open('/tmp/v_heredoc.py', 'w').write(body)
    py_compile.compile('/tmp/v_heredoc.py', doraise=True)
    print(j, 'heredoc py_compile OK')
    print(j, 'bash -n rc', subprocess.run(['bash', '-n', R + j]).returncode)
    r = subprocess.run(['bash', R + j, 'asserts-only'], capture_output=True, text=True)
    print(j, 'asserts-only:', r.stdout.strip(), 'rc', r.returncode)
q = open(R + 'watchman/FINDER_QUEUE.md').read().split('\n')
for l in q:
    m = re.match(r'^(46[345])\. (\S+ \S+)', l)
    if m: print('queue', m.group(1), m.group(2))
print('RUNNING items left by this run:', [l[:12] for l in q if re.match(r'^46[345]\. RUNNING', l)])
h = open(R + 'watchman/HYPOTHESES.md').read().split('\n')
print('ledger lines for 463-465:', sum(1 for l in h if re.search(r'item 46[345]\)', l)))
rep = open(R + 'reports/finder_2026-11-08_items463-464.md').read()
print('report lines', len(rep.split('\n')))
print('secret-like strings in report/jobs:', bool(re.search(r'postgres(ql)?://|password|sk-[A-Za-z0-9]', rep + open(R + 'jobs/499_nogoal_move.sh').read() + open(R + 'jobs/499_nogoal_move_wide.sh').read(), re.I)))
print(subprocess.run(['git', '-C', R, 'log', '--oneline', '-1', 'origin/main', '--', 'reports/finder_2026-11-08_items463-464.md'], capture_output=True, text=True).stdout.strip())
print('unpushed commits:', subprocess.run(['git', '-C', R, 'log', '--oneline', 'origin/main..main'], capture_output=True, text=True).stdout.strip() or 'none')
