# DPL Risk Attribution Design — WT-D20260517_001 risk-research Step 5.4

**Author**: risk-research agent
**Date**: 2026-05-17
**Novelty**: DPL의 explainability 부재 문제를 risk attribution으로 해소 — KR 첫 적용

---

## 1. The DPL Explainability Problem

**Traditional factor model**:
- B exposure matrix가 명시적 (FF5 5 factor × N stock)
- Variance decomposition: σ_p² = w' B Ω B' w + w' D w
- Each factor contribution는 직접 attribution

**DPL paradigm**:
- 634 features → Transformer hidden → score → weight
- Single function f_θ: R^{N×F} → simplex^{N}, top-K
- **B matrix is implicit** in θ (model parameters)
- Variance contribution per feature 추론 → **gradient-based attribution** 필요

---

## 2. Gradient × Input Attribution Protocol

### 2.1 Integrated Gradient (Sundararajan-Taly-Yan 2017)

Per sig_date t, per ticker i, per feature f:

```
IG(i, f, t) = (x_{i,f,t} - x'_{i,f,t}) × ∫_0^1 (∂ f_θ(x') / ∂ x'_f)|_{x' = baseline + α(x - baseline)} dα
```

- **Baseline x'**: cross-section mean per feature (PIT-safe, same sig_date)
- **Integration steps**: 50 (numerical Riemann)
- **Output**: attribution per (ticker, feature, sig_date) triple

```python
# Forge cycle PyTorch implementation
import captum  # from facebookresearch
from captum.attr import IntegratedGradients

ig = IntegratedGradients(model.forward_w)  # wraps DPL forward → weight output
attrs = ig.attribute(
    inputs=X_t,                    # N_t × F features
    baselines=X_t_mean,            # N_t × F cross-section mean
    target=range(N_t),             # per-stock weight
    n_steps=50,
    return_convergence_delta=True
)
# attrs shape: N_t × F
# Convergence delta < 0.01 → trust attribution
```

### 2.2 Saliency vs Integrated Gradients vs DeepLIFT

| Method | Pros | Cons | Recommendation |
|--------|------|------|----------------|
| **Saliency (∇)** | Fast, single forward+backward | Saturation bias, gradient noise | Quick check |
| **Integrated Gradients** | Axiomatic (Sundararajan 2017), conservation guaranteed | Computational cost (50× forward) | **Primary** |
| **DeepLIFT (Shrikumar 2017)** | Faster than IG, similar guarantees | Less stable for deep models | Fallback |

본 protocol = **Integrated Gradients primary**, Saliency 보조 (sanity check).

---

## 3. Variance Attribution

### 3.1 Per-feature variance contribution

```
σ_p² = Var(r_p) = Var(w' r)

# Per-feature attribution approach (linear approximation)
# Σ_p^f = ∂σ_p² / ∂(feature_f exposure) measured via:
#   1. Build factor-mimicking portfolio (FMP) for each feature
#      FMP_f = regression of stock returns on feature exposures → coefficients = FMP weight
#   2. σ_p²_f = w' (FMP_f outer product) Σ_stocks w
#   3. Normalize: σ_p²_f / σ_p² × 100% = factor f variance share

# Forge cycle implementation
for (f in 634_features) {
  fmp_f <- build_fmp(feature_exposure_panel, returns_panel, feature_f)
  var_contrib_f <- t(weights) %*% fmp_f %*% Sigma_stocks %*% weights
}
sort(var_contrib, desc=TRUE)[1:10]  # top 10 features driving σ_p
```

### 3.2 Top 10 risk drivers

Output schema:

```json
{
  "variance_attribution_top10": [
    {"feature": "...", "var_contribution_pct": 0.XX, "category": "Layer_A_factor_db"},
    ...
  ],
  "residual_var_pct": 0.XX,
  "explained_var_pct": 0.XX
}
```

**Acceptance**: top-10 features explain ≥ 50% of σ_p² (interpretability target).

---

## 4. Feature Importance Stability (Across sig_dates)

L-326 lesson: subperiod stability ≥ 0.5. 본 DPL attribution도 동일:

```r
# Per walk-forward window (5 windows)
top10_per_window <- list()
for (w in 1:5) {
  ig_attr_w <- aggregate_ig(window_w_attrs)
  top10_per_window[[w]] <- order(-abs(ig_attr_w))[1:10]
}

# Jaccard overlap across windows
jaccard_pairs <- combn(5, 2)
jaccard_scores <- apply(jaccard_pairs, 2, function(p) {
  jaccard(top10_per_window[[p[1]]], top10_per_window[[p[2]]])
})

# Target: median Jaccard ≥ 0.4 (40% top10 overlap = moderate stability)
# < 0.2 → feature importance non-stable, model overfits per-window
```

---

## 5. Risk-Adjusted Feature Ranking

DPL output features의 risk-adjusted score:

```
risk_adj_importance(f) = mean_attribution(f) / (1 + crowding_score(f))
                       = mean_attribution(f) × (1 - 0.5 × overcrowd_penalty(f))
```

- **High attribution + low crowding** → robust signal
- **High attribution + high crowding** → decay risk (Acadian 2026)
- **Low attribution + low crowding** → noise (drop)
- **Low attribution + high crowding** → trap (avoid)

→ Forge cycle emit `risk_adjusted_feature_ranking.csv` (634 features sorted).

---

## 6. Output schema

```json
// stage_artifacts/WT_D20260517_001/dpl_risk_attribution.json (Forge cycle emission)
{
  "method": "Integrated Gradients (Sundararajan 2017) + Variance Attribution (FMP)",
  "n_features": 634,
  "n_sig_dates": 124,
  "attribution_summary": {
    "top_10_drivers": [...],
    "category_aggregation": {
      "Layer_A_factor_db_monthly": "X.XX% var",
      "Layer_B_wt007_inherit": "X.XX%",
      "Layer_C_factor_db_daily_gap": "X.XX%",
      "Layer_D_daily_aggregate": "X.XX%",
      "Layer_F_interactions": "X.XX%",
      ...
    }
  },
  "stability": {
    "median_jaccard_top10_across_windows": 0.XX,
    "convergence_delta_mean": 0.XX
  },
  "risk_adjusted_ranking_path": "stage_artifacts/WT_D20260517_001/risk_adjusted_feature_ranking.csv"
}
```

---

## 7. References

- Sundararajan M., Taly A., Yan Q. (2017) "Axiomatic Attribution for Deep Networks" *ICML* arXiv:1703.01365
- Shrikumar A., Greenside P., Kundaje A. (2017) "Learning Important Features Through Propagating Activation Differences" (DeepLIFT) *ICML*
- Kokhlikyan N. et al. (2020) "Captum: A unified and generic model interpretability library for PyTorch" arXiv:2009.07896
- Hastie T., Tibshirani R., Wainwright M. (2015) *Statistical Learning with Sparsity* — Variance decomposition
- L-326 (subperiod stability lesson)

---

## 8. Pragmatic Caveat

Captum/IG는 PyTorch dependent — Forge cycle 의무. 본 risk-research stage는 **protocol spec emit only**.
