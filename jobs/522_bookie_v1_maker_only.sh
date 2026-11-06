#!/bin/bash
# 522: BOOKIE v1 (maker only) + void v0. Overnight 5-6 Nov the v0 bot wrote 920k paper orders, 630k of them TAKER fills: the normalised
# "fair" sat above the market on every runner, so the lay branch took the market's lay price all night (−£27,302 paper at £2 stakes, and
# settlement by price collapse on top). That is the opposite of the bookie frame. v1: quote one tick inside the spread (or join the
# touch), maker fills only, one quote pair per runner per 5 min, markets >= £5k matched, settle on the OFFICIAL result via listMarketBook
# (runner ids learned from listMarketCatalogue into liq_runners). v0 rows are marked version='v0' and excluded from money and the five.
# Also: H1 last_output tail now shows in the scoreboard queue so a failed build explains itself.
set -o pipefail
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local()); c.autocommit=True; k=c.cursor(); k.execute("SET statement_timeout='600s'")
k.execute("ALTER TABLE bookie_paper ADD COLUMN IF NOT EXISTS version TEXT")
k.execute("UPDATE bookie_paper SET version='v0' WHERE version IS NULL"); print("v0 rows marked:",k.rowcount)
k.execute("ALTER TABLE bookie_paper ALTER COLUMN version SET DEFAULT 'v1'")
k.execute("UPDATE bookie_paper SET status='void_v0' WHERE version='v0' AND status='open'")
k.execute("select version,status,count(*),round(coalesce(sum(pnl),0)::numeric,2) from bookie_paper group by 1,2 order by 1,2"); print(k.fetchall())
PY
pkill -f bookie_paper.py; pkill -f run_bookie.sh; sleep 2
cat > /root/pe-sports/bookie/bookie_paper.py <<'PYFILE'
# BOOKIE PAPER BOT v1 (THE ONE JOB, step 2 — "we are the bookie"). Rests paper orders INSIDE the live spread on the Betfair football tape
# (Railway liq_sample, 22 market types) and is paid the spread when both sides fill. MAKER ONLY: v0 (5 Nov) took the market's own price on
# every lay because the normalised "fair" sat above the market on every runner — 630k taker fills, −£27k paper, voided. v1 rules:
#  QUOTE: for each runner with a two-sided book, spread >= 2 ticks -> BACK at tick_up(back_px), LAY at tick_down(lay_px) (one tick inside);
#         spread == 1 tick -> join the touch (BACK at back_px, LAY at lay_px). Never cross. One quote pair per runner per 5 minutes,
#         markets with total_matched >= £5,000 only, 10-minute order life, £2 nominal. Fair-price skew (H1) is applied only from sane cells
#         and only tilts which side is quoted (no back if fair says the runner is overpriced; no lay if underpriced).
#  FILL (one tick adverse): BACK at P fills when a later sample shows back_px >= tick_up(P); LAY at L fills when lay_px <= tick_down(L).
#  SETTLE: official result from Betfair listMarketBook once the market is CLOSED (runner status WINNER/LOSER), 2% commission on net
#         market profit per market. Table bookie_paper (local). The Verifier reports fills, maker ratio, adverse rate, £ per £100 quoted.
import sys, time, datetime, traceback, json, requests, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-queue/runner'); import creds
STAKE=2.0; COMM=0.02; TTL=600; REQUOTE=300; MIN_MATCHED=5000; BATCH=40
LADDER=[(2,0.01),(3,0.02),(4,0.05),(6,0.1),(10,0.2),(20,0.5),(30,1),(50,2),(100,5),(1000,10)]
def tick(p):
    for lim,inc in LADDER:
        if p<lim: return inc
    return 10
def tick_down(p): return round(max(1.01,p-tick(p-1e-9)),2)
def tick_up(p): return round(min(1000,p+tick(p)),2)
def nticks(a,b):
    n=0; p=a
    while p<b-1e-9 and n<50: p=tick_up(p); n+=1
    return n
def log(m):
    with open('/root/pe-sports/bookie/bookie.log','a') as f: f.write(f"{datetime.datetime.utcnow():%Y-%m-%d %H:%M:%S} {m}\n")
