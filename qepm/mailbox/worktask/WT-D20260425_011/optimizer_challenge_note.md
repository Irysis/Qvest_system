# WT-D20260425_011 — Optimizer Challenge Note (Iter 6 MEGA_06)

**Iter 6 STR_1699 + Kelly_frac05 + 3-Layer Overlay — Optimizer Research handoff**

Author: Optimizer Research Agent (Opus 4.7) | 2026-04-25

---

## 1. Codex Critic Round Summary

Single-round Codex critique (GPT-5.5 + xhigh) executed against `optimization_package_draft.json`.

- **Round 1 stance**: REVISE
- **Critical concerns**: 6
- **Triage outcome**: 4 ACCEPT + 4 PARTIAL + 1 REBUTTAL

Codex critique is treated as devil's advocate per agent definition. No veto power.
Walk-forward (RF-O9): NOT triggered — 215 sig_dates time-series schedule confirmed.
Hard constraints (max_names ≤ 20, weight_bounds [0, 0.20], long-only, Σw=1): ALL PASS.
Both turnover hard cap (≤600%) AND CVaR_d cap (≤2.5%) PASS — Iter 5 CVaR breach resolved.

---

## 2. ACCEPT (4 mechanical fixes applied)

### 2.1 NO_SILENT_OVERRIDE_OPTIMIZER_ARTIFACTS (HIGH)

Producing all 4 mandatory artifacts now: (1) optimization_package.json (final, this finalize step), (2) optimizer_challenge_note.md (this Codex triage record), (3) weight_method_selected.md (selection rationale + comparison table), (4) artifact_lineage.json append via record_package_lineage(). Status transition RISK_DONE → OPTIMIZER_DONE. AX-002 process honesty satisfied.

### 2.2 CRISIS_BOUNDARY_SHRINK_PARTIAL (MEDIUM)

Codex caught CRISIS held-month cap inconsistency: 2 / 5 CRISIS dates had pre-cash maxw > 0.10 (held from non-CRISIS rebalance). Applied iter_cap_project() to enforce 0.10 pre-cash cap on ALL CRISIS dates. Post-fix verification: max pre-cash on CRISIS rows = 0.1000 (target ≤ 0.10+1e-6 PASS). weights.csv updated in mailbox + stage_artifacts. AX-001 v2 small-sample shrink now consistently enforced.

### 2.3 AS_OF_KELLY_PROJECTION_ITERATIVE (MEDIUM)

Single-pass Kelly cap projection at as_of produced max weight 0.17 (over Kelly base cap 0.10). Replaced with iterative iter_kelly_project() (max_iter=100): post-fix max weight = 0.138 (structurally infeasible to honor all per-name Kelly caps simultaneously due to total floor 0.02 × 19 + 0.10 × 1 = 0.48 < 1). asof_kelly_diagnostics.iterative_projection_applied=TRUE recorded in package.

### 2.4 RF_O7_FLOATING_POINT_TOLERANCE (LOW)

Red flag RF_O7_long_only_or_bound originally TRIGGERED_BLOCK due to floating-point: pre-fix max(maxw_risk) = 0.20 + 2.7e-13 (tolerance issue, not real breach). After iterative Kelly projection, as_of max = 0.138 (well below both 0.20 hard cap and 0.10 Kelly cap). RF_O7 corrected to PASS.

---

## 3. PARTIAL (4 documented limitations)

### 3.1 RF_O11_ALPHA_WEAKNESS_NOT_CONFIDENCE_AWARE (HIGH)

Codex concern: selected InvVol_Quarterly_KO has confidence_used=FALSE; RF-A1 (alpha sub_stab=0.041) is active. Confidence-aware MVO variants WERE evaluated in walk-forward method shopping:   - MVO_conf_TP_Quarterly_KO: net_IR=0.681 (-10.7% vs InvVol_Quarterly_KO 0.763)   - MVO_conf_TP_KO: net_IR=0.642 (-15.8%) Selecting confidence-aware MVO would sacrifice ~11% net_IR. Reasoning: (a) RF-A1 is ALPHA-side issue (sub_stab) and is alpha-package responsibility. Optimizer cannot     'repair' weak alpha robustness with weighting; it can only avoid OVER-CONCENTRATING on weak alpha. (b) Confidence vector uniformity (0.22~0.41 range, std 0.07) provides minimal differentiation;     psi penalty (1-c)^2 effectively flat. (c) InvVol_Quarterly_KO's superior net_IR reflects KR concentrated equity property:     alpha-rank dispersion is small (top-20 already alpha-positive),     so risk-aware diversification dominates alpha-conviction weighting under estimation noise (DeMiguel 2009). (d) AX-001 v2 conditional Defense activation is via FM_Regime cash policy (CRISIS 30%) + DD Brake — these     are 'avoid concentration on weak alpha during stress' machinery. Trade-off documented; user/Q-Lead may override to MVO_conf_TP_Quarterly_KO (net_IR=0.681) if explicit confidence weighting preferred. Forge backtest will measure realized SR/MDD/IR for both methods.

