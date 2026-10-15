#!/bin/bash
# 082: 014 red-card backfill crashed on a non-JSON response from API-Football mid-run. Wrap every call: retry 3x with backoff,
# skip the fixture on persistent failure, never crash. Then re-queue it as a waiting job (exit 75 until quota is available).
python3 - <<'PY'
p='/root/pe-scan/events_backfill.py'; s=open(p).read()
if 'def safe_json(' not in s:
    s=s.replace("import os, re, sys, glob, json, time, datetime, requests, psycopg2, psycopg2.extras",
"""import os, re, sys, glob, json, time, datetime, requests, psycopg2, psycopg2.extras
def safe_json(url,**kw):
    for i in range(3):
        try:
            r=requests.get(url,timeout=30,**kw)
            if r.status_code==429: time.sleep(20); continue
            return r.json()
        except Exception as e:
            time.sleep(3*(i+1))
    return None""")
    s=s.replace("requests.get(b+\"/status\",headers=h,timeout=30).json()","(safe_json(b+'/status',headers=h) or {})")
    import re
    s=re.sub(r"requests\.get\(([^)]*?)\)\.json\(\)",r"(safe_json(\1) or {})",s)
    open(p,'w').write(s); print("patched")
else: print("already patched")
PY
python3 -m py_compile /root/pe-scan/events_backfill.py && cd /root/pe-scan && python3 events_backfill.py
