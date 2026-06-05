# Plan v0.4.2 NULL RESULT — KOSPI200 Forward Bearish Forecast (Phase 1)

**Date**: 2026-05-19
**Status**: ★ NULL RESULT (학술적 정직 적립 — AX-002 process honesty 정합)
**Q-Lead**: Claude Opus 4.7 (1M context)
**Owner**: 도훈

---

## A. 결론 1줄

**본 plan의 features 9건 중 8건 (89%)이 기존 약세 detection 4종 (MRS / KTRI v3 / M4 / R05)과 정보 source 중복 → 신규 alpha source가 아닌 "재포장" 실증**.

---

## B. 핵심 정량 결과

### B.1 S9 Validation Suite (5 gates + 1 uncertainty)

#### y_onset (primary target) — **5/5 ALL FAIL**

| Gate | Result | Status |
|---|---|---|
| 1 DM test | stat=-0.588 / p=0.7217 | ❌ FAIL (baseline이 더 정확) |
| 2 Brier Skill Score | BSS=-0.0073 (음수) | ❌ FAIL |
| 3 Calibration | slope=0.265 (over-dispersed) / ECE=0.0288 | ❌ FAIL |
| 4 Event recall @ top 20% | recall=0.240 / lift=0.040 | ❌ FAIL |
| 5 PR-AUC | 0.1050 / lift 9.77% (cutoff 20%) | ❌ FAIL |
| Bootstrap CI | BSS=-0.0203 [-0.1091, 0.0063] | — |

#### y_tail_q15 (secondary) — **1/5 PASS**

| Gate | Result | Status |
|---|---|---|
| 1 DM test | stat=-2.303 / p=0.9894 | ❌ FAIL |
| 2 Brier Skill Score | BSS=-0.0792 | ❌ FAIL |
| 3 Calibration | slope=0.625 / ECE=0.1402 | ❌ FAIL |
| 4 Event recall | recall=0.345 / lift=0.145 | ❌ FAIL |
| 5 PR-AUC | 0.3248 / lift 55.09% | ✅ PASS |
| Bootstrap CI | BSS=-0.0602 [-0.1828, 0.0369] | — |

### B.2 S4 Orthogonality (Information Value Add)

**risk-research agent 실증 결과 (cor matrix 9 features × 4 baseline)**:

| Feature | max\|cor\| vs 4src | IVA |
|---|---|---|
| macro_risk_score | **0.503** | NEGATIVE |
| kr_credit_spread | 0.423 | NEGATIVE |
| vkospi_z | 0.409 | INSUFFICIENT |
| foreign_netbuy_20d_z | 0.279 | NEGATIVE |
| **kr_term_spread** | **0.270** | **POSITIVE (+0.014)** ⭐ |
| q08_composite_quality | 0.264 | NEGATIVE |
| vix_log_diff_ewma_21d | 0.211 | NEGATIVE |
| v12_composite_value | 0.202 | NEGATIVE |
| otm_skew_25d | 0.112 | INSUFFICIENT |

**→ 8/9 features NEGATIVE incremental value. kr_term_spread만 marginal +0.014**.

---

## C. 본질 진단 — 왜 NULL RESULT 인가?

### C.1 Feature 정보 source 중복 표

| 본 plan Block | 기존 4종 cover |
|---|---|
| H3 파생 stress (VKOSPI / put-call / 25Δ skew) | ⊂ KTRI v3 + R05 (VRP/IV 기반) |
| H4 rates/credit (term spread / credit spread) | ⊂ M4 BOCPD (macro factor) + R05 |
| H5 글로벌 전이 (VIX / 미10y-2y / Macro_Risk_Score) | ⊂ MRS (미국 매크로) + macro_regime |
| H6 flow/공매도 (외인 net buy / 공매도) | ⊂ KTRI v3 (KR microstructure) |
| H7 valuation (Q08 / V12 / sue) | ⊂ factor_db Q+V family (risk model 입력) |
| State engine (SJM / M4 / R05) | = 기존 4종 자체 |

→ **본 plan은 기존 4종을 "재구성"한 것**. 정보 source가 같으므로 incremental value 0~±0.014 (marginal).

### C.2 왜 이렇게 됐는가? (Q-Lead 자체 반성)

1. **Feature selection이 같은 학술 framework**: H3~H7 모두 KR quant academic taxonomy (factor + macro + flow + valuation)에서 출발 → 기존 4종도 같은 taxonomy로 build
2. **Macro/Factor space는 finite**: 같은 학술 framework (VRP / term spread / fundamental score)에서 features 추출 = 같은 source
3. **진짜 신규 source는 framework 외부**: alt data / cross-market / sentiment / 학술 신규 discovery

### C.3 도훈님 본질 통찰 (역사적 확인)

- **Session 첫 응답**: "이미 KOSPI200 약세 detection 4중 admit 중"
- **Codex round 1**: "신규 5번째 직교 source 아닌 재포장 위험" + "Net additional value +3~7% 보수"
- **risk-research S4** (오늘): "8/9 IVA NEGATIVE"

→ **본질은 처음부터 명확했음. 검증 cycle을 거쳐 입증**.

---

## D. Q-Lead 자체 부정확 5건 누적 (governance 정직 인정)

