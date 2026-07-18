#!/usr/bin/env python3
"""_infer_family word-boundary 회귀 테스트 (2026-07-18 W29 /cleaner 근본원인 수리).

배경: 구 substring 매칭(`kw.lower() in text_lower`)이 짧은 팩터코드 키워드
(Q01/GPA/EP/BP/M01/C19/D29…)를 무관 토큰에 오매치해 family 오귀속
(FQ011→'q01'→quality_profitability, deep→'ep'→value, 2012-11→'12-1'→momentum).
word-boundary 매처가 ① artifact 매치는 기각하고 ② 정당한 매치·한글 substring은
보존하는지 고정한다. 실행: "$QVEST_PY" 02_Infrastructure/axiom/test_lcode_harvester_family.py
"""
from __future__ import annotations

import importlib.util
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))


def _load_harvester():
    spec = importlib.util.spec_from_file_location("lh", os.path.join(HERE, "lcode_harvester.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


lh = _load_harvester()
_FAILS: list[str] = []


def _expect(desc, got, *, eq=None, ne=None):
    ok = True
    if eq is not None and got != eq:
        ok = False
    if ne is not None and got == ne:
        ok = False
    tag = "OK  " if ok else "FAIL"
    detail = ""
    if not ok:
        detail = f" (got={got!r}, expect_eq={eq!r} expect_ne={ne!r})"
        _FAILS.append(desc + detail)
    print(f"  [{tag}] {desc}{detail}")


def test_artifact_rejections():
    """substring 오귀속이 word-boundary로 기각되는지."""
    inf = lh._infer_family
    print("== ARTIFACT REJECTIONS ==")
    # FQ011 champion carrier 참조만으로 quality_profitability 오귀속(q01) 금지
    _expect("FQ011 champ reval !-> quality_profitability",
            inf("FQ011_CHAMPIONSHIP_REVAL_20260710", ["AR"], "FQ011 챔피언십 재검증 오버레이", ""),
            ne="quality_profitability")
    _expect("SPEC2 ref FQ011 !-> quality_profitability",
            inf("SPEC2_TIMING_LUCK_20260711", ["AR"], "FQ011 캐리어 timing luck", ""),
            ne="quality_profitability")
    # 'deep'/'step'/'concept' ⊃ ep/bp → value 오귀속 금지
    _expect("deep/step/concept !-> value",
            inf("STR_X", ["ML"], "deep learning step-by-step concept", ""), ne="value")
    # 날짜 '2012-11' ⊃ '12-1' → momentum 오귀속 금지
    _expect("date 2012-11 !-> momentum",
            inf("STR_Y", [], "backtest window 2012-11 to 2020", ""), ne="momentum")
    # 'GPARSE' ⊃ 'GPA' → quality_profitability 오귀속 금지
    _expect("GPARSE !-> quality_profitability",
            inf("GPARSE_MODULE", [], "gparse pipeline util", ""), ne="quality_profitability")


def test_legit_matches():
    """정당한 팩터코드 매치·한글 substring이 보존되는지."""
    inf = lh._infer_family
    print("== LEGIT MATCHES PRESERVED ==")
    _expect("EP_STANDALONE -> value",
            inf("EP_STANDALONE_LOWTURN", ["VALUE"], "earnings-to-price standalone", ""), eq="value")
    _expect("Q07 earnings_stability -> quality_earnings",
            inf("Q07_D29", [], "earnings_stability + accrual_quality", ""), eq="quality_earnings")
    _expect("Hangul 모멘텀 -> momentum",
            inf("STR_MOM", [], "모멘텀 전략 12-1 검증", ""), eq="momentum")
    _expect("Hangul compound 역모멘텀 -> momentum",
            inf("STR_REVMOM", [], "역모멘텀 신호 탐색", ""), eq="momentum")
    _expect("Q01_GPA composite -> quality_profitability",
            inf("Q01_GPA_COMPOSITE", [], "GPA profitability composite", ""), eq="quality_profitability")
    _expect("D29 lowbeta -> defense",
            inf("D29_LOWBETA", [], "lowbeta defense sleeve", ""), eq="defense")
    _expect("C19 consensus -> consensus",
            inf("C19_ANALYST", [], "consensus analyst revision", ""), eq="consensus")
    _expect("overlay 국면 -> overlay_regime (EXT first-match)",
            inf("STR_OV", [], "regime overlay 국면 타이밍", ""), eq="overlay_regime")
    # underscore = 팩터코드 경계로 취급 (Q07_D29 내 Q07 매치 유지)
    _expect("underscore-delimited Q07_... matches",
            inf("Q07_COMPOSITE", [], "quality composite", ""), eq="quality_earnings")


def test_kw_hit_boundary():
    """_kw_hit 경계 원자성: alnum 경계 격리 + 한글 문맥 통과."""
    print("== _kw_hit BOUNDARY SEMANTICS ==")
    h = lh._kw_hit
    _expect("'ep' not in 'deep'", h("ep", "deep"), eq=False)
    _expect("'ep' in 'ep_standalone'", h("ep", "ep_standalone"), eq=True)
    _expect("'ep' in 'the ep factor'", h("ep", "the ep factor"), eq=True)
    _expect("'q01' not in 'fq011'", h("q01", "fq011"), eq=False)
    _expect("'q01' in 'q01_gpa'", h("q01", "q01_gpa"), eq=True)
    _expect("'12-1' not in '2012-11'", h("12-1", "2012-11"), eq=False)
    _expect("'모멘텀' in '역모멘텀전략' (Hangul substring kept)", h("모멘텀", "역모멘텀전략"), eq=True)


def test_override_and_explicit_priority():
    """harvest() 우선순위: explicit family > override > 키워드 > plan 폴백."""
    print("== harvest() PRIORITY (explicit > override > keyword) ==")
    with tempfile.TemporaryDirectory() as td:
        arts = os.path.join(td, "stage_artifacts")
        os.makedirs(arts, exist_ok=True)
        # (1) explicit family 필드가 키워드를 이겨야 함: sid는 momentum이지만 explicit=defense
        json.dump({"l_code": "L-TEST-EXPLICIT", "strategy_id": "MOM12_STRAT",
                   "lesson_text": "모멘텀 12-1", "family": "defense", "grade": "F"},
                  open(os.path.join(arts, "l_code_explicit.json"), "w", encoding="utf-8"))
        # (2) override가 키워드를 이겨야 함: sid는 value(EP)지만 override로 flow_supply 지정
        json.dump({"l_code": "L-TEST-OVERRIDE", "strategy_id": "EP_STANDALONE",
                   "lesson_text": "earnings to price", "grade": "F"},
                  open(os.path.join(arts, "l_code_override.json"), "w", encoding="utf-8"))
        # (3) 순수 키워드
        json.dump({"l_code": "L-TEST-KEYWORD", "strategy_id": "D29_LOWBETA",
                   "lesson_text": "lowbeta defense", "grade": "F"},
                  open(os.path.join(arts, "l_code_keyword.json"), "w", encoding="utf-8"))
        # override 파일 배치
        os.makedirs(os.path.join(td, "06_Registry"), exist_ok=True)
        json.dump({"overrides": {"L-TEST-OVERRIDE": "flow_supply"}},
                  open(os.path.join(td, "06_Registry", "lcode_family_override.json"), "w", encoding="utf-8"))
        corpus = lh.harvest(td)
        by = {x["l_code"]: x for x in corpus["lcodes"]}
        _expect("explicit field wins over keyword",
                by.get("L-TEST-EXPLICIT", {}).get("family"), eq="defense")
        _expect("explicit family_source=explicit",
                by.get("L-TEST-EXPLICIT", {}).get("family_source"), eq="explicit")
        _expect("override wins over keyword",
                by.get("L-TEST-OVERRIDE", {}).get("family"), eq="flow_supply")
        _expect("override family_source=override",
                by.get("L-TEST-OVERRIDE", {}).get("family_source"), eq="override")
        _expect("keyword path still works",
                by.get("L-TEST-KEYWORD", {}).get("family"), eq="defense")
        _expect("keyword family_source=keyword",
                by.get("L-TEST-KEYWORD", {}).get("family_source"), eq="keyword")


def main() -> int:
    test_artifact_rejections()
    test_legit_matches()
    test_kw_hit_boundary()
    test_override_and_explicit_priority()
    print()
    if _FAILS:
        print(f"FAILED: {len(_FAILS)} assertion(s)")
        for f in _FAILS:
            print("  -", f)
        return 1
    print("ALL PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
