# Σ Estimator Design — WT-D20260517_001 risk-research Step 5.1

**Author**: risk-research agent
**Date**: 2026-05-17
**WT type**: discovery_design_phase_a (paradigm shift — DPL first KR application)
**Lineage**: alpha_package.json (124 sig_dates × 634 features × top-20) → Forge cycle Σ rolling

---

## 0. Charter §10 + Lockbox 정합

본 cycle은 **design-only spec** (Codex C1 reframe accepted at alpha stage). 실제 Σ 행렬 emission은 **Forge cycle** GPU train 종료 직후 dpl_v1_weights.pt 산출과 함께 sig_date별 covariance.parquet emit.

**Lockbox scope** (`.claude/rules/lockbox-scope.md` 2026-05-09 mandate):
- risk-research = 정규 리서치 단계 → lockbox 정합 의무
- rolling Σ는 PIT C1 strict (Date ≤ sig_date)
- walk-forward 5 windows shift-12m 정합 (alpha와 동일 schema)

---

## 1. DPL paradigm vs Traditional Risk Model 차이

### Traditional (FF5-style two-stage)

```
μ̂(features) → MVO[μ̂, Σ] → w
Σ = BΩB' + D  (factor model 분해, B는 명시적)
```

### DPL (You-Zhang 2025, 본 WT)

```
features → NN(θ) → w  (직접 학습, μ̂/Σ 우회)
Σ는 사후 측정만 — alpha 산출 input X
```

**핵심 차이**: B (exposure) matrix가 traditional처럼 explicit하지 않음. 1044 raw features → 64-dim transformer hidden → score head이 latent factor structure 학습. **post-hoc factor-mimicking portfolio (PCA on residuals) 통해서만 B 측정 가능**.

