#!/bin/bash
# 114: STRATEGY FACTORY v2 — memory-safe. v1 loaded a whole sport into pandas (3.8M greyhound rows) and was OOM-killed. v2 pulls
# market ids per sport, processes them in batches of 2,000 markets (server-side cursor, only the columns needed), builds the
# per-runner records incrementally, and runs the same battery on the assembled compact frame (one row per runner, ~2M rows max).
python3 - <<'PY'
p='/root/pe-factory/factory.py'; s=open(p).read()
old_start=s.index("for sport in SPORTS:"); old_end=s.index("    R=pd.DataFrame(recs)")
new='''for sport in SPORTS:
    cur.execute("SELECT DISTINCT market_id FROM bf_hist_other WHERE sport=%s AND market_id<>'1' AND market_type IN ('MATCH_ODDS','WIN','OUTRIGHT_WINNER','TOURNAMENT_WINNER')",(sport,))
    mids=[r[0] for r in cur.fetchall()]; print(sport,"markets",len(mids),flush=True)
    recs=[]
    for bi in range(0,len(mids),2000):
        batch=mids[bi:bi+2000]
        D=pd.read_sql("SELECT market_id, market_time mt, sel, ts, ltp::float ltp, inplay FROM bf_hist_other WHERE sport=%s AND market_id = ANY(%s) ORDER BY market_id, ts",con,params=(sport,batch))
        for mid,g in D.groupby('market_id',sort=False):
            pre=g[~g.inplay]; ip=g[g.inplay]
            if pre.empty or ip.empty: continue
            sels=g.sel.unique(); n=len(sels)
            if n<2: continue
            sp={}; p10={}; mt=pd.Timestamp(g.mt.iloc[0])
            for s_ in sels:
                ps=pre[pre.sel==s_]
                if ps.empty: continue
                sp[s_]=ps.ltp.iloc[-1]
                early=ps[pd.to_datetime(ps.ts)<=mt-pd.Timedelta(minutes=10)]
                p10[s_]=early.ltp.iloc[-1] if not early.empty else None
            if len(sp)<2: continue
            last={s_:ip[ip.sel==s_].ltp.iloc[-1] for s_ in sels if not ip[ip.sel==s_].empty}
            if not last: continue
            w=min(last,key=last.get)
            if last[w]>=1.15: continue
            fav=min(sp,key=sp.get); srt=sorted(sp.values()); second=srt[1] if len(srt)>1 else None
            fi=ip[ip.sel==fav]; fpath=list(fi.ltp.values); ftimes=list(pd.to_datetime(fi.ts).values)
            for s_,v in sp.items():
                recs.append(dict(mid=mid,mt=mt,sel=s_,sp=v,p10=p10.get(s_),won=(s_==w),is_fav=(s_==fav),fav_sp=sp[fav],second=second,n=n,
                                 fpath=fpath if s_==fav else None,ftimes=ftimes if s_==fav else None))
        del D
        if bi % 20000 == 0: print("  ",sport,bi,"markets done, runners",len(recs),flush=True)
'''
s=s[:old_start]+new+s[old_end:]
open(p,'w').write(s); print("factory v2 written")
PY
python3 -m py_compile /root/pe-factory/factory.py || exit 1
cd /root/pe-factory && nohup timeout 7200 python3 factory.py > factory_run.log 2>&1 &
echo "factory v2 started in background (log /root/pe-factory/factory_run.log); results in strategy_results when done"
