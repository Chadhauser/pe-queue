#!/bin/bash
# 187: API-Football returns errors.requests = "reached the request limit for the day" while its header still claims 7,499 remaining
# (186). The recorder trusted the header and kept polling. Now: a 'requests' error marks the quota dead and the loop sleeps 15 min
# between probes until a call succeeds again; the heartbeat's http_status column carries -1 while dead so the morning check sees it.
python3 - <<'PY'
p='/root/pe-stats/stats_recorder.py'; s=open(p).read(); n=0
old='''def get(path,params):
    global remaining
    r=requests.get(BASE+path,params=params,headers=AFH,timeout=20)
    try: remaining=int(r.headers.get('x-ratelimit-requests-remaining') or remaining or 0)
    except Exception: pass
    return r.status_code,(r.json() if r.status_code==200 else None)'''
new='''QUOTA_DEAD=[0.0]
def get(path,params):
    global remaining
    r=requests.get(BASE+path,params=params,headers=AFH,timeout=20)
    try: remaining=int(r.headers.get('x-ratelimit-requests-remaining') or remaining or 0)
    except Exception: pass
    j=r.json() if r.status_code==200 else None
    if j is not None and isinstance(j.get('errors'),dict) and 'requests' in j['errors']:
        QUOTA_DEAD[0]=time.time(); remaining=-1; print("QUOTA EXHAUSTED:",j['errors']['requests'][:80],flush=True); return r.status_code,None
    QUOTA_DEAD[0]=0.0
    return r.status_code,j'''
assert old in s; s=s.replace(old,new); n+=1
old2="        st,data=get(\"/fixtures\",{\"live\":\"all\"}); live=(data or {}).get('response',[]); matched=0"
new2="        if QUOTA_DEAD[0] and time.time()-QUOTA_DEAD[0]<900:\n            cur.execute(\"INSERT INTO stats_heartbeat VALUES (1,now(),0,0,-1) ON CONFLICT (id) DO UPDATE SET last_seen=now(), live=0, matched=0, http_status=-1\"); time.sleep(120); continue\n        st,data=get(\"/fixtures\",{\"live\":\"all\"}); live=(data or {}).get('response',[]); matched=0"
assert old2 in s; s=s.replace(old2,new2); n+=1
open(p,'w').write(s); print("patches:",n)
PY
python3 -m py_compile /root/pe-stats/stats_recorder.py && pkill -f stats_recorder.py; sleep 3; /root/pe-stats/keepalive.sh; sleep 30; pgrep -af stats_recorder.py | head -1; tail -3 /root/pe-stats/stats.log
