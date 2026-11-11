# -*- coding: utf-8 -*-
"""README.md 의 분류표 자리(표식 줄 또는 앞서 끼운 표)에 classification_table.md 를 끼운다 — 표는 손으로 옮겨 적지 않는다."""
import os, re
HERE = os.path.dirname(os.path.abspath(__file__)); REP = os.path.dirname(HERE)
BEG, END = "<!-- TABLE:BEGIN -->", "<!-- TABLE:END -->"
table = open(os.path.join(REP, 'classification_table.md'), encoding='utf-8').read().rstrip('\n')
p = os.path.join(REP, 'README.md')
s = open(p, encoding='utf-8').read()
block = BEG + "\n" + table + "\n" + END
if "<!-- TABLE -->" in s:
    s = s.replace("<!-- TABLE -->", block, 1)
elif BEG in s and END in s:
    s = s[:s.index(BEG)] + block + s[s.index(END) + len(END):]
else:
    raise SystemExit("표 자리 표식 없음")
open(p, 'w', encoding='utf-8', newline='\n').write(s)
print("표 %d행 삽입" % (table.count('\n') - 1))
