#!/bin/bash
set -o pipefail
# 487 (Finder 2026-11-04, queue item 33): RACING IN-PLAY "SHORTENED 15% / 25%" on bf_hist_other (Betfair BASIC), GB/IE WIN. The item says May 2026; the census shows the table runs Sep 2024..Sep 2026, so all of it is eligible.
# SAMPLE: the only index is (sport, market_id), so a date filter means full scans (job 467 timed out). Market ids come from a loose index scan and are SHUFFLED with a fixed seed, then pulled in chunks until the time budget ends: coverage is printed and is spread over dates, not cut at one end.
# DATA LIMIT: BASIC is about one LTP print a minute and has no book. A race lasts 1-5 minutes, so a print can be up to a minute stale and the fill is a proxy: treat any positive result as an upper bound. No touch exists on this table.
# OFF PRICE: the runner's last pre-off print (inplay false) no more than 10 min before market_time onward; none = not eligible, counted. Off price > 50 not traded.
# TRIGGER: first in-play print with ltp <= off x (1-X), X = 15% or 25%. Earlier triggers cannot see later prices.
# FILL: you see the trigger print and act after it, so BACK fills at the WORSE (lower) of the trigger print and the runner's next print (none = trigger print), less one tick; LAY at the worse (higher) of the two, plus one tick. Back at 1.01 cannot be filled: counted.
# FILLS, all with one tick adverse, all unknown = -£10: NEXT = the runner's next print, the first price you could act on; no next print = no trade, counted. This is the line that can pass. TRIG = the trigger print itself, impossible in practice, an upper bound, never eligible. WORSE = the worse of the two.
# FIRST RUN: WORSE alone (3,600 markets, 0 of 96 lines, back -5.05, lay -1.66). Back and lay both lost because WORSE looks ahead against the trader: a winner fills at the later short price, a loser keeps the trigger price. Too harsh to clear a line or to kill one, hence NEXT and TRIG. 
# SECOND RUN (720 s budget, 600 s statement timeout, under the brief's 2400 s) died listing market ids: QueryCanceled, the listing took 448 s on the first run. Timeout and budget are now 2400 s. THIS VERSION HAS NOT COMPLETED A RUN; the NEXT and TRIG lines are untested (item 33b).
# RESULT: racing_bsp win_lose by event_dt + runner name; otherwise inferred from the final in-play print (<= 1.05 winner, >= 100 loser); otherwise UNKNOWN. KNOWN = diagnostic only. WORST = unknown is -£10. Agreement of the inference with racing_bsp is printed. Positions are held to the result, never dropped.
# SETS: ALL is correlated within a race. FIRST = first runner to trigger in the race, one entry per race. Only WORST + FIRST can pass. E>=1.2 re-tests without entries at 1.2 or shorter, where the race may be over.
# COST: 2% commission on profit, £10 stake / £10 liability. Halves: median race date.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,time,random,unicodedata,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter
warnings.filterwarnings('ignore')
pd.set_option('display.width',230); pd.set_option('display.max_rows',80); pd.set_option('display.max_columns',30)
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
BUDGET=2400; CHUNK=300
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LAD=np.array(LAD)
def dn(p): return float(LAD[max(int(np.searchsorted(LAD,round(p,2)-1e-9))-1,0)])
def up(p): return float(LAD[min(int(np.searchsorted(LAD,round(p,2)-1e-9))+1,len(LAD)-1)])
def back_fill(trig,nxt):
    a=dn(min(trig,nxt) if nxt is not None else trig)
    return None if a<=1.01 else a
def lay_fill(trig,nxt): return up(max(trig,nxt) if nxt is not None else trig)
def back_pnl(a,won): return 10*(a-1)*0.98 if won else -10.0
def lay_pnl(a,won): return -10.0 if won else 10/(a-1)*0.98
def trigger(prints,off,x):
    """prints: in-play ltp in time order. Index of the first print at or below off*(1-x), or None."""
    for i,p in enumerate(prints):
        if p<=off*(1-x)+1e-9: return i
    return None
