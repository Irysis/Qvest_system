# K-RAMP Codex Ideal Operating Process Guide v1.0

> **Recommended path in repository**: `docs/CODEX_IDEAL_OPERATING_PROCESS.md`  
> **Use with**: `AGENTS.md` / `docs/K_RAMP_SYSTEM_CONSTITUTION.md`  
> **System**: K-RAMP — Korea Regime-Aware Multi-Factor Portfolio Management System  
> **Purpose**: Convert the K-RAMP constitutional blueprint into a repeatable Codex operating procedure.  
> **Core idea**: Codex must not behave as a one-shot code generator. Codex must behave as a governed quantitative research architect that observes the repository, diagnoses the current gate, implements the smallest testable architecture increment, scores constitutional compliance, documents the change, and either promotes or reverts the increment.

---

# 0. How Codex Must Use This Guide

This guide is a companion document to the K-RAMP master constitution.

If this file conflicts with `AGENTS.md`, the following priority order applies:

1. `AGENTS.md` at repository root.
2. `docs/K_RAMP_SYSTEM_CONSTITUTION.md`.
3. `docs/CODEX_IDEAL_OPERATING_PROCESS.md`.
4. Other local module-level `AGENTS.md` files.
5. User task instructions for the current task.

However, if the user gives a direct instruction that weakens data integrity, look-ahead prevention, transaction-cost realism, capacity realism, robustness testing, explainability, or governance, Codex must refuse the weakening and propose a safe implementation alternative.

Codex must treat this document as an operating manual. Do not merely summarize it. Convert it into repository structure, code, tests, reports, and gate decisions.

---

# 1. Operating Identity

## 1.1 Codex role

Codex is the principal software architect, quantitative developer, test engineer, documentation steward, and governance assistant for K-RAMP.

Codex must perform every task under the following identity:

```text
I am not building attractive backtests.
I am building a governed QEPM operating system.
The system must survive data-mining pressure, regime overfitting, cost underestimation, capacity errors, and unexplained allocation decisions.
```

## 1.2 What Codex must optimize

Codex must optimize in this order:

1. Data integrity.
2. Point-in-time safety.
3. Bias defense.
4. Pure-factor-first architecture.
5. Transaction-cost and capacity realism.
6. Robustness and out-of-sample verification.
7. Risk decomposition completeness.
8. Investor-agent explainability.
9. Reproducibility.
10. Runtime performance.
11. Dashboard usability.
12. Incremental strategy complexity.

Codex must not optimize first for Sharpe ratio, CAGR, hit ratio, or maximum historical performance.

## 1.3 Forbidden development behaviors

Codex must not:

- Directly select the best-performing strategy from the 2,000-strategy pool.
- Treat 2,000 strategies as 2,000 independent alpha sources.
- Build M-code portfolios before approved pure factors and factor groups exist.
- Use the regime engine as a hard switch.
- Build an investor agent that cannot explain every allocation decision.
- Ignore gross versus net return distinction.
- Ignore transaction costs, turnover, slippage, or capacity.
- Ignore look-ahead bias, survivorship bias, or data revision bias.
- Add functionality without tests.
- Add architecture-changing code without documentation or an ADR.
- Proceed to the next gate when the current gate fails hard constraints.

---

# 2. Canonical Codex Work Loop

Every task must be handled through the following loop:

```text
Observe
  -> Diagnose
  -> Propose
  -> Implement
  -> Test
  -> Score
  -> Document
  -> Promote / Revert / Quarantine
```

This loop is mandatory for every non-trivial task.

## 2.1 Observe

Codex must inspect the repository before modifying it.

Minimum observation checklist:

```text
- Current working directory
- Existing files and directories
- Existing AGENTS.md files
- Existing config files
- Existing tests
- Existing docs
- Existing data contracts
- Existing outputs
- Existing milestone reports
- Existing architecture gap logs
- Existing evaluation history
```

Recommended commands:

```bash
pwd
ls
tree -a -L 3 || find . -maxdepth 3 -type f | sort
find . -name AGENTS.md -print
find . -maxdepth 3 -type f \( -name "*.yml" -o -name "*.yaml" -o -name "*.json" -o -name "*.md" \) | sort
```

Codex must not assume the repository is empty.

## 2.2 Diagnose

Codex must determine:

```text
1. Which K-RAMP gate is currently active?
2. What artifacts are required for this gate?
3. Which required artifacts already exist?
4. Which hard constraints are missing or violated?
5. Which compliance score is currently the weakest?
6. What is the smallest testable change that improves the system?
```

The diagnosis must be recorded in a short process note or milestone report.

## 2.3 Propose

Before implementation, Codex must create a concise implementation proposal.

Proposal format:

```markdown
## Proposed Increment

Current gate: Gate X - <name>
Primary gap: <gap>
Smallest safe increment: <increment>
Files to add/update:
- <file>
- <file>
Tests to run:
- <test>
Expected compliance score impact:
- <score>: +<expected improvement>
Hard constraints touched:
- <constraint>
Rollback plan:
- <plan>
```

For small changes, this can be brief. For architecture changes, this must be written to `00_Lawbook/K_RAMP/adr/ADR-YYYYMMDD-<short-title>.md`.

## 2.4 Implement

Implementation rules:

- Prefer small, composable modules.
- Prefer typed schemas and explicit configuration.
- Keep R and Python responsibilities separated by module boundary.
- Use Parquet, CSV, JSON, YAML, or clear APIs at R/Python boundaries.
- Do not hide assumptions in code.
- Put thresholds in config files, not hard-coded logic.
- Keep deterministic seeds for synthetic data and tests.
- Preserve existing user work.

