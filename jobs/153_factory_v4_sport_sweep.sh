#!/bin/bash
# 153: FACTORY v4 — SPORT SWEEP v1 (football, two seasons of 1-minute Match Odds, bf_hist_price Aug 2024 -> Jun 2026, ~33k games).
# Same four layers as 151, our data. LAYER 1 grammar = trigger x side-role x direction x exit, scored by entry-price band:
#   triggers: GOAL (1st / 2nd / 3rd+, enter +2 or +5 min; roles scorer / conceder / draw), CLOCK (minute 1/15/30/46/60/75 given goals so
#   far 0 / 1 / 2+; roles home / draw / away), DRIFT (a side's price moved >= +15% or <= -15% over the last 10 min away from any goal;
#   roles that side). directions back / lay. exits +5 / +10 / +15 / +30 min hedged, NEXT GOAL (hedge the minute before it, else settle),
#   FT settle. Costs: 2% spread each way, 2% commission on profit. No look-ahead: every entry uses the first print at/after the trigger
#   minute, exits use first print at/after the exit minute; goal minute and the one after are never entry minutes (stale LTP).
# LAYER 2: per cell n, mean per £10, t, halves by date. Survivor = n >= 200, t >= 3.5 (threshold for ~4,000 cells), both halves > 0.
# LAYER 3: neighbour plateau (adjacent exit and delay also positive) + bootstrap on the top 20 cells. -> v4_sport_results, survivor
#   trades -> v4_sport_trades. Runs in the background (~1-2 h); 154 reads it. Grammar tested on a synthetic game locally first.
mkdir -p /root/pe-factory/v4 && cd /root/pe-factory/v4 && cat > sport_sweep.py <<'PYFILE'
import sys, math, datetime, psycopg2, psycopg2.extras, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
pd.set_option('display.width',250); pd.set_option('display.max_rows',400)
SPREAD=0.02; COMM=0.02; MAXM=95
SIDES=('HOME','DRAW','AWAY'); EXITS=('+5','+10','+15','+30','NG','FT')
def pnl_back(e,x=None,win=None):
    if x is None:
        p=10*(e*(1-SPREAD)-1) if win else -10.0
    else:
        p=10*(e*(1-SPREAD)/(x*(1+SPREAD))-1)
    return p*(1-COMM) if p>0 else p
def pnl_lay(e,x=None,win=None):
    if x is None:
        p=-10*(e*(1+SPREAD)-1) if win else 10.0
    else:
        p=10*(1-e*(1+SPREAD)/(x*(1-SPREAD)))
    return p*(1-COMM) if p>0 else p
def band(e): return '<1.5' if e<1.5 else ('1.5-2.5' if e<2.5 else ('2.5-5' if e<5 else '5+'))
def dense(s):   # minute-indexed series -> array[0..MAXM] forward-filled, NaN before first print
    a=np.full(MAXM+1,np.nan); m=s.index.values.astype(int); v=s.values; ok=(m>=0)&(m<=MAXM); a[m[ok]]=v[ok]
    last=np.nan
    for i in range(MAXM+1):
        if np.isnan(a[i]): a[i]=last
        else: last=a[i]
    return a
