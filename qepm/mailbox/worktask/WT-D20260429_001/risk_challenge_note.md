# WT-D20260429_001 Risk Challenge Note (Charter §8 + Codex Round 1 Response)

**As-of**: 2026-03-31  |  **Risk estimator**: ledoit_wolf_id  |  **Σ condition**: 59.41
**STR_1715 portfolio TDC q5 (CF-03)**: 0.4494  |  **Gate**: 0.30  |  **Verdict**: FAIL

## 1. CF-RISK-01 (HIGH) — STR_1715 portfolio lower-tail dependence breach
Defense panel (Top-20 alpha_z monthly EW, n=267 joint obs) vs STR_1715 (PG2 active):
- Empirical Joe-Clayton TDC q5 = **0.4494** (gate 0.30 — **FAIL**)
- Empirical q10 = 0.4120, q20 = 0.5431
- Pearson correlation = 0.6142, Kendall τ = 0.4186
- Clayton parametric lower = 0.6179

**Diagnosis**: alpha_inheritance_cor (IC-level mean) = 0.273, but portfolio-level lower-tail dependence is 50% higher than gate. Q07_Earnings_Stability IC-cor 0.737 (Codex CF-03) appears to translate into portfolio crash co-movement.

**Action handoff**: Risk Agent does NOT modify alpha (Charter §8). Optimizer is required to:
- Apply explicit constraint: ρ(defense, STR_1715) ≤ 0.5 OR active-allocation-cap to limit defense weight
- Consider regime-conditional allocation (defense weight active only in CRISIS regimes)
- Re-evaluate composite using residual-on-STR_1715 transformation if hard 0.30 gate is binding

## 2. RF-R1 (HIGH) — MKT variance share 101.92%
- Variance decomposition (Euler): MKT=101.92%, SMB=12.24%, WML=0.31%, **LVOL=-21.97%** (defense hedge), Specific=7.49%
- Net systematic = MKT + LVOL = 79.96% (LVOL is structural hedge, partially offsets MKT)
- **Interpretation**: defense candidate panel still has 80% net market exposure. Risk consistent with alpha specification (Low_Volatility = beta-positive but lower-than-market). Optimizer must size defense weight aware that this is NOT zero-beta hedge.

## 3. Codex Round 1 Concerns Resolution

| Codex Concern | Severity | Resolution |
|---|---|---|
| C1 RF-R1 MKT 101.92% | HIGH | **PARTIAL ACCEPT**: Decomposition mathematically correct (MKT 101.92% + LVOL -21.97% = 80% net systematic). Reporting clarified. Risk authority cannot modify alpha — flagged for Optimizer sizing. |
| C2 TDC q5 = 0.4494 | HIGH | **ACCEPT**: CF-RISK-01 issued. Pearson rho cap alone insufficient — Optimizer must apply CVaR-budget OR residual-on-STR_1715 transformation. |
| C3 CVaR 9.27% vs 2.5% cap | HIGH | **R1 REBUTTAL → R2 ACCEPT**: codex_risk_critic_prompt.md L50 confirms `cvar_cap=0.025 monthly default`. Original R1 daily-equiv argument inverted. CF-RISK-02 issued. Daily-equiv (sqrt(20) iid) = 2.07% PASS, but iid breaks under heavy-tail (Hill α=1.45). For deployment top-20 portfolio with cash overlay, CVaR likely lower. Optimizer recompute required. |
| C4 R²=26.55% vs systematic_share=92.51% | HIGH | **ACCEPT**: Distinct concepts now reported separately. CF-RISK-03 issued: R² < 30% role prompt threshold. KR FF5 v2 (with HML+RMW+CMA via DART quarterly) recommended at deployment. Current 100% LW unjustified given δ=0.0189 (very low shrinkage). |
| C5 shrinkage δ null | MEDIUM | **ACCEPT**: ledoit_wolf_id with explicit δ=0.0189 / target=identity_mu now exposed. |
| C6 4-state regime + bootstrap | MEDIUM | **PARTIAL ACCEPT**: 4-state {BULL=38/NORMAL=126/CAUTION=0/CRISIS=115} audit added. CAUTION=0 docs; bootstrap CI deferred (does not affect single-cutoff Σ). regime_switch_rate_realized=0.2212. CF-RISK-04 issued for thin-state caveats. |
| C7 risk_challenge_note.md | MEDIUM | **ACCEPT**: This document. |

