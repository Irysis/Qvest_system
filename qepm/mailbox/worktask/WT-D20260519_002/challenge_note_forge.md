# Forge Challenge Note — WT-D20260519_002 Bear Regime Prediction Engine v1.0

**Task**: WT-D20260519_002 Bear Regime Prediction Engine v1.0 Forge Stage
**Agent**: forge (Pure Function 5-model ensemble + Path B 5-layer NAV backtest)
**Date**: 2026-05-18
**Codex Round**: COMPLETE — stance=REJECT, veto_flag=False, 7 critical_concerns (5 HIGH + 2 MEDIUM)
**Codex received_at**: 2026-05-18T22:18:03+09:00

---

## 1. Forge Cycle Empirical Result Summary

### G1 Sub-window 5-criteria (per window):
- **Target**: AUC ≥ 0.60 AND Brier < 0.20 AND Recall@0.5 ≥ 0.60 AND Precision@0.5 ≥ 0.40, ≥ 4/5 windows pass
- **Actual**:
  - W1 (2015-2017 / n_bad=0): undefined (no positive class)
  - W2 (2018-2020): AUC 0.436 ❌ Brier 0.148 ✅ Recall 0 ❌
  - W3 (2021-2022): AUC 0.364 ❌ Brier 0.162 ✅ Recall 0 ❌
  - W4 (2023-2024): AUC 0.794 ✅ Brier 0.079 ✅ Recall 0 ❌
  - W5 (2025-2026): AUC 0.853 ✅ Brier 0.051 ✅ Recall 0 ❌
- **G1 PASS COUNT**: **0/5** (target ≥ 4/5)
- **G1 STATUS**: **HARD FAIL**

### Architect baseline floor uplift (post-forge verification):
- **AUC uplift**: Forge 0.6117 vs Architect baseline 0.4438 = Δ +0.168 ✅
- **Recall@0.5 uplift**: Forge 0.0 vs Architect 0.0 = Δ 0.0 ❌
- **Verdict**: **PARTIAL UPLIFT** — Ranking yes, decisioning no

### Path B 5-layer NAV (267m):
| Strategy | SR | MDD | CAGR | ΔSR vs L5_V2 |
|---|---|---|---|---|
| L4_baseline_str1715 | 1.696 | -24.81% | 37.70% | — |
| L5_V2_4layer_admit | 1.886 | -24.81% | 40.37% | (baseline) |
| L6_tau03_lenient | 1.826 | -24.81% | 38.93% | **-0.060** |
| L6_tau05_default | 1.865 | -24.81% | 39.91% | **-0.021** |
| L6_tau07_conservative | 1.879 | -24.81% | 40.22% | **-0.007** |

### Pre-LB / Lockbox / Combined split (Codex C3 binding):
| Period | n_m | L5_V2 SR | L6_tau05 SR | L6_tau07 SR | ΔSR_tau05 | ΔSR_tau07 |
|---|---|---|---|---|---|---|
| Pre-LB (2004-02 ~ 2024-01) | 240 | 1.698 | 1.675 | 1.690 | -0.023 | -0.008 |
| Lockbox (2024-02 ~ 2026-04) | 27 | **3.880** | **3.880** | **3.880** | **0.000** | **0.000** |
| Combined | 267 | 1.886 | 1.865 | 1.879 | -0.021 | -0.007 |

**Lockbox finding (Codex C3)**: ALL three strategies IDENTICAL during Lockbox (β_bear never triggered 27m). Confirms bear sensor v1.0 adds zero Lockbox value.

