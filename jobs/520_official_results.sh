#!/bin/bash
# 520: OFFICIAL RESULTS INTO THE HISTORY (from audit 519). The BASIC file's final marketDefinition carries each runner's status
# (WINNER/LOSER) — the loader parsed it and threw it away, and H1 settled by price collapse instead, which is biased (in-play rows often
# end early: goal-collapsed markets kept, the rest dropped -> 97-100% "win rates"). Now: (1) loader_core.py writes bf_hist_result
# (market_id, sel, status, settled_time) for every file it reads; (2) the two finished soccer months are re-read so they get results
# (rows dedupe on the unique index); (3) H1 settles on bf_hist_result only; (4) the Verifier holds any cell with |IS rate - implied|>15
# points, t>15 or >£3/£10 as DATA CHECK instead of WORKS; (5) the bookie bot uses only sane cells and quotes at factor 1.0 otherwise
# (pure spread capture = the baseline). Daemon and bot restarted.
set -o pipefail
F=/root/pe-hist/loader_core.py; cp $F $F.bak_520
python3 - <<'PY'
import re
p='/root/pe-hist/loader_core.py'; s=open(p).read(); orig=s
# table
anchor='CREATE TABLE IF NOT EXISTS bf_hist_other_files'
assert anchor in s, 'files-table anchor missing'
s=s.replace(anchor,"CREATE TABLE IF NOT EXISTS bf_hist_result (sport TEXT, market_id TEXT, event_id TEXT, market_type TEXT, sel TEXT, status TEXT, settled_time TEXT, market_status TEXT, PRIMARY KEY (market_id, sel));\n  "+anchor,1)
# module-level buffer
s=s.replace("def parse(local):","RES_ROWS=[]\ndef parse(local):",1)
# collect after mid=
m=re.search(r"^(\s*)mid=os\.path\.basename\(fp\)\.replace\('\.bz2',''\)\s*$",s,re.M); assert m, 'mid anchor missing'
ind=m.group(1)
s=s[:m.end()]+"\n"+ind+"RES_ROWS.extend((sport,mid,str(md_.get('eventId')),md_.get('marketType'),runners.get(r.get('id'),str(r.get('id'))),r.get('status'),md_.get('settledTime'),md_.get('status')) for r in md_.get('runners',[]) if r.get('status') in ('WINNER','LOSER'))"+s[m.end():]
# flush wherever rows are flushed
flush='psycopg2.extras.execute_values(cur,"INSERT INTO bf_hist_other VALUES %s",rows,page_size=5000)'
assert flush in s
s=s.replace(flush,flush+'; (psycopg2.extras.execute_values(cur,"INSERT INTO bf_hist_result VALUES %s ON CONFLICT DO NOTHING",RES_ROWS,page_size=5000) if RES_ROWS else None); RES_ROWS.clear()')
open(p,'w').write(s); print("loader patched; flush sites:",s.count('bf_hist_result VALUES'))
PY
python3 -m py_compile $F || { cp $F.bak_520 $F; echo "compile failed, restored"; exit 1; }
# re-read the finished soccer months so they carry results (file bookkeeping removed; rows dedupe)
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local()); c.autocommit=True; k=c.cursor()
k.execute("select path from bf_hist_other_files limit 3"); print("sample paths:",k.fetchall())
k.execute("select sport,y,m from bf_hist_months where status='DONE' and sport='Soccer'"); months=k.fetchall(); print("soccer DONE months:",months)
MON={1:'Jan',2:'Feb',3:'Mar',4:'Apr',5:'May',6:'Jun',7:'Jul',8:'Aug',9:'Sep',10:'Oct',11:'Nov',12:'Dec'}
tot=0
for sp,y,m in months:
    k.execute("delete from bf_hist_other_files where path like %s",(f"%/{y}/{MON[m]}/%",)); tot+=k.rowcount
    k.execute("update bf_hist_months set status='PARTIAL' where sport=%s and y=%s and m=%s",(sp,y,m))
