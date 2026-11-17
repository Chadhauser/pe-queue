# 633 — 2026-11-17 07:00 UTC
```
/root/pe-brain/repo/brain/active_positions.py:161:            f"   Open {age}min | Alerts fired: {flag_str}"
/root/pe-brain/repo/brain/calibrate_goal_model.py:173:            f"Alerts fired: {stats['alerts']}\n"
/root/pe-brain/repo/brain/copilot_app.py:10:state has fired in alerts_sent_jsonb. This app simply surfaces the instruction
/root/pe-brain/repo/brain/copilot_app.py:17:froze such cards at 45' so exits never fired. _effective_minute() now estimates
/root/pe-brain/repo/brain/copilot_app.py:22:app is THE output surface. Added /signals (fired goal signals with honest
/root/pe-brain/repo/brain/copilot_app.py:185:    fired = any(alerts.get(k) for k in ('status', 'warning', 'exit', 'green', 'broken'))
/root/pe-brain/repo/brain/copilot_app.py:186:    fresh = (elapsed <= 52) and not fired and total == (_parse_total(row.get('ht_score')) or total)
/root/pe-brain/repo/brain/copilot_app.py:726:                    'fired_at': d['captured_at'].isoformat() if d.get('captured_at') else None,
/root/pe-brain/repo/brain/copilot_app.py:836:    <span class="when">${when(s.fired_at)}</span></div>
/root/pe-brain/repo/brain/copilot_app.py:858:                          : '<div class="empty">No signals fired in the last 24h. They appear here the moment the brain fires one.</div>';
/root/pe-brain/repo/brain/copilot_v2.py:9:            machine has NOT fired — one plain-English reason why not.
/root/pe-brain/repo/brain/copilot_v2.py:21:  goal_live_predictions — what the machine saw and whether it fired
/root/pe-brain/repo/brain/copilot_v2.py:310:    """Best available match minute for a fired card."""
/root/pe-brain/repo/brain/copilot_v2.py:314:    fired_at = row.get('captured_at')
/root/pe-brain/repo/brain/copilot_v2.py:316:    if fired_at:
/root/pe-brain/repo/brain/copilot_v2.py:318:            mins = (datetime.now(timezone.utc) - fired_at).total_seconds() / 60.0
/root/pe-brain/repo/brain/copilot_v2.py:340:def _not_fired_reason(side, live, pred, fired_dirs, kicked_off):
/root/pe-brain/repo/brain/copilot_v2.py:344:    if fired_dirs:
/root/pe-brain/repo/brain/copilot_v2.py:393:            fired = {}
/root/pe-brain/repo/brain/copilot_v2.py:398:                    fired.setdefault(r['fixture_id'], []).append(d)
== /root/pe-brain/repo/brain/copilot_v2.py
line 
--- keys
goal_live_predictions [('PRIMARY KEY (id)',)]
  defaults [('id', "nextval('goal_live_predictions_id_seq'::regclass)"), ('captured_at', 'now()'), ('alert_sent', 'false'), ('settled', 'false')]
goal_advisories [('PRIMARY KEY (id)',)]
  defaults [('id', "nextval('goal_advisories_id_seq'::regclass)"), ('sent_at', 'now()'), ('settled', 'false'), ('promotion_eligible', 'false')]
goal_poisson [('PRIMARY KEY (id)',)]
  defaults [('id', "nextval('goal_poisson_id_seq'::regclass)"), ('sent_at', 'now()'), ('settled', 'false')]
goal_alerts [('PRIMARY KEY (id)',)]
  defaults [('id', "nextval('goal_alerts_id_seq'::regclass)"), ('sent_at', 'now()'), ('settled', 'false')]
```