## 2.5 Test

Codex must run the relevant tests after every implementation increment.

Minimum test stack:

```bash
# Python
python -m pytest tests/python

# R
Rscript -e "testthat::test_dir('tests/R/testthat')"
```

If the environment is incomplete, Codex must create or update environment-check scripts rather than silently skipping tests.

## 2.6 Score

Codex must update the K-RAMP compliance score after each meaningful increment.

Required score outputs:

```text
outputs/governance/constitution_compliance_report.md
outputs/json/constitution_compliance_score.json
outputs/governance/gate_review_report.md
outputs/governance/evaluation_history.csv
```

Codex must compute or update the following score families:

| Score | Meaning |
|---|---|
| `ACS` | Architecture Coverage Score |
| `DCCS` | Data Contract Compliance Score |
| `BDS` | Backtest Bias Defense Score |
| `PFIS` | Pure Factor Integrity Score |
| `SDS` | Strategy De-duplication Score |
| `RDDS` | Robustness and Data-Mining Defense Score |
| `CCS2` | Cost and Capacity Score |
| `RMCS` | Risk Manager Completeness Score |
| `IAES` | Investor Agent Explainability Score |
| `RS` | Reproducibility Score |
| `DGS` | Documentation and Governance Score |
| `RIDS` | Recursive Improvement Discipline Score |
| `CCS` | Constitution Compliance Score, aggregate |

Suggested aggregate formula:

```text
CCS = weighted_mean(
  ACS, DCCS, BDS, PFIS, SDS, RDDS, CCS2, RMCS, IAES, RS, DGS, RIDS
)
```

Hard constraints override aggregate score. If a hard constraint fails, the gate fails even if aggregate `CCS` is high.

## 2.7 Document

Every meaningful implementation must update at least one of:

```text
docs/ARCHITECTURE_BLUEPRINT.md
docs/ARCHITECTURE_ROADMAP.md
docs/DATA_DICTIONARY.md
docs/VALIDATION_POLICY.md
docs/FACTOR_APPROVAL_POLICY.md
docs/MCODE_POLICY.md
docs/RISK_MANAGER_POLICY.md
docs/INVESTOR_AGENT_POLICY.md
docs/RECURSIVE_DEVELOPMENT_PROTOCOL.md
00_Lawbook/K_RAMP/adr/ADR-*.md
outputs/governance/milestone_report_*.md
```

Codex must keep implementation and documentation synchronized.

## 2.8 Promote, revert, or quarantine

After testing and scoring, Codex must decide:

```text
PROMOTE: Tests passed, score improved or stayed compliant, no hard violations.
REVERT: Tests failed or hard constraints violated and no safe fix is available in this increment.
QUARANTINE: Work is partially useful but incomplete; isolate it behind feature flags or experimental folders.
```

Quarantined modules must not be part of production pipelines.

---

# 3. Gate Detection Protocol

Codex must identify the current gate from repository evidence.

| Gate | Name | Repository evidence |
|---:|---|---|
| 0 | Constitution Parsing | Constitution docs and requirement map absent or incomplete |
| 1 | Repository and Environment | Repo skeleton, package files, CI/test setup absent or incomplete |
| 2 | Synthetic Data and Data Contract | Synthetic data, schema, and validation absent or incomplete |
| 3 | Strategy Inventory | Strategy metadata, returns matrix, overlay tags, de-dup reports absent or incomplete |
| 4 | Pure Factor Factory | Pure factor extraction, neutralization, validation, lineage absent or incomplete |
| 5 | Factor Group and Regime Mapping | Factor clustering and regime-conditional matrix absent or incomplete |
| 6 | M-code Factory | M0 and initial M-code specs/returns/holdings absent or incomplete |
| 7 | Risk Manager | M-code risk decomposition and risk flags absent or incomplete |
| 8 | Investor Agent | Explainable allocation engine absent or incomplete |
| 9 | Integrated Backtest | End-to-end simulation absent or incomplete |
| 10 | Dashboard and Monitoring | Shiny/dashboard/reporting absent or incomplete |
| 11 | Recursive Governance | Recursive gap detection, self-improvement loop, evaluation history absent or incomplete |

If repository evidence is ambiguous, Codex must select the earliest plausible incomplete gate.

---

# 4. Gate-by-Gate Ideal Operating Process

## Gate 0. Constitution Parsing Gate

### Goal

Convert the K-RAMP blueprint into explicit, machine-checkable requirements.

### Entry condition

One or more of the following is missing:

```text
AGENTS.md
docs/K_RAMP_SYSTEM_CONSTITUTION.md
config/system_constitution.yml
config/validation_thresholds.yml
outputs/json/constitution_requirement_map.json
outputs/governance/constitution_compliance_report.md
```

### Codex actions

1. Read the master prompt and constitution.
2. Extract all hard constraints.
3. Extract all soft preferences.
4. Convert requirements into YAML and JSON.
5. Create a constitution compliance evaluator skeleton.
6. Create first compliance report.

### Required outputs

```text
AGENTS.md
docs/K_RAMP_SYSTEM_CONSTITUTION.md
docs/CODEX_IDEAL_OPERATING_PROCESS.md
config/system_constitution.yml
config/validation_thresholds.yml
outputs/json/constitution_requirement_map.json
outputs/governance/constitution_compliance_report.md
```

### Minimum hard constraints

```yaml
hard_constraints:
  no_lookahead_bias: true
  no_survivorship_bias: true
  point_in_time_data_required: true
  pure_factor_first: true
  no_direct_best_backtest_selection: true
  no_regime_hard_switching: true
  transaction_cost_required: true
  capacity_required: true
  investor_agent_explainability_required: true
  tests_required_before_gate_promotion: true
  documentation_required: true
```

