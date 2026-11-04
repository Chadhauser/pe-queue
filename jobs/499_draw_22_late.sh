#!/bin/bash
set -o pipefail
# 499_draw_22_late (Finder 2026-11-04, queue item 37): BACK THE DRAW AT 2-2 LATE. af_price_map x bf_hist_price x af_events, then liq_sample x goal_timeline. The number 499 is reused with a new slug: 450-499 are all taken.
# SIGNAL: first minute t >= X (X 60,70,75,80,85; item = 75, t <= 89) where af says the score is S and the last goal is at least L minutes old (L 2,5,8; item = 2). L guards against the tape clock: a print just after the af minute can still be from before the goal.
# FILL: first real MO DRAW print in tape minutes t+1..t+3 (never forward-filled; none = no trade, counted), one tick adverse, £10 back, 2% commission on profit. worse = the worse of that print and the next within 2 min (a look-ahead against the trader, a sensitivity only). x3 = three ticks adverse.
# EXITS: settle on the FT score; g8 = first real print at or after next goal +8, one tick adverse, else settle at the result. No game is ever dropped on its result.
# DROPPED FOR DATA: goal events that do not add up to the FT score; first print outside -5..+20 min of the af kick-off. Both counted. Own goals are NOT flipped (af is_home credits the benefiting team, job 471).
# CONTROLS: same rule at 0-0, 1-1, 3-3. Halves: season 2024 v 2025. The last goal to 2-2 is ALWAYS an equaliser (2-1 or 1-2 before it), so the item's split cannot exist: split by who scored it, by favourite v underdog, and by comeback from 0-2 v alternating.
# FORWARD: goal_timeline 2-2 held for 2 minutes at 75'+ on consecutive rows (a phantom goal that reverts never signals); first liq_sample row within 120 s, back_px one tick adverse. Result = last goal_timeline row at 85'+; unknown = -£10, and known-only is shown too.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,time,unicodedata,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',240); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',40)
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
def back_settle(a,won): return net(10*(a-1) if won else -10.0)
def back_hedge(a,q): return net(10*(a/up(q)-1))
def first_print(arr,lo,hi):
    for m in range(max(lo,0),min(hi,len(arr))):
        if not np.isnan(arr[m]): return m
    return None
def signal(gl,sh,sa,X,L):
    """gl = sorted [(minute,'h'|'a')]. First t in X..89 with score (sh,sa) at t and the last goal <= t-L; None if never."""
    for t in range(X,90):
        h=sum(1 for m,s in gl if m<=t and s=='h'); a=sum(1 for m,s in gl if m<=t and s=='a')
        if (h,a)!=(sh,sa): continue
        if max([m for m,_ in gl if m<=t],default=-99)<=t-L: return t
    return None
def trade(arr,gl,t,draw,k=1):
    """Returns (ent,p,settle,g8), or None if no print."""
    ent=first_print(arr,t+1,t+4)
    if ent is None: return None
    p=float(arr[ent]); a=dn(p,k)
    if a<=1.01: return None
    s=back_settle(a,draw); g=[m for m,_ in gl if m>t]
    if not g: return ent,p,s,s
    m=first_print(arr,max(g[0]+8,ent+1),len(arr))
    return ent,p,s,(s if m is None else back_hedge(a,float(arr[m])))
def path(gl):
    o=''.join(s for _,s in gl)
    return 'comeback' if o[:2] in ('hh','aa') else 'alternating'
