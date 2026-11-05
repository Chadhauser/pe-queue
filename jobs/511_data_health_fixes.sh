#!/bin/bash
# 511: DATA HEALTH FIXES from the first scoreboard (09:08 UTC 5 Nov): (1) racing_bsp stopped 12 Oct — 067 was a one-off rebuild with no
# daily pull; now /root/pe-data/bsp_daily.py (local DB) runs 09:40 daily and backfills 13 Oct -> yesterday. (2) af_fixtures results for
# the current season were never refreshed after 331 (0 finished fixtures in 48h): /root/pe-data/af_daily.py (local DB, season 2026,
# re-pulls every league's fixture list so statuses/scores update, then events+stats for new FT) every 3 h. (3) xx_tape has no ts index so
# every 24h count timed out: CREATE INDEX CONCURRENTLY on (exchange, ts) on Railway. (4) sports_team.py feed definitions corrected
# (stream_ticks.ts_recv, coach_tape on Railway, 150s timeouts) and the daemon restarted only once H1 is not running.
set -o pipefail
mkdir -p /root/pe-data
cat > /root/pe-data/bsp_daily.py <<'PY'
import sys,io,time,datetime,requests,pandas as pd,psycopg2,psycopg2.extras
sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_local(),sslmode='prefer'); con.autocommit=True; cur=con.cursor()
cur.execute("CREATE TABLE IF NOT EXISTS racing_bsp_files (fname TEXT PRIMARY KEY, rows INT, loaded_at TIMESTAMPTZ)")
cur.execute("SELECT fname FROM racing_bsp_files"); done={r[0] for r in cur.fetchall()}
cur.execute("SELECT coalesce(max(event_dt)::date, date '2026-10-12') FROM racing_bsp"); d=cur.fetchone()[0]-datetime.timedelta(days=1)
end=datetime.date.today()-datetime.timedelta(days=1); n=0
COLS=['event_id','menu_hint','event_name','event_dt','selection_id','selection_name','win_lose','bsp','ppwap','morningwap','ppmax','ppmin','ipmax','ipmin','morningtradedvol','pptradedvol','iptradedvol']
while d<=end:
    for country in ('uk','ire'):
        for market in ('win','place'):
            fname=f"dwbfprices{country}{market}{d:%d%m%Y}.csv"
            if fname in done: continue
            try: r=requests.get(f"https://promo.betfair.com/betfairsp/prices/{fname}",timeout=30)
            except Exception as e: print("fetch error",fname,repr(e)[:60]); continue
            if r.status_code!=200 or len(r.content)<50: continue   # not published yet: retry tomorrow
            df=pd.read_csv(io.StringIO(r.text)); df.columns=[c.strip().lower() for c in df.columns]
            for c in COLS:
                if c not in df.columns: df[c]=None
            rows=[]
            for x in df[COLS].itertuples(index=False):
                try: dt=datetime.datetime.strptime(str(x.event_dt).strip(),'%d-%m-%Y %H:%M')
                except Exception: dt=None
                rows.append((country,market,int(x.event_id) if pd.notna(x.event_id) else None,x.menu_hint,x.event_name,dt,int(x.selection_id) if pd.notna(x.selection_id) else None,x.selection_name,
                             int(x.win_lose) if pd.notna(x.win_lose) else None,*[(float(v) if pd.notna(v) else None) for v in (x.bsp,x.ppwap,x.morningwap,x.ppmax,x.ppmin,x.ipmax,x.ipmin,x.morningtradedvol,x.pptradedvol,x.iptradedvol)]))
            cur.execute("DELETE FROM racing_bsp WHERE country=%s AND market=%s AND event_dt::date=%s",(country,market,d))
            psycopg2.extras.execute_values(cur,"INSERT INTO racing_bsp VALUES %s",rows,page_size=2000)
            cur.execute("INSERT INTO racing_bsp_files VALUES (%s,%s,NOW()) ON CONFLICT (fname) DO UPDATE SET rows=EXCLUDED.rows, loaded_at=NOW()",(fname,len(rows))); n+=1
    d+=datetime.timedelta(days=1)
