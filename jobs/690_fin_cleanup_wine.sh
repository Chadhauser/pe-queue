#!/bin/bash
# 690: cleanup only (Peter's handover 16 Nov 14:47: "/root/.mt5wine can go", no Wine/MT5 on this box). Removes the Wine prefix,
# any WineHQ packages/sources, the Xvfb screen and MT5 leftovers. Keeps /root/pe-data. Starts nothing. Numbered 690 so it never
# jumps the sports chat's 600s jobs. Runs in seconds.
O=/root/pe-fin/team/public/cleanup.txt; mkdir -p $(dirname $O)
{ echo "690 $(date -u +%FT%H:%M) UTC"; df -h / | tail -1
pkill -f mt5_bridge.py; pkill -f terminal64.exe; WINEPREFIX=/root/.mt5wine wineserver -k 2>/dev/null; pkill -f "Xvfb :99"
rm -rf /root/.mt5wine /root/pe-fin/mt5/*.exe /root/pe-fin/mt5/pyembed.zip /root/pe-fin/mt5/login.ini
DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq winehq-staging wine-staging wine-staging-amd64 wine-staging-i386 >/dev/null 2>&1
rm -f /etc/apt/sources.list.d/winehq-*.sources; apt-get clean
echo "wine left: $(command -v wine || echo none) | .mt5wine: $([ -d /root/.mt5wine ] && echo PRESENT || echo gone)"
echo "fin processes: $(pgrep -af 'pe-fin|mt5|terminal64|wine' | grep -v pgrep | wc -l) | fin cron lines: $(crontab -l | grep -cE '/root/pe-fin/|mt5')"
df -h / | tail -1; echo "DONE 690"; } > $O 2>&1
unset GITHUB_TOKEN; /root/pe-fin/team/publish.sh >/dev/null 2>&1; cat $O
