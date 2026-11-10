#!/usr/bin/env python
"""factor_db_vintage_coverage.py — 팩터 DB 수리가 판 표식 원장에 올랐는가 (감사 레인 A · 2026-11-10)

왜: 판 표식 원장(06_Registry/factor_db_vintage.json)은 손으로 한 줄씩 붙인다. 계약(contracts/factor_db_vintage.R)은 그 원장만
  읽으므로, 수리(전체 재빌드 · 부분 재계산)가 끝났는데 원장에 줄이 안 붙으면 수리 **전에** 잰 측정이 '현행'으로 남아
  A 자격 관문 · P4 기저 풀 · 상설 판을 그대로 통과한다(침묵). 수리 실행기는 끝날 때 요약 JSON 을 남긴다:
    .cache/scheduler_logs/factor_subset_repair_<stamp>.json   (factor_db/run_factor_subset_repair.sh · schema factor_subset_repair/v1)
    .cache/scheduler_logs/factor_db_full_rebuild_<stamp>.json (factor_db/run_factor_db_full_rebuild.sh · schema factor_db_full_rebuild/v1)
  이 검사기는 그 요약(result = 성공)마다 원장 항목이 있는지 본다. 고치지 않는다(원장 writer 는 Q · 추가 전용) — 보고만.

판정(성과 수치 없음 · 시각 · id 만):
  U  미기록 — 성공 요약인데 덮는 원장 항목이 없다. 덮음 = (요약 decision id 가 항목 id 또는 decision 문자열에 있다)
     ∨ (scope = all 인 항목의 completed_at ≥ 요약 시작 시각 stamp — 그 시각 앞의 측정은 어차피 그 항목이 낡음으로 가린다).
  P  진행 중 — completed_at 이 빈 항목(계약상 범위에 닿는 측정 전부 낡음) · 보고만.
  M  당월 옛 코드 — 원장 최신 항목 완료 뒤에 당월 파일(factor_db_<최신 YYYYMM>.parquet)이 다시 쓰이지 않았다.
     부분 수리는 당월을 일일 체인([6a])에 맡기는데, [6a] 계획은 데이터 상태만 본다(factor_db_builder.R .fdb_update_plan —
     스냅샷 날짜 = RAWDATA 최신일이고 7일 안이면 빌드 없음) → RAWDATA 가 멈추면 당월이 옛 코드로 남는다.
  D  결정 기록 누락 — 항목 decision 의 첫 결정 id(대문자-…-YYYYMMDD)가 06_Registry/decision_register.json 에 없다 · 보고만.
출력: 한 줄 'FDV_COVERAGE<TAB>status=OK|GAP<TAB>unrecorded=..<TAB>in_progress=..<TAB>current_month=..<TAB>decision_unregistered=..'
종료: 0 = U · M 없음 · 3 = U 또는 M 있음 · 1 = 판독 불가(원장 없음 · 파손)
사용: python factor_db_vintage_coverage.py [--root <루트>] [--json]
"""
from __future__ import annotations

import argparse
import glob
import io
import json
import os
import re
import sys
from datetime import datetime

ID_RE = re.compile(r"[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+-20\d{6}")


def _t(s):
    s = str(s or "").strip()
    if not s:
        return None
    s = re.sub(r"([+-]\d{2}):?(\d{2})$", "", s)       # 원장 · 요약 모두 KST — 시간대 표기는 뗀다(계약 .fdv_time 과 같은 규칙)
    for f in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M", "%Y%m%d_%H%M%S", "%Y-%m-%d"):
        try:
            return datetime.strptime(s, f)
        except ValueError:
            pass
    return None


def _load(p):
    with io.open(p, encoding="utf-8-sig") as fh:
        return json.load(fh)


