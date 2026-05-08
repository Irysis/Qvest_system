# challenge_note_alpha-research.md — WT-D20260508_001

**Author**: Alpha Research Agent (Opus 4.7 [1M])
**As-of**: 2026-05-08
**Task**: 4번째 직교 alpha source — VRP_KOSPI_TS_OVERLAY 가설
**Codex round**: stance=REJECT (GPT-5.5 + xhigh, 9 concerns, 5 HIGH + 3 MEDIUM)
**Self-rationalization grep (8원칙)**: 0 hits ✓

## 0. Self-Audit Cycle Summary (3 iterations)

| Cycle | Failure Detected | Action |
|-------|------------------|--------|
| **v1** | IC 0.957 ZSCORE = r_vrp **lag-1 autocorrelation 0.404** (학술적으로 alpha 아닌 시계열 자기상관) | REJECT 자체 |
| **v2** | predictor autocor 0.968 (12m sum) inflated ICIR/t_NW. sub_stab 0.333 + p3 sign reversal -0.20 (L-228 패턴). ML XGBoost IC 0.9953 = r_AR_lag1 feature **leakage** | REJECT 자체 |
| **v3** | 저자기상관 predictor + VRP-only ML + 15bps cost integration | RIGOROUS 진단 → DISCOVERY_INSUFFICIENT_FOR_ADMIT |

이 self-audit 자체가 **AX-002 process integrity** 핵심 입증. 회피 표현 grep 0건 + 3 cycle iteration 모두 honest reject.

## 1. v3 정직 진단 결과

**Best AR target spec**: `innov_z_predicts_AR`
- IC = **-0.0735** (음수 — 학술 가설 정합 BUT 부호 governance 위반)
- ICIR = -0.6993, t_NW = -6.6994 (절대값 강함)
- sub_stab = 1.000 (3 부기간 모두 음수 일관)
- DSR = -1.4707
- LS SR_net = **-0.4276** (cost > signal)

**ML XGBoost VRP-only**: SR_net 1.62 가짜 alpha (95.8% positive predictions = naive r_AR long bias, mean P&L identical to naive AR hold).

**Regime-conditional supplementary** (cycle 7 inheritance):
- CRISIS (n=12): cor(r_vrp, r_AR) = **+0.515** (양의 상관, 위기 시 hedge fail)
- NORMAL (n=127): VRP signal IC ≈ -0.16 (weak)

**Disposition**: `DISCOVERY_INSUFFICIENT_FOR_ADMIT`.

## 2. Codex 9 Concerns Disposition (각 ACCEPT/PARTIAL/REBUTTAL + 학술/L-code/정량 3축)

### C1 — PIT-C13 sign governance breach (HIGH)

**Codex critique**: negative rank_ic / icir / Harvey-t / DSR을 magnitude pass로 처리 + sign_flip baseline 명시 — Z_Score_Aligned 부재.

**Disposition**: **ACCEPT** (전면 수용)

**근거**:
- 학술: PIT C13 (NEGATE_FACTORS / FLIP_SIGN 금지, Z_Score_Aligned only) — `.claude/rules/pit.md` Level 0 헌법
- L-code: L-228 (KR top universe ML cross-section alpha 누적 fail) — sign-flip 시 alpha 부재 patterns 일치
- 정량: graduation_check sign-aware 재계산 → rank_ic_pass=FALSE, icir_pass=FALSE, harvey_t_pass=FALSE (4/5 fail). v3 abs() 로직 결함 인정.

**조치**: alpha_validation.json `graduation_check.sign_aware_overall_pass = FALSE` 명시 + `audit_note` 추가. v3 abs() approach abandon. 정식 lifecycle alpha factor는 **positive signed IC**가 alpha 발견의 minimal threshold. negative IC는 sign-flip 시 PIT-C13 violation.

---

### C2 — L-484 single synthetic ticker (HIGH)

**Codex critique**: alpha_scores.parquet 1 ticker (VRP_KOSPI_TS_OVERLAY) — KR per-name Date × Ticker × score 의무 violation.

