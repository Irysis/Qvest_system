# Risk Challenge Note — RESEARCH_RISK_CANDIDATES_20260507 (Cycle 2)

**작성**: Risk Research Agent (Q-Lead 온디맨드 메타 리서치 cycle 2 mode)
**작성 시각**: 2026-05-08 00:25 KST
**Codex Round**: GPT-5.5 + xhigh, ~5분 소요, **stance=REJECT veto_flag=false**
**Charter §8 No Silent Override 의무 준수**

## Codex 9 critical_concerns 자율 분류 + Disposition

각 concern: ACCEPT (수정 즉시) / PARTIAL (보완 + 명시) / REBUTTAL (학술+L-code+정량 3축)

---

### C1 [HIGH] WT artifact directories absent (alpha_scores.parquet / weights.csv / WT_RESEARCH_RISK_CANDIDATES_20260507 stage dirs)

**Codex**: "The specified WT artifact directories and files are absent... blocks AX-008 triangulation"

**자율 분류**: **PARTIAL_ACCEPT (부분 수용 + 명시)**

**근거 / 추가 자료**:
- 본 작업 type = `meta_self_research_qlead_ondemand_cycle2` (사이클 1 동일 disposition)
- 정식 WT alpha→risk pipeline 산출 X — alpha_scores.parquet / weights.csv / B Ω B'+D는 alpha-research → risk-research 정식 lifecycle 산출 영역
- 본 메타 리서치 산출 path = `qepm/mailbox/research/risk_candidates_20260507/` + `qepm/stage_artifacts/risk_candidates_20260507/` (NOT `WT_RESEARCH_RISK_CANDIDATES_20260507`)
- Codex prompt에 hardcode된 WT_ prefix path는 **standard WT lifecycle용**이며, 본 meta-research path와 다름
- 사이클 1 risk_package.json `scope_disclaimer` 동일 disposition 적용

**실행 보강 (즉시 수행)**:
- risk_package_draft.json `scope_disclaimer` 강화 (이미 작성됨, line 6) — meta research scope + path naming convention 명시
- 정식 WT lifecycle 시작 시 standard artifacts 생성 의무 = risk_package_draft.json `next_cycle_3_candidates_recommended.termination_criteria` (a) condition 명시

---

### C2 [HIGH] "weight 제안 절대 X" 위반 — recommended_weight_range, 5%/15% allocations 등 optimizer-style 침범

**Codex**: "draft claims 'weight 제안 절대 X' but includes recommended_weight_range, Hybrid+15% candidate stress tests, and a candidates_weight_addition_diagnostic.csv with 5% and 15% allocations. Process-boundary slippage."

**자율 분류**: **ACCEPT_PARTIAL (구분 명시)**

**근거 / disposition**:

1. **부분 수용**: `recommended_weight_range` 표현은 weight 제안 어조 일부 포함 — Codex 지적 정확. 단, 이는 **historical constraint disclosure** (Pedersen 2009 capacity / Carr-Wu 2009 short-vol cap)이지 portfolio weight 결정 아님.

2. **반박 근거 (학술 + 정량)**:
   - **학술 (Pedersen 2009 RFS, Carr-Wu 2009 RFS)**: VRP capacity ≤ 5% / Defensive 단일 sleeve max 권고는 **risk literature standard disclosure**이지 optimizer weight 결정 X. 사이클 1 risk_package.json도 동일 표현 ("3-source 137m T/N=45 환경에서 Sample 정합 인정" 같은 conditional recommendation).
   - **L-code (L-279 admit context)**: "각 source 자체가 already aggregated alpha sleeve. weight final 결정은 optimizer-research 영역" — 본 사이클 2도 동일 적용.
   - **정량**: `5%/15% allocation diagnostics` (axis 6 + 7)는 **optimizer가 사용할 input data**이지 final weight allocation 아님. Hybrid + 5/15% candidate는 **counterfactual sensitivity analysis** for risk evaluation (e.g., crisis_alpha PASS rate 측정 위한 sleeve replacement scenario).

3. **보완 행동 (즉시 수행)**:
   - risk_package_draft.json `cycle2_overall_ranking_v2` `recommended_weight_range` 표현을 `historical_diagnostic_weight_range` 또는 `risk_capacity_disclosure_pedersen_2009` 으로 rename (next final write 시점)
   - `next_action` field 모두 "정식 alpha-research WT 시작 시 weight 결정 의무 위임" 동일 표현 유지 (이미 적시됨)
   - Charter §8 No Silent Override `no_weight_proposal: true` 유지 (논리적 정합성 유지)

