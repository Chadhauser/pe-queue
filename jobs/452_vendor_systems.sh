#!/bin/bash
set -o pipefail
# 452 (Finder 2026-11-02, queue item 4): VENDOR SYSTEMS through the honest engine. bf_hist_price (1-min LTP, last trade in the minute,
# second half = Betfair clock minus half-time offset) + af_events goal minutes via af_price_map. Four systems, exact rules from the queue:
#  (a) LTD: draw at KO (minute-0 print) in 5.6-7.6 -> LAY the draw. Exits: FT, or first goal +2 (first real print g+2..g+5).
#  (b) 2H GOALS: HT 0-0 and KO Over-2.5 <= 1.80 -> BACK Over 2.5 at the first real print 46-48, hold to settle.
#  (c) EARLY GOAL GLITCH: pre-match favourite (shorter KO price) scores the first goal before 20' (1-0 to fav) and is <= 1.30 at the
#      decision print (first real print g+2..g+4) -> LAY the favourite. Exit at the equaliser +2 (real print e+2..e+5) or at 60' (first
#      real print 60..63), whichever first; variant: hold to FT.
#  (d) LATE DRAW: first minute m in 71..85 with score 1-1 (goals <= m) and draw print <= 2.0 -> BACK the draw, hold to FT.
# Honesty: no forward-fill. Decision on a real print; FILL at the WORSE of the decision print and the next real print within 2 minutes
# (covers a goal landing inside the 1-minute granularity), then one tick adverse. Exits one tick adverse. MO never settles early, so a
# missing exit print is NOT skipped: the position is held to the first real print at any later minute, else settled at the result. Back stake £10 / lay liability £10, 2% commission on profit.
# (b): a 2H goal at/before the decision minute = skip and count (all would-be winners, biased against). Halves = season 2024 vs 2025.
# One entry per game per system (no correlated samples).
# Prints AT 1.01 are kept (a first draft filtered ltp>1.01, which hid the exit prints of cruising favourites in (c) — the losing lays).
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,time,psycopg2,pandas as pd,numpy as np
from collections import defaultdict
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
def tick(p): return 0.01 if p<2 else 0.02 if p<3 else 0.05 if p<4 else 0.1 if p<6 else 0.2 if p<10 else 0.5 if p<20 else 1 if p<30 else 2 if p<50 else 5 if p<100 else 10
def pnl(side,p,q,won):
    # p = fill before the adverse tick; q = exit print (None -> settle). Same formulas as 315.
    if side=='B':
        p=p-tick(p)
        if p<=1.01: return None
        if q is None: r=10*(p-1) if won else -10.0
        else: q=q+tick(q); r=10*(p/q-1)
    else:
        p=p+tick(p); s=10/(p-1)
        if q is None: r=s if not won else -10.0
        else: q=max(1.01,q-tick(q)); r=s*(1-p/q)
    return r*0.98 if r>0 else r
# known answers: back 2.0 -> 1.98 win 9.604; lay 6.0 -> 6.2 (tick .2 at 6) stake 10/5.2, not won -> 1.884615; lay 6.0 green at 3.0 -> q 2.95:
# s*(1-6.2/2.95) = -2.118644 (loss); back 1.5 exit 1.3 -> fill 1.49, q 1.31: 10*(1.49/1.31-1)=1.374046 -> 1.346565
assert abs(pnl('B',2.0,None,True)-9.604)<1e-9 and abs(pnl('L',6.0,None,False)-10/5.2*0.98)<1e-9
assert abs(pnl('L',6.0,3.0,False)-(10/5.2)*(1-6.2/2.95))<1e-9 and abs(pnl('B',1.5,1.3,False)-10*(1.49/1.31-1)*0.98)<1e-9 and pnl('L',2.0,None,True)==-10.0
print("P&L unit checks: OK",flush=True)
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET statement_timeout='3000s'")
G=pd.read_sql("""SELECT m.event_id, f.fixture_id, f.season, f.league, f.hg, f.ag, f.ht_hg, f.ht_ag FROM af_price_map m
 JOIN af_fixtures f ON f.fixture_id=substr(m.understat_id,3)::bigint WHERE f.status='FT' AND f.hg IS NOT NULL AND f.ht_hg IS NOT NULL""",con)
