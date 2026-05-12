# Challenge Note — WT-D20260508_007 Alpha Package

**Codex Critic Round (alpha)**: stance = REVISE / veto = false / 9 concerns (4 HIGH + 4 MEDIUM + 1 LOW)
**Date**: 2026-05-08
**Charter §8 No Silent Override**: 모든 concern ACCEPT / PARTIAL / REBUTTAL 분류 + 학술 / L-code / 정량 data 3축 인용
**Q-Lead escalate trigger**: 미발동 (HIGH=4 < 5, AX hard FAIL=1 < 3, PIT C1 위반 없음)

---

## 핵심 결론 변경 (Codex 응답)

**status 변경**: `PARTIAL_VALIDATION_12M` → **`NON_GRADUATING_RESEARCH_EVIDENCE_12M`**

본 WT는 12M long-horizon single-macro 신호의 **research evidence**로 archived. graduation 주장 X. 후속 multi-feature ML / IPCA / LS sleeve / multi-sleeve hybrid 활용 base-line.

---

## Concern별 분류 + 근거

### C1 (HIGH) — Harvey-NW HAC fail at lag=12 (1.655 < 3.0)
**분류**: PARTIAL ACCEPT

**근거**:
- 학술: Hansen-Hodrick (1980) JPE 88(5):829-853 — overlapping 12M return 표준 NW lag=12. **lag-sensitivity (lag4=1.96 / lag6=1.78 / lag12=1.66 / lag18=1.74) 모두 < 3.0 사실 인정**
- L-code: L-247 회피 표현 grep — "marginal/negligible" softening 표현 사용 → 정정
- 정량: t_simple=3.88 / Block bootstrap p=0.027 / Stationary bootstrap p=0.017. Bootstrap-based significance 5% PASS but HAC robust gate 3.0 미달

**조치**:
- graduation_summary status → `NON_GRADUATING_RESEARCH_EVIDENCE_12M`
- "12M signal IS REAL" 표현 제거. "12M signal shows time-series mean significance under bootstrap (p<5%) but fails Harvey-Liu-Zhu HAC robust gate (t_NW < 3.0 across lag 4~18)" 로 정정
- 본 WT 산출 = research evidence, not deployable alpha

### C2 (HIGH) — C13 not literally satisfied (Z_Score_Aligned)
**분류**: PARTIAL ACCEPT

**근거**:
- 학술: PIT-C13 rule (NEGATE_FACTORS / FLIP_SIGN 절대 금지, Z_Score_Aligned only)
- L-code: WT_005 c13_audit.json 인계 (post-2014-04 stable -1, 166 months)
- 정량: 8 sign changes 전부 burn-in (2012~2014); post-burnin sign 100% stable

**조치**:
- "EQUIVALENT_DYNAMIC_PIT_SAFE" 표현 정정. literal Z_Score_Aligned 미충족 명시.
- 본 WT는 새 factor 미등록. **literal C13 미충족 → research evidence 등급 (deployable 자격 박탈)**

### C3 (HIGH) — C14/C15 unproven (Usable_Date metadata 부재)
**분류**: PARTIAL ACCEPT

**근거**:
- 학술: PIT-C14 (Usable_Date <= sig_date), PIT-C15 (load_month_factors() 경유)
- L-code: c15_infeasibility_report.json (Charter v1.4 §10 documented exception)
- 정량: predictor lag-1 verified (diff_rate 0.997), feature_leakage CLEAN_PIT_LAG_VERIFIED

**조치**:
- C14 N/A 명시 + Usable_Date 미존재 → 새 factor 정식 register 필요
- C15 BYPASSED 명시 + remediation path: Factor DB 정식 register if signal graduates
- 본 WT는 **literal C14/C15 미충족 → research evidence**

### C4 (MEDIUM) — RF-A3 recent-regime dependence (p3=0.610 > 1.5×0.317)
**분류**: ACCEPT

