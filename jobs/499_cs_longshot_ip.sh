#!/bin/bash
set -o pipefail
# 499_cs_longshot_ip (Finder 2026-11-08, queue item 439, Finder's own, source c): in-play long-shot Correct Score runners, Sep 2024 to Apr 2025.
# Item 114 read CS before the off per scoreline, item 115 the current scoreline in-play on Sep 2026; no read has asked whether the long CS lines
# in running (the scorelines two or more goals away, priced 10-200) are overpriced, where a favourite-longshot bias should be largest.
# Rule fixed before any price was read:
#  WINDOW by clock from the market time (the off), no score feed needed: W20 off+20..25 min, W55 off+70..75 min (about minute 55 with the break),
#   W80 off+95..100 min. First in-play print of each runner inside the window, filled at the worse of it and the next print within 120 s.
#  BAND on the fill print: 10-20, 20-50, 50-200. Over 200 not traded. Back and lay.
#  ALL: every runner in the band (many per game, correlated, so t_game, the t over per-game mean P&L, is shown next to t).
#  ONE: per game, window and band, the runner whose print is nearest the band's geometric middle (14.1, 31.6, 100), ties to the first by name.
#  RESULT from af_fixtures or fd_matches, as jobs/499_cs_scorelines.sh (disagree: dropped and counted). Every trade is held to the final score,
#   so a line already dead (a goal made the scoreline impossible) settles as a loser for the back, a winner for the lay; nothing drops.
#  LTP prints, one tick adverse, 2% on profit, back stake 10, lay liability 10. Halves by median market date. Standard bar, and on ALL also t_game >= 3.5.
python3 - "$@" <<'PY' 2>&1 | grep --line-buffered -v -E "UserWarning|pd.read_sql"
import sys,re,time,warnings,psycopg2,pandas as pd,numpy as np
from collections import Counter,defaultdict
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner'); sys.path.insert(0,'/root/pe-queue/jobs'); import creds
from lib_cand import step,back_settle,lay_settle,tstat,passes,norm,loose
import lib_cand; lib_cand._checks()
pd.set_option('display.width',240); pd.set_option('display.max_rows',300); pd.set_option('display.max_columns',30)
T0=time.time()
def pnl(side,p,won):
    if side=='B':
        a=step(p,-1)
        return np.nan if a<=1.01 else back_settle(a,won)
    return lay_settle(step(p,1),won)
def cs_won(s,hg,ag):
    s=s.strip()
    if s=='Any Other Home Win': return hg>ag and hg>3
    if s=='Any Other Away Win': return ag>hg and ag>3
    if s=='Any Other Draw': return hg==ag and hg>3
    m=re.fullmatch(r'(\d+) - (\d+)',s)
    return None if m is None else (int(m[1])==hg and int(m[2])==ag)
def fill(ts,px,i,side):
    p=float(px[i])
    if i+1<len(ts) and ts[i+1]-ts[i]<=120: p=max(p,float(px[i+1])) if side=='L' else min(p,float(px[i+1]))
    return p
BANDS=[('10-20',10.0,20.0,14.142),('20-50',20.0,50.0,31.623),('50-200',50.0,200.0,100.0)]
WIN=[('W20',20,25),('W55',70,75),('W80',95,100)]
def band(p):
    for nm,lo,hi,mid in BANDS:
        if lo<=p<hi or (hi==200.0 and p==200.0): return nm,mid
    return None,None
def secs(col): return (pd.to_datetime(col,utc=True)-pd.Timestamp('1970-01-01',tz='UTC'))/pd.Timedelta(seconds=1)
def gate(v,when,ev=None):
    m=np.isfinite(v); v=v[m]; when=when[m]
    if len(v)==0: return dict(n=0,mean=np.nan,t=0.0,t_game=np.nan,n1=0,h1=np.nan,n2=0,h2=np.nan,PASS=False)
    md=np.median(when); a=v[when<md]; b=v[when>=md]; t=tstat(v)
    tg=np.nan
    if ev is not None:
        g=pd.Series(v).groupby(np.asarray(ev)[m]).mean().values; tg=tstat(g)
    ok=passes(len(v),len(a),len(b),t,a.mean() if len(a) else -1,b.mean() if len(b) else -1,v.mean())
    if ev is not None: ok=bool(ok and np.isfinite(tg) and tg>=3.5)
    return dict(n=len(v),mean=v.mean(),t=t,t_game=tg,n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(b),h2=b.mean() if len(b) else np.nan,PASS=ok)