def tstat(x):
    x=np.asarray(x,dtype=float); s=x.std(ddof=1) if len(x)>1 else 0
    return float(x.mean()/(s/len(x)**0.5)) if s>0 else 0.0
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|club|de|the|athletic|atletico|real|cd|ud|sd|rcd|ca)\b"," ",s)
    return set(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def sim(A,B): return len(A&B)/max(1,len(A|B))
def final_row(status,minute): return status in ('2H','ET') and minute is not None and minute>=85
def fwd_signal(rows,MIN=75,KNOWN=120):
    """rows: time-ordered (ts_seconds,minute,h,a). 2-2 unbroken for KNOWN seconds at minute >= MIN -> index of that row; a revert restarts the clock."""
    st=None
    for i,(ts,mn,h,a) in enumerate(rows):
        if (h,a)!=(2,2): st=None; continue
        if st is None: st=ts
        if ts-st>=KNOWN and mn is not None and MIN<=mn<=89: return i
    return None
# known answers, worked by hand: back 3.0 -> 2.98 wins 10*1.98*.98 = 19.404; loses -10. Hedge a 2.98, q 2.0: lay at 2.02, 10*(2.98/2.02-1) = 4.752475, *.98 = 4.657426. A hedge at a loss takes no commission.
assert dn(3.0)==2.98 and dn(3.0,3)==2.94 and up(2.0)==2.02 and dn(3.05)==3.0 and dn(1.02)==1.01
assert abs(back_settle(2.98,True)-19.404)<1e-9 and back_settle(2.98,False)==-10.0 and abs(back_hedge(2.98,2.0)-4.657426)<1e-5 and abs(back_hedge(2.0,4.0)-10*(2/4.1-1))<1e-9
G22=[(10,'h'),(20,'h'),(50,'a'),(70,'a')]
assert signal(G22,2,2,75,2)==75 and signal(G22,2,2,60,2)==72 and signal(G22,2,2,60,8)==78 and signal([(10,'h'),(20,'h'),(50,'a'),(74,'a')],2,2,75,2)==76
assert signal(G22+[(76,'h')],2,2,75,2)==75 and signal([(10,'h'),(20,'h'),(50,'a'),(74,'a'),(75,'h')],2,2,75,2) is None and signal([],0,0,75,2)==75 and signal([(88,'h'),(88,'a'),(88,'h'),(88,'a')],2,2,75,2) is None
A_=np.full(131,np.nan); A_[76]=3.0; A_[90]=2.0
r=trade(A_,G22+[(80,'h')],75,False); assert r[0]==76 and r[1]==3.0 and r[2]==-10.0 and abs(r[3]-back_hedge(2.98,2.0))<1e-9
r=trade(A_,G22+[(85,'h')],75,True); assert r[3]==back_settle(2.98,True)   # 85+8=93: the print at 90 is too early, none after, so settle
B_=np.full(131,np.nan); B_[76]=3.0
assert trade(B_,G22+[(85,'h')],75,False)[3]==-10.0 and trade(B_,G22,75,True)[3]==back_settle(2.98,True) and trade(np.full(131,np.nan),G22,75,True) is None
assert path(G22)=='comeback' and path([(1,'h'),(2,'a'),(3,'h'),(4,'a')])=='alternating' and path([(1,'a'),(2,'h'),(3,'h'),(4,'a')])=='alternating'
assert fwd_signal([(0,70,2,2),(60,76,2,2),(130,77,2,2)])==2 and fwd_signal([(0,76,2,2),(60,77,2,1),(120,78,2,2),(180,79,2,2)]) is None and fwd_signal([(0,76,2,2),(100,77,3,2)]) is None
assert abs(tstat([1,3])-2.0)<1e-9 and final_row('2H',85) and not final_row('HT',45)
print("known-answer checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'"); cur.execute("SET statement_timeout='2400s'")
G=pd.read_sql("""SELECT m.event_id,f.fixture_id,f.league,f.season,f.kickoff,f.hg,f.ag FROM af_price_map m JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL""",con)
EV=pd.read_sql("SELECT fixture_id,coalesce(minute,0) mn,is_home FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal' AND detail IN ('Normal Goal','Penalty','Own Goal')",con,params=(list(map(int,G.fixture_id)),))
goals=defaultdict(list)
for r in EV.itertuples(): goals[r.fixture_id].append((int(r.mn),'h' if r.is_home else 'a'))
for k in goals: goals[k].sort(key=lambda z:z[0])
STATES=((2,2),(0,0),(1,1),(3,3)); XS=(60,70,75,80,85); LS=(2,5,8)
rows=[]; cnt=defaultdict(int); clock=defaultdict(list); ft_ok=[]
for i in range(0,len(G),1000):
    sub=G.iloc[i:i+1000]
    P=pd.read_sql("SELECT event_id,minute,m,sel,ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND mkt='MO' AND ((sel='DRAW' AND minute BETWEEN 50 AND 130) OR (sel IN ('HOME','AWAY') AND minute BETWEEN 0 AND 2)) AND ltp>=1.01 AND ltp<1000",con,params=(list(sub.event_id),))
    P=P.sort_values('m').drop_duplicates(['event_id','sel','minute'])
    D={e:x for e,x in P[P.sel=='DRAW'].groupby('event_id')}; K=P[P.sel!='DRAW'].groupby(['event_id','sel']).agg(ltp=('ltp','first'),m=('m','first'))
    for g in sub.itertuples():
        x=D.get(g.event_id)
        if x is None: cnt['no draw prints']+=1; continue
        gl=goals.get(g.fixture_id,[]); hg,ag=int(g.hg),int(g.ag)
        if sum(s=='h' for _,s in gl)!=hg or sum(s=='a' for _,s in gl)!=ag: cnt['goal events do not match FT']+=1; continue
        fav=None; lag=None
        try:
            h=K.loc[(g.event_id,'HOME')]; a=K.loc[(g.event_id,'AWAY')]; fav=('h',h.ltp) if h.ltp<=a.ltp else ('a',a.ltp)
            lag=(pd.to_datetime(min(h.m,a.m),utc=True)-pd.to_datetime(g.kickoff,utc=True)).total_seconds()/60
        except KeyError: pass
        if lag is not None and not -5<=lag<=20: cnt['first print outside kick-off window']+=1; continue
        arr=np.full(131,np.nan); arr[x.minute.values]=x.ltp.values; draw=hg==ag; cnt['games used']+=1
        vals=arr[~np.isnan(arr)]
        if len(vals) and (vals[-1]<=1.10 or vals[-1]>=10): ft_ok.append((vals[-1]<=1.10)==draw)
        # clock check: draw price round an equaliser to 2-2 with no other goal near, relative to the goal minute
        if len(gl)>=4 and [s for _,s in gl[:4]].count('h')==2:
            gm=gl[3][0]
            if 60<=gm<=80 and gl[2][0]<gm-10 and (len(gl)==4 or gl[4][0]>gm+10):
                for o in range(-3,11):
                    if not np.isnan(arr[gm+o]): clock[o].append(arr[gm+o])
        for sh,sa in STATES:
            for X in XS:
                for L in LS:
                    t=signal(gl,sh,sa,X,L)
                    if t is None: continue
                    r=trade(arr,gl,t,draw)
                    if r is None: cnt[f'{sh}-{sa} X{X} L{L} signal, no print']+=1; continue
                    ent,p,s1,g1=r; r3=trade(arr,gl,t,draw,3)
                    if r3 is None: continue
                    nx=first_print(arr,ent+1,ent+3); pw=p if nx is None else min(p,float(arr[nx]))
                    last=max([m for m,_ in gl if m<=t],default=None)
                    gs=sorted(gl,key=lambda z:z[0]); lastby=gs[sum(1 for m,_ in gl if m<=t)-1][1] if last is not None else None
                    rows.append(dict(state=f'{sh}-{sa}',X=X,L=L,event_id=g.event_id,league=g.league,season=int(g.season),t=t,ent=ent,p=p,draw=draw,s=s1,g8=g1,s3=r3[2],g83=r3[3],worse=back_settle(dn(pw),draw),age=(t-last) if last is not None else None,
                        lastby=lastby,lastfav=(None if fav is None or lastby is None else ('fav' if lastby==fav[0] else 'dog')),favp=(None if fav is None else fav[1]),path=path(gl) if (sh,sa)==(2,2) else None))
    print(f"  {min(i+1000,len(G))}/{len(G)} {time.time()-T0:.0f}s",flush=True)
R=pd.DataFrame(rows); assert not R.duplicated(['state','X','L','event_id']).any()
print("\ncounts:",{k:v for k,v in cnt.items() if ' X' not in k}); print("signal but no print, 2-2 X75:",{k:v for k,v in cnt.items() if k.startswith('2-2 X75')})
print(f"tape's last draw print agrees with the af result, where the print is decisive: {np.mean(ft_ok):.4f} of {len(ft_ok)}")
print("\n== CLOCK: median draw price by tape minute minus af minute of the goal making it 2-2 (goal 60-80', no other goal within 10 min)")
print(" ".join(f"{o:+d}:{np.median(clock[o]):.2f}(n{len(clock[o])})" for o in sorted(clock)))
def line(d,c='s'):
    a=d[d.season==2024][c]; b=d[d.season==2025][c]; v=d[c]; r=dict(n=len(v),games=d.event_id.nunique(),px=d.p.median(),per10=v.mean(),t=tstat(v),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,max_win=v.max() if len(v) else np.nan)
    r['PASS']=bool(r['n']>=300 and r['n1']>=150 and r['n2']>=150 and r['t']>=3.5 and r['h1']>0 and r['h2']>0 and r['per10']>=0.15); return r
o=[]
for (st,X,L),d in R.groupby(['state','X','L']):
    for c in ('s','g8','s3','g83','worse'): o.append(dict(state=st,X=X,L=L,exit=c,**line(d,c)))
T=pd.DataFrame(o)
print("\n== ALL LINES, 2-2\n",T[T.state=='2-2'].sort_values(['X','L','exit']).round(3).to_string(index=False))
print("\n== CONTROLS, X75 L2\n",T[(T.state!='2-2')&(T.X==75)&(T.L==2)].sort_values(['state','exit']).round(3).to_string(index=False))
B=R[(R.state=='2-2')&(R.X==75)&(R.L==2)].copy()
print(f"\n== THE ITEM'S LINE, 2-2 X75 L2: n {len(B)}, won {B.draw.mean():.4f}, mean 1/price {(1/B.p).mean():.4f}, z {(B.draw.sum()-(1/B.p).sum())/np.sqrt(((1/B.p)*(1-1/B.p)).sum()):.2f}")
B['age_b']=pd.cut(B.age,[0,4,9,19,200],labels=['2-4','5-9','10-19','20+']); B['pb']=pd.cut(B.p,[1,1.8,2.2,2.6,3,4,6,1000]); B['tb']=pd.cut(B.t,[74,76,80,85,90]); B['favb']=pd.cut(B.favp,[1,1.5,2,3,100])
for col in ('age_b','pb','tb','lastby','lastfav','path','favb'):
    u=[]
    for k,d in B.groupby(col,observed=True): u.append(dict(split=k,**line(d),won=d.draw.mean(),imp=(1/d.p).mean(),g8=d.g8.mean(),s3=d.s3.mean()))
    print(f"\n-- by {col}\n",pd.DataFrame(u).drop(columns=['PASS']).round(3).to_string(index=False))
u=[]
for k,d in B.groupby('league'):
    if len(d)>=20: u.append(dict(league=k,**line(d),g8=d.g8.mean(),s3=d.s3.mean()))
print("\n-- by league, n>=20, top 15 by t, and how many are positive\n",pd.DataFrame(u).sort_values('t',ascending=False).head(15).drop(columns=['PASS']).round(3).to_string(index=False)); print("leagues positive:",sum(x['per10']>0 for x in u),"of",len(u))
print(f"\nwithout prices over 6: {line(B[B.p<=6])}"); print(f"elapsed {time.time()-T0:.0f}s",flush=True)
# forward
try:
    print("\n== FORWARD liq_sample x goal_timeline",flush=True)
    Tl=pd.read_sql("SELECT fixture_id,captured_at,home_team,away_team,minute,score_home h,score_away a,status FROM goal_timeline WHERE captured_at>=(SELECT min(ts)-interval '3 hours' FROM liq_sample) AND score_home IS NOT NULL ORDER BY captured_at",con)
    Lq=pd.read_sql("SELECT ts,event_name,ltp::float ltp,back_px::float bp,back_sz::float bs,lay_px::float lp,lay_sz::float ls FROM liq_sample WHERE mkt='MO' AND sel='DRAW' AND back_px>1 AND lay_px>back_px",con)
    Lq['t']=(pd.to_datetime(Lq.ts,utc=True)-pd.Timestamp('2020-01-01',tz='UTC')).dt.total_seconds()
    Tl['t']=(pd.to_datetime(Tl.captured_at,utc=True)-pd.Timestamp('2020-01-01',tz='UTC')).dt.total_seconds(); Tl['mn']=pd.to_numeric(Tl.minute,errors='coerce')
    print(f"liq rows {len(Lq)}, games {Lq.event_name.nunique()}, {pd.to_datetime(Lq.ts,utc=True).min()} to {pd.to_datetime(Lq.ts,utc=True).max()}; timeline fixtures {Tl.fixture_id.nunique()}",flush=True)
    evs={e:d.sort_values('t') for e,d in Lq.groupby('event_name')}; fw=[]; nsig=0; nomatch=0; nofill=0; gaps=[]
    for f_,g in Tl.groupby('fixture_id'):
        rr=[(a,None if pd.isna(b) else b,c,d) for a,b,c,d in zip(g.t,g.mn,g.h,g.a)]
        i=fwd_signal(rr)
        if i is None: continue
        nsig+=1; ts=rr[i][0]; H,A=norm(g.home_team.iloc[0]),norm(g.away_team.iloc[0]); best=None; bs=0
        for ev,e in evs.items():
            if e.t.iloc[-1]<ts or e.t.iloc[0]>ts: continue
            h_,_,a_=ev.partition(' v '); s=min(sim(norm(h_),H),sim(norm(a_),A))
            if s>bs: bs,best=s,ev
        if best is None or bs<0.3: nomatch+=1; continue
        e=evs[best]; w=e[(e.t>=ts)&(e.t<=ts+120)]
        if not len(w): nofill+=1; continue
        q=w.iloc[0]; a=dn(q.bp)
        last=g.iloc[-1]; known=final_row(last.status,None if pd.isna(last.mn) else last.mn)
        draw=bool(last.h==last.a) if known else None; s=back_settle(a,draw) if known else -10.0
        ch=g[(g.t>ts)&((g.h!=2)|(g.a!=2))]; g8=s
        if len(ch):
            z=e[(e.t>=ch.t.iloc[0]+480)]
            if len(z): g8=back_hedge(a,z.iloc[0].lp)
        fw.append(dict(event=best,mn=rr[i][1],ltp=q.ltp,bp=q.bp,lp=q.lp,gap=ix(q.lp)-ix(q.bp),ltp_gap=(ix(q.ltp)-ix(q.bp)) if pd.notna(q.ltp) and q.ltp>=1.01 else np.nan,size_ok=q.bs>=10,known=known,draw=draw,s=s,g8=g8))
    print(f"2-2 signals at 75'+ {nsig}, no market match {nomatch}, no touch within 120 s {nofill}, traded {len(fw)}")
    if fw:
        F=pd.DataFrame(fw); Kn=F[F.known]
        print(f"unknown=-£10: n {len(F)} per10 {F.s.mean():+.3f} t {tstat(F.s):.2f} g8 {F.g8.mean():+.3f} | known only n {len(Kn)} per10 {Kn.s.mean():+.3f} t {tstat(Kn.s):.2f} draw {Kn.draw.astype(float).mean():.3f} implied {(1/Kn.bp).mean():.3f}")
        print(f"gap back to lay, ticks: median {F.gap.median()}, mean {F.gap.mean():.2f}; ltp above back, ticks: median {F.ltp_gap.median()}, mean {F.ltp_gap.mean():.2f}; back size >= £10: {F.size_ok.mean():.2f}")
        print(F.sort_values('mn').head(30).round(2).to_string(index=False))
except Exception as e:
    print("FORWARD SECTION FAILED, tape result stands:",type(e).__name__,str(e)[:300],flush=True)
W=T[T.PASS&(T.state=='2-2')&(T.exit.isin(['s','g8']))]; print(f"\n== SURVIVORS: {len(W)} of {len(T[(T.state=='2-2')&T.exit.isin(['s','g8'])])} 2-2 lines (LTP-based, so an upper bound; one family of correlated lines picked from grid v4's 368,330 cells)"); print(W.round(3).to_string(index=False) if len(W) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