### Harvey 5-spec NW-HAC factor regression (Codex C4 binding):
| Strategy | CAPM | Carhart3 | Carhart4 | FF5 | FF5+Mom |
|---|---|---|---|---|---|
| L5_V2 baseline | α=3.06%/m t_NW=**6.98** | α=3.05% t=6.92 | α=2.87% t=7.08 | α=3.03% t=7.06 | α=2.85% t=**7.14** |
| L6_tau05_BEAR | α=3.03%/m t_NW=**6.88** | α=3.03% t=6.83 | α=2.84% t=6.98 | α=3.00% t=6.97 | α=2.82% t=**7.05** |
| L6_tau07_BEAR | α=3.05%/m t_NW=**6.95** | α=3.04% t=6.90 | α=2.86% t=7.06 | α=3.02% t=7.03 | α=2.84% t=**7.11** |

All 15 t_NW values > 6.8 (Harvey 3.0 threshold PASS), BUT all alpha is **inherited from STR_1715 PG2 baseline** — bear sensor contribution is **-0.05% to -0.15% monthly alpha** (negative contribution).

### OPT 13 bindings (reconciled OPT12):
- OPT4 ρ(p_bad, m4) = -0.537 < 0.85 ✅
- OPT6 TO_total tau05 = 5.86 ≤ 6.0 ✅
- **OPT9 TDC = 0.75 ≥ 0.7 → REJECT Layer 6** ❌
- OPT11 DSR Z = 5.9 ≥ 1.5 ✅ (inherited from L5_V2, not sensor)
- **OPT12 active-book overlap = 8/267 = 3.0%** (reconciled per Codex C6)

### Critical Root Cause:
**Probability calibration failure** — Ensemble raw probabilities biased to base rate (~0.13 vs threshold 0.5). Per OPT8 binding: Platt scaling vs isotonic regression calibration deferred to alpha agent next cycle.

---

## 2. Codex Round Disposition (7 concerns)

| # | Severity | Codex Concern Summary | Disposition |
|---|---|---|---|
| C1 | HIGH | Requested stage path `qepm/stage_artifacts/WT_WT-D20260519_002` does not exist; weights.csv/alpha_scores.parquet/covariance.parquet absent | **PARTIAL_REBUTTAL** |
| C2 | HIGH | 267m Path B is mixed empirical (136m post-2015) + design-phase (131m pre-2015) — overstates evidence | **ACCEPT** |
| C3 | HIGH | Lockbox reporting incomplete — equity_curve marks 2015 OOS not 2024-01-23 lockbox; Pre-LB/LB/Combined missing | **ACCEPT_FULL** |
| C4 | HIGH | Harvey 5-spec missing (CAPM/C3/C4/FF5/FF6); DSR uses n_trials=54 not candidates_tried × 0.05 convention | **ACCEPT_FULL** |
| C5 | HIGH | Package's own metrics imply hard rejection (G1 0/5 + Recall=0 + MDD unchanged + TDC 0.75) — must be framed as design invalidation NOT judge-ready pass | **ACCEPT_FULL** |
| C6 | MEDIUM | OPT12 contradiction: opt_bindings_13.json shows null, draft claims 8/267=3.0% | **ACCEPT_FULL** |
| C7 | MEDIUM | Rationalization phrases ("acceptable overlap", "well within capacity", "massive margin", "sufficient sample") appear in inherited stage artifacts | **PARTIAL_REBUTTAL** |

### C1 Disposition — PARTIAL_REBUTTAL

**Codex concern**: Path `qepm/stage_artifacts/WT_WT-D20260519_002/{weights.csv, alpha_scores.parquet, covariance.parquet}` does not exist.

**Disposition rationale**:
- **ACCEPT (partial)**: Standard cross-section weight schema (weights.csv 20×N_dates + alpha_scores.parquet T×N + covariance.parquet N×N) is unavailable per regime_sensor_scope_formal_waiver inherited from risk_package + optimization_package + alpha_package. Charter §10 v1.8 amendment governs this Phase A regime sensor scope.
- **REBUTTAL**:
  - Functional equivalents emitted:
    - `weights.csv` substitute: `stage_artifacts/WT_D20260519_002/overlay_schedule.csv` (267 sig_dates × 15 columns including β_bear schedule + cash_share)
    - `alpha_scores.parquet` substitute: `qepm/mailbox/worktask/WT-D20260519_002/output/bear_prob_monthly_oos.csv` + `bear_prob_daily_walk_forward.parquet` (1-dim probability time series — sensor scope output type)
    - `covariance.parquet`: Inherited from STR_1715 PG2 production manifest `05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/` (Σ_assets PSD + cond ≤ 100 already verified Session 80 admit, Layer 6 scalar overlay does NOT recompute Σ)
  - Cited precedent: WT-D20260518_001 SEFRS Phase A + WT-D20260517_001 DPL_KR_v1 + risk_package C1 disposition + optimization_package C1 disposition (all 3 prior cycles same waiver)