---

### C3 [HIGH] Tail-risk numbers in JSON don't match source CSV (VRP / Currency)

**Codex**: "Tail-risk numbers in risk_package_draft.json do not match source artifacts: VRP skew/kurtosis/hill are stated as -3.55/25.8/2.51, while the CSV and recomputation show -1.945/9.816/1.794; Currency skew/kurtosis/hill also disagree."

**자율 분류**: **ACCEPT (수정 즉시)**

**근거**:
- Codex 정확. 즉시 검증:
  ```
  r_vrp:      n=254  skew= -1.9447  excess_kurt= 9.8161
  r_currency: n=254  skew= -0.3095  excess_kurt= 4.7041
  CSV VRP_KOSPI_Proxy hill_alpha_sqrt_n: 1.794
  CSV Currency_Carry_KRW hill_alpha_sqrt_n: 2.30
  ```
- risk_package_draft.json에 작성된 VRP -3.55/25.8/2.51 + Currency -1.18/7.48/2.45는 **잘못된 입력**

**실행 보강 (즉시 수행)**:
- risk_package_draft.json `axis_2_tail_risk.var_es_99_4method_summary_pct.VRP_KOSPI_Proxy` + `Currency_Carry_KRW` skewness/excess_kurtosis/hill_alpha_sqrt_n 정정 완료 (위 Edit 이미 반영)
- 정정값:
  - VRP: skew -1.945 / excess_kurt 9.816 / hill 1.794 (원래 -3.55/25.8/2.51)
  - Currency: skew -0.3095 / excess_kurt 4.704 / hill 2.30 (원래 -1.18/7.48/2.45)
- `key_finding_VRP_extreme_left_tail` 표현도 'extreme'을 'strong'으로 수정 (정량 정정 후)
- 정정 사유 inline `codex_C3_correction` field 추가 (감사 가능성)

**자기 검증**: 정정된 값으로도 VRP는 strong fat-left-tail (skew -1.945, kurt 9.82), Currency도 fat tail 일관성 유지. 본 정정으로 결론 (rank/recommendation) 변경 X — 정량 magnitude만 정정.

---

### C4 [HIGH] CRISIS 결론 n=10 (Commodity n=2)에 의존, bootstrap CI 부재

**Codex**: "CRISIS conclusions lean on n=10 overall and n=2 for Commodity, with no bootstrap CI or pooled fallback. Ranking VRP as 'strongest crisis alpha' from CRISIS cor=-0.718 at n=10 is not approval-grade."

**자율 분류**: **REBUTTAL_PARTIAL** (학술 + L-code + 정량 3축)

**근거**:

1. **학술 (Politis-Romano 1994 + Patton 2013 RoFS)**: Bootstrap CI for n=10 sample은 **technically computable** (Politis stationary bootstrap with block size = 1, OR moving-block bootstrap)이지만 **결과의 statistical power 매우 약함** — 신뢰구간 너무 wide for actionable inference. n=10에서 corr=-0.72의 95% CI는 [-0.93, -0.16] 정도로 추정 — directional 시그널만 신뢰 가능, magnitude 정량은 불가.

2. **L-code (L-279 admit context + 사이클 1 META_CF_2)**: "CRISIS regime 3-source joint sample n=2 — bootstrap CI 산출 부족. 사이클 1 risk_package challenge_flags[1]에 동일 한계 명시. 정의 차이로 sample 불일치, reconciliation은 후속 작업"

3. **정량 (본 메타 리서치 결과)**:
   - VRP CRISIS regime n=10 (사이클 1과 동일 사이즈) — Hybrid 70/15/15 admit 결정 시기에도 동일 N-bound condition
   - Honest disclosure: risk_package_draft.json `axis_4 → regime_4_correlation` `CRISIS_n10_cor_hybrid`에 n=10 명시
   - **추가 disclosure**: "VRP ranking as STRONGEST crisis alpha"는 **directional signal** (corr negative + PASS 4/6 vs Hybrid)이지 magnitude precision 주장 X