L=psycopg2.connect(creds.pg_local(),sslmode='prefer'); L.autocommit=True; lc=L.cursor()
lc.execute("""CREATE TABLE IF NOT EXISTS bookie_paper (id BIGSERIAL PRIMARY KEY, ts TIMESTAMPTZ, market_id TEXT, event_name TEXT, mkt TEXT, sel TEXT, side TEXT,
  price NUMERIC, fair NUMERIC, mkt_back NUMERIC, mkt_lay NUMERIC, stake NUMERIC, status TEXT, fill_ts TIMESTAMPTZ, fill_price NUMERIC, fill_kind TEXT,
  won INT, pnl NUMERIC, settled_ts TIMESTAMPTZ, start_ts TIMESTAMPTZ);
  CREATE INDEX IF NOT EXISTS bookie_paper_ts ON bookie_paper (ts); CREATE INDEX IF NOT EXISTS bookie_paper_mkt ON bookie_paper (market_id, status);
  CREATE TABLE IF NOT EXISTS bookie_heartbeat (id INT PRIMARY KEY, last_seen TIMESTAMPTZ, open_orders INT, fills INT);
  ALTER TABLE bookie_paper ADD COLUMN IF NOT EXISTS version TEXT DEFAULT 'v1'""")
# ---- Betfair (settlement only)
APP,USER,PW=creds.betfair(); SSO=None; SSO_T=0
def login():
    global SSO,SSO_T
    r=requests.post("https://identitysso.betfair.com/api/login",data={"username":USER,"password":PW},headers={"X-Application":APP,"Accept":"application/json"},timeout=20).json()
    if r.get('status')=='SUCCESS': SSO=r['token']; SSO_T=time.time(); return True
    log(f"login failed {r.get('error')}"); return False
def book(mids):
    if SSO is None or time.time()-SSO_T>3*3600:
        if not login(): return []
    r=requests.post("https://api.betfair.com/exchange/betting/rest/v1.0/listMarketBook/",json={"marketIds":mids},headers={"X-Application":APP,"X-Authentication":SSO,"Content-Type":"application/json"},timeout=25)
    if r.status_code!=200: log(f"listMarketBook {r.status_code} {r.text[:120]}"); return []
    return r.json()
def catalogue(mids):
    if SSO is None or time.time()-SSO_T>3*3600:
        if not login(): return []
    r=requests.post("https://api.betfair.com/exchange/betting/rest/v1.0/listMarketCatalogue/",json={"filter":{"marketIds":mids},"marketProjection":["RUNNER_DESCRIPTION"],"maxResults":len(mids)},headers={"X-Application":APP,"X-Authentication":SSO,"Content-Type":"application/json"},timeout=25)
    if r.status_code!=200: log(f"listMarketCatalogue {r.status_code} {r.text[:120]}"); return []
    return r.json()
lc.execute("CREATE TABLE IF NOT EXISTS liq_runners (market_id TEXT, sel_id BIGINT, name TEXT, PRIMARY KEY (market_id, sel_id))")
def calib():
    C={}
    try:
        lc.execute("select market_type, band_lo, band_hi, fair_factor from fair_price_calib where n_is>=300 and fair_factor is not null and abs(rate_is-p_mean_is)<=0.08")
        for mt,lo,hi,f in lc.fetchall(): C.setdefault(mt,[]).append((float(lo),float(hi),float(f)))
    except Exception as e: log(f"calib read failed {e!r}"[:160])
    return C
SHORT={'MO':'MATCH_ODDS','OU05':'OVER_UNDER_05','OU15':'OVER_UNDER_15','OU25':'OVER_UNDER_25','OU35':'OVER_UNDER_35','OU45':'OVER_UNDER_45','OU55':'OVER_UNDER_55',
 'BTTS':'BOTH_TEAMS_TO_SCORE','CS':'CORRECT_SCORE','AH':'ASIAN_HANDICAP','DNB':'DRAW_NO_BET','HT_MO':'HALF_TIME','HT_CS':'HALF_TIME_SCORE','HTFT':'HALF_TIME_FULL_TIME',
 'FH05':'FIRST_HALF_GOALS_05','FH15':'FIRST_HALF_GOALS_15','FH25':'FIRST_HALF_GOALS_25','DC':'DOUBLE_CHANCE','HWTN':'TEAM_A_WIN_TO_NIL','AWTN':'TEAM_B_WIN_TO_NIL','MOBTTS':'MATCH_ODDS_AND_BTTS','MOOU25':'MATCH_ODDS_AND_OU_25'}
def skew(C,mkt,p):
    for lo,hi,f in C.get(SHORT.get(mkt,''),[]):
        if lo<=p<hi: return f
    return 1.0
