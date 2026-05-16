# Alternative Optimizer Comparison Protocol — Step 4.2

**WT-D20260517_001 · optimizer-research Step 4.2**
**Author**: optimizer-research agent
**Date**: 2026-05-17
**Lineage**: alpha_package §model.constraint_projection / risk_package §sigma_estimator_choice / You-Zhang 2025 §5

---

## 0. Purpose

DPL은 features → weights 직접 emission paradigm (Two-stage μ̂→optimizer 우회). **그러나** DPL value-add 정량화 의무 (alpha CF-A2-DPL Codex C2 ACCEPT — Composite 개선 입증).

본 protocol = DPL 학습 후 **post-hoc 사후 검증 비교**:
- DPL이 학습한 intermediate scores (ScoreHead s_t) 추출
- 동일 scores를 입력으로 전통 optimizer 가동
- DPL weights (4-stage projection) vs 전통 optimizer weights 비교
- → DPL "joint learning value-add" 정량화

---

## 1. Baseline optimizer suite

You-Zhang 2025 §5 정합 + Pfaff Ch.10-12 + Gilli-Maringer Ch.12 reference.

| ID | Method | Inputs | Output | Library |
|---|---|---|---|---|
| **B1_MVO** | Markowitz mean-variance | α̂ = DPL ScoreHead s_t / Σ = risk_package LW | w_mvo | `quadprog::solve.QP` |
| **B2_HRP** | Hierarchical Risk Parity | Σ = risk_package LW (no α̂) | w_hrp | `02_Infrastructure/portfolio/hrp_core.R` |
| **B3_ERC** | Equal Risk Contribution | Σ = risk_package LW | w_erc | `02_Infrastructure/portfolio/advanced_weights.R` |
| **B4_CVaR_LP** | CVaR LP | Return history T=60m | w_cvar | `Rglpk::Rglpk_solve_LP` |
| **B5_MaxDiv** | Maximum Diversification | Σ = risk_package LW | w_md | `fPortfolio::mdpPortfolio` |
| **B6_EW** | Equal-weight top-20 (naive) | Top-20 by α̂ rank | w_ew = 0.05 each | trivial |
| **DPL_KR_v1** | DPL 4-stage projection | features X_t (joint trained) | w_dpl | PyTorch (Forge cycle) |

**Hard constraints applied to ALL methods**:
- long-only (Stage 1 equivalent)
- max_names = 20
- weight_bounds [0, 0.20]
- Σw = 1
- LIQ 2e8 KRW filter (universe)

**Cost-aware loss / TO penalty**: 본 baseline suite은 unconstrained MVO X. `mvo_weights()` from `weight_method_registry.R` (alpha CF-A2-DPL Codex C2 mandate retain): bounds [0, 0.20] + max_names 20 + λ=2.0 + ψ=0.3 + turnover_penalty.

---

## 2. Comparison method

### 2.1 Identical input setup

**Per sig_date**:
1. DPL forward pass → ScoreHead output s_t (raw scalar, pre-ReLU)
2. s_t cross-section Z-scored within sig_date
3. Σ_stocks_t = risk_package LW oracle 60m rolling at sig_date (sig_date_lockbox)
4. Return history H_t = realized 60-month return panel ending sig_date

