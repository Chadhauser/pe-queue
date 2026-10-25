#!/bin/bash
# 190: re-run of 174 with ONE FIX: an Over/Under market SETTLES the moment a goal decides it (Over 1.5 at 1-0 wins on the next goal and prints nothing afterwards). 174 looked for a post-goal print to exit, found none, and DROPPED every winning Over trade — which is why the OPEN family read −£6 per £10. Now a goal that decides the line settles the trade (win/lose at the line); a goal that does not decide it exits at the next print. MO cells unaffected.
# 174: FACTORY v4 — STATS-CONDITIONED FAMILY (the football in the football). Universe: the ~3,400 top-5-league games where Understat
# shots (minute, xG, result) are joined to minute prices (MO, OU25, OU15). Goals and score state come from Understat's TRUE goal
# minutes (price lag +1), not from price detection. At trigger minutes 20..75 (step 5) the rule reads the game so far:
#   DOM  : cumulative xG difference >= d (0.5 / 0.8 / 1.2) for one side while the game is level -> back the dominant side, lay the
#          other side, lay the draw.          OPEN : total xG >= x (1.0 / 1.5 / 2.0) with <= 1 goal scored -> back OVER 2.5 / OVER 1.5.
#   DEAD : total xG <= 0.4 at 30'+ with 0-0 -> back UNDER 2.5, back the draw.       SOT variants: shots-on-target difference >= 3 / 5.
# Exits: +10 / +20 min hedged, NEXT GOAL (exit after it), FT settle. 2% spread each way, 2% comm, book-sanity on MO entries, real prints only.
# Honesty: n >= 100 per cell (smaller universe), t >= 3.0, both halves by date > 0, bootstrap top 15. -> v4_stats_results. Waits
# (exit 75) until the shot loader has finished.
cd /root/pe-factory/v4 && cat > stats_sweep.py <<'PYFILE'
import sys, math, datetime, psycopg2, psycopg2.extras, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',250); pd.set_option('display.max_rows',400)
SPREAD=0.02; COMM=0.02; MAXM=95; TRIG=(20,25,30,35,40,55,60,65,70,75); EXITS=('+10','+20','NG','FT')
def pnl(direction,e,x=None,win=None):
    if direction=='back': p=(10*(e*(1-SPREAD)-1) if win else -10.0) if x is None else 10*(e*(1-SPREAD)/(x*(1+SPREAD))-1)
    else: p=(-10*(e*(1+SPREAD)-1) if win else 10.0) if x is None else 10*(1-e*(1+SPREAD)/(x*(1-SPREAD)))
    return p*(1-COMM) if p>0 else p
def band(e): return '<1.5' if e<1.5 else ('1.5-2.5' if e<2.5 else ('2.5-5' if e<5 else '5+'))
def series(df,mkt,sel):
    s=df[(df.mkt==mkt)&(df.sel==sel)].drop_duplicates('minute').set_index('minute').ltp
    return s[(s.index>=0)&(s.index<=MAXM)].to_dict()
def px_at(d,m,tol=2):
    for k in range(m,m+tol+1):
        if k in d and d[k]>1.0: return k,float(d[k])
    return None,None
