#!/bin/bash
set -o pipefail
# 499_tick_touch_ou25 (Finder 2026-11-07, queue item 386, Finder's own, source a, from item 385): item 385's OU25 entries, result read from the market. Under won if Under's last OPEN back <= 1.03; Over won if the OU25 market's last OPEN tick is 5 min or more before that game's MO last OPEN tick; else not scored, counted. Rule pushed before this job read a price. Read only, temp tables.
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
def bk(p,w):
    a=step(p,-1); return np.nan if a<=1.01 else back_settle(a,w)
def ly(p,w): return lay_settle(step(p,1),w)
def ou_result(under_last,t_ou,t_mo):
    """'Under', 'Over' or None. Under's last back at or under 1.03 wins first; a market that stops 300 s or more before its game's MO was closed by the third goal."""
    if under_last is not None and under_last<=1.03: return 'Under'
    if t_ou is not None and t_mo is not None and t_mo-t_ou>=300: return 'Over'
    return None
# known answers, worked by hand
assert abs(bk(2.0,True)-10*.99*.98)<1e-9 and ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9 and np.isnan(bk(1.02,True))
assert ou_result(1.02,1000,1100)=='Under' and ou_result(1.5,1000,1300)=='Over' and ou_result(1.5,1000,1299) is None and ou_result(None,1000,None) is None and ou_result(1.02,1000,5000)=='Under'
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SELECT DISTINCT ON (market_id) market_id,mkt,event_name,ts::date FROM liq_sample WHERE mkt IN ('MO','OU25') AND event_name IS NOT NULL ORDER BY market_id,ts")
NM={}; MOF={}
for m,mk,e,d in cur.fetchall():
    NM[m]=(mk,e,d)
    if mk=='MO': MOF[(e,d)]=m
cur.execute("SELECT market_id,max(extract(epoch from pt))::float8 FROM stream_ticks WHERE sport='football' AND mkt='MO' AND inplay AND status='OPEN' AND pt IS NOT NULL GROUP BY 1")
TMO=dict(cur.fetchall()); print(f"MO games with a last tick {len(TMO)}, {time.time()-T0:.0f}s",flush=True)
rc=psycopg2.connect(creds.pg_railway(),sslmode='require'); k=rc.cursor(); k.execute("SET statement_timeout='600s'")
k.execute("""SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,captured_at::date,score_home,score_away,status,minute FROM goal_timeline WHERE captured_at>'2026-11-01' ORDER BY fixture_id,captured_at DESC""")
G=k.fetchall(); rc.close(); FIN={}
for f,h,a,d,sh,sa,st,mn in G:
    if st=='2H' and mn is not None and mn>=85 and sh is not None and sa is not None: FIN.setdefault(d,[]).append((norm(h),norm(a),(sh,sa)))
def final_of(e,d):
    if ' v ' not in e: return None
    h,a=e.split(' v ',1); c=[]
    for dd in (d,d-datetime.timedelta(days=1),d+datetime.timedelta(days=1)): c+=FIN.get(dd,[])
    return loose(norm(h),norm(a),c) if c else None
tab='tc_ou'
cur.execute(f"""CREATE TEMP TABLE {tab} AS SELECT market_id,sel_id,sel,extract(epoch from pt)::float8 t,back_px::float8 back_px,back_sz::float8 back_sz,lay_px::float8 lay_px,lay_sz::float8 lay_sz FROM stream_ticks WHERE sport='football' AND mkt='OU25' AND inplay AND status='OPEN' AND pt IS NOT NULL""")
cur.execute(f"CREATE INDEX ON {tab} (market_id,sel_id,t)"); cur.execute(f"ANALYZE {tab}")
cur.execute(f"CREATE TEMP TABLE {tab}_f AS SELECT DISTINCT ON (market_id,sel_id) market_id,sel_id,back_px st FROM {tab} WHERE back_px IS NOT NULL ORDER BY market_id,sel_id,t")
cur.execute(f"CREATE TEMP TABLE {tab}_s AS SELECT DISTINCT market_id,extract(epoch from pt)::float8 t FROM stream_ticks WHERE sport='football' AND mkt='OU25' AND inplay AND status='SUSPENDED' AND pt IS NOT NULL")
cur.execute(f"CREATE INDEX ON {tab}_s (market_id,t)"); cur.execute(f"ANALYZE {tab}_s")
cur.execute(f"SELECT DISTINCT ON (market_id,sel_id) market_id,sel_id,sel,back_px FROM {tab} WHERE back_px IS NOT NULL ORDER BY market_id,sel_id,t DESC")
UL={}; NAMES={}
for m,s,n,b in cur.fetchall():
    NAMES.setdefault(m,{})[int(s)]=n
    if str(n).lower().startswith('under'): UL[m]=b
