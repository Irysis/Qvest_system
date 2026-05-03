# STR_1715_LRO_v0.1 — Methodology Doc (risk-research)

**WT_ID**: WT-S20260503_001
**Date**: 2026-05-04
**Author**: risk-research agent

---

## 1. Latent Risk Overlay (LRO) Pipeline

```
Step 1: Known Factor Residualization
  R_i,t = α + Σ β_k F_k,t + Σ γ_s S_s,t + ε_i,t      (K=6 known + 11 sector)
  →  U_i,t = ε_i,t   (residual return matrix)

Step 2: Rolling PCA on cov(U_t)  [window 252d, t < sig_d]
  Σ_U,t = B_t Λ_t B_t' + diag(D_t)
  →  Top K=5 eigvectors B_t  (N × 5)
  →  λ_t  (5)

Step 3: Procrustes Alignment to B_ref (IS-frozen)
  Q_t = arg min_Q ||B_t Q - B_ref||_F     s.t.  Q'Q = I
  →  B_t* = B_t Q_t   (sign + permutation stable)

Step 4: Subspace Drift
  P_t = B_t* B_t*'
  P_ref = B_ref B_ref'
  D_t = ||P_t - P_ref||_F / sqrt(2K)

Step 5: Anchor Mapping  (10 anchors, label only)
  R²_k,a,t = lm(PC_k,t ~ anchor_a,t)$r.squared

Step 6: Portfolio Risk Decomposition  (w_t = STR_1715 weight proxy)
  x_t = B_t*' w_t                          (latent exposure, K-vec)
  σ_p²(t) = w_t' Σ_t w_t
  LRS_k(t) = (x_k,t² × λ_k,t) / σ_p²(t)
  LFC(t) = max_k LRS_k(t)
  LHHI(t) = Σ_k LRS_k(t)²
  IdioShare(t) = (w_t' D_t w_t) / σ_p²(t)
  MRC_i(t) = w_i,t × (Σ_t w_t)_i / σ_p(t)
  Top3MRC(t) = sum of top 3 normalized MRC
  ARS_a(t) = Σ_k LRS_k(t) × R²_k,a(t)

Step 7: Robust PIT z-score  (expanding median/MAD, min_obs=24m)
  Z_X(t) = (X_t - median(X_τ<t)) / (1.4826 × MAD(X_τ<t))

Step 8: Latent Risk Index
  LRI(t) = 0.25·Z_LFC + 0.20·Z_LHHI + 0.20·Z_D
         + 0.15·Z_ARS_Revision + 0.10·Z_ARS_Momentum + 0.10·Z_Top3MRC

Step 9: 4-state classification (IS quantile frozen, hysteresis)
  q = quantile(LRI[sig_date <= IS_END], probs = c(0.65, 0.80, 0.90, 0.95))
  state(t):
    Normal     if  LRI < q0.80          OR  prev was non-Normal AND LRI < q0.65
    Crowded    if  q0.80 ≤ LRI < q0.90
    HighRisk   if  q0.90 ≤ LRI < q0.95
    Extreme    if  LRI ≥ q0.95
```

---

## 2. Implementation Details

### 2.1 Known KR factor returns

각 daily date d에 대해:
- 해당 month sig_d에서 `load_month_factors(sig_m, coverage_min=0.05)` panel load
- factor_mapping (LRO_PARAMS$factor_mapping):
  - MKT_KR    = mean(Z_aligned of MK01_CAPM_Beta, D02_Beta, D12_Beta_126d)
  - SIZE_KR   = mean(L26_Log_MktCap)
  - VALUE_KR  = mean(V01_BM, V02_EP)
  - MOM_KR    = mean(M01_Mom_12_1)
  - QUALITY_KR= mean(Q01_GPA, Q02_ROE, Q03_ROA, Q07_Earnings_Stability)
  - LOWVOL_KR = mean(R01_VaR_95, R02_VaR_99, D02_Beta)
- daily long-short: top30% Z 평균 Ret(d) - bottom30% Z 평균 Ret(d)

### 2.2 Sector dummies

- raw RAWDATA `Sector` column 사용
- 가장 populous 11 sector + Other → 12 sector dummy (S_t)

### 2.3 OLS multivariate

cross-section 매 t:
```
X = [1, F_t, S_t]  (T_w × (1 + 6 + 12))
B_known = (X'X)⁻¹ X' R   (regression coefficients)
U = R - X B_known        (residual)
```

### 2.4 PCA

```
cov_U = cov(U)
eig = eigen(cov_U, symmetric=TRUE)
B_t = eig$vectors[, 1:K]   (top K=5)
λ_t = eig$values[1:K]
```

### 2.5 Procrustes

