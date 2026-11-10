#!/bin/bash
# 551 (Tue 10 Nov 2026, 13:50). THE DESK, UN-PAUSED AND DATA-LED (Peter: "test more... stop making excuses").
# The in-play fair-price map (H1b: minute band x probability band, seven years, official results) already exists. Its cells are too thin
# for the bot's bar but good enough to CALL for a human at £2: the Verifier writes fair_price_passed_inplay from it at a lower bar
# (n_is>=100, n_oos>=50, same-sign error both halves, |error|>=1pt/0.5pt, fair factor 0.7-1.3). The desk watches the live in-play tape
# every 20 s; when a runner's price sits in a passed in-play cell at that minute, it writes the CLICK line (take the available price, hold
# to full time — exactly how the map scored it) to calls/<date>.md on GitHub, plus the FADE and HT11 lines already built. Every call is
# scored against the final score whether Peter clicks or not. Runs from tonight; Peter sits with it when he can.
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
cd /root/pe-sports/team && cat > verifier_cells_inplay.py <<'PY'
# verifier_cells_inplay (551): the ONLY writer of fair_price_passed_inplay — in-play cells for the DESK at the desk's bar (lower than the bot's).
import sys, datetime, psycopg2
sys.path.insert(0,'/root/pe-queue/runner'); import creds
con=psycopg2.connect(creds.pg_local(),sslmode='disable'); con.autocommit=True; c=con.cursor()
c.execute("""CREATE TABLE IF NOT EXISTS fair_price_passed_inplay (market_type TEXT, minute_lo INT, minute_hi INT, band_lo NUMERIC, band_hi NUMERIC, side TEXT, fair_factor NUMERIC,
  n_is INT, n_oos INT, edge_is NUMERIC, edge_oos NUMERIC, passed_at TIMESTAMPTZ DEFAULT now(), PRIMARY KEY (market_type, minute_lo, band_lo))""")
MB={1:(1,15),2:(16,30),3:(31,45),4:(46,60),5:(61,75),6:(76,90)}
c.execute("SELECT market_type, band, band_lo, band_hi, fair_factor, n_is, n_oos, rate_is-p_mean_is, rate_oos-p_mean_oos FROM fair_price_calib_inplay WHERE n_is>=100 AND n_oos>=50 AND rate_oos IS NOT NULL")
rows=c.fetchall(); c.execute("DELETE FROM fair_price_passed_inplay"); n=0
for mt,b,lo,hi,f,nis,noos,eis,eoos in rows:
    mb=int(b)//100
    if mb not in MB or f is None or not (0.7<=float(f)<=1.3) or eis is None or eoos is None: continue
    if (eis>0)==(eoos>0) and abs(eis)>=0.01 and abs(eoos)>=0.005:
        c.execute("INSERT INTO fair_price_passed_inplay VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,now())",(mt,MB[mb][0],MB[mb][1],lo,hi,'BACK' if eis>0 else 'LAY',f,nis,noos,round(float(eis),4),round(float(eoos),4))); n+=1