print("games:",len(G),"| seasons:",G.season.value_counts().to_dict(),flush=True)
EV=pd.read_sql("""SELECT fixture_id, coalesce(minute,0) AS minute, is_home, detail FROM af_events WHERE fixture_id=ANY(%s) AND type='Goal'
 AND detail IN ('Normal Goal','Penalty','Own Goal')""",con,params=(list(map(int,G.fixture_id)),))
goals=defaultdict(list)
for r in EV.itertuples():
    side=('h' if r.is_home else 'a') if r.detail!='Own Goal' else ('a' if r.is_home else 'h')
    goals[r.fixture_id].append((int(r.minute),side))
for k in goals: goals[k].sort()
def score(gl,m): return (sum(1 for g,s in gl if g<=m and s=='h'), sum(1 for g,s in gl if g<=m and s=='a'))
def rp(arr,a,b):
    for mm in range(max(0,a),min(b,96)+1):
        if not np.isnan(arr[mm]): return mm
    return None
def favband(f): return '<1.5' if f<1.5 else '1.5-2' if f<2 else '2-3' if f<3 else '3+'
T=[]; SK=defaultdict(int); t0=time.time()
def add(sysn,g,fb,side,p,q,won,mode):
    r=pnl(side,p,q,won)
    if r is None: SK[sysn+' unfillable']+=1; return
    T.append(dict(system=sysn,fixture_id=g.fixture_id,season=int(g.season),league=g.league,fav=fb,px=p,pnl=r,won=bool(won),mode=mode))
for i in range(0,len(G),1500):
    sub=G.iloc[i:i+1500]
    P=pd.read_sql("SELECT event_id, minute, mkt, sel, ltp::float ltp FROM bf_hist_price WHERE event_id=ANY(%s) AND ((mkt='MO' AND sel IN ('HOME','DRAW','AWAY')) OR (mkt='OU25' AND sel='OVER')) AND minute BETWEEN 0 AND 95 AND ltp>=1.01 AND ltp<1000",con,params=(list(sub.event_id),))
    px={}
    for (eid,mkt,sel),gg in P.groupby(['event_id','mkt','sel'],sort=False):
        arr=np.full(97,np.nan); arr[gg.minute.values]=gg.ltp.values; px.setdefault(eid,{})[(mkt,sel)]=arr
    for g in sub.itertuples():
        b=px.get(g.event_id)
        if not b or any(k not in b for k in (('MO','HOME'),('MO','AWAY'),('MO','DRAW'))): continue
        H,A,Dr=b[('MO','HOME')],b[('MO','AWAY')],b[('MO','DRAW')]; O=b.get(('OU25','OVER'))
        if np.isnan(H[0]) or np.isnan(A[0]): continue
        fb=favband(min(H[0],A[0])); gl=goals.get(g.fixture_id,[]); hg,ag=int(g.hg),int(g.ag)
        # (a) LTD
        if not np.isnan(Dr[0]) and 5.6<=Dr[0]<=7.6:
            n1=rp(Dr,1,2); p=Dr[0] if n1 is None else max(Dr[0],Dr[n1])
            draw=hg==ag
            add('a LTD hold FT',g,fb,'L',p,None,draw,'FT')
            first=gl[0][0] if gl else None
            if first is None or first+2>95: add('a LTD exit goal+2',g,fb,'L',p,None,draw,'goal+2')
            else:
                e=rp(Dr,first+2,95)
                if e is None: SK['a LTD exit goal+2: no print to 95 -> settled']+=1
                add('a LTD exit goal+2',g,fb,'L',p,None if e is None else Dr[e],draw,'goal+2')
        # (b) HT 0-0, KO Over <= 1.80
        if O is not None and int(g.ht_hg)==0 and int(g.ht_ag)==0 and not np.isnan(O[0]) and O[0]<=1.80:
            d=rp(O,46,48)
            if d is None: SK['b no 46-48 print']+=1
            else:
                g2=next((m for m,s in gl if m>45),None)
                if g2 is not None and g2<=d: SK['b 2H goal before decision (winners)']+=1
                else:
                    n1=rp(O,d+1,d+2); p=O[d] if n1 is None else min(O[d],O[n1])
                    add('b HT0-0 back O2.5',g,fb,'B',p,None,hg+ag>2,'settle')
        # (c) early goal glitch
        favh=H[0]<=A[0]; F=H if favh else A; fs='h' if favh else 'a'
        if gl and gl[0][0]<20 and gl[0][1]==fs:
            g1=gl[0][0]; d=rp(F,g1+2,g1+4)
            if d is not None and F[d]<=1.30:
                if len(gl)>1 and gl[1][0]<=d+2: SK['c second goal before fill']+=1
                else:
                    n1=rp(F,d+1,d+2); p=F[d] if n1 is None else max(F[d],F[n1])
                    favwon=(hg>ag) if favh else (ag>hg)
                    add('c lay fav hold FT',g,fb,'L',p,None,favwon,'FT')
                    eq=None
                    for m,s in gl[1:]:
                        h,a=score(gl,m)
                        if h==a: eq=m; break
                    if eq is not None and eq<60: e=rp(F,eq+2,95); why='equaliser'
                    else: e=rp(F,60,95); why='60min'
                    if e is None: SK['c no exit print to 95 ('+why+') -> settled']+=1
                    add('c lay fav exit 60/eq',g,fb,'L',p,None if e is None else F[e],favwon,why)
        # (d) 1-1 after 70, draw <= 2.0
        for m in range(71,86):
            if score(gl,m)!=(1,1) or np.isnan(Dr[m]) or Dr[m]>2.0: continue
            n1=rp(Dr,m+1,m+2); p=Dr[m] if n1 is None else min(Dr[m],Dr[n1])
            add('d 1-1 70+ back draw',g,fb,'B',p,None,hg==ag,'FT'); break
    print(f"  {min(i+1500,len(G))}/{len(G)} games | trades {len(T)} | {int(time.time()-t0)}s",flush=True)
