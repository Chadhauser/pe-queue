#!/bin/bash
set -o pipefail
# 316: GOAL SIGNAL vs THE MARKET, priced from our own recorder. goal_live_predictions never stored a price, so each prediction at
# score-total 2 is joined to the Under 2.5 price on ip_tape (multi-sport in-play recorder, since September) by team-name match and
# nearest sample within 90 s. Same test as 305: model P(no more goals) = 1 - p_goal_rest_of_match vs market 1/under_price; back
# Under when model >= market + M points, lay Under when <= market - M (M = 3/5/8/12). One prediction per fixture per 5-min bucket,
# one tick adverse, 2% commission, £10 risk. Halves: before/after 27 Oct (delayed vs live key). Table gs_vs_market_v2.
python3 - <<'PY' 2>&1 | grep -v -E "UserWarning|pd.read_sql"
import sys,re,unicodedata,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor(); cur.execute("SET statement_timeout='2400s'")
mt=pd.read_sql("SELECT market_type, count(*) n FROM ip_tape WHERE ts>now()-interval '60 days' AND (sport ILIKE '%%soccer%%' OR sport ILIKE '%%foot%%' OR sport='1') AND (market_type ILIKE '%%2.5%%' OR market_type ILIKE '%%25%%') GROUP BY 1 ORDER BY 2 DESC",con)
print("OU2.5-like market types on ip_tape:",mt.to_dict('records'))
if len(mt)==0: print("no OU2.5 market on ip_tape — nothing to price against"); sys.exit(0)
MT=mt.market_type.iloc[0]
P=pd.read_sql("""SELECT fixture_id, captured_at, minute, p_goal_rest_of_match::float p_rest FROM (
  SELECT *, row_number() OVER (PARTITION BY fixture_id, minute/5 ORDER BY captured_at) rn FROM goal_live_predictions
  WHERE settled AND p_goal_rest_of_match IS NOT NULL AND score_home+score_away=2 AND minute BETWEEN 1 AND 85 AND captured_at>now()-interval '60 days') x WHERE rn=1""",con)
FX=pd.read_sql("SELECT DISTINCT ON (fixture_id) fixture_id, home_team, away_team, league_name league, score_home+score_away ft_tot, captured_at last_seen FROM goal_timeline WHERE captured_at>now()-interval '61 days' AND minute>=80 ORDER BY fixture_id, captured_at DESC",con)
P=P.merge(FX,on='fixture_id'); print("predictions at total=2 with a final score:",len(P),"| fixtures:",P.fixture_id.nunique(),flush=True)
T=pd.read_sql("SELECT ts, event_name, sel_name, ltp::float ltp, back_px::float back_px, lay_px::float lay_px FROM ip_tape WHERE market_type=%s AND ts>now()-interval '60 days' AND status='OPEN' AND sel_name ILIKE 'under%%'",con,params=(MT,))
print("under-2.5 samples on tape:",len(T),"| events:",T.event_name.nunique(),flush=True)
def norm(s):
    s=unicodedata.normalize('NFKD',str(s)).encode('ascii','ignore').decode().lower()
    s=re.sub(r"\b(fc|cf|afc|sc|ac|as|ss|us|sv|vfb|vfl|tsg|fk|club|de|the|athletic|atletico|sporting|real|cd|ud|sd|rcd|calcio|women|w|u21|u23|ii|b|if|bk|ff|aif|is|kv|sk|fsv)\b"," ",s)
    return set(w for w in re.sub(r"[^a-z0-9 ]"," ",s).split() if len(w)>2)
def sim(a,b): A,B=norm(a),norm(b); return len(A&B)/max(1,len(A|B))
ev=T.groupby('event_name').ts.agg(['min','max']).reset_index()
ev['h']=ev.event_name.str.split(' v ').str[0]; ev['a']=ev.event_name.str.split(' v ').str[1]
fx=P.drop_duplicates('fixture_id')[['fixture_id','home_team','away_team','last_seen']]
m={}
for f in fx.itertuples():
    cand=ev[(ev['min']<f.last_seen)&(ev['max']>f.last_seen-pd.Timedelta(hours=3))]
    best=None; bs=0; b2=0
    for c in cand.itertuples():
        sc=sim(f.home_team,c.h)+sim(f.away_team,c.a)
        if sc>bs: b2=bs; bs=sc; best=c.event_name
        elif sc>b2: b2=sc
    if best and bs>=1.0 and bs-b2>=0.3: m[f.fixture_id]=best