c.execute("SELECT market_type, minute_lo, minute_hi, band_lo, band_hi, side, n_is, edge_is, edge_oos FROM fair_price_passed_inplay ORDER BY 1,2,4")
print(f"{datetime.datetime.utcnow():%Y-%m-%d %H:%M} in-play desk cells: {n}"); [print("  ",r) for r in c.fetchall()]
PY
python3 -m py_compile verifier_cells_inplay.py && python3 verifier_cells_inplay.py | head -40
( crontab -l 2>/dev/null | grep -v 'verifier_cells_inplay.py'; echo "*/30 * * * * /usr/bin/python3 /root/pe-sports/team/verifier_cells_inplay.py >> /root/pe-sports/team/verifier_cells_inplay.log 2>&1" ) | crontab -
echo "== desk: add the CELL line =="
cd /root/pe-sports/desk && cp desk.py desk.py.bak_551 && python3 - <<'PY'
p='/root/pe-sports/desk/desk.py'; s=open(p).read()
assert 'CELL' not in s
# helpers
s=s.replace("seen_goals=set(); seen_ht=set()","""seen_goals=set(); seen_ht=set(); seen_cell=set(); CELLS=[]; CELLS_T=0
MTYPE={'MO':'MATCH_ODDS','OU15':'OVER_UNDER_15','OU25':'OVER_UNDER_25','OU35':'OVER_UNDER_35','OU05':'OVER_UNDER_05','OU45':'OVER_UNDER_45','BTTS':'BOTH_TEAMS_TO_SCORE'}
def load_cells():
    lc.execute("SELECT market_type, minute_lo, minute_hi, band_lo, band_hi, side, fair_factor FROM fair_price_passed_inplay"); return [(a,int(b),int(c),float(d),float(e),f,float(g)) for a,b,c,d,e,f,g in lc.fetchall()]
def cell_hit(mt,minute,p):
    for m,lo,hi,blo,bhi,side,f in CELLS:
        if m==mt and lo<=minute<=hi and blo<=p<bhi: return side,f
    return None,None
def settle_cell(mkt,sel,gh,ga):
    tot=gh+ga
    if mkt=='MO': w={'HOME':gh>ga,'AWAY':ga>gh,'DRAW':gh==ga}.get(sel)
    elif mkt.startswith('OU'): line=int(mkt[2:])/10; w=(tot>line) if sel=='OVER' else (tot<line)
    elif mkt=='BTTS': w=(gh>0 and ga>0) if sel in ('YES','Yes') else not (gh>0 and ga>0)
    else: w=None
    return w""",1)