def game_trades(P,gl,scorers,winner,date):
    """P: dict side->dense array; gl: goal minutes; scorers: side per goal; winner: side or None. Returns trade tuples."""
    out=[]
    barred=set()
    for g in gl: barred.update((g,g+1))
    def px(side,m):
        if m>MAXM: return None
        v=P[side][m]; return None if (np.isnan(v) or v<=1.01) else float(v)
    def exits_for(side,direction,m,e):
        res=[]
        for ex in EXITS:
            if ex=='FT':
                if winner is None: continue
                win=(winner==side); p=pnl_back(e,win=win) if direction=='back' else pnl_lay(e,win=win)
            elif ex=='NG':
                nxt=[g for g in gl if g>m]
                if nxt:
                    x=px(side,nxt[0]-1)
                    if x is None or nxt[0]-1<=m: continue
                    p=pnl_back(e,x) if direction=='back' else pnl_lay(e,x)
                else:
                    if winner is None: continue
                    win=(winner==side); p=pnl_back(e,win=win) if direction=='back' else pnl_lay(e,win=win)
            else:
                h=int(ex[1:]); xm=m+h
                if xm>MAXM-3: continue
                x=px(side,xm)
                if x is None: continue
                p=pnl_back(e,x) if direction=='back' else pnl_lay(e,x)
            res.append((ex,p))
        return res
    def emit(trig,role,side,m):
        if m in barred or m<1 or m>88: return
        e=px(side,m)
        if e is None: return
        b=band(e)
        for direction in ('back','lay'):
            for ex,p in exits_for(side,direction,m,e):
                out.append((trig,role,direction,ex,b,date,round(p,3)))
    # GOAL triggers
    for k,(g,sc) in enumerate(zip(gl,scorers)):
        kk='1' if k==0 else ('2' if k==1 else '3+')
        if sc is None: continue
        conc='AWAY' if sc=='HOME' else 'HOME'
        for d in (2,5):
            for role,side in (('scorer',sc),('conceder',conc),('draw','DRAW')):
                emit(f'GOAL{kk}+{d}',role,side,g+d)
    # CLOCK triggers
    for m in (1,15,30,46,60,75):
        n=sum(1 for g in gl if g<m); st='0' if n==0 else ('1' if n==1 else '2+')
        for side in SIDES: emit(f'CLOCK{m}g{st}',side.lower(),side,m)
    # DRIFT triggers: first +15% drift and first -15% steam per side, away from goals
    for side in SIDES:
        seen={'drift':False,'steam':False}
        for m in range(11,86):
            if any(abs(m-g)<=5 for g in gl): continue
            a=px(side,m-10); b_=px(side,m)
            if a is None or b_ is None: continue
            r=b_/a-1
            if r>=0.15 and not seen['drift']: seen['drift']=True; emit('DRIFT+15',side.lower(),side,m)
            if r<=-0.15 and not seen['steam']: seen['steam']=True; emit('STEAM-15',side.lower(),side,m)
    return out
def parse_game(g):
    S={sel:s.drop_duplicates('minute').set_index('minute').ltp for sel,s in g.groupby('sel')}
    if 'DRAW' not in S or len(S['DRAW'])<30 or 'HOME' not in S or 'AWAY' not in S: return None
    P={sel:dense(S[sel]) for sel in SIDES}
    dr=S['DRAW']; dv=dr.values; dm=dr.index.values
    goals=[int(dm[i]) for i in range(1,len(dv)) if dv[i]>=dv[i-1]*1.20 and 2<=dm[i]<=92]
    gl=[]
    for gm in goals:
        if not gl or gm-gl[-1]>=4: gl.append(gm)
    scorers=[]
    for gm in gl:
        ratios={}
        for side in ('HOME','AWAY'):
            pre=P[side][gm-1]; post=P[side][min(gm+1,MAXM)]
            if not np.isnan(pre) and not np.isnan(post) and pre>0: ratios[side]=post/pre
        sc=min(ratios,key=ratios.get) if ratios else None
        scorers.append(sc if (sc and ratios[sc]<=0.90) else None)
    finals={s:P[s][MAXM] for s in SIDES}; finals={k:v for k,v in finals.items() if not np.isnan(v)}
    winner=None
    if finals:
        w=min(finals,key=finals.get)
        if finals[w]<=1.15: winner=w
    return P,gl,scorers,winner
