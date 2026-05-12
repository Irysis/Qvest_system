# Weight Method Selected — WT-P20260509_002 (FINAL post-Codex)

**Selected method**: `WF_DRO_W_eps0.1` (Walk-forward Distributionally Robust Optimization, Wasserstein ε=0.1)

**Date**: 2026-05-09
**Agent**: optimizer-research
**Mandate source**: 도훈 직접 mandate 2026-05-09 (A안 walk-forward dynamic, paradigm-free)
**Codex Critic Round**: Round 1 → APPROVE_CONDITIONAL (3 ACCEPT + 1 PARTIAL + 3 REBUTTAL, see challenge_note_optimizer.md)

---

## 1. Selection summary (post-revision)

| Field | Value |
|---|---|
| Method | Walk-forward DRO Wasserstein, ε=0.1 |
| Academic reference | Esfahani-Kuhn (2018) Mathematical Programming 171 |
| Composite score | 91.10 (tied #1-#8 dynamic methods, spread 0.97) |
| Tie-breaker | Charter v1.5: Validity > Implementability > Robustness > Performance |
| SR (annualized) | 1.8631 |
| CAGR | 20.49% |
| MDD | -11.15% |
| Sortino | 4.510 |
| Calmar | 1.838 |
| Turnover (annualized) | **4.70%** (lowest dynamic) |
| AX-001 v2 portfolio (3-test) | PASS |
| DSR (Bailey-LdP, N=10) | DSR ≈ 1.00 (z=6.05) |
| Harvey-Liu t_NW (lag 4) | 6.28 (>>3.0 PASS) |
| Sub-period sign consistency | 80% (4 of 5 PASS, 2022-2023 negative) |

---

## 2. Walk-forward design

- **Rolling window**: 60 months (Σ + μ both estimated from past 60m only)
- **Burn-in**: 60 months (first 60 sig_dates skipped — see infeasibility_report.json)
- **Rebalance**: monthly
- **PIT strict**: 각 sig_date의 weights = 직전 60m past data만 사용. Future leak 0건.
- **No in-sample optimization**: 의무
- **Eval period**: 2010-02-01 ~ 2026-04-01 (195 obs post-burn-in)

---

## 3. Methods evaluated (10, R2-C cap compliant)

1. WF_RP_ERC — Risk Parity Equal Risk Contribution (Spinu 2013 cyclic CD)
2. WF_MV_lambda{2,5,10} — Markowitz Mean-Variance with risk aversion ∈ {2, 5, 10}
3. WF_IV — Inverse Volatility
4. WF_MaxDiv — Maximum Diversification Ratio (Choueifaty-Coignard 2008)
5. WF_Bayesian_PS — Bayesian shrinkage (Pástor-Stambaugh 2009 + Avramov 2002 + Jorion 1986)
6. WF_DRO_W_eps{0.01, 0.05, 0.1} — Distributionally Robust Optimization Wasserstein (Esfahani-Kuhn 2018)

**Excluded** (Codex C2 ACCEPT):
- WF_HRP — numerical degeneracy with N=3 active sleeves
- WF_BL — null-view BL collapse to IV (redundancy)

**Constraint set (per-sleeve)**:
- AR_on_M4: [0, 0.50]
- TSMOM_8ETF: [0, 0.50]
- KR_10y: **[0, 0.20]** (Codex C1 ACCEPT mandatory: A148070 단일 ETF cap)
- Cash: [0, 0]
- Σw = 1, long-only

---

## 4. Sleeve definition (immutable from upstream)

| Sleeve | Definition |
|---|---|
| AR_on_M4 | STR_1715 alpha-updated × M4 overlay × β threshold (50% sleeve standalone, 256m) |
| TSMOM_8ETF | 8-ETF basket re-derived (KODEX_KTB10Y A148070 제거 후 재정규화: r_8ETF = (r_9ETF − w_KTB10Y · r_KTB10Y) / (1 − w_KTB10Y), 135m TSMOM_PRESENT=TRUE) |
| KR_10y | KODEX 국고채10년 (A148070) standalone returns (256m) |
| Cash | 0% return retain (UB=0 walk-forward 강제) |

---

## 5. Selection rationale (paradigm-free)

### 5.1 Composite score 분포 (post Codex revision)

| Rank | Method | Composite | SR | CAGR | MDD | TO_ann |
|---|---|---|---|---|---|---|
| 1 | WF_MV_lambda2 | 91.13 | 1.8838 | 20.79% | -11.52% | 30.29% |
| 2 | **WF_DRO_W_eps0.1** | **91.10** | **1.8631** | **20.49%** | **-11.15%** | **4.70%** |
| 3 | WF_MV_lambda5 | 91.08 | 1.8789 | 21.75% | -11.52% | 9.07% |
| 4 | WF_MaxDiv | 91.08 | 1.8798 | 21.36% | -11.54% | 7.59% |
| 5 | WF_DRO_W_eps0.01 | 91.04 | 1.8695 | 21.65% | -11.52% | 11.12% |
| 6 | WF_Bayesian_PS | 90.94 | 1.8665 | 21.48% | -11.52% | 14.00% |
| 7 | WF_MV_lambda10 | 90.91 | 1.8545 | 21.16% | -11.35% | 19.33% |
| 8 | WF_DRO_W_eps0.05 | 90.49 | 1.8648 | 21.18% | -12.38% | 7.86% |
| (penalized) | WF_IV | 64.4 | 1.99 | 14.10% | -8.01% | **0.00% — STATIC** |
| (penalized) | WF_RP_ERC | 64.4 | 1.99 | 14.10% | -8.01% | **0.00% — STATIC** |

### 5.2 Tie-breaker (Charter v1.5)

Charter v1.5 hierarchy: **Validity > Implementability > Robustness > Performance > Novelty**.

- **Validity**: 8 dynamic 모두 PASS — 동률
- **Implementability** (turnover annualized):
  - **WF_DRO_W_eps0.1: 4.70%** (최저)
  - 다음 WF_MaxDiv: 7.59%
  - 다음 WF_DRO_W_eps0.05: 7.86%
  - WF_MV_lambda5: 9.07%
- **Robustness** (DSR / Harvey / sub-period): 8개 모두 DSR≈1, Harvey >3.0 PASS — 동률
- **Performance** (SR / CAGR / MDD): 1위 SR WF_MV_lambda2 1.884 vs WF_DRO_W_eps0.1 1.863 (Δ 0.021, 미미)

→ Implementability 우선 적용 (Charter v1.5) → **WF_DRO_W_eps0.1 자율 권고**.

### 5.3 Why DRO Wasserstein ε=0.1?

- Esfahani-Kuhn (2018) framework: rolling 60m sample distribution을 nominal로 두고 Wasserstein-2 ball ε 내 worst-case distribution에 대해 robust optimization
- ε=0.1 = ambiguity radius 보수적
- Closed-form approximation: Σ_DRO = Σ + ε² · I, μ_DRO = μ − ε · diag(Σ)^0.5
- 결과: cov inflation + mean shrinkage → **least aggressive corner solution → low turnover + low MDD**
- KR_10y cap 0.20 정합 + AR-TSMOM dynamic trade-off 유지

### 5.4 Effectively-static method 제외

WF_IV / WF_RP_ERC raw composite 92.0 (1위/2위)였으나 weight evolution sd_AR=0, sd_TSMOM=0, sd_KR=0 → **완전 stationary** = effective static. 도훈 mandate "no_static_weight_admit" 정신 위반 → composite × 0.7 penalty + tie-zone 제외.

KR_10y cap 강제 후 IV/RP_ERC 모두 (AR 0.30, TSMOM 0.50, KR 0.20) cap-bind static 수렴. 이는 IV 수학적으로 inverse-vol weight가 cap에 모두 bind되어 매번 동일 산출.

---

## 6. Convergence finding (paradigm-free)

도훈 framing **S4 (50/25/20/5)** vs walk-forward dynamic best **WF_DRO_W_eps0.1 (latest 2026-04-01: 50/30/20/0)**:

| Sleeve | S4 도훈 framing | WF_DRO_W_eps0.1 (latest) | Δ |
|---|---|---|---|
| AR_on_M4 | 0.50 | 0.50 | 0.00 |
| TSMOM | 0.25 | 0.30 | +0.05 |
| KR_10y | 0.20 | 0.20 | 0.00 |
| Cash | 0.05 | 0.00 | -0.05 |

**Walk-forward dynamic (paradigm-free)** 결과가 도훈 직관 framing과 AR/KR 정확 일치, TSMOM/Cash trade-off만 ±5pp.

→ 도훈 직관은 paradigm 정당화 없이도 walk-forward 정량 도출 weight 영역과 수렴. **체리피킹 retract 정합** (paradigm 인용 없이 정량 검증으로 동일 영역 도달 입증).

→ **Codex GOV-C1 비평 정합**: static admit 회피 + walk-forward dynamic admit + paradigm 인용 0건.

---

## 7. AX 공리 정합

- **AX-001 v2 conditional defense (portfolio version, 3-test)**: PASS
  - crisis_alpha = +0.026 (bad regime에서 method가 S0 대비 +2.6%pt month outperform)
  - mdd_alleviation = +11.17%pt (S0 -22.32% → method -11.15%)
  - spread_bad = +0.026 (bad 평균 return spread > 0)
- **AX-002 PIT strict**: walk-forward 60m rolling, 매 sig_date 추정 = 직전 60m past data only
- **AX-007 multi-sleeve EXCEPTION**: 3 risk-bearing sleeves (single-sleeve top20 long-only 회피)
- **AX-008 triangulation**: 1.5/3 (Optimizer + Codex Critic Round PARTIAL) → Forge + Architect 후속

---

## 8. Static vs Dynamic 정량 비교

| Metric | BENCH_S0 (alpha 100%) | BENCH_S4 (50/25/20/5) | WF_DRO_W_eps0.1 (dynamic) | Δ vs S4 | Δ vs S0 |
|---|---|---|---|---|---|
| SR | 1.7166 | 1.8600 | 1.8631 | +0.003 | +0.146 |
| CAGR | 40.21% | 21.06% | 20.49% | -0.57pp | -19.72pp |
| MDD | -22.32% | -12.44% | -11.15% | +1.29pp (better) | +11.17pp (better) |
| Sortino | 3.886 | 4.407 | 4.510 | +0.103 | +0.624 |
| TO_ann | 0% | 0% | 4.70% | +4.70pp | +4.70pp |

**Δ 해석**:
- SR/CAGR S4와 거의 동일 (Δ <0.005, 0.6pp) — dynamic 정통 cost (rolling estimation 잡음)
- MDD dynamic 우월 (-11.15% vs -12.44%, +1.29pp 개선)
- Sortino dynamic 우월 (+0.10)
- Turnover dynamic +4.70pp — hurdle 600% mandate 압도적 통과

**vs S0**: SR +0.15 + MDD +11.17pp + Sortino +0.62 = **trade-off 합리** (CAGR -19.72pp는 hedge cost).

---

## 9. Deployment-ready weights (latest 2026-04-01)

| Sleeve | Weight |
|---|---|
| AR_on_M4 | 0.5000 |
| TSMOM_8ETF | 0.3000 |
| KR_10y | 0.2000 |
| Cash | 0.0000 |
| **Sum** | **1.0000** |

다음 sig_date (2026-05-XX) weight = walk-forward 매월 재산출. Forge handoff 시 195 dates × 4 sleeves schedule 사용.

---

## 10. Hard boundary / mandate compliance

- alpha_definition_unchanged: ✅
- sleeve_definition_unchanged: ✅
- no_static_weight_admit: ✅ (S4 admit 후보 아님 + WF_IV/RP_ERC effective static penalty)
- paradigm_free: ✅
- AX-002 PIT strict: ✅
- AX-001 v2 conditional defense PASS: ✅
- request.json constraints 준수: ✅ (weight_bound [0, 0.50] for AR/TSMOM, [0, 0.20] for KR_10y per Codex C1, Σw=1, long-only, rolling 60m, burn-in 60m)
- Codex GOV-C1 비평 정합: ✅
- single_asset_cap_0.20 (KR_10y): ✅ (Codex C1 ACCEPT, cap binding)
- candidates_tried <= 10 (R2-C): ✅ (Codex C2 ACCEPT)

---

## 11. Codex Critic Round summary

| Concern | Severity | Disposition | Action |
|---|---|---|---|
| C1: KR_10y > 0.20 cap | CRITICAL | ACCEPT | UB lowered 0.50→0.20 |
| C2: 12 candidates > 10 | HIGH | ACCEPT | HRP/BL 제외 |
| C3: IR_vs_S0 negative | HIGH | PARTIAL | Sleeve scope rebuttal + TDC reporting |
| C4: AX-001 v2 임의 | HIGH | REBUTTAL | Portfolio adaptation 학술 정통 |
| C5: WT-specific artifacts | HIGH | REBUTTAL | inherit_ref mandate |
| C6: Cash UB=0 | MEDIUM | REBUTTAL | mandate scope |
| C7: doc completion | MEDIUM | ACCEPT | challenge_note + listing 추가 |

상세: `challenge_note_optimizer.md`

---

## 12. Forge handoff (next action)

1. weights.csv (`stage_artifacts/WT-P20260509_002/weights.csv`) 195 dates × 4 sleeves
2. infeasibility_report.json (burn-in 60m mandatory skip, AR_on_M4 100% fallback 권장)
3. optimization_package.json (final, 13.9KB)
4. Forge run_all.R + 10-component bt_result + 195m walk-forward backtest
5. AX-008 triangulation 진척 (Optimizer + Codex 1.5 → Forge + Architect 후속)