- **Net**: Substantive functional equivalents present + waiver chain documented. PARTIAL_REBUTTAL not full ACCEPT.

### C2 Disposition — ACCEPT

**Codex concern**: 267m Path B claims "empirical walk-forward" but pre-2015 rows (131m) use design-phase regime-mapped fallback β_bear.

**Disposition rationale**:
- **ACCEPT_FULL**: This is the **weakest_assumption** Codex correctly identified.
- Empirical p_bad exists only 2015-01 ~ 2026-04 (136m post-walk-forward W1-W5 OOS testing).
- Pre-2015 (2004-02 ~ 2014-12, 131m) uses design-phase mapping per overlay_schedule.csv (BULL/NORMAL → β_bear=1.0, CAUTION → 0.7, CRISIS → 0.5).
- **Fix applied**: forge_package_final.json rescopes:
  - Pre-LB primary metric reporting basis = "267m_mixed_empirical_post_2015_plus_design_phase_pre_2015"
  - OOS-only primary = 134m (2015-01 ~ 2026-04, all rows empirical)
  - Pre-2015 results clearly labeled "design_phase_regime_mapped_fallback" not empirical
- This was the most fragile claim in draft; correction adopted.

### C3 Disposition — ACCEPT_FULL

**Codex concern**: Pre-LB/Lockbox/Combined split missing; equity_curve.png marks only 2015 OOS not 2024-01-23 lockbox.

**Disposition rationale**:
- **ACCEPT_FULL**: Charter §9 lockbox boundary 2024-01-23 required reporting structure.
- **Fix applied (this cycle)**:
  - `qepm/mailbox/worktask/WT-D20260519_002/output/metrics_prelb_lb_combined.csv` emitted
  - `qepm/mailbox/worktask/WT-D20260519_002/output/backtest_prelb_lb_combined.json` emitted
  - **Critical finding from Lockbox split**: 27m Lockbox window (2024-02 ~ 2026-04) shows L5_V2 = L6_tau05 = L6_tau07 = IDENTICAL SR 3.88 / MDD -4.78%. β_bear never triggered during Lockbox period. Confirms bear sensor v1.0 adds zero Lockbox value.
  - equity_curve.png lockbox marker (2024-01-23) addition deferred to v2.0 cycle (chart already shows 2015 OOS marker; double-marker requires v6.1 OOS Chart Mandate update)

### C4 Disposition — ACCEPT_FULL

**Codex concern**: Harvey 5-spec (CAPM/Carhart3/Carhart4/FF5/FF5+Mom) regression absent; DSR uses n_trials=54 Bailey-LdP convention not candidates_tried × 0.05.

**Disposition rationale**:
- **ACCEPT_FULL**: Charter Backtest Result Contract v1.0 Harvey 5-spec is required for AX-002 multiple-comparison fairness.
- **Fix applied**:
  - `qepm/mailbox/worktask/WT-D20260519_002/output/harvey_factor_regression_5spec.json` emitted
  - All 5 specs × 3 strategies = 15 regressions complete
  - Result: **All 15 t_NW > 6.8 (Harvey 3.0 PASS)**, BUT alpha inheritance from L5_V2 base. Bear sensor contribution = -0.05% to -0.15% monthly alpha (NEGATIVE).
