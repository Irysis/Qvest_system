# Weight Method Selection — WT-D20260508_010

**Task**: R14_DUVOL Skewness Idiosyncratic alpha (Bali-Engle-Murray 2016 + Chen-Hong-Stein 2001)
**Method Selected**: ERC_top20_walk
**Selection Objective**: net_ir_proxy_via_cost_adjusted_sr
**Candidates Tried**: 6 (init.md `<v61_method_shopping_log>` 상한 10 — 6/10 정합)

---

## Method Comparison Table (walk-forward 59 sig_dates, 15bps round-trip cost)

| # | Method | Family | SR_a | mean_m | sd_m | MDD | TO/period | Selected |
|---|---|---|---|---|---|---|---|---|
| 1 | EW_top20_linear | linear_baseline | 0.5824 | 0.0090 | 0.0538 | -0.3105 | 0.272 | |
| 2 | Top_quintile_EW | non_linear | 0.5824 | 0.0090 | 0.0538 | -0.3105 | 0.272 | |
| 3 | EW_top20_confidence | linear_baseline | 0.5824 | 0.0093 | 0.0555 | -0.3216 | 0.288 | |
| 4 | MVO_conf_aware (λ=2, ψ=0.3) | classical | 0.6819 | 0.0116 | 0.0587 | -0.2130 | 0.355 | |
| 5 | HRP_top20 | risk_parity | NA | NA | NA | NA | NA | (infeasible build_hrp NULL fallback) |
| 6 | **ERC_top20** | **risk_parity** | **0.8698** | **0.0133** | **0.0529** | **-0.2104** | **0.271** | **✓** |

**Selection rationale**: ERC_top20_walk = 최고 cost-adjusted SR (0.87) + 가장 낮은 MDD (-21%) + 평균 turnover (0.27/period). HRP는 build 단계에서 single-linkage clustering distance matrix 비정사각 에러로 NULL → fallback EW_linear (5/6 valid).

---

## ERC_top20 Method Details

**Equal Risk Contribution (ERC)** — Maillard-Roncalli-Teïletche (2010) JPM 36(4):
- Goal: marginal risk contribution `MC_i = w_i * (Σw)_i / sqrt(w'Σw)` 모든 i 동일
- Iterative gradient: `w ← w - 0.05 * (rc - mean(rc))`
- Initialize: `w = 1/K` (K=20)
- Iter: 200, projected onto bounds [0, 0.20] + Σw=1 normalization

**Pre-selection**: 매 sig_date alpha_z 상위 20개 (alpha winsor ±2σ 후) → ERC 분배

**Constraints applied**:
- max_names = 20 ✓
- weight_bounds = [0, 0.20] ✓
- min_names = 15 ✓ (n_active = 20)
- hhi_cap = 0.10 ✓ (HHI = 0.0502)
- alpha_winsor = 2.0σ ✓ (12 / 348 winsorized)
- long_only ✓
- Σw = 1.000000 ✓

---

## Walk-forward Performance (59 sig_dates, 2021-06 ~ 2026-04)

```
n_obs = 59
mean_m_net = 0.0133 (gross 0.0141 - cost 0.000807 = 0.01329)
sd_m = 0.0529
SR_a (annualized) = 0.8698
MDD = -0.2104
turnover_avg = 0.271 (per rebalance, two-sided ÷2)
turnover_round_trip_avg_per_period = 0.542
turnover_annual = 0.271 × 12 = 3.255 (under 600% cap)
estimated_cost_per_period = 2 × 0.271 × 0.0015 = 0.000807
```

**RF-O9 schedule density**: 60/60 unique sig_dates = 100% ✓ (Charter v6.3 §9 ≥0.95 PASS)

---

## Hybrid Combine Recommendation (multi-sleeve EXCEPTION AX-007)

**Walk-forward measured (proof anchor, 59 matched months)**:

| w_Hybrid | w_R14_DUVOL | SR_a | MDD | mean_m | sd_m | σ_red_pct |
|---|---|---|---|---|---|---|
| 1.00 | 0.00 | 1.8651 | -0.1748 | 0.0276 | 0.0512 | — |
| 0.90 | 0.10 | 1.9458 | -0.1759 | 0.0258 | 0.0459 | 1.01 |
| 0.85 | 0.15 | 1.9808 | -0.1766 | 0.0249 | 0.0436 | 1.58 |
| **0.70** | **0.30** | **2.0287** | **-0.1801** | **0.0222** | **0.0380** | **3.32** |
| 0.50 | 0.50 | 1.8271 | -0.2015 | 0.0187 | 0.0355 | 4.46 |

**Analytical Markowitz grid (ρ_wf=-0.087 const)**: 최적점 w_h=0.65/w_a=0.35 SR=2.13 (interpolation).

---

## 4-Sleeve Composition Recommendation (Charter §10 deployment_wt scope inheritance)

**Current PG2 active book**: STR_1715_AR (70%) + TSMOM (15%) + KR_10y (15%)
**Add R14_DUVOL** → 4 sleeves (multi-sleeve EXCEPTION AX-007 PASS)

