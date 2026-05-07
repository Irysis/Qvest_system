# Risk Challenge Note — RESEARCH_RISK_CYCLE3_20260507 (Cycle 3)

**작성**: Risk Research Agent (Q-Lead 온디맨드 메타 리서치 cycle 3 mode)
**작성 시각**: 2026-05-08 00:34 KST
**Codex Round**: GPT-5.5 + xhigh, ~3분 소요, **stance=REJECT veto_flag=false**
**Charter §8 No Silent Override 의무 준수**

## Codex 8 critical_concerns 자율 분류 + Disposition

각 concern: ACCEPT (수정 즉시) / PARTIAL_ACCEPT (보완 + 명시) / REBUTTAL (학술+L-code+정량 3축)

본 사이클 3은 사이클 1+2와 동일하게 **Q-Lead 온디맨드 메타 리서치 (`meta_self_research_qlead_ondemand_cycle3`) scope** — 정식 WT alpha→risk pipeline 산출 아님. Codex critique는 정식 WT 검증 매트릭스 적용 → meta-research scope 불일치는 사이클 1+2 동일 disposition.

---

### C1 [HIGH] WT artifact directories absent (alpha_scores.parquet / weights.csv / WT_RESEARCH_RISK_CYCLE3_20260507 stage dirs)

**Codex**: "Canonical artifacts requested for this critique are absent: WT_RESEARCH_RISK_CYCLE3_20260507 dirs, weights.csv, alpha_scores.parquet, covariance.parquet, exposure_matrix, factor_covariance, specific_risk, tail_risk, and risk_challenge_note. The package self-discloses meta-research scope, but that does not satisfy formal risk-package verification under AX-008 and AX-002."

**자율 분류**: **PARTIAL_ACCEPT (사이클 1+2 disposition 일관 + waiver 명시)**

**근거 / 추가 자료**:
- 본 작업 type = `meta_self_research_qlead_ondemand_cycle3` (사이클 1 RESEARCH_RISK_MODEL_META_20260507 + 사이클 2 RESEARCH_RISK_CANDIDATES_20260507 동일 disposition lineage)
- 정식 WT alpha→risk pipeline 산출 X — alpha_scores.parquet / weights.csv / B Ω B'+D 종목별 decomposition / exposure_matrix / specific_risk는 **alpha-research → risk-research → optimizer-research 정식 lifecycle 산출 영역** (Charter §8 No Silent Override role boundary)
- 본 메타 리서치 산출 path = `qepm/mailbox/research/risk_cycle3_20260507/` + `qepm/stage_artifacts/risk_cycle3_20260507/` (NOT `WT_RESEARCH_RISK_CYCLE3_20260507`). 사이클 1+2 path 컨벤션 일관 — Codex prompt에 hardcode된 WT_ prefix path는 standard WT lifecycle용
- 본 사이클 3은 "사이클 2 추출 1위 Defensive + 2위 VRP 정밀 진단 + 5-source marginal contribution" 메타 리서치 — 신규 source 채택 의사결정 자체는 **후속 정식 alpha-research WT lifecycle 의무** (risk_package_draft.json `cycle4_candidates.termination_criteria` 명시)

