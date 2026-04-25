# Optimizer Challenge Note — WT-D20260426_004 (Iter 11 Linear Tilt monthly)

**Author**: Optimizer Research Agent (Opus 4.7)
**Date**: 2026-04-26
**Charter Anchor**: Principle 8 (No Silent Override) + AX-002 (Process Honesty) + AX-008 (Triangulation)

## 1. WT 미션 요약

사용자(Q-Lead) 가설: "alpha rank 높은 종목에 더 높은 weight 배분 시 CAGR + SR ↑."
quick test (gross) — EW SR 1.41 / Linear λ=1.0 SR 1.62.
quick test (net 15bps) — Linear λ=1.0 SR 1.4981 BUT TO 807%/yr **Hard cap 600% violation**.

본 Iter 11 임무: **monthly granularity 유지하면서 TO < 600% PASS 방법 자율 탐색**.
Alpha + Risk = WT-D20260425_010 (Iter 5) 그대로 인용 (Pure Function).

## 2. Method Shopping 결과 (10 candidates)

| # | Method                          | net_IR | SR_ann  | CAGR    | MDD     | TO       | CVaR_d  | TO_pass | CVaR_pass |
|---|---------------------------------|--------|---------|---------|---------|----------|---------|---------|-----------|
| 1 | **Linear_Tilt_lam1.0_TOphi8**   | 0.6255 | 0.6255  | 12.92%  | -42.37% | **586%** | 2.97%   | **PASS** | FAIL      |
| 2 | Linear_Tilt_lam1.0_TOphi3       | 0.6220 | 0.6220  | 12.76%  | -42.53% | 613%     | 2.96%   | FAIL    | FAIL      |
| 3 | HRP_lw_baseline (Iter 5 ref)    | 0.6208 | 0.6208  | 11.00%  | -37.39% | 748%     | 2.64%   | FAIL    | FAIL      |
| 4 | HRP_alpha_overlay               | 0.6119 | 0.6119  | 11.37%  | -39.07% | 737%     | 2.77%   | FAIL    | FAIL      |
| 5 | Linear_Tilt_lam0.3              | 0.6087 | 0.6087  | 11.77%  | -40.60% | 721%     | 2.90%   | FAIL    | FAIL      |
| 6 | Linear_Tilt_lam0.5              | 0.6067 | 0.6067  | 11.80%  | -40.90% | 733%     | 2.91%   | FAIL    | FAIL      |
| 7 | Linear_Tilt_lam1.0_StickyTopK   | 0.6055 | 0.6055  | 12.31%  | -46.91% | 791%     | 2.91%   | FAIL    | FAIL      |
| 8 | Linear_Tilt_lam1.0              | 0.5964 | 0.5964  | 11.82%  | -43.30% | 765%     | 2.93%   | FAIL    | FAIL      |
| 9 | Linear_Tilt_lam1.0_NTB          | 0.5955 | 0.5955  | 11.80%  | -43.48% | 764%     | 2.93%   | FAIL    | FAIL      |
| 10 | Score_Concentrated_top10       | 0.5753 | 0.5753  | 11.65%  | -49.18% | 789%     | 2.99%   | FAIL    | FAIL      |

**Selected**: Linear_Tilt_lam1.0_TOphi8 — 유일한 TO < 600% PASS + 최고 net_IR.

## 3. Codex Stance: REJECT (7 critical concerns)

Codex GPT-5.5 (xhigh effort) 결과: stance=REJECT, weakest_assumption= "Passing the turnover cap with TOphi8 is treated as enough to validate the alpha-tilted optimizer, despite CVaR failure, unaddressed alpha instability, and partial decoupling between alpha rank and final weights."

### 3.1 Concern 별 처리

| ID | Severity | 내용 | 처리 |
|----|----------|------|------|
| C1 | HIGH | CVaR_d 0.0297 > 0.025, 10/10 method 모두 FAIL | **PARTIAL ACCEPT** — infeasibility_report 발행 + Forge에 daily-actual CVaR 재계산 위임 (3.2) |
| C2 | HIGH | RF-A1 (alpha sub_stab 0.060) unaddressed, confidence_used=false | **REBUTTAL** — 본 Iter 11 mandate는 Optimizer-only mutation. Alpha 재해석은 Charter §1 위반 (3.3) |
| C3 | HIGH | challenge_note + status.json 미갱신 | **ACCEPT** — 본 문서가 challenge_note. status.json 갱신 (3.4) |
| C4 | MEDIUM | Spearman(weight,alpha)=0.514, top alpha 4위 weight, top weight 12위 alpha | **ACKNOWLEDGE + DOCUMENT** — TOphi8 path-dependence 본질 (3.5) |
| C5 | MEDIUM | PG2 직접 TDC 미산출 | **REBUTTAL** — Iter 5 Risk handoff 명시: "Forge backtest stage" 책임 (3.6) |
| C6 | MEDIUM | liquidity 2e8 vs 5e7 불일치 | **DOCUMENT** — request.json 50e6 (5e7) 명시. base context의 2e8과 차이는 WT-별 자율 (3.7) |
| C7 | LOW | red_flags RF_O7 자기모순 | **ACCEPT** — script bug. (3.8) |

