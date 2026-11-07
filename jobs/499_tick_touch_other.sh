#!/bin/bash
set -o pipefail
# 499_tick_touch_other (Finder 2026-11-07, queue item 384, Finder's own, source a, from items 380 and 357): item 380's first in-play touch on football MO, football OU25, tennis MO. Rule pushed before any price was scored. Reads stream_ticks and liq_sample, local; writes only finder_touch_other, created by this job.
# ENTRY first in-play tick with back_px <= Q after a first in-play tick above Q; bet delay D; fill at the first tick of that runner at least D s later, no more than D+30 s, with a touch on that side, one tick adverse. A suspension between signal and fill, the bet lapses, no trade, counted. No tick in time, no trade, counted.
# RESULT inferred: the runner whose last OPEN back_px is at or under 1.03. Other markets at last-print odds, overround removed; resolved-only printed beside it. Football checked against goal_timeline on exact names. 2%, £10 risk.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))  # this job only
import sys,time,psycopg2,warnings,pandas as pd,numpy as np
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,lay_settle,tstat,passes
from lib_wom import tgame
pd.set_option('display.width',230); pd.set_option('display.max_rows',120); pd.set_option('display.max_columns',30)
T0=time.time()
SQL_TOUCH="""WITH h AS (SELECT market_id,sel_id,min(t) tt FROM {tab} WHERE back_px<=%(q)s GROUP BY 1,2)
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
def score(fn,p,prob):
    """prob 1 or 0 where the result is read, else the last-print chance: the two outcomes weighted, not a coin flip."""
    return fn(p,True)*prob+fn(p,False)*(1-prob)
def infer(last):
    """last: {sel: last OPEN back}. Returns {sel: chance}, resolved flag. Winner at or under 1.03, else 1/price scaled to one."""
    if not last: return {},False
    lo=min(last,key=last.get)
    if last[lo]<=1.03: return {s:(1.0 if s==lo else 0.0) for s in last},True
    tot=sum(1/v for v in last.values()); return {s:(1/v)/tot for s,v in last.items()},False
# known answers, worked by hand
assert abs(bk(2.0,True)-10*.99*.98)<1e-9 and ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9 and np.isnan(bk(1.02,True))
assert infer({1:1.02,2:40.0})==({1:1.0,2:0.0},True)
_i=infer({1:2.0,2:2.0}); assert _i[1] is False and abs(_i[0][1]-.5)<1e-12
_i=infer({1:1.5,2:3.0}); assert abs(_i[0][1]-2/3)<1e-12 and abs(_i[0][2]-1/3)<1e-12   # 0.667+0.333=1.0
assert abs(score(bk,2.0,.5)-(.5*10*.99*.98-.5*10))<1e-9 and score(bk,2.0,1.0)==bk(2.0,True)
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
# hand-worked table: runner 1 touches 2.0 at t=10; D 5 back at t=16 (1.9), lay at t=18 (1.95); suspended at t=17 lapses the lay, not the back. Runner 2 started under Q. Runner 3 touches at t=100, next tick t=200, past D+30. Runner 4 never touches.
cur.execute("CREATE TEMP TABLE tmp_k (market_id text,sel_id bigint,t float8,back_px float8,back_sz float8,lay_px float8,lay_sz float8)")
_r=[('m',1,0.,3.0,5,3.1,5),('m',1,10.,2.0,5,2.1,5),('m',1,12.,1.9,5,None,None),('m',1,16.,1.9,7,None,None),('m',1,18.,None,None,1.95,8),
    ('m',2,0.,1.5,5,1.6,5),('m',2,8.,1.4,5,1.5,5),('n',3,0.,3.0,5,3.1,5),('n',3,100.,2.0,5,2.1,5),('n',3,200.,1.9,5,2.0,5),('n',4,0.,5.0,5,5.1,5),('n',4,60.,4.0,5,4.1,5)]
cur.executemany("INSERT INTO tmp_k VALUES (%s,%s,%s,%s,%s,%s,%s)",_r)
cur.execute(SQL_F.format(tab='tmp_k')); cur.execute("CREATE TEMP TABLE tmp_k_s (market_id text,t float8)"); cur.execute("INSERT INTO tmp_k_s VALUES ('m',17.0)")
def kq(q,d):
    cur.execute(SQL_TOUCH.format(tab='tmp_k'),dict(q=q,d=d)); return sorted(cur.fetchall())
_a=kq(2.0,5.0)
assert _a==[('m',1,3.0,10.0,16.0,1.9,7.0,18.0,1.95,8.0,False,True),('n',3,3.0,100.0,None,None,None,None,None,None,False,False)],_a
cur.execute("DROP TABLE tmp_k,tmp_k_f,tmp_k_s"); print("sql checks: OK",flush=True)
# names for the check against goal_timeline
cur.execute("SELECT DISTINCT ON (market_id) market_id,event_name,ts::date FROM liq_sample WHERE mkt IN ('MO','OU25') AND event_name IS NOT NULL ORDER BY market_id,ts")
NM={m:(e,d) for m,e,d in cur.fetchall()}
cur.execute("""SELECT DISTINCT ON (fixture_id) home_team,away_team,captured_at::date,score_home,score_away,status FROM goal_timeline WHERE captured_at>'2026-11-01' ORDER BY fixture_id,captured_at DESC""")
GT={}
for h,a,d,sh,sa,st in cur.fetchall():
    if st in ('FT','AET','PEN') and sh is not None: GT[(h,a,d)]=(sh,sa)
print(f"goal_timeline finished fixtures since 1 Nov {len(GT)}",flush=True)
def official(m,market,sel_names):
    if m not in NM: return None
    e,d=NM[m]
    if ' v ' not in e: return None
    h,a=e.split(' v ',1)
    for dd in (d,d+pd.Timedelta(days=1).to_pytimedelta()):
        if (h,a,dd) in GT:
            sh,sa=GT[(h,a,dd)]
            if market=='MO': name=h if sh>sa else a if sa>sh else 'The Draw'
            else: name='Over 2.5 Goals' if sh+sa>=3 else 'Under 2.5 Goals'
            return name
    return None
SETS=[('football','MO',(6.0,10.0)),('football','OU25',(6.0,10.0)),('tennis','MO',(5.0,10.0))]
rows=[]; lapse=[]
for sp,mk,DS in SETS:
    cur.execute(f"""CREATE TEMP TABLE tt_{sp}{mk} AS SELECT market_id,sel_id,extract(epoch from pt)::float8 t,back_px::float8 back_px,back_sz::float8 back_sz,lay_px::float8 lay_px,lay_sz::float8 lay_sz FROM stream_ticks WHERE sport=%s AND mkt=%s AND inplay AND status='OPEN' AND pt IS NOT NULL""",(sp,mk))
    tab=f"tt_{sp}{mk}"
    cur.execute(f"CREATE INDEX ON {tab} (market_id,sel_id,t)"); cur.execute(f"ANALYZE {tab}")
    cur.execute(SQL_F.format(tab=tab))
    cur.execute(f"CREATE TEMP TABLE {tab}_s AS SELECT DISTINCT market_id,extract(epoch from pt)::float8 t FROM stream_ticks WHERE sport=%s AND mkt=%s AND inplay AND status='SUSPENDED' AND pt IS NOT NULL",(sp,mk))
    cur.execute(f"CREATE INDEX ON {tab}_s (market_id,t)"); cur.execute(f"ANALYZE {tab}_s")
    cur.execute(f"SELECT count(*),count(DISTINCT market_id),min(t),max(t) FROM {tab}"); nt,nm,lo,hi=cur.fetchone()
    print(f"\n{sp} {mk}: ticks {nt:,}, markets {nm}, {pd.to_datetime(lo,unit='s')} to {pd.to_datetime(hi,unit='s')}, {time.time()-T0:.0f}s",flush=True)
    cur.execute(f"SELECT DISTINCT ON (market_id,sel_id) market_id,sel_id,back_px FROM {tab} WHERE back_px IS NOT NULL ORDER BY market_id,sel_id,t DESC")
    L={}
    for m,s,b in cur.fetchall(): L.setdefault(m,{})[int(s)]=b
    PR={m:infer(v) for m,v in L.items()}; nres=sum(v[1] for v in PR.values()); print(f"  resolved at or under 1.03: {nres} of {len(PR)} ({nres/max(1,len(PR)):.3f})",flush=True)
    if sp=='football':
        cur.execute("SELECT DISTINCT ON (market_id,sel_id) market_id,sel_id,sel FROM stream_ticks WHERE sport='football' AND mkt=%s AND inplay AND sel IS NOT NULL ORDER BY market_id,sel_id,pt DESC",(mk,))
        SN={(m,int(s)):n for m,s,n in cur.fetchall()}; ok=bad=0; badl=[]
        for m,(pr,res) in PR.items():
            if not res: continue
            nm_=official(m,mk,None)
            if nm_ is None: continue
            w=max(pr,key=pr.get); wn=SN.get((m,w))
            if wn is None: continue
            if wn==nm_ or (nm_=='The Draw' and wn.lower() in ('the draw','draw')): ok+=1
            else: bad+=1; badl.append((NM[m][0],wn,nm_))
        print(f"  check against goal_timeline, exact names: agree {ok}, differ {bad}, share {ok/max(1,ok+bad):.3f}; first differing {badl[:6]}",flush=True)
    for q in (2,1.5,1.3,1.2,1.1):
        for d in DS:
            cur.execute(SQL_TOUCH.format(tab=tab),dict(q=q,d=d)); got=cur.fetchall(); nl=[0,0,0]; print(f"  q {q} d {d}: touched {len(got)} | {time.time()-T0:.0f}s",flush=True)
            for m,sel,st,tt,tb,pb,sb,tl,pl,sl,bs,ls in got:
                sel=int(sel); pr,res=PR.get(m,({},False)); prob=pr.get(sel)
                if prob is None: nl[2]+=1; continue
                if pb is None: nl[0]+=1
                elif bs: nl[1]+=1
                else:
                    v=score(bk,pb,prob)
                    if v==v: rows.append((sp,mk,m,sel,q,d,'back',tb,pb,sb,prob,res,v))
                if pl is not None and not ls: rows.append((sp,mk,m,sel,q,d,'lay',tl,pl,sl,prob,res,score(ly,pl,prob)))
            lapse.append((sp,mk,q,d,len(got),nl[0],nl[1],nl[2]))
    cur.execute(f"DROP TABLE {tab},{tab}_f,{tab}_s")
print("\n== entries with no trade: sport market q delay touched, no back tick in time, back lapsed on a suspension, no price at the end\n",pd.DataFrame(lapse,columns='sp mk q d touched notick lapsed noend'.split()).to_string(index=False),flush=True)
R=pd.DataFrame(rows,columns='sp mk m sel q d side t px sz prob res v'.split()); print(f"entries {len(R):,}",flush=True)
def tab_(x,**k):
    v=x.v.values; md=np.median(x.t.values); h=x.t.values<md; a,b=v[h],v[~h]; tr=tgame(v,x.m.values); z=x[x.res]
    return dict(**k,n=len(v),games=x.m.nunique(),per10=v.mean(),t=tstat(v),tr=tr,h1=a.mean() if len(a) else np.nan,h2=b.mean() if len(b) else np.nan,res_share=x.res.mean(),res_per10=z.v.mean() if len(z) else np.nan,res_t=tgame(z.v.values,z.m.values) if len(z)>1 else 0.0,won=x.prob.mean(),imp=(1/x.px).mean(),fill=x.px.median(),sz=x.sz.median(),PASS=passes(len(v),len(a),len(b),tr,a.mean() if len(a) else 0,b.mean() if len(b) else 0,v.mean()))
O=pd.DataFrame([tab_(x,sp=k[0],mk=k[1],q=k[2],delay=k[3],side=k[4]) for k,x in R.groupby(['sp','mk','q','d','side'])]).sort_values('tr',ascending=False)
print(f"\n== ITEM 384: {len(O)} lines, by t per game; res_ columns score resolved markets only\n",O.round(3).to_string(index=False))
Z=O[O.PASS==True]; print(f"\n== SURVIVORS: {len(Z)}\n",Z.round(3).to_string(index=False) if len(Z) else "none")
# stream_ticks rolls: keep the entries so an unseen re-read can pool them.
from psycopg2.extras import execute_values
cur.execute("CREATE TABLE IF NOT EXISTS finder_touch_other (sport text,mkt text,market_id text,sel bigint,q float8,d float8,side text,t float8,px float8,sz float8,prob float8,res boolean,v float8,PRIMARY KEY (market_id,sel,q,d,side))")
execute_values(cur,"INSERT INTO finder_touch_other VALUES %s ON CONFLICT DO NOTHING",[(r.sp,r.mk,r.m,int(r.sel),float(r.q),float(r.d),r.side,float(r.t),float(r.px),None if r.sz!=r.sz or r.sz is None else float(r.sz),float(r.prob),bool(r.res),float(r.v)) for r in R.itertuples()])
con.close()
print(f"total {time.time()-T0:.0f}s")
PY
