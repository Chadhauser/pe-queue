#!/bin/bash
set -o pipefail
# 466 (Finder 2026-11-03, queue item 0e): RELATED-MARKET ARBITRAGE INSIDE ONE FOOTBALL GAME on liq_sample (real touch, every market,
# ~1 snapshot per minute; all markets of one game share the same ts in a snapshot, so legs are synchronous).
# Pairs: DNB~MO, AH0~DNB, CS~OU25, CS~BTTS, OU15~OU25~OU35. For every game x snapshot an LP finds the stake mix (backs and lays at the
# touch, legs with < £2 at the touch excluded) that MAXIMISES THE GUARANTEED (worst-outcome) P&L per £1 at risk, after 2% commission
# charged per winning bet (>= Betfair's per-market commission, i.e. conservative). Outcome space = final scores h,a in 0..8,
# restricted to h>=sh, a>=sa where (sh,sa) = goal_timeline score 60 s BEFORE the snapshot (lagged -> superset of the truth; a VAR-
# disallowed goal could make it wrong, that is said). Games not matched to the timeline use the full grid (conservative).
# Two price versions: TOUCH (spec) and ADV (one tick adverse on every leg; honesty rule). An arb = margin > 0. "Cross" = the pair
# margin beats the best single-market margin in the same snapshot (else it is an intra-market overround hole, reported apart).
# Persistence: consecutive snapshots with margin > 0. EXECUTION CHECK (honest P&L): weights found at snapshot k are executed at
# snapshot k+1's prices (one tick adverse; legs gone or < £2 are simply not filled) and scored at the WORST outcome -> P&L per £10.
# One trade per game x pair x run. Halves = game date before/after the median date. Capacity = £ at risk the thinnest leg allows.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,unicodedata,time,difflib,psycopg2,pandas as pd,numpy as np
from multiprocessing import Pool
from scipy.optimize import linprog
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
def tick(p): return 0.01 if p<2 else 0.02 if p<3 else 0.05 if p<4 else 0.1 if p<6 else 0.2 if p<10 else 0.5 if p<20 else 1 if p<30 else 2 if p<50 else 5 if p<100 else 10
def tdown(p): return max(1.01,p-tick(p-1e-9))
def tup(p): return min(1000.0,p+tick(p))
G=[(h,a) for h in range(9) for a in range(9)]
def res(mkt,sel,h,a,hs):
    # 1 sel wins / 0 void / -1 loses ; hs = 'h'|'a' side for DNB/AH team selections
    t=h+a
    if mkt=='MO': return 1 if (sel=='HOME' and h>a) or (sel=='AWAY' and a>h) or (sel=='DRAW' and h==a) else -1
    if mkt in ('DNB','AH'):
        if h==a: return 0
        return 1 if (h>a)==(hs=='h') else -1
    if mkt=='BTTS': return 1 if (h>0 and a>0)==(sel=='YES') else -1
    if mkt in ('OU15','OU25','OU35'):
        line={'OU15':1.5,'OU25':2.5,'OU35':3.5}[mkt]; return 1 if (t>line)==sel.startswith('OVER') else -1
    if mkt=='CS':
        if sel=='ANYOTHERHOMEWIN': return 1 if h>a and max(h,a)>=4 else -1
        if sel=='ANYOTHERAWAYWIN': return 1 if a>h and max(h,a)>=4 else -1
        if sel=='ANYOTHERDRAW': return 1 if h==a and h>=4 else -1
        x,y=sel.split('-'); return 1 if (h,a)==(int(x),int(y)) else -1
    raise ValueError(mkt)
