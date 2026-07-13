#!/usr/bin/env python3
"""
L-code Harvester — Sprint 4 AX-P0 Layer 1

퀀트 리서치 산출물(L-code)을 유일한 primary 원천으로 삼아 normalized corpus를
생성한다. Axiom 엔진의 입력 단.

Inputs:
  - stage_artifacts/l_code_*.json            (flat, back-compat)
  - stage_artifacts/l_code/<mode>/l_code_*.json  (mode-separated; e.g. alpha_search/)
  - qepm/memory/axioms/active/AX-*.json (승격된 L-code 역링크 확인용)

Output:
  .cache/lcode_corpus.json

Schema:
  {
    "schema_version": "v54_ax_p0_mode",
    "last_updated": ISO8601,
    "n_lcodes": int,
    "mode_distribution": {mode: count, ...},
    "lcodes": [
      {
        "l_code": "L-XXX",
        "strategy_id": str,
        "lesson_text": str,
        "tags": [str, ...],
        "family": str | null,        (inferred from strategy_id/tags)
        "research_mode": str,         (explicit field > directory > heuristic)
        "grade": "A|B|C|F",
        "core_reference": str,
        "source_file": str,          (relative path)
        "mtime": ISO8601,
        "promoted_to_axiom": str | null  (AX-XXX if already promoted)
      }
    ]
  }

Usage: python3 lcode_harvester.py [--project-dir PATH]
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys
from datetime import datetime, timezone

RE_LCODE = re.compile(r"L-\d+")
RE_STR = re.compile(r"STR_\d+[A-Za-z0-9_]*")

FAMILY_KEYWORDS = {
    "quality_earnings": ["Q07", "Q03", "earnings_stability", "accrual_quality", "piotroski"],
    "quality_profitability": ["Q01", "GPA", "profitability", "CBPQ", "cash_profitability", "GSCD"],
    "value": ["EP", "BP", "value_trap", "BCSNA", "sector_neutral_accrual"],
    "defense": ["D29", "D25", "D04", "lowbeta", "defense"],
    "momentum": ["M01", "IndMom", "momentum", "모멘텀", "mom12", "mom6", "12-1", "6-1",
                 "factor_mom", "추세", "trend", "reversal", "역방향", "52주", "저점", "mean-rev"],
    "ml_complexity": ["CVaR_LP", "XGB", "ML", "HRP", "FM", "factor_vol", "lightgbm",
                      "ensemble", "앙상블", "딥러닝", "신경망", "ngboost"],
    "behavioral": ["contrarian", "flow", "ret_autocorr", "atypicality", "수급", "투자자"],
    "consensus": ["C19", "consensus", "analyst"],
}

# v2 (2026-07-04 엔진 재설계): unknown 146건 해소용 확장 15군 — 기본 8군 무매치 시에만
# 순차 적용 (기본 8군 기존 분류 결과 불변 보장. distill plan family_reclassification 정합:
# low_vol/liquidity/consensus_analyst/flow_supply/earnings_event/value/quality/seasonality/
# options_derivatives/network_info/overlay_regime/size/dividend/technical_price/infra_process).
FAMILY_KEYWORDS_EXT = {
    # infra_process 우선 — 인프라/프로세스 기록이 팩터 키워드에 오분류되는 것 차단
    "infra_process": ["hook", "훅", "버그", "bug", "세그폴트", "segfault", "파이프라인",
                      "pipeline", "인프라", "infra", "캐시", "cache", "스키마", "schema",
                      "registry", "레지스트리", "무결성", "integrity", "미래참조", "lookahead",
                      "look-ahead", "인코딩", "encoding", "role_honesty", "프로세스 규칙",
                      "harness", "하네스", "워크플로", "mailbox", "체크리스트"],
    "overlay_regime": ["overlay", "오버레이", "regime", "국면", "vol-target", "vol target",
                       "볼타겟", "타이밍", "timing", "절대모멘텀", "dd-brake", "dd_brake",
                       "낙폭 브레이크", "crash protection", "크래시", "현금화", "cash overlay",
                       "market timing", "시장 타이밍", "turning point", "변곡"],
    "low_vol": ["low-vol", "low vol", "lowvol", "저변동", "min-vol", "minvol",
                "minimum variance", "저베타", "low beta", "idiosyncratic vol", "ivol",
                "residual vol", "잔차 변동성", "변동성 역가중", "beta_asym"],
    "value": ["pbr", "per", "저평가", "밸류", "가치주", "book-to-market", "b/m",
              "earnings yield", "청산가치", "ncav"],
    "quality": ["quality", "퀄리티", "qmj", "roe", "roa", "이익의 질", "재무 건전"],
    "dividend": ["배당", "dividend", "주주환원", "shareholder yield", "자사주", "buyback"],
    "liquidity": ["amihud", "illiquid", "유동성 프리미엄", "거래대금 회전", "turnover ratio",
                  "liquidity premium", "저유동성"],
    "flow_supply": ["외국인", "기관 매수", "기관 순매수", "공매도", "short interest",
                    "insider", "내부자", "수급", "매수 강도", "othercorp", "지분 공시"],
    "earnings_event": ["pead", "earnings surprise", "어닝 서프라이즈", "이익 서프라이즈",
                       "실적 발표", "earnings announcement", "sue", "리비전", "revision",
                       "추정치 변화", "esbr", "escr", "목표주가 갭", "tp_gap"],
    "consensus_analyst": ["컨센서스", "애널리스트", "목표주가", "target price", "recommend",
                          "투자의견"],
    "seasonality": ["계절성", "seasonal", "january", "월별 효과", "월중", "turn-of-month",
                    "월말", "요일 효과"],
    "options_derivatives": ["옵션", "option", "implied vol", "내재변동성", "put-call",
                            "선물 베이시스", "futures basis", "파생"],
    "network_info": ["네트워크", "network", "supply chain", "공급망", "peer", "연관 기업",
                     "graph", "lead-lag", "리드랙"],
    "size": ["소형주", "small-cap", "small cap", "시가총액 하위", "마이크로캡", "microcap"],
    "technical_price": ["갭 빈도", "gap_freq", "overnight", "intraday", "오버나이트",
                        "기술적", "technical", "캔들", "가격 패턴", "hurst", "허스트",
                        "fip", "pcdm", "고점 대비", "신고가"],
}


def _load(path: str):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def _infer_family(strategy_id: str, tags: list[str], lesson_text: str,
                  core_reference: str = "") -> str | None:
    text = ((strategy_id or "") + " " + " ".join(tags or []) + " "
            + (lesson_text or "")[:500] + " " + (core_reference or "")[:200])
    text_lower = text.lower()
    best = None
    best_hits = 0
    for fam, kws in FAMILY_KEYWORDS.items():
        hits = sum(1 for kw in kws if kw.lower() in text_lower)
        if hits > best_hits:
            best_hits = hits
            best = fam
    if best is not None:
        return best
    # v2: 기본 8군 무매치분만 확장 15군 순차 적용 (기존 분류 불변 — dict 순서 = 우선순위,
    # infra_process가 최우선. best-hits가 아닌 first-match: 확장군은 상호 배타 키워드).
    for fam, kws in FAMILY_KEYWORDS_EXT.items():
        if any(kw.lower() in text_lower for kw in kws):
            return fam
    return None


# ── v2: grade 정규화 (plan JSON grade_normalization_map 소비 — lcode_schema.R 정합) ──
_DEFAULT_GRADE_MAP = {
    "A": "A", "A_NOVEL": "A", "A_DEF": "A", "A_CONDITIONAL": "A",
    "A_CONDITIONAL_REAFFIRMED": "A", "B": "B", "B_ARCHIVE": "B",
    "C": "C", "F": "F", "REJECT": "F",
    "INFRASTRUCTURE": "PROCESS", "INFRASTRUCTURE_CRITICAL": "PROCESS",
    "INFRASTRUCTURE_PROCESS": "PROCESS", "METHODOLOGY": "PROCESS",
    "PROCESS_INTEGRITY_RULE": "PROCESS", "ROLE_HONESTY_RULE": "PROCESS",
    "PROCESS_RULE (Defense composite admission operational rule)": "PROCESS",
    "PROCESS_RULE (infra bug pattern)": "PROCESS",
    "SR_CEILING_FINDING": "PROCESS",
    "N/A (factor-level discovery)": "PROCESS",
    "N/A (axiom-level discovery synthesis)": "PROCESS",
    "TIER2_SUMMARY": "PROCESS", "TIER3_SUMMARY": "PROCESS",
}
# PROCESS-class grade → record_type 세분 (lcode_schema.R LCODE_PROCESS_GRADE_MAP 정합)
_PROCESS_RECORD_TYPE = {
    "INFRASTRUCTURE": "infra", "INFRASTRUCTURE_CRITICAL": "infra",
    "INFRASTRUCTURE_PROCESS": "infra",
    "TIER2_SUMMARY": "summary", "TIER3_SUMMARY": "summary",
}


def _load_grade_map(project_dir: str) -> dict:
    """distill plan JSON의 grade_normalization_map 소비. 부재 시 내장 기본맵."""
    plan_path = os.path.join(project_dir, "06_Registry", "lcode_distill_plan_20260704.json")
    plan = _load(plan_path)
    if isinstance(plan, dict):
        gm = (plan.get("grade_normalization_map") or {}).get("map")
        if isinstance(gm, dict) and gm:
            return gm
    return dict(_DEFAULT_GRADE_MAP)


def _load_plan_family_map(project_dir: str) -> dict:
    """distill plan dispositions의 (source_file → family) 소비 — 키워드 무매치분 폴백 전용.

    plan family_reclassification(unknown 143→8)의 per-lcode 확정 분류를 재사용한다.
    키워드 매치가 있는 엔트리는 override하지 않는다 (결정론 + 신규 L-code 일반화 유지).
    """
    plan_path = os.path.join(project_dir, "06_Registry", "lcode_distill_plan_20260704.json")
    plan = _load(plan_path)
    out: dict[str, str] = {}
    if isinstance(plan, dict):
        for d in plan.get("dispositions") or []:
            f = str(d.get("file") or "").replace("\\", "/")
            fam = d.get("family")
            if f and fam and fam != "unknown":
                out[f] = str(fam)
    return out


def _normalize_grade(grade_raw, record_type_explicit, grade_map: dict):
    """반환: (grade_norm | None, record_type). PROCESS-class는 grade=None + record_type 분리."""
    rt = str(record_type_explicit) if record_type_explicit else None
    if grade_raw is None or grade_raw == "":
        return None, (rt or "performance")
    g = str(grade_raw)
    mapped = grade_map.get(g)
    if mapped == "PROCESS":
        return None, (rt or _PROCESS_RECORD_TYPE.get(g, "process"))
    if mapped in ("A", "B", "C", "F"):
        return mapped, (rt or "performance")
    # unmappable(예: 'unknown') — 원문 보존 + performance 취급 (정직 원장)
    return g, (rt or "performance")


def _infer_mode(data: dict, source_file: str) -> str:
    """Infer research_mode. Priority: explicit field > directory > created_by/strategy_id pattern.

    모드별 L-code 분리: stage_artifacts/l_code/<mode>/ 디렉터리이거나 research_mode 필드가
    있으면 그 모드. 기존 평면 파일(stage_artifacts/l_code_*.json)은 출처 추론.
    """
    explicit = data.get("research_mode")
    if explicit:
        return str(explicit)
    # directory-based: .../l_code/<mode>/l_code_*.json
    parts = source_file.replace("\\", "/").split("/")
    if "l_code" in parts:
        i = parts.index("l_code")
        if i + 1 < len(parts) - 1:  # there is a subdir between l_code/ and the file
            return parts[i + 1]
    # source/created_by/strategy_id heuristics (back-compat for flat files)
    created_by = str(data.get("created_by") or "").lower()
    source = str(data.get("source") or "").lower()
    sid = str(data.get("strategy_id") or "")
    if sid.startswith("STR_AS_"):
        return "alpha_search"
    if "judge" in created_by or "judge" in source:
        return "judge_gate"
    if "governor" in created_by or "governor" in source or "admission" in sid.lower():
        return "governor_admission"
    if created_by == "scout":
        return "alpha_research"
    return "qepm_legacy"


_CONSTRUCTION_KEYWORDS = {
    # momentum을 reversal보다 먼저 체크 + "역방향"(실패 lesson 상투어 "역방향 가설 탐색 후보") 제거
    "momentum": ["momentum", "모멘텀", "mom12", "mom6", "12-1", "6-1", "추세", "trend"],
    "reversal": ["reversal", "52주", "저점", "mean-rev", "단기반전"],
    "ml_sizing": ["ml", "xgb", "lightgbm", "ensemble", "앙상블", "딥러닝", "신경망", "ngboost"],
    "value": ["value", "밸류", "per", "pbr", " ep", "저평가", "장부"],
    "quality": ["quality", "퀄리티", " gp", "수익성", "profitab"],
    "low_vol": ["저변동", "low-vol", "lowvol", "변동성"],
    "dividend": ["배당", "dividend"],
    "size": ["규모", "size", "소형", "중소형", "small-cap"],
}


def _infer_construction(data: dict) -> str:
    """construction_type 추론(r7 Independence 축). explicit 필드 우선, 없으면 키워드."""
    explicit = data.get("construction_type")
    if explicit:
        return str(explicit)
    text = (str(data.get("strategy_id") or "") + " " + str(data.get("core_reference") or "")
            + " " + str(data.get("lesson_text") or "")[:300] + " "
            + " ".join(data.get("tags") or [])).lower()
    for ct, kws in _CONSTRUCTION_KEYWORDS.items():
        if any(kw in text for kw in kws):
            return ct
    return "single_factor_long_only"


def _infer_metric_type(data: dict, mode: str) -> str:
    """metric_type 추론(INV-1 게이트 입력). explicit 우선, 없으면 모드 기반 보수 추론."""
    mt = data.get("metric_type")
    if mt:
        return str(mt)
    if mode == "alpha_search":
        return "proxy"
    if mode in ("factor_rotation", "regime_research"):
        return "backtested"
    return "estimated"  # 불명확 → 보수적(mode-local 한정)


def _check_promoted(l_code: str, project_dir: str) -> str | None:
    """Scan active axioms for supporting_l_codes containing this L-code."""
    active_dir = os.path.join(project_dir, "qepm", "memory", "axioms", "active")
    if not os.path.isdir(active_dir):
        return None
    for ax_path in glob.glob(os.path.join(active_dir, "AX-*.json")):
        ax = _load(ax_path)
        if not isinstance(ax, dict):
            continue
        supporting = ax.get("supporting_l_codes", [])
        if isinstance(supporting, list) and l_code in supporting:
            return ax.get("axiom_id") or os.path.basename(ax_path).replace(".json", "")
    return None


_MODE_ALIASES = {"qepm": "qepm_legacy"}  # lcode_schema.R LCODE_MODE_ALIASES 정합 (promote GEN 폴백 봉합)


def harvest(project_dir: str) -> dict:
    arts = os.path.join(project_dir, "stage_artifacts")
    lcodes: list[dict] = []
    seen: set[str] = set()  # dedup by absolute path
    grade_map = _load_grade_map(project_dir)
    plan_family = _load_plan_family_map(project_dir)
    id_first_file: dict[str, str] = {}  # v2: l_code ID 충돌 감지 (A1-F6)
    n_id_collisions = 0

    # Flat (back-compat) + mode-separated subdirectories (stage_artifacts/l_code/<mode>/).
    patterns = [
        os.path.join(arts, "l_code_*.json"),
        os.path.join(arts, "l_code", "**", "l_code_*.json"),
    ]
    paths: list[str] = []
    for pat in patterns:
        paths.extend(glob.glob(pat, recursive=True))

    for p in sorted(paths):
        ap = os.path.abspath(p)
        if ap in seen:
            continue
        seen.add(ap)
        data = _load(p)
        if not isinstance(data, dict):
            continue
        l_code = data.get("l_code")
        if not l_code:
            # try to extract from filename
            m = RE_LCODE.search(os.path.basename(p))
            l_code = m.group(0) if m else None
        if not l_code:
            continue

        strategy_id = data.get("strategy_id", "")
        tags = data.get("tags", []) or []
        lesson_text = data.get("lesson_text", "") or ""
        core_reference = data.get("core_reference", "")
        source_file = os.path.relpath(p, project_dir)
        family = _infer_family(strategy_id, tags, lesson_text, core_reference)
        if family is None:  # v2: 키워드 무매치 → plan 확정 분류 폴백 (unknown 146→8)
            family = plan_family.get(source_file.replace("\\", "/"))
        mode = _infer_mode(data, source_file)
        mode = _MODE_ALIASES.get(mode, mode)  # v2: qepm→qepm_legacy normalize
        promoted = _check_promoted(l_code, project_dir)

        # v2: ID 충돌 감지 (같은 l_code가 서로 다른 파일 — WARN + 마킹, 원장 정직 보존)
        collision_with = None
        if l_code in id_first_file:
            collision_with = id_first_file[l_code]
            n_id_collisions += 1
            print(f"[lcode_harvester][WARN] l_code ID collision: {l_code} "
                  f"({source_file} vs {collision_with}) — REASSIGN_ID 대상 검토", file=sys.stderr)
        else:
            id_first_file[l_code] = source_file

        # v2: grade 정규화 (plan grade_normalization_map) + record_type 분리
        grade_raw = data.get("grade")
        grade_norm, record_type = _normalize_grade(grade_raw, data.get("record_type"), grade_map)

        entry = {
            "l_code": l_code,
            "strategy_id": strategy_id,
            "lesson_text": lesson_text,
            "tags": tags,
            "family": family,
            "research_mode": mode,
            "construction_type": _infer_construction(data),
            "metric_type": _infer_metric_type(data, mode),
            "grade": grade_norm,          # canonical A/B/C/F | None(비성과) | 원문(unmappable)
            "grade_raw": grade_raw,       # 원문 보존 (정직 원장)
            "record_type": record_type,   # performance/process/infra/summary
            "core_reference": core_reference,
            "source_file": source_file,
            "mtime": datetime.fromtimestamp(os.path.getmtime(p), tz=timezone.utc).isoformat(timespec="seconds"),
            "promoted_to_axiom": promoted,
        }
        if collision_with:
            entry["id_collision_with"] = collision_with
        # v8.1 트랙C+D: 학습/실측 필드 pass-through (있을 때만 — 없는 구 L-code는 그대로 = 정직성).
        # cluster_extractor가 mechanism_draft/oos_validation_draft/falsification_draft 실값 매핑에 사용.
        # v8.2.1 (2026-07-03 아키텍처 감사 AXM-06/GOV-01): oos_months·oos_effect_vs_is는 External 축,
        # portfolio_alpha_t는 promote_global essence 게이트(weakest_t)와 promote.R Rigor 축이 소비 —
        # 미전달 시 global 승격이 구조적으로 불가하던 갭 봉합.
        # v2 (2026-07-04): selection_type·lcode_schema_version 추가 (emit v2 신필드).
        for opt in ("mechanism_hypothesis", "data_supported_conclusion", "next_probe",
                    "fmt_codes", "oos_retention", "falsification_attempts", "authoritative",
                    "oos_months", "oos_effect_vs_is", "portfolio_alpha_t",
                    "selection_type", "lcode_schema_version"):
            v = data.get(opt)
            if v not in (None, "", [], {}):
                entry[opt] = v
        lcodes.append(entry)

    lcodes.sort(key=lambda x: x["l_code"])

    return {
        "schema_version": "v2_engine_redesign_20260704",
        "last_updated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "n_lcodes": len(lcodes),
        "family_distribution": _family_dist(lcodes),
        "mode_distribution": _mode_dist(lcodes),
        "grade_distribution": _grade_dist(lcodes),
        "record_type_distribution": _record_type_dist(lcodes),
        "n_id_collisions": n_id_collisions,
        "n_promoted": sum(1 for x in lcodes if x["promoted_to_axiom"]),
        "lcodes": lcodes,
    }


def _family_dist(lcodes: list[dict]) -> dict[str, int]:
    out: dict[str, int] = {}
    for x in lcodes:
        fam = x.get("family") or "unknown"
        out[fam] = out.get(fam, 0) + 1
    return dict(sorted(out.items(), key=lambda kv: -kv[1]))


def _mode_dist(lcodes: list[dict]) -> dict[str, int]:
    out: dict[str, int] = {}
    for x in lcodes:
        m = x.get("research_mode") or "unknown"
        out[m] = out.get(m, 0) + 1
    return dict(sorted(out.items(), key=lambda kv: -kv[1]))


def _grade_dist(lcodes: list[dict]) -> dict[str, int]:
    out: dict[str, int] = {}
    for x in lcodes:
        g = x.get("grade")
        if g is None:  # 비성과 기록 — record_type으로 집계 (grade 없음)
            g = f"(record_type={x.get('record_type', 'process')})"
        out[g] = out.get(g, 0) + 1
    return out


def _record_type_dist(lcodes: list[dict]) -> dict[str, int]:
    out: dict[str, int] = {}
    for x in lcodes:
        rt = x.get("record_type") or "performance"
        out[rt] = out.get(rt, 0) + 1
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--project-dir",
        default=os.environ.get("QVEST_PROJECT_DIR")
        or os.environ.get("CLAUDE_PROJECT_DIR") or os.environ.get("QM_ROOT") or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    )
    ap.add_argument("--output", default=None)
    args = ap.parse_args()

    out = args.output or os.path.join(args.project_dir, ".cache", "lcode_corpus.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)

    corpus = harvest(args.project_dir)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(corpus, f, indent=2, ensure_ascii=False)

    print(
        f"[lcode_harvester] {out} — n={corpus['n_lcodes']} "
        f"promoted={corpus['n_promoted']} "
        f"families={corpus['family_distribution']} "
        f"grades={corpus['grade_distribution']}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
