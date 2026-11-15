import sys
sys.path.insert(0, 'runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local())
k = c.cursor()
# Independent of the job: SQL window counts, no Python state code, no lib_cand.
sql = """
with g as (
  select div, season, date, home team, fthg, ftag, psch, pscd, psca, 'H' venue, home, away from fd_matches where fthg is not null and ftag is not null and season<'9000'
  union all
  select div, season, date, away team, fthg, ftag, psch, pscd, psca, 'A' venue, home, away from fd_matches where fthg is not null and ftag is not null and season<'9000'
), f as (
  select div, season, team, min(date) d0 from g group by 1,2,3
), m as (
  select x.* from fd_matches x
  join f a on a.div=x.div and a.season=x.season and a.team=x.home and a.d0=x.date
  join f b on b.div=x.div and b.season=x.season and b.team=x.away and b.d0=x.date
  where x.fthg is not null and x.ftag is not null and x.season<'9000'
)
select count(*) g1_all,
       count(*) filter (where psch is not null and pscd is not null and psca is not null) n_pin,
       avg((fthg>ftag)::int) filter (where psch is not null and pscd is not null and psca is not null) home_won,
       avg((fthg<ftag)::int) filter (where psch is not null and pscd is not null and psca is not null) away_won,
       count(*) filter (where raw->>'BFECA' is not null and raw->>'BFECH' is not null and raw->>'BFECD' is not null) n_bfec,
       avg((fthg<ftag)::int) filter (where raw->>'BFECA' is not null and raw->>'BFECH' is not null and raw->>'BFECD' is not null) bfec_away_won
from m
"""
k.execute(sql)
print('sql check', k.fetchone())
k.execute("select div,count(*) from fd_matches where season='2425' and fthg is not null group by 1 order by 1")
print('2425 games by div', k.fetchall())
# Biggest lay win on BFEC Away: is a 1.05 close a real away favourite?
k.execute("select date,home,away,fthg,ftag,raw->>'BFECH',raw->>'BFECD',raw->>'BFECA' from fd_matches where (raw->>'BFECA')::float8<=1.06 and raw->>'BFECA'<>'' order by date limit 8")
for r in k.fetchall():
    print(r)
