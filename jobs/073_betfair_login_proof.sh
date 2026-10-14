#!/bin/bash
# 073: PROOF, not alarm. Peter's Betfair username/password were never wiped — they live in /root/pe-logger/betfair.env, a file my
# credential lookup did not read (it only read files named .env*). Lookup fixed. This job logs in to Betfair from a fresh process
# and prints SUCCESS/FAIL so the record is clear, then lets 070 (recorder restart with the extra markets) proceed safely.
python3 - <<'PY'
import sys; sys.path.insert(0,'/root/pe-queue/runner'); import creds, requests
print(creds.report())
a,u,p=creds.betfair()
r=requests.post("https://identitysso.betfair.com/api/login",data={"username":u,"password":p},headers={"X-Application":a,"Accept":"application/json"},timeout=15).json()
print("FRESH BETFAIR LOGIN:",r.get('status'),r.get('error') or '')
import os; print("betfair.env present:",os.path.exists('/root/pe-logger/betfair.env'))
PY
