#!/bin/bash
# 537: BUG (mine) found 16 Nov 14:00 UTC. The server clock is CET, so the ORB and K2 paper bots start at 07:20/07:25 New York time
# and ask Alpaca "is the market open?" — at that hour the answer is NO (it opens 09:30), so both bots logged "market closed"
# and quit. No paper trades today so far. Fix: ask Alpaca's trading CALENDAR whether today is a trading day instead.
# Then clear today's false "market closed" record and relaunch both bots now so they still catch today's 09:31/09:35 ET open.
cd /root/pe-fin/bot || exit 1
python3 - <<'PY'
import re
for f in ('orb_alpaca_bot.py','k2_gapfade_bot.py'):
    s=open(f).read()
    if 'TRADING_DAY_CHECK' in s: print(f,'already fixed'); continue
    s=re.sub(r"sc,clk=api\('GET','/clock'\)\n(\s+)if sc==200 and not clk.get\('is_open'\):",
             r"sc,cal=api('GET','/calendar',params={'start':str(today),'end':str(today)})  # TRADING_DAY_CHECK\n\1if sc==200 and not any(c.get('date')==str(today) for c in (cal or [])):",s)
    open(f,'w').write(s); print(f,'patched' if 'TRADING_DAY_CHECK' in s else 'PATCH FAILED')
import json,datetime as dt,zoneinfo
t=str(dt.datetime.now(zoneinfo.ZoneInfo('America/New_York')).date())
for p in ('bot_trades.json','k2_trades.json'):
    try: d=json.load(open(p))
    except Exception: continue
    n=len(d); d=[x for x in d if not (x.get('date')==t and (x.get('note')=='market closed' or not x.get('legs') and 'note' in x))]
    json.dump(d,open(p,'w'),indent=1); print(p,'removed',n-len(d),'false entries for',t)
PY
python3 -m py_compile orb_alpaca_bot.py k2_gapfade_bot.py || exit 1
grep -n "TRADING_DAY_CHECK" orb_alpaca_bot.py k2_gapfade_bot.py
pgrep -f orb_alpaca_bot.py >/dev/null || (nohup /usr/bin/python3 orb_alpaca_bot.py >> cron.log 2>&1 &)
pgrep -f k2_gapfade_bot.py >/dev/null || (nohup /usr/bin/python3 k2_gapfade_bot.py >> k2_cron.log 2>&1 &)
sleep 5; echo "running:"; pgrep -af "orb_alpaca_bot|k2_gapfade_bot"; tail -2 orb_alpaca.log; tail -2 k2.log 2>/dev/null
echo "tz: $(date) | NY $(TZ=America/New_York date +%H:%M)"
echo "DONE 537"
