import sys, psycopg2
sys.path.insert(0, '/root/pe-queue/runner'); import creds
con = psycopg2.connect(creds.pg_local()); cur = con.cursor()
for t in ('racing_bsp', 'fd_matches'):
    cur.execute("SELECT column_name,data_type FROM information_schema.columns WHERE table_name=%s ORDER BY ordinal_position", (t,))
    print(t, cur.fetchall())
cur.execute("SELECT event_name,menu_hint,market,event_dt,selection_id,selection_name FROM racing_bsp WHERE market='win' ORDER BY event_dt DESC LIMIT 6") if False else None
cur.execute("SELECT * FROM racing_bsp WHERE market='win' ORDER BY event_dt DESC LIMIT 3")
print([d[0] for d in cur.description])
for r in cur.fetchall(): print(r)
cur.execute("SELECT count(*),min(event_dt),max(event_dt),count(DISTINCT event_id) FROM racing_bsp WHERE market='win'"); print(cur.fetchall())
cur.execute("SELECT * FROM fd_matches LIMIT 1"); print(cur.fetchall()[0][:40])
cur.execute("SELECT count(*) FROM fd_matches"); print(cur.fetchall())
