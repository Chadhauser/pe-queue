#!/bin/bash
# 642 (Tue 17 Nov 2026, 09:15). PAPER ONLY. Two fixes to the pre-off paper bot (bookie_v2), from today's reports:
#  1. The verifier re-run (639) wrote the 6 pruned losing cells back into fair_price_passed. The bot now skips any cell listed in
#     fair_price_blocked (filled from fair_price_passed_pruned), so a verifier re-run can never bring them back.
#  2. Loser autopsy (629): two filters learned on the OLDER half of history that also lifted the NEWER half:
#     OVER_UNDER_45 LAY: skip when the price shortened 1-5% since first seen (~60 min out) or the country is NL/GR/TR/IT
#       (newer half £+2.3 -> £+3.6 per £100 on 7,831 bets); FIRST_HALF_GOALS_25 LAY: skip kick-offs 12:00-14:59 UTC (£+19.0 -> £+21.5).
#     Filters that did not hold on the newer half are NOT applied. Version -> v2.2 so the record splits.
R=/root/pe-queue/reports/bot_642.md; B=/root/pe-sports/bookie/bookie_v2.py
{ echo "# 642 — $(date -u '+%F %H:%M') UTC"; echo '```'
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); con.autocommit=True; c=con.cursor()
c.execute("CREATE TABLE IF NOT EXISTS fair_price_blocked AS SELECT sport, market_type, band_lo, band_hi, side, now() AS blocked_at, 'loser at tradable price (612), pruned 626'::text AS why FROM fair_price_passed_pruned WHERE false")
c.execute("""INSERT INTO fair_price_blocked SELECT DISTINCT sport, market_type, band_lo, band_hi, side, now(), 'loser at tradable price (612), pruned 626'
             FROM fair_price_passed_pruned p WHERE NOT EXISTS (SELECT 1 FROM fair_price_blocked b WHERE b.sport=p.sport AND b.market_type=p.market_type AND b.side=p.side AND b.band_lo=p.band_lo)""")
c.execute("SELECT sport, market_type, band_lo, band_hi, side FROM fair_price_blocked ORDER BY 2,3"); print("blocked:", c.fetchall())
c.execute("""SELECT count(*) FROM fair_price_passed p WHERE NOT EXISTS (SELECT 1 FROM fair_price_blocked x WHERE x.sport=p.sport AND x.market_type=p.market_type AND x.side=p.side AND x.band_lo=p.band_lo)"""); print("cells the bot will trade:", c.fetchone()[0])
PY
cp $B $B.bak_642
python3 - "$B" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read(); n=0
E=[("lc.execute(\"SELECT sport, market_type, band_lo, band_hi, side, fair_factor FROM fair_price_passed\")",
    "lc.execute(\"SELECT sport, market_type, band_lo, band_hi, side, fair_factor FROM fair_price_passed p WHERE NOT EXISTS (SELECT 1 FROM fair_price_blocked x WHERE x.sport=p.sport AND x.market_type=p.market_type AND x.side=p.side AND x.band_lo=p.band_lo)\")   # 642"),
   ("cat={}; cat_t=0; last_quote={}; C={}; C_t=0", "cat={}; cat_t=0; last_quote={}; C={}; C_t=0; FIRST={}   # 642: first-seen mid per runner (~60 min out)"),
   ("                key=(mid,sid)\n", "                key=(mid,sid); FIRST.setdefault(key,(bb+bl)/2)\n"),
   ("                    if not (0<sto<=TAKE_WINDOW_S): continue\n",
    "                    if not (0<sto<=TAKE_WINDOW_S): continue\n"
    "                    f0=FIRST.get(key,(bb+bl)/2); mv=((bb+bl)/2-f0)/f0; cc=((m.get('event') or {}).get('countryCode') or '')\n"
    "                    hr=datetime.datetime.fromisoformat(m['marketStartTime'].replace('Z','+00:00')).hour\n"
    "                    if mt=='OVER_UNDER_45' and side=='LAY' and (-0.05<mv<-0.01 or cc in ('NL','GR','TR','IT')): continue   # 642 loser autopsy\n"
    "                    if mt=='FIRST_HALF_GOALS_25' and side=='LAY' and 12<=hr<=14: continue   # 642 loser autopsy\n"),
   ("VERSION='v2.1'","VERSION='v2.2'")]
for old,new in E:
    if new.strip() in s: n+=1; continue
    if s.count(old)==1: s=s.replace(old,new); n+=1
    else: print("anchor not found once:", old[:70].replace("\n","\\n"), s.count(old))
if n==len(E): open(p,'w').write(s); print(f"bot patched ({n}/{len(E)})")
else: print(f"only {n}/{len(E)} anchors - bot NOT changed")
PY
python3 -m py_compile $B && echo compiles || { cp $B.bak_642 $B; echo "compile failed - restored"; }
grep -nE "642|VERSION=" $B | head -8
pkill -f 'python3 bookie_v2.py'; sleep 40
echo "bot processes: $(pgrep -f 'python3 bookie_v2.py' | wc -l)"; tail -4 /root/pe-sports/bookie/bookie_v2.out 2>/dev/null | cut -c1-200
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "642: bot blocklist + autopsy filters" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
echo "642 done"