cur.execute("SELECT max(event_dt), count(*) FILTER (WHERE event_dt>now()-interval '3 days') FROM racing_bsp"); print("bsp files loaded",n,"| max event_dt / rows 3d:",cur.fetchone())
PY
cat > /root/pe-data/af_daily.py <<'PY'
import sys,time,requests,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
AF=creds.apifootball(); H={"x-apisports-key":AF}; BASE="https://v3.football.api-sports.io"
LEAGUES=[39,40,41,42,140,141,135,136,78,79,61,62,88,94,144,179,203,197,218,207,103,113,119,71,128,253,98,2,3]; S=2026
con=psycopg2.connect(creds.pg_local(),sslmode='prefer'); con.autocommit=True; k=con.cursor()
DEADLINE=time.time()+15*60; remaining=None
def get(path,params):
    global remaining
    for a in range(3):
        r=requests.get(BASE+path,params=params,headers=H,timeout=20); remaining=r.headers.get('x-ratelimit-requests-remaining',remaining)
        if r.status_code==429: time.sleep(10); continue
        if r.status_code!=200: time.sleep(2); continue
        j=r.json()
        if j.get('errors') and not j.get('response'): print("api error",params,j.get('errors')); return None
        time.sleep(0.25); return j.get('response')
    return None
upd=0
for L in LEAGUES:
    res=get("/fixtures",{"league":L,"season":S}) or []
    for f in res:
        fx=f['fixture']; t=f['teams']; g=f['goals']; ht=(f.get('score') or {}).get('halftime') or {}
        k.execute("""INSERT INTO af_fixtures (fixture_id,league_id,league,season,kickoff,home,away,hg,ag,ht_hg,ht_ag,status,events_done,stats_done) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,false,false)
                     ON CONFLICT (fixture_id) DO UPDATE SET hg=EXCLUDED.hg, ag=EXCLUDED.ag, ht_hg=EXCLUDED.ht_hg, ht_ag=EXCLUDED.ht_ag, status=EXCLUDED.status, kickoff=EXCLUDED.kickoff""",
                  (fx['id'],L,f['league']['name'],S,fx['date'],t['home']['name'],t['away']['name'],g['home'],g['away'],ht.get('home'),ht.get('away'),fx['status']['short'])); upd+=1
print("fixtures refreshed",upd,"| remaining",remaining,flush=True)
k.execute("SELECT fixture_id, home FROM af_fixtures WHERE season=%s AND status IN ('FT','AET','PEN') AND (NOT coalesce(events_done,false) OR NOT coalesce(stats_done,false)) ORDER BY kickoff DESC",(S,)); todo=k.fetchall(); print("needing events/stats:",len(todo)); done=0
for fid,home in todo:
    if time.time()>DEADLINE or (remaining is not None and int(remaining)<300): break
    ev=get("/fixtures/events",{"fixture":fid})
    if ev is not None:
        k.execute("DELETE FROM af_events WHERE fixture_id=%s",(fid,))
        k.executemany("INSERT INTO af_events VALUES (%s,%s,%s,%s,%s,%s,%s,%s)",[(fid,(e.get('time') or {}).get('elapsed'),(e.get('time') or {}).get('extra'),(e.get('team') or {}).get('name'),(e.get('team') or {}).get('name')==home,e.get('type'),e.get('detail'),(e.get('player') or {}).get('name')) for e in ev])
        k.execute("UPDATE af_fixtures SET events_done=true WHERE fixture_id=%s",(fid,))
    st=get("/fixtures/statistics",{"fixture":fid})
    if st is not None:
        k.execute("DELETE FROM af_stats WHERE fixture_id=%s",(fid,))
        for t in st:
            d={x['type']:x['value'] for x in t.get('statistics',[])}
            def num(v):
                try: return float(str(v).replace('%','')) if v is not None else None
                except Exception: return None
            import json
            k.execute("INSERT INTO af_stats VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)",(fid,t['team']['name']==home,t['team']['name'],num(d.get('Total Shots')),num(d.get('Shots on Goal')),num(d.get('Ball Possession')),num(d.get('Corner Kicks')),num(d.get('expected_goals')),json.dumps(d)))
        k.execute("UPDATE af_fixtures SET stats_done=true WHERE fixture_id=%s",(fid,))
    done+=1