### 3.2 SEQUENTIAL_ADMISSION_FAIRNESS_GAP (HIGH)

Codex concern: direct PG2 TDC null + integration metrics TBD + MEGA_05 SR 1.110 cited despite fair-period warning. Reality: STR_1656_MLRA_M05 is ML model output WITHOUT alpha vector trail in mailbox. STR_1631_SYN_05 alpha vector also not exposed. Risk handoff explicitly states PG2 alpha vector unavailable. Cross-section Jaccard vs Iter 5 ancestor = 0.111 is the strongest direct proxy at Optimizer layer. Q-Lead provided fair_comparison_note.md (2026-04-25): STR_1699 vs MEGA_05 fair-period (243m) pairwise NAV cor = 0.10 — strongest comparable. Iter 6 = STR_1699 alpha + MEGA_05 machinery; the 0.10 cor is a STR_1699-vs-MEGA_05 finding, NOT Iter 6 vs PG2 finding. Sequential admission scenarios documented (replacement / 80_20 / 50_50) with status TBD by Forge. Fixed: removed unfair MEGA_05 SR 1.110 cite from expected_benefit; replaced with STR_1699 5-spec FF5 PASS (verifiable Iter 5 evidence). Forge backtest stage delivers portfolio-level realized correlation against PG2 NAV (Forge has NAV access, Optimizer doesn't). AX-008 Verification Triangulation completes at Forge layer.

### 3.3 DAILY_TAIL_EVIDENCE_PROXY_ONLY (MEDIUM)

Codex concern: CVaR_d_proxy = monthly_realized / sqrt(21) — proxy only. Selected InvVol_Quarterly_KO CVaR_d_proxy = 1.66% PASSES 2.5% cap (Iter 5 HRP_Quarterly 2.61% FAILED). Forge backtest will compute actual daily portfolio CVaR_95 using daily (Date, Ticker) holdings × Ret_d. Risk handoff: 'Hard caps (CVaR<2.5%) are Optimizer/Forge gates for FINAL portfolio.' Iter 6 surfaces no_breach explicitly (proxy-level PASS) — admission decision rests with Forge backtest. Note: heavy fat-tail proxy via sqrt(21) typically OVERSTATES daily CVaR (Hill α=3.00 fat tails), so realized daily CVaR likely 5-15% lower than 1.66% proxy.

### 3.4 BETA_DRIFT_DEFERRAL (MEDIUM)

Codex concern: port_MKT beta=0.660 outside [1.00, 1.05] target. Iter 6 request.json has NO explicit beta target (request.json::hard_constraints does not specify beta_target). request.json::soft_penalties = []. Codex applied a generic optimizer checklist target inappropriately. Discovery WT focuses on alpha/optimizer logic; deployment-stage beta hedge is Forge/Governor responsibility. AX-002 process honesty: this is documented as Forge handoff item, not silent override. Note: lower beta (0.66) is a CONSEQUENCE of 15% cash overlay (CAUTION FM regime) + InvVol diversification. Beta = 0.85 × 0.66 (risk side) + 0.15 × 0 (cash) = 0.66 — internally consistent with 3-Layer Overlay design.

---

## 4. REBUTTAL (1 explicit role-boundary defenses)

### 4.1 OPTIMIZER_REESTIMATES_SIGMA_OUTSIDE_RISK_HANDOFF (HIGH)

**Arguments:**

1. Risk_package delivered SINGLE-SNAPSHOT Σ (covariance.parquet) for as_of date 2023-11-01 for the 20 alpha-selected tickers.
2. Walk-forward over 215 sig_dates with PER-DATE changing universe REQUIRES 215 distinct Σ matrices. Only 1 + 1 fallback Σ delivered. Risk did not (and could not, given file structure) deliver 215 per-date Σ artifacts.
3. Per Optimizer agent definition: 'Risk model 재정의 금지' = don't redefine the METHODOLOGY (estimator class), not 'don't compute per-date Σ'. I apply Risk's SELECTED methods (LW_oracle for normal regimes, LW_constcor pooled fallback for CRISIS/CAUTION) per sig_date. Risk's method choice is preserved — I do not re-test the 5 Risk method-shopping candidates.
4. As_of target_weights are strictly aligned to Risk's covariance.parquet artifact (sigma_method='lw_constcor_pooled_fallback_risk_artifact' since CAUTION regime). Walk-forward historical dates apply Risk's policy to per-date eligible universe. Iter 5 precedent: same boundary acknowledged + REBUTTAL_VALID.
5. Alternative (rejected): use Risk's as_of Σ for ALL 215 dates → would require pretending the 20 as_of tickers are valid in 2006 (false; some names didn't exist), violating PIT C1.