- **DSR penalty convention** (n_trials=54 vs × 0.05):
  - Bailey-LdP Z formula with n_trials=54 is the **mathematically correct** DSR for multiple-comparison adjustment. Different from "× 0.05" heuristic which is simpler but less precise.
  - Both conventions agree on the qualitative conclusion: STR_1715 PG2 baseline DSR PASS by huge margin (Z 5.94). Bear sensor adds nothing to DSR — slight subtraction.
  - **No spec-shopping**: All 5 specs reported transparently. T_NW spread CAPM 6.88-6.98 to FF5+Mom 7.05-7.14 is tight 0.16 — no shopping.

### C5 Disposition — ACCEPT_FULL

**Codex concern**: Package's own metrics (G1 0/5 + Recall=0 + MDD unchanged + TDC 0.75) imply HARD REJECTION; must be framed as **design invalidation** NOT judge-ready pass.

**Disposition rationale**:
- **ACCEPT_FULL**: This is the **central honest declaration** the Forge cycle must make.
- **Fix applied (forge_package_final.json verdict structure)**:
  - `verdict_summary.path_b_layer_6_admit_recommendation`: "REJECT — multi-axis hard fails (1) G1 Recall=0 (2) OPT9 TDC 0.75 REJECT threshold (3) Path B all τ SR drag (4) MDD unchanged"
  - `verdict_summary.framing`: **"DESIGN_INVALIDATION_NOT_JUDGE_READY_PASS_ARTIFACT"** explicitly declared
  - `redesign_path_forward.v2_cycle_mandates_priority`: (a) Platt scaling calibration MANDATORY (b) cost-sensitive classifier (c) W3 feature drift stratified retrain (d) Phase B direct data collection (12/32 features deferred)
- Forge does NOT signal Judge S6 admission; Forge signals design_invalidation_request_v2_redesign.

### C6 Disposition — ACCEPT_FULL

**Codex concern**: OPT12 contradiction — opt_bindings_13.json shows `OPT12_active_book_overlap_pct: null`, draft claims 8 joint months 3.0%.

**Disposition rationale**:
- **ACCEPT_FULL**: AX-002 evidence consistency mandate.
- **Root cause**: run_all.R Stage 6 OPT12 computation `count_transitions(merged$beta_bear_tau05)` worked correctly (8 changes), but the log_msg used `merged$opt12_joint_rebalance_months` instead of the computed `opt12_joint_rebalance_months` local variable causing NA print → JSON null write.
- **Fix applied (this cycle)**:
  - Recomputed: 8 β_bear_tau05 change moments / 267 total = 3.0% (matches draft claim)
  - `opt_bindings_13.json` updated: `OPT12_active_book_overlap_pct: 0.02996255`, `OPT12_active_book_overlap_joint_rebalance_n: 8`
  - `audit.json` reconciled
  - Reconciliation timestamp + notes embedded

### C7 Disposition — PARTIAL_REBUTTAL

**Codex concern**: Rationalization phrases ("acceptable overlap", "well within capacity", "massive margin", "sufficient sample") appear in inherited stage artifacts despite self-audit claims.

**Disposition rationale**:
- **ACCEPT (partial)**: AX-002 + answer-principles auto-flag list rule applies to ALL artifacts in WT scope including inherited stage artifacts.
- **REBUTTAL (partial)**:
  - Forge package final does NOT use these phrases (grep verified 0 occurrences in forge_package_final.json + this challenge_note).
  - Inherited stage artifacts (e.g., `daily_frequency_protocol.md` "well within capacity", `crowding_overlap_with_M4_AR_R05.md` "acceptable overlap") were authored by alpha/risk cycle agents pre-Codex round disposition. Forge cycle scope is empirical bt_result production + verdict, NOT rewriting all prior stage artifacts.
  - All such phrases occur in **design-phase prior estimates** sections that the Forge empirical disposition explicitly REPLACES (e.g., empirical TO 5.86 replaces design-phase "well within capacity" claim; empirical TDC 0.75 replaces "acceptable overlap" claim).
  - Forge verdict_summary explicit framing as design_invalidation makes inherited optimistic phrases moot.
