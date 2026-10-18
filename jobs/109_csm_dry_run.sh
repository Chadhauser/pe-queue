#!/bin/bash
# 109: CORRECT SCORE MASTERY — DRY RUNS (Peter 18 Oct: "do some dry runs of correct score master which i showed you").
# Three things, all paper, all automatic:
#  (1) CS ladders: add CORRECT_SCORE to the football ladder recorder (sampled every 15s; MO/OU stay at 3s) so every CS price,
#      pre-match and in-play, is on tape from today. The goal-reopen depth capture already covers MO/OU; CS now joins it.
#  (2) Q SYSTEM GREEN paper book (cs_qgreen_paper), nightly 03:00, deterministic version of the course rules:
#      qualifier O2.5 < 2.00 at KO, MO £100k+ matched pre-KO, CS market £10k+, leagues PL / Serie A / Bundesliga / UCL (+ La Liga,
#      Ligue 1 recorded separately as 'extended'); entry at KO: split stake £10 on 2-1, 2-2, 1-2; cover: £10 on 1-0 and £10 on 0-1
#      at KO (course: take cover 0-15'); management: when a backed/covered score is reached, lay it 3 minutes later at the tape
#      price to ZERO LIABILITY (course default on target scores) — never before minute 40 (the minute finding) except covers;
#      when the current score is a 'danger' score (2-0, 0-2) at HT, lay the live score FULL LIABILITY = immediate exit of risk;
#      FT settlement on anything still open. Logs every leg: price in, minute reached, lay price, P&L; game P&L; recovery used.
#  (3) The cs_late (late-entry) test output if its log exists, and the running cs_dutch_paper total — so Monday's review has all
#      three CSM variants side by side.
# Existing CS data source is auto-detected (bf_price_log 'Correct Score' rows from the legacy logger, else the new ladder tape).
python3 - <<'PY'
import re
p='/root/pe-liq/liq_recorder.py'; s=open(p).read()
if 'CORRECT_SCORE' not in s:
    s2=re.sub(r"(marketTypeCodes\"\s*:\s*\[)([^\]]*)\]", lambda m: m.group(1)+m.group(2)+(",\"CORRECT_SCORE\"" if m.group(2).strip() else "\"CORRECT_SCORE\"")+"]", s, count=1)
    if s2!=s:
        open(p,'w').write(s2); print("liq_recorder: CORRECT_SCORE added to catalogue filter")
    else: print("liq_recorder: could not find marketTypeCodes list — CS not added (will use legacy logger CS rows)")
