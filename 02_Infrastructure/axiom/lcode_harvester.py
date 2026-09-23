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

⚠ 정본 우회 방지 (2026-07-13 task#54-2): --output으로 커스텀 출력을 지정해도
  정본 corpus(.cache/lcode_corpus.json)를 **함께 갱신**한다(이중 쓰기).
  배경: 커스텀 출력이 정본을 우회 → corpus 정체 → hypothesis_index 중복방지
  게이트가 이틀간 실명하던 07-13 실사고. 정본 갱신을 생략할 방법은 없다
  (의도적 미제공 — 정본이 항상 최신이어야 신선도 사슬이 성립).

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
import functools
import glob
import json
import math
import os
import re
import sys
import time
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


@functools.lru_cache(maxsize=4096)
def _kw_pattern(kw_lower: str) -> "re.Pattern[str]":
    r"""팩터 키워드의 단어경계 매처 (2026-07-18 W29 /cleaner 근본원인 수리 — task_07f3ac0e).

    구 구현의 substring 매칭(`kw.lower() in text_lower`)이 짧은 팩터코드 키워드
    (Q01/GPA/EP/BP/M01/C19/D29…)를 무관 토큰에 오매치해 family를 오귀속하던 결함:
      · 'FQ011'(챔피언십 캐리어 전략명) ⊃ 'q01' → quality_profitability 오귀속
        (L-AR-20260710_223505 챔피언십 reval, L-AR-20260711_164659 timing-luck —
         quality 내용 전무한데 FQ011 *참조*만으로 오분류 → DIST-AR-022/016 오귀속 연쇄)
      · 'deep'/'step'/'repo'/'concept' ⊃ 'ep'/'bp' → value 오귀속(코퍼스 전반)
      · '2012-11'(날짜) ⊃ '12-1' → momentum 오귀속
    경계 `(?<![a-z0-9])…(?![a-z0-9])`: ASCII/alnum 키워드는 단어경계로 격리하되,
    한글 문맥 문자는 [a-z0-9]가 아니므로 경계가 항상 성립 → 한글 키워드('모멘텀'/'추세'/
    '앙상블'…)는 종전 substring 의미 그대로 유지(한국어=공백 없는 교착어 — substring이 옳음).
    밑줄('_')은 alnum이 아니므로 팩터코드 구분자 경계로 취급('Q07_D29' 내 'Q07' 매치 유지).
    """
    return re.compile(r"(?<![a-z0-9])" + re.escape(kw_lower) + r"(?![a-z0-9])")


def _kw_hit(kw: str, text_lower: str) -> bool:
    """단어경계 기반 키워드 히트. text_lower·kw 모두 소문자 전제 (한글은 case 없음)."""
    return _kw_pattern(kw.lower()).search(text_lower) is not None


def _infer_family(strategy_id: str, tags: list[str], lesson_text: str,
                  core_reference: str = "") -> str | None:
    text = ((strategy_id or "") + " " + " ".join(tags or []) + " "
            + (lesson_text or "")[:500] + " " + (core_reference or "")[:200])
    text_lower = text.lower()
    best = None
    best_hits = 0
    for fam, kws in FAMILY_KEYWORDS.items():
        hits = sum(1 for kw in kws if _kw_hit(kw, text_lower))
        if hits > best_hits:
            best_hits = hits
            best = fam
    if best is not None:
        return best
    # v2: 기본 8군 무매치분만 확장 15군 순차 적용 (기존 분류 불변 — dict 순서 = 우선순위,
    # infra_process가 최우선. best-hits가 아닌 first-match: 확장군은 상호 배타 키워드).
    for fam, kws in FAMILY_KEYWORDS_EXT.items():
        if any(_kw_hit(kw, text_lower) for kw in kws):
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


def _load_family_override(project_dir: str) -> dict:
    """큐레이션된 per-L-code family override (게이트-리뷰된 재분류) 소비.

    우선순위: explicit `family` 필드 > **이 override** > 키워드 추론(word-boundary) >
    distill-plan 폴백. plan family_reclassification 선례와 동형이나(06_Registry에 per-lcode
    확정 분류), 그 폴백맵(_load_plan_family_map)과 결정적으로 다르다: **키워드 매치가 있어도
    override가 우선**한다. substring→word-boundary 전환(2026-07-18)이 유발하는 90/315
    재분류 중 ① 신규 추론도 신뢰 못 하거나 ② 신규 추론이 unknown으로 떨어지는 케이스를
    게이트 리뷰 후 여기에 고정해 '추론 자체가 틀린' 케이스를 결정론적으로 교정한다.
    key = l_code(안정 식별자 — [[reference-code-identity-stability]]) 우선, source_file 허용.
    파일 부재 시 빈 맵 → 순수 word-boundary 추론(신규 L-code 일반화 유지).
    """
    path = os.path.join(project_dir, "06_Registry", "lcode_family_override.json")
    data = _load(path)
    out: dict[str, str] = {}
    if isinstance(data, dict):
        ov = data.get("overrides")
        if isinstance(ov, dict):
            for k, v in ov.items():
                if isinstance(v, str) and v.strip():
                    out[str(k).replace("\\", "/")] = v.strip()
    return out


# 구스키마 verdict 자유문("Grade B (44.4) / Discard", "C (Archive)", "F / Archive_Priority")
# 에서 선두 등급 토큰만 canonical 로 뽑는다. 뒤따르는 처분(Discard/Keep/Archive)은 등급이
# 아니므로 버리되 원문은 grade_raw 로 보존한다(정직 원장).
# _CONDITIONAL 접미(B_CONDITIONAL / Keep 등)는 canonical 등급이 아니라 조건부 꼬리표이므로
# 기저 문자만 canonical 로 취하고 조건부 여부는 grade_raw 에 남긴다(canonical = A/B/C/F 설계 유지).
RE_VERDICT_GRADE = re.compile(r"^\s*(?:Grade\s*)?([ABCDF])(?:_CONDITIONAL)?\b",
                              re.IGNORECASE)


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
    # 구스키마 verdict 자유문 파싱 (2026-07-25 전략트리 편입)
    m = RE_VERDICT_GRADE.match(g)
    if m:
        return m.group(1).upper(), (rt or "performance")
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


# lcode_schema.R LCODE_VALID_METRIC_TYPES 정합 (measurement-graduation §1 enum)
_VALID_METRIC_TYPES = ("proxy", "estimated", "canonical_screen", "backtested", "unavailable")


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


def _normalize_metric_type(mt_raw: str, source_file: str) -> tuple[str, str | None]:
    """[2026-07-17 운영감사 A4] 비enum metric_type 정규화 (grade normalize 선례 동형).

    emit 경로 밖에서 직접 착지한 비enum 신조어('observational_monitoring', l_code_R42
    실물)가 corpus에 그대로 유입되던 갭. 원장 파일 원문은 불변(정직 원장) — corpus
    엔트리만 canonical 'unavailable'(보수: 실측 권위 불인정)로 정규화하고 원값을
    metric_type_raw로 보존 + WARN. 반환: (canonical, raw|None — 정규화 발생분만)."""
    if mt_raw in _VALID_METRIC_TYPES:
        return mt_raw, None
    print(f"[lcode_harvester][WARN] non-enum metric_type '{mt_raw}' ({source_file}) — "
          f"canonical 'unavailable' 정규화 (원값 metric_type_raw 보존, 원장 파일 불변)",
          file=sys.stderr)
    return "unavailable", mt_raw


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


# 전략트리 아티팩트는 여러 스키마가 공존한다 (2026-07-25 실측 → 2026-08-09 3세대 확인):
#   구(42건): l_code    / lesson      / verdict / factor_id      — 2026-03 QEPM 배치
#   신(44건): l_code_id / lesson_text / grade   / core_reference
#   3세대   : l_code_id / finding     / mechanism|mechanism_diagnosis / key_metrics
# 종전 harvester 는 신 필드명만 읽어 구스키마를 lesson_text="" 로 만들었다.
# ★2026-08-09 재발: 같은 결함이 3세대(`finding`)에서 그대로 다시 열렸다 — 이번 주 발행 45건 중
#   4건이 lesson_text="" 로 수확됐다(corpus 전체 481건 중 공란 5건 = 이번 주가 4건).
#   증상이 **오류가 아니라 빈 문자열**이라 L-code 는 정상 계상되는데 지식만 사라진다
#   (corpus → knowledge_index → 주입면까지 공란이 전파 = 검색·회수 불가).
#   ★고정 alias 목록은 emitter 스키마가 바뀔 때마다 같은 구멍을 다시 연다 —
#   근본 방어는 아래 표가 아니라 `_assert_lesson_reachable()`(수확 후 공란율 감시)다.
# 원본은 건드리지 않고 읽는 시점에만 canonical 필드로 투영한다 (원 필드도 그대로 남김).
# alias 선택 근거 = 데이터 실측(2026-08-09): canonical 키가 빈 아티팩트 10건 중
#   본문 보유 키는 finding 6 / mechanism 6 / title 8 — 의미상 lesson 의 직접 대응물은 finding.
_LEGACY_FIELD_MAP = [
    ("l_code", ("l_code_id", "lcode")),
    ("lesson_text", ("lesson", "text", "description", "finding", "findings")),
    ("grade", ("verdict",)),
    ("core_reference", ("factor_id",)),
    ("created_at", ("date",)),
]


def _coerce_text(v):
    """alias 값이 str 이 아닐 때(dict/list) 읽을 수 있는 문자열로 평탄화.

    실측 2026-08-09: `findings` 는 dict 로 쓰인 아티팩트가 있다(FQ-004). 종전엔 dict 를
    그대로 lesson_text 에 넣거나(하류 str 가정 파손) 건너뛰어(지식 손실) 둘 다 나빴다.
    """
    if isinstance(v, str):
        return v
    if isinstance(v, dict):
        return " / ".join("%s: %s" % (k, _coerce_text(x)) for k, x in v.items() if x)
    if isinstance(v, (list, tuple)):
        return " / ".join(_coerce_text(x) for x in v if x)
    return str(v) if v is not None else ""


def _adapt_legacy_schema(data: dict) -> dict:
    """구스키마 필드를 canonical 이름으로 투영 (비파괴 — 원 필드 보존)."""
    out = dict(data)
    for canon, aliases in _LEGACY_FIELD_MAP:
        if out.get(canon):
            continue
        for a in aliases:
            v = data.get(a)
            if v:
                out[canon] = _coerce_text(v) if canon == "lesson_text" else v
                break
    return out


# 본문 후보로 인정하는 키 (공란 진단 메시지용 — alias 표와 별개, 진단 전용)
_BODY_HINT_KEYS = ("finding", "findings", "lesson", "text", "description",
                   "mechanism", "mechanism_diagnosis", "title", "hypothesis")


def _warn_empty_lesson(entry: dict, raw: dict) -> bool:
    """★근본 방어: lesson_text 공란을 **소리나게** 만든다.

    고정 alias 목록은 emitter 스키마가 바뀔 때마다 같은 구멍을 다시 연다 —
    실제로 2026-07-25(신 스키마)·2026-08-09(finding / findings) 두 번 재발했고,
    증상이 오류가 아니라 **빈 문자열**이라 L-code 는 정상 계상되면서 지식만 사라졌다
    (corpus → knowledge_index → 주입면까지 공란 전파 = 검색·회수 불가).
    alias 를 늘리는 것으로는 다음 변형을 막지 못하므로, 공란이 나오면 **어느 파일의
    어느 키에 본문이 있는지**까지 찍어 다음 수리가 즉시 가능하게 한다.
    """
    if (entry.get("lesson_text") or "").strip():
        return False
    cands = [k for k in _BODY_HINT_KEYS if isinstance(raw, dict) and raw.get(k)]
    print("[lcode_harvester][WARN] lesson_text 공란 — %s (%s). 본문 후보 키: %s. "
          "_LEGACY_FIELD_MAP 의 lesson_text alias 에 추가할 것 (지식 손실 = 조용한 실패)"
          % (entry.get("l_code"), entry.get("source_file"),
             ", ".join(cands) or "(없음 — emitter 측 결손)"),
          file=sys.stderr)
    return True


def harvest(project_dir: str) -> dict:
    arts = os.path.join(project_dir, "stage_artifacts")
    lcodes: list[dict] = []
    seen: set[str] = set()  # dedup by absolute path
    grade_map = _load_grade_map(project_dir)
    plan_family = _load_plan_family_map(project_dir)
    family_override = _load_family_override(project_dir)  # 큐레이션 재분류 (키워드보다 우선)
    id_first_file: dict[str, str] = {}  # v2: l_code ID 충돌 감지 (A1-F6)
    id_first_strategy: dict[str, str] = {}  # v3: 충돌 유형 판정용 (cross_strategy 여부)
    n_id_collisions = 0

    # Flat (back-compat) + mode-separated subdirectories (stage_artifacts/l_code/<mode>/)
    # + 전략트리 (2026-07-25 도훈 승인 — 스캔범위 확장).
    #   04_Research/strategies/<STR>/stage_artifacts/l_code*.json 은 종전 어느 스캐너에도
    #   잡히지 않아 86 아티팩트가 미적립 상태였다. 원본을 SOT 로 유지한 채 여기서 직접 읽는다.
    #   (구 운반 경로 sg_sync_methodology_memory→methodology_memory.md 는 sink 부재로 무효.)
    patterns = [
        os.path.join(arts, "l_code_*.json"),
        os.path.join(arts, "l_code", "**", "l_code_*.json"),
        os.path.join(project_dir, "04_Research", "strategies", "*",
                     "stage_artifacts", "l_code*.json"),
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
        data = _adapt_legacy_schema(data)
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
        # family 결정 4단 우선순위 (2026-07-18 prefer-explicit + override 수리):
        #   ① explicit `family` 필드(emit-time 고정) → ② 큐레이션 override(게이트-리뷰 재분류)
        #   → ③ word-boundary 키워드 추론 → ④ distill-plan 폴백(키워드 무매치분).
        # family_source를 함께 기록해 재분류 감사·게이트 리뷰가 가능하게 한다.
        src_key = source_file.replace("\\", "/")
        family_explicit = data.get("family")
        if isinstance(family_explicit, str) and family_explicit.strip():
            family = family_explicit.strip()
            family_source = "explicit"
        elif l_code in family_override or src_key in family_override:
            family = family_override.get(l_code) or family_override.get(src_key)
            family_source = "override"
        else:
            family = _infer_family(strategy_id, tags, lesson_text, core_reference)
            if family is not None:
                family_source = "keyword"
            else:  # v2: 키워드 무매치 → plan 확정 분류 폴백 (unknown 146→8)
                family = plan_family.get(src_key)
                family_source = "plan_fallback" if family else None
        mode = _infer_mode(data, source_file)
        mode = _MODE_ALIASES.get(mode, mode)  # v2: qepm→qepm_legacy normalize
        promoted = _check_promoted(l_code, project_dir)

        # v2: ID 충돌 감지 (같은 l_code가 서로 다른 파일 — WARN + 마킹, 원장 정직 보존)
        # v3 (2026-07-25): 충돌 *유형*까지 판정해 조치를 즉시 알려준다. 종전 "REASSIGN_ID 대상
        #   검토"는 막연해서 매주 찍히고도 아무 조치로 이어지지 않았음(5건 누적 후 적발).
        #   판별은 결정적 — 전략 다름=신규 발급 / 같은 전략·같은 폴더=정본 선택 / 다른 폴더=병합.
        collision_with = None
        collision_kind = None
        if l_code in id_first_file:
            collision_with = id_first_file[l_code]
            n_id_collisions += 1
            prev_strategy = id_first_strategy.get(l_code)
            if prev_strategy and strategy_id and prev_strategy != strategy_id:
                collision_kind = "cross_strategy"
                advice = f"서로 다른 전략({prev_strategy} vs {strategy_id}) — 후행 기록에 미발급 번호 신규 발급"
            elif os.path.dirname(source_file) == os.path.dirname(collision_with):
                collision_kind = "same_dir_duplicate"
                advice = "같은 전략·같은 폴더 이중 기록 — 정본 1개 선택 후 나머지 superseded/ 이관"
            else:
                collision_kind = "cross_zone_variant"
                advice = "같은 전략·다른 위치(루트 vs 전략트리) — 정본에 내용 병합 후 superseded/ 이관"
            print(f"[lcode_harvester][WARN] l_code ID collision [{collision_kind}]: {l_code} "
                  f"({source_file} vs {collision_with}) — {advice}", file=sys.stderr)
        else:
            id_first_file[l_code] = source_file
            id_first_strategy[l_code] = strategy_id

        # v2: grade 정규화 (plan grade_normalization_map) + record_type 분리
        grade_raw = data.get("grade")
        grade_norm, record_type = _normalize_grade(grade_raw, data.get("record_type"), grade_map)
        # A4: metric_type enum 정규화 (비enum → 'unavailable' 보수 + 원값 보존 + WARN)
        mt_norm, mt_raw = _normalize_metric_type(_infer_metric_type(data, mode), source_file)

        entry = {
            "l_code": l_code,
            "strategy_id": strategy_id,
            "lesson_text": lesson_text,
            "tags": tags,
            "family": family,
            "family_source": family_source,  # explicit|override|keyword|plan_fallback|None (감사)
            "research_mode": mode,
            "construction_type": _infer_construction(data),
            "metric_type": mt_norm,
            "grade": grade_norm,          # canonical A/B/C/F | None(비성과) | 원문(unmappable)
            "grade_raw": grade_raw,       # 원문 보존 (정직 원장)
            "record_type": record_type,   # performance/process/infra/summary
            "core_reference": core_reference,
            "source_file": source_file,
            "mtime": datetime.fromtimestamp(os.path.getmtime(p), tz=timezone.utc).isoformat(timespec="seconds"),
            "promoted_to_axiom": promoted,
        }
        # ── v9.21 권위 등급 투영 (2026-08-24) ────────────────────────────────
        #   ★corpus 는 **고정 키 집합**만 투영한다. 그래서 원본에 `essence_grade` 를 병기해도
        #     여기서 투영하지 않으면 **소비자가 볼 수 없다** — 이 저장소가 반복한
        #     "생산자만 있고 소비자 0" 형태다(실측: 재계산 반영 직후 corpus 보유 0/547).
        #   ★`grade`(역사, 발행 시점 판정)를 덮지 않는다. 별도 키로 **병기**한다 —
        #     `grade_raw` 가 원문을 보존하는 것과 같은 정직-원장 규약.
        #   ★없는 것을 지어내지 않는다: 원본에 필드가 없으면 키를 만들지 않는다
        #     (그래야 "재계산 대상이 아니었다"와 "등급이 미발행이다"가 구분된다).
        if "essence_grade" in data:
            entry["essence_grade"] = data.get("essence_grade")   # None = 권위 등급 미발행(계약 미경유)
            _er = data.get("essence_regrade")
            if isinstance(_er, dict):
                # 전문은 원본에 있다. corpus 에는 **추적에 필요한 최소분**만 싣는다.
                entry["essence_regrade_ref"] = _er.get("ref")
                entry["essence_grade_at_emit"] = _er.get("grade_at_emit")
                entry["essence_structural_drawdown"] = bool(_er.get("structural_drawdown"))

        if collision_with:
            entry["id_collision_with"] = collision_with
            entry["id_collision_kind"] = collision_kind  # v3: cross_strategy/same_dir_duplicate/cross_zone_variant
        if mt_raw is not None:
            entry["metric_type_raw"] = mt_raw  # A4: 비enum 원값 보존 (정직 원장)
        # v8.1 트랙C+D: 학습/실측 필드 pass-through (있을 때만 — 없는 구 L-code는 그대로 = 정직성).
        # cluster_extractor가 mechanism_draft/oos_validation_draft/falsification_draft 실값 매핑에 사용.
        # v8.2.1 (2026-07-03 아키텍처 감사 AXM-06/GOV-01): oos_months·oos_effect_vs_is는 External 축,
        # portfolio_alpha_t는 promote_global essence 게이트(weakest_t)와 promote.R Rigor 축이 소비 —
        # 미전달 시 global 승격이 구조적으로 불가하던 갭 봉합.
        # v2 (2026-07-04): selection_type·lcode_schema_version 추가 (emit v2 신필드).
        # v3 (2026-08-23 v9 Lean Loop): source_paper·paper_assumption_broken·next_probes·
        #   live_trigger 추가. 스키마 v3(lcode_emit)가 발행하기 시작하면 별도 배선 없이
        #   corpus 로 흐르게 미리 열어 둔다 — 없는 구 L-code 는 그대로 미기록(정직성 불변).
        for opt in ("mechanism_hypothesis", "data_supported_conclusion", "next_probe",
                    "fmt_codes", "oos_retention", "falsification_attempts", "authoritative",
                    "oos_months", "oos_effect_vs_is", "portfolio_alpha_t",
                    "selection_type", "lcode_schema_version",
                    "source_paper", "paper_assumption_broken", "next_probes", "live_trigger"):
            v = data.get(opt)
            if v not in (None, "", [], {}):
                entry[opt] = v
        # [2026-07-17 운영감사 A3] authoritative.* nested 실측값 top-level lift —
        # alpha_search emit이 portfolio_alpha_t를 authoritative.portfolio_alpha_t_nw_lag3
        # 에만 기록한 48건이 promote.R .lc_get(top-level 조회)에서 NA 유실되던 갭.
        # top-level 기존값이 있으면 보존(lift 미적용). oos_retention도 동일 nested 소스.
        auth = data.get("authoritative")
        if isinstance(auth, dict):
            for top_key, nested_key in (("portfolio_alpha_t", "portfolio_alpha_t_nw_lag3"),
                                        ("oos_retention", "oos_retention")):
                if top_key in entry:
                    continue  # top-level 기존값 우선 보존
                v = auth.get(nested_key)
                if isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v):
                    entry[top_key] = v
                    entry[f"{top_key}_source"] = f"authoritative.{nested_key}"
        _warn_empty_lesson(entry, data)
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


_ATOMIC_RETRIES = 8
_ATOMIC_SLEEP_INIT = 0.02
_ATOMIC_SLEEP_CAP = 0.25


def _write_json_atomic(obj: dict, path: str) -> None:
    """temp + os.replace 원자적 쓰기 — 중단/동시읽기 시 반파일(손상 JSON) 방지.

    OneDrive 경로 확립 관행(temp-rename, [project-windows-arrow-mmap-1224])과 정합.
    R 측 정본 = 02_Infrastructure/utils/atomic_json.R::qvest_atomic_write_json (같은 계약).

    ★2026-08-23 v9.1 후속 실측 (Windows 11 · Python 3.12):
      소비자가 대상 파일 핸들을 연 채이면 ``os.replace`` 는
      ``PermissionError: [WinError 5]`` 로 **실패한다**. 파일이 찢기지는 않지만
      (기존 내용이 그대로 남는다) 갱신분이 **조용히 유실**되고 tmp 가 잔재로 쌓인다.
      write_positive_context() 호출부는 예외를 삼키므로(WARN 후 계속) 유실이 더 조용하다.
      ⇒ 유한 재시도로 그 창을 덮고, 소진하면 tmp 를 치운 뒤 예외를 올린다.
      ※핸들 점유는 소비자 1회 read 시간(수 ms)이라 대개 첫 1~2회에서 풀린다.
    """
    d = os.path.dirname(path)
    if d:
        os.makedirs(d, exist_ok=True)
    tmp = os.path.join(d or ".", f".{os.path.basename(path)}.tmp_{os.getpid()}")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2, ensure_ascii=False)
    last: "OSError | None" = None
    for i in range(_ATOMIC_RETRIES):
        try:
            os.replace(tmp, path)  # Windows에서도 원자적 교체 (기존 파일 덮어씀)
            return
        except OSError as exc:     # PermissionError 포함 — 대상 핸들 점유가 대표 사유
            last = exc
            time.sleep(min(_ATOMIC_SLEEP_CAP, _ATOMIC_SLEEP_INIT * (2 ** i)))
    try:
        os.remove(tmp)             # 잔재 tmp 누적 차단 (payload 는 어차피 재계산 가능)
    except OSError:
        pass
    raise OSError(
        f"원자적 기록 실패 (os.replace {_ATOMIC_RETRIES}회) — 정본 미갱신: {path} ({last})"
    )


