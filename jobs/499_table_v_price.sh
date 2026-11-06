#!/bin/bash
set -o pipefail
# 499_table_v_price (Finder 2026-11-06, queue item 285, Finder's own, source d; entry from jobs/499_referee_home.sh, table from jobs/499_dead_rubber.sh): is a plain place in the league table priced? Rule pushed in the queue (8b1a00f) before any price. Read only. No tables written. LTP only, so a pass is an upper bound.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_800_000_000,1_800_000_000))
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict,Counter
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import line
from lib_official import bk,ly,secs,checks
import lib_cand; lib_cand._checks(); checks()
LG=[39,40,41,42,61,62,78,79,88,94,119,135,136,140,141,144,179,197,203,207,218]
def tables(fx):
    """fx rows (id,secs,home,away,hg,ag) one league-season. Returns {id:(home place,away place,teams,played h,played a)}; place 1 = top; points then goal difference; same-time games are not history for each other."""
    c=Counter()
    for r in fx: c[r[2]]+=1; c[r[3]]+=1
    if len(c)<10: return {},Counter(short=1)
    L=Counter(c.values()).most_common(1)[0][0]; fx=sorted(fx,key=lambda z:z[1])
    pts=defaultdict(int); gd=defaultdict(int); pl=defaultdict(int); out={}; skip=Counter(); i=0
    while i<len(fx):
        j=i
        while j<len(fx) and fx[j][1]==fx[i][1]: j+=1
        order=sorted(c,key=lambda t:(-pts[t],-gd[t],t)); pos={t:n+1 for n,t in enumerate(order)}
        for f,k,h,a,hg,ag in fx[i:j]:
            if pl[h]>=L or pl[a]>=L: skip['past length']+=1; continue
            out[f]=(pos[h],pos[a],len(c),pl[h],pl[a])
        for f,k,h,a,hg,ag in fx[i:j]:
            pl[h]+=1; pl[a]+=1; gd[h]+=hg-ag; gd[a]+=ag-hg
            if hg>ag: pts[h]+=3
            elif ag>hg: pts[a]+=3
            else: pts[h]+=1; pts[a]+=1
        i=j
    return out,skip
# known answer, worked by hand: A beats B 2-0; C and D draw; at game 3 A is 1st (3 pts), C and D level on 1 and gd 0 sorted by name, B last. 10-team minimum met with filler sides.
_f=[(1,0,'A','B',2,0),(2,0,'C','D',1,1),(3,10,'A','C',1,0),(4,10,'B','D',0,0)]+[(100+i,0,f'X{i}',f'Y{i}',0,0) for i in range(4)]+[(200+i,10,f'X{i}',f'Y{i}',0,0) for i in range(4)]
_t,_=tables(_f); assert _t[3][0]==1 and _t[3][1] in (2,3,4,5,6,7,8,9,10,11) and _t[1][0]==_t[1][1]-1 and _t[3][3]==1 and _t[3][4]==1
assert _t[4][0]==12 and _t[3][2]==12   # B lost 0-2, bottom of the 12 sides
print("checks: OK",flush=True); T0=time.time()
pd.set_option('display.width',230); pd.set_option('display.max_rows',80); pd.set_option('display.max_columns',30)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; con.cursor().execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
F=pd.read_sql("SELECT fixture_id,league_id,season,kickoff,home,away,hg,ag FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND season IN (2024,2025) AND league_id=ANY(%s)",con,params=(LG,))
F['tt']=secs(F.kickoff); T={}; sk=Counter()
for (l,s),g in F.groupby(['league_id','season']):
    a,b=tables([tuple(x) for x in g[['fixture_id','tt','home','away','hg','ag']].itertuples(index=False)]); T.update(a); sk+=b
print("games with a table",len(T),"skipped",dict(sk),flush=True)
G=pd.read_sql("SELECT m.event_id,f.fixture_id,f.season,f.kickoff,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.season IN (2024,2025) AND f.league_id=ANY(%s)",con,params=(LG,))
G=G[G.fixture_id.isin(T)]
NMS=pd.read_sql("SELECT DISTINCT ON (event_id) event_id,event_name FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='MO' AND sel='HOME' AND minute=1",con,params=(list(G.event_id),))
BAD=NMS.event_name.str.contains(r"U-?(?:1[5-9]|2[0-3])\b|\(W\)|\bWomen\b| II\b| B(?: v |$)| Reserves?(?: v |$)|^Jong | v Jong ",regex=True); bad=set(NMS.event_id[BAD]); print('maps naming a youth, women or reserve game but pointing at a senior fixture, dropped',len(bad),flush=True); G=G[~G.event_id.isin(bad)]
EV=pd.read_sql("SELECT fixture_id,min(coalesce(minute,0)) gm FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal') AND coalesce(minute,0)<=2 GROUP BY 1",con,params=(list(map(int,G.fixture_id)),))
fg=dict(zip(EV.fixture_id,EV.gm)); parts=[]
for i in range(0,len(G),1000):
    P=pd.read_sql("SELECT event_id,sel,minute,m,ltp::float8 ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='MO' AND sel IN ('HOME','AWAY','DRAW') AND minute>=0 AND minute<=2 AND ltp>=1.01 AND ltp<1000",con,params=(list(G.event_id.iloc[i:i+1000]),))
    parts.append(P.sort_values(['event_id','sel','minute','m']).drop_duplicates(['event_id','sel']))
