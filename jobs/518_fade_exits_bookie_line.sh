#!/bin/bash
# 518: (1) H0 fade forward paper now tests exits +5/+10/+15 min (the pre-registered next door) and caps the lay price at 6.0 — the
# first run's "all tiers" means were dominated by 10+ lays on tier-3 scorers (liability 100x), not a trade we would place. Re-run today.
# (2) Scoreboard five-line 2 now shows the bookie paper bot itself: orders by status with £, fills maker/taker. Daemon restarted when idle.
set -o pipefail
cd /root/pe-sports/team
cat > fade_forward.py <<'PYFILE'
# H0 POST-GOAL FADE — forward paper on the real ladder (the one named line allowed: Peter's verified result; the question is capacity).
# Entry: lay the scorer (MO runner whose LTP fell 10%+ on reopen) or lay OVER in OU25 at the BEST LAY recorded at +60/+120/+300 s after
# the goal (liq_goal_depth, Railway). Exit: back at the best back nearest +10 min from the archived 1/min tape (local liq_sample), or
# nothing if no sample within 3 min. One tick adverse on entry (lay one tick higher than recorded), 2% commission on wins. Per £10 stake.
# IS/OOS = older half / newer half of goals by time. Control = side chosen at random (back the scorer instead of laying).
# RESULT per market x offset (all tiers) and for tier 1+2 only. Re-runs daily; n grows with every goal the recorder sees.
import sys, math, json, numpy as np, pandas as pd, psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
COMM=0.02; rng=np.random.default_rng(11)
LADDER=[(2,0.01),(3,0.02),(4,0.05),(6,0.1),(10,0.2),(20,0.5),(30,1),(50,2),(100,5),(1000,10)]
def tick_up(p):
    for lim,inc in LADDER:
        if p<lim: return round(p+inc,2)
    return p+10
R=psycopg2.connect(creds.pg_railway(),sslmode='require'); rc=R.cursor(); rc.execute("SET statement_timeout='300s'")
G=pd.read_sql("SELECT market_id, event_name, competition, mkt, sel, goal_ts, offset_s, ts, pre_ltp, ltp, lay_px, lay3_sz, minute FROM liq_goal_depth WHERE offset_s IN (60,120,300) AND lay_px IS NOT NULL",R)
for c in ('pre_ltp','ltp','lay_px','lay3_sz'): G[c]=pd.to_numeric(G[c],errors='coerce')
G['moved']=G.ltp/G.pre_ltp-1
E=G[((G.mkt=='MO')&(G.moved<-0.10))|((G.mkt=='OU25')&(G.sel=='OVER'))].copy()
print("goal-depth entries:",len(E),"markets",E.market_id.nunique(),"goals from",str(E.goal_ts.min())[:10],"to",str(E.goal_ts.max())[:10],flush=True)
L=psycopg2.connect(creds.pg_local()); lc=L.cursor(); lc.execute("SET statement_timeout='900s'")
mids=list(E.market_id.unique())
S=pd.read_sql("SELECT ts, market_id, sel, back_px FROM liq_sample WHERE market_id = ANY(%(m)s) AND back_px IS NOT NULL",L,params={'m':mids}).sort_values('ts')
S['back_px']=pd.to_numeric(S.back_px,errors='coerce'); print("tape rows for those markets (local archive):",len(S),flush=True)
TOP5={'English Premier League','Spanish La Liga','Italian Serie A','German Bundesliga','French Ligue 1','UEFA Champions League'}
EUR={'English Championship','Dutch Eredivisie','Portuguese Primeira Liga','Belgian Pro League','Turkish Super League','Scottish Premiership','Spanish Segunda Division','Italian Serie B','German Bundesliga 2','French Ligue 2','UEFA Europa League'}
E['tier']=E.competition.map(lambda c:'1' if c in TOP5 else '2' if c in EUR else '3')
SK={k:g.reset_index(drop=True) for k,g in S.groupby(['market_id','sel'])}
def exit_px(mid,sel,when):
    g=SK.get((mid,sel))
    if g is None: return None
    i=g.ts.searchsorted(when); cands=[j for j in (i-1,i) if 0<=j<len(g)]
    if not cands: return None
    j=min(cands,key=lambda j:abs((g.ts.iloc[j]-when).total_seconds()))
    return float(g.back_px.iloc[j]) if abs((g.ts.iloc[j]-when).total_seconds())<=180 else None