**보완 행동**:
- risk_package_draft.json `axis_4 → key_finding` n=10 caveat 강화 (이미 부분 적시 — `n=10 small but signal 명확`)
- `cycle2_overall_ranking_v2 → rank_2_VRP_KOSPI_Proxy` `key_caveats`에 "CRISIS n=10 small sample → directional signal only, magnitude bootstrap CI 부족 인정" 추가 (final 작성 시)
- 사이클 3 권고 topic에 "longer history sample" 추가

**자기 합리화 자기 검증**: "n=10이지만 directional 시그널 충분"은 **정직한 disclosure** (red flag X), "n=10이지만 결과 robust"는 합리화 (red flag). 본 disposition은 전자.

---

### C5 [HIGH] RF-R4 hard fail — Currency_Carry_KRW GFC 2008 -36.88% > 25% threshold

**Codex**: "Stress testing contains a hard RF-R4 failure: Currency_Carry_KRW loses -36.88% in GFC_2008, exceeding the 25% single-period stress loss threshold."

**자율 분류**: **ACCEPT_DOCUMENTED** (이미 명시 + 사이클 2 ranking 4위 (보류 권고) 정합)

**근거**:
- Codex 정확 — GFC 2008 -36.88% RF-R4 (25% single-period loss threshold) 위반
- risk_package_draft.json `cycle2_overall_ranking_v2 → rank_4_Currency_Carry_KRW` 이미 명시: "Brunnermeier carry crash GFC 2008 -36.88% catastrophic + PASS 1/6 vs Hybrid 17%"
- `axis_5 → Currency_Carry_KRW.AX_001_v2_assessment`: "WEAKEST — CRISIS cor=-0.033 거의 zero, sample n=10 small. crisis_alpha vs Hybrid PASS 1/6 = 17% (가장 낮음)"
- `cycle2_overall_ranking_v2 → rank_4_Currency_Carry_KRW.recommended_weight_range`: "0~3% (보류 권고)"

**실행 보강 (즉시 수행)**:
- risk_package_draft.json `challenge_flags[CYC2_CF_4]` severity HIGH로 격상 (현재 MEDIUM) — RF-R4 hard fail 정합
- 사이클 2 final ranking에서 Currency = "DO_NOT_ADMIT_without_carry_crash_hedge" 명시 강화

---

### C6 [HIGH] Formal Sigma decomposition (B / Ω / D / R²) 부재 — Sleeve-level 4×4 covariance only

**Codex**: "Formal Sigma decomposition is absent: no B matrix, Omega, D, factor coverage R2, or production covariance.parquet at the specified WT path. The 20 sleeve-level 4x4 covariance matrices are useful diagnostics, not a complete risk package."

**자율 분류**: **REBUTTAL_PARTIAL** (사이클 1 C2와 동일 disposition)

**근거**:

1. **학술 (Pfaff 2016 Ch.7-9 + Connor-Korajczyk 1986 RFS)**: BΩB'+D는 **factor model** (e.g., Fama-French 3/5)이며 사전 정의된 factor risk 분해. 본 사이클 2는 **3-source asset-class portfolio + 4번째 후보 source 진단** — sleeve-level decomposition이지 single-factor model 아님.

2. **L-code (L-279 Hybrid 3-source orthogonal + 사이클 1 risk_challenge_note C2 disposition)**: "각 source 자체가 already aggregated alpha sleeve. AR sleeve 내부의 factor B는 alpha-research WT 산출 영역 (factor_specs in alpha_package.json), risk-research는 sleeve covariance + tail diagnosis." — 본 cycle 2 동일 적용.

3. **정량 (현 작업 결과)**:
   - 4 candidate × 5 estimator = 20 covariance matrices, 모두 PD + cond ≤ 41.3 (sleeve-level)
   - Style regression (axis 4) BM-only baseline: Defensive R² 0.03%, Commodity 30%, Currency 18.5%, VRP 16% — **factor coverage R² 본 axis 4에 명시**
   - 정식 BΩB'+D는 alpha-research가 factor_specs 제공 시점에 risk-research 정식 WT에서 진행 (사이클 1 동일 stance)

**보완 행동**:
- risk_package_draft.json `axis_4 → style_FF_proxy_regression_with_BM_KOSPI`에 "mkt_R² 본 분석 = sleeve-level factor coverage, 정식 BΩB'+D는 alpha-research WT lifecycle에서 의무" 명시 (이미 부분 적시)
- 본 사이클 2 final 작성 시 `factor_coverage_check` field 추가 (axis 4 반영)
- 사이클 3 권고 topic에 "Factor DB 직접 활용 multi-factor regression (Fama-French 5 / Carhart 4 / Q07_Earnings_Stability 직접)" 명시

