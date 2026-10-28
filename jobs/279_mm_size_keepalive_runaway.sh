#!/bin/bash
# 279: RUNAWAY — keepalive_mm_size.sh matched processes by an env var that is not in the command line (env ... python3 execs),
# so every minute it started two more size-book processes (3 seen at 09:38). Kill them all, pass the book on argv so pgrep
# can see it, restart exactly one per book, verify counts.
set -e
echo "processes before: $(pgrep -fc race_mm_size.py || true)"
pkill -f race_mm_size.py || true; sleep 3; echo "after kill: $(pgrep -fc race_mm_size.py || true)"
python3 - <<'PY'
p='/root/pe-race/race_mm_size.py'; s=open(p).read()
old="import os; STAKE=float(os.environ.get('MM_STAKE','10')); BOOK=os.environ.get('MM_BOOK','10touch'); HB_ID=int(os.environ.get('MM_HB','2'));"
new="import os; BOOK=(sys.argv[1] if len(sys.argv)>1 else os.environ.get('MM_BOOK','10touch')); STAKE=float(BOOK.rstrip('through').rstrip('touch') or 10); HB_ID={'50through':2,'200through':3}.get(BOOK,2);"
assert old in s, "env anchor missing"; s=s.replace(old,new,1); open(p,'w').write(s); print("argv book")
PY
python3 -m py_compile /root/pe-race/race_mm_size.py
cat > /root/pe-race/keepalive_mm_size.sh <<'SH'
#!/bin/bash
cd /root/pe-race
pgrep -f "race_mm_size.py 50through" >/dev/null || nohup python3 race_mm_size.py 50through >> mm_size50.log 2>&1 &
pgrep -f "race_mm_size.py 200through" >/dev/null || nohup python3 race_mm_size.py 200through >> mm_size200.log 2>&1 &
SH
chmod +x /root/pe-race/keepalive_mm_size.sh
/root/pe-race/keepalive_mm_size.sh; sleep 5; /root/pe-race/keepalive_mm_size.sh; sleep 5
echo "processes now (expect 2):"; pgrep -af race_mm_size.py
# duplicate rows written by the runaway copies: keep one per (book, market, sel, quoted_ts)
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require'); c.autocommit=True; k=c.cursor()
k.execute("DELETE FROM racing_mm_stream a USING racing_mm_stream b WHERE a.book=b.book AND a.market_id=b.market_id AND a.sel_id=b.sel_id AND a.quoted_ts=b.quoted_ts AND a.id>b.id AND a.book<>'10touch'"); print("duplicate size-book rows removed:",k.rowcount)
k.execute("SELECT book, count(*) FROM racing_mm_stream GROUP BY 1"); print(k.fetchall())
PY