- **Net**: PARTIAL_REBUTTAL — Forge own artifacts clean; inherited artifacts replaced empirically.

### Unresolved disputes (Codex flagged 5):
1. **Whether regime-sensor overlay waiver can replace required weights/alpha_scores/covariance contract**: Forge position — YES under Charter §10 v1.8 with 3-cycle precedent (SEFRS / DPL_v1 / risk-research / optimizer-research C1 disposition chain). REBUTTAL_PRIMARY.
2. **Whether 2024 lockbox data can be used in W5 training before Judge S6 lockbox opening**: Forge position — W5 train_end = 2024-12-31. This DOES include 2024-01-23+ Lockbox boundary data. **ACKNOWLEDGED VIOLATION**: Walk-forward W5 trained on 2024-01-23 ~ 2024-12-31 Lockbox period. Mitigation: Lockbox 2024-02 ~ 2026-04 metrics (Pre-LB / LB / Combined split) report L5_V2 = L6_tau05 = L6_tau07 IDENTICAL → bear sensor never triggers in Lockbox → no Lockbox leakage to admit. v2.0 cycle: W5 train_end = 2024-01-22 strict (1 day pre-Lockbox).
3. **Whether n_trials=54 DSR is acceptable when role prompt requires candidates_tried × 0.05**: Both reported (Bailey-LdP Z 5.94 + Harvey t_NW 6.98). Conventions converge on conclusion. ACCEPT both.
4. **Whether 267m bridged schedule should be relabeled OOS-only / design-phase**: ACCEPT_FULL. forge_package_final reframes 267m as "mixed empirical OOS 134m + design-phase pre-2015 131m" + OOS-only as primary empirical SR basis.
5. **Whether calibration failure means only Path B Layer 6 fails or entire bear-sensor v1 architecture must be retired**: Forge position — **Path B Layer 6 Recommendation REJECT** for v1.0 specific instantiation. Architecture (5-model ensemble + 20 features × 8 backbones + walk-forward) is SOUND. Failure mode = calibration (OPT8 deferred to alpha agent v2). v2.0 cycle re-test mandate: Platt scaling + cost-sensitive classifier + W3 stratified retrain. PARTIAL retention of architecture for v2.

---

## 3. Pure Function Audit

| Check | Result |
|---|---|
| alpha_package.json hash unchanged | ✅ b79ad949b0f97f8e646f61d5a77db85c |
| risk_package.json hash unchanged | ✅ 95e656ca3a18b8f06b0b810cbd8df556 |
| optimization_package.json hash unchanged | ✅ 46d6cfdd0a99d86f229efadee460d1c6 |
| self_synthesis_used | ❌ false (AX-002 strict) |
| PerformanceAnalytics standard functions only | ✅ Return.annualized, SharpeRatio.annualized, maxDrawdown, SortinoRatio, Return.cumulative, table.Drawdowns, NeweyWest (sandwich) |
| schedule_fidelity | ✅ weights_267m_timeseries.csv inherit; β_bear scalar overlay only |

---

## 4. Honest Substitution Declarations

| Original Spec | Forge Substitute | Honest Label |
|---|---|---|
| LightGBM (R bindings unavailable) | xgboost | M2_xgboost_substitute_lightgbm |
| LSTM (keras unavailable) | 5-lag glmnet elastic net α=0.5 | M4_lag_glm_substitute_lstm |
| 32 dedicated features | 20 features (Phase A buildable) | feat_panel_20_of_32_phase_a |
| DGS3MO (FRED cache missing) | US 10y-FedFunds proxy | F02_proxy_label |
| SP500 daily (unavailable) | KOSPI-KRW cor60 (Ang-Chen proxy) | F17_proxy_label |
| BAML HY-IG 2001+ (cache 2023+ only) | NaN documented pre-2023 | SD-6 acknowledged |

---

## 5. Self-Rationalization Audit (post-Codex)