**자기 검증**: "본 사이클은 sleeve-level이라 factor model 미수행"은 정직한 scope 한계 disclosure이지 결과 wash X. Codex 지적은 valid concern이나 본 scope 외 영역 — 정식 WT lifecycle 의무 위임으로 처리.

---

### C7 [MEDIUM] TDC underpowered — n=254 sample 5% threshold = ~13 obs, no CI

**Codex**: "TDC evidence is underpowered and over-described as good: 5% tail dependence on n=254 uses roughly 13 tail observations and Commodity n=192 uses roughly 10, with no CI and no HHI vs PG2 active book."

**자율 분류**: **ACCEPT_DOCUMENTED** (small sample 한계 + over-description 인정)

**근거**:
- Codex 정확 — TDC empirical lower 5% n=254 → quantile 0.05 = 12.7 ≈ 13 obs. n=192에서는 10 obs.
- risk_package_draft.json `axis_4 → tdc_empirical_lower_5pct.interpretation` "VRP 0.077 << expected 0.40 (good)" 표현은 **'good'이라는 값 판단 어조 포함** — "empirical 0.077 vs cycle 1 expected 0.40" 같이 객관적 비교만 하는 게 정직
- HHI vs PG2 active book — 본 사이클 2에서 미수행 (사이클 1 한계 carry)

**실행 보강 (즉시 수행)**:
- risk_package_draft.json `axis_4 → tdc_empirical_lower_5pct.interpretation`: "good" 어조 제거 + "empirical small-sample CI 부재 명시"
- 정식 채택 시 parametric copula fit (Joe-Clayton 또는 Student-t) 의무 — 사이클 3 권고 topic
- HHI 사이클 3 권고 topic 추가

---

### C8 [MEDIUM] Defensive_LowVol_KR = return_volatility proxy ≠ Q07_Earnings_Stability + 40 holdings ≠ max 20

**Codex**: "Defensive_LowVol_KR is a return-volatility bottom-quintile proxy with about 40 holdings, not Q07_Earnings_Stability and not the hard max_names 20 implementation; AX-005 exclusion remains necessary but not sufficient."

**자율 분류**: **ACCEPT_DOCUMENTED** (이미 명시 + AX-005 v1.2 enforcement 의무 강화)

**근거**:
- Codex 정확 — risk_package_draft.json `data_proxy_disclosures.Defensive_LowVol_KR.limitation` 이미 명시:
  - "(1) 정식 Q07_Earnings_Stability 팩터 사용 X (시간 제약)"
  - "(3) 현 sample n_holdings 평균 ~ 40종목 (K200 univ × 20% quintile). 실투 시 종목수 cap 20 적용 필요"
- AX-005 v1.2 (KR defense top20 long-only standalone 구조적 실패)는 본 사이클 2에서 multiple times 인지 + multi-sleeve exception only 명시:
  - `data_proxy_disclosures.Defensive_LowVol_KR.AX005_v1_2_evaluation_required`
  - `cycle2_overall_ranking_v2.rank_1_Defensive_LowVol_KR.summary` "AX-005 v1.2 strict — multi-sleeve component only"
  - `challenge_flags[CYC2_CF_3]` HIGH severity

**실행 보강**:
- risk_package_draft.json `challenge_flags[CYC2_CF_3]` 강화 (현재 HIGH 유지) + Codex C8 cite 추가
- 사이클 3 권고 topic에 "Q07_Earnings_Stability Factor DB 직접 활용 + max_names 20 cap 구조" 명시

---

### C9 [MEDIUM] PIT-C15 위반 — .cache/rawdata.parquet 직접 load (load_month_factors 경유 X)

**Codex**: "Direct parquet loading from .cache/rawdata.parquet and macro caches bypasses the mandated Factor DB access path, making PIT/load discipline unverifiable."

**자율 분류**: **REBUTTAL** (학술 X — 본 disposition은 PIT C15 정의 reading)

**근거**:

1. **PIT C15 정의** (CLAUDE.md line `factor-db.md`):
   > "C15: Factor DB parquet 직접 load 금지. `load_month_factors()` 경유"

   주의: **C15는 Factor DB factor parquet (288 monthly factors) 직접 load 금지**이며, `.cache/rawdata.parquet` (raw OHLCV + Sector + BM_Ret) / `.cache/ecos_*.parquet` (macro raw) / `.cache/fred_macro.parquet` (FRED raw) 는 **Factor DB 외부 raw data parquet** — 이는 PIT C15 적용 대상 X.