def rconn(): return psycopg2.connect(creds.pg_railway(),sslmode='require',connect_timeout=20)
last_cal=0; C={}; R=None; last_quote={}
while True:
    try:
        if time.time()-last_cal>3600: C=calib(); last_cal=time.time(); log(f"calibration sane cells {sum(len(v) for v in C.values())}")
        if R is None or R.closed: R=rconn()
        rc=R.cursor(); rc.execute("SET statement_timeout='40s'")
        rc.execute("""WITH last AS (SELECT market_id, max(ts) ts FROM liq_sample WHERE ts>now()-interval '90 seconds' GROUP BY 1)
                      SELECT s.market_id, s.ts, s.event_name, s.mkt, s.sel, s.ltp, s.back_px, s.lay_px, s.total_matched FROM liq_sample s JOIN last USING (market_id, ts)""")
        rows=rc.fetchall(); R.commit(); by={}
        for mid,ts,ev,mkt,sel,ltp,bp,lp,tm in rows: by.setdefault(mid,[]).append((ts,ev,mkt,sel,float(ltp or 0),float(bp or 0),float(lp or 0),float(tm or 0)))
        # fills (maker only)
        lc.execute("select id, market_id, sel, side, price from bookie_paper where status='open'"); filled=0
        for oid,mid,sel,side,price in lc.fetchall():
            for ts,ev,mkt,s,ltp,bp,lp,tm in by.get(mid,[]):
                if s!=sel: continue
                price=float(price)
                if side=='BACK' and bp>=tick_up(price): lc.execute("update bookie_paper set status='filled', fill_ts=%s, fill_price=%s, fill_kind='maker' where id=%s",(ts,price,oid)); filled+=1
                elif side=='LAY' and lp>0 and lp<=tick_down(price): lc.execute("update bookie_paper set status='filled', fill_ts=%s, fill_price=%s, fill_kind='maker' where id=%s",(ts,price,oid)); filled+=1
        lc.execute("update bookie_paper set status='expired' where status='open' and ts<now()-interval '%s seconds'"%TTL)
        lc.execute("select market_id, sel, side from bookie_paper where status='open'"); have={(a,b,c) for a,b,c in lc.fetchall()}
        quoted=0; now=time.time()
        for mid,rs in by.items():
            if rs[0][7]<MIN_MATCHED or len(rs)<2: continue
            tot=sum(1/r[4] for r in rs if r[4]>1)
            for ts,ev,mkt,sel,ltp,bp,lp,tm in rs:
                if bp<=1 or lp<=1 or lp<=bp or ltp<=1: continue
                key=(mid,sel)
                if now-last_quote.get(key,0)<REQUOTE: continue
                nt=nticks(bp,lp)
                qb,ql=(tick_up(bp),tick_down(lp)) if nt>=2 else (bp,lp)
                if ql<qb: continue
                p=(1/ltp)/tot if tot>0 else 0; f=skew(C,mkt,p); fair=1/max(0.005,min(0.99,p*f)) if p>0 else None
                want_back = fair is None or f>=1.0   # fair says runner is under- or fairly priced -> happy to back
                want_lay  = fair is None or f<=1.0   # fair says over- or fairly priced -> happy to lay
                if want_back and key+('BACK',) not in have:
                    lc.execute("insert into bookie_paper (ts,market_id,event_name,mkt,sel,side,price,fair,mkt_back,mkt_lay,stake,status,version) values (%s,%s,%s,%s,%s,'BACK',%s,%s,%s,%s,%s,'open','v1')",(ts,mid,ev,mkt,sel,qb,fair,bp,lp,STAKE)); quoted+=1
                if want_lay and key+('LAY',) not in have:
                    lc.execute("insert into bookie_paper (ts,market_id,event_name,mkt,sel,side,price,fair,mkt_back,mkt_lay,stake,status,version) values (%s,%s,%s,%s,%s,'LAY',%s,%s,%s,%s,%s,'open','v1')",(ts,mid,ev,mkt,sel,ql,fair,bp,lp,STAKE)); quoted+=1
                last_quote[key]=now
        # runner ids for markets we quote (needed to settle by official result); 5-minute cadence, 40 markets per call
        if now-globals().get('_cat_t',0)>300:
            globals()['_cat_t']=now
            lc.execute("select distinct market_id from liq_runners"); known={m for (m,) in lc.fetchall()}
            need=[m for m in by if m not in known][:120]
            for i in range(0,len(need),40):
                for m in catalogue(need[i:i+40]):
                    for r in m.get('runners',[]): lc.execute("insert into liq_runners values (%s,%s,%s) on conflict do nothing",(m['marketId'],r['selectionId'],r.get('runnerName','')))
        # settlement: official result via listMarketBook for markets with fills that have left the tape for 2h+
        lc.execute("select distinct market_id from bookie_paper where status='filled' and version='v1' and ts<now()-interval '120 minutes'"); due=[m for (m,) in lc.fetchall() if m not in by][:BATCH]
        settled=0
        if due:
            for b in book(due):
                if b.get('status')!='CLOSED':
                    continue
                win={str(r['selectionId']):r.get('status') for r in b.get('runners',[])}
                lc.execute("select id, sel, side, fill_price, stake from bookie_paper where market_id=%s and status='filled'",(b['marketId'],)); fills=lc.fetchall()
                # runner names -> selection ids via the tape (liq_sample stores names); map by name through the recorder's catalogue table if present, else by order
                lc.execute("select sel_id, name from liq_runners where market_id=%s",(b['marketId'],)); cat_=lc.fetchall()
                def norm(x): return ''.join(ch for ch in str(x).upper() if ch.isalnum())
                nm={norm(n):str(i) for i,n in cat_}
                for oid,sel,side,fp,stk in fills:
                    k=norm(sel); sid=nm.get(k) or next((v for kk,v in nm.items() if k and (k in kk or kk in k)),None); st=win.get(sid) if sid else None
                    if st not in ('WINNER','LOSER'):
                        lc.execute("update bookie_paper set status='unsettleable', settled_ts=now() where id=%s",(oid,)); continue
                    fp=float(fp); stk=float(stk); won=1 if st=='WINNER' else 0
                    gross=((fp-1)*stk if won else -stk) if side=='BACK' else (-(fp-1)*stk if won else stk)
                    pnl=gross*(1-COMM) if gross>0 else gross
                    lc.execute("update bookie_paper set status='settled', won=%s, pnl=%s, settled_ts=now() where id=%s",(won,round(pnl,4),oid)); settled+=1
        lc.execute("select count(*) filter (where status='open'), count(*) filter (where status in ('filled','settled') and version='v1') from bookie_paper"); o,f=lc.fetchone()
        lc.execute("insert into bookie_heartbeat values (1,now(),%s,%s) on conflict (id) do update set last_seen=now(), open_orders=excluded.open_orders, fills=excluded.fills",(o,f))
        if quoted or filled or settled: log(f"markets {len(by)} quoted {quoted} filled {filled} settled {settled} open {o}")
    except Exception:
        log(traceback.format_exc()[-600:])
        try: R.close()
        except Exception: pass
        R=None; time.sleep(20)
    time.sleep(20)
