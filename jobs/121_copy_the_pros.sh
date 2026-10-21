#!/bin/bash
# 121: COPY THE PROS FIRST (Peter 21 Oct: "shouldn't you emulate before innovation? Get the money in and then be clever").
# The proven, widely-traded methods we never ran through the Factory, tested on OUR data with the usual rules (2pct spread each
# way, 2pct comm, train/test halves, t>=2 both). Results -> strategy_results (sport='Soccer-copy' / 'CLV') so the morning report
# lists survivors with everything else.
#  1. LAY THE DRAW classic (Goal Profits / Psychoff / Caan): home fav 1.50-2.20 at SP, draw 3.2-4.2; lay draw at KO; exit (back
#     draw) at the first goal = first in-play minute where the draw LTP jumps >=20pct vs previous minute; stop at 65' at the draw
#     price then. 2-year Betfair history, bf_hist_other soccer MATCH_ODDS. Bands by draw SP.
#  2. CLOSING LINE VALUE: Betfair SP vs Pinnacle closing price on the same match from the football-data seasons already loaded
#     (any table holding both PSH/PSD/PSA and Betfair odds). Back where Betfair SP > Pinnacle x 1.03 (settle), lay where Betfair
#     SP < Pinnacle x 0.97. Bands by edge size. If no table has both, print exactly which columns exist so the loader can be fixed.
#  3. UNDER 2.5 at 0-0 after 60' and OVER 1.5 at 0-0 at HT: on the live ladder tape (liq_sample OU25/OU15 since 10 Oct) — small n,
#     reported as data-collection numbers, not a verdict.
cd /root/pe-factory && cat > copy_pros.py <<'PYFILE'
import sys, math, datetime, psycopg2, psycopg2.extras, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
SP_=0.02; COMM=0.02; today=datetime.date.today()
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
pd.set_option('display.width',250); pd.set_option('display.max_rows',300)
def tstat(x): x=pd.Series(x,dtype=float).dropna(); return float(x.mean()/(x.std(ddof=1)/math.sqrt(len(x)))) if len(x)>2 and x.std(ddof=1)>0 else 0.0
def prof(p): return p*(1-COMM) if p>0 else p
def lay_hedge(e,x): return prof(1-(e*(1+SP_))/(x*(1-SP_)))
def lay_settle(px,won): return -(px*(1+SP_)-1) if won else prof(1.0)
def back_settle(px,won): return prof(px*(1-SP_)-1) if won else -1.0
out=[]
def emit(sport,strat,df,col,bandcol='band'):
    if df is None or len(df)<60: print(f"  {strat}: n={0 if df is None else len(df)} too small"); return
    df=df.copy(); med=pd.to_datetime(df.mt).median(); df['half']=np.where(pd.to_datetime(df.mt)<med,1,2)
    print(f"\n== {strat}: n {len(df)} | per £100 {df[col].mean()*100:+.1f} | t {tstat(df[col]):.1f}")
    for band,g in df.groupby(bandcol,observed=True):
        a=g[g.half==1][col]; b=g[g.half==2][col]
        if len(a)<25 or len(b)<25: continue
        p1,p2=a.mean()*100,b.mean()*100; t1,t2=tstat(a),tstat(b); surv=bool(p1>1 and p2>1 and t1>=2 and t2>=2 and len(g)>=100)
        print(f"   band {band}: n {len(g)} | h1 {p1:+.1f} (t {t1:.1f}) | h2 {p2:+.1f} (t {t2:.1f}) {'SURVIVOR' if surv else ''}")
        out.append((today,sport,strat,str(band),len(g),len(a),round(p1,2),round(t1,2),len(b),round(p2,2),round(t2,2),round(g[col].mean()*100,2),surv,f"{pd.to_datetime(df.mt).min():%Y-%m}->{pd.to_datetime(df.mt).max():%Y-%m}"))
