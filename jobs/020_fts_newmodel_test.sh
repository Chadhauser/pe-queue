#!/bin/bash
# 020: FTS "New Model" (10 Oct 2026) — load and test. Waits (exit 75) until Peter has scp'd the file to /root/fts/fts_newmodel.csv.gz.
# TEST A (their history, 47,979 matches): their fair odds vs the 7am Betfair price — log-loss and ROI by value band, by season.
#   CAVEAT printed with the result: the model was generated BACKWARDS over these fixtures, so history may be in-sample; forward
#   daily sheets are the honest test.
# TEST B (our minute tape, strict: fresh prices, 2pct spread, 2pct comm, train <Jul 2025 / test >=Jul 2025):
#   B1 "Home Gains": back home at KO price, exit 3 min after first home goal (fresh price) else settle at FT; by their Supremacy
#      and "Home scores first" deciles and Tier.
#   B2 "Over 1.5 drip": back O1.5 at 20/27/35 if still 0-0, exit 3 min after a goal else settle; by Goals rank / "0-0 at 20' -> goal" deciles.
#      Needs the OU15 market from job 010 — if not loaded yet, B2 uses O2.5 as a proxy and says so.
F=/root/fts/fts_newmodel.csv.gz
[ -f "$F" ] || { echo "WAITING: $F not on server yet (scp it from Downloads)"; exit 75; }
cd /root/pe-scan && cat > fts_newmodel_test.py <<'PYFILE'
import gzip, csv, re, sys, math, datetime, collections, psycopg2, psycopg2.extras, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
SPREAD=0.02; COMM=0.02
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; cur=con.cursor()
# ---- load ----
COLS={0:'match_dt',1:'league',2:'home',3:'away',4:'xg_h',5:'xg_a',6:'xg_tot',7:'supremacy',8:'fh_xg_h',9:'fh_xg_a',10:'fh_xg_tot',11:'goals_rank_lg',12:'goals_rank_all',
 13:'fh_rank_lg',14:'fh_rank_all',15:'mismatch_rank',16:'fair_h',17:'fair_d',18:'fair_a',19:'fair_o15',20:'fair_o25',21:'fair_o35',22:'fair_o45',23:'fair_btts',24:'fair_fh05',25:'fair_fh15',
 26:'wm_h1',27:'wm_h2',28:'wm_a1',29:'wm_a2',30:'p_00at25_1hgoal',31:'p_goalby10_2nd',32:'p_00at20_goal',33:'p_home_first',34:'p_goal_after70',35:'p_goal_after80',36:'tier',37:'ab_agree',38:'games',
 39:'mo_vol',40:'mo_h_back',42:'mo_h_lay',44:'mo_a_back',46:'mo_a_lay',48:'mo_d_back',50:'mo_d_lay',52:'o25_vol',53:'u25_back',55:'u25_lay',57:'o25_back',59:'o25_lay',
 61:'o15_vol',62:'u15_back',64:'u15_lay',66:'o15_back',68:'o15_lay',70:'o35_vol',71:'u35_back',73:'u35_lay',75:'o35_back',77:'o35_lay',79:'o45_vol',80:'u45_back',82:'u45_lay',84:'o45_back',86:'o45_lay',
 88:'btts_vol',89:'btts_y_back',91:'btts_y_lay',93:'btts_n_back',95:'btts_n_lay',97:'fh05_vol',98:'fhu05_back',100:'fhu05_lay',102:'fho05_back',104:'fho05_lay',106:'fh15_vol',107:'fhu15_back',109:'fhu15_lay',111:'fho15_back',113:'fho15_lay',
 115:'ht_score',116:'ft_score',117:'ht1x2',118:'ft1x2',119:'goal_times',120:'ht_h',121:'ht_a',122:'ht_goals',123:'ft_h',124:'ft_a',125:'ft_goals'}
cur.execute("DROP TABLE IF EXISTS fts_newmodel")
cur.execute("CREATE TABLE fts_newmodel ("+",".join(f"{v} TEXT" for v in COLS.values())+")")
rows=[]; n=0
with gzip.open('/root/fts/fts_newmodel.csv.gz','rt') as f:
    r=csv.reader(f)
    for i,row in enumerate(r):
        if i<4: continue
        if not row or not row[0]: continue
        rows.append(tuple((row[k] if k<len(row) else None) or None for k in COLS)); n+=1
        if len(rows)>=5000: psycopg2.extras.execute_values(cur,"INSERT INTO fts_newmodel VALUES %s",rows); rows=[]
