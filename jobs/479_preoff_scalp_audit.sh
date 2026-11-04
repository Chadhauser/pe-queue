#!/bin/bash
set -o pipefail
# 479 (Finder 2026-11-04, queue item 0c): AUDIT OF THE RACING PRE-OFF SCALPER PAPER BOT (jobs/328, table preoff_scalp_paper), then an independent replay of its rule on all of stream_ticks.
# PART A: the bot's own rows: n, per £10, hit rate, ticks, by side / exit / price band / venue / secs-to-off.
# PART B: every bot trade against stream_ticks: book age at entry, entry price v book, targets really traded THROUGH (ltp strictly beyond target AND tv up since entry), in-play check, size at the touch.
#   Re-priced to house rules: one tick adverse each way, back stake £10, lay liability £10 (the bot lays £10 STAKE, so its lay risk is £10 x (p-1)). A target not confirmed through is re-priced at the real touch on the first tick at or after the bot's exit.
# PART C: own code, not the bot's. Signal on tick i, fill at the touch on the NEXT tick of that runner, exits on that runner's own later ticks only, nothing forward-filled.
#   BOT = last three ltp values per tick. SPEC = last three prices where tv rose, as the spec says "traded". FADE = SPEC trigger with the side flipped, as job 459 found back_sz heavy means the price lengthens.
#   WoM uses the touch only: stream_ticks records no size at levels 2 and 3, so the spec's "first three price points" cannot be tested on this box. No result table is joined: a position with no later print is counted as no_exit and kept out of the mean, so a non-zero count must be read as a caveat.
# Halves: before/after the median entry date. Many trades per race, so t is inflated: FIRST = first trade per race only.
python3 -W ignore - <<'PY' 2>&1
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import deque,defaultdict
pd.set_option('display.width',240); pd.set_option('display.max_rows',200); pd.set_option('display.max_columns',40)
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
LAD=[]
for lo,hi,st in ((1.01,2,0.01),(2,3,0.02),(3,4,0.05),(4,6,0.1),(6,10,0.2),(10,20,0.5),(20,30,1),(30,50,2),(50,100,5),(100,1000,10)):
    x=lo
    while x<hi-1e-9: LAD.append(round(x,2)); x+=st
LAD.append(1000.0); LADA=np.array(LAD)
def pos(p): return int(np.searchsorted(LADA,round(float(p),2)-1e-9))
def up(p,k=1): return float(LADA[min(pos(p)+k,len(LADA)-1)])
def dn(p,k=1): return float(LADA[max(pos(p)-k,0)])
def pnl(side,p,q,k=1):
    """Green-up P&L. BACK: stake £10 at p, lay out at q. LAY: liability £10 at p, back out at q. k ticks adverse each way, 2% on profit."""
    if side=='BACK':
        a=dn(p,k); b=up(q,k); r=10*(a/b-1)
    else:
        a=up(p,k); b=dn(q,k); r=10/(a-1)*(1-a/b)
    return r*0.98 if r>0 else r
def tstat(v):
    v=np.asarray(v,dtype=float); n=len(v)
    if n<2: return 0.0
    s=v.std(ddof=1)
    return float(v.mean()/(s/np.sqrt(n))) if s>0 else 0.0
# known answers, worked by hand
assert up(2.0)==2.02 and dn(2.0)==1.99 and up(2.98)==3.0 and dn(3.0)==2.98 and up(3.95)==4.0 and dn(6.0)==5.9 and up(2.0,2)==2.04 and dn(8.0,2)==7.6
assert abs(pnl('BACK',4.0,3.8,0)-10*(4/3.8-1)*0.98)<1e-9                 # 0.5263*0.98 = +0.5158
assert abs(pnl('BACK',4.0,4.2,0)-10*(4/4.2-1))<1e-9                      # -0.4762, no commission on a loss
assert pnl('BACK',4.0,4.0,0)==0 and pnl('LAY',4.0,4.0,0)==0
assert abs(pnl('LAY',3.0,3.1,0)-(10/2)*(1-3/3.1)*0.98)<1e-9              # stake £5, +0.1613*0.98
assert abs(pnl('LAY',3.0,2.9,0)-(10/2)*(1-3/2.9))<1e-9                   # stake £5, -0.1724
assert abs(pnl('BACK',4.0,4.0,1)-10*(3.95/4.1-1))<1e-9 and abs(pnl('BACK',4.0,4.0,1)+0.3659)<1e-3   # scratch costs one tick each way; below 4.0 the step is 0.05, above it 0.1
assert abs(pnl('LAY',4.0,4.0,1)-(10/3.1)*(1-4.1/3.95))<1e-9 and abs(pnl('LAY',4.0,4.0,1)+0.1225)<1e-3
assert abs(tstat([1,3])-2.0)<1e-9
print("known-answer checks: OK",flush=True)

