#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
registry_validate_availability.py — 선언 availability ↔ 코드 강제점 정합 검증 (AST v1.1 §3-2)
==============================================================================================
2026-07-25. registry_migrate_ast_v11.py 동반 검증기. 두 층위:

  [L1] 구조 검증: 373 전량이 신규 4필드(availability/restatement_prone/vintage_available/
       refresh_mode) 보유 + enum·타입 유효. add_factor.R 라인-타겟 append가 신필드 없는
       엔트리를 추가하면 여기서 잡힘.
  [L2] 코드 강제점 대조: 선언 availability.rule ↔ 실제 코드 하드코딩 (파일을 파싱해
       하드코딩 실존 확인 후 도메인 선언과 대조). 불일치는 availability.known_discrepancy
       보유 엔트리만 허용 — 그 외 발견 시 FAIL 보고.

  코드 강제점 (2026-07-25 실측 라인):
    parse_fundamental_xlsx.R:199   Factor_Date := Period_Date + 45L   (전분기 일률 +45d)
    data_collector_dart.R:840      Factor_Date := bsns_year+1 "-03-31" (연간 3/31)
    data_collector_dart_quarterly.R:497-501  Q1 5/15 Q2 8/15 Q3 11/15 Q4 3/31 (분기 고정일)
    compute_investor.R:100         inv[Date < sig_d]                  (strict t-1)

종료코드: 0 = PASS(허용된 known_discrepancy만), 1 = FAIL(구조 위반 또는 미신고 불일치).
사용:
  .venv_qvest_ml/Scripts/python.exe 02_Infrastructure/factor_db/registry_validate_availability.py \
      [--registry <path>] [--skip-code-check]