print("file records cleared for re-read:",tot)
PY
echo "== restart loader (keepalive relaunches)"; pkill -f "pe-hist/loader.py"; sleep 5; pgrep -af "pe-hist/loader" | head -2
# daemon, verifier, H1, bot
cd /root/pe-sports/team && cp sports_team.py sports_team.py.bak_520 && cp fairprice_v0.py fairprice_v0.py.bak_520
cat > sports_team.py <<'PYFILE'
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
    b=tryq('local',"select status, count(*), round(coalesce(sum(pnl),0)::numeric,2) from bookie_paper group by 1 order by 1")
    b2=tryq('local',"select fill_kind, count(*) from bookie_paper where status in ('filled','settled') group by 1")
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
        verdict='WORKS' if ok else ('WORKS AT £2' if small else 'NOT YET')
        # sanity critic: a closing price is not wrong by 15 points, and no honest line pays £3/£10 on a 1.3 shot — that is a settlement or join artefact (audit 519)
        if (r.get('is_rate') is not None and r.get('implied') is not None and abs(r['is_rate']-r['implied'])>0.15) or t>15 or mean>3.0: verdict='DATA CHECK (artefact)'
        out.append(dict(name=r.get('name',h['id']),n=n,mean_per10=mean,t=t,is_t=r.get('is_t'),oos_t=r.get('oos_t'),control_t=r.get('control_t'),
                        verdict=verdict,next_door=h.get('next_door'),checked=datetime.date.today().isoformat()))
    return out
def write_scoreboard(sb):
    json.dump(sb,open(SB+'.tmp','w'),indent=1); os.replace(SB+'.tmp',SB)
    L=[f"# SPORTS SCOREBOARD (Verifier-only) — {sb['updated']} UTC","",f"Money: live £{sb['money']['live_month']:.2f} | paper £{sb['money']['paper_month']:.2f} | live edges {sb['money']['live_edges']}","","## Data health (24h)"]
    broken=[k for k,v in sb['data_health'].items() if v['status']=='BROKEN']
    L.append(f"BROKEN: {', '.join(broken) if broken else 'none'}")
    for k,v in sb['data_health'].items(): L.append(f"- {k}: {v['status']} | rows24h {v['rows_24h']} | last {v['last']} {v.get('note','')}")
    L+=["","## The five"]+[f"- {k}: {v}" for k,v in sb['five'].items()]
    L+=["","## Verdicts (gate: t>=3.5, both halves >0, n>=300, mean>=+£0.15/£10, real prints, one tick adverse, 2% commission, |control t|<=2)","","| line | n | £/£10 | t | IS t | OOS t | control t | verdict | next door |","|---|---|---|---|---|---|---|---|---|"]
    arte=[v for v in sb['verdicts'] if str(v['verdict']).startswith('DATA CHECK')]
    if arte: L.append(f"| ({len(arte)} cells held back as DATA CHECK — settlement audit, not shown) | | | | | | | | |")
    for v in sorted([v for v in sb['verdicts'] if not str(v['verdict']).startswith('DATA CHECK')],key=lambda v:-(v.get('t') or 0))[:40]: L.append(f"| {v['name']} | {v.get('n')} | {v.get('mean_per10')} | {v.get('t')} | {v.get('is_t')} | {v.get('oos_t')} | {v.get('control_t')} | **{v['verdict']}** | {v.get('next_door') or ''} |")
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
cat > fairprice_v0.py <<'PYFILE'
# H1 FAIR PRICE v0 (pre-registered 5 Nov 2026). THE ONE JOB, step 1: the data tells us the price.
# Data: local bf_hist_other (Betfair BASIC, 1 row per runner per minute, Soccer 2019-2026, 33 market types, 18 countries).
# For every market: the last pre-off LTP per runner (the closing price) and the OFFICIAL result from the file's final market definition
# (bf_hist_result: runner status WINNER/LOSER, written by the loader from job 520). Settlement by price collapse was dropped after
# audit 519 showed the in-play tape often ends early, which kept goal-collapsed markets and dropped the rest (99% "win rates").
# Calibration by (market_type, implied-probability band): IS = older half of the loaded markets by date, OOS = newer half (the loader fills newest-first, so the split moves back as months land; the date range is printed). Fair price per cell =
# 1 / IS win rate (written to fair_price_calib for the bookie bot). Residual test per cell, direction pre-registered as "trade toward
# the IS fair price": back if IS rate > implied (underpriced), lay if IS rate < implied; P&L per £10 at the closing price one tick
# ADVERSE, 2% commission on wins; t over all rows, IS/OOS halves, control = side chosen at random instead of by the fair price.
# One market type at a time end-to-end (memory-safe). Prints RESULT lines for cells with n>=300.
import sys, math, json, datetime, gc, numpy as np, pandas as pd, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-queue/runner'); import creds
COMM=0.02; rng=np.random.default_rng(7)
LADDER=[(2,0.01),(3,0.02),(4,0.05),(6,0.1),(10,0.2),(20,0.5),(30,1),(50,2),(100,5),(1000,10)]
def tick(p):
    for lim,inc in LADDER:
        if p<lim: return inc
    return 10
