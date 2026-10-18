#!/bin/bash
# 105: PETER'S REAL FILLS, AUTOMATIC. Nightly 23:30 pull of settled bets from Betfair listClearedOrders (last 7 days, SETTLED,
# grouped by bet) into bf_cleared; then match each M1 alert (m1_alerts, entry_sent not null) to his bets on the same market_id
# within -2/+15 min of the alert -> m1_alerts gets actual_entry, actual_exit, actual_pnl, slippage. Also runs once now.
mkdir -p /root/pe-report && cat > /root/pe-report/cleared_sync.py <<'PYFILE'
import sys, datetime, requests, psycopg2, psycopg2.extras
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
sys.path.insert(0,'/root/pe-queue/runner'); import creds
APP,U,P=creds.betfair()
r=requests.post("https://identitysso.betfair.com/api/login",data={"username":U,"password":P},headers={"X-Application":APP,"Accept":"application/json"},timeout=15).json()
TOK=r['token']; H={"X-Authentication":TOK,"X-Application":APP,"Content-Type":"application/json"}
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS bf_cleared (bet_id TEXT PRIMARY KEY, market_id TEXT, event_type_id TEXT, selection_id BIGINT, side TEXT, placed_date TIMESTAMPTZ, settled_date TIMESTAMPTZ,
  price_requested NUMERIC, price_matched NUMERIC, size_settled NUMERIC, profit NUMERIC, commission NUMERIC, bet_outcome TEXT, raw JSONB);
  ALTER TABLE m1_alerts ADD COLUMN IF NOT EXISTS actual_entry NUMERIC; ALTER TABLE m1_alerts ADD COLUMN IF NOT EXISTS actual_exit NUMERIC;
  ALTER TABLE m1_alerts ADD COLUMN IF NOT EXISTS actual_pnl NUMERIC; ALTER TABLE m1_alerts ADD COLUMN IF NOT EXISTS actual_stake NUMERIC""")
now=datetime.datetime.now(datetime.timezone.utc); frm=now-datetime.timedelta(days=7)
rows=[]; i=0
while True:
    body={"betStatus":"SETTLED","settledDateRange":{"from":frm.isoformat().replace('+00:00','Z'),"to":now.isoformat().replace('+00:00','Z')},"groupBy":"BET","includeItemDescription":True,"fromRecord":i,"recordCount":1000}
    res=requests.post("https://api.betfair.com/exchange/betting/rest/v1.0/listClearedOrders/",json=body,headers=H,timeout=30).json()
    items=res.get('clearedOrders',[])
    for o in items:
        rows.append((o['betId'],o.get('marketId'),o.get('eventTypeId'),o.get('selectionId'),o.get('side'),o.get('placedDate'),o.get('settledDate'),o.get('priceRequested'),o.get('priceMatched'),o.get('sizeSettled'),o.get('profit'),o.get('commission'),o.get('betOutcome'),psycopg2.extras.Json(o)))
    if not res.get('moreAvailable'): break
    i+=len(items)
if rows: psycopg2.extras.execute_values(cur,"INSERT INTO bf_cleared VALUES %s ON CONFLICT (bet_id) DO UPDATE SET profit=EXCLUDED.profit, settled_date=EXCLUDED.settled_date",rows)
print("cleared bets pulled (7d):",len(rows))
cur.execute("SELECT event_type_id, count(*), round(sum(profit)::numeric,2), round(sum(commission)::numeric,2) FROM bf_cleared WHERE settled_date>now()-interval '7 days' GROUP BY 1"); print("by sport (7d): n, profit, commission:",cur.fetchall())
# match M1 alerts to his bets
cur.execute("SELECT id, market_id, entry_sent, exit_sent FROM m1_alerts WHERE entry_sent IS NOT NULL")
for aid,mid,es,xs in cur.fetchall():
    cur.execute("""SELECT side, price_matched, size_settled, profit FROM bf_cleared WHERE market_id=%s AND placed_date BETWEEN %s AND %s ORDER BY placed_date""",(mid,es-datetime.timedelta(minutes=2),(xs or es)+datetime.timedelta(minutes=15)))
    bets=cur.fetchall()
    if not bets: continue
    lay=[b for b in bets if b[0]=='LAY']; back=[b for b in bets if b[0]=='BACK']
    cur.execute("UPDATE m1_alerts SET actual_entry=%s, actual_exit=%s, actual_stake=%s, actual_pnl=%s WHERE id=%s",
                (lay[0][1] if lay else None, back[0][1] if back else None, lay[0][2] if lay else None, sum(float(b[3] or 0) for b in bets), aid))
cur.execute("SELECT event_name, minute, team, entry_px, exit_px, actual_entry, actual_exit, actual_pnl FROM m1_alerts WHERE entry_sent IS NOT NULL ORDER BY entry_sent"); print("M1 paper vs actual:",cur.fetchall())
PYFILE
python3 -m py_compile /root/pe-report/cleared_sync.py || exit 1
( crontab -l 2>/dev/null | grep -v cleared_sync ; echo "30 23 * * * cd /root/pe-report && python3 cleared_sync.py >> cleared_sync.log 2>&1" ) | crontab -
cd /root/pe-report && python3 cleared_sync.py
