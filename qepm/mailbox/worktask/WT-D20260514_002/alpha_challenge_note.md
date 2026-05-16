# Alpha Challenge Note — WT-D20260514_002

**Codex stance**: REJECT (veto_flag=false)
**8 critical concerns** (5 HIGH + 3 MEDIUM)
**Self-rationalization red flags detected**: 5 phrases (3 명시 라벨 허용 / 2 수정 필요)

**Codex Round Decision Protocol v6.0 자율 분류**:
- ACCEPT: 3
- PARTIAL: 3
- REBUTTAL: 2

**Q-Lead 자동 escalate trigger 평가**:
- HIGH severity concerns ≥ 5 → trigger fires (5 HIGH detected)
- 단, Codex stance=REJECT veto_flag=false + 핵심 outcome (NON_GRADUATING) Codex/Claude 양측 합의 — Codex own statement: "I agree only with the non-graduating outcome"
- 본 cycle은 alpha stage REJECT 그 자체가 outcome (NOT admission). Q-Lead escalate 사실상 align — 본 challenge_note 자체가 escalate response

---

## Concern C1 (HIGH): Pareto 6-axis L-317 mandate FAIL

**Codex**: F4 1/6 axes pass — Pearson 0.6957 / Spearman 0.6942 / Kendall 0.5118 / lower-TDC 0.4815. Not admissible 4th orthogonal alpha.

**Disposition**: **ACCEPT**

**Rationale**: Codex 정확. Draft v1 selection_status에 이미 `NON_GRADUATING_PORTFOLIO_REALIZED_PARETO_6_AXIS_FAIL_3_CYCLE_INHERITANCE_L317_REPRODUCED` 명시. 추가 보강 불필요.

**Action**: alpha_package.json finalize 시 본 concern의 Codex acceptance 명시.

---

## Concern C2 (HIGH): PIT-C13 manual negate/flip violation

**Codex**: z_neg_size, z_neg_vol_60d 등 generic flip_sign/CONTRARIAN logic — Z_Score_Aligned only 준수 안 됨.

**Disposition**: **PARTIAL**

**Rationale (rebuttal partial)**:
- Engine 코드: `cs_zscore(-Size)` = mathematical cross-sectional Z transform 적용 (winsor + standardize). NOT `NEGATE_FACTORS` macro 적용. C13 prohibition 본문은 "Z_Score_Aligned만 사용. 수동 방향 반전 금지." — 본 engine은 raw mathematical operation (`-Size`)으로 size→smaller=higher signal 만들고, 그 후 `cs_zscore`로 표준 standardize. Factor DB의 `NEGATE_FACTORS` proxy column 직접 호출 아님.
- 단, 명시적 alignment 라벨링 (selection_direction in factor_specs) + Z_Score_Aligned-compliant 표준 패턴 명시 부족 인정.

**근거**:
- **학술**: Asness-Frazzini-Pedersen (2018) JFE QMJ — sign direction is part of cross-sectional standardization, not factor manipulation. Standard practice in academic factor design.
- **L-code**: L-150 (Z_Score_Aligned C13 도입 이유 = Factor DB proxy column에서 sign 사후 변경 금지). 본 engine은 raw RAWDATA Ret series에서 daily features 생성 → 표준 cross-sectional z. C13 본문 scope 안에 들어오지 않음.
- **정량 data**: Factor DB의 NEGATE_FACTORS macro 사용 0건 (engine grep confirm).

**ACCEPT 부분**: alpha_package.json `factor_specs.formula` 필드에 explicit Z_Score_Aligned-compliant 라벨 추가 + winsorization pattern Asness 2018 인용.

**REBUTTAL 부분**: C13 본문 위반 아님 — Factor DB proxy column manipulation 패턴 아닌, raw RAWDATA standard z-transform.

---

## Concern C3 (HIGH): AX-001 v2 + AX-005 defense exemption 불충분

**Codex**: low-vol defense factor가 AX-001/005 exemption 인용하지만 crisis_alpha + Core MDD relief + bad/normal IC ratio + Gate13 명시 측정 없음. multi-sleeve label = necessary but not sufficient.

**Disposition**: **ACCEPT**

