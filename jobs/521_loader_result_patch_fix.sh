#!/bin/bash
# 521: 520's loader patch stopped at its flush anchor (354 changed the insert to "... ON CONFLICT DO NOTHING"), but the job carried on
# and cleared the file records, so the loader is re-reading the months WITHOUT capturing results. Patch with a regex anchor, verify by
# compile + a grep of all three insertion points, restart the loader. H1 re-queued for 6 h from now (results need time to land).
set -o pipefail
F=/root/pe-hist/loader_core.py; cp $F $F.bak_521
python3 - <<'PY' || { cp /root/pe-hist/loader_core.py.bak_521 /root/pe-hist/loader_core.py; echo "PATCH FAILED, restored"; exit 1; }
import re
p='/root/pe-hist/loader_core.py'; s=open(p).read()
if 'bf_hist_result' in s: print("already patched"); raise SystemExit(0)
anchor='CREATE TABLE IF NOT EXISTS bf_hist_other_files'; assert anchor in s, 'files-table anchor'
s=s.replace(anchor,"CREATE TABLE IF NOT EXISTS bf_hist_result (sport TEXT, market_id TEXT, event_id TEXT, market_type TEXT, sel TEXT, status TEXT, settled_time TEXT, market_status TEXT, PRIMARY KEY (market_id, sel));\n  "+anchor,1)
assert 'def parse(local):' in s; s=s.replace("def parse(local):","RES_ROWS=[]\ndef parse(local):",1)
m=re.search(r"^(\s*)mid=os\.path\.basename\(fp\)\.replace\('\.bz2',''\)\s*$",s,re.M); assert m, 'mid anchor'
ind=m.group(1)
s=s[:m.end()]+"\n"+ind+"RES_ROWS.extend((sport,mid,str(md_.get('eventId')),md_.get('marketType'),runners.get(r.get('id'),str(r.get('id'))),r.get('status'),md_.get('settledTime'),md_.get('status')) for r in md_.get('runners',[]) if r.get('status') in ('WINNER','LOSER'))"+s[m.end():]
pat=re.compile(r'psycopg2\.extras\.execute_values\(cur,"INSERT INTO bf_hist_other VALUES %s[^"]*",rows,page_size=5000\)')
n=len(pat.findall(s)); assert n>=1, 'flush anchor'
s=pat.sub(lambda mm: mm.group(0)+'; (psycopg2.extras.execute_values(cur,"INSERT INTO bf_hist_result VALUES %s ON CONFLICT DO NOTHING",RES_ROWS,page_size=5000) if RES_ROWS else None); RES_ROWS.clear()',s)
open(p,'w').write(s); print("patched; flush sites:",n)
PY
python3 -m py_compile $F || { cp $F.bak_521 $F; echo "compile failed, restored"; exit 1; }
grep -c "bf_hist_result" $F
pkill -f "pe-hist/loader.py"; sleep 8; pgrep -af "pe-hist/loader" | head -2; tail -3 /root/pe-hist/loader.log | cut -c1-160
python3 - <<'PY'
import json,datetime; p='/root/pe-sports/team/hypotheses.json'; r=json.load(open(p))
for h in r['hypotheses']:
    if h['id'].startswith('H1 fair price v0'): h['status']='proposed'; h['not_before']=(datetime.datetime.utcnow()+datetime.timedelta(hours=6)).isoformat(); h['note']='waits for official results to land (521)'
json.dump(r,open(p,'w'),indent=1); print("H1 scheduled for", [h.get('not_before') for h in r['hypotheses'] if h['id'].startswith('H1')])
PY
sleep 240; python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
k=psycopg2.connect(creds.pg_local()).cursor(); k.execute("select count(*), count(distinct market_id) from bf_hist_result"); print("bf_hist_result rows/markets after 4 min:",k.fetchone())
PY