# ═══════════════════════════════════════════════════════════════════════════════
# v9 Lean Loop — 양성 주입 컨텍스트 (2026-08-23)
#
# 배경(실측): 에이전트 spawn 주입면(axiom_context_inject.sh)이 사실상 "죽은 방향
#   재제안 금지" 목록이었다 — distilled_knowledge 167 카드 중 negative 71 vs
#   positive 11(6.6%), 주입 블록 제목이 "확립 전략 진실 — 죽은 방향 재제안 금지".
#   창의성 입력면이 금지 목록이면 에이전트가 받는 건 지도가 아니라 울타리다.
# 재설계: 주입문을 "무엇이 통했나(연구-tier 상위 전략) + 최근 교훈 + dead 는 1줄
#   포인터"로 뒤집는다. 훅은 **읽기만** 하고 모든 집계는 여기서 한다 —
#   주입 훅은 매 Agent spawn 마다 도는 경로라 레지스트리 3종을 파싱시킬 수 없다.
# 출력: .cache/positive_context.json (훅이 부재 시 고정부만 주입 = 회귀 없음)
# ═══════════════════════════════════════════════════════════════════════════════

PC_OUTPUT_REL = os.path.join(".cache", "positive_context.json")
PC_MIN_PORT_T = 1.96      # 연구-tier 하한 (자본 HARD 2.95 아님 — 여긴 "출발점" 표시용)
PC_TOP_N = 5              # 상위 전략 줄 수
PC_RECENT_N = 3           # 최근 교훈 줄 수
PC_DIST_N = 3             # 양성 DIST 카드 줄 수
PC_MECH_CHARS = 55        # 전략 줄의 기전 1줄 상한
PC_LESSON_CHARS = 90      # 최근 교훈 lesson_text 상한
PC_PROBE_CHARS = 40       # 최근 교훈 next_probe 첫 항목 상한
PC_DIST_CHARS = 65        # DIST statement 상한

