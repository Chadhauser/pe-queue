t=open('/root/pe-queue/jobs/499_dec22_rereads.sh').read()
hdr_old=t.split('\n')[2]+'\n'+t.split('\n')[3]+'\n'+t.split('\n')[4]
hdr_new=('# 499_nov22_rereads (Finder 2026-11-08, 16:05 UTC run): items 451, 448 and 450 on November 2022, a month no read has used (Soccer 2022-11 DONE on the loader, 53,502 of 53,502 files, 8 Nov).\n'
 '# Copy of jobs/499_dec22_rereads.sh with only the month changed (12 -> 11, "Dec 2022" -> "Nov 2022"); each job still runs unchanged except its month list and labels.\n'
 '# Read only, no tables written. One month cannot reach n 300: interim reads, n stated, pooled with earlier unseen months in the report.')
assert t.count(hdr_old)==1
t=t.replace(hdr_old,hdr_new)
n=t.count('range(12,13)'); assert n==3, n
t=t.replace('range(12,13)','range(11,12)')
t=t.replace('"December 2022 only"','"November 2022 only"')
t=t.replace('Dec 2022','Nov 2022')
assert 'Dec 2022' not in t and '12,13' not in t
open('/root/pe-queue/jobs/499_nov22_rereads.sh','w').write(t)
print(t[:600])
