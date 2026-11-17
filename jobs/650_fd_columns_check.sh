#!/bin/bash
# 650 (Tue 17 Nov 2026, 15:10). Read only. 649's settle found Pinnacle closing in football-data only up to 14 Jan 2026. Which closing-odds
# columns does this season's file carry (Pinnacle, Betfair exchange, max, average), and which do older seasons' raw rows hold?
R=/root/pe-queue/reports/fd_cols_650.md
{ echo "# 650 — $(date -u '+%F %H:%M') UTC"; echo '```'
curl -s https://www.football-data.co.uk/mmz4281/2627/E0.csv | head -1 | tr ',' '\n' | grep -nE "^P|^Max|^Avg|^BF|^B365C|^PSC" | tr '\n' ' '; echo
curl -s https://www.football-data.co.uk/mmz4281/2627/E0.csv | sed -n 2p | cut -c1-400
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor()
for s in ('1920','2223','2425','2526'):
    c.execute("SELECT count(*), count(*) FILTER (WHERE raw ? 'AvgCH'), count(*) FILTER (WHERE raw ? 'PSCH'), count(*) FILTER (WHERE raw ? 'BFECH'), count(*) FILTER (WHERE raw ? 'MaxCH'), max(date) FILTER (WHERE psch IS NOT NULL) FROM fd_matches WHERE season=%s",(s,))
    print(s, "rows, AvgCH, PSCH, BFECH, MaxCH, last psch:", c.fetchone())
PY
echo '```'; } > $R 2>&1
cd /root/pe-queue && git add $R && git commit -qm "650: fd columns" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
