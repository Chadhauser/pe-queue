# fin/ — the financial-trading chat's segregated lane (16 Nov 2026)

The shared runner only runs `jobs/*.sh`, so nothing in this folder runs on the server until `DEPLOY.sh` is executed once.

- `runner/fin_runner.sh` — own queue (`fin/jobs/*.sh`), own clone (`/root/pe-finq/repo`), nice 19 + ionice idle, 30-minute cap per job, stops under 25 GB free disk, `unset GITHUB_TOKEN` before pushing. Reports go to `fin/reports/`.
- `bots/tick.py` — Alpaca PAPER bots run as one short tick per minute: ORB on QQQ, last-hour momentum (M7B) on QQQM, K2 small-cap gap fade, K4 small-cap 5-day reversal. Paper endpoint only. No new entries under 25 GB free disk or if `/root/pe-finq/state/KILL` exists.
- `bots/test_tick.py` — offline test against a fake broker (19 worked examples). It must pass before deploy.
- `DEPLOY.sh` — refuses to run until `reports/post_upgrade.md` exists and free disk is at least 25 GB.
- Never on this box: Wine, MetaTrader, the team research loop, or data pulls (those need Peter's go-ahead).
- Real money: never without Peter's yes in chat.
