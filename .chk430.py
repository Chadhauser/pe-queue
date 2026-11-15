import py_compile, subprocess
p = '/root/pe-queue/jobs/499_equaliser_side.sh'
s = open(p).read()
body = s.split("<<'PY'", 1)[1].split('\n', 1)[1].rsplit('\nPY', 1)[0]
open('/tmp/claude-0/c430.py', 'w').write(body)
py_compile.compile('/tmp/claude-0/c430.py', doraise=True)
print('py_compile OK')
print(subprocess.run(['bash', '-n', p], capture_output=True, text=True))
