#!/bin/bash
# fin 027 (own runner): offline tests on the box after the opening-break protection change; shows the calendar for Friday's half day.
cd /root/pe-finq/repo/fin/bots && echo "offline test: $(timeout 300 python3 test_tick.py 2>&1 | tail -1)" && python3 -c "
import tick as T, datetime as dt
T.H = T._creds(); print('Friday calendar:', T.calendar_day(dt.date(2026, 11, 27)))"