## 3b. Codex Round 2 Additional Concerns Resolution

| Codex R2 Concern | Severity | Resolution |
|---|---|---|
| R2-C3 monthly CVaR cap unit | HIGH | **ACCEPT (REVERSED from R1)**: Re-read codex_risk_critic_prompt.md L50 — cap is monthly default 0.025. CF-RISK-02 issued. Daily-equiv argument retained as DIAGNOSTIC ONLY, not justification. |
| R2-C4 R² < 30% threshold | HIGH | **ACCEPT**: codex_risk_critic_prompt.md L34 confirms 30% threshold. CF-RISK-03 + recommendation for KR FF5 v2 enrichment at deployment. |
| R2-C5 RF-R7 + bootstrap CI | MEDIUM | **ACCEPT**: CF-RISK-04 issued. Single-window estimation acknowledged; subperiod decay test deferred to deployment phase (not affecting current Σ). |
| R2-C6 DCC-Copula not tested | MEDIUM | **REBUTTAL**: DCC-GARCH is dynamic time-series model — alpha as_of=2026-03-31 single-cutoff Σ structurally not applicable. DCC would apply at deployment for time-varying allocation, not at as-of Σ. Hill α=1.45 caveat acknowledged via RF-R6 flag. |
| R2-C7 weights.csv + AX-008 triangulation | MEDIUM | **REBUTTAL**: weights.csv is OPTIMIZER artifact (next phase). Risk Agent role boundary (risk_research_init.md `<strict_prohibitions>` 3) explicitly forbids weight proposal. AX-008 second source = independent Optimizer + Judge phases (deferred per design). |

## 4. PIT C1-C15 Compliance
- C1 expanding window: factor returns and Σ estimation use rolling 60m up to PIT_HARD_CUTOFF=2026-03-31
- C2 same-day circular: tertile sorts use Size_lag/Ret6_lag/Vol_lag (t-1 month)
- C9 DD/VT lag: not applicable (Risk Σ phase, no overlay)
- C11 macro lag: KR-only data, no FRED leakage
- C13 Z_Score_Aligned: alpha-side responsibility (PASS — alpha_package validated)
- C14 IC Usable_Date: alpha-side responsibility
- C15 Factor DB: alpha-side via factor_db_connector

## 5. Σ + Tail Risk Summary
- **Σ**: 60×60 (Top-60 candidate panel), method=ledoit_wolf_id, cond=59.41, min_eig=0.001722, PSD=TRUE
- **Stress 8 worst**: RateHike_2022 = -0.2192 (-21.92%)
- **CVaR(5%) monthly**: -0.0927 / **CDaR(5%)**: -0.2377 / **Max DD (in-window)**: -0.2470
- **Hill alpha**: 1.4516 (hill)
- **Liquidity**: Top-60 panel ADV≥2e8 = 60/60 (100% PASS for deployment)
- **Crowding**: defense panel vs STR_1715 holdings overlap = 4/20 (20%)
- **Sector top**: 필수소비재 = 20.00%, HHI = 0.1061

## 6. Selection Objective
- selection_objective = **condition_number** (R4 P3 HARD compliant)
- Method log: 4 candidates {sample, ledoit_wolf_id, lw_constcor, gerber_rmt}
- Selected: ledoit_wolf_id (smallest cond among PSD candidates)

---
*Risk Agent only quantifies covariance + tail. Alpha modification, weight proposal, family saturation expulsion are NOT Risk authority. Optimizer/Governor ingest this package + challenge_note for downstream decisions.*

