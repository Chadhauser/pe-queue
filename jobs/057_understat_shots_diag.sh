#!/bin/bash
# 057: 047 loaded 3,476 Understat matches but ZERO shots. Fetch one match page from this server and show exactly what the
# shotsData block looks like now, so the parser can be fixed (the league pages changed in Oct; match pages may have too).
cd /root/pe-scan && python3 - <<'PY'
import re, requests, sys, psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor()
cur.execute("SELECT understat_id, home_team, away_team FROM understat_matches ORDER BY match_date DESC LIMIT 1"); uid,h,a=cur.fetchone(); print("match",uid,h,a)
H={"User-Agent":"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/124 Safari/537.36","Accept-Language":"en-GB,en;q=0.9"}
r=requests.get(f"https://understat.com/match/{uid}",headers=H,timeout=30); t=r.text
print("HTTP",r.status_code,"len",len(t))
for k in ("shotsData","match_info","rostersData","JSON.parse"):
    i=t.find(k); print(k,"at",i, repr(t[max(0,i-80):i+200]) if i>=0 else "")
print("script tags:",len(re.findall(r"<script",t)))
m=re.search(r"var\s+shotsData\s*=\s*JSON\.parse\('((?:\\.|[^'])*)'\)",t)
print("regex shotsData match:",bool(m), (len(m.group(1)) if m else 0))
if m:
    import json; s=m.group(1).encode().decode('unicode_escape'); d=json.loads(s); print("parsed keys",list(d.keys()),"h shots",len(d.get('h',[])),"first",d.get('h',[{}])[0])
PY