cur.execute(f"SELECT market_id,max(t) FROM {tab} GROUP BY 1"); TOU=dict(cur.fetchall())
RES={}; cnt={'Under':0,'Over':0,'none':0,'no_mo':0}; ok=bad=0; diff=[]
for m,tou in TOU.items():
    mk,e,d=NM.get(m,(None,None,None)); mo=MOF.get((e,d)) if e else None
    if mo is None or mo not in TMO: cnt['no_mo']+=1
    r=ou_result(UL.get(m),tou,TMO.get(mo) if mo else None)
    if r is None: cnt['none']+=1; continue
    cnt[r]+=1; RES[m]=r
    fin=final_of(e,d) if e else None
    if fin is not None:
        g='Over' if sum(fin)>=3 else 'Under'
        if g==r: ok+=1
        else: bad+=1; diff.append((e,fin,r))
share=ok/max(1,ok+bad); READ=share>=0.95 and ok+bad>=30
print(f"OU25 markets {len(TOU)}, results {cnt}; check on the goal row: agree {ok}, differ {bad}, share {share:.3f}, a read: {READ}; first differing {diff[:5]} | {time.time()-T0:.0f}s",flush=True)
rows=[]; nores=[]
for q in (2,1.5,1.3,1.2,1.1):
    for d in (6.0,10.0):
        cur.execute(SQL_TOUCH.format(tab=tab),dict(q=q,d=d)); got=cur.fetchall(); nr=0
        for m,sel,st,tt,tb,pb,sb,tl,pl,sl,bs,ls in got:
            sel=int(sel); r=RES.get(m)
            if r is None: nr+=1; continue
            won=str(NAMES[m].get(sel,'')).lower().startswith(r.lower())
            if pb is not None and not bs:
                v=bk(pb,won)
                if v==v: rows.append((m,sel,q,d,'back',tb,pb,sb,won,r,v))
            if pl is not None and not ls: rows.append((m,sel,q,d,'lay',tl,pl,sl,won,r,ly(pl,won)))
        nores.append((q,d,len(got),nr))
print("touched and not scored: q delay touched noresult",nores,flush=True)
R=pd.DataFrame(rows,columns='m sel q d side t px sz won r v'.split()); print(f"entries {len(R):,}; Under wins share of markets {cnt['Under']/max(1,cnt['Under']+cnt['Over']):.3f}",flush=True)
def tab_(x,**k):
    v=x.v.values; md=np.median(x.t.values); h=x.t.values<md; a,b=v[h],v[~h]; tr=tgame(v,x.m.values)
    return dict(**k,n=len(v),games=x.m.nunique(),per10=v.mean(),t=tstat(v),tr=tr,n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,won=x.won.mean(),fill=x.px.median(),imp=(1/x.px).mean(),sz=x.sz.median(),PASS=READ and passes(len(v),len(a),len(b),tr,a.mean() if len(a) else 0,b.mean() if len(b) else 0,v.mean()))
O=pd.DataFrame([tab_(x,q=k[0],delay=k[1],side=k[2]) for k,x in R.groupby(['q','d','side'])]).sort_values('tr',ascending=False)
print(f"\n== ITEM 386: {len(O)} lines, by t per game\n",O.round(3).to_string(index=False))
Z=O[O.PASS==True]; print(f"\n== SURVIVORS: {len(Z)}\n",Z.round(3).to_string(index=False) if len(Z) else "none")
con.close()
print(f"total {time.time()-T0:.0f}s")
PY
