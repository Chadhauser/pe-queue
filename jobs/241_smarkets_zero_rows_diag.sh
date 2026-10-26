#!/bin/bash
# 241: Smarkets recorder reports 44 live events but has NEVER written a row (xx_tape: 0 smarkets rows since 14 Oct). Step through the
# snapshot with counts at each stage to find where it goes empty (market filter? contract/market id types? quotes shape?).
cd /root/pe-xx && python3 - <<'PY'
src=open('xx_recorder.py').read(); i=src.index('# ---------------- Smarkets'); j=src.index('# ---------------- Matchbook')
head=src[:src.index('# ---------------- Smarkets')]
# run the preamble (imports, creds, session) then the smarkets functions
ns={}; exec(head,ns); exec(src[i:j],ns)
sm=ns['sm']
ev=sm("events/",{"state":"live","type_domain":"football","limit":50}).get('events',[])
print("live football events:",len(ev)); 
if ev:
    e=ev[0]; print("sample event keys:",list(e.keys())[:12]); print("sample:",{k:e.get(k) for k in ('id','name','start_datetime','state','type')})
    ids=",".join(str(x['id']) for x in ev[:20]); mk=sm(f"events/{ids}/markets/",{"limit":500}).get('markets',[])
    print("markets for 20 events:",len(mk)); 
    if mk:
        m=mk[0]; print("sample market keys:",list(m.keys())[:14]); print("sample:",{k:m.get(k) for k in ('id','name','event_id','market_type','state')})
        names={}
        for x in mk: n=(x.get('market_type',{}).get('name') if isinstance(x.get('market_type'),dict) else x.get('market_type')) or x.get('name'); names[str(n)]=names.get(str(n),0)+1
        print("market names:",sorted(names.items(),key=lambda t:-t[1])[:12])
        mids=[x['id'] for x in mk[:30]]
        ct=sm(f"markets/{','.join(str(z) for z in mids)}/contracts/",{"limit":1000}).get('contracts',[]); print("contracts:",len(ct)); 
        if ct: print("sample contract:",{k:ct[0].get(k) for k in ('id','name','market_id','state')}, "types:",type(ct[0]['id']).__name__,type(ct[0]['market_id']).__name__,"market id type:",type(mk[0]['id']).__name__)
        q=sm(f"markets/{','.join(str(z) for z in mids)}/quotes/"); print("quotes keys:",len(q), "sample key type:",type(next(iter(q))).__name__ if q else None)
        if q:
            k0=next(iter(q)); print("sample quote:",k0,str(q[k0])[:300])
            cm={str(c['id']):c for c in ct}; hit=sum(1 for k in q if str(k) in cm); print("quote keys that match a contract id (as str):",hit,"of",len(q))
PY
echo "== recorder log tail"; tail -5 /root/pe-xx/recorder.log
