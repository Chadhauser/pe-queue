#!/bin/bash
set -o pipefail
# 499_tick_touch_cs (Finder 2026-11-07, queue item 387, Finder's own, source a, from items 385, 386): item 385's football entries, settled from the correct-score market. Unresolved entries graded as -£10 losers, the worst case; a line passes only on that. Rule pushed before this job read a price, though items 385 and 386's prints had been seen. Writes only finder_touch_cs, created by this job, so stream_ticks rolling loses nothing.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))  # this job only
import sys,time,datetime,re,psycopg2,warnings,pandas as pd,numpy as np
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
def cs_read(sel):
    """CS selection to (side for MO: H, A or D; goals at least). None if not a score."""
    s=str(sel).upper().replace(' ','')
    if s=='ANYOTHERHOMEWIN': return ('H',4)
    if s=='ANYOTHERAWAYWIN': return ('A',4)
    if s=='ANYOTHERDRAW': return ('D',8)
    m=re.fullmatch(r'(\d+)-(\d+)',s)
    if not m: return None
    h,a=int(m.group(1)),int(m.group(2)); return ('H' if h>a else 'A' if a>h else 'D',h+a)
def win_ou(name,goals): return str(name).lower().startswith('over')==(goals>=3)
def win_mo(name,side,hn,an):
    if side=='H': return name==hn
    if side=='A': return name==an
    return 'draw' in str(name).lower()