# unit checks of settlement + payoff
assert res('CS','ANYOTHERHOMEWIN',4,1,None)==1 and res('CS','ANYOTHERHOMEWIN',3,1,None)==-1 and res('CS','2-1',2,1,None)==1
assert res('DNB','X',1,1,'h')==0 and res('AH','X',0,2,'a')==1 and res('OU25','UNDER',1,1,None)==1 and res('OU35','OVER 3.5 GOALS',2,2,None)==1
assert res('BTTS','NO',3,0,None)==1 and res('MO','DRAW',2,2,None)==1
def legpay(side,px,r):
    # per £1 AT RISK: back stake 1 -> win 0.98(px-1); lay liability 1 (stake 1/(px-1)) -> sel loses: +0.98/(px-1), sel wins: -1
    if r==0: return 0.0
    if side=='B': return 0.98*(px-1) if r==1 else -1.0
    return -1.0 if r==1 else 0.98/(px-1)
assert abs(legpay('L',3.0,-1)-0.49)<1e-12 and legpay('B',2.0,1)==0.98
PAIRS={'DNB~MO':('DNB','MO'),'AH0~DNB':('AH','DNB'),'CS~OU25':('CS','OU25'),'CS~BTTS':('CS','BTTS'),'OU15~OU25~OU35':('OU15','OU25','OU35')}
RC={}
def payvec(l,outs):
    k=(l[0],l[1],l[2])
    if k not in RC: RC[k]={(h,a):res(l[0],l[1],h,a,l[2]) for (h,a) in G}
    rv=np.array([RC[k][o] for o in outs]); px=l[4]
    if l[3]=='B': return np.where(rv==1,0.98*(px-1),np.where(rv==0,0.0,-1.0))
    return np.where(rv==1,-1.0,np.where(rv==0,0.0,0.98/(px-1)))
def solve(legs,outs):
    # legs: list of (mkt,sel,hs,side,px,size_cap) ; returns (margin per £1, weights, capacity £)
    if len(legs)<2 or not outs: return (None,None,None)
    P=np.column_stack([payvec(l,outs) for l in legs])
    n=len(legs); c=np.zeros(n+1); c[-1]=-1
    A=np.hstack([-P,np.ones((len(outs),1))]); b=np.zeros(len(outs))
    Aeq=np.zeros((1,n+1)); Aeq[0,:n]=1
    r=linprog(c,A_ub=A,b_ub=b,A_eq=Aeq,b_eq=[1],bounds=[(0,None)]*n+[(-1,1)],method='highs')
    if r.status!=0: return (None,None,None)
    x=r.x[:n]; m=r.x[-1]; used=x>1e-6
    cap=min(legs[j][5]/x[j] for j in range(n) if used[j]) if used.any() else 0
    return (m,x,cap)