# mechanism_hypothesis / lesson_text 앞에 붙는 생성기 보일러플레이트.
#   예: "가설 'Piotroski F-Score …' — 검증 결과 지배 요인: FMT-01(MDD 53.9% > 45% …)"
# ★제거하는 건 **템플릿 단어**("가설 '", "' — 검증 결과 지배 요인:")이지 그 안의 가설명이
#   아니다. 가설명을 같이 버리면 5줄이 전부 동일한 FMT 진단문이 되어(실측) 판별 정보가
#   0이 되고, 뒤에 붙는 [FMT-01] 토큰과도 중복된다. 캡처군 1 = 가설명을 앞에 남긴다.
#   접두가 없으면 무변경(no-op) — 어느 원천에 적용해도 안전하다.
RE_PC_BOILER = re.compile(
    r"^\s*가설\s*['\"‘’“”](?P<name>.*?)['\"‘’“”]\s*"
    r"[—–:\-]\s*검증\s*결과\s*지배\s*요인\s*:\s*"
)


def _pc_num(v):
    """유한 실수만 통과. bool 은 int 서브클래스라 명시 배제."""
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return None
    return v if math.isfinite(v) else None


def _pc_clip(s, n: int) -> str:
    """공백 정규화 후 n자 상한(초과 시 말줄임표). 주입 예산이 문자 단위라 문자로 센다."""
    t = " ".join(str(s or "").split())
    return t if len(t) <= n else t[: max(0, n - 1)] + "…"


