# Finder 2026-11-07: price-free census to fix thresholds for items 333 and 335. Seasons 2016-2023 only, no prices, nothing written.
import sys,psycopg2,pandas as pd,numpy as np
sys.path.insert(0,'/root/pe-queue/runner'); import creds
pd.set_option('display.width',200); pd.set_option('display.max_rows',100)
con=psycopg2.connect(creds.pg_local()); cur=con.cursor(); cur.execute("SET work_mem='64MB'; SET statement_timeout='600s'")
F=pd.read_sql("SELECT fixture_id,league_id,season,hg,ag FROM af_fixtures WHERE status='FT' AND hg IS NOT NULL AND season BETWEEN 2016 AND 2023",con)
print("fixtures",len(F))
E=pd.read_sql("""SELECT e.fixture_id,coalesce(e.minute,0) mn,coalesce(e.extra,0) ex,e.type,e.detail FROM af_events e JOIN af_fixtures f USING(fixture_id)
 WHERE f.status='FT' AND f.season BETWEEN 2016 AND 2023""",con)
print("events",len(E)); E['t']=E.type.str.lower()
cov=set(E[E.t=='subst'].fixture_id); print("covered by a subst row",len(cov))
E=E[E.fixture_id.isin(cov)]
E2=E[(E.mn>=46)&(E.mn<=84)]
stop=E2[(E2.t.isin(['card','var']))|((E2.t=='goal'))].groupby('fixture_id').size()
subs=E2[E2.t=='subst'].groupby('fixture_id').size()
late=E[(E.mn>=90)]
addt=late.groupby('fixture_id').ex.max()
gl=E[(E.t=='goal')&(E.detail.isin(['Normal Goal','Penalty','Own Goal']))]
g85=gl[gl.mn>=85].groupby('fixture_id').size()
g90=gl[(gl.mn>=90)].groupby('fixture_id').size()
D=pd.DataFrame(index=sorted(cov)); D['stop']=stop; D['subs']=subs; D['addt']=addt; D['g85']=g85; D['g90']=g90
D[['stop','subs','g85','g90']]=D[['stop','subs','g85','g90']].fillna(0)
print(D.stop.describe().round(2).to_dict()); print("quantiles",D.stop.quantile([.1,.2,.33,.5,.67,.8,.9]).to_dict())
D['b']=pd.cut(D.stop,[-1,3,5,7,9,99],labels=['0-3','4-5','6-7','8-9','10+'])
print(D.groupby('b',observed=True).agg(n=('stop','size'),addt_max=('addt','mean'),has_addt=('addt',lambda s:s.notna().mean()),g85=('g85','mean'),p85=('g85',lambda s:(s>0).mean()),p90=('g90',lambda s:(s>0).mean())).round(3))
print("corr stop~g85",round(D.stop.corr(D.g85),3),"subs~g85",round(D.subs.corr(D.g85),3))
print("-- by season share with extra>0",E[E.mn>=90].groupby(E.fixture_id.map(F.set_index('fixture_id').season)).ex.apply(lambda s:(s>0).mean()).round(3).to_dict())
# style columns: coverage and spread
S=pd.read_sql("SELECT s.fixture_id,s.is_home,f.league_id,f.season,(s.raw->>'Fouls')::float fouls,(s.raw->>'Shots insidebox')::float box,(s.raw->>'Passes accurate')::float acc,(s.raw->>'Total passes')::float tot FROM af_stats s JOIN af_fixtures f USING(fixture_id) WHERE f.status='FT' AND f.season BETWEEN 2021 AND 2025",con)
print("style rows",len(S)); print(S.groupby('season')[['fouls','box','acc','tot']].agg(['count','mean']).round(2))
con.close()
