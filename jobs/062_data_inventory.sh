#!/bin/bash
# 062: FULL DATA INVENTORY — every table in Postgres with row count, first/last timestamp (if any timestamp column) and size, so
# "are you analysing all the data" has a checklist: what is held, what has been scanned (job number), what has not. Also looks
# for the 164,900-runner racing history (BSP+result, Jan 2022-Mar 2026) by any name, and for greyhound/golf/cricket tape tables.
cd /root && python3 - <<'PY'
import sys, psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor()
cur.execute("""SELECT c.relname, c.reltuples::bigint, pg_size_pretty(pg_total_relation_size(c.oid)) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind IN ('r','m') ORDER BY pg_total_relation_size(c.oid) DESC""")
tabs=cur.fetchall(); print(f"{len(tabs)} tables")
cur.execute("SELECT table_name, column_name, data_type FROM information_schema.columns WHERE table_schema='public'"); cols={}
for t,c,d in cur.fetchall(): cols.setdefault(t,[]).append((c,d))
for t,n,sz in tabs:
    tcol=next((c for c,d in cols.get(t,[]) if d.startswith('timestamp') or d=='date'),None)
    rng=''
    if tcol and n>0:
        try: cur.execute(f'SELECT min("{tcol}")::date, max("{tcol}")::date FROM "{t}"'); a,b=cur.fetchone(); rng=f"{a} -> {b} ({tcol})"
        except Exception as e: con.rollback(); rng='?'
    print(f"{t:40s} {n:>12,d} {sz:>9s}  {rng}")
print("\n--- tables with bsp/sp + result-like columns (racing history candidates):")
for t,cl in cols.items():
    names={c for c,_ in cl}
    if ({'bsp','sp','bsp_win','starting_price'} & names) and ({'won','win','result','position','pos','finish'} & {x.lower() for x in names}): print(" ",t,sorted(names)[:14])
print("\n--- tables mentioning greyhound/golf/cricket/tennis/basket in name or columns:")
for t,cl in cols.items():
    s=(t+' '+' '.join(c for c,_ in cl)).lower()
    if any(k in s for k in ('greyhound','grey','golf','cricket','tennis','basket','sport')): print(" ",t)
PY
echo "--- files on disk that could be the 164,900-runner history:"; find /root -maxdepth 3 \( -iname "*racing*" -o -iname "*runner*" -o -iname "*bsp*" \) -size +1M 2>/dev/null | head -20
