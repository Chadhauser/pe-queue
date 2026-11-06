#!/bin/bash
set -o pipefail
# 499_exotic_unread (Finder 2026-11-06, queue item 266, Finder's own, source d): pre-off on Sep 2026 markets never read. Rule pushed in the queue (ae1146f) before any price. Read only. No tables written, so a second copy from the runner does no harm.
# ENTRY last non-in-play print T-20 to T-2, worse of it and the next within 120 s, one tick adverse, 2%, GBP 10 risk, hold to the result. Over 50 not traded. One bet per event per line, lowest id. FAV, DOG from MO in the same window. Settled on goal_timeline; no score match dropped and counted.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
from lib_official import bk,ly,fill,last_in,checks
import lib_cand,lib_exotic as X; lib_cand._checks(); checks(); X.checks(); print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',220); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',30)
HC=[f'TEAM_{a}_{k}' for a in 'AB' for k in (1,2,3)]; WN=['TEAM_A_WIN_TO_NIL','TEAM_B_WIN_TO_NIL']; CB=['MATCH_ODDS_AND_BTTS','MATCH_ODDS_AND_OU_25']
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
E=X.load(con,HC+WN+CB+['ODD_OR_EVEN','MATCH_ODDS']); SC,nsc=X.scores(con); con.close()
print(f"games with a pre-off print {len(E):,}; finished goal_timeline rows {nsc:,}; {time.time()-T0:.0f}s",flush=True)
C=Counter(); rows=[]
def add(ev,off,nm,en,won):
    ts,px=en; i=last_in(ts,off-1200,off-120)
    if i is None: C['no print in window']+=1; return
    for side in 'BL':
        p=fill(ts,px,i,side)
        if p>50: C['over 50, not traded']+=1; continue
        v=bk(p,won) if side=='B' else ly(p,won)
        if v is None: C['bottom of ladder, no back']+=1; continue
        rows.append((ev,off,nm,side,p,won,v))
matched=0
for (ev,off),M in E.items():
    home,_x,away=ev.partition(' v ')
    if not any(k!='MATCH_ODDS' for k in M): C['MO only, nothing to read']+=1; continue
    sc=SC(ev,off)
    if sc is None: C['no score match, game dropped']+=1; continue
    matched+=1; sh,sa=sc
    fav=X.mo_fav(M.get('MATCH_ODDS',{}),home,away,off)
    if fav is None: C['no MO favourite, FAV-DOG lines skipped']+=1
    rl=lambda r:'FAV' if r==fav else 'DOG'
    for mty,S in M.items():
        if mty=='ODD_OR_EVEN':
            for s,en in S.items():
                s0=str(s).strip().lower()
                if s0 in ('odd','even'): add(ev,off,'ODD_EVEN '+s0,en,((sh+sa)%2==1)==(s0=='odd'))
        if fav is None: continue
        if mty in HC:
            hh=X.hc_home(mty)
            for s,en in S.items():
                p=X.hc_parse(s,home,away)
                if str(s).strip()=='Draw':
                    hf=hh if fav=='H' else -hh; add(ev,off,f"HC DRAW fav{hf:+d}",en,X.hc_draw_won(hh,sh,sa))
                elif p is None: C['handicap runner not read']+=1
                elif not X.hc_ok(p,hh): C['handicap sign v market type, skipped']+=1
                else: add(ev,off,f"HC {rl(p[0])}{p[1]:+d}",en,X.hc_won(p[0],p[1],sh,sa))
        elif mty in WN:
            r='H' if mty.startswith('TEAM_A') else 'A'; win=(sh>0 and sa==0) if r=='H' else (sa>0 and sh==0)
            for s,en in S.items():
                s0=str(s).strip().lower()
                if s0 in ('yes','no'): add(ev,off,f"WTN {rl(r)} {s0}",en,win==(s0=='yes'))
        elif mty in CB:
            for s,en in S.items():
                p=X.combo_parse(s,home,away)
                if p is None: C['combo runner not read']+=1; continue
                lab='DRAW' if p[0]=='D' else rl(p[0]); add(ev,off,f"{'MOBTTS' if 'BTTS' in mty else 'MOOU25'} {lab}/{p[1]}",en,X.combo_won(p[0],p[1],sh,sa))
print("games matched to a score",matched,"counted:",dict(sorted(C.items())),flush=True)
R=pd.DataFrame(rows,columns='e off nm side p won v'.split()); dup=int(R.duplicated(['e','off','nm','side']).sum()); print("duplicate rows, must be 0:",dup,flush=True); assert dup==0
md=np.median(R.off.values); print("halves split at",pd.Timestamp(md,unit='s',tz='UTC'),flush=True)
out=[]
for k,x in R.groupby(['nm','side']):
    l=line(x.v.values,np.where(x.off<md,1,2)); out.append(dict(line=k[0],side=k[1],n=l['n'],games=len(x),per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],maxwin=l['maxwin'],won=x.won.mean(),imp=(1/x.p).mean(),PASS=l['PASS']))
O=pd.DataFrame(out); print(f"\n== {len(O)} lines, n>=100 by t"); print(O[O.n>=100].sort_values('t',ascending=False).head(20).round(3).to_string(index=False))
print("\n== worst 5, n>=100"); print(O[O.n>=100].sort_values('t').head(5).round(3).to_string(index=False))
S=O[O.PASS==True]
print(f"\n== SURVIVORS: {len(S)} of {len(O)}\n",S.round(3).to_string(index=False) if len(S) else "none")
for r in S.itertuples():
    x=R[(R.nm==r.line)&(R.side==r.side)]; print(' ',r.line,r.side,'without the largest win:',round((x.v.sum()-x.v.max())/(len(x)-1),3),'Sep weeks:',x.groupby(pd.to_datetime(x.off,unit='s').dt.isocalendar().week).v.mean().round(2).to_dict())
print(f"total {time.time()-T0:.0f}s")
PY
