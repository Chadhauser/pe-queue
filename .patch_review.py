def sub(p, old, new):
    s = open(p).read()
    assert old in s, old[:50]
    open(p, 'w').write(s.replace(old, new))

# payday: country holds lower-case 'uk', so the GB filter silently passed Ireland as well
sub('/root/pe-queue/jobs/499_payday.sh.wip',
    "W=W[W.country.isin(['GB','UK','GBR'])] if W.country.isin(['GB','UK','GBR']).any() else W\n",
    "W=W[W.country=='uk'].copy(); assert len(W) and set(W.country)=={'uk'}   # review fix: the first filter tested upper-case names against 'uk' and let Ireland through\n")

# last race: the tested helper was not the code in use
sub('/root/pe-queue/jobs/499_last_race.sh.wip',
    '''def card_state(ts_list,t):
    """times of one meeting's races, one race's time: its place on the card."""
    s=sorted(set(ts_list))
    return 'FIRST' if t==s[0] else 'LAST_MEET' if t==s[-1] else 'MID'
''',
    '''def card_states(M):
    """M has course, day, t: FIRST, LAST_MEET or MID per row, and the last race anywhere that day."""
    first=M.groupby(['course','day']).t.transform('min'); last=M.groupby(['course','day']).t.transform('max')
    return np.where(M.t==first,'FIRST',np.where(M.t==last,'LAST_MEET','MID')),M.t==M.groupby('day').t.transform('max')
''')
sub('/root/pe-queue/jobs/499_last_race.sh.wip',
    "assert card_state([1,2,3,3,4,5],1)=='FIRST' and card_state([1,2,3,4,5],5)=='LAST_MEET' and card_state([1,2,3,4,5],3)=='MID'\n",
    "_m=pd.DataFrame(dict(course=['a']*3+['b']*2,day=[1]*5,t=[1.,2.,3.,2.5,4.])); _s,_l=card_states(_m); assert list(_s)==['FIRST','MID','LAST_MEET','FIRST','LAST_MEET'] and list(_l)==[False,False,False,False,True]\n")
sub('/root/pe-queue/jobs/499_last_race.sh.wip',
    """M['st']=M.groupby(['course','day']).t.transform(lambda s:0)  # placeholder overwritten below
first=M.groupby(['course','day']).t.transform('min'); last=M.groupby(['course','day']).t.transform('max'); M['st']=np.where(M.t==first,'FIRST',np.where(M.t==last,'LAST_MEET','MID'))
lastday=M.groupby('day').t.transform('max'); M['lastday']=M.t==lastday
""",
    "M['st'],M['lastday']=card_states(M)\n")

# corner lines: no official results exist, so stop cleanly and say so
sub('/root/pe-queue/jobs/499_corner_lines.sh.wip',
    'TY=cur.fetchall(); print("official results by type",TY,flush=True); types=[t for t,_ in TY]\n',
    'TY=cur.fetchall(); print("official results by type",TY,flush=True); types=[t for t,_ in TY]\nif not types: print("\\n== SURVIVORS: none; BLOCKED, bf_hist_result holds none of these market types, no price read"); sys.exit(0)\n')
print('ok')
