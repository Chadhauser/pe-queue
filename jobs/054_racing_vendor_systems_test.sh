#!/bin/bash
# 054: VENDOR RACING SYSTEMS vs OUR OWN RESULTS — from the Trend Report PDFs Peter uploaded 13 Oct. Both are BSP-only, so they
# test on racing_results (and any bigger BSP+result table found) with no tape needed:
#  (A) Lay odds-on favourites (BSP<2.0) to 1pt LIABILITY — all courses, then the vendor's 29-course list, then by race-type keyword.
#  (B) Triple Dutch: fav BSP>=2.0 and 2nd fav BSP<=4.0; dutch% = 1/fav + 1/2nd. S1: 3-runner races dutch%>=55% lay both (1pt liab each
#      side = back the outsider). S2: 4+ runners dutch% 55-72.5% lay both. S3: dutch% >72.5% dutch BACK both.
# Every cell: n, strike, P&L per £100 risk, t-stat, by month. Vendor claims are UNVERIFIED until they survive here.
cd /root/pe-scan && cat > racing_vendor_test.py <<'PYFILE'
import sys, math, re, psycopg2, pandas as pd, numpy as np
sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
COMM=0.02
con=psycopg2.connect(DB,sslmode='require'); cur=con.cursor()
cur.execute("""SELECT table_name, string_agg(column_name,',') FROM information_schema.columns WHERE table_schema='public' GROUP BY 1
               HAVING bool_or(column_name ILIKE 'bsp') AND bool_or(column_name ILIKE 'won' OR column_name ILIKE 'win%' OR column_name ILIKE 'result%' OR column_name ILIKE 'pos%')""")
print("tables with BSP + result columns:");
for t,c in cur.fetchall():
    cur.execute(f"SELECT count(*) FROM {t}"); print(" ",t,cur.fetchone()[0],"rows |",c[:200])
R=pd.read_sql("SELECT market_id, venue, market_name, market_start, runner, bsp, won FROM racing_results WHERE bsp IS NOT NULL AND bsp>1",con)
R['bsp']=R.bsp.astype(float); R['won']=R.won.astype(bool); R['venue']=R.venue.str.strip().str.title()
R['month']=pd.to_datetime(R.market_start).dt.to_period('M').astype(str)
print("racing_results runners",len(R),"races",R.market_id.nunique(),R.month.min(),"->",R.month.max())
def tstat(x): x=pd.Series(x).dropna(); return round(float(x.mean()/(x.std(ddof=1)/math.sqrt(len(x)))),1) if len(x)>2 and x.std(ddof=1)>0 else 0.0
def rep(df,col,title,by=None):
    print(f"\n=== {title}: n {len(df)} | strike {df[col+'_win'].mean()*100:.1f}% | P&L per £100 risk {df[col].mean()*100:+.1f} | t {tstat(df[col])} ===")
    if by is not None and len(df):
        g=df.groupby(by)[col].agg(['size','mean']); g['mean']=(g['mean']*100).round(1); g['t']=df.groupby(by)[col].apply(tstat)
        print(g[g['size']>=15].sort_values('mean',ascending=False).to_string())
# ---- (A) lay odds-on favourites to 1pt liability
F=R.sort_values('bsp').groupby('market_id').head(1).copy()   # the favourite by BSP
A=F[F.bsp<2.0].copy()
# lay to liability 1: stake = 1/(bsp-1); win (horse loses) = stake*(1-comm); lose = -1
A['stk']=1/(A.bsp-1); A['lay']=np.where(A.won,-1.0,A.stk*(1-COMM)); A['lay_win']=~A.won
rep(A,'lay','A1. lay ALL odds-on favs, 1pt liability','venue')
V=['Cartmel','Roscommon','Redcar','Pontefract','Thurles','Naas','York','Thirsk','Ripon','Chelmsford City','Kelso','Hexham','Newbury','Fontwell','Fakenham','Killarney','Leicester','Fairyhouse','Epsom','Bangor-On-Dee','Bangor','Market Rasen','Ffos Las','Curragh','Downpatrick','Towcester','Clonmel','Southwell','Bath','Stratford']
rep(A[A.venue.isin(V)],'lay','A2. vendor 29-course list only','venue')
def rtype(n):
    n=(n or '').lower()
    for k,lab in (('hcap hrd','Hcap Hurdle'),('hcap chs','Hcap Chase'),('hcap','Handicap other'),('nov','Novice'),('mdn','Maiden'),('hunt','Hunters'),('grp','Group'),('listed','Listed'),('stks','Stakes/Conditions'),('nhf','NH Flat'),('hrd','Hurdle other'),('chs','Chase other'),('clm','Claimer'),('sell','Seller'),('nurs','Nursery')):
        if k in n: return lab
    return 'other'
