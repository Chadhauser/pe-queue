#!/bin/bash
# 701 (Sat 21 Nov 2026 11:25, Peter: "Lay is my least favourite especially at long shots"). Adds his preference to the waiting
# losses brief before it starts. Paper only. Nothing deleted.
F=/root/pe-builder/BRIEF_losses.md
[ -f "$F" ] || { echo "brief not there yet"; exit 75; }
grep -q "PETER DOES NOT WANT TO LAY LONG SHOTS" "$F" || cat >> "$F" <<'ADD'
PETER DOES NOT WANT TO LAY LONG SHOTS (21 Nov 11:25, overrides the 'long shots' bullet above): do NOT build or propose rules that lay a selection priced 5.0 or longer. Express the same finding from the BACK side instead: if outsiders are overpriced by the crowd, then the shorter-priced runners and teams in the same markets are underpriced - test BACKING the favourite and the second favourite (and backing the short side in two-way markets) at the same moments, as trades with a target, a stop and a time limit, and held, each price band its own row. Wherever a result can be reached by a back or by a lay, show the back version first. Lays are allowed only at prices under 3.0 (where the money at risk is less than twice the stake) and must be labelled 'lay' in the sentence. 'Offering prices' and 'being the exit' stay in, but only the BACK-side orders at 5.0 or longer; no resting lays on long shots. Also, small change to /root/pe-sports/grid/bankbook.py (back it up first, add a hand-worked check): the bank book skips any lay at 5.0 or longer and counts it as skipped; the full paper record is unchanged. Say in the page how much of the bank book's result that changes.
ADD
echo "preference in the brief: $(grep -c 'PETER DOES NOT WANT TO LAY LONG SHOTS' $F)"