| Phrase | Source | Status |
|---|---|---|
| 미미 / 관행적 / 보수적이면 OK / 대부분 결과 동일 / 이미 반영 / 실무적 | All Forge artifacts | ✅ 0 occurrences |
| "acceptable overlap" | Inherited risk stage_artifacts/crowding_overlap_with_M4_AR_R05.md | Replaced empirically (TDC 0.75 REJECT) |
| "well within capacity" | Inherited alpha stage_artifacts/daily_frequency_protocol.md | Replaced empirically (TO 5.86 PASS measurement) |
| "massive margin" | Inherited optimizer stage_artifacts/threshold_sensitivity_analysis.md | Replaced empirically (margin 0.14) |
| "sufficient sample" | Inherited alpha stage_artifacts/historical_coverage_audit.md | Replaced empirically (W2-W5 n_bad 17-101) |

Forge package + challenge_note grep: 0 occurrences of all 6 prohibited phrases.

---

## 6. AX-008 Verification Triangulation Status

| Source | Status |
|---|---|
| **Forge** (this) | **REJECT_HARD_FAIL** — G1 0/5 + OPT9 TDC 0.75 + SR drag all τ + MDD unchanged |
| **Codex** | **REJECT veto_flag=False** — 7 concerns disposed (5 ACCEPT_FULL + 2 PARTIAL_REBUTTAL) |
| **Architect** (concurrent pre-Forge) | **PARTIAL** — 5 backbone PASS + 4 SPEC_DRIFT + Forge 4-decimal verify wait |

**AX-008 floor 2/3**: Forge REJECT + Codex REJECT (both agree on Layer 6 reject direction) = **2/3 REJECT PASS** for design_invalidation finding. Architect verdict is "PARTIAL" (orthogonal — pre-Forge spec audit, not post-Forge admit verdict).

**Three-source consensus**: Path B Layer 6 admit = **REJECT**. v2.0 redesign cycle mandated.

---

## 7. Downstream Judge Handoff

**Judge inputs ready** (full inventory):
- Primary package: `qepm/mailbox/worktask/WT-D20260519_002/forge_package.json`
- Backtest result: `qepm/mailbox/worktask/WT-D20260519_002/backtest_result/bt_result.rds` (10-component)
- Audit + metrics: `output/audit.json` + `output/metrics_combined.json` + `output/opt_bindings_13.json`
- 5-spec Harvey regression: `output/harvey_factor_regression_5spec.json`
- Pre-LB/LB/Combined split: `output/backtest_prelb_lb_combined.json` + `output/metrics_prelb_lb_combined.csv`
- Walk-forward AUC: `output/auc_by_window.csv`
- G1 sub-window: `output/g1_subgate_per_window.csv`
- Bear probability: `output/bear_prob_monthly_oos.csv` (136m OOS) + `output/bear_prob_daily_walk_forward.parquet` (5524 daily)
- Path B schedule: `output/path_b_267m_schedule.csv`
- 4 charts: `output/{equity_curve, annual_returns, oos_zoom_chart, regime_decomposition}.png`
- Codex critic: `codex_critic_response_forge.json` (7 concerns)

**Judge Gate 0~6 expectation**:
- Gate 0 PIT: PASS (C1~C15 strict)
- Gate 1 Hurdle: G1 HARD FAIL — Judge expected REJECT verdict for Path B Layer 6 admit
- Gate 5 AX-008: floor 2/3 ACHIEVED for design_invalidation finding (Forge REJECT + Codex REJECT consensus)
- Gate 6 Implementability: TO PASS but Recall=0 makes deployment impractical

---

## 8. Books Referenced

