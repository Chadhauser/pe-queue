#!/bin/bash
set -o pipefail
# 499_alt_line_arb (Finder 2026-11-07, queue item 375, Finder's own, source c): a riskless cross between neighbouring alternative lines at the real in-play touch on ip_tape. Rule pushed before any lock was summed. Read only.
# LINES ip_tape has no line number. A frame's rows keep book order, so physical row order within one (market, ts, selection) gives neighbours; direction per market and selection is that day's majority. The job prints how often the order holds; a pass goes to a recorder item, not to live.
# LOCK back £B at a on the easier line, lay £B x a/b at b on the harder line: both covered and neither covered both pay B x (a/b - 1), the middle pays more. Worked in the asserts. 2% on the profit.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import resource; resource.setrlimit(resource.RLIMIT_AS,(1_500_000_000,1_500_000_000))  # this job only
import sys,time,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import LD
import lib_cand; lib_cand._checks()
pd.set_option('display.width',230); pd.set_option('display.max_rows',100); pd.set_option('display.max_columns',30)
T0=time.time(); GAP=30.0; DELAY=5.0
def down(p):
    p=np.asarray(p,dtype=float); return LD[np.clip(np.searchsorted(LD,p-1e-9,side='left')-1,0,len(LD)-1)]
def up(p):
    p=np.asarray(p,dtype=float); return LD[np.clip(np.searchsorted(LD,p+1e-9,side='right'),0,len(LD)-1)]
def outcomes(a,b,B=10.0):
    """back B at a on the easier line, lay L=B*a/b at b on the harder line: (both covered, middle, neither), before commission."""
    L=B*a/b
    return (B*(a-1)-L*(b-1), B*(a-1)+L, -B+L)
def lock10(a,b): return 10*(np.asarray(a,float)/np.asarray(b,float)-1)
def episodes(ts,gap=GAP):
    """sorted seconds of crossed frames for one pair: episode number per frame"""
    ts=np.asarray(ts,float); return np.concatenate([[0],np.cumsum(np.diff(ts)>gap)]) if len(ts) else np.array([],dtype=int)
# known answers, worked by hand
o=outcomes(2.2,2.0); assert abs(o[0]-1.0)<1e-9 and abs(o[2]-1.0)<1e-9 and abs(o[1]-23.0)<1e-9 and abs(lock10(2.2,2.0)-1.0)<1e-9
assert list(episodes([0,10,40,71,100]))==[0,0,0,1,1] and list(episodes([0,31]))==[0,1]
assert down(2.0)==1.99 and up(2.0)==2.02 and down(50.0)==48.0 and up(50.0)==55.0
print("checks: OK",flush=True)
if len(sys.argv)>1 and sys.argv[1]=='asserts-only': sys.exit(0)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
cur.execute("SELECT min(ts),max(ts) FROM ip_tape"); lo,hi=cur.fetchone(); print("tape",lo,hi,flush=True)
days=pd.date_range(pd.Timestamp(lo).tz_convert('UTC').normalize(),pd.Timestamp(hi).tz_convert('UTC').normalize(),freq='D')
SPORTS="('basketball','american_football','rugby_union','australian_rules','ice_hockey','baseball','rugby_league')"
ALL=[];ST=[]
for d in days:
    d2=d+pd.Timedelta(days=1)
    # Done in SQL with a temp table on disk: the box had about 1 GB free, and 3M+ rows a day in pandas could threaten the recorders.
    cur.execute("DROP TABLE IF EXISTS tmp_alt")
    cur.execute(f"""CREATE TEMP TABLE tmp_alt AS
      SELECT sport,market_id,market_type,ts,sel_id,back_px,back_sz,lay_px,lay_sz,
             (row_number() OVER f)-1 j, lag(back_px) OVER f bp0, lag(lay_px) OVER f lp0, lag(back_sz) OVER f bs0, lag(lay_sz) OVER f ls0
      FROM ip_tape WHERE ts>=%s AND ts<%s AND sport IN {SPORTS} AND market_type IN ('HANDICAP','COMBINED_TOTAL') AND status='OPEN'
      WINDOW f AS (PARTITION BY market_id,ts,sel_id ORDER BY ctid)""",(d.to_pydatetime(),d2.to_pydatetime()))
    cur.execute("SELECT count(*),count(DISTINCT market_id) FROM tmp_alt"); nr,nm=cur.fetchone()
    if not nr: continue
    cur.execute("""CREATE TEMP TABLE tmp_dir AS SELECT market_id,sel_id,count(*) FILTER (WHERE back_px>bp0) n_up,count(*) FILTER (WHERE back_px<bp0) n_dn,count(*) FILTER (WHERE back_px=bp0) n_eq FROM tmp_alt WHERE bp0 IS NOT NULL AND back_px IS NOT NULL GROUP BY 1,2""")
    cur.execute("SELECT coalesce(sum(greatest(n_up,n_dn)+n_eq),0)::float8/nullif(sum(n_up+n_dn+n_eq),0) FROM tmp_dir"); agree=cur.fetchone()[0]
    V=pd.read_sql("""SELECT w.sport,w.market_id,w.market_type,extract(epoch from w.ts)::float8 t,w.sel_id,w.j,
          CASE WHEN x.n_up>x.n_dn THEN w.bp0 ELSE w.back_px END::float8 a, CASE WHEN x.n_up>x.n_dn THEN w.lay_px ELSE w.lp0 END::float8 b,
          CASE WHEN x.n_up>x.n_dn THEN w.bs0 ELSE w.back_sz END::float8 sa, CASE WHEN x.n_up>x.n_dn THEN w.lay_sz ELSE w.ls0 END::float8 sb
        FROM tmp_alt w JOIN tmp_dir x USING (market_id,sel_id)
        WHERE (x.n_up>x.n_dn AND w.bp0>w.lay_px) OR (x.n_dn>x.n_up AND w.back_px>w.lp0)""",con)
    V=V[(V.a<=50)&(V.b<=50)]
    ST.append(dict(day=str(d.date()),rows=nr,markets=nm,order_agrees=round(agree,4) if agree is not None else None,crossed=len(V)))
    ALL.append(V); print(ST[-1],f"{time.time()-T0:.0f}s",flush=True)
    cur.execute("DROP TABLE tmp_alt; DROP TABLE tmp_dir")