def line(name,d,col='x'):
    v=d[col].astype(float); dm=d.day.sort_values().iloc[len(d)//2] if len(d) else None
    a=d[d.day<dm][col] if len(d) else v; c=d[d.day>=dm][col] if len(d) else v
    r=dict(line=name,n=len(v),races=d.market_id.nunique(),per10=v.mean(),t=tstat(v),hit=(v>0).mean(),n1=len(a),h1=a.mean(),n2=len(c),h2=c.mean())
    r['PASS']=bool(r['n']>=300 and r['n1']>=150 and r['n2']>=150 and r['t']>=3.5 and r['h1']>0 and r['h2']>0 and r['per10']>=0.15)
    return r
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
T=pd.read_sql("SELECT * FROM preoff_scalp_paper ORDER BY ts",con)
for c in ('entry_px','exit_px','pnl_per_10','wom'): T[c]=T[c].astype(float)
print(f"bot rows {len(T)}, closed {T.exit_ts.notna().sum()}, races {T.market_id.nunique()}, first {T.ts.min()}, last {T.ts.max()}, now {pd.Timestamp.now(tz='UTC')}",flush=True)
T=T[T.exit_ts.notna()].copy()
V={}
for tb in ('racing_results','racing_tape','racing_mm_stream','market_tracker'):
    try:
        cur.execute(f"SELECT DISTINCT market_id,venue FROM {tb} WHERE market_id=ANY(%s) AND venue IS NOT NULL",(list(T.market_id.unique()),))
        for a,b in cur.fetchall(): V.setdefault(a,b)
    except Exception as e: print("venue source failed",tb,type(e).__name__,flush=True)
T['venue']=T.market_id.map(V).fillna('unknown'); print(f"venue found for {T.market_id.isin(V).sum()} of {len(T)} trades",flush=True)
T['band']=pd.cut(T.entry_px,[0,3,5,100],labels=['2-3','3-5','5-8'],right=False).astype(str)
T['sto']=pd.cut(T.secs_to_off,[0,120,300,601],labels=['30-120','120-300','300-600']).astype(str)
T['half']=np.where(T.ts<T.ts.iloc[len(T)//2],'h1','h2')
T['x_bot']=T.pnl_per_10
def cut(d,col,val='x_bot'):
    return d.groupby(col).agg(n=(val,'size'),per10=(val,'mean'),t=(val,tstat),hit=(val,lambda s:(s>0).mean()),ticks=('ticks','mean'),races=('market_id','nunique')).round(3)
print(f"\n== PART A, bot's own P&L as recorded: n {len(T)}, per £10 {T.x_bot.mean():.3f}, t {tstat(T.x_bot):.2f}, hit {(T.x_bot>0).mean():.3f}, mean ticks {T.ticks.mean():.2f}, sum £{T.x_bot.sum():.2f}")
for c in ('half','side','exit_reason','band','sto','venue'): print(f"\nby {c}\n",cut(T,c).to_string(),flush=True)

# PART B
rows=[]
for mid,tr in T.groupby('market_id',sort=False):
    S=pd.read_sql("""SELECT sel_id,ts_recv ts,back_px::float bp,back_sz::float bs,lay_px::float lp,lay_sz::float ls,ltp::float ltp,tv::float tv,inplay,status FROM stream_ticks
       WHERE market_id=%s AND ts_recv>=%s AND ts_recv<=%s ORDER BY ts_recv""",con,params=(mid,tr.ts.min()-pd.Timedelta(seconds=120),tr.exit_ts.max()+pd.Timedelta(seconds=1800)))
    ip=S[S.inplay==True]; off=ip.ts.min() if len(ip) else pd.NaT
    for r in tr.itertuples():
        g=S[S.sel_id==r.sel_id]; e=g[g.ts<=r.ts]; nx=g[g.ts>r.ts]; bk=r.side=='BACK'; o=dict(id=r.id,off_known=pd.notna(off),entry_after_off=bool(pd.notna(off) and r.ts>=off),exit_after_off=bool(pd.notna(off) and r.exit_ts>=off))
        if len(e)==0: rows.append(dict(o,no_prior=True)); continue
        e=e.iloc[-1]; tv0=e.tv if pd.notna(e.tv) else 0.0
        o.update(no_prior=False,age=(r.ts-e.ts).total_seconds(),book_match=abs((e.bp if bk else e.lp)-r.entry_px)<1e-6)
        o['size_ok']=bool((e.bs>=10) if bk else (e.ls>=10/(r.entry_px-1)))
        w=nx[nx.ts<=r.exit_ts]; tgt=dn(r.entry_px,2) if bk else up(r.entry_px,2); tr_up=w.tv>tv0
        o['through']=bool(((w.ltp<tgt if bk else w.ltp>tgt)&tr_up).any())
        w60=nx[nx.ts<=r.ts+pd.Timedelta(seconds=60)]
        o['entry_through']=bool(((w60.ltp>r.entry_px if bk else w60.ltp<r.entry_px)&(w60.tv>tv0)).any())
        q=r.exit_px
        if r.exit_reason=='target' and not o['through']:
            a=nx[(nx.ts>=r.exit_ts)&nx.bp.notna()&nx.lp.notna()]
            q=(a.iloc[0].lp if bk else a.iloc[0].bp) if len(a) else np.nan
        if r.exit_reason!='target':
            z=g[g.ts<=r.exit_ts]
            o['exit_match']=bool(len(z) and abs((z.iloc[-1].lp if bk else z.iloc[-1].bp)-r.exit_px)<1e-6)
        o['x_house']=pnl(r.side,r.entry_px,q,1) if pd.notna(q) else np.nan
        o['x_nocost']=pnl(r.side,r.entry_px,r.exit_px,0)
        n1=nx[nx.bp.notna()&nx.lp.notna()]
        o['x_next']=pnl(r.side,(n1.iloc[0].bp if bk else n1.iloc[0].lp),q,1) if len(n1) and pd.notna(q) else np.nan
        rows.append(o)
    print(f"  market {mid}: {len(tr)} trades, {len(S)} ticks",flush=True)
B=T.merge(pd.DataFrame(rows),on='id'); B['day']=B.ts.dt.date.astype(str)
tg=B[B.exit_reason=='target']; nt=B[B.exit_reason!='target']
print("\n== PART B, bot trades v stream_ticks")
print(f"no earlier tick for the runner: {int(B.no_prior.sum())}")
print(f"book age at entry: median {B.age.median():.1f}s, p90 {B.age.quantile(.9):.1f}s, max {B.age.max():.1f}s; older than 5 s: {(B.age>5).mean():.3f}")
print(f"entry price = touch on the last tick: {B.book_match.mean():.3f}; £10 risk available at the touch: {B.size_ok.mean():.3f}")
print(f"targets traded THROUGH: {int(tg.through.sum())} of {len(tg)}; non-target exit = last touch: {nt.exit_match.mean():.3f} of {len(nt)}")
print(f"entry traded through within 60 s (the spec's fill test, which the bot does not apply): {B.entry_through.mean():.3f}; bot P&L with it {B[B.entry_through==True].x_bot.mean():.3f} (n {int((B.entry_through==True).sum())}), without {B[B.entry_through==False].x_bot.mean():.3f}")
print(f"races with an in-play tick found: {B[B.off_known].market_id.nunique()} of {B.market_id.nunique()}; entries at/after the off: {int(B.entry_after_off.sum())}; exits at/after the off: {int(B.exit_after_off.sum())}; secs_to_off at entry {B.secs_to_off.min()}..{B.secs_to_off.max()}")
print(f"lay stake: bot uses £10, so liability at the mean lay price {B[B.side=='LAY'].entry_px.mean():.2f} is £{10*(B[B.side=='LAY'].entry_px.mean()-1):.2f}, not £10")
L=[line('bot as recorded',B,'x_bot'),line('bot exits, no cost, lay liability £10',B,'x_nocost')]
for nm,c in (('HOUSE: one tick each way, lay liability £10','x_house'),('HOUSE + fill at the next tick','x_next')):
    d=B[B[c].notna()]; L.append(line(nm,d,c))
    for s in ('BACK','LAY'): L.append(line(f"  {nm[:5]} {s}",d[d.side==s],c))
print("(one trading day so far, so the date-median halves cannot separate: a blank h1 means every trade is in h2)")
print(pd.DataFrame(L).round(3).to_string(index=False),flush=True)

# PART C
class Sim:
    def __init__(s,name,traded,flip):
        s.name,s.traded,s.flip=name,traded,flip; s.open={}; s.pend={}; s.cool={}; s.closed=[]; s.no_exit=0; s.ip_exit=0
    def step(s,r,st):
        mid,sid,ts,bp,bs,lp,ls,ltp,tv,sto,inplay,status=r; k=(mid,sid); tvv=tv or 0.0
        o=s.open.get(k)
        if o:
            age=(ts-o['t']).total_seconds(); live=(not inplay) and status=='OPEN'; q=why=None; bk=o['side']=='BACK'
            if live and ltp and tvv>o['tv0'] and (ltp<dn(o['px'],2) if bk else ltp>up(o['px'],2)): q,why=(dn(o['px'],2) if bk else up(o['px'],2)),'target'
            elif bp and lp:
                ex=lp if bk else bp
                if not live: q,why=ex,'off'
                elif (lp>=up(o['px'],2)) if bk else (bp<=dn(o['px'],2)): q,why=ex,'stop'
                elif age>=60: q,why=ex,'time'
                elif sto is not None and sto<=30: q,why=ex,'pre_off'
            if q:
                del s.open[k]; s.ip_exit+=why=='off'
                s.closed.append(dict(sim=s.name,market_id=mid,sel_id=sid,day=str(o['t'].date()),ts=o['t'],side=o['side'],px=o['px'],q=q,why=why,sto=o['sto'],x0=pnl(o['side'],o['px'],q,0),x=pnl(o['side'],o['px'],q,1),x3=pnl(o['side'],o['px'],q,3)))
            return
        p=s.pend.pop(k,None)
        if p and not inplay and status=='OPEN' and bp and lp and sto is not None and sto>30:
            s.open[k]=dict(side=p,px=bp if p=='BACK' else lp,t=ts,tv0=tvv,sto=sto); s.cool[k]=ts; return
        if p or len(s.open)+len(s.pend)>=3 or inplay or status!='OPEN': return
        if not (bp and lp and bs and ls and sto is not None and 30<sto<=600 and 2.0<=bp<=8.0): return
        if pos(lp)-pos(bp)>2 or sum(st['mv'][mid].values())<50000: return
        h=st['wom'][k]
        if len(h)<5: return
        wom=sum(x[1] for x in h)/len(h); l3=st['tr3' if s.traded else 'lt3'][k]
        if len(l3)<3: return
        ln=l3[0]<l3[1]<l3[2]; sh=l3[0]>l3[1]>l3[2]; side=None
        if wom>=0.65 and not ln: side='BACK'
        elif wom<=0.35 and not sh: side='LAY'
        if not side: return
        c=s.cool.get(k)
        if c is not None and (ts-c).total_seconds()<90: return
        s.pend[k]=({'BACK':'LAY','LAY':'BACK'}[side] if s.flip else side)
cur.execute("SELECT min(ts_recv),max(ts_recv) FROM stream_ticks"); lo,hi=cur.fetchone(); print(f"\n== PART C, replay on stream_ticks {lo} .. {hi}",flush=True)
SIMS=[Sim('BOT',False,False),Sim('SPEC',True,False),Sim('FADE',True,True)]
day=pd.Timestamp(lo).tz_convert('UTC').normalize(); end=pd.Timestamp(hi).tz_convert('UTC'); t0=time.time()
while day<=end:
    a=day+pd.Timedelta(hours=9); b=day+pd.Timedelta(hours=23)
    con2=psycopg2.connect(DB,sslmode='require'); c2=con2.cursor(name='rt'); c2.itersize=50000
    c3=con2.cursor(); c3.execute("SET LOCAL work_mem='64MB'; SET LOCAL statement_timeout='2400s'")
    c2.execute("""SELECT market_id,sel_id,ts_recv,back_px::float,back_sz::float,lay_px::float,lay_sz::float,ltp::float,tv::float,secs_to_off,inplay,status FROM stream_ticks
       WHERE ts_recv>=%s AND ts_recv<%s AND sport='racing' AND mkt='WIN' AND secs_to_off>=-1800 AND secs_to_off<=1200 ORDER BY ts_recv""",(a,b))
    st=dict(mv=defaultdict(dict),wom=defaultdict(deque),lt3=defaultdict(lambda:deque(maxlen=3)),tr3=defaultdict(lambda:deque(maxlen=3)),tv=defaultdict(float)); n=0
    for r in c2:
        n+=1; mid,sid,ts,bp,bs,lp,ls,ltp,tv,sto,inplay,status=r; k=(mid,sid)
        for s in SIMS: s.step(r,st)   # the signal below sees this tick only from the next tick on, so a fill cannot use its own tick
        if tv is not None: st['mv'][mid][sid]=tv
        h=st['wom'][k]
        if bs and ls: h.append((ts,bs/(bs+ls)))
        while h and (ts-h[0][0]).total_seconds()>30: h.popleft()
        if ltp:
            st['lt3'][k].append(ltp)
            if tv is not None and tv>st['tv'][k]: st['tr3'][k].append(ltp)
        if tv is not None: st['tv'][k]=max(tv,st['tv'][k])
    c2.close(); con2.close()
    for s in SIMS: s.no_exit+=len(s.open); s.open={}; s.pend={}
    print(f"  {day.date()}: {n} ticks, closed {[len(s.closed) for s in SIMS]}, {int(time.time()-t0)}s",flush=True)
    day+=pd.Timedelta(days=1)
print("no_exit (position with no later print, kept out of the mean):",{s.name:s.no_exit for s in SIMS},"| exits on an in-play or suspended tick:",{s.name:s.ip_exit for s in SIMS})
C=pd.DataFrame([x for s in SIMS for x in s.closed]); O=[]
if len(C):
    C['band']=pd.cut(C.px,[0,3,5,1000],labels=['2-3','3-5','5-8'],right=False).astype(str)
    C['sto_b']=pd.cut(C.sto,[0,120,300,10000],labels=['30-120','120-300','300-600']).astype(str)
    for nm,d in C.groupby('sim'):
        O.append(line(f"{nm} one tick",d)); O.append(line(f"{nm} no cost",d,'x0')); O.append(line(f"{nm} three ticks",d,'x3'))
        f=d.sort_values('ts').drop_duplicates('market_id'); O.append(line(f"{nm} FIRST per race",f))
        for c in ('side','band','sto_b','why'):
            for v,e in d.groupby(c): O.append(line(f"{nm} {c}={v}",e))
    R=pd.DataFrame(O).sort_values('t',ascending=False)
    print("\n== replay lines, sorted by t, one tick adverse unless named\n",R.round(3).to_string(index=False))
    print("\nby day, one tick\n",C.groupby(['sim','day']).x.agg(['size','mean']).round(3).to_string())
    b3=C[(C.sim=='BOT')&(C.day=='2026-11-03')]; print(f"\nreproduction, 3 Nov: replay BOT n {len(b3)} no-cost {b3.x0.mean():.3f} v bot n {len(T[T.ts.dt.date.astype(str)=='2026-11-03'])} recorded {T[T.ts.dt.date.astype(str)=='2026-11-03'].x_bot.mean():.3f} (the bot polls every 2 s, caps on its own open positions and has no restart memory, so not tick-exact)")
    W=R[R.PASS&R.line.str.contains('one tick|FIRST')]
else: W=pd.DataFrame()
print(f"\n== SURVIVORS: {len(W)}, whole-sim lines only, on a sample of a few days"); print(W.round(3).to_string(index=False) if len(W) else "none")
PY
