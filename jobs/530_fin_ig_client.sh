#!/bin/bash
# 530: Saturday-build item 6 — IG spread betting (tax-free venue for an individual). ig_client.py (login, search, open with
# stop/limit distances, positions, close) on the DEMO endpoint; live only if IG_ENV=live AND IG_ALLOW_LIVE=1 are both set (tested:
# IG_ENV=live alone stays on demo). ig_cost_probe.py: read-only, three times a day records IG's quoted spread on US Tech 100,
# US 500, Russell 2000 and 40 random names from the small-cap universe, and whether each is listed as a daily funded bet ->
# scoreboard/ig_costs.md. That table decides which crumbs can move to IG. Tested offline against a fake IG: auth headers, open +
# confirm, close via _method DELETE all PASS. DORMANT until IG demo keys are on the box (Thursday).
cd /root/pe-fin/team || exit 1
cat > ig_client.py <<'PY'
# IG spread-bet client (Saturday-build item 6: the tax-free venue for an individual). REST API, DEMO endpoint unless IG_ENV=live
# AND IG_ALLOW_LIVE=1 are both on the box. Keys live in /root/pe-logger/.env: IG_API_KEY, IG_USERNAME, IG_PASSWORD, IG_ENV.
# Spread bets are sized in £ per point; 'DFB' = daily funded bet (closes/rolls daily), which suits intraday systems.
import sys, json, time, requests
sys.path.insert(0,'/root/pe-queue/runner')
def creds():
    import creds as c; return c.all_vars()
class IG:
    def __init__(self):
        E=creds(); self.key,self.user,self.pw=E.get('IG_API_KEY'),E.get('IG_USERNAME'),E.get('IG_PASSWORD')
        live=E.get('IG_ENV')=='live' and E.get('IG_ALLOW_LIVE')=='1'
        self.base='https://api.ig.com/gateway/deal' if live else 'https://demo-api.ig.com/gateway/deal'; self.live=live
        self.s=requests.Session(); self.s.headers.update({'X-IG-API-KEY':self.key or '','Content-Type':'application/json; charset=UTF-8','Accept':'application/json; charset=UTF-8'})
    def ready(self): return bool(self.key and self.user and self.pw)
    def _req(self,method,path,version='1',**kw):
        h={'Version':version}; h.update(kw.pop('headers',{}))
        r=self.s.request(method,self.base+path,headers=h,timeout=30,**kw)
        try: j=r.json()
        except Exception: j={'raw':r.text[:200]}
        return r.status_code,j,r
    def login(self):
        sc,j,r=self._req('POST','/session',version='2',data=json.dumps({'identifier':self.user,'password':self.pw}))
        if sc!=200: return False,j
        self.s.headers.update({'CST':r.headers.get('CST',''),'X-SECURITY-TOKEN':r.headers.get('X-SECURITY-TOKEN','')}); return True,j
    def search(self,term):
        sc,j,_=self._req('GET','/markets',params={'searchTerm':term}); return j.get('markets',[]) if sc==200 else []
    def market(self,epic):
        sc,j,_=self._req('GET',f'/markets/{epic}',version='3'); return j if sc==200 else None
    def open(self,epic,direction,size,stop_distance=None,limit_distance=None):
        body=dict(epic=epic,expiry='DFB',direction=direction.upper(),size=str(size),orderType='MARKET',currencyCode='GBP',forceOpen=True,guaranteedStop=False)
        if stop_distance: body['stopDistance']=str(stop_distance)
        if limit_distance: body['limitDistance']=str(limit_distance)
        sc,j,_=self._req('POST','/positions/otc',version='2',data=json.dumps(body))
        if sc!=200: return dict(ok=False,error=j)
        ref=j.get('dealReference'); time.sleep(1); sc2,c,_=self._req('GET',f'/confirms/{ref}')
        return dict(ok=c.get('dealStatus')=='ACCEPTED',confirm=c)
    def positions(self):
        sc,j,_=self._req('GET','/positions',version='2'); return j.get('positions',[]) if sc==200 else []
    def close(self,deal_id,direction,size):
        body=dict(dealId=deal_id,direction='SELL' if direction.upper()=='BUY' else 'BUY',size=str(size),orderType='MARKET')
        sc,j,_=self._req('POST','/positions/otc',version='1',headers={'_method':'DELETE'},data=json.dumps(body)); return sc==200,j