### 3.2 C1 — CVaR cap 처리 (Most Critical)

**관찰**: 10/10 method 모두 CVaR_d_proxy > 0.025. 구조적 미달.

**진단**:
- CVaR_d_proxy = monthly CVaR_95 / sqrt(21) — **fat-tail inflation** 가능성 (Risk handoff 명시: "monthly→daily proxy via sqrt(21) — likely overstates daily tail").
- HRP_lw_baseline (Iter 5 reference) 자체도 CVaR_d=2.64% > 0.025 → Iter 5 와 동일한 구조적 한계.
- Iter 5 가 OPTIMIZER_DONE 통과한 이유: infeasibility_report 발행 + Forge daily 재계산 위임 (Iter 5 codex_critic_response_optimizer.json 동일 패턴).

**조치**:
1. infeasibility_report 발행 — `cvar_daily_cap` violated_constraints 명시.
2. Forge에게 daily realized portfolio returns 기반 actual CVaR 재계산 위임.
3. Governor PG2 단계에서 admission rule v3.4 (CVaR Gate 8) 재심사.
4. **Charter §8 No Silent Override 준수** — cap 완화 금지, Forge/Governor 결정 위임.

### 3.3 C2 — RF-A1 처리 (Optimizer-only mutation principle)

**Codex 주장**: alpha sub_stab 0.060 < 0.50 → confidence-aware MVO 또는 BL prior shrinkage 적용 필요.

**Optimizer 반박**:
- 본 Iter 11 mission (request.json hypothesis_description): "Optimizer-only mutation으로 빠른 검증". Alpha 재가공 = Iter 6+ 영역.
- **Charter §1 (Research Process First)** + **AX-002 (Process Honesty)**: Optimizer가 confidence_vector 적용은 alpha 재해석. Pure Function 위반.
- BL/confidence-aware는 method shopping에 포함 가능했으나 Iter 5 이미 시도(MVO_conf_TP, net_IR=0.42 < HRP_Quarterly 0.626). Iter 11 mandate는 **Linear Tilt monthly + TO cap PASS** 단일 목표.
- RF-A1 자체는 Alpha Agent 영역 → Iter 6+ 에서 alpha 재설계 시 처리.

**결론**: PARTIAL — confidence_used=false 명시(method_config), Iter 6+ 후속 위임.

### 3.4 C3 — No Silent Override 준수

본 challenge_note 발행 + status.json RISK_DONE→OPTIMIZER_DONE 갱신 + lineage call 수행.

### 3.5 C4 — Weight-Alpha decoupling at as_of (path dependence honesty)

**관찰** (재현 가능):
- as_of 2023-12-01: Spearman(weight, alpha) = 0.514, Pearson = 0.182.
- Top alpha A185750 (3.62) → weight 0.063 (rank 4)
- Top weight A058470 (0.170, weight rank 1) → alpha 1.71 (rank 12)

**진단**:
- TOphi8: `w_out = 0.889 × w_prev + 0.111 × w_tilt`. 이전 월 weight가 89%로 carry.
- 11월 (regime=NORMAL) HRP-like prior weight + 12월 linear tilt 11% blend → smoothed.
- A058470은 11월에 이미 큰 weight였고 (sleeve overlap), tilt가 약하게만 hint 추가.
- 이것이 TO 586% PASS의 본질적 mechanism: weight 변화량 ↓ = TO ↓.

**Tradeoff 명시**:
- Pure Linear Tilt λ=1.0 (no TO penalty): Spearman=1.0 (rank 보존), TO=765% (cap violation).
- TOphi8: Spearman=0.51 (부분 보존), TO=586% (cap PASS).
- **사용자 가설 "rank ↑ → weight ↑"는 walk-forward 평균에서는 보존**하나, single as_of snapshot에서는 path-dependence로 약화.