def _pc_fmt2(v) -> str:
    x = _pc_num(v)
    return f"{x:.2f}" if x is not None else "?"


def _pc_pct(v) -> str:
    """0.211 → '21%'. 원장이 비율(fraction)로 기록한다 — %로 이미 적힌 값은 없다."""
    x = _pc_num(v)
    return f"{round(x * 100):.0f}%" if x is not None else "?"


def _pc_score(meta: dict) -> str:
    x = _pc_num((meta or {}).get("score"))
    return f"{x:g}" if x is not None else "?"


def _pc_first_probe(entry: dict) -> str:
    """next_probes(v3 리스트) → next_probe(구 스키마: 문자열 또는 리스트) 순."""
    for key in ("next_probes", "next_probe"):
        v = (entry or {}).get(key)
        if isinstance(v, (list, tuple)):
            for x in v:
                if str(x or "").strip():
                    return str(x)
        elif isinstance(v, str) and v.strip():
            return v
    return ""


def _pc_mechanism(lc_entry: dict, meta: dict) -> str:
    """전략 1줄 기전.

    우선순위 = corpus 의 mechanism_hypothesis → lesson_text(보일러플레이트 접두 제거)
    → module_catalog 의 meta.strategy_idea. 셋 다 비면 빈 문자열(줄에서 생략).
    ★접두 제거는 어느 원천에도 적용한다 — 접두가 없으면 no-op 이라 부작용이 없고,
      mechanism_hypothesis 가 그 접두를 실제로 달고 있는 유일한 필드다.
    """
    for raw in ((lc_entry or {}).get("mechanism_hypothesis"),
                (lc_entry or {}).get("lesson_text"),
                (meta or {}).get("strategy_idea")):
        t = " ".join(str(raw or "").split())
        if not t:
            continue
        # 템플릿 단어만 걷어내고 가설명은 앞으로 끌어올린다("<가설명> — <지배 요인>").
        stripped = RE_PC_BOILER.sub(
            lambda m: (m.group("name").strip() + " — ") if m.group("name").strip() else "", t
        ).strip()
        return stripped or t
    return ""


