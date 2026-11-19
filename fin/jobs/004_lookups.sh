#!/bin/bash
# fin 004 (own runner): read-only lookups for Peter's 19 Nov questions — old simulated ledger, K2 per-name result, ideas tested, history tests.
echo "=== old paper ledger"; python3 - <<'PY'
import json
try:
    l=json.load(open('/root/pe-fin/team/paper_ledger.json')); print({k:l[k] for k in ('strategy','label','start','updated','trades','wins','usd','gbp')})
    for r in l['days']: print(r.get('date'), r.get('side'), r.get('reason') or r.get('note'), r.get('usd'))
except Exception as e: print('ERR',e)
PY
echo "=== K2 per-name P&L 17 and 18 Nov (from broker fills)"
cd /root/pe-finq/repo/fin/bots && python3 - <<'PY'
import json, os, datetime as dt, tick as T
T.H=T._creds()
for day in ('2026-11-17','2026-11-18'):
    d=json.load(open(os.path.join(T.BOTS,f'day_{day}.json'))); legs=[l for l in d.get('K2',{}).get('legs',[]) if l.get('status',0)<300]
    syms={l['sym'] for l in legs}
    sc,o=T.api('GET','/orders',params={'status':'closed','after':day+'T13:00:00Z','until':day+'T22:00:00Z','limit':500,'direction':'asc'})
    pn={}
    for x in (o if sc==200 else []):
        if x['symbol'] in syms and x.get('filled_avg_price') and float(x.get('filled_qty') or 0)>0:
            pn[x['symbol']]=pn.get(x['symbol'],0)+float(x['filled_qty'])*float(x['filled_avg_price'])*(1 if x['side']=='sell' else -1)
    print(day,'legs',len(legs),'wins',sum(1 for v in pn.values() if v>0),'losses',sum(1 for v in pn.values() if v<=0),'total',round(sum(pn.values()),2),{k:round(v,2) for k,v in pn.items()})
PY
echo "=== team files"; ls -la /root/pe-fin/team 2>/dev/null | head -60
echo "=== scoreboard"; for f in /root/pe-fin/team/scoreboard.md /root/pe-fin/team/SCOREBOARD.md; do [ -f $f ] && head -c 9000 $f; done
echo "=== ledgers / verdict counts"; ls /root/pe-fin/team/*.json 2>/dev/null
python3 - <<'PY'
import json,glob,collections
for f in glob.glob('/root/pe-fin/team/*.json'):
    try:
        j=json.load(open(f))
        if isinstance(j,list): print(f,'list',len(j), collections.Counter(str(x.get('verdict') or x.get('status')) for x in j if isinstance(x,dict)).most_common(8))
        elif isinstance(j,dict):
            for k,v in j.items():
                if isinstance(v,list) and v and isinstance(v[0],dict): print(f,k,len(v), collections.Counter(str(x.get('verdict') or x.get('status')) for x in v).most_common(8))
    except Exception as e: print(f,'ERR',e)
PY
