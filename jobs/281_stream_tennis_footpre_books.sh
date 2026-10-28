#!/bin/bash
# 281: TWO MORE BOOKS ON THE SAME ENGINE. (a) Stream universe gains tennis Match Odds in-play (event type 2) and football Match
# Odds starting within 2 h (pre-match, top 40 by matched). (b) Engine gains MM_MKT so a book can target one market type.
# (c) Books: 'tennis10' (in-play, both players, no time window — tennis markets never close pre-off) and 'footpre10' (pre-match,
# 2 h window, flatten at 60 s before KO). Both £10, touch fills, same KPIs. Stream retention is 3 days so volume is fine.
set -e
echo "== stream universe"
python3 - <<'PY'
p='/root/pe-stream/stream_client.py'; s=open(p).read()
anchor="""    except Exception as e: print("catalogue",repr(e)[:150],flush=True)
    return out"""
add="""        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["2"],"marketTypeCodes":["MATCH_ODDS"],"inPlayOnly":True},"marketProjection":["EVENT","RUNNER_DESCRIPTION","MARKET_START_TIME"],"maxResults":40,"sort":"MAXIMUM_TRADED"}):
            out[m['marketId']]=dict(sport='tennis',mkt='MO',ev=m['event']['name'],start=datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00')),names={r['selectionId']:r['runnerName'] for r in m['runners']})
        t2=(now+datetime.timedelta(hours=2)).strftime('%Y-%m-%dT%H:%M:%SZ'); t_now=now.strftime('%Y-%m-%dT%H:%M:%SZ')
        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["1"],"marketTypeCodes":["MATCH_ODDS"],"inPlayOnly":False,"marketStartTime":{"from":t_now,"to":t2}},"marketProjection":["EVENT","RUNNER_DESCRIPTION","MARKET_START_TIME"],"maxResults":40,"sort":"MAXIMUM_TRADED"}):
            if m['marketId'] not in out: out[m['marketId']]=dict(sport='football',mkt='MO_PRE',ev=m['event']['name'],start=datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00')),names={r['selectionId']:r['runnerName'] for r in m['runners']})
"""
assert anchor in s, "universe anchor missing"
if "sport='tennis'" in s: print("already patched")
else: s=s.replace(anchor,add+anchor,1); open(p,'w').write(s); print("tennis in-play + football pre-match added to the universe")
PY
python3 -m py_compile /root/pe-stream/stream_client.py; pkill -f stream_client.py || true; sleep 2; nohup /root/pe-stream/keepalive.sh >/dev/null 2>&1 &
echo "== engine: MM_MKT"
python3 - <<'PY'
p='/root/pe-race/race_mm_size.py'; s=open(p).read()
s=s.replace("FROM stream_ticks WHERE sport=%s AND ts_recv > %s","FROM stream_ticks WHERE sport=%s AND mkt=%s AND ts_recv > %s",1)
s=s.replace("FROM stream_ticks WHERE sport=%s AND ts_recv>now()-interval '3 minutes'","FROM stream_ticks WHERE sport=%s AND mkt=%s AND ts_recv>now()-interval '3 minutes'",1)
s=s.replace("(SPORT,last_ts or datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=5),SPORT,RANKMAX))","(SPORT,MKT,last_ts or datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=5),SPORT,MKT,RANKMAX))",1)
s=s.replace("SPORT=os.environ.get('MM_SPORT','racing');","SPORT=os.environ.get('MM_SPORT','racing'); MKT=os.environ.get('MM_MKT','WIN');",1)
assert s.count("AND mkt=%s")==2 and "MKT=os.environ" in s and "(SPORT,MKT,last_ts" in s, "mkt anchors missing"
open(p,'w').write(s); print("MM_MKT added")
PY
python3 -m py_compile /root/pe-race/race_mm_size.py
cat > /root/pe-race/keepalive_mm_size.sh <<'SH'
#!/bin/bash
cd /root/pe-race
pgrep -f "race_mm_size.py 50through" >/dev/null || nohup python3 race_mm_size.py 50through >> mm_size50.log 2>&1 &
pgrep -f "race_mm_size.py 200through" >/dev/null || nohup python3 race_mm_size.py 200through >> mm_size200.log 2>&1 &
pgrep -f "race_mm_size.py 10v1" >/dev/null || MM_WINDOW=120 MM_RANK=1 MM_MINSPREAD=3 MM_EXCL="wolverhampton,kempton,lingfield,southwell,chelmsford,newcastle,dundalk" nohup python3 race_mm_size.py 10v1 >> mm_v1.log 2>&1 &
pgrep -f "race_mm_size.py tennis10" >/dev/null || MM_SPORT=tennis MM_MKT=MO MM_OKST=INPLAY MM_WINDOW=100000000 MM_FLAT=-100000000 MM_RANK=2 nohup python3 race_mm_size.py tennis10 >> mm_tennis.log 2>&1 &
pgrep -f "race_mm_size.py footpre10" >/dev/null || MM_SPORT=football MM_MKT=MO_PRE MM_OKST=OPEN MM_WINDOW=7200 MM_FLAT=60 MM_RANK=3 nohup python3 race_mm_size.py footpre10 >> mm_footpre.log 2>&1 &
SH
chmod +x /root/pe-race/keepalive_mm_size.sh
pkill -f race_mm_size.py || true; sleep 2; /root/pe-race/keepalive_mm_size.sh; sleep 90
echo "processes (expect 5):"; pgrep -af race_mm_size.py
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
k=psycopg2.connect(DB,sslmode='require').cursor()
k.execute("SELECT sport, mkt, count(*), count(DISTINCT market_id) FROM stream_ticks WHERE ts_recv>now()-interval '2 minutes' GROUP BY 1,2 ORDER BY 1,2"); print("stream last 2 min:",k.fetchall())
k.execute("SELECT * FROM stream_heartbeat"); print(k.fetchall())
PY
tail -n 2 /root/pe-race/mm_tennis.log /root/pe-race/mm_footpre.log 2>/dev/null || true