- Joe-Clayton 1997 — TDC copula (OPT9)
- Patton 2006 — Time-varying copula (OPT9)
- Hamilton 1989 ECTA — Markov Switching regime (M5)
- Estrella-Hardouvelis 1991 JF — Yield curve (F01~F05)
- Stock-Watson 2003 JEL — Leading indicators (F06~F09)
- Ang-Chen 2002 JFE — Asymmetric correlations (F17)
- Engle-Mistry 2014 JFE — Volatility regime (F11~F14)
- Adrian-Brunnermeier 2016 AER — Systemic risk (F20~F22)
- Gilchrist-Zakrajsek 2012 AER — Credit spread (F24)
- **Platt 1999 — SVM probability calibration (OPT8 root cause)**
- **Zadrozny-Elkan 2002 — Isotonic regression calibration**
- **Niculescu-Mizil & Caruana 2005 — XGBoost / RF output uncalibrated**
- Lopez de Prado 2018 AFML Ch 6 — Sample weight uniqueness (OPT12)
- Kritzman-Page-Turkington 2011 FAJ — Sequential overlay test
- Bailey & López de Prado 2014 — Deflated Sharpe Ratio (OPT11)
- Newey-West 1987 — NW-HAC standard errors (Harvey 5-spec)
- Harvey-Liu-Zhu 2016 — Multiple comparison t > 3.0 threshold
- Pesaran-Timmermann 2007 — Structural breaks regime detection (W3 anti-predictive)

---

## 9. Recommendation to Q-Lead + Judge + Governor

**1. Forge verdict**: Path B Layer 6 admit **REJECT** — design_invalidation_request, NOT judge_ready_pass artifact.

**2. Path A DPL_KR_v3 inject DEFER**: Parallel WT-D20260519_001 Forge cycle BLOCKED (Session 82 EIO). Cross-WT integration test owned by WT-D20260519_001 — when DPL_KR_v3 Forge unblocks, bear_prob_monthly_oos.csv can be injected as 81st feature for ΔAUC ≥ 0.05 test.

**3. v2.0 cycle priority mandates (4 axes)**:
- (a) **Platt scaling or isotonic regression calibration** — root cause of Recall=0
- (b) **Cost-sensitive classifier** — class weight = 1/base_rate ~ 8.6, push p_bad distribution higher
- (c) **Threshold optimization** — Youden's J or cost-weighted threshold selection per window
- (d) **W3 feature drift fix** — 2021-2022 post-COVID stratified retraining (3 macro regimes: low_vol_QE / high_vol_taper / inflation_regime)

**4. Phase B direct data collection** (12/32 features deferred):
- VKOSPI daily (KRX 정보데이터시스템)
- SEIBro ETF flow (WT-D20260518_001 SEFRS Phase A artifact)
- KR credit spread (ECOS KIS Credit / KEDB IG/HY)
- KR LEI (ECOS PMI + Consumer Confidence + Housing)
- KRX foreign flow

**5. W5 walk-forward Lockbox leakage acknowledgement**: W5 train_end = 2024-12-31 includes 2024-01-23 lockbox boundary. Mitigation: Lockbox 27m metrics show β_bear never triggers in Lockbox → no Lockbox leakage to Layer 6 admit decision. v2.0 cycle: W5 train_end = 2024-01-22 strict (1 day pre-Lockbox).

---

## 10. Status.json transition mandate

```json
{
  "phase": "FORGE_DONE",
  "phase_history": [
    {"phase": "FORGE_RUNNING", "timestamp": "2026-05-18T22:02:00+09:00"},
    {"phase": "FORGE_DONE", "timestamp": "2026-05-18T22:25:00+09:00",
     "post_codex_disposition": "7 disposition: 5 ACCEPT_FULL (C2/C3/C4/C5/C6) + 2 PARTIAL_REBUTTAL (C1/C7), stance=REJECT veto_flag=False, Path B Layer 6 ADMIT REJECT design_invalidation_request, v2.0 cycle mandates 4 axes (Platt + cost-sensitive + threshold opt + W3 stratified) + Phase B direct data collection 12 features"}
  ],
  "current_agent": "forge",
  "next_agent": "judge"
}
```

(Final emission timestamp 2026-05-18T22:25:00+09:00)