def vtick(p):
    inc=np.full(len(p),10.0);
    for lim,i in reversed(LADDER): inc=np.where(p<lim,i,inc)
    return inc
def tick_down(p): return np.round(np.maximum(1.01,p-vtick(p-1e-9)),2)
def tick_up(p): return np.round(np.minimum(1000,p+vtick(p)),2)
def tstat(a): a=np.asarray(a,float); return float(a.mean()/(a.std(ddof=1)/math.sqrt(len(a)))) if len(a)>5 and a.std()>0 else 0.0
edges=[0,0.03,0.06,0.10,0.15,0.20,0.25,0.30,0.35,0.40,0.45,0.50,0.55,0.60,0.65,0.70,0.80,0.90,1.0001]
con=psycopg2.connect(creds.pg_local(),sslmode='prefer'); cur=con.cursor(); cur.execute("SET statement_timeout=0; SET work_mem='512MB'")
cur.execute("SELECT market_type, count(DISTINCT market_id) FROM bf_hist_other WHERE sport='Soccer' GROUP BY 1 ORDER BY 2 DESC"); types=cur.fetchall(); print("types:",types,flush=True)
cur.execute("DROP TABLE IF EXISTS fair_price_calib; CREATE TABLE fair_price_calib (market_type TEXT, band INT, band_lo NUMERIC, band_hi NUMERIC, n_is INT, rate_is NUMERIC, p_mean_is NUMERIC, n_oos INT, rate_oos NUMERIC, p_mean_oos NUMERIC, fair_factor NUMERIC, built_at TIMESTAMPTZ DEFAULT now())"); con.commit()
T0=datetime.datetime.now(datetime.UTC); out=0; tot_rows=0; tot_dropped=0
for mt,nmk in types:
    cur.execute("""
    WITH pre AS (SELECT DISTINCT ON (market_id, sel) market_id, sel, market_time, ltp AS close_ltp
                 FROM bf_hist_other WHERE sport='Soccer' AND market_type=%s AND NOT inplay AND ltp>1 AND ltp<1000 ORDER BY market_id, sel, ts DESC),
         res AS (SELECT market_id, sel, (status='WINNER')::int AS won FROM bf_hist_result WHERE market_type=%s AND status IN ('WINNER','LOSER'))
    SELECT pre.market_id, pre.market_time, pre.close_ltp::float8, res.won FROM pre JOIN res USING (market_id, sel)""",(mt,mt))
    df=pd.DataFrame(cur.fetchall(),columns=['market_id','market_time','close_ltp','won']); con.commit()
    if len(df)<1000: print(f"  {mt}: {len(df)} rows with official results — skipped (results arrive as the loader re-reads files)",flush=True); continue
    df['market_id']=df.market_id.astype('category').cat.codes
    nw=df.groupby('market_id',sort=False).won.transform('sum'); clean=(nw==1)   # exactly one official winner per market (no dead heats / voids)
    dropped=int(df.loc[~clean,'market_id'].nunique()); df=df[clean].copy(); tot_dropped+=dropped
    df['won']=df.won.astype(np.int8); df['p_raw']=1/df.close_ltp; df['p']=df.p_raw/df.groupby('market_id',sort=False).p_raw.transform('sum')
    mtime=pd.to_datetime(df.market_time,utc=True); SPLIT=mtime.quantile(0.5); df['band']=pd.cut(df.p,edges,right=False,labels=False).astype(int); df['oos']=mtime>=SPLIT
    print(f"  {mt}: dates {mtime.min():%Y-%m-%d}..{mtime.max():%Y-%m-%d}, IS/OOS split {SPLIT:%Y-%m-%d}",flush=True)
    cal=df.groupby(['band','oos']).agg(n=('won','size'),rate=('won','mean'),p_mean=('p','mean')).reset_index()
    IS=cal[~cal.oos].set_index('band'); OOS=cal[cal.oos].set_index('band')
    rows=[]
    for b,r in IS.iterrows():
        o=OOS.loc[b] if b in OOS.index else None
        rows.append((mt,int(b),edges[b],edges[b+1],int(r.n),float(r.rate),float(r.p_mean),int(o.n) if o is not None else 0,float(o.rate) if o is not None else None,float(o.p_mean) if o is not None else None,float(r.rate/r.p_mean) if r.p_mean>0 else None))
    if rows: psycopg2.extras.execute_values(cur,"INSERT INTO fair_price_calib (market_type,band,band_lo,band_hi,n_is,rate_is,p_mean_is,n_oos,rate_oos,p_mean_oos,fair_factor) VALUES %s",rows); con.commit()
    df=df.merge(IS[['rate','p_mean']].rename(columns={'rate':'fair_rate','p_mean':'p_is'}),left_on='band',right_index=True,how='inner').reset_index(drop=True)
    back=(df.fair_rate>df.p_is).values; cl=df.close_ltp.values; won=df.won.values
    bk=tick_down(cl); ly=tick_up(cl)
    def pnl_of(w): return np.where(back,np.where(w==1,(bk-1)*10*(1-COMM),-10.0),np.where(w==1,-(ly-1)*10,10.0*(1-COMM)))
    df['pnl']=pnl_of(won); df['side']=np.where(back,'BACK','LAY'); oos=df.oos.values
    cells=0
    for b,gdf in df.groupby('band'):
        n=len(gdf)
        if n<300 or gdf.oos.sum()<50 or (~gdf.oos).sum()<50: continue
        idx=gdf.index.values; w=won[idx]; rside=rng.random(len(idx))<0.5   # control: side chosen at random, not by the fair price
        ctrl=np.where(rside,np.where(w==1,(bk[idx]-1)*10*(1-COMM),-10.0),np.where(w==1,-(ly[idx]-1)*10,10.0*(1-COMM)))
        isx=gdf.loc[~gdf.oos,'pnl'].values; oox=gdf.loc[gdf.oos,'pnl'].values
        name=f"H1 {mt} p{edges[b]:.2f}-{edges[b+1]:.2f} {gdf.side.iloc[0]} at close (IS rate {gdf.fair_rate.iloc[0]:.3f} vs implied {gdf.p_is.iloc[0]:.3f})"
        print("RESULT "+json.dumps(dict(name=name,n=int(n),mean_per10=round(float(gdf.pnl.mean()),3),t=round(tstat(gdf.pnl.values),2),is_mean=round(float(isx.mean()),3),is_t=round(tstat(isx),2),oos_mean=round(float(oox.mean()),3),oos_t=round(tstat(oox),2),control_t=round(tstat(ctrl),2),n_oos=int(gdf.oos.sum()),is_rate=round(float(gdf.fair_rate.iloc[0]),4),implied=round(float(gdf.p_is.iloc[0]),4))),flush=True); cells+=1; out+=1
    tot_rows+=len(df)
    print(f"  {mt}: {len(df)} runner-rows, {df.market_id.nunique()} clean markets, dropped {dropped}, cells {cells}, {(datetime.datetime.now(datetime.UTC)-T0).seconds}s",flush=True)
    del df,g,cal; gc.collect()
