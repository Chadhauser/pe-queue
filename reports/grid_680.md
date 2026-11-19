# 680 - 2026-11-19 16:04 UTC
```
sort line: already fixed
report guard: added
compiles
running: 1
/root/pe-sports/team/grid_history.py:92: UserWarning: pandas only supports SQLAlchemy connectable (engine/connection) or database string URI or sqlite3 DBAPI2 connection. Other DBAPI2 objects are not 
  df = pd.read_sql("""SELECT o.market_id, o.sel, o.market_time, o.ts, o.ltp::float8 ltp, o.inplay, (r.status = 'WINNER') won
/root/pe-sports/team/grid_history.py:92: UserWarning: pandas only supports SQLAlchemy connectable (engine/connection) or database string URI or sqlite3 DBAPI2 connection. Other DBAPI2 objects are not 
  df = pd.read_sql("""SELECT o.market_id, o.sel, o.market_time, o.ts, o.ltp::float8 ltp, o.inplay, (r.status = 'WINNER') won
/root/pe-sports/team/grid_history.py:92: UserWarning: pandas only supports SQLAlchemy connectable (engine/connection) or database string URI or sqlite3 DBAPI2 connection. Other DBAPI2 objects are not 
  df = pd.read_sql("""SELECT o.market_id, o.sel, o.market_time, o.ts, o.ltp::float8 ltp, o.inplay, (r.status = 'WINNER') won
```

# The full grid, stage 1: Betfair history - 2026-11-19 16:06 UTC

Market types finished: 7 of 29. Slices tested so far: 2,840. With 300 or more bets: 144. Profitable in both halves: 33.
At the last traded price, 2% commission, held to the result. Back is per £100 staked; lay is per £100 at risk. £ a month is at £10 a bet. UNVERIFIED until the same slice holds at real offered prices.

## Top 20 survivors by £ a month

| # | sport | market | when | price band | side | price move | bets | £ per £100 | first half | second half | £ a month at £10 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Cricket | MATCH_ODDS | in-play, first third | 80-90% chance | lay | price falling | 498 | +16.30 | +28.04 | +4.83 | £68 |
| 2 | Cricket | MATCH_ODDS | 6 hours before | 60-70% chance | lay | no earlier price | 533 | +10.46 | +6.66 | +13.09 | £46 |
| 3 | Cricket | MATCH_ODDS | in-play, first third | 10-20% chance | back | price rising | 456 | +11.19 | +21.04 | +1.77 | £43 |
