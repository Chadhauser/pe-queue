import sys, glob, re
sys.path.insert(0, '/root/pe-queue/runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local())
k = c.cursor()
k.execute("SET statement_timeout='300s'")
def q(s):
    k.execute(s)
    return k.fetchall()
def cols(t):
    return [x[0] for x in q("select column_name from information_schema.columns where table_name='%s' order by ordinal_position" % t)]
for t in ['tennis_results_2026','tennis_matches','cricket_matches','bf_hist_other_files','bf_hist_months','af_fixtures','fd_matches','greyhound_racecards_today','racing_results','af_lineups','af_player_stats']:
    print(t, cols(t))
print(q("select * from bf_hist_months limit 3"))
blob = {}
for f in glob.glob('jobs/*.sh'):
    blob[f] = open(f, errors='ignore').read()
Q = open('watchman/FINDER_QUEUE.md').read()
H = open('watchman/HYPOTHESES.md').read()
for w in ['last race','race order','payday','pay day','pay-day','manager','new coach','qualifier','wild card','wildcard','winner_entry','entry','seed','payweek','altitude','attendance','venue','travel','distance','ACC','PSH','AvgH','MaxH','BFEH','red card','sent off','lucky loser','golf','politics','boxing','snooker','darts','rugby','ice_hockey','australian','bank','reverse fixture','streak','odd or even','stoppage','added time','captain','debut','loan','age']:
    fs = [f for f in blob if w in blob[f]]
    print(repr(w), 'jobs', len(fs), 'queue', len(re.findall(re.escape(w), Q)), 'ledger', len(re.findall(re.escape(w), H)), [f[5:] for f in fs[:4]])