if rows: psycopg2.extras.execute_values(cur,"INSERT INTO fts_newmodel VALUES %s",rows)
cur.execute("SELECT count(*), min(match_dt), max(match_dt), count(DISTINCT league) FROM fts_newmodel"); print("fts_newmodel loaded:",cur.fetchone(),flush=True)
D=pd.read_sql("SELECT * FROM fts_newmodel",con)
for c in D.columns:
    if c not in ('match_dt','league','home','away','tier','ab_agree','ht_score','ft_score','ht1x2','ft1x2','goal_times'): D[c]=pd.to_numeric(D[c],errors='coerce')
D['date']=pd.to_datetime(D.match_dt,errors='coerce').dt.date
D['season']=np.where(pd.to_datetime(D.match_dt,errors='coerce')<pd.Timestamp('2025-07-01'),'to_2024/25','2025/26')
D=D[D.ft_h.notna()]
print("rows with FT result",len(D),"| tier counts",D.tier.value_counts().to_dict())
pd.set_option('display.width',250)
# ---- TEST A: their fair odds vs the market ----
print("\n=== TEST A: FTS New Model fair odds vs 7am Betfair back price (history; CAVEAT: model generated backwards over these fixtures -> may be in-sample) ===")
def ll(p,y): p=np.clip(p,1e-4,1-1e-4); return -(y*np.log(p)+(1-y)*np.log(1-p))
tests=[('home win','fair_h','mo_h_back',D.ft_h>D.ft_a),('draw','fair_d','mo_d_back',D.ft_h==D.ft_a),('away win','fair_a','mo_a_back',D.ft_h<D.ft_a),
       ('over 1.5','fair_o15','o15_back',D.ft_goals>1.5),('over 2.5','fair_o25','o25_back',D.ft_goals>2.5),('over 3.5','fair_o35','o35_back',D.ft_goals>3.5),
       ('btts','fair_btts','btts_y_back',(D.ft_h>0)&(D.ft_a>0)),('fh over 0.5','fair_fh05','fho05_back',D.ht_goals>0.5),('fh over 1.5','fair_fh15','fho15_back',D.ht_goals>1.5)]
out=[]
for name,fc,mc,y in tests:
    m=D[(D[fc]>1)&(D[mc]>1)&(D.tier!='Provisional')]; yy=y.loc[m.index].astype(int)
    pm=1/m[mc]; pf=1/m[fc]
    # normalise market prob roughly by removing a 2pct overround share
    for s in ('to_2024/25','2025/26'):
        k=m.season==s
        if k.sum()<200: continue
        # value bet: back when fair prob > market prob by 5+ pts; ROI at back price after comm
        v=(pf[k]-pm[k])>=0.05
        win=yy[k][v]; px=m[mc][k][v]
        roi=((win*(px-1)*(1-COMM))-(1-win)).mean()*100 if v.sum() else np.nan
        out.append((name,s,int(k.sum()),round(ll(pm[k],yy[k]).mean(),4),round(ll(pf[k],yy[k]).mean(),4),int(v.sum()),round(roi,1) if v.sum() else None))
print(pd.DataFrame(out,columns=['market','season','n','logloss_market','logloss_fts','value_bets(5pt+)','value_roi_pct']).to_string(index=False))
print("Reading: logloss_fts < logloss_market = their odds beat the market. value_roi_pct = backing their 5pt+ 'value' at the 7am price after 2pct comm.")
# ---- TEST B: on our tape ----
def norm(s): return re.sub(r'[^a-z]','',(s or '').lower().split(' ')[0])
M={}
for _,r in D.iterrows():
    gl=[]
    for t in str(r.goal_times or '').split(','):
        mm=re.match(r"\s*(\d+)(?:\+(\d+))?\((H|A)\)",t)
        if mm: gl.append((int(mm.group(1))+int(mm.group(2) or 0),mm.group(3)))
    M[(r.date,norm(r.home),norm(r.away))]=(sorted(gl),r)
cur.execute("SELECT count(*) FROM bf_hist_price WHERE mkt='OU15'"); has15=cur.fetchone()[0]>0
print("\n=== TEST B on the Betfair minute tape (fresh prices only, 2pct spread, 2pct comm). OU15 loaded:",has15,"===")
scur=con.cursor(name='tape'); scur.itersize=50000
scur.execute("SELECT event_id,hw,aw,m,minute,mkt,sel,ltp FROM bf_hist_price WHERE ht_offset IS NOT NULL AND mkt IN ('MO','OU25','OU15') ORDER BY event_id,m")
B1=[]; B2=[]; n_ev=0; n_seen=0
def px_at(px,mkt,sel,t,tol=3):
    d=px.get((mkt,sel),{})
    for k in range(t,t-tol-1,-1):
        if k in d: return d[k]
    return None
def settle_pnl(side,entry,won):
    if side=='back': return ((entry*(1-SPREAD)-1)*(1-COMM)) if won else -1.0