PY
cat > ig_cost_probe.py <<'PY'
# IG COST PROBE — the number that decides whether a crumb survives on the tax-free venue: IG's quoted spread for each instrument
# our edges trade, sampled at the moments the bots trade (09:31/09:36 ET and 15:00 ET). Writes /root/pe-fin/team/public/ig_costs.md.
# Read-only: logs in, reads quotes, never places an order. Dormant until IG keys are on the box.
import sys, json, datetime as dt, pandas as pd
sys.path.insert(0,'/root/pe-fin/team'); from ig_client import IG
OUT='/root/pe-fin/team/public/ig_costs.md'; STORE='/root/pe-fin/team/ig_costs.csv'
def main():
    ig=IG()
    if not ig.ready(): print("IG keys not on the box: dormant"); return
    ok,j=ig.login()
    if not ok: print("IG login failed",str(j)[:200]); return
    terms=['US Tech 100','US 500','Russell 2000']
    try: terms+=list(pd.read_csv('/root/pe-data/crumbs/universe_small.csv',index_col=0).sample(40,random_state=dt.date.today().toordinal()).index)
    except Exception: pass
    rows=[]
    for t in terms:
        ms=[m for m in ig.search(t) if m.get('expiry')=='DFB'][:1]
        if not ms: rows.append(dict(term=t,listed=False)); continue
        m=ms[0]; bid,off=m.get('bid'),m.get('offer')
        if bid and off: rows.append(dict(term=t,listed=True,epic=m['epic'],name=m.get('instrumentName'),bid=bid,offer=off,spread_bps=round(1e4*(off-bid)/((off+bid)/2),1),status=m.get('marketStatus')))
        else: rows.append(dict(term=t,listed=True,epic=m['epic'],status=m.get('marketStatus')))
    D=pd.DataFrame(rows); D['t']=dt.datetime.utcnow().isoformat()[:16]
    try: D=pd.concat([pd.read_csv(STORE),D])
    except Exception: pass
    D.to_csv(STORE,index=False)
    q=D[D.spread_bps.notna()] if 'spread_bps' in D else D.iloc[0:0]
    L=[f"# IG spread-bet costs (demo quotes) — updated {dt.datetime.utcnow():%Y-%m-%d %H:%M} UTC","",
       f"Small-cap names sampled: {int((~D.term.isin(terms[:3])).sum())}; listed on IG as daily funded bets: {int(D[~D.term.isin(terms[:3])].listed.sum())}.","",
       "| instrument | median spread bps | samples |","|---|---|---|"]
    if len(q):
        for name,g in q.groupby('term'): L.append(f"| {name} | {g.spread_bps.median():.1f} | {len(g)} |")
    L+=["","Rule: a crumb moves to IG only if its backtest edge per trade exceeds IG's median spread here by at least 2x."]
    open(OUT,'w').write("\n".join(L)); print("\n".join(L[:12]))
if __name__=='__main__': main()
PY
python3 -m py_compile ig_client.py ig_cost_probe.py || exit 1
( crontab -l 2>/dev/null | grep -v ig_cost_probe.py; echo "33 14,20 * * 1-5 cd /root/pe-fin/team && /usr/bin/python3 ig_cost_probe.py >> ig_probe.log 2>&1"; echo "38 14 * * 1-5 cd /root/pe-fin/team && /usr/bin/python3 ig_cost_probe.py >> ig_probe.log 2>&1" ) | crontab -
python3 ig_cost_probe.py
