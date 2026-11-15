j = '/root/pe-queue/jobs/499_touch_log_racing.sh.wip'
t = open(j).read()
a = 'nticks(1.98, 2.02) == 2'
assert t.count(a) == 1
open(j, 'w').write(t.replace(a, 'nticks(1.98, 2.02) == 3'))
print('fixed')
