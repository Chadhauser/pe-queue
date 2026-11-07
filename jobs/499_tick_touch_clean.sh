#!/bin/bash
set -o pipefail
# 499_tick_touch_clean (Finder 2026-11-07, queue item 385, Finder's own, source a, from item 384): first in-play touch on football MO and OU25, signal needing a real book: back_px <= Q and lay_px <= Q x 1.05 on the same tick. Rule pushed before this job read a price, though item 384's football prints had been seen. Reads stream_ticks, liq_sample, Railway goal_timeline; writes only finder_touch_clean, created by this job.
# Fill at the first tick of that runner at least D s later, no more than D+30 s, with a touch on that side, one tick adverse. A suspension between signal and fill, the bet lapses, no trade, counted. Result from the last goal_timeline row at minute 85+ in 2H, names by lib_cand.loose within a day; MO falls back to last OPEN back <= 1.03, then last-print odds; OU25 has no fall-back. 2%, £10 risk.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))  # this job only
import sys,time,datetime,psycopg2,warnings,pandas as pd,numpy as np
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,lay_settle,tstat,passes,norm,loose
from lib_wom import tgame
pd.set_option('display.width',230); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',30)
T0=time.time()
SQL_TOUCH="""WITH h AS (SELECT market_id,sel_id,min(t) tt FROM {tab} WHERE back_px<=%(q)s AND lay_px<=%(q)s*1.05+1e-9 GROUP BY 1,2)
SELECT h.market_id,h.sel_id,f.st,h.tt,b.t,b.back_px,b.back_sz,l.t,l.lay_px,l.lay_sz,
  (b.t IS NOT NULL AND EXISTS (SELECT 1 FROM {tab}_s s WHERE s.market_id=h.market_id AND s.t>h.tt AND s.t<=b.t)),
  (l.t IS NOT NULL AND EXISTS (SELECT 1 FROM {tab}_s s WHERE s.market_id=h.market_id AND s.t>h.tt AND s.t<=l.t))
FROM h JOIN {tab}_f f USING (market_id,sel_id)
  LEFT JOIN LATERAL (SELECT x.t,x.back_px,x.back_sz FROM {tab} x WHERE x.market_id=h.market_id AND x.sel_id=h.sel_id AND x.t>=h.tt+%(d)s AND x.t<=h.tt+%(d)s+30 AND x.back_px IS NOT NULL ORDER BY x.t LIMIT 1) b ON true
  LEFT JOIN LATERAL (SELECT x.t,x.lay_px,x.lay_sz FROM {tab} x WHERE x.market_id=h.market_id AND x.sel_id=h.sel_id AND x.t>=h.tt+%(d)s AND x.t<=h.tt+%(d)s+30 AND x.lay_px IS NOT NULL ORDER BY x.t LIMIT 1) l ON true
WHERE f.st>%(q)s"""
SQL_F="CREATE TEMP TABLE {tab}_f AS SELECT DISTINCT ON (market_id,sel_id) market_id,sel_id,back_px st FROM {tab} WHERE back_px IS NOT NULL ORDER BY market_id,sel_id,t"
def bk(p,w):
    a=step(p,-1); return np.nan if a<=1.01 else back_settle(a,w)
def ly(p,w): return lay_settle(step(p,1),w)
def score(fn,p,prob): return fn(p,True)*prob+fn(p,False)*(1-prob)
def infer(last):
    if not last: return {},False
    lo=min(last,key=last.get)
    if last[lo]<=1.03: return {s:(1.0 if s==lo else 0.0) for s in last},True
    tot=sum(1/v for v in last.values()); return {s:(1/v)/tot for s,v in last.items()},False
def by_score(mk,h,a,sh,sa,names):
    """names {sel: runner name}. Returns {sel: 1 or 0}, or None if the winner's runner is not there."""
    if mk=='MO': w=h if sh>sa else a if sa>sh else None
    else: w='Over 2.5 Goals' if sh+sa>=3 else 'Under 2.5 Goals'
    out={}; hit=False
    for s,n in names.items():
        l=str(n).lower()
        won=('draw' in l and w is None) if mk=='MO' and (w is None or 'draw' in l) else (n==w)
        out[s]=1.0 if won else 0.0; hit=hit or won
    return out if hit else None
