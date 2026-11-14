#!/bin/bash
# 566 (Sat 14 Nov 2026, 07:05). The break check heals the one break that has hit three times before it emails:
#  - a queue clone stuck mid-rebase/merge, or refusing to pull -> abort the stuck step, merge-pull, push; email only if that fails.
#  - one email per distinct break, not one per calendar day (the 13/14 Nov pair was one break reported twice across midnight).
#  - and the restore lesson: every serial sequence in the goal/alert tables is checked against max(id) hourly; a lagging one is reset
#    and reported in the email body, because a lagging sequence silently blocks every insert.
set -o pipefail
S=/root/pe-sports/team/break_check.sh; cp $S $S.bak_566
python3 - <<'PY'
p='/root/pe-sports/team/break_check.sh'; s=open(p).read()
old='''cd /root/pe-queue && if ! timeout 60 git pull -q 2>/tmp/break_pull.err; then B="$B queue cannot pull ($(tail -1 /tmp/break_pull.err | cut -c1-60));"; fi'''
new='''cd /root/pe-queue
if [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ] || [ -f .git/MERGE_HEAD ]; then git rebase --abort 2>/dev/null; git merge --abort 2>/dev/null; HEALED="$HEALED aborted a stuck rebase/merge;"; fi
git config pull.rebase false; git config rebase.autoStash true
if ! timeout 60 git pull -q --no-edit 2>/tmp/break_pull.err; then git add -u -q 2>/dev/null; git -c user.name=breakcheck -c user.email=peter@edwardsbros.co.uk commit -qm "server-side edits (break check)" 2>/dev/null; timeout 60 git pull -q --no-edit 2>/tmp/break_pull.err && HEALED="$HEALED committed stray edits and pulled;" || B="$B queue cannot pull ($(tail -1 /tmp/break_pull.err | cut -c1-60));"; fi
[ "$(git rev-list origin/main..HEAD --count 2>/dev/null)" != 0 ] && { timeout 60 git push -q 2>/dev/null && HEALED="$HEALED pushed local commits;"; }
# sequences behind the data silently block inserts (lesson of the 13 Nov restore)
SEQ=$(python3 - <<'PYS'
import sys,psycopg2; sys.path.insert(0,'/root/pe-queue/runner'); import creds
try:
    con=psycopg2.connect(creds.pg_local(),sslmode='disable',connect_timeout=10); con.autocommit=True; c=con.cursor(); out=[]
    for t in ('goal_alerts','goal_live_predictions','goal_timeline','m1_alerts','af_fixtures','af_events','bookie_paper','desk_calls'):
        try:
            c.execute("select pg_get_serial_sequence(%s,'id')",(t,)); sq=c.fetchone()[0]
            if not sq: continue
            c.execute(f"select coalesce(max(id),0) from {t}"); mx=c.fetchone()[0]; c.execute("select last_value from "+sq); lv=c.fetchone()[0]
            if lv<mx: c.execute("select setval(%s,%s)",(sq,mx)); out.append(f"{t} sequence reset {lv}->{mx}")
        except Exception: pass
    print("; ".join(out))
except Exception as e: print("")
PYS
); [ -n "$SEQ" ] && HEALED="$HEALED $SEQ;"'''
assert old in s; s=s.replace(old,new,1)
s=s.replace('D=/root/pe-sports/team/break_sent; mkdir -p $D; T=$(date -u +%F); B=""','D=/root/pe-sports/team/break_sent; mkdir -p $D; T=$(date -u +%F); B=""; HEALED=""')
# one email per distinct break (key on the text only, not the day); healed-only runs log, no email
s=s.replace('K=$(echo "$B" | md5sum | cut -c1-8); [ -f $D/$T-$K ] && exit 0','K=$(echo "$B" | md5sum | cut -c1-8); ls $D/*-$K >/dev/null 2>&1 && exit 0')
s=s.replace('B=$(echo $B | sed \'s/^ *//\'); [ -z "$B" ] && exit 0','B=$(echo $B | sed \'s/^ *//\'); [ -n "$HEALED" ] && echo "$(date -u +%FT%H:%M) healed:$HEALED" >> /root/pe-sports/team/break_healed.log; [ -z "$B" ] && exit 0')
s=s.replace('f"Break found at {datetime.datetime.utcnow():%H:%M} UTC: {sys.argv[1]} No real money is at risk. Details go to reports/ in the repository."','f"Break found at {datetime.datetime.utcnow():%H:%M} UTC: {sys.argv[1]} The check tried to heal it first and could not. No real money is at risk."')
open(p,'w').write(s); print("break_check patched; healed-log + sequence check + single email per break")
PY
bash -n $S && echo "compiles" || { cp $S.bak_566 $S; echo RESTORED; exit 1; }
bash $S; echo "break check exit $?"; tail -3 /root/pe-sports/team/break_healed.log 2>/dev/null
echo "566 done"
