#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""rf_overlay_ledger_count.py — 오버레이 arm 방출 원장에서 **레인 몫 방출** 수를 센다 (v10.4 2026-09-17)

★왜 파일인가: 일간 상한은 원장에서 세지 별도 카운터를 두지 않는다(rf_overlay_propose.sh 규약 그대로).
  다만 원장에는 이제 레인 밖 방출(세션 수동 등재 · B5 설계 레인)도 `source` 를 달고 실리므로
  "오늘 몇 건" 을 그냥 세면 남의 방출이 레인의 하루 예산을 먹는다(같은 날 세션 등재 1건 → 레인 halt_daily_cap).
  source 가 overlay_propose 이거나 **필드가 없는(구판 legacy) 기록만** 레인 몫으로 센다.
  셸 인라인이 아니라 파일인 이유 = 검사(test_rf_overlay_admit_source.R)가 **같은 코드**를 태운다 —
  인라인 사본을 검사에 복제하면 정본과 갈린다(이 저장소의 반복 결함).

사용: python rf_overlay_ledger_count.py <ledger.jsonl> [YYYY-MM-DD] [source,source,...]
  날짜 기본 = 오늘(로컬) · source 집합 기본 = overlay_propose. 필드 부재 기록은 항상 레인 몫이다.
출력: 정수 한 줄 (원장 부재·손상 줄은 0 으로 센다 — 상한 판정이 인프라 오류로 레인을 죽이지 않게)
"""
import io
import json
import sys
import datetime


def count_lane_emissions(ledger, day=None, sources=("overlay_propose",)):
    day = day or datetime.date.today().isoformat()
    n = 0
    try:
        for ln in io.open(ledger, encoding="utf-8"):
            ln = ln.strip()
            if not ln:
                continue
            try:
                r = json.loads(ln)
            except Exception:
                continue
            if r.get("record_type") != "arm_emission":
                continue
            if not str(r.get("emitted_at", "")).startswith(day):
                continue
            src = r.get("source")
            if src is None or src == "" or src in sources:   # 부재 = 구판 legacy = 레인 몫
                n += 1
    except FileNotFoundError:
        pass
    return n


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.stdout.write("usage: <ledger.jsonl> [YYYY-MM-DD] [source,...]\n")
        sys.exit(2)
    d = sys.argv[2] if len(sys.argv) >= 3 and sys.argv[2] else None
    s = tuple(x for x in (sys.argv[3].split(",") if len(sys.argv) >= 4 else ["overlay_propose"]) if x)
    sys.stdout.write("%d\n" % count_lane_emissions(sys.argv[1], d, s))
