import sys,psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
c=psycopg2.connect(creds.pg_local()); k=c.cursor()
k.execute("SELECT column_name,data_type FROM information_schema.columns WHERE table_name='finder_tlog' ORDER BY ordinal_position"); print([f"{a}:{b[:6]}" for a,b in k.fetchall()])
k.execute("SELECT indexname,indexdef FROM pg_indexes WHERE tablename='finder_tlog'"); print(k.fetchall())
k.execute("SELECT min(captured_at),max(captured_at) FROM finder_tlog"); print(k.fetchone())
k.execute("SELECT * FROM finder_tlog LIMIT 1"); print([str(x)[:30] for x in k.fetchone()])
