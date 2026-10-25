#!/bin/bash
# 167: UNDERSTAT SHOTS — find where the shot data moved. 047 loaded 3,476 top-5-league matches (Mar 2024 -> May 2026) but zero shots:
# the match page no longer embeds shotsData (057). The redesigned site loads it by XHR. Probe: (a) grep the match page HTML/JS for
# the API path; (b) try the likely endpoints. Output = which URL returns shot JSON, so 168 can load every match's shots (minute, xG,
# result, team) and join them to the two-season minute prices. (This is the dataset for the stats-conditioned grammar.)
cd /root/pe-scan && python3 - <<'PY'
import re, requests, json, sys, psycopg2
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
H={"User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0 Safari/537.36","Accept":"application/json, text/plain, */*","Accept-Language":"en-GB,en;q=0.9","Referer":"https://understat.com/","X-Requested-With":"XMLHttpRequest"}
cur=psycopg2.connect(DB,sslmode='require').cursor(); cur.execute("SELECT understat_id, home_team, away_team, match_date FROM understat_matches WHERE match_date<'2026-05-01' ORDER BY match_date DESC LIMIT 1"); uid,h,a,d=cur.fetchone(); print("match",uid,h,a,d)
r=requests.get(f"https://understat.com/match/{uid}",headers=H,timeout=20); t=r.text; print("page",r.status_code,len(t))
for pat in (r"['\"](/[a-zA-Z0-9_/\-]*(?:shot|Shot|api|json|data|Data)[a-zA-Z0-9_/\-\.]*)['\"]", r"fetch\(([^)]{0,120})\)", r"\$\.(?:get|post|ajax)\(([^)]{0,160})\)", r"(https?://[^\s'\"]*understat[^\s'\"]*)"):
    hits=sorted(set(m if isinstance(m,str) else m[0] for m in re.findall(pat,t)))[:25]; print(pat[:40],"->",hits)
scripts=re.findall(r'<script[^>]+src=["\']([^"\']+)["\']',t); print("script srcs:",scripts[:15])
for s_ in scripts:
    if 'understat' in s_ or s_.startswith('/'):
        url=s_ if s_.startswith('http') else 'https://understat.com'+s_
        try:
            js=requests.get(url,headers=H,timeout=20).text
            paths=sorted(set(re.findall(r"['\"](/[a-zA-Z0-9_/\-]*(?:shot|match|api|get)[a-zA-Z0-9_/\-\.?=]*)['\"]",js)))[:30]
            if paths: print("in",url,":",paths)
        except Exception as e: print("js fail",url,repr(e)[:60])
for url in (f"https://understat.com/api/match/{uid}/shots",f"https://understat.com/api/match/{uid}",f"https://understat.com/getShotsData/?match={uid}",f"https://understat.com/main/getShotsData/?match={uid}",f"https://understat.com/match/{uid}/shots",f"https://understat.com/api/shots?match={uid}",f"https://understat.com/getMatchData/?match={uid}"):
    try:
        rr=requests.get(url,headers=H,timeout=20); body=rr.text[:160].replace("\n"," "); print(rr.status_code,url,"->",body)
        if rr.status_code==200 and ('xG' in rr.text or 'minute' in rr.text): print("   *** CANDIDATE: contains xG/minute; length",len(rr.text))
    except Exception as e: print("fail",url,repr(e)[:60])
PY
