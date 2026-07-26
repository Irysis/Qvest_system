#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
registry_migrate_ast_v11.py — factor_registry 기계가독 승격 (AST v1.1 SOT §3-2 Step 1)
=====================================================================================
2026-07-25. 1회성 deliberate 전량 마이그레이션 (백업 + 검증 동반 — 13k줄 reformat 함정의
명시적 예외). 재실행 가능·멱등: 4개 신규 필드가 모두 있는 엔트리는 건드리지 않음.

각 엔트리에 추가되는 필드 (update_freq 뒤 삽입):
  "availability": {"type": "fixed|regulatory|manual_export", "rule": "<기계가독>",
                   ["known_discrepancy": "<선언≠구현 실측 불일치 — 침묵 codify 금지>"]}
  "restatement_prone": bool
  "vintage_available": bool
  "refresh_mode": "auto|manual"

도출 근거 = 06_Registry/ast_field_map_v0.json 도메인 실측 (2026-07-25):
  rawdata/price    : A1 (수정주가 재작성=restatement true, pin 사본=vintage true, 일배치 00:03)
  investor_flow    : A6/A7/FDB-B4 (수동 QW export 실효 ~22일, compute_investor.R:100 strict t-1)
  fundamental(_xlsx): C-* (분기 +45d·연간 3/31, 정정공시 재작성·vintage 미보존, 수동 refresh)
  consensus        : C-CONSENSUS-QW (as-of daily vintage 보유, incremental append 과거행 불변)
  macro/macro_fred : E1/FDB-B5/E11 (FRED 개정=restatement true, C11 publication lag / sig_d-1)

기존 lag_rule 자유문자열은 보존 (사람용 주석으로 강등 — 리네임·삭제 금지).

사용:
  .venv_qvest_ml/Scripts/python.exe 02_Infrastructure/factor_db/registry_migrate_ast_v11.py \
      [--registry <path>] [--dry-run]
  기본: canonical + .cache 2사본 모두 마이그레이션.