**Forwarded to baseline**:
- B1_MVO: (s_t Z-scored, Σ_t) → w_mvo via `mvo_weights(alpha=s_t, cov_matrix=Σ_t, lambda=2.0, psi=0.3, bounds=c(0, 0.20), max_names=20)`
- B2_HRP: (Σ_t) → w_hrp via HRP recursive bisection + cluster allocation
- B3_ERC: (Σ_t) → w_erc via Newton iteration
- B4_CVaR_LP: (H_t α=0.05) → w_cvar via Rockafellar-Uryasev 2000 LP
- B5_MaxDiv: (Σ_t) → w_md via max(σ_w·1) / sqrt(w'Σw)
- B6_EW: top-20 by s_t rank → w_ew = 0.05 each
- DPL: w_dpl from end-to-end forward pass

### 2.2 Metrics measured per method

| Metric | Definition | Method |
|---|---|---|
| Net SR | `(mean(r_p_net) - rf) / sd(r_p_net) × √12` | PerformanceAnalytics `SharpeRatio.annualized` |
| Gross SR | Same as Net SR but pre-cost | Same |
| MDD | Max drawdown | PerformanceAnalytics `maxDrawdown` |
| CAGR | Compound annual growth rate | PerformanceAnalytics `Return.annualized` |
| Turnover | Σ\|Δw\| annualized | TO = `mean(rowSums(abs(diff(W))))` × 12 |
| Cor vs STR_1715 | Pearson on monthly returns | `cor(r_p_method, r_str1715, method="pearson")` |
| Cor vs DPL | Pearson on monthly returns | `cor(r_p_method, r_p_dpl, method="pearson")` |
| HHI | Σ w_i² | per sig_date, averaged |

### 2.3 DPL value-add definition

**Definition 1 (Pareto improvement)**:
> DPL Pareto-dominates baseline B if SR(DPL) > SR(B) AND MDD(DPL) ≥ MDD(B) (less worse, or equal) — at same gross.

**Definition 2 (joint learning benefit)**:
> Quantify `ΔSR_joint = SR(DPL) - SR(MVO with same DPL-ScoreHead α̂)`.
>   - ΔSR_joint > 0 → joint learning provides MVO-uncapturable signal
>   - ΔSR_joint ≈ 0 → DPL ≈ MVO; Two-stage paradigm sufficient (DPL paradigm value LOW)
>   - ΔSR_joint < 0 → DPL underperforms; back to MVO baseline

**Definition 3 (orthogonality)**:
> If cor(DPL, STR_1715) < 0.3 AND cor(MVO, STR_1715) < 0.3 → orthogonality is paradigm-shift-agnostic (paradigm doesn't claim sole orthogonality).
> If cor(DPL, STR_1715) < 0.3 AND cor(MVO, STR_1715) > 0.5 → DPL specifically extracts orthogonal signal.

---

## 3. Walk-forward integrity

### 3.1 Out-of-sample partition

`alpha_package §evaluation_windows`:
- 5 walk-forward windows shift-12m overlapping
- Each: train 60m / val 12m / test 12m (window 5 test = 4m partial)
- Total: 52 net test months

### 3.2 Per-window baseline emission

Per window w ∈ {1..5}:
1. Forge DPL train on train_w → DPL θ_w
2. Forge DPL forward pass on test_w → s_t (ScoreHead intermediate) + w_dpl_t for t ∈ test_w
3. Per sig_date t ∈ test_w:
   - α̂_t = s_t (DPL learned scores)
   - Σ_t = risk_package LW oracle 60m rolling ending t
   - H_t = realized returns up to t-1 (PIT)
4. For each baseline B ∈ {B1..B6}:
   - w_B_t = optimize(α̂_t, Σ_t, H_t, constraints)
5. Realize r_B,t+1 = Σ w_B_t · r_t+1

### 3.3 Aggregation

- Stack all (5 × 12-ish) = 52 monthly returns per method
- Compute Net SR / MDD / CAGR / Turnover / Cor over 52 months

**PIT integrity**:
- α̂_t uses **DPL θ_w only from train_w**, applied via forward pass at test_w sig_date — no future leak.
- Σ_t uses **60m rolling ending t** — strictly past.
- H_t uses **realized returns up to t-1** — strictly past.

---

## 4. Implementation skeleton (Forge cycle)

본 protocol은 alpha-research / optimizer-research design phase에서 spec emit. Forge agent 실행 의무.

```r
# Forge cycle pseudocode (post DPL train)
library(quadprog)
library(Rglpk)

source("02_Infrastructure/portfolio/weight_method_registry.R")
source("02_Infrastructure/portfolio/mean_variance_optimizer.R")
source("02_Infrastructure/portfolio/hrp_core.R")
source("02_Infrastructure/portfolio/advanced_weights.R")

dpl_scores_panel <- arrow::read_parquet("alpha_scores.parquet")  # post DPL train
sigma_per_sigdate <- "stage_artifacts/WT_D20260517_001/sigma_per_sigdate"
ret_panel <- load_returns_panel()  # PIT cleaned t-1 returns

baselines <- c("B1_MVO", "B2_HRP", "B3_ERC", "B4_CVaR_LP", "B5_MaxDiv", "B6_EW")

results_per_sigdate <- list()
for (sig_date in unique(dpl_scores_panel$sig_date)) {
  alpha_t <- dpl_scores_panel[sig_date == sig_date, .(Ticker, alpha_score)]
  sigma_t <- readRDS(file.path(sigma_per_sigdate, paste0(sig_date, ".rds")))
  ret_hist <- ret_panel[Date <= sig_date - 1L][order(-Date)][1:60]  # 60m rolling

  w_b <- list(
    B1_MVO     = mvo_weights(alpha_t$alpha_score, sigma_t, lambda=2.0, psi=0.3, bounds=c(0, 0.20), max_names=20),
    B2_HRP     = hrp_weights(sigma_t, bounds=c(0, 0.20), max_names=20),
    B3_ERC     = erc_weights(sigma_t, bounds=c(0, 0.20), max_names=20),
    B4_CVaR_LP = cvar_lp_weights(ret_hist, alpha_level=0.05, bounds=c(0, 0.20), max_names=20),
    B5_MaxDiv  = maxdiv_weights(sigma_t, bounds=c(0, 0.20), max_names=20),
    B6_EW      = ew_top20(alpha_t)
  )

  results_per_sigdate[[as.character(sig_date)]] <- w_b
}

# Aggregate metrics
metrics_per_method <- compute_metrics(results_per_sigdate, ret_panel)
# returns: data.frame(method, net_sr, mdd, cagr, turnover, cor_vs_str1715, cor_vs_dpl, hhi)

# Output
arrow::write_parquet(metrics_per_method, "stage_artifacts/WT_D20260517_001/optimizer_comparison.parquet")
```

**Parallelization** (v6.1 R13 mandate):
```r
library(future); library(future.apply)
plan(multisession, workers = min(5L, parallel::detectCores() - 1L))
results_per_sigdate <- future_lapply(unique_sig_dates, function(sd) {
  # ... above per-sigdate loop body
})
plan(sequential)
```

124 sig_dates × 6 methods sequential ~10분 → parallel 4-5 workers ~3분.

---

## 5. Decision rules (post-emission, Judge stage)

### 5.1 DPL paradigm validation

- **PASS**: SR(DPL) ≥ SR(B1_MVO) AND MDD(DPL) ≤ MDD(B1_MVO) → joint learning value-add positive Pareto.
- **MARGINAL**: \|SR(DPL) - SR(B1_MVO)\| < 0.1 → paradigm value debatable. DSR Bailey-LdP Z 의무 cross-check.
- **FAIL**: SR(DPL) < SR(B1_MVO) → Two-stage paradigm sufficient. DPL paradigm value LOW. → Phase 3 paradigm shift 가설 reject.

### 5.2 Orthogonal source / substitution decision (G2 gate)

`request.json §decision_gates.G2`:
- DPL: |cor(DPL, STR_1715)| < 0.5 → substitution candidate
- DPL: |cor(DPL, STR_1715)| < 0.3 → 4th orthogonal source candidate

Plus baseline cor for context:
- B1_MVO (DPL scores fed): cor vs STR_1715 → context (if also < 0.3, paradigm-agnostic orthogonality)

### 5.3 Production weights selection rule

**Critical (도훈 명시 정합)**: 본 비교 protocol은 **사후 검증용** ONLY. Production weights는 DPL forward pass (4-stage projection) emit. Optimizer-research agent는 baseline weights를 production candidate로 제시 X.

이유:
1. DPL은 features → weights 직접 emission paradigm (You-Zhang 2025)
2. Baseline (MVO with DPL scores)는 paradigm comparison artifact ONLY
3. Production candidate weights = DPL_KR_v1 4-stage projection output

만약 DPL FAIL (§5.1) → WT_001 cycle reject → 다음 cycle paradigm 재검토. baseline weights를 production 승급 X.

---

## 6. Forge cycle obligations

본 protocol은 Forge cycle implementation의 reference:

1. `optimizer_comparison.parquet` emit — 7 methods × 52 test months × {Net SR, MDD, CAGR, Turnover, Cor vs STR_1715, Cor vs DPL, HHI}
2. `optimizer_comparison_summary.json` emit — aggregate metrics + decision rule disposition
3. `weight_comparison_per_sigdate.parquet` emit — sig_date × method × Ticker × weight (audit trail)
4. Method shopping log: `optimization_package.json::method_shopping_log` 8 candidates (DPL + 7 baseline) — v6.1 R2-C ≤ 10 정합.

---

## 7. Open decisions (Codex Round)

본 protocol Codex Critic Round (optimizer stage) 입력:

1. **B4_CVaR_LP의 sample bias**: T=60m historical returns만 사용 → CRISIS 5/52 regime 입력 부족. risk_package C5 PARTIAL REBUTTAL 정합. Forge cycle CVaR LP에 regime-conditional bootstrap injection 검토.
2. **B1_MVO의 confidence weight**: `mvo_weights()` v6.1 R4-A — `confidence` argument 의무. DPL Stage 2 Gumbel softmax max-peak를 confidence proxy로 사용 가능 (alpha_package §model.constraint_projection §output_spec confidence_vector).
3. **Universe consistency**: 모든 baseline은 동일한 LIQ 2e8 filtered universe 사용 의무. Forge cycle universe_filter_t 적용 확인.

---

**Submitted**: 2026-05-17 optimizer-research Step 4.2 deliverable. Forge cycle 실제 측정 의무.
