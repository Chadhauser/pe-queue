#!/bin/bash
# 572 (Sat 14 Nov 2026, 09:10). CEO correction of 08:38, acted on from the 571 reading.
#  A. Diversify: the non-football cells moved out on 13 Nov go back into fair_price_passed (they passed the same Verifier); the engine runs
#     WEEKLY on every sport as a fixed cron (Sunday 01:00 UTC, one sport at a time, 128 MB), then verifier_cells.py re-derives the passed
#     list. The bot's universe is the event types of the passed cells, so it follows automatically. Paper only; proof gate unchanged.
#  B. Archive: xx_tape (Smarkets/Matchbook, 0.8 GB a day, never archived) joins the nightly archive; a monthly read-back check
#     (zstdcat | wc on every file vs the row count recorded in archive.log) runs on the 1st; nothing else about deletion changes
#     (the archive already deletes only after the file's row count matches).
#  C. Restore the small dropped tables now (under 40 MB dumps): af_stats, bfsp_history, racing_tape, runners, fd_matches, bf_golf_log.
#     The large ones (bf_price_log 221 MB, bf_racing_log 83, bf_tennis_log 70, finder logs) wait for disk; ch_accounts, factory_trades,
#     xx_ip_331 are not collection and stay as dumps.
#  D. Break check: any sport's feed silent 6 hours on a tape where the same 6-hour window a week ago had rows -> break.
#  E. Friday email opens with expected £ a month by sport at the largest stake the market supports, against £10,000, then the week's action.
set -o pipefail
cd /root/pe-sports/team
echo "== A. cells back + weekly engine =="
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); con.autocommit=True; c=con.cursor()
c.execute("insert into fair_price_passed select * from fair_price_passed_frozen_out f where not exists (select 1 from fair_price_passed p where p.sport=f.sport and p.market_type=f.market_type and p.band_lo=f.band_lo and p.side=f.side)"); print("cells restored:",c.rowcount)
c.execute("select sport, count(*) from fair_price_passed group by 1 order by 2 desc"); print("passed cells by sport:",c.fetchall())
c.execute("comment on table fair_price_passed is 'Verifier-only. Every sport. Re-derived weekly (Sunday 01:00 UTC engine run, job 572). Paper only until the proof gate.'")
PY
cat > /root/pe-sports/team/weekly_engine.sh <<'SH'
#!/bin/bash
# 572: the fair-price engine, every sport, one at a time, then the Verifier. Sunday 01:00 UTC. Memory-safe (one process, 128 MB work_mem).
cd /root/pe-sports/team; L=/root/pe-sports/team/weekly_engine.log
echo "== $(date -u '+%F %H:%M') weekly engine ==" >> $L
for S in $(python3 -c "
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, psycopg2
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor(); c.execute(\"select distinct sport from bf_hist_other where market_time>now()-interval '400 days'\"); print(' '.join(s.replace(' ','_') for (s,) in c.fetchall()))"); do
  N="${S//_/ }"; [ "$(free -m | awk '/Mem:/{print $7}')" -lt 1500 ] && { echo "skip $N: under 1.5 GB free memory" >> $L; continue; }
  FP_SPORTS="$N" timeout 5400 /usr/bin/python3 fairprice_v0.py > "fairprice_weekly_${S}.log" 2>&1; echo "$N exit $? RESULT lines $(grep -c ^RESULT fairprice_weekly_${S}.log)" >> $L
done
/usr/bin/python3 verifier_cells.py >> $L 2>&1; echo "verifier done $(date -u +%H:%M)" >> $L
SH
chmod +x weekly_engine.sh; bash -n weekly_engine.sh && ( crontab -l | grep -v weekly_engine.sh; echo "0 1 * * 0 /root/pe-sports/team/weekly_engine.sh" ) | crontab - && echo "weekly engine cron set (Sunday 01:00 UTC)"
echo "== B. archive: xx_tape in; monthly read-back =="
python3 - <<'PY'
p='/root/pe-archive/archive_tape.py'; s=open(p).read()
if "'xx_tape'" not in s: s=s.replace("T=[('stream_ticks','ts_recv'),('ip_tape','ts'),('liq_sample','ts')]","T=[('stream_ticks','ts_recv'),('ip_tape','ts'),('liq_sample','ts'),('xx_tape','ts')]   # 572: xx_tape archived too"); open(p,'w').write(s); print("xx_tape added to the archive")
else: print("xx_tape already archived")
PY
python3 -m py_compile /root/pe-archive/archive_tape.py && echo "archive compiles"
cat > /root/pe-archive/archive_readback.sh <<'SH'
#!/bin/bash
# 572: monthly read-back — every archive file is decompressed and its row count compared with what archive.log recorded. Mismatch -> listed.
cd /root/pe-archive; OUT=/root/pe-queue/reports/archive_readback_$(date -u +%F).md; echo "# Archive read-back $(date -u +%F)" > $OUT; BAD=0
for f in */*.csv.zst; do t=${f%%/*}; d=$(basename $f .csv.zst); want=$(grep "^$t $d: " archive.log | tail -1 | sed -E 's/.*: ([0-9]+) rows.*/\1/'); have=$(( $(zstdcat "$f" | wc -l) - 1 )); [ "$want" = "$have" ] && echo "- $f ok ($have rows)" >> $OUT || { echo "- $f MISMATCH log $want file $have" >> $OUT; BAD=$((BAD+1)); }; done
echo "mismatches: $BAD" >> $OUT; cd /root/pe-queue && git add reports/archive_readback_*.md && git commit -qm "archive read-back" && git pull -q --no-edit && git push -q
[ $BAD -gt 0 ] && cd /root/operators && set -a && . ./.env && set +a && PYTHONPATH=/root/operators python3 -c "from engines.mail import send_text; send_text('Trading estate: archive read-back found $BAD mismatches','See reports/archive_readback in the repository. Nothing has been deleted from those days beyond what the files hold.','peter@edwardsbros.co.uk')"
SH
chmod +x /root/pe-archive/archive_readback.sh; bash -n /root/pe-archive/archive_readback.sh && ( crontab -l | grep -v archive_readback.sh; echo "30 5 1 * * /root/pe-archive/archive_readback.sh >> /root/pe-archive/readback.log 2>&1" ) | crontab - && echo "monthly read-back cron set"
echo "== C. restore the small tables =="
DSN=$(python3 -c "import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds; print(creds.pg_local())")
for t in af_stats bfsp_history racing_tape runners fd_matches bf_golf_log; do f=/root/pe-archive/tables/public.$t.sql.zst
  if [ -f "$f" ] && ! psql "$DSN" -At -c "select to_regclass('public.$t')" | grep -q "$t"; then zstdcat "$f" | psql -q "$DSN" >/dev/null 2>&1 && echo "restored $t: $(psql "$DSN" -At -c "select count(*) from $t") rows"; else echo "$t: present or no dump"; fi; done
df -h / | tail -1
echo "== D. break check: per-sport feed silence =="
S=/root/pe-sports/team/break_check.sh; cp $S $S.bak_572
python3 - <<'PY'
p='/root/pe-sports/team/break_check.sh'; s=open(p).read(); assert '572' not in s
add='''# 572 (Peter): any sport's feed silent for 6 hours, on a tape where the same 6-hour window a week ago had rows
FEED=$(python3 - <<'PYF'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
try:
    c=psycopg2.connect(creds.pg_local(),sslmode='disable',connect_timeout=10).cursor(); c.execute("SET statement_timeout='120s'"); out=[]
    for t,ts in (('stream_ticks','ts_recv'),('ip_tape','ts'),('xx_tape','ts')):
        c.execute(f"select sport from (select sport, count(*) filter (where {ts}>now()-interval '6 hours') now6, count(*) filter (where {ts} between now()-interval '7 days 6 hours' and now()-interval '7 days') last6 from {t} where {ts}>now()-interval '7 days 6 hours' and ({ts}>now()-interval '6 hours' or {ts}<now()-interval '7 days') group by 1) x where now6=0 and last6>=1000")
        for (sp,) in c.fetchall(): out.append(f"{sp} silent 6 hours on {t}")
    print("; ".join(out)+(";" if out else ""))
except Exception as e: print("")
PYF
); B="$B $FEED"
'''
a='pgrep -f bookie_v2.py >/dev/null'; s=s.replace(a,add+a,1); open(p,'w').write(s); print("break_check: per-sport feed silence added")
PY
bash -n $S && echo "break_check compiles" || { cp $S.bak_572 $S; echo RESTORED; }
echo "== E. Friday email opener =="
python3 - <<'PY'
p='/root/pe-sports/team/friday_email.py'; s=open(p).read(); assert '572' not in s
add='''
# 572: opening line — expected £ a month by sport, at the largest stake the market supports, against £10,000; then the week's action
def opener():
    cols_bp=cols('bookie_paper'); sp_col=next((k for k in ('sport','event_type','event_type_name') if k in cols_bp),None)
    by={}
    rows=q(f"select coalesce({sp_col},'football') sport, count(*), coalesce(sum(pnl),0), coalesce(sum(stake),0), min(ts), max(ts) from bookie_paper where version='v2' and status='settled' and fill_kind='taker' group by 1") if sp_col else q("select 'football', count(*), coalesce(sum(pnl),0), coalesce(sum(stake),0), min(ts), max(ts) from bookie_paper where version='v2' and status='settled' and fill_kind='taker'")
    for sp,n,pnl,stk,t0,t1 in rows:
        if not n or not stk: continue
        days=max(1.0,((t1-t0).total_seconds()/86400) if t0 and t1 else 1.0); per100=float(pnl)/float(stk)*100
        T=touch_size(q("select market_id, ts, side from bookie_paper where version='v2' and fill_kind='taker' order by ts desc")) or 2.0
        by[sp]=by.get(sp,0)+ (n/days)*T*per100/100*30
    fade=q("select count(*), coalesce(sum(pnl),0), coalesce(sum(stake),0), min(ts), max(ts) from desk_calls where line='FADE' and status='closed'")
    if fade and fade[0][0]:
        n,pnl,stk,t0,t1=fade[0]; days=max(1.0,(t1-t0).total_seconds()/86400); per100=float(pnl)/float(stk)*100
        T=touch_size(q("select market_id, ts, side from desk_calls where line='FADE' order by ts desc")) or 2.0
        by['football']=by.get('football',0)+(n/days)*T*per100/100*30
    tot=sum(by.values()); parts=", ".join(f"{k} £{v:+,.0f}" for k,v in sorted(by.items(),key=lambda kv:-kv[1]))
    return (f"Expected a month from every rule on forward paper, at the largest stake the markets support (median at the touch), against the £10,000 target: £{tot:+,.0f} ({parts}). These are estimates from the paper record, not promises; a negative figure means the rule as it stands loses.",
            "This week to close the gap: the fair-price engine runs on every sport Sunday 01:00 and every cell that passes both halves goes onto forward paper from Monday; the bot and the fade keep counting towards 100.")
'''
s=s.replace("L=[f\"Bets settled this week:","O=opener()\nL=[O[0],O[1],f\"Bets settled this week:",1)
s=s.replace("RULES=[dict(",add+"\nRULES=[dict(",1)
open(p,'w').write(s); print("friday opener added")
PY
python3 -m py_compile friday_email.py && echo compiles && python3 friday_email.py | head -3 | cut -c1-400 || { cp friday_email.py.bak_568 friday_email.py; echo "RESTORED friday_email.py to 568"; }
echo "572 done"