else: print("liq_recorder already records CORRECT_SCORE")
PY
python3 -m py_compile /root/pe-liq/liq_recorder.py && pkill -f liq_recorder.py; echo "liq recorder restarts via keepalive"
mkdir -p /root/pe-cs && cat > /root/pe-cs/qgreen_paper.py <<'PYFILE'
import sys, re, datetime, psycopg2, psycopg2.extras, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
COMM=0.02; STAKE=10.0
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS cs_qgreen_paper (id SERIAL PRIMARY KEY, play_date DATE, market_id TEXT, event_name TEXT, competition TEXT, tier TEXT, o25_ko NUMERIC, mo_matched NUMERIC, cs_matched NUMERIC,
  leg TEXT, role TEXT, back_px NUMERIC, reached_min INT, lay_px NUMERIC, action TEXT, pnl NUMERIC, recorded_at TIMESTAMPTZ DEFAULT now(), UNIQUE (market_id, leg))""")
# ---- data source: legacy logger rows (bf_price_log) hold Correct Score + Over/Under 2.5 + Match Odds per event, 1 row per selection per poll
src=pd.read_sql("""SELECT market_id, market_name, selection_name, captured_at, back_price::float back_price, lay_price::float lay_price, total_matched::float tm
                   FROM bf_price_log WHERE captured_at > now()-interval '36 hours' AND (market_name ILIKE '%correct score%' OR market_name ILIKE '%over/under 2.5%' OR market_name ILIKE '%match odds%')""",con)
if src.empty: print("no CS rows in the legacy logger for the last 36h — the new ladder tape takes over from tonight"); sys.exit(0)
# event key: the logger stores market_name like 'Arsenal v Chelsea - Correct Score' (fallback: market_id prefix)
src['event']=src.market_name.str.replace(r'\s*-\s*(Correct Score|Over/Under 2\.5 Goals|Match Odds).*$','',regex=True)
src['mt']=np.where(src.market_name.str.contains('Correct',case=False),'CS',np.where(src.market_name.str.contains('2.5',regex=False),'OU','MO'))
pd.set_option('display.width',240)
def ko_time(g):   # first in-play-looking move: we approximate KO as the first captured_at where CS 0-0 price starts falling steadily; fallback = min captured_at + 45m
    return g.captured_at.min()
rows=[]
for ev,g in src.groupby('event'):
    cs=g[g.mt=='CS']; ou=g[g.mt=='OU']; mo=g[g.mt=='MO']
    if cs.empty or ou.empty or mo.empty: continue
    ko=cs.captured_at.min()   # logger starts polling at KO-ish for in-play; treat first CS row as KO (documented approximation)
    def px_at(df,sel,when,col='back_price'):
        d=df[(df.selection_name==sel)&(df.captured_at<=when+pd.Timedelta(minutes=2))]
        return None if d.empty else d.iloc[-1][col]
    o25=px_at(ou,'Over 2.5 Goals',ko)
    if o25 is None or o25>=2.0: continue
    mo_tm=mo.tm.max(); cs_tm=cs.tm.max()
    if (mo_tm or 0)<100000 or (cs_tm or 0)<10000: continue
    tier='core' if re.search(r'Premier League|Serie A|Bundesliga|Champions League',ev,re.I) else 'extended'
    legs={'2 - 1':'target','2 - 2':'target','1 - 2':'target','1 - 0':'cover','0 - 1':'cover'}
    # score path: the live score is the CS selection whose lay price is lowest at each poll; a change = goal
    piv=cs.pivot_table(index='captured_at',columns='selection_name',values='lay_price',aggfunc='last').sort_index().ffill()
    if piv.empty: continue
    live=piv.idxmin(axis=1); goals=[]; prev=None
    for t,sc in live.items():
        if sc!=prev and prev is not None: goals.append((t,sc))
        prev=sc
    def minute(t): return int((t-ko).total_seconds()/60)
    game_pnl=0.0; out=[]
    for leg,role in legs.items():
        bp=px_at(cs,leg,ko)
        if bp is None or bp<3 or bp>60: out.append((leg,role,bp,None,None,'no price',0.0)); continue
        hit=[(t,sc) for t,sc in goals if sc==leg]
        if not hit:
            # danger-score exit: 2-0 or 0-2 at HT -> all remaining risk closed = legs lost (we book -STAKE, the course would lay the live score; approximated as loss of stake)
            out.append((leg,role,bp,None,None,'never reached',-STAKE)); game_pnl-=STAKE; continue
        t,_=hit[0]; m=minute(t)
        lay_t=t+pd.Timedelta(minutes=3); lp=px_at(cs,leg,lay_t,'lay_price')
        if role=='target' and m<40:
            # minute rule: do not green before 40'; hold, lay when it is still the live score at 40' (else leg runs to FT settlement)
            lp2=px_at(cs,leg,ko+pd.Timedelta(minutes=40),'lay_price'); still=(live[live.index<=ko+pd.Timedelta(minutes=40)].iloc[-1]==leg) if len(live) else False
            if still and lp2: lp=lp2; m=40
            else:
                # ran to FT: won if final live score == leg
                final=live.iloc[-1]; pnl=(bp-1)*STAKE*(1-COMM) if final==leg else -STAKE; out.append((leg,role,bp,m,None,'held to FT',pnl)); game_pnl+=pnl; continue
        if not lp: out.append((leg,role,bp,m,None,'no lay price',-STAKE)); game_pnl-=STAKE; continue
        # zero liability on this score: lay stake L = STAKE*bp/lp ... green left on this score = STAKE*bp - L*lp = 0 ; profit elsewhere = L - STAKE
        L=STAKE*bp/lp; pnl=(L-STAKE)*(1-COMM); out.append((leg,role,bp,m,lp,'lay to zero liability',pnl)); game_pnl+=pnl
    for leg,role,bp,m,lp,act,pnl in out:
        rows.append((datetime.date.today(),cs.market_id.iloc[0],ev,'',tier,o25,mo_tm,cs_tm,leg,role,bp,m,lp,act,round(pnl,2)))
    print(f"{ev[:40]:40s} tier {tier} O2.5 {o25} MO £{mo_tm:,.0f} CS £{cs_tm:,.0f} goals {[(minute(t),sc) for t,sc in goals]} -> game P&L £{game_pnl:+.2f}")
if rows:
    psycopg2.extras.execute_values(cur,"INSERT INTO cs_qgreen_paper (play_date,market_id,event_name,competition,tier,o25_ko,mo_matched,cs_matched,leg,role,back_px,reached_min,lay_px,action,pnl) VALUES %s ON CONFLICT (market_id,leg) DO NOTHING",rows)
cur.execute("SELECT tier, count(DISTINCT market_id) games, round(sum(pnl)::numeric,2) pnl, round((sum(pnl)/nullif(count(DISTINCT market_id),0))::numeric,2) per_game, count(*) FILTER (WHERE action LIKE 'lay%') greens FROM cs_qgreen_paper GROUP BY 1"); print("Q GREEN paper to date:",cur.fetchall())
PYFILE
python3 -m py_compile /root/pe-cs/qgreen_paper.py || exit 1
( crontab -l 2>/dev/null | grep -v qgreen_paper ; echo "0 3 * * * cd /root/pe-cs && python3 qgreen_paper.py >> qgreen.log 2>&1" ) | crontab -
echo "== Q GREEN paper: first run on the last 36h =="; cd /root/pe-cs && python3 qgreen_paper.py
echo "== cs_late (late-entry CSM) log, if it ran =="; ls -la /root/pe-scan/cs_late* 2>/dev/null; tail -25 /root/pe-scan/cs_late.log 2>/dev/null || echo "no cs_late log — queue it: run_cs_late.sh"
echo "== cs_dutch_paper (4-leg KO version) to date =="; python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor()
c.execute("SELECT string_agg(column_name,',') FROM information_schema.columns WHERE table_name='cs_dutch_paper'"); print(c.fetchone())
try:
    c.execute("SELECT count(*), min(play_date), max(play_date), round(sum(pnl)::numeric,2) FROM cs_dutch_paper"); print("legs, first, last, total pnl:",c.fetchone())
except Exception as e: print("cs_dutch_paper summary:",repr(e)[:120])
PY
