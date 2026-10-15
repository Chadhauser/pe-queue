#!/bin/bash
# 085: (a) Smarkets: the events endpoint sometimes returns non-JSON (HTML or empty) — show the status/body once, and make the
# recorder log it instead of silently writing nothing. (b) Red-card backfill 082 lost its DB connection after 25 min of work
# (resumable) — rerun; exit 75 so it keeps going every cycle until done.
python3 - <<'PY'
import sys, requests; sys.path.insert(0,'/root/pe-queue/runner'); import creds
E=creds.all_vars(); S=requests.Session()
r=S.post("https://api.smarkets.com/v3/sessions/",json={"username":E['SMARKETS_USERNAME'],"password":E['SMARKETS_PASSWORD']},timeout=20); print("login status",r.status_code,r.text[:150])
tok=r.json().get('token') if r.headers.get('content-type','').startswith('application/json') else None
if tok:
    for url,params in (("https://api.smarkets.com/v3/events/",{"state":"live","type_domain":"football","limit":5}),("https://api.smarkets.com/v3/events/",{"state":"live","type_domain":"football","limit":5,"sort":"start_datetime"})):
        q=S.get(url,params=params,headers={"Authorization":"Session-Token "+tok},timeout=20); print(url,params,"->",q.status_code,q.headers.get('content-type'),q.text[:300])
PY
p=/root/pe-xx/xx_recorder.py
python3 - <<'PY'
p='/root/pe-xx/xx_recorder.py'; s=open(p).read()
s=s.replace('''    r=S.get("https://api.smarkets.com/v3/"+url,params=params,headers={"Authorization":"Session-Token "+SM_TOK},timeout=20); r.raise_for_status(); return r.json()''',
'''    r=S.get("https://api.smarkets.com/v3/"+url,params=params,headers={"Authorization":"Session-Token "+SM_TOK},timeout=20)
    if r.status_code!=200 or not r.headers.get('content-type','').startswith('application/json'):
        raise RuntimeError(f"smarkets {url} HTTP {r.status_code} {r.headers.get('content-type')} {r.text[:120]}")
    return r.json()''')
open(p,'w').write(s)
PY
python3 -m py_compile $p && pkill -f xx_recorder.py; sleep 75; tail -4 /root/pe-xx/recorder.log
cd /root/pe-scan && python3 events_backfill.py; rc=$?; [ $rc -eq 0 ] && exit 75 || exit $rc
