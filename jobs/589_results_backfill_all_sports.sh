#!/bin/bash
# 589 (Sun 15 Nov 2026, 16:45). Results backfill for the sports loaded before the loader wrote results (17 Oct): Cricket, Tennis, Horse
# Racing, Greyhound Racing. The loader deletes files after parsing, so the files are re-downloaded (results only, no price rows), each
# market's runner statuses inserted into bf_hist_result under BOTH market_id schemes the price table has used (file basename "1.2345" and the
# older "TYPE|event|time"), so the engine's join finds them either way. Cricket first as the pilot (9,391 files); the script reports the
# match rate against bf_hist_other before carrying on. Then the engine runs for those sports and the Verifier re-derives the passed list.
# Runs in the background (nohup); progress in /root/pe-hist/results_backfill.log; report reports/results_backfill.md.
set -o pipefail
cat > /root/pe-hist/results_backfill.py <<'PY'
import os, sys, bz2, json, time, calendar, datetime, shutil, requests, psycopg2, psycopg2.extras, concurrent.futures as cf
sys.path.insert(0,'/root/pe-queue/runner'); import creds
APP,U,P=creds.betfair()
r=requests.post("https://identitysso.betfair.com/api/login",data={"username":U,"password":P},headers={"X-Application":APP,"Accept":"application/json"},timeout=20).json()
tok=r.get('token'); assert tok, "SSO login failed"
H={"ssoid":tok,"Content-Type":"application/json"}
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); con.autocommit=True; cur=con.cursor(); cur.execute("SET statement_timeout='600s'")
SPEC={'Tennis':(['MATCH_ODDS'],[]),'Greyhound Racing':(['WIN'],['GB','IE']),'Cricket':(['MATCH_ODDS'],[]),'Horse Racing':(['WIN'],['GB','IE'])}
ORDER=[s for s in sys.argv[1:]] or ['Cricket','Tennis','Horse Racing','Greyhound Racing']
def log(*a): print(datetime.datetime.utcnow().strftime('%H:%M'),*a,flush=True)
def synth(md_):
    mt=md_.get('marketTime','');  # '2025-08-26T08:25:00.000Z' -> '2025-08-26 08:25:00+00'
    t=mt.replace('T',' ').split('.')[0].replace('Z','')+'+00'
    return f"{md_.get('marketType')}|{md_.get('eventName')}|{t}"
def parse(local):
    md_=None; runners={}
    with bz2.open(local,'rt') as f:
        for ln in f:
            if '"marketDefinition"' not in ln: continue
            try: o=json.loads(ln)
            except Exception: continue
            for mc in o.get('mc',[]):
                if 'marketDefinition' in mc: md_=mc['marketDefinition']; runners.update({x['id']:x['name'] for x in md_.get('runners',[])})
    return md_,runners
def fetch(fp,base):
    local=os.path.join(base,os.path.basename(fp))
    for attempt in range(3):
        try:
            d=requests.get("https://historicdata.betfair.com/api/DownloadFile",params={"filePath":fp},headers={"ssoid":tok},timeout=120)
            if d.status_code==200: open(local,'wb').write(d.content); return fp,local
            if d.status_code==429: time.sleep(20)
        except Exception: time.sleep(5)
    return fp,None
