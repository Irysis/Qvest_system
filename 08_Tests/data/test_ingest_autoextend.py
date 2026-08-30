#!/usr/bin/env python
"""test_ingest_autoextend.py — QuantiWise 적재 자동확장 **배선**의 회귀 검사.

배경 (2026-08-30 실사고): QuantiWise 적재가 2026-07-24 에서 한 달 멈췄는데 계기 셋이
각각 다른 것을 재느라 아무도 못 잡았다 — Gate A 는 다운로드 상태파일, Gate B 는 팩터DB
앵커(신선한 주가 축이 채운다), daily_refresh [0] 은 **베이스** xlsx mtime. 정작
qw_refresh.ps1 은 `Update_File/*_update.xlsx` 에 쓰는데 그걸 읽는 모듈
(incremental_update_file.R)은 정규 경로에 배선돼 있지 않았다. 결과: 2026-09 PG2 비중이
낡은 축으로 산출돼 20종 중 9종이 잘못 선택됐다.

★이 검사는 **배선만** 잰다. 신선도 판정 자체는 정본(morning_steps/freshness_audit.R)
  하나뿐이고 여기서 재구현하지 않는다(도훈 지적 2026-08-30). 초판은 판정기를 따로
  만들었다가 중복이라 걷어냈다 — 그 이력을 여기 남긴다.

계약:
  ① daily_refresh 가 Update_File 모듈(incremental_update_file.R)을 호출한다
  ② 베이스 모듈이 Update_File 모듈보다 **먼저** 온다 (뒤집히면 전체 재빌드가 증분을 지운다)
  ③ 두 모듈을 **한 run_r 블록에서 함께 source 하지 않는다** — 같은 함수명
     (incremental_update_all 등)을 export 하므로 조용히 덮인다(사고의 직접 원인)
  ④ 적재 뒤 검증 단계가 배선돼 있고, **정본 감사기를 호출**한다(자체 판정 금지)
  ⑤ 감사기 목록에 전략 소비 패널 5종이 등재돼 있다 — 목록에 없으면 아무도 안 잰다
  ⑥ [음성 대조] 판정 분기가 OK / STALE / 판독불가 3갈래로 갈린다
     (미측정을 미달로 접으면 원인을 원천이 아니라 게이트에서 찾게 된다)

실행: python 08_Tests/data/test_ingest_autoextend.py
"""
from __future__ import annotations

import json
import os
import re
import sys

_SELF = os.path.dirname(os.path.abspath(__file__))
CODE_ROOT = os.path.abspath(os.path.join(_SELF, "..", ".."))
if not os.path.exists(os.path.join(CODE_ROOT, "02_Infrastructure", "data", "daily_refresh.sh")):
    CODE_ROOT = os.environ.get("QM_ROOT", CODE_ROOT).replace("\\", "/")
REFRESH = os.path.join(CODE_ROOT, "02_Infrastructure", "data", "daily_refresh.sh")
AUDIT = os.path.join(CODE_ROOT, "02_Infrastructure", "ops", "morning_steps", "freshness_audit.R")

PASS, FAIL = 0, 0


def ok(m):
    global PASS
    print(f"  [PASS] {m}")
    PASS += 1


def ng(m):
    global FAIL
    print(f"  [FAIL] {m}")
    FAIL += 1


def main():
    for p in (REFRESH, AUDIT):
        if not os.path.exists(p):
            print(f"XX 대상 부재: {p}")
            return 9
    src = open(REFRESH, encoding="utf-8").read()
    aud = open(AUDIT, encoding="utf-8").read()

    p_base = src.find("data/incremental_cache_update.R")
    p_upd = src.find("data/incremental_update_file.R")

    if p_upd > 0:
        ok("① Update_File 모듈이 배선돼 있다 (자동확장 경로 실재)")
    else:
        ng("① Update_File 모듈 미배선 — 적재가 한 번도 일어나지 않는다(실사고 재발)")

    if p_base > 0 and p_upd > 0 and p_base < p_upd:
        ok("② 순서 = 베이스 재빌드 → 증분 append")
    else:
        ng(f"② 순서 이상 (base={p_base} update={p_upd}) — 재빌드가 증분을 지운다")

    blocks = re.findall(r"run_r\s+'(.*?)'", src, flags=re.S)
    both = [b for b in blocks
            if "incremental_cache_update.R" in b and "incremental_update_file.R" in b]
    if not both:
        ok("③ 두 모듈이 별도 run_r 블록 — 동명 함수 shadowing 없음")
    else:
        ng("③ 한 블록에서 함께 source — 같은 이름 export 라 조용히 덮인다(사고 원인)")

    if "freshness_audit.R" in src:
        ok("④ 적재 뒤 검증이 **정본 감사기**를 호출한다 (판정 중복 구현 없음)")
    else:
        ng("④ 정본 감사기 미호출 — 판정을 자체 구현했거나 검증이 없다")

    # ⑤ 감사기 목록에 전략 소비 패널이 있는가 — 목록에 없으면 아무도 안 잰다
    need = ["rawdata", "consensus", "investor_act", "universe_support", "fred_wide"]
    miss = [n for n in need if f'check_freshness("{n}"' not in aud]
    if not miss:
        ok(f"⑤ 감사기에 전략 소비 패널 {len(need)}종 전부 등재")
    else:
        ng(f"⑤ 감사 목록 누락: {miss} — 목록에 없으면 정지해도 아무도 모른다")

    # ⑥ 판정 3갈래 — 미측정을 미달로 접지 않는다
    seg = src[src.find("[0c/7]"):src.find("[0c/7]") + 2500] if "[0c/7]" in src else ""
    br = {"OK": "OK)" in seg, "STALE": "STALE:*)" in seg,
          "미측정": ("unreadable" in seg or "판독 불가" in seg)}
    if all(br.values()):
        ok("⑥ 판정 3갈래(OK / STALE / 판독불가) — 미측정을 미달로 접지 않는다")
    else:
        ng(f"⑥ 판정 분기 부족: {br}")

    print(f"결과: PASS={PASS} FAIL={FAIL}")
    print(json.dumps({"test": "ingest_autoextend", "pass": PASS, "fail": FAIL,
                      "total": PASS + FAIL, "skipped": 0}, ensure_ascii=False))
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
