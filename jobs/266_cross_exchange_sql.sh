#!/bin/bash
# 266: 257 was OOM-killed loading three days of xx_tape into pandas. Same test, done in SQL on 24 h: Betfair recorder (football
# MO) joined to Matchbook/Smarkets per minute bucket, same game (accent-stripped names), same runner; edge counted only with
# >= £20 on both sides; 2% commission each side; both directions; persistence over the next 2 minutes.
set -e
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; k=con.cursor()
try: k.execute("CREATE EXTENSION IF NOT EXISTS unaccent"); print("unaccent: extension")
except Exception as e:
    k.execute("CREATE OR REPLACE FUNCTION pg_temp.unaccent(text) RETURNS text AS $$ SELECT translate($1,'áàâäãåéèêëíìîïóòôöõúùûüçñ','aaaaaaeeeeiiiiooooouuuucn') $$ LANGUAGE sql IMMUTABLE"); k.execute("SET search_path=pg_temp,public"); print("unaccent: fallback translate (",str(e)[:60],")")
k.execute("SET statement_timeout='1500s'")
k.execute("""
DROP TABLE IF EXISTS tmp_xx; CREATE TEMP TABLE tmp_xx AS
SELECT date_trunc('minute',ts) m, exchange,
       regexp_replace(lower(replace(unaccent(event_name),' vs ',' v ')),'[^a-z0-9 ]','','g') ev,
       regexp_replace(lower(unaccent(sel_name)),'[^a-z0-9 ]','','g') seln,
       avg(back_px) back_px, avg(back_sz) back_sz, avg(lay_px) lay_px, avg(lay_sz) lay_sz
FROM xx_tape WHERE ts>now()-interval '24 hours' AND inplay AND back_px IS NOT NULL AND lay_px IS NOT NULL
  AND (market_name ILIKE '%match odds%' OR market_name ILIKE '%winner%' OR market_name ILIKE '%1x2%' OR market_name ILIKE '%full time%')
GROUP BY 1,2,3,4"""); k.execute("SELECT count(*) FROM tmp_xx"); print("xx minute rows:",k.fetchone()[0])
k.execute("""
DROP TABLE IF EXISTS tmp_bf; CREATE TEMP TABLE tmp_bf AS
SELECT date_trunc('minute',ts) m, competition,
       regexp_replace(lower(replace(unaccent(event_name),' vs ',' v ')),'[^a-z0-9 ]','','g') ev, sel,
       avg(back_px) back_px, avg(back_sz) back_sz, avg(lay_px) lay_px, avg(lay_sz) lay_sz
FROM liq_sample WHERE mkt='MO' AND ts>now()-interval '24 hours' AND back_px IS NOT NULL AND lay_px IS NOT NULL AND lay_px<=back_px*1.2
GROUP BY 1,2,3,4"""); k.execute("SELECT count(*) FROM tmp_bf"); print("betfair minute rows:",k.fetchone()[0])
k.execute("""
DROP TABLE IF EXISTS tmp_j; CREATE TEMP TABLE tmp_j AS
SELECT b.m, b.competition, b.ev, b.sel, x.exchange, b.back_px bb, b.back_sz bbs, b.lay_px bl, b.lay_sz bls, x.back_px xb, x.back_sz xbs, x.lay_px xl, x.lay_sz xls,
       (b.back_px*0.98)/(x.lay_px*1.02)-1 edge_a, (x.back_px*0.98)/(b.lay_px*1.02)-1 edge_b
FROM tmp_bf b JOIN tmp_xx x ON x.ev=b.ev AND x.m=b.m
 AND ( (b.sel='DRAW' AND x.seln LIKE '%draw%')
    OR (b.sel='HOME' AND x.seln NOT LIKE '%draw%' AND (split_part(b.ev,' v ',1) LIKE '%'||x.seln||'%' OR x.seln LIKE '%'||split_part(b.ev,' v ',1)||'%'))
    OR (b.sel='AWAY' AND x.seln NOT LIKE '%draw%' AND (split_part(b.ev,' v ',2) LIKE '%'||x.seln||'%' OR x.seln LIKE '%'||split_part(b.ev,' v ',2)||'%')) )""")
k.execute("SELECT count(*), count(DISTINCT ev) FROM tmp_j"); print("matched minute samples, games:",k.fetchone())
for name,cond,col in [('A back Betfair / lay other','bbs>=20 AND xls>=20','edge_a'),('B back other / lay Betfair','xbs>=20 AND bls>=20','edge_b')]:
    k.execute(f"SELECT count(*), count(*) FILTER (WHERE {col}>0), round(avg({col}) FILTER (WHERE {col}>0)*100,2), count(DISTINCT ev) FILTER (WHERE {col}>0) FROM tmp_j WHERE {cond}"); n,p,me,g=k.fetchone()
    print(f"\n{name}: samples(size>=£20 both) {n} | positive edge {p} ({100*p/max(n,1):.1f}%) | mean edge when positive {me}% | games {g}")
    k.execute(f"SELECT exchange, count(*) FROM tmp_j WHERE {cond} AND {col}>0 GROUP BY 1"); print("  by exchange:",k.fetchall())
    k.execute(f"SELECT competition, count(*) FROM tmp_j WHERE {cond} AND {col}>0 GROUP BY 1 ORDER BY 2 DESC LIMIT 6"); print("  top leagues:",k.fetchall())
    k.execute(f"SELECT round(avg(CASE WHEN n2.{col}>0 THEN 1 ELSE 0 END),2) FROM tmp_j j JOIN tmp_j n2 ON n2.ev=j.ev AND n2.sel=j.sel AND n2.exchange=j.exchange AND n2.m=j.m+interval '2 minutes' WHERE j.{cond.replace('bbs','bbs').replace(' AND ',' AND j.')} AND j.{col}>0"); print("  persistence 2 min later:",k.fetchone())
    k.execute(f"SELECT ev, sel, exchange, m, round({col}*100,2) FROM tmp_j WHERE {cond} AND {col}>0 ORDER BY {col} DESC LIMIT 5"); print("  biggest:",k.fetchall())
PY
