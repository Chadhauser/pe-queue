import py_compile, subprocess
f = '/root/pe-queue/jobs/499_calib_fresh_unseen.sh'
s = open(f).read()
body = s.split("<<'PY'", 1)[1].split('\n', 1)[1].rsplit('\nPY', 1)[0]
open('/root/pe-queue/.chk487_body.py', 'w').write(body)
py_compile.compile('/root/pe-queue/.chk487_body.py', doraise=True)
print('py_compile OK', len(body.splitlines()), 'lines')
print(subprocess.run(['bash', '-n', f], capture_output=True, text=True))
