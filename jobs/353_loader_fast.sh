#!/bin/bash
# 353: LOADER SPEED. Soccer 2026-09 alone lists 200,347 Basic files (every market in every country), and the loader
# downloads and parses one file at a time: ~40 days for 92 soccer months. Two changes to /root/pe-hist/loader_core.py:
# (1) Soccer = the 30 market types the tests use, in the 18 countries we trade (list below), which cuts the file count
# by ~10x; (2) downloads in parallel (12 threads, prefetch per chunk of 48) with parsing in the main thread.
# Backup kept; compile-checked; the running loader is restarted via its keepalive. Report: files/min before and after.
set -o pipefail
F=/root/pe-hist/loader_core.py; cp $F $F.bak_353
python3 - <<'PY'
p='/root/pe-hist/loader_core.py'; s=open(p).read()
old_spec="'Soccer':([],[])"
new_spec=("'Soccer':(['MATCH_ODDS','OVER_UNDER_05','OVER_UNDER_15','OVER_UNDER_25','OVER_UNDER_35','OVER_UNDER_45','BOTH_TEAMS_TO_SCORE','CORRECT_SCORE','ASIAN_HANDICAP','DRAW_NO_BET',"
          "'HALF_TIME','HALF_TIME_SCORE','HALF_TIME_FULL_TIME','FIRST_HALF_GOALS_05','FIRST_HALF_GOALS_15','FIRST_HALF_GOALS_25','SECOND_HALF_GOALS_05','SECOND_HALF_GOALS_15','NEXT_GOAL',"
          "'TEAM_A_OVER_UNDER_05','TEAM_A_OVER_UNDER_15','TEAM_B_OVER_UNDER_05','TEAM_B_OVER_UNDER_15','TOTAL_GOALS','DOUBLE_CHANCE','CLEAN_SHEET','WINNING_MARGIN',"
          "'OVER_UNDER_CORNERS','CORNER_HANDICAP','OVER_UNDER_BOOKING_POINTS','TO_SCORE','FIRST_GOAL_SCORER','GOAL_LINE'],"
          "['GB','ES','IT','DE','FR','PT','NL','BE','TR','SC','AT','CH','DK','SE','NO','GR','US','JP'])")
assert old_spec in s, "soccer spec anchor missing"; s=s.replace(old_spec,new_spec,1)
old_loop='''    for fp in pending:
        if time.time()-T0>BUDGET: break
        local=os.path.join(base,os.path.basename(fp))
        got=False
        for attempt in range(3):
            try:
                d=requests.get("https://historicdata.betfair.com/api/DownloadFile",params={"filePath":fp},headers={"ssoid":tok},timeout=120)
                if d.status_code==200: open(local,'wb').write(d.content); got=True; break
                if d.status_code==429: time.sleep(20)
            except Exception: time.sleep(5)
        if not got: continue
        try: md_,runners,last_min=parse(local)'''
new_loop='''    import concurrent.futures as _cf
    def _fetch(fp):
        local=os.path.join(base,os.path.basename(fp))
        for attempt in range(3):
            try:
                d=requests.get("https://historicdata.betfair.com/api/DownloadFile",params={"filePath":fp},headers={"ssoid":tok},timeout=120)
                if d.status_code==200: open(local,'wb').write(d.content); return fp,local
                if d.status_code==429: time.sleep(20)
            except Exception: time.sleep(5)
        return fp,None
    _t_chunk=time.time(); _n_chunk=0
    for _i in range(0,len(pending),48):
        if time.time()-T0>BUDGET: break
        with _cf.ThreadPoolExecutor(max_workers=12) as _ex: _got=list(_ex.map(_fetch,pending[_i:_i+48]))
        for fp,local in _got:
          if local is None: continue
          try: md_,runners,last_min=parse(local)'''
assert old_loop in s, "download loop anchor missing"; s=s.replace(old_loop,new_loop,1)
# the rest of the old loop body is indented 8 spaces; it now sits inside the inner for, so re-indent that body by 2
i=s.index(new_loop)+len(new_loop); j=s.index("    if rows: psycopg2.extras.execute_values(cur,\"INSERT INTO bf_hist_other VALUES %s\",rows,page_size=5000)")
body=s[i:j]
body="\n".join(("  "+ln if ln.startswith("        ") else ln) for ln in body.split("\n"))
body=body.replace("done.add(fp); n+=1","done.add(fp); n+=1; _n_chunk+=1\n          if _n_chunk%480==0: print(f'    {_n_chunk} files, {60*_n_chunk/max(1,time.time()-_t_chunk):.0f} files/min',flush=True)",1)
s=s[:i]+body+s[j:]
open(p,'w').write(s); print("loader_core patched")
PY
python3 -m py_compile /root/pe-hist/loader_core.py || { cp $F.bak_353 $F; echo "compile failed, restored"; exit 1; }
sed -n '/def _fetch/,/if rows: psycopg2/p' /root/pe-hist/loader_core.py | head -60 | cut -c1-160
echo "== restart"; pkill -f "pe-hist/loader.py"; sleep 70; pgrep -af "pe-hist/loader" | head -2; tail -5 /root/pe-hist/loader.log | cut -c1-200
