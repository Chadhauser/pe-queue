#!/bin/bash
# 499_census_nov06 (Finder 2026-11-06, seventh run): read-only structure check before any rule is fixed. No prices are read.
# Greyhound card fields no job has used: form_summary, best_run_time, race_class, trainer, age, sex. The cards are saved after the race
# (race_stage 'Final Result'), so the point here is look-ahead: does a row's form or best time already contain that night's run?
set -o pipefail
python3 - <<'PY' | grep -v -E "UserWarning|pd.read_sql"
import sys,re,warnings
warnings.filterwarnings('ignore')
sys.path.insert(0,'/root/pe-queue/runner')
import creds, psycopg2, pandas as pd, numpy as np
pd.set_option('display.width',200); pd.set_option('display.max_rows',80); pd.set_option('display.max_columns',30)
c=psycopg2.connect(creds.pg_railway(),sslmode='require')
C=pd.read_sql("""SELECT race_date,track,race_time,race_id,race_class,distance,race_stage,trap_number,greyhound,age,sex,trainer,form_summary,best_run_time,finish_position,run_status,reserve,fetched_at FROM greyhound_racecards_today""",c); c.close()
print('rows',len(C),'races',C.race_id.nunique(),'dates',C.race_date.min(),C.race_date.max())
print('dupes race+dog',C.duplicated(['race_id','greyhound']).sum())
C=C.drop_duplicates(['race_id','greyhound'])
print('stage',C.race_stage.value_counts().to_dict()); print('status',C.run_status.value_counts().to_dict()); print('reserve',C.reserve.value_counts().to_dict())
print('finish null',C.finish_position.isna().mean().round(3),'form null',C.form_summary.isna().mean().round(3),'best null',C.best_run_time.isna().mean().round(3),'age null',C.age.isna().mean().round(3),'trainer null',C.trainer.isna().mean().round(3))
print('class top',C.drop_duplicates('race_id').race_class.value_counts().head(30).to_dict())
print('distance top',C.drop_duplicates('race_id').distance.astype(str).value_counts().head(12).to_dict())
print('age',C.age.value_counts().sort_index().to_dict(),'sex',C.sex.value_counts().to_dict())
print('form length',C.form_summary.astype(str).str.len().value_counts().sort_index().to_dict())
print('form chars',pd.Series(list(''.join(C.form_summary.dropna().astype(str)))).value_counts().to_dict())
print('best_run_time sample',C.best_run_time.dropna().sample(8,random_state=1).tolist())
C['rd']=pd.to_datetime(C.race_date); C['fd']=pd.to_datetime(C.fetched_at,utc=True).dt.tz_convert('Europe/London').dt.tz_localize(None).dt.normalize()
print('fetched day minus race day',(C.fd-C.rd).dt.days.value_counts().sort_index().head(8).to_dict())
tm=pd.to_datetime(C.race_date.astype(str)+' '+C.race_time.astype(str),errors='coerce',utc=True)
C['lag_h']=(pd.to_datetime(C.fetched_at,utc=True)-tm)/pd.Timedelta(hours=1)
print('fetched minus off, hours, quantiles',C.lag_h.quantile([.01,.1,.5,.9,.99]).round(2).to_dict(),'share before off',round((C.lag_h<0).mean(),4))
# look-ahead on form: which end is latest, and does it hold this race's finish?
R=C[C.finish_position.notna()&C.form_summary.notna()].copy(); R['form']=R.form_summary.astype(str); R=R[R.form.str.len()>0]
R['fin']=R.finish_position.astype(int).astype(str)
print('this finish == form last char',round((R.form.str[-1]==R.fin).mean(),4),'== form first char',round((R.form.str[0]==R.fin).mean(),4),'n',len(R))
R=R.sort_values(['greyhound','rd','race_time']); R['pf']=R.groupby('greyhound').fin.shift(1); R['pd']=R.groupby('greyhound').rd.shift(1); Q=R[R.pf.notna()]
print('PREVIOUS race finish == form last char',round((Q.form.str[-1]==Q.pf).mean(),4),'== form first char',round((Q.form.str[0]==Q.pf).mean(),4),'n',len(Q))
print('gap days to previous card row, quantiles',((Q.rd-Q['pd']).dt.days).quantile([.1,.5,.9]).to_dict())
# look-ahead on best time
def sec(s):
    m=re.search(r'(\d+\.\d+)',str(s)); return float(m.group(1)) if m else np.nan
B=C[C.finish_position.notna()].copy(); B['bt']=B.best_run_time.map(sec); B=B.sort_values(['greyhound','rd','race_time'])
B['pbt']=B.groupby('greyhound').bt.shift(1); B['pfin']=B.groupby('greyhound').finish_position.shift(1); B=B[B.pbt.notna()&B.bt.notna()]; B['improved']=B.bt<B.pbt-1e-9; B['changed']=(B.bt-B.pbt).abs()>1e-9
print('best time improved v previous row: all',round(B.improved.mean(),4),'| when THIS race won',round(B[B.finish_position==1].improved.mean(),4),'| when THIS race lost',round(B[B.finish_position!=1].improved.mean(),4),'| when PREVIOUS race won',round(B[B.pfin==1].improved.mean(),4),'| PREVIOUS lost',round(B[B.pfin!=1].improved.mean(),4),'n',len(B))
# won rate by fastest in race, a leak shows as far above the rate implied by a live screen; prices are not read here
C['bt']=C.best_run_time.map(sec); V=C[C.finish_position.notna()&C.bt.notna()].copy(); V['rk']=V.groupby('race_id').bt.rank(method='min')
print('won rate by best-time rank',V.groupby('rk').finish_position.apply(lambda x:(x==1).mean()).round(3).head(6).to_dict())
PY