### Gate 0 pass criteria

```text
ACS >= 80
DGS >= 80
RIDS >= 70
No missing hard-constraint definitions
```

---

## Gate 1. Repository and Environment Gate

### Goal

Create a reproducible R + Python repository skeleton.

### Codex actions

1. Create repository directories.
2. Add Python package structure.
3. Add R scripts and testthat structure.
4. Add environment check scripts.
5. Add seed management.
6. Add linting or formatting conventions if feasible.
7. Create initial README.

### Required structure

```text
K-RAMP/
  AGENTS.md
  README.md
  pyproject.toml
  requirements.txt
  DESCRIPTION
  config/
  data_raw/
  data_processed/
  data_synthetic/
  docs/
  00_Lawbook/K_RAMP/adr/
  python/kramp/
    __init__.py
    data/
    strategy/
    factor/
    regime/
    mcode/
    risk/
    agent/
    governance/
  R/
    data_validation.R
    factor_diagnostics.R
    performance_analytics.R
    shiny_modules/
  scripts/python/
  scripts/R/
  tests/python/
  tests/R/testthat/
  outputs/
    governance/
    json/
    reports/
    factor/
    mcode/
    risk/
    agent/
```

### Language boundary rule

Use Python for:

```text
- orchestration
- schemas
- validators
- optimization engines
- test harnesses
- governance scoring
- pipeline execution
```

Use R for:

```text
- research diagnostics
- tidyverse workflows
- PerformanceAnalytics outputs
- Shiny dashboards
- finance-specific reporting
```

Use Parquet or clearly defined files between R and Python.

### Gate 1 pass criteria

```text
ACS >= 85
RS >= 80
DGS >= 80
Environment check scripts exist
Basic Python and R tests can run or fail with documented missing dependencies
```

---

## Gate 2. Synthetic Data and Data Contract Gate

### Goal

Build a testable data contract before using real user data.

### Codex actions

1. Define schema for all core data tables.
2. Generate synthetic data that mimics Korean equity panel structure.
3. Validate date keys, ticker keys, universe membership, and signal availability.
4. Create no-lookahead tests.
5. Create point-in-time availability tests.

### Required data tables

```text
prices
universe_membership
fundamentals
strategy_meta
strategy_returns
strategy_holdings
factor_signals
regime_probabilities
benchmarks
risk_free_rates
corporate_actions
trading_calendar
```

### Required schema fields

#### `prices`

```text
date
ticker
open
high
low
close
adjusted_close
volume
trading_value
return_1d
source
asof_timestamp
```

#### `fundamentals`

```text
ticker
fiscal_period_end
announcement_date
data_available_date
metric_name
metric_value
source
asof_timestamp
```

#### `strategy_meta`

```text
strategy_id
strategy_name
signal_family
universe
weighting_method
rebalance_frequency
overlay_flag
cost_model_flag
holdings_available
expected_turnover
capacity_proxy
created_at
version
```

#### `strategy_returns`

```text
date
strategy_id
gross_return
net_return
turnover
cost_estimate
universe
version
```

#### `strategy_holdings`

```text
date
strategy_id
ticker
weight
signal_score
sector
market_cap
adv_20d
version
```

#### `regime_probabilities`

```text
date
regime_id
regime_name
probability
confidence
model_version
```

### Required tests

```text
test_required_columns
test_primary_key_uniqueness
test_no_future_dates
test_signal_date_before_rebalance_date
test_fundamental_data_available_before_use
test_universe_membership_as_of_date
test_gross_net_return_distinction
test_regime_probability_sum_to_one
test_no_negative_trading_value
test_missing_value_policy
```

### Gate 2 pass criteria

```text
DCCS >= 95
BDS >= 85
RS >= 85
All schema tests pass on synthetic data
```

---

## Gate 3. Strategy Inventory Gate

### Goal

Convert the 2,000-strategy pool into a structured, auditable inventory.

### Codex interpretation

The 2,000 strategies are not verified alpha sources. They are contaminated raw materials that may contain:

```text
- duplicate signals
- overlapping holdings
- hidden overlays
- timing filters
- volatility targeting
- stop-loss rules
- rebalance artifacts
- cost omissions
- universe effects
- liquidity distortions
- data-mined parameter choices
```

### Codex actions

1. Load strategy metadata.
2. Validate strategy return matrix.
3. Validate holdings if available.
4. Tag overlays.
5. Estimate strategy similarity.
6. Group strategy families.
7. Produce de-duplication report.

### Required outputs

```text
data_processed/strategy_inventory.parquet
data_processed/strategy_return_matrix.parquet
data_processed/strategy_overlay_summary.parquet
data_processed/strategy_similarity_matrix.parquet
outputs/reports/strategy_deduplication_report.md
outputs/json/strategy_family_map.json
```

### Required similarity diagnostics

```text
return_correlation
holdings_overlap
factor_exposure_distance
drawdown_correlation
turnover_similarity
universe_similarity
rebalance_similarity
```

### Strategy family grouping rule

A strategy pair should be considered likely duplicate or near-duplicate when at least two of the following hold:

```text
return_correlation > 0.90
holdings_overlap > 0.70
drawdown_correlation > 0.80
factor_exposure_distance < configured_threshold
same_signal_family == true
same_universe == true
```

### Gate 3 pass criteria

```text
SDS >= 85
DCCS >= 95
BDS >= 90
Strategy inventory coverage >= 95% of supplied strategies
Overlay tagging coverage >= 90%
```