def infer(last):
    return True if last<=1.05 else False if last>=100 else None
def rname(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"^\s*\d+[.\s]+","",s); s=re.sub(r"\((gb|ire|fr|usa|ger|aus|nz|saf|ity|jpn|arg|uae)\)","",s)
    return re.sub(r"[^a-z0-9]","",s)
def band(p): return '<3' if p<3 else '3-6' if p<6 else '6-12' if p<12 else '12-25' if p<25 else '25+'
def tstat(v):
    v=np.asarray(v,dtype=float)
    return float(v.mean()/(v.std(ddof=1)/np.sqrt(len(v)))) if len(v)>1 and v.std(ddof=1)>0 else 0.0
# known answers, worked by hand
assert dn(2.0)==1.99 and up(2.0)==2.02 and up(1.99)==2.0 and dn(3.0)==2.98 and up(3.0)==3.05
assert trigger([5.0,4.5,4.25,3.0],5.0,0.15)==2                 # 5.0 x 0.85 = 4.25: at the level counts
assert trigger([5.0,4.5],5.0,0.15) is None and trigger([3.0,5.0],5.0,0.25)==0
assert back_fill(4.0,3.5)==3.45 and back_fill(4.0,5.0)==3.95 and back_fill(4.0,None)==3.95    # worse of the two, then one tick
assert back_fill(1.02,1.01) is None and back_fill(1.02,None) is None                          # 1.01 after the tick cannot be backed
assert lay_fill(4.0,5.0)==5.1 and lay_fill(4.0,3.5)==4.1 and lay_fill(4.0,None)==4.1
assert abs(back_pnl(3.45,True)-24.01)<1e-9 and back_pnl(3.45,False)==-10.0                    # 10 x 2.45 x 0.98 = 24.01
assert abs(lay_pnl(5.1,False)-10/4.1*0.98)<1e-9 and lay_pnl(5.1,True)==-10.0                  # liability 10
assert infer(1.05) is True and infer(1.06) is None and infer(100) is False and infer(99) is None
assert rname('1. Far Above Dream (IRE)')==rname('Far Above Dream') and rname("O'Brien's Boy")=='obriensboy'
assert band(2.99)=='<3' and band(3.0)=='3-6' and band(25.0)=='25+'
print("known-answer checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'; SET max_parallel_workers_per_gather=0")
t0=time.time()
cur.execute("""WITH RECURSIVE t AS ((SELECT market_id FROM bf_hist_other WHERE sport='Horse Racing' ORDER BY market_id LIMIT 1)
  UNION ALL SELECT (SELECT market_id FROM bf_hist_other WHERE sport='Horse Racing' AND market_id>t.market_id ORDER BY market_id LIMIT 1) FROM t WHERE t.market_id IS NOT NULL)
  SELECT market_id FROM t WHERE market_id IS NOT NULL""")
MID=[r[0] for r in cur.fetchall()]; random.Random(4).shuffle(MID)
print(f"racing market ids {len(MID)} | {int(time.time()-t0)}s",flush=True)
RB=pd.read_sql("SELECT country,event_dt,selection_name,win_lose FROM racing_bsp WHERE upper(market)='WIN' AND win_lose IS NOT NULL",con)
RB['k']=RB.selection_name.map(rname); RB['dt']=pd.to_datetime(RB.event_dt)
RES={(d.value,k):int(w) for d,k,w in zip(RB.dt,RB.k,RB.win_lose)}
print(f"racing_bsp WIN results {len(RES)} | {RB.dt.min()} .. {RB.dt.max()} | countries {RB.country.value_counts().head(4).to_dict()} | {int(time.time()-t0)}s",flush=True)
SK=Counter(); rows=[]; done=0; agree=Counter(); printsn=[]; gaps=[]; dtcheck=Counter()
def lookup(mt,k):
    """racing_bsp event_dt has no zone: try as UTC, then as UK local at +1 h in summer."""
    t=pd.Timestamp(mt).tz_convert('UTC').tz_localize(None)
    r=RES.get((t.value,k))
    if r is not None: dtcheck['utc']+=1; return r
    r=RES.get(((t+pd.Timedelta(hours=1)).value,k))
    if r is not None: dtcheck['+1h']+=1; return r
    return None