print(f"cells reported {out} | runner-rows {tot_rows} | markets dropped (no single official winner) {tot_dropped}")
print("NEXT DOOR (pre-registered): same map at in-play minute bands 0-15/15-30/30-45/HT/45-60/60-75/75+ (H1b), then by country (H1c).")
PYFILE
cat > /root/pe-sports/bookie/bookie_paper.py <<'PYFILE'
# BOOKIE PAPER BOT (THE ONE JOB, step 2 — Peter, 5 Nov 2026: "we are the bookie"). Rests paper orders at OUR fair price on the live
# Betfair football tape (Railway liq_sample, 22 market types since 08:17 UTC 5 Nov), both sides of every runner, £2 nominal.
# Fair price: normalised implied probability x fair_factor(market_type, band) from fair_price_calib (local, built by H1; only sane cells), else 1.0.
# Quote: BACK order one tick ABOVE fair (we want better than fair), LAY order one tick BELOW fair. Order lives 10 minutes.
# Fill (one tick adverse, resting-order realism): BACK at P fills when a later sample shows back_px >= tick_up(P) (layers came to us);
# LAY at L fills when lay_px <= tick_down(L). If the market already offers better than our price at quote time, we take it at the market
# price (that is a value bet by the same fair price) and mark it 'taker'.
# Settlement: after the market's start + 2h, the last in-play LTP: winner <=1.10, others >=5.0 (clean collapse) -> pnl at 2% commission.
# Writes local table bookie_paper. The Verifier (sports_team.py) reads it: fills, adverse rate, £ per £100 quoted, net £ this month.
import sys, time, datetime, traceback, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-queue/runner'); import creds
STAKE=2.0; COMM=0.02; TTL=600; MINS_SETTLE=120
SHORT={'MO':'MATCH_ODDS','OU05':'OVER_UNDER_05','OU15':'OVER_UNDER_15','OU25':'OVER_UNDER_25','OU35':'OVER_UNDER_35','OU45':'OVER_UNDER_45','OU55':'OVER_UNDER_55',
 'BTTS':'BOTH_TEAMS_TO_SCORE','CS':'CORRECT_SCORE','AH':'ASIAN_HANDICAP','DNB':'DRAW_NO_BET','HT_MO':'HALF_TIME','HT_CS':'HALF_TIME_SCORE','HTFT':'HALF_TIME_FULL_TIME',
 'FH05':'FIRST_HALF_GOALS_05','FH15':'FIRST_HALF_GOALS_15','FH25':'FIRST_HALF_GOALS_25','SH05':'SECOND_HALF_GOALS_05','SH15':'SECOND_HALF_GOALS_15','NG':'NEXT_GOAL',
 'HOU05':'TEAM_A_OVER_UNDER_05','HOU15':'TEAM_A_OVER_UNDER_15','AOU05':'TEAM_B_OVER_UNDER_05','AOU15':'TEAM_B_OVER_UNDER_15','TG':'TOTAL_GOALS','DC':'DOUBLE_CHANCE',
 'CSHEET':'CLEAN_SHEET','WM':'WINNING_MARGIN','HWTN':'TEAM_A_WIN_TO_NIL','AWTN':'TEAM_B_WIN_TO_NIL','MOBTTS':'MATCH_ODDS_AND_BTTS','MOOU25':'MATCH_ODDS_AND_OU_25'}