# ---------- 1. LAY THE DRAW on 2-year history
print("=== 1. LAY THE DRAW classic — bf_hist_other Soccer MATCH_ODDS",flush=True)
cur.execute("SELECT count(DISTINCT market_id) FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_id<>'1'"); print("soccer MO markets in history:",cur.fetchone()[0],flush=True)
cur.execute("SELECT market_id FROM bf_hist_other WHERE sport='Soccer' AND market_type='MATCH_ODDS' AND market_id<>'1' GROUP BY market_id HAVING bool_or(inplay) AND bool_or(NOT inplay)")
mids=[r[0] for r in cur.fetchall()]; print("with pre-match AND in-play rows:",len(mids),flush=True)
recs=[]
for i in range(0,len(mids),1500):
    D=pd.read_sql("SELECT market_id, event_name, market_time mt, sel, ts, ltp::float ltp, inplay FROM bf_hist_other WHERE market_id = ANY(%s) AND market_type='MATCH_ODDS' ORDER BY market_id, ts",con,params=(mids[i:i+1500],))
    for mid,g in D.groupby('market_id',sort=False):
        pre=g[~g.inplay]; ip=g[g.inplay]
        if pre.empty or ip.empty: continue
        sels=list(g.sel.unique())
        draw=[s for s in sels if str(s).strip().lower() in ('the draw','draw')]
        if len(draw)!=1 or len(sels)!=3: continue
        draw=draw[0]; teams=[s for s in sels if s!=draw]
        sp={s:pre[pre.sel==s].ltp.iloc[-1] for s in sels if not pre[pre.sel==s].empty}
        if len(sp)!=3 or sp[draw]<=1: continue
        ev=str(g.event_name.iloc[0]); home=ev.split(' v ')[0].strip() if ' v ' in ev else None
        hs=[s for s in teams if home and str(s).strip()==home]
        home_sp=sp[hs[0]] if hs else None
        if home_sp is None: continue
        mt=pd.Timestamp(g.mt.iloc[0]); dr=ip[ip.sel==draw].copy()
        if len(dr)<10: continue
        dr['minute']=(pd.to_datetime(dr.ts)-mt).dt.total_seconds()/60.0
        dr=dr[(dr.minute>=0)&(dr.minute<=120)]
        if dr.empty: continue
        prev=dr.ltp.shift(1); jump=dr[(dr.ltp>=prev*1.20)&(dr.minute>=1)]
        e=sp[draw]
        last=ip[ip.sel==draw].ltp.iloc[-1]; draw_won=last<1.15
        if not jump.empty and jump.minute.iloc[0]<=65:
            x=jump.ltp.iloc[0]; pnl=lay_hedge(e,x); how='goal'
        else:
            at65=dr[dr.minute>=65]
            if at65.empty: pnl=lay_settle(e,draw_won); how='settle'
            else: x=at65.ltp.iloc[0]; pnl=lay_hedge(e,x); how='stop65'
        recs.append(dict(mid=mid,mt=mt,home_sp=home_sp,draw_sp=e,pnl=pnl,how=how))
    print(" processed",min(i+1500,len(mids)),flush=True)
R=pd.DataFrame(recs)
if len(R):
    print("all 3-way soccer markets scored:",len(R),"| exit mix:",R.how.value_counts().to_dict())
    Q=R[(R.home_sp>=1.5)&(R.home_sp<=2.2)&(R.draw_sp>=3.2)&(R.draw_sp<=4.2)].copy(); Q['band']=pd.cut(Q.draw_sp,[3.2,3.5,3.8,4.2])
    emit('Soccer-copy','LTD classic: home 1.5-2.2, draw 3.2-4.2, exit 1st goal, stop 65',Q,'pnl')
    W=R[(R.draw_sp>=3.0)&(R.draw_sp<=5.0)].copy(); W['band']=pd.cut(W.draw_sp,[3.0,3.5,4.0,4.5,5.0])
    emit('Soccer-copy','LTD any favourite: draw 3.0-5.0, exit 1st goal, stop 65',W,'pnl')
    H=R[(R.home_sp>=1.5)&(R.home_sp<=2.2)&(R.draw_sp>=3.2)&(R.draw_sp<=4.2)].copy(); H['band']=pd.cut(H.home_sp,[1.5,1.7,1.9,2.2])
    emit('Soccer-copy','LTD classic by home price',H,'pnl')