def main():
    con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET statement_timeout='7000s'")
    cur.execute("SELECT DISTINCT event_id FROM bf_hist_price WHERE mkt='MO'"); evs=[r[0] for r in cur.fetchall()]; print("games:",len(evs),flush=True)
    parts=[]; games=0; ntr=0
    def pack(T):
        df=pd.DataFrame(T,columns=['trig','role','dir','exit','band','d','p'])
        for c in ('trig','role','dir','exit','band'): df[c]=df[c].astype('category')
        df['d']=pd.to_datetime(df.d); df['p']=df.p.astype('float32'); return df
    for b in range(0,len(evs),1500):
        D=pd.read_sql("SELECT event_id, m, minute, sel, ltp::float ltp FROM bf_hist_price WHERE mkt='MO' AND event_id = ANY(%s) AND minute BETWEEN 0 AND 95 ORDER BY event_id, sel, minute",con,params=(evs[b:b+1500],))
        T=[]
        for eid,g in D.groupby('event_id',sort=False):
            r=parse_game(g)
            if r is None: continue
            games+=1; T.extend(game_trades(*r,pd.Timestamp(g.m.iloc[0]).date()))
        if T: parts.append(pack(T)); ntr+=len(T)
        print(" processed",min(b+1500,len(evs)),"trades so far",ntr,flush=True)
    R=pd.concat(parts,ignore_index=True)
    for c in ('trig','role','dir','exit','band'): R[c]=R[c].astype(str)
    med=R.d.median(); R['half']=np.where(R.d<med,'H1','H2')
    print(f"\n=== SPORT SWEEP v1: {games} games, {len(R)} trades, {R.d.min().date()} -> {R.d.max().date()} ===")
    G=R.groupby(['trig','role','dir','exit','band'])
    C=G.p.agg(n='size',mean='mean',sd='std').reset_index(); C['t']=C['mean']/(C.sd/np.sqrt(C.n))
    H=R.groupby(['trig','role','dir','exit','band','half']).p.mean().unstack('half').reset_index(); C=C.merge(H,on=['trig','role','dir','exit','band'],how='left')
    C['pos']=G.p.apply(lambda s:(s>0).mean()).values
    N=len(C); print("cells:",N,"| survivor rule: n>=200, t>=3.5, both halves>0")
    for thr in (2.0,3.0,3.5): print(f"  t>={thr} & n>=200 & both halves>0:",int(((C.t>=thr)&(C.n>=200)&(C.H1>0)&(C.H2>0)).sum()))
    S=C[(C.t>=3.5)&(C.n>=200)&(C.H1>0)&(C.H2>0)].sort_values('t',ascending=False)
    # plateau: neighbouring exit also positive (same trig/role/dir/band)
    order={e:i for i,e in enumerate(EXITS)}
    def plateau(r):
        i=order[r.exit]; nb=[EXITS[j] for j in (i-1,i+1) if 0<=j<len(EXITS)]
        q=C[(C.trig==r.trig)&(C.role==r.role)&(C.dir==r.dir)&(C.band==r.band)&(C.exit.isin(nb))]
        return bool(len(q)) and bool((q['mean']>0).all())
    if len(S): S=S.assign(plateau=[plateau(r) for r in S.itertuples()])
    print("\n=== SURVIVORS ===\n", S.round(3).to_string(index=False) if len(S) else " none")
    print("\nTop 30 cells by t (n>=200):\n",C[C.n>=200].sort_values('t',ascending=False).head(30).round(3).to_string(index=False))
    print("\nBottom 10 by t (n>=200) — the inverse of a strong loser is a candidate too:\n",C[C.n>=200].sort_values('t').head(10).round(3).to_string(index=False))
    print("\nBy trigger family (all cells): mean t, % cells positive:\n",C.assign(fam=C.trig.str.extract(r'^([A-Z]+)')[0]).groupby('fam').agg(cells=('t','size'),mean_t=('t','mean'),pct_pos=('mean',lambda s:(s>0).mean())).round(3).to_string())
    # bootstrap top 20 (by t, n>=200)
    rng=np.random.default_rng(3); boot=[]
    for r in C[C.n>=200].sort_values('t',ascending=False).head(20).itertuples():
        x=R[(R.trig==r.trig)&(R.role==r.role)&(R.dir==r.dir)&(R.exit==r.exit)&(R.band==r.band)].p.values
        tot=np.array([rng.choice(x,len(x),replace=True).sum() for _ in range(500)]); dds=[]
        for _ in range(200):
            c=np.cumsum(rng.permutation(x)); dds.append((np.maximum.accumulate(c)-c).max())
        boot.append(dict(cell=f"{r.trig} {r.role} {r.dir} {r.exit} {r.band}",n=r.n,total=round(x.sum(),1),p5=round(np.percentile(tot,5),1),p95=round(np.percentile(tot,95),1),worst_dd=round(max(dds),1),flag='SOLID' if np.percentile(tot,5)>0 else 'FRAGILE'))
    print("\n=== BOOTSTRAP top 20 (500 resamples, per £10) ===\n",pd.DataFrame(boot).to_string(index=False))
    cur.execute("CREATE TABLE IF NOT EXISTS v4_sport_results (run_date DATE, trig TEXT, role TEXT, dir TEXT, exit TEXT, band TEXT, n INT, mean NUMERIC, t NUMERIC, h1 NUMERIC, h2 NUMERIC, pos NUMERIC, survivor BOOL)")
    cur.execute("DELETE FROM v4_sport_results WHERE run_date=current_date")
    surv=set(zip(S.trig,S.role,S.dir,S.exit,S.band)) if len(S) else set()
    def f(v): return None if pd.isna(v) else float(round(v,4))
    psycopg2.extras.execute_values(cur,"INSERT INTO v4_sport_results VALUES %s",[(datetime.date.today(),r.trig,r.role,r.dir,r.exit,r.band,int(r.n),f(r.mean),f(r.t),f(r.H1),f(r.H2),f(r.pos),(r.trig,r.role,r.dir,r.exit,r.band) in surv) for r in C.itertuples()],page_size=2000)
    cur.execute("CREATE TABLE IF NOT EXISTS v4_sport_trades (run_date DATE, trig TEXT, role TEXT, dir TEXT, exit TEXT, band TEXT, d DATE, p NUMERIC)")
    cur.execute("DELETE FROM v4_sport_trades WHERE run_date=current_date")
    keep=R[[ (a,b,c,d_,e) in surv for a,b,c,d_,e in zip(R.trig,R.role,R.dir,R.exit,R.band)]] if surv else R.iloc[0:0]
    if len(keep): psycopg2.extras.execute_values(cur,"INSERT INTO v4_sport_trades VALUES %s",[(datetime.date.today(),r.trig,r.role,r.dir,r.exit,r.band,r.d.date(),float(r.p)) for r in keep.itertuples()],page_size=5000)
    print("stored cells",N,"survivor trades",len(keep))