LADDER=[(2,0.01),(3,0.02),(4,0.05),(6,0.1),(10,0.2),(20,0.5),(30,1),(50,2),(100,5),(1000,10)]
def tick(p):
    for lim,inc in LADDER:
        if p<lim: return inc
    return 10
def tick_down(p): return round(max(1.01,p-tick(p-1e-9)),2)
def tick_up(p): return round(min(1000,p+tick(p)),2)
def snap(p):  # to the ladder
    inc=tick(p); return round(round(p/inc)*inc,2)
def log(m):
    with open('/root/pe-sports/bookie/bookie.log','a') as f: f.write(f"{datetime.datetime.utcnow():%Y-%m-%d %H:%M:%S} {m}\n")
L=psycopg2.connect(creds.pg_local(),sslmode='prefer'); L.autocommit=True; lc=L.cursor()
lc.execute("""CREATE TABLE IF NOT EXISTS bookie_paper (id BIGSERIAL PRIMARY KEY, ts TIMESTAMPTZ, market_id TEXT, event_name TEXT, mkt TEXT, sel TEXT, side TEXT,
  price NUMERIC, fair NUMERIC, mkt_back NUMERIC, mkt_lay NUMERIC, stake NUMERIC, status TEXT, fill_ts TIMESTAMPTZ, fill_price NUMERIC, fill_kind TEXT,
  won INT, pnl NUMERIC, settled_ts TIMESTAMPTZ, start_ts TIMESTAMPTZ);
  CREATE INDEX IF NOT EXISTS bookie_paper_ts ON bookie_paper (ts); CREATE INDEX IF NOT EXISTS bookie_paper_mkt ON bookie_paper (market_id, status);
  CREATE TABLE IF NOT EXISTS bookie_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, open_orders INT, fills INT)""")
def calib():
    # only cells whose IS win rate sits within 8 points of the implied probability are used (a 30-point gap is a settlement artefact,
    # audit 519); every market type the recorder carries falls back to factor 1.0 = quote both sides inside the spread at the
    # normalised market price, which is the pure bookie baseline the Verifier measures first
    C={mt:[] for mt in SHORT.values()}
    try:
        lc.execute("select market_type, band_lo, band_hi, fair_factor, n_is from fair_price_calib where n_is>=300 and fair_factor is not null and abs(rate_is-p_mean_is)<=0.08")
        for mt,lo,hi,f,n in lc.fetchall(): C.setdefault(mt,[]).append((float(lo),float(hi),float(f)))
    except Exception as e: log(f"calib read failed {e!r}"[:160])
    return C