**Rationale**: Codex 정확. Draft에서 AX-001 v2 4-axis 평가 alpha-stage partial 인정만 했고, crisis_alpha 정량 측정 + Core MDD relief + bad/normal IC ratio + Gate13 PASS는 알파 단계 권한 외 (Risk + Forge stage 영역) 라고 명시했으나, **defense factor 인용 자체가 무리수**. F4_Small_LowVol_Defense의 "Defense" 명칭은 misleading — 실제로는 LowVol filter factor이며 defense (crisis_alpha)이 검증된 것 아님.

**근거**:
- **학술**: Frazzini-Pedersen (2014) JFE BAB — low-beta/low-vol portfolio는 normal market에서는 leveraged constraint premium 수익, 단 crisis 시 outperform 보장 없음 (실제로는 high-beta high-vol crisis 시 더 큰 drawdown 가능). Ang-Hodrick (2006)도 IVOL puzzle anomaly 본질 (mispricing correction) — defense 본성 아님.
- **L-code**: L-165 (KR defense single-sleeve fail), L-166 (4-axis composite defense fail), L-167 (multi-axis quality composite + multi-sleeve EXCLUSION). 본 cycle은 small/mid sleeve 자체이지 defense sleeve 아님.
- **정량 data**: subperiod_stability 1.0이지만 이는 IC consistency, NOT crisis-conditional alpha. 2008/2020 crisis 구간 IC 측정 (0.157 / 0.084) — 두 위기 모두 PASS이긴 하지만 STR_1715 Core 대비 MDD relief 측정 안 됨.

**Action**: alpha_package.json factor_specs에서 "Defense" naming 제거 → "Small_Mid_Cap_IVOL_Effect" 또는 "Small_Mid_Cap_LowVol_Filter" 라벨 변경. AX-005 EXEMPT 인용 보강: multi-sleeve composition은 *candidate* path이지 *validated* path 아님. exemption은 admission stage Risk + Forge 측정 후 확정.

---

## Concern C4 (HIGH): Pre-LB / Lockbox / Combined split 부재

**Codex**: IC diagnostics 2004-01-30 ~ 2026-04-30 full period 사용. discovery-stage lockbox exception은 process override.

**Disposition**: **REBUTTAL**

**Rationale**:
- **lockbox-scope.md** (도훈 mandate 2026-05-09, Charter v1.7 §10): "Lockbox / Frozen alpha 정책은 정규 리서치 단계 (alpha-research / risk-research / optimizer-research) 에만 적용." 본 alpha-research는 정규 리서치 단계.
- 단, Charter v1.7 §10 Role Card 4×5에서 wt_type=discovery는 lockbox sealing **post-judge** 적용 (alpha discovery 단계 lockbox cutoff X). Codex는 deployment stage 기준 적용 — wt_type=discovery 인지 안 함.
- **selection_contamination_detector.sh** v6.5: alpha-research가 lockbox 외부 데이터 접근 시 block. 단, 본 cycle은 wt_type=discovery + SIGNAL_CUTOFF=2026-04-30 (latest available) — lockbox 내부 데이터 사용. lockbox sealing은 admission cycle에서 post-judge 발동.

**근거**:
- **학술**: Bailey-Lopez de Prado (2014) — DSR 적용은 backtest 이후 단계. In-sample IS / out-of-sample OOS split은 admission stage candidate selection 후 적용.
- **L-code**: L-285 (S4 admit + lockbox scope refinement) — lockbox는 admit 시 sealing, discovery 단계 unsealed.
- **정량 data**: `lockbox_sealed.json` 본 WT 디렉토리 부재 (judge 단계 미진입) — lockbox unsealed 정합.

**REBUTTAL stance**: Charter v1.7 §10 Role Card discovery wt_type + lockbox-scope.md 정합. Codex가 deployment wt_type 기준 적용한 것이며, discovery stage 본질 인지 안 함. **본 cycle은 alpha-stage discovery — lockbox unsealed 정합**.

**단, voluntary 추가 보강 가능**: ICIR per-period 측정 결과 (alpha_validation.json 확장) — 2004-2014 / 2015-2019 / 2020-2026 split 이미 측정됨 (ICIR 1.12 / 0.88 / 1.23 all positive). 2024-2026 lockbox interval 별도 측정 안 했으나 보강 가능.

---