---

## Gate 4. Pure Factor Factory Gate

### Goal

Extract pure factors before building M-code portfolios.

### Codex interpretation

A pure factor is not a good backtest. A pure factor is a repeatable, economically interpretable signal whose performance remains after controlling for construction effects, overlay effects, cost effects, and standard risk exposures.

### Codex actions

1. Rebuild raw factor signals where possible.
2. Strip overlays.
3. Standardize universe, rebalance frequency, weighting rule, and cost model.
4. Neutralize unwanted exposures where required.
5. Compute IC, rank IC, spread returns, turnover, cost drag, and capacity.
6. Run robustness diagnostics.
7. Assign factor approval status.
8. Record factor lineage.

### Pure factor model

Use a decomposition similar to:

```text
Strategy Return
  = Pure Factor Return
  + Construction Effect
  + Overlay Effect
  + Cost Effect
  + Residual Noise
```

Return-based fallback model when only strategy returns are available:

```text
r_strategy,t = alpha
             + beta_value * r_value,t
             + beta_momentum * r_momentum,t
             + beta_quality * r_quality,t
             + beta_lowvol * r_lowvol,t
             + beta_size * r_size,t
             + beta_liquidity * r_liquidity,t
             + epsilon_t
```

### Required outputs

```text
data_processed/pure_factor_returns.parquet
data_processed/pure_factor_scores.parquet
data_processed/factor_lineage.parquet
data_processed/factor_validation_metrics.parquet
data_processed/approved_factor_library.parquet
outputs/reports/pure_factor_extraction_report.md
outputs/reports/factor_validation_report.md
```

### Required factor diagnostics

```text
rank_ic_mean
rank_ic_vol
rank_icir
quintile_spread_gross
quintile_spread_net
hit_ratio
monotonicity_score
turnover
cost_drag
capacity_score
beta_to_market
size_exposure
sector_exposure
liquidity_exposure
drawdown
expected_shortfall
parameter_stability
subperiod_stability
regime_stability
```

### Gate 4 pass criteria

```text
PFIS >= 90
RDDS >= 85
CCS2 >= 85
No approved factor may have missing lineage
No approved factor may omit net-of-cost diagnostics
```

---

## Gate 5. Factor Group and Regime Mapping Gate

### Goal

Group approved pure factors into economically and statistically coherent factor families, then estimate regime-conditional return and risk.

### Codex actions

1. Construct factor distance matrix.
2. Cluster pure factors into factor groups.
3. Assign economic labels only after statistical clustering.
4. Estimate unconditional factor group return/risk.
5. Estimate regime-conditional factor group return/risk.
6. Validate that regime engine is used as soft conditional information, not hard switch.

### Factor distance model

```text
D_ij = w1 * (1 - corr(factor_return_i, factor_return_j))
     + w2 * (1 - corr(signal_i, signal_j))
     + w3 * (1 - holdings_overlap_i_j)
     + w4 * exposure_distance_i_j
     + w5 * regime_behavior_distance_i_j
```

Weights must come from config.

### Regime blending rule

Codex must implement soft blending:

```text
mu_blended_i,t
  = (1 - regime_confidence_t) * mu_unconditional_i
  + regime_confidence_t * sum_s P(S_t = s) * mu_i,s
```

Hard switching is prohibited unless explicitly marked as an experimental stress test and excluded from production.

### Required outputs

```text
data_processed/factor_distance_matrix.parquet
data_processed/factor_group_map.parquet
data_processed/factor_group_returns.parquet
data_processed/regime_factor_matrix.parquet
outputs/reports/factor_grouping_report.md
outputs/reports/regime_factor_mapping_report.md
```

### Gate 5 pass criteria

```text
PFIS >= 90
RDDS >= 90
BDS >= 90
Regime probabilities must sum to 1 by date
No hard-switch production allocation
```

---

## Gate 6. M-code Factory Gate

### Goal

Build role-specific M-code portfolios from approved factor groups.

### Codex interpretation

M-codes are not performance-ranked strategy combinations. M-codes are governed portfolio modules with distinct roles, risk budgets, expected regimes, forbidden regimes, cost models, and validation status.

### Required initial M-codes

| M-code | Role |
|---|---|
| `M0` | Baseline diversified multi-factor portfolio |
| `M1` | Defensive quality / low-risk portfolio |
| `M2` | Offensive momentum / growth portfolio |
| `M3` | Recovery value / reversal portfolio |
| `M4` | Neutral core multi-factor portfolio |

### Required M-code specification fields

```text
mcode_id
mcode_name
investment_hypothesis
universe
benchmark
factor_groups
construction_rule
weighting_rule
rebalance_frequency
cost_model
capacity_model
risk_budget
expected_regimes
forbidden_regimes
max_turnover
max_single_name_weight
max_sector_deviation
max_factor_exposure
validation_status
version
created_at
```

### M-code objective function

Baseline form:

```text
maximize_w:
  w' * mu
  - lambda / 2 * w' * Sigma * w
  - kappa * transaction_cost(delta_w)
  - eta * constraint_penalty(w)
```

Subject to:

```text
sum(w) = 1
0 <= w_i <= max_weight
sector_deviation <= limit
turnover <= limit
liquidity_usage <= limit
factor_exposure <= limit
```

### Required outputs

```text
data_processed/mcode_specs.parquet
data_processed/mcode_returns.parquet
data_processed/mcode_holdings.parquet
data_processed/mcode_exposures.parquet
outputs/reports/mcode_development_report.md
outputs/reports/mcode_validation_report.md
```

### Gate 6 pass criteria