if __name__=='__main__': main()
PYFILE
python3 -m py_compile sport_sweep.py || exit 1
python3 - <<'PY'
import numpy as np, pandas as pd, sys; sys.path.insert(0,'/root/pe-factory/v4')
src=open('/root/pe-factory/v4/sport_sweep.py').read().split("def main():")[0].replace("from bot_core import DB","DB=''"); ns={}; exec(src,ns)
rows=[]
for m in range(0,96):
    h=2.0 if m<20 else (1.4 if m<60 else 1.2); d=3.4 if m<20 else (5.0 if m<60 else 8.0); a=3.5 if m<20 else (8.0 if m<60 else 20.0)
    if m>=93: h,d,a=1.01,50.0,100.0
    for sel,p in (('HOME',h),('DRAW',d),('AWAY',a)): rows.append(dict(event_id='e',m=pd.Timestamp('2025-01-01'),minute=m,sel=sel,ltp=p))
g=pd.DataFrame(rows); P,gl,sc,w=ns['parse_game'](g); print("goals",gl,"scorers",sc,"winner",w)
T=ns['game_trades'](P,gl,sc,w,pd.Timestamp('2025-01-01').date()); R=pd.DataFrame(T,columns=['trig','role','dir','exit','band','d','p'])
print(R[(R.trig=='GOAL1+2')&(R.role=='scorer')].to_string(index=False))
e=1.4; x=1.4; exp5=10*(e*0.98/(x*1.02)-1); print("expected back scorer +5 (flat price, pays spread):",round(exp5,3))
assert abs(R[(R.trig=='GOAL1+2')&(R.role=='scorer')&(R.dir=='back')&(R.exit=='+5')].p.iloc[0]-exp5)<0.01
assert gl==[20] and sc==['HOME'] and w=='HOME'; print("grammar tests PASS")
PY
(nohup timeout 10000 python3 sport_sweep.py > sport_sweep.log 2>&1 &); echo "sport sweep started in background -> /root/pe-factory/v4/sport_sweep.log"