# ---------- 2. CLOSING LINE VALUE — find a table with Pinnacle + Betfair odds
print("\n=== 2. CLOSING LINE VALUE — looking for Pinnacle + Betfair odds columns",flush=True)
cur.execute("""SELECT table_name, string_agg(column_name,',' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema='public'
               GROUP BY table_name HAVING bool_or(lower(column_name) IN ('psh','pinnacle_home','ps_h','pinh')) OR bool_or(lower(column_name) LIKE '%pinn%')""")
cands=cur.fetchall()
for t,cols in cands: print("  candidate",t,":",cols[:400])
done_clv=False
for t,cols in cands:
    cl=[c.lower() for c in cols.split(',')]
    def pick(*names):
        for n in names:
            if n in cl: return cols.split(',')[cl.index(n)]
        return None
    ph,pdw,pa=pick('psh','pinnacle_home','pinh'),pick('psd','pinnacle_draw','pind'),pick('psa','pinnacle_away','pina')
    bh,bd,ba=pick('bfeh','bfh','betfair_home','bf_home','b365h'),pick('bfed','bfd','betfair_draw','bf_draw','b365d'),pick('bfea','bfa','betfair_away','bf_away','b365a')
    res=pick('ftr','result','fthg'); date=pick('date','match_date','kickoff','ko')
    if not (ph and pdw and pa and bh and bd and ba and res and date): continue
    print(f"  using {t}: pinnacle {ph},{pdw},{pa} vs exchange/bookie {bh},{bd},{ba} result {res} date {date}")
    X=pd.read_sql(f'SELECT "{date}" d,"{ph}" ph,"{pdw}" pd,"{pa}" pa,"{bh}" bh,"{bd}" bd,"{ba}" ba,"{res}" r FROM "{t}"',con)
    hg=pick('fthg'); ag=pick('ftag')
    if res=='fthg' and ag:
        Y=pd.read_sql(f'SELECT "{ag}" ag FROM "{t}"',con); X['r']=np.where(X.r>Y.ag,'H',np.where(X.r<Y.ag,'A','D'))
    X=X.dropna(); X['mt']=pd.to_datetime(X.d,errors='coerce'); X=X[X.mt.notna()]
    rows=[]
    for side,pc,bc in (('H','ph','bh'),('D','pd','bd'),('A','pa','ba')):
        s=X[[pc,bc,'r','mt']].copy(); s.columns=['pin','bf','r','mt']; s=s[(s.pin>1)&(s.bf>1)]
        s['edge']=s.bf/s.pin-1; s['won']=(s.r==side)
        s['back']=[back_settle(b,w) for b,w in zip(s.bf,s.won)]; s['lay']=[lay_settle(b,w) for b,w in zip(s.bf,s.won)]
        s['side']=side; rows.append(s)
    S=pd.concat(rows)
    B=S[S.edge>=0.03].copy(); B['band']=pd.cut(B.edge,[0.03,0.06,0.10,0.20,2.0]); emit('CLV',f'back when exchange > Pinnacle (edge bands) [{t}]',B,'back')
    L=S[S.edge<=-0.03].copy(); L['band']=pd.cut(L.edge,[-1.0,-0.20,-0.10,-0.06,-0.03]); emit('CLV',f'lay when exchange < Pinnacle (edge bands) [{t}]',L,'lay')
    B2=B.copy(); B2['band']=B2.side; emit('CLV',f'back exchange>Pinnacle by side [{t}]',B2,'back')
    done_clv=True
