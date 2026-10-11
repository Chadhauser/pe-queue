#!/bin/bash
# 030: recorder still gets HTTP 400 on some listMarketBook batches. Log the response body (the Betfair error code) and fall back
# per batch: EX_ALL_OFFERS -> EX_BEST_OFFERS (depth 3) -> skip batch. Never lose the whole loop to one bad batch.
python3 - <<'PY'
p='/root/pe-liq/liq_recorder.py'; s=open(p).read()
old_api=s[s.index('def api(ep,payload):'):s.index('con=psycopg2.connect')]
new_api='''def api(ep,payload):
    if TOK is None or time.time()-TOK_T>3000: login()
    r=requests.post(f"https://api.betfair.com/exchange/betting/rest/v1.0/{ep}/",json=payload,headers={"X-Authentication":TOK,"X-Application":APP_KEY,"Content-Type":"application/json","Accept":"application/json"},timeout=20)
    if r.status_code!=200:
        print("API",ep,r.status_code,r.text[:300],flush=True); r.raise_for_status()
    return r.json()
'''
s=s.replace(old_api,new_api)
old_books=s[s.index('def books(ids):'):s.index('def rec_rows')]
new_books='''def books(ids):
    out=[]
    for i in range(0,len(ids),8):
        chunk=ids[i:i+8]
        try: out+=api('listMarketBook',{"marketIds":chunk,"priceProjection":{"priceData":["EX_ALL_OFFERS"]}}); continue
        except Exception as e: print("batch ALL_OFFERS failed, trying BEST_OFFERS:",repr(e)[:120],flush=True)
        try: out+=api('listMarketBook',{"marketIds":chunk,"priceProjection":{"priceData":["EX_BEST_OFFERS"],"exBestOffersOverrides":{"bestPricesDepth":3}}})
        except Exception as e: print("batch skipped:",repr(e)[:120],flush=True)
    return out
'''
s=s.replace(old_books,new_books)
open(p,'w').write(s)
PY
python3 -m py_compile /root/pe-liq/liq_recorder.py || exit 1
pkill -f liq_recorder.py; pkill -f keepalive.sh; sleep 80
pgrep -af liq_recorder.py; echo "--- last 12 log lines:"; tail -12 /root/pe-liq/recorder.log
