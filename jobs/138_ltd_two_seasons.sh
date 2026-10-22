#!/bin/bash
# 138: LAY THE DRAW ON THE RIGHT TABLE — bf_hist_price (Aug 2024 -> Jun 2026, two full seasons, 1-minute LTPs, normalised team
# names hw/aw). Replaces the 121/127 runs which used the Jul-Sep 2026 table by mistake.
#  Entry: lay the draw at the last pre-KO draw LTP (minute<=1). Goal = draw LTP jumps >=20pct minute-to-minute.
#  Exits side by side: E1 first goal (hedge at the post-goal draw price), stop 65' | E2 draw drifts +10pct any time before 65'
#  (near-miss drift) else E1 | E3 draw drifts +20pct else E1 | all with 2pct spread each way + 2pct comm, per £1 lay stake.
#  Cuts: home price band, draw price band, country, and the Poisson rolling-form filter (football_matches, previous 10 games) —
#  xG band, P(home) band, and the S1/S7-style combined filter. Survivor = both halves >1 per £100, t>=2 both, n>=100.
cd /root/pe-factory && cat > ltd_two_seasons.py <<'PYFILE'
import sys, re, math, datetime, unicodedata, psycopg2, psycopg2.extras, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
SP_=0.02; COMM=0.02; today=datetime.date.today()
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor(); cur.execute("SET statement_timeout='1800s'")
pd.set_option('display.width',250); pd.set_option('display.max_rows',400)
def tstat(x): x=pd.Series(x,dtype=float).dropna(); return float(x.mean()/(x.std(ddof=1)/math.sqrt(len(x)))) if len(x)>2 and x.std(ddof=1)>0 else 0.0
def prof(p): return p*(1-COMM) if p>0 else p
def lay_hedge(e,x): return prof(1-(e*(1+SP_))/(x*(1-SP_)))
def lay_settle(px,won): return -(px*(1+SP_)-1) if won else prof(1.0)
out=[]
def emit(strat,df,col,bandcol='band'):
    df=df[df[col].notna()]
    if len(df)<60: print(f"  {strat}: n={len(df)} too small"); return
    df=df.copy(); med=df.mt.median(); df['half']=np.where(df.mt<med,1,2)
    print(f"\n== {strat}: n {len(df)} | per £100 {df[col].mean()*100:+.1f} | t {tstat(df[col]):.1f} | {df.mt.min().date()} -> {df.mt.max().date()}")
    for band,g in df.groupby(bandcol,observed=True):
        a=g[g.half==1][col]; b=g[g.half==2][col]
        if len(a)<25 or len(b)<25: continue
        p1,p2=a.mean()*100,b.mean()*100; t1,t2=tstat(a),tstat(b); surv=bool(p1>1 and p2>1 and t1>=2 and t2>=2 and len(g)>=100)
        print(f"   {str(band):34s} n {len(g):5d} | h1 {p1:+6.1f} (t {t1:4.1f}) | h2 {p2:+6.1f} (t {t2:4.1f}) {'SURVIVOR' if surv else ''}")
        out.append((today,'Soccer-2s',strat,str(band),int(len(g)),int(len(a)),float(round(p1,2)),float(round(t1,2)),int(len(b)),float(round(p2,2)),float(round(t2,2)),float(round(g[col].mean()*100,2)),surv,f"{df.mt.min():%Y-%m}->{df.mt.max():%Y-%m}"))