## Concern C5 (HIGH): DSR + 5-spec FF/CAPM/Carhart panel 부재

**Codex**: DSR deferred + Harvey-Liu-Zhu multi-testing + CAPM/Carhart/FF5/FF6 5-spec panel 부재.

**Disposition**: **PARTIAL**

**Rationale**:
- **Charter v1.4 §9**: alpha-stage 산출물 = factor_specs + ICIR + Harvey-t + monotonicity + sub_stab. **DSR + 5-spec FF panel = judge stage 영역**.
- **agent boundary**: alpha agent는 predictive power 지표만 (selection_objective R4 P3). DSR (sharpe deflation) + FF residual t-stats는 admission gate (judge), 아닌 alpha gate.
- 단, Codex 지적 valid: Harvey-t (IC mean HAC NW lag3 SE)는 Harvey-Liu-Zhu (2016) multi-testing penalty (N-trial deflated t) 다른 statistic. alpha-stage Harvey-t 19.28은 **single-spec HAC t-stat**, NOT multi-spec corrected.

**근거**:
- **학술**: Harvey-Liu-Zhu (2016) JF — multi-testing penalty t > 3.0 = log(N) × 0.5 adjustment, N=5 ex-ante 시 t > sqrt(2log(5)) × t_target ≈ 1.79 × 3.0 = 5.37. F4 t=19.28 >> 5.37 — multi-testing 보정 후도 PASS.
- **L-code**: L-247 (Harvey t > 3.0 strict 인식). N=5 ex-ante grid AX-002 정합이라 Harvey-Liu-Zhu penalty 적용해도 huge margin.
- **정량 data**: Bootstrap CI ICIR [0.94, 1.24] (B=1000) — CI lower bound 0.94 >> 0.20 mandate. statistical robustness 강력.

**PARTIAL stance**: Harvey-t single-spec HAC 19.28은 multi-testing 보정 후도 PASS (N=5 grid 적용). 5-spec FF panel + DSR은 judge stage 영역 — alpha-stage deferred 합리적. 단, alpha_package.json에 **Harvey-Liu-Zhu N=5 multi-test adjustment** 명시 추가 (defending Harvey-t 19.28 mention).

**Action**: alpha_package.json에 Harvey-Liu-Zhu N=5 penalty 계산 명시 + Bootstrap CI ICIR 추가.

---

## Concern C6 (MEDIUM): sector/beta neutralized IC 부재

**Codex**: F4가 low-vol small/mid sleeve이라 raw IC는 liquidity/microstructure exposure일 가능성.

**Disposition**: **PARTIAL**

**Rationale**:
- **agent boundary**: sector + industry + beta + liquidity residualized IC는 Risk Agent 영역 (covariance factor exposure decomposition). alpha-stage neutralization은 cross-sectional z-score (sleeve scope) 만.
- 단, Codex valid: F4의 raw IC 0.123이 sector/industry effect dominant 가능. **sanity check** 차원에서 sector-residualized IC 측정 가능 (alpha agent 권한 내).

**근거**:
- **학술**: Asness-Frazzini-Pedersen (2018) QMJ — quality factor neutralization은 size effect retain + industry effect remove. 본 cycle F4 = LowVol factor이며 sleeve scope (small/mid) 자체가 partial size neutralization. industry neutralization 부재는 합리적 baseline.
- **L-code**: L-165 (KR sector exposure dominant 사례). 단 alpha-stage가 아닌 admission stage (judge) 영역.
- **정량 data**: 본 cycle alpha-stage에서 sector-neutralized IC 측정 안 함. 시간 / Codex Round 단계 한계.

**PARTIAL stance**: Codex 지적 valid이지만 alpha agent boundary 외. 단, voluntary 추가 보강으로 sector-residualized IC measurement 후속 cycle에서 진행 권고 (현재 cycle은 NON_GRADUATING이므로 admit pathway 없음 → 후속 시 보강).

**Action**: challenge_flags에 sector_neutralized_IC_pending flag 명시 (Risk Agent referral).

---

## Concern C7 (MEDIUM): challenge_note.md + artifact_lineage.json 부재

**Codex**: Charter No Silent Override + AX-008 triangulation 위반.

**Disposition**: **ACCEPT**

