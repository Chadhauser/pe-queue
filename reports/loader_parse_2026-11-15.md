# loader_core parse, verbatim — 2026-11-15 16:06 UTC (job 588)

```python
for y in (2024,2025,2026):
    for m in range(1,13):
        pass
todo=[(s,y,m) for s in PRIO for (sp,y,m) in sorted(owned,key=lambda x:(x[1],x[2]),reverse=True) if sp==s and st.get((s,y,m)) not in ('DONE','DONE_PRICE','EMPTY')]
print("months still to load:",len(todo),"| first:",todo[:5])
cur.execute("SELECT path FROM bf_hist_other_files"); done={r[0] for r in cur.fetchall()}
RES_ROWS=[]
def parse(local):
    md_=None; runners={}; last_min={}; inplay=False
    with bz2.open(local,'rt') as f:
        for ln in f:
            if not ln.strip(): continue
            try: o=json.loads(ln)
            except Exception: continue
            pt=o.get('pt')
            for mc in o.get('mc',[]):
                if 'marketDefinition' in mc:
                    md_=mc['marketDefinition']; runners.update({x['id']:x['name'] for x in md_.get('runners',[])}); inplay=bool(md_.get('inPlay'))
                if not md_: continue
                for rc in mc.get('rc',[]):
                    if 'ltp' in rc and rc['id'] in runners: last_min[(rc['id'],pt//60000)]=(pt,rc['ltp'],inplay)
    return md_,runners,last_min
for sport,y,m in todo:
    if time.time()-T0>BUDGET: break
    mts,ctry=SPEC.get(sport,(['MATCH_ODDS'],[]))
    body={"sport":sport,"plan":"Basic Plan","fromDay":1,"fromMonth":m,"fromYear":y,"toDay":calendar.monthrange(y,m)[1],"toMonth":m,"toYear":y,"marketTypesCollection":mts,"countriesCollection":ctry,"fileTypeCollection":["M"]}
    r=requests.post("https://historicdata.betfair.com/api/DownloadListOfFiles",headers=H,json=body,timeout=180)
    if r.status_code!=200: print(f"{sport} {y}-{m:02d}: LIST HTTP {r.status_code} {r.text[:100]}"); cur.execute("INSERT INTO bf_hist_months VALUES (%s,%s,%s,'LISTFAIL',0,0,NOW()) ON CONFLICT (sport,y,m) DO UPDATE SET status='LISTFAIL',updated=NOW()",(sport,y,m)); continue
    files=r.json()
    if not files: print(f"{sport} {y}-{m:02d}: empty list"); cur.execute("INSERT INTO bf_hist_months VALUES (%s,%s,%s,'EMPTY',0,0,NOW()) ON CONFLICT (sport,y,m) DO UPDATE SET status='EMPTY',updated=NOW()",(sport,y,m)); continue
    base=f"/root/bfdata/{sport.replace(' ','_').lower()}"; os.makedirs(base,exist_ok=True); n=0; rows=[]; pending=[f for f in files if f not in done]
    print(f"{sport} {y}-{m:02d}: {len(files)} files, {len(pending)} to load",flush=True)
    import concurrent.futures as _cf
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
          try: md_,runners,last_min=parse(local)
          except Exception as e: md_=None
          try: os.remove(local)
          except Exception: pass
          if md_:
              mid=os.path.basename(fp).replace('.bz2','')
              RES_ROWS.extend((sport,mid,str(md_.get('eventId')),md_.get('marketType'),runners.get(r.get('id'),str(r.get('id'))),r.get('status'),md_.get('settledTime'),md_.get('status')) for r in md_.get('runners',[]) if r.get('status') in ('WINNER','LOSER'))
              for (sid,_),(pt,p,ip) in last_min.items():
                  rows.append((sport,mid,str(md_.get('eventId')),md_.get('eventName'),md_.get('marketType'),md_.get('marketTime'),md_.get('countryCode'),runners[sid],datetime.datetime.utcfromtimestamp(pt/1000).replace(tzinfo=datetime.timezone.utc),p,ip))
          cur.execute("INSERT INTO bf_hist_other_files VALUES (%s,NOW()) ON CONFLICT DO NOTHING",(fp,)); done.add(fp); n+=1; _n_chunk+=1
          if _n_chunk%480==0: print(f'    {_n_chunk} files, {60*_n_chunk/max(1,time.time()-_t_chunk):.0f} files/min',flush=True)
          if len(rows)>=20000: psycopg2.extras.execute_values(cur,"INSERT INTO bf_hist_other VALUES %s ON CONFLICT DO NOTHING",rows,page_size=5000); (psycopg2.extras.execute_values(cur,"INSERT INTO bf_hist_result VALUES %s ON CONFLICT DO NOTHING",RES_ROWS,page_size=5000) if RES_ROWS else None); RES_ROWS.clear(); rows=[]
    if rows: psycopg2.extras.execute_values(cur,"INSERT INTO bf_hist_other VALUES %s ON CONFLICT DO NOTHING",rows,page_size=5000); (psycopg2.extras.execute_values(cur,"INSERT INTO bf_hist_result VALUES %s ON CONFLICT DO NOTHING",RES_ROWS,page_size=5000) if RES_ROWS else None); RES_ROWS.clear()
```
## /root/bfdata
```
/root/bfdata/cricket/: 1253 files, 6.4M
/root/bfdata/cricket/xds_nfs__edp_processed__BASIC__2026__Mar__18__35303629__1.254460264.bz2
/root/bfdata/cricket/xds_nfs__edp_processed__BASIC__2026__Mar__3__35303974__1.254558423.bz2
/root/bfdata/ext/: 661056 files, 2.6G
/root/bfdata/ext/xds_nfs__edp_processed__BASIC__2024__Aug__2__29072538__1.153319636.bz2
/root/bfdata/ext/xds_nfs__edp_processed__BASIC__2024__Aug__2__29072538__1.153319678.bz2
/root/bfdata/greyhound_racing/: 0 files, 4.0K
/root/bfdata/horse_racing/: 1302 files, 14M
/root/bfdata/horse_racing/xds_nfs__edp_processed__BASIC__2026__May__20__35623150__1.258335913.bz2
/root/bfdata/horse_racing/xds_nfs__edp_processed__BASIC__2026__May__19__35619037__1.258299720.bz2
/root/bfdata/soccer/: 51361 files, 229M
/root/bfdata/soccer/1.248867678.bz2
/root/bfdata/soccer/1.248747739.bz2
/root/bfdata/tennis/: 0 files, 4.0K
total 645520
drwxr-xr-x  8 root root 13647872 Oct 16 21:53 .
drwx------ 66 root root     4096 Nov 15 17:00 ..
-rw-r--r--  1 root root  8145860 Oct  4 11:10 _filelist.json
-rw-r--r--  1 root root     6881 Oct  4 17:04 _load.log
-rw-r--r--  1 root root     5079 Oct  6 19:05 _load2.log
-rw-r--r--  1 root root    12578 Oct  4 14:50 _pull.log
drwxr-xr-x  2 root root   147456 Oct 17 21:24 cricket
drwxr-xr-x  2 root root 76525568 Oct 10 12:06 ext
drwxr-xr-x  2 root root     4096 Oct 17 19:21 greyhound_racing
```
## months by sport and status
```
('Cricket', 'DONE', 25, 9391, 202409, 202609)
('Golf', 'EMPTY', 76, 0, 202001, 202604)
('Greyhound Racing', 'DONE', 26, 104708, 202409, 202610)
('Horse Racing', 'DONE', 25, 27748, 202409, 202609)
('Soccer', 'DONE', 37, 1686537, 202110, 202607)
('Soccer', 'LISTFAIL', 12, 0, 202411, 202510)
('Soccer', 'PARTIAL', 11, 524498, 202210, 202609)
('Tennis', 'DONE', 18, 51367, 202409, 202603)
('Tennis', 'PARTIAL', 1, 3901, 202510, 202510)
files loaded: 2508487
files by first path part: [('', 2508439), ('NOTOWNED::Horse Racing::2025-02', 1), ('DONE::Soccer::2024-12', 1), ('NOTOWNED::Horse Racing::2024-09', 1), ('NOTOWNED::Tennis::2025-02', 1), ('NOTOWNED::Tennis::2025-04', 1), ('NOTOWNED::Basketball::2025-03', 1), ('NOTOWNED::Horse Racing::2024-10', 1), ('NOTOWNED::Tennis::2024-12', 1), ('NOTOWNED::Greyhound Racing::2025-04', 1), ('NOTOWNED::Greyhound Racing::2025-02', 1), ('NOTOWNED::Basketball::2024-11', 1)]
sample paths: [('/xds_nfs/edp_processed/BASIC/2026/Sep/2/34690471/1.247358822.bz2',), ('/xds_nfs/edp_processed/BASIC/2026/Sep/2/34690471/1.247358823.bz2',), ('/xds_nfs/edp_processed/BASIC/2026/Sep/2/34690471/1.247358824.bz2',)]
```