def run():
    con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET statement_timeout='7000s'")
    M=pd.read_sql("SELECT m.understat_id, m.event_id FROM xg_price_map m WHERE EXISTS (SELECT 1 FROM understat_shots s WHERE s.understat_id::text=m.understat_id)",con)
    SH=pd.read_sql("SELECT understat_id::text understat_id, minute, team_side, xg::float xg, result FROM understat_shots WHERE understat_id::text = ANY(%s)",con,params=(list(M.understat_id),))
    SH['side']=np.where((SH.team_side=='h')^(SH.result=='OwnGoal'),'HOME','AWAY'); SH['goal']=SH.result.isin(['Goal','OwnGoal']); SH['sot']=SH.result.isin(['Goal','SavedShot'])
    print("games",len(M),"shots",len(SH),flush=True)
    T=[]; games=0
    for b in range(0,len(M),300):
        sub=M.iloc[b:b+300]
        D=pd.read_sql("SELECT event_id, m, minute, mkt, sel, ltp::float ltp FROM bf_hist_price WHERE mkt IN ('MO','OU25','OU15') AND event_id = ANY(%s) AND minute BETWEEN 0 AND 95",con,params=(list(sub.event_id),))
        for r in sub.itertuples():
            g=D[D.event_id==r.event_id]
            if g.empty: continue
            sh=SH[SH.understat_id==r.understat_id]
            if sh.empty: continue
            date=pd.Timestamp(g.m.iloc[0]).date()
            Pm={s_:series(g,'MO',s_) for s_ in ('HOME','DRAW','AWAY')}; Po={s_:series(g,'OU25',s_) for s_ in ('OVER','UNDER')}; P15={s_:series(g,'OU15',s_) for s_ in ('OVER','UNDER')}
            if len(Pm['DRAW'])<30: continue
            goals=sorted([(int(x.minute)+1,x.side) for x in sh[sh.goal].itertuples()])   # price lag +1
            games+=1
            def state(m):
                hg=sum(1 for t,s_ in goals if t<=m and s_=='HOME'); ag=sum(1 for t,s_ in goals if t<=m and s_=='AWAY'); return hg,ag
            def feats(m):
                d=sh[sh.minute<=m-1]; h=d[d.side=='HOME']; a=d[d.side=='AWAY']
                return dict(xgh=h.xg.sum(),xga=a.xg.sum(),soth=int(h.sot.sum()),sota=int(a.sot.sum()),shh=len(h),sha=len(a))
            def decided_by(goal_min,mkt_line):
                if mkt_line is None: return None
                tot_after=sum(1 for t,_ in goals if t<=goal_min)
                return 'OVER' if tot_after>mkt_line else None
            def exits(prices,sel,direction,m,e,win_fn,mkt_line=None):
                out=[]
                def settle_or_exit(ex,gm):
                    if decided_by(gm,mkt_line) is not None:
                        out.append((ex,pnl(direction,e,win=(sel=='OVER')))); return
                    xm,x=px_at(prices,gm+2)
                    if x is None: return
                    out.append((ex,pnl(direction,e,x)))
                for ex in EXITS:
                    if ex=='FT':
                        w=win_fn(sel)
                        if w is None: continue
                        out.append((ex,pnl(direction,e,win=w)))
                    elif ex=='NG':
                        nxt=[t for t,_ in goals if t>m]
                        if nxt: settle_or_exit(ex,nxt[0])
                        else:
                            w=win_fn(sel)
                            if w is None: continue
                            out.append((ex,pnl(direction,e,win=w)))
                    else:
                        h=int(ex[1:]); xm_=m+h
                        if xm_>MAXM-3: continue
                        nxt=[t for t,_ in goals if m<t<xm_]
                        if nxt: settle_or_exit(ex,nxt[0]); continue
                        xm,x=px_at(prices,xm_)
                        if x is None: continue
                        out.append((ex,pnl(direction,e,x)))
                return out
            hg_ft,ag_ft=state(200); tot=hg_ft+ag_ft
            def win_mo(sel): return (sel=='HOME' and hg_ft>ag_ft) or (sel=='AWAY' and ag_ft>hg_ft) or (sel=='DRAW' and hg_ft==ag_ft)
            def win_ou25(sel): return (tot>2.5) if sel=='OVER' else (tot<2.5)
            def win_ou15(sel): return (tot>1.5) if sel=='OVER' else (tot<1.5)
            def book_ok(m):
                b_=0
                for s_ in ('HOME','DRAW','AWAY'):
                    k,v=px_at(Pm[s_],m,0)
                    if v is None: return False
                    b_+=1/v
                return 0.92<=b_<=1.12
            def emit(trig,mkt,sel,direction,m):
                prices=Pm[sel] if mkt=='MO' else (Po[sel] if mkt=='OU25' else P15[sel]); winf=win_mo if mkt=='MO' else (win_ou25 if mkt=='OU25' else win_ou15)
                line=None if mkt=='MO' else (2.5 if mkt=='OU25' else 1.5)
                if mkt=='MO' and not book_ok(m): return
                em,e=px_at(prices,m,1)
                if e is None or e>12: return
                for ex,p in exits(prices,sel,direction,m,e,winf,line): T.append((trig,mkt+' '+sel,direction,ex,band(e),date,round(p,3)))
            for m in TRIG:
                if any(abs(m-t)<=2 for t,_ in goals): continue      # not in a goal's shadow
                hg,ag=state(m); f=feats(m); level=(hg==ag); dx=f['xgh']-f['xga']; dsot=f['soth']-f['sota']; txg=f['xgh']+f['xga']
                for d in (0.5,0.8,1.2):
                    if level and abs(dx)>=d:
                        dom='HOME' if dx>0 else 'AWAY'; oth='AWAY' if dx>0 else 'HOME'
                        emit(f'DOMxg{d}@{m}','MO',dom,'back',m); emit(f'DOMxg{d}@{m}','MO',oth,'lay',m); emit(f'DOMxg{d}@{m}','MO','DRAW','lay',m)
                for d in (3,5):
                    if level and abs(dsot)>=d:
                        dom='HOME' if dsot>0 else 'AWAY'; emit(f'DOMsot{d}@{m}','MO',dom,'back',m); emit(f'DOMsot{d}@{m}','MO','DRAW','lay',m)
                for x in (1.0,1.5,2.0):
                    if txg>=x and hg+ag<=1:
                        emit(f'OPENxg{x}@{m}','OU25','OVER','back',m); emit(f'OPENxg{x}@{m}','OU15','OVER','back',m)
                if m>=30 and txg<=0.4 and hg+ag==0:
                    emit(f'DEADxg@{m}','OU25','UNDER','back',m); emit(f'DEADxg@{m}','MO','DRAW','back',m)
        print(" processed",min(b+300,len(M)),"trades",len(T),flush=True)
    R=pd.DataFrame(T,columns=['trig','sel','dir','exit','band','d','p']); R['d']=pd.to_datetime(R.d); med=R.d.median(); R['half']=np.where(R.d<med,'H1','H2')
    R['fam']=R.trig.str.replace(r'@\d+','',regex=True); R['minute']=R.trig.str.extract(r'@(\d+)').astype(int)
    print(f"\n=== STATS SWEEP: {games} games, {len(R)} trades, {R.d.min().date()} -> {R.d.max().date()} ===")
    # cells pooled over trigger minute (rule x market x dir x exit x band), minute kept as a secondary view
    G=R.groupby(['fam','sel','dir','exit','band']); C=G.p.agg(n='size',mean='mean',sd='std',pos=lambda s:(s>0).mean()).reset_index(); C=C[(C.sd>0)&C.sd.notna()]; C['t']=C['mean']/(C.sd/np.sqrt(C.n))
    H=R.groupby(['fam','sel','dir','exit','band','half']).p.mean().unstack('half').reset_index(); C=C.merge(H,on=['fam','sel','dir','exit','band'],how='left')
    for h_ in ('H1','H2'):
        if h_ not in C: C[h_]=np.nan
    N=len(C); print("cells:",N,"| survivor rule: n>=100, t>=3.0, both halves>0")
    S=C[(C.t>=3.0)&(C.n>=100)&(C.H1>0)&(C.H2>0)].sort_values('t',ascending=False)
    print("\n=== SURVIVORS ===\n",S.round(3).to_string(index=False) if len(S) else " none")
    print("\nTop 25 by t (n>=100):\n",C[C.n>=100].sort_values('t',ascending=False).head(25).round(3).to_string(index=False))
    print("\nBottom 10 by t (n>=100):\n",C[C.n>=100].sort_values('t').head(10).round(3).to_string(index=False))
    print("\nBy family (mean t, % cells positive):\n",C.groupby('fam').agg(cells=('t','size'),mean_t=('t','mean'),pct_pos=('mean',lambda s:(s>0).mean())).round(3).to_string())
    print("\nBy trigger minute for the top family cells (mean per £10):")
    for r in C[C.n>=100].sort_values('t',ascending=False).head(5).itertuples():
        sub=R[(R.fam==r.fam)&(R.sel==r.sel)&(R.dir==r.dir)&(R.exit==r.exit)&(R.band==r.band)]
        print(" ",r.fam,r.sel,r.dir,r.exit,r.band,"->",sub.groupby('minute').p.agg(['size','mean']).round(2).to_dict('index'))
    rng=np.random.default_rng(9); boot=[]
    for r in C[C.n>=100].sort_values('t',ascending=False).head(15).itertuples():
        x=R[(R.fam==r.fam)&(R.sel==r.sel)&(R.dir==r.dir)&(R.exit==r.exit)&(R.band==r.band)].p.values
        tot=np.array([rng.choice(x,len(x),replace=True).sum() for _ in range(500)]); dds=[(np.maximum.accumulate(np.cumsum(rng.permutation(x)))-np.cumsum(rng.permutation(x))).max() for _ in range(200)]
        boot.append(dict(cell=f"{r.fam} {r.sel} {r.dir} {r.exit} {r.band}",n=r.n,total=round(x.sum(),1),p5=round(np.percentile(tot,5),1),p95=round(np.percentile(tot,95),1),worst_dd=round(max(dds),1),flag='SOLID' if np.percentile(tot,5)>0 else 'FRAGILE'))
    print("\n=== BOOTSTRAP top 15 ===\n",pd.DataFrame(boot).to_string(index=False))
    cur.execute("CREATE TABLE IF NOT EXISTS v4_stats_results (run_date DATE, fam TEXT, sel TEXT, dir TEXT, exit TEXT, band TEXT, n INT, mean NUMERIC, t NUMERIC, h1 NUMERIC, h2 NUMERIC, pos NUMERIC, survivor BOOL)"); cur.execute("DELETE FROM v4_stats_results WHERE run_date=current_date")
    surv=set(zip(S.fam,S.sel,S.dir,S.exit,S.band)) if len(S) else set()
    def f(v): return None if pd.isna(v) else float(round(v,4))
    psycopg2.extras.execute_values(cur,"INSERT INTO v4_stats_results VALUES %s",[(datetime.date.today(),r.fam,r.sel,r.dir,r.exit,r.band,int(r.n),f(r.mean),f(r.t),f(r.H1),f(r.H2),f(r.pos),(r.fam,r.sel,r.dir,r.exit,r.band) in surv) for r in C.itertuples()])
    print("stored",N)
if __name__=='__main__': run()
PYFILE
python3 -m py_compile stats_sweep.py || exit 1
timeout 7000 python3 stats_sweep.py 2>&1 | grep -v -E "UserWarning|pd.read_sql"