```text
ACS >= 90
PFIS >= 90
CCS2 >= 90
RDDS >= 90
M0 exists and is used as baseline
Each M-code has role, hypothesis, constraints, and validation status
```

---

## Gate 7. Risk Manager Gate

### Goal

Build a risk manager that decomposes performance, risk, exposure, costs, liquidity, and model risk for all M-codes and final portfolios.

### Codex interpretation

The risk manager diagnoses. It does not allocate capital.

### Codex actions

1. Compute M-code performance metrics.
2. Compute risk contribution.
3. Compute factor attribution.
4. Compute sector attribution.
5. Compute drawdown overlap.
6. Compute cost and turnover impact.
7. Compute liquidity and capacity flags.
8. Compute regime mismatch flags.
9. Output human-readable and machine-readable risk reports.

### Required risk formulas

Portfolio return:

```text
r_p,t = a' * r_m,t
```

Portfolio variance:

```text
sigma_p^2 = a' * Sigma_m * a
```

Marginal risk contribution:

```text
MRC_i = (Sigma_m * a)_i / sigma_p
```

Component risk contribution:

```text
CRC_i = a_i * MRC_i
```

Risk contribution percentage:

```text
RC_i = CRC_i / sigma_p
```

### Required outputs

```text
data_processed/risk_manager_metrics.parquet
data_processed/risk_manager_factor_attribution.parquet
data_processed/risk_manager_cost_capacity.parquet
outputs/json/risk_manager_flags.json
outputs/reports/risk_manager_report.md
```

### Required risk flags

```text
factor_crowding_risk
liquidity_risk
drawdown_risk
regime_mismatch_risk
correlation_breakdown_risk
turnover_spike_risk
model_drift_risk
capacity_breach_risk
cost_drag_risk
unintended_exposure_risk
```

### Gate 7 pass criteria

```text
RMCS >= 90
CCS2 >= 90
RDDS >= 90
Every active M-code has risk decomposition
Every risk flag has threshold and reason code
```

---

## Gate 8. Investor Agent Gate

### Goal

Build an explainable allocation engine that allocates capital across M-codes using regime probabilities, risk manager outputs, costs, capacity, and constraints.

### Codex interpretation

The investor agent is not a black-box alpha maximizer. It is a constrained risk-budget allocator.

### Codex actions

1. Receive current regime probabilities.
2. Receive blended expected returns and risk estimates.
3. Receive risk manager flags.
4. Filter invalid M-codes.
5. Run constrained optimization.
6. Apply turnover, cost, and capacity constraints.
7. Produce allocation weights.
8. Produce decision logs and reason codes.

### Baseline objective function

```text
maximize_a:
  a' * mu_t
  - lambda / 2 * a' * Sigma_t * a
  - kappa * transaction_cost(a_t - a_t_minus_1)
  - psi * drawdown_penalty(a)
  - omega * model_risk_penalty(a)
```

Subject to:

```text
sum(a) <= 1
0 <= a_i <= a_i_max
risk_contribution_i <= rc_i_max
turnover(a_t - a_t_minus_1) <= turnover_max
factor_exposure(a) <= exposure_limit
capacity_usage(a) <= capacity_limit
```

### Required decision log fields

```text
decision_date
regime_probabilities
regime_confidence
mcode_expected_returns
mcode_risk_estimates
risk_flags
constraints
objective_function
pre_trade_weights
post_trade_weights
turnover
cost_estimate
capacity_usage
filtered_out_mcodes
reason_codes
human_readable_summary
model_version
```

### Required outputs

```text
data_processed/investor_agent_allocations.parquet
data_processed/investor_agent_decision_log.parquet
outputs/json/investor_agent_latest_decision.json
outputs/reports/investor_agent_report.md
```

### Gate 8 pass criteria

```text
IAES >= 90
RMCS >= 90
CCS2 >= 90
No allocation without reason code
No allocation violating risk manager hard flags
No hard regime switching in production
```

---

## Gate 9. Integrated Backtest Gate

### Goal

Run end-to-end system simulation from data validation to final investor-agent allocation and performance evaluation.

### Codex actions

1. Assemble full pipeline.
2. Run synthetic-data end-to-end test.
3. Run real-data test if provided.
4. Compare investor agent versus baselines.
5. Run cost sensitivity.
6. Run regime placebo tests.
7. Run parameter perturbation tests.
8. Produce integrated backtest report.

### Required baselines

```text
M0 only
Equal-weight M-code allocation
Risk-parity M-code allocation
No-regime investor agent
Random-regime placebo allocation
Static benchmark allocation
```

### Required outputs

```text
outputs/reports/integrated_backtest_report.md
outputs/reports/baseline_comparison_report.md
outputs/reports/robustness_stress_report.md
data_processed/integrated_backtest_results.parquet
```

### Gate 9 pass criteria

```text
RDDS >= 95
BDS >= 95
CCS2 >= 90
IAES >= 90
Investor agent must beat or explain failure against simple baselines
```

If the investor agent fails to improve on simple baselines, Codex must not hide the result. It must document failure and recommend fallback allocation.

---

## Gate 10. Dashboard and Monitoring Gate

### Goal

Build dashboards and monitoring reports for research review and ongoing operation.

### Codex actions

1. Build static report generation.
2. Build Shiny dashboard modules or equivalent.
3. Add performance, risk, factor exposure, cost, capacity, and decision-log views.
4. Add alert panel.
5. Add exportable reports.

### Preferred R dashboard modules

```text
R/shiny_modules/performance_panel.R
R/shiny_modules/risk_panel.R
R/shiny_modules/factor_exposure_panel.R
R/shiny_modules/cost_capacity_panel.R
R/shiny_modules/investor_agent_decision_panel.R
R/shiny_modules/governance_panel.R
```

