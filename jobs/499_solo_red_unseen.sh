#!/bin/bash
set -o pipefail
# 499_solo_red_unseen (Finder 2026-11-05, queue items 102, 103, from jobs/499_new_division.sh): two lines picked from a table, read on seasons they have not seen. Rules written in the queue before these prices were read. No new cuts.
# READ 1 fd_matches, Pinnacle close (earlier quote if none), book 1.00-1.08, one tick adverse, 2%, £10, to result, halves by date median. CANNOT PASS: a bookmaker quote is not an exchange print, so it only supports or contradicts.
# READ 2 bf_hist_other MATCH_ODDS Jul-Sep 2026, names matched with lib_cand.loose as jobs/499_ht_double_change.sh, market time within 20 min of the af kick-off. First in-play print of each runner within 3 min of market time, all three needed. Too few trades to pass: a negative read closes the line.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import *
import lib_cand; lib_cand._checks()
pd.set_option('display.width',220); pd.set_option('display.max_rows',100); pd.set_option('display.max_columns',30)
T0=time.time()
def bk(x,won):
    a=step(x,-1); return None if a<=1.01 else back_settle(a,won)
def near_count(minutes):
    """Other games within 90 minutes either side, for one division on one date. A game exactly 90 away counts."""
    m=np.asarray(minutes,dtype=float); s=np.sort(m); return np.searchsorted(s,m+90,side='right')-np.searchsorted(s,m-90,side='left')-1
def hhmm(t):
    try:
        h,mi=str(t).split(':')[:2]; return int(h)*60+int(mi)
    except Exception: return None
def red_walk(games):
    """games: (key,when_days,home,away,red_home,red_away) in date order, one division. {key:'H','A' or None}: the team with a red in its previous game within 14 days, the opponent without."""
    last={}; out={}
    for k,d,h,a,rh,ra in games:
        pr=lambda t:(t in last and d-last[t][0]<=14 and last[t][1])
        ph,pa=pr(h),pr(a); out[k]='H' if ph and not pa else 'A' if pa and not ph else None
        last[h]=(d,bool(rh)); last[a]=(d,bool(ra))
    return out
def summ(name,v,h=None):
    v=np.asarray(v,dtype=float)
    if len(v)==0: return dict(line=name,n=0)
    s=np.sort(v); d=dict(line=name,n=len(v),per10=round(v.mean(),3),t=round(tstat(v),2),no_top_win=round(s[:-1].mean(),3) if len(v)>1 else np.nan)
    if h is not None:
        h=np.asarray(h); d['h1']=round(v[h==1].mean(),3) if (h==1).any() else np.nan; d['h2']=round(v[h==2].mean(),3) if (h==2).any() else np.nan
    return d
