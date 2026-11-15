import subprocess, time
t0 = time.time()
while time.time() - t0 < 570:
    r = subprocess.run(['pgrep', '-f', '[j]ump_up_delay_touch.sh.wip'], capture_output=True)
    if r.returncode != 0:
        print('ended after', int(time.time() - t0), 's'); break
    time.sleep(10)
else:
    print('still running after 570 s')
print(open('/tmp/claude-0/-root-pe-queue/58675828-e0e2-4c63-b6f6-c8cc94592854/tasks/b9deq6fm1.output').read()[-5000:])