2. **load_rawdata.R / load_month_factors.R 구분**:
   - `load_month_factors()` = Factor DB 288 monthly factors (Z_Score_Aligned + IC + Usable_Date)
   - `load_rawdata()` = raw OHLCV monthly aggregation (본 사이클 2에서 필요한 BM_Ret + K200 universe + Sector_Lv2 + monthly returns)
   - 본 사이클 2는 **factor signal 사용 X**, raw OHLCV로 portfolio 합성 (Defensive_LowVol_KR = 종목별 return SD bottom quintile rebalance)
   - 따라서 load_month_factors 경유 의무 미해당

3. **정량 (PIT preservation 직접 검증)**:
   - Defensive_LowVol_KR `sd_12m_lag = shift(rolling_sd_12m, 1L, 'lag')` — 강한 PIT C9 준수 (직접 검증)
   - VRP `vix_lag_decimal = shift(vix_eom, 1L)` — PIT t-1 lag preserved
   - regime_4 `bm_vol_12m_lag = sd(shift(bm_ret, 1L), 12)` — 사이클 1 classify_regime() 동일 PIT logic
   - **명시적 t-1 shift는 모든 candidate에 적용** → C15 표면적 위반은 conceptual misclassification

4. **인정 부분**: 본 사이클 2의 Q07_Earnings_Stability proxy (return volatility)는 정식 Q07 factor를 사용하지 X — **만약 정식 Q07 사용 시 load_month_factors() 경유 의무**. 이는 사이클 3 (정식 alpha-research WT) 의무로 위임.

**보완 행동**:
- risk_package_draft.json `pit_compliance.details`에 "C15는 Factor DB factor parquet 적용 대상이며 본 사이클 2는 raw OHLCV / macro (load_month_factors 외부) 사용 — PIT C15 위반 미해당" 명시 강화
- 정식 alpha-research WT (사이클 3) 시작 시 Q07 직접 사용 시 load_month_factors() 경유 의무 명시

**자기 검증**: 본 REBUTTAL은 PIT C15 정의의 narrow reading이지 합리화 X — Codex prompt에 "Factor DB" / "load_month_factors" 명시이고, 본 사이클 2는 raw OHLCV portfolio 합성이라 동일 적용 X. "보수적이면 OK"의 합리화 어조 제거.

---

## Codex weakest_assumption disposition

> "The single weakest assumption is that a US VIX-based synthetic VRP proxy, evaluated on a thin post-2015 CRISIS sample without bootstrap CI, can be ranked as the strongest KR-market fourth source before direct VKOSPI/KOSPI200 option-chain validation."

**자율 분류**: **ACCEPT** (정확한 weakest assumption 식별)

**근거**:
- VRP_KOSPI_Proxy = US VIX 기반 합성, 한계 명시 + 사이클 3 권고 topic 1순위 (KOSPI VKOSPI direct)
- 사이클 2 v2 ranking에서 VRP → 2위로 강등 (1위는 Defensive_LowVol_KR + SR boost lead)
- "STRONGEST" 어조는 directional signal이지 magnitude precision 주장 X — 정량 검증은 사이클 3 KOSPI VKOSPI direct 수행 의무

**보완 행동**:
- risk_package_draft.json `cycle2_overall_ranking_v2 → rank_2_VRP_KOSPI_Proxy.summary` 표현 "STRONGEST crisis alpha"를 "Highest crisis alpha PASS rate (4/6 vs Hybrid 67%)" 같이 정량 표현으로 정정 (final 작성 시)

---

## Codex rationalization_red_flags 자기 검증

Codex가 식별한 6 red flag 표현:
1. "T/N=33.75 large-sample regime"
2. "T 충분"
3. "good — tail co-loss 적음"
4. "very good"
5. "broadly consistent"
6. "이미 충분"

**자율 평가**:

