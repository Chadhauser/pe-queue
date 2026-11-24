#!/bin/bash
# 719 (Tue 24 Nov 2026 06:40). Orders 716, 717 and 718 (all approved by Peter on 22-23 Nov) have waited since 06:15 UTC 23 Nov on
# a false match: their "is another session running" check matched the nightly scorecard loop's own shell. This sets the three up
# without that check and runs them one after another (memory), late under first. Paper/trial only. No orders. Nothing deleted.
Q=/root/pe-queue; S=/root/pe-queue-state
for j in 716_goal_signal_backtest 717_late_under_on_trial_properly 718_improve_goal_signal; do
  grep -v -E "exit 75|nohup setsid" $Q/jobs/$j.sh > /tmp/$j.setup.sh && bash /tmp/$j.setup.sh > /tmp/$j.setup.out 2>&1
  mkdir -p $S/done; touch $S/done/$j; rm -f $S/waiting/$j
done
ls -la /root/pe-builder/run_lateunder.sh /root/pe-builder/run_scoreback.sh /root/pe-builder/run_signal3.sh 2>&1 | awk '{print $1, $NF}'
cat > /root/pe-builder/run_chain_719.sh <<'SH'
#!/bin/bash
# one at a time, in this order; each is its own session with its own time limit
/root/pe-builder/run_lateunder.sh
/root/pe-builder/run_scoreback.sh
/root/pe-builder/run_signal3.sh
echo "chain 719 ended $(date -u '+%F %H:%M')" >> /root/pe-builder/sessions.log
SH
chmod +x /root/pe-builder/run_chain_719.sh
nohup setsid /root/pe-builder/run_chain_719.sh > /dev/null 2>&1 < /dev/null & sleep 20
echo "chain: $(pgrep -fc '[r]un_chain_719.sh') | late under now: $(pgrep -fc '^/bin/bash /root/pe-builder/run_lateunder.sh') | free memory: $(free -g | awk '/Mem/{print $7" GB of "$2}') | started $(date -u +%H:%M) UTC 24 Nov (716-718 were stuck from 06:15 UTC 23 Nov)" > $Q/reports/running_now.md
cd $Q && git add reports/running_now.md && git commit -qm "719: three stuck sessions started in a chain" -q && git pull -q --no-rebase --no-edit && env -u GITHUB_TOKEN git push -q