if not done_clv:
    cur.execute("SELECT table_name, string_agg(column_name,',' ORDER BY ordinal_position) FROM information_schema.columns WHERE table_schema='public' AND table_name ILIKE ANY (ARRAY['%football%','%season%','%odds%','%fixture%','%match%']) GROUP BY 1")
    print("  NO table with Pinnacle+exchange odds found. Tables that look like football odds and their columns:")
    for t,c in cur.fetchall(): print("   ",t,":",c[:300])
# ---------- 3. tape cells (small n, data collection)
print("\n=== 3. Live tape: UNDER 2.5 at 0-0 after 60' / OVER 1.5 at 0-0 at HT (liq_sample since 10 Oct, small n)",flush=True)
try:
    G=pd.read_sql("""SELECT event_name, goal_ts, min(minute) minute FROM liq_goal_depth WHERE mkt='MO' AND offset_s=0 AND upper(coalesce(sel,'')) NOT IN ('DRAW','THE DRAW','X') AND pre_ltp>0 AND ltp>0
                     GROUP BY event_name, goal_ts HAVING min(ltp/pre_ltp)<=0.97 ORDER BY event_name, goal_ts""",con)
    goals={}
    for ev,g in G.groupby('event_name'):
        ts=[]; last=None
        for t,m in zip(g.goal_ts,g.minute):
            if last is None or (t-last).total_seconds()>=240: ts.append((t,m)); last=t
        goals[ev]=ts
    def px_at(ev,mkt,sel_like,lo,hi,col):
        cur.execute(f"SELECT {col} FROM liq_sample WHERE event_name=%s AND mkt=%s AND sel ILIKE %s AND minute BETWEEN %s AND %s AND {col} IS NOT NULL ORDER BY ts LIMIT 1",(ev,mkt,sel_like,lo,hi)); r=cur.fetchone(); return float(r[0]) if r else None
    cur.execute("SELECT DISTINCT event_name FROM liq_sample WHERE mkt IN ('OU25','OU15') AND minute>0"); evs=[r[0] for r in cur.fetchall()]
    u=[]; o=[]
    for ev in evs:
        gl=goals.get(ev,[]); mins=[m for _,m in gl if m is not None]
        if not any(m<=60 for m in mins):
            e=px_at(ev,'OU25','Under%',60,63,'back_px')
            if e:
                later=[m for m in mins if m>60]; won=len(later)<3   # under 2.5 from 0-0 at 60 loses only on 3+ late goals
                u.append(dict(ev=ev,e=e,won=won,pnl=back_settle(e,won)))
        if not any(m<=45 for m in mins):
            e=px_at(ev,'OU15','Over%',45,47,'back_px')
            if e:
                later=[m for m in mins if m>45]; won=len(later)>=2
                o.append(dict(ev=ev,e=e,won=won,pnl=back_settle(e,won)))
    for name,L in (("UNDER 2.5 at 0-0 at 60'",u),("OVER 1.5 at 0-0 at HT",o)):
        if L:
            d=pd.DataFrame(L); print(f"  {name}: n {len(d)} | win {d.won.mean():.0%} | avg price {d.e.mean():.2f} | per £100 {d.pnl.mean()*100:+.1f}")
        else: print(f"  {name}: no qualifying games on tape yet")
except Exception as e: print("tape cells:",repr(e)[:200])
if out:
    cur.execute("DELETE FROM strategy_results WHERE run_date=%s AND sport IN ('Soccer-copy','CLV')",(today,))
    psycopg2.extras.execute_values(cur,"INSERT INTO strategy_results VALUES %s",out); print("\ncells written:",len(out))
PYFILE
python3 -m py_compile copy_pros.py || exit 1
timeout 3300 python3 copy_pros.py
( crontab -l 2>/dev/null | grep -v copy_pros ; echo "15 5 * * * cd /root/pe-factory && python3 copy_pros.py >> copy_pros.log 2>&1" ) | crontab -
