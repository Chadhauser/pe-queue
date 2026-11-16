#!/bin/bash
# 620 (Mon 16 Nov 2026). Peter: "little and often ... taking the small bites the big boys don't want" and "find all problems now".
# Part 1: small_bites.py — in-and-out trades on the tape (no holding to settlement): follow/fade steam and drift, green after 5/10 min,
#   worst-case taking both ways and posting the green; plus posting both sides inside wide spreads. By sport, market, liquidity, halves.
# Part 2: problem sweep on the paper bot — bets per day, fills, statuses, bets per event, projected date for 100 settled, commission,
#   heartbeat, recorder rows per hour since the migration. Writes reports/small_bites.md and reports/problem_sweep.md.
set -o pipefail
mkdir -p /root/pe-sports/team
cat > /root/pe-sports/team/small_bites.py <<'PYEOF'
#!/usr/bin/env python3
"""Small bites: in-and-out trades on the tape, no holding to settlement. Model-free.
Tests on every sport/market we record (stream_ticks, 2 Nov onwards), per-minute snapshots:
  STEAM_FOLLOW / STEAM_FADE / DRIFT_FOLLOW / DRIFT_FADE : mid moved >=k ticks in last 5 min -> enter now, green up after H min
     exit A = take the price at H (pessimistic: cross the spread both ways); exit P = post a 2-tick green, filled only if traded through, else take at H
  MAKE : spread >=3 ticks -> post back and lay one tick inside; filled only if traded through; a one-sided fill is closed by taking at H
Liquidity buckets by traded volume, first half vs second half by date. £2 stakes, 2% commission on winning greens."""
import sys, os, glob, subprocess, io, datetime as dt
import numpy as np, pandas as pd, psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
COMM=0.02; ST=2.0
T=[]; p=1.01
for hi,inc in [(2,.01),(3,.02),(4,.05),(6,.1),(10,.2),(20,.5),(30,1),(50,2),(100,5),(1000,10)]:
    while p<hi-1e-9: T.append(round(p,2)); p=round(p+inc,2)
T.append(1000.0); T=np.array(T)
def tk(px): return np.searchsorted(T, np.round(px,2)-1e-6)
def px(i): return T[np.clip(i,0,len(T)-1)]
# worked checks of the green-up arithmetic
def g_back_lay(b,l): return ST*(b/l-1)          # back at b, lay out at l
def g_lay_back(l,b): return ST*(1-l/b)          # lay at l, back out at b
assert abs(g_back_lay(3.0,2.5)-0.4)<1e-9   # win: +4 -2.4*1.5=+0.4 ; lose: -2+2.4=+0.4
assert abs(g_lay_back(2.5,3.0)-(2*(1-2.5/3)))<1e-9  # lay 2@2.5, back 1.667@3: win -3+3.333=+0.333, lose +2-1.667=+0.333
assert tk(2.0)==99 and px(tk(2.02))==2.02 and px(tk(3.0)+1)==3.05
COLS=['ts_recv','pt','latency_ms','market_id','sport','mkt','sel_id','sel','back_px','back_sz','lay_px','lay_sz','back2_px','lay2_px','ltp','tv','inplay','status','secs_to_off']
KEEP=['m','market_id','sport','mkt','sel_id','back_px','back_sz','lay_px','lay_sz','ltp','tv','inplay','status','secs_to_off']
def snap(df):
    df['ts_recv']=pd.to_datetime(df['ts_recv'],utc=True,errors='coerce'); df=df.dropna(subset=['ts_recv'])
    df['m']=df['ts_recv'].dt.floor('min')
    df=df.sort_values('ts_recv').drop_duplicates(['market_id','sel_id','m'],keep='last')
    return df[KEEP]
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); c=con.cursor(); c.execute("SET statement_timeout='3600s'; SET work_mem='512MB'")
c.execute("SELECT min(ts_recv)::date FROM stream_ticks"); tab0=c.fetchone()[0]
SNAP='/root/pe-sports/team/sb_snap'; os.makedirs(SNAP,exist_ok=True)
for f in sorted(glob.glob('/root/pe-archive/stream_ticks/*.csv.zst')):
    d=dt.date.fromisoformat(os.path.basename(f)[:10])
    if (tab0 and d>=tab0) or os.path.exists(f'{SNAP}/{d}.pkl'): continue
    raw=subprocess.run(['zstd','-dc',f],capture_output=True).stdout
    hdr='market_id' in raw[:400].decode('utf8','ignore').split('\n')[0]
    parts=[snap(ch) for ch in pd.read_csv(io.BytesIO(raw),header=0 if hdr else None,names=None if hdr else COLS,chunksize=2_000_000,low_memory=False)]
    del raw; x=pd.concat(parts); x=x.sort_values('m').drop_duplicates(['market_id','sel_id','m'],keep='last'); x.to_pickle(f'{SNAP}/{d}.pkl'); print('archive',d,len(x),file=sys.stderr)