con.close()
V=pd.concat(ALL,ignore_index=True).sort_values(['market_id','sel_id','j','t']); print(f"crossed frames {len(V):,}, markets {V.market_id.nunique()}",flush=True)
print("\n== raw crossed frames by sport, market\n",V.groupby(['sport','market_type']).agg(frames=('t','size'),markets=('market_id','nunique'),a_b=('a',lambda s:0)).drop(columns='a_b').to_string(),flush=True)
E=[]
for (m,s,j),x in V.groupby(['market_id','sel_id','j'],sort=False):
    ep=episodes(x.t.values)
    for e in np.unique(ep):
        y=x[ep==e]; t0=y.t.iloc[0]; late=y[y.t>=t0+DELAY]
        r=dict(sport=y.sport.iloc[0],mt=y.market_type.iloc[0],market=m,t0=t0,dur=y.t.iloc[-1]-t0,frames=len(y),a0=y.a.iloc[0],b0=y.b.iloc[0],take=False)
        if len(late):
            z=late.iloc[0]; a=float(down(z.a)); b=float(up(z.b)); lk=float(lock10(a,b)); B=min(10.0,z.sa,z.sb*b/a) if a>1.01 else 0.0
            r.update(take=True,a=z.a,b=z.b,lock=lk*.98 if lk>0 else lk,size=B,lock_raw=float(lock10(z.a,z.b))*.98)
        E.append(r)
E=pd.DataFrame(E); print(f"episodes {len(E):,}; takeable, still crossed {DELAY:.0f}s on, {int(E['take'].sum()):,}; median duration {E.dur.median():.0f}s",flush=True)
T=E[E['take']].copy(); md=T.t0.median() if len(T) else 0
def row(x,k):
    h=x.t0<md; v=x.lock.values
    return dict(line=k,n=len(x),markets=x.market.nunique(),lock=v.mean(),lock_raw=x.lock_raw.mean(),h1=v[h.values].mean() if h.any() else np.nan,n1=int(h.sum()),h2=v[~h.values].mean() if (~h).any() else np.nan,n2=int((~h).sum()),pos=(v>0).mean(),size=x['size'].median(),dur=x.dur.median(),gbp=(x.lock*x['size']/10).sum(),PASS=bool(len(x)>=300 and h.sum()>=150 and (~h).sum()>=150 and v.mean()>=.15 and v[h.values].mean()>0 and v[~h.values].mean()>0))
if len(T):
    out=[row(x,f"{k[0]} {k[1]}") for k,x in T.groupby(['sport','mt'])]; S=T[T['size']>=2]
    out+=[row(x,f"{k[0]} {k[1]} size>=2") for k,x in S.groupby(['sport','mt'])]; out.append(row(S,'ALL size>=2'))
    O=pd.DataFrame(out).sort_values('lock',ascending=False); print("\n== ITEM 375, takeable episodes, per £10, one tick adverse each side, 2%; lock_raw no tick; gbp the sum at the size on show\n",O.round(3).to_string(index=False))
    print("\nlargest raw crosses, for the eye\n",T.sort_values('lock_raw',ascending=False).head(10)[['sport','mt','market','dur','frames','a','b','lock_raw','size']].round(3).to_string(index=False))
    Z=O[O.PASS&O.line.str.contains('size>=2')]; print(f"\n== SURVIVORS: {len(Z)}\n",Z.round(3).to_string(index=False) if len(Z) else "none")
else: print("\n== SURVIVORS: 0, none takeable")
print(f"total {time.time()-T0:.0f}s")
PY
