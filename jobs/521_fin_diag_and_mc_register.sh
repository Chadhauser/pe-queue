#!/bin/bash
# 521: (1) the box's own state onto the scoreboard every 10 min (diag.txt: bot log tail, bot check, crontab, postgres, data dirs)
# so the chat never has to ask Peter to run commands to find out what happened. (2) 520's Monte Carlo registered as a Verifier
# hypothesis so its RESULT lines land in the scoreboard instead of only the runner log (my mistake in 520). (3) daemon restart so
# the oanda_fx/alpaca_crypto data-health lines and the bot section go live. (4) bot login check re-run, output into diag.txt.
cd /root/pe-fin/team || exit 1
cat > diag.sh <<'SH'
#!/bin/bash
D=/root/pe-fin/team/public/diag.txt; mkdir -p /root/pe-fin/team/public
{ echo "DIAG $(date -u +%Y-%m-%dT%H:%M) UTC"; echo; echo "## bot log (last 15)"; tail -15 /root/pe-fin/bot/orb_mnq.log 2>/dev/null || echo "(no bot log yet)"
  echo; echo "## bot cron.log (last 5)"; tail -5 /root/pe-fin/bot/cron.log 2>/dev/null; echo; echo "## bot trades"; cat /root/pe-fin/bot/bot_trades.json 2>/dev/null | head -40
  echo; echo "## last bot --check"; cat /root/pe-fin/bot/check.txt 2>/dev/null
  echo; echo "## crontab (fin lines)"; crontab -l 2>/dev/null | grep -E "pe-fin|paper_orb|oanda|crypto|orb_mnq"
  echo; echo "## postgres"; (systemctl is-active postgresql 2>/dev/null || pg_isready 2>/dev/null || echo unknown)
  echo; echo "## data on disk (months)"; for d in /root/pe-data/alpaca/QQQ /root/pe-data/alpaca/BTCUSD /root/pe-data/oanda/EUR_USD /root/pe-data/oanda/XAU_USD; do echo "$d: $(ls $d 2>/dev/null | wc -l) files, last $(ls $d 2>/dev/null | tail -1)"; done
  echo; echo "## daemon"; pgrep -af fin_team.py | head -2; echo; echo "## team.log tail"; tail -8 /root/pe-fin/team/team.log
  echo; echo "## oanda_pull.log tail"; tail -4 /root/pe-fin/oanda_pull.log 2>/dev/null; echo; echo "## crypto_pull.log tail"; tail -4 /root/pe-fin/crypto_pull.log 2>/dev/null
} > $D 2>&1
SH
chmod +x diag.sh
( crontab -l 2>/dev/null | grep -v diag.sh; echo "*/10 * * * * /root/pe-fin/team/diag.sh" ) | crontab -
cd /root/pe-fin/bot && (python3 orb_mnq_bot.py --check > check.txt 2>&1; echo "exit $?" >> check.txt); cat check.txt | tail -5
cd /root/pe-fin/team && python3 - <<'PY'
import json; reg=json.load(open('hypotheses.json')); have={h['id'] for h in reg['hypotheses']}
if 'MC Lucid 1-contract' not in have:
    reg['hypotheses'].append({"id":"MC Lucid 1-contract","script":"/root/pe-fin/team/mc_lucid.py","args":["37.6"],"status":"proposed","pre_registered_sign":"diagnostic: pass% at real 1-contract risk under Lucid 50K rules","next_door":"if pass <40%: price the 100K/150K tiers (deeper cushion) before any fee","timeout":1800})
json.dump(reg,open('hypotheses.json','w'),indent=1); print("MC registered")
PY
grep -q "control" mc_lucid.py || sed -i '1i # control: not applicable (Monte Carlo of a verified trade series, no direction to shuffle)' mc_lucid.py
pkill -f 'fin_team.py'; sleep 1; nohup /root/pe-fin/team/run_team.sh & disown; sleep 3; pgrep -f fin_team.py >/dev/null && echo "daemon restarted" || echo "DAEMON NOT RUNNING"
/root/pe-fin/team/diag.sh; /root/pe-fin/team/publish.sh; echo "diag published"; head -30 /root/pe-fin/team/public/diag.txt
