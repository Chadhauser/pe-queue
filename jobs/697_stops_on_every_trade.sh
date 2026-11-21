#!/bin/bash
# 697 (Sat 21 Nov 2026 08:48, Peter: a trade exits when green and exits when it has lost an agreed percentage of the stake).
# Adds that to the brief of the waiting builder session (696) before it starts. Paper only. Nothing deleted.
F=/root/pe-builder/BRIEF_winners.md
[ -f "$F" ] || { echo "brief not there yet"; exit 75; }
grep -q "STOP ON EVERY TRADE" "$F" || cat >> "$F" <<'ADD'
STOP ON EVERY TRADE (Peter, 21 Nov, not optional): a trade has three exits fixed before it goes on - a target (out when it is green by a set amount), a stop (out when it has lost an agreed percentage of the stake) and a time limit. In step 4 run every surviving condition with stops of 5%, 10% and 20% of the stake and targets of the same sizes and double, each as its own row, the stop filled at the real price on offer when it is hit (never at the stop level itself; if the market is suspended the stop fills at the first real price after it reopens - show how often that happened and what it cost). Also add the same stop-and-target versions of every in-and-out way already on paper (they have a time exit only) as new rows. From now on nothing new goes onto paper without a stop. In the handover say which stop and target made the most on the unseen days.
ADD
echo "stop rule in the brief: $(grep -c 'STOP ON EVERY TRADE' $F)"