k.execute("SELECT count(*) FROM af_fixtures WHERE kickoff>now()-interval '48 hours' AND status IN ('FT','AET','PEN')"); print("events/stats done",done,"| finished fixtures 48h:",k.fetchone()[0],"| remaining",remaining)
PY
python3 -m py_compile /root/pe-data/bsp_daily.py /root/pe-data/af_daily.py || exit 1
( crontab -l 2>/dev/null | grep -v 'bsp_daily.py\|af_daily.py'; echo "40 9 * * * python3 /root/pe-data/bsp_daily.py >> /root/pe-data/bsp_daily.log 2>&1"; echo "20 */3 * * * python3 /root/pe-data/af_daily.py >> /root/pe-data/af_daily.log 2>&1" ) | crontab -
echo "== BSP backfill now"; timeout 900 python3 /root/pe-data/bsp_daily.py | tail -3
echo "== AF results refresh now"; timeout 1100 python3 /root/pe-data/af_daily.py | tail -4
echo "== xx_tape index on Railway (concurrently)"
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_railway(),sslmode='require'); con.autocommit=True; c=con.cursor(); c.execute("SET statement_timeout=0")
c.execute("CREATE INDEX CONCURRENTLY IF NOT EXISTS xx_tape_exch_ts ON xx_tape (exchange, ts)"); c.execute("SET statement_timeout='120s'")
c.execute("select exchange,count(*),max(ts) from xx_tape where ts>now()-interval '24 hours' group by 1"); print("xx_tape 24h:",c.fetchall())
PY
echo "== daemon feeds corrected; restart when H1 is not running"
cp /root/pe-sports/team/sports_team.py /root/pe-sports/team/sports_team.py.bak_511
cat > /root/pe-sports/team/sports_team.py <<'PYFILE'
# SPORTS TEAM — continuous background loop on the trading server (Peter, 5 Nov 2026).
# Proposer = pre-registered hypotheses.json (THE ONE JOB: fair price first, then the resting-order bookie bot; no named strategies).
# Critics = mechanical pre-run checks. Builder runs the script. Verifier applies the gates and is the ONLY writer of
# /root/pe-sports/team/scoreboard.{json,md}. Every cycle opens with a DATA HEALTH block over both databases (Railway live tape,
# local history); the five live jobs get one status line each from the tables themselves. The scoreboard is mirrored into
# Railway job_results (job='SPORTS_SCOREBOARD') so the chat can read it from anywhere.
import os, sys, json, time, subprocess, datetime, traceback, re
sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
ROOT='/root/pe-sports/team'; REG=f'{ROOT}/hypotheses.json'; SB=f'{ROOT}/scoreboard.json'; SBMD=f'{ROOT}/scoreboard.md'; LOG=f'{ROOT}/team.log'
GATE=dict(t_min=3.5, n_min=300, mean_min_per10=0.15, control_abs_max=2.0)
def log(m):
    with open(LOG,'a') as f: f.write(f"{datetime.datetime.utcnow():%Y-%m-%d %H:%M:%S} {m}\n")
def jload(p,d):
    try: return json.load(open(p))
    except Exception: return d
def q(db,sql,timeout='150s'):
    dsn=creds.pg_railway() if db=='railway' else creds.pg_local()
    con=psycopg2.connect(dsn, sslmode='require' if db=='railway' else 'prefer', connect_timeout=20)
    try:
        cur=con.cursor(); cur.execute(f"SET statement_timeout='{timeout}'"); cur.execute(sql); r=cur.fetchall(); con.commit(); return r
    finally: con.close()
