# After-upgrade money jobs 2026-11-16 16:12 UTC (job 615)

## 1. In-play fair-price engine
```
Soccer exit 1 RESULT lines 0
Tennis exit 1 RESULT lines 0
Cricket exit 1 RESULT lines 0
Horse Racing exit 1 RESULT lines 0
Greyhound Racing exit 1 RESULT lines 0
  print(f"{datetime.datetime.utcnow():%Y-%m-%d %H:%M} passed cells: {n} (fair_factor BETWEEN 0.7 AND 1.3 enforced)"); [print("  ",r) for r in c.fetchall()]
cells dropped by the replay (negative on real books): 0
2026-11-16 16:37 passed cells: 20 (fair_factor BETWEEN 0.7 AND 1.3 enforced)
   ('Cricket', 'MATCH_ODDS', Decimal('0.45'), Decimal('0.5'), 'BACK', 372, Decimal('0.0217'), Decimal('0.0108'))
   ('Cricket', 'MATCH_ODDS', Decimal('0.5'), Decimal('0.55'), 'LAY', 410, Decimal('-0.0172'), Decimal('-0.0079'))
   ('Greyhound Racing', 'WIN', Decimal('0.5'), Decimal('0.55'), 'LAY', 387, Decimal('-0.0641'), Decimal('-0.0315'))
   ('Horse Racing', 'WIN', Decimal('0.5'), Decimal('0.55'), 'LAY', 348, Decimal('-0.0262'), Decimal('-0.0244'))
   ('Soccer', 'BOTH_TEAMS_TO_SCORE', Decimal('0.3'), Decimal('0.35'), 'BACK', 2400, Decimal('0.0206'), Decimal('0.0069'))
   ('Soccer', 'BOTH_TEAMS_TO_SCORE', Decimal('0.65'), Decimal('0.7'), 'LAY', 2460, Decimal('-0.0197'), Decimal('-0.0073'))
   ('Soccer', 'CLEAN_SHEET', Decimal('0.7'), Decimal('0.8'), 'LAY', 576, Decimal('-0.0169'), Decimal('-0.0058'))
   ('Soccer', 'CORRECT_SCORE', Decimal('0.2'), Decimal('0.25'), 'BACK', 765, Decimal('0.0233'), Decimal('0.0135'))
   ('Soccer', 'DOUBLE_CHANCE', Decimal('0.25'), Decimal('0.3'), 'LAY', 1054, Decimal('-0.0195'), Decimal('-0.0067'))
   ('Soccer', 'FIRST_GOAL_SCORER', Decimal('0.1'), Decimal('0.15'), 'LAY', 430, Decimal('-0.0221'), Decimal('-0.0162'))
   ('Soccer', 'FIRST_HALF_GOALS_05', Decimal('0.4'), Decimal('0.45'), 'BACK', 1545, Decimal('0.011'), Decimal('0.0263'))
   ('Soccer', 'FIRST_HALF_GOALS_05', Decimal('0.55'), Decimal('0.6'), 'LAY', 1520, Decimal('-0.0106'), Decimal('-0.0276'))
   ('Soccer', 'FIRST_HALF_GOALS_25', Decimal('0.03'), Decimal('0.06'), 'LAY', 407, Decimal('-0.0143'), Decimal('-0.0081'))
   ('Soccer', 'HALF_TIME', Decimal('0.6'), Decimal('0.65'), 'BACK', 599, Decimal('0.016'), Decimal('0.0196'))
   ('Soccer', 'HALF_TIME', Decimal('0.65'), Decimal('0.7'), 'LAY', 342, Decimal('-0.0288'), Decimal('-0.0147'))
   ('Soccer', 'HALF_TIME_FULL_TIME', Decimal('0.3'), Decimal('0.35'), 'BACK', 1818, Decimal('0.0145'), Decimal('0.0085'))
   ('Soccer', 'HALF_TIME_FULL_TIME', Decimal('0.35'), Decimal('0.4'), 'BACK', 1227, Decimal('0.0203'), Decimal('0.023'))
   ('Soccer', 'HALF_TIME_FULL_TIME', Decimal('0.4'), Decimal('0.45'), 'LAY', 814, Decimal('-0.0108'), Decimal('-0.0168'))
   ('Soccer', 'HALF_TIME_FULL_TIME', Decimal('0.45'), Decimal('0.5'), 'BACK', 681, Decimal('0.0334'), Decimal('0.0138'))
   ('Soccer', 'OVER_UNDER_45', Decimal('0.9'), Decimal('1.0001'), 'LAY', 12341, Decimal('-0.0154'), Decimal('-0.0171'))
```
## 2. Restore large dropped tables
```
restored bf_price_log: 18832456 rows
restored bf_racing_log: 9714286 rows
restored bf_tennis_log: 6718240 rows
restored ch_accounts: 903124 rows
restored factory_trades: 2627870 rows
restored finder_rlog: 9498623 rows
restored finder_tlog: 6596035 rows
restored xx_ip_331: 1054112 rows
```
## 3. Loader guard
20:if shutil.disk_usage('/root').free<20e9: print('WAITING: box disk under 20 GB free'); sys.exit(75)
## 4. Stream recorder subscription
```
8:def login():
12:def api(tok,ep,payload):
15:def connect_db():
24:def _passed_types():
29:def refresh_universe(tok):
33:        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["7"],"marketTypeCodes":["WIN"],"marketCountries":["GB","IE"],"marketStartTime":{"from":t0,"to":t1}},"marketProjection":["EV
35:        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["1"],"marketTypeCodes":["MATCH_ODDS","OVER_UNDER_25"],"inPlayOnly":True},"marketProjection":["EVENT","RUNNER_DESCRIPTION","
38:        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["2"],"marketTypeCodes":["MATCH_ODDS"],"inPlayOnly":True},"marketProjection":["EVENT","RUNNER_DESCRIPTION","MARKET_START_TIM
41:        for m in api(tok,'listMarketCatalogue',{"filter":{"eventTypeIds":["1"],"marketTypeCodes":["MATCH_ODDS"],"inPlayOnly":False,"marketStartTime":{"from":t_now,"to":t2}},"marketProjection":["EVE
46:        t0=datetime.datetime.utcnow(); f={"eventTypeIds":["1"],"marketTypeCodes":_passed_types(),"marketStartTime":{"from":t0.strftime('%Y-%m-%dT%H:%M:%SZ'),"to":(t0+datetime.timedelta(hours=2)).st
54:def apply_mc(mc):
72:def best(d,lvl=0): return d.get(lvl,(None,None))
75:def stream_loop():
81:            def send(o): s.sendall((json.dumps(o)+"\r\n").encode())
90:                    state['sub_ids']=set(ids); last_sub=time.time(); print("subscribed",len(ids),"markets",flush=True)
```
/dev/sda1       968G  145G  824G  15% /
               total        used        free      shared  buff/cache   available
Mem:              17           3           0           1          15          14
