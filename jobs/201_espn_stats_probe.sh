#!/bin/bash
# 201: STATS FEED REPLACEMENT PROBE. API-Football's quota is gone for the day and FotMob/SofaScore are closed to the server. ESPN's
# public site API needs no key and (for many leagues) carries in-play team statistics. Probe: which leagues are reachable, which have
# a live game now, and which statistic names the summary endpoint returns (we need shots on target / total shots / possession; xG is a
# bonus). Read-only, 60 s.
python3 - <<'PY'
import requests, json, time
H={"User-Agent":"Mozilla/5.0"}
leagues=["eng.1","eng.2","eng.3","esp.1","ita.1","ger.1","fra.1","ned.1","por.1","sco.1","bel.1","tur.1","usa.1","bra.1","arg.1","jpn.1","aus.1","uefa.champions","uefa.europa","fin.1","swe.1","nor.1","den.1","aut.1","sui.1","gre.1","mex.1"]
live=[]
for lg in leagues:
    try:
        r=requests.get(f"https://site.api.espn.com/apis/site/v2/sports/soccer/{lg}/scoreboard",headers=H,timeout=10)
        if r.status_code!=200: print(lg,"HTTP",r.status_code); continue
        ev=r.json().get('events',[])
        st=[(e['id'],e['name'],e['status']['type']['state'],e['status'].get('displayClock')) for e in ev]
        n_in=[s for s in st if s[2]=='in']; live+= [(lg,)+s for s in n_in]
        print(f"{lg:16s} events {len(ev):2d} live {len(n_in)}", (n_in[0][1:] if n_in else ''))
    except Exception as e: print(lg,"ERR",repr(e)[:80])
print("\nlive now:",len(live))
for lg,eid,name,_,clk in live[:4]:
    r=requests.get(f"https://site.api.espn.com/apis/site/v2/sports/soccer/{lg}/summary?event={eid}",headers=H,timeout=10)
    j=r.json(); bx=j.get('boxscore',{}); teams=bx.get('teams',[])
    print("\n==",lg,name,clk,"| boxscore teams:",len(teams))
    for t in teams:
        print("  ",t['team']['displayName'],{s['name']:s.get('displayValue') for s in t.get('statistics',[])})
    kp=j.get('keyEvents') or j.get('plays') or []; print("   key events:",len(kp), [ (k.get('clock',{}).get('displayValue'),k.get('type',{}).get('text')) for k in kp[:6]])
    # also check header for scoreboard-level stats
    sc=requests.get(f"https://site.api.espn.com/apis/site/v2/sports/soccer/{lg}/scoreboard",headers=H,timeout=10).json()
    e=next(x for x in sc['events'] if x['id']==eid); comp=e['competitions'][0]
    for c in comp['competitors']: print("   scoreboard stats",c['team']['abbreviation'],{s['name']:s.get('displayValue') for s in c.get('statistics',[])})
PY
