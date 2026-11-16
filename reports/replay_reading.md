# Replay reading 2026-11-16 15:26 UTC (job 609)

## bot decision + settlement (bookie_v2.py)
```
7:STAKE=2.0; COMM=0.02; TTL=600; REQUOTE=300; MIN_MATCHED=2000.0; MIN_SIZE=10.0; MAX_PRICE=20.0; MAX_SPREAD=3; HORIZON_MIN=60; VERSION='v2'; MODE='taker'; TAKE_WINDOW_S=120   # 549: take, don't make
8:LADDER=[(2,0.01),(3,0.02),(4,0.05),(6,0.1),(10,0.2),(20,0.5),(30,1),(50,2),(100,5),(1000,10)]
9:def tick(p):
13:def tick_down(p): return round(max(1.01,p-tick(p-1e-9)),2)
14:def tick_up(p): return round(min(1000,p+tick(p)),2)
15:def nticks(a,b):
19:def log(m):
24:    def __init__(self): self._c=L.cursor()
25:    def execute(self,*a,**k):
30:    def __getattr__(self,n): return getattr(self._c,n)
34:def login():
39:def api(ep,body):
43:    if r.status_code!=200: log(f"{ep} {r.status_code} {r.text[:120]}"); return []
47:def _matched(b):   # 578: Betfair's market-level totalMatched came back empty on every book from 12 Nov 23:58; fall back to the runners, then to the ladder
52:    ok=sum(1 for r in b.get('runners',[]) if (r.get('ex',{}).get('availableToBack') or [{}])[0].get('size',0)>=MIN_SIZE and (r.get('ex',{}).get('availableToLay') or [{}])[0].get('size',0)>=MIN_SIZE
53:    return MIN_MATCHED if ok>=2 else 0
54:def cells():
55:    lc.execute("SELECT sport, market_type, band_lo, band_hi, side, fair_factor FROM fair_price_passed"); C={}
61:def cell_for(C,mt,p):
75:                for m in api('listMarketCatalogue',{"filter":f,"marketProjection":["EVENT","EVENT_TYPE","MARKET_START_TIME","MARKET_DESCRIPTION"],"maxResults":200}): m['_et']=et; cat[m['marketId']]
80:            for b in api('listMarketBook',{"marketIds":mids[i:i+40],"priceProjection":{"priceData":["EX_BEST_OFFERS"]}}): books[b['marketId']]=b
88:            bb=(r.get('ex',{}).get('availableToBack') or [{}])[0].get('price'); bl=(r.get('ex',{}).get('availableToLay') or [{}])[0].get('price'); price=float(price)
91:        lc.execute("UPDATE bookie_paper SET status='expired' WHERE version=%s AND status='open' AND ts<now()-interval '%s seconds'"%("%s",TTL),(VERSION,))
97:            if not m or (m.get('_et'),mt) not in C or b.get('status')!='OPEN' or b.get('inplay') or _matched(b)<MIN_MATCHED: continue   # 578: robust liquidity read
100:                ex=r.get('ex',{}); bb=(ex.get('availableToBack') or [{}])[0]; bl=(ex.get('availableToLay') or [{}])[0]
106:                if bl<=bb or bsz<MIN_SIZE or lsz<MIN_SIZE or bl>MAX_PRICE or nticks(bb,bl)>MAX_SPREAD: continue
114:                    try: sto=(datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00'))-datetime.datetime.now(datetime.timezone.utc)).total_seconds()
135:        # settlement: filled v2 rows whose market is CLOSED
136:        lc.execute("SELECT DISTINCT market_id FROM bookie_paper WHERE version=%s AND status='filled'",(VERSION,)); due=[m for (m,) in lc.fetchall()][:40]; settled=0
138:            for b in api('listMarketBook',{"marketIds":due}):
144:                    if s not in ('WINNER','LOSER'): lc.execute("UPDATE bookie_paper SET status='unsettleable', settled_ts=now() WHERE id=%s",(oid,)); continue
145:                    fp=float(fp); stk=float(stk); won=1 if s=='WINNER' else 0
146:                    gross=((fp-1)*stk if won else -stk) if side=='BACK' else (-(fp-1)*stk if won else stk)
147:                    pnl=gross*(1-COMM) if gross>0 else gross
148:                    lc.execute("UPDATE bookie_paper SET status='settled', won=%s, pnl=%s, settled_ts=now() WHERE id=%s",(won,round(pnl,4),oid)); settled+=1
149:        lc.execute("SELECT count(*) FILTER (WHERE status='open'), count(*) FILTER (WHERE status IN ('filled','settled')) FROM bookie_paper WHERE version=%s",(VERSION,)); o,fl=lc.fetchone()
151:        if quoted or filled or settled: log(f"[{MODE}] universe {len(cat)} books {len(books)} bets {quoted} filled {filled} settled {settled} open {o}")
```
## liq_sample columns: ['ts', 'market_id', 'event_name', 'competition', 'mkt', 'sel', 'minute', 'ltp', 'back_px', 'back_sz', 'lay_px', 'lay_sz', 'back3_sz', 'lay3_sz', 'total_matched']
## stream_ticks columns: ['ts_recv', 'pt', 'latency_ms', 'market_id', 'sport', 'mkt', 'sel_id', 'sel', 'back_px', 'back_sz', 'lay_px', 'lay_sz', 'back2_px', 'lay2_px', 'ltp', 'tv', 'inplay', 'status', 'secs_to_off']
## bookie_paper columns: ['id', 'ts', 'market_id', 'event_name', 'mkt', 'sel', 'side', 'price', 'fair', 'mkt_back', 'mkt_lay', 'stake', 'status', 'fill_ts', 'fill_price', 'fill_kind', 'won', 'pnl', 'settled_ts', 'start_ts', 'version', 'exchange', 'bf_market_id']
## fair_price_passed columns: ['sport', 'market_type', 'band_lo', 'band_hi', 'side', 'fair_factor', 'n_is', 'n_oos', 'edge_is', 'edge_oos', 'source', 'passed_at']
## bf_hist_result columns: ['sport', 'market_id', 'event_id', 'market_type', 'sel', 'status', 'settled_time', 'market_status']
## market_results columns: []
## bf_results columns: []
## mkt_results columns: []
## liq_sample range + market types: [(datetime.date(2026, 11, 11), datetime.date(2026, 11, 16))] [('CS', 857), ('OU35', 854), ('MO', 852), ('OU45', 851), ('AH', 851), ('OU25', 850), ('DC', 849), ('OU55', 848), ('OU15', 848), ('FH15', 847), ('OU05', 847), ('DNB', 847), ('BTTS', 846), ('FH05', 845), ('FH25', 841), ('HT_MO', 838), ('HT_CS', 832), ('HTFT', 820), ('MOBTTS', 738), ('MOOU25', 737), ('HWTN', 722), ('AWTN', 720), ('RED', 20), ('BOOK_MO', 20), ('CORN_MO', 20)]
## stream_ticks range + sports: [(datetime.date(2026, 11, 11), datetime.date(2026, 11, 16))] [('football', 7696), ('tennis', 406), ('racing', 125)]
## sample liq_sample row: [(datetime.datetime(2026, 11, 16, 15, 27, 1, 841072, tzinfo=datetime.timezone.utc), '1.265603356', 'VfB Stuttgart (W) v Leverkusen (W)', 'German Frauen-Bundesliga', 'MOOU25', 'DRAW/OVER 2.5 GOALS', 0, None, Decimal('11.5'), Decimal('25.54'), Decimal('14.0'), Decimal('22.78'), Decimal('88.33'), Decimal('22.880000000000003'), Decimal('0.0'))]
## sample stream_ticks row: [(datetime.datetime(2026, 11, 16, 15, 28, 12, 215577, tzinfo=datetime.timezone.utc), datetime.datetime(2026, 11, 16, 15, 28, 12, 164000, tzinfo=datetime.timezone.utc), 51, '1.265612743', 'tennis', 'MO', 41716022, 'Antoine Ghibaudo', Decimal('2.02'), Decimal('53.81'), Decimal('2.04'), Decimal('13.93'), Decimal('2'), Decimal('2.06'), Decimal('2.02'), Decimal('20562.18'), True, 'OPEN', -4992)]
## passed cells: [('Cricket', 'MATCH_ODDS', Decimal('0.5'), Decimal('0.55'), 'LAY'), ('Cricket', 'MATCH_ODDS', Decimal('0.45'), Decimal('0.5'), 'BACK'), ('Greyhound Racing', 'WIN', Decimal('0.5'), Decimal('0.55'), 'LAY'), ('Horse Racing', 'WIN', Decimal('0.5'), Decimal('0.55'), 'LAY'), ('Soccer', 'BOTH_TEAMS_TO_SCORE', Decimal('0.3'), Decimal('0.35'), 'BACK'), ('Soccer', 'BOTH_TEAMS_TO_SCORE', Decimal('0.65'), Decimal('0.7'), 'LAY'), ('Soccer', 'CLEAN_SHEET', Decimal('0.7'), Decimal('0.8'), 'LAY'), ('Soccer', 'CORRECT_SCORE', Decimal('0.2'), Decimal('0.25'), 'BACK'), ('Soccer', 'DOUBLE_CHANCE', Decimal('0.25'), Decimal('0.3'), 'LAY'), ('Soccer', 'FIRST_GOAL_SCORER', Decimal('0.1'), Decimal('0.15'), 'LAY'), ('Soccer', 'FIRST_HALF_GOALS_05', Decimal('0.4'), Decimal('0.45'), 'BACK'), ('Soccer', 'FIRST_HALF_GOALS_05', Decimal('0.55'), Decimal('0.6'), 'LAY'), ('Soccer', 'FIRST_HALF_GOALS_25', Decimal('0.03'), Decimal('0.06'), 'LAY'), ('Soccer', 'HALF_TIME', Decimal('0.65'), Decimal('0.7'), 'LAY'), ('Soccer', 'HALF_TIME', Decimal('0.6'), Decimal('0.65'), 'BACK'), ('Soccer', 'HALF_TIME_FULL_TIME', Decimal('0.3'), Decimal('0.35'), 'BACK'), ('Soccer', 'HALF_TIME_FULL_TIME', Decimal('0.45'), Decimal('0.5'), 'BACK'), ('Soccer', 'HALF_TIME_FULL_TIME', Decimal('0.4'), Decimal('0.45'), 'LAY'), ('Soccer', 'HALF_TIME_FULL_TIME', Decimal('0.35'), Decimal('0.4'), 'BACK'), ('Soccer', 'OVER_UNDER_45', Decimal('0.9'), Decimal('1.0001'), 'LAY')]
## bookie_paper settled sample: [('1.265400819', 'BOTH_TEAMS_TO_SCORE', 'LAY', Decimal('1.53'), Decimal('2.0'), 'settled', 0, Decimal('1.96'), datetime.datetime(2026, 11, 16, 13, 0, tzinfo=datetime.timezone.utc), datetime.datetime(2026, 11, 16, 14, 21, 20, 427963, tzinfo=datetime.timezone.utc)), ('1.265562639', 'WIN', 'LAY', Decimal('1.95'), Decimal('2.0'), 'settled', 0, Decimal('1.96'), datetime.datetime(2026, 11, 16, 13, 42, tzinfo=datetime.timezone.utc), datetime.datetime(2026, 11, 16, 13, 45, 25, 795802, tzinfo=datetime.timezone.utc)), ('1.265576530', 'WIN', 'LAY', Decimal('1.84'), Decimal('2.0'), 'settled', 0, Decimal('1.96'), datetime.datetime(2026, 11, 16, 12, 15, tzinfo=datetime.timezone.utc), datetime.datetime(2026, 11, 16, 12, 17, 5, 172635, tzinfo=datetime.timezone.utc))]
## tables with 'result' in the name: [('fair_price_results',), ('v4_fin_results',), ('boring_results_v3',), ('bf_hist_result',), ('goal_backtest_results',), ('job_results',), ('boring_results_v2',), ('hist_scan_results',), ('v4_stats_results',), ('boring_results',), ('poisson_gap_results',), ('fts_advanced_results',), ('finder_rresults',), ('robustness_results',), ('strategy_results',), ('v4_sport_results_sub',), ('tb_cricket_results',), ('v4_sport_results',), ('backtest_results',), ('tb_tennis_results',), ('golf_market_results',), ('tennis_market_results',), ('tb_results',), ('v4_af_results',), ('racing_results',), ('cricket_market_results',), ('pe_backtest_results',), ('event_results',), ('summer_match_results',), ('tennis_results_2026',), ('betfair_probe_results',)]

## archive files by table (tape held off the database)
/root/pe-archive/__pycache__/ 2 files archive_tape.cpython-312.pyc .. offbox.cpython-312.pyc
/root/pe-archive/ip_tape/ 11 files 2026-10-31.csv.zst .. 2026-11-10.csv.zst
/root/pe-archive/liq_sample/ 11 files 2026-10-31.csv.zst .. 2026-11-10.csv.zst
/root/pe-archive/stream_ticks/ 9 files 2026-11-02.csv.zst .. 2026-11-10.csv.zst
/root/pe-archive/tables/ 17 files public.af_events.sql.zst .. public.xx_ip_331.sql.zst
/root/pe-archive/xx_tape/ 8 files 2026-11-03.csv.zst .. 2026-11-10.csv.zst
