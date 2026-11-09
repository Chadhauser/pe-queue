#!/bin/bash
set -o pipefail
# 499_aug22_rereads (Finder 2026-11-09, 04:05 UTC run, lane A): items 448, 450 and 465 on August 2022, a month no read has used in full (451 closed, kept for the record)
# (Soccer 2022-08 on the loader: run only once bf_hist_months shows it DONE; Aug 2022 is the oldest month on the box, so any item needing earlier games has a burn-in and may read n near 0).
# Copy of jobs/499_sep22_rereads.sh with only the month changed (9 -> 8, September -> August labels); each child job runs unchanged except its month list and labels.
# Item 465: jobs/499_nogoal_move_wide.sh (item 464's code, unchanged) with the window cut to Aug 2022 and the same added scored line as the Oct and Sep reads:
# SH4 back HOLD, thin books (windows item 463 could not price), ONE bet a game (earliest qualifying window), official result, never dropped.
# Item 445 is not here: jobs/499_jump_down_lay.sh already reads every month from Aug 2022 and is re-run unchanged.
# Read only, no tables written. One month cannot reach n 300: interim reads, n stated, pooled with earlier unseen months in the report.
rewrite() {
  python3 - "$@" <<'PY'
import sys
t=open(sys.argv[1]).read()
pairs=sys.argv[2:]
assert len(pairs)%2==0
for a,b in zip(pairs[0::2],pairs[1::2]):
    assert t.count(a)>=1, "window text not found in "+sys.argv[1]+": "+a
    t=t.replace(a,b)
print(t)
PY
}
J=/root/pe-queue/jobs
echo "== ITEM 451 (jump-up FAV E1), Aug 2022 only"
rewrite $J/499_jump_up_fav_unseen.sh \
  "for y,ms in ((2023,range(1,2)),):" "for y,ms in ((2022,range(8,9)),):" \
  "January 2023 only" "August 2022 only" \
  "Jan 2023" "Aug 2022" \
  | bash || echo "ERROR: item 451 Aug 2022 failed"
echo "== ITEM 448 (N1 G2 NOT_LEVEL lay Under), Aug 2022 only"
rewrite $J/499_ht_two_up_lay.sh \
  "for y,ms in ((2023,range(1,3)),):" "for y,ms in ((2022,range(8,9)),):" \
  "Jan and Feb 2023" "Aug 2022" \
  "Jan-Feb 2023" "Aug 2022" \
  | bash || echo "ERROR: item 448 Aug 2022 failed"
echo "== ITEM 450 (level-score FAV DNB back), Aug 2022 only"
rewrite $J/499_level_fav_dnb_unseen.sh \
  "MONTHS=((2023,range(1,3)),)" "MONTHS=((2022,range(8,9)),)" \
  "ITEM 450, Jan-Feb 2023" "ITEM 450, Aug 2022" \
  | bash || echo "ERROR: item 450 Aug 2022 failed"
echo "== ITEM 465 (thin-book SH4 back HOLD, one a game), Aug 2022 only"
rewrite $J/499_nogoal_move_wide.sh \
  "a=pd.Timestamp(2022,11,1)" "a=pd.Timestamp(2022,8,1)" \
  "while a<pd.Timestamp(2026,11,1):" "while a<pd.Timestamp(2022,9,1):" \
  "P_=O[O.PASS==True]" "S4=T[T.c=='SH4'].sort_values('t',kind='stable').drop_duplicates('e'); print('\n== ITEM 465 Aug 2022 scored: SH4 back HOLD, one bet a game (earliest window), thin books'); print(row('SH4 back HOLD one a game *',S4,'rb')); print(row('SH4 E85 back HOLD (reading)',T[(T.c=='SH4')&(T.E==85)],'rb')); print('SH4 games',S4.e.nunique(),'by window',S4.groupby('E').size().to_dict()); P_=O[O.PASS==True]" \
  | bash || echo "ERROR: item 465 Aug 2022 failed"
echo "== SURVIVORS: none can pass on one month (n under 300 by construction); interim reads only, pooled with earlier unseen months in the report"
