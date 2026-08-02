# -*- coding: utf-8 -*-
"""
ast_verify.py — AST PIT 정적검증기 (Qvest AST v1.1 SOT §4, Step 3 선행 구현)
================================================================================

SOT: 02_Infrastructure/docs/qvest_ast_v1_1_sot.md §4 (verify() 알고리즘 = 원안 v1.0 §4 채택)
리프 해석 이중 소스:
  1) 02_Infrastructure/factor_db/factor_registry.json — 승격 스키마
     availability{type, rule, known_discrepancy} + restatement_prone + vintage_available
     (2026-07-25 wf_6e8ece74 S1 마이그레이션 완료분, 373 엔트리)
  2) 06_Registry/ast_field_map_v0.json — 비-registry 리프 그룹 58개
     (ast_leaf_class / restatement_prone / vintage_available; avail 규칙은 map 실측 서술을
      본 파일 GROUP_AVAIL 표로 기계화 — 각 항목에 map 근거 인용)

판정 3종 + 계약 FAIL:
  PASS                : 전 리프 avail_ts <= decision_ts (t_d)
  FAIL_LOOKAHEAD      : avail_ts > t_d 리프 존재 (위반 리프·경로 명시) — alpha 반려, forge 0 소비
  WARN_RESTATEMENT    : 통과하되 restatement_prone ∧ vintage 無 리프 존재 → 스펙 플래그
  FAIL_CONTRACT       : escape 리프 계약 결측 / 𝒪 밖 연산자 / 미등재 리프 / STORED_SCORE의
                        FIELD 위장 (사유 명시)

상향 전파 알고리즘 (원안 §4):
  LEAF                    : avail_ts = ref_ts + lag (소스별 규칙, 아래 GROUP_AVAIL/레지스트리 rule)
  TS_LAG(x, k)            : verify(x, t - k)            — lag 완화
  롤링류(TS_MEAN/STD/...)  : verify(x, t)                — 최신 관측이 구속
  TS_CORR / TS_BETA       : max(verify(x,t), verify(y,t))
  AS_OF(x, rule)          : rule 해석 — "(factor_date|usable_date|date) <= t" 형이면
                            as-of 조인이 가용성을 t로 클램프 (컴파일러-소유 조인 전제, §4-2)
  VINTAGE(x, pin_tag)     : 핀 스냅샷 평가 — subtree의 restatement 경고 면제 (§7 vintage pinning)
  기타 𝒪 연산자            : max(children)
  𝒪 밖 연산자              : FAIL_CONTRACT (1차 차단은 ast_spec_gate.sh — 본 검증기는 fail-closed 이중화)
  음수 k(TS_LAG)          : LEAD 등가 = 문법 위반 → FAIL_LOOKAHEAD

known_discrepancy 처리 (registry 171건):
  선언·구현 불일치 리프는 **보수 쪽 값**으로 판정하고 verdict.discrepancy_used에 기록 (침묵 금지).
  - consensus 'T-1' + disc(33건): 코드 same-day 허용·제공시각 미상 → 보수 avail = t + 1d
  - macro 'C11_publication_lag'(14건): 코드 1d 근사 vs 실제 발표 lag 수주 → 보수 상한
    C11_CONSERVATIVE_LAG_DAYS = 35d ("검증 안 됨 (상한 가정)" — 시리즈별 실측 lag 테이블 부재 시
    보수 envelope. registry known_discrepancy '실제 발표 lag(예: CPI 수주)' 인용 근거)
  - fundamental 'quarterly+45d;annual_3/31'(124건): 빌더 .pit_fund as-of 내부강제로 구조적
    look-ahead는 없음 → avail = t. 단 xlsx Q4 +45d(≈2/14) vs 확정 3/31 노출창 [2/14, 3/31)은
    SOT §3 수리 항목(별도 사이클) — discrepancy_used로 주석 (판정영향 주석 의무, block 아님)

escape 리프 4종 계약 (SOT §2 — 결측 시 FAIL_CONTRACT):
  MODEL_SCORE  : training_window_end 선언 + <= t_d - 1 + training_leaves 목록(각 리프 본 맵 검증)
  STORED_SCORE : provenance {store_build_hash, generator_code_path, generated_at} 3필드
                 + production_parity_verified == true (§7b 기계화).
                 선택 embedded_data_through 선언 시 <= t_d - 1d (production T-1 규약) —
                 위반 = 동월 vintage 형상(실사고 2, stored-panel same-month lookahead) → FAIL_LOOKAHEAD
  LLM_SCORE    : doc_rcept_dt <= t_d (프롬프트/모델 sha 결측은 warning note)
  SPECIAL_OP   : op_code_path + walk_forward == true 선언

alpha_package.json 기대 형상 (Step 2 스키마 3층화 전 최소 계약):
  {
    "strategy_id": "...",
    "pit": {"sig_date": "YYYY-MM-DD", "decision_ts": "YYYY-MM-DD"},   # decision_ts 결측 시 sig_date(최엄격)
    "ast": { <node> }        # 또는 top-level "factor_definition": {"ast": ...} / "spec": {"ast": ...}
  }
  node  = {"op": "TS_MEAN", "children": [...], "window": 252, ...}
        | {"op": "TS_LAG", "children": [x], "k": 21, "unit": "d"|"m"}
        | {"op": "AS_OF", "children": [x], "rule": "factor_date<=t"}
        | {"op": "VINTAGE", "children": [x], "pin_tag": "pin20260703"}
        | leaf
  leaf  = {"leaf": "FIELD", "group_id": "<ast_field_map group_id>", "field": "...",
           "period": "quarterly"|"annual",        # regulatory_fund 그룹만; 결측 시 annual(보수)
           "ref_basis": "rcept"|"event_date",     # event 그룹만; 결측 시 rcept
           "series_class": "market_daily"|"release"}  # E1 FRED만; 결측 시 release(보수)
        | {"leaf": "REGISTRY", "factor": "V01_BM"}
        | {"leaf": "MODEL_SCORE", "training_window_end": "...", "trained_at": "...",
           "training_leaves": [<leaf>...]}
        | {"leaf": "STORED_SCORE", "group_id": "...", "provenance": {...},
           "production_parity_verified": true, "embedded_data_through": "YYYY-MM-DD"}
        | {"leaf": "LLM_SCORE", "doc_rcept_dt": "...", "prompt_sha": "...", "model_sha": "..."}
        | {"leaf": "SPECIAL_OP", "op_code_path": "...", "walk_forward": true}

CLI:
  python ast_verify.py <alpha_package.json> [--out verdict.json] [--decision-ts YYYY-MM-DD]
                       [--sig-date YYYY-MM-DD] [--registry PATH] [--map PATH]
  종료코드: PASS/WARN_RESTATEMENT = 0, FAIL_* = 1 (파이프라인 게이트 소비용)

작성: 2026-07-25 (S2c). 동적 검정(judge lag1·strict A/B·vintage-swap)은 대체 불가 병행 — SOT §4 HARD 원칙.
"""

