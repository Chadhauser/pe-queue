import re, subprocess, sys
for j in ('499_touch_log_pull', '499_touch_log_racing', '499_touch_log_tennis'):
    p = f'/root/pe-queue/jobs/{j}.sh.wip'
    s = open(p).read()
    m = re.search(r"<<'PY'[^\n]*\n(.*)\nPY\n", s, re.S)
    compile(m.group(1), j, 'exec')
    r = subprocess.run(['bash', '-n', p], capture_output=True, text=True)
    print(j, 'heredoc compiles; bash -n rc', r.returncode, r.stderr[:200])
