#!/bin/bash
# 510: SPORTS TEAM — continuous background agent on this server (Peter, 5 Nov 08:19: "Fair price first, then the resting-order bot, no
# named strategies until it is live. Make the test loop a continuous background agent on this server with one scoreboard file only the
# Verifier writes, and a data health line every morning"). Proposer = hypotheses.json (H1 fair price v0 -> H1b in-play bands -> H1c by
# country; H2 = the bookie paper bot, a daemon the team starts once fair_price_calib exists). Critics reject anything without a control,
# commission, adverse tick, or that names a strategy. Verifier is the ONLY writer of /root/pe-sports/team/scoreboard.{json,md} and mirrors
# it to Railway job_results as SPORTS_SCOREBOARD. Data health over BOTH databases every 10-minute cycle. nohup + @reboot + keepalive cron.
set -o pipefail
mkdir -p /root/pe-sports/team /root/pe-sports/bookie && cd /root/pe-sports/team
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
def q(db,sql,timeout='60s'):
    dsn=creds.pg_railway() if db=='railway' else creds.pg_local()
    con=psycopg2.connect(dsn, sslmode='require' if db=='railway' else 'prefer', connect_timeout=20)
    try:
        cur=con.cursor(); cur.execute(f"SET statement_timeout='{timeout}'"); cur.execute(sql); r=cur.fetchall(); con.commit(); return r
    finally: con.close()
