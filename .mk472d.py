s=open('.diag472c.py').read()
old="""AND market_time>=%s AND market_time<%s AND ts>=market_time-interval '30 minutes' AND ts<=market_time+interval '150 minutes'\""",con,params=(lo,hi))"""
assert s.count(old)==1
new="""AND market_time>=%s AND market_time<%s AND ts>=market_time-interval '30 minutes' AND ts<=market_time+interval '150 minutes'
                     AND event_id IN (SELECT DISTINCT event_id FROM bf_hist_other WHERE sport='Soccer' AND market_type='BOTH_TEAMS_TO_SCORE' AND inplay
                                      AND market_time>=%s AND market_time<%s)\""",con,params=(lo,hi,lo,hi))"""
s=s.replace(old,new)
# speed fix (9 Nov): only games with an in-play BTTS print can trade, so the chunk query keeps those events; nothing in the rule changes
open('.diag472d.py','w').write("# .diag472d.py = .diag472c.py with the chunk SQL cut to events holding an in-play BTTS print (speed only, 9 Nov)\n"+s)
print('ok')