d=tab0
while d and d<=dt.date.today():
    if not os.path.exists(f'{SNAP}/{d}.pkl') or d>=dt.date.today()-dt.timedelta(days=1):
        c.execute("""SELECT DISTINCT ON (market_id,sel_id,date_trunc('minute',ts_recv)) date_trunc('minute',ts_recv) m,market_id,sport,mkt,sel_id,
           back_px,back_sz,lay_px,lay_sz,ltp,tv,inplay,status,secs_to_off FROM stream_ticks WHERE ts_recv>=%s AND ts_recv<%s
           ORDER BY market_id,sel_id,date_trunc('minute',ts_recv),ts_recv DESC""",(d,d+dt.timedelta(days=1)))
        pd.DataFrame(c.fetchall(),columns=KEEP).to_pickle(f'{SNAP}/{d}.pkl'); print('table',d,file=sys.stderr)
    d+=dt.timedelta(days=1)
files=sorted(glob.glob(f'{SNAP}/*.pkl')); days=[dt.date.fromisoformat(os.path.basename(f)[:10]) for f in files]
half_split=days[len(days)//2]
out=[]; nsnap=0; nsel=0
for f in files:
  S=pd.read_pickle(f)
  S['m']=pd.to_datetime(S['m'],utc=True)
  for k in ['back_px','back_sz','lay_px','lay_sz','ltp','tv','secs_to_off']: S[k]=pd.to_numeric(S[k],errors='coerce').astype('float32')
  S['inplay']=S['inplay'].astype(str).str.lower().isin(['true','t','1','1.0'])
  S['open']=S['status'].astype(str).str.upper().isin(['OPEN','ACTIVE','NAN','NONE'])
  S=S.dropna(subset=['back_px','lay_px']); S=S[(S.back_px>1)&(S.lay_px>S.back_px)&(S.lay_px<=50)]
  S=S.sort_values(['market_id','sel_id','m']).reset_index(drop=True)
  grp=(S['market_id'].astype(str)+'|'+S['sel_id'].astype(str)); S['g']=pd.factorize(grp)[0]; del grp
  S['tb']=tk(S.back_px.values); S['tl']=tk(S.lay_px.values); S['mid']=(S.tb+S.tl)/2; S['spr']=S.tl-S.tb
  S['day']=S.m.dt.date
  S['half']=np.where(S.day<half_split,1,2)
  S['liq']=pd.cut(S.tv.fillna(0),[-1,5e3,5e4,5e5,1e12],labels=['<5k','5k-50k','50k-500k','500k+']).astype(str)
  S['phase']=np.where(S.inplay,'inplay','pre')
  nsnap+=len(S); nsel+=S.g.nunique()
  def fwd(col,H,fn):
      s=S[col]; r=(s[::-1].rolling(H,min_periods=1).max() if fn=='max' else s[::-1].rolling(H,min_periods=1).min())[::-1].shift(-1)
      return r
  for H in (5,10):
      same=(S.g.shift(-H)==S.g)&((S.m.shift(-H)-S.m)<=pd.Timedelta(minutes=2*H))
      b1=S.back_px.shift(-H); l1=S.lay_px.shift(-H); ok1=S.open.shift(-H).fillna(False)
      exit_ok= same & ok1 & ((S.phase=='inplay') | (S.secs_to_off.fillna(0)>=H*60+60)) & (S.phase==S.phase.shift(-H))
      fmax=fwd('ltp',H,'max'); fmin=fwd('ltp',H,'min')
      base= exit_ok & S.open & (S.spr<=3) & (S.back_sz>=ST) & (S.lay_sz>=ST)
      for k in (2,3,5):
          prev=S.g.shift(5)==S.g; mv=(S.mid-S.mid.shift(5)).where(prev)
          steam=(mv<=-k); drift=(mv>=k)
          for name,sig,side in [('STEAM_FOLLOW',steam,'back'),('STEAM_FADE',steam,'lay'),('DRIFT_FOLLOW',drift,'lay'),('DRIFT_FADE',drift,'back')]:
              onset=sig & ~(sig.shift(1).fillna(False) & (S.g.shift(1)==S.g))
              sel=base & onset
              if side=='back':
                  b0=S.back_px; a=g_back_lay(b0,l1)
                  tgt=px(tk(b0.values)-2); thr=px(tk(b0.values)-3); filled=fmin<=thr
                  pp=np.where(filled,g_back_lay(b0,tgt),a)
              else:
                  l0=S.lay_px; a=g_lay_back(l0,b1)
                  tgt=px(tk(l0.values)+2); thr=px(tk(l0.values)+3); filled=fmax>=thr
                  pp=np.where(filled,g_lay_back(l0,tgt),a)
              for ex,v in (('A',a),('P',pp)):
                  v=pd.Series(v,index=S.index); v=v.where(v<=0,v*(1-COMM))
                  out.append(pd.DataFrame({'strat':f'{name} k{k} H{H} {ex}','phase':S.phase[sel],'sport':S.sport[sel],'mkt':S.mkt[sel],'liq':S.liq[sel],'half':S.half[sel],'pnl':v[sel]}))
      # MAKE: post inside a spread of >=3 ticks
      mk= exit_ok & S.open & (S.spr>=3)
      Lb=pd.Series(px(S.tl.values-1),index=S.index); Bl=pd.Series(px(S.tb.values+1),index=S.index)
      fb=fmax>=pd.Series(px(S.tl.values),index=S.index)      # our back offer at Lb: filled if trades went through it to the old lay price
      fl=fmin<=pd.Series(px(S.tb.values),index=S.index)
      v=np.select([fb&fl, fb&~fl, ~fb&fl],[g_back_lay(Lb,Bl), g_back_lay(Lb,l1), g_lay_back(Bl,b1)],default=np.nan)
      v=pd.Series(v,index=S.index); v=v.where(v<=0,v*(1-COMM))
      first=mk & ~(mk.shift(1).fillna(False)&(S.g.shift(1)==S.g)) & v.notna()
      out.append(pd.DataFrame({'strat':f'MAKE H{H}','phase':S.phase[first],'sport':S.sport[first],'mkt':S.mkt[first],'liq':S.liq[first],'half':S.half[first],'pnl':v[first]}))
  del S
R=pd.concat(out,ignore_index=True); R=R.dropna(subset=['pnl'])
R.to_pickle('/root/pe-sports/team/small_bites_trades.pkl')
def summ(df,keys):
    g=df.groupby(keys+['half']).pnl.agg(['count','sum']).unstack('half').fillna(0)
    g.columns=[f'{a}{b}' for a,b in g.columns]
    for h in (1,2):
        if f'count{h}' not in g: g[f'count{h}']=0; g[f'sum{h}']=0
    g['n']=g.count1+g.count2; g['pnl']=g.sum1+g.sum2
    g['per100']=100*g.pnl/(ST*g.n); g['h1_per100']=100*g.sum1/(ST*g.count1.clip(lower=1)); g['h2_per100']=100*g.sum2/(ST*g.count2.clip(lower=1))
    return g.reset_index().sort_values('pnl',ascending=False)
pd.set_option('display.width',250); pd.set_option('display.max_rows',400)
print(f"# Small bites — in and out on the tape — {dt.datetime.utcnow():%F %H:%M} UTC\n")
print(f"Snapshots {nsnap:,} (selection-minutes), {nsel:,} selection-days, days {days[0]}..{days[-1]}, half 2 from {half_split}. £2 a bet, 2% commission on winning greens.")
print("Exit A = take the price both ways (worst case). Exit P = post a 2-tick green, counted filled only if the price traded one tick THROUGH it. MAKE = post one tick inside a 3+ tick spread on both sides, same trade-through rule.\n")
A=summ(R,['strat','phase'])
print("## Every strategy, by phase\n"); print(A[['strat','phase','n','pnl','per100','h1_per100','h2_per100']].to_string(index=False,float_format=lambda x:f'{x:.2f}'))
B=summ(R,['strat','phase','sport','mkt','liq'])
keep=B[(B.n>=150)&(B.sum1>0)&(B.sum2>0)]
print(f"\n## Cells profitable in BOTH halves with 150+ trades ({len(keep)} of {len(B)})\n"); print(keep[['strat','phase','sport','mkt','liq','n','pnl','per100','h1_per100','h2_per100']].head(80).to_string(index=False,float_format=lambda x:f'{x:.2f}'))
L=summ(R,['strat','liq']); print("\n## Thin vs deep markets (all sports)\n"); print(L[['strat','liq','n','pnl','per100','h1_per100','h2_per100']].head(60).to_string(index=False,float_format=lambda x:f'{x:.2f}'))
PYEOF
cd /root/pe-sports/team && timeout 9000 python3 small_bites.py > /root/pe-queue/reports/small_bites.md 2> /root/pe-sports/team/small_bites.log || { echo; echo "STOPPED: exit $? — last log lines:"; tail -5 /root/pe-sports/team/small_bites.log; } >> /root/pe-queue/reports/small_bites.md
python3 - > /root/pe-queue/reports/problem_sweep.md 2>&1 <<'PY'
import sys, re, datetime as dt, psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local(),sslmode='disable').cursor(); c.execute("SET statement_timeout='600s'")
def q(s,a=()):
    try: c.execute(s,a); return c.fetchall()
    except Exception as e: c.connection.rollback(); return [("ERR",str(e)[:150])]