def _pc_top_strategies(project_dir: str, by_sid: dict) -> list[str]:
    """module_catalog.json 연구-tier 상위 N 전략 줄.

    선별: authoritative_essence 보유 ∧ PORT_t(NW lag-3) ≥ 1.96 ∧ 오염 라벨 제외.
    정렬: grade B/A 우선 → PORT_t 내림차순. 중복: module_hash 동일 = 같은 실산출물의
      이명(2026-08-20 batch_434 치환 실측)이라 최상위 1건만 남긴다.
    """
    cat = _load(os.path.join(project_dir, "06_Registry", "module_catalog.json")) or {}
    mods = cat.get("modules")
    if not isinstance(mods, dict):
        return []
    rows = []
    for sid, m in mods.items():
        if not isinstance(m, dict):
            continue
        if m.get("label_contaminated") or m.get("grade_contaminated"):
            continue  # 08-20 이명 오염 감사 라벨 — 등급/라벨 신뢰 불가
        meta = m.get("meta") if isinstance(m.get("meta"), dict) else {}
        ess = meta.get("authoritative_essence")
        if not isinstance(ess, dict):
            continue  # 실측 essence 없는 항목은 "통했다"의 근거가 될 수 없다
        pt = _pc_num(ess.get("portfolio_alpha_t_nw_lag3"))
        if pt is None or pt < PC_MIN_PORT_T:
            continue
        grade = str(m.get("grade") or "?")
        rows.append({
            "sid": str(m.get("strategy_id") or sid),
            "grade": grade,
            "pt": pt,
            "ess": ess,
            "meta": meta,
            "hash": m.get("module_hash") or f"__nohash__{sid}",
            "rank": 0 if grade in ("A", "B") else 1,
        })
    rows.sort(key=lambda r: (r["rank"], -r["pt"]))

    lines, seen = [], set()
    for r in rows:
        if r["hash"] in seen:
            continue
        seen.add(r["hash"])
        e, meta = r["ess"], r["meta"]
        lc = by_sid.get(r["sid"]) or {}
        mech = _pc_clip(_pc_mechanism(lc, meta), PC_MECH_CHARS)
        fmt = lc.get("fmt_codes") or meta.get("fmt_codes")
        if isinstance(fmt, (list, tuple)) and fmt:
            mech = (mech + " " if mech else "") + f"[{fmt[0]}]"
        elif isinstance(fmt, str) and fmt.strip():
            mech = (mech + " " if mech else "") + f"[{fmt.split(',')[0].strip()}]"
        lines.append(
            f"- {r['sid']} {r['grade']} s{_pc_score(meta)} PORT_t {r['pt']:.2f} "
            f"SR {_pc_fmt2(e.get('net_sharpe'))} CAGR {_pc_pct(e.get('cagr'))} "
            f"MDD {_pc_pct(e.get('mdd'))} OOS {_pc_fmt2(e.get('oos_retention'))} | {mech}"
        )
        if len(lines) >= PC_TOP_N:
            break
    return lines