# ---- DATA HEALTH: (label, db, rows-in-24h sql, last-ts sql). Zero rows in 24h = BROKEN. Errors = BROKEN with the error.
FEEDS=[
 ('betfair in-play tape liq_sample','railway',"select count(*) from liq_sample where ts>now()-interval '24 hours'","select max(ts) from liq_sample"),
 ('betfair stream_ticks','railway',"select count(*) from stream_ticks where ts_recv>now()-interval '24 hours'","select max(ts_recv) from stream_ticks"),
 ('smarkets xx_tape','railway',"select count(*) from xx_tape where exchange ilike 'smarkets%' and ts>now()-interval '24 hours'","select max(ts) from xx_tape where exchange ilike 'smarkets%'"),
 ('matchbook xx_tape','railway',"select count(*) from xx_tape where exchange ilike 'matchbook%' and ts>now()-interval '24 hours'","select max(ts) from xx_tape where exchange ilike 'matchbook%'"),
 ('goal signal alerts','railway',"select count(*) from goal_alerts where sent_at>now()-interval '24 hours'","select max(sent_at) from goal_alerts"),
 ('BASIC history loader (files)','local',"select count(*) from bf_hist_other_files where loaded_at>now()-interval '24 hours'","select max(loaded_at) from bf_hist_other_files"),
 ('API-Football results (finished fixtures, 48h)','local',"select count(*) from af_fixtures where kickoff>now()-interval '48 hours' and status in ('FT','AET','PEN')","select max(kickoff) from af_fixtures where status in ('FT','AET','PEN')"),
 ('racing BSP (daily files, 3d)','local',"select count(*) from racing_bsp where event_dt>now()-interval '3 days'","select max(event_dt) from racing_bsp"),
 ('coach tape','railway',"select count(*) from coach_tape where tape_date>=current_date-1","select max(tape_date) from coach_tape"),
 ('tape archive (local liq_sample copy)','local',"select count(*) from liq_sample where ts>now()-interval '24 hours'","select max(ts) from liq_sample"),
 ('bookie paper orders','local',"select count(*) from bookie_paper where ts>now()-interval '24 hours'","select max(ts) from bookie_paper"),
]
def data_health():
    out={}
    for label,db,sql_n,sql_last in FEEDS:
        try:
            n=q(db,sql_n)[0][0]; last=q(db,sql_last)[0][0]
            out[label]=dict(status='ok' if n and n>0 else 'BROKEN', rows_24h=int(n or 0), last=str(last)[:16] if last else None, db=db)
        except Exception as e: out[label]=dict(status='BROKEN', rows_24h=0, last=None, db=db, note=re.sub(r'\s+',' ',repr(e))[:120])
    return out
# ---- FIVE LIVE JOBS: one line each, read from the tables (never from memory)
def five_status():
    L={}
    def tryq(db,sql):
        try: return q(db,sql)
        except Exception as e: return [('ERR',re.sub(r'\s+',' ',repr(e))[:100])]
    r=tryq('local',"select tbl,n,n_7d,pnl_total,pnl_7d,per_10,dry from paper_ledger where run_at=(select max(run_at) from paper_ledger) and (tbl ilike '%fade%' or tbl ilike '%goal%') order by tbl")
    L['1 post-goal fade']=f"paper_ledger: {r}" if r else "paper_ledger has no fade rows yet (356 first run pending)"
    r=tryq('railway',"select exchange,count(*),max(ts)::text from xx_tape where ts>now()-interval '7 days' group by 1 order by 1")
    L['2 cross-exchange']=f"xx_tape 7d by exchange: {r} | bookie bot: see 'bookie paper orders' health line and the H2 verdict"
    r=tryq('local',"select count(*) from information_schema.tables where table_name ilike '%fan_bias%'")
    L['3 fan-bias']=f"verdict due Mon 10 Nov; tables present: {r[0][0] if r and r[0][0]!='ERR' else r}"
    r=tryq('local',"select count(*) filter (where status='DONE'), count(*) filter (where status<>'DONE'), sum(loaded) from bf_hist_months")
    r2=tryq('local',"select count(*) from bf_hist_other_files where loaded_at>now()-interval '24 hours'")
    L['4 history loader']=f"months DONE/other: {r} | files loaded 24h: {r2}"
    r=tryq('railway',"select count(*), count(*) filter (where real_price is not null), coalesce(sum(pnl_paper),0) from goal_alerts where sent_at>now()-interval '7 days'")
    L['5 goal signal']=f"alerts 7d (with real price): {r}"
    return L
def money():
    m={'live_month':0.0,'paper_month':0.0,'live_edges':0}
    try: m['live_month']=float(q('railway',"select coalesce(sum(profit),0) from real_trades where placed_at>=date_trunc('month',now())")[0][0])
    except Exception: pass
    try: m['paper_month']=float(q('local',"select coalesce(sum(pnl),0) from bookie_paper where status='settled' and ts>=date_trunc('month',now())")[0][0])
    except Exception: pass
    return m
