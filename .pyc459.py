import py_compile, re
s = open('/root/pe-queue/jobs/499_ht_break_drift.sh').read()
body = s.split("<<'PY'", 1)[1].split('\n', 1)[1].rsplit('\nPY', 1)[0]
open('/tmp/ht459_body.py', 'w').write(body)
py_compile.compile('/tmp/ht459_body.py', doraise=True)
print('py_compile OK', len(body.splitlines()), 'lines')