### Required dashboard views

```text
rolling_return
rolling_volatility
rolling_sharpe
rolling_drawdown
expected_shortfall
mcode_risk_contribution
factor_exposure
sector_exposure
turnover
transaction_cost
capacity_usage
risk_flags
investor_agent_reason_codes
compliance_score_history
```

### Gate 10 pass criteria

```text
DGS >= 90
RMCS >= 90
IAES >= 90
Dashboard must show net performance and risk flags
Dashboard must not show only attractive headline metrics
```

---

## Gate 11. Recursive Governance Gate

### Goal

Enable controlled recursive improvement.

### Codex actions

1. Maintain architecture gap log.
2. Maintain evaluation history.
3. Detect weakest score.
4. Propose next smallest safe improvement.
5. Implement only if tests and documentation can be updated.
6. Promote, revert, or quarantine changes.
7. Produce recursive improvement report.

### Required outputs

```text
outputs/governance/architecture_gap_log.md
outputs/governance/evaluation_history.csv
outputs/governance/recursive_improvement_report.md
outputs/governance/promotion_decision_log.md
```

### Recursive improvement decision rule

```text
If hard constraint fails:
    fix hard constraint before new features
Else if any critical score < 85:
    improve weakest critical score
Else if gate incomplete:
    complete current gate
Else:
    propose next gate increment
```

### Gate 11 pass criteria

```text
RIDS >= 95
DGS >= 90
RS >= 90
Every improvement has tests, score delta, documentation, and promote/revert decision
```

---

# 5. Standard Task Intake Protocol

When the user asks Codex to perform a task, Codex must classify the task before coding.

## 5.1 Task classes

| Task class | Examples | Required response |
|---|---|---|
| Constitution task | Update principles, constraints, scores | Update config/docs/evaluator |
| Architecture task | Add modules, change structure | ADR + skeleton + tests |
| Data task | Add schema, ingest data, validation | Data contract + validators |
| Research task | Factor diagnostics, regime tests | Reproducible analysis + report |
| Implementation task | Build module | Code + unit tests + docs |
| Debug task | Fix failing tests | Minimal patch + regression test |
| Performance task | Optimize runtime | Benchmark before/after |
| Governance task | Compliance report, gate review | Update score and logs |
| Dashboard task | Add visuals | UI + data contract + screenshot/report if possible |

## 5.2 Task handling template

Codex should produce a concise process trace like this:

```markdown
## Process Trace

Task: <user task>
Task class: <class>
Current gate: Gate X - <name>
Primary files inspected:
- <file>
- <file>
Primary gap found:
- <gap>
Planned increment:
- <increment>
Tests to run:
- <test>
Expected outputs:
- <output>
```

Do not expose hidden chain-of-thought. Provide an auditable summary instead.

---

# 6. How Codex Should Respond to Common User Requests

## 6.1 User says: "Build the risk manager"

Codex must check gates first.

If Gate 0-6 are incomplete:

```text
Do not build full production risk manager.
Build risk manager skeleton, schemas, interfaces, tests, and known-gaps report.
```

If Gate 6 is complete:

```text
Implement risk manager module and reports.
```

## 6.2 User says: "Optimize the investor agent for highest CAGR"

Codex must not directly optimize for historical CAGR.

Safe response:

```text
Implement constrained risk-adjusted optimization using expected returns, covariance, transaction costs, capacity limits, drawdown penalties, and explainability logs. Report CAGR as evaluation output only.
```

## 6.3 User says: "Use regime engine to switch 100% into best M-code"

Codex must refuse production hard switching.

Safe implementation:

```text
Add hard-switching only as experimental stress-test baseline.
Production uses soft regime blending with confidence caps and allocation limits.
```

## 6.4 User says: "Select top 20 strategies from the 2,000 backtests"

Codex must not rank directly by historical performance.

Safe implementation:

```text
Create strategy inventory, tag overlays, de-duplicate strategy families, estimate data-mining risk, and extract pure factors before selecting any production components.
```

## 6.5 User says: "Skip transaction costs for now"

Codex may allow a gross-return diagnostic only if clearly marked experimental.

Production pipeline must require transaction costs.

---

# 7. Evaluation Metrics and Scoring Details

## 7.1 Architecture Coverage Score: `ACS`

Measures whether required modules exist and are connected.

Suggested components:

```text
repository_structure_coverage
module_presence
pipeline_connectivity
config_coverage
interface_clarity
```

## 7.2 Data Contract Compliance Score: `DCCS`

Measures schema and data validation maturity.

Suggested components:

```text
required_columns_present
primary_key_validity
date_validity
schema_test_coverage
missing_value_policy
cross_table_integrity
```

## 7.3 Backtest Bias Defense Score: `BDS`

Measures defense against false historical performance.

Suggested components:

```text
no_lookahead_tests
point_in_time_tests
survivorship_bias_tests
universe_membership_tests
fundamental_availability_lag_tests
gross_net_separation
```

## 7.4 Pure Factor Integrity Score: `PFIS`

Measures whether the system extracts genuine pure factors.

Suggested components:

```text
overlay_detection
construction_effect_control
factor_lineage
neutralization
net_of_cost_validation
factor_approval_policy
```

## 7.5 Strategy De-duplication Score: `SDS`

Measures whether the strategy pool is de-overlapped.

Suggested components:

```text
return_correlation_matrix
holdings_overlap_matrix
exposure_similarity_matrix
family_grouping
duplicate_handling_policy
```

