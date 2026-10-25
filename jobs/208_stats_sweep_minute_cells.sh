#!/bin/bash
# 208: the stats sweep pools each cell over trigger minute. The LTD question is minute-specific (the live bots fire at 46/60/75), so
# store the per-minute cells too (v4_stats_minute) and re-run (the sweep takes ~3 min). Then print LEVEL00 / LEAD1 / DOMxg0.5 by minute.
cd /root/pe-factory/v4 && python3 - <<'PY'
p='stats_sweep.py'; s=open(p).read()
anchor='    print("stored",N)'
add='''    Mg=R.groupby(['fam','sel','dir','exit','band','minute']).p.agg(n='size',mean='mean',sd='std').reset_index(); Mg=Mg[(Mg.n>=30)&(Mg.sd>0)]; Mg['t']=Mg['mean']/(Mg.sd/np.sqrt(Mg.n))
    cur.execute("CREATE TABLE IF NOT EXISTS v4_stats_minute (run_date DATE, fam TEXT, sel TEXT, dir TEXT, exit TEXT, band TEXT, minute INT, n INT, mean NUMERIC, t NUMERIC)"); cur.execute("DELETE FROM v4_stats_minute WHERE run_date=current_date")
    psycopg2.extras.execute_values(cur,"INSERT INTO v4_stats_minute VALUES %s",[(datetime.date.today(),r.fam,r.sel,r.dir,r.exit,r.band,int(r.minute),int(r.n),f(r.mean),f(r.t)) for r in Mg.itertuples()],page_size=2000)
    print("minute cells stored",len(Mg))
'''
if 'v4_stats_minute' in s: print("already")
else:
    assert anchor in s; s=s.replace(anchor,add+anchor,1); open(p,'w').write(s); print("minute cells added")
PY
python3 -m py_compile stats_sweep.py || exit 1
timeout 3300 python3 stats_sweep.py 2>&1 | grep -E "minute cells stored|stored|SWEEP:" | head -5
python3 - <<'PY'
import sys,psycopg2,pandas as pd; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',200); c=psycopg2.connect(DB,sslmode='require')
for fam,sel,d,ex,band in [('LEVEL00','MO DRAW','lay','NG','1.5-2.5'),('LEVEL00','MO DRAW','lay','NG','2.5-5'),('LEVEL00','MO DRAW','lay','FT','1.5-2.5'),('LEAD1','MO DRAW','lay','FT','5+'),('LEAD1','MO HOME','back','FT','<1.5'),('DOMxg0.5','MO AWAY','lay','NG','5+'),('OPENxg1.0','OU25 OVER','lay','+20','2.5-5')]:
    m=pd.read_sql("SELECT minute, n, mean, t FROM v4_stats_minute WHERE run_date=current_date AND fam=%s AND sel=%s AND dir=%s AND exit=%s AND band=%s ORDER BY minute",c,params=(fam,sel,d,ex,band))
    print(f"\n{fam} {sel} {d} exit {ex} band {band}:\n",m.round(2).to_string(index=False))
PY
