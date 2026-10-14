#!/bin/bash
# 077: PETER 14 Oct: "look at all available markets and sports and everything else on Betfair and others". The in-play recorder
# now discovers EVERY event type Betfair lists (football excluded - the football recorder owns it) and records every in-play
# market of the main types per sport (MATCH_ODDS, WIN, PLACE, MONEYLINE, SET_WINNER, plus the sport's top-matched market when
# none of those exist), so darts, snooker, rugby, ice hockey, baseball, American football, esports, MMA, boxing, volleyball,
# handball, politics/specials all land in ip_tape/ip_reopen. Markets capped at 240 per loop by total matched; thin sampling >60.
python3 - <<'PY'
p='/root/pe-ip/ip_recorder.py'; s=open(p).read()
old=s[s.index("SPORTS={"):s.index("TOK=None")]
new='''SPORTS={}  # filled dynamically from listEventTypes every catalogue refresh; football (1) excluded (own recorder)
MAIN=['MATCH_ODDS','WIN','PLACE','MONEYLINE','SET_WINNER','MATCH_WINNER','TOURNAMENT_WINNER','OUTRIGHT_WINNER']
'''
s=s.replace(old,new)
old=s[s.index("def refresh_catalogue():"):s.index("def books(ids):")]
new='''def refresh_catalogue():
    global cat,last_cat,SPORTS
    new={}
    try:
        ets=api('listEventTypes',{"filter":{"inPlayOnly":True}})
        SPORTS={e['eventType']['id']:e['eventType']['name'].lower().replace(' ','_') for e in ets if e['eventType']['id']!='1'}
    except Exception as e: print("eventTypes",repr(e)[:80],flush=True)
    for etid,sport in SPORTS.items():
        try:
            res=api('listMarketCatalogue',{"filter":{"eventTypeIds":[etid],"inPlayOnly":True},
                   "marketProjection":["EVENT","COMPETITION","RUNNER_DESCRIPTION","MARKET_START_TIME","MARKET_DESCRIPTION"],"sort":"MAXIMUM_TRADED","maxResults":120})
        except Exception as e: print("catalogue",sport,repr(e)[:100],flush=True); continue
        bytype={}
        for m in res:
            mt=(m.get('description') or {}).get('marketType') or ''
            if mt in MAIN or len(bytype.get(m['event']['id'],[]))==0:
                bytype.setdefault(m['event']['id'],[]).append(m)
        for ev,ms in bytype.items():
            for m in ms[:3]:
                try: st=datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00'))
                except Exception: st=datetime.datetime.now(datetime.timezone.utc)
                new[m['marketId']]={'sport':sport,'event':m['event']['name'],'comp':(m.get('competition') or {}).get('name',''),'mt':(m.get('description') or {}).get('marketType') or '',
                                    'start':st,'runners':{r['selectionId']:r['runnerName'] for r in m['runners']},'tm':m.get('totalMatched') or 0}
    # cap by total matched
    if len(new)>240:
        keep=sorted(new.items(),key=lambda kv:-kv[1]['tm'])[:240]; new=dict(keep)
    for mid,meta in cat.items():
        if mid not in new and meta.get('gone') is None: meta['gone']=time.time(); new[mid]=meta
        elif mid not in new and time.time()-meta['gone']<120: new[mid]=meta
    cat=new; last_cat=time.time()
'''
s=s.replace(old,new)
open(p,'w').write(s)
PY
python3 -m py_compile /root/pe-ip/ip_recorder.py || exit 1
# restart only if a fresh login works (same guard as 070)
python3 - <<'PY2' || { echo "WAITING: no fresh Betfair login - not restarting"; exit 75; }
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, requests
a,u,p=creds.betfair(); assert a and u and p
r=requests.post("https://identitysso.betfair.com/api/login",data={"username":u,"password":p},headers={"X-Application":a,"Accept":"application/json"},timeout=15).json(); assert r.get('status')=='SUCCESS', r; print("fresh login OK")
PY2
pkill -f ip_recorder.py; sleep 90; tail -3 /root/pe-ip/recorder.log