# known answers, worked by hand
assert abs(bk(2.0,True)-10*.99*.98)<1e-9 and ly(2.0,True)==-10.0 and abs(ly(2.0,False)-10/1.02*.98)<1e-9 and np.isnan(bk(1.02,True))
assert cs_read('2-1')==('H',3) and cs_read('0-0')==('D',0) and cs_read('1-3')==('A',4) and cs_read('ANYOTHERAWAYWIN')==('A',4) and cs_read('ANYOTHERDRAW')==('D',8) and cs_read('15') is None
assert win_ou('Over 2.5 Goals',3) and not win_ou('Under 2.5 Goals',3) and win_ou('Under 2.5 Goals',2) and not win_ou('Over 2.5 Goals',2)
assert win_mo('Leeds','A','Spurs','Leeds') and not win_mo('Spurs','A','Spurs','Leeds') and win_mo('The Draw','D','Spurs','Leeds') and not win_mo('Spurs','D','Spurs','Leeds')
print("known-answer checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("""SELECT DISTINCT ON (event_name,market_id) event_name,market_id,sel,minute,ts,back_px FROM liq_sample WHERE mkt='CS' AND minute>=85 AND back_px<=1.2 AND lay_px<=1.3 ORDER BY event_name,market_id,ts DESC""")
CSR={}
for e,m,sel,mn,ts,b in cur.fetchall():
    r=cs_read(sel)
    if r: CSR[(e,ts.date())]=r; CSR[(e,(ts-datetime.timedelta(hours=8)).date())]=r
print(f"CS finals {len(set(CSR.values()))} kinds, keys {len(CSR)}, {time.time()-T0:.0f}s",flush=True)
cur.execute("SELECT DISTINCT ON (market_id) market_id,mkt,event_name,ts::date FROM liq_sample WHERE mkt IN ('MO','OU25') AND event_name IS NOT NULL ORDER BY market_id,ts")
NM={m:(e,d) for m,mk,e,d in cur.fetchall()}
def cs_of(m):
    if m not in NM: return None
    e,d=NM[m]
    return CSR.get((e,d)) or CSR.get((e,d+datetime.timedelta(days=1)))
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
rows=[]; info=[]
for mk in ('MO','OU25'):
    tab=f"tq_{mk}"
    cur.execute(f"""CREATE TEMP TABLE {tab} AS SELECT market_id,sel_id,sel,extract(epoch from pt)::float8 t,back_px::float8 back_px,back_sz::float8 back_sz,lay_px::float8 lay_px,lay_sz::float8 lay_sz FROM stream_ticks WHERE sport='football' AND mkt=%s AND inplay AND status='OPEN' AND pt IS NOT NULL""",(mk,))
    cur.execute(f"CREATE INDEX ON {tab} (market_id,sel_id,t)"); cur.execute(f"ANALYZE {tab}")
    cur.execute(f"CREATE TEMP TABLE {tab}_f AS SELECT DISTINCT ON (market_id,sel_id) market_id,sel_id,back_px st FROM {tab} WHERE back_px IS NOT NULL ORDER BY market_id,sel_id,t")
    cur.execute(f"CREATE TEMP TABLE {tab}_s AS SELECT DISTINCT market_id,extract(epoch from pt)::float8 t FROM stream_ticks WHERE sport='football' AND mkt=%s AND inplay AND status='SUSPENDED' AND pt IS NOT NULL",(mk,))
    cur.execute(f"CREATE INDEX ON {tab}_s (market_id,t)"); cur.execute(f"ANALYZE {tab}_s")
    cur.execute(f"SELECT DISTINCT ON (market_id,sel_id) market_id,sel_id,sel,back_px FROM {tab} WHERE back_px IS NOT NULL ORDER BY market_id,sel_id,t DESC")
    NAMES={}; UL={}
    for m,s,n,b in cur.fetchall():
        NAMES.setdefault(m,{})[int(s)]=n
        if str(n).lower().startswith('under'): UL[m]=b
    res=0; none=0; conflict=0; ok=bad=0; diff=[]; RS={}
    for m in NAMES:
        r=cs_of(m)
        if r is None: none+=1; continue
        if mk=='OU25' and r[1]<3 and UL.get(m,9.0)>1.05: conflict+=1; continue
        RS[m]=r; res+=1
        fin=final_of(*NM[m]) if m in NM else None
        if fin is not None:
            same=(r[0]==('H' if fin[0]>fin[1] else 'A' if fin[1]>fin[0] else 'D')) if mk=='MO' else ((r[1]>=3)==(sum(fin)>=3))
            if same: ok+=1
            else: bad+=1; diff.append((NM[m][0],fin,r))
    share=ok/max(1,ok+bad); READ=share>=0.95 and ok+bad>=30; info.append((mk,READ))
    print(f"\nfootball {mk}: markets {len(NAMES)}, result {res}, no CS final {none}, conflict {conflict}; goal row agree {ok}, differ {bad}, share {share:.3f}, can pass {READ}; first differing {diff[:5]} | {time.time()-T0:.0f}s",flush=True)
    for q in (2,1.5,1.3,1.2,1.1):
        for d in (6.0,10.0):
            cur.execute(SQL_TOUCH.format(tab=tab),dict(q=q,d=d))
            for m,sel,st,tt,tb,pb,sb,tl,pl,sl,bs,ls in cur.fetchall():
                sel=int(sel); nm=NAMES.get(m,{}).get(sel,''); r=RS.get(m)
                if r is None: won=None
                elif mk=='OU25': won=win_ou(nm,r[1])
                else:
                    hn,an=(NM[m][0].split(' v ',1)+[''])[:2] if m in NM else ('','')
                    won=win_mo(nm,r[0],hn,an)
                if pb is not None and not bs:
                    a=step(pb,-1)
                    if a>1.01: rows.append((mk,m,sel,q,d,'back',tb,pb,sb,won,-10.0 if won is None else bk(pb,won)))
                if pl is not None and not ls: rows.append((mk,m,sel,q,d,'lay',tl,pl,sl,won,-10.0 if won is None else ly(pl,won)))
    cur.execute(f"DROP TABLE {tab},{tab}_f,{tab}_s")
R=pd.DataFrame(rows,columns='mk m sel q d side t px sz won v'.split()); print(f"entries {len(R):,}, unresolved share {R.won.isna().mean():.3f}",flush=True)
READ=dict(info)
def tab_(x,**k):
    v=x.v.values; md=np.median(x.t.values); h=x.t.values<md; a,b=v[h],v[~h]; tr=tgame(v,x.m.values); z=x[x.won.notna()]
    return dict(**k,n=len(v),games=x.m.nunique(),unres=x.won.isna().sum(),worst=v.mean(),tr=tr,n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,mid_n=len(z),mid=z.v.mean() if len(z) else np.nan,mid_t=tgame(z.v.values,z.m.values) if len(z)>1 else 0.0,won=z.won.astype(float).mean() if len(z) else np.nan,fill=x.px.median(),imp=(1/x.px).mean(),sz=x.sz.median(),PASS=READ[k['mk']] and passes(len(v),len(a),len(b),tr,a.mean() if len(a) else 0,b.mean() if len(b) else 0,v.mean()))
O=pd.DataFrame([tab_(x,mk=k[0],q=k[1],delay=k[2],side=k[3]) for k,x in R.groupby(['mk','q','d','side'])]).sort_values('mid_t',ascending=False)
print(f"\n== ITEM 387: {len(O)} lines, by the middle read's t; worst = unresolved as -£10; PASS on worst only\n",O.round(3).to_string(index=False))
Z=O[O.PASS==True]; print(f"\n== SURVIVORS: {len(Z)}\n",Z.round(3).to_string(index=False) if len(Z) else "none")
from psycopg2.extras import execute_values
cur.execute("CREATE TABLE IF NOT EXISTS finder_touch_cs (mkt text,market_id text,sel bigint,q float8,d float8,side text,t float8,px float8,sz float8,won boolean,v float8,PRIMARY KEY (market_id,sel,q,d,side))")
execute_values(cur,"INSERT INTO finder_touch_cs VALUES %s ON CONFLICT DO NOTHING",[(r.mk,r.m,int(r.sel),float(r.q),float(r.d),r.side,float(r.t),float(r.px),None if r.sz is None or r.sz!=r.sz else float(r.sz),None if r.won is None or r.won!=r.won else bool(r.won),float(r.v)) for r in R.itertuples()])
con.close()
print(f"total {time.time()-T0:.0f}s")
PY