# known answers, worked by hand
assert abs(pnl('B',2.0,True)-10*0.99*0.98)<1e-9 and pnl('B',2.0,False)==-10.0
assert abs(pnl('L',6.0,False)-10/5.2*0.98)<1e-9 and pnl('L',6.0,True)==-10.0
assert abs(pnl('L',20.0,False)-10/20.0*0.98)<1e-9      # lay at 20 one tick adverse is 21 (tick 1 above 20): liability 10 wins 10/20
assert pnl('B',30.0,False)==-10.0 and abs(pnl('B',30.0,True)-10*28*0.98)<1e-9   # back 30 one tick adverse is 29 (tick 1 from 20 to 30)
assert cs_won('2 - 1',2,1) and not cs_won('2 - 1',1,2) and cs_won('Any Other Home Win',4,1) and not cs_won('Any Other Draw',3,3) and cs_won('x',0,0) is None
assert band(10.0)[0]=='10-20' and band(19.99)[0]=='10-20' and band(20.0)[0]=='20-50' and band(200.0)[0]=='50-200' and band(9.8)[0] is None and band(210.0)[0] is None
_ts=np.array([0.,100.,500.]); _px=np.array([20.0,19.0,30.0]); assert fill(_ts,_px,0,'B')==19.0 and fill(_ts,_px,0,'L')==20.0 and fill(_ts,_px,2,'L')==30.0
_g=gate(np.array([1.0,0.5]*200),np.arange(400.0)); assert _g['PASS'] is True
_g=gate(np.array([1.0,0.5]*200),np.arange(400.0),ev=np.repeat(np.arange(2),200)); assert _g['PASS'] is False   # two games only: t_game cannot pass
print("known-answer checks: OK",flush=True)
con=psycopg2.connect(creds.pg_local()); con.autocommit=True; cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='2400s'")
AF=pd.read_sql("SELECT fixture_id,kickoff,home,away,hg,ag FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND kickoff>='2024-08-25' AND kickoff<'2025-05-10'",con)
AF['t']=pd.to_datetime(AF.kickoff,utc=True); AF['H']=AF.home.map(norm); AF['A']=AF.away.map(norm); AF=AF.sort_values('t').reset_index(drop=True); at=AF.t.values.astype('datetime64[ns]')
FD=pd.read_sql("SELECT date,home,away,fthg,ftag FROM fd_matches WHERE fthg IS NOT NULL AND date>='2024-08-25' AND date<'2025-05-10'",con)
FD['H']=FD.home.map(norm); FD['A']=FD.away.map(norm); FDD=defaultdict(list)
for r in FD.itertuples(): FDD[r.date].append((r.H,r.A,(int(r.fthg),int(r.ftag))))
print(f"results held: af {len(AF)}, fd {len(FD)}; {time.time()-T0:.0f}s",flush=True)
def res_af(H,A,mt):
    lo=np.searchsorted(at,np.datetime64((mt-pd.Timedelta(hours=3)).tz_convert(None))); hi=np.searchsorted(at,np.datetime64((mt+pd.Timedelta(hours=3)).tz_convert(None)),side='right')
    return loose(H,A,[(r.H,r.A,(int(r.hg),int(r.ag))) for r in AF.iloc[lo:hi].itertuples()])
def res_fd(H,A,mt): return loose(H,A,FDD.get(mt.date(),[])) or None
SK=Counter()
def res1(ev,mt):
    h,_,a=ev.partition(' v '); H,A=norm(h),norm(a); x=res_af(H,A,mt); y=res_fd(H,A,mt)
    if x is not None and y is not None and x!=y: SK['af and fd disagree, dropped']+=1; return None
    return x if x is not None else y
def month_ip(lo,hi):
    """In-play CS prints inside the three windows only, never a print outside them."""
    return pd.read_sql("""SELECT market_id,event_name,market_time,sel,ts,ltp::float8 ltp FROM bf_hist_other
      WHERE sport='Soccer' AND market_type='CORRECT_SCORE' AND market_time>=%s AND market_time<%s AND inplay AND ltp>=1.01 AND ltp<1000
        AND ((ts>=market_time+interval '20 min' AND ts<market_time+interval '27 min')
          OR (ts>=market_time+interval '70 min' AND ts<market_time+interval '77 min')
          OR (ts>=market_time+interval '95 min' AND ts<market_time+interval '102 min'))""",con,params=(lo,hi))
