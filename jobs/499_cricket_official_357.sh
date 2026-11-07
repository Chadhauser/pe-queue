#!/bin/bash
set -o pipefail
# 499_cricket_official_357 (Finder 2026-11-07, queue item 362, Finder's own, source a): jobs/499_cricket_own_error.sh unchanged except that a game's winner comes from cricket_matches on Railway, to 27 Apr 2026, this one table, and a game with no official winner is counted and skipped. Same months, so it only keeps or kills the lean and cannot pass. Item 354's section prints too, on the same official games; item 362 reads the OUT lines of item 357.
python3 - /root/pe-queue/jobs/499_cricket_own_error.sh <<'PY' | bash || echo "ERROR: own_error failed"
import sys
t=open(sys.argv[1]).read()
def sw(a,b):
    global t
    assert t.count(a)==1,a
    t=t.replace(a,b)
sw("from lib_cand import line,step\n","from lib_cand import line,step,norm\n")
sw("C=Counter(); seen=set(); G=[]; IPV=[]; IPN=Counter()\n","""C=Counter(); seen=set(); G=[]; IPV=[]; IPN=Counter()
_r=psycopg2.connect(creds.pg_railway(),sslmode='require'); CM=pd.read_sql("SELECT match_date,team1,team2,winner FROM cricket_matches WHERE match_date>='2024-08-25'",_r); _r.close()
_ix=defaultdict(list)
for _x in CM.itertuples(): _ix[frozenset((norm(_x.team1),norm(_x.team2)))].append((_x.match_date,_x.winner))
print("official",len(CM),CM.match_date.min(),CM.match_date.max(),flush=True)
def official(ev,mt,names):
    h_,_,a_=str(ev).partition(' v '); day=pd.Timestamp(mt).date()
    hits=[x for dd,x in _ix.get(frozenset((norm(h_),norm(a_))),[]) if abs((dd-day).days)<=1]
    if len(hits)!=1 or hits[0] is None: return None
    tw=[s for s in names if norm(s)==norm(hits[0])]
    return tw[0] if len(tw)==1 else None
""")
sw("win=infer(last); C['resolved' if win else 'unresolved']+=1\n","""win=official(ev,g.mt.iloc[0],list(run)); C['official' if win else 'no official winner, skipped']+=1
    if win is None: continue
""")
sw("assert len(G)>1000","assert len(G)>100")
print(t)
PY
echo "== SURVIVORS: none can pass here, these months chose the lines"