print(f"# Problem sweep — paper bot and recorders — {dt.datetime.utcnow():%F %H:%M} UTC\n")
src=open('/root/pe-sports/bookie/bookie_v2.py').read()
print("## Bot settings in code\n"); [print('-',l.strip()) for l in src.splitlines() if re.match(r'\s*(STAKE|COMM|MIN_SIZE|MAX_PRICE|MAX_SPREAD|TAKE_WINDOW_S|MIN_MATCHED|MODE)\s*=',l)]
print("\n## Paper bets per day (last 10 days)\n| day | placed | filled | settled | pnl £ | avg fill vs asked |\n|---|---|---|---|---|---|")
for r in q("""SELECT ts::date, count(*), count(fill_ts), count(settled_ts), round(coalesce(sum(pnl),0)::numeric,2),
              round(avg(fill_price-price)::numeric,4) FROM bookie_paper WHERE ts>now()-interval '10 days' GROUP BY 1 ORDER BY 1"""): print('|'+'|'.join(str(x) for x in r)+'|')
print("\n## Status / fill kind last 7 days\n"); print(q("SELECT status, fill_kind, count(*), round(coalesce(sum(pnl),0)::numeric,2) FROM bookie_paper WHERE ts>now()-interval '7 days' GROUP BY 1,2 ORDER BY 3 DESC LIMIT 20"))
print("\n## Settled bets by market type since 11 Nov\n"); print(q("SELECT mkt, side, count(*), round(sum(pnl)::numeric,2), round((100*sum(pnl)/nullif(sum(stake),0))::numeric,1) FROM bookie_paper WHERE settled_ts IS NOT NULL AND ts>='2026-11-11' GROUP BY 1,2 ORDER BY 3 DESC"))
print("\n## Bets per event (correlation) last 7 days, filled\n"); print(q("SELECT max(n), round(avg(n),2), count(*) FILTER (WHERE n>=3) FROM (SELECT event_name, count(*) n FROM bookie_paper WHERE fill_ts IS NOT NULL AND ts>now()-interval '7 days' GROUP BY 1) x"))
r=q("SELECT count(*) FROM bookie_paper WHERE settled_ts IS NOT NULL AND ts>='2026-11-11'")[0][0]
d=q("SELECT count(*)/5.0 FROM bookie_paper WHERE settled_ts IS NOT NULL AND settled_ts>now()-interval '5 days'")[0][0]
print(f"\n## Pace to the 100-bet gate\n\nSettled since 11 Nov: {r}. Settling per day (last 5 days): {float(d or 0):.1f}.")
print("\n## Heartbeat and recorders\n"); print("bookie_heartbeat latest:", q("SELECT * FROM bookie_heartbeat ORDER BY 1 DESC LIMIT 1"))
print("stream_ticks rows per hour, last 8 h:", q("SELECT date_trunc('hour',ts_recv) h, count(*) FROM stream_ticks WHERE ts_recv>now()-interval '8 hours' GROUP BY 1 ORDER BY 1"))
print("liq_sample rows per hour, last 8 h:", q("SELECT date_trunc('hour',ts) h, count(*) FROM liq_sample WHERE ts>now()-interval '8 hours' GROUP BY 1 ORDER BY 1"))
print("\n## Passed cells in force\n"); print(q("SELECT * FROM fair_price_passed LIMIT 0") and '' ); print([d[0] for d in c.description] if c.description else '')
print(q("SELECT count(*) FROM fair_price_passed"))
PY
cd /root/pe-queue && git add reports/small_bites.md reports/problem_sweep.md && git commit -qm "620: small bites and problem sweep" && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q && echo pushed