cur.execute("SELECT mkt, count(DISTINCT event_id) FROM bf_hist_price GROUP BY 1 ORDER BY 2 DESC"); print("bf_hist_price markets (events):",cur.fetchall(),flush=True)
cur.execute("SELECT min(m), max(m), count(DISTINCT event_id) FROM bf_hist_price WHERE mkt='MO'"); print("MO span:",cur.fetchone(),flush=True)
cur.execute("SELECT DISTINCT event_id FROM bf_hist_price WHERE mkt='MO'"); evs=[r[0] for r in cur.fetchall()]
recs=[]
for i in range(0,len(evs),2000):
    D=pd.read_sql("SELECT event_id, event_name, hw, aw, country, m, minute, sel, ltp::float ltp FROM bf_hist_price WHERE mkt='MO' AND event_id = ANY(%s) ORDER BY event_id, m",con,params=(evs[i:i+2000],))
    for eid,g in D.groupby('event_id',sort=False):
        dr=g[g.sel=='DRAW']; hm=g[g.sel=='HOME']
        if len(dr)<20 or hm.empty: continue
        pre=dr[dr.minute<=0]; pre=pre if not pre.empty else dr[dr.minute<=1]; e=pre.ltp.iloc[-1] if not pre.empty else dr.ltp.iloc[0]
        hpre=hm[hm.minute<=0]; hpre=hpre if not hpre.empty else hm[hm.minute<=1]; h=hpre.ltp.iloc[-1] if not hpre.empty else hm.ltp.iloc[0]
        ip=dr[(dr.minute>=1)&(dr.minute<=120)].reset_index(drop=True)
        if len(ip)<10 or e<=1 or h<=1: continue
        prev=ip.ltp.shift(1); jumps=ip[(ip.ltp>=prev*1.20)]
        gmin=int(jumps.minute.iloc[0]) if not jumps.empty else None; gpx=float(jumps.ltp.iloc[0]) if not jumps.empty else None
        last=float(dr.ltp.iloc[-1]); draw_won=last<1.15
        at65=ip[ip.minute>=65]; p65=float(at65.ltp.iloc[0]) if not at65.empty else None
        def e1():
            if gmin is not None and gmin<=65: return lay_hedge(e,gpx),'goal'
            return (lay_hedge(e,p65),'stop65') if p65 else (lay_settle(e,draw_won),'settle')
        def drift(k):
            w=ip[(ip.minute<65)&(ip.ltp>=e*(1+k))]
            if gmin is not None: w=w[w.minute<gmin]
            if not w.empty: return lay_hedge(e,float(w.ltp.iloc[0])),f'drift{int(k*100)}'
            return e1()
        p1,x1=e1(); p2,x2=drift(0.10); p3,x3=drift(0.20)
        recs.append(dict(eid=eid,ev=g.event_name.iloc[0],hw=g.hw.iloc[0],aw=g.aw.iloc[0],country=g.country.iloc[0],mt=pd.Timestamp(g.m.iloc[0]),home_sp=h,draw_sp=e,gmin=gmin,e1=p1,x1=x1,e2=p2,x2=x2,e3=p3,x3=x3))
    print(" processed",min(i+2000,len(evs)),flush=True)
R=pd.DataFrame(recs); print("LTD-scored events:",len(R),"| exit mix E1:",R.x1.value_counts().to_dict(),flush=True)
R['mt']=pd.to_datetime(R.mt,utc=True)
Q=R[(R.home_sp>=1.5)&(R.home_sp<=2.2)&(R.draw_sp>=3.2)&(R.draw_sp<=4.2)].copy()
for col,label in (('e1','E1 first goal / stop 65'),('e2','E2 drift +10pct else E1'),('e3','E3 drift +20pct else E1')):
    Q['band']=pd.cut(Q.draw_sp,[3.2,3.5,3.8,4.2]); emit(f'LTD classic [{label}] by draw price',Q,col)
    Q['band']=pd.cut(Q.home_sp,[1.5,1.7,1.9,2.2]); emit(f'LTD classic [{label}] by home price',Q,col)
Q['band']=Q.country; emit('LTD classic [E1] by country',Q,'e1')
W=R[(R.draw_sp>=3.0)&(R.draw_sp<=6.0)].copy(); W['band']=pd.cut(W.draw_sp,[3.0,3.5,4.0,4.5,5.0,6.0]); emit('LTD any favourite [E1] by draw price',W,'e1')
# ---- Poisson rolling form from football_matches
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"[^a-z0-9 ]"," ",s); return re.sub(r"\s+"," ",s).strip()
F=pd.read_sql("SELECT date::date d, league_code, home_team, away_team, fthg, ftag FROM football_matches WHERE fthg IS NOT NULL AND date>='2023-06-01' ORDER BY date",con)
F['h']=F.home_team.map(norm); F['a']=F.away_team.map(norm); F['d']=pd.to_datetime(F.d)
long=pd.concat([F[['d','h','fthg','ftag']].rename(columns={'h':'team','fthg':'gf','ftag':'ga'}),F[['d','a','ftag','fthg']].rename(columns={'a':'team','ftag':'gf','fthg':'ga'})]).sort_values('d')
long['gf10']=long.groupby('team').gf.transform(lambda s: s.shift(1).rolling(10,min_periods=6).mean()); long['ga10']=long.groupby('team').ga.transform(lambda s: s.shift(1).rolling(10,min_periods=6).mean())
form=long.dropna(subset=['gf10']).drop_duplicates(['team','d'])
teams=form.team.unique(); tok={t:set(t.split()) for t in teams}
def find(hw):
    hw=str(hw).lower().strip()
    if not hw: return None
    c=[t for t in teams if hw in t.split() or t.startswith(hw) or hw in t]
    return min(c,key=len) if c else None
