#!/bin/bash
# 011: state scan over ALL markets incl OU15/OU35/BTTS/FH05/FH15, coarser minute bands (15 min) and score (level/+1/+2/-1/-2) so cells reach n>=500: STAGE 2a — exhaustive state scan, data leads. market x selection x minute band x score x pre-match band x league tier.
# Market implied prob (fresh LTP, normalised) vs actual outcome rate. Back/lay expected profit per £100 at the fresh LTP,
# 2pct spread, 2pct comm, held to full time. Train 2024/25, test 2025/26 (the tape's two seasons). STAGE 3 validation built in.
# Gate: needs the extra markets loaded by 010. Exits 75 (WAITING) until they are in bf_hist_price.
N=$(python3 - <<'PY'
import sys, psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
c=psycopg2.connect(DB,sslmode='require').cursor(); c.execute("SELECT count(DISTINCT event_id) FROM bf_hist_price WHERE mkt IN ('OU15','OU35','BTTS','FH05','FH15')"); print(c.fetchone()[0])
PY
)
echo "events with extra markets: $N"
if [ "${N:-0}" -lt 500 ]; then echo "WAITING: extra markets not loaded yet (010 pending)"; exit 75; fi
cd /root/pe-scan && cat > state_scan_v2.py <<'PYFILE'
import re, sys, math, datetime, collections, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
SPREAD=0.02; COMM=0.02; MINS=list(range(5,86,5)); BAND=lambda t: 5*((t-5)//15)+5
def norm(s): return re.sub(r'[^a-z]','',(s or '').lower().split(' ')[0])
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor()
cur.execute("SELECT match_date, competition, home_team, away_team, goal_times, mo_home_back, mo_draw_back, mo_away_back, ft_home, ft_away FROM fts_advanced_results WHERE match_date>='2024-08-01'")
G={}
TOP={'English Premier League','Spanish Primera Division','Italian Serie A','German Bundesliga','French Ligue 1'}
for d,lg,h,a,gt,ph,pd_,pa,fh,fa in cur.fetchall():
    d=datetime.date.fromisoformat(str(d)[:10]); goals=[]
    for t in (gt or '').split('|'):
        mm=re.match(r"\s*(\d+)(?:\+(\d+))?\((H|A)\)",t)
        if mm: goals.append((int(mm.group(1))+int(mm.group(2) or 0),mm.group(3)))
    try: ph=float(ph)
    except: ph=None
    fav='home_fav_short' if ph and ph<1.6 else 'home_fav' if ph and ph<2.2 else 'even' if ph and ph<3.0 else 'away_fav' if ph else 'na'
    G[(d,norm(h),norm(a))]=(sorted(goals),int(fh),int(fa),'tier1' if lg in TOP else 'tier2',fav)
print("goal/price records",len(G),flush=True)
agg=collections.defaultdict(lambda:[0,0.0,0.0,0.0,0.0])  # key -> [n, sum_implied, wins, sum_back_pnl, sum_lay_pnl]
scur=con.cursor(name='tape'); scur.itersize=50000
scur.execute("SELECT event_id,hw,aw,m,minute,mkt,sel,ltp FROM bf_hist_price WHERE ht_offset IS NOT NULL ORDER BY event_id,m")
n_ev=0; n_seen=0
def process(rows):
    global n_ev,n_seen
    n_seen+=1
    hw,aw=norm(rows[0][1]),norm(rows[0][2]); d=rows[0][3].date()
    rec=G.get((d,hw,aw)) or G.get((d-datetime.timedelta(days=1),hw,aw)) or G.get((d+datetime.timedelta(days=1),hw,aw))
    if n_seen==300:
        print(f"SELF-CHECK after 300 events: {n_ev} joined",flush=True)
        if n_ev<30: sys.exit("ABORT join")
    if not rec: return
    n_ev+=1
    goals,fh,fa,tier,fav=rec
    season='2024/25' if d<datetime.date(2025,7,1) else '2025/26'
    px=collections.defaultdict(dict)
    for _,_,_,m,minute,mkt,sel,ltp in rows:
        if ltp and ltp>1.0: px[(mkt,sel)][minute]=float(ltp)
    hth=sum(1 for g,x in goals if g<=45 and x=='H'); hta=sum(1 for g,x in goals if g<=45 and x=='A')
    resm={'MO':{'HOME':fh>fa,'DRAW':fh==fa,'AWAY':fh<fa},'OU25':{'OVER':fh+fa>2.5,'UNDER':fh+fa<2.5},'OU15':{'OVER':fh+fa>1.5,'UNDER':fh+fa<1.5},'OU35':{'OVER':fh+fa>3.5,'UNDER':fh+fa<3.5},'BTTS':{'YES':fh>0 and fa>0,'NO':not(fh>0 and fa>0)},'FH05':{'OVER':hth+hta>0.5,'UNDER':hth+hta<0.5},'FH15':{'OVER':hth+hta>1.5,'UNDER':hth+hta<1.5}}
    for t in MINS:
        if any(0<=t-g<3 for g,_ in goals): continue
        sh=sum(1 for g,s in goals if g<=t and s=='H'); sa=sum(1 for g,s in goals if g<=t and s=='A')
        diff=sh-sa; score=('level' if diff==0 else f"h+{min(diff,2)}" if diff>0 else f"a+{min(-diff,2)}")+f"/{min(sh+sa,3)}g"
        for mkt,sels in (('MO',('HOME','DRAW','AWAY')),('OU25',('OVER','UNDER')),('OU15',('OVER','UNDER')),('OU35',('OVER','UNDER')),('BTTS',('YES','NO')),('FH05',('OVER','UNDER')),('FH15',('OVER','UNDER'))):
            if mkt.startswith('FH') and t>45: continue
            cur_px={s:px.get((mkt,s),{}).get(t) for s in sels}
            if any(v is None for v in cur_px.values()): continue
            inv={s:1/v for s,v in cur_px.items()}; tot=sum(inv.values())
            for s in sels:
                p=cur_px[s]; won=resm[mkt][s]
                back=((p*(1-SPREAD)-1)*(1-COMM) if won else -1.0)
                lay=(-(p*(1+SPREAD)-1) if won else (1-COMM))
                a=agg[(season,mkt,s,BAND(t),score,fav,tier)]
                a[0]+=1; a[1]+=inv[s]/tot; a[2]+=int(won); a[3]+=back; a[4]+=lay
buf=[]; last=None
for r in scur:
    if last is not None and r[0]!=last:
        process(buf); buf=[]
        if n_ev%2000==0 and n_ev: print("events",n_ev,flush=True)
    buf.append(r); last=r[0]
if buf: process(buf)
print("events joined",n_ev,flush=True)
rows=[(k[0],k[1],k[2],k[3],k[4],k[5],k[6],v[0],v[1]/v[0],v[2]/v[0],100*v[3]/v[0],100*v[4]/v[0]) for k,v in agg.items()]
D=pd.DataFrame(rows,columns=['season','mkt','sel','minute','score','prematch','tier','n','implied','actual','back_per100','lay_per100'])
D.to_csv('/root/pe-scan/state_scan_v2_cells.csv',index=False)
con2=psycopg2.connect(DB,sslmode='require'); con2.autocommit=True; cur2=con2.cursor()
cur2.execute("DROP TABLE IF EXISTS state_scan_v2"); cur2.execute("CREATE TABLE state_scan_v2 (season TEXT, mkt TEXT, sel TEXT, minute INT, score TEXT, prematch TEXT, tier TEXT, n INT, implied NUMERIC, actual NUMERIC, back_per100 NUMERIC, lay_per100 NUMERIC)")
import psycopg2.extras; psycopg2.extras.execute_values(cur2,"INSERT INTO state_scan_v2 VALUES %s",[tuple(r) for r in rows],page_size=5000)
# STAGE 3: train 2024/25, test 2025/26, n>=500 in train, same sign both, best of back/lay
tr=D[D.season=='2024/25'].set_index(['mkt','sel','minute','score','prematch','tier']); te=D[D.season=='2025/26'].set_index(['mkt','sel','minute','score','prematch','tier'])
J=tr.join(te,lsuffix='_tr',rsuffix='_te',how='inner')
J=J[(J.n_tr>=500)&(J.n_te>=150)]
out=[]
for idx,r in J.iterrows():
    for side,c in (('BACK','back_per100'),('LAY','lay_per100')):
        a,b=r[c+'_tr'],r[c+'_te']
        if a>2 and b>2: out.append((*idx,side,int(r.n_tr),round(a,2),int(r.n_te),round(b,2),round(r.implied_tr,3),round(r.actual_tr,3),round(r.actual_te,3)))
S=pd.DataFrame(out,columns=['mkt','sel','minute','score','prematch','tier','side','n_train','per100_train','n_test','per100_test','implied_tr','actual_tr','actual_te']).sort_values('per100_test',ascending=False)
pd.set_option('display.width',250)
print(f"\nSTATES tested (n>=500 train): {len(J)}  x 2 sides = {2*len(J)} ; SURVIVORS positive both seasons (>2 per 100): {len(S)} ; chance expectation ~{int(2*len(J)*0.25*0.4)}")
print("\nSURVIVING STATES — VERIFIED = survived 2025/26 after being found on 2024/25 (held to FT, LTP, 2pct spread, 2pct comm):")
print(S.head(60).to_string(index=False))
S.to_csv('/root/pe-scan/state_scan_v2_survivors.csv',index=False)
print("\nBIGGEST GAPS implied vs actual in TRAIN regardless of survival (top 25, n>=500):")
tr2=D[(D.season=='2024/25')&(D.n>=500)].copy(); tr2['gap']=tr2.actual-tr2.implied
print(tr2.reindex(tr2.gap.abs().sort_values(ascending=False).index).head(25)[['mkt','sel','minute','score','prematch','tier','n','implied','actual','back_per100','lay_per100']].round(3).to_string(index=False))
PYFILE
python3 state_scan_v2.py