"""
import argparse
import io
import json
import os
import re
import sys

ROOT = os.environ.get("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
DEFAULT_REGISTRY = os.path.join(ROOT, "02_Infrastructure", "factor_db", "factor_registry.json")

NEW_FIELDS = ("availability", "restatement_prone", "vintage_available", "refresh_mode")
VALID_AVAIL_TYPES = ("fixed", "regulatory", "manual_export")
VALID_REFRESH = ("auto", "manual")

# 코드 강제점 정의: (파일 상대경로, 존재해야 하는 정규식, 설명)
CODE_ENFORCEMENT_POINTS = [
    ("02_Infrastructure/data/parse_fundamental_xlsx.R",
     r'month\(Period_Date\)\s*==\s*12L[\s\S]{0,120}"-03-31"[\s\S]{0,120}Period_Date\s*\+\s*45L',
     "xlsx: Q4(말월=12)=익년 3/31 명시 고정, Q1~Q3=+45d (Q4 lag repair 2026-07-25 — C4 확정 정합)"),
    ("02_Infrastructure/data/data_collector_dart.R",
     r'Factor_Date\s*:=\s*as\.Date\(paste0\(bsns_year\s*\+\s*1,\s*"-03-31"\)\)',
     "DART annual: Factor_Date = 익년 3/31"),
    ("02_Infrastructure/data/data_collector_dart_quarterly.R",
     r'"-05-15"[\s\S]{0,200}"-08-15"[\s\S]{0,200}"-11-15"[\s\S]{0,200}"-03-31"',
     "DART quarterly: Q1 5/15 / Q2 8/15 / Q3 11/15 / Q4 익년 3/31 고정일"),
    ("02_Infrastructure/factor_db/compute_investor.R",
     r"inv\s*<-\s*inv\[Date\s*<\s*sig_d\]",
     "investor_flow: strict Date < sig_d (t-1)"),
]

# 도메인 기대 선언 (마이그레이션 규칙과 동일 — 이탈 시 FAIL)
EXPECTED_DECLARATION = {
    "rawdata":          {"type": "fixed",         "rule": "T-1"},
    "price":            {"type": "fixed",         "rule": "T-1"},
    "investor_flow":    {"type": "manual_export", "rule": "strict_t-1;effective_lag~22d"},
    "fundamental":      {"type": "regulatory",    "rule": "quarterly+45d;annual_3/31"},
    "fundamental_xlsx": {"type": "regulatory",    "rule": "quarterly+45d;annual_3/31"},
    "consensus":        {"type": "fixed",         "rule": "T-1"},
    "macro":            {"type": "regulatory",    "rule": "C11_publication_lag"},
    "macro_fred":       {"type": "fixed",         "rule": "-1d"},
}

# 코드 강제와 선언이 어긋나는 도메인 → known_discrepancy 보유 의무
# (xlsx: 연간도 +45d vs 선언 annual_3/31 / fundamental: 혼합 basis /
#  consensus: 코드 same-day vs 선언 T-1 / macro: 1일 근사 vs 실제 발표 lag)
# (2026-07-25 Q4 lag repair 반영) fundamental/fundamental_xlsx는 코드가 Q4=3/31로 수리되어
# 선언≠코드 불일치 해소 — known_discrepancy 의무 목록에서 해제. consensus(코드 same-day vs 선언 T-1)·
# macro(발표 lag 1일 근사)는 잔존.
DOMAINS_REQUIRING_KD = ("consensus", "macro")


def check_structure(reg):
    errs = []
    for fid, e in reg.items():
        missing = [k for k in NEW_FIELDS if k not in e]
        if missing:
            errs.append("%s: 신규 필드 결측 %s" % (fid, missing))
            continue
        av = e["availability"]
        if not isinstance(av, dict) or "type" not in av or "rule" not in av:
            errs.append("%s: availability 구조 위반 (dict{type,rule} 아님): %r" % (fid, av))
            continue
        if av["type"] not in VALID_AVAIL_TYPES:
            errs.append("%s: availability.type 무효 '%s'" % (fid, av["type"]))
        if not isinstance(av["rule"], str) or not av["rule"]:
            errs.append("%s: availability.rule 비문자열/공백" % fid)
        if not isinstance(e["restatement_prone"], bool):
            errs.append("%s: restatement_prone 비불리언" % fid)
        if not isinstance(e["vintage_available"], bool):
            errs.append("%s: vintage_available 비불리언" % fid)
        if e["refresh_mode"] not in VALID_REFRESH:
            errs.append("%s: refresh_mode 무효 '%s'" % (fid, e["refresh_mode"]))
        if "lag_rule" not in e:
            errs.append("%s: lag_rule(사람용 주석) 소실 — 보존 의무 위반" % fid)
    return errs


def check_code_points():
    errs, infos = [], []
    for rel, pat, desc in CODE_ENFORCEMENT_POINTS:
        p = os.path.join(ROOT, rel)
        if not os.path.exists(p):
            errs.append("강제점 파일 부재: %s" % rel)
            continue
        with io.open(p, "r", encoding="utf-8", errors="replace") as f:
            src = f.read()
        if re.search(pat, src):
            infos.append("OK  %s — %s" % (rel, desc))
        else:
            errs.append("강제점 하드코딩 미발견: %s — %s (코드 변경? 선언 재검토 필요)" % (rel, desc))
    return errs, infos


def check_declaration_vs_domain(reg):
    errs = []
    for fid, e in reg.items():
        if not all(k in e for k in NEW_FIELDS):
            continue  # 구조 검증에서 이미 보고
        ds = e.get("data_source")
        exp = EXPECTED_DECLARATION.get(ds)
        if exp is None:
            errs.append("%s: 미지의 data_source '%s' — 기대 선언 부재" % (fid, ds))
            continue
        av = e["availability"]
        if not isinstance(av, dict):
            continue
        if av.get("type") != exp["type"] or av.get("rule") != exp["rule"]:
            errs.append("%s: 선언 이탈 — availability {%s,%s} != 기대 {%s,%s} (data_source=%s)"
                        % (fid, av.get("type"), av.get("rule"), exp["type"], exp["rule"], ds))
        if ds in DOMAINS_REQUIRING_KD and not av.get("known_discrepancy"):
            errs.append("%s: data_source=%s 는 선언≠코드 실측 불일치 도메인 — "
                        "availability.known_discrepancy 결측 (침묵 codify 금지)" % (fid, ds))
    return errs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--registry", default=DEFAULT_REGISTRY)
    ap.add_argument("--skip-code-check", action="store_true")
    args = ap.parse_args()

    with io.open(args.registry, "r", encoding="utf-8") as f:
        reg = json.load(f)  # json 유효성 자체가 첫 게이트
    print("[validate] registry: %s — entries=%d" % (args.registry, len(reg)))

    all_errs = []
    s_errs = check_structure(reg)
    print("[L1 구조] %s (%d건 위반)" % ("PASS" if not s_errs else "FAIL", len(s_errs)))
    all_errs += s_errs

    if not args.skip_code_check:
        c_errs, c_infos = check_code_points()
        for m in c_infos:
            print("  [L2 강제점] " + m)
        print("[L2 강제점] %s (%d건 위반)" % ("PASS" if not c_errs else "FAIL", len(c_errs)))
        all_errs += c_errs

    d_errs = check_declaration_vs_domain(reg)
    print("[L2 선언대조] %s (%d건 위반)" % ("PASS" if not d_errs else "FAIL", len(d_errs)))
    all_errs += d_errs

    if all_errs:
        print("\n== 위반 상세 (%d) ==" % len(all_errs))
        for m in all_errs:
            print("  FAIL " + m)
        sys.exit(1)
    print("[validate] 전체 PASS — 불일치는 known_discrepancy 신고분만 존재")
    sys.exit(0)


if __name__ == "__main__":
    main()