R['hteam']=R.hw.map(find); R['ateam']=R.aw.map(find); R['d']=R.mt.dt.tz_localize(None).dt.normalize()
print("name match: home",R.hteam.notna().mean().round(3),"away",R.ateam.notna().mean().round(3),flush=True)
def join(R,col,pref):
    f=form.rename(columns={'team':col,'gf10':pref+'gf','ga10':pref+'ga'})[[col,'d',pref+'gf',pref+'ga']].sort_values('d')
    return pd.merge_asof(R.sort_values('d'),f,on='d',by=col,tolerance=pd.Timedelta(days=1),direction='nearest')
M=join(R.dropna(subset=['hteam','ateam']).rename(columns={'hteam':'th','ateam':'ta'}),'th','h_'); M=join(M,'ta','a_')
M=M[M.h_gf.notna()&M.a_gf.notna()].copy(); print("joined to rolling form:",len(M),"of",len(R),flush=True)
M['lam_h']=np.sqrt(M.h_gf*M.a_ga); M['lam_a']=np.sqrt(M.a_gf*M.h_ga); M['xg']=M.lam_h+M.lam_a
def ph(lh,la):
    P=[math.exp(-lh)*lh**i/math.factorial(i) for i in range(8)]; Q=[math.exp(-la)*la**j/math.factorial(j) for j in range(8)]
    return sum(P[i]*Q[j] for i in range(8) for j in range(8) if i>j)
M['p_home']=[ph(a,b) for a,b in zip(M.lam_h,M.lam_a)]
Qm=M[(M.home_sp>=1.5)&(M.home_sp<=2.2)&(M.draw_sp>=3.2)&(M.draw_sp<=4.2)].copy()
Qm['band']=pd.cut(Qm.xg,[0,2.2,2.6,3.0,10]); emit('LTD classic + Poisson: by expected goals [E1]',Qm,'e1'); emit('LTD classic + Poisson: by expected goals [E2]',Qm,'e2')
Qm['band']=pd.cut(Qm.p_home,[0,0.4,0.5,0.6,1]); emit('LTD classic + Poisson: by P(home) [E1]',Qm,'e1')
S=Qm[(Qm.xg>=2.6)&(Qm.p_home>=0.5)].copy(); S['band']='xg>=2.6 & p_home>=0.5'; emit('LTD classic + Poisson FILTER [E1]',S,'e1'); emit('LTD classic + Poisson FILTER [E2]',S,'e2')
Wm=M[(M.draw_sp>=3.0)&(M.draw_sp<=6.0)].copy(); Wm['band']=pd.cut(Wm.xg,[0,2.2,2.6,3.0,10]); emit('LTD any fav + Poisson: by expected goals [E1]',Wm,'e1')
if out:
    cur.execute("DELETE FROM strategy_results WHERE run_date=%s AND sport='Soccer-2s'",(today,)); psycopg2.extras.execute_values(cur,"INSERT INTO strategy_results VALUES %s",out); print("\ncells written:",len(out))
S2=pd.DataFrame([o for o in out if o[12]],columns=['d','sport','strategy','band','n','n1','p1','t1','n2','p2','t2','all','surv','months'])
print("\n=== SURVIVORS ===\n", S2[['strategy','band','n','p1','p2','t1','t2']].to_string(index=False) if len(S2) else "none")
PYFILE
python3 -m py_compile ltd_two_seasons.py || exit 1
timeout 3400 python3 ltd_two_seasons.py 2>&1 | grep -v -E "UserWarning|pd.read_sql"
