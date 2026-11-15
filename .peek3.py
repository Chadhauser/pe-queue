import sys, psycopg2, pandas as pd
sys.path.insert(0, '/root/pe-queue/runner'); import creds
pd.set_option('display.width', 200); pd.set_option('display.max_rows', 80)
rc = psycopg2.connect(creds.pg_railway(), sslmode='require', connect_timeout=30)
CM = pd.read_sql("SELECT * FROM cricket_matches WHERE match_date>='2024-08-25'", rc); rc.close()
print(len(CM), list(CM.columns), CM.match_date.min(), CM.match_date.max())
print(CM.competition.value_counts().head(40).to_string())
w = CM[CM.competition.astype(str).str.contains('wom|WBBL|WPL', case=False) | CM.team1.astype(str).str.contains(r'\bW(omen)?\b')]
print('women rows', len(w)); print(w[['match_date', 'team1', 'team2', 'winner', 'competition']].head(12).to_string())
