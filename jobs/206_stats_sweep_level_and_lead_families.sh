#!/bin/bash
# 206: HONEST HISTORICAL CHECK OF THE PRICE-ONLY LTD FAMILY. The price-only sweep's CLOCK cells carry a survivorship bias (they keep
# only games whose detected goal count equals the true total, which drops games with hard-to-detect late goals and flatters every
# lay-to-FT cell — the 75' lead cells failed the live replay for exactly that reason). The stats sweep has TRUE goal minutes from
# Understat for 3,446 games, so the same rules are added there with no detection step at all:
#   LEVEL00@m : score 0-0 at m -> lay the draw (exits +10/+20/next goal/FT)           [the live bots' rule]
#   LEAD1@m   : one-goal lead at m -> lay the draw, back the leader (exit FT)          [the cells that failed live]
# Minutes 20..75 step 5 as before. Output: the usual survivor table plus these families by trigger minute.
cd /root/pe-factory/v4 && python3 - <<'PY'
p='stats_sweep.py'; s=open(p).read()
anchor="                if m>=30 and txg<=0.4 and hg+ag==0:\n"
add="""                if hg==0 and ag==0: emit(f'LEVEL00@{m}','MO','DRAW','lay',m)
                if abs(hg-ag)==1:
                    emit(f'LEAD1@{m}','MO','DRAW','lay',m); emit(f'LEAD1@{m}','MO',('HOME' if hg>ag else 'AWAY'),'back',m)
"""
if 'LEVEL00' in s: print("already present")
else:
    assert anchor in s, "anchor missing"; s=s.replace(anchor,add+anchor,1); open(p,'w').write(s); print("families added")
PY
python3 -m py_compile stats_sweep.py || exit 1
timeout 3300 python3 stats_sweep.py 2>&1 | grep -v -E "UserWarning|pd.read_sql| processed" > /root/pe-factory/v4/stats_sweep_206.log
sed -n '/SURVIVORS/,/Bottom 10/p' /root/pe-factory/v4/stats_sweep_206.log | head -80
echo "== LEVEL00 / LEAD1 cells (n>=100)"
python3 - <<'PY'
import sys,psycopg2,pandas as pd; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',220)
c=psycopg2.connect(DB,sslmode='require')
d=pd.read_sql("SELECT fam, sel, dir, exit, band, n, mean, t, h1, h2 FROM v4_stats_results WHERE run_date=(SELECT max(run_date) FROM v4_stats_results) AND (fam LIKE 'LEVEL00%%' OR fam LIKE 'LEAD1%%') AND n>=100 ORDER BY fam, t DESC",c)
print(d.round(2).to_string(index=False))
PY
grep -A12 "By trigger minute" /root/pe-factory/v4/stats_sweep_206.log | head -14