## 7.6 Robustness and Data-Mining Defense Score: `RDDS`

Measures whether the system resists overfitting.

Suggested components:

```text
is_oos_split
walk_forward_test
parameter_perturbation_test
regime_placebo_test
multiple_testing_adjustment
subperiod_stability
```

## 7.7 Cost and Capacity Score: `CCS2`

Measures real-world implementability.

Suggested components:

```text
transaction_cost_model
turnover_model
slippage_model
market_impact_proxy
adv_capacity_proxy
cost_sensitivity_test
```

## 7.8 Risk Manager Completeness Score: `RMCS`

Measures risk diagnostic completeness.

Suggested components:

```text
performance_decomposition
factor_attribution
risk_contribution
drawdown_overlap
cost_capacity_flags
regime_mismatch_flags
model_drift_flags
```

## 7.9 Investor Agent Explainability Score: `IAES`

Measures allocation transparency.

Suggested components:

```text
decision_log_completeness
reason_codes
constraint_reporting
risk_flag_usage
allocation_before_after
human_readable_summary
```

## 7.10 Reproducibility Score: `RS`

Measures whether results can be recreated.

Suggested components:

```text
seed_control
environment_files
versioned_configs
reproducible_scripts
stable_output_paths
ci_or_test_runner
```

## 7.11 Documentation and Governance Score: `DGS`

Measures documentation maturity.

Suggested components:

```text
architecture_docs
data_dictionary
validation_policy
adr_coverage
milestone_reports
known_gap_reports
```

## 7.12 Recursive Improvement Discipline Score: `RIDS`

Measures whether self-improvement is controlled.

Suggested components:

```text
architecture_gap_log
evaluation_history
score_delta_tracking
promote_revert_decisions
quarantine_policy
```

---

# 8. Hard Gate Promotion Rules

Codex may promote to the next gate only if all conditions hold:

```text
1. Required artifacts for the current gate exist.
2. Required tests for the current gate pass or failures are explicitly documented as environment-only failures.
3. No hard constraint is violated.
4. Critical score thresholds are met.
5. A gate review report exists.
6. Evaluation history is updated.
7. Documentation is synchronized with code.
```

Codex must not promote a gate based on subjective completion.

---

# 9. Required Report Templates

## 9.1 Gate review report template

Path:

```text
outputs/governance/gate_review_report.md
```

Template:

```markdown
# Gate Review Report

Date: YYYY-MM-DD
Current gate: Gate X - <name>
Review status: PASS / FAIL / QUARANTINE

## Required Artifacts

| Artifact | Exists | Notes |
|---|---:|---|
| <artifact> | yes/no | <notes> |

## Tests

| Test suite | Status | Notes |
|---|---:|---|
| Python pytest | pass/fail/skipped | <notes> |
| R testthat | pass/fail/skipped | <notes> |
| Data validation | pass/fail/skipped | <notes> |

## Compliance Scores

| Score | Value | Threshold | Pass |
|---|---:|---:|---:|
| ACS |  |  |  |
| DCCS |  |  |  |
| BDS |  |  |  |
| PFIS |  |  |  |
| SDS |  |  |  |
| RDDS |  |  |  |
| CCS2 |  |  |  |
| RMCS |  |  |  |
| IAES |  |  |  |
| RS |  |  |  |
| DGS |  |  |  |
| RIDS |  |  |  |
| CCS |  |  |  |

## Hard Constraint Review

| Constraint | Status | Evidence |
|---|---:|---|
| no_lookahead_bias | pass/fail | <evidence> |
| pure_factor_first | pass/fail | <evidence> |
| transaction_cost_required | pass/fail | <evidence> |
| investor_agent_explainability_required | pass/fail | <evidence> |

## Decision

PROMOTE / REVERT / QUARANTINE

## Next Recommended Increment

<one concrete next step>
```

## 9.2 Architecture gap log template

Path:

```text
outputs/governance/architecture_gap_log.md
```

Template:

```markdown
# Architecture Gap Log

| ID | Date | Gate | Gap | Severity | Related score | Proposed fix | Status |
|---|---|---:|---|---|---|---|---|
| GAP-0001 | YYYY-MM-DD | 2 | Missing PIT validation | Critical | BDS | Add availability lag tests | Open |
```

## 9.3 ADR template

Path:

```text
00_Lawbook/K_RAMP/adr/ADR-YYYYMMDD-<short-title>.md
```

Template:

```markdown
# ADR: <Title>

Date: YYYY-MM-DD
Status: Proposed / Accepted / Rejected / Superseded

## Context

<problem>

## Decision

<decision>

## Alternatives Considered

1. <alternative>
2. <alternative>

## Consequences

### Positive

- <positive>

### Negative / Risks

- <risk>

## Tests / Evidence

- <test>

## Related Files

- <file>
```

---

# 10. First-Run Codex Instruction

If this is the first time Codex sees the repository, execute this sequence:

```text
1. Inspect repository.
2. Detect whether AGENTS.md exists.
3. If absent, create AGENTS.md from the K-RAMP master constitution.
4. Create docs/CODEX_IDEAL_OPERATING_PROCESS.md from this guide.
5. Create docs/K_RAMP_SYSTEM_CONSTITUTION.md if absent.
6. Create config/system_constitution.yml.
7. Create config/validation_thresholds.yml.
8. Create repository skeleton.
9. Create synthetic data generator skeleton.
10. Create schema validation skeleton.
11. Create constitution evaluator skeleton.
12. Create minimal Python and R tests.
13. Run tests.
14. Produce Gate 0 review report.
15. Stop at Gate 0 or Gate 1 boundary unless gate promotion criteria are met.
```