# ---- DATA HEALTH: (label, db, rows-in-24h sql, last-ts sql). Zero rows in 24h = BROKEN. Errors = BROKEN with the error.
FEEDS=[
 ('betfair in-play tape liq_sample','railway',"select count(*) from liq_sample where ts>now()-interval '24 hours'","select max(ts) from liq_sample"),
 ('betfair stream_ticks','railway',"select count(*) from stream_ticks where ts>now()-interval '24 hours'","select max(ts) from stream_ticks"),
 ('smarkets xx_tape','railway',"select count(*) from xx_tape where exchange ilike 'smarkets%' and ts>now()-interval '24 hours'","select max(ts) from xx_tape where exchange ilike 'smarkets%'"),
 ('matchbook xx_tape','railway',"select count(*) from xx_tape where exchange ilike 'matchbook%' and ts>now()-interval '24 hours'","select max(ts) from xx_tape where exchange ilike 'matchbook%'"),
 ('goal signal alerts','railway',"select count(*) from goal_alerts where sent_at>now()-interval '24 hours'","select max(sent_at) from goal_alerts"),
 ('BASIC history loader (files)','local',"select count(*) from bf_hist_other_files where loaded_at>now()-interval '24 hours'","select max(loaded_at) from bf_hist_other_files"),
 ('API-Football fixtures','local',"select count(*) from af_fixtures where kickoff>now()-interval '24 hours' and status in ('FT','AET','PEN')","select max(kickoff) from af_fixtures where status in ('FT','AET','PEN')"),
 ('racing BSP','local',"select count(*) from racing_bsp where event_dt>now()-interval '48 hours'","select max(event_dt) from racing_bsp"),
 ('coach tape','local',"select count(*) from coach_tape where tape_date>=current_date-1","select max(tape_date) from coach_tape"),
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
cat > fairprice_v0.py <<'PYFILE'
# H1 FAIR PRICE v0 (pre-registered 5 Nov 2026). THE ONE JOB, step 1: the data tells us the price.
# Data: local bf_hist_other (Betfair BASIC, 1 row per runner per minute, Soccer 2019-2026, 33 market types, 18 countries).
# For every market: the last pre-off LTP per runner (the closing price) and the last in-play LTP (settlement: the winner collapses
# to <=1.10 while every other runner is >=5.0; markets without a clean collapse are dropped and counted).
# Calibration by (market_type, implied-probability band): IS = market_time < 2024-01-01, OOS = 2024-01-01 on. Fair price per cell =
# 1 / IS win rate (written to fair_price_calib for the bookie bot). Residual test per cell, direction pre-registered as "trade toward
# the IS fair price": back if IS rate > implied (underpriced), lay if IS rate < implied; P&L per £10 at the closing price one tick
# ADVERSE, 2% commission on wins; t over all rows, IS/OOS halves, control = outcomes shuffled within the cell.
# Prints RESULT lines (name,n,mean_per10,t,is_mean,is_t,oos_mean,oos_t,control_t) for cells with n>=300.
import sys, math, json, datetime, numpy as np, pandas as pd, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-queue/runner'); import creds
COMM=0.02; rng=np.random.default_rng(7)
LADDER=[(2,0.01),(3,0.02),(4,0.05),(6,0.1),(10,0.2),(20,0.5),(30,1),(50,2),(100,5),(1000,10)]
def tick(p):
    for lim,inc in LADDER:
        if p<lim: return inc
    return 10
def tick_down(p): return round(max(1.01,p-tick(p-1e-9)),2)
def tick_up(p): return round(min(1000,p+tick(p)),2)
con=psycopg2.connect(creds.pg_local(),sslmode='prefer'); cur=con.cursor(); cur.execute("SET statement_timeout=0; SET work_mem='1GB'")
print("pulling closing and settlement prices, one market type at a time...",flush=True); t0=datetime.datetime.utcnow()
cur.execute("SELECT market_type, count(DISTINCT market_id) FROM bf_hist_other WHERE sport='Soccer' GROUP BY 1 ORDER BY 2 DESC"); types=cur.fetchall(); print("types:",types,flush=True)
parts=[]
for mt,_ in types:
    cur.execute("""
    WITH pre AS (SELECT DISTINCT ON (market_id, sel) market_id, sel, market_type, market_time, country, ltp AS close_ltp
                 FROM bf_hist_other WHERE sport='Soccer' AND market_type=%s AND NOT inplay AND ltp>1 AND ltp<1000 ORDER BY market_id, sel, ts DESC),
         fin AS (SELECT DISTINCT ON (market_id, sel) market_id, sel, ltp AS last_ltp
                 FROM bf_hist_other WHERE sport='Soccer' AND market_type=%s AND inplay AND ltp>1 ORDER BY market_id, sel, ts DESC)
    SELECT pre.market_id, pre.sel, pre.market_type, pre.market_time, pre.country, pre.close_ltp, fin.last_ltp
    FROM pre JOIN fin USING (market_id, sel)""",(mt,mt))
    d=pd.DataFrame(cur.fetchall(),columns=['market_id','sel','market_type','market_time','country','close_ltp','last_ltp']); parts.append(d)
    print(f"  {mt}: {len(d)} rows, {d.market_id.nunique()} markets, {(datetime.datetime.utcnow()-t0).seconds}s",flush=True)
df=pd.concat(parts,ignore_index=True); del parts
print(f"rows {len(df)} markets {df.market_id.nunique()}",flush=True)
df['close_ltp']=df.close_ltp.astype(float); df['last_ltp']=df.last_ltp.astype(float)
# settlement by collapse
g=df.groupby('market_id'); mn=g.last_ltp.transform('min'); n_le=g.last_ltp.transform(lambda s:(s<=1.10).sum()); n_mid=g.last_ltp.transform(lambda s:((s>1.10)&(s<5)).sum())
clean=(mn<=1.10)&(n_le==1)&(n_mid==0); dropped=df.loc[~clean,'market_id'].nunique(); df=df[clean].copy()
df['won']=(df.last_ltp<=1.10).astype(int)
print(f"clean-settled markets {df.market_id.nunique()} | dropped (no clean collapse) {dropped}",flush=True)
# implied probabilities, normalised per market
df['p_raw']=1/df.close_ltp; df['p']=df.p_raw/df.groupby('market_id').p_raw.transform('sum')
edges=[0,0.03,0.06,0.10,0.15,0.20,0.25,0.30,0.35,0.40,0.45,0.50,0.55,0.60,0.65,0.70,0.80,0.90,1.0001]
df['band']=pd.cut(df.p,edges,right=False,labels=False); df['oos']=pd.to_datetime(df.market_time,utc=True)>=pd.Timestamp('2024-01-01',tz='UTC')
cal=df.groupby(['market_type','band','oos']).agg(n=('won','size'),rate=('won','mean'),p_mean=('p','mean'),px_mean=('close_ltp','mean')).reset_index()
IS=cal[~cal.oos].set_index(['market_type','band']); OOS=cal[cal.oos].set_index(['market_type','band'])
# write the calibration table (IS fit; OOS alongside for the record)
cur.execute("DROP TABLE IF EXISTS fair_price_calib; CREATE TABLE fair_price_calib (market_type TEXT, band INT, band_lo NUMERIC, band_hi NUMERIC, n_is INT, rate_is NUMERIC, p_mean_is NUMERIC, n_oos INT, rate_oos NUMERIC, p_mean_oos NUMERIC, fair_factor NUMERIC, built_at TIMESTAMPTZ DEFAULT now())")
rows=[]
for (mt,b),r in IS.iterrows():
    o=OOS.loc[(mt,b)] if (mt,b) in OOS.index else None
    rows.append((mt,int(b),edges[int(b)],edges[int(b)+1],int(r.n),float(r.rate),float(r.p_mean),int(o.n) if o is not None else 0,float(o.rate) if o is not None else None,float(o.p_mean) if o is not None else None,float(r.rate/r.p_mean) if r.p_mean>0 else None))
psycopg2.extras.execute_values(cur,"INSERT INTO fair_price_calib (market_type,band,band_lo,band_hi,n_is,rate_is,p_mean_is,n_oos,rate_oos,p_mean_oos,fair_factor) VALUES %s",rows); con.commit()
print(f"fair_price_calib written: {len(rows)} cells",flush=True)
# residual test per cell, direction fixed by the IS fair price
def tstat(a): a=np.asarray(a,float); return float(a.mean()/(a.std(ddof=1)/math.sqrt(len(a)))) if len(a)>5 and a.std()>0 else 0.0
df['fair_rate']=df.set_index(['market_type','band']).index.map(lambda k: IS.rate.get(k,np.nan)); df['p_is']=df.set_index(['market_type','band']).index.map(lambda k: IS.p_mean.get(k,np.nan))
df=df[df.fair_rate.notna()&(df.p_is>0)].copy()
back=df.fair_rate>df.p_is  # underpriced -> back; else lay
bk_px=df.close_ltp.map(tick_down); ly_px=df.close_ltp.map(tick_up)
pnl_back=np.where(df.won==1,(bk_px-1)*10*(1-COMM),-10.0)
pnl_lay=np.where(df.won==1,-(ly_px-1)*10,10.0*(1-COMM))
df['pnl']=np.where(back,pnl_back,pnl_lay); df['side']=np.where(back,'BACK','LAY')
out=0
for (mt,b),gdf in df.groupby(['market_type','band']):
    n=len(gdf)
    if n<300 or gdf.oos.sum()<50 or (~gdf.oos).sum()<50: continue
    isx=gdf.loc[~gdf.oos,'pnl']; oox=gdf.loc[gdf.oos,'pnl']
    ctrl=gdf.pnl.values.copy(); w=gdf.won.values.copy(); rng.shuffle(w)
    ctrl=np.where(gdf.side.values=='BACK',np.where(w==1,(bk_px[gdf.index]-1)*10*(1-COMM),-10.0),np.where(w==1,-(ly_px[gdf.index]-1)*10,10.0*(1-COMM)))
    name=f"H1 {mt} p{edges[int(b)]:.2f}-{edges[int(b)+1]:.2f} {gdf.side.iloc[0]} at close (IS rate {gdf.fair_rate.iloc[0]:.3f} vs implied {gdf.p_is.iloc[0]:.3f})"
    print("RESULT "+json.dumps(dict(name=name,n=int(n),mean_per10=round(float(gdf.pnl.mean()),3),t=round(tstat(gdf.pnl),2),is_mean=round(float(isx.mean()),3),is_t=round(tstat(isx),2),oos_mean=round(float(oox.mean()),3),oos_t=round(tstat(oox),2),control_t=round(tstat(ctrl),2),n_oos=int(gdf.oos.sum())))); out+=1
print(f"cells reported {out} | market types {df.market_type.nunique()} | OOS rows {int(df.oos.sum())} | IS rows {int((~df.oos).sum())}")
print("NEXT DOOR (pre-registered): same map at in-play minute bands 0-15/15-30/30-45/HT/45-60/60-75/75+ (H1b), then by country (H1c).")
PYFILE
cat > /root/pe-sports/bookie/bookie_paper.py <<'PYFILE'
# BOOKIE PAPER BOT (THE ONE JOB, step 2 — Peter, 5 Nov 2026: "we are the bookie"). Rests paper orders at OUR fair price on the live
# Betfair football tape (Railway liq_sample, 22 market types since 08:17 UTC 5 Nov), both sides of every runner, £2 nominal.
# Fair price: normalised implied probability x fair_factor(market_type, band) from fair_price_calib (local, built by H1).
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
    lc.execute("select market_type, band_lo, band_hi, fair_factor, n_is from fair_price_calib where n_is>=300 and fair_factor is not null")
    C={}
    for mt,lo,hi,f,n in lc.fetchall(): C.setdefault(mt,[]).append((float(lo),float(hi),float(f)))
    return C
def factor(C,mt,p):
    for lo,hi,f in C.get(mt,[]):
        if lo<=p<hi: return f
    return None
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
[ -f hypotheses.json ] || cat > hypotheses.json <<'JSONF'
{"hypotheses":[
 {"id":"H1 fair price v0 (closing price calibration, every soccer market type)","script":"/root/pe-sports/team/fairprice_v0.py","status":"proposed","kind":"sweep","pre_registered_sign":"trade toward the IS fair price","next_door":"H1b: same map at in-play minute bands; H1c: by country","timeout":14400,"repeat_hours":168,"note":"re-fits weekly as the loader adds months"}
]}
JSONF
python3 -m py_compile sports_team.py fairprice_v0.py /root/pe-sports/bookie/bookie_paper.py || exit 1
cat > run_team.sh <<'SH'
#!/bin/bash
cd /root/pe-sports/team && exec python3 sports_team.py >> team.out 2>&1
SH
cat > /root/pe-sports/bookie/run_bookie.sh <<'SH'
#!/bin/bash
cd /root/pe-sports/bookie && while true; do python3 bookie_paper.py >> bookie.out 2>&1; sleep 15; done
SH
chmod +x run_team.sh /root/pe-sports/bookie/run_bookie.sh
( crontab -l 2>/dev/null | grep -v 'pe-sports/team/run_team.sh\|pe-sports/bookie/run_bookie.sh'; echo "@reboot nohup /root/pe-sports/team/run_team.sh &"; echo "*/10 * * * * pgrep -f 'sports_team.py' >/dev/null || nohup /root/pe-sports/team/run_team.sh &"; echo "*/10 * * * * [ -f /root/pe-sports/bookie/.ready ] && { pgrep -f 'bookie_paper.py' >/dev/null || nohup /root/pe-sports/bookie/run_bookie.sh & }" ) | crontab -
echo "== data health + five + money, first pass (no hypothesis yet)"
python3 - <<'PY'
import sys, json; sys.path.insert(0,'/root/pe-sports/team'); import sports_team as T
sb={'money':T.money(),'verdicts':[],'queue':[],'data_health':T.data_health(),'five':T.five_status()}
import datetime; sb['updated']=datetime.datetime.utcnow().isoformat()[:16]; T.write_scoreboard(sb); print(open(T.SBMD).read())
PY
pkill -f 'sports_team.py' 2>/dev/null; sleep 1; nohup /root/pe-sports/team/run_team.sh & disown
sleep 3; pgrep -f sports_team.py >/dev/null && echo "team daemon running pid $(pgrep -f sports_team.py | head -1)" || { echo "DAEMON NOT RUNNING"; exit 1; }
echo "H1 fair price v0 is now building in the daemon (bf_hist_other scan by market type; expect 20-90 min). The bookie paper bot starts itself when fair_price_calib lands."
tail -3 team.log