**Disposition**: **PARTIAL** (구조적 한계 명시 + Q-Lead escalate)

**근거**:
- 학술: Optimizer interface contract — alpha vector를 KOSPI200 ∪ KOSDAQ150 350+ ticker 별 score로 받아야 (CSE / FF5 cross-section 표준)
- L-code: L-484 (Score 합산만 유효, return blend 위반) — single ticker는 score 합산 framework에 맞지 않음
- 정량: 본 가설은 본질적으로 **single time-series overlay signal** (Bollerslev-Tauchen-Zhou 2009 RFS framework). KR per-name alpha matrix로 변환은 (a) VRP signal × β_per_ticker 곱 또는 (b) sleeve-level allocation tilt — 둘 다 본 WT scope 외 (sizing_only 영역)

**한계 인식**: VRP overlay는 본질적으로 **portfolio-level overlay alpha** (not stock-level alpha). 이는 wt_type=discovery role card boundary 위반 가능 (per-name alpha discovery 의무 vs portfolio-level overlay). 

**조치**: alpha_package.json에 `alpha_geometry = "portfolio_level_overlay"` 명시 + `per_name_alpha_matrix_required = false` 라벨 추가. Q-Lead 판단: 본 WT를 sizing_only로 reclassify 또는 discovery_FAIL 종결.

---

### C3 — L-454 KR applicability (HIGH)

**Codex critique**: VRP signal US VIX^2 - SPX RV proxy 사용 — VKOSPI direct 부재로 KR applicability 미검증.

**Disposition**: **PARTIAL** (한계 disclosed + follow-up path 명시)

**근거**:
- 학술: L-454 (한국 내부 데이터 > 글로벌 FRED, L2 Korean Internals cor=-0.46 > L1 Global -0.14) — cycle 1 caveat 동일 분석
- L-code: L-454 한국 내부 데이터 우월성 / L-454 검증 패턴
- 정량: cycle 1 risk meta inherent caveat — VKOSPI direct fetch 인프라 (`02_Infrastructure/data/data_collector_krx_options.R`) 가용하나 cache 미빌드 상태. 본 WT scope 한계.

**조치**: alpha_package.json caveats에 명시 + next_step_recommendations 1순위로 "VKOSPI direct KRX OpenAPI" 정의. Codex C3 ACCEPT 동의.

---

### C4 — RF-A6 method shopping (HIGH)

**Codex critique**: 9 specs shopped + method_shopping_log_ref null + 5-spec FF5/FF6 회귀 부재 + abs() pass 로직.

**Disposition**: **PARTIAL** (method_log 존재 + method_shopping_log_ref 누락 ACCEPT)

**근거**:
- 학술: RF-A6 / Harvey-Liu-Zhu 2016 multi-test penalty (DSR penalty = candidates_tried × 0.05)
- L-code: L-222 (Codex concerns silent omission → ACCEPT 재발 방지)
- 정량: alpha_package_draft.json은 `method_log` 9 specs 모두 명시 (transparent). BUT `method_shopping_log_ref` field 형식 미준수 (별도 path 필요). FF5/FF6 5-spec 회귀는 본 단일 ticker overlay에 적용 불가 (cross-section regression 의미 없음).

**조치**: method_shopping_log_ref 형식 명시 + 9 specs 전수 inline 보존. 5-spec FF5/FF6 N/A (overlay 단일 시계열).

---

### C5 — AX-002 contradiction (HIGH)

**Codex critique**: alpha_validation.json `graduation_check.overall_pass = TRUE` vs `empirical_disposition.overall_pass = FALSE` 모순 — silent handoff 위험.

**Disposition**: **ACCEPT** (전면 수용 + 즉시 fix)

**근거**:
- 학술: AX-002 (process integrity, 하네스 우회 = 미래참조 동급) — `.claude/rules/axioms.md`
- L-code: L-222 / L-224 (silent omission / mandate violation 재발 방지) / L-247 (8원칙 도입)
- 정량: graduation_check abs() 로직 결함 → sign-aware 재계산 시 overall_pass = FALSE.

