import re, subprocess, sys
# extract the rewrite pairs for item 465 and 450 from the new job, apply them, and py_compile the heredoc python
src = open('/root/pe-queue/jobs/499_oct22_rereads.sh').read()
def heredoc(text):
    m = re.search(r"<<'PY'[^\n]*\n(.*?)\nPY\n", text, re.S)
    return m.group(1)
jobs = {
 '499_nogoal_move_wide.sh': [("a=pd.Timestamp(2022,11,1)", "a=pd.Timestamp(2022,10,1)"),
                             ("while a<pd.Timestamp(2026,11,1):", "while a<pd.Timestamp(2022,11,1):")],
 '499_level_fav_dnb_unseen.sh': [("MONTHS=((2023,range(1,3)),)", "MONTHS=((2022,range(10,11)),)")],
}
# the 465 extra line, copied from the job text
m = re.search(r'"P_=O\[O.PASS==True\]" "(.*?)" \\\n', src)
extra = m.group(1)
jobs['499_nogoal_move_wide.sh'].append(("P_=O[O.PASS==True]", extra))
for j, pairs in jobs.items():
    t = open('/root/pe-queue/jobs/' + j).read()
    for a, b in pairs:
        assert t.count(a) >= 1, (j, a)
        t = t.replace(a, b)
    code = heredoc(t)
    compile(code, j, 'exec')
    print(j, 'compiles; pairs found', len(pairs))
print('extra line:', extra[:120])