E0=E.copy(); frames=[]
for hold in (5,10,15):
    E=E0.copy(); E['hold']=hold
    E['exit']=[exit_px(m,s,t+pd.Timedelta(minutes=hold)) for m,s,t in zip(E.market_id,E.sel,E.ts)]
    E=E[E.exit.notna()&(E.lay_px>1.01)&(E.lay_px<=6)].copy(); E['entry']=E.lay_px.map(tick_up)   # lay price capped at 6.0: liability 50x stake beyond that is not a trade we would place
    # lay £10 at entry, back £10 at exit: pnl per £10 = 10*(1 - entry/exit) (profit if the price drifts back up)
    E['pnl']=10*(1-E.entry/E.exit); E['pnl']=np.where(E.pnl>0,E.pnl*(1-COMM),E.pnl)
    E=E.sort_values('goal_ts'); E['oos']=np.arange(len(E))>=len(E)//2; frames.append(E)
E=pd.concat(frames,ignore_index=True)
def tstat(x): x=np.asarray(x,float); return float(x.mean()/(x.std(ddof=1)/math.sqrt(len(x)))) if len(x)>5 and x.std(ddof=1)>0 else 0.0
def emit(name,X):
    if len(X)<30: return
    ctrl=np.where(rng.random(len(X))<0.5,X.pnl.values,-X.pnl.values)
    isx=X.loc[~X.oos,'pnl'].values; oox=X.loc[X.oos,'pnl'].values
    print("RESULT "+json.dumps(dict(name=name,n=int(len(X)),mean_per10=round(float(X.pnl.mean()),3),t=round(tstat(X.pnl.values),2),is_mean=round(float(isx.mean()),3) if len(isx) else 0,is_t=round(tstat(isx),2),oos_mean=round(float(oox.mean()),3) if len(oox) else 0,oos_t=round(tstat(oox),2),control_t=round(tstat(ctrl),2),size3_med=float(X.lay3_sz.median()) if X.lay3_sz.notna().any() else None)),flush=True)
for mkt in ('MO','OU25'):
    for off in (60,120,300):
        for hold in (5,10,15):
            X=E[(E.mkt==mkt)&(E.offset_s==off)&(E.hold==hold)]; emit(f"H0 fade {mkt} lay +{off}s exit +{hold}m (all tiers, lay<=6)",X)
            emit(f"H0 fade {mkt} lay +{off}s exit +{hold}m (tier 1+2, lay<=6)",X[X.tier!='3'])
print("entries priced with a +10 min exit:",len(E),"| OOS half from",str(E.loc[E.oos,'goal_ts'].min())[:10] if E.oos.any() else None)
print("NEXT DOOR (pre-registered): maker entry one tick inside the spread; by minute band.")
PYFILE
cp sports_team.py sports_team.py.bak_518
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
python3 -m py_compile fade_forward.py sports_team.py || { cp sports_team.py.bak_518 sports_team.py; echo "compile failed, restored daemon"; exit 1; }
python3 - <<'PY'
import json; p='/root/pe-sports/team/hypotheses.json'; r=json.load(open(p))
for h in r['hypotheses']:
    if h['id'].startswith('H0 post-goal fade') and h['status']!='running': h['status']='proposed'; h.pop('not_before',None); h['note']='exits 5/10/15, lay<=6 (518)'
json.dump(r,open(p,'w'),indent=1); print([(h['id'][:24],h['status']) for h in r['hypotheses']])
PY
for i in $(seq 1 60); do grep -q '"status": "running"' hypotheses.json || break; sleep 60; done
if ! grep -q '"status": "running"' hypotheses.json; then pkill -f sports_team.py; sleep 2; nohup /root/pe-sports/team/run_team.sh & disown; sleep 2; echo "daemon restarted $(pgrep -f sports_team.py | head -1)"; else echo "build still running after 60 min; keepalive applies the new daemon file later"; fi
tail -3 /root/pe-sports/bookie/bookie.log