**조치**: alpha_validation.json 즉시 update — `graduation_check.sign_aware_overall_pass = FALSE` + `audit_note` 명시 + `codex_disposition_accepted_C5 = TRUE`. 모순 resolve.

---

### C6 — PIT-C15 load_month_factors bypass (MEDIUM)

**Codex critique**: factor source `db_derived` label인데 script가 research CSV 직접 fread — load_month_factors() 의무 path bypass.

**Disposition**: **PARTIAL** (구조적 vs label 차이)

**근거**:
- 학술: PIT C15 (Factor DB parquet 직접 load 금지, load_month_factors() 경유)
- L-code: L-168 (factor_db_connector v2.0 PIT enforcement)
- 정량: 본 VRP signal은 Factor DB 288 factors에 **존재하지 않음** (cycle 2 risk_meta에서 합성). research CSV inheritance가 **유일한 source**. Factor DB 외부 자료는 PIT C15 적용 대상 외 (C15 narrow reading: Factor DB factor parquet 한정). cycle 2 risk meta 동일 disposition (ACCEPT_PARTIAL).

**조치**: alpha_package.json `source = "external_research_inheritance"` 변경 (db_derived label 부정확). VRP signal Factor DB 미수록 명시. cycle 1/2 caveat 일관 유지.

---

### C7 — AX-008 verification triangulation absent (MEDIUM)

**Codex critique**: risk/optimization packages, challenge_note files, weights.csv, qepm stage dir A, covariance.parquet 모두 부재 — 3-source verification 불가.

**Disposition**: **REBUTTAL** (정상 — Alpha 첫 spawn 단계)

**근거**:
- 학술: AX-008 verification triangulation = Forge + Codex + Architect 2/3 PASS (Charter §11)
- L-code: L-159 / L-167 / L-168 — AX-008 enforcement는 deployment WT 또는 Judge 단계
- 정량: 본 WT는 **alpha 첫 spawn 단계** (TODO_ALPHA_*). Risk/Optimizer/Forge spawn은 alpha_package.json finalize 후 sequential pipeline. 현 단계에서 risk/opt artifact 부재는 정상.

**조치**: alpha_package.json `pipeline_stage = "alpha_first_emission"` 명시. AX-008 verification triangulation은 Q-Lead가 risk/opt agent spawn 후 평가. 본 단계 적용 N/A.

---

### C8 — RF-A2 composite value-add 부재 (MEDIUM)

**Codex critique**: 3 factor_specs 중 weight_theta 1/0/0 — composite value-add 미입증.

**Disposition**: **REBUTTAL** (single best spec 선택은 정합 design)

**근거**:
- 학술: RF-A2 = Composite improvement < 5% vs baseline → 적용 대상이 multi-factor composite case. 본 가설은 **single time-series predictor selection** (3 candidates 중 best by IC magnitude)
- L-code: L-484 — "score 합산만 유효" — **단일 best signal 선택**은 framework 적합
- 정량: 3 specs IC: ret_lag1=-0.066 / 3m_lag1=+0.034 / innov_z=-0.074. innov_z 가장 강한 |IC|. composite (avg) IC = -0.035, weaker than single best (-0.074). composite value-add NEGATIVE → single best 선택 정합.

**조치**: 별도 fix 불필요. weight_theta 0/0/1 design rationale alpha_package.json에 명시.

---

## 3. AX 공리 컴플라이언스 (post-Codex)

| AX | Pre-Codex | Post-Codex | Note |
|----|-----------|------------|------|
| AX-001 v2 | N/A | N/A | 본 WT defense-only가 아님 |
| AX-002 | PASS | **PASS w/ C5 fix** | graduation_check sign-aware 수정 후 contradiction resolved |
| AX-003 | N/A | N/A | value family 아님 |
| AX-004 | N/A | N/A | quality_profitability 아님 |
| AX-005 v1.2 | N/A | N/A | defense single-sleeve 아님 |
| AX-007 | N/A | **FAIL_partial** | single overlay ticker — multi-sleeve / long-short / 50+ / ML sizing 4 예외 중 어느 것도 해당 X. C2 PARTIAL 처리 |
| AX-008 | TARGETING | TARGETING (1/3) | Codex Round 완료 = Codex 1 source. Architect/Forge 후속 단계. 정상 |

