s=open('.diag472c.py').read()
old="while a<pd.Timestamp(2026,11,1):"
assert s.count(old)==1
s=s.replace(old,"while a<pd.Timestamp(2024,1,1):  # cut 9 Nov: Oct 2022-Dec 2023 only, 57 of the 87 GAP2 trades, to fit the run")
open('.diag472e.py','w').write("# .diag472e.py = .diag472c.py cut to Oct 2022-Dec 2023 (time only; rule unchanged), 9 Nov\n"+s)
print('ok')
