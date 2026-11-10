#!/usr/bin/env python
"""dr_heal_plan.py — 아침 자가 복구가 다시 돌릴 daily_refresh 단계 계획 (감사 레인 A · 2026-11-10 도훈 '실패한 단계만')

입력: 밤 실행 상태 .cache/daily_refresh_state.json(daily_refresh.sh 가 단계마다 쓴다) · 오늘 날짜 · 감사기의 낡은 항목 · 퀀티 축.
출력: 한 줄 'DR_HEAL<TAB>plan=<단계,…>|FULL<TAB>reason=<…>' · 종료 0(판독 실패도 FULL 로 0 — 모르면 전부 돌린다).

단계 순서 = daily_refresh.sh 실행 순서(ingest qw universe macro dart krf fdb nonret). 하류(DOWN)는 코드에서 다시 짚은 쓰기 → 읽기 관계:
  ingest  [0a][0b] Update_File → RAWDATA · 컨센서스 · 수급 · 유니버스 보조 쓰기 → qw([0b'] 재적재 · 벤치 게이트) · universe([3] 매핑이 RAWDATA 를 다시 씀) ·
          macro(KTRI v3 · 국면이 RAWDATA · 벤치를 읽는다 — 보수적으로 포함) · krf([5c] 입력 = RAWDATA) · fdb([6a] 경계 = RAWDATA 최신일)
  qw      벤치 = 거래일 캘린더 정본 · RAWDATA 주가 → universe · macro · krf · fdb (ingest 와 같은 이유)
  universe RAWDATA K200 · 위생 열 → macro(보수) · krf · fdb
  macro   국면 · 거시 캐시 → fdb(국면 · 거시 계열 팩터 — 보수)
  dart    DART 재무 · 내부자 → krf(재무 1단계 표) · fdb(재무 팩터)
  krf · fdb · nonret  — 체인 안 하류 없음([0c] 검증 · [7] 보고는 늘 돈다)
씨앗 = 밤 실행에서 실패한 단계 ∪ 기록이 없는 단계(중도 사망) ∪ 낡은 항목이 가리키는 단계 ∪ 퀀티 축('qw'). 모르는 낡은 항목 = FULL.
FULL 조건: 상태 파일 없음 · 판독 실패 · 오늘 밤 실행이 아님(PC 꺼짐 등) · 상태 파일이 자가 복구 실행의 것 · 씨앗 0(이유를 모르면 전부).
사용: python dr_heal_plan.py --state <json> [--today YYYY-MM-DD] [--stale a,b] [--qw-behind 0|1]
"""
from __future__ import annotations

import argparse
import io
import json
import sys
from datetime import date

ORDER = ["ingest", "qw", "universe", "macro", "dart", "krf", "fdb", "nonret"]
DOWN = {
    "ingest": ["qw", "universe", "macro", "krf", "fdb"],
    "qw": ["universe", "macro", "krf", "fdb"],
    "universe": ["macro", "krf", "fdb"],
    "macro": ["fdb"],
    "dart": ["krf", "fdb"],
    "krf": [], "fdb": [], "nonret": [],
}
# freshness_audit.R 감사 이름 → 생산 단계(daily_refresh.sh 안의 생산자 위치). p3_forecast = 브리핑 산출물(리프레시 하류 아님)
STALE_TO_STAGE = {
    "rawdata": "qw", "benchmark": "qw", "consensus": "qw", "investor_act": "qw", "universe_support": "qw",
    "msm_daily": "macro", "fred": "macro", "fred_wide": "macro", "ktri_indices": "macro", "ktri_v3_signals": "macro",
    "regime_daily": "macro", "p3_forecast": None,
}


def plan(state: dict | None, today: str, stale: list[str], qw_behind: bool):
    if not isinstance(state, dict) or state.get("schema") != "daily_refresh_state_v1":
        return None, "no_state"
    if state.get("run_date") != today:
        return None, "no_night_run_today(run_date=%s)" % state.get("run_date")
    if state.get("mode") != "full":
        return None, "last_run_was_%s" % state.get("mode")
    rec = {s.get("name"): s.get("status") for s in (state.get("stages") or []) if isinstance(s, dict)}
    seeds = {n for n, st in rec.items() if st != "ok" and n in DOWN}
    missing = [n for n in ORDER if n not in rec]
    if missing and state.get("status") != "done":
        seeds |= set(missing)                       # 중도 사망 — 기록 없는 단계부터
    for it in stale:
        nm = it.split("(", 1)[0].strip()
        if not nm:
            continue
        if nm not in STALE_TO_STAGE:
            return None, "unknown_stale_item(%s)" % nm
        if STALE_TO_STAGE[nm]:
            seeds.add(STALE_TO_STAGE[nm])
    if qw_behind:
        seeds.add("qw")
    if not seeds:
        return None, "no_seed"
    out = set(seeds)
    for s in list(seeds):
        out |= set(DOWN[s])
    return [n for n in ORDER if n in out], "seeds=" + ",".join(n for n in ORDER if n in seeds)


def _split_items(s: str) -> list[str]:
    """'a,b(STALE,lag=3d),c' → ['a', 'b(STALE,lag=3d)', 'c'] — 괄호 안 쉼표는 나누지 않는다(감사기 stale_items 꼴 · EDC_RESULT 이름 꼴 둘 다)."""
    out, cur, depth = [], "", 0
    for ch in s or "":
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth = max(0, depth - 1)
        if ch == "," and depth == 0:
            out.append(cur); cur = ""
        else:
            cur += ch
    out.append(cur)
    return [x.strip() for x in out if x.strip() and x.strip() != "-"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--state", required=True)
    ap.add_argument("--today", default=date.today().isoformat())
    ap.add_argument("--stale", default="")
    ap.add_argument("--qw-behind", default="0")
    a = ap.parse_args()
    try:
        st = json.load(io.open(a.state, encoding="utf-8-sig"))
    except Exception:
        st = None
    stale = _split_items(a.stale)
    p, why = plan(st, a.today, stale, a.qw_behind == "1")
    print("DR_HEAL\tplan=%s\treason=%s" % ("FULL" if p is None else ",".join(p), why))
    return 0


if __name__ == "__main__":
    sys.exit(main())
