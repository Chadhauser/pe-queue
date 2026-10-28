#!/bin/bash
# 280: (a) size verdict so far: traded-through fills are adversely selected (£200 book 139 rounds -£9.5/£10-equiv; £50 -£7.0;
#     £10 touch 269 rounds -£0.3) -> size books keep running for the record, but the desk's answer is quote quality, not size.
# (b) BOOK v1 — the KPI-derived rule as its own paper book '10v1': quote only inside 120 s, rank-1 runner only, spread >= 3
#     ticks, turf only (all-weather venues excluded). Out-of-sample test of yesterday's cut.
# (c) the MM script becomes generic via env: MM_SPORT, MM_WINDOW, MM_FLAT, MM_RANK, MM_MINSPREAD, MM_EXCL (venue substrings),
#     MM_OKST (statuses allowed) — the same engine will run the tennis and football pre-match books (281).
set -e
python3 - <<'PY'
p='/root/pe-race/race_mm_size.py'; s=open(p).read(); o=s
s=s.replace("WINDOW=480; FLAT_AT=20; MIN_SPREAD=2;","WINDOW=int(os.environ.get('MM_WINDOW','480')); FLAT_AT=int(os.environ.get('MM_FLAT','20')); MIN_SPREAD=int(os.environ.get('MM_MINSPREAD','2')); SPORT=os.environ.get('MM_SPORT','racing'); RANKMAX=int(os.environ.get('MM_RANK','2')); EXCL=[x for x in os.environ.get('MM_EXCL','').lower().split(',') if x]; OKST=os.environ.get('MM_OKST','OPEN').split(',');",1)
# the 'import os' must precede: it is on the STAKE line which comes after WINDOW line in the original -> move import to top
s=s.replace("import sys, time, datetime, psycopg2, psycopg2.extras","import sys, os, re, time, datetime, psycopg2, psycopg2.extras",1)
s=s.replace("STAKE=float(BOOK.rstrip('through').rstrip('touch') or 10);","STAKE=float(re.match(r'\\d+',BOOK).group(0)) if re.match(r'\\d+',BOOK) else 10.0;",1)
s=s.replace("FROM stream_ticks WHERE sport='racing' AND ts_recv > %s","FROM stream_ticks WHERE sport=%s AND ts_recv > %s",1)
s=s.replace("FROM stream_ticks WHERE sport='racing' AND ts_recv>now()-interval '3 minutes'","FROM stream_ticks WHERE sport=%s AND ts_recv>now()-interval '3 minutes'",1)
s=s.replace("WHERE rk.rank<=2 ORDER BY t.ts\"\"\",(last_ts or datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=5),))",
            "WHERE rk.rank<=%s ORDER BY t.ts\"\"\",(SPORT,last_ts or datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(seconds=5),SPORT,RANKMAX))",1)
s=s.replace("if st!='OPEN' or sto<=FLAT_AT:","if st not in OKST or sto<=FLAT_AT:",1)
s=s.replace("if st!='OPEN' or sto>WINDOW or sto<=FLAT_AT+5: continue","if st not in OKST or sto>WINDOW or sto<=FLAT_AT+5: continue\n            if EXCL and any(x in (venue or '').lower() for x in EXCL): continue",1)
for a in ["sport=%s AND ts_recv > %s","rk.rank<=%s","st not in OKST or sto<=FLAT_AT","any(x in (venue or '').lower()","RANKMAX=int"]: assert a in s, "anchor missing: "+a
open(p,'w').write(s); print("generic MM engine written")
PY
python3 -m py_compile /root/pe-race/race_mm_size.py
# heartbeat ids per book
python3 - <<'PY'
p='/root/pe-race/race_mm_size.py'; s=open(p).read()
s=s.replace("HB_ID={'50through':2,'200through':3}.get(BOOK,2);","HB_ID={'50through':2,'200through':3,'10v1':4,'tennis10':5,'footpre10':6}.get(BOOK,2);",1); open(p,'w').write(s)
PY
python3 -m py_compile /root/pe-race/race_mm_size.py
cat > /root/pe-race/keepalive_mm_size.sh <<'SH'
#!/bin/bash
cd /root/pe-race
pgrep -f "race_mm_size.py 50through" >/dev/null || nohup python3 race_mm_size.py 50through >> mm_size50.log 2>&1 &
pgrep -f "race_mm_size.py 200through" >/dev/null || nohup python3 race_mm_size.py 200through >> mm_size200.log 2>&1 &
pgrep -f "race_mm_size.py 10v1" >/dev/null || MM_WINDOW=120 MM_RANK=1 MM_MINSPREAD=3 MM_EXCL="wolverhampton,kempton,lingfield,southwell,chelmsford,newcastle,dundalk" nohup python3 race_mm_size.py 10v1 >> mm_v1.log 2>&1 &
SH
chmod +x /root/pe-race/keepalive_mm_size.sh
# restart the two size books on the new engine (their rules unchanged: env defaults = old constants)
pkill -f "race_mm_size.py 50through" || true; pkill -f "race_mm_size.py 200through" || true; sleep 2
/root/pe-race/keepalive_mm_size.sh; sleep 20; echo "processes (expect 3):"; pgrep -af race_mm_size.py
# 10v1 fills on touch like the £10 book: it quotes £10 so STAKE parses to 10; but it inherited the traded-through rule from the size copy -> switch by env
python3 - <<'PY'
p='/root/pe-race/race_mm_size.py'; s=open(p).read()
s=s.replace("if ltp>=up(q['bk'])-1e-9:   # traded THROUGH our back","if ltp>=(up(q['bk']) if THROUGH else q['bk'])-1e-9:   # traded THROUGH our back (size books) or touched (£10 books)",1)
s=s.replace("elif ltp<=down(q['ly'])+1e-9:","elif ltp<=(down(q['ly']) if THROUGH else q['ly'])+1e-9:",1)
s=s.replace("if q['first']=='BACK' and ltp<=down(q['ly'])+1e-9:","if q['first']=='BACK' and ltp<=(down(q['ly']) if THROUGH else q['ly'])+1e-9:",1)
s=s.replace("if q['first']=='LAY' and ltp>=up(q['bk'])-1e-9:","if q['first']=='LAY' and ltp>=(up(q['bk']) if THROUGH else q['bk'])-1e-9:",1)
s=s.replace(".get(BOOK,2);",".get(BOOK,2); THROUGH=BOOK.endswith('through');",1)
assert s.count("if THROUGH else")==4 and "THROUGH=BOOK" in s; open(p,'w').write(s); print("touch/through by book name")
PY
python3 -m py_compile /root/pe-race/race_mm_size.py
pkill -f race_mm_size.py || true; sleep 2; /root/pe-race/keepalive_mm_size.sh; sleep 15; echo "processes after final restart (expect 3):"; pgrep -af race_mm_size.py; tail -n 2 /root/pe-race/mm_v1.log || true
