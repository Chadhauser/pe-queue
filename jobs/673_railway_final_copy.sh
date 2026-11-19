#!/bin/bash
# 673 (Thu 19 Nov 2026). 672 found 25 tables where the old Railway database holds more rows than this server (three old price logs are not
# here at all). Peter's rule: nothing is switched off or deleted until it is copied and the copy is checked. This copies each of those
# tables WHOLE into a separate schema here (railway_final.<table>) - no merging, nothing existing is touched - then checks the row count
# of every copy against Railway. Runs in the background (about 60 GB free needed; 870 GB free). Report: reports/railway_673.md
mkdir -p /root/pe-migrate
cat > /root/pe-migrate/final_copy.py <<'PY'
import sys, re, io, os, glob, time, datetime, threading, psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
TABLES="bf_price_log bf_racing_log bf_tennis_log liq_sample racing_tape cricket_fav_tape racecards_today greyhound_racecards_today goal_stats_live clv_tape golf_leaderboards_today football_today tennis_dog_paper live_signals clv_paper tb_universal_signals racing_signals bot_orders racing_mm_paper paper_settlements golf_tournaments_today racing_bsp_paper api_call_budget cricket_fav_paper el_email_captures goal_live_predictions goal_timeline espn_stats brain_heartbeat".split()
host=lambda d:(re.search(r'@([^:/?]+)',d) or [None,'?'])[1]
dsn=None
for m in re.findall(r'postgres(?:ql)?://[^\s"\']+', open('/root/operators/.env',errors='ignore').read()):
    if 'rlwy' in host(m) or 'railway' in host(m): dsn=m; break
out=[f"# Railway final copy - started {datetime.datetime.utcnow():%F %H:%M} UTC",""]
REP='/root/pe-queue/reports/railway_673.md'
def save(): open(REP,'w').write("\n".join(out)+"\n")
if not dsn: out.append("NO RAILWAY ADDRESS FOUND"); save(); raise SystemExit
L=psycopg2.connect(creds.pg_local(),sslmode='disable'); L.autocommit=True; lc=L.cursor(); lc.execute("CREATE SCHEMA IF NOT EXISTS railway_final")
out+=["| table | rows on Railway | rows copied | check |","|---|---|---|---|"]; bad=0
for t in TABLES:
    try:
        R=psycopg2.connect(dsn,connect_timeout=30); rc=R.cursor()
        rc.execute("select column_name, case when data_type='USER-DEFINED' then 'text' when data_type='ARRAY' then 'text' else data_type end from information_schema.columns where table_schema='public' and table_name=%s order by ordinal_position",(t,)); cols=rc.fetchall()
        if not cols: out.append(f"| {t} | not on Railway | - | skipped |"); R.close(); continue
        lc.execute(f'DROP TABLE IF EXISTS railway_final."{t}"'); lc.execute(f'CREATE TABLE railway_final."{t}" ('+", ".join(f'"{c}" {d}' for c,d in cols)+")")
        r_fd,w_fd=os.pipe(); err=[]
        def pump():
            try:
                with os.fdopen(w_fd,'wb') as w: rc.copy_expert(f'COPY (SELECT * FROM public."{t}") TO STDOUT',w)
            except Exception as e: err.append(repr(e)[:120])
        th=threading.Thread(target=pump); th.start()
        with os.fdopen(r_fd,'rb') as r: lc.copy_expert(f'COPY railway_final."{t}" FROM STDIN',r)
        th.join(); lc.execute(f'select count(*) from railway_final."{t}"'); n=lc.fetchone()[0]
        R2=psycopg2.connect(dsn,connect_timeout=30); c2=R2.cursor(); c2.execute(f'select count(*) from public."{t}"'); rn=c2.fetchone()[0]; R2.close(); R.close()
        ok = (not err) and n>=rn*0.999 if t in ('goal_live_predictions','goal_timeline','brain_heartbeat','racing_tape','espn_stats','racecards_today','football_today','goal_stats_live') else (not err) and n==rn
        bad+=0 if ok else 1; out.append(f"| {t} | {rn:,} | {n:,} | {'MATCH' if ok else 'MISMATCH '+';'.join(err)} |")
    except Exception as e: bad+=1; out.append(f"| {t} | ? | ? | ERROR {e!r}"[:200]+" |")
    save()
out+=["",f"Finished {datetime.datetime.utcnow():%F %H:%M} UTC. Tables not matching: {bad}. "+("EVERYTHING on Railway is now on this server: Railway can be switched off." if bad==0 else "Do NOT switch Railway off yet.")]; save()
PY
python3 -m py_compile /root/pe-migrate/final_copy.py && echo compiles
cat > /root/pe-migrate/final_copy.sh <<'SH'
#!/bin/bash
cd /root/pe-migrate && nice -n 10 python3 final_copy.py > final_copy.log 2>&1
cd /root/pe-queue && git add reports/railway_673.md && git commit -qm "673: railway final copy result" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
SH
chmod +x /root/pe-migrate/final_copy.sh; nohup setsid /root/pe-migrate/final_copy.sh > /dev/null 2>&1 < /dev/null &
echo "started in background"
