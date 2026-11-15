J = '/root/pe-queue/jobs/'
checks = {
 '499_pen_other_unseen.sh': ["A,B='2023-04-01','2026-10-01'"],
 '499_ht_identity_may23.sh': ["for y,m in [(2023,5)]:"],
 '499_ht_youth_may23.sh': ["for y,m in [(2023,5)]:"],
 '499_ht_cards_older.sh': ["A,B='2023-05-01','2023-08-01'"],
 '499_foul_draw_unseen.sh': ["WINS=(('2023-11-01','2024-08-01'),('2026-07-01','2026-10-01'))"],
 '499_script_run_unseen.sh': ["WINS=(('2023-11-01','2024-08-01'),('2026-07-01','2026-10-01'))"],
 '499_jump_up_delay.sh': ["for y,ms in ((2023,range(5,13)),(2024,range(1,12)),(2026,range(5,11))):", "MAY23", "ITEM 422 May 2023", "T.dt<pd.Timestamp('2023-06-01',tz='UTC')"],
}
for f, ss in checks.items():
    t = open(J + f).read()
    for s in ss:
        print(f, t.count(s), s[:50])
import re
t = open(J + '499_jump_up_delay.sh').read()
for l in t.split('\n'):
    if 'MAY23' in l or '2023-06-01' in l:
        print('  >', l.strip()[:200])
