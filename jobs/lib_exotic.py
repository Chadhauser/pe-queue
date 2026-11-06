# lib_exotic (Finder 2026-11-06, items 266, 267): reading and settling the Sep 2026 markets with no official result. Read only, no secrets. Run directly for the known-answer checks.
import re
import pandas as pd
from lib_cand import norm,loose
from lib_official import secs,last_in
LO,HI='2026-09-01','2026-10-01'
def hc_home(mty):
    """TEAM_A_k gives the home side +k, TEAM_B_k gives it -k, read off the sample and checked against every printed runner in hc_ok."""
    m=re.fullmatch(r'TEAM_([AB])_(\d)',mty)
    return None if not m else (int(m[2]) if m[1]=='A' else -int(m[2]))
def hc_parse(sel,home,away):
    """'Leeds -1' -> ('H',-1) when Leeds is at home. None if the name is neither side or there is no handicap."""
    m=re.fullmatch(r'(.+) ([+-])(\d+)',str(sel).strip())
    if not m: return None
    k=int(m[3])*(1 if m[2]=='+' else -1)
    return ('H',k) if m[1]==home else ('A',k) if m[1]==away else None
def hc_ok(p,hh): return (p[0]=='H' and p[1]==hh) or (p[0]=='A' and p[1]==-hh)
def hc_won(role,k,sh,sa): return ((sh-sa) if role=='H' else (sa-sh))+k>0
def hc_draw_won(hh,sh,sa): return (sh-sa)+hh==0
def combo_parse(sel,home,away):
    """'Leeds/Over 2.5 Goals' -> ('H','over'); 'Draw/Yes' -> ('D','yes'). Splits on the last '/', as a team name may hold one."""
    a,x,b=str(sel).strip().rpartition('/')
    if not x: return None
    role='H' if a==home else 'A' if a==away else 'D' if a in ('Draw','The Draw') else None
    b=b.strip().lower(); part=next((w for w in ('yes','no','over','under') if b.startswith(w)),None)
    return (role,part) if role and part else None
def combo_won(role,part,sh,sa):
    o=(sh>sa) if role=='H' else (sa>sh) if role=='A' else (sh==sa)
    p=(sh>0 and sa>0) if part=='yes' else not (sh>0 and sa>0) if part=='no' else (sh+sa>=3) if part=='over' else (sh+sa<3)
    return bool(o and p)
def load(con,types,log=print):
    """(event name, off) -> {market type: {sel: (ts,px)}}. Non-in-play prints from T-20 only. Sep 2026 holds a game under two id forms (item 151), so one market per game per type, lowest id. Chunked by 5 days."""
    E={}; rows=0; seen={}
    days=pd.date_range(LO,HI,freq='5D',tz='UTC').tolist()+[pd.Timestamp(HI,tz='UTC')]
    for a,b in zip(days[:-1],days[1:]):
        if a>=b: continue
        P=pd.read_sql("SELECT market_id,event_name ev,market_type mty,market_time mt,sel,ts,ltp::float8 ltp FROM bf_hist_other WHERE sport='Soccer' AND market_type=ANY(%s) AND market_time>=%s AND market_time<%s AND NOT inplay AND ltp>=1.01 AND ltp<1000 AND ts>=market_time-interval '20 minutes'",con,params=(list(types),a.to_pydatetime(),b.to_pydatetime()))
        rows+=len(P); P['tt']=secs(P.ts); P['off']=secs(P.mt); P=P.sort_values('tt',kind='stable')
        for (ev,off,mty,mid),g in P.groupby(['ev','off','mty','market_id'],sort=True):
            if (ev,off,mty) in seen: continue
            seen[(ev,off,mty)]=mid; g=g.drop_duplicates(['sel','tt'])
            E.setdefault((ev,off),{})[mty]={s:(y.tt.values,y.ltp.values) for s,y in g.groupby('sel',sort=False)}
        log(f"  {a.date()} rows so far {rows:,}, games {len(E):,}",flush=True)
    return E
def scores(con):
    """The last goal_timeline row per fixture, minute 88+, no extra time, as item 167. Returns a function (event name, off) -> (home goals, away goals) or None, plus the row count."""
    GT=pd.read_sql("SELECT DISTINCT ON (fixture_id) fixture_id,home_team,away_team,captured_at,minute,score_home,score_away,status FROM goal_timeline WHERE captured_at>='2026-08-31' AND captured_at<'2026-10-03' AND score_home IS NOT NULL AND score_away IS NOT NULL ORDER BY fixture_id,captured_at DESC",con)
    GT['t']=secs(GT.captured_at); GT['mn']=pd.to_numeric(GT.minute,errors='coerce')
    GT=GT[(GT.mn>=88)&~GT.status.isin(['AET','PEN','ET'])].sort_values('t').reset_index(drop=True); GT['H']=GT.home_team.map(norm); GT['A']=GT.away_team.map(norm); tt=GT.t.values
    def f(ev,off):
        hm,_x,aw=ev.partition(' v '); lo,hi=tt.searchsorted(off),tt.searchsorted(off+14400)
        fx=loose(norm(hm),norm(aw),[(z.H,z.A,z.Index) for z in GT.iloc[lo:hi].itertuples()])
        return None if fx is None else (int(GT.score_home[fx]),int(GT.score_away[fx]))
    return f,len(GT)
def mo_fav(m,home,away,off):
    """'H' or 'A' from the last MO prints T-20 to T-2, exact names; None if not both priced, or level."""
    a,b=m.get(home),m.get(away)
    if a is None or b is None: return None
    i,j=last_in(a[0],off-1200,off-120),last_in(b[0],off-1200,off-120)
    if i is None or j is None or a[1][i]==b[1][j]: return None
    return 'H' if a[1][i]<b[1][j] else 'A'
def checks():
    assert hc_home('TEAM_A_1')==1 and hc_home('TEAM_B_3')==-3 and hc_home('MATCH_ODDS') is None
    assert hc_parse('Leeds -1','Leeds','Hull')==('H',-1) and hc_parse('Hull +2','Leeds','Hull')==('A',2) and hc_parse('Draw','Leeds','Hull') is None and hc_parse('Stoke +1','Leeds','Hull') is None
    assert hc_ok(('H',1),1) and hc_ok(('A',-1),1) and not hc_ok(('H',-1),1)
    # Home -1 at 2-0 wins, at 1-0 is the handicap draw, at 1-1 loses. Away +1 at 1-0 draws, at 1-1 wins.
    assert hc_won('H',-1,2,0) and not hc_won('H',-1,1,0) and hc_draw_won(-1,1,0) and not hc_won('H',-1,1,1)
    assert not hc_won('A',1,1,0) and hc_won('A',1,1,1) and not hc_draw_won(-1,1,1)
    assert combo_parse('Leeds/Over 2.5 Goals','Leeds','Hull')==('H','over') and combo_parse('Draw/Yes','Leeds','Hull')==('D','yes') and combo_parse('Brighton/Hove/No','Brighton/Hove','Hull')==('H','no') and combo_parse('Leeds','Leeds','Hull') is None
    assert combo_won('H','yes',2,1) and not combo_won('H','yes',2,0) and combo_won('H','no',2,0) and combo_won('D','no',0,0) and combo_won('D','yes',1,1) and combo_won('A','over',1,2) and not combo_won('A','over',0,2) and combo_won('A','under',0,2)
    assert abs(secs(pd.Series([pd.Timestamp('2026-09-01',tz='UTC')])).iloc[0]-1788220800)<1e-6
    return True
if __name__=='__main__':
    checks(); print("lib_exotic known-answer checks: OK")
