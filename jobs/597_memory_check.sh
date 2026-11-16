#!/bin/bash
# 597 (Mon 16 Nov 2026, 08:30). Peter says the memory upgrade is already done; the box reported 7.9 GB yesterday. Read what it says now.
echo "== memory =="; free -m | head -2; grep -i "MemTotal" /proc/meminfo; nproc; echo "cpus above"
echo "== dmidecode (RAM slots) =="; dmidecode -t memory 2>/dev/null | grep -i "Size:" | head -8
echo "== uptime / last reboot =="; uptime -s; uptime
echo "== disk =="; df -h / | tail -1
echo "== cloud-init / contabo product hints =="; cat /sys/class/dmi/id/product_name 2>/dev/null; cat /etc/cloud/cloud.cfg.d/*contabo* 2>/dev/null | head -5
echo "== bot bets by sport, last 24h =="; python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor(); c.execute("SET statement_timeout='60s'")
c.execute("select column_name from information_schema.columns where table_name='bookie_paper' order by ordinal_position"); cols=[r[0] for r in c.fetchall()]; print("cols:",cols)
sp=next((k for k in ('sport','event_type','event_type_id','mkt') if k in cols),None)
c.execute(f"select coalesce({sp}::text,'?'), count(*) from bookie_paper where version='v2' and ts>now()-interval '24 hours' group by 1 order by 2 desc") if sp else None; print("bets 24h by",sp,":",c.fetchall() if sp else "no sport column")
c.execute("select count(*), coalesce(sum(pnl),0) from bookie_paper where version='v2' and status='settled' and fill_kind='taker'"); print("taker settled, pnl:",c.fetchone())
PY
echo "== goal monitor =="; pgrep -fa monitor_ht | cut -c1-100; tail -3 /root/pe-brain/*.log 2>/dev/null | cut -c1-200 | tail -6
echo "597 done"
