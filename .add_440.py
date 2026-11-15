p='watchman/FINDER_QUEUE.md'
t=open(p).read()
assert '\n440. ' not in t
line=("440. BLOCKED 2026-11-08 — no manager or coach on the box: af_fixtures holds referee only, af_lineups formation and players only, no table has a coach column; "
"needs API-Football /coachs (career start and end dates per team) loaded by the loader, not Finder, as the brief forbids downloads "
"(Finder's own, source b, the published new-manager bounce; ledger and queue searched for manager, sacked, new manager, bounce: none on football) "
"**New-manager bounce at the first in-play print.** Rationale: a sacking is public news and the crowd may back the first games under a new manager; "
"the market may already price it, so it needs a test. Rule to fix once the data is held: a team's first 1, 3 and 5 league games under a new permanent or interim coach, "
"back and lay its Match Odds at the first in-play print in tape minutes 0..2 with the guards of jobs/499_team_form_stage.sh, to the result, 2%, GBP 10; seasons 2024 v 2025; "
"control every side in the same price bands.\n")
i=t.index('\n439. '); j=t.index('\n',i+1)
t=t[:j+1]+line+t[j+1:]
open(p,'w').write(t); print('ok')
