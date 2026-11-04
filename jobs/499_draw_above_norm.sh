#!/bin/bash
set -o pipefail
# 499_draw_above_norm (Finder 2026-11-04, queue item 57): IS A FRESH DRAW PRICE ABOVE ITS SAME-STATE NORM TOO LONG? bf_hist_price MO DRAW x af_events x af_fixtures, then liq_sample x goal_timeline. The number 499 is reused with a new slug: 450-499 are all taken.
# STATES: level scores 0-0, 1-1, 2-2, 3-3, tape minutes 60..89, goal known 2+ minutes (af minute <= print minute - 2).
# NORM, season 2024 ONLY: median print by state and 5-minute band, from prints whose last goal is 20+ minutes old (0-0: every print). ratio = print / norm. No norm for a cell with under 30 prints: no trade.
# SIGNAL: first print per game in the ratio range, and under 0.8 x the last print in g-6..g-2 before the last goal (none = kept). One entry per game per line.
# FILL: the NEXT real print within 1..3 minutes, as the signal print has been seen; none = no trade, counted. FOUR ticks adverse (the real touch runs a median 3 ticks under LTP, plus the house tick), per the item; k=1 shown. Back £10, 2% commission. Settle on FT; g8 = next goal +8 first real print, else result, one tick adverse on the exit.
# RATIO RANGES: 1.05-1.25 is the item's; 1.05-1.10, 1.10-1.15, 1.15-1.25 and 0.95-1.05 (control). The cut is CHOSEN on 2024 (best per10 at k=4, settle, n >= 100) and SCORED on 2025 only; halves at the 2025 median date. 2024 prints set the norm, so 2024 lines are in sample.
# FORWARD: goal_timeline level score held 120 s at 60'+, liq_sample real back touch, the same norm and range on back_px, fill on the next row within 120 s, one tick adverse. Result: last goal_timeline row at 85'+, unknown = -£10. No pre-goal check, as the touch needs no stale guard.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,time,unicodedata,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',240); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',40)
T0=time.time()
LD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    v=lo
    while v<hi-1e-9: LD.append(round(v,2)); v+=st