def _pc_positive_dist(project_dir: str) -> list[str]:
    """양성 DIST 카드 ≤3줄. proposed 는 [초안] 라벨(도훈 승인 D-i, INV-6 정합)."""
    dk = _load(os.path.join(project_dir, "06_Registry", "distilled_knowledge.json")) or {}
    out = []
    for e in dk.get("entries", []) or []:
        if not isinstance(e, dict) or e.get("polarity") != "positive":
            continue
        status = e.get("status")
        if status not in ("distilled", "proposed"):
            continue
        stmt = (e.get("statement_refined") or "").strip() or (e.get("statement_draft") or "").strip()
        if not stmt:
            continue
        tag = " [초안]" if status == "proposed" else ""
        out.append(f"- {e.get('dist_id')}{tag}: {_pc_clip(stmt, PC_DIST_CHARS)}")
        if len(out) >= PC_DIST_N:
            break
    return out


def _pc_recent_lessons(corpus: dict) -> list[str]:
    """최근 성과 L-code 3건 — mtime 내림차순. 다음 시도(next_probe 첫 항목)까지 한 줄에."""
    # ★2026-09-23 (플랜 P0-M3 · 감사 D6-03): 재라벨된 강화 셀(reinforcement_cell)은 '최근 교훈'이 아니다 —
    #   셀 1칸 측정의 보일러플레이트("<셀> 충실구현: 등급 X" + 고정 next_probe)라 주입면 3줄 중 1~2줄을 차지했다.
    #   셀의 교훈 정본은 블록 L-code(reinforcement)다. corpus 에서는 지우지 않는다(조회·증류는 mode 로 구분).
    perf = [x for x in (corpus.get("lcodes") or [])
            if isinstance(x, dict) and x.get("record_type") == "performance"
            and x.get("research_mode") != "reinforcement_cell"]
    perf.sort(key=lambda x: str(x.get("mtime") or ""), reverse=True)
    lines = []
    for x in perf[:PC_RECENT_N]:
        lesson = _pc_clip(x.get("lesson_text"), PC_LESSON_CHARS)
        probe = _pc_clip(_pc_first_probe(x), PC_PROBE_CHARS)
        tail = f" ▸ {probe}" if probe else ""
        lines.append(f"- {x.get('l_code')} {x.get('grade') or '?'} | {lesson}{tail}")
    return lines


