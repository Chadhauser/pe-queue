#!/bin/bash
# 532 (Sun 8 Nov 2026). Four faults on the Betfair side of the one job, all found in the Watchman reports of 7-8 Nov, fixed together
# because they share one effect: the Betfair in-play tape and the Betfair bookie leg stop on busy Saturdays.
#  A. liq_recorder.py: listMarketCatalogue answers 400 TOO_MUCH_DATA once a market type carries ~200+ markets (every Saturday afternoon:
#     tape lost 11:59-21:00 UTC on 7 Nov, same shape on 31 Oct). api() raises, the loop does nothing, cron/watchdog restarts cannot help.
#     Fix: bf_chunk.py, imported first, wraps requests.Session.request: on TOO_MUCH_DATA it bisects the request by marketStartTime window
#     (depth 6), merges the pages, drops MARKET_DESCRIPTION only as a last resort on a leaf, and hands back one 200 response. Nothing
#     else about the recorder changes. Tested here with a request built to fail (every soccer market 36 h out, maxResults 1000).
#  B. bookie_paper.py:76 — the 90-second snapshot joined the WHOLE liq_sample (20M+ rows) to the last-ts CTE, so the read hit the 40 s
#     limit every loop once Railway slowed (1,574 tracebacks; leg stalled from 19:17 UTC 7 Nov). Fix: the same 90 s filter on the joined side.
#  C. bookie_paper.py:134 — liq_sample stores Match Odds runners as HOME/AWAY/DRAW, liq_runners stores team names, so every home/away
#     fill went 'unsettleable' (369+). Fix: HOME/AWAY map to the halves of the event name, DRAW to 'The Draw'; the stuck rows go back to
#     'filled' so they settle on the official result.
#  D. sports_team.py data_health: a count that timed out on Railway was reported BROKEN (3 feeds this morning) with no proof of no rows.
#     Fix: the last-timestamp read (index-only, fast) decides liveness when the 24 h count times out; the line says the count was unread.
# The quote-side question in the Watchman's list (:102) is checked and not a fault: f>1 means the market price is longer than the fair
# price, so backing it is right; a BACK one tick above best back is a maker order inside the spread.
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
echo "== A. recorder shim =="
test -f /root/pe-liq/liq_recorder.py || { echo "no /root/pe-liq/liq_recorder.py"; exit 1; }
cat > /root/pe-liq/bf_chunk.py <<'PY'
# bf_chunk (532): Betfair listMarketCatalogue answers 400 TOO_MUCH_DATA when one request would return too many markets. This module,
# imported before anything else, wraps requests.Session.request (which requests.post and session.post both go through). Any POST to a
# .../listMarketCatalogue/ URL that comes back TOO_MUCH_DATA is retried as a bisection over marketStartTime windows and the pages are
# merged (dedup by marketId) into one synthetic 200 response. Last resort on a leaf that still fails: drop MARKET_DESCRIPTION. A leaf that
# fails even then is logged and skipped, so the caller gets what Betfair would give rather than nothing. Other requests are untouched.
import json, datetime, requests
_orig=requests.Session.request
LOG='/root/pe-liq/bf_chunk.log'
def _log(m):
    try:
        with open(LOG,'a') as f: f.write(f"{datetime.datetime.utcnow():%Y-%m-%d %H:%M:%S} {m}\n")
    except Exception: pass
def _body(kw):
    if kw.get('json') is not None: return kw['json'],'json'
    d=kw.get('data')
    if isinstance(d,(str,bytes)):
        try: return json.loads(d),'data'
        except Exception: return None,None
    return None,None
def _iso(t): return t.strftime('%Y-%m-%dT%H:%M:%SZ')
def _too_much(r):
    try: return r.status_code==400 and 'TOO_MUCH_DATA' in r.text
    except Exception: return False
def _call(self,method,url,kw,body,how):
    kw=dict(kw)
    if how=='json': kw['json']=body
    else: kw['data']=json.dumps(body)
    return _orig(self,method,url,**kw)