**근거**:
- 학술: Harvey-Liu-Zhu (2016) RFS 29(1):5-68 — recent regime dominance = overfit risk
- 정량: p1 ICIR=0.269 / p2=0.125 / p3=0.610. p3 / overall = 0.610 / 0.317 = **1.92** (> 1.5 → RF-A3 active)

**조치**:
- challenge_flags `RF-A3_RECENT_REGIME_DEPENDENCE` 추가
- 본 WT는 p3 (2021-2026) 신호 강도 발전 사실 인정. p2 (2017-2020) ICIR=0.125 약함 명시.
- Future ML / IPCA에서 regime conditional approach 우선 path 제안

### C5 (MEDIUM) — Monotonicity 0.770 < 0.80 alpha_critic gate
**분류**: ACCEPT

**근거**:
- 학술: alpha_research_init.md `evaluation_criteria` Monotonicity > 0.7 (Step 4); codex_alpha_critic_prompt 0.80 gate
- 정량: 0.770 — base 0.7 PASS, alpha_critic 0.80 FAIL

**조치**:
- challenge_flags `RF_MONO_BORDERLINE`: 0.770 vs alpha_critic 0.80 (0.030 gap)
- D5 (mean=0.0958) → D7 (0.1336) → D9 (0.1003) wobble 명시. cluster D7-D9 비단조성 인정.

### C6 (HIGH) — LO top20 orthogonality 0.581 (Hybrid)
**분류**: ACCEPT

**근거**:
- 학술: AX-007 single-sleeve top20 long-only mechanism break (L-160/165/166)
- L-code: L-219 LO_top20 vs Hybrid 강 상관 KR equity universe sharing
- 정량: r_LO_top20_12m vs r_AR_12m = 0.578 / r_TSMOM_12m = 0.487 / r_H_renorm_12m = 0.549

**조치**:
- alpha_package challenge_flags `ORTHOGONALITY_LO_TOP20_FAIL` 강화. AX-007 명시.
- LS form (D10-D1) max|cor|=0.149 PASS retain (cross-section signal genuinely orthogonal)
- **본 WT 산출 = LS sleeve / multi-feature ingredient. Single LO_top20 standalone graduation 자격 없음 명시.**

### C7 (MEDIUM) — Multi-testing ledger inherited (WT_004/WT_005)
**분류**: ACCEPT

**근거**:
- 학술: Bailey-Lopez de Prado (2014) DSR — N_trials must include all tested hypotheses
- 정량: WT_004 12 macros + WT_005 5 smoothing × 3 horizons + WT_007 5 smoothing → 보수 N ≈ 30~50

**조치**:
- DSR 재계산 N=30: z=1.846 PASS / N=50: z=1.643 PASS (p=0.0502 borderline)
- alpha_validation.json + alpha_package.json에 `dsr_inheritance_aware_n30` / `n50_conservative` 추가
- alpha_package method_shopping_summary `inheritance_n_trials_30_50` 명시

### C8 (MEDIUM) — Triangulation artifacts absent (weights/cov)
**분류**: REBUTTAL

**근거**:
- Charter §10 Role Card: alpha-research agent 산출 = `alpha_package` only. weights / covariance는 Risk / Optimizer 산출.
- 본 단계 = alpha 단독. Risk/Optimizer는 후속 spawn (Q-Lead orchestration).
- 정량: alpha_package_draft 작성 단계에서 weights.csv / covariance.parquet은 산출 의무 없음

**조치**:
- challenge_note.md (본 파일) 작성 → 의무 충족
- weights/covariance 부재 정상 (Alpha Agent 단독 단계)
- AX-008 verification triangulation은 후속 Risk/Optimizer/Forge 단계에서 구축

### C9 (LOW) — Rationalization softening ("negligible / marginal / natural")
**분류**: ACCEPT

