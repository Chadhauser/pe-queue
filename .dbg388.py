import re, sys
sys.path.insert(0, '/root/pe-queue/jobs')
s = open('/root/pe-queue/jobs/499_touch_log_racing.sh.wip').read()
body = re.search(r"<<'PY'[^\n]*\n(.*)\nPY\n", s, re.S).group(1).split('\n')
print(39, body[38])
from lib_cand import step, lay_hedge
print('step 5 up', step(5.0, 1), 'hedge a', lay_hedge(step(5.0, 1), 5.0))
print('hedge b', lay_hedge(5.0, 4.0), 'step 4 down', step(4.0, -1))
print('hand a', 10 / (5.1 - 1) * (1 - 5.1 / 4.9), 'hand b', 2.5 * (1 - 5 / 3.95))