for c_ in range(0,len(MID),CHUNK):
    if time.time()-t0>BUDGET: SK['chunks not pulled, budget']+=1; break
    ids=MID[c_:c_+CHUNK]
    cur.execute("""SELECT market_id,event_name,market_time,sel,ts,ltp::float8,inplay FROM bf_hist_other
      WHERE sport='Horse Racing' AND market_id=ANY(%s) AND market_type='WIN' AND country IN ('GB','IE') AND ltp IS NOT NULL AND (inplay OR ts>=market_time-interval '10 minutes')""",(ids,))
    d=pd.DataFrame(cur.fetchall(),columns=['mid','ev','mt','sel','ts','ltp','ip']); done+=len(ids)
    if d.empty: continue
    d=d.sort_values(['mid','sel','ts'],kind='stable')
    for mid_,g in d.groupby('mid',sort=False):
        if not g.ip.any(): SK['race: no in-play prints']+=1; continue
        day=pd.Timestamp(g.mt.iloc[0]).date(); field=g.sel.nunique(); run=[]
        for sel,s in g.groupby('sel',sort=False):
            pre=s[~s.ip]; ip=s[s.ip]
            if ip.empty: SK['runner: no in-play print']+=1; continue
            k=rname(sel); w=lookup(g.mt.iloc[0],k); pr=ip.ltp.values; inf=infer(pr[-1]); printsn.append(len(pr))
            if len(pr)>1: gaps.append(float(np.median(np.diff(ip.ts.values).astype('timedelta64[s]').astype(float))))
            if w is not None and inf is not None: agree['match' if bool(w)==inf else 'differ']+=1
            won=bool(w) if w is not None else inf
            src='bsp' if w is not None else 'tape' if inf is not None else 'unknown'
            SK['result '+src]+=1
            if pre.empty: SK['runner: no pre-off print']+=1; continue
            off=float(pre.ltp.iloc[-1])
            if off>50 or off<=1.01: SK['runner: off price out of range']+=1; continue
            run.append((sel,off,pr,ip.ts.values,won))
        for x in (0.15,0.25):
            ent=[]
            for sel,off,pr,ts_,won in run:
                i=trigger(pr,off,x)
                if i is None: continue
                ent.append((ts_[i],sel,off,pr[i],pr[i+1] if i+1<len(pr) else None,won))
            ent.sort(key=lambda z:z[0])
            for n,(t_,sel,off,tp,nx,won) in enumerate(ent):
                bf=back_fill(tp,nx); lf=lay_fill(tp,nx)
                if bf is None: SK['back unfillable at 1.01']+=1
                nb=None if nx is None else back_fill(nx,None); nl=None if nx is None else lay_fill(nx,None); tb=back_fill(tp,None); tl=lay_fill(tp,None); w_=(lambda f,a:np.nan if a is None else (-10.0 if won is None else f(a,won)))
                rows.append(dict(bn=w_(back_pnl,nb),ln=w_(lay_pnl,nl),bt=w_(back_pnl,tb),lt=w_(lay_pnl,tl),mid=mid_,day=day,x=int(x*100),off=off,band=band(off),field='<=8' if field<=8 else '9-12' if field<=12 else '13+',first=n==0,hasnext=nx is not None,
                    known=won is not None,bf=np.nan if bf is None else bf,lf=lf,
                    bk=np.nan if bf is None or won is None else back_pnl(bf,won),lk=np.nan if won is None else lay_pnl(lf,won),
                    bw=np.nan if bf is None else (-10.0 if won is None else back_pnl(bf,won)),lw=-10.0 if won is None else lay_pnl(lf,won)))
    print(f"  {done}/{len(MID)} markets | rows {len(rows)} | {int(time.time()-t0)}s",flush=True)