def evalw(legs_next,w_legs,w,outs):
    # weights w on legs w_legs (key mkt,sel,side); fill only legs present at k+1 (adverse tick, >=£2); worst-outcome P&L per £1 placed
    have={(l[0],l[1],l[3]):l for l in legs_next}; tot=0; pay=np.zeros(len(outs))
    for l,wj in zip(w_legs,w):
        if wj<=1e-6: continue
        q=have.get((l[0],l[1],l[3]))
        if q is None: continue
        tot+=wj; pay+=wj*payvec(q,outs)
    return float(pay.min()/sum(w)) if tot>0 else 0.0
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|club|de|the|athletic|atletico|sporting|real|cd|ud|sd|rcd|calcio|women|w|u21|u23|ii|b|if|bk|ff|aif|is|kv|sk|fsv|sv)\b"," ",s)
    return set(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def sim(a,b): A,B=norm(a),norm(b); return len(A&B)/max(1,len(A|B))
def ssim(a,b): return difflib.SequenceMatcher(None,str(a).lower(),str(b).lower()).ratio()
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET statement_timeout='2400s'")
t0=time.time()
L=pd.read_sql("""SELECT ts, event_name, competition, mkt, sel, minute, back_px::float bp, back_sz::float bs, lay_px::float lp, lay_sz::float ls,
  total_matched::float tm FROM liq_sample WHERE event_name LIKE '%% v %%' AND back_px>1 AND lay_px>1
  AND (mkt IN ('MO','DNB','CS','BTTS','OU15','OU25','OU35') OR (mkt='AH' AND sel ~ ' [+-]?0$'))""",con)
T=pd.read_sql("SELECT fixture_id, captured_at, home_team, away_team, score_home, score_away FROM goal_timeline WHERE captured_at>=%s",con,params=(L.ts.min()-pd.Timedelta(hours=3),))
print(f"liq_sample rows {len(L):,} | games {L.event_name.nunique():,} | {L.ts.min():%d %b %H:%M} -> {L.ts.max():%d %b %H:%M} UTC | timeline fixtures {T.fixture_id.nunique():,} | load {time.time()-t0:.0f}s",flush=True)
fx=T.groupby('fixture_id').agg(home=('home_team','first'),away=('away_team','first')).reset_index()
def match_fixture(ev):
    h,a=ev.split(' v ',1); best=None; bs=0; b2=0
    for f in fx.itertuples():
        sc=sim(h,f.home)+sim(a,f.away)
        if sc>bs: b2=bs; bs=sc; best=f.fixture_id
        elif sc>b2: b2=sc
    return best if bs>=1.0 and bs-b2>=0.3 else None
def work(item):
    ev,g=item; out=[]; skips={'no timeline':0}
    home,away=ev.split(' v ',1); fid=match_fixture(ev)
    tl=T[T.fixture_id==fid].sort_values('captured_at') if fid is not None else None
    if tl is None or not len(tl): skips['no timeline']=1
    dup=g.duplicated(['ts','mkt','sel'],keep=False)
    bad=set(g[dup].mkt)            # recorder defect seen in smoke test: MO home runner labelled AWAY (two AWAY rows) -> labels unreliable
    if bad: skips['dup labels']=1; skips['dup_mkts']=sorted(bad); g=g[~g.mkt.isin(bad)]
    # DNB/AH team -> home/away: by price consistency with MO (DNB home fair = (pH+pA)/pH at mids); fallback = name similarity
    teams=list(g[g.mkt=='DNB'].sel.unique()); mapping={}
    if len(teams)==2 and 'MO' in set(g.mkt):
        mo=g[(g.mkt=='MO')&(g.lp<1000)].assign(mid=lambda d:(d.bp+d.lp)/2).pivot_table(index='ts',columns='sel',values='mid',aggfunc='first')
        dn=g[(g.mkt=='DNB')&(g.lp<1000)].assign(mid=lambda d:(d.bp+d.lp)/2).pivot_table(index='ts',columns='sel',values='mid',aggfunc='first')
        j=mo.join(dn,how='inner')
        if len(j) and {'HOME','AWAY'}<=set(j.columns) and teams[0] in j.columns:
            fh=(1/j.HOME)/((1/j.HOME)+(1/j.AWAY)); e1=(1/j[teams[0]]-fh).abs().median(); e2=(1/j[teams[0]]-(1-fh)).abs().median()
            if pd.notna(e1) and pd.notna(e2): mapping={teams[0]:'h' if e1<=e2 else 'a',teams[1]:'a' if e1<=e2 else 'h'}
    if teams and not mapping: skips['dnb map by name']=1
    def side_of(name): return mapping.get(name) or ('h' if ssim(name,home)>=ssim(name,away) else 'a')
    snaps=sorted(g.ts.unique()); byts={t:d for t,d in g.groupby('ts')}
    def legs_at(t,mkts,adv):
        d=byts[t]; d=d[d.mkt.isin(mkts)]; legs=[]
        for r in d.itertuples():
            hs=side_of(r.sel.rsplit(' ',1)[0] if r.mkt=='AH' else r.sel) if r.mkt in ('DNB','AH') else None
            sel=r.sel if r.mkt!='AH' else 'AH0'
            bp=tdown(r.bp) if adv else r.bp; lp=tup(r.lp) if adv else r.lp
            if r.bs>=2 and bp>1.01: legs.append((r.mkt,r.sel,hs,'B',bp,r.bs))
            if r.ls>=2 and lp<1000: legs.append((r.mkt,r.sel,hs,'L',lp,r.ls*(lp-1)))
        return legs
    def outs_at(t):
        if tl is None or not len(tl): return G
        s=tl[tl.captured_at<=t-pd.Timedelta(seconds=60)]
        sh,sa=(int(s.iloc[-1].score_home),int(s.iloc[-1].score_away)) if len(s) else (0,0)
        return [(h,a) for (h,a) in G if h>=sh and a>=sa]
    for i,t in enumerate(snaps):
        d=byts[t]; present=set(d.mkt); outs=outs_at(t)
        mo_tm=d[d.mkt=='MO'].tm.max() if 'MO' in present else np.nan; minute=int(d.minute.max() or 0)
        for pname,mk in PAIRS.items():
            if not all(m in present for m in mk): continue
            m0=None
            for adv in (0,1):
                legs=legs_at(t,mk,adv)
                if adv==1 and m0 is not None and m0<=1e-9: m,x,cap=m0,None,None   # adverse prices are worse: no touch arb -> no ADV arb (m kept as upper bound)
                else: m,x,cap=solve(legs,outs)
                if m is None: continue
                if adv==0: m0=m
                rec=dict(ev=ev,comp=d.competition.iloc[0],pair=pname,adv=adv,ts=t,i=i,minute=minute,mo_tm=mo_tm,m=m,cap=cap,single=np.nan,exec=np.nan,timeline=fid is not None)
                if m>1e-9 and x is not None:
                    rec['single']=max([solve([l for l in legs if l[0]==mm],outs)[0] or -1 for mm in mk])
                    if adv==1 and i+1<len(snaps):
                        rec['exec']=evalw(legs_at(snaps[i+1],mk,1),legs,x,outs_at(snaps[i+1]))
                out.append(rec)
    return out,skips
items=list(L.groupby('event_name'))
import os
if os.environ.get('N_GAMES'): items=items[:int(os.environ['N_GAMES'])]
with Pool(4) as pool: res_=pool.map(work,items,chunksize=4)
R=pd.DataFrame([r for o,_ in res_ for r in o]); nos=sum(s['no timeline'] for _,s in res_)
dm=pd.Series([m for _,s in res_ for m in s.get('dup_mkts',[])]).value_counts().to_dict()
print(f"recorder label defect (a selection name repeated inside one snapshot -> that market dropped for the game): {sum(s.get('dup labels',0) for _,s in res_)} games, markets {dm}"
      f" | DNB/AH sides mapped by name only: {sum(s.get('dnb map by name',0) for _,s in res_)} games")
print(f"snapshots x pairs x versions: {len(R):,} | games {R.ev.nunique():,} (no timeline match -> full outcome grid: {nos}) | {time.time()-t0:.0f}s",flush=True)
R['day']=pd.to_datetime(R.ts).dt.tz_convert('Europe/London').dt.date
med=sorted(R.day.unique())[len(R.day.unique())//2]; R['half']=np.where(R.day<med,'h1','h2')
R['tier']=pd.cut(R.mo_tm.fillna(0),[-1,10000,100000,1e12],labels=['MO<£10k','£10k-100k','>£100k'])
R['phase']=np.where(R.minute<=0,'pre/KO','in-play')
R['arb']=R.m>1e-9; R['cross']=R.arb&(R.m>R.single+1e-9)
print(f"halves: h1 < {med} <= h2\n\n== FREQUENCY of a positive guaranteed margin (per 1,000 snapshots ~ minutes), TOUCH vs ADV (1 tick adverse)")
f=R.groupby(['pair','adv']).agg(snaps=('m','size'),games=('ev','nunique'),arb_per_1000=('arb',lambda s:1000*s.mean()),cross_per_1000=('cross',lambda s:1000*s.mean()),
  margin_p99=('m',lambda s:100*s.quantile(.99)),margin_max=('m',lambda s:100*s.max())).round(2)
print(f.to_string())
print("\n== by tier x phase (ADV, cross-market arbs per 1,000)")
print(R[R.adv==1].groupby(['pair','tier','phase'],observed=True).agg(snaps=('m','size'),cross_per_1000=('cross',lambda s:1000*s.mean())).round(2).to_string())
A=R[R.cross].sort_values(['ev','pair','adv','i']).copy()
A['run']=(A.groupby(['ev','pair','adv']).i.diff()!=1).cumsum()
runs=A.groupby('run').agg(ev=('ev','first'),comp=('comp','first'),pair=('pair','first'),adv=('adv','first'),half=('half','first'),tier=('tier','first'),
  phase=('phase','first'),minute=('minute','first'),snaps=('i','size'),secs=('ts',lambda s:(s.max()-s.min()).total_seconds()),m0=('m','first'),
  cap0=('cap','first'),exec=('exec','first')).reset_index(drop=True)
print("\n== CROSS-MARKET ARB RUNS (persistence) — size of margin (% of £ at risk), snapshots, seconds")
if len(runs):
    print(runs.groupby(['pair','adv']).agg(runs=('ev','size'),games=('ev','nunique'),med_margin=('m0',lambda s:100*s.median()),p90_margin=('m0',lambda s:100*s.quantile(.9)),
      persist_ge60s=('secs',lambda s:(s>=60).sum()),med_cap=('cap0','median')).round(2).to_string())
    big=runs[(runs.m0>=0.01)&(runs.secs>=60)&(runs.cap0>=5)]
    print(f"\nruns with margin>=1%, persisting >=60 s and capacity >= £5: TOUCH {int((big.adv==0).sum())}, ADV {int((big.adv==1).sum())}")
    print("\n== largest 15 ADV runs by margin"); print(runs[runs.adv==1].sort_values('m0',ascending=False).head(15).assign(m0=lambda d:(100*d.m0).round(2),exec=lambda d:(10*d.exec).round(2),cap0=lambda d:d.cap0.round(1)).to_string(index=False))
print("\n== HONEST EXECUTION (ADV): weights from the snapshot that showed the arb, filled at the NEXT snapshot (1 tick adverse, missing legs unfilled),")
print("   scored at the worst outcome; one trade per run; per £10 at risk")
X=runs[(runs.adv==1)&runs.exec.notna()].copy() if len(runs) else pd.DataFrame()
S=[]
if len(X):
    X['p10']=10*X.exec
    for keys,grp in [(('ALL',),X)]+[((p,),g) for p,g in X.groupby('pair')]+[((p,ph),g) for (p,ph),g in X.groupby(['pair','phase'])]+[((p,'margin>=1%'),g) for p,g in X[X.m0>=0.01].groupby('pair')]:
        n=len(grp); mu=grp.p10.mean(); sd=grp.p10.std(ddof=1) if n>1 else np.nan; t=mu/(sd/np.sqrt(n)) if n>1 and sd>0 else np.nan
        h1=grp[grp.half=='h1'].p10.mean(); h2=grp[grp.half=='h2'].p10.mean(); n1=(grp.half=='h1').sum(); n2=(grp.half=='h2').sum()
        ok=n>=300 and n1>=150 and n2>=150 and t>=3.5 and mu>=0.15 and h1>0 and h2>0
        S.append(dict(line=' '.join(keys),n=n,games=grp.ev.nunique(),per10=round(mu,3),t=round(t,2),h1=round(h1,3),n1=n1,h2=round(h2,3),n2=n2,pos=f"{(grp.p10>0).mean():.0%}",PASS='PASS' if ok else ''))
    S=pd.DataFrame(S).sort_values('t',ascending=False); print(S.to_string(index=False))
print("\n== SURVIVORS (n>=300, >=150 per half, t>=3.5, both halves >0, mean >= +£0.15/£10; executed at next snapshot, 1 tick adverse, worst outcome)")
sv=S[S.PASS=='PASS'] if len(S) else []
print(sv.to_string(index=False) if len(sv) else "none")
print(f"done {time.time()-t0:.0f}s")
PY