def factor(C,mt,p):
    for lo,hi,f in C.get(mt,[]):
        if lo<=p<hi: return f
    return 1.0
def rconn(): return psycopg2.connect(creds.pg_railway(),sslmode='require',connect_timeout=20)
last_cal=0; C={}; R=None
while True:
    try:
        if time.time()-last_cal>3600: C=calib(); last_cal=time.time(); log(f"calibration cells {sum(len(v) for v in C.values())} types {len(C)}")
        if R is None or R.closed: R=rconn()
        rc=R.cursor(); rc.execute("SET statement_timeout='40s'")
        # latest snapshot per market (all runners at the market's latest ts), last 90 s
        rc.execute("""WITH last AS (SELECT market_id, max(ts) ts FROM liq_sample WHERE ts>now()-interval '90 seconds' GROUP BY 1)
                      SELECT s.market_id, s.ts, s.event_name, s.mkt, s.sel, s.ltp, s.back_px, s.lay_px, s.minute FROM liq_sample s JOIN last USING (market_id, ts)""")
        rows=rc.fetchall(); R.commit()
        by={}
        for mid,ts,ev,mkt,sel,ltp,bp,lp,minute in rows: by.setdefault(mid,[]).append((ts,ev,mkt,sel,float(ltp or 0),float(bp or 0),float(lp or 0),minute))
        # open orders: fills
        lc.execute("select id, market_id, sel, side, price from bookie_paper where status='open'"); opens=lc.fetchall()
        filled=0
        for oid,mid,sel,side,price in opens:
            for ts,ev,mkt,s,ltp,bp,lp,minute in by.get(mid,[]):
                if s!=sel: continue
                price=float(price)
                if side=='BACK' and bp>=tick_up(price): lc.execute("update bookie_paper set status='filled', fill_ts=%s, fill_price=%s, fill_kind='maker' where id=%s",(ts,price,oid)); filled+=1
                if side=='LAY' and lp>0 and lp<=tick_down(price): lc.execute("update bookie_paper set status='filled', fill_ts=%s, fill_price=%s, fill_kind='maker' where id=%s",(ts,price,oid)); filled+=1
        lc.execute("update bookie_paper set status='expired' where status='open' and ts<now()-interval '%s seconds'"%TTL)
        # new quotes: one open order per (market, sel, side); skip markets that already have an open or filled order on that runner this minute
        lc.execute("select market_id, sel, side from bookie_paper where status='open'"); have={(a,b,c) for a,b,c in lc.fetchall()}
        quoted=0
        for mid,rs in by.items():
            mkt=rs[0][2]; mt=SHORT.get(mkt)
            if not mt or mt not in C: continue
            tot=sum(1/r[4] for r in rs if r[4]>1)
            if tot<=0 or len(rs)<2: continue
            for ts,ev,_,sel,ltp,bp,lp,minute in rs:
                if ltp<=1 or bp<=1 or lp<=1 or lp<bp: continue
                p=(1/ltp)/tot; f=factor(C,mt,p)
                if f is None: continue
                pf=min(0.99,max(0.005,p*f)); fair=1/pf
                qb=snap(tick_up(fair)); ql=snap(tick_down(fair))
                if (mid,sel,'BACK') not in have:
                    if bp>=qb: lc.execute("insert into bookie_paper (ts,market_id,event_name,mkt,sel,side,price,fair,mkt_back,mkt_lay,stake,status,fill_ts,fill_price,fill_kind) values (%s,%s,%s,%s,%s,'BACK',%s,%s,%s,%s,%s,'filled',%s,%s,'taker')",(ts,mid,ev,mkt,sel,bp,fair,bp,lp,STAKE,ts,bp))
                    else: lc.execute("insert into bookie_paper (ts,market_id,event_name,mkt,sel,side,price,fair,mkt_back,mkt_lay,stake,status) values (%s,%s,%s,%s,%s,'BACK',%s,%s,%s,%s,%s,'open')",(ts,mid,ev,mkt,sel,qb,fair,bp,lp,STAKE))
                    quoted+=1
                if (mid,sel,'LAY') not in have:
                    if lp<=ql: lc.execute("insert into bookie_paper (ts,market_id,event_name,mkt,sel,side,price,fair,mkt_back,mkt_lay,stake,status,fill_ts,fill_price,fill_kind) values (%s,%s,%s,%s,%s,'LAY',%s,%s,%s,%s,%s,'filled',%s,%s,'taker')",(ts,mid,ev,mkt,sel,lp,fair,bp,lp,STAKE,ts,lp))
                    else: lc.execute("insert into bookie_paper (ts,market_id,event_name,mkt,sel,side,price,fair,mkt_back,mkt_lay,stake,status) values (%s,%s,%s,%s,%s,'LAY',%s,%s,%s,%s,%s,'open')",(ts,mid,ev,mkt,sel,ql,fair,bp,lp,STAKE))
                    quoted+=1
        # settlement: filled orders on markets whose first quote is >2h old and that have left the live tape
        lc.execute("select distinct market_id from bookie_paper where status='filled' and ts<now()-interval '%s minutes'"%MINS_SETTLE); due=[m for (m,) in lc.fetchall() if m not in by]
        settled=0
        for mid in due[:40]:
            rc.execute("select distinct on (sel) sel, ltp from liq_sample where market_id=%s and ts>now()-interval '12 hours' order by sel, ts desc",(mid,)); fin=rc.fetchall(); R.commit()
            if not fin: continue
            fin=[(s,float(l or 0)) for s,l in fin]; winners=[s for s,l in fin if 0<l<=1.10]; mids=[s for s,l in fin if 1.10<l<5]
            if len(winners)!=1 or mids:
                lc.execute("update bookie_paper set status='unsettleable', settled_ts=now() where market_id=%s and status='filled' and ts<now()-interval '10 hours'",(mid,)); continue
            w=winners[0]
            lc.execute("select id, sel, side, fill_price, stake from bookie_paper where market_id=%s and status='filled'",(mid,))
            for oid,sel,side,fp,stk in lc.fetchall():
                fp=float(fp); stk=float(stk); won=1 if sel==w else 0
                pnl=((fp-1)*stk*(1-COMM) if won else -stk) if side=='BACK' else (-(fp-1)*stk if won else stk*(1-COMM))
                lc.execute("update bookie_paper set status='settled', won=%s, pnl=%s, settled_ts=now() where id=%s",(won,round(pnl,4),oid)); settled+=1
        lc.execute("select count(*) filter (where status='open'), count(*) filter (where status in ('filled','settled')) from bookie_paper"); o,f=lc.fetchone()
        lc.execute("insert into bookie_heartbeat values (1,now(),%s,%s) on conflict (id) do update set last_seen=now(), open_orders=excluded.open_orders, fills=excluded.fills",(o,f))
        if quoted or filled or settled: log(f"markets {len(by)} quoted {quoted} filled {filled} settled {settled} open {o}")
    except Exception:
        log(traceback.format_exc()[-600:]);
        try: R.close()
        except Exception: pass
        R=None; time.sleep(20)
    time.sleep(20)