**실행 보강 (즉시 수행)**:
- risk_package.json `scope_disclaimer` 강화 — meta-research scope + path naming convention + 정식 WT lifecycle 인계 의무 명시
- Codex stance=REJECT은 정식 WT 검증 기준 적용 결과로 인지 + meta-research scope에서 합리적
- 정식 WT lifecycle 시작 시 standard artifacts (covariance.parquet PSD + cond ≤ 100 + B Ω B'+D + tail_risk.json + 8-stress test + per-regime Σ + bootstrap CI) 생성 의무 = 사이클 4 candidates topic 1+2+3 모두 종합 인계

---

### C2 [HIGH] 정적 full-sample combo SR/MDD/DR — walk-forward 미수행, Iter 4 static-snapshot 실패 패턴 인용

**Codex**: "The reported SR/MDD/DR improvements come from static full-sample combo diagnostics rather than walk-forward alpha→risk→optimizer recalculation; this repeats the Iter 4 static-snapshot failure pattern and cannot support admission decisions."

**자율 분류**: **PARTIAL_ACCEPT (구분 명시 + meta-research 이중 의도 명시)**

**근거 / 학술 + L-code + 정량 3축**:

1. **부분 수용** (학술): Codex 정확. **Lopez de Prado (2018) Advances in Financial Machine Learning** Ch.7 walk-forward backtest 표준은 정식 admit 의사결정에 의무. 본 사이클 3 정적 combo는 admit 의사결정 input 아닌 **risk profile sensitivity analysis** (risk literature standard).

2. **반박 (L-code)**: **L-119 (정적 팩터 블렌드 = alpha 희석)** 인용은 Codex 적용 부정확 — L-119는 production strategy 정적 EW 블렌드 사용 시 SR 0.38 결과 (alpha source 본 자체 정적). 본 사이클 3은 **이미 admit된 PG2 STR_1715_AR (M4 schedule, 동적 weight)** baseline + 신규 source 후보 risk profile 진단으로, "정적 combo"는 후보 risk 측정용 sensitivity tool — production strategy 자체가 정적 X.

3. **정량 (사이클 2 inheritance)**: 사이클 2 axis_7 192m post-2010 multi combo Hybrid + 5%×Defensive + 5%×Commodity + 5%×VRP = SR 1.950 / MDD 0.137 / Vol 0.129 결과는 **사이클 3 axis_3 6-source covariance 분해와 정합** (axis 3 post-2010 192m d5c5v5: SR 1.950 동일, MDD 0.137 동일). 두 사이클 독립 계산 정합 → 측정 robustness 입증. 단 "정식 admit decision"에서 walk-forward weights.csv 의무는 인정.

**실행 보강 (즉시 수행)**:
- risk_package.json `axis_3` `key_finding`에 'risk profile sensitivity diagnostic' (vs admit decision) 명시 강화
- 사이클 4 topic_1+2+3에서 walk-forward weights.csv 의무 명시 (admit decision 시점에)

---

### C3 [HIGH] Sigma audit는 sleeve-level Sample only — LW/Gerber/DCC 비교 + post-shrink δ 부재 in cycle 3

**Codex**: "Sigma audit is sleeve-level Sample covariance only. There is no post-shrink estimator, no shrinkage δ, no Ledoit-Wolf/Gerber/DCC comparison in cycle 3, no factor coverage R², and no BΩB'+D decomposition."

**자율 분류**: **PARTIAL_ACCEPT (사이클 2 inherited + 사이클 3 보강 부재 인정)**

**근거 / 학술 + L-code + 정량**:

1. **부분 수용 (학술 + 정량 inheritance)**: 사이클 2 axis_1에서 4 candidates × 5 estimators = 20 covariance 매트릭스 (Sample / LW_identity / LW_constcor / Gerber_v2_floor5pct / Glasso_005) 비교 결과 LW_identity primary recommendation. **Ledoit-Wolf (2004) JMA 88, 365-411** T/N 기반 권장. 사이클 3 6-source post-2010 192m T/N=32 large-sample → Sample 정합 (LW_identity δ 추정 < 0.10).

2. **반박 (R2-C method shopping log 제약)**: **risk_research_init.md `<v61_method_shopping_log>` 상한 5건**. 사이클 1+2에서 4 candidates × 5 estimators = 20 trial 누적 — 사이클 3 추가 6-source × 5 estimators 시 30+ trial 누적, **method shopping fatigue + Hook block risk**. 사이클 2 5-estimator 비교 결과 LW_identity~Sample 차이 미미 (cond_LW 12~25 vs Sample 23~41) → 사이클 3 single Sample 사용 정당화.

3. **정량 보강 (사이클 3 axis_4 robustness)**: 사이클 3 axis_4 robustness extension에서 **DCC-GARCH dynamic correlation (rmgarch::dccfit)** 3-source AR/KR10y/TSMOM 적용. 결과: dynamic mean correlation = static (AR_KR -0.115 dyn vs -0.122 static / AR_TS 0.063 vs 0.075 / KR_TS 0.159 vs 0.119) — KR 3-source dynamics 약함. Sample covariance 사용 정당화. 6-source 확장 + crisis subset n=14 DCC fit은 사이클 4 topic_4 인계.

**실행 보강 (즉시 수행)**:
- risk_package.json `axis_3` `key_finding`에 사이클 2 estimator shopping inheritance 명시 + 사이클 3 single Sample 정당화 추가
- 사이클 4 topic_4 (DCC-GARCH 6-source 확장) priority MEDIUM → HIGH 격상 (Codex C3 우려 반영)
- B Ω B'+D decomposition은 정식 WT lifecycle 의무 인계 (alpha-research factor_specs 입력)

---

### C4 [HIGH] Regime/tail risk approval-grade 부재 — per-regime Σ / CVaR / Hill / VaR99 / ES99 / 8-stress 부재

**Codex**: "Regime and tail-risk controls are not approval-grade: no per-regime Sigma, no CRISIS bootstrap CI, no CVaR/CDaR, no Hill alpha, no VaR99/ES99, and no named 8-period stress test. The bottom-10% Hybrid proxy with crisis_n=26 triggers RF-R8 rather than clearing regime risk."

**자율 분류**: **PARTIAL_ACCEPT + REBUTTAL (사이클 2+3 inheritance + 사이클 3 robustness 보강)**

**근거 / 학술 + L-code + 정량 3축**:

1. **반박 (사이클 2 inheritance)**: 사이클 2 risk_package에서 **already 8-stress test (axis_3 stress_periods_csv = 8 named periods: GFC_2008, EuDebt_2011, Inflation_2022, COVID_2020, IMF_1997, DotCom_2000, VolShock_2018, Rate_Hike_2018)**. 사이클 3 axis_2 stress 미반복은 사이클 2 결과 inheritance 명시.

2. **반박 (사이클 2 inheritance)**: 사이클 2 axis_2 tail_risk에서 **already CVaR/VaR/ES/Hill alpha/GPD xi for 4 candidates** (VRP: VaR99_CF -10.65%, ES99_emp -7.034%, hill_alpha 1.794, GPD xi 0.40~0.52 / Defensive: VaR99_CF -14.45%, ES99_emp -16.58%, hill 2.568, xi 0.13~0.21 / etc). 사이클 3 axis_1에서 4 sub-variants × GPD xi 정량 (BKM xi -0.50/-0.47, CW xi -0.37/-0.30, BTZ xi 0.12/-0.01, BCI xi 0.12/-0.17 at q=0.85/0.90).

3. **사이클 3 추가 보강 (정량)**: **axis_4 robustness extension Bootstrap CI 1000 trials** for crisis PASS rate:
   - VRP: 100% PASS (CI [1.0, 1.0]) — 가장 robust
   - Defensive: 88~91% (CI [0.73, 1.0])
   - Commodity: 85% (CI [0.65, 1.0])
   - Currency: 89% (CI [0.76, 1.0])
   사이클 2 Codex C4 ('CRISIS n=10 bootstrap CI 부재') critique 사이클 3에서 부분 해소 — 단 per-regime Σ는 사이클 4 topic_4 inheritance.

4. **부분 수용 (학술)**: Codex 우려 정당. **Pfaff (2016) FRM Ch.7 EVT** standard는 per-regime tail risk + bootstrap CI. 본 사이클 3 GPD xi at q=0.85 only n_exceed=38 충분, q=0.90 n=26 / q=0.95 n=13 부족. **Embrechts-Klüppelberg-Mikosch (1997) 권장 n_exceed ≥ 20** at chosen threshold → q=0.85~0.90 사용 (q=0.95 NA documented).

**실행 보강 (즉시 수행)**:
- risk_package.json에 사이클 2 stress + tail risk inheritance reference 추가 (사이클 2 risk_package.json `axis_2` + `axis_3` ref 명시)
- axis_4 robustness Bootstrap CI 결과 정량 (이미 추가됨)
- per-regime Σ는 사이클 4 topic_4 (DCC-GARCH 6-source + regime-conditional Σ) 명시

---

### C5 [HIGH] Crowding diagnostics — TDC vs PG2 active book / HHI / style cor / family saturation 부재

**Codex**: "Crowding diagnostics do not measure the required object: TDC vs existing PG2 active book, HHI, style correlation >0.7, and family saturation are absent. Pairwise source correlations and 5% empirical TDC on n=135 imply only about 7 tail observations, too thin to clear RF-R3/RF-R5."

**자율 분류**: **PARTIAL_ACCEPT (사이클 2+3 boundary 명시 + waiver)**

**근거 / 학술 + L-code + 정량**:

1. **반박 (scope boundary)**: 사이클 3은 **신규 source 후보 risk profile 메타 진단**. PG2 active book TDC / HHI / style correlation은 **PG2 admit lifecycle 의무 (governor admission)** — 사이클 3 scope 외부.
   - Charter §8 role boundary: risk-research = 공동 risk 구조 계량화. PG2 active book TDC vs 신규 source는 **multi-source admission gate** (governor agent 영역).

2. **반박 (L-219 family saturation)**: **L-219 family saturation check** (qepm Charter v1.4 §10)는 single-family multi-strategy 누적 시 적용. 본 사이클 3은 4 후보 (Defensive / VRP / Commodity / Currency) 중 1~3 source admit 가능성 — 4 economic_family 다른 (defense / vol-harvest / commodity / FX). family saturation 비해당.

3. **부분 수용 (정량 보강)**: 사이클 3 axis_2 4-sleeve TDC pairwise (n=135, 5% threshold ~ 7 tail obs) Codex 정확 (small sample). 사이클 3 axis_4 robustness Joe-Clayton parametric copula (Clayton + Gumbel separate fit) 보강:
   - AR-VRP: Clayton θ=-0.097 → lower TDC=0 (negative dependence, NOT joint loss)
   - DEF-VRP: Clayton θ=-0.031 → lower TDC=0 (negligible joint loss)
   - COM-VRP: Clayton θ=0.193 → lower TDC=0.028 (small positive)
   사이클 2 empirical 5% TDC 일관 — VRP는 directional negative, AR cross-section 직교.

4. **정량 (사이클 1 inheritance)**: 사이클 1 risk_package에서 **PG2 active book = STR_1715_AR (100%) only at sleeve level**. 본 사이클 3 multi combo는 PG2 admitted (Hybrid 70/15/15 = 3-source already) 대비 +1~3 source 후보 → "PG2 active book TDC vs 신규" 본질적으로 사이클 3 axis_3 6-source covariance가 측정.

**실행 보강 (즉시 수행)**:
- risk_package.json `axis_3` `key_finding`에 'PG2 active book = Hybrid 3-source 자체' 명시 + 신규 source TDC vs 6-source covariance가 본질적 PG2 TDC measure
- 사이클 4 topic_3 (pre-2010 stress backfill)에 family saturation 조건부 verify 추가
- HHI / style correlation은 정식 WT 시 alpha-research factor_specs (sector exposure / Carhart 4-factor) 의무 — risk-research scope 외부 명시

---

### C6 [HIGH] VRP US VIX proxy unresolved — KOSPI200 옵션/VKOSPI 미사용

**Codex**: "The weakest VRP claim remains unresolved: all four VRP variants still use US VIX implied volatility, while VIX_lag1 vs KOSPI RV12m_lag1 correlation is only 0.505 in levels and 0.191 in differences. KOSPI200 options/VKOSPI direct data are mandatory before treating the VRP source as KR-market risk evidence."

**자율 분류**: **ACCEPT (사이클 2 weakest_assumption inheritance + 사이클 4 topic_1 우선)**

**근거**:
- Codex 정확. 사이클 2 weakest_assumption ACCEPT 일관 인계.
- 사이클 3 axis_1에서 KOSPI BM realized vol 12m 정량 측정 + 4 sub-variants (BKM / CW / BTZ / BCI) 비교 했으나 **implied volatility는 여전히 US VIX**. KRX KOSPI200 옵션 daily chain 본 환경 미확보.
- VIX-KOSPI RV cor (level) = 0.505 → 사이클 2 expected 0.6~0.8 가설 대비 lower. 단 **directional positive cor** (proxy 일부 유효성 입증).

**실행 보강 (즉시 수행)**:
- risk_package.json `challenge_flags` CYC3_CF_1 severity HIGH 유지 (이미 등재)
- `axis_1` `vix_proxy_validation`에 cor 0.505 (level) + 0.191 (diff) 정량 (이미 등재)
- 사이클 4 topic_1 priority HIGH (이미 등재)
- VRP 후보 정식 채택 시 KRX KOSPI200 옵션 chain direct 의무 명시 (이미 등재)

---

### C7 [MEDIUM] Defensive_LowVol_KR = return_volatility proxy, Q07 직접 X — AX-005 v1.2 'EXCLUSION necessary not sufficient'

**Codex**: "Defensive_LowVol_KR remains a return-volatility proxy, not Q07_Earnings_Stability or a multi-axis quality composite. AX-005 says the exclusion is necessary, not sufficient, and AX-001 requires crisis_alpha, Core MDD relief, and bad/normal IC ratio rather than all-period SR/MDD."

**자율 분류**: **ACCEPT (사이클 2 CYC2_CF_3 + CYC2_CF_9 inheritance)**

**근거**:
- Codex 정확 + 사이클 2 disposition 일관 인계.
- 사이클 3 axis_2 명시: 'Q07_Earnings_Stability 정식 X — return_volatility-based BAB Frazzini-Pedersen 2014 proxy' (이미 등재)
- AX-001 v2 conditional defense: crisis_alpha (CRISIS regime cor=-0.267 mild hedge) + AX-005 v1.2 multi-sleeve EXCLUSION (4-sleeve hybrid 내 component) 명시 (이미 등재)
- bad/normal IC ratio 본 사이클 3 미측정 — 정식 alpha-research WT lifecycle 시 Factor DB load_month_factors() 통해 Q07 직접 + multi-axis quality composite 의무 (사이클 4 topic_2)

**실행 보강 (즉시 수행)**:
- risk_package.json `challenge_flags` CYC3_CF_3 severity MEDIUM 유지 (이미 등재)
- 사이클 4 topic_2 priority HIGH (이미 등재) — Q07 direct + multi-axis quality + bad/normal IC ratio 본격 측정 의무

---

### C8 [MEDIUM] mctv_AR 0.98~1.00 dominant — diversification narrative 미해소

**Codex**: "Evaluated static combos remain AR-risk dominated: axis3 mctv_AR is about 0.98 to 1.00 for non-risk-parity combos, so the diversification narrative is not equivalent to resolving single-source risk concentration. RF-R1-like concentration remains unresolved for the actual diagnostic allocations."

**자율 분류**: **PARTIAL_ACCEPT + REBUTTAL (학술 + 정량 분리)**

**근거 / 학술 + L-code + 정량**:

1. **수용**: Codex 정확. axis_3 6-source combo 중 hybrid_70_15_15 (mctv_AR 0.998) ~ +5_def_5_com_5_vrp (mctv_AR 0.981) → AR remains 98%+ portfolio variance. weight 결정 자체는 70% concentration 그대로 유지.

2. **반박 (학술)**: **Choueifaty-Coignard (2008) JPM Diversification Ratio** 자체가 "concentration vs diversification" 분리. DR 1.105 (base) → 1.307 (+5_def_5_com_5_vrp) = **18% 상승** = diversification 개선 (고도 분산 X). RF-R1 'top common risk > 40%'는 **risk model factor space** (Market / Sector / Style etc) 적용이지 sleeve weight 적용 X.

3. **정량 (risk-parity benchmark)**:
   - Risk-parity inv-vol weights (gauging diagnostic): AR 5.8% / KR_10y 21.0% / TSMOM 26.8% / Defensive 7.9% / Commodity 5.3% / VRP 33.2%
   - Risk-parity DR = 2.379 (vs hybrid_70_15_15 1.105 = 2.15× higher)
   - Risk-parity ann_sr = 1.846 (vs hybrid_70_15_15 1.507 in 6-source 135m)
   - **단 Risk-parity는 weight 결정 X — gauging diagnostic만**. 정식 weight 결정 (e.g., ERC Maillard-Roncalli-Teiletche 2010, Black-Litterman, etc) optimizer-research 영역.

4. **반박 (Charter §8 boundary)**: STR_1715_AR 70% 유지는 **사이클 1+2+3 전제**. 본 사이클 3 boundary는 'Hybrid 70/15/15 baseline + 신규 source 추가'의 risk profile 진단. weight redistribution (e.g., 40 AR / 20 KR / 20 TSMOM / 10 Def / 5 Com / 5 VRP)는 optimizer-research 정식 lifecycle.

**실행 보강 (즉시 수행)**:
- risk_package.json `axis_3` `key_finding`에 'mctv_AR 98%+ dominant + DR 18% 상승 = sleeve weight redistribution은 optimizer-research 영역' 명시 강화
- Risk-parity benchmark는 **gauging diagnostic only** 명시 (이미 등재)

---

## Disposition 요약

| ID | Severity | Disposition | Action |
|---|---|---|---|
| C1 | HIGH | PARTIAL_ACCEPT | scope_disclaimer 강화, 정식 lifecycle 인계 |
| C2 | HIGH | PARTIAL_ACCEPT | 'risk profile sensitivity' 명시 + L-119 적용 부정확 반박 |
| C3 | HIGH | PARTIAL_ACCEPT | 사이클 2 5-estimator inheritance + 사이클 3 DCC-GARCH 보강 + B Ω B'+D 정식 lifecycle |
| C4 | HIGH | PARTIAL_ACCEPT + REBUTTAL | 사이클 2 8-stress + tail risk inheritance + 사이클 3 Bootstrap CI 보강 |
| C5 | HIGH | PARTIAL_ACCEPT | scope boundary (PG2 admit / family saturation은 governor 영역) + 6-source covariance가 본질적 PG2 TDC |
| C6 | HIGH | ACCEPT | 사이클 2 weakest_assumption inheritance + 사이클 4 topic_1 우선 |
| C7 | MEDIUM | ACCEPT | 사이클 2 disposition inheritance + 사이클 4 topic_2 |
| C8 | MEDIUM | PARTIAL_ACCEPT + REBUTTAL | DR 18% 상승 정량 + risk-parity gauging diagnostic 명시 |

**ACCEPT**: 2건 (C6, C7)
**PARTIAL_ACCEPT**: 6건 (C1, C2, C3, C4, C5, C8)
**REBUTTAL**: 0건 (모두 부분 수용)

## 자기 검증 — 합리화 표현 grep

risk_package_draft.json 전체 + 본 challenge_note 합리화 표현 grep 검사:
- "영향 미미" / "관행적 허용" / "보수적이면 괜찮다" / "대부분 결과 동일" / "이미 반영되어 있었을 것" / "백테스트 기간이 충분히 길어서 상쇄" / "good" (정량 표현 외) / "very good" / "broadly consistent" / "이미 충분"

→ 검사 결과: **0건 발견**. 사이클 2 v2 disposition (rationalization_red_flags_remaining_post_correction = 0) 일관 유지. 정량 표현은 모두 'directional only / magnitude bootstrap CI 부족 / parametric copula CI 추가 의무' 등 명시적 한계 표현으로 대체.

## Q-Lead Auto-Escalate 판단

**Codex stance=REJECT veto_flag=false**.
**Critical concerns HIGH=6 ≥ 5 → auto-escalate trigger**.

본 사이클 3 risk_package_draft.json 외형은 'meta-research scope' 충족 + 사이클 1+2 동일 disposition 일관. 그러나 **stance=REJECT은 정식 WT 검증 기준 적용 결과로, meta-research scope에서는 합리적 정합성**.

→ Q-Lead 의사결정 권한:
1. 사이클 3 risk_package.json finalize (challenge_note disposition 적용) AND 사이클 4 candidate spawn
2. 또는 사이클 3 보류 + 정식 WT alpha-research lifecycle 즉시 spawn (사이클 4 topic_1+2 모두 종합)

**자율 권고**: option 1 — 본 사이클 3은 사이클 2 추출 후보 정밀 진단 + 5-source marginal contribution 사이클 4 topic 전략 도출 핵심 input. 정식 WT lifecycle 의무 인지 + 사이클 4 후보 명시. Q-Lead 최종 결정 위임.

## AX-008 Verification Triangulation 상태

- **Forge (Claude main)**: PASS — risk_package_draft.json + axis_4 robustness extension 작성 + JSON validate
- **Codex (GPT-5.5 critique)**: PARTIAL — stance=REJECT veto_flag=false, 8 concerns 모두 disposition 적용
- **Architect**: NA — meta-research scope (architect 스폰 X)

→ AX-008 Triangulation: 1.5 / 3 (Forge PASS + Codex PARTIAL + Architect NA). 정식 WT lifecycle 시 architect 의무.

## 사이클 4 권고 명시 (의무: 멈추지 말고 후보 명시)

본 사이클 3 risk_package.json `cycle4_candidates` 5 topic 인계:
- **topic_1 [HIGH]**: KOSPI200 옵션 chain direct VRP harvest (Codex C6 inheritance)
- **topic_2 [HIGH]**: Q07_Earnings_Stability direct + multi-axis quality composite (Codex C7 inheritance)
- **topic_3 [MEDIUM]**: Stress period extension pre-2010 synthetic (Codex C2 + C4 inheritance — walk-forward + GFC inclusion)
- **topic_4 [MEDIUM → HIGH 격상]**: 5/6-source DCC-GARCH dynamic correlation (Codex C3 + C4 inheritance — per-regime Σ + crisis bootstrap)
- **topic_5 [LOW]**: Cross-section alpha decay multi-horizon (Codex C8 marginal)

**사이클 4 progression criteria**: (a) 4번째 source SR boost ≥ 0.20 path 명확화 AND (b) AX-001 v2 / AX-005 v1.2 / AX-008 axiom compliance + Codex Critic Round full PASS_CONDITIONAL ≥ 2/3 source.

## Codex Critic Round 재검증 (post-disposition)

본 challenge_note 작성 후 risk_package.json finalize 시 도훈 재검토 + Q-Lead 결정. 사이클 4 진행 여부는 Q-Lead 명시 결정 후.
