import os
p='.finish_395.py'; t=open(p).read()
names=('499_sep23_rereads','499_dnb_resting_pooled','499_cricket_touch','499_cricket_bands_truth','499_cricket_official_357','499_cricket_touch_inplay','499_reopen_racing','499_reopen_restored','499_reopen_tennis','499_tennis_log_no_replay')
for n in names: print(n,'taken' if os.path.exists(f'jobs/{n}.sh') else 'free')
assert not os.path.exists('jobs/499_cricket_touch_preoff.sh')
os.rename('jobs/499_cricket_touch.sh.wip','jobs/499_cricket_touch_preoff.sh.wip')
t=t.replace("'499_cricket_touch','499_cricket_bands_truth'","'499_cricket_touch_preoff','499_cricket_bands_truth'")
t=t.replace("jobs/499_cricket_touch.sh,","jobs/499_cricket_touch_preoff.sh,").replace("job 499_cricket_touch unchanged","job 499_cricket_touch_preoff unchanged").replace("(499_cricket_touch, item 395)","(499_cricket_touch_preoff, item 395)")
a="; older months need af_fixtures before season 2023)"
assert a in t
t=t.replace(a,"; older months: af_fixtures runs from 2016, af_stats on those seasons not checked)")
open(p,'w').write(t)
for f in ('/root/.claude/projects/-root-pe-queue/memory/rest-replay-snapshots.md',):
    s=open(f).read(); s2=s.replace('jobs/499_cricket_touch.sh','jobs/499_cricket_touch_preoff.sh'); assert s!=s2; open(f,'w').write(s2)
w='jobs/499_cricket_touch_preoff.sh.wip'; s=open(w).read(); s2=s.replace('# 499_cricket_touch (Finder','# 499_cricket_touch_preoff (Finder'); assert s!=s2; open(w,'w').write(s2)
print('ok')