def critics(h):
    probs=[]
    if not os.path.exists(h['script']): probs.append('script missing')
    else:
        src=open(h['script']).read()
        if 'RESULT' not in src: probs.append('script prints no RESULT line')
        if 'control' not in src.lower(): probs.append('no control in script')
        if 'commission' not in src.lower() and 'COMM' not in src: probs.append('no commission in script')
        if 'tick' not in src.lower(): probs.append('no adverse tick in script')
    if not h.get('pre_registered_sign'): probs.append('no pre-registered direction')
    if re.search(r'\b(S\d{1,2}|LTD|Caan|STL|UTT|playbook|vendor)\b',h['id']): probs.append('named strategy — banned until the bookie bot is live')
    return probs
def build(h):
    try:
        p=subprocess.run(['python3','-I',h['script']]+h.get('args',[]),cwd=ROOT,capture_output=True,text=True,timeout=h.get('timeout',7200))
        res=[json.loads(l[7:]) for l in p.stdout.splitlines() if l.startswith('RESULT ')]
        return res,(p.stdout[-4000:]+p.stderr[-1500:])
    except Exception as e: return [],repr(e)
def verify(h,res):
    out=[]
    for r in res:
        n=r.get('n',0); t=r.get('t',0); mean=r.get('mean_per10',0)
        ok=(t>=GATE['t_min'] and r.get('is_mean',0)>0 and r.get('oos_mean',0)>0 and n>=GATE['n_min'] and mean>=GATE['mean_min_per10'] and abs(r.get('control_t',0))<=GATE['control_abs_max'])
        small=(not ok) and n>=100 and t>=2.0 and r.get('oos_mean',0)>0 and mean>0
        out.append(dict(name=r.get('name',h['id']),n=n,mean_per10=mean,t=t,is_t=r.get('is_t'),oos_t=r.get('oos_t'),control_t=r.get('control_t'),
                        verdict='WORKS' if ok else ('WORKS AT £2' if small else 'NOT YET'),next_door=h.get('next_door'),checked=datetime.date.today().isoformat()))
    return out
def write_scoreboard(sb):
    json.dump(sb,open(SB+'.tmp','w'),indent=1); os.replace(SB+'.tmp',SB)
    L=[f"# SPORTS SCOREBOARD (Verifier-only) — {sb['updated']} UTC","",f"Money: live £{sb['money']['live_month']:.2f} | paper £{sb['money']['paper_month']:.2f} | live edges {sb['money']['live_edges']}","","## Data health (24h)"]
    broken=[k for k,v in sb['data_health'].items() if v['status']=='BROKEN']
    L.append(f"BROKEN: {', '.join(broken) if broken else 'none'}")
    for k,v in sb['data_health'].items(): L.append(f"- {k}: {v['status']} | rows24h {v['rows_24h']} | last {v['last']} {v.get('note','')}")
    L+=["","## The five"]+[f"- {k}: {v}" for k,v in sb['five'].items()]
    L+=["","## Verdicts (gate: t>=3.5, both halves >0, n>=300, mean>=+£0.15/£10, real prints, one tick adverse, 2% commission, |control t|<=2)","","| line | n | £/£10 | t | IS t | OOS t | control t | verdict | next door |","|---|---|---|---|---|---|---|---|---|"]
    for v in sorted(sb['verdicts'],key=lambda v:-(v.get('t') or 0))[:40]: L.append(f"| {v['name']} | {v.get('n')} | {v.get('mean_per10')} | {v.get('t')} | {v.get('is_t')} | {v.get('oos_t')} | {v.get('control_t')} | **{v['verdict']}** | {v.get('next_door') or ''} |")
    L+=["","## Queue"]+[f"- {h['id']}: {h['status']} {h.get('note','')}" for h in sb['queue']]
    open(SBMD+'.tmp','w').write("\n".join(L)); os.replace(SBMD+'.tmp',SBMD)
    try:
        con=psycopg2.connect(creds.pg_railway(),sslmode='require',connect_timeout=20); cur=con.cursor()
        cur.execute("delete from job_results where job='SPORTS_SCOREBOARD'"); cur.execute("insert into job_results(job,started,finished,status,log) values ('SPORTS_SCOREBOARD',now(),now(),'ok',%s)",("\n".join(L)[:60000],)); con.commit(); con.close()
    except Exception as e: log(f"mirror failed {e!r}"[:200])
