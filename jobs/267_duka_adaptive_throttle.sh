#!/bin/bash
# 267: Dukascopy throttle — 404 ERRs in one slice means the server is refusing most requests. Make the downloader adaptive:
#  log the HTTP status distribution, and when >30% of an hour-batch errors, drop to 1 worker with 0.4s spacing for the next 30 days.
cd /root/pe-fin || exit 1
python3 - <<'PY'
p='/root/pe-fin/duka_1m.py'; s=open(p).read()
s=s.replace("""        except urllib.error.HTTPError as e:
            if e.code==404: return None
            time.sleep(1)""","""        except urllib.error.HTTPError as e:
            STATUS[e.code]=STATUS.get(e.code,0)+1
            if e.code==404: return None
            time.sleep(1+attempt)""")
s=s.replace("unfinished=False\n","unfinished=False; STATUS={}; slow_until=None\n",1)
old="        with ThreadPoolExecutor(4) as ex: res=list(ex.map(lambda h:fetch(sym,d,h),range(24)))"
new="""        slow = slow_until is not None and d<=slow_until
        if slow:
            res=[]
            for h in range(24): res.append(fetch(sym,d,h)); time.sleep(0.4)
        else:
            with ThreadPoolExecutor(4) as ex: res=list(ex.map(lambda h:fetch(sym,d,h),range(24)))
        if sum(1 for r in res if isinstance(r,str))>7 and not slow: slow_until=d+datetime.timedelta(days=30); print(f"throttled on {d}: switching to 1 worker/0.4s until {slow_until}",flush=True)"""
assert old in s; s=s.replace(old,new)
s=s.replace('print(f"== {sym}: days on disk','print("HTTP status counts:",STATUS); print(f"== {sym}: days on disk')
open(p,'w').write(s); print('adaptive throttle installed')
PY
python3 -m py_compile /root/pe-fin/duka_1m.py && echo "267 done"