def _bisect(self,method,url,kw,body,how,lo,hi,depth,out,stats):
    b=json.loads(json.dumps(body)); f=b.setdefault('filter',{}); f['marketStartTime']={'from':_iso(lo),'to':_iso(hi)}
    r=_call(self,method,url,kw,b,how); stats['calls']+=1
    if r.status_code==200:
        for m in r.json(): out[m.get('marketId')]=m
        return
    if _too_much(r) and depth<6 and (hi-lo).total_seconds()>600:
        mid=lo+(hi-lo)/2
        _bisect(self,method,url,kw,body,how,lo,mid,depth+1,out,stats); _bisect(self,method,url,kw,body,how,mid,hi,depth+1,out,stats); return
    if _too_much(r) and 'MARKET_DESCRIPTION' in (b.get('marketProjection') or []):
        b['marketProjection']=[p for p in b['marketProjection'] if p!='MARKET_DESCRIPTION']
        r=_call(self,method,url,kw,b,how); stats['calls']+=1; stats['desc_dropped']+=1
        if r.status_code==200:
            for m in r.json(): out[m.get('marketId')]=m
            return
    stats['failed_leaves']+=1; _log(f"leaf failed {lo:%d %H:%M}-{hi:%d %H:%M} {r.status_code} {r.text[:80]!r}")
def request(self,method,url,**kw):
    r=_orig(self,method,url,**kw)
    if not (str(method).upper()=='POST' and 'listMarketCatalogue' in str(url) and _too_much(r)): return r
    body,how=_body(kw)
    if body is None: return r
    now=datetime.datetime.utcnow(); f=body.get('filter') or {}
    w=f.get('marketStartTime') or {}
    try:
        lo=datetime.datetime.fromisoformat(w['from'].replace('Z','+00:00')).replace(tzinfo=None) if 'from' in w else (now-datetime.timedelta(hours=8) if f.get('inPlayOnly') else now-datetime.timedelta(hours=12))
        hi=datetime.datetime.fromisoformat(w['to'].replace('Z','+00:00')).replace(tzinfo=None) if 'to' in w else (now+datetime.timedelta(hours=1) if f.get('inPlayOnly') else now+datetime.timedelta(days=7))
    except Exception: lo,hi=now-datetime.timedelta(hours=12),now+datetime.timedelta(days=7)
    out={}; stats={'calls':0,'desc_dropped':0,'failed_leaves':0}
    _bisect(self,method,url,kw,body,how,lo,hi,0,out,stats)
    _log(f"TOO_MUCH_DATA on {f.get('marketTypeCodes')} inplay={f.get('inPlayOnly')} -> {len(out)} markets in {stats['calls']} calls, desc dropped {stats['desc_dropped']}, failed leaves {stats['failed_leaves']}")
    s=requests.Response(); s.status_code=200; s._content=json.dumps(list(out.values())).encode(); s.headers['Content-Type']='application/json'
    s.url=r.url; s.request=r.request; s.encoding='utf-8'; s.reason='OK'
    return s
requests.Session.request=request
PY
python3 -m py_compile /root/pe-liq/bf_chunk.py && echo "bf_chunk compiles"
cd /root/pe-liq && cp liq_recorder.py liq_recorder.py.bak_532
if grep -q 'import bf_chunk' liq_recorder.py; then echo "shim import already present"; else
python3 - <<'PY'
src=open('/root/pe-liq/liq_recorder.py').read().split('\n')
i=next(k for k,l in enumerate(src) if l.startswith('import ') or l.startswith('from '))
src.insert(i,"import sys as _s532; _s532.path.insert(0,'/root/pe-liq'); import bf_chunk  # 532: listMarketCatalogue TOO_MUCH_DATA -> bisect by start-time window")
open('/root/pe-liq/liq_recorder.py','w').write('\n'.join(src)); print("shim import inserted at line",i+1)
PY
fi
python3 -m py_compile /root/pe-liq/liq_recorder.py && echo "liq_recorder compiles" || { cp liq_recorder.py.bak_532 liq_recorder.py; echo "RESTORED recorder (compile failed)"; exit 1; }
echo "-- shim test: a request built to overflow (all soccer markets, 36 h, heavy projection, maxResults 1000) --"
cd /root/pe-liq && timeout 240 python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-liq'); sys.path.insert(0,'/root/pe-queue/runner')
import bf_chunk, creds, requests, time, datetime
APP,USER,PW=creds.betfair()
r=requests.post("https://identitysso.betfair.com/api/login",data={"username":USER,"password":PW},headers={"X-Application":APP,"Accept":"application/json"},timeout=20).json()
assert r.get('status')=='SUCCESS', r.get('error'); tok=r['token']
H={"X-Application":APP,"X-Authentication":tok,"Content-Type":"application/json"}
now=datetime.datetime.utcnow()
body={"filter":{"eventTypeIds":["1"],"marketTypeCodes":["MATCH_ODDS","OVER_UNDER_25","ASIAN_HANDICAP","CORRECT_SCORE"],
      "marketStartTime":{"from":now.strftime('%Y-%m-%dT%H:%M:%SZ'),"to":(now+datetime.timedelta(hours=36)).strftime('%Y-%m-%dT%H:%M:%SZ')}},
      "marketProjection":["EVENT","COMPETITION","RUNNER_DESCRIPTION","MARKET_START_TIME","MARKET_DESCRIPTION"],"maxResults":1000}