# known answers, worked by hand
assert abs(bk(2.0,True)-10*.99*.98)<1e-9 and ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9 and np.isnan(bk(1.02,True))
_n={1:'Spurs',2:'Leeds',3:'The Draw'}
assert by_score('MO','Spurs','Leeds',2,1,_n)=={1:1.0,2:0.0,3:0.0}
assert by_score('MO','Spurs','Leeds',0,1,_n)=={1:0.0,2:1.0,3:0.0}
assert by_score('MO','Spurs','Leeds',1,1,_n)=={1:0.0,2:0.0,3:1.0}
assert by_score('MO','Spurs FC','Leeds',2,1,_n) is None
_o={7:'Over 2.5 Goals',8:'Under 2.5 Goals'}
assert by_score('OU25','x','y',2,1,_o)=={7:1.0,8:0.0} and by_score('OU25','x','y',1,1,_o)=={7:0.0,8:1.0}
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
# hand-worked table. Runner 1: junk at t=5 (lay 30), real touch t=10; D 5, back t=16 1.9, lay t=18 1.95, suspended t=17 lapses the lay only. Runner 2 started under Q. Runner 3 junk only, never a real touch.
cur.execute("CREATE TEMP TABLE tmp_k (market_id text,sel_id bigint,t float8,back_px float8,back_sz float8,lay_px float8,lay_sz float8)")
_r=[('m',1,0.,3.0,5,3.1,5),('m',1,5.,1.01,5,30.,5),('m',1,10.,2.0,5,2.1,5),('m',1,16.,1.9,7,None,None),('m',1,18.,None,None,1.95,8),
    ('m',2,0.,1.5,5,1.6,5),('m',2,8.,1.4,5,1.5,5),('n',3,0.,3.0,5,3.1,5),('n',3,9.,1.01,5,20.,5),('n',3,20.,1.01,5,20.,5)]
cur.executemany("INSERT INTO tmp_k VALUES (%s,%s,%s,%s,%s,%s,%s)",_r)
cur.execute(SQL_F.format(tab='tmp_k')); cur.execute("CREATE TEMP TABLE tmp_k_s (market_id text,t float8)"); cur.execute("INSERT INTO tmp_k_s VALUES ('m',17.0)")
cur.execute(SQL_TOUCH.format(tab='tmp_k'),dict(q=2.0,d=5.0)); _a=sorted(cur.fetchall())
assert _a==[('m',1,3.0,10.0,16.0,1.9,7.0,18.0,1.95,8.0,False,True)],_a
cur.execute("DROP TABLE tmp_k,tmp_k_f,tmp_k_s"); print("sql checks: OK",flush=True)
# finals, from Railway: goal_timeline has no FT row and the local copy stops 4 Nov
rc=psycopg2.connect(creds.pg_railway(),sslmode='require'); k=rc.cursor(); k.execute("SET statement_timeout='600s'")
k.execute("""SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,captured_at::date,score_home,score_away,status,minute FROM goal_timeline WHERE captured_at>'2026-11-01' ORDER BY fixture_id,captured_at DESC""")
G=k.fetchall(); rc.close()
FIN={}
for f,h,a,d,sh,sa,st,mn in G:
    if st=='2H' and mn is not None and mn>=85 and sh is not None and sa is not None: FIN.setdefault(d,[]).append((norm(h),norm(a),(h,a,sh,sa)))
print(f"goal_timeline fixtures {len(G)}, usable finals {sum(len(v) for v in FIN.values())}, {time.time()-T0:.0f}s",flush=True)
cur.execute("SELECT DISTINCT ON (market_id) market_id,event_name,ts::date FROM liq_sample WHERE mkt IN ('MO','OU25') AND event_name IS NOT NULL ORDER BY market_id,ts")
NM={m:(e,d) for m,e,d in cur.fetchall()}
def final_of(m):
    if m not in NM or ' v ' not in NM[m][0]: return None
    e,d=NM[m]; h,a=e.split(' v ',1); c=[]
    for dd in (d,d-datetime.timedelta(days=1),d+datetime.timedelta(days=1)): c+=FIN.get(dd,[])
    return loose(norm(h),norm(a),c) if c else None