| Grid | STR_1715_AR | TSMOM | KR_10y | R14_DUVOL | Proj SR | σ_red% | Comment |
|---|---|---|---|---|---|---|---|
| A | 0.70 | 0.15 | 0.15 | 0.00 | 1.87 | 0% | status quo, no R14_DUVOL admit |
| **B (primary)** | **0.63** | **0.135** | **0.135** | **0.10** | **1.97** | **1.0%** | **Diversifier 10% — preserves Hybrid integrity** |
| C (alternate) | 0.56 | 0.12 | 0.12 | 0.20 | 2.07 | 2.1% | Moderate, AX-001 v2 FAIL caveat |
| D (aggressive) | 0.49 | 0.105 | 0.105 | 0.30 | 2.13 | 3.3% | Walk-forward measured 2.03 / MDD worsens |

**Optimizer primary recommendation**: **B_63_13.5_13.5_10** (10% R14_DUVOL Diversifier)

**Rationale**:
1. **AX-001 v2 FAIL → Diversifier role advisory** (Risk Agent honest downgrade): R14_DUVOL은 Defense 아님. 보수적 10% allocation이 role classification 정합.
2. **MDD worsens at 70/30 (-0.0052)**: walk-forward 측정에서 D 그리드는 MDD -0.18 vs Hybrid alone -0.17, 즉 -0.005pp 약화. Δ작지만 이는 R14_DUVOL이 Defense가 아니라 Diversifier임의 경험적 입증.
3. **rho_walk_forward CI [-0.264, 0.179] includes 0**: ρ 음수 zone 신뢰 약함. PARTIAL diversification source. 신중한 10% allocation으로 rho realized 변동성 hedge.
4. **σ-reduction +1.0% (B grid) marginal**: 1% σ 감소가 SR +0.10 충분 가치. 30% allocation은 sample size 기반 over-fit 우려.

**Q-Lead/Governor 결정**: A/B/C/D 중 deployment promotion 시점 conviction 기반 선택.

---

## Hard Constraints Audit

| 제약 | Threshold | Observed | PASS |
|---|---|---|---|
| max_names | ≤ 20 | 20 | ✓ |
| min_names | ≥ 15 | 20 | ✓ |
| weight_bounds | [0, 0.20] | [0.0000, 0.0533] | ✓ |
| Σw | = 1.0 ± 0.001 | 1.000000 | ✓ |
| HHI | ≤ 0.10 | 0.0502 | ✓ |
| long_only | weights ≥ 0 | min=0 | ✓ |
| alpha_winsor | ±2σ | 12/348 clipped | ✓ |
| schedule_density | ≥ 0.95 | 1.000 (60/60) | ✓ |
| turnover_annual | ≤ 6.0 | 3.26 | ✓ |

---

## Codex Critic Round 1 Resolution

**Stance received**: REJECT
**Concerns**: 7 (1 CRITICAL + 2 HIGH + 3 MEDIUM + 1 LOW)
**Optimizer classification**: ACCEPT=2 / PARTIAL=3 / REBUTTAL=2

| ID | Severity | Topic | Classification | Action |
|---|---|---|---|---|
| C1 | CRITICAL | Σ κ=202 vs Codex strict ≤100 | PARTIAL | role-spec init.md cond<500 PASS, WT-009 precedent, Discovery WT scope |
| C2 | HIGH | RF-O8 CVaR breach silent | **ACCEPT** | infeasibility_report 발행 (No Silent Override) |
| C3 | HIGH | RF-O10 selection_objective mismatch | **ACCEPT** | selection_objective 정정 + method_log net_ir 컬럼 추가 |
| C4 | MEDIUM | Sequential admission incomplete | PARTIAL | Discovery WT scope, deployment promotion 시 정식 측정 |
| C5 | MEDIUM | Artifact path | PARTIAL | path 정합 (challenge_note + alias 작성) |
| C6 | MEDIUM | Crisis fallback / cash sleeve | REBUTTAL | Optimizer scope 밖 (Forge C-layer per L-274) |
| C7 | LOW | RF-O6/O7 label swap | REBUTTAL | init.md spec 정합, Codex misquote |

**HIGH severity 모두 ACCEPT 처리** → silent_override = FALSE / escalate = FALSE

상세 → `qepm/mailbox/worktask/WT-D20260508_010/challenge_note_optimizer.md`

---

## References

**Academic**:
- Maillard-Roncalli-Teïletche (2010) ERC Properties JPM 36(4)
- Markowitz (1952) Portfolio Selection JF 7(1)
- Ledoit-Wolf (2004) Honey JPM 30(4)
- Grinold (1989) Fundamental Law JPM (IR = IC × √breadth)
- Bali-Engle-Murray (2016) Empirical AP Ch.7 (idio skewness)
- Chen-Hong-Stein (2001) JFE 61 (NCSKEW DUVOL)

**L-codes**:
- L-129 CDaR LP MDD breach silent
- L-219 family saturation
- L-269 v6.0 Codex Critic Round
- L-272 v7.0 Hardening
- L-274 STR_1715 PG2 forward_weights.R 3-Layer
- L-281 Cross-asset orthogonality

---

**Generated**: 2026-05-08T17:32:00+0900
**Optimizer Agent**: optimizer-research v1.2
