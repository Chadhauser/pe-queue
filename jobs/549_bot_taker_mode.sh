#!/bin/bash
# 549 (Tue 10 Nov 2026, 13:40). BOT v2 TAKER MODE — what the two numbers say when put side by side:
#   replay control (546): a random resting order in pre-off football costs ~7% per fill (picked off);
#   passed cells (544):   the market is wrong by 1-3 points of probability.
# Edge < cost of making, so the bot does not rest orders in these cells. It TAKES the available price in the last 2 minutes before the
# off when a runner sits in a passed cell and the price is on the right side of fair — the exact bet the seven-year map scored (closing
# price, one tick adverse). Paper £2, settled on the official result, 2% commission, fill_kind='taker'. Maker quoting stays OFF until a
# cell's measured edge exceeds the measured pick-off cost on the real-book replay.
# Also: the Verifier drops cells whose fair factor is outside 0.7-1.3 (a closing price wrong by 30%+ is a stale-print artefact until the
# real-book replay clears it) — that removes the Over 4.5 long-price cell from the bot for now.
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
cd /root/pe-sports/bookie && cp bookie_v2.py bookie_v2.py.bak_549 && python3 - <<'PY'
p='/root/pe-sports/bookie/bookie_v2.py'; s=open(p).read()
assert 'TAKER' not in s
s=s.replace("HORIZON_MIN=60; VERSION='v2'","HORIZON_MIN=60; VERSION='v2'; MODE='taker'; TAKE_WINDOW_S=120   # 549: take, don't make",1)
old="""                key=(mid,sid)
                if now-last_quote.get(key,0)<REQUOTE or key in have: continue
                nt=nticks(bb,bl); q=None
                if side=='BACK':
                    qb=tick_up(bb) if nt>=2 else bb
                    if qb>=fair and qb<bl: q=('BACK',qb)
                else:
                    ql=tick_down(bl) if nt>=2 else bl
                    if ql<=fair and ql>bb: q=('LAY',ql)
                if not q: continue
                lc.execute("INSERT INTO bookie_paper (ts,market_id,event_name,mkt,sel,side,price,fair,mkt_back,mkt_lay,stake,status,version,exchange,bf_market_id,start_ts) VALUES (now(),%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,'open',%s,'betfair',%s,%s)",
                           (mid,(m.get('event') or {}).get('name'),mt,sid,q[0],q[1],round(fair,3),bb,bl,STAKE,VERSION,mid,m.get('marketStartTime')))
                last_quote[key]=now; quoted+=1"""
new="""                key=(mid,sid)
                if key in have or key in taken: continue
                if MODE=='taker':
                    # TAKER (549): last TAKE_WINDOW_S before the off, take the available price if it is on the right side of fair
                    try: sto=(datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00'))-datetime.datetime.now(datetime.timezone.utc)).total_seconds()
                    except Exception: continue
                    if not (0<sto<=TAKE_WINDOW_S): continue
                    if side=='BACK' and bb>fair: q=('BACK',bb)
                    elif side=='LAY' and bl<fair: q=('LAY',bl)
                    else: continue
                    lc.execute("INSERT INTO bookie_paper (ts,market_id,event_name,mkt,sel,side,price,fair,mkt_back,mkt_lay,stake,status,version,exchange,bf_market_id,start_ts,fill_ts,fill_price,fill_kind) VALUES (now(),%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,'filled',%s,'betfair',%s,%s,now(),%s,'taker')",
                               (mid,(m.get('event') or {}).get('name'),mt,sid,q[0],q[1],round(fair,3),bb,bl,STAKE,VERSION,mid,m.get('marketStartTime'),q[1]))
                    taken.add(key); quoted+=1; continue
                if now-last_quote.get(key,0)<REQUOTE: continue
                nt=nticks(bb,bl); q=None
                if side=='BACK':
                    qb=tick_up(bb) if nt>=2 else bb
                    if qb>=fair and qb<bl: q=('BACK',qb)
                else:
                    ql=tick_down(bl) if nt>=2 else bl
                    if ql<=fair and ql>bb: q=('LAY',ql)
                if not q: continue
                lc.execute("INSERT INTO bookie_paper (ts,market_id,event_name,mkt,sel,side,price,fair,mkt_back,mkt_lay,stake,status,version,exchange,bf_market_id,start_ts) VALUES (now(),%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,'open',%s,'betfair',%s,%s)",
                           (mid,(m.get('event') or {}).get('name'),mt,sid,q[0],q[1],round(fair,3),bb,bl,STAKE,VERSION,mid,m.get('marketStartTime')))
                last_quote[key]=now; quoted+=1"""
