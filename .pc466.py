import py_compile, re
s = open('/root/pe-queue/jobs/499_race_trip_tp.sh').read()
body = s.split("<<'PY'", 1)[1].split('\n', 1)[1].rsplit('\nPY', 1)[0]
open('/root/pe-queue/.pc466_body.py', 'w').write(body)
py_compile.compile('/root/pe-queue/.pc466_body.py', doraise=True)
print('py_compile OK', len(body.split('\n')), 'lines')
