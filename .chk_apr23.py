import re
J = '/root/pe-queue/jobs/'
OLD = "WINS=(('2023-11-01','2024-08-01'),('2026-07-01','2026-10-01'))"
NEW = "WINS=(('2023-04-01','2023-05-01'),)"
jobs = {
    '499_jump_up_delay.sh': [("for y,ms in ((2023,range(5,13)),(2024,range(1,12)),(2026,range(5,11))):", "for y,ms in ((2023,range(4,5)),):"),
                             ("T.dt<pd.Timestamp('2023-06-01',tz='UTC')", "T.dt<pd.Timestamp('2023-05-01',tz='UTC')"),
                             ("MAY23", "APR23"), ("ITEM 422 May 2023", "ITEM 422 April 2023")],
    '499_ht_identity_may23.sh': [("for y,m in [(2023,5)]:", "for y,m in [(2023,4)]:")],
    '499_ht_youth_may23.sh': [("for y,m in [(2023,5)]:", "for y,m in [(2023,4)]:")],
    '499_ht_cards_older.sh': [("A,B='2023-05-01','2023-08-01'", "A,B='2023-04-01','2023-05-01'")],
    '499_foul_draw_unseen.sh': [(OLD, NEW)],
    '499_script_run_unseen.sh': [(OLD, NEW)],
}
for f, pairs in jobs.items():
    t = open(J + f).read()
    for a, b in pairs:
        n = t.count(a)
        assert n >= 1, (f, a)
        t = t.replace(a, b)
        print(f, 'replaced', n, 'x', a[:50])
    m = re.search(r"<<'PY'[^\n]*\n(.*?)\nPY\n", t, re.S)
    compile(m.group(1), f, 'exec')
    left = [w for w in ('2023-06-01', 'range(5,13)', "(2023,5)", "'2023-08-01'", '2023-11-01', 'MAY23') if w in m.group(1)]
    print(f, 'compiles; old window text left:', left)