def trade_pnl(entry,exit_):  # back at entry, lay at exit (prices after spread)
    e=entry*(1-SPREAD); x=exit_*(1+SPREAD); p=e/x-1
    return p*(1-COMM) if p>0 else p
def process(rows):
    global n_ev,n_seen
    n_seen+=1
    hw,aw=norm(rows[0][1]),norm(rows[0][2]); d=rows[0][3].date()
    rec=M.get((d,hw,aw)) or M.get((d-datetime.timedelta(days=1),hw,aw)) or M.get((d+datetime.timedelta(days=1),hw,aw))
    if n_seen==300:
        print(f"SELF-CHECK after 300 events: {n_ev} joined",flush=True)
        if n_ev<30: sys.exit("ABORT join")
    if not rec: return
    n_ev+=1; goals,r=rec; season=r.season
    px=collections.defaultdict(dict)
    for _,_,_,_,minute,mkt,sel,ltp in rows: px[(mkt,sel)][int(minute)]=float(ltp)
    # B1 Home Gains
    e=px_at(px,'MO','HOME',2)
    if e and e>1.01:
        hg=[g for g,s in goals if s=='H']
        if hg:
            x=px_at(px,'MO','HOME',hg[0]+3,tol=2)
            pnl=trade_pnl(e,x) if x else None
        else:
            pnl=settle_pnl('back',e,r.ft_h>r.ft_a)
        if pnl is not None: B1.append((season,r.tier,r.supremacy,r.p_home_first,e,pnl))
    # B2 Over 1.5 drip at 20/27/35 if 0-0
    mk='OU15' if has15 else 'OU25'
    for t in (20,27,35):
        if any(g<=t for g,s in goals): break
        e=px_at(px,mk,'OVER',t)
        if not e or e<=1.01: continue
        nxt=[g for g,s in goals if g>t]
        if nxt:
            x=px_at(px,mk,'OVER',nxt[0]+3,tol=2); pnl=trade_pnl(e,x) if x else None
        else:
            pnl=settle_pnl('back',e,(r.ft_goals>1.5) if has15 else (r.ft_goals>2.5))
        if pnl is not None: B2.append((season,t,r.tier,r.goals_rank_all,r.p_00at20_goal,e,pnl))
buf=[]; last=None
for row in scur:
    if last is not None and row[0]!=last: process(buf); buf=[]
    buf.append(row); last=row[0]
if buf: process(buf)
print(f"events seen {n_seen}, joined {n_ev}, B1 trades {len(B1)}, B2 trades {len(B2)}")
def table(df,by,label):
    print(f"\n{label}: P&L per £100, by {by}, train vs test")
    T=df.groupby(by+['season']).pnl.agg(['size','mean']).unstack('season')
    T.columns=[f"{a}_{b}" for a,b in T.columns];
    for c in T.columns:
        if c.startswith('mean'): T[c]=(100*T[c]).round(1)
    print(T.to_string())
b1=pd.DataFrame(B1,columns=['season','tier','supremacy','p_home_first','entry','pnl'])
if len(b1):
    b1['sup_band']=pd.cut(b1.supremacy,[-9,-0.5,0,0.25,0.5,0.75,1.0,9]); b1['phf_band']=pd.cut(b1.p_home_first,[0,0.4,0.45,0.5,0.55,0.6,0.65,1])
    print("\nB1 HOME GAINS overall:"); print(b1.groupby('season').pnl.agg(['size','mean']).assign(mean=lambda x:(100*x['mean']).round(1)).to_string())
    table(b1,['tier'],'B1 by Tier'); table(b1,['sup_band'],'B1 by Supremacy'); table(b1,['phf_band'],'B1 by "Home scores first" prob')
b2=pd.DataFrame(B2,columns=['season','t','tier','goals_rank','p_goal','entry','pnl'])
if len(b2):
    b2['rank_band']=pd.cut(b2.goals_rank,[0,40,55,70,85,101]); b2['pg_band']=pd.cut(b2.p_goal,[0,0.75,0.82,0.88,0.92,1])
    print(f"\nB2 OVER 1.5 DRIP ({'OU15' if has15 else 'O2.5 PROXY'}) overall:"); print(b2.groupby(['t','season']).pnl.agg(['size','mean']).assign(mean=lambda x:(100*x['mean']).round(1)).to_string())
    table(b2,['rank_band'],'B2 by Goals rank (all leagues)'); table(b2,['pg_band'],'B2 by "0-0 at 20 -> goal" prob'); table(b2,['tier'],'B2 by Tier')
print("\nVERDICT RULE: a cell is a candidate only if positive in BOTH seasons with n>=150 train and n>=60 test. Anything else is noise.")
PYFILE
python3 fts_newmodel_test.py