LD.append(1000.0); LD=np.array(LD)
def ix(p): return int(np.searchsorted(LD,round(float(p),2)-1e-9))
def dn(p,k=1): return float(LD[max(ix(p)-k,0)])
def up(p,k=1): return float(LD[min(ix(p)+k,len(LD)-1)])
def net(x): return x*0.98 if x>0 else x
def back(a,won): return net(10*(a-1)) if won else -10.0
def hedge(a,q): return net(10*(a/up(q)-1))
def band(m): return int(m//5*5)
def state_at(gl,m):
    h=sum(1 for g,s in gl if g<=m and s=='h'); a=sum(1 for g,s in gl if g<=m and s=='a'); return h,a
def level_known(gl,m):
    """State key if the score at m is level, at most 3-3, and the last goal is at least 2 minutes old; else None."""
    h,a=state_at(gl,m)
    if h!=a or h>3: return None
    if max([g for g,_ in gl if g<=m],default=-99)>m-2: return None
    return f'{h}-{a}'
def pre_price(arr,g):
    for m in range(g-2,g-7,-1):
        if 0<=m<len(arr) and not np.isnan(arr[m]): return float(arr[m])
    return None
def signal(arr,gl,norm,lo,hi):
    """(m,p,st,age) of the first print 60..89 in the ratio range and past the pre-goal check, or None."""
    for m in range(60,90):
        if np.isnan(arr[m]): continue
        st=level_known(gl,m)
        if st is None: continue
        n=norm.get((st,band(m)))
        if n is None: continue
        p=float(arr[m])
        if not lo<=p/n<hi: continue
        last=max([g for g,_ in gl if g<=m],default=None)
        if last is not None:
            q=pre_price(arr,last)
            if q is not None and p>=0.8*q: continue
        return m,p,st,(m-last if last is not None else None)
    return None
def next_print(arr,m):
    for x in range(m+1,min(m+4,len(arr))):
        if not np.isnan(arr[x]): return x
    return None
def g8_exit(arr,gl,m,e):
    g=[x for x,_ in gl if x>m]
    if not g: return None
    for x in range(max(g[0]+8,e+1),len(arr)):
        if not np.isnan(arr[x]): return float(arr[x])
    return None
def tstat(v):
    v=np.asarray(v,dtype=float); n=len(v)
    if n<2: return 0.0
    s=v.std(ddof=1); return float(v.mean()/(s/np.sqrt(n))) if s>0 else 0.0
def tnorm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|club|de|the|athletic|atletico|real|cd|ud|sd|rcd|ca)\b"," ",s)
    return set(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def sim(A,B): return len(A&B)/max(1,len(A|B))
def final_row(status,minute): return status in ('2H','ET') and minute is not None and minute>=85
# known answers, worked by hand
assert dn(2.0,4)==1.96 and dn(3.0,4)==2.92 and abs(back(1.96,True)-9.408)<1e-9 and back(1.96,False)==-10.0 and abs(hedge(2.0,1.8)-10*(2/1.81-1)*.98)<1e-9
G22=[(10,'h'),(20,'h'),(50,'a'),(70,'a')]
assert level_known(G22,72)=='2-2' and level_known(G22,71) is None and level_known(G22,69) is None and level_known([],60)=='0-0' and level_known([(1,'h')],60) is None and level_known([(1,'h'),(2,'h'),(3,'h'),(4,'h'),(5,'a'),(6,'a'),(7,'a'),(8,'a')],60) is None
A_=np.full(131,np.nan); A_[66]=4.0; A_[72]=2.0; A_[73]=1.9; A_[75]=1.7; A_[80]=1.5
NM={('2-2',70):1.8,('2-2',75):1.6,('2-2',80):1.4}
assert signal(A_,G22,NM,1.05,1.25)==(72,2.0,'2-2',2)                                      # 2.0/1.8=1.11, under 0.8 x 4.0
assert signal(A_,G22,NM,1.2,1.25) is None                                                 # no print reaches 1.20
B_=A_.copy(); B_[72]=3.3; assert signal(B_,G22,{('2-2',70):3.0},1.05,1.25) is None        # 3.3/3.0=1.10, but >= 0.8 x 4.0, a stale print
assert signal(A_,G22,{},1.05,1.25) is None                                                # no norm, no trade
assert next_print(A_,72)==73 and next_print(A_,75) is None and next_print(A_,73)==75 and g8_exit(A_,G22,72,73) is None
assert g8_exit(A_,G22+[(72,'a')],71,73)==1.5 and g8_exit(A_,G22+[(85,'a')],72,73) is None and abs(tstat([1,3])-2.0)<1e-9 and final_row('2H',85) and not final_row('HT',85) and band(64)==60
print("known-answer checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.league,f.season,f.kickoff,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.season IN (2024,2025)""",con).drop_duplicates('event_id')
EV=pd.read_sql("SELECT fixture_id,coalesce(minute,0) mn,is_home FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')",con,params=(list(map(int,G.fixture_id)),))
goals=defaultdict(list)
for r in EV.itertuples(): goals[r.fixture_id].append((int(r.mn),'h' if r.is_home else 'a'))
for k in goals: goals[k].sort(key=lambda z:z[0])
GM=[]; pool=defaultdict(list); c=defaultdict(int)
for i in range(0,len(G),1000):
    sub=G.iloc[i:i+1000]
    P=pd.read_sql("SELECT event_id,minute,m,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='MO' AND sel='DRAW' AND minute BETWEEN 0 AND 130 AND ltp>=1.01 AND ltp<1000",con,params=(list(sub.event_id),))
    P=P.sort_values('m').drop_duplicates(['event_id','minute']); D={e:x for e,x in P.groupby('event_id')}
    for g in sub.itertuples():
        x=D.get(g.event_id)
        if x is None: c['no draw prints']+=1; continue
        gl=goals.get(g.fixture_id,[]); hg,ag=int(g.hg),int(g.ag)
        if sum(s=='h' for _,s in gl)!=hg or sum(s=='a' for _,s in gl)!=ag: c['goals do not match FT']+=1; continue
        arr=np.full(131,np.nan); arr[x.minute.values]=np.round(x.ltp.values,2); GM.append((g.event_id,g.league,int(g.season),pd.to_datetime(g.kickoff,utc=True),hg==ag,gl,arr))
        if int(g.season)==2024:
            for m in range(60,90):
                if np.isnan(arr[m]): continue
                st=level_known(gl,m)
                if st is None: continue
                last=max([q for q,_ in gl if q<=m],default=None)
                if last is None or m-last>=20: pool[(st,band(m))].append(arr[m])
    print(f"  {min(i+1000,len(G))}/{len(G)} {time.time()-T0:.0f}s",flush=True)
print("counts",dict(c),"games",len(GM),flush=True)
NORM={k:float(np.median(v)) for k,v in pool.items() if len(v)>=30}; print("2024 norm by state and band:\n",pd.Series(NORM).unstack(0).round(2).to_string(),flush=True)
RANGES={'1.05-1.25':(1.05,1.25),'1.05-1.10':(1.05,1.10),'1.10-1.15':(1.10,1.15),'1.15-1.25':(1.15,1.25),'0.95-1.05 control':(0.95,1.05)}; rows=[]; nofill=defaultdict(int)
for ev,lg,sn,ko,draw,gl,arr in GM:
    for rn,(lo,hi) in RANGES.items():
        s=signal(arr,gl,NORM,lo,hi)
        if s is None: continue
        m,p,st,age=s; e=next_print(arr,m)
        if e is None: nofill[rn]+=1; continue
        pf=float(arr[e]); q=g8_exit(arr,gl,m,e)
        a4=dn(pf,4); a1=dn(pf,1)
        if a4<=1.01: nofill[rn+' too short']+=1; continue
        rows.append(dict(rn=rn,event_id=ev,league=lg,season=sn,ko=ko,st=st,m=m,p=p,pf=pf,age=age,draw=draw,s4=back(a4,draw),s1=back(a1,draw),g4=back(a4,draw) if q is None else hedge(a4,q),g1=back(a1,draw) if q is None else hedge(a1,q)))
R=pd.DataFrame(rows); assert not R.duplicated(['rn','event_id']).any(); print("signal but no fill, counted:",dict(nofill),flush=True)
med=R[R.season==2025].ko.median()
def line(name,d,c='s4'):
    v=d[c]; x25=d[d.season==2025]; a=x25[x25.ko<med][c]; b=x25[x25.ko>=med][c]
    r=dict(line=name,exit=c,n=len(v),px=d.pf.median(),won=d.draw.mean(),imp=(1/d.pf).mean(),per10=v.mean(),t=tstat(v),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,best=v.max() if len(v) else np.nan)
    r['PASS']=bool(r['n']>=300 and r['n1']>=150 and r['n2']>=150 and r['t']>=3.5 and r['h1']>0 and r['h2']>0 and r['per10']>=0.15); return r
F=R[R.season==2024]; H=R[R.season==2025]; L=F[F.rn!='0.95-1.05 control'].groupby('rn').s4.agg(['size','mean']); L=L[L['size']>=100].sort_values('mean',ascending=False); print("\n2024 (in sample) by range, k=4 settle:\n",L.round(3).to_string()); pick=L.index[0]; print("chosen on 2024:",pick,flush=True)
O=[]
for rn in RANGES:
    for c_ in ('s4','s1','g4','g1'): O.append(line(f"2025 {rn}"+(' [CHOSEN]' if rn==pick else ''),H[H.rn==rn],c_))
T=pd.DataFrame(O); print("\n== HOLD-OUT 2025, one entry per game\n",T.drop(columns=['PASS']).round(3).to_string(index=False))
X=H[H.rn==pick]; print("\n-- chosen, by state\n",pd.DataFrame([line(str(k),d) for k,d in X.groupby('st')]).drop(columns=['PASS','exit']).round(3).to_string(index=False))
X=X.assign(mb=X.m.map(band)); print("\n-- chosen, by minute band\n",pd.DataFrame([line(str(k),d) for k,d in X.groupby('mb')]).drop(columns=['PASS','exit']).round(3).to_string(index=False)); print("\nchosen, by league, n>=15, top and bottom 4:\n",X.groupby('league').s4.agg(['size','mean']).query('size>=15').sort_values('mean').round(3).pipe(lambda d:pd.concat([d.head(4),d.tail(4)])).to_string(),flush=True)
lo,hi=RANGES[pick]
try:
    print("\n== FORWARD")
    Lq=pd.read_sql("SELECT ts,event_name,minute,back_px::float bp,back_sz::float bs,lay_px::float lp FROM liq_sample WHERE mkt='MO' AND sel='DRAW' AND minute>=60 AND back_px>1 AND lay_px>back_px ORDER BY ts",con)
    Tl=pd.read_sql("SELECT fixture_id,captured_at,home_team,away_team,minute,score_home h,score_away a,status FROM goal_timeline WHERE captured_at>=(SELECT min(ts)-interval '3 hours' FROM liq_sample) AND score_home IS NOT NULL ORDER BY captured_at",con); con.close()
    E0=pd.Timestamp('2020-01-01',tz='UTC'); Lq['t']=(pd.to_datetime(Lq.ts,utc=True)-E0).dt.total_seconds(); Tl['t']=(pd.to_datetime(Tl.captured_at,utc=True)-E0).dt.total_seconds(); Tl['mn']=pd.to_numeric(Tl.minute,errors='coerce')
    evs={e:d for e,d in Lq.groupby('event_name')}; toks={e:tuple(map(tnorm,e.partition(' v ')[::2])) for e in evs}; fw=[]; un=0; sig=0
    for f_,g in Tl.groupby('fixture_id'):
        g=g[(g.h==g.a)|(g.mn>=60)]; last=g.iloc[-1] if len(g) else None
        if last is None or last.mn!=last.mn or last.mn<60: continue
        H_,A_2=tnorm(g.home_team.iloc[0]),tnorm(g.away_team.iloc[0]); best=None; bs=0
        for ev,(a_,b_) in toks.items():
            d=evs[ev]
            if d.t.iloc[-1]<g.t.iloc[0] or d.t.iloc[0]>g.t.iloc[-1]: continue
            s=min(sim(a_,H_),sim(b_,A_2))
            if s>bs: bs,best=s,ev
        if best is None or bs<0.3: un+=1; continue
        d=evs[best]; st0=None; done=False; tt=g.t.values; hh=g.h.values; aa=g.a.values; mm=g.mn.values
        for j in range(len(tt)):
            if hh[j]!=aa[j] or hh[j]>3: st0=None; continue
            if st0 is None or st0[0]!=hh[j]: st0=(hh[j],tt[j])
            if tt[j]-st0[1]<120 or not 60<=mm[j]<=89: continue
            n=NORM.get((f'{hh[j]}-{aa[j]}',band(mm[j])))
            if n is None: continue
            w=d[(d.t>=tt[j])&(d.t<=tt[j]+60)]
            if not len(w) or not lo<=w.bp.iloc[0]/n<hi: continue
            nx=d[(d.t>w.t.iloc[0])&(d.t<=w.t.iloc[0]+120)]
            if not len(nx): continue
            sig+=1; q=nx.iloc[0]; kn=final_row(last.status,last.mn); dr=bool(last.h==last.a) if kn else False; a1=dn(q.bp)
            if a1>1.01: fw.append(dict(event=best,st=f'{hh[j]}-{aa[j]}',mn=mm[j],bp=q.bp,gap=ix(q.lp)-ix(q.bp),size_ok=q.bs>=10,known=kn,draw=dr,x=back(a1,dr) if kn else -10.0))
            done=True; break
    W=pd.DataFrame(fw); print(f"range {pick}; fixtures unmatched {un}; traded {len(W)}")
    if len(W):
        K=W[W.known]; print(f"unknown = -£10: per10 {W.x.mean():+.3f} t {tstat(W.x):.2f} | known n {len(K)} per10 {K.x.mean():+.3f} t {tstat(K.x):.2f} draw {K.draw.astype(float).mean():.3f} implied {(1/K.bp).mean():.3f} | back to lay median ticks {W.gap.median()} | size >= £10 {W.size_ok.mean():.2f}"); print(W.groupby('st').x.agg(['size','mean']).round(3).to_string())
except Exception as e:
    print("FORWARD SECTION FAILED, tape result stands:",type(e).__name__,str(e)[:300],flush=True)
W2=T[T.PASS&T.line.str.contains('CHOSEN')&T.exit.isin(['s4','g4'])]; print(f"\n== SURVIVORS: {len(W2)} (2025 only, range chosen on 2024, four ticks, LTP-based so an upper bound)"); print(W2.round(3).to_string(index=False) if len(W2) else "none"); print(f"total {time.time()-T0:.0f}s")
PY