import argparse
import calendar
import datetime as _dt
import json
import os
import sys

# ----------------------------------------------------------------------------- 경로 기본값
_QM_ROOT = os.environ.get("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
DEFAULT_REGISTRY = os.path.join(_QM_ROOT, "02_Infrastructure/factor_db/factor_registry.json")
DEFAULT_FIELD_MAP = os.path.join(_QM_ROOT, "06_Registry/ast_field_map_v0.json")

# ----------------------------------------------------------------------------- 보수 상수 (근거 명시)
FUND_QUARTERLY_LAG_DAYS = 45      # parse_fundamental_xlsx.R:199 / DART 분기 고정일 5/15·8/15·11/15 (45일 규칙)
C11_CONSERVATIVE_LAG_DAYS = 35    # 보수 envelope 상한 — registry known_discrepancy "실제 발표 lag(예: CPI 수주)"
                                  # 기반. 시리즈별 실측 lag 테이블 부재 상태의 상한 가정 (검증 안 됨 (상한 가정)).
EVENT_DATE_REPORT_LAG_DAYS = 7    # DART 임원거래 법정 보고기한 5영업일(ast_field_map D1) → 달력 7일 보수 환산
CONSENSUS_DISC_LAG_DAYS = 1       # T-1 선언 vs 코드 same-day(제공시각 미상) → 보수 T-1 = +1d

# ----------------------------------------------------------------------------- 𝒪 연산자 (SOT §2 — 원안 v1.0 §2 채택)
# (S2d 정합 2026-07-25) operator_library.json(기계 SOT) canonical 명칭 병기 수용:
#   CS_ZSCORE/CS_WINSORIZE/CS_NEUTRALIZE/CS_DEMEAN/TS_DELTA — SOT §2 축약 표기
#   (ZSCORE/DELTA 등)와 라이브러리 canonical 표기가 검증기에서 갈라지던 dialect 갭 봉합.
#   의미론 동일(CS=children max / TS_DELTA=롤링류 t 구속)이라 판정 무영향·수용만 확장.
CS_OPS = {"CS_RANK", "ZSCORE", "WINSORIZE", "NEUTRALIZE", "DEMEAN",
          "CS_ZSCORE", "CS_WINSORIZE", "CS_NEUTRALIZE", "CS_DEMEAN"}
ROLLING_OPS = {"TS_MEAN", "TS_STD", "TS_RANK", "TS_MIN", "TS_MAX", "TS_SUM", "DELTA",
               "TS_DELTA"}
PAIR_OPS = {"TS_CORR", "TS_BETA"}
ARITH_OPS = {"ADD", "SUB", "MUL", "DIV", "LOG", "ABS", "SIGN", "SQRT"}
COND_OPS = {"CLIP", "IF_ELSE", "WHERE"}
PIT_OPS = {"AS_OF", "VINTAGE"}
O_ALL = CS_OPS | ROLLING_OPS | PAIR_OPS | ARITH_OPS | COND_OPS | PIT_OPS | {"TS_LAG"}

ESCAPE_LEAVES = {"MODEL_SCORE", "STORED_SCORE", "LLM_SCORE", "SPECIAL_OP"}
LEAF_KINDS = {"FIELD", "REGISTRY"} | ESCAPE_LEAVES

# ----------------------------------------------------------------------------- 비-registry 리프 그룹 avail 규칙
# ast_field_map_v0.json 실측 서술의 기계화. kind:
#   t1                : avail = t + 1d           (자동배치 T-1 계열)
#   t1_manual         : avail = t + 1d + 스테일 플래그 (수동 export/수집정지 — look-ahead 아님·스테일 위험)
#   strict_t1_manual22: avail = t + 1d (C2 strict) + 스테일 플래그(실효 ~22d, map A6 실측)
#   regulatory_fund   : quarterly → t + 45d / annual → 익년 3/31 (Step 0 확정, data_collector_dart.R:840)
#   event_rcept       : ref_basis=rcept → t + 0d / event_date → t + 7d (법정 5영업일 보수 환산)
#   c11_fred          : series_class=market_daily → t + 1d / release(기본) → t + 35d 보수 상한
GROUP_AVAIL = {
    # --- rawdata / 유니버스 / 벤치 / 지수 (map domain A — 일배치 cron 00:03, T-1 정합 실측)
    "A1_RAWDATA_OHLCVS_daily":              {"kind": "t1"},
    "A2_universe_krx_monthly":              {"kind": "t1"},
    "A3_universe_support_membership_panels": {"kind": "t1_manual",
        "stale_note": "수동 QuantiWise export — 월중 정기변경 최대 ~1개월 지연 반영(방향 PIT-안전, map A3)"},
    "A4_benchmark_kospi200":                {"kind": "t1"},
    "A5_index_panels_multi":                {"kind": "t1"},
    "A6_investor_flow_stock_daily":         {"kind": "strict_t1_manual22",
        "stale_note": "수동 export 실효 지연 ~22일 실측(map A6) — 미래참조 아님·라이브 스테일 위험"},
    "A8_investor_flow_market_aux":          {"kind": "t1_manual",
        "stale_note": "수집 정지 상태 실측(2026-03-13 종점, map A8) — 소비 전 재가동 필요"},
    # --- 재무 (map domain C — Step 0: C4 연간 = 익년 3/31 확정)
    "C-QWXLSX-RAW":                         {"kind": "regulatory_fund"},
    "C-DART-ANNUAL":                        {"kind": "regulatory_fund", "force_period": "annual"},
    "C-DART-QUARTERLY":                     {"kind": "regulatory_fund"},
    "C-FUND-MERGED":                        {"kind": "regulatory_fund"},
    # --- 컨센서스 (map C-CONSENSUS-QW — registry 선언 T-1 미러, 제공시각 미상은 registry disc와 동일 구조)
    "C-CONSENSUS-QW":                       {"kind": "t1"},
    # --- DART 이벤트 (map domain D — rcept_dt = 가용시점 권위, T+0 접수 당일)
    "D1_dart_insider_hist_events":          {"kind": "event_rcept"},
    "D2_dart_insider_recent_elestock":      {"kind": "event_rcept"},
    "D6_disclosure_list_archive":           {"kind": "event_rcept"},
    "D7_pledge_audit_census":               {"kind": "event_rcept"},
    "D8_buyback_decisions":                 {"kind": "event_rcept"},
    # --- 매크로 원천 (map domain E)
    "E1_fred_macro_raw":                    {"kind": "c11_fred"},
    "E2_ecos_kr_rates":                     {"kind": "t1"},
    # --- misc 수급/DART (map domain F — A6/A8 실측과 동일 계열)
    "F2_investor_flow_stock_level":         {"kind": "strict_t1_manual22",
        "stale_note": "QW export 수동 ~60d lag 기록(cache_registry flow_features note, map F2)"},
    "F3_investor_flow_market_level":        {"kind": "t1_manual",
        "stale_note": "cache_registry 미등재 orphan·수집 정지 실측(map F3)"},
    "F4_dart_pledge_audit_acquired":        {"kind": "event_rcept"},
}

# A1 내 투영 컬럼(원천은 A2/A3 — map A1 notes). 주석 전용(가용성 동일 t1).
A1_PROJECTED_FIELDS = {"K200", "KQ150", "Float", "AdminStock", "TradingHalt",
                       "UnfaithfulDisc", "Sector", "Sector_Lv2", "Name", "Market"}

# registry rule 문자열 → 해석기 키 (실측 5종 전수 — 본 파일 작성 시점 registry 스캔)
REGISTRY_RULES = {"T-1", "-1d", "strict_t-1;effective_lag~22d",
                  "C11_publication_lag", "quarterly+45d;annual_3/31"}


# ----------------------------------------------------------------------------- 날짜 유틸
def parse_date(s):
    if isinstance(s, _dt.date):
        return s
    return _dt.date.fromisoformat(str(s).strip()[:10])


def shift_months_back(d, k):
    """달력 k개월 후퇴 (일자 클램프: 3/31 - 1m = 2/28|29)."""
    y = d.year
    m = d.month - k
    while m <= 0:
        m += 12
        y -= 1
    last = calendar.monthrange(y, m)[1]
    return _dt.date(y, m, min(d.day, last))


def next_annual_331(t):
    """연간(사업보고서 계열) availability = 익년 3/31 (Step 0 확정, data_collector_dart.R:840)."""
    return _dt.date(t.year + 1, 3, 31)


# ----------------------------------------------------------------------------- 검증기 본체
class AstVerifier:
    def __init__(self, registry, field_map, decision_ts):
        self.registry = registry
        self.field_map_groups = self._index_groups(field_map)
        self.t_d = decision_ts
        # 수집 버킷
        self.violations = []          # FAIL_LOOKAHEAD 근거
        self.contract_failures = []   # FAIL_CONTRACT 근거
        self.restatement_leaves = []  # WARN_RESTATEMENT 근거 (restat ∧ vintage 無)
        self.discrepancy_used = []    # known_discrepancy 보수 적용 기록 (침묵 금지)
        self.staleness_flags = []
        self.notes = []
        self.leaf_count = 0
        self.dialect_args_used = False   # ALB-001: ast_compile.R 방언("args") 순회 여부
        self.parity_unverified = []      # ALB-002: production_parity_verified=false 리프(정직 선언)
        self.unmapped_restatement = []   # ALB-003: field_map 미등재로 개정위험 확인 불가한 리프
        self.op_count = 0

    @staticmethod
    def _index_groups(field_map):
        idx = {}
        for dom in field_map.get("domains", {}).values():
            for g in dom.get("leaf_groups", []):
                cls = str(g.get("ast_leaf_class", ""))
                idx[g["group_id"]] = {
                    "class": cls.split("(")[0].strip(),
                    "restatement_prone": bool(g.get("restatement_prone")),
                    "vintage_available": bool(g.get("vintage_available")),
                }
        return idx

    # ---- 기록 헬퍼 -----------------------------------------------------------
    def _fail_lookahead(self, path, leaf_desc, ref_ts, avail_ts, rule, detail):
        self.violations.append({
            "type": "LOOKAHEAD", "path": path, "leaf": leaf_desc,
            "ref_ts": str(ref_ts), "avail_ts": str(avail_ts),
            "decision_ts": str(self.t_d), "rule": rule, "detail": detail,
        })

    def _fail_contract(self, path, leaf_type, missing, detail):
        self.contract_failures.append({
            "path": path, "leaf_type": leaf_type, "missing": missing, "detail": detail,
        })

    def _mark_restatement(self, path, leaf_desc, source, under_vintage_pin):
        if under_vintage_pin:
            self.notes.append("%s: restatement-prone이나 VINTAGE 핀 하위 — 경고 면제 (§7)" % path)
            return
        self.restatement_leaves.append({"path": path, "leaf": leaf_desc, "source": source})

    def _mark_discrepancy(self, path, leaf_desc, rule, applied, note):
        self.discrepancy_used.append({
            "path": path, "leaf": leaf_desc, "rule": rule,
            "conservative_applied": applied, "registry_note_head": (note or "")[:160],
        })

    # ---- 리프 해석 -----------------------------------------------------------
    def _resolve_field_leaf(self, node, t, path, clamp_asof, under_pin):
        gid = node.get("group_id")
        field = node.get("field", "")
        desc = "FIELD[%s:%s]" % (gid, field)
        if not gid or gid not in self.field_map_groups:
            self._fail_contract(path, "FIELD", ["group_id"],
                                "미등재 리프 그룹 %r — canonical 리프 강제(SOT §4-1): ast_field_map 등재분만" % gid)
            return t
        ginfo = self.field_map_groups[gid]
        cls = ginfo["class"]
        if cls in ("EXTERNAL", "NOT_LEAF"):
            self._fail_contract(path, "FIELD", [],
                                "%s는 ast_leaf_class=%s — 리프 부적격(map 판정)" % (gid, cls))
            return t
        if cls in ("STORED_SCORE", "LLM_SCORE"):
            self._fail_contract(path, "FIELD", [],
                                "%s는 %s 그룹 — FIELD 위장 금지(SOT §4-1, 사고2 유형). escape 리프로 선언 필수"
                                % (gid, cls))
            return t
        # FIELD_REGISTRY_PTR 그룹을 FIELD로 직접 참조 → REGISTRY 리프로 재선언 유도
        if cls == "FIELD_REGISTRY_PTR":
            self._fail_contract(path, "FIELD", [],
                                "%s는 FIELD_REGISTRY_PTR — {\"leaf\":\"REGISTRY\",\"factor\":...}로 선언"
                                " (registry가 SOT, 3중 SOT 방지)" % gid)
            return t

        spec = GROUP_AVAIL.get(gid)
        if spec is None:
            self._fail_contract(path, "FIELD", [],
                                "%s: GROUP_AVAIL 미기계화 그룹 — 검증기 표 갱신 전 소비 불가(fail-closed)" % gid)
            return t
        kind = spec["kind"]

        if gid == "A1_RAWDATA_OHLCVS_daily" and field in A1_PROJECTED_FIELDS:
            self.notes.append("%s: %s는 A1 내 투영 사본 — 원천은 A2/A3 (map A1 notes)" % (path, field))

        if kind in ("t1", "t1_manual", "strict_t1_manual22"):
            avail = t + _dt.timedelta(days=1)
            if kind != "t1":
                self.staleness_flags.append({"path": path, "leaf": desc,
                                             "note": spec.get("stale_note", "manual export")})
        elif kind == "regulatory_fund":
            period = spec.get("force_period") or node.get("period") or "annual"  # 결측 = annual(보수)
            if period == "quarterly":
                avail = t + _dt.timedelta(days=FUND_QUARTERLY_LAG_DAYS)
                rule_used = "quarterly+45d"
            else:
                avail = next_annual_331(t)
                rule_used = "annual_3/31 (Step 0 확정)"
            # xlsx Q4 +45d(≈2/14) vs 3/31 — 보수 쪽(3/31) 판정 + 주석 (SOT §3 수리 항목)
            self._mark_discrepancy(path, desc, "quarterly+45d;annual_3/31", rule_used,
                                   "xlsx 경로 Q4 일률 +45d(≈익년 2/14)는 3/31 대비 공격적 — 보수(3/31) 기준 판정, "
                                   "노출창 [2/14,3/31) 수리 전 주석 (SOT §3)")
        elif kind == "event_rcept":
            basis = node.get("ref_basis", "rcept")
            if basis == "event_date":
                avail = t + _dt.timedelta(days=EVENT_DATE_REPORT_LAG_DAYS)
                self.notes.append("%s: 사건일 기준 참조 — 법정 5영업일 보고기한 보수 환산 +%dd (map D1)"
                                  % (path, EVENT_DATE_REPORT_LAG_DAYS))
            else:
                avail = t  # rcept_dt = 접수 당일 공개 (map 도메인 D 공통 규약)
        elif kind == "c11_fred":
            sc = node.get("series_class", "release")  # 결측 = release(보수)
            if sc == "market_daily":
                avail = t + _dt.timedelta(days=1)
            else:
                avail = t + _dt.timedelta(days=C11_CONSERVATIVE_LAG_DAYS)
                self._mark_discrepancy(path, desc, "C11_publication_lag",
                                       "+%dd 보수 상한" % C11_CONSERVATIVE_LAG_DAYS,
                                       "발표 lag 실측 테이블 부재 — 상한 가정 적용(모듈 상수 주석 참조)")
        else:  # pragma: no cover — GROUP_AVAIL 정의 오류 방어
            self._fail_contract(path, "FIELD", [], "%s: 알 수 없는 avail kind %r" % (gid, kind))
            return t

        if clamp_asof:
            avail = min(avail, t)  # 컴파일러-소유 as-of 조인이 가용분만 결합 (§4-2)
        if ginfo["restatement_prone"] and not ginfo["vintage_available"]:
            self._mark_restatement(path, desc, "ast_field_map:%s" % gid, under_pin)
        if avail > self.t_d:
            self._fail_lookahead(path, desc, t, avail, kind,
                                 "ref_ts + lag > decision_ts — TS_LAG 부족 또는 AS_OF 미적용")
        return avail

    def _resolve_registry_leaf(self, node, t, path, clamp_asof, under_pin):
        name = node.get("factor") or node.get("name")
        desc = "REGISTRY[%s]" % name
        entry = self.registry.get(name) if name else None
        if entry is None:
            self._fail_contract(path, "REGISTRY", ["factor"],
                                "factor_registry 미등재 %r — canonical 리프 강제(SOT §4-1)" % name)
            return t
        avail_meta = entry.get("availability") or {}
        rule = avail_meta.get("rule")
        disc = avail_meta.get("known_discrepancy")
        if rule not in REGISTRY_RULES:
            self._fail_contract(path, "REGISTRY", ["availability.rule"],
                                "%s: 해석 불가 rule %r — 검증기 rule 표 갱신 전 소비 불가(fail-closed)" % (name, rule))
            return t

        if rule == "T-1":
            if disc:  # consensus 33건: 코드 same-day 허용·제공시각 미상 → 보수 T-1
                avail = t + _dt.timedelta(days=CONSENSUS_DISC_LAG_DAYS)
                self._mark_discrepancy(path, desc, rule, "+%dd (보수 T-1)" % CONSENSUS_DISC_LAG_DAYS, disc)
            else:
                avail = t  # 내부 T-1 강제 — sig_date t 행은 t에 가용
        elif rule == "-1d":
            avail = t
        elif rule == "strict_t-1;effective_lag~22d":
            avail = t  # C2 strict(compute_investor.R:100) — look-ahead 없음
            self.staleness_flags.append({"path": path, "leaf": desc,
                                         "note": "수동 export 실효 지연 ~22d (rule 자체 표기) — 라이브 스테일 위험"})
        elif rule == "C11_publication_lag":
            avail = t + _dt.timedelta(days=C11_CONSERVATIVE_LAG_DAYS)
            self._mark_discrepancy(path, desc, rule,
                                   "+%dd 보수 상한" % C11_CONSERVATIVE_LAG_DAYS, disc)
        else:  # quarterly+45d;annual_3/31
            avail = t  # 빌더 .pit_fund as-of 내부강제(factor_db_builder.R:389-401) — 구조적 look-ahead 없음
            self._mark_discrepancy(path, desc, rule, "as-of 내부강제 인정(avail=t)",
                                   (disc or "") + " | Q4 노출창 [2/14,3/31) 수리 전 주석(SOT §3)")

        if clamp_asof:
            avail = min(avail, t)
        if entry.get("restatement_prone") and not entry.get("vintage_available"):
            self._mark_restatement(path, desc, "factor_registry:%s" % name, under_pin)
        if avail > self.t_d:
            self._fail_lookahead(path, desc, t, avail, rule,
                                 "registry rule 보수 판정 결과 decision_ts 초과 — TS_LAG 보강 필요")
        return avail

    # ---- escape 리프 계약 ----------------------------------------------------
    def _resolve_escape_leaf(self, node, t, path, under_pin):
        kind = node["leaf"]
        desc = "%s[%s]" % (kind, node.get("id") or node.get("group_id") or node.get("name") or "")
        if kind == "MODEL_SCORE":
            missing = [f for f in ("training_window_end", "training_leaves") if not node.get(f)]
            if missing:
                self._fail_contract(path, kind, missing,
                                    "MODEL_SCORE 계약 결측 — 학습창 종점(<= t_d-1) 선언 + 학습 리프 목록 의무 (SOT §2)")
                return t
            twe = parse_date(node["training_window_end"])
            if twe > self.t_d - _dt.timedelta(days=1):
                self._fail_lookahead(path, desc, twe, twe, "MODEL_SCORE",
                                     "학습창 종점 %s > t_d-1 (%s) — 학습창 계약 위반"
                                     % (twe, self.t_d - _dt.timedelta(days=1)))
            deadline = parse_date(node["trained_at"]) if node.get("trained_at") else self.t_d
            if node.get("trained_at") and deadline > self.t_d - _dt.timedelta(days=1):
                self._fail_lookahead(path, desc, deadline, deadline, "MODEL_SCORE",
                                     "trained_at %s > t_d-1 — walk-forward 위반" % deadline)
            # 학습 데이터 리프는 각각 본 맵 검증 대상 (SOT §2) — 학습창 종점 시점으로 검증
            saved_td = self.t_d
            self.t_d = deadline
            for i, tl in enumerate(node["training_leaves"]):
                self._verify(tl, twe, "%s.training_leaves[%d]" % (path, i), False, under_pin)
            self.t_d = saved_td
            return twe
        if kind == "STORED_SCORE":
            # ALB-001 (2026-08-02): provenance 위치 방언 이중 수용.
            #  문서형 = node["provenance"] / ast_compile.R = node["contract"].
            #  종전엔 앞쪽만 봐서, 계약을 **정확히 채운** 패키지도 "provenance 결측"으로
            #  반려됐다 — 검사기가 있는 곳을 안 봐서 나는 거짓 위반이다.
            prov = node.get("provenance") or node.get("contract") or {}
            missing = [f for f in ("store_build_hash", "generator_code_path", "generated_at")
                       if not prov.get(f)]
            # ── ALB-002 수리 (2026-08-02): 선언 회피와 정직한 false 를 구분한다 ──
            #  종전 `is not True` 는 **false 선언을 결측과 동일 취급**했다. 그러면
            #  production 대응물이 아직 없는 신규 리서치 패널은 (a) 정직히 false → FAIL_CONTRACT
            #  (b) true → 거짓 주장, 둘뿐이라 **정직한 진입 경로가 존재하지 않는다.**
            #  이는 v8.3 이 주력으로 선언한 '비-return 신규 원천' lane 을 기계가 막는 형태다.
            #  규범 정합: measurement-graduation §7b 의 production-코드-권위는 **incumbent base
            #  비교 측정**에 걸리는 요건이지, 신규 후보 패널의 존재 자격이 아니다.
            #  → 키 부재 = 계약 결측(선언 회피) / false = 통과 + 미검증 플래그(judge·governor 입력).
            ppv = prov.get("production_parity_verified",
                           node.get("production_parity_verified"))
            if ppv is None:
                missing.append("production_parity_verified")
            elif ppv is not True:
                self.parity_unverified.append({"path": path, "leaf": desc})
                self.notes.append(
                    "%s: production_parity_verified=false — 정직 선언으로 통과시키되 "
                    "incumbent base 비교(§7b)에는 이 패널을 쓸 수 없다(judge·governor 입력)." % path)
            if missing:
                self._fail_contract(path, kind, missing,
                                    "STORED_SCORE 계약 결측 — provenance 3필드 + production_parity_verified 의무 "
                                    "(§7b 기계화, 저장 패널 FIELD 위장 금지)")
            gid = node.get("group_id")
            if gid and gid in self.field_map_groups:
                gi = self.field_map_groups[gid]
                if gi["restatement_prone"] and not gi["vintage_available"]:
                    self._mark_restatement(path, desc, "ast_field_map:%s" % gid, under_pin)
            else:
                # ── ALB-003 수리 (2026-08-02): 미등재 리프의 조용한 skip 금지 ──────
                #  종전엔 group_id 가 없거나 map 밖이면 restatement 검사를 그냥 건너뛰었다.
                #  그 결과 **개정 위험이 가장 큰 원천이 무경고 통과**했다(실사례: 관세 수출
                #  패널 — 매월 전 이력을 무기한 개정하는데 restatement_leaves 가 빈 배열).
                #  위험과 검사 커버리지가 반비례하는 구조다.
                #  확인 **불가**를 확인 **완료**로 취급하지 않는다 — 외부 저장 패널은
                #  vintage 보장을 증명하지 못하면 보수적으로 restatement 로 표시한다.
                #  (WARN_RESTATEMENT = 통과 + 스펙 플래그이므로 과차단이 아니다. SOT §4)
                if not (node.get("vintage_available") is True):
                    self.unmapped_restatement.append({"path": path, "leaf": desc, "group_id": gid})
                    self._mark_restatement(
                        path, desc,
                        "unmapped:%s" % (gid or "no_group_id"), under_pin)
                    self.notes.append(
                        "%s: field_map 미등재 STORED_SCORE — 개정(restatement) 위험을 확인할 수 "
                        "없어 보수적으로 표시했다. 해소하려면 ast_field_map 등재 또는 리프에 "
                        "vintage_available=true 를 근거와 함께 선언할 것." % path)
            if node.get("embedded_data_through"):
                edt = parse_date(node["embedded_data_through"])
                if edt > self.t_d - _dt.timedelta(days=1):
                    self._fail_lookahead(
                        path, desc, edt, edt, "STORED_SCORE",
                        "embedded_data_through %s > t_d-1 (%s) — 동월 vintage 소비 형상 "
                        "(실사고 2: stored-panel same-month lookahead, production T-1 규약 §7b)"
                        % (edt, self.t_d - _dt.timedelta(days=1)))
                return edt
            return t
        if kind == "LLM_SCORE":
            if not node.get("doc_rcept_dt"):
                self._fail_contract(path, kind, ["doc_rcept_dt"],
                                    "LLM_SCORE 계약 결측 — 채점 대상 문서 rcept_dt 선언 의무 (SOT §2)")
                return t
            rdt = parse_date(node["doc_rcept_dt"])
            if rdt > self.t_d:
                self._fail_lookahead(path, desc, rdt, rdt, "LLM_SCORE",
                                     "문서 rcept_dt %s > t_d — 미래 문서 채점" % rdt)
            if not (node.get("prompt_sha") and node.get("model_sha")):
                self.notes.append("%s: prompt/model sha 동결 미선언 — 재현성 경고 (SOT §2)" % path)
            return rdt
        if kind == "SPECIAL_OP":
            missing = [f for f in ("op_code_path",) if not node.get(f)]
            if node.get("walk_forward") is not True:
                missing.append("walk_forward")
            if missing:
                self._fail_contract(path, kind, missing,
                                    "SPECIAL_OP 계약 결측 — 연산 정의 코드 경로 + walk-forward 선언 의무 (SOT §2)")
            return t
        self._fail_contract(path, kind, [], "알 수 없는 escape 리프 %r" % kind)  # pragma: no cover
        return t

    # ---- 재귀 ---------------------------------------------------------------
    def _verify(self, node, t, path, clamp_asof=False, under_pin=False):
        if not isinstance(node, dict):
            self._fail_contract(path, "?", [], "노드 형상 오류(비 dict): %r" % (node,))
            return t
        # ── ALB-001/007 수리 (2026-08-02): 리프 방언 이중 수용 ──────────────────
        #  문서형 방언 : {"leaf": "FIELD", ...}
        #  컴파일러 방언: {"type": "leaf", "class": "STORED_SCORE", ...}  (ast_compile.R)
        #  종전엔 앞쪽만 인식해 컴파일러 트리에서 leaf_count 가 0이 되고, 리프가
        #  연산자로 오인돼 "𝒪 밖 연산자 None" 이 나거나(수리 중간 상태) 순회 자체가
        #  멈춰 빈 PASS 가 나왔다. PIT 정적검증의 본체가 리프 avail_ts 이므로,
        #  리프를 못 세면 이 검증기는 아무것도 검증하지 않는다.
        if ("leaf" in node) or (node.get("type") == "leaf"):
            self.leaf_count += 1
            kind = node.get("leaf") or node.get("class")
            if kind is not None:
                kind = str(kind)
            if "leaf" not in node:
                # 하위 resolver 들이 node["leaf"] 를 직접 읽으므로 진입 지점에서 정규화한다
                # (사본 — 입력 트리는 건드리지 않는다).
                node = dict(node)
                node["leaf"] = kind
            if kind == "FIELD":
                return self._resolve_field_leaf(node, t, path, clamp_asof, under_pin)
            if kind == "REGISTRY":
                return self._resolve_registry_leaf(node, t, path, clamp_asof, under_pin)
            if kind in ESCAPE_LEAVES:
                return self._resolve_escape_leaf(node, t, path, under_pin)
            self._fail_contract(path, str(kind), [],
                                "알 수 없는 리프 종류 %r (허용: %s)" % (kind, sorted(LEAF_KINDS)))
            return t

        op = node.get("op")
        self.op_count += 1
        # ALB-001 (2026-08-02): 연산자 파라미터 위치 방언 이중 수용.
        #  문서형 = {"op":"TS_LAG", "k":21, "unit":"d"} (최상위)
        #  ast_compile.R = {"op":"TS_LAG", "params":{"k":12}} (하위 묶음)
        #  종전엔 최상위만 읽어 k/window/unit 이 전부 None 으로 보였고, 정상 트리가
        #  "TS_LAG k 비정수/결측" 으로 반려됐다. 최상위 명시값이 우선하도록 병합한다.
        if isinstance(node.get("params"), dict):
            _merged = dict(node["params"])
            _merged.update(node)
            node = _merged
        # ── ALB-001/007 수리 (2026-08-02): 노드 방언 이중 수용 ──────────────────
        #  ast_compile.R 은 자식을 "args" 로, 본 검증기 문서형은 "children" 으로 쓴다.
        #  종전엔 "children" 만 읽어 컴파일러가 실제로 실행하는 트리에서 자식 순회가
        #  0이 되고, 위반이 없어서가 아니라 **아무것도 보지 않아서** PASS 가 나왔다.
        #  (실측: leaf_count=0 · op_count=1 로 PASS — WT-D20260802_001 라운드 적발)
        children = node.get("children")
        if children is None:
            children = node.get("args")
            if children is not None:
                self.dialect_args_used = True
        if children is None:
            children = []
        if op not in O_ALL:
            self._fail_contract(path, "OP", [],
                                "𝒪 밖 연산자 %r — SOT §2 확장 규율(operator_backlog 경유)·ast_spec_gate ④ 대상" % op)
            # fail-closed지만 하위 리프 정보도 수집
            for i, c in enumerate(children):
                self._verify(c, t, "%s.%s/%d" % (path, op, i), clamp_asof, under_pin)
            return t

        if op == "TS_LAG":
            k = node.get("k")
            unit = node.get("unit", "d")
            if not isinstance(k, int) or k < 0:
                if isinstance(k, int) and k < 0:
                    self._fail_lookahead(path, "TS_LAG(k=%d)" % k, t, t, "TS_LAG",
                                         "음수 lag = LEAD 등가 — 𝒪 LEAD 부재 원칙 위반(문법 제거 대상)")
                else:
                    self._fail_contract(path, "OP", ["k"], "TS_LAG k 비정수/결측: %r" % (k,))
                return t
            t_shift = shift_months_back(t, k) if unit == "m" else t - _dt.timedelta(days=k)
            return self._verify(children[0], t_shift, "%s.TS_LAG[k=%d%s]/0" % (path, k, unit),
                                clamp_asof, under_pin) if children else t
        if op in ROLLING_OPS:
            # 롤링류 — 창의 최신 관측(t)이 구속 (원안 §4)
            return max([self._verify(c, t, "%s.%s/%d" % (path, op, i), clamp_asof, under_pin)
                        for i, c in enumerate(children)] or [t])
        if op in PAIR_OPS:
            return max([self._verify(c, t, "%s.%s/%d" % (path, op, i), clamp_asof, under_pin)
                        for i, c in enumerate(children)] or [t])
        if op == "AS_OF":
            rule = str(node.get("rule", "")).strip().lower().replace(" ", "")
            clamped = rule in ("factor_date<=t", "usable_date<=t", "date<=t", "date<t",
                               "factor_date<t", "usable_date<t")
            if not clamped:
                self.notes.append("%s: AS_OF rule %r 해석 불가 — 클램프 불인정(보수), children 그대로 판정"
                                  % (path, node.get("rule")))
            return max([self._verify(c, t, "%s.AS_OF/%d" % (path, i), clamp_asof or clamped, under_pin)
                        for i, c in enumerate(children)] or [t])
        if op == "VINTAGE":
            if not node.get("pin_tag"):
                self._fail_contract(path, "OP", ["pin_tag"],
                                    "VINTAGE 노드 pin_tag 결측 — §7 vintage pinning 규약(핀 tag 기록 의무)")
                return max([self._verify(c, t, "%s.VINTAGE/%d" % (path, i), clamp_asof, under_pin)
                            for i, c in enumerate(children)] or [t])
            self.notes.append("%s: VINTAGE pin_tag=%s — subtree restatement 경고 면제 (§7)"
                              % (path, node["pin_tag"]))
            return max([self._verify(c, t, "%s.VINTAGE/%d" % (path, i), clamp_asof, True)
                        for i, c in enumerate(children)] or [t])
        # CS/산술/조건 — children max
        return max([self._verify(c, t, "%s.%s/%d" % (path, op, i), clamp_asof, under_pin)
                    for i, c in enumerate(children)] or [t])

    # ---- 진입점 -------------------------------------------------------------
    def run(self, ast_root, sig_date):
        max_avail = self._verify(ast_root, sig_date, "root")
        # ── ALB-007 근본 방어 (2026-08-02): 빈 순회를 PASS 로 반환하지 않는다 ────
        #  리프를 하나도 못 본 검증은 "위반 없음"이 아니라 "판정 불가"다. 방언이
        #  또 갈리든 트리 형상이 바뀌든, 검사가 죽으면 통과가 아니라 계약 실패로
        #  드러나야 한다 — 오탐 제거와 검사 사망은 겉보기가 같다.
        if self.leaf_count == 0:
            self._fail_contract(
                "root", "TRAVERSAL", [],
                "리프 0개 순회 — 빈 검증은 PASS 가 될 수 없다(ALB-007). "
                "노드 방언(children/args) 불일치 또는 트리 형상 오류를 의심하라. "
                "op_count=%d" % self.op_count)
        if self.violations:
            verdict = "FAIL_LOOKAHEAD"
        elif self.contract_failures:
            verdict = "FAIL_CONTRACT"
        elif self.restatement_leaves:
            verdict = "WARN_RESTATEMENT"
        else:
            verdict = "PASS"
        return verdict, max_avail


# ----------------------------------------------------------------------------- 패키지 로딩
def extract_asts(pkg):
    """[CF-10/ALB-006 CLI측 수리 2026-08-02] schema 정본 위치 factors[].ast 포함 전량 수집.
    ALB-006 수리(08-02)가 ast_spec_gate.sh 훅에는 들어갔으나 이 CLI 는 구판 그대로였다 —
    같은 결함이 두 소비자에 있는데 한쪽만 고치면 '수리됨'과 '안 됨'이 공존한다
    (WT-D20260802_002 CF-10 적발). 다중 팩터는 전 팩터를 각각 검증해야 한다."""
    out = []
    for holder in (pkg, pkg.get("factor_definition") or {}, pkg.get("spec") or {}):
        if isinstance(holder, dict) and isinstance(holder.get("ast"), dict):
            out.append(holder["ast"])
    for f in (pkg.get("factors") or []):
        if isinstance(f, dict) and isinstance(f.get("ast"), dict):
            out.append(f["ast"])
    uniq, seen = [], set()
    for a in out:
        try:
            k = json.dumps(a, sort_keys=True, ensure_ascii=False)
        except Exception:
            k = id(a)
        if k in seen:
            continue
        seen.add(k)
        uniq.append(a)
    return uniq


def extract_ast(pkg):
    a = extract_asts(pkg)
    return a[0] if a else None


def extract_pit_dates(pkg, cli_sig, cli_td):
    pit = pkg.get("pit") or {}
    sig = cli_sig or pit.get("sig_date") or pkg.get("sig_date")
    td = cli_td or pit.get("decision_ts") or pkg.get("decision_ts")
    if sig is None:
        raise ValueError("sig_date 결측 — package pit.sig_date 또는 --sig-date 필요")
    sig_d = parse_date(sig)
    td_d = parse_date(td) if td else sig_d  # 결측 시 sig_date 당일 판정(최엄격)
    if td_d < sig_d:
        raise ValueError("decision_ts(%s) < sig_date(%s) — 형상 오류" % (td_d, sig_d))
    return sig_d, td_d


def main(argv=None):
    ap = argparse.ArgumentParser(description="AST PIT 정적검증기 (Qvest AST v1.1 SOT §4)")
    ap.add_argument("package", help="alpha_package.json 경로")
    ap.add_argument("--out", help="verdict JSON 출력 경로 (기본: stdout만)")
    ap.add_argument("--decision-ts", dest="decision_ts", help="t_d 오버라이드 (YYYY-MM-DD)")
    ap.add_argument("--sig-date", dest="sig_date", help="sig_date 오버라이드 (YYYY-MM-DD)")
    ap.add_argument("--registry", default=DEFAULT_REGISTRY)
    ap.add_argument("--map", dest="field_map", default=DEFAULT_FIELD_MAP)
    args = ap.parse_args(argv)

    with open(args.package, encoding="utf-8") as f:
        pkg = json.load(f)
    with open(args.registry, encoding="utf-8") as f:
        registry = json.load(f)
    with open(args.field_map, encoding="utf-8") as f:
        field_map = json.load(f)

    ast_root = extract_ast(pkg)
    result = {
        "schema": "ast_verify/v1",
        "strategy_id": pkg.get("strategy_id"),
        "package_path": os.path.abspath(args.package),
        "checked_at": _dt.datetime.now().isoformat(timespec="seconds"),
        "sources": {
            "factor_registry": os.path.abspath(args.registry),
            "ast_field_map": os.path.abspath(args.field_map),
            "field_map_version": (field_map.get("_meta") or {}).get("version"),
        },
    }
    if ast_root is None:
        result.update({"verdict": "FAIL_CONTRACT",
                       "contract_failures": [{"path": "root", "leaf_type": "PACKAGE",
                                              "missing": ["ast"],
                                              "detail": "package에 ast 노드 부재 (top-level/factor_definition/spec)"}],
                       "violations": [], "restatement_leaves": [], "discrepancy_used": [],
                       "staleness_flags": [], "notes": []})
        _emit(result, args.out)
        return 1

    sig_d, td = extract_pit_dates(pkg, args.sig_date, args.decision_ts)
    v = AstVerifier(registry, field_map, td)
    verdict, max_avail = v.run(ast_root, sig_d)

    result.update({
        "verdict": verdict,
        "sig_date": str(sig_d),
        "decision_ts": str(td),
        "max_avail_ts": str(max_avail),
        "leaf_count": v.leaf_count,
        # 2026-08-02: 방언·parity 가시화 (ALB-001/002/007)
        "dialect_args_used": v.dialect_args_used,
        "parity_unverified": v.parity_unverified,
        "unmapped_restatement": v.unmapped_restatement,
        "op_count": v.op_count,
        "violations": v.violations,
        "contract_failures": v.contract_failures,
        "restatement_leaves": v.restatement_leaves,
        "discrepancy_used": v.discrepancy_used,
        "staleness_flags": v.staleness_flags,
        "notes": v.notes,
    })
    _emit(result, args.out)
    return 0 if verdict in ("PASS", "WARN_RESTATEMENT") else 1


def _emit(result, out_path):
    txt = json.dumps(result, ensure_ascii=False, indent=2)
    print(txt)
    if out_path:
        tmp = out_path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(txt)
        os.replace(tmp, out_path)


if __name__ == "__main__":
    sys.exit(main())