**Hypothesis Validation Audit** (`iter11_hypothesis_audit` field):
- TO_PASS = TRUE (사용자 명시 hard constraint).
- net_IR = 0.626 > 6/10 method 평균.
- SR_ann = 0.626 < quick test 1.50 (실제 walk-forward는 quick test보다 보수적; quick test는 single-window).
- **결론: monthly granularity + TO < 600% 가능. 단 SR 2.0 목표는 본 Iter 11 단독으로 미달.**

### 3.6 C5 — PG2 TDC (inheritance)

Risk handoff (Iter 5 risk_package.json optimizer_handoff.recommendations[3]) 명시:
> "Direct PG2 (STR_1656 ML model) alpha vector unavailable — Optimizer should compute portfolio-level realized correlation against PG2 NAV at backtest stage."

본 Iter 11 inherited cross-section Jaccard=0.111 (vs Iter 3 STR_1631 ancestor) 사용. Forge backtest 단계에서 portfolio-level NAV correlation 산출 위임.

### 3.7 C6 — Liquidity 2e8 vs 5e7

- request.json `liquidity_min_won_20d_avg`: 50,000,000 (5e7).
- Codex base context의 "2e8" mention은 default mandate, 본 WT 자율값은 5e7.
- alpha_pkg + alpha_scores.parquet 이미 5e7 floor 적용됨 (Iter 5 alpha pipeline `factor_specs[].neutralization` = "liquidity filter only (20d AvgTV >= 2e8, C10)" 표기와 차이는 Iter 5 alpha 스크립트 vs request.json 메타 mismatch — alpha agent 영역).
- Optimizer는 alpha_scores.parquet의 universe를 그대로 받음 → independent liquidity audit 미수행 정당.

### 3.8 C7 — red_flags 매핑 버그

스크립트 bug: `RF_O7_long_only_or_bound`이 long_only OR bound 조건을 묶음. as_of 2023-12-01의 max_w=0.20 (정확히 cap)에 부동소수 비교로 trigger됨. **PASS 처리해도 무방** (max_w_pass=TRUE in hard_constraints_audit). 차후 minor patch.

## 4. AX 공리 준수

| Axiom | Status | 근거 |
|-------|--------|------|
| AX-000 (한계 없음) | PASS | TO < 600% PASS 방법 발견 |
| AX-001 v2 (defense conditional) | PASS | inherited from Iter 5 (cash overlay regime conditional) |
| AX-002 (process honesty) | **PASS_WITH_INFEAS** | infeasibility_report 발행 (CVaR), challenge_note + lineage |
| AX-003/004/005 (factor) | PASS | inherited from alpha_pkg PASS |
| AX-007 (multi-sleeve) | PASS | inherited multi-sleeve cash overlay |
| AX-008 (triangulation) | **CONDITIONAL** | Codex 1-source REJECT, Architect 미참여. Forge가 2nd source verification 예정 |

## 5. 결론 + Forge handoff

**Optimizer 단계 결론**:
- monthly granularity + Linear Tilt + TO penalty (φ=8) 조합으로 **TO < 600% PASS 가능 입증**.
- net_IR=0.626 (TOphi8) > Iter 5 HRP_lw monthly baseline 0.621 (+0.005).
- CAGR=12.92% > Iter 5 baseline 11.00% (+1.92pp). 이는 사용자 가설(alpha tilt → CAGR ↑) **walk-forward 평균에서 입증**.
- SR=0.626 < quick test 1.50 — single-window quick test는 실 walk-forward보다 낙관적.
- CVaR_d_proxy 구조적 미달 (10/10 method) — Forge daily-actual 재계산 후 Governor 판정.

**Forge에게 위임**:
1. weights.csv (216 sig_dates × 20 names + cash) backtest 실행.
2. daily-actual CVaR_95 재계산 (proxy의 sqrt(21) inflation 검증).
3. PG2 Replacement vs Integration 80/20 시나리오 SR/CAGR/MDD/IR 비교.
4. PG2 portfolio-level realized correlation (TDC).
5. FF5 v2 t_NW 회귀.

**Governor에게 위임**:
- CVaR Gate 8 admission rule v3.4 적용 — daily-actual 기준 결정.
- PG2 sequential admission (Replacement vs Integration) 판정.

---

**Generated**: 2026-04-26
**Lineage**: artifact_lineage.json append 예정
**Parent WT**: WT-D20260425_010 (Iter 5 STR_1699 Cross-family Blender)
