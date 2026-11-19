# 682 - 2026-11-19 16:12 UTC
```
compiles
finished-list cleared: 11 market types will be redone with both families
running: 1
  df = pd.read_sql("""SELECT o.market_id, o.sel, o.market_time, o.ts, o.ltp::float8 ltp, o.inplay, (r.status = 'WINNER') won
/root/pe-sports/team/grid_history.py:111: UserWarning: pandas only supports SQLAlchemy connectable (engine/connection) or database string URI or sqlite3 DBAPI2 connection. Other DBAPI2 objects are not
  df = pd.read_sql("""SELECT o.market_id, o.sel, o.market_time, o.ts, o.ltp::float8 ltp, o.inplay, (r.status = 'WINNER') won
/root/pe-sports/team/grid_history.py:111: UserWarning: pandas only supports SQLAlchemy connectable (engine/connection) or database string URI or sqlite3 DBAPI2 connection. Other DBAPI2 objects are not
  df = pd.read_sql("""SELECT o.market_id, o.sel, o.market_time, o.ts, o.ltp::float8 ltp, o.inplay, (r.status = 'WINNER') won
```

# The full grid, stage 1: Betfair history - 2026-11-19 16:13 UTC

Market types finished: 2 of 29. Slices tested so far: 4,426. With 300 or more bets: 752. Profitable in both halves: 199.
At the last traded price, 2% commission. Two families: hold to the result (back is per £100 staked, lay per £100 at risk) and in-and-out (enter at one time, exit at a later one, per £100 of the first stake). £ a month is at £10 a bet. UNVERIFIED until the same slice holds at real offered prices.

## Top 20 survivors by £ a month

| # | sport | market | when | price band | side | price move | bets | £ per £100 | first half | second half | £ a month at £10 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Horse Racing | WIN | in-play, first third | 0-10% chance | back | price rising | 6,782 | +30.17 | +26.70 | +32.88 | £1,574 |
| 2 | Greyhound Racing | WIN | 10 minutes before | 0-10% chance | back | no earlier price | 1,442 | +28.02 | +16.95 | +35.48 | £808 |
| 3 | Horse Racing | WIN | 2 minutes before | 0-10% chance | back | price flat | 7,454 | +13.00 | +6.56 | +18.58 | £745 |
| 4 | Greyhound Racing | WIN | 10 minutes before | 40-50% chance | lay | no earlier price | 1,642 | +7.58 | +8.74 | +6.58 | £249 |
| 5 | Greyhound Racing | WIN | 2 minutes before | 30-40% chance | back | price falling | 2,083 | +4.78 | +4.97 | +4.70 | £199 |
