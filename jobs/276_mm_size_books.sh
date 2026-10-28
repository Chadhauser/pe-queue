#!/bin/bash
# 276: BOOK 1 SIZE TEST (Peter 28 Oct: "lets say we traded £200 per race"). The racing market-maker runs three paper books on the
# same live stream: '10touch' (existing: £10, filled when LTP touches our price), '50through' and '200through' (£50/£200, filled
# only when the market trades THROUGH our price by a tick — the honest rule for size, since a big quote is not first in the queue).
# Same table, new column 'book'; each process tags its rows via a session setting + trigger. Report per book: rounds, capture
# rate, adverse rate, net ticks/round, P&L per £10 of stake.
set -e
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; k=c.cursor()
k.execute("ALTER TABLE racing_mm_stream ADD COLUMN IF NOT EXISTS book TEXT DEFAULT '10touch'")
k.execute("""CREATE OR REPLACE FUNCTION mm_set_book() RETURNS trigger AS $$ BEGIN
  IF current_setting('mm.book', true) IS NOT NULL AND current_setting('mm.book', true)<>'' THEN NEW.book := current_setting('mm.book', true); END IF; RETURN NEW; END $$ LANGUAGE plpgsql""")
k.execute("DROP TRIGGER IF EXISTS mm_book_trg ON racing_mm_stream; CREATE TRIGGER mm_book_trg BEFORE INSERT ON racing_mm_stream FOR EACH ROW EXECUTE FUNCTION mm_set_book()")
print("book column + trigger ready")
PY
python3 - <<'PY'
src=open('/root/pe-race/race_mm_stream.py').read()
s=src.replace("STAKE=10.0;","import os; STAKE=float(os.environ.get('MM_STAKE','10')); BOOK=os.environ.get('MM_BOOK','10touch');",1)
s=s.replace("con=connect(); cur=con.cursor()","con=connect(); cur=con.cursor(); cur.execute(\"SET mm.book=%s\",(BOOK,))",1)
# traded-through fills: one tick beyond our price
s=s.replace("if ltp>=q['bk']-1e-9:   # our back got hit","if ltp>=up(q['bk'])-1e-9:   # traded THROUGH our back",1)
s=s.replace("elif ltp<=q['ly']+1e-9:","elif ltp<=down(q['ly'])+1e-9:",1)
s=s.replace("if q['first']=='BACK' and ltp<=q['ly']+1e-9:","if q['first']=='BACK' and ltp<=down(q['ly'])+1e-9:",1)
s=s.replace("if q['first']=='LAY' and ltp>=q['bk']-1e-9:","if q['first']=='LAY' and ltp>=up(q['bk'])-1e-9:",1)
# heartbeat: own row per book so the watchdog sees each process
s=s.replace("INSERT INTO racing_mm_stream_hb VALUES (1,","INSERT INTO racing_mm_stream_hb VALUES (%s,",1)
assert s.count("up(q['bk'])")==2 and s.count("down(q['ly'])")==2 and "mm.book" in s, "fill anchors missing"
open('/root/pe-race/race_mm_size.py','w').write(s); print("race_mm_size.py written")
PY
grep -n "racing_mm_stream_hb VALUES" /root/pe-race/race_mm_size.py | cut -c1-200
python3 - <<'PY'
# the hb INSERT now has one extra %s at the front: add the book id (2 for 50, 3 for 200) to its params
p='/root/pe-race/race_mm_size.py'; s=open(p).read()
import re
m=re.search(r'INSERT INTO racing_mm_stream_hb VALUES \(%s,now\(\),%s,\(SELECT count\(\*\) FROM racing_mm_stream WHERE quoted_ts::date=current_date AND exit_reason IS NOT NULL\)\) ON CONFLICT \(id\) DO UPDATE[^"]*",\(',s)
assert m, "hb params anchor missing"
s=s[:m.end()]+"HB_ID,"+s[m.end():]
s=s.replace("BOOK=os.environ.get('MM_BOOK','10touch');","BOOK=os.environ.get('MM_BOOK','10touch'); HB_ID=int(os.environ.get('MM_HB','2'));",1)
s=s.replace("WHERE quoted_ts::date=current_date AND exit_reason IS NOT NULL)","WHERE quoted_ts::date=current_date AND exit_reason IS NOT NULL AND book=current_setting('mm.book',true))",1)
open(p,'w').write(s); print("hb per book")
PY
python3 -m py_compile /root/pe-race/race_mm_size.py
cat > /root/pe-race/keepalive_mm_size.sh <<'SH'
#!/bin/bash
cd /root/pe-race
pgrep -f "MM_BOOK=50through" >/dev/null || (MM_STAKE=50 MM_BOOK=50through MM_HB=2 nohup env MM_BOOK=50through python3 race_mm_size.py >> mm_size50.log 2>&1 &)
pgrep -f "MM_BOOK=200through" >/dev/null || (MM_STAKE=200 MM_BOOK=200through MM_HB=3 nohup env MM_BOOK=200through python3 race_mm_size.py >> mm_size200.log 2>&1 &)
SH
chmod +x /root/pe-race/keepalive_mm_size.sh
( crontab -l 2>/dev/null | grep -v keepalive_mm_size ; echo "* * * * * /root/pe-race/keepalive_mm_size.sh" ) | crontab -
/root/pe-race/keepalive_mm_size.sh; sleep 45; pgrep -af race_mm_size.py; tail -3 /root/pe-race/mm_size50.log /root/pe-race/mm_size200.log
cat > /root/pe-race/mm_report.py <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
k=psycopg2.connect(DB,sslmode='require').cursor()
k.execute("""SELECT book, count(*) rounds, count(*) FILTER (WHERE exit_reason='CAPTURED') captured, count(*) FILTER (WHERE exit_reason IN ('STOP','FLAT_PRE_OFF') OR exit_reason LIKE 'MARKET_%') adverse,
             count(*) FILTER (WHERE exit_reason IN ('UNFILLED','PULLED')) unfilled, round(avg(ticks),2) net_ticks, round(sum(pnl_per_10),2) pnl_at_book_stake, round(sum(pnl_per_10)*10/CASE book WHEN '50through' THEN 50 WHEN '200through' THEN 200 ELSE 10 END,2) pnl_per_10_equiv, round(avg(pnl_per_10)*10/CASE book WHEN '50through' THEN 50 WHEN '200through' THEN 200 ELSE 10 END,3) per_round_per_10
             FROM racing_mm_stream WHERE exit_reason IS NOT NULL GROUP BY 1 ORDER BY 1"""); [print(r) for r in k.fetchall()]
PY
python3 /root/pe-race/mm_report.py