A['rtype']=A.market_name.map(rtype)
rep(A,'lay','A3. all courses by race type','rtype')
KEEP=['Group','Listed','Stakes/Conditions','Hcap Hurdle','Hcap Chase','Hunters','Maiden','Hurdle other','NH Flat']
rep(A[A.venue.isin(V)&A.rtype.isin(KEEP)],'lay','A4. vendor courses AND vendor race types (the full vendor rule)','month')
rep(A,'lay','A5. all odds-on lays by month','month')
# ---- (B) Triple Dutch
R['n']=R.groupby('market_id').runner.transform('count')
top=R.sort_values('bsp').groupby('market_id').head(2)
piv=top.groupby('market_id').agg(fav=('bsp','first'),sec=('bsp','last'),fav_won=('won','first'),sec_won=('won','last'),n=('n','first'),venue=('venue','first'),month=('month','first'),mname=('market_name','first')).reset_index()
piv=piv[(piv.fav>=2.0)&(piv.sec<=4.0)&(piv.sec>=piv.fav)].copy(); piv['dpct']=(1/piv.fav+1/piv.sec)*100
piv['either']=piv.fav_won|piv.sec_won
# lay both to 1pt liability EACH side? vendor: £100 total liability -> we model: lay both so total liability = 1 (split so each lay has liability 0.5)
def laypair(r):
    s1=0.5/(r.fav-1); s2=0.5/(r.sec-1)
    if r.fav_won: return -0.5+s2*(1-COMM)
    if r.sec_won: return -0.5+s1*(1-COMM)
    return (s1+s2)*(1-COMM)
piv['lay']=piv.apply(laypair,axis=1); piv['lay_win']=~piv.either
# dutch back both to equal profit on £1 total
def dutch(r):
    a=1/r.fav; b=1/r.sec; sa=a/(a+b); sb=b/(a+b)
    if r.fav_won: return (sa*r.fav-1)*(1-COMM)
    if r.sec_won: return (sb*r.sec-1)*(1-COMM)
    return -1.0
piv['back']=piv.apply(dutch,axis=1); piv['back_win']=piv.either
S1=piv[(piv.n==3)&(piv.dpct>=55)]; rep(S1,'lay','B1. Triple Dutch S1: 3-runner races, dutch%>=55, lay both','month')
S2=piv[(piv.n>=4)&(piv.dpct.between(55,72.5))]; rep(S2,'lay','B2. S2: 4+ runners, dutch% 55-72.5, lay both (all classes - we lack class)','month')
S2c=S2[S2.mname.str.contains(r'Grp|Listed|Class 1|Class 2|Hcap',case=False,na=False)]; rep(S2c,'lay','B2b. S2 restricted to Group/Listed/named-class names','venue')
S3=piv[(piv.n>=4)&(piv.dpct>72.5)]; rep(S3,'back','B3. S3: dutch%>72.5, dutch BACK both','month')
piv['band']=pd.cut(piv.dpct,[0,50,55,60,65,70,72.5,80,100])
print("\n=== B4. lay-both P&L by dutch% band (all 4+ runner races) ==="); g=piv[piv.n>=4].groupby('band',observed=True).lay.agg(['size','mean']); g['mean']=(g['mean']*100).round(1); print(g.to_string())
print("\nVERDICT RULE: a vendor system is a candidate only if positive here with t>=2 and no single month carrying it; racing_results is ~5 weeks so anything positive goes to the 164,900-runner history next (table printed above if it exists).")
PYFILE
python3 racing_vendor_test.py