def audit(root: str) -> dict:
    led_p = os.path.join(root, "06_Registry", "factor_db_vintage.json")
    L = _load(led_p)
    if L.get("schema") != "factor_db_vintage_v1":
        raise ValueError("원장 스키마 불일치: %s" % L.get("schema"))
    entries = L.get("entries") or []
    summ = []
    logs = os.path.join(root, ".cache", "scheduler_logs")
    for pat in ("factor_subset_repair_*.json", "factor_db_full_rebuild_*.json"):
        for p in sorted(glob.glob(os.path.join(logs, pat))):
            if ".prev_" in os.path.basename(p):
                continue                                  # 재개 전 판 — 같은 stamp 의 최종 요약이 따로 있다
            try:
                s = _load(p)
            except Exception:
                summ.append({"file": os.path.basename(p), "result": "unreadable"}); continue
            summ.append({"file": os.path.basename(p), "result": s.get("result"), "stamp": s.get("stamp"),
                         "decision": s.get("decision") or "", "note": s.get("note") or ""})
    unrecorded = []
    for s in summ:
        if s.get("result") != "성공":
            continue
        st = _t(s.get("stamp"))
        dec = s.get("decision") or ""
        cov = False
        for e in entries:
            if dec and (dec == e.get("id") or dec in str(e.get("decision") or "")):
                cov = True; break
            ca = _t(e.get("completed_at"))
            if e.get("scope") == "all" and ca is not None and st is not None and ca >= st:
                cov = True; break
            if (e.get("completed_at") in (None, "")) and dec and dec in json.dumps(e, ensure_ascii=False):
                cov = True; break
        if not cov:
            unrecorded.append(s["file"])
    in_prog = [e.get("id") for e in entries if not str(e.get("completed_at") or "").strip()]
    # M 당월 — 원장 최신 완료 시각 뒤에 당월 파일이 다시 쓰였나
    done = [(_t(e.get("completed_at")), e.get("id")) for e in entries if _t(e.get("completed_at"))]
    cm = {"state": "na"}
    fdb = sorted(glob.glob(os.path.join(root, ".cache", "factor_db", "factor_db_[0-9][0-9][0-9][0-9][0-9][0-9].parquet")))
    if done and fdb:
        last_t, last_id = max(done)
        f = fdb[-1]
        mt = datetime.fromtimestamp(os.path.getmtime(f))
        cm = {"state": "ok" if mt >= last_t else "old_code", "file": os.path.basename(f),
              "mtime": mt.strftime("%Y-%m-%dT%H:%M:%S"), "after": last_id}
    # D 결정 기록
    dr_ids = set()
    try:
        D = _load(os.path.join(root, "06_Registry", "decision_register.json"))
        dr_ids = set(ID_RE.findall(json.dumps(D, ensure_ascii=False)))
        dr_ok = True
    except Exception:
        dr_ok = False
    unreg = []
    if dr_ok:
        for e in entries:
            ids = ID_RE.findall(str(e.get("decision") or ""))
            if ids and ids[0] not in dr_ids:
                unreg.append(ids[0])
    gap = bool(unrecorded) or cm.get("state") == "old_code"
    return {"status": "GAP" if gap else "OK", "unrecorded": unrecorded, "in_progress": in_prog,
            "current_month": cm, "decision_unregistered": unreg if dr_ok else ["(decision_register 판독 불가)"],
            "n_summaries": len(summ), "n_entries": len(entries)}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.environ.get("QM_ROOT") or os.getcwd())
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    root = a.root.replace("\\", "/")
    try:
        r = audit(root)
    except Exception as e:                                # 판독 불가는 'OK' 로 접지 않는다
        print("FDV_COVERAGE\tstatus=ERROR\treason=%s" % e.__class__.__name__)
        return 1
    cm = r["current_month"]
    print("FDV_COVERAGE\tstatus=%s\tunrecorded=%s\tin_progress=%s\tcurrent_month=%s\tdecision_unregistered=%s" % (
        r["status"], ",".join(r["unrecorded"]) or "-", ",".join(r["in_progress"]) or "-",
        "%s(%s)" % (cm.get("state"), cm.get("file", "-")), ",".join(r["decision_unregistered"]) or "-"))
    if a.json:
        print(json.dumps(r, ensure_ascii=False, indent=1))
    return 3 if r["status"] == "GAP" else 0


if __name__ == "__main__":
    sys.exit(main())