raw=bf_chunk._orig(requests.Session(),'POST',"https://api.betfair.com/exchange/betting/rest/v1.0/listMarketCatalogue/",json=body,headers=H,timeout=25)
print("without shim:",raw.status_code,raw.text[:90].replace('\n',' '))
t=time.time(); r=requests.post("https://api.betfair.com/exchange/betting/rest/v1.0/listMarketCatalogue/",json=body,headers=H,timeout=25)
ms=r.json() if r.status_code==200 else []
print("with shim:",r.status_code,"markets",len(ms),"distinct",len({m['marketId'] for m in ms}),"with description",sum('description' in m for m in ms),f"{time.time()-t:.1f}s")
print("PASS A" if r.status_code==200 and len(ms)>200 else "FAIL A (overflow case did not return a merged 200 with >200 markets)")
PY
tail -3 /root/pe-liq/bf_chunk.log 2>/dev/null
pkill -f liq_recorder.py && echo "recorder stopped; keepalive cron relaunches it within 60 s with the shim" || echo "recorder was not running"
echo; echo "== B+C. bookie_paper.py =="
cd /root/pe-sports/bookie && cp bookie_paper.py bookie_paper.py.bak_532
python3 - <<'PY'
p='/root/pe-sports/bookie/bookie_paper.py'; s=open(p).read(); n0=len(s)
old="FROM liq_sample s JOIN last USING (market_id, ts)\"\"\")"
new="FROM liq_sample s JOIN last USING (market_id, ts) WHERE s.ts>now()-interval '90 seconds'\"\"\")   # 532: filter the joined side too (was a whole-table join, 40 s timeouts)"
assert s.count(old)==1, "B anchor"; s=s.replace(old,new)
old="lc.execute(\"select id, sel, side, fill_price, stake from bookie_paper where market_id=%s and status='filled'\",(b['marketId'],)); fills=lc.fetchall()"
new="lc.execute(\"select id, sel, side, fill_price, stake, event_name from bookie_paper where market_id=%s and status='filled'\",(b['marketId'],)); fills=lc.fetchall()"
assert s.count(old)==1, "C1 anchor"; s=s.replace(old,new)
old="                nm={norm(n):str(i) for i,n in cat_}\n                for oid,sel,side,fp,stk in fills:\n                    k=norm(sel);"
new=("                nm={norm(n):str(i) for i,n in cat_}\n"
     "                def sel_key(sel,ev):   # 532: the tape codes Match Odds runners HOME/AWAY/DRAW; the catalogue has team names\n"
     "                    u=str(sel).upper()\n"
     "                    if u=='DRAW': return norm('The Draw')\n"
     "                    if u in ('HOME','AWAY'):\n"
     "                        parts=re.split(r'\\s+v(?:s\\.?)?\\s+|\\s+-\\s+',str(ev or ''),maxsplit=1)\n"
     "                        if len(parts)==2: return norm(parts[0] if u=='HOME' else parts[1])\n"
     "                    return norm(sel)\n"
     "                for oid,sel,side,fp,stk,ev_ in fills:\n"
     "                    k=sel_key(sel,ev_);")
assert s.count(old)==1, "C2 anchor"; s=s.replace(old,new)
s=s.replace("import sys, time, datetime, traceback, json, requests, psycopg2, psycopg2.extras","import sys, time, datetime, traceback, json, re, requests, psycopg2, psycopg2.extras",1)
assert 'import sys, time, datetime, traceback, json, re, requests' in s, "re import"
open(p,'w').write(s); print("bookie_paper.py patched", n0, "->", len(s))
PY
python3 -m py_compile bookie_paper.py && echo "bookie_paper compiles" || { cp bookie_paper.py.bak_532 bookie_paper.py; echo "RESTORED bookie_paper (compile failed)"; exit 1; }
echo "-- B check: the fixed snapshot read against Railway, timed --"
timeout 120 python3 - <<'PY'
import sys,time; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
R=psycopg2.connect(creds.pg_railway(),sslmode='require',connect_timeout=20); c=R.cursor(); c.execute("SET statement_timeout='100s'")
t=time.time()
try:
    c.execute("""WITH last AS (SELECT market_id, max(ts) ts FROM liq_sample WHERE ts>now()-interval '90 seconds' GROUP BY 1)
                 SELECT count(*), count(distinct s.market_id) FROM liq_sample s JOIN last USING (market_id, ts) WHERE s.ts>now()-interval '90 seconds'""")
    print("fixed read: rows, markets =",c.fetchone(),f"in {time.time()-t:.1f}s  (0 rows is fine if the tape is quiet; the point is it returns)")
