#!/bin/bash
# 035: 032 got HTTP 200 but found no datesData on any league page. Show what Understat actually returns to this server.
python3 - <<'PY'
import requests, re
H={"User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36","Accept":"text/html,application/xhtml+xml","Accept-Language":"en-GB,en;q=0.9","Referer":"https://understat.com/"}
for url in ("https://understat.com/league/EPL/2025","https://understat.com/match/26631"):
    r=requests.get(url,headers=H,timeout=30)
    t=r.text
    print("URL",url,"status",r.status_code,"len",len(t),"server",r.headers.get('server'),"cf-ray",r.headers.get('cf-ray'))
    print("  has datesData:",'datesData' in t,"| has shotsData:",'shotsData' in t,"| JSON.parse count:",t.count('JSON.parse'))
    for name in ('datesData','shotsData'):
        i=t.find(name)
        if i>=0: print("  context:",repr(t[i-20:i+120]))
    print("  head:",repr(re.sub(r'\s+',' ',t[:400])))
    print("  title:",re.findall(r'<title>(.*?)</title>',t,re.S)[:1])
PY
