#!/bin/bash
# 081: Smarkets logs in and sees ~75 live markets but writes 0 rows. Print one raw markets/contracts/quotes response shape so the
# parser can be matched to what the API actually returns, then apply the obvious fix (quotes keyed by contract id as string vs int;
# market_type filter too strict).
cd /root/pe-xx && python3 - <<'PY'
import sys, json, requests
sys.path.insert(0,'/root/pe-queue/runner'); import creds
E=creds.all_vars(); S=requests.Session()
r=S.post("https://api.smarkets.com/v3/sessions/",json={"username":E['SMARKETS_USERNAME'],"password":E['SMARKETS_PASSWORD']},timeout=20).json(); tok=r.get('token'); print("login",bool(tok))
H={"Authorization":"Session-Token "+tok}
ev=S.get("https://api.smarkets.com/v3/events/",params={"state":"live","type_domain":"football","limit":5},headers=H,timeout=20).json().get('events',[])
print("events sample keys:",list(ev[0].keys()) if ev else None, [e.get('name') for e in ev])
if ev:
    ids=",".join(str(e['id']) for e in ev[:3])
    mk=S.get(f"https://api.smarkets.com/v3/events/{ids}/markets/",params={"limit":50},headers=H,timeout=20).json().get('markets',[])
    print("markets:",len(mk)); print("first market:",json.dumps(mk[0])[:400] if mk else None)
    print("market names:",sorted({m.get('name') for m in mk})[:20])
    if mk:
        mids=[m['id'] for m in mk[:5]]
        ct=S.get(f"https://api.smarkets.com/v3/markets/{','.join(mids)}/contracts/",headers=H,timeout=20).json().get('contracts',[])
        print("contracts:",len(ct),"first:",json.dumps(ct[0])[:300] if ct else None)
        q=S.get(f"https://api.smarkets.com/v3/markets/{','.join(mids)}/quotes/",headers=H,timeout=20).json()
        print("quotes type:",type(q).__name__,"keys sample:",list(q.keys())[:5] if isinstance(q,dict) else None)
        k=list(q.keys())[0] if isinstance(q,dict) and q else None
        print("one quote:",json.dumps(q[k])[:400] if k else None)
PY
