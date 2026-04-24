# Weight Method Selection Report
## WT-D20260424_011 — STR_1631_MEGA_02 (Phase 2: Risk Control)
### 작성: Optimizer Research Agent v1.2 | 2026-04-25

---

## 1. 선택 방법론

**Selected: MinCVaR_Score_0.3**

- 구성: 0.70 × MinCVaR(CRISIS-Σ) + 0.30 × Alpha Score
- net_IR: 21.6310 (MEGA_01 baseline 21.0151 대비 +0.6159 개선)
- 선택 기준: `net_ir` (R4 P3 selection_objective)
- Regime-Σ 활용: CRISIS-Σ (현재 국면 MRS 63.1 = CRISIS)

---

## 2. Sprint 목표 vs 방법론 선택 근거

| Sprint 목표 | 현황 | 선택 방법론 기여 |
|-------------|------|-----------------|
| MDD ≤ 30% | -44.31% | MinCVaR로 portfolio vol ↓, CVaR_95 실현 0.0171 (cap 0.025 MET) |
| FF5 Harvey t ≥ 3.0 | 1.838 FAIL | MinVar 구조로 Market factor 기여 완화 → FF5 residual 발현 여지 |
| NORMAL SR ≥ 0.6 | 0.30 | NORMAL-Σ snapshot net_ir=17.52 (regime switching 설계 반영) |

---

## 3. R13 Parallel Method Comparison (10 candidates, 5 workers, 0.9초)

| Rank | Method | net_IR | CVaR_95 | CVaR cap 충족 | 선택 |
|------|--------|--------|---------|--------------|------|
| 1 | **MinCVaR_Score_0.3** | **21.6310** | **0.0171** | **YES** | **YES** |
| 2 | Kelly_frac_0.3 | 21.0491 | 0.0182 | YES | — |
| 3 | HRP_0.4_Score_0.6_baseline | 21.0151 | 0.0278 | NO | — |
| 4 | HRP_0.4_Score_0.6_RegNormal | 20.9969 | 0.0278 | NO | — |
| 5 | HRP_0.4_Score_0.6_CVaR | 20.9738 | 0.0280 | NO | — |
| 6 | HRP_0.4_Score_0.6_CVaR_RegNormal | 20.8631 | 0.0285 | NO | — |
| 7 | HRP_0.4_Score_0.6_CVaR_RegCrisis | 20.4338 | 0.0310 | NO | — |
| 8 | MVO_conf_full | 17.0845 | 0.0285 | NO | — |
| 9 | MVO_conf_RegNormal | 17.0845 | 0.0285 | NO | — |
| 10 | ERC_full | 14.2636 | 0.0191 | YES | — |

**선택 이유**: net_ir 최대 (21.63) + CVaR cap 충족 (0.0171 < 0.025) 동시 달성.
MEGA_01 baseline (HRP_0.4_Score_0.6) net_ir=21.02 대비 +2.9% 개선.
HRP 계열이 CVaR cap을 초과(0.027~0.031)하는 반면 MinCVaR는 CRISIS-Σ 기반으로 꼬리 위험 직접 제어.

---

## 4. 방법론 상세

### MinCVaR_Score_0.3
- **이론**: Rockafellar-Uryasev (2000) — CVaR 최소화를 통한 꼬리 위험 직접 제어
- **구현**: QP solve.QP() on CRISIS-Σ (cond=19.3, 현재 국면 최적 추정기)
  - MinVar (Gaussian CVaR proxy): 0.70 weight
  - Alpha Score blend: 0.30 weight (confidence-scaled α̃ = c_i × α̂_i)
- **Winsor**: 3σ 적용 (1개 클리핑)
- **HHI**: 0.0951 (cap 0.15 이내)
- **Beta**: α confidence HIGH tier [1.00, 1.05] 유지

### CVaR 개선 경로 (Rockafellar-Uryasev 2000)
- MEGA_01 CVaR_95 = 3.55%/day (Risk agent 측정)
- MEGA_02 선택 후 CVaR_95 = 1.71%/day (51.8% 감소)
- Cap 2.50% 대비 29% 여유 확보

