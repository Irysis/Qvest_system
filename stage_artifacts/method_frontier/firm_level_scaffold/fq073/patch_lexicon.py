#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""patch_lexicon.py — 7901(아연) 엔트리 복구 + 제어문자 오염 검사.
   (셸 heredoc이 백슬래시를 먹어 \b -> 0x08 로 깨진 것을 파일 경유로 정정)"""
import json, os, re

FQ = os.path.dirname(os.path.abspath(__file__))
p = os.path.join(FQ, "hs_lexicon.json")
L = json.load(open(p, encoding="utf-8"))

L["7901"] = {
    "desc": "아연 괴·연 제련",
    "w": 3,
    "kw": [r"\b아연\b", r"아연\s*제련", r"아연\s*괴", r"\b연\s*아연\b",
           r"\b연괴\b", r"전기\s*아연", r"아연\s*사업", r"제련\s*사업"],
}

bad = [(k, kw) for k, v in L.items() if not k.startswith("_")
       for kw in v["kw"] if any(ord(c) < 32 for c in kw)]
if bad:
    raise SystemExit("제어문자 오염 잔여: %s" % bad)

json.dump(L, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("[patch] 7901 =", json.load(open(p, encoding="utf-8"))["7901"]["kw"])
print("[patch] 제어문자 오염 0건. 총 HS 엔트리 =", len([k for k in L if not k.startswith("_")]))
for k, v in L.items():
    if k.startswith("_"):
        continue
    for kw in v["kw"]:
        try:
            re.compile(kw)
        except re.error as e:
            print("  ★ 정규식 오류", k, repr(kw), e)