except Exception as e: print("fixed read FAILED:",repr(e)[:160])
PY
echo "-- C: release the HOME/AWAY/DRAW rows wrongly marked unsettleable so they settle on the official result --"
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
L=psycopg2.connect(creds.pg_local()); L.autocommit=True; c=L.cursor()
c.execute("update bookie_paper set status='filled', settled_ts=null where status='unsettleable' and coalesce(exchange,'betfair')='betfair' and version='v1.1' and upper(sel) in ('HOME','AWAY','DRAW')"); print("rows released to filled:",c.rowcount)
c.execute("select count(*) from bookie_paper where version='v1.1' and coalesce(exchange,'betfair')='betfair' and status='unsettleable'"); print("betfair unsettleable left:",c.fetchone()[0])
PY
pkill -f bookie_paper.py; echo "betfair leg stopped; keepalive relaunches it with the fixes"
echo; echo "== D. sports_team.py data_health =="
cd /root/pe-sports/team && cp sports_team.py sports_team.py.bak_532
python3 - <<'PY'
p='/root/pe-sports/team/sports_team.py'; s=open(p).read()
old="""def data_health():
    out={}
    for label,db,sql_n,sql_last in FEEDS:
        try:
            n=q(db,sql_n)[0][0]; last=q(db,sql_last)[0][0]
            out[label]=dict(status='ok' if n and n>0 else 'BROKEN', rows_24h=int(n or 0), last=str(last)[:16] if last else None, db=db)
        except Exception as e: out[label]=dict(status='BROKEN', rows_24h=0, last=None, db=db, note=re.sub(r'\\s+',' ',repr(e))[:120])
    return out"""
new="""def data_health():
    # 532: the last-timestamp read is index-only and fast; the 24 h count can time out when Railway is slow. A timed-out count is not
    # proof of no rows, so liveness then comes from the last timestamp (within 24 h = ok) and the line says the count was unread.
    out={}
    for label,db,sql_n,sql_last in FEEDS:
        last=None; lerr=None
        try: last=q(db,sql_last,'60s')[0][0]
        except Exception as e: lerr=re.sub(r'\\s+',' ',repr(e))[:100]
        try:
            n=q(db,sql_n)[0][0]
            out[label]=dict(status='ok' if n and n>0 else 'BROKEN', rows_24h=int(n or 0), last=str(last)[:16] if last else None, db=db)
        except Exception as e:
            fresh=False
            try:
                if isinstance(last,datetime.datetime): fresh=(datetime.datetime.now(datetime.timezone.utc)-(last if last.tzinfo else last.replace(tzinfo=datetime.timezone.utc))).total_seconds()<86400
                elif isinstance(last,datetime.date): fresh=(datetime.date.today()-last).days<=1
            except Exception: pass
            out[label]=dict(status='ok' if fresh else 'BROKEN', rows_24h=None, last=str(last)[:16] if last else None, db=db,
                            note=('count unread (timed out); last ts within 24h' if fresh else 'count unread: '+re.sub(r'\\s+',' ',repr(e))[:90]+(f'; last-ts read: {lerr}' if lerr else '')))
    return out"""
assert s.count(old)==1, "D anchor"; s=s.replace(old,new); open(p,'w').write(s); print("sports_team.py data_health patched")
PY
python3 -m py_compile sports_team.py && echo "sports_team compiles" || { cp sports_team.py.bak_532 sports_team.py; echo "RESTORED sports_team (compile failed)"; exit 1; }
echo "-- D check: run data_health once from the patched module --"
cd /root/pe-sports/team && timeout 600 python3 - <<'PY'
import sys, importlib.util, json; sys.path.insert(0,'/root/pe-sports/team')
src=open('/root/pe-sports/team/sports_team.py').read()
head=src.split('\ndef five_status')[0]   # imports, q(), FEEDS, data_health only — no daemon loop
ns={}; exec(compile(head,'sports_team_head','exec'),ns)
for k,v in ns['data_health']().items(): print(f"  {k}: {v['status']} | rows24h {v['rows_24h']} | last {v['last']} {v.get('note','')}")
PY
pkill -f 'sports_team.py'; sleep 2; nohup /root/pe-sports/team/run_team.sh >/dev/null 2>&1 & disown
sleep 20; echo "daemon pids:"; pgrep -f sports_team.py | wc -l; echo "bookie pids:"; pgrep -f bookie_paper.py | wc -l; echo "recorder pids:"; pgrep -f liq_recorder.py | wc -l
echo "532 done"