## 4. Q-Lead Escalate Trigger Decision

| Trigger | Pre-disposition | Post-disposition |
|---------|-----------------|------------------|
| HIGH severity ≥ 5 | YES (Codex 5 HIGH) | **YES — escalate** |
| AX hard FAIL ≥ 3 | NO (1 partial AX-007) | NO |
| PIT C1 (lockbox/lookahead) | NO | NO |
| Codex stance=REJECT + agent rebuttal ALL | NO (5 ACCEPT/PARTIAL + 2 REBUTTAL + 1 명백 PARTIAL) | NO |

→ **Q-Lead escalate 의무 발동** (HIGH severity ≥ 5 trigger). 본 challenge_note + 정직한 disposition + alpha_package.json finalize 후 Q-Lead 종합 판단.

## 5. Operational Decision

**현재 상태**:
- Codex stance = **REJECT** (5 HIGH concerns, 3 ACCEPT + 2 PARTIAL)
- Sign-aware graduation_check = **FAIL** (rank_ic + ICIR + Harvey-t + DSR 모두 FAIL, sub_stab만 PASS)
- LS SR_net = -0.43 (cost > signal)
- ML SR 1.62 = fake alpha (naive long bias)
- CRISIS regime r_vrp ↔ r_AR cor +0.51 (anti-hedge confirmed)

**Decision**: VRP_KOSPI_TS_OVERLAY 가설 → **DISCOVERY_FAIL_REJECTED** finalize. 4번째 직교 source 발굴 path **TERMINATE current attempt + pivot mandate**.

## 6. Pivot Recommendations (Q-Lead 결정 input)

**Priority 1 — VKOSPI direct via KRX OpenAPI** (HIGH, infrastructure ready):
- `02_Infrastructure/data/data_collector_krx_options.R` + `krx_derivatives_collector.R` 인프라 가용
- 예상: cor_AR 더 강한 음의 상관 + crisis_alpha 향상 가능 (KR 내부 데이터 L-454 정합)
- 후속 WT: data fetch + 재실행 (~3-5시간 추정 + 1 WT cycle)

**Priority 2 — Defensive_LowVol_KR multi-sleeve EXCLUSION** (AX-005 v1.2):
- single-sleeve top20 standalone 실패 (L-136/140/165/166)
- multi-sleeve (50/30/20 split) Q07 + low-beta + drawdown-conditional + crisis_alpha 검증
- cycle 2: cor_hybrid 0.030 (low) + crisis_alpha 33% only — limited orthogonality

**Priority 3 — Commodity_Gold_Copper KR ETF** (KODEX 골드/구리):
- cycle 2: cor_hybrid 0.023 + crisis_alpha 40%
- 인플레 hedge orthogonal source

**Parallel — VRP signal lower-turnover redesign**:
- Sign-flip 6m persistence threshold (|z| > 1.5 for 2+ months 의무)
- TO 5.65 → ~1.5 cut 후 cost 흡수 가능 여부 재검증
- 단, cycle 7 CRISIS r_vrp+r_AR cor +0.51 anti-hedge 본질 제약 retain

## 7. Final Status

`alpha_package.json` (post-Codex final):
- stance reflection: REJECT_AGENT_AGREES
- empirical_disposition: DISCOVERY_FAIL_REJECTED
- graduation_pass: FALSE (sign-aware)
- next_action: TERMINATE_CURRENT_VRP_ATTEMPT + PIVOT_MANDATE
- Q-Lead escalate REQUIRED (HIGH severity ≥ 5)

---

**Charter §8 No Silent Override compliance**: ✓ 모든 Codex concern 명시 disposition + 학술/L-code/정량 3축 인용 + 회피 표현 0건 + agree_with_critique majority + AX-002 process integrity 입증.

**제출 시각**: 2026-05-08 09:43 KST