# the CELL scan, inserted before the HT11 block
anchor="        # ---- HT11: half-time 1-1 on the live scores -> back Over 2.5 on the tape"
block='''        # ---- CELL (551): in-play fair-price cells at this minute -> take the available price, hold to FT
        if time.time()-CELLS_T>600: CELLS=load_cells(); CELLS_T=time.time()
        if CELLS:
            tc.execute("""WITH last AS (SELECT market_id, max(ts) ts FROM liq_sample WHERE ts>now()-interval '90 seconds' GROUP BY 1)
                          SELECT s.market_id, s.event_name, s.mkt, s.sel, s.minute, s.ltp, s.back_px, s.lay_px, s.back_sz, s.lay_sz FROM liq_sample s JOIN last USING (market_id, ts) WHERE s.ts>now()-interval '90 seconds' AND s.minute IS NOT NULL""")
            bym={}
            for mid,ev,mkt,sel,minute,ltp,bp,lp,bs,ls in tc.fetchall(): bym.setdefault(mid,[]).append((ev,mkt,sel,int(minute or 0),float(ltp or 0),float(bp or 0),float(lp or 0),float(bs or 0),float(ls or 0)))
            for mid,rs in bym.items():
                mt=MTYPE.get(rs[0][1]);
                if not mt or len(rs)<2: continue
                tot=sum(1/r[4] for r in rs if r[4]>1)
                if tot<=0: continue
                for ev,mkt,sel,minute,ltp,bp,lp,bs,ls in rs:
                    if ltp<=1 or (mid,sel) in seen_cell or minute<1 or minute>90: continue
                    p=(1/ltp)/tot; side,f=cell_hit(mt,minute,p)
                    if side is None: continue
                    fair=1/max(0.005,min(0.995,p*f))
                    px=bp if side=='BACK' else lp
                    if px<=1 or (side=='BACK' and px<=fair) or (side=='LAY' and px>=fair) or (bs if side=='BACK' else ls)<10: continue
                    seen_cell.add((mid,sel)); lv=live_for(ev); team=sel
                    if sel in ('HOME','AWAY') and lv: team=lv['home'] if sel=='HOME' else lv['away']
                    lc.execute("INSERT INTO desk_calls (day,line,market_id,event_name,mkt,sel,side,price,stake,exit_rule,note) VALUES (current_date,'CELL',%s,%s,%s,%s,%s,%s,%s,'hold to full time',%s)",(mid,ev,mkt,sel,side,px,STAKE,f"min {minute} p {p:.3f} fair {fair:.2f}"+(f" af fixture {lv['fid']}" if lv else "")))
                    write(f"- **{now:%H:%M} {ev} ({minute}') — CELL. CLICK: {side} {team if mkt=='MO' else sel+' '+mkt} at {px:.2f}, £{STAKE:.0f}.** EXIT: none, hold to full time. Why: at minute {minute} the market rates this {p:.0%}; seven years of results say {1/fair:.0%} — fair {fair:.2f}.")
        # ---- CELL settlement from the final score
        lc.execute("SELECT id, event_name, mkt, sel, side, price, note FROM desk_calls WHERE line='CELL' AND status='open' AND ts<now()-interval '40 minutes'")
        for cid,ev,mkt,sel,side,price,note in lc.fetchall():
            fid=re.search(r'af fixture (\\d+)',note or '')
            lv=None
            if fid:
                try: lv=requests.get(f"https://v3.football.api-sports.io/fixtures?id={fid.group(1)}",headers={"x-apisports-key":AF_KEY},timeout=20).json()['response'][0]
                except Exception: lv=None
            if not lv:
                lc.execute("UPDATE desk_calls SET status='unsettleable', note=coalesce(note,'')||' | no fixture match' WHERE id=%s AND ts<now()-interval '4 hours'",(cid,)); continue
            if lv['fixture']['status']['short'] not in ('FT','AET','PEN'): continue
            gh,ga=lv['goals']['home'] or 0,lv['goals']['away'] or 0; w=settle_cell(mkt,sel,gh,ga)
            if w is None: lc.execute("UPDATE desk_calls SET status='unsettleable' WHERE id=%s",(cid,)); continue
            price=float(price); won=w if side=='BACK' else (not w)
            pnl=((price-1)*STAKE*(1-COMM) if won else -STAKE) if side=='BACK' else (STAKE*(1-COMM) if won else -(price-1)*STAKE)
            lc.execute("UPDATE desk_calls SET status='settled', exit_ts=now(), result=%s, pnl=%s WHERE id=%s",('WIN' if won else 'LOSS',round(pnl,2),cid))
            write(f"- {now:%H:%M} {ev} — CELL settled: FT {gh}-{ga}, {'WIN' if won else 'LOSS'} {'+' if pnl>=0 else ''}£{pnl:.2f}.")
'''
assert s.count(anchor)==1; s=s.replace(anchor,block+anchor)
s=s.replace("Lines today: FADE (lay the scorer at +2 min, back out at +10 min) · HT11 (1-1 at half-time, back Over 2.5, hold).","Lines today: CELL (in-play fair-price cells, take and hold) · FADE (lay the scorer at +2 min, back out at +10 min) · HT11 (1-1 at half-time, back Over 2.5, hold).")
open(p,'w').write(s); print("desk: CELL line added")
PY
python3 -m py_compile desk.py && echo "desk compiles" || { cp desk.py.bak_551 desk.py; echo RESTORED; exit 1; }
rm -f /root/pe-sports/STOPPED /root/pe-sports/desk/STOPPED
( crontab -l 2>/dev/null | sed 's/^#PAUSED-543 \(.*run_desk.sh.*\)$/\1/' ) | crontab -; crontab -l | grep -c run_desk && echo "desk keepalive restored"
pkill -f desk.py; sleep 2; nohup /root/pe-sports/desk/run_desk.sh >/dev/null 2>&1 & disown
sleep 45; echo "desk pids: $(pgrep -f desk.py | wc -l)"; tail -3 /root/pe-sports/desk/desk.log
# the scoreboard settled table gets the CELL line
python3 - <<'PY'
p='/root/pe-sports/team/sports_team.py'; s=open(p).read()
a="    add('desk FADE (lay scorer +2m, out +10m)'"
if "desk CELL" not in s and a in s:
    s=s.replace(a,"    add('desk CELL (in-play cells, take and hold)',\"select count(*), coalesce(sum(stake),0), coalesce(sum(pnl),0), count(*) filter (where exit_ts>now()-interval '7 days'), coalesce(sum(pnl) filter (where exit_ts>now()-interval '7 days'),0) from desk_calls where line='CELL' and status='settled'\")\n"+a,1); open(p,'w').write(s); print("scoreboard: desk CELL line")
PY
python3 -m py_compile /root/pe-sports/team/sports_team.py && pkill -f sports_team.py; sleep 2; nohup /root/pe-sports/team/run_team.sh >/dev/null 2>&1 & disown
echo "551 done — desk live from now: CELL + FADE + HT11, calls/<date>.md"
