import py_compile, subprocess
s = open('/root/pe-queue/jobs/499_calib_unseen.sh').read()
body = s.split("<<'PY'", 1)[1].split('\n', 1)[1].rsplit('\nPY', 1)[0]
open('/root/pe-queue/.chk486_body.py', 'w').write(body)
py_compile.compile('/root/pe-queue/.chk486_body.py', doraise=True)
print('py_compile OK', len(body.splitlines()), 'lines')
print(subprocess.run(['bash', '-n', '/root/pe-queue/jobs/499_calib_unseen.sh'], capture_output=True, text=True))