PYFILE
cd /root/pe-sports/team && cp sports_team.py sports_team.py.bak_522
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
    b=tryq('local',"select status, count(*), round(coalesce(sum(pnl),0)::numeric,2) from bookie_paper where version='v1' group by 1 order by 1")
    b2=tryq('local',"select side, count(*), round(avg(pnl)::numeric,3) from bookie_paper where version='v1' and status='settled' group by 1")
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
    try: m['paper_month']=float(q('local',"select coalesce(sum(pnl),0) from bookie_paper where status='settled' and version='v1' and ts>=date_trunc('month',now())")[0][0])
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
    L+=["","## Queue"]+[f"- {h['id']}: {h['status']} {h.get('note','')}"+(f" | last output: {h.get('tail','')}" if h['status']=='failed' else '') for h in sb['queue']]
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
        h['status']='running'; json.dump(reg,open(REG,'w'),indent=1); write_scoreboard({**sb,'queue':[{'id':x['id'],'status':x['status'],'note':x.get('note',''),'tail':''} for x in reg['hypotheses']],'updated':datetime.datetime.utcnow().isoformat()[:16]})
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
PYFILE
python3 -m py_compile /root/pe-sports/bookie/bookie_paper.py sports_team.py || { cp sports_team.py.bak_522 sports_team.py; echo "compile failed"; exit 1; }
nohup /root/pe-sports/bookie/run_bookie.sh >/dev/null 2>&1 & disown
if ! grep -q '"status": "running"' hypotheses.json; then pkill -f sports_team.py; sleep 2; nohup /root/pe-sports/team/run_team.sh & disown; fi
sleep 90; pgrep -f bookie_paper.py >/dev/null && echo "bookie v1 up" || echo "BOOKIE DOWN"; tail -4 /root/pe-sports/bookie/bookie.log
python3 - <<'PY'
import json; r=json.load(open('/root/pe-sports/team/hypotheses.json'))
for h in r['hypotheses']: print(h['id'][:30],h['status'],h.get('note',''),'| tail:',(h.get('last_output') or '')[-700:].replace(chr(10),' '))
PY
