#!/bin/bash
set -o pipefail
# 486 (Finder 2026-11-04, queue item 0d, validation of 484): are the MISSING labels real, or name-matching errors?
# WHY: 484's first run compared one spelling with the XI. af_lineups spells one man several ways across fixtures ('L. Vallejo' / 'Luciano Vallejo', accents), 3,598 such pairs, so Haaland was "absent" from a game he scored in (35 absent-but-scored, 666 scorers unresolved). Those first-run labels are void.
# NOW: identity = af_lineups.player_id. A scorer name (af_events has no id) resolves to the unique id at the club whose names match; goals are summed by id, so spellings cannot split a scorer.
# TEST 1 (hard): a key scorer absent from the whole sheet (no XI, no bench) cannot score in that game. Compares on id, matching event names to the ids on the sheet. Must be about zero.
# TEST 2: bench-but-scored is possible and only reported. TEST 3: rates of XI / bench / absent by rank on all line-up fixtures. No prices, no API calls.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,unicodedata,warnings,psycopg2,pandas as pd
from collections import Counter,defaultdict
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
def pname(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    return [w for w in re.sub(r"[^a-z ]"," ",s).split() if w]
def same_player(a,b):
    A,B=pname(a),pname(b)
    if not A or not B: return False
    if A==B: return True
    if A[-1]!=B[-1]: return False
    if len(A)==1 or len(B)==1: return True
    return A[0][0]==B[0][0]
def resolve_id(scorer,idn):
    """idn: {player_id: set of spellings}. Unique id for a scorer, or None if absent or ambiguous."""
    ex=[i for i,ns in idn.items() if any(pname(n)==pname(scorer) for n in ns)]
    if len(ex)==1: return ex[0]
    if len(ex)>1: return None
    m=[i for i,ns in idn.items() if any(same_player(scorer,n) for n in ns)]
    return m[0] if len(m)==1 else None
def key_ids(names,idn,k=2):
    """names: one per goal. Top 3 by goals summed by id; an unresolved name stays as ('?',name)."""
    c=Counter()
    for n,g in Counter(names).items():
        i=resolve_id(n,idn); c[i if i is not None else ('?',n)]+=g
    return [p for p,g in sorted(c.items(),key=lambda kv:(-kv[1],str(kv[0])))[:3] if g>=k]
_i={1:{'L. Vallejo','Luciano Vallejo'},2:{'J. Silva','Joao Silva'},3:{'J. Silva','Jose Silva'},4:{'E. Godoy','É. Godoy'}}
assert resolve_id('Luciano Vallejo',_i)==1 and resolve_id('L. Vallejo',_i)==1 and resolve_id('Lucas Vallejo',_i)==1
assert resolve_id('Joao Silva',_i)==2 and resolve_id('J. Silva',_i) is None and resolve_id('Nobody Else',_i) is None
assert resolve_id('É. Godoy',_i)==4 and resolve_id('E. Godoy',_i)==4              # two spellings, one id: not ambiguous
assert key_ids(['L. Vallejo','Luciano Vallejo','Joao Silva'],_i)==[1]               # spellings summed: 2 goals, id 1; id 2 has only 1
assert key_ids(['Nobody Else','Nobody Else'],_i)==[('?','Nobody Else')]
print("known-answer checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='600s'")
LU=pd.read_sql("SELECT fixture_id,team,player_id,player,starter FROM af_lineups",con)
print(f"rows {len(LU)} | null player_id {LU.player_id.isna().sum()} | zero player_id {(LU.player_id==0).sum()}",flush=True)
LU=LU[LU.player_id.notna()&(LU.player_id!=0)].drop_duplicates(['fixture_id','team','player_id']); LU['player_id']=LU.player_id.astype('int64')
print(f"one id, several spellings at one club: {int((LU.groupby(['team','player_id']).player.nunique()>1).sum())} of {LU.groupby(['team','player_id']).ngroups}",flush=True)
F=pd.read_sql("SELECT fixture_id,season,kickoff,home,away FROM af_fixtures WHERE kickoff>'2026-01-01' AND kickoff<now()+interval '1 day' AND status='FT'",con)
G=pd.read_sql("""SELECT e.fixture_id,e.team,e.player FROM af_events e JOIN af_fixtures f USING(fixture_id) WHERE f.kickoff>'2026-01-01' AND f.status='FT' AND e.type='Goal' AND e.detail IN ('Normal Goal','Penalty') AND e.player IS NOT NULL""",con).merge(F[['fixture_id','kickoff','season']],on='fixture_id')
xi=defaultdict(set); bench=defaultdict(set); idn=defaultdict(lambda:defaultdict(set))
for r in LU.itertuples():
    idn[r.team][r.player_id].add(r.player); (xi if r.starter else bench)[(r.fixture_id,r.team)].add(r.player_id)
games=defaultdict(list)
for f in F.sort_values('kickoff').itertuples():
    games[f.home].append((f.kickoff,f.fixture_id,f.season)); games[f.away].append((f.kickoff,f.fixture_id,f.season))
print("xi size:",Counter(len(v) for v in xi.values()).most_common(4))
C=Counter(); R=Counter(); T=Counter(); bad=[]; samp=[]
for f in F[F.fixture_id.isin(LU.fixture_id)].itertuples():
    ev=G[G.fixture_id==f.fixture_id]
    for t in (f.home,f.away):
        prior=[x for x in games[t] if x[0]<f.kickoff and x[2]==f.season]
        if len(prior)<5 or len(xi[(f.fixture_id,t)])!=11: T['skip']+=1; continue
        key=key_ids(list(G[(G.team==t)&(G.season==f.season)&(G.kickoff<f.kickoff)].player),idn[t])
        if not key: T['no key']+=1; continue
        if any(isinstance(k,tuple) for k in key): T['unresolved']+=1; C['unresolved scorer']+=sum(isinstance(k,tuple) for k in key); continue
        T['usable']+=1; anyout=False
        today={resolve_id(n,idn[t]) for n in ev[ev.team==t].player}
        for rk,k in enumerate(key,1):
            where='xi' if k in xi[(f.fixture_id,t)] else 'bench' if k in bench[(f.fixture_id,t)] else 'absent'
            R[(rk,where)]+=1; C[where]+=1; anyout=anyout or where!='xi'
            if where!='xi' and k in today:
                C[where+' but scored']+=1
                if where=='absent': bad.append((str(f.kickoff.date()),t,sorted(idn[t][k])))
            if where=='absent' and len(samp)<12: samp.append((str(f.kickoff.date()),t,sorted(idn[t][k])))
        T['any out']+=anyout
print("team-games:",dict(T))
print("key scorers:",dict(C))
print("by rank:",{k:R[k] for k in sorted(R)})
print("TEST 1 absent but scored:",bad[:20])
print("absent sample:",samp)
PY