con.close(); P=pd.concat(parts,ignore_index=True).merge(G[['event_id','fixture_id','kickoff']],on='event_id')
lag=(pd.to_datetime(P.m,utc=True)-pd.to_datetime(P.kickoff,utc=True))/pd.Timedelta(minutes=1); gm=P.fixture_id.map(fg)
bad=(lag<-5)|(lag>20)|(gm.notna()&(gm<P.minute)); print(f"rows dropped by the guards {int(bad.sum())} of {len(P)}",flush=True); P=P[~bad]
W=P.pivot_table(index='event_id',columns='sel',values='ltp',aggfunc='first')
D=G.merge(W[['HOME','DRAW','AWAY']].dropna().reset_index(),on='event_id').sort_values('kickoff').drop_duplicates('fixture_id')
D['off']=secs(D.kickoff); X=[T[f] for f in D.fixture_id]
D['ph'],D['pa'],D['nt'],D['gh'],D['ga']=zip(*X)
n0=len(D); D=D[(D.gh>=10)&(D.ga>=10)&(D.ph!=D.pa)].copy()
print(f"mapped games with three prints {n0}, both sides 10+ games {len(D)}, by season {D.season.value_counts().to_dict()}",flush=True)
D['hw']=D.hg>D.ag; D['aw']=D.ag>D.hg
D['hi_home']=D.ph<D.pa; D['gap']=(D.ph-D.pa).abs()
D['p_hi']=np.where(D.hi_home,D.HOME,D.AWAY); D['p_lo']=np.where(D.hi_home,D.AWAY,D.HOME)
D['w_hi']=np.where(D.hi_home,D.hw,D.aw); D['w_lo']=np.where(D.hi_home,D.aw,D.hw); D['dis']=D.p_hi>D.p_lo
D['top3v']=(D[['ph','pa']].min(axis=1)<=3)&(D[['ph','pa']].max(axis=1)>D.nt-3)
def vals(x,pc,wc,f): return np.array([np.nan if (q:=f(float(p),bool(w))) is None else q for p,w in zip(x[pc],x[wc])],dtype=float)
md=float(np.median(D.off)); out=[]
def add(nm,x,pc,wc,f,lab):
    v=vals(x,pc,wc,f); m=np.isfinite(v); v=v[m]; z=x[m]
    if len(v)<30: out.append(dict(line=nm+' '+lab,n=len(v),PASS=False)); return
    l=line(v,np.where(z.off<md,1,2)); out.append(dict(line=nm+' '+lab,n=l['n'],per10=l['per10'],t=l['t'],n1=l['n1'],h1=l['h1'],n2=l['n2'],h2=l['h2'],maxwin=l['maxwin'],won=z[wc].astype(float).mean(),imp=(1/z[pc]).mean(),PASS=l['PASS']))
def four(nm,x):
    for s,pc,wc in (('HIGHER','p_hi','w_hi'),('LOWER','p_lo','w_lo')):
        add(nm+' '+s,x,pc,wc,bk,'back'); add(nm+' '+s,x,pc,wc,ly,'lay')
for g_ in (4,8):
    four(f'DIS_H gap{g_}+',D[D.dis&D.hi_home&(D.gap>=g_)]); four(f'DIS_A gap{g_}+',D[D.dis&~D.hi_home&(D.gap>=g_)])
four('TOP3vBOTTOM3',D[D.top3v])
for s,pc,wc in (('HOME','HOME','hw'),('AWAY','AWAY','aw')):
    add('CONTROL all '+s,D,pc,wc,bk,'back'); add('CONTROL all '+s,D,pc,wc,ly,'lay')
L=pd.DataFrame(out); print(f"\nlines {len(L)}"); print(L.sort_values('t',ascending=False).round(3).to_string(index=False))
S=L[(L.PASS==True)&~L.line.str.startswith('CONTROL')]
print(f"\n== SURVIVORS: {len(S)} of {int((~L.line.str.startswith('CONTROL')).sum())} scored\n",S.round(3).to_string(index=False) if len(S) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