PYFILE
python3 -m py_compile sports_team.py fairprice_v0.py /root/pe-sports/bookie/bookie_paper.py || exit 1
python3 - <<'PY'
import json; p='/root/pe-sports/team/hypotheses.json'; r=json.load(open(p))
for h in r['hypotheses']:
    if h['id'].startswith('H1 fair price v0'): h['status']='proposed'; h['repeat_hours']=12; h.pop('not_before',None); h['note']='official-result settlement (520); re-fits every 12h as results land'
json.dump(r,open(p,'w'),indent=1)
# existing artefact verdicts are withdrawn from the scoreboard
sb=json.load(open('/root/pe-sports/team/scoreboard.json')); sb['verdicts']=[v for v in sb['verdicts'] if not str(v['name']).startswith('H1 ')]; json.dump(sb,open('/root/pe-sports/team/scoreboard.json','w'),indent=1)
print("H1 re-queued; artefact verdicts withdrawn")
PY
pkill -f sports_team.py; pkill -f bookie_paper.py; sleep 2; nohup /root/pe-sports/team/run_team.sh & disown; sleep 3
pgrep -f sports_team.py >/dev/null && echo "daemon up" || echo "DAEMON DOWN"; pgrep -f bookie_paper.py >/dev/null && echo "bookie up (keepalive loop)" || echo "bookie restarting via keepalive"
