import re
want = {'17','265','269','272','273','74','302','283','362','352','70','387','137'}
for i, l in enumerate(open('/root/pe-queue/watchman/FINDER_QUEUE.md'), 1):
    m = re.match(r'^\s*(\d+)\.\s*(\*\*)?(TODO|RUNNING)', l)
    if m and m.group(1) in want:
        print(i, l[:1500].rstrip())
        print()
print('--- tail of ledger')
for l in open('/root/pe-queue/watchman/HYPOTHESES.md').readlines()[-12:]:
    print(l[:300].rstrip())
