#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""patch_lexicon2.py — 약한 꼬리 실측 오류 3건의 근본 수리.

근거(build 산출 mapping_audit 실측):
  1) 유한양행 → 3304 화장품 오배정. 3004 사전에 **평문 '의약품'이 없어** 제약사 본문이
     한 건도 안 걸렸고, 생활유통 부문의 '화장품'이 argmax를 먹었다.
     ※ '바이오의약품'(3002)과의 충돌은 L-guard가 자동 처리 — '오'+'의약품'이라 좌측 차단.
  2) 농심 → 1905 제과 오배정. '라면'은 2음절이라 L-guard가 걸리는데, 한국어 조건 어미
     '~한다면/오른다면'뿐 아니라 정상 용례인 '신라면·봉지라면'까지 좌측 차단된다.
     → 4음절+ 합성어 형태를 추가해 우회(L-guard 미적용 구간).
  3) 천보 → 4011 타이어(점수 3) 오배정: 근거 점수 하한이 없어 우연 1회 매치가 통과.
     → 러너 쪽 TH_WEAK 하한으로 별도 수리(build_fq073_crosswalk.py).
"""
import json, os, re

FQ = os.path.dirname(os.path.abspath(__file__))
p = os.path.join(FQ, "hs_lexicon.json")
L = json.load(open(p, encoding="utf-8"))

for kw in [r"의약품", r"약품\s*사업", r"제약\s*사업", r"의약\s*사업"]:
    if kw not in L["3004"]["kw"]:
        L["3004"]["kw"].append(kw)

for kw in [r"라면\s*사업", r"라면\s*시장", r"라면류", r"봉지\s*라면", r"용기\s*라면",
           r"즉석\s*면", r"건면", r"유탕면"]:
    if kw not in L["1902"]["kw"]:
        L["1902"]["kw"].append(kw)

bad = [(k, kw) for k, v in L.items() if not k.startswith("_")
       for kw in v["kw"] if any(ord(c) < 32 for c in kw)]
if bad:
    raise SystemExit("제어문자 오염: %s" % bad)
for k, v in L.items():
    if k.startswith("_"):
        continue
    for kw in v["kw"]:
        re.compile(kw)

json.dump(L, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("[patch2] 3004 kw =", L["3004"]["kw"])
print("[patch2] 1902 kw =", L["1902"]["kw"])
