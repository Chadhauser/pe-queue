# 631 — 2026-11-17 06:56 UTC
```python
    best_market, best_p = eligible[0]

    fair_price = 1.0 / best_p if best_p > 0 else 99.0
    fixture_label = f"{home} v {away}"
    action_text = f"BACK {best_market.replace('O', 'Over ').replace('U', 'Under ')} Goals"
    has_baseline = baseline_league_name is not None and baseline_league_name in _league_baselines

    if has_baseline:
        reasoning_text = (f"League λ={full_lambda:.2f}. Remaining-half λ={remaining_lambda:.2f}. "
                          f"Given HT {score}, P({best_market})={best_p*100:.1f}%, fair={fair_price:.2f}.")
    else:
        reasoning_text = (f"No baseline for this league. Using international default λ={DEFAULT_LEAGUE_LAMBDA}. "
                          f"P({best_market})={best_p*100:.1f}%, fair={fair_price:.2f}. "
                          f"⚠ Estimate only — model improves with team-level data.")

    return {
        'fixture': fixture_label, 'league': league_name, 'league_id': league_id,
        'ht_score': score, 'ht_total': ht_total, 'remaining_lambda': remaining_lambda,
        'p_o15': market_probs.get('O1.5', 0), 'p_o25': market_probs.get('O2.5', 0),
        'p_o35': market_probs.get('O3.5', 0), 'p_o45': market_probs.get('O4.5', 0),
        'p_o55': market_probs.get('O5.5', 0), 'p_u25': market_probs.get('U2.5', 0),
        'p_u35': market_probs.get('U3.5', 0), 'p_u45': market_probs.get('U4.5', 0),
        'best_market': best_market, 'best_p': best_p, 'best_fair_price': fair_price,
        'action': action_text, 'reasoning': reasoning_text, 'has_baseline': has_baseline,
    }


def conn():
    return psycopg2.connect(DB_URL, sslmode='require')


def ensure_schema():
    with conn() as c:
        with c.cursor() as cur:
            cur.execute("""
                ALTER TABLE goal_alerts
                  ADD COLUMN IF NOT EXISTS settled BOOLEAN DEFAULT FALSE,
                  ADD COLUMN IF NOT EXISTS settled_at TIMESTAMPTZ,
                  ADD COLUMN IF NOT EXISTS ft_score TEXT,
                  ADD COLUMN IF NOT EXISTS ft_total INT,
                  ADD COLUMN IF NOT EXISTS outcome TEXT,
                  ADD COLUMN IF NOT EXISTS pnl_paper NUMERIC,
                  ADD COLUMN IF NOT EXISTS real_price NUMERIC,
                  ADD COLUMN IF NOT EXISTS real_lay_price NUMERIC,
                  ADD COLUMN IF NOT EXISTS real_price_ts TIMESTAMPTZ,
                  ADD COLUMN IF NOT EXISTS real_event TEXT
            """)
            cur.execute("""
                ALTER TABLE goal_advisories
                  ADD COLUMN IF NOT EXISTS settled BOOLEAN DEFAULT FALSE,
                  ADD COLUMN IF NOT EXISTS settled_at TIMESTAMPTZ,
                  ADD COLUMN IF NOT EXISTS ft_score TEXT,
                  ADD COLUMN IF NOT EXISTS ft_total INT,
                  ADD COLUMN IF NOT EXISTS outcome TEXT,
                  ADD COLUMN IF NOT EXISTS pnl_paper NUMERIC
            """)
            c.commit()


def boot_smoke_test() -> bool:
    test_id = f"BOOT_TEST_{int(time.time())}"
    try:
        with conn() as c:
            with c.cursor() as cur:
                cur.execute("""
                    INSERT INTO goal_alerts (
                        sent_at, strategy_id, alert_type, severity, fixture, action, full_text
                    ) VALUES (NOW(), %s, 'BOOT_TEST', 'INFO', 'Test v Test', 'BOOT', 'boot smoke test')
                    RETURNING id
                """, (test_id,))
                row_id = cur.fetchone()[0]
                cur.execute("DELETE FROM goal_alerts WHERE id = %s", (row_id,))
                c.commit()
        print(f"[BOOT TEST OK] goal_alerts INSERT/DELETE round-trip succeeded")
        return True
    except Exception as exc:
        msg = f"❌ <b>v11.3 boot smoke test FAILED</b>\n\n{type(exc).__name__}: {str(exc)[:300]}"
        send_telegram(msg)
        print(f"[BOOT TEST FAIL] {exc}")
        raise


def load_league_baselines():
    global _league_baselines
    try:
        with conn() as c:
            with c.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute("SELECT league, avg_total, n_matches FROM goal_league_baselines")
                _league_baselines = {}
                for r in cur.fetchall():
                    _league_baselines[r['league']] = float(r['avg_total'])
                    _league_baselines[f"_n_{r['league']}"] = r['n_matches']
        print(f"Loaded {len([k for k in _league_baselines if not k.startswith('_n_')])} league baselines")
    except Exception as exc:
        print(f"[BASELINE LOAD FAIL] {exc}")


def get_active_strategies() -> dict:
    with conn() as c:
        with c.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("""
                SELECT strategy_id, name, mode, target_market, side, stake_pct,
                       backtest_n, backtest_win_rate, backtest_roi_pct
                FROM goal_strategies
                WHERE mode IN ('LIVE', 'SHADOW')
            """)
            return {r['strategy_id']: dict(r) for r in cur.fetchall()}


def _real_touch_for(payload: dict, cur):
    """Real Betfair back/lay at alert time, or (None,)*4. Never raises."""
    if real_price is None:
        return None, None, None, None
    try:
        mkt, sel = real_price.market_for_action(payload.get('action'))
        fx = payload.get('fixture') or ''
        home, away = (fx.split(' v ', 1) + [''])[:2]
        r = real_price.guarded(cur, real_price.real_touch, home, away, mkt, sel)
        if not r:
            return None, None, None, None
        return r['back_px'], r['lay_px'], r['ts'], r['event_name']
    except Exception as exc:
        print(f"[REAL-PRICE FAIL] {exc}")
        return None, None, None, None


def write_alert(payload: dict) -> Optional[int]:
    try:
        with conn() as c:
            with c.cursor() as cur:
                rb, rl, rts, rev = _real_touch_for(payload, cur)
                if rb:
                    payload['target_price_min'] = round(rb * 0.97, 2)
                    payload['target_price_max'] = round(rb * 1.03, 2)
                cur.execute("""
                    INSERT INTO goal_alerts (
                        sent_at, strategy_id, alert_type, severity, fixture, minute, score, action,
                        target_price_min, target_price_max, stake_gbp, stop_loss_minute, green_up_target,
                        p_success, expected_value, full_text, user_action_taken,
                        real_price, real_lay_price, real_price_ts, real_event
                    ) VALUES (NOW(), %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, FALSE,
                              %s, %s, %s, %s)
                    RETURNING id
                """, (payload['strategy_id'], 'HT_TRIGGER', payload.get('severity', 'INFO'),
                      payload['fixture'], payload['minute'], payload['score'], payload['action'],
                      payload['target_price_min'], payload['target_price_max'], payload['stake_gbp'],
                      payload['stop_loss_minute'], payload['green_up_target'],
                      payload.get('p_success'), payload.get('expected_value'), payload['full_text'],
                      rb, rl, rts, rev))
                return cur.fetchone()[0]
    except Exception as exc:
        print(f"[ALERT WRITE FAIL] {exc} | payload={payload.get('strategy_id')} {payload.get('severity')}")
        global _last_api_error_telegram_ts
        if time.time() - _last_api_error_telegram_ts > 3600:
            send_telegram(f"⚠️ <b>Brain: ALERT WRITE FAILED</b>\n\n{type(exc).__name__}: {str(exc)[:300]}")
            _last_api_error_telegram_ts = time.time()
        return None


def write_advisory(payload: dict) -> Optional[int]:
    try:
```
## fired lines with the nearest timestamps in the log
```
813692:[GOAL-SIGNAL] live=19 candidates=15 fired=1 stats_calls=1
854534:[GOAL-SIGNAL] live=3 candidates=3 fired=2 stats_calls=1
854974:[GOAL-SIGNAL] live=12 candidates=8 fired=1 stats_calls=3
855511:[GOAL-SIGNAL] live=3 candidates=1 fired=1 stats_calls=1
855515:[GOAL-SIGNAL] live=3 candidates=1 fired=1 stats_calls=0
856162
855684:[SETTLE] Starting daily settlement at 2026-11-17 02:00:16.317071+00:00
855911:[GOAL-SIG] Running daily calibration for 2026-11-17
856144:[GOAL-SIG] Running daily calibration for 2026-11-17
```
## tables named in that code, freshness
```
goal_alerts sent_at last 2026-11-07 19:04:00.562343+00:00
goal_league_baselines last_refreshed last 2026-06-01 23:22:26.651354+00:00
goal_strategies no timestamp column / not a table
```