def _pc_dead_counts(project_dir: str) -> tuple:
    """hypothesis_index 의 사망 판정 집계 — 주입은 개수 + lookup 1줄로만 한다.

    구 주입면은 negative 카드 본문 5건을 매 spawn 마다 실었다(= 재제안 금지 목록).
    개수 + 조회 명령이면 필요할 때 에이전트가 스스로 확인할 수 있다.
    """
    hi = _load(os.path.join(project_dir, "06_Registry", "hypothesis_index.json")) or {}
    entries = hi.get("entries") if isinstance(hi, dict) else hi
    n_fail = n_neg = 0
    for e in entries or []:
        if not isinstance(e, dict):
            continue
        v = e.get("verdict")
        if v == "FAIL":
            n_fail += 1
        elif v == "DISTILLED_NEG":
            n_neg += 1
    return n_fail, n_neg


def _pc_n_fired(project_dir: str) -> int:
    """부활 발화 건수. 파일 부재 = 0 (모닝브리핑이 주말 skip 하므로 정상 상태)."""
    rv = _load(os.path.join(project_dir, ".cache", "failure_revival_flags.json"))
    if not isinstance(rv, dict):
        return 0
    n = _pc_num(rv.get("n_fired"))
    if n is not None:
        return int(n)
    fired = rv.get("fired")
    return len(fired) if isinstance(fired, list) else 0