print("coverage:",done,"of",len(MID),"market ids | counts (not hidden):",dict(SK),flush=True)
print("result agreement bsp v tape:",dict(agree),"| racing_bsp clock matches:",dict(dtcheck),flush=True)
if printsn: print(f"in-play prints per runner: median {np.median(printsn):.0f}, p90 {np.percentile(printsn,90):.0f} | median gap between prints {np.median(gaps) if gaps else float('nan'):.0f}s",flush=True)
D=pd.DataFrame(rows)
if D.empty: print("ERROR: no triggers, so no verdict"); sys.exit(1)
md=sorted(D[D['first']].day)[len(D[D['first']])//2]
print(f"\nraces with a trigger {D.mid.nunique()} | days {D.day.min()}..{D.day.max()} | halves split at {md} | known result {100*D.known.mean():.1f}% | has a next print {100*D.hasnext.mean():.1f}%",flush=True)
print("trades by month:",D[D['first']&(D.x==15)].groupby(pd.to_datetime(D.day).dt.to_period('M')).size().to_dict())
def line(d,col,**k):
    d=d[d[col].notna()]; a=d[d.day<md][col]; c=d[d.day>=md][col]; v=d[col]
    if not len(v): return dict(**k,n=0,races=0,per10=np.nan,t=0.0,n1=0,h1=np.nan,n2=0,h2=np.nan,PASS=False)
    ok=k.get('res')=='NEXT' and k.get('set')=='FIRST'
    return dict(**k,n=len(v),races=d.mid.nunique(),per10=v.mean(),t=tstat(v),n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(c),h2=c.mean() if len(c) else np.nan,PASS=bool(ok and len(v)>=300 and len(a)>=150 and len(c)>=150 and tstat(v)>=3.5 and a.mean()>0 and c.mean()>0 and v.mean()>=0.15))
res=[]
for x in (15,25):
    b=D[D.x==x]
    for st,s_ in (('FIRST',b[b['first']]),('ALL',b)):
        for side,kc,wc,fc,nc,tc in (('back','bk','bw','bf','bn','bt'),('lay','lk','lw','lf','ln','lt')):
            for lab,dd in (('all',s_),('E>=1.2',s_[s_[fc]>1.2]))+tuple(('off '+o,s_[s_.band==o]) for o in ('<3','3-6','6-12','12-25','25+'))+tuple(('field '+f,s_[s_.field==f]) for f in ('<=8','9-12','13+')):
                res.append(line(dd,wc,x=x,set=st,side=side,res='WORST',cut=lab))
                res.append(line(dd,nc,x=x,set=st,side=side,res='NEXT',cut=lab))
                res.append(line(dd,tc,x=x,set=st,side=side,res='TRIG',cut=lab))
                if lab in ('all','E>=1.2'): res.append(line(dd,kc,x=x,set=st,side=side,res='KNOWN',cut=lab))
R=pd.DataFrame(res).sort_values('t',ascending=False)
print("\n== TOP 25 BY t, per £10\n",R.head(25).round(3).to_string(index=False))
print("\n== TOP 15 BY t, NEXT only\n",R[R.res=='NEXT'].head(15).round(3).to_string(index=False))
print("\n== HEADLINE LINES\n",R[(R.cut=='all')].sort_values(['x','set','side','res']).round(3).to_string(index=False))
W=R[R.PASS==True]; print(f"\n== SURVIVORS: {len(W)} of {len(R)} lines"); print(W.round(3).to_string(index=False) if len(W) else "none")
PY