Do not jump to factor modeling, M-code construction, risk manager implementation, or investor-agent optimization on first run unless the repository already satisfies all prior gates.

---

# 11. Quality Bar for Codex Outputs

Every Codex output must satisfy:

```text
- Is it auditable?
- Is it testable?
- Is it reproducible?
- Is it conservative against overfitting?
- Does it preserve pure-factor-first architecture?
- Does it separate gross and net returns?
- Does it respect cost and capacity realism?
- Does it avoid hard regime switching?
- Does it explain investor-agent decisions?
- Does it update governance artifacts?
```

If any answer is no, Codex must either fix the issue or mark the output as experimental/quarantined.

---

# 12. Good Versus Bad Codex Behavior

## 12.1 Good behavior

```text
User: Build M1.
Codex: Checks whether pure factor library and factor groups exist. If not, builds M1 interface and reports missing prerequisites. If yes, builds M1 with role, hypothesis, factor groups, constraints, costs, validation, tests, and report.
```

```text
User: Add regime allocation.
Codex: Implements soft regime blending, confidence caps, no hard switching, placebo tests, and decision logs.
```

```text
User: Improve performance.
Codex: Runs baseline comparison, checks cost sensitivity, inspects weak scores, proposes robust improvements rather than parameter-mining.
```

## 12.2 Bad behavior

```text
User: Build M1.
Codex: Picks the top Sharpe strategies from the 2,000-strategy pool and combines them.
```

```text
User: Add regime allocation.
Codex: Switches 100% into the best historical M-code for the predicted regime.
```

```text
User: Improve performance.
Codex: Sweeps parameters until backtest CAGR exceeds 16%.
```

These are constitutional violations.

---

# 13. Minimum Viable Architecture Evolution Roadmap

Codex should evolve K-RAMP in the following order.

## Stage A. Governance-first skeleton

```text
Gate 0 -> Gate 1
```

Deliver:

```text
constitution docs
configs
repo skeleton
basic tests
evaluator skeleton
```

## Stage B. Data-first validation

```text
Gate 2
```

Deliver:

```text
synthetic data
schemas
PIT validators
bias defense tests
```

## Stage C. Strategy-pool normalization

```text
Gate 3
```

Deliver:

```text
strategy inventory
overlay tags
deduplication map
strategy family report
```

## Stage D. Pure factor factory

```text
Gate 4
```

Deliver:

```text
factor lineage
pure factor returns
factor validation metrics
approved factor library
```

## Stage E. Factor group and regime layer

```text
Gate 5
```

Deliver:

```text
factor groups
regime-factor matrix
soft blending expected returns
```

## Stage F. M-code layer

```text
Gate 6
```

Deliver:

```text
M0 baseline
M1-M4 role-specific portfolios
M-code validation report
```

## Stage G. Risk and allocation intelligence

```text
Gate 7 -> Gate 8
```

Deliver:

```text
risk manager
risk flags
investor agent
allocation decision logs
```

## Stage H. Full-system verification

```text
Gate 9
```

Deliver:

```text
integrated backtest
baseline comparisons
stress tests
placebo tests
cost sensitivity tests
```

## Stage I. Monitoring and recursive improvement

```text
Gate 10 -> Gate 11
```

Deliver:

```text
dashboard
monitoring reports
architecture gap log
evaluation history
recursive improvement loop
```

---

# 14. Final System State

The final K-RAMP architecture should look like this:

```text
[Raw User Tidy Data]
    -> [Data Contract Validation]
    -> [Point-in-Time Safe Data Mart]
    -> [Strategy Inventory DB]
    -> [Strategy De-duplication / Overlay Tagging]
    -> [Pure Factor Extraction Engine]
    -> [Approved Factor Library]
    -> [Factor Group Clustering]
    -> [Regime-Factor Conditional Matrix]
    -> [M-code Portfolio Factory]
    -> [Risk Manager]
    -> [Investor Agent]
    -> [Integrated Backtest]
    -> [Dashboard / Monitoring]
    -> [Recursive Governance Loop]
```

Operational decision flow:

```text
Current regime probabilities
+ M-code expected returns
+ M-code risk estimates
+ cost and capacity estimates
+ risk manager flags
+ constraints
    -> Investor Agent
    -> final M0/M1/M2/M3/M4/... allocation
    -> performance, risk, and decision attribution
    -> feedback into factor, M-code, risk manager, and investor agent review
```

---

# 15. Definition of Done

A Codex task is done only when all are true:

```text
1. The repository was inspected before changes.
2. The current gate was identified.
3. The implementation was minimal and aligned with the gate.
4. Tests were added or updated.
5. Tests were run or environment limitations were documented.
6. Compliance scores were updated if the task affects architecture.
7. Documentation was updated.
8. The promote/revert/quarantine decision was recorded.
9. No hard constraint was violated.
10. The next recommended increment is clear.
```

If these are not satisfied, the task is incomplete.

---

# 16. Codex Self-Check Before Every Final Response

Before finalizing a task, Codex must answer internally and summarize externally:

```text
- What did I inspect?
- What gate am I in?
- What did I change?
- What tests did I run?
- What passed and failed?
- What scores changed?
- What remains incomplete?
- What is the next safest step?
```

The external response should be concise and factual.

---

# 17. Core Principle

K-RAMP must evolve by controlled recursive improvement, not by uncontrolled feature expansion.

The highest-value Codex behavior is not writing the largest amount of code. The highest-value behavior is identifying the most important missing safeguard, implementing the smallest testable fix, verifying it, scoring it, documenting it, and only then moving forward.