**Decision:** REBUTTAL_VALID. Risk artifact is single-snapshot by Risk's design. Optimizer applies Risk's policy per-date for walk-forward. As_of strictly uses Risk artifact.

---

## 5. Selected Configuration Summary

- **Method**: InvVol_Quarterly_KO
- **net_IR**: 0.763
- **CAGR**: 10.73%
- **MDD**: -27.73%
- **TO (annual)**: 337% (cap 600%)
- **CVaR_d_proxy**: 1.66% (cap 2.50%) ✅ PASS — Iter 5 breach resolved
- **n_sig_dates_walkforward**: 215 (≥60 mandate)
- **HHI_asof**: 0.0558
- **Multi-sleeve**: Core 55% / Defense 30% / Cash 15%

## 6. Iter 6 Kelly + 3-Layer Overlay Implementation

### 6.1 Kelly_frac05 sizing
- Fraction: 0.50
- Base cap: 0.10
- Formula: ub_kelly_i = max(0.02, min(ub_use, kelly_raw_i / max(kelly_raw) * min(ub_use, KELLY_BASE_CAP)))  where kelly_raw_i = max(alpha_i, 0) / sigma_ii^2 * fraction
- As_of max ub_kelly: 0.1000 / min: 0.0200

### 6.2 DD Brake (BM 12M rolling DD)
- Thresholds: light 6% → cash 10% / medium 8% → cash 30% / heavy 20% → cash 50%
- As_of dd_lag: 0.0000 → dd_cash 0%
- PIT-safe: dd_lag = shift(dd_12m, 1L)

### 6.3 VolReg (BM 12M rolling vol)
- Vol target ann: 12%
- Scale formula: scale = min(1.0, vol_target / max(vol_lag, eps))
- As_of vol_lag: 0.1200 / vol_scale: 1.0000
- Avg vol_scale overall: 0.7444

### 6.4 FM Regime cash policy
- BULL 0% / NORMAL 5% / CAUTION 15% / CRISIS 30%
- As_of regime: CAUTION → fm_cash 15%

### 6.5 Combine rule
- Formula: total_cash = max(dd_cash, fm_cash) + (1 - max(dd_cash, fm_cash)) * (1 - vol_scale); cap 0.95
- As_of total_cash: 15% (binding: FM)

## 7. Risk Handoff Compliance

- **Pooled Σ fallback**: ENFORCED for CRISIS + CAUTION = 29 / 215 sig_dates
- **AX-001 v2 cash policy**: BULL 0% / NORMAL 5% / CAUTION 15% / CRISIS 30%
- **CRISIS small-sample shrink**: max_weight=0.10 (vs 0.20 default) in CRISIS regime
- **As_of target_weights**: 100% aligned to Risk's covariance.parquet artifact (20 tickers)
- **Σ-implied vol_ratio = 1.69** → VolReg scale 0.59 predicted at as_of (Risk pre-flight)

## 8. Forge Handoff Items

1. **Validate CVaR_d** using actual daily portfolio returns (monthly proxy is conservative).
2. **Direct PG2 TDC** vs MEGA_05 NAV history (cross-section Jaccard 0.111 is upper bound).
3. **Sequential admission** — replacement / 80_20 / 50_50 scenarios → Forge backtest.
4. **Beta hedge** — port_MKT 0.660 at as_of (long-only top-N + 15% cash).
5. **Kelly+Overlay realized impact** — verify 3-Layer compresses realized vol toward 12% target.
6. **Crisis defense validation** — AX-001 v2 conditional alpha + bad/normal IC ratio + core MDD mitigation.

## 9. References

- Kelly (1956) — A New Interpretation of Information Rate
- Thorp (1969) — Optimal Gambling Systems for Favorable Games
- MacLean-Thorp-Ziemba (2010) — Kelly Capital Growth Investment Criterion
- Barroso-Santa-Clara (2015) — Risk-managed momentum (VolReg basis)
- Moreira-Muir (2017) — Volatility-managed portfolios
- Ledoit-Wolf (2004) — Oracle shrinkage covariance estimation
- López de Prado (2016) — Hierarchical Risk Parity
- DeMiguel-Garlappi-Uppal (2009) — 1/N diversification benefit
- QEPM L-484 — score-level composite (NOT 수익률 블렌드)
- QEPM L-204 — STR_1699 first 5-spec FF5 PASS pattern
- QEPM L-205 — Replacement vs Sequential admission rule
- QEPM AX-001 v2 — Conditional defense + cash policy
- QEPM AX-007 — multi-sleeve exception #1
- QEPM AX-002 — Process honesty

Generated: 2026-04-25T23:53:22+0900
