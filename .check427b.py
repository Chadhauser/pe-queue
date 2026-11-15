import sys, glob, re
sys.path.insert(0, 'runner')
import creds, psycopg2
c = psycopg2.connect(creds.pg_local())
k = c.cursor()
k.execute("""select count(*) from fd_matches where season='2627' and div='G1' and date<'2026-08-23' and fthg is not null
             and (home in ('OFI Crete','Volos NFC') or away in ('OFI Crete','Volos NFC'))""")
print('OFI or Volos games before 23 Aug 2026:', k.fetchone()[0])
k.execute("select div,season from fd_matches where date='2026-08-23' and home='OFI Crete'")
print(k.fetchall())
n = [int(re.search(r'jobs/(\d+)', f).group(1)) for f in glob.glob('jobs/4[5-9]*')]
print('numbers used 450-498:', len(set(x for x in n if 450 <= x <= 498)), 'of 49; free:', sorted(set(range(450, 499)) - set(n))[:12])
