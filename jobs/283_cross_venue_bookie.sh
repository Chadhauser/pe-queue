#!/bin/bash
# 283: THE BOOKIE ACROSS VENUES. We don't look for arbs that already exist (270: none); we POST the price on the thin venue and
# hedge on the deep one. Quote one tick inside Matchbook's/Smarkets' spread; if filled, hedge instantly at Betfair's opposite
# touch. Edge per fill = thin-venue improvement minus Betfair's touch minus both commissions (Betfair 2%, Matchbook 1.5%,
# Smarkets 2%). This measures, per minute bucket over 24 h, football Match Odds in-play and pre-match:
#   - how often a one-tick-inside quote on the thin venue is hedgeable at Betfair for a profit (both sides)
#   - mean locked edge when it is, per £10; how much Betfair size sits at the hedge price; by league and by exchange
# Then (if positive) the paper books 'mb10' / 'smk10' follow the same engine with the xx tape as the quote feed.
set -e
python3 - <<'PY'
import sys,psycopg2; sys.path.insert(0,'/root/pe-bot'); from bot_core import DB
con=psycopg2.connect(DB,sslmode='require'); con.autocommit=True; k=con.cursor(); k.execute("SET statement_timeout='1500s'")
try: k.execute("CREATE EXTENSION IF NOT EXISTS unaccent")
except Exception: k.execute("CREATE OR REPLACE FUNCTION pg_temp.unaccent(text) RETURNS text AS $$ SELECT translate($1,'áàâäãåéèêëíìîïóòôöõúùûüçñ','aaaaaaeeeeiiiiooooouuuucn') $$ LANGUAGE sql IMMUTABLE"); k.execute("SET search_path=pg_temp,public")
k.execute("""DROP TABLE IF EXISTS tmp_x; CREATE TEMP TABLE tmp_x AS
SELECT date_trunc('minute',ts) m, exchange, inplay,
       regexp_replace(lower(replace(unaccent(event_name),' vs ',' v ')),'[^a-z0-9 ]','','g') ev,
       regexp_replace(lower(unaccent(sel_name)),'[^a-z0-9 ]','','g') seln,
       avg(back_px) xb, avg(back_sz) xbs, avg(lay_px) xl, avg(lay_sz) xls
FROM xx_tape WHERE ts>now()-interval '24 hours' AND back_px IS NOT NULL AND lay_px IS NOT NULL AND lay_px>back_px
  AND lower(market_name) IN ('match odds','full-time result') AND sel_name NOT LIKE '%%/%%' GROUP BY 1,2,3,4,5""")
k.execute("""DROP TABLE IF EXISTS tmp_b; CREATE TEMP TABLE tmp_b AS
SELECT date_trunc('minute',ts) m, competition, regexp_replace(lower(replace(unaccent(event_name),' vs ',' v ')),'[^a-z0-9 ]','','g') ev, sel,
       avg(back_px) bb, avg(back_sz) bbs, avg(lay_px) bl, avg(lay_sz) bls
FROM liq_sample WHERE mkt='MO' AND ts>now()-interval '24 hours' AND back_px IS NOT NULL AND lay_px IS NOT NULL AND lay_px<=back_px*1.2 GROUP BY 1,2,3,4""")
k.execute("""DROP TABLE IF EXISTS tmp_q; CREATE TEMP TABLE tmp_q AS
SELECT b.m, b.competition, b.ev, b.sel, x.exchange, x.inplay, b.bb, b.bbs, b.bl, b.bls, x.xb, x.xbs, x.xl, x.xls,
  CASE WHEN x.exchange='matchbook' THEN 0.015 ELSE 0.02 END xc,
  -- tick size at the quote price (Betfair ladder; both venues use it or finer)
  CASE WHEN x.xl<2 THEN 0.01 WHEN x.xl<3 THEN 0.02 WHEN x.xl<4 THEN 0.05 WHEN x.xl<6 THEN 0.1 WHEN x.xl<10 THEN 0.2 WHEN x.xl<20 THEN 0.5 WHEN x.xl<30 THEN 1 WHEN x.xl<50 THEN 2 WHEN x.xl<100 THEN 5 ELSE 10 END tk
FROM tmp_b b JOIN tmp_x x ON x.ev=b.ev AND x.m=b.m
 AND ( (b.sel='DRAW' AND x.seln LIKE '%%draw%%')
    OR (b.sel='HOME' AND x.seln NOT LIKE '%%draw%%' AND (split_part(b.ev,' v ',1) LIKE '%%'||x.seln||'%%' OR x.seln LIKE '%%'||split_part(b.ev,' v ',1)||'%%'))
    OR (b.sel='AWAY' AND x.seln NOT LIKE '%%draw%%' AND (split_part(b.ev,' v ',2) LIKE '%%'||x.seln||'%%' OR x.seln LIKE '%%'||split_part(b.ev,' v ',2)||'%%')) )""")
k.execute("SELECT count(*), count(DISTINCT ev), count(*) FILTER (WHERE inplay) FROM tmp_q"); print("matched minute samples, games, in-play samples:",k.fetchone())
# our LAY quote on the thin venue one tick inside its lay touch: ql = xl - tk ; must still be above its back touch. Hedge: BACK on Betfair at bb.
# locked per £10 lay stake: back £10 at bb, lay £10 at ql -> if runner wins: 10*(bb-1)*(1-0.02) - 10*(ql-1); if loses: -10 + 10*(1-xc). Use the lower outcome (worst case) as 'locked'.
k.execute("""DROP TABLE IF EXISTS tmp_e; CREATE TEMP TABLE tmp_e AS
SELECT *, (xl-tk) ql, (xb+tk) qb,
  LEAST(10*(bb-1)*0.98 - 10*((xl-tk)-1), -10 + 10*(1-xc)) lay_side_locked,     -- lay thin @ ql, back Betfair @ bb
  LEAST(10*((xb+tk)-1)*(1-xc) - 10*(bl-1), -10*(1) + 10*0.98) back_side_locked  -- back thin @ qb, lay Betfair @ bl
FROM tmp_q WHERE (xl-tk)>xb AND (xb+tk)<xl""")
for side,col,szcol in [('LAY on thin venue / BACK Betfair','lay_side_locked','bbs'),('BACK on thin venue / LAY Betfair','back_side_locked','bls')]:
    k.execute(f"""SELECT exchange, inplay, count(*) n, count(*) FILTER (WHERE {col}>0) pos, round(100.0*count(*) FILTER (WHERE {col}>0)/count(*),1) pct,
                         round(avg({col}) FILTER (WHERE {col}>0),3) mean_pos, round(avg({szcol}) FILTER (WHERE {col}>0),0) bf_size_at_hedge
                  FROM tmp_e GROUP BY 1,2 ORDER BY 1,2"""); print(f"\n== {side}: exchange | inplay | samples | positive | % | mean locked per £10 | Betfair size at hedge"); [print("  ",r) for r in k.fetchall()]
    k.execute(f"SELECT competition, count(*) FILTER (WHERE {col}>0) pos, round(avg({col}) FILTER (WHERE {col}>0),3) FROM tmp_e GROUP BY 1 ORDER BY 2 DESC NULLS LAST LIMIT 8"); print("   top leagues:",k.fetchall())
k.execute("SELECT exchange, round(avg((xl-xb)/tk),1) thin_spread_ticks, round(avg((bl-bb)/tk),1) bf_spread_ticks FROM tmp_e GROUP BY 1"); print("\nspread in ticks, thin venue vs Betfair:",k.fetchall())
PY
