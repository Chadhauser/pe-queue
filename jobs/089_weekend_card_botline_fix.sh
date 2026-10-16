#!/bin/bash
# 089: weekend card bot line used a column that does not exist (opened_at) -> entered_at. Re-run so tonight's 17:00 card is right.
sed -i "s/opened_at>=now()/entered_at>=now()/" /root/pe-report/weekend_card.py && python3 -m py_compile /root/pe-report/weekend_card.py && cd /root/pe-report && python3 weekend_card.py | head -12
