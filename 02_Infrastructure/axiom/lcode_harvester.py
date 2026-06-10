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
    return best


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


def harvest(project_dir: str) -> dict:
    arts = os.path.join(project_dir, "stage_artifacts")
    lcodes: list[dict] = []
    seen: set[str] = set()  # dedup by absolute path

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
        mode = _infer_mode(data, source_file)
        promoted = _check_promoted(l_code, project_dir)

        entry = {
            "l_code": l_code,
            "strategy_id": strategy_id,
            "lesson_text": lesson_text,
            "tags": tags,
            "family": family,
            "research_mode": mode,
            "construction_type": _infer_construction(data),
            "metric_type": _infer_metric_type(data, mode),
            "grade": data.get("grade"),
            "core_reference": core_reference,
            "source_file": source_file,
            "mtime": datetime.fromtimestamp(os.path.getmtime(p), tz=timezone.utc).isoformat(timespec="seconds"),
            "promoted_to_axiom": promoted,
        }
        # v8.1 트랙C+D: 학습/실측 필드 pass-through (있을 때만 — 없는 구 L-code는 그대로 = 정직성).
        # cluster_extractor가 mechanism_draft/oos_validation_draft/falsification_draft 실값 매핑에 사용.
        for opt in ("mechanism_hypothesis", "data_supported_conclusion", "next_probe",
                    "fmt_codes", "oos_retention", "falsification_attempts", "authoritative"):
            v = data.get(opt)
            if v not in (None, "", [], {}):
                entry[opt] = v
        lcodes.append(entry)

    lcodes.sort(key=lambda x: x["l_code"])

    return {
        "schema_version": "v54_ax_p0_mode",
        "last_updated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "n_lcodes": len(lcodes),
        "family_distribution": _family_dist(lcodes),
        "mode_distribution": _mode_dist(lcodes),
        "grade_distribution": _grade_dist(lcodes),
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
        g = x.get("grade") or "unknown"
        out[g] = out.get(g, 0) + 1
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