rows=[]; lapse=[]
for mk in ('MO','OU25'):
    tab=f"tc_{mk}"
    cur.execute(f"""CREATE TEMP TABLE {tab} AS SELECT market_id,sel_id,extract(epoch from pt)::float8 t,back_px::float8 back_px,back_sz::float8 back_sz,lay_px::float8 lay_px,lay_sz::float8 lay_sz FROM stream_ticks WHERE sport='football' AND mkt=%s AND inplay AND status='OPEN' AND pt IS NOT NULL""",(mk,))
    cur.execute(f"CREATE INDEX ON {tab} (market_id,sel_id,t)"); cur.execute(f"ANALYZE {tab}")
    cur.execute(SQL_F.format(tab=tab))
    cur.execute(f"CREATE TEMP TABLE {tab}_s AS SELECT DISTINCT market_id,extract(epoch from pt)::float8 t FROM stream_ticks WHERE sport='football' AND mkt=%s AND inplay AND status='SUSPENDED' AND pt IS NOT NULL",(mk,))
    cur.execute(f"CREATE INDEX ON {tab}_s (market_id,t)"); cur.execute(f"ANALYZE {tab}_s")
    cur.execute(f"SELECT DISTINCT ON (market_id,sel_id) market_id,sel_id,back_px FROM {tab} WHERE back_px IS NOT NULL ORDER BY market_id,sel_id,t DESC")
    L={}
    for m,s,b in cur.fetchall(): L.setdefault(m,{})[int(s)]=b
    cur.execute("SELECT DISTINCT ON (market_id,sel_id) market_id,sel_id,sel FROM stream_ticks WHERE sport='football' AND mkt=%s AND inplay AND sel IS NOT NULL ORDER BY market_id,sel_id,pt DESC",(mk,))
    SN={}
    for m,s,n in cur.fetchall(): SN.setdefault(m,{})[int(s)]=n
    PR={}; src={'goal':0,'last':0,'odds':0,'none':0}; agree=[0,0]; diff=[]
    for m,last in L.items():
        pr,res=infer(last); fin=final_of(m); got=None
        if fin is not None:
            bh,ba=NM[m][0].split(' v ',1)   # Betfair's names, the runners'; the feed's names only find the game
            got=by_score(mk,bh,ba,fin[2],fin[3],SN.get(m,{}))
        if got is not None:
            for s in last: got.setdefault(s,0.0)
            PR[m]=(got,True,'goal'); src['goal']+=1
            if mk=='MO' and res:
                same=max(pr,key=pr.get)==max(got,key=got.get); agree[0 if same else 1]+=1
                if not same: diff.append((NM[m][0],fin[2],fin[3],SN[m].get(max(pr,key=pr.get))))
        elif mk=='MO':
            PR[m]=(pr,res,'last' if res else 'odds'); src['last' if res else 'odds']+=1
        else: src['none']+=1
    print(f"\nfootball {mk}: markets {len(L)}, results {src}; MO: goal row and 1.03 agree {agree[0]}, differ {agree[1]}, first differing {diff[:5]} | {time.time()-T0:.0f}s",flush=True)
    for q in (2,1.5,1.3,1.2,1.1):
        for d in (6.0,10.0):
            cur.execute(SQL_TOUCH.format(tab=tab),dict(q=q,d=d)); got=cur.fetchall(); nl=[0,0,0]
            for m,sel,st,tt,tb,pb,sb,tl,pl,sl,bs,ls in got:
                sel=int(sel)
                if m not in PR or sel not in PR[m][0]: nl[2]+=1; continue
                pr,res,how=PR[m]; prob=pr[sel]
                if pb is None: nl[0]+=1
                elif bs: nl[1]+=1
                else:
                    v=score(bk,pb,prob)
                    if v==v: rows.append((mk,m,sel,q,d,'back',tb,pb,sb,prob,how,v))
                if pl is not None and not ls: rows.append((mk,m,sel,q,d,'lay',tl,pl,sl,prob,how,score(ly,pl,prob)))
            lapse.append((mk,q,d,len(got),nl[0],nl[1],nl[2]))
    cur.execute(f"DROP TABLE {tab},{tab}_f,{tab}_s")
print("\n== touches and no trades: market q delay touched, no back tick in time, back lapsed, no result\n",pd.DataFrame(lapse,columns='mk q d touched notick lapsed nores'.split()).to_string(index=False),flush=True)
R=pd.DataFrame(rows,columns='mk m sel q d side t px sz prob how v'.split()); print(f"entries {len(R):,}",flush=True)
def tab_(x,**k):
    v=x.v.values; md=np.median(x.t.values); h=x.t.values<md; a,b=v[h],v[~h]; tr=tgame(v,x.m.values); z=x[x.how!='odds']
    return dict(**k,n=len(v),games=x.m.nunique(),per10=v.mean(),t=tstat(v),tr=tr,n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,goal=(x.how=='goal').mean(),res_per10=z.v.mean() if len(z) else np.nan,won=x.prob.mean(),fill=x.px.median(),imp=(1/x.px).mean(),sz=x.sz.median(),PASS=passes(len(v),len(a),len(b),tr,a.mean() if len(a) else 0,b.mean() if len(b) else 0,v.mean()))
O=pd.DataFrame([tab_(x,mk=k[0],q=k[1],delay=k[2],side=k[3]) for k,x in R.groupby(['mk','q','d','side'])]).sort_values('tr',ascending=False)
print(f"\n== ITEM 385: {len(O)} lines, by t per game; goal = share scored from the goal row; res_per10 leaves out last-print odds\n",O.round(3).to_string(index=False))
Z=O[O.PASS==True]; print(f"\n== SURVIVORS: {len(Z)}\n",Z.round(3).to_string(index=False) if len(Z) else "none")
from psycopg2.extras import execute_values
cur.execute("CREATE TABLE IF NOT EXISTS finder_touch_clean (mkt text,market_id text,sel bigint,q float8,d float8,side text,t float8,px float8,sz float8,prob float8,how text,v float8,PRIMARY KEY (market_id,sel,q,d,side))")
execute_values(cur,"INSERT INTO finder_touch_clean VALUES %s ON CONFLICT DO NOTHING",[(r.mk,r.m,int(r.sel),float(r.q),float(r.d),r.side,float(r.t),float(r.px),None if r.sz is None or r.sz!=r.sz else float(r.sz),float(r.prob),r.how,float(r.v)) for r in R.itertuples()])
con.close()
print(f"total {time.time()-T0:.0f}s")
PY
