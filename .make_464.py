src = open('/root/pe-queue/jobs/499_nogoal_move.sh').read()
reps = [
 ("# 499_nogoal_move (Finder 2026-11-08, queue item 463,",
  "# 499_nogoal_move_wide (Finder 2026-11-08, queue item 464: item 463's code, t0/t1 prints from the last 180 s, scored only on windows 463 could not price).\n# Built from 499_nogoal_move (queue item 463,"),
 ("                i0=last_in(tt,t0-60,t0); i1=last_in(tt,t1-60,t1)\n                if i0 is None or i1 is None: C[f'E{E} no print at t0 or t1']+=1; continue\n",
  "                seen=(last_in(tt,t0-60,t0) is not None) and (last_in(tt,t1-60,t1) is not None)\n                i0=last_in(tt,t0-180,t0); i1=last_in(tt,t1-180,t1)\n                if i0 is None or i1 is None: C[f'E{E} no print at t0 or t1 in 180 s']+=1; continue\n"),
 ("                rows.append(dict(e=e,t=t1,E=E,c=c,rl=rl,",
  "                rows.append(dict(e=e,t=t1,E=E,c=c,rl=rl,seen=seen,"),
 ("                C[f'{c} trades']+=1; nt+=1",
  "                C[f'{c} trades'+(' SEEN by 463' if seen else ' UNSEEN')]+=1; nt+=1"),
 ("T=pd.DataFrame(rows)\nif T.empty: print(\"\\n== SURVIVORS\\nnone (no trades)\"); sys.exit(0)\n",
  "TA=pd.DataFrame(rows)\nif TA.empty: print(\"\\n== SURVIVORS\\nnone (no trades)\"); sys.exit(0)\nT=TA[~TA.seen].copy()\nprint('ALL windows at 180 s',len(TA),'of which UNSEEN (scored)',len(T),flush=True)\n"),
 ("== ITEM 463, {len(O)} scored lines", "== ITEM 464 (UNSEEN windows only), {len(O)} scored lines"),
 ("R_=pd.DataFrame(r);",
  "for c in ('SH2','SH4'):\n    for nm,col in COLS: r.append(row(f'ALL 180 s {c} all windows {nm} (audit, overlaps 463)',TA[TA.c==c],col))\nR_=pd.DataFrame(r);"),
]
for a, b in reps:
    assert src.count(a) == 1, a[:60]
    src = src.replace(a, b)
open('/root/pe-queue/jobs/499_nogoal_move_wide.sh', 'w').write(src)
print('ok')