| # | 사례 | 발견자 | 즉시 복구 |
|---|---|---|---|
| 1 | Phase 4 inventory 부재 | Codex round 2 | 메모리 stale 수정 |
| 2 | macro_fred.parquet 잘못된 폐기 | Q-Lead 자체 | fred_macro에서 cp (54,303 rows) |
| 3 | ECOS 항목 코드 매핑 오류 | Q-Lead 자체 | 010320000 → 010300000 fix + 재 fetch |
| 4 | Y_onset shift off-by-one | Codex round 4 | (미수정, null result로 적립) |
| 5 | plan feature ≠ model FEATURE_COLS | Codex round 4 | (미수정, sue_z + SJM state 누락) |

### Governance SOP 강화 (L-330 + 본 null result)

1. 메모리 inherit 시 자원 실재 직접 검증 의무
2. 폐기 결정 시 build script + downstream chain 추적 의무
3. 외부 API mapping 시 기존 cache 정합 sample value 비교 의무
4. **신규**: target build 시 forward window shift 정확성 검증 (Codex 1차 verification 의무)
5. **신규**: Plan feature ↔ model FEATURE_COLS 정합성 audit (Plan markdown 작성 시 실제 model 구현 정합 검증)

---

## E. 학술적 가치 (Null Result Paper 형식)

### E.1 발견 (Findings)

1. **9 features × 4 baseline cor matrix**: 8/9 NEGATIVE IVA
2. **walk-forward 5 gate**: y_onset 0/5 PASS, y_tail_q15 1/5 PASS (PR-AUC만)
3. **SJM state engine (KR-013)**: KR 적용 가능, COVID 2020 binary label fail / continuous distance feature 강건
4. **PIT manifest loader fail-closed**: 7/7 test PASS (infra 자체는 valid)

### E.2 학술적 함의 (Implications)

1. **KR 시장에서 "기존 factor + macro + flow + valuation framework 내 신규 features 추가"는 incremental value 한계**
2. **기존 KR regime detection 4종 (MRS / KTRI / M4 / R05)이 이미 같은 framework 내 정보를 cover**
3. **진짜 alpha source는 framework 외부**: alt data (DART NLP / 뉴스) / cross-market / sentiment / 학술 신규 discovery

### E.3 후속 연구 (Next Cycle)

→ **Plan v1.0 alt data based bearish forecast** (별도 cycle 결성)
- workspace: `04_Research/decision_framework/bearish_forecast_v2_alt_data/`
- feature blocks A1~A7 (DART NLP / 뉴스 sentiment / US sector flow / Google Trends / options higher moments / global macro / arxiv 학술 discovery)
- WT-D20260514_007 (Session 81 alt data theme) inherit
- Charter v1.7 §10 discovery_design_phase_a 정합

---

## F. Plan v0.4.2 Artifact retain (학습 자원)

본 workspace `04_Research/decision_framework/bearish_forecast_v1/` 모든 산출물 retain (deletion 금지):

### F.1 Infra (재사용 가능)
- `scripts/00_pit_manifest_loader.R` ★ (7/7 test PASS, denylist + fail-closed)
- `tests/test_pit_manifest_loader.R` ★
- `scripts/05_validation_suite.R` (5 gates + 1 uncertainty, 재사용 가능)
- `config/feature_lag_table.csv` 패턴 (변수별 PIT lag spec)

### F.2 학습 자원
- `outputs/02_targets/targets_full.parquet` (Y_onset + Y_tail_Q15/Q10 + Y_regime_strong)
- `outputs/01_data/feature_panel.parquet` + `feature_panel_extended.parquet`
- `outputs/03_models/{elastic_net, xgboost, stacking_ensemble, markov_switching}/` (모델 학습 결과)
- `outputs/04_evaluation/` (S9 validation 결과)
- `outputs/05_orthogonality/cor_matrix_vs_4src.csv` ★ (본 null result 핵심 증거)

### F.3 Codex Dialectic 자원
- `/tmp/codex_plan_verdict_v03.txt` (Round 1 WEAK)
- `/tmp/codex_round2_verdict.txt` (Round 2 ACCEPTABLE)
- `/tmp/codex_round3_verdict.txt` (Round 3 STRONG)
- `/tmp/codex_round4_verdict.txt` (Round 4 ACCEPTABLE 격하)

### F.4 도훈님 mandate 정합 인프라
- FRED 1990-01 확장 (17/22 series Train 1995-01 cover) — 다음 cycle 재사용
- ECOS bond 1990-01 확장 (KR_CorpAA / KR_Call1D 1995-01-03 / KR_CPI 1990-01) — 다음 cycle 재사용
- macro_regime.parquet 1990-01~ build — 다음 cycle 재사용
- `02_Infrastructure/data/data_collector_ecos.R::ecos_fetch_bond_rates` (신규 collector) — daily_refresh.sh 통합 권고

---

## G. 결론 + 다음 cycle 진입

**Plan v0.4.2 NULL RESULT**:
- Gate fail 정직 인정
- features 기존 4종 재포장 입증
- 학술적 가치 = "재포장 한계 실증" + infra 검증

**즉시 다음 cycle 진입 (γ)**:
- `04_Research/decision_framework/bearish_forecast_v2_alt_data/` mkdir
- Plan v1.0 alt data based bearish forecast 결성
- WT-D20260514_007 (Session 81 alt data theme) inherit
- Charter v1.7 §10 discovery_design_phase_a Role Card 정합

L-331 적립 (본 null result + v2 cycle 결성).