print("fixtures matched to a tape event:",len(m),"of",len(fx),flush=True)
P['event_name']=P.fixture_id.map(m); P=P[P.event_name.notna()].copy()
T=T.sort_values('ts'); P=P.sort_values('captured_at')
J=pd.merge_asof(P,T,left_on='captured_at',right_on='ts',by='event_name',direction='nearest',tolerance=pd.Timedelta(seconds=90))
J=J[J.lay_px.notna()&J.back_px.notna()&(J.back_px>1.01)&(J.lay_px<20)].copy()
print("predictions priced:",len(J),flush=True)
if len(J)<200: print("too few priced predictions"); sys.exit(0)
J['no_more']=J.ft_tot<=2; J['model_p']=1-J.p_rest; J['mkt_p']=1/((J.back_px+J.lay_px)/2); J['edge']=(J.model_p-J.mkt_p)*100
J['era']=np.where(pd.to_datetime(J.captured_at,utc=True)>=pd.Timestamp('2026-10-27',tz='UTC'),'live-key','delayed-key')
rows=[]
for M in (3,5,8,12):
    b=J[J.edge>=M].copy(); b['side']='BACK_UNDER'; b['pnl']=np.where(b.no_more,10*(b.back_px-1)*0.98,-10.0); b['M']=M; rows.append(b)
    l=J[J.edge<=-M].copy(); l['side']='LAY_UNDER'; s=10/(l.lay_px-1); l['pnl']=np.where(l.no_more,-10.0,s*0.98); l['M']=M; rows.append(l)
R=pd.concat(rows,ignore_index=True)
R['mband']=pd.cut(R.minute,[0,30,45,60,75,85],labels=['1-30','31-45','46-60','61-75','76-85'])
def t(x): return x.mean()/(x.std(ddof=1)/len(x)**0.5) if len(x)>1 and x.std(ddof=1)>0 else 0
def rep(dims):
    return R.groupby(dims,observed=True).agg(n=('pnl','size'),fixtures=('fixture_id','nunique'),per10=('pnl','mean'),t=('pnl',t),
        h1=('pnl',lambda x:x[R.loc[x.index,'era']=='delayed-key'].mean()),h2=('pnl',lambda x:x[R.loc[x.index,'era']=='live-key'].mean()),n2=('pnl',lambda x:(R.loc[x.index,'era']=='live-key').sum())).round(3)
cur.execute("DROP TABLE IF EXISTS gs_vs_market_v2; CREATE TABLE gs_vs_market_v2 (level TEXT, side TEXT, m INT, mband TEXT, league TEXT, n INT, fixtures INT, per10 NUMERIC, t NUMERIC, h1 NUMERIC, h2 NUMERIC, n_live INT)"); con.commit()
out=[]
for dims in (['side','M'],['side','M','mband'],['side','M','league']):
    g=rep(dims).reset_index(); g['level']='+'.join(dims)
    for c in ('mband','league'):
        if c not in g: g[c]=None
    out.append(g)
    for x in g.itertuples(): cur.execute("INSERT INTO gs_vs_market_v2 VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",(x.level,x.side,int(x.M),None if x.mband is None else str(x.mband),x.league,int(x.n),int(x.fixtures),float(x.per10),float(x.t),None if pd.isna(x.h1) else float(x.h1),None if pd.isna(x.h2) else float(x.h2),int(x.n2)))
con.commit()
A=pd.concat(out,ignore_index=True)
print("\n== model vs market (per £10; h1 delayed-key era, h2 live-key era)"); print(A[A.level=='side+M'][['side','M','n','fixtures','per10','t','h1','h2','n2']].to_string(index=False))
J['eb']=pd.cut(J.edge,[-100,-12,-8,-5,-3,3,5,8,12,100])
print("\n== calibration"); print(J.groupby('eb',observed=True).agg(n=('no_more','size'),model_p=('model_p','mean'),market_p=('mkt_p','mean'),actual=('no_more','mean')).round(3).to_string())
S=A[(A.n>=200)&(A.t>=3.5)&(A.h1>0)&(A.h2>0)&(A.per10>=0.15)].sort_values('t',ascending=False)
print(f"\n== SURVIVORS: {len(S)}"); print(S.head(30).to_string(index=False) if len(S) else "none")
PY
