# Bear Regime Prediction Engine v2.0 — Admission Protocol

## 1. v2.0 vs v1.0 — Decision Gates Update

| Gate | v1.0 (WT-D20260519_002) | v2.0 (WT-D20260518_001) | Rationale |
|---|---|---|---|
| **G0_PIT** | C1~C15 strict | C1~C15 strict + Phase B feature audit | PIT C11 publish-lag explicit per PB01~PB12 |
| **G1 AUC** | ≥ 0.60 in 4/5 | ≥ 0.60 in 4/5 (unchanged) | v1.0 actual 0.6117 mean → ranking power exists |
| **G1 Brier** | < 0.20 in 4/5 | **< 0.15 in 4/5** (TIGHTENED) | Post-calibration target lower, ECE bound |
| **G1 Recall@τ** | ≥ 0.60 in 4/5 at τ=0.5 | **≥ 0.60 in 4/5 at τ_optimal (Youden's J)** | v1.0 root cause fix — τ=0.5 degenerate |
| **G1 Precision@τ** | ≥ 0.40 in 4/5 at τ=0.5 | **≥ 0.40 in 4/5 at τ_optimal** | same — calibrated threshold |
| **G1 sub-window stability** | 4/5 | **4/5** (unchanged) | v1.0 actual 0/5 → catastrophic; v2.0 calibration should restore |
| **G1_NEW Calibration ECE** | not measured | **< 0.10 mean** | NEW gate — calibration audit |
| **G2 Economic Significance** | Diebold-Mariano test vs persistence | same | unchanged |
| **G3 Feature Stability** | Gini < 0.5 + top-10 overlap ≥ 0.6 | same | unchanged |
| **G4 DSR** | Bailey-LdP Z ≥ 1.5 (n_trials=20) | Bailey-LdP Z ≥ 1.5 (**n_trials=90 v2.0 binding**) | 90 = 5 models × 3 calibration × 2 threshold × 3 strata |
| **G5 Integration** | DPL ΔAUC ≥ 0.05 OR standalone | same | unchanged |
| **G6 AX-008** | Forge + Codex + Architect ≥ 2/3 | same | unchanged |

## 2. v2.0 New Gate: G1.5 Calibration Audit

Inserted between G1 and G2 (Forge Stage 4 binding):

| Sub-gate | Criterion | Pass threshold | v1.0 baseline |
|---|---|---|---|
| **G1.5a ECE** | Expected Calibration Error per window | < 0.10 mean across 5 windows | not measured |
| **G1.5b Reliability Diagram** | calibration curve slope close to 1 | slope ∈ [0.7, 1.3] in 4/5 windows | not measured |
| **G1.5c p_max_bear_class** | max p_bad in true bear months | ≥ 0.5 in 4/5 windows | v1.0 actual 0.397 (FAIL) |
| **G1.5d p_mean_separation** | mean(p_bear) - mean(p_non_bear) | ≥ 0.10 in 4/5 windows | v1.0 actual -0.01 (degenerate, FAIL) |

**G1.5 binding**: If 3 of 4 sub-gates fail → re-train calibrator with different method (Platt → isotonic → Beta). If all 3 calibration methods fail G1.5 → Phase B feature insufficient signal, document and abort.

## 3. v2.0 Failure Cutoffs

| Cutoff | Trigger | Action |
|---|---|---|
| **G1 hard fail (0/5 pass)** | Recall@τ_optimal = 0 in all 5 windows | HARD ABORT — calibration paradigm insufficient, document and retire v2.0 |
| **G1.5 calibration fail** | 3 of 4 sub-gates fail with all calibration methods | HARD ABORT — feature signal insufficient |
| **Synthetic detection (Codex)** | self_synthesis_used = true detected | HARD ABORT — AX-002 violation |
| **Phase B fetch fail** | ≥ 5 of 12 features fail Path A+B+C | DEGRADE to N<27 features, document, continue if N ≥ 24 |
| **Codex REJECT veto=true** | Codex Stage 3 critic returns veto_flag=true | DEFER — Q-Lead escalate |

## 4. Production Promotion Eligibility (post-Forge)

For v2.0 to admit to PG1 → PG2:
- **G1 5-subgate ≥ 4/5 windows pass** AND
- **G1.5 calibration audit pass** (ECE < 0.10 mean) AND
- **G4 DSR Bailey-LdP Z ≥ 1.5 with n_trials=90** AND
- **G6 AX-008 ≥ 2/3** (Forge + Codex + Architect) AND
- **EITHER**
  - Path A: DPL_KR_v3 integration ΔAUC ≥ 0.05 (downstream WT-D20260519_001 Forge cycle)
  - OR Path B: Standalone admit STR_1715 PG2 Layer 6 with TO ≤ 6.0/yr + DSR Z ≥ 1.5 + MDD improvement vs L5_V2 baseline (v1.0 Path B all τ SR drag — v2.0 must demonstrate uplift)

## 5. Lockbox Sealing Protocol (PIT scope)

Per `.claude/rules/lockbox-scope.md`:
- **alpha-research (this cycle)**: SIGNAL_CUTOFF = `as.Date("2024-01-22")` hardcoded — 1 BD pre-Lockbox boundary (v1.0 W5 train_end fix from challenge_note_forge)
- **Walk-forward windows**:
  - W1: 1990-01 ~ 2014-12 train / 2015-01 ~ 2017-12 test
  - W2: 1990-01 ~ 2017-12 train / 2018-01 ~ 2019-12 test
  - W3: 1990-01 ~ 2019-12 train / 2020-01 ~ 2021-12 test
  - W4: 1990-01 ~ 2021-12 train / 2022-01 ~ 2023-12 test
  - W5: **train_end = 2024-01-22 strict** (1 BD pre-Lockbox) / test = 2024-01-23 ~ 2026-04-30 (Lockbox-aware)
- **Forge / monitoring / Q-Lead**: SIGNAL_CUTOFF = `max(sig_date)` — Lockbox 폐기 (lockbox-scope.md mandate)

## 6. Codex Round Cadence

### This cycle (alpha-research Stage 4):
- Codex critic spawns post `alpha_package_draft.json` write
- 5-stage flow: draft → codex auto → challenge_note → final
- AX-008 status post alpha cycle: 0/3 → 1/3 (Codex contribution)

### Forge cycle (TBD, separate WT or continued under same WT):
- Codex critic spawns post `forge_package_draft.json` write
- AX-008 status post Forge: 1/3 → 2/3 (target)
- Architect concurrent verification: AX-008 2/3 → 3/3 (target)

## 7. Honest Phase A Disclosure (Charter v1.8 §10)

This alpha-research cycle is **`discovery_design_phase_a`** scope (inherit v1.0 Charter v1.8 amendment):
- own_deliverables: alpha_package.json + 4 design protocols + challenge_note
- exempt_deliverables: alpha_vector / alpha_scores.parquet / Forge metrics (Forge cycle output)
- deferred_to_forge_cycle: 6 stages (data fetch + feature build + train + ensemble + Architect + integration test)

**G9 Codex pass = phase_a_design_only_evaluation** (inherit v1.0 paradigm). Alpha admission cert発급 = Forge cycle Stage 4 후 별도 Codex Round.

## 8. v1.0 Lineage Inherit (Charter §10 Role Card)

| Inherit from | Component | v2.0 Action |
|---|---|---|
| WT-D20260519_002 | 8-academic-backbone feature catalog (20 built) | RETAIN — base catalog |
| WT-D20260519_002 | Strategy A vs B vs C parallel benchmark (Codex C5) | RETAIN — Strategy B 2001+ mandatory |
| WT-D20260519_002 | feature_usable_date_table 32 entries | RETAIN + ADD PB01-PB12 (44 total) |
| WT-D20260519_002 | 5-model ensemble (Logistic L1, LightGBM, RandomForest, LSTM, MarkovSwitching) | RETAIN |
| WT-D20260519_002 | DSR n_trials accounting (20 → **90** v2.0) | UPDATE per Section 3 above |
| WT-D20260519_002 | Path A (DPL_KR_v3 integration) | RETAIN |
| WT-D20260519_002 | Path B (STR_1715 PG2 Layer 6) | RETAIN — but must demonstrate uplift (v1.0 SR drag) |

**Calibration + cost-sensitive + threshold opt + W3 stratified = NEW v2.0**. These 4 axes are NOT inherited from v1.0 — they are the **root cause fixes**.

## 9. References

- **Pesaran, M. H., & Timmermann, A. (2007)**. Selection of estimation window in the presence of breaks. *J. Econometrics* (Axis 4 stratified)
- **Bailey, D. H., & López de Prado, M. (2014)**. The deflated Sharpe ratio: correcting for selection bias, backtest overfitting and non-normality. *J. Portfolio Management* (G4 DSR)
- **Harvey, C. R., Liu, Y., & Zhu, H. (2016)**. ... and the cross-section of expected returns. *RFS* (multiple testing)
- **Diebold, F. X., & Mariano, R. S. (1995)**. Comparing predictive accuracy. *J. Business & Economic Statistics* (G2 economic significance)
- Charter v1.8 §10 Role Card (discovery_design_phase_a precedent from WT-D20260519_002 inherit)