rows=[]; games=0; onecheck=Counter()
for lo,hi in zip(pd.date_range('2024-08-01','2025-05-01',freq='MS').strftime('%Y-%m-%d'),pd.date_range('2024-09-01','2025-06-01',freq='MS').strftime('%Y-%m-%d')):
    P=month_ip(lo,hi)
    if len(P)==0: print(f"  {lo}: no rows",flush=True); continue
    P['tt']=secs(P.ts); P['off']=secs(P.market_time); P=P.drop_duplicates(['market_id','sel','tt']).sort_values(['market_id','sel','tt'])
    for (mid,ev,mt),g in P.groupby(['market_id','event_name','market_time']):
        mt=pd.Timestamp(mt).tz_convert('UTC'); r=res1(ev,mt)
        if r is None: SK['market: no result']+=1; continue
        SK['market: scored']+=1; games+=1; hg,ag=r; off=mt.timestamp(); nwin=Counter()
        cand=defaultdict(list)
        for s,y in g.groupby('sel',sort=False):
            won=cs_won(s,hg,ag)
            if won is None: SK['unknown runner']+=1; continue
            ts,px=y.tt.values,y.ltp.values
            for wn,a,b in WIN:
                ii=np.where((ts>=off+a*60)&(ts<off+b*60))[0]
                if len(ii)==0: continue
                i=ii[0]; nwin[(s,wn)]+=1   # the fill may use the next print up to 120 s on, so the query reads 2 min past the window
                for side in 'BL':
                    p=fill(ts,px,i,side); bn,mid_=band(p)
                    if bn is None: SK['outside 10-200, not traded']+=1; continue
                    v=pnl(side,p,won)
                    if np.isnan(v): continue
                    rows.append(('ALL',wn,bn,side,ev+'|'+str(off),off,p,won,v,s))
                    cand[(wn,bn,side)].append((abs(np.log(p/mid_)),s.strip(),p,won,v))
        for (wn,bn,side),lst in cand.items():
            lst.sort(key=lambda z:(z[0],z[1])); d,s,p,won,v=lst[0]
            rows.append(('ONE',wn,bn,side,ev+'|'+str(off),off,p,won,v,s)); onecheck[(ev,off,wn,bn,side)]+=1
    print(f"  {lo}: rows {len(P)}, games scored {games}, trades {len(rows)}, {time.time()-T0:.0f}s",flush=True)
con.close()
assert max(onecheck.values())==1, "ONE must hold one runner per game, window, band, side"
if games<2000: print(dict(SK)); sys.exit(f"only {games} games scored: a code fault, not a result")
print("counts:",dict(sorted(SK.items())),flush=True)
R=pd.DataFrame(rows,columns=['var','win','band','side','ev','when','p','won','v','sel'])
# a game wins exactly one CS runner, so in any window the winners among traded runners per game are 0 or 1
w1=R[(R['var']=='ALL')&(R.side=='L')].groupby(['ev','win']).won.sum(); print("winning runners per game-window among traded (must be 0 or 1):",dict(Counter(w1.values)),flush=True); assert w1.max()<=1
out=[]
for (var,wn,bn,side),d in R.groupby(['var','win','band','side']):
    r=gate(d.v.values.astype(float),d.when.values,ev=d.ev.values if var=='ALL' else None)
    fp=d.p.map(lambda q:step(q,-1)) if side=='B' else d.p.map(lambda q:step(q,1))
    out.append(dict(var=var,win=wn,band=bn,side=side,**r,games=d.ev.nunique(),won=d.won.mean(),imp=(1/fp).mean(),med_p=d.p.median()))
S=pd.DataFrame(out)
print(f"\ndates {pd.Timestamp(R.when.min(),unit='s'):%Y-%m-%d} to {pd.Timestamp(R.when.max(),unit='s'):%Y-%m-%d}; games {R.ev.nunique()}; lines {len(S)}")
print("\n== EVERY LINE\n",S.sort_values(['var','side','win','band']).drop(columns=['n1','n2']).round(3).to_string(index=False))
print("\n== TOP 15 by t\n",S.sort_values('t',ascending=False).head(15).drop(columns=['n1','n2']).round(3).to_string(index=False))
L=R[(R['var']=='ALL')&(R.side=='L')]
print("\n== LAY ALL by scoreline, all windows and bands pooled (read only, not a gate)\n",L.groupby('sel').agg(n=('v','size'),mean=('v','mean'),won=('won','mean'),med_p=('p','median')).sort_values('n',ascending=False).head(20).round(3).to_string())
Y=S[S.PASS]; print(f"\n== SURVIVORS: {len(Y)} of {len(S)}\n",Y.round(3).to_string(index=False) if len(Y) else "none")
print(f"total {time.time()-T0:.0f}s")
PY
