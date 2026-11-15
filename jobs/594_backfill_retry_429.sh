#!/bin/bash
# 594 (Sun 15 Nov 2026, 18:20). The backfill's month-list call got HTTP 429 (rate limit) on nine Tennis months and skipped them. Patch the
# script (takes effect on its next run): retry the list call up to 6 times with a 30 s wait on 429. The running process is left alone; a
# Tennis-only second pass is queued after it finishes.
set -o pipefail
python3 - <<'PY'
p='/root/pe-hist/results_backfill.py'; s=open(p).read(); assert '594' not in s
old='        rr=requests.post("https://historicdata.betfair.com/api/DownloadListOfFiles",headers=H,json=body,timeout=180)\n        if rr.status_code!=200: log(sport,y,m,"LIST HTTP",rr.status_code); continue'
new='''        for _try in range(6):   # 594: 429 = rate limit, wait and retry
            rr=requests.post("https://historicdata.betfair.com/api/DownloadListOfFiles",headers=H,json=body,timeout=180)
            if rr.status_code==429: time.sleep(30); continue
            break
        if rr.status_code!=200: log(sport,y,m,"LIST HTTP",rr.status_code); continue'''
assert old in s; s=s.replace(old,new,1); open(p,'w').write(s); print("patched")
PY
python3 -m py_compile /root/pe-hist/results_backfill.py && echo compiles
echo "594 done"