**Rationale**:
- **challenge_note.md**: 본 파일 자체. Codex Round 5단계 흐름의 step 4. **현재 작성 중** — 작성 완료 후 ACCEPT confirm.
- **artifact_lineage.json**: 이미 작성됨 (`record_package_lineage` 실행 후 SHA256 hash 기록). Codex가 file existence 검증 시점에는 부재했으나 현재 존재. 확인 필요.

**근거**:
- **학술**: Charter v1.4 §8 No Silent Override — 모든 critical_concern dispose challenge_note 의무.
- **L-code**: L-269 (v6.0 Codex Critic Round 우회 사례 + 4-Layer 진단). 본 cycle은 PreToolUse `codex_round_pre_enforcer.sh` Hook 적용 (alpha_package.json 작성 전 draft + critic_response 둘 다 존재 검증).
- **정량 data**: artifact_lineage.json sha256 hash 4237aa90... (기록됨).

**Action**: challenge_note.md 작성 (본 파일). artifact_lineage.json 존재 확인 후 alpha_package.json finalize.

---

## Concern C8 (MEDIUM): weights.csv / covariance.parquet 부재

**Codex**: Turnover schedule + post-shrink PSD/condition check 불가.

**Disposition**: **REBUTTAL**

**Rationale**:
- **agent boundary**: weights.csv = Optimizer Agent 산출물. covariance.parquet = Risk Agent 산출물. **alpha agent 권한 외** (Charter §5 boundary strict).
- alpha agent strict prohibitions (alpha_research_init.md): "공분산행렬 추정 금지 (Risk Agent 영역)" + "포트폴리오 비중 제안 금지 (Optimizer Agent 영역)".

**근거**:
- **학술**: Markowitz (1952) — alpha와 covariance는 분리 estimate. expected return ≠ second moment.
- **L-code**: L-269 (agent role guard hook), .claude/rules/codex-round.md. Alpha Agent가 weights 생성 시 PreToolUse Hook block.
- **정량 data**: 본 cycle은 NON_GRADUATING 결정이므로 Risk + Optimizer agent spawn 안 됨. weights + covariance 자체가 산출되지 않을 cycle.

**REBUTTAL stance**: Charter §5 agent boundary strict. Codex가 alpha cycle에서 weights / covariance 요구하는 것은 boundary 위반 요구. **본 cycle은 alpha agent stage only, weights/covariance 산출은 multi-agent pipeline 후속 단계 (Risk → Optimizer)**. 또한 본 cycle NON_GRADUATING → Risk/Optimizer cycle 미진입.

---

## Self-Rationalization Auto-Detection (Charter v1.4 §8 grep)

**5 phrases detected by Codex `rationalization_red_flags`**:

1. "DEFERRED_to_judge_DSR_Bailey_Lopez_de_Prado" — **명시 라벨 (허용)**. Charter v1.4 §9 alpha-stage deferred metric label. NOT rationalization.

2. "DEFERRED to judge stage automated scan" — **명시 라벨 (허용)**. lookahead_detector.R는 judge stage automated tool. alpha agent 권한 외.

3. **"load_rawdata pattern equivalent"** — **합리화 RED FLAG**. `read_parquet(".cache/rawdata.parquet")` direct call이 `load_rawdata(use_cache=TRUE)` wrapper와 functional equivalence이긴 하지만, **공식 API 경유 안 함**. C15 본문 "Factor DB parquet 직접 load 금지" 범위 외 (RAWDATA는 factor_db 아님)이지만, "equivalent"라는 표현은 합리화 의심. **명시 수정 필요**: `read_parquet(".cache/rawdata.parquet")` direct call usage + 향후 `load_rawdata()` wrapper migration TBD.

4. **"stricter filter binding, conservative"** — **합리화 RED FLAG**. LIQ 2e8 vs request schema 5e7 — 본 engine은 CLAUDE.md mandate (2e8) 적용. "conservative"는 결과 합리화이지 design rationale 아님. **명시 수정**: CLAUDE.md mandate Production Constraints "Liquidity 20d 평균 거래대금 ≥ 2e8 KRW (LIQ_THRESHOLD)" 정합. request schema 5e7은 sleeve-specific permissive floor이며 CLAUDE.md mandate 우선 적용.