```
M = B_ref' B_t                  (K × K)
svd_M = svd(M)
Q_t = svd_M$v %*% t(svd_M$u)
B_t_aligned = B_t Q_t
```

### 2.6 Anchors (10)

- Market: cross-sectional mean Ret
- Size/Value/Momentum/Quality/LowRisk: F_t columns
- Semi_AI: S_t sector matching "Semiconductors|IT|Technology|반도체|전자|Electronics"
- Bio: S_t sector matching "Biotechnology|Bio|Health|Pharmaceutical|바이오|제약"
- Energy_Cyclical: S_t sector matching "Energy|Oil|Materials|Steel|화학|에너지|Chemicals|조선"
- Revision: F_t QUALITY_KR (placeholder — proper analyst revision factor not in factor DB; label only)

### 2.7 Frozen params (AX-002)

`stage_artifacts/WT_WT-S20260503_001/lro_params_frozen.json`:
- K = 5
- residualization_window = 252
- pca_method = "covariance"
- is_endpoint = 2024-06-30
- threshold quantiles + hysteresis (entry q0.80, exit q0.65)
- LRI weights (6 components)
- factor_mapping (full)
- SHA-256 SHA = a5c55fc8355b26af...

Forge 의무: verify_hash 동일 SHA. 다르면 schedule_fidelity FAIL.

---

## 3. Empirical Choices Justification

| Choice | Alternative | Justification |
|---|---|---|
| K = 5 | K∈{3,5,8} | 5는 Marchenko-Pastur null (T_w=252, N=500 → eigenvalue noise threshold ~0.5%) 위 안정적, eigenvalue gap relative ≥ 2.25%. K=3 too few for 11-sector + 6-factor jointly residualized; K=8 noise inclusion |
| residualization_window 252d | 504d | KR market regime shifts ~1y (외환위기/IT버블/리먼/COVID). 252d = 1 trading year, regime adapts faster. 504d 비교는 robustness check 가능 |
| cov-PCA vs cor-PCA | cor-PCA | LRS = (x² λ) / σ_p² 가 portfolio variance 직접 분해와 일치하려면 cov 필요. cor-PCA는 standardize 후 추가 계산 필요 (σ_p² ≠ Σ_k x_k² λ_k) |
| EW_top20 weight proxy | STR_1715 actual weight | risk research에서 weight 시계열 reconstruct는 forge 책임. risk research는 latent risk **infra** + **methodology**까지. 실 STR_1715 weight 적용 시 magnitudes 다름 (challenge note h) |
| Hysteresis (entry 0.80 / exit 0.65) | symmetric (0.80/0.80) | Hamilton (1989) regime switching 표준 — boundary 진동 방지. 0.65는 q0.80과 q0.95 격차의 ~50% 안쪽 |
| MAD 1.4826 | sd | Hampel (1974) — outlier robust. KR 시장 fat tail 환경 (2008/2020/2022) 적합 |

---

## 4. Outputs

| Path | Description |
|---|---|
| `stage_artifacts/WT_WT-S20260503_001/lro_params_frozen.json` | AX-002 frozen params + SHA |
| `stage_artifacts/WT_WT-S20260503_001/B_ref.parquet` | IS endpoint loadings (frozen) |
| `stage_artifacts/WT_WT-S20260503_001/covariance.parquet` | last sig_date Σ = B Λ B' + D |
| `stage_artifacts/WT_WT-S20260503_001/residuals.parquet` | last window U_t panel |
| `stage_artifacts/WT_WT-S20260503_001/lro_monthly_risk_report.csv` | full 268m metrics + state + LRI |
| `stage_artifacts/WT_WT-S20260503_001/lro_policy_state.csv` | monthly state + transitions |
| `stage_artifacts/WT_WT-S20260503_001/lro_factor_mapping.csv` | per-month PC ↔ top-anchor R² |
| `stage_artifacts/WT_WT-S20260503_001/anchor_map.json` | IS freeze + OOS comparison |
| `stage_artifacts/WT_WT-S20260503_001/tail_risk.json` | state-conditional VaR/ES/CDaR |
| `stage_artifacts/WT_WT-S20260503_001/_debug/single_rebalance_2024_12_31/` | debug 8-file (B_t, B_ref, Q_t, D_t, LRI, mrc, anchor_R2, residuals) |
| `stage_artifacts/WT_WT-S20260503_001/_debug/debug_pass.json` | 9-field gate (overall_pass=true) |
| `stage_artifacts/WT_WT-S20260503_001/_debug/pit_audit_2024_12_31.json` | single-point PIT audit |

---

## 5. Self-detected Limitations (for challenge note)

(see 01_research_design.md §8 + challenge_note.md)