summary=[]
for sport in ORDER:
    cur.execute("SELECT count(*) FROM bf_hist_result WHERE sport=%s",(sport,)); before=cur.fetchone()[0]
    cur.execute("SELECT y,m FROM bf_hist_months WHERE sport=%s AND status IN ('DONE','PARTIAL','DONE_PRICE') ORDER BY y DESC, m DESC",(sport,)); months=cur.fetchall()
    log(sport,"months:",len(months),"results before:",before); mts,ctry=SPEC[sport]; base=f"/root/bfdata/_rb_{sport.replace(' ','_').lower()}"; os.makedirs(base,exist_ok=True); tot=0
    for y,m in months:
        if shutil.disk_usage('/root').free<5e9: log("STOP: disk under 5 GB"); break
        body={"sport":sport,"plan":"Basic Plan","fromDay":1,"fromMonth":m,"fromYear":y,"toDay":calendar.monthrange(y,m)[1],"toMonth":m,"toYear":y,"marketTypesCollection":mts,"countriesCollection":ctry,"fileTypeCollection":["M"]}
        rr=requests.post("https://historicdata.betfair.com/api/DownloadListOfFiles",headers=H,json=body,timeout=180)
        if rr.status_code!=200: log(sport,y,m,"LIST HTTP",rr.status_code); continue
        files=rr.json(); rows=[]; n=0
        for i in range(0,len(files),48):
            with cf.ThreadPoolExecutor(max_workers=12) as ex: got=list(ex.map(lambda fp: fetch(fp,base), files[i:i+48]))
            for fp,local in got:
                if not local: continue
                try: md_,runners=parse(local)
                except Exception: md_=None
                try: os.remove(local)
                except Exception: pass
                if not md_: continue
                n+=1; ids=[os.path.basename(fp).replace('.bz2',''), synth(md_)]
                for mid in ids:
                    rows.extend((sport,mid,str(md_.get('eventId')),md_.get('marketType'),runners.get(x.get('id'),str(x.get('id'))),x.get('status'),md_.get('settledTime'),md_.get('status')) for x in md_.get('runners',[]) if x.get('status') in ('WINNER','LOSER'))
            if len(rows)>=10000: psycopg2.extras.execute_values(cur,"INSERT INTO bf_hist_result VALUES %s ON CONFLICT DO NOTHING",rows,page_size=5000); rows=[]
        if rows: psycopg2.extras.execute_values(cur,"INSERT INTO bf_hist_result VALUES %s ON CONFLICT DO NOTHING",rows,page_size=5000)
        tot+=n; log(f"  {sport} {y}-{m:02d}: {len(files)} files, {n} markets with results")
    cur.execute("SELECT count(*) FROM bf_hist_result WHERE sport=%s",(sport,)); after=cur.fetchone()[0]
    cur.execute("SELECT count(DISTINCT r.market_id) FROM bf_hist_result r WHERE r.sport=%s AND EXISTS (SELECT 1 FROM bf_hist_other o WHERE o.sport=%s AND o.market_id=r.market_id)",(sport,sport)); matched=cur.fetchone()[0]
    cur.execute("SELECT count(DISTINCT market_id) FROM bf_hist_result WHERE sport=%s",(sport,)); dm=cur.fetchone()[0]
    line=f"{sport}: markets re-read {tot}, result rows {before} -> {after}, result markets {dm}, of which {matched} join to a price market"
    log(line); summary.append(line)
    if matched < 0.5*max(1,dm/2): log("  WARNING: under half the result markets join to prices — ids do not line up; stopping after this sport for a reading"); break
open('/root/pe-hist/results_backfill_summary.txt','w').write("\n".join(summary)+"\n")
log("backfill done; running the engine for these sports")
for sport in ORDER:
    os.environ['FP_SPORTS']=sport; S=sport.replace(' ','_')
    rc=os.system(f"cd /root/pe-sports/team && FP_SPORTS='{sport}' timeout 7200 /usr/bin/python3 fairprice_v0.py > fairprice_weekly_{S}.log 2>&1"); log(sport,"engine exit",rc>>8, "RESULT lines", sum(1 for l in open(f'/root/pe-sports/team/fairprice_weekly_{S}.log') if l.startswith('RESULT')))
os.system("cd /root/pe-sports/team && /usr/bin/python3 verifier_cells.py >> weekly_engine.log 2>&1")
cur.execute("SELECT sport, count(*) FROM fair_price_passed GROUP BY 1 ORDER BY 2 DESC"); passed=cur.fetchall(); log("passed cells by sport:",passed)
R='/root/pe-queue/reports/results_backfill.md'
with open(R,'w') as f:
    f.write(f"# Results backfill and engine, every sport — {datetime.datetime.utcnow():%F %H:%M} UTC\n\n")
    f.write("## Backfill\n"+"\n".join("- "+s for s in summary)+"\n\n## Engine\n```\n"+os.popen("tail -30 /root/pe-sports/team/weekly_engine.log | grep -v Deprecation").read()+"\n```\n")
    for sport in ORDER:
        S=sport.replace(' ','_'); f.write(f"### {sport}\n```\n"+os.popen(f"grep -v Deprecation /root/pe-sports/team/fairprice_weekly_{S}.log | tail -12 | cut -c1-200").read()+"```\n")
    f.write(f"\n## Passed cells by sport now\n{passed}\n")
os.system("cd /root/pe-queue && git add reports/results_backfill.md && git commit -qm 'results backfill + engine report' && git pull -q --no-rebase --no-edit && git push -q")
log("report pushed")
PY
python3 -m py_compile /root/pe-hist/results_backfill.py && echo "backfill compiles" || exit 1
echo "== loader disk guard 20 -> 10 GB (579's change never landed) =="
sed -i "s/shutil.disk_usage('\/root').free<20e9: print('WAITING: box disk under 20 GB free')/shutil.disk_usage('\/root').free<10e9: print('WAITING: box disk under 10 GB free')/" /root/pe-hist/loader_core.py && grep -n "disk under" /root/pe-hist/loader_core.py | cut -c1-120
echo "== start the backfill in the background =="
pgrep -f results_backfill.py >/dev/null && echo "already running" || { cd /root/pe-hist && nohup python3 results_backfill.py > results_backfill.log 2>&1 & disown; sleep 120; tail -5 /root/pe-hist/results_backfill.log | cut -c1-200; }
echo "589 done"