def start_bookie_if_ready():
    """H2 is a daemon, not a one-shot: start it once the fair-price table exists; keepalive cron keeps it up."""
    try:
        n=q('local',"select count(*) from fair_price_calib")[0][0]
        if n and subprocess.run(['pgrep','-f','bookie_paper.py'],capture_output=True).returncode!=0:
            open('/root/pe-sports/bookie/.ready','w').write('1'); subprocess.Popen(['nohup','/root/pe-sports/bookie/run_bookie.sh'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); log("bookie paper bot started")
    except Exception: pass
def cycle():
    reg=jload(REG,{'hypotheses':[]}); sb=jload(SB,{'money':{},'verdicts':[],'queue':[]})
    sb['data_health']=data_health(); broken=[k for k,v in sb['data_health'].items() if v['status']=='BROKEN']
    if broken: log(f"DATA BROKEN: {broken}")
    sb['five']=five_status(); sb['money']=money(); start_bookie_if_ready()
    ran=0
    for h in reg['hypotheses']:
        if h.get('status')!='proposed' or ran>=1: continue
        if h.get('not_before') and h['not_before']>datetime.datetime.utcnow().isoformat(): continue
        probs=critics(h)
        if probs: h['status']='rejected_by_critics'; h['note']='; '.join(probs); log(f"{h['id']} rejected: {probs}"); continue
        h['status']='running'; json.dump(reg,open(REG,'w'),indent=1); write_scoreboard({**sb,'queue':[{'id':x['id'],'status':x['status'],'note':x.get('note','')} for x in reg['hypotheses']],'updated':datetime.datetime.utcnow().isoformat()[:16]})
        log(f"building {h['id']}"); res,tail=build(h); h['last_output']=tail[-2500:]
        if not res: h['status']='failed'; h['note']='no RESULT line — see last_output'; log(f"{h['id']} no RESULT: {tail[-300:]}"); continue
        verd=verify(h,res); sb['verdicts']=[v for v in sb['verdicts'] if not str(v['name']).startswith(h['id'].split()[0])]+verd
        h['status']='verified'; h['verdicts']=[v['verdict'] for v in verd]; ran+=1; log(f"{h['id']} -> {[v['verdict'] for v in verd][:10]}")
        if h.get('repeat_hours'): h['status']='proposed'; h['not_before']=(datetime.datetime.utcnow()+datetime.timedelta(hours=h['repeat_hours'])).isoformat()
    json.dump(reg,open(REG,'w'),indent=1)
    sb['queue']=[{'id':h['id'],'status':h['status'],'note':h.get('note','')} for h in reg['hypotheses']]; sb['updated']=datetime.datetime.utcnow().isoformat()[:16]
    write_scoreboard(sb)
if __name__=='__main__':
    once='--once' in sys.argv
    while True:
        try: cycle()
        except Exception: log(traceback.format_exc()[-800:])
        if once: break
        time.sleep(600)
PYFILE
python3 -m py_compile /root/pe-sports/team/sports_team.py || { cp /root/pe-sports/team/sports_team.py.bak_511 /root/pe-sports/team/sports_team.py; echo "compile failed, restored"; exit 1; }
for i in $(seq 1 100); do
  grep -q '"status": "running"' /root/pe-sports/team/hypotheses.json || break
  pgrep -f fairprice_v0.py >/dev/null || break
  sleep 60
done
if pgrep -f fairprice_v0.py >/dev/null; then echo "H1 still running after 100 min; daemon picks up the new feeds at its next restart (keepalive)"; else
  pkill -f 'sports_team.py'; sleep 2; nohup /root/pe-sports/team/run_team.sh & disown; sleep 3; echo "daemon restarted pid $(pgrep -f sports_team.py | head -1)"; fi
tail -5 /root/pe-sports/team/team.log; echo; sed -n 1,25p /root/pe-sports/team/scoreboard.md