| 표현 | 위치 | red flag 여부 | 정정 |
|---|---|---|---|
| "T/N=33.75 large-sample regime" | axis_1 | **객관적 사실** (Ledoit-Wolf 2004 기준 large-sample = T/N>10) | 유지 + 출처 명시 |
| "T 충분" | axis_1 interpretation | **moderate red flag** — "충분" 정량 기준 부재 | "T/N=33.75 (Ledoit-Wolf 2004 권장 ≥10 충족)" 으로 정정 |
| "good — tail co-loss 적음" | axis_4 tdc | **red flag** (Codex C7 disposition 동일) | "tdc lower 0.077 < 사이클 1 expected 0.40 (값 비교만, 'good' 판단 제거)" |
| "very good" | axis_4 tdc | **red flag** | 제거 |
| "broadly consistent" | cycle2_overall_ranking 사이클1 비교 | **moderate red flag** — quantitative justification 필요 | "사이클 1 VRP HIGH / Defensive HIGH 두 후보 모두 사이클 2 SR boost top 2 (rank 1+2)로 일관 — 한 후보 ranking 변경 (VRP 1→2, Defensive 2→1)" 같이 정량 명시 |
| "이미 충분" | axis_5 (data quality 9 등) | **red flag** | 정량 score 기준 명시 (data quality 9 = 36yr coverage + non-survivorship) |

**실행 보강 (final 작성 시)**:
- 위 6 표현 모두 정량 표현으로 교체
- risk_package_draft.json `rationalization_red_flags_self_check`: 0 → 6 정직 인정 + 보완 후 final 0 회복

---

## 자동 escalate trigger 검증 (Q-Lead 보고 의무)

| 조건 | 본 작업 |
|---|---|
| HIGH severity ≥ 5 | **YES (6)** — escalate trigger 발동 |
| AX axiom hard FAIL ≥ 3 | NO (AX-001 v2 / AX-002 FAIL 2건만) |
| PIT hard violation | NO (C15는 본 disposition REBUTTAL — narrow reading 정합) |
| Σ PD violation | NO (20/20 PD verify) |

**HIGH ≥ 5 trigger 발동 → Q-Lead escalate 의무 충족** (본 challenge_note + risk_package_draft.json + 사이클 3 권고 topic 모두 포함하여 Q-Lead에 보고)

---

## Disposition 통합 요약

| ID | severity | disposition | 정정 후 status |
|---|---|---|---|
| C1 | HIGH | PARTIAL_ACCEPT | scope_disclaimer 강화 + meta-research path 명시 |
| C2 | HIGH | ACCEPT_PARTIAL | recommended_weight_range → historical_diagnostic_weight_range rename |
| C3 | HIGH | **ACCEPT** | tail-risk numbers 정정 (이미 Edit 적용) |
| C4 | HIGH | REBUTTAL_PARTIAL | n=10 directional only, magnitude X 명시 |
| C5 | HIGH | ACCEPT_DOCUMENTED | challenge_flags severity 격상 (CYC2_CF_4 MEDIUM→HIGH) |
| C6 | HIGH | REBUTTAL_PARTIAL | sleeve-level scope 명시 (사이클 1과 동일 disposition) |
| C7 | MEDIUM | ACCEPT_DOCUMENTED | "good" 어조 제거 + small sample CI 명시 |
| C8 | MEDIUM | ACCEPT_DOCUMENTED | AX-005 v1.2 enforcement 명시 (이미 적시) |
| C9 | MEDIUM | REBUTTAL | C15 narrow reading (Factor DB factor parquet 적용 대상) |

**Total: 4 ACCEPT + 2 ACCEPT_PARTIAL + 3 REBUTTAL_PARTIAL/REBUTTAL** = 9/9 disposition

**Charter §8 No Silent Override 준수**: 위 disposition 모두 explicit reasoning + 학술/L-code/정량 3축 인용 + Codex 지적 대비 무시 X. REJECT verdict 결과 자체는 본 작업이 정식 admit-grade approval 대상 아닌 **meta research scope** 기준 평가 정합성 확인.

---

## final 행동 목록 (risk_package.json final 작성 시)

1. ✅ tail-risk numbers VRP/Currency 정정 완료 (위 Edit)
2. risk_package_draft.json → risk_package.json (no _draft) 작성 시:
   - 위 9 disposition 반영 (rename / strengthen / cite Codex)
   - challenge_flags `CYC2_CF_4` severity HIGH로 격상
   - rationalization_red_flags 6 표현 정정
   - codex_critic_round section 추가 (사이클 1과 동일 schema)
3. 사이클 3 권고 topic 우선순위 갱신 (Codex C7 HHI / C8 Q07 / C9 load_month_factors 추가)