R=pd.DataFrame(T)
print("skips (counted, not hidden):",dict(SK))
def tstat(x): return x.mean()/(x.std(ddof=1)/len(x)**0.5) if len(x)>1 and x.std(ddof=1)>0 else 0.0
rows=[]
for dims in (['system'],['system','fav'],['system','league']):
    for k,gg in R.groupby(dims):
        k=k if isinstance(k,tuple) else (k,)
        a=gg[gg.season==2024].pnl; c=gg[gg.season==2025].pnl
        rows.append(dict(dim='+'.join(dims),line=' / '.join(map(str,k)),n=len(gg),games=gg.fixture_id.nunique(),per10=gg.pnl.mean(),t=tstat(gg.pnl),
             n1=len(a),h1=a.mean() if len(a) else np.nan,n2=len(c),h2=c.mean() if len(c) else np.nan,hit=gg.won.mean(),avg_px=gg.px.mean()))
S=pd.DataFrame(rows).round(3)
S['PASS']=(S.n>=300)&(S.n1>=150)&(S.n2>=150)&(S.t>=3.5)&(S.h1>0)&(S.h2>0)&(S.per10>=0.15)
print("\n== headline per system (per £10; h1 = 2024, h2 = 2025; hit = selection won)")
print(S[S.dim=='system'].to_string(index=False))
print("\n== by favourite band (n>=30)"); print(S[(S.dim=='system+fav')&(S.n>=30)].to_string(index=False))
print("\n== top 15 by t, all lines n>=30"); print(S[S.n>=30].sort_values('t',ascending=False).head(15).to_string(index=False))
W=S[S.PASS].sort_values('t',ascending=False)
print(f"\n== SURVIVORS: {len(W)}"); print(W.to_string(index=False) if len(W) else "none")
PY