assert s.count(old)==1, "quote block anchor"; s=s.replace(old,new)
old2="""        lc.execute("SELECT market_id, sel FROM bookie_paper WHERE version=%s AND status='open'",(VERSION,)); have={(a,b) for a,b in lc.fetchall()}"""
new2="""        lc.execute("SELECT market_id, sel FROM bookie_paper WHERE version=%s AND status='open'",(VERSION,)); have={(a,b) for a,b in lc.fetchall()}
        lc.execute("SELECT market_id, sel FROM bookie_paper WHERE version=%s AND fill_kind='taker' AND ts>now()-interval '6 hours'",(VERSION,)); taken={(a,b) for a,b in lc.fetchall()}   # one taker bet per runner"""
assert s.count(old2)==1, "have anchor"; s=s.replace(old2,new2)
# log line says the mode
s=s.replace('log(f"universe {len(cat)} books {len(books)} quoted {quoted}','log(f"[{MODE}] universe {len(cat)} books {len(books)} bets {quoted}')
open(p,'w').write(s); print("bookie_v2: taker mode")
PY
python3 -m py_compile bookie_v2.py && echo "compiles" || { cp bookie_v2.py.bak_549 bookie_v2.py; echo RESTORED; exit 1; }
# the artefact gate in the Verifier
python3 - <<'PY'
p='/root/pe-sports/team/verifier_cells.py'; s=open(p).read()
if 'fair_factor BETWEEN 0.7 AND 1.3' not in s:
    s=s.replace("c.execute(\"DELETE FROM fair_price_passed WHERE source='H1'\"); n=0","c.execute(\"DELETE FROM fair_price_passed WHERE source='H1'\"); n=0\nARTEFACT=lambda f: f is None or not (0.7<=float(f)<=1.3)   # 549: a closing price wrong by 30%+ is a stale print until the real-book replay clears it")
    s=s.replace("    if (eis>0)==(eoos>0) and abs(eis)>=0.01 and abs(eoos)>=0.005:","    if ARTEFACT(f): continue\n    if (eis>0)==(eoos>0) and abs(eis)>=0.01 and abs(eoos)>=0.005:")
    s=s.replace('print(f"{datetime.datetime.utcnow():%Y-%m-%d %H:%M} passed cells: {n}")','print(f"{datetime.datetime.utcnow():%Y-%m-%d %H:%M} passed cells: {n} (fair_factor BETWEEN 0.7 AND 1.3 enforced)")')
    open(p,'w').write(s); print("verifier: artefact gate on fair factor")
PY
python3 -m py_compile /root/pe-sports/team/verifier_cells.py && python3 /root/pe-sports/team/verifier_cells.py
pkill -f bookie_v2.py; sleep 100; tail -3 /root/pe-sports/bookie/bookie_v2.log
# scoreboard: settled lines by fill kind
python3 - <<'PY'
p='/root/pe-sports/team/sports_team.py'; s=open(p).read()
old="""    add('bookie v2 (Betfair, pre-off, passed cells)',"select count(*), coalesce(sum(stake),0), coalesce(sum(pnl),0), count(*) filter (where settled_ts>now()-interval '7 days'), coalesce(sum(pnl) filter (where settled_ts>now()-interval '7 days'),0) from bookie_paper where version='v2' and status='settled'")"""
new="""    add('bot v2 TAKER (passed cells, last 2 min pre-off)',"select count(*), coalesce(sum(stake),0), coalesce(sum(pnl),0), count(*) filter (where settled_ts>now()-interval '7 days'), coalesce(sum(pnl) filter (where settled_ts>now()-interval '7 days'),0) from bookie_paper where version='v2' and status='settled' and fill_kind='taker'")
    add('bot v2 MAKER (resting, 9-10 Nov, now off)',"select count(*), coalesce(sum(stake),0), coalesce(sum(pnl),0), count(*) filter (where settled_ts>now()-interval '7 days'), coalesce(sum(pnl) filter (where settled_ts>now()-interval '7 days'),0) from bookie_paper where version='v2' and status='settled' and coalesce(fill_kind,'maker')<>'taker'")"""
if s.count(old)==1: s=s.replace(old,new); open(p,'w').write(s); print("scoreboard: taker/maker lines")
else: print("scoreboard anchor not found — settled line unchanged")
PY
python3 -m py_compile /root/pe-sports/team/sports_team.py && pkill -f sports_team.py; sleep 2; nohup /root/pe-sports/team/run_team.sh >/dev/null 2>&1 & disown
echo "549 done — bot v2 is a taker in passed cells; maker off; artefact cells excluded"