# known answers, worked by hand
assert list(near_count([900,990,991,1500]))==[1,2,1,0]
assert hhmm('15:00')==900 and hhmm(None) is None and hhmm('')is None
_r=red_walk([(1,0,'A','B',1,0),(2,7,'A','C',0,0),(3,7,'B','D',0,0),(4,14,'A','B',0,1),(5,21,'B','A',0,0),(6,40,'A','B',1,1),(7,60,'A','C',0,0)])
assert _r[1] is None and _r[2]=='H' and _r[3] is None and _r[4] is None and _r[5]=='H' and _r[6] is None and _r[7] is None    # game 7: A's red is 20 days old
_r2=red_walk([(1,0,'A','B',1,1),(2,7,'A','B',0,0)]); assert _r2[2] is None    # both had one
assert abs(bk(2.04,True)-9.996)<1e-9 and bk(2.04,False)==-10.0
print("checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
DIV=['E0','E1','E2','E3','SP1','SP2','I1','I2','D1','D2','F1','F2','N1','P1','SC0']; TOP=['E0','SP1','I1','D1','F1']
D=pd.read_sql("""SELECT div,date,home,away,fthg,ftag,hr,ar,coalesce(psch,psh)::float ph,coalesce(pscd,psd)::float pd,coalesce(psca,psa)::float pa,raw->>'Time' tm FROM fd_matches
 WHERE div=ANY(%s) AND date>='2012-07-01' AND date<'2024-07-01' AND fthg IS NOT NULL AND ftag IS NOT NULL""",con,params=(DIV,))
D['date']=pd.to_datetime(D.date); D=D.sort_values(['div','date']).reset_index(drop=True); D['k']=D.index
print(f"fd rows {len(D)}, with Pinnacle {int(D.ph.notna().sum())}, with time {int(D.tm.notna().sum())}, top five with time {int((D.tm.notna()&D['div'].isin(TOP)).sum())}, {time.time()-T0:.0f}s",flush=True)
bookv=1/D.ph+1/D.pd+1/D.pa; D['ok']=bookv.between(1.0,1.08)
D['res']=np.where(D.fthg>D.ftag,'H',np.where(D.ftag>D.fthg,'A','D'))
# READ 1, item 102
X=D[D['div'].isin(TOP)&D.tm.notna()&D.ok].copy(); X['mn']=X.tm.map(hhmm); X=X[X.mn.notna()]; X['near']=0
for _,g in X.groupby(['div','date']): X.loc[g.index,'near']=near_count(g.mn.values)
rows=[]
for r in X.itertuples():
    pr={'H':r.ph,'D':r.pd,'A':r.pa}; f=min(pr,key=pr.get); v=bk(pr[f],r.res==f)
    if v is None: continue
    l=lay_settle(step(pr[f],1),r.res==f)
    rows.append((r.date,r.near,v,l))
A=pd.DataFrame(rows,columns=['date','near','bk','ly']); med=A.date.median(); A['h']=np.where(A.date<med,1,2)
o=[]
for nm,m in (('SOLO',A.near==0),('PACK',A.near>=3),('ALL',A.near>=0)):
    o.append(summ(f"{nm} fav back",A.bk[m],A.h[m])); o.append(summ(f"{nm} fav lay",A.ly[m],A.h[m]))
print(f"\n== item 102 READ 1, Pinnacle, {A.date.min():%Y-%m-%d} to {A.date.max():%Y-%m-%d}, median {med:%Y-%m-%d}"); print(pd.DataFrame(o).to_string(index=False),flush=True)
# READ 1, item 103
red={}
for _,g in D.groupby('div'):
    g=g.sort_values('date'); red.update(red_walk(list(zip(g.k,(g.date-pd.Timestamp('2012-01-01')).dt.days,g.home,g.away,g.hr.fillna(0)>0,g.ar.fillna(0)>0))))
Y=D[D.ok]; rows=[]
for r in Y.itertuples():
    w=red.get(r.k)
    for side,p,won in (('H',r.ph,r.res=='H'),('A',r.pa,r.res=='A')):
        v=bk(p,won)
        if v is not None: rows.append((r.date,w==side,v,lay_settle(step(p,1),won)))
B=pd.DataFrame(rows,columns=['date','red','bk','ly']); med=B.date.median(); B['h']=np.where(B.date<med,1,2)
o=[summ('RED team back',B.bk[B.red],B.h[B.red]),summ('RED team lay',B.ly[B.red],B.h[B.red]),summ('every team back',B.bk,B.h),summ('every team lay',B.ly,B.h)]
print(f"\n== item 103 READ 1, Pinnacle, median {med:%Y-%m-%d}"); print(pd.DataFrame(o).to_string(index=False),flush=True)
# READ 2, both
F=pd.read_sql("SELECT fixture_id,league_id,kickoff,home,away,hg,ag FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND kickoff>='2026-06-01' AND kickoff<'2026-10-01' AND league_id NOT IN (2,3)",con)
F['ks']=pd.to_datetime(F.kickoff,utc=True).map(lambda t:t.timestamp()); F=F.sort_values('ks').reset_index(drop=True)
RD=pd.read_sql("SELECT DISTINCT fixture_id,is_home FROM af_events WHERE fixture_id=ANY(%s) AND type='Card' AND detail='Red Card' AND is_home IS NOT NULL",con,params=(list(map(int,F.fixture_id)),))
rset={(int(a),bool(b)) for a,b in zip(RD.fixture_id,RD.is_home)}; rw={}
for _,g in F.groupby('league_id'):
    rw.update(red_walk([(r.fixture_id,r.ks/86400,r.home,r.away,(r.fixture_id,True) in rset,(r.fixture_id,False) in rset) for r in g.itertuples()]))
F['near']=0
for _,g in F.groupby('league_id'):
    ks=np.sort(g.ks.values); F.loc[g.index,'near']=np.searchsorted(ks,g.ks.values+5400,side='right')-np.searchsorted(ks,g.ks.values-5400,side='left')-1
U=F[F.ks>=pd.Timestamp('2026-07-01',tz='UTC').timestamp()].reset_index(drop=True); U['H']=U.home.map(norm); U['A']=U.away.map(norm); ksv=U.ks.values
print(f"\n== READ 2, af games Jul-Sep 2026 {len(U)}, red-last states {sum(1 for f in U.fixture_id if rw.get(f))}",flush=True)
cur.execute("""WITH RECURSIVE t AS ((SELECT market_id FROM bf_hist_other WHERE sport='Soccer' AND market_id>=%s AND market_id<%s ORDER BY market_id LIMIT 1)
 UNION ALL SELECT (SELECT market_id FROM bf_hist_other WHERE sport='Soccer' AND market_id>t.market_id AND market_id<%s ORDER BY market_id LIMIT 1) FROM t WHERE t.market_id IS NOT NULL) SELECT market_id FROM t WHERE market_id IS NOT NULL""",('MATCH_ODDS','MATCH_ODDT','MATCH_ODDT'))
ids=[r[0] for r in cur.fetchall() if '|' in r[0]]; seen=defaultdict(list)
for mid in ids:
    _,ev,mt=mid.split('|',2)
    if ' v ' not in ev: continue
    ms=pd.Timestamp(mt).timestamp(); lo,hi=np.searchsorted(ksv,ms-1200),np.searchsorted(ksv,ms+1200,side='right')
    if hi<=lo: continue
    h,_,a=ev.partition(' v '); idx=loose(norm(h),norm(a),[(U.H.iat[i],U.A.iat[i],i) for i in range(lo,hi)])
    if idx is not None: seen[idx].append((mid,h.strip(),a.strip(),ms))
one={k:v[0] for k,v in seen.items() if len(v)==1}; print(f"MATCH_ODDS markets {len(ids)}; af games matched to one market {len(one)}; to several, dropped {sum(len(v)>1 for v in seen.values())}; {time.time()-T0:.0f}s",flush=True)
want=[]
for i,(mid,h,a,ms) in one.items():
    r=U.iloc[i]; top=int(r.league_id) in {39,140,135,78,61}
    if rw.get(r.fixture_id) or (top and (r.near==0 or r.near>=3)): want.append((i,mid,h,a,ms))
mids=[w[1] for w in want]; FP={}
for c in range(0,len(mids),500):
    P=pd.read_sql("SELECT market_id,sel,ts,ltp::float ltp FROM bf_hist_other WHERE sport='Soccer' AND market_id=ANY(%s) AND inplay AND ltp>=1.01 AND ltp<1000",con,params=(mids[c:c+500],))
    P['tt']=(pd.to_datetime(P.ts,utc=True)-pd.Timestamp('1970-01-01',tz='UTC'))/pd.Timedelta(seconds=1)
    for (m,s),g in P.sort_values('tt').groupby(['market_id','sel'],sort=False): FP[(m,s)]=(g.tt.values,g.ltp.values)
con.close()
def first(m,s,ms):
    g=FP.get((m,s))
    if g is None: return None
    i=first_idx(g[0],ms,ms+180)
    return None if i is None else float(g[1][i])
rows=[]; ct=defaultdict(int)
for i,mid,h,a,ms in want:
    r=U.iloc[i]; res='H' if r.hg>r.ag else 'A' if r.ag>r.hg else 'D'
    pr={'H':first(mid,h,ms),'A':first(mid,a,ms),'D':first(mid,'The Draw',ms)}
    top=int(r.league_id) in {39,140,135,78,61}
    w=rw.get(r.fixture_id)
    if w and pr[w] is not None:
        v=bk(pr[w],res==w)
        if v is not None: rows.append(('RED team back',v)); rows.append(('RED team lay',lay_settle(step(pr[w],1),res==w)))
    if top and (r.near==0 or r.near>=3):
        if None in pr.values(): ct['fav: a runner had no print']+=1; continue
        f=min(pr,key=pr.get); st='SOLO_TOP5' if r.near==0 else 'PACK_TOP5'; v=bk(pr[f],res==f)
        if v is not None: rows.append((st+' fav back',v)); rows.append((st+' fav lay',lay_settle(step(pr[f],1),res==f)))
print("skipped",dict(ct))
Z=pd.DataFrame(rows,columns=['line','v']); print(pd.DataFrame([summ(k,x.v) for k,x in Z.groupby('line')]).to_string(index=False))
print("\n== SURVIVORS (neither read can pass: quotes in read 1, n under the bar in read 2)\nnone")
print(f"total {time.time()-T0:.0f}s")
PY
