#!/bin/bash
# 104: THE STRATEGY FACTORY — runs itself every night at 03:30 on the server (cron), no prompting. For EVERY sport in the 2-year
# Betfair history (bf_hist_other: tennis, greyhounds, basketball, cricket, horse racing, golf, soccer extras) it derives per
# market: each runner's SP (last pre-play LTP), its price 10 minutes before the off, its in-play path, and the winner; then runs
# the same battery on every sport with CORRECT hedge accounting (profit per £1 stake = 1 - entry/exit for lays, entry/exit - 1
# for backs, 2pct spread each way, 2pct commission on profit; settled bets at SP x0.98):
#   A  lay by SP band (settle)            B  back by SP band (settle)
#   C  pre-off steamers (price fell 10%+ in last 10 min): back at SP   D  pre-off drifters (rose 10%+): lay at SP
#   E  in-play drift-back: favourite drifts to k x SP (k=1.5,2,3) -> back, settle
#   F  in-play lay-green: lay favourite at SP, green when it drifts +g% (g=20,40), stop at -s% (s=12,25), hedged P&L
#   G  in-play steam-ride: favourite shortens to 0.7 x SP in play -> back, sell 10 minutes later (if still open) else settle
#   H  favourite/longshot: lay the SP favourite when 2nd favourite within 20% (close market), settle
# Each cell: n, train-half and test-half P&L per £100, t both halves, by month. Survivor = positive both halves, t>=2 both, n>=100.
# Everything lands in strategy_results (one row per sport x strategy x band x run_date) and survivors are listed first in the
# 19:50 daily report. New sports/months are picked up automatically as the loader adds them.
mkdir -p /root/pe-factory && cat > /root/pe-factory/factory.py <<'PYFILE'
import sys, math, datetime, psycopg2, psycopg2.extras, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
SP_=0.02; COMM=0.02
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS strategy_results (run_date DATE, sport TEXT, strategy TEXT, band TEXT, n INT, n1 INT, per100_1 NUMERIC, t1 NUMERIC, n2 INT, per100_2 NUMERIC, t2 NUMERIC,
  per100_all NUMERIC, survivor BOOLEAN, months TEXT, PRIMARY KEY (run_date,sport,strategy,band))""")
today=datetime.date.today()
def tstat(x): x=pd.Series(x,dtype=float).dropna(); return float(x.mean()/(x.std(ddof=1)/math.sqrt(len(x)))) if len(x)>2 and x.std(ddof=1)>0 else 0.0
def prof(p): return p*(1-COMM) if p>0 else p
def back_settle(px,won): return prof(px*(1-SP_)-1) if won else -1.0
def lay_settle(px,won): return -(px*(1+SP_)-1) if won else prof(1.0)      # per £1 stake
def lay_hedge(e,x): return prof(1-(e*(1+SP_))/(x*(1-SP_)))                # lay at e, back at x, per £1 stake
def back_hedge(e,x): return prof((e*(1-SP_))/(x*(1+SP_))-1)               # back at e, lay at x
cur.execute("SELECT DISTINCT sport FROM bf_hist_other WHERE market_id<>'1'")
SPORTS=[r[0] for r in cur.fetchall()]; print("sports in history:",SPORTS,flush=True)
out=[]
def emit(sport,strat,df,col,bandcol='band'):
    if df is None or len(df)<100: return
    df=df.copy(); med=pd.to_datetime(df.mt).median(); df['half']=np.where(pd.to_datetime(df.mt)<med,1,2)
    for band,g in df.groupby(bandcol,observed=True):
        a=g[g.half==1][col]; b=g[g.half==2][col]
        if len(a)<40 or len(b)<40: continue
        p1,p2=a.mean()*100,b.mean()*100; t1,t2=tstat(a),tstat(b)
        surv=bool(p1>1 and p2>1 and t1>=2 and t2>=2 and len(g)>=100)
        out.append((today,sport,strat,str(band),len(g),len(a),round(p1,2),round(t1,2),len(b),round(p2,2),round(t2,2),round(g[col].mean()*100,2),surv,f"{pd.to_datetime(df.mt).min():%Y-%m}->{pd.to_datetime(df.mt).max():%Y-%m}"))
for sport in SPORTS:
    D=pd.read_sql("""SELECT market_id, event_name, market_time mt, sel, ts, ltp::float ltp, inplay FROM bf_hist_other
                     WHERE sport=%s AND market_id<>'1' AND market_type IN ('MATCH_ODDS','WIN','OUTRIGHT_WINNER','TOURNAMENT_WINNER') ORDER BY market_id, ts""",con,params=(sport,))
    if D.empty: continue
    print(sport,"rows",len(D),"markets",D.market_id.nunique(),flush=True)
    recs=[]
    for mid,g in D.groupby('market_id',sort=False):
        pre=g[~g.inplay]; ip=g[g.inplay]
        if pre.empty: continue
        sels=g.sel.unique(); n=len(sels)
        if n<2: continue
        sp={}; p10={}
        mt=pd.Timestamp(g.mt.iloc[0])
        for s in sels:
            ps=pre[pre.sel==s]
            if ps.empty: continue
            sp[s]=ps.ltp.iloc[-1]
            early=ps[pd.to_datetime(ps.ts)<=mt-pd.Timedelta(minutes=10)]
            p10[s]=early.ltp.iloc[-1] if not early.empty else None
        if len(sp)<2: continue
        # winner: in-play last price < 1.15 and clearly separated; racing: lowest final; if no in-play rows skip
        if ip.empty: continue
        last={s:ip[ip.sel==s].ltp.iloc[-1] for s in sels if not ip[ip.sel==s].empty}
        if not last: continue
        w=min(last,key=last.get)
        if last[w]>=1.15: continue
        fav=min(sp,key=sp.get); srt=sorted(sp.values()); second=srt[1] if len(srt)>1 else None
        fi=ip[ip.sel==fav]; fpath=list(fi.ltp.values); ftimes=list(pd.to_datetime(fi.ts).values)
        for s,v in sp.items():
            recs.append(dict(mid=mid,mt=mt,sel=s,sp=v,p10=p10.get(s),won=(s==w),is_fav=(s==fav),fav_sp=sp[fav],second=second,n=n,
                             fpath=fpath if s==fav else None,ftimes=ftimes if s==fav else None))
    R=pd.DataFrame(recs)
    if R.empty: continue
    print(sport,"runners",len(R),"markets",R.mid.nunique(),"win rate check",round(R.won.mean(),3),flush=True)
    R['band']=pd.cut(R.sp,[1,1.3,1.6,2,3,5,10,20,1000],labels=['1-1.3','1.3-1.6','1.6-2','2-3','3-5','5-10','10-20','20+'])
    R['lay']=[lay_settle(p,w) for p,w in zip(R.sp,R.won)]; R['back']=[back_settle(p,w) for p,w in zip(R.sp,R.won)]
    emit(sport,'A lay at SP',R,'lay'); emit(sport,'B back at SP',R,'back')
    M=R[R.p10.notna()&(R.p10>1)].copy(); M['mv']=M.sp/M.p10-1
    emit(sport,'C steamer 10%+ back at SP',M[M.mv<=-0.10],'back'); emit(sport,'D drifter 10%+ lay at SP',M[M.mv>=0.10],'lay')
    F=R[R.is_fav & R.fpath.notna()].copy()
    for k in (1.5,2.0,3.0):
        F[f'e{k}']=[next((p for p in path if p>=k*s),None) for path,s in zip(F.fpath,F.sp)]
        sub=F[F[f'e{k}'].notna()].copy(); sub['pnl']=[back_settle(e,w) for e,w in zip(sub[f'e{k}'],sub.won)]
        emit(sport,f'E fav drifts to {k}x SP: back, settle',sub,'pnl')
    for gpct,spct in ((0.2,0.12),(0.4,0.12),(0.4,0.25),(0.2,0.25)):
        def lg(row):
            e=row.sp; tg=e*(1+gpct); st=e*(1-spct)
            for p in row.fpath:
                if p>=tg: return lay_hedge(e,p)
                if p<=st: return lay_hedge(e,p)
            return lay_settle(e,row.won)
        F['pnl']=F.apply(lg,axis=1); emit(sport,f'F lay fav at SP, green +{int(gpct*100)}% stop -{int(spct*100)}%',F,'pnl')
    def ride(row):
        e=None; t0=None
        for p,t in zip(row.fpath,row.ftimes):
            if e is None and p<=0.7*row.sp: e=p; t0=t; continue
            if e is not None and (t-t0)>=np.timedelta64(10,'m'): return back_hedge(e,p)
        return back_settle(e,row.won) if e is not None else np.nan
    F['pnl']=F.apply(ride,axis=1); emit(sport,'G fav shortens to 0.7x SP in play: back, sell +10m',F[F.pnl.notna()],'pnl')
    H=R[R.is_fav & R.second.notna()].copy(); H=H[H.second<=H.sp*1.2]; emit(sport,'H lay fav when 2nd fav within 20%',H,'lay')
    # racing extras: field size bands for fav lay/back
    if 'Racing' in sport:
        R['fband']=pd.cut(R.n,[0,6,9,13,40],labels=['2-6','7-9','10-13','14+']); emit(sport,'A2 lay fav by field size',R[R.is_fav],'lay','fband'); emit(sport,'B2 back fav by field size',R[R.is_fav],'back','fband')
cur.execute("DELETE FROM strategy_results WHERE run_date=%s",(today,))
psycopg2.extras.execute_values(cur,"INSERT INTO strategy_results VALUES %s",out)
print("\ncells written",len(out)); S=pd.DataFrame(out,columns=['run_date','sport','strategy','band','n','n1','per100_1','t1','n2','per100_2','t2','per100_all','survivor','months'])
pd.set_option('display.width',250); pd.set_option('display.max_rows',400)
print("\n=== SURVIVORS (positive both halves, t>=2 both, n>=100) ===\n", S[S.survivor].sort_values('per100_2',ascending=False).to_string(index=False) if S.survivor.any() else "none this run")
print("\n=== near misses (both halves positive, any t) ===\n", S[(S.per100_1>0)&(S.per100_2>0)&~S.survivor].sort_values('per100_all',ascending=False).head(30).to_string(index=False))
print("\n=== worst cells (the opposite side is the candidate if both halves strongly negative) ===\n", S[(S.per100_1<-3)&(S.per100_2<-3)&(S.t1<=-2)&(S.t2<=-2)].sort_values('per100_all').head(20).to_string(index=False))
PYFILE
python3 -m py_compile /root/pe-factory/factory.py || exit 1
( crontab -l 2>/dev/null | grep -v pe-factory ; echo "30 3 * * * cd /root/pe-factory && python3 factory.py >> factory.log 2>&1" ) | crontab -
echo "CRON INSTALLED: strategy factory nightly 03:30. First run now:"
cd /root/pe-factory && timeout 3000 python3 factory.py
