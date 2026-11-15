import re, py_compile, subprocess
src = open('/root/pe-queue/jobs/499_season_open.sh').read()
body = src.split("<<'PY'", 1)[1].split('\nPY\n', 1)[0].split('\n', 1)[1]
open('/tmp/heredoc428.py', 'w').write(body)
py_compile.compile('/tmp/heredoc428.py', doraise=True)
print('1 py_compile heredoc: OK')
print("2 old bug gone:", 'Y.div.isin' not in src, "| fix present:", "Y['div'].isin(TOP)" in src)
q = open('/root/pe-queue/watchman/FINDER_QUEUE.md').read().split('\n')
for l in q:
    if re.match(r'^(428|429)\. ', l) or l.startswith('70. TODO (recurring'):
        print('3 queue:', l[:150])
h = open('/root/pe-queue/watchman/HYPOTHESES.md').read().rstrip('\n').split('\n')
print('4 ledger last two:'); [print('   ', x[:150]) for x in h[-2:]]
r = open('/root/pe-queue/reports/finder_2026-11-07_item428.md').read()
print('5 report lines:', r.count('\n'), '| has verdict:', '## Verdict' in r, '| DSN-like text:', bool(re.search(r'postgres(ql)?://', r)))
out = open('/tmp/claude-0/-root-pe-queue/f8da5700-e41c-44fc-bdd7-25e73a93d8f5/tasks/bobfkzdsz.output').read()
print('6 job log tail:', [x for x in out.split('\n') if x.startswith(('== SURVIVORS', 'total', '[exited'))])