"""
import argparse
import io
import json
import os
import sys
from collections import OrderedDict

ROOT = os.environ.get("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
DEFAULT_TARGETS = [
    os.path.join(ROOT, "02_Infrastructure", "factor_db", "factor_registry.json"),
    os.path.join(ROOT, ".cache", "factor_db", "factor_registry.json"),
]

NEW_FIELDS = ("availability", "restatement_prone", "vintage_available", "refresh_mode")

# ── 도메인 도출 규칙 (data_source → 4필드) — ast_field_map_v0 실측 기준 ──────────
KD_FUND = (
    "혼합 basis: fundamental_merged 내 XLSX-source 행은 전분기 일률 Period_Date+45d"
    "(Q4 포함, parse_fundamental_xlsx.R:199), DART-source 행은 연간 익년 3/31"
    "(data_collector_dart.R:840)·분기 고정일 5/15·8/15·11/15·3/31"
    "(data_collector_dart_quarterly.R:557-560, 라인 갱신 2026-07-26). 동일 키 충돌 시 DART 우선 dedupe"
    "(parse_fundamental_xlsx.R:349-358). C4 3-way(pit.md '연간 5월' vs DART 3/31 vs "
    "xlsx +45d) 불일치 — 도훈 결정 대기 (ast_field_map_v0 fundamentals)"
)
KD_XLSX = (
    "xlsx 생산측 Factor_Date = 전분기 일률 Period_Date+45d (parse_fundamental_xlsx.R:199)"
    " — Q4(연간)도 +45d(≈익년 2/14)로 선언 annual_3/31보다 공격적. C4 3-way"
    "(pit.md '연간 5월' vs DART 3/31 vs xlsx +45d) 불일치 — 도훈 결정 대기"
    " (ast_field_map_v0 C-QWXLSX-RAW)"
)
KD_CONS = (
    "코드 강제점은 Date <= sig_d(same-day 허용: factor_db_builder.R:441 .pit_consensus, "
    "compute_consensus.R:33) — 선언 T-1과 비대칭(구 lag_rule 'T-1 disclosure' 명시는 "
    "4/33건뿐, 제공 시각 메타 부재로 당일값 사용 미검증. ast_field_map_v0 C-REGISTRY-PTR-CONS)"
)
KD_MACRO = (
    "실제 발표 lag(예: CPI 수주)는 코드에서 1일 근사로만 강제 — compute_regime.R:31-32 "
    "Date <= sig_d(월간 as-of)·:75-77 FRED sig_d-1. 선언(C11 publication lag) 대비 약한 강제"
    " (ast_field_map_v0 FDB-B5)"
)

DOMAIN_MAP = {
    "rawdata": {
        "availability": {"type": "fixed", "rule": "T-1"},
        "restatement_prone": True,   # 수정주가 원장 전기간 재작성 (A1)
        "vintage_available": True,   # pin_cache 사본 (RAWDATA_pin*, §7)
        "refresh_mode": "auto",      # 일배치 cron 00:03 KST (daily_refresh.sh)
    },
    "price": {
        "availability": {"type": "fixed", "rule": "T-1"},
        "restatement_prone": True,
        "vintage_available": True,
        "refresh_mode": "auto",
    },
    "investor_flow": {
        "availability": {"type": "manual_export",
                         "rule": "strict_t-1;effective_lag~22d"},
        "restatement_prone": False,
        "vintage_available": False,
        "refresh_mode": "manual",    # QuantiWise 수동 export (A6)
    },
    "fundamental": {
        "availability": {"type": "regulatory",
                         "rule": "quarterly+45d;annual_3/31",
                         "known_discrepancy": KD_FUND},
        "restatement_prone": True,   # 정정공시 재작성, vintage 미보존 (C-*)
        "vintage_available": False,
        "refresh_mode": "manual",    # fundamental_merged on_demand 도훈 수동
    },
    "fundamental_xlsx": {
        "availability": {"type": "regulatory",
                         "rule": "quarterly+45d;annual_3/31",
                         "known_discrepancy": KD_XLSX},
        "restatement_prone": True,
        "vintage_available": False,
        "refresh_mode": "manual",
    },
    "consensus": {
        "availability": {"type": "fixed", "rule": "T-1",
                         "known_discrepancy": KD_CONS},
        "restatement_prone": False,  # incremental append 과거행 불변 (C-CONSENSUS-QW)
        "vintage_available": True,   # as-of daily 시계열 = 컨센서스-레벨 vintage
        "refresh_mode": "manual",    # Consensus.xlsx QW export 기반
    },
    "macro": {
        "availability": {"type": "regulatory", "rule": "C11_publication_lag",
                         "known_discrepancy": KD_MACRO},
        "restatement_prone": True,   # FRED 개정 시리즈 latest-vintage overwrite (E1)
        "vintage_available": False,
        "refresh_mode": "auto",      # daily_refresh.sh:187
    },
    "macro_fred": {
        "availability": {"type": "fixed", "rule": "-1d"},  # compute_regime.R:75-77 sig_d-1
        "restatement_prone": True,
        "vintage_available": False,
        "refresh_mode": "auto",
    },
}


def migrate_entry(fid, entry):
    """엔트리 1건에 신규 필드 주입. 이미 4필드 전부 보유 시 무변경(멱등).
    반환: (new_entry, changed:bool)"""
    if all(k in entry for k in NEW_FIELDS):
        return entry, False
    ds = entry.get("data_source")
    if ds not in DOMAIN_MAP:
        raise SystemExit(
            "[migrate] FAIL-LOUD: 미지의 data_source '%s' (entry %s) — 도출 규칙 부재. "
            "DOMAIN_MAP 확장 후 재실행." % (ds, fid))
    derived = DOMAIN_MAP[ds]
    out = OrderedDict()
    inserted = False
    keys = list(entry.keys())
    anchor = "update_freq" if "update_freq" in entry else (
        "lag_rule" if "lag_rule" in entry else None)
    for k in keys:
        out[k] = entry[k]
        if k == anchor:
            for nf in NEW_FIELDS:
                out[nf] = entry.get(nf, json.loads(json.dumps(derived[nf])))
            inserted = True
    if not inserted:  # anchor 부재 — 말미 추가
        for nf in NEW_FIELDS:
            if nf not in out:
                out[nf] = json.loads(json.dumps(derived[nf]))
    return out, True


def migrate_file(path, dry_run=False):
    with io.open(path, "r", encoding="utf-8") as f:
        reg = json.load(f, object_pairs_hook=OrderedDict)
    n_total, n_changed = 0, 0
    new_reg = OrderedDict()
    for fid, entry in reg.items():
        n_total += 1
        new_entry, changed = migrate_entry(fid, entry)
        new_reg[fid] = new_entry
        n_changed += int(changed)
    if dry_run:
        print("[migrate][dry-run] %s: entries=%d would-change=%d" % (path, n_total, n_changed))
        return n_total, n_changed
    if n_changed == 0:
        print("[migrate] %s: entries=%d 변경 0 (이미 마이그레이션됨 — 멱등 no-op)" % (path, n_total))
        return n_total, 0
    # 원 파일 규약 유지: UTF-8 no-BOM, LF, 2-space indent + 말미 개행
    tmp = path + ".tmp_migrate"
    payload = json.dumps(new_reg, ensure_ascii=False, indent=2) + "\n"
    with io.open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(payload)
    # round-trip 검증 후 원자 교체 (temp-rename 패턴)
    with io.open(tmp, "r", encoding="utf-8") as f:
        chk = json.load(f)
    assert len(chk) == n_total, "round-trip entry count mismatch"
    assert all(all(k in v for k in NEW_FIELDS) for v in chk.values()), \
        "round-trip: 신규 필드 결측 엔트리 존재"
    os.replace(tmp, path)
    print("[migrate] %s: entries=%d changed=%d — 기록 완료" % (path, n_total, n_changed))
    return n_total, n_changed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--registry", action="append", default=None,
                    help="대상 registry 경로 (복수 지정 가능; 기본 canonical+.cache)")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    targets = args.registry or DEFAULT_TARGETS
    for p in targets:
        if not os.path.exists(p):
            print("[migrate] SKIP (부재): %s" % p)
            continue
        migrate_file(p, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
