import re, py_compile
s=open('/root/pe-queue/jobs/499_calib_fresh_ou45.sh').read()
body=re.search(r"<<'PY'[^\n]*\n(.*)\nPY\n",s,re.S).group(1)
open('/root/pe-queue/.chk487b_body.py','w').write(body)
py_compile.compile('/root/pe-queue/.chk487b_body.py',doraise=True)
print('py_compile OK', len(body.splitlines()), 'lines')