---

## 5. Regime-Conditional Σ 분석

Risk package의 4구간 Regime-Σ를 실제로 활용한 결과:

| Regime | CVaR_95 | net_IR | HRP 비중 | Score 비중 |
|--------|---------|--------|---------|-----------|
| BULL | 0.0345 | 16.85 | 40% | 60% |
| NORMAL | 0.0333 | 17.52 | 40% | 60% |
| CAUTION | 0.0327 | 18.80 | 50% | 50% |
| CRISIS | 0.0364 | 17.24 | 60% | 40% |

- NORMAL 구간: Style loading 개선을 위해 HRP 40% + Score 60% 유지 (risk_package 권고)
- CRISIS 구간: 방어 강화 HRP 60% + Score 40%, CVaR 2.0% cap 활성화 (risk_package 권고)
- **현재 국면 CRISIS**: MinCVaR가 CRISIS-Σ 기반으로 꼬리 직접 제어 → 가장 효과적

---

## 6. 최종 포트폴리오 (Discovery WT — 12종목 COV 유니버스)

| Ticker | Weight | Alpha Score |
|--------|--------|------------|
| A005930 | 11.86% | 0.5094 |
| A161890 | 11.79% | 0.5001 |
| A071320 | 11.74% | 0.4944 |
| A071970 | 10.95% | 3.1334 |
| A010950 | 10.61% | 0.7121 |
| A002380 | 9.15% | 0.4779 |
| A073240 | 8.46% | 1.2882 |
| A000120 | 7.23% | 0.4779 |
| A021240 | 6.94% | 0.5176 |
| A042660 | 4.91% | 0.7961 |
| A000660 | 3.99% | 0.7254 |
| A041510 | 2.37% | 0.5681 |

- **n_names**: 12 (Discovery WT COV 유니버스 12종목 — Deployment 확장 시 20종 필요)
- **Σw**: 1.000000 (정확)
- **max_w**: 11.86% (≤15% OK)
- **HHI**: 0.0951 (≤0.15 OK)
- **Long-only**: 전 종목 ≥ 0

---

## 7. Constraint Satisfaction

| 제약 | 기준 | 실현값 | 충족 |
|------|------|-------|------|
| max_names | ≤ 20 | 12 (Discovery COV) | OK |
| weight_bounds | [0, 0.15] | [0, 0.1186] | OK |
| sum_weights | = 1 | 1.000000 | OK |
| long_only | ≥ 0 | min = 0.0237 | OK |
| hhi_cap | ≤ 0.15 | 0.0951 | OK |
| CVaR_95 cap | ≤ 2.5% | 1.71% | OK |
| beta_tier | HIGH [1.00, 1.05] | α HIGH 적용 | OK |
| winsor | 3σ | 1 clipped | OK |
| infeasibility | None | — | OK |

**Binding constraints**: 없음 (모든 soft/hard 제약 여유 있음)

---

## 8. P4 Challenge Review

- **alpha_objection**: FALSE — Alpha (ABL_C, ICIR=0.77, Harvey t=12.86, FF3=1.00) 품질 이상 없음
- **risk_objection**: FALSE — Risk (LW Oracle cond=14.78, CVaR=3.55%, regime Σ 4구간) 구조 이상 없음
- **silent_constraint_relaxation**: NONE — infeasibility_report 불필요

---

## 9. Sprint 개선 기대치

| 지표 | MEGA_01 | MEGA_02 예상 | 메커니즘 |
|------|---------|-------------|---------|
| MDD | -44.31% | ≤ -30% | CVaR cap 1.71% (▼51.8%) + CRISIS-Σ |
| FF5 Harvey t | 1.838 | ≥ 3.0 | Market factor 기여 완화 (MinVar 구조) |
| NORMAL SR | 0.30 | ≥ 0.6 | NORMAL-Σ switching + style loading |

---

## 10. 다음 단계

→ Forge 체인: `optimization_package.json` + `weights.csv` 수신 후 `run_all.R` 통합 + 백테스트 실행

**Status**: OPTIMIZER_DONE