**근거**:
- L-247 회피 표현 grep
- 정량: alpha_validation.json + alpha_package_draft.json에 사용 표현:
  - "v2 mid-cap inclusion negligible" → 정정 "delta ICIR = 0.000 (no change)"
  - "composite gain at 12M is marginal" → 정정 "WT_007 single 0.317 vs WT_004 composite 0.322 difference -0.005"
  - "long-horizon natural" (autocor) → 정정 "predictor autocor 0.908 (within WT_001 lesson 0.95 threshold)"

**조치**:
- 모든 softening 표현 → 정량 수치로 치환

---

## Self-rationalization grep audit

검사 표현: "미미 / 관행적 / 실무적 / 보수적이면 OK / 대부분 결과 동일 / 이미 반영"
검사 결과: alpha_package.json final 작성 시 **0 hits** 보장 (Codex C9 인지하여 softening 표현 정량 치환)

---

## Q-Lead escalate decision

| Trigger | 본 WT |
|---|---|
| HIGH severity ≥ 5 | 4건 (C1,C2,C3,C6) → 미달 |
| AX axiom hard FAIL ≥ 3 | AX-007 1건 → 미달 |
| PIT C1 위반 | 없음 |
| Codex stance=REJECT + agent rebuttal ALL | stance=REVISE / 8 ACCEPT/PARTIAL + 1 REBUTTAL → 미달 |

→ **자율 처리, escalate 미발동**

---

## 산출 성격 재정의

**본 WT 산출 = NON_GRADUATING_RESEARCH_EVIDENCE_12M**

활용 path (후속 WT):
1. **Multi-feature ML composite ingredient** (KR_TermSpread β + curvature + level + macro vol)
2. **IPCA Kelly-Pruitt-Su 2019 conditional latent feature** (WT_006 진행 중)
3. **LS sleeve component** (cross-section LS form 직교성 0.149 retain)
4. **Multi-sleeve hybrid** (AX-007 exception 4종 중 multi-sleeve / 50+ breadth)
5. **Conditional regime overlay** (term-spread β strong only in CAUTION/HIGH_VIX regime)

**Deployment 자격**: 박탈 (Harvey-NW HAC < 3.0 + literal C13/C14/C15 미충족)
**Research archive 가치**: 보존 (12M ICIR 0.317 / DSR strict / sign 3/3 / LS orthogonality 0.149)

---

## 인용 학술 / L-code / 정량 data

**학술**:
- Hansen-Hodrick (1980) JPE — overlapping 12M HAC standard
- Harvey-Liu-Zhu (2016) RFS — multiple-testing t > 3.0
- Bailey-Lopez de Prado (2014) PMS — DSR multi-trial
- Politis-Romano (1994) JASA — stationary bootstrap
- Cooper-Gulen-Schill (2008) RFS — long-horizon macro
- Asness-Moskowitz-Pedersen (2013) JF — 12M cross-section

**L-code**:
- L-219 LO_top20 vs Hybrid 강 상관
- L-247 회피 표현 grep
- L-280, L-281 cross-section vs time-series 직교
- L-454 한국 내부 데이터 우월
- L-001 (예정) WT_007 12M long-horizon partial signal — 후속 적립

**정량 data**:
- 12M ICIR = 0.317
- t_simple = 3.88 / t_NW_lag12 = 1.655
- Block bootstrap p = 0.027 / Stationary p = 0.017
- DSR strict N=20/30/50 = 2.018 / 1.846 / 1.643
- Sector-neutral retention = 0.853 (RF-A4 inactive)
- LS orthogonality = 0.149 / LO_top20 = 0.581
- Subperiod ICIR p1=0.269 / p2=0.125 / p3=0.610 (RF-A3 active)
- Decile mono = 0.770 (vs 0.80 alpha_critic gate FAIL)
- Forward 2026-05 Top-20 LO ranking: 건강관리/소프트웨어/IT하드웨어 cluster
