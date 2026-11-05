#!/bin/bash
# 520: OFFICIAL RESULTS INTO THE HISTORY (from audit 519). The BASIC file's final marketDefinition carries each runner's status
# (WINNER/LOSER) — the loader parsed it and threw it away, and H1 settled by price collapse instead, which is biased (in-play rows often
# end early: goal-collapsed markets kept, the rest dropped -> 97-100% "win rates"). Now: (1) loader_core.py writes bf_hist_result
# (market_id, sel, status, settled_time) for every file it reads; (2) the two finished soccer months are re-read so they get results
# (rows dedupe on the unique index); (3) H1 settles on bf_hist_result only; (4) the Verifier holds any cell with |IS rate - implied|>15
# points, t>15 or >£3/£10 as DATA CHECK instead of WORKS; (5) the bookie bot uses only sane cells and quotes at factor 1.0 otherwise
# (pure spread capture = the baseline). Daemon and bot restarted.
# 406 (watchman fix of 520): line 26 `assert flush in s` failed because job 354 had added ON CONFLICT DO NOTHING to the insert, so the loader was never patched while the job carried on and exited 0.
# 406 scope: step (1) only. Steps (2)-(5) already ran in 520, and the Watchman may not delete bookkeeping, restart the loader or write /root/pe-sports.
# The running loader compiled its code when its cycle began, so this patch has NO EFFECT until Peter restarts it. See reports/watchman_* for that step.
set -eo pipefail
F=/root/pe-hist/loader_core.py
if grep -q 'bf_hist_result' "$F"; then echo "loader already writes bf_hist_result, nothing to do"; exit 0; fi
cp "$F" "$F.bak_406"
python3 - "$F" <<'PY'
import re, sys
p=sys.argv[1]; s=open(p).read()
# table
anchor='CREATE TABLE IF NOT EXISTS bf_hist_other_files'
assert anchor in s, 'files-table anchor missing'
s=s.replace(anchor,"CREATE TABLE IF NOT EXISTS bf_hist_result (sport TEXT, market_id TEXT, event_id TEXT, market_type TEXT, sel TEXT, status TEXT, settled_time TEXT, market_status TEXT, PRIMARY KEY (market_id, sel));\n  "+anchor,1)
# module-level buffer
assert 'def parse(local):' in s, 'parse anchor missing'
s=s.replace("def parse(local):","RES_ROWS=[]\ndef parse(local):",1)
# collect after mid=
m=re.search(r"^(\s*)mid=os\.path\.basename\(fp\)\.replace\('\.bz2',''\)\s*$",s,re.M); assert m, 'mid anchor missing'
ind=m.group(1)
s=s[:m.end()]+"\n"+ind+"RES_ROWS.extend((sport,mid,str(md_.get('eventId')),md_.get('marketType'),runners.get(r.get('id'),str(r.get('id'))),r.get('status'),md_.get('settledTime'),md_.get('status')) for r in md_.get('runners',[]) if r.get('status') in ('WINNER','LOSER'))"+s[m.end():]
# flush wherever rows are flushed (the 520 anchor lacked the ON CONFLICT clause job 354 added)
flush='psycopg2.extras.execute_values(cur,"INSERT INTO bf_hist_other VALUES %s ON CONFLICT DO NOTHING",rows,page_size=5000)'
assert s.count(flush)==2, 'expected 2 flush sites, found %d'%s.count(flush)
s=s.replace(flush,flush+'; (psycopg2.extras.execute_values(cur,"INSERT INTO bf_hist_result VALUES %s ON CONFLICT DO NOTHING",RES_ROWS,page_size=5000) if RES_ROWS else None); RES_ROWS.clear()')
open(p,'w').write(s); print("loader patched; flush sites:",s.count('bf_hist_result VALUES'))
PY
python3 -m py_compile "$F" || { cp "$F.bak_406" "$F"; echo "compile failed, restored"; exit 1; }
echo "patched on disk. NOT LIVE until the loader is restarted (Peter's step)."
