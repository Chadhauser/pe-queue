# 663 — 2026-11-19 07:04 UTC
```
  209 /root/pe-sports/team/sports_team.py
   91 /root/pe-sports/team/friday_email.py
  300 total
-rw-r--r-- 1 root root 25749 Nov 19 08:02 /root/pe-sports/team/hypotheses.json
-rw-r--r-- 1 root root 73480 Nov 19 08:02 /root/pe-sports/team/scoreboard.json
-rw-r--r-- 1 root root 13423 Nov 19 08:02 /root/pe-sports/team/scoreboard.md
== sports_team.py
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
    # 568: history loader PAUSED — search closed 13 Nov, nothing consumes new history until 26 Dec; it also stops itself under 20 GB free
 ('API-Football results (finished fixtures, 48h)','local',"select count(*) from af_fixtures where kickoff>now()-interval '48 hours' and status in ('FT','AET','PEN')","select max(kickoff) from af_fixtures where status in ('FT','AET
 ('racing BSP (daily files, 3d)','local',"select count(*) from racing_bsp where event_dt>now()-interval '3 days'","select max(event_dt) from racing_bsp"),
 ('coach tape','railway',"select count(*) from coach_tape where tape_date>=current_date-1","select max(tape_date) from coach_tape"),
 ('tape archive (local liq_sample copy)','local',"select count(*) from liq_sample where ts>now()-interval '24 hours'","select max(ts) from liq_sample"),
 ('bookie paper orders','local',"select count(*) from bookie_paper where ts>now()-interval '24 hours'","select max(ts) from bookie_paper"),
]
def data_health():
    # 532: the last-timestamp read is index-only and fast; the 24 h count can time out when Railway is slow. A timed-out count is not
    # proof of no rows, so liveness then comes from the last timestamp (within 24 h = ok) and the line says the count was unread.
    out={}
    for label,db,sql_n,sql_last in FEEDS:
        last=None; lerr=None
        try: last=q(db,sql_last,'60s')[0][0]
        except Exception as e: lerr=re.sub(r'\s+',' ',repr(e))[:100]
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
                            note=('count unread (timed out); last ts within 24h' if fresh else 'count unread: '+re.sub(r'\s+',' ',repr(e))[:90]+(f'; last-ts read: {lerr}' if lerr else '')))
    return out
# ---- FIVE LIVE JOBS: one line each, read from the tables (never from memory)
def five_status():
    L={}
    def tryq(db,sql):
        try: return q(db,sql)
        except Exception as e: return [('ERR',re.sub(r'\s+',' ',repr(e))[:100])]
    r=tryq('local',"select tbl,n,n_7d,pnl_total,pnl_7d,per_10,dry from paper_ledger where run_at=(select max(run_at) from paper_ledger) and (tbl ilike '%fade%' or tbl ilike '%goal%') order by tbl")
    L['1 post-goal fade']='see the H0 rows in the verdict table (daily forward paper on the real ladder; m1_alerts real trades: '+str(tryq('railway',"select count(actual_pnl), round(sum(actual_pnl)::numeric,2) from m1_alerts"))+')
    r=tryq('railway',"select exchange,count(*),max(ts)::text from xx_tape where ts>now()-interval '7 days' group by 1 order by 1")
    b=tryq('local',"select coalesce(exchange,'betfair') ex, status, count(*), round(coalesce(sum(pnl),0)::numeric,2) from bookie_paper where version='v2' group by 1,2 order by 1,2")
    b2=tryq('local',"select side, count(*), round(avg(pnl)::numeric,3) from bookie_paper where version='v2' and status='settled' group by 1")
    L['2 cross-exchange / bookie bot']=f"bookie_paper by status (n, £): {b} | fills by kind: {b2} | xx_tape 7d: {[(e,n) for e,n,_ in r] if r and r[0][0]!='ERR' else r}"
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
    try: m['paper_month']=float(q('local',"select coalesce(sum(pnl),0) from bookie_paper where status='settled' and version='v2' and ts>=date_trunc('month',now())")[0][0])
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
        verdict='WORKS' if ok else ('WORKS AT £2' if small else 'NOT YET')
        # sanity critic: a closing price is not wrong by 15 points, and no honest line pays £3/£10 on a 1.3 shot — that is a settlement or join artefact (audit 519)
        if (r.get('is_rate') is not None and r.get('implied') is not None and abs(r['is_rate']-r['implied'])>0.15) or t>15 or mean>3.0: verdict='DATA CHECK (artefact)'
        out.append(dict(name=r.get('name',h['id']),n=n,mean_per10=mean,t=t,is_t=r.get('is_t'),oos_t=r.get('oos_t'),control_t=r.get('control_t'),
                        verdict=verdict,next_door=h.get('next_door'),checked=datetime.date.today().isoformat()))
    return out
def settled_lines():
    """PROOF GATE (Peter, 12 Nov): per rule, settled n/100, £ after commission, each half of the settled run, PASS or n more."""
    rows=[]
    def add(label,sql):
        try:
            pn=[float(x) for (x,) in q('local',sql)]   # pnl per settled bet, oldest first
            n=len(pn); tot=sum(pn); h=n//2; a=sum(pn[:h]); b=sum(pn[h:]); per100=None
            try: stk=float(q('local',sql.replace('select pnl','select sum(stake)').split(' order by')[0])[0][0] or 0)
            except Exception: stk=0
            if stk: per100=tot/stk*100
            gate='PASS' if (n>=100 and tot>0 and a>0 and b>0) else (f'{100-n} more' if n<100 else 'FAIL (a half is negative)')
            rows.append((label,n,tot,per100,a,b,gate))
        except Exception as e: rows.append((label,0,0.0,None,0.0,0.0,'no table'))
    add('bot TAKER — all passed cells',"select pnl from bookie_paper where version='v2' and status='settled' and fill_kind='taker' order by settled_ts")
    try:
        for (mt,side) in q('local',"select distinct mkt, side from bookie_paper where version='v2' and fill_kind='taker' and status='settled'"):
            add(f'  taker cell {mt} {side}',f"select pnl from bookie_paper where version='v2' and status='settled' and fill_kind='taker' and mkt='{mt}' and side='{side}' order by settled_ts")
    except Exception: pass
    add('desk FADE (lay scorer +2m, out +10m)',"select pnl from desk_calls where line='FADE' and status='closed' order by exit_ts")
    add('desk HT11 (1-1 HT, back O2.5)',"select pnl from desk_calls where line='HT11' and status='settled' order by exit_ts")
    add('desk CELL (in-play cells)',"select pnl from desk_calls where line='CELL' and status='settled' order by exit_ts")
    add('H0 fade forward paper (m1_alerts)',"select pnl_paper as pnl from m1_alerts where pnl_paper is not null and sent_at>='2026-10-09' order by sent_at")
    return rows

def caught_24h():
    """What the controls stopped in the last 24 h (empty for a week = the controls are not working; say so)."""
    out=[]; cut=(datetime.datetime.utcnow()-datetime.timedelta(hours=24)).strftime('%Y-%m-%d %H:%M:%S')
    def count(path,needle=None):
        try: return sum(1 for l in open(path) if l[:19]>=cut and (needle is None or needle in l))
        except Exception: return 0
    k=count('/root/pe-guard/railway_guard.log','killed');            out.append(f"Railway reads over 4 min killed: {k}")
    k=count('/root/pe-liq/bf_chunk.log','TOO_MUCH_DATA');            out.append(f"Betfair catalogue overflows absorbed (recorder stayed up): {k}")
    try: v=q('local',"select count(*) from desk_calls where status='void' and ts>now()-interval '24 hours'")[0][0]
    except Exception: v=0
    out.append(f"desk calls voided for no tape at exit: {v}")
    k=count('/root/pe-sports/team/sports_team.log','bookie v2 started by daemon'); out.append(f"bookie v2 relaunched by daemon: {k}")
    try: nq=q('local',"select count(*) from bookie_paper where version='v2' and ts>now()-interval '24 hours'")[0][0]; nc=q('local',"select count(*) from fair_price_passed")[0][0]
    except Exception: nq=nc=None
    out.append(f"bookie v2: passed cells {nc}, quotes 24h {nq} (no cell -> no quote)")
    return out
def write_scoreboard(sb):
    json.dump(sb,open(SB+'.tmp','w'),indent=1); os.replace(SB+'.tmp',SB)
    L=[f"# SPORTS SCOREBOARD (Verifier-only) — {sb['updated']} UTC","",f"Money: live £{sb['money']['live_month']:.2f} | paper £{sb['money']['paper_month']:.2f} | live edges {sb['money']['live_edges']}","","## Data health (24h)
    try:
        L.insert(3,""); L.insert(4,"## PROOF GATE — 100 settled paper bets, profit after commission overall and in each half, in line with the backtest; then Peter says yes"); L.insert(5,"| rule | settled / 100 | £ after commis
        for i,(lab,n,pnl,per100,a,b,gate) in enumerate(settled_lines()): L.insert(7+i,f"| {lab} | {n} / 100 | {pnl:+.2f} | {'n/a' if per100 is None else f'{per100:+.2f}'} | {a:+.2f} | {b:+.2f} | {gate} |")
    except Exception as e: L+=[f"(settled lines failed: {e!r})"]
    broken=[k for k,v in sb['data_health'].items() if v['status']=='BROKEN']
    L.append(f"BROKEN: {', '.join(broken) if broken else 'none'}")
    for k,v in sb['data_health'].items(): L.append(f"- {k}: {v['status']} | rows24h {v['rows_24h']} | last {v['last']} {v.get('note','')}")
    L+=["","## The five"]+[f"- {k}: {v}" for k,v in sb['five'].items()]
    L+=["","## Verdicts (gate: t>=3.5, both halves >0, n>=300, mean>=+£0.15/£10, real prints, one tick adverse, 2% commission, |control t|<=2)","","| line | n | £/£10 | t | IS t | OOS t | control t | verdict | next door |","|-
    arte=[v for v in sb['verdicts'] if str(v['verdict']).startswith('DATA CHECK')]
    if arte: L.append(f"| ({len(arte)} cells held back as DATA CHECK — settlement audit, not shown) | | | | | | | | |")
    for v in sorted([v for v in sb['verdicts'] if not str(v['verdict']).startswith('DATA CHECK')],key=lambda v:-(v.get('t') or 0))[:40]: L.append(f"| {v['name']} | {v.get('n')} | {v.get('mean_per10')} | {v.get('t')} | {v.get('is_t
    L+=["","## Queue"]+[f"- {h['id']}: {h['status']} {h.get('note','')}"+(f" | last output: {h.get('tail','')}" if h['status']=='failed' else '') for h in sb['queue']]
    try: L+=["","## Caught (24h) — what the controls stopped"]+[f"- {c}" for c in caught_24h()]
    except Exception as e: L+=[f"(caught line failed: {e!r})"]
    open(SBMD+'.tmp','w').write("\n".join(L)); os.replace(SBMD+'.tmp',SBMD)
    try:
        con=psycopg2.connect(creds.pg_railway(),sslmode='require',connect_timeout=20); cur=con.cursor()
        cur.execute("delete from job_results where job='SPORTS_SCOREBOARD'"); cur.execute("insert into job_results(job,started,finished,status,log) values ('SPORTS_SCOREBOARD',now(),now(),'ok',%s)",("\n".join(L)[:60000],)); con.co
    except Exception as e: log(f"mirror failed {e!r}"[:200])
def start_bookie_if_ready():
    """H2 is a daemon, not a one-shot: start it once the fair-price table exists; keepalive cron keeps it up."""
    try:
        n=q('local',"select count(*) from fair_price_calib")[0][0]
        if n and subprocess.run(['pgrep','-f','bookie_v2.py'],capture_output=True).returncode!=0:   # 542: v2 only; v1.1 (two-sided) is stopped for good
            subprocess.Popen(['nohup','/root/pe-sports/bookie/run_bookie_v2.sh'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); log("bookie v2 started by daemon")
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
        h['status']='running'; json.dump(reg,open(REG,'w'),indent=1); write_scoreboard({**sb,'queue':[{'id':x['id'],'status':x['status'],'note':x.get('note',''),'tail':''} for x in reg['hypotheses']],'updated':datetime.datetime.ut
        log(f"building {h['id']}"); res,tail=build(h); h['last_output']=tail[-2500:]
        if not res: h['status']='failed'; h['note']='no RESULT line — see last_output'; log(f"{h['id']} no RESULT: {tail[-300:]}"); continue
        verd=verify(h,res); sb['verdicts']=[v for v in sb['verdicts'] if not str(v['name']).startswith(h['id'].split()[0])]+verd
        h['status']='verified'; h['verdicts']=[v['verdict'] for v in verd]; ran+=1; log(f"{h['id']} -> {[v['verdict'] for v in verd][:10]}")
        if h.get('repeat_hours'): h['status']='proposed'; h['not_before']=(datetime.datetime.utcnow()+datetime.timedelta(hours=h['repeat_hours'])).isoformat()
    json.dump(reg,open(REG,'w'),indent=1)
    sb['queue']=[{'id':h['id'],'status':h['status'],'note':h.get('note',''),'tail':re.sub(r'\s+',' ',(h.get('last_output') or ''))[-400:]} for h in reg['hypotheses']]; sb['updated']=datetime.datetime.utcnow().isoformat()[:16]
    write_scoreboard(sb)
if __name__=='__main__':
    once='--once' in sys.argv
    while True:
        try: cycle()
        except Exception: log(traceback.format_exc()[-800:])
        if once: break
        time.sleep(600)
== hypotheses.json (first 80 lines)
{
 "hypotheses": [
  {
   "id": "H0 post-goal fade forward paper (lay scorer / lay Over after reopen, exit +10m)",
   "script": "/root/pe-sports/team/fade_forward.py",
   "status": "proposed",
   "kind": "single",
   "pre_registered_sign": "lay the scorer after the reopen; price drifts back",
   "next_door": "exit +5m / +15m; maker entry one tick inside",
   "timeout": 3000,
   "repeat_hours": 24,
   "last_output": "ean_per10\": -0.897, \"t\": -1.0, \"is_mean\": -0.969, \"is_t\": -1.12, \"oos_mean\": -0.815, \"oos_t\": -0.48, \"control_t\": 1.39, \"size3_med\": 176.14000000000001}\nRESULT {\"name\": \"H0 fade OU25 lay +120s
   "verdicts": [
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET"
   ],
   "note": "un-paused 12 Nov (CEO order 2): the only verified edge",
   "not_before": "2026-11-19T14:26:17.675870"
  },
  {
   "id": "H1 fair price v1 (all sports, all single-line markets, k winners)",
   "script": "/root/pe-sports/team/fairprice_v0.py",
   "status": "failed",
   "kind": "sweep",
   "pre_registered_sign": "trade toward the IS fair price",
   "next_door": "H1b: same map at in-play minute bands; H1c: by country",
   "timeout": 14400,
   "repeat_hours": 12,
   "note": "no RESULT line \u2014 see last_output",
   "last_output": "Traceback (most recent call last):\n  File \"/root/pe-sports/team/fairprice_v0.py\", line 22, in <module>\n    cur.execute(\"SELECT sport, market_type, count(DISTINCT market_id) FROM bf_hist_other GROUP BY 1,2 H
   "verdicts": [
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
    "NOT YET",
== scoreboard.md
# SPORTS SCOREBOARD (Verifier-only) — 2026-11-19T07:02 UTC

Money: live £0.00 | paper £-2.91 | live edges 0

## PROOF GATE — 100 settled paper bets, profit after commission overall and in each half, in line with the backtest; then Peter says yes
| rule | settled / 100 | £ after commission | £ per £100 | first half £ | second half £ | gate |
|---|---|---|---|---|---|---|
| bot TAKER — all passed cells | 82 / 100 | -2.85 | -1.74 | -3.02 | +0.18 | 18 more |
|   taker cell BOTH_TEAMS_TO_SCORE BACK | 4 / 100 | -8.00 | -100.00 | -4.00 | -4.00 | 96 more |
|   taker cell BOTH_TEAMS_TO_SCORE LAY | 6 / 100 | -0.20 | -1.67 | -0.10 | -0.10 | 94 more |
|   taker cell CORRECT_SCORE BACK | 6 / 100 | +4.15 | +34.60 | +10.15 | -6.00 | 94 more |
|   taker cell DRAW_NO_BET BACK | 1 / 100 | -2.00 | -100.00 | +0.00 | -2.00 | 99 more |
|   taker cell FIRST_GOAL_SCORER LAY | 3 / 100 | -7.68 | -128.00 | +1.96 | -9.64 | 97 more |
|   taker cell FIRST_HALF_GOALS_15 BACK | 4 / 100 | -8.00 | -100.00 | -4.00 | -4.00 | 96 more |
|   taker cell FIRST_HALF_GOALS_15 LAY | 3 / 100 | -1.88 | -31.33 | +1.96 | -3.84 | 97 more |
|   taker cell FIRST_HALF_GOALS_25 BACK | 2 / 100 | -4.00 | -100.00 | -2.00 | -2.00 | 98 more |
|   taker cell HALF_TIME LAY | 1 / 100 | +1.96 | +98.00 | +0.00 | +1.96 | 99 more |
|   taker cell HALF_TIME_FULL_TIME BACK | 2 / 100 | +2.02 | +50.45 | -2.00 | +4.02 | 98 more |
|   taker cell MATCH_ODDS BACK | 2 / 100 | -4.00 | -100.00 | -2.00 | -2.00 | 98 more |
|   taker cell MATCH_ODDS LAY | 3 / 100 | -1.60 | -26.67 | +1.96 | -3.56 | 97 more |
|   taker cell OVER_UNDER_25 BACK | 8 / 100 | +4.70 | +29.39 | +3.86 | +0.84 | 92 more |
|   taker cell OVER_UNDER_25 LAY | 7 / 100 | +7.26 | +51.86 | +5.88 | +1.38 | 93 more |
|   taker cell OVER_UNDER_45 LAY | 12 / 100 | +2.08 | +8.67 | -1.16 | +3.24 | 88 more |
|   taker cell WIN LAY | 18 / 100 | +12.34 | +34.28 | +10.00 | +2.34 | 82 more |
| desk FADE (lay scorer +2m, out +10m) | 401 / 100 | -9.12 | -1.14 | -23.03 | +13.91 | FAIL (a half is negative) |
| desk HT11 (1-1 HT, back O2.5) | 6 / 100 | +2.04 | +17.00 | +0.99 | +1.05 | 94 more |
| desk CELL (in-play cells) | 0 / 100 | +0.00 | n/a | +0.00 | +0.00 | 100 more |
| H0 fade forward paper (m1_alerts) | 0 / 100 | +0.00 | n/a | +0.00 | +0.00 | no table |

## Data health (24h)
BROKEN: goal signal alerts, API-Football results (finished fixtures, 48h), coach tape
- betfair in-play tape liq_sample: ok | rows24h 2378128 | last 2026-11-19 07:01 
- betfair stream_ticks: ok | rows24h 6256355 | last 2026-11-19 07:01 
- smarkets xx_tape: ok | rows24h 1174233 | last 2026-11-19 07:01 
- matchbook xx_tape: ok | rows24h 1963350 | last 2026-11-19 07:02 
- goal signal alerts: BROKEN | rows24h 0 | last 2026-11-07 19:04 
- API-Football results (finished fixtures, 48h): BROKEN | rows24h 0 | last 2026-11-08 22:30 
- racing BSP (daily files, 3d): ok | rows24h 302 | last 2026-11-16 20:30 
- coach tape: BROKEN | rows24h 0 | last 2026-11-08 
- tape archive (local liq_sample copy): ok | rows24h 2378128 | last 2026-11-19 07:01 
- bookie paper orders: ok | rows24h 26 | last 2026-11-19 05:29 

## The five
- 1 post-goal fade: see the H0 rows in the verdict table (daily forward paper on the real ladder; m1_alerts real trades: [(30, Decimal('-4.15'))])
- 2 cross-exchange / bookie bot: bookie_paper by status (n, £): [('betfair', 'expired', 9, Decimal('0.00')), ('betfair', 'filled', 1, Decimal('0.00')), ('betfair', 'settled', 89, Decimal('-2.91'))] | fills by kind: [('BACK', 34, 
- 3 fan-bias: verdict due Mon 10 Nov; tables present: 1
- 4 history loader: months DONE/other: [(165, 99, 3665531)] | files loaded 24h: [(373294,)]
- 5 goal signal: alerts 7d (with real price): [(0, 0, Decimal('0'))]

## Verdicts (gate: t>=3.5, both halves >0, n>=300, mean>=+£0.15/£10, real prints, one tick adverse, 2% commission, |control t|<=2)

| line | n | £/£10 | t | IS t | OOS t | control t | verdict | next door |
|---|---|---|---|---|---|---|---|---|
| (2 cells held back as DATA CHECK — settlement audit, not shown) | | | | | | | | |
| H1 OVER_UNDER_45 p0.90-1.00 LAY at close (IS rate 0.917 vs implied 0.927) | 11868 | 0.059 | 2.11 | 0.22 | 2.87 | -1.93 | **WORKS AT £2** | H1b: same map at in-play minute bands; H1c: by country |
| H1 DRAW_NO_BET p0.06-0.10 LAY at close (IS rate 0.053 vs implied 0.081) | 936 | 2.114 | 2.1 | 2.32 | 0.78 | -0.08 | **WORKS AT £2** | H1b: same map at in-play minute bands; H1c: by country |
| H1 FIRST_HALF_GOALS_05 p0.55-0.60 LAY at close (IS rate 0.553 vs implied 0.584) | 1599 | 0.433 | 2.06 | 1.67 | 1.23 | -1.71 | **WORKS AT £2** | H1b: same map at in-play minute bands; H1c: by country |
| H1 OVER_UNDER_45 p0.06-0.10 BACK at close (IS rate 0.086 vs implied 0.081) | 9414 | 0.598 | 1.71 | 0.29 | 2.2 | -1.85 | **NOT YET** | H1b: same map at in-play minute bands; H1c: by country |
| H1 CORRECT_SCORE p0.20-0.25 BACK at close (IS rate 0.268 vs implied 0.224) | 983 | 1.008 | 1.69 | 1.58 | 0.84 | -0.71 | **NOT YET** | H1b: same map at in-play minute bands; H1c: by country |
| H1 DRAW_NO_BET p0.90-1.00 BACK at close (IS rate 0.961 vs implied 0.938) | 1778 | 0.079 | 1.57 | 1.64 | 0.65 | -1.03 | **NOT YET** | H1b: same map at in-play minute bands; H1c: by country |
== sports_team log tail
2026-11-19 04:36:48 DATA BROKEN: ['goal signal alerts', 'API-Football results (finished fixtures, 48h)', 'coach tape']
2026-11-19 04:47:10 DATA BROKEN: ['goal signal alerts', 'API-Football results (finished fixtures, 48h)', 'coach tape']
2026-11-19 04:57:33 DATA BROKEN: ['goal signal alerts', 'API-Football results (finished fixtures, 48h)', 'coach tape']
2026-11-19 05:07:56 DATA BROKEN: ['goal signal alerts', 'API-Football results (finished fixtures, 48h)', 'coach tape']
2026-11-19 05:18:19 DATA BROKEN: ['goal signal alerts', 'API-Football results (finished fixtures, 48h)', 'coach tape']
2026-11-19 05:28:41 DATA BROKEN: ['goal signal alerts', 'API-Football results (finished fixtures, 48h)', 'coach tape']
2026-11-19 05:39:05 DATA BROKEN: ['goal signal alerts', 'API-Football results (finished fixtures, 48h)', 'coach tape']
2026-11-19 05:49:27 DATA BROKEN: ['goal signal alerts', 'API-Football results (finished fixtures, 48h)', 'coach tape']
2026-11-19 05:59:50 DATA BROKEN: ['goal signal alerts', 'API-Football results (finished fixtures, 48h)', 'coach tape']
2026-11-19 06:10:18 DATA BROKEN: ['goal signal alerts', 'API-Football results (finished fixtures, 48h)', 'coach tape']
2026-11-19 06:20:41 DATA BROKEN: ['goal signal alerts', 'API-Football results (finished fixtures, 48h)', 'coach tape']
2026-11-19 06:31:06 DATA BROKEN: ['goal signal alerts', 'API-Football results (finished fixtures, 48h)', 'coach tape']
2026-11-19 06:41:29 DATA BROKEN: ['goal signal alerts', 'API-Football results (finished fixtures, 48h)', 'coach tape']
2026-11-19 06:51:52 DATA BROKEN: ['goal signal alerts', 'API-Football results (finished fixtures, 48h)', 'coach tape']
2026-11-19 07:02:16 DATA BROKEN: ['goal signal alerts', 'API-Football results (finished fixtures, 48h)', 'coach tape']
== friday_email.py head + cron
# 568: Peter's Friday email. Four lines + one line per rule. Plain sentences, no abbreviations. Every figure read from the tables; estimates say so.
import sys,json,datetime,statistics,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/operators'); import creds
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); c=con.cursor(); c.execute("SET statement_timeout='120s'")
RESTORE='2026-11-13 13:52+00'   # goal tables restored (job 557); alerts before this are the old engine's
def q(sql,args=()):
    try: c.execute(sql,args); return c.fetchall()
    except Exception as e: con.rollback(); return []
def one(sql,args=(),d=None):
    r=q(sql,args); return r[0] if r else d
def cols(t): return [r[0] for r in q("select column_name from information_schema.columns where table_name=%s",(t,))]
def touch_size(rows):
    """median £ available at the touch on the rule's own markets around its entries (liq_sample back_sz/lay_sz)."""
    xs=[]
    for mid,ts,side in rows[:60]:
        r=one("select percentile_cont(0.5) within group (order by %s) from liq_sample where market_id=%%s and ts between %%s - interval '90 seconds' and %%s + interval '90 seconds'" % ('lay_sz' if sid
        if r and r[0] is not None: xs.append(float(r[0]))
    return statistics.median(xs) if xs else None

# 572: opening line — expected £ a month by sport, at the largest stake the market supports, against £10,000; then the week's action
def opener():
    cols_bp=cols('bookie_paper'); sp_col=next((k for k in ('sport','event_type','event_type_name') if k in cols_bp),None)
    by={}
    rows=q(f"select coalesce({sp_col},'football') sport, count(*), coalesce(sum(pnl),0), coalesce(sum(stake),0), min(ts), max(ts) from bookie_paper where version='v2' and status='settled' and fill_kin
    for sp,n,pnl,stk,t0,t1 in rows:
        if not n or not stk: continue
        days=max(1.0,((t1-t0).total_seconds()/86400) if t0 and t1 else 1.0); per100=float(pnl)/float(stk)*100
        T=touch_size(q("select market_id, ts, side from bookie_paper where version='v2' and fill_kind='taker' order by ts desc")) or 2.0
        by[sp]=by.get(sp,0)+ (n/days)*T*per100/100*30
    fade=q("select count(*), coalesce(sum(pnl),0), coalesce(sum(stake),0), min(ts), max(ts) from desk_calls where line='FADE' and status='closed'")
    if fade and fade[0][0]:
# Money team: Fridays 06:00 UTC (decisions.md 2026-10-18). Same UTC guard (server is Europe/Berlin). MONEY_TEAM_LIVE gates its
@reboot nohup /root/pe-sports/team/run_team.sh &
*/10 * * * * pgrep -f '[s]ports_team.py' >/dev/null || nohup /root/pe-sports/team/run_team.sh &
#FROZEN-561 */30 * * * * /usr/bin/python3 /root/pe-sports/team/verifier_cells.py >> /root/pe-sports/team/verifier_cells.log 2>&1
#FROZEN-561 40 4 * * * cd /root/pe-sports/team && timeout 7000 /usr/bin/python3 replay_fills.py >> replay_fills.log 2>&1
#FROZEN-561 */30 * * * * /usr/bin/python3 /root/pe-sports/team/verifier_cells_inplay.py >> /root/pe-sports/team/verifier_cells_inplay.log 2>&1
*/2 * * * * /root/pe-sports/team/goal_alert_mail.sh
0 7 * * 5 /root/pe-sports/team/friday_email.sh
20 * * * * /root/pe-sports/team/break_check.sh >> /root/pe-sports/team/break_check.log 2>&1
0 1 * * 0 /root/pe-sports/team/weekly_engine.sh
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
5 * * * * cd /root/pe-sports/team && /usr/bin/python3 real_money_guard.py >> real_money_guard.log 2>&1
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
*/5 * * * * pgrep -f '[s]mall_bites_live.py' >/dev/null || nohup /root/pe-sports/team/run_small_bites_live.sh >/dev/null 2>&1 &   # 626 small bites forward paper
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
*/5 * * * * pgrep -f '[v]3_recorder.py' >/dev/null || nohup /root/pe-sports/team/run_v3_recorder.sh >/dev/null 2>&1 &   # 649 v3 forward paper recorder
10 7 * * * /root/pe-sports/team/run_v3_settle.sh   # 649 v3 forward paper settle
*/5 * * * * pgrep -f '[c]oherence_paper.py' >/dev/null || nohup /root/pe-sports/team/run_coherence_paper.sh >/dev/null 2>&1 &   # 654 coherence forward paper
15 7 * * * /root/pe-sports/team/coherence_report.sh   # 654 coherence paper report
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
*/5 * * * * pgrep -f '[b]ook_recorder.py' >/dev/null || nohup /root/pe-sports/team/run_book_recorder.sh >/dev/null 2>&1 &   # 655 THE recorder
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
# (Peter, 16 Nov 2026). The 17 Nov line is a one-off first run so the Friday 20 Nov list has a day of slack; remove it after.
0 7,8 * * 5     [ "$(date -u +\%H)" = "06" ] && cd /root/operators && DRY_RUN=0 ./run.sh money-team >> runs/cron.log 2>&1
# --- added 5 Nov 2026 (Peter: the money team works through the day; one scoreboard only the Verifier writes) ---
bookie_paper.start_ts: last 7 days (1755, datetime.datetime(2026, 11, 19, 5, 30, tzinfo=datetime.timezone.utc))
clv_paper.ko: last 7 days (0, None)
coherence_paper.start_ts: last 7 days (23, datetime.datetime(2026, 11, 17, 23, 30, tzinfo=datetime.timezone.utc))
cricket_fav_paper.ts: last 7 days (0, None)
cs_dutch_paper.recorded_at: last 7 days (0, None)
cs_late_paper.recorded_at: last 7 days (0, None)
cs_q_paper.recorded_at: last 7 days (0, None)
cs_qgreen_paper.recorded_at: last 7 days (0, None)
cs_trade_paper.recorded_at: last 7 days (0, None)
daily_paper_pnl.rolled_up_at: last 7 days (0, None)
fin_paper_daily.run_ts: last 7 days (4, datetime.datetime(2026, 11, 13, 22, 40, 4, 265565, tzinfo=datetime.timezone.utc))
late_over_paper.goal_ts: last 7 days (6, datetime.datetime(2026, 11, 15, 19, 3, 56, 24767, tzinfo=datetime.timezone.utc))
ltd_inplay_paper.entry_ts: last 7 days (0, None)
paper_ledger.last_ts: last 7 days (0, None)
paper_settlements.fired_at: last 7 days (41, datetime.datetime(2026, 11, 18, 3, 55, 43, 884174, tzinfo=datetime.timezone.utc))
paper_trades.created_at: last 7 days (0, None)
preoff_scalp_paper.ts: last 7 days (0, None)
racing_bsp_paper.settled_at: last 7 days (0, None)
racing_mm_paper.exit_ts: last 7 days (0, None)
racing_swing_paper.exit_ts: last 7 days (0, None)
s6_paper.ts: last 7 days (0, None)
s9_paper.exit_ts: last 7 days (0, None)
small_bites_paper.exit_min: last 7 days (1589, datetime.datetime(2026, 11, 18, 9, 35, 42, 611011, tzinfo=datetime.timezone.utc))
sport_paper_trades.settled_at: last 7 days (0, None)
t2_paper.ts: last 7 days (0, None)
tb_paper_trades.opened_at: last 7 days (0, None)
tennis_dog_paper.ts: last 7 days (0, None)
tennis_lay_paper.recorded_at: last 7 days (0, None)
v3_paper.start_ts: last 7 days (0, None)
xg_paper.goal_ts: last 7 days (0, None)
```
