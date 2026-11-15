# loader_core.py and Postgres memory — 2026-11-15 16:04 UTC (job 587)

## A. loader_core.py (110 lines)
```
9:def ok(tok): return requests.get("https://historicdata.betfair.com/api/GetMyData",headers={"ssoid":tok},timeout=20).status_code==200
13:    if r.get('status')!='SUCCESS': print("WAITING: SSO login failed",r.get('error')); sys.exit(75)
15:    if not ok(tok): print("WAITING: token not accepted by Historic Data API"); sys.exit(75)
18:cur.execute("SELECT pg_database_size(current_database())/1e9"); gb=cur.fetchone()[0]; print(f"DB size {gb:.1f} GB")
20:if shutil.disk_usage('/root').free<20e9: print('WAITING: box disk under 20 GB free'); sys.exit(75)
21:cur.execute("""CREATE TABLE IF NOT EXISTS bf_hist_other (sport TEXT, market_id TEXT, event_id TEXT, event_name TEXT, market_type TEXT, market_time TIMESTAMPTZ, country TEXT,
22:  sel TEXT, ts TIMESTAMPTZ, ltp NUMERIC, inplay BOOLEAN); CREATE INDEX IF NOT EXISTS bfo_mkt ON bf_hist_other (sport, market_id);
23:  CREATE TABLE IF NOT EXISTS bf_hist_result (sport TEXT, market_id TEXT, event_id TEXT, market_type TEXT, sel TEXT, status TEXT, settled_time TEXT, market_status TEXT, PRIMARY KEY (market_id, sel));
24:  CREATE TABLE IF NOT EXISTS bf_hist_other_files (path TEXT PRIMARY KEY, loaded_at TIMESTAMPTZ);
25:  CREATE TABLE IF NOT EXISTS bf_hist_months (sport TEXT, y INT, m INT, status TEXT, files INT, loaded INT, updated TIMESTAMPTZ, PRIMARY KEY (sport,y,m))""")
26:md=requests.get("https://historicdata.betfair.com/api/GetMyData",headers=H,timeout=30).json()
30:        fd=str(d.get('forDate'))[:7]; y,m=int(fd[:4]),int(fd[5:7]); owned.add((d.get('sport'),y,m))
32:print("owned sport-months:",len(owned))
34:SPEC={'Tennis':(['MATCH_ODDS'],[]),'Greyhound Racing':(['WIN'],['GB','IE']),'Basketball':(['MATCH_ODDS'],[]),'Cricket':(['MATCH_ODDS'],[]),
35:      'Horse Racing':(['WIN'],['GB','IE']),'Golf':(['OUTRIGHT_WINNER','TOURNAMENT_WINNER'],[]),'Soccer':(['MATCH_ODDS','OVER_UNDER_05','OVER_UNDER_15','OVER_UNDER_25','OVER_UNDER_35','OVER_UNDER_45','BOTH_TEAMS_TO_SCORE','CORRE
36:PRIO=['Soccer','Horse Racing','Tennis','Cricket','Greyhound Racing','Basketball','Golf']
37:cur.execute("SELECT sport,y,m,status FROM bf_hist_months"); st={(a,b,c):d for a,b,c,d in cur.fetchall()}
38:cur.execute("CREATE INDEX IF NOT EXISTS bfo_type_time ON bf_hist_other (sport, market_type, market_time)")
45:cur.execute("SELECT path FROM bf_hist_other_files"); done={r[0] for r in cur.fetchall()}
47:def parse(local):
62:for sport,y,m in todo:
64:    mts,ctry=SPEC.get(sport,(['MATCH_ODDS'],[]))
65:    body={"sport":sport,"plan":"Basic Plan","fromDay":1,"fromMonth":m,"fromYear":y,"toDay":calendar.monthrange(y,m)[1],"toMonth":m,"toYear":y,"marketTypesCollection":mts,"countriesCollection":ctry,"fileTypeCollection":["M"]}
67:    if r.status_code!=200: print(f"{sport} {y}-{m:02d}: LIST HTTP {r.status_code} {r.text[:100]}"); cur.execute("INSERT INTO bf_hist_months VALUES (%s,%s,%s,'LISTFAIL',0,0,NOW()) ON CONFLICT (sport,y,m) DO UPDATE SET status='LI
69:    if not files: print(f"{sport} {y}-{m:02d}: empty list"); cur.execute("INSERT INTO bf_hist_months VALUES (%s,%s,%s,'EMPTY',0,0,NOW()) ON CONFLICT (sport,y,m) DO UPDATE SET status='EMPTY',updated=NOW()",(sport,y,m)); continue
70:    base=f"/root/bfdata/{sport.replace(' ','_').lower()}"; os.makedirs(base,exist_ok=True); n=0; rows=[]; pending=[f for f in files if f not in done]
71:    print(f"{sport} {y}-{m:02d}: {len(files)} files, {len(pending)} to load",flush=True)
73:    def _fetch(fp):
78:                if d.status_code==200: open(local,'wb').write(d.content); return fp,local
79:                if d.status_code==429: time.sleep(20)
94:              RES_ROWS.extend((sport,mid,str(md_.get('eventId')),md_.get('marketType'),runners.get(r.get('id'),str(r.get('id'))),r.get('status'),md_.get('settledTime'),md_.get('status')) for r in md_.get('runners',[]) if r.get(
96:                  rows.append((sport,mid,str(md_.get('eventId')),md_.get('eventName'),md_.get('marketType'),md_.get('marketTime'),md_.get('countryCode'),runners[sid],datetime.datetime.utcfromtimestamp(pt/1000).replace(tzinfo=da
97:          cur.execute("INSERT INTO bf_hist_other_files VALUES (%s,NOW()) ON CONFLICT DO NOTHING",(fp,)); done.add(fp); n+=1; _n_chunk+=1
99:          if len(rows)>=20000: psycopg2.extras.execute_values(cur,"INSERT INTO bf_hist_other VALUES %s ON CONFLICT DO NOTHING",rows,page_size=5000); (psycopg2.extras.execute_values(cur,"INSERT INTO bf_hist_result VALUES %s ON C
100:    if rows: psycopg2.extras.execute_values(cur,"INSERT INTO bf_hist_other VALUES %s ON CONFLICT DO NOTHING",rows,page_size=5000); (psycopg2.extras.execute_values(cur,"INSERT INTO bf_hist_result VALUES %s ON CONFLICT DO NOTHIN
101:    left=len([f for f in files if f not in done]); status='DONE' if left==0 else 'PARTIAL'
102:    cur.execute("INSERT INTO bf_hist_months VALUES (%s,%s,%s,%s,%s,%s,NOW()) ON CONFLICT (sport,y,m) DO UPDATE SET status=EXCLUDED.status,files=EXCLUDED.files,loaded=EXCLUDED.loaded,updated=NOW()",(sport,y,m,status,len(files),
103:    print(f"   {sport} {y}-{m:02d}: +{n} files this run, {left} left -> {status}",flush=True)
104:cur.execute("SELECT sport, count(*) FILTER (WHERE status='DONE'), count(*) FILTER (WHERE status<>'DONE'), sum(loaded) FROM bf_hist_months GROUP BY 1 ORDER BY 1")
105:print("progress by sport (done months, other months, files loaded):",cur.fetchall())
106:cur.execute("SELECT sport, count(DISTINCT market_id), min(market_time)::date, max(market_time)::date FROM bf_hist_other GROUP BY 1 ORDER BY 1"); print("bf_hist_other:",cur.fetchall())
107:cur.execute("SELECT sport,y,m,status FROM bf_hist_months")
110:if remaining: print(f"WAITING: {len(remaining)} owned months still to load — re-running"); sys.exit(75)
```
## A2. bf_hist_other columns and a non-Soccer sample
```
bf_hist_other: ['sport', 'market_id', 'event_id', 'event_name', 'market_type', 'market_time', 'country', 'sel', 'ts', 'ltp', 'inplay']
tennis sample: [('Tennis', 'MATCH_ODDS|Binda v Tokuda|2025-08-26 08:25:00+00', '34657330', 'Binda v Tokuda', 'MATCH_ODDS', datetime.datetime(2025, 8, 26, 8, 25, tzinfo=datetime.timezone.utc), None, 'Alexandr Binda', datetime.datetime(2025, 8, 26, 8, 38, 20, 497000, tzinfo=datetime.timezone.utc), Decimal('3.45'), True), ('Tennis', 'MATCH_ODDS|Binda v Tokuda|2025-08-26 08:25:00+00', '34657330', 'Binda v Tokuda', 'MATCH_ODDS', datetime.datetime(2025, 8, 26, 8, 25, tzinfo=datetime.timezone.utc), None, 'Alexandr Binda', datetime.datetime(2025, 8, 26, 8, 39, 19, 916000, tzinfo=datetime.timezone.utc), Decimal('3.55'), True)]
indexes: ['CREATE UNIQUE INDEX bfo_uniq ON public.bf_hist_other USING btree (market_id, sel, ts)', 'CREATE INDEX bfo_mkt ON public.bf_hist_other USING btree (sport, market_id)', 'CREATE INDEX bfo_type_time ON public.bf_hist_other USING btree (sport, market_type, market_time)', 'CREATE UNIQUE INDEX bf_hist_result_pkey ON public.bf_hist_result USING btree (market_id, sel)']
bf_hist_months : [('Cricket', 2024, 9, 'DONE', 371, 371, datetime.datetime(2026, 10, 17, 19, 24, 27, 60741, tzinfo=datetime.timezone.utc)), ('Cricket', 2024, 10, 'DONE', 357, 357, datetime.datetime(2026, 10, 17, 19, 18, 43, 137914, tzinfo=datetime.timezone.utc)), ('Cricket', 2024, 11, 'DONE', 264, 264, datetime.datetime(2026, 10, 17, 19, 13, 3, 764990, tzinfo=datetime.timezone.utc)), ('Cricket', 2024, 12, 'DONE', 245, 245, datetime.datetime(2026, 10, 17, 19, 11, 52, 682101, tzinfo=datetime.timezone.utc)), ('Cricket', 2025, 1, 'DONE', 268, 268, datetime.datetime(2026, 10, 17, 19, 6, 39, 682416, tzinfo=datetime.timezone.utc)), ('Cricket', 2025, 2, 'DONE', 251, 251, datetime.datetime(2026, 10, 17, 19, 1, 19, 855624, tzinfo=datetime.timezone.utc)), ('Cricket', 2025, 3, 'DONE', 388, 388, datetime.datetime(2026, 10, 17, 19, 0, 14, 583927, tzinfo=datetime.timezone.utc)), ('Cricket', 2025, 4, 'DONE', 227, 227, datetime.datetime(2026, 10, 17, 18, 54, 34, 622706, tzinfo=datetime.timezone.utc)), ('Cricket', 2025, 5, 'DONE', 254, 254, datetime.datetime(2026, 10, 17, 18, 49, 33, 423691, tzinfo=datetime.timezone.utc)), ('Cricket', 2025, 6, 'DONE', 379, 379, datetime.datetime(2026, 10, 17, 18, 48, 26, 163170, tzinfo=datetime.timezone.utc)), ('Cricket', 2025, 7, 'DONE', 387, 387, datetime.datetime(2026, 10, 17, 18, 42, 46, 58188, tzinfo=datetime.timezone.utc)), ('Cricket', 2025, 8, 'DONE', 477, 477, datetime.datetime(2026, 10, 17, 18, 37, 2, 749193, tzinfo=datetime.timezone.utc)), ('Cricket', 2025, 9, 'DONE', 286, 286, datetime.datetime(2026, 10, 17, 18, 30, 56, 562532, tzinfo=datetime.timezone.utc)), ('Cricket', 2025, 10, 'DONE', 277, 277, datetime.datetime(2026, 10, 17, 18, 25, 18, 573998, tzinfo=datetime.timezone.utc)), ('Cricket', 2025, 11, 'DONE', 454, 454, datetime.datetime(2026, 10, 17, 18, 18, 59, 576249, tzinfo=datetime.timezone.utc)), ('Cricket', 2025, 12, 'DONE', 490, 490, datetime.datetime(2026, 10, 17, 18, 12, 47, 307234, tzinfo=datetime.timezone.utc)), ('Cricket', 2026, 1, 'DONE', 519, 519, datetime.datetime(2026, 10, 17, 18, 6, 31, 403840, tzinfo=datetime.timezone.utc)), ('Cricket', 2026, 2, 'DONE', 349, 349, datetime.datetime(2026, 10, 17, 18, 6, 31, 134926, tzinfo=datetime.timezone.utc)), ('Cricket', 2026, 3, 'DONE', 385, 385, datetime.datetime(2026, 10, 17, 18, 6, 30, 917830, tzinfo=datetime.timezone.utc)), ('Cricket', 2026, 4, 'DONE', 380, 380, datetime.datetime(2026, 10, 17, 18, 6, 30, 697729, tzinfo=datetime.timezone.utc)), ('Cricket', 2026, 5, 'DONE', 520, 520, datetime.datetime(2026, 10, 17, 17, 58, 46, 650832, tzinfo=datetime.timezone.utc)), ('Cricket', 2026, 6, 'DONE', 647, 647, datetime.datetime(2026, 10, 17, 17, 52, 21, 651638, tzinfo=datetime.timezone.utc)), ('Cricket', 2026, 7, 'DONE', 520, 520, datetime.datetime(2026, 10, 17, 17, 39, 23, 396525, tzinfo=datetime.timezone.utc)), ('Cricket', 2026, 8, 'DONE', 416, 416, datetime.datetime(2026, 10, 17, 17, 32, 51, 232571, tzinfo=datetime.timezone.utc)), ('Cricket', 2026, 9, 'DONE', 280, 280, datetime.datetime(2026, 10, 17, 17, 26, 46, 223403, tzinfo=datetime.timezone.utc)), ('Golf', 2020, 1, 'EMPTY', 0, 0, datetime.datetime(2026, 10, 18, 2, 32, 7, 212138, tzinfo=datetime.timezone.utc)), ('Golf', 2020, 2, 'EMPTY', 0, 0, datetime.datetime(2026, 10, 18, 2, 32, 6, 996379, tzinfo=datetime.timezone.utc)), ('Golf', 2020, 3, 'EMPTY', 0, 0, datetime.datetime(2026, 10, 18, 2, 32, 6, 791007, tzinfo=datetime.timezone.utc)), ('Golf', 2020, 4, 'EMPTY', 0, 0, datetime.datetime(2026, 10, 18, 2, 32, 6, 542624, tzinfo=datetime.timezone.utc)), ('Golf', 2020, 5, 'EMPTY', 0, 0, datetime.datetime(2026, 10, 18, 2, 32, 6, 280776, tzinfo=datetime.timezone.utc)), ('Golf', 2020, 6, 'EMPTY', 0, 0, datetime.datetime(2026, 10, 18, 2, 32, 6, 7377, tzinfo=datetime.timezone.utc)), ('Golf', 2020, 7, 'EMPTY', 0, 0, datetime.datetime(2026, 10, 18, 2, 32, 5, 773798, tzinfo=datetime.timezone.utc)), ('Golf', 2020, 8, 'EMPTY', 0, 0, datetime.datetime(2026, 10, 18, 2, 32, 5, 549687, tzinfo=datetime.timezone.utc)), ('Golf', 2020, 9, 'EMPTY', 0, 0, datetime.datetime(2026, 10, 18, 2, 32, 5, 335214, tzinfo=datetime.timezone.utc)), ('Golf', 2020, 10, 'EMPTY', 0, 0, datetime.datetime(2026, 10, 18, 2, 32, 5, 135739, tzinfo=datetime.timezone.utc)), ('Golf', 2020, 11, 'EMPTY', 0, 0, datetime.datetime(2026, 10, 18, 2, 32, 4, 935168, tzinfo=datetime.timezone.utc)), ('Golf', 2020, 12, 'EMPTY', 0, 0, datetime.datetime(2026, 10, 18, 2, 32, 4, 708059, tzinfo=datetime.timezone.utc)), ('Golf', 2021, 1, 'EMPTY', 0, 0, datetime.datetime(2026, 10, 18, 2, 32, 4, 502760, tzinfo=datetime.timezone.utc)), ('Golf', 2021, 2, 'EMPTY', 0, 0, datetime.datetime(2026, 10, 18, 2, 32, 4, 298685, tzinfo=datetime.timezone.utc)), ('Golf', 2021, 3, 'EMPTY', 0, 0, datetime.datetime(2026, 10, 18, 2, 32, 4, 83093, tzinfo=datetime.timezone.utc))]
```
## B. Postgres memory
```
               total        used        free      shared  buff/cache   available
Mem:            7941        3215         325        1587        6294        4725

[1266736.178774] Out of memory: Killed process 970033 (python3) total-vm:5042860kB, anon-rss:3505708kB, file-rss:3072kB, shmem-rss:0kB, UID:0 pgtables:7324kB oom_score_adj:0
[1467757.028637] Out of memory: Killed process 2158011 (python3) total-vm:4471540kB, anon-rss:2676228kB, file-rss:2944kB, shmem-rss:0kB, UID:0 pgtables:5944kB oom_score_adj:0
[1526459.095642] Out of memory: Killed process 2778726 (python3) total-vm:4526836kB, anon-rss:3044484kB, file-rss:2816kB, shmem-rss:0kB, UID:0 pgtables:6564kB oom_score_adj:0
[1635531.049559] Memory cgroup out of memory: Killed process 12762 (python) total-vm:2860200kB, anon-rss:2242864kB, file-rss:27520kB, shmem-rss:0kB, UID:1000 pgtables:4720kB oom_score_adj:0
[1746747.922082] Out of memory: Killed process 1668638 (python3) total-vm:3939124kB, anon-rss:3658940kB, file-rss:2944kB, shmem-rss:0kB, UID:0 pgtables:7312kB oom_score_adj:0
[1912513.243638] Out of memory: Killed process 2554333 (postgres) total-vm:2335036kB, anon-rss:12456kB, file-rss:3072kB, shmem-rss:2087476kB, UID:109 pgtables:4476kB oom_score_adj:0

1536MB 64MB 256MB 100 5955MB 
  RSS COMMAND
1698692 postgres
1697708 postgres
1697584 postgres
1686468 postgres
1678084 postgres
1671516 postgres
1666848 postgres
1657824 postgres
1618284 postgres
1611304 postgres
1594420 postgres
```