def write_positive_context(corpus: dict, project_dir: str) -> dict:
    """.cache/positive_context.json 생성 — axiom_context_inject.sh 의 유일한 변동부 원천."""
    by_sid = {}
    for x in corpus.get("lcodes") or []:
        sid = x.get("strategy_id")
        if not sid:
            continue
        prev = by_sid.get(sid)
        # 같은 전략에 L-code 가 여럿이면 mechanism_hypothesis 보유분 > 최신 mtime 순
        if prev is None:
            by_sid[sid] = x
        elif bool(x.get("mechanism_hypothesis")) > bool(prev.get("mechanism_hypothesis")):
            by_sid[sid] = x
        elif (bool(x.get("mechanism_hypothesis")) == bool(prev.get("mechanism_hypothesis"))
              and str(x.get("mtime") or "") > str(prev.get("mtime") or "")):
            by_sid[sid] = x

    n_fail, n_neg = _pc_dead_counts(project_dir)
    n_fired = _pc_n_fired(project_dir)
    dead_line = (f"[dead configs {n_fail + n_neg} (FAIL {n_fail} + DISTILLED_NEG {n_neg}) — 착수 전 "
                 "`Rscript 02_Infrastructure/tools/hypothesis_index.R lookup <kw>` 1줄 확인]")
    if n_fired > 0:
        dead_line += f" (부활 발화 {n_fired})"

    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "generator": "02_Infrastructure/axiom/lcode_harvester.py::write_positive_context",
        "positive_block": "\n".join(_pc_top_strategies(project_dir, by_sid)),
        "dist_block": "\n".join(_pc_positive_dist(project_dir)),
        "recent_block": "\n".join(_pc_recent_lessons(corpus)),
        "dead_line": dead_line,
        "n_dead": n_fail + n_neg,
        "n_fired": n_fired,
    }
    _write_json_atomic(payload, os.path.join(project_dir, PC_OUTPUT_REL))
    return payload


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--project-dir",
        default=os.environ.get("QVEST_PROJECT_DIR")
        or os.environ.get("CLAUDE_PROJECT_DIR") or os.environ.get("QM_ROOT") or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    )
    ap.add_argument(
        "--output", default=None,
        help="커스텀 출력 경로. 지정해도 정본 .cache/lcode_corpus.json은 함께 갱신됨"
             " (이중 쓰기 — 07-13 정본 우회 실사고 재발 방지, 우회 불가)",
    )
    args = ap.parse_args()

    canonical = os.path.join(args.project_dir, ".cache", "lcode_corpus.json")
    out = args.output or canonical

    corpus = harvest(args.project_dir)
    _write_json_atomic(corpus, out)

    # (2026-07-13 task#54-2) 커스텀 --output 지정 시에도 정본을 함께 갱신 (이중 쓰기).
    # 커스텀 출력이 정본을 우회하던 07-13 실사고(corpus 정체 → hypothesis_index
    # 중복방지 게이트 이틀 실명) 재발 방지 배선.
    dual_note = ""
    if os.path.abspath(out) != os.path.abspath(canonical):
        _write_json_atomic(corpus, canonical)
        dual_note = f" (+정본 동시 갱신: {canonical})"

    print(
        f"[lcode_harvester] {out}{dual_note} — n={corpus['n_lcodes']} "
        f"promoted={corpus['n_promoted']} "
        f"families={corpus['family_distribution']} "
        f"grades={corpus['grade_distribution']}"
    )

    # (v9 Lean Loop 2026-08-23) 주입면 양성 컨텍스트 생성.
    #   ★실패해도 수확 자체는 성공으로 둔다 — 이 배선이 L-code 적립 경로를 막으면
    #     주입 극성을 고치려다 지식 적립을 끊는 것이라 본말전도다.
    #     훅은 파일 부재 시 고정부만 주입하므로 실패 = 구 동작보다 조용한 축소일 뿐.
    try:
        pc = write_positive_context(corpus, args.project_dir)
        print(f"[lcode_harvester] positive_context — 전략 {len(pc['positive_block'].splitlines())}"
              f" · DIST {len(pc['dist_block'].splitlines())}"
              f" · 최근교훈 {len(pc['recent_block'].splitlines())}"
              f" · dead {pc['n_dead']} · 부활발화 {pc['n_fired']}")
    except Exception as exc:  # noqa: BLE001 — 정직 경보 후 계속
        print(f"[lcode_harvester][WARN] positive_context 생성 실패: {exc}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