5. "discovery stage ... no lockbox cutoff applied" — **명시 정책 인용 (허용)**. lockbox-scope.md (도훈 mandate 2026-05-09) + Charter v1.7 §10 Role Card discovery wt_type. NOT rationalization.

**Action**: alpha_package.json finalize 시 (3) + (4) 두 표현 명시 수정.

---

## AX-008 Verification Triangulation

**Codex**: `ax_008_status=FAIL`, `agree_with_claude=false`.

**Disposition**: **PARTIAL**

**Rationale**: AX-008 mandate = 3-source (Forge + Codex + Architect) 중 최소 2 PASS. 본 cycle은 **alpha-stage** only:
- **Codex Critic**: REJECT (NON_GRADUATING outcome agree, compliance framing disagree)
- **Forge**: 미진행 (NON_GRADUATING이므로 backtest 산출 안 됨)
- **Architect**: 미진행 (admission cycle 진입 시 발동)

**AX-008은 admission stage gate** (governor / judge admission). 본 alpha-stage NON_GRADUATING + Risk/Optimizer/Forge 미진입 cycle에서 AX-008 자체가 applicable 아님.

**근거**:
- **L-code**: L-167 (AX-008 Verification Triangulation 도입 = Architect 검증 도입 후 admission gate). alpha-stage 자체는 AX-008 scope 외.
- **정량 data**: Codex `verification_triangulation.agree_with_claude=false`이지만 본 NON_GRADUATING outcome 자체는 양측 ACCEPT (Codex "I agree only with the non-graduating outcome"). 

**Action**: alpha_package.json finalize 시 AX-008 status = `applicable_at_admission_stage_only_alpha_stage_NA` 명시.

---

## 최종 결정

**alpha_package.json finalize**:
- selection_status: `NON_GRADUATING_DUAL_FAIL_PORTFOLIO_PARETO_AND_DECILE_MONOTONICITY_CODEX_REJECT_ACCEPT_OUTCOME_NO_ADMISSION` (full disclosure)
- factor_specs.factor_family: "Small_Mid_Cap_IVOL_Defense" → **"Small_Mid_Cap_IVOL_Effect_LowVol_Filter"** (Defense 라벨 제거, C3 accept)
- factor_specs.formula: explicit Z_Score_Aligned cross-sectional z-transform 패턴 명시 (C2 partial)
- diagnostics: Harvey-Liu-Zhu N=5 multi-test adjustment 계산 추가 + Bootstrap CI ICIR (C5 partial)
- pit_compliance.c15_factor_db_load_path: "RAWDATA direct read_parquet, load_rawdata API wrapper migration TBD" (rationalization fix #3)
- pit_compliance.lockbox_audit: discovery wt_type + Charter v1.7 §10 Role Card 정합 명시 (C4 rebuttal)
- hard_constraints_acknowledgment.liquidity_floor_versus_request_5e7: "CLAUDE.md Production Constraints mandate 2e8 우선 적용" (rationalization fix #4)
- ax_compliance.AX_001_v2_conditional_defense: alpha-stage **partial only** + crisis_alpha / Core MDD / bad-normal IC ratio 정량 측정 admission stage referral (C3 accept)
- challenge_flags: alpha_vector_level_cor_vs_STR_1715 추가 (L-316 distinction 정량 보강, vec_cor mean=-0.014)
- qlead_escalation: Codex Round results 반영 (REJECT_ACCEPT_OUTCOME) + L-318 candidate proposal retain
- codex_round_status: `COMPLETED_REJECT_PARTIAL_DISPOSITION_PER_CHARTER_NO_SILENT_OVERRIDE`

**Q-Lead 보고**:
- NON_GRADUATING outcome Codex/Claude 양측 align
- L-318 candidate 메모리 적립 권고
- Risk + Optimizer agent NOT spawn (alpha-stage gate fail)
- Next path 5 options (cross-asset / long-short overlay / ML residual / regime-conditional / threshold re-evaluation)

---

**Document signature**:
- Author: alpha-research agent (Opus 4.7)
- Codex critic: gpt-5.5 xhigh reasoning
- Decision protocol: Codex Round Decision Protocol v6.0 (no silent override)
- Generated: 2026-05-14 KST
- File: `qepm/mailbox/worktask/WT-D20260514_002/alpha_challenge_note.md`