**Risk Agent 책임 재정의**:
1. Σ는 **사후 검증용** (DPL output weights 가정 시 portfolio variance σ_p² = w'Σw)
2. Crowding은 **per-feature** 측정 (Σ 행렬과 독립)
3. Stress는 **DPL weights × historical regime returns** Monte Carlo
4. Attribution은 **gradient × input** via PyTorch autograd

---

## 2. Σ Estimator 4-way 병렬 비교 design (v6.1 R13 정합)

### 2.1 후보 estimator

| # | Estimator | 적용 condition | 강점 | 약점 |
|---|-----------|---------------|------|------|
| 1 | **Sample (pairwise)** | N ≥ 120 충분 | Unbiased, 해석 명확 | High dim에서 noise dominant, condition number 폭발 |
| 2 | **Ledoit-Wolf (oracle shrinkage)** | N ≥ 60 | Auto-shrinkage to const-cor target, PSD 보장, MVO standard | Constant correlation assumption is naive |
| 3 | **Gerber + RMT noise filter** | Outlier/non-Gaussian | Robust to fat tails (Gerber 2015), Marchenko-Pastur eigenvalue filter | Higher computational cost, 2 hyperparams (Gerber threshold + RMT cutoff) |
| 4 | **DCC-Copula (Engle 2002 + Pfaff Ch.9)** | Regime shift 의심 | Time-varying correlation, tail dependence capture | 추정 불안정, n_assets × T 조건부 stringent |

### 2.2 KR Top500 universe context

- N_t ≈ 500 (after LIQ 2e8 filter at alpha-emit stage), top-20 selection
- **rolling window**: 60 monthly returns (12 sig_dates × 5 = 60m)
- **샘플 부족**: N=500 features × T=60 → sample cov rank=60 ≪ 500 → singular
- → **Sample 단독 사용 불가**, Ledoit-Wolf default 채택 mandatory

**Decision rule (risk-research selection_objective = "shrinkage_quality")**:

```
Primary: Ledoit-Wolf oracle shrinkage rolling 60m per-sig_date
Backup: Gerber + RMT (stress regime detected — VKOSPI > 75th pct)
Reject: Sample (singular at N >> T), DCC-Copula (T=60 insufficient for GARCH stable fit)
```

### 2.3 Per-sig_date rolling (L-326 학습 반영)

**L-326 명시 학습**: WT_015_002 5-source blend에서 single snapshot Σ 추정 → cross-window drift miss → revoke. 본 cycle은 **124 sig_dates 각각 rolling 60m 재계산 mandatory**.

```r
# Forge cycle 실행 예 (PyTorch + R bridge)
for (sd in sig_dates) {  # 124 sig_dates
  window_returns <- returns_panel[Date > sd %m-% months(60) & Date <= sd]
  # N=500 stocks (filter), T=60 months
  Sigma_lw <- cov_lw_oracle(window_returns)
  saveRDS(Sigma_lw, sprintf("stage_artifacts/WT_D20260517_001/sigma_per_sigdate/%s.rds", sd))
}
```

**Output**: `stage_artifacts/WT_D20260517_001/sigma_estimators.parquet`
- columns: `sig_date`, `estimator_name`, `condition_number`, `min_eigenvalue`, `pct_explained_top10_eig`, `shrinkage_intensity`
- rows: 124 sig_dates × 4 estimators = 496 (forge cycle benchmark)
- primary Σ 행렬 자체는 RDS per sig_date (parquet은 metadata만)

---

## 3. Acceptance Criteria

Per sig_date Σ:
- **PSD**: min eigenvalue ≥ 0 (or ≥ -1e-8 numerical tol)
- **Condition number ≤ 500** (LW 후) — 위반 시 Gerber+RMT fallback
- **Shrinkage intensity** report (LW ρ ∈ [0, 1])
- **Stability**: |Σ_t - Σ_{t-1}|_F / |Σ_{t-1}|_F < 0.5 (Frobenius relative change)

---

## 4. Sample Bias Mitigation (CF-A3 inherit)

Alpha stage CF-A3 (124 sig_dates × 52 test months canonical) 위험 Risk stage 그대로 적용:
- Recent 3Y Σ (2023-2026) vs overall Σ subperiod stability ≥ 0.5 (Frobenius correlation)
- Per-window Σ × walk-forward 5 windows → between-window correlation reporting
- Forge cycle gate: 위반 시 Gerber+RMT pivot

---

## 5. AX-008 Verification Triangulation 정합

본 design spec은 **Forge cycle을 위한 protocol**. AX-008 ≥ 2/3 PASS는 다음 단계:
- **Forge** (Step 1): dpl_v1_weights.pt + per-sig_date Σ.rds × 124 emit
- **Codex** (Step 2): risk_package.json critique
- **Architect** (Step 3): independent reproduction of LW Σ on 1 sample sig_date

본 risk-research stage Σ design spec emit → Forge implements → Codex Critic Round (Step 5.5) 평가 → Architect (deployment cycle separate WT) reproduction.

---

## 6. Method Shopping Log (v6.1 R2-C HARD ≤ 5)

| # | Estimator | Considered | Selected | Rationale |
|---|-----------|-----------|----------|-----------|
| 1 | Sample pairwise | Yes | No | N(500) >> T(60) → singular |
| 2 | Ledoit-Wolf oracle | Yes | **Primary** | Default rolling 60m, PSD 보장, condition ≤ 500 target |
| 3 | Gerber + RMT | Yes | Backup | Stress regime fallback |
| 4 | DCC-Copula | Yes | No | T=60 insufficient for GARCH, complexity overhead |
| 5 | Nonlinear shrinkage (NLS) | Considered | No (v2 deferred) | Rcpp v2 dependency, current v1 미가용 |

**candidates_tried = 4** (hard cap 5 미초과).

---

## 7. References

- Ledoit O., Wolf M. (2003) "Improved Estimation of the Covariance Matrix of Stock Returns" *J. Empirical Finance* 10(5): 603-621
- Ledoit O., Wolf M. (2020) "Analytical Nonlinear Shrinkage of Large-Dimensional Covariance Matrices" *Annals of Statistics* 48(5): 3043-3065
- Gerber S., Markowitz H., Pujara P., Vorobyov O. (2015) "The Gerber Statistic: A Robust Co-Movement Measure" *J. Portfolio Management* 42(4)
- Engle R. (2002) "Dynamic Conditional Correlation" *JBES* 20: 339-350
- Pfaff B. (2016) *Financial Risk Modelling* Ch.4 (VaR), Ch.8 (GARCH), Ch.9 (Copula)
- Marchenko V., Pastur L. (1967) eigenvalue distribution — RMT noise filtering
- L-326 (WT_015_002 single-snapshot covariance lesson)
