#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""test_sot_access_paths_py.py — python AST 정본 소비경로 추출기 6축 대조

R 판(test_sot_access_paths.R)과 동일 축. 이 파일이 필요한 이유는 실측으로 증명됐다:
  2026-08-20 세션에서 python 판 결함(재할당 오탐)을 고친 뒤 "R 도 고쳤다"고 가정했는데,
  R 테스트에 축을 추가하자 **R 판은 과잉 교정이 남아 있었다**. 테스트 없는 수리는 가정이다.

축:
  [A] 양성 대조 — 추출 경로가 정본에 실재 (허위 추출 0)
  [B] 음성 대조 — 가짜 뿌리로는 0건
  [C] 별칭 ON/OFF — 별칭 추적이 실제로 경로를 살리는가
  [D] 재할당 무효화 — 다른 값으로 덮인 별칭이 오탐을 안 내는가
  [E] 과잉 교정 아님 — 재할당 *이전* 정당 접근은 보존되는가
  [F] 동적 키 — d[k] (k 가 변수) 는 버리는가 (과소 추출 = 안전)
"""
import io
import json
import os
import sys

ROOT = os.environ.get("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
sys.path.insert(0, os.path.join(ROOT, "02_Infrastructure", "ops"))
from sot_access_paths_py import extract_paths  # noqa: E402

SOT = os.path.join(ROOT, "02_Infrastructure/worktask/constraint_defaults.json")
SRC = os.path.join(ROOT, "02_Infrastructure/validation/deployed_holdings_check.py")
FX = os.path.join(ROOT, ".cache", "_test_sot_py")

PASS = [0]
FAIL = [0]


def ok(m):
    PASS[0] += 1
    print("  PASS  " + m)


def ng(m):
    FAIL[0] += 1
    print("  FAIL  " + m)


def write_fx(name, lines):
    os.makedirs(FX, exist_ok=True)
    p = os.path.join(FX, name)
    io.open(p, "w", encoding="utf-8", newline="").write("\n".join(lines) + "\n")
    return p


d = json.load(io.open(SOT, encoding="utf-8"))

print("== [A] 양성 대조 ==")
ps = extract_paths(SRC, "d")
if len(ps) >= 5:
    ok("경로 %d건 추출 (>=5)" % len(ps))
else:
    ng("추출 %d건 — 너무 적음" % len(ps))
bad = []
for p in ps:
    v, good = d, True
    for k in p.split("$")[1:]:
        if isinstance(v, dict) and k in v:
            v = v[k]
        else:
            good = False
            break
    if not good:
        bad.append(p)
if not bad:
    ok("%d/%d 전부 정본에 실재 (허위 추출 0)" % (len(ps), len(ps)))
else:
    ng("정본 부재 %d건: %s" % (len(bad), bad[:3]))

print("== [B] 음성 대조 ==")
p0 = extract_paths(SRC, "NOSUCH_zzz")
ok("가짜 뿌리 -> 0건") if not p0 else ng("가짜 뿌리인데 %d건 — 오탐" % len(p0))

print("== [C] 별칭 ON/OFF ==")
on = extract_paths(SRC, "d", follow_alias=True)
off = extract_paths(SRC, "d", follow_alias=False)
if len(on) > len(off):
    ok("ON=%d OFF=%d — 별칭 추적이 %d경로를 살림" % (len(on), len(off), len(on) - len(off)))
else:
    ng("ON=%d OFF=%d — 별칭 추적 효과 없음(대조 무효)" % (len(on), len(off)))

print("== [D]/[E] 재할당 ==")
fx = write_fx("realias.py", ['d = load()', 't = d["tier_soft_deployment"]',
                             'a = t["max_names"]', 't = read_table()', 'b = t["SomeCol"]'])
if os.path.exists(fx):
    ok("[선행검증] 픽스처 생성")
else:
    ng("[선행검증] 픽스처 실패")
pr = extract_paths(fx, "d")
ok("재할당 후 접근이 오탐으로 안 들어감") if "d$tier_soft_deployment$SomeCol" not in pr \
    else ng("재할당 무효화 미작동")
ok("재할당 *이전* 정당 접근 보존 (과잉 교정 아님)") if "d$tier_soft_deployment$max_names" in pr \
    else ng("과잉 교정 — 이전 접근까지 죽었다")

print("== [F] 동적 키 ==")
fx2 = write_fx("dyn.py", ['d = load()', 'k = pick()', 'v = d[k]', 'w = d["max_names"]'])
pd_ = extract_paths(fx2, "d")
ok("동적 키는 버림 (과소 추출 = 안전)") if not any("$" in x and x.endswith("$k") for x in pd_) \
    else ng("동적 키가 경로로 새어들어감")
ok("같은 파일의 정적 키는 잡음") if "d$max_names" in pd_ else ng("정적 키까지 놓침")

import shutil  # noqa: E402
shutil.rmtree(FX, ignore_errors=True)
print("\n== 결과: %d PASS / %d FAIL ==" % (PASS[0], FAIL[0]))
sys.exit(1 if FAIL[0] else 0)
