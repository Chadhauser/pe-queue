#!/bin/bash
# 074: cross-exchange recorder: Smarkets returned HTTP 400 because we asked for all live event ids in one URL (too long). Chunk
# events to 15 per call and markets to 40 per call. Matchbook login is failing with 'incorrect credentials' (Peter to re-paste).
python3 - <<'PY'
p='/root/pe-xx/xx_recorder.py'; s=open(p).read()
old=s[s.index("def sm_snapshot(now):"):s.index("# ---------------- Matchbook")]
new='''def sm_snapshot(now):
    rows=[]; live=0
    for sport in SM_SPORT.values():
        ev=sm("events/",{"state":"live","type_domain":sport,"limit":200}).get('events',[])
        if not ev: continue
        live+=len(ev); emap={str(e['id']):e for e in ev}
        for i in range(0,len(ev),15):
            ids=",".join(str(e['id']) for e in ev[i:i+15])
            try: mk=sm(f"events/{ids}/markets/",{"limit":500}).get('markets',[])
            except Exception as e: print("markets chunk error",repr(e)[:80],flush=True); continue
            mk=[m for m in mk if 'winner' in (m.get('name','')+' '+(m.get('market_type',{}) or {}).get('name','')).lower()] or mk[:3*15]
            for j in range(0,len(mk),40):
                part=mk[j:j+40]; mids=[m['id'] for m in part]
                try:
                    ct=sm(f"markets/{','.join(mids)}/contracts/",{"limit":1000}).get('contracts',[]); cmap={c['id']:c for c in ct}
                    q=sm(f"markets/{','.join(mids)}/quotes/")
                except Exception as e: print("quotes chunk error",repr(e)[:80],flush=True); continue
                for m in part:
                    e=emap.get(str(m['event_id']),{})
                    for cid,qq in q.items():
                        c=cmap.get(cid)
                        if not c or c['market_id']!=m['id']: continue
                        bids=qq.get('bids',[]); offers=qq.get('offers',[])
                        bp=(10000/bids[0]['price']) if bids else None; bs=(bids[0]['quantity']/10000) if bids else None
                        lp=(10000/offers[0]['price']) if offers else None; ls=(offers[0]['quantity']/10000) if offers else None
                        lt=qq.get('last_executed_price'); lt=(10000/lt) if lt else None
                        rows.append((now,'smarkets',sport,e.get('name'),str(m['id']),m.get('name'),e.get('start_datetime'),True,c.get('name'),bp,bs,lp,ls,lt))
    return rows,live
'''
s=s.replace(old,new); open(p,'w').write(s)
PY
python3 -m py_compile /root/pe-xx/xx_recorder.py || exit 1
pkill -f xx_recorder.py; sleep 70; tail -5 /root/pe-xx/recorder.log
