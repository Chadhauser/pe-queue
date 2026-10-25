#!/bin/bash
# 193: FotMob as the live stats source (API-Football's daily cap kills the feed before Europe kicks off). Probe from the server:
# today's match list, one live/recent match's details, and whether shot-level xG with minutes is present. No key needed.
python3 - <<'PY'
import requests, json, datetime, time
H={"User-Agent":"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124.0 Safari/537.36","Accept":"application/json","Accept-Language":"en-GB,en;q=0.9","Referer":"https://www.fotmob.com/"}
d=datetime.datetime.utcnow().strftime('%Y%m%d')
r=requests.get("https://www.fotmob.com/api/matches",params={"date":d,"timezone":"Europe/London"},headers=H,timeout=20); print("matches:",r.status_code,len(r.text))
if r.status_code!=200: print(r.text[:300]); raise SystemExit
j=r.json(); leagues=j.get('leagues',[]); print("leagues today:",len(leagues))
live=[]; recent=[]
for L in leagues:
    for m in L.get('matches',[]):
        st=m.get('status',{})
        rec=(L.get('name'),m.get('home',{}).get('name'),m.get('away',{}).get('name'),m.get('id'),st.get('started'),st.get('finished'),st.get('liveTime',{}).get('short') if isinstance(st.get('liveTime'),dict) else None)
        if st.get('started') and not st.get('finished'): live.append(rec)
        elif st.get('finished'): recent.append(rec)
print("live now:",len(live)); [print("  ",x) for x in live[:10]]
print("finished today:",len(recent))
pick=(live or recent)[:1]
for L,hn,an,mid,*_ in pick:
    r2=requests.get("https://www.fotmob.com/api/matchDetails",params={"matchId":mid},headers=H,timeout=20); print("matchDetails",mid,hn,"v",an,":",r2.status_code,len(r2.text))
    if r2.status_code!=200: print(r2.text[:300]); continue
    md=r2.json(); print("top keys:",list(md.keys())[:12])
    content=md.get('content',{}); print("content keys:",list(content.keys())[:20])
    sm=content.get('shotmap',{}); shots=sm.get('shots') if isinstance(sm,dict) else sm
    print("shotmap shots:",len(shots) if shots else 0)
    if shots:
        s0=shots[0]; print("shot keys:",list(s0.keys())); print("sample:",{k:s0.get(k) for k in ('min','minAdded','teamId','expectedGoals','expectedGoalsOnTarget','eventType','isOnTarget','playerName')})
    stats=content.get('stats',{}); print("stats keys:",list(stats.keys())[:10] if isinstance(stats,dict) else type(stats))
    try:
        periods=stats.get('Periods',{}); allp=periods.get('All',{}); groups=allp.get('stats',[]); print("stat groups:",[g.get('title') for g in groups][:8])
        top=groups[0].get('stats',[]) if groups else []; print("top stats:",[(x.get('title'),x.get('stats')) for x in top][:8])
    except Exception as e: print("stats parse:",repr(e)[:80])
    gen=md.get('general',{}); print("general:",{k:gen.get(k) for k in ('matchTimeUTC','started','finished','leagueName')})
PY
