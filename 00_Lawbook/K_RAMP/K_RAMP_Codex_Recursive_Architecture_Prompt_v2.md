# K-RAMP v2.0: Codex Recursive Architecture Prompt

> **Purpose**: Give this Markdown file directly to Codex as the master development prompt for the K-RAMP system.  
> **Recommended use**: Save this file as `AGENTS.md` at the repository root, and also keep a copy under `docs/K_RAMP_SYSTEM_CONSTITUTION.md`.  
> **System name**: **K-RAMP** — Korea Regime-Aware Multi-Factor Portfolio Management System.  
> **Mission**: Convert a pool of approximately 2,000 Korean equity backtested strategies into a governed, explainable, risk-aware, regime-aware multi-factor portfolio operating system.  
> **Primary market**: Korean listed equities, including KOSPI200, KOSDAQ150, KRX300, and custom large/mid/small-cap universes.  
> **Target performance reference**: Long-run target CAGR is 16%, but this is an evaluation target, not a direct optimization objective.

---

# 0. Operating Instruction to Codex

You are the principal software architect, quantitative developer, and test engineer for the K-RAMP project.

Your job is not merely to write code. Your job is to turn this investment blueprint into a working research and portfolio-management architecture that can recursively improve without violating the system constitution.

You must perform work in this order:

1. Parse and internalize this constitution.
2. Create or update the repository structure.
3. Generate architecture documents, configuration files, schemas, tests, and synthetic data before implementing full quantitative logic.
4. Implement the system by milestones, with acceptance tests and measurable gates.
5. After each milestone, produce a constitution compliance report.
6. Never proceed to the next major milestone if the current milestone fails its evaluation gate.
7. When a design ambiguity exists, choose the more conservative, testable, and auditable interpretation.
8. Never optimize for attractive backtests at the cost of robustness, data integrity, transaction costs, or explainability.

If you are running in a repository that already has code, first inspect the existing structure. Do not overwrite user work without making an explicit migration plan.

---

# 1. System Identity

## 1.1 One-sentence definition

K-RAMP is a Korean equity quantitative portfolio-management platform that extracts pure factors from a large strategy pool, groups them into economically and statistically coherent factor families, builds multiple M-code multi-factor portfolios, decomposes their risks, and allocates capital dynamically through a regime-aware but risk-constrained investor agent.

## 1.2 What this system is

K-RAMP is:

- A research governance system.
- A point-in-time data validation system.
- A strategy inventory and decomposition system.
- A pure factor extraction engine.
- A factor validation and robustness engine.
- A factor-group clustering engine.
- A regime-factor conditional return/risk mapping engine.
- An M-code portfolio factory.
- A risk manager.
- An investor agent.
- A backtesting, reporting, and monitoring platform.
- A recursively improving architecture controlled by explicit evaluation gates.

## 1.3 What this system is not

K-RAMP is not:

- A best-backtest selector.
- A black-box strategy combiner.
- A regime hard-switching machine.
- A system that treats all 2,000 strategies as independent alpha sources.
- A system that accepts strategy returns without checking data-mining risk.
- A system that uses alternative data such as ESG, news, social media, NLP sentiment, or analyst text.
- A system that ignores capacity, turnover, transaction costs, slippage, or market impact.
- A system that optimizes directly for CAGR 16% by overfitting historical data.

---

# 2. Language Policy: R and Python Are Both Allowed

The previous version of the constitution was R-only. This version explicitly permits both **R** and **Python**.

## 2.1 General language rule

Use the language that best fits the module, while preserving reproducibility, auditability, and clear interfaces.

Do not mix R and Python inside the same logical module unless there is a documented reason. Prefer file-based or API-based boundaries between R and Python modules.

## 2.2 R responsibilities

Prefer R for:

- Quant research notebooks and exploratory empirical analysis.
- Tidy data transformations where `tidyverse` gives clarity.
- Fast table operations with `data.table` where needed.
- Portfolio performance analytics using `PerformanceAnalytics`.
- R-based statistical factor diagnostics.
- Shiny dashboards for performance, risk, rolling metrics, and interactive review.
- Replicating existing user workflows if the user’s raw data and research logic are already R-oriented.

Recommended R packages:

```text
tidyverse
data.table
arrow
lubridate
slider
zoo
xts
PerformanceAnalytics
quantmod
TTR
broom
testthat
yaml
jsonlite
shiny
plotly
DT
```

## 2.3 Python responsibilities

Prefer Python for:

- Repository-level orchestration.
- Typed configuration and schema validation.
- Package-style system architecture.
- Large-scale pipeline execution.
- Data contracts and validation with explicit models.
- Factor library persistence.
- Optimization engines.
- Risk model services.
- Automated reports.
- Unit tests and CI-friendly test suites.
- Optional API/dashboard backend.

Recommended Python packages:

```text
pandas
polars
numpy
scipy
statsmodels
scikit-learn
pyarrow
pydantic
pandera
cvxpy
riskfolio-lib             # optional, only if useful and justified
matplotlib
plotly
pytest
ruff
mypy
pre-commit
hydra-core               # optional config orchestration
fastapi                  # optional service layer
streamlit                # optional quick diagnostic UI
```

## 2.4 Interoperability rule

Use **Parquet** as the default cross-language data exchange format.

Preferred interfaces:

```text
R module output       -> data_processed/*.parquet
Python module input   -> data_processed/*.parquet
Python module output  -> outputs/*.parquet or outputs/*.json
R dashboard input     -> outputs/*.parquet or outputs/*.json
```

Avoid hidden state. Every cross-language boundary must have:

- A schema.
- A validation test.
- A versioned file path.
- A timestamp.
- A data lineage field where possible.

## 2.5 No language tribalism

Do not rewrite a working R module in Python merely because Python is allowed. Do not rewrite a working Python module in R merely because R is familiar. Refactor only when the change improves reliability, speed, maintainability, or testability.

---

# 3. Non-Negotiable System Constitution

These are hard constraints. If a proposed implementation violates these rules, reject the implementation.

## 3.1 Research-process constitution

Every research idea must pass through this sequence:

```text
Idea generation
  -> Data gathering and validation
  -> Model construction
  -> Backtesting and verification
  -> Reporting and implementation decision
```

Every implemented model must produce a written methodology report. No model may be promoted into the production candidate set without a report.

## 3.2 Data-integrity constitution

All backtests must defend against:

- Look-ahead bias.
- Survivorship bias.
- Revision bias in financial statement data.
- Delisting omission.
- Universe drift caused by using unavailable future constituents.
- Corporate-action mishandling.
- Rebalance-date misalignment.
- Signal availability lag errors.
- Transaction-cost omission.
- Unrealistic liquidity assumptions.

If the data cannot support point-in-time validation, the system must mark the output as **research-only / non-production**.

## 3.3 Strategy-pool skepticism constitution

The 2,000-strategy pool is contaminated raw material until proven otherwise.

Do not assume:

- Each strategy is independent.
- Each strategy represents a unique alpha source.
- Each strategy’s backtest survives transaction costs.
- Each strategy’s overlay is separable without analysis.
- Each strategy’s historical Sharpe is reliable.
- Each strategy’s regime performance is stable.

Every strategy must be inventoried, tagged, de-duplicated, cost-adjusted, and robustness-scored.

## 3.4 Pure-factor-first constitution

M-code portfolios must be built from approved pure factor families, not directly from attractive strategy backtests.

Use this conceptual decomposition:

```text
strategy_return[t]
  = pure_factor_component[t]
  + construction_effect[t]
  + overlay_effect[t]
  + noise[t]
```

Regression form:

```text
r_strategy_j[t]
  = alpha_j
  + beta_j'  * F_pure[t]
  + gamma_j' * C_construction[t]
  + delta_j' * O_overlay[t]
  + epsilon_j[t]
```

A strategy whose return is dominated by overlay terms must not be classified as a pure factor.

## 3.5 Regime-engine constitution

The regime engine is a conditional distribution estimator, not an all-or-nothing switch.

It may estimate:

```text
E[r_factor | regime]
Var[r_factor | regime]
P(loss | regime)
Expected Shortfall | regime
Regime confidence
```

It must not directly command:

```text
Current regime = A, therefore allocate 100% to M2.
```

Use soft blending:

```text
mu_blend_i[t]
  = (1 - rho[t]) * mu_unconditional_i
    + rho[t] * sum_s P(S_t = s) * mu_i_given_s
```

Where:

```text
rho[t] = validated regime confidence in [0, 1]
```

If regime confidence is low, allocation must converge toward unconditional baseline or M0.

## 3.6 Cost and capacity constitution

Every strategy, factor, and M-code must be evaluated net of realistic frictions.

At minimum, include:

- Explicit commission.
- Tax or transaction levy if applicable.
- Bid-ask spread proxy.
- Slippage.
- Market impact proxy.
- Turnover.
- ADV participation.
- Capacity score.

Any performance metric that does not specify gross or net status is invalid.

## 3.7 Model-risk constitution

Every factor, M-code, and allocation rule must carry a model-risk score.

Minimum model-risk dimensions:

- Data-mining risk.
- Parameter sensitivity.
- Regime dependency.
- Cost sensitivity.
- Liquidity sensitivity.
- Crowding risk.
- Valuation-cycle risk.
- Factor crash risk.
- Correlation-breakdown risk.
- Implementation complexity risk.

## 3.8 Explainability constitution

Every allocation produced by the investor agent must have an explanation record.

Minimum explanation fields:

```text
decision_date
regime_probabilities
regime_confidence
candidate_mcodes
filtered_out_mcodes
expected_return_estimates
risk_estimates
cost_estimates
risk_manager_flags
optimization_objective
constraints_used
pre_trade_weights
post_trade_weights
turnover
expected_transaction_cost
reason_codes
human_readable_summary
```

## 3.9 Target-return constitution

The user’s long-term reference target is:

```text
Target CAGR = 16%
```

But the optimizer must not directly maximize CAGR. CAGR is an evaluation outcome.

The allocation engine should optimize risk-adjusted, cost-adjusted, robust expected utility or risk-budgeted objective functions.

Example objective:

```text
maximize_a:
  a' * mu_t
  - lambda / 2 * a' * Sigma_t * a
  - kappa * transaction_cost(delta_a)
  - psi * model_risk_penalty(a)
  - chi * drawdown_penalty(a)
```

## 3.10 No alternative data constitution

Do not use:

- ESG data.
- News data.
- Social media data.
- Analyst report text.
- NLP-derived sentiment.
- Web scraping for alpha signals.
- Unlicensed alternative datasets.

Allowed data categories:

- Price and volume.
- Corporate actions.
- Financial statements.
- Market capitalization.
- Sector/industry classifications.
- Index membership if point-in-time safe.
- Benchmark returns.
- Risk-free rates.
- Existing backtested strategy returns supplied by the user.
- User-provided regime-engine outputs.

---

# 4. Repository Architecture

Create this monorepo.

```text
k-ramp-system/
  AGENTS.md
  README.md
  pyproject.toml
  requirements.txt
  environment.yml
  DESCRIPTION
  renv.lock                         # optional if R environment is initialized
  .gitignore
  .pre-commit-config.yaml

  config/
    system_constitution.yml
    language_policy.yml
    data_contracts.yml
    universe_rules.yml
    transaction_cost_model.yml
    validation_thresholds.yml
    factor_approval_policy.yml
    regime_policy.yml
    mcode_specs.yml
    risk_manager_policy.yml
    investor_agent_policy.yml
    architecture_roadmap.yml

  data_raw/                         # gitignored
    .gitkeep

  data_interim/                      # gitignored
    .gitkeep

  data_processed/                    # gitignored
    .gitkeep

  outputs/
    governance/
    reports/
    tables/
    figures/
    logs/
    parquet/
    rds/
    json/

  python/
    kramp/
      __init__.py
      config/
        loader.py
        schemas.py
      data/
        validation.py
        point_in_time.py
        synthetic.py
      strategy/
        inventory.py
        overlay_tagging.py
        similarity.py
      factor/
        signal_processing.py
        pure_extraction.py
        validation.py
        grouping.py
      regime/
        mapping.py
        diagnostics.py
      mcode/
        builder.py
        specs.py
      risk/
        attribution.py
        risk_manager.py
        stress.py
      agent/
        investor_agent.py
        optimizer.py
        constraints.py
      backtest/
        engine.py
        performance.py
        costs.py
      reporting/
        governance_report.py
        performance_report.py
      recursive/
        evaluator.py
        roadmap.py
        adr.py
      utils/
        dates.py
        returns.py
        logging.py

  R/
    00_packages.R
    01_utils_dates.R
    02_utils_returns.R
    03_data_validation.R
    04_strategy_inventory.R
    05_overlay_tagging.R
    06_strategy_similarity.R
    07_factor_signal_processing.R
    08_pure_factor_extraction.R
    09_factor_validation.R
    10_factor_grouping.R
    11_regime_factor_mapping.R
    12_mcode_builder.R
    13_backtest_engine.R
    14_risk_manager.R
    15_investor_agent.R
    16_reporting.R
    17_pipeline_orchestrator.R

  scripts/
    python/
      00_check_environment.py
      01_generate_synthetic_test_data.py
      02_debug_one_strategy_inventory.py
      03_debug_one_factor_signal_date.py
      04_debug_one_factor_portfolio_rebalance.py
      05_debug_one_factor_validation.py
      06_debug_one_regime_mapping.py
      07_debug_one_mcode_build.py
      08_debug_one_risk_report.py
      09_debug_one_investor_allocation.py
      10_run_full_pipeline_on_synthetic_data.py
      11_run_full_pipeline_on_user_data.py
    R/
      00_install_packages.R
      01_generate_synthetic_test_data.R
      02_debug_one_strategy_inventory.R
      03_debug_one_factor_signal_date.R
      04_debug_one_factor_portfolio_rebalance.R
      05_debug_one_factor_validation.R
      06_debug_one_regime_mapping.R
      07_debug_one_mcode_build.R
      08_debug_one_risk_report.R
      09_debug_one_investor_allocation.R
      10_run_full_pipeline_on_synthetic_data.R
      11_run_full_pipeline_on_user_data.R

  tests/
    python/
      test_config.py
      test_data_contracts.py
      test_no_lookahead.py
      test_strategy_inventory.py
      test_strategy_similarity.py
      test_pure_factor_extraction.py
      test_factor_validation.py
      test_factor_grouping.py
      test_regime_mapping.py
      test_mcode_builder.py
      test_risk_manager.py
      test_investor_agent.py
      test_recursive_evaluator.py
    R/
      testthat.R
      testthat/
        test_data_validation.R
        test_return_alignment.R
        test_no_lookahead.R
        test_strategy_inventory.R
        test_factor_extraction.R
        test_factor_validation.R
        test_regime_mapping.R
        test_mcode_builder.R
        test_risk_manager.R
        test_investor_agent.R

  shiny_app/
    app.R
    R/
      module_performance.R
      module_risk.R
      module_factor_exposure.R
      module_allocation.R
      module_governance.R
    www/

  docs/
    K_RAMP_SYSTEM_CONSTITUTION.md
    ARCHITECTURE_BLUEPRINT.md
    ARCHITECTURE_ROADMAP.md
    DATA_DICTIONARY.md
    VALIDATION_POLICY.md
    FACTOR_APPROVAL_POLICY.md
    MCODE_POLICY.md
    RISK_MANAGER_POLICY.md
    INVESTOR_AGENT_POLICY.md
    RECURSIVE_DEVELOPMENT_PROTOCOL.md
    adr/
      0001-language-boundary.md
      0002-data-format-parquet.md
      0003-regime-soft-allocation.md
```

---

# 5. Data Contracts

The user will provide tidy data. Implement strict validation.

Each table must have:

```text
schema_version
created_at or as_of_date where appropriate
source_name where appropriate
```

Where impossible, document the exception.

## 5.1 `prices`

One row per stock per date.

Required columns:

```text
date                  Date
asset_id              character
close                 numeric
adj_close             numeric
volume                numeric
shares_outstanding    numeric, optional but strongly recommended
market_cap            numeric, optional but strongly recommended
is_trading            logical, optional
```

Validation:

- `date` must be unique within `asset_id`.
- Prices must be positive when `is_trading = TRUE`.
- Returns must be computed from `adj_close`, not raw close, unless explicitly configured.

## 5.2 `universe_membership`

One row per asset per effective date or date range.

Required columns:

```text
date                  Date
asset_id              character
universe_id           character
is_member             logical
```

Optional columns:

```text
sector
industry
listing_date
delisting_date
exchange
is_managed_issue
is_spac
is_preferred
```

Validation:

- Universe membership must be date-specific.
- No future index constituents may be applied to the past.

## 5.3 `fundamentals`

One row per stock per reporting item per as-of date.

Required columns:

```text
asset_id              character
fiscal_period_end     Date
report_date           Date
available_date        Date
item                  character
value                 numeric
currency              character, optional
```

Validation:

- Signal construction must use `available_date`, not `fiscal_period_end`.
- If `available_date` is missing, the table is not production-safe.

## 5.4 `strategy_meta`

One row per backtested strategy.

Required columns:

```text
strategy_id           character, unique
strategy_name         character
universe_id           character
signal_family         character
source_signal         character
portfolio_type        character
weighting_method      character
rebalance_freq        character
has_regime_filter     logical
has_stop_loss         logical
has_vol_target        logical
has_cash_timing       logical
has_sector_neutral    logical
has_beta_neutral      logical
version               character
research_owner        character, optional
created_at            datetime, optional
```

## 5.5 `strategy_returns`

One row per strategy per date.

Required columns:

```text
date                  Date
strategy_id           character
ret_gross             numeric
ret_net               numeric, optional
turnover              numeric, optional
cash_weight           numeric, optional
```

Validation:

- `ret_gross` must be present.
- `ret_net` must be clearly marked if unavailable.
- Return frequency must be inferable or configured.

## 5.6 `strategy_holdings`

One row per strategy, rebalance date, and asset.

Required columns:

```text
date                  Date
strategy_id           character
asset_id              character
weight                numeric
position_side         character, optional: long, short, cash
```

Validation:

- Weight sum must be within configured bounds.
- Long-only strategies must not have negative asset weights.
- Long-short gross and net exposure must be validated.

## 5.7 `factor_signals`

One row per asset per signal date per factor candidate.

Required columns:

```text
date                  Date
asset_id              character
factor_id             character
raw_signal            numeric
signal_available_date Date, optional but strongly recommended
```

Optional columns:

```text
signal_family
z_score
rank_score
neutralized_score
winsorized_score
```

Validation:

- If `signal_available_date` exists, it must be <= portfolio formation date.
- Missing signal handling must be explicit.

## 5.8 `regime_probabilities`

One row per date per regime.

Required columns:

```text
date                  Date
regime_id             character
probability           numeric
regime_confidence     numeric
```

Validation:

- Probabilities must sum to 1 per date, within tolerance.
- Confidence must be in [0, 1].

## 5.9 `benchmarks`

Required columns:

```text
date                  Date
benchmark_id          character
ret                   numeric
```

## 5.10 `risk_free_rates`

Required columns:

```text
date                  Date
rate                  numeric
rate_frequency        character
```

---

# 6. Core Modules and Required Outputs

## 6.1 Data Validation Module

Purpose:

- Validate schemas.
- Validate point-in-time availability.
- Validate return alignment.
- Validate universe membership.
- Produce error reports.

Required outputs:

```text
outputs/governance/data_validation_report.md
outputs/json/data_validation_summary.json
outputs/parquet/validated_*.parquet
```

Minimum tests:

- Missing required columns fail.
- Duplicate keys fail.
- Future fundamentals fail.
- Invalid universe membership fails.
- Invalid return date alignment fails.

## 6.2 Strategy Inventory Module

Purpose:

- Convert 2,000 strategies into a structured inventory.
- Tag strategy families.
- Identify overlay usage.
- Identify rebalance rules.
- Identify construction effects.

Required outputs:

```text
outputs/parquet/strategy_inventory.parquet
outputs/reports/strategy_inventory_report.md
outputs/tables/strategy_overlay_summary.csv
```

Required classification fields:

```text
strategy_id
signal_family
pure_signal_candidate
construction_type
overlay_type
estimated_turnover
cost_status
universe_id
rebalance_freq
```

## 6.3 Strategy Similarity and De-duplication Module

Purpose:

- Detect duplicate or near-duplicate strategies.
- Cluster strategies by return, holdings, signal, exposure, and drawdown similarity.

Similarity measures:

```text
return_correlation
rank_correlation
holdings_overlap
active_weight_overlap
factor_exposure_distance
drawdown_correlation
turnover_similarity
```

Duplicate family rule example:

```text
same_family =
  return_correlation > 0.90
  OR holdings_overlap > 0.70
  OR exposure_distance < threshold
```

Required outputs:

```text
outputs/parquet/strategy_similarity_matrix.parquet
outputs/parquet/strategy_clusters.parquet
outputs/reports/strategy_deduplication_report.md
```

## 6.4 Pure Factor Extraction Module

Purpose:

- Separate pure factor effects from overlays and construction artifacts.
- Rebuild factor portfolios using standardized construction rules where signals are available.
- Use return-based style analysis where only strategy returns are available.

Preferred approach if raw factor signals exist:

```text
raw signal
  -> winsorization
  -> z-score
  -> sector/size/beta/liquidity neutralization
  -> portfolio construction under standardized rules
  -> gross and net factor return calculation
```

Neutralization form:

```text
z_pure = z_raw - X * (X'X)^(-1) * X' * z_raw
```

Where `X` may include:

```text
sector dummies
log market cap
beta
volatility
liquidity
known factor scores
```

Required outputs:

```text
outputs/parquet/pure_factor_returns.parquet
outputs/parquet/pure_factor_scores.parquet
outputs/reports/pure_factor_extraction_report.md
```

## 6.5 Factor Validation Module

Purpose:

- Validate factor candidates before adding them to factor library.

Minimum metrics:

```text
rank_ic_mean
rank_ic_std
rank_ic_ir
quintile_spread_gross
quintile_spread_net
hit_rate
turnover
capacity_score
cost_drag
market_beta
size_exposure
sector_exposure
volatility_exposure
max_drawdown
expected_shortfall
skewness
kurtosis
rolling_ic_stability
subperiod_stability
regime_dependency_score
deflated_sharpe_ratio
pbo_score_if_available
```

Approval rule example:

```text
approved =
  economic_rationale_present == TRUE
  AND rank_ic_ir_oos > 0
  AND net_quintile_spread_oos > 0
  AND cost_drag < configured_limit
  AND capacity_score >= configured_minimum
  AND data_mining_risk_score <= configured_maximum
  AND correlation_with_existing_factor_group < configured_maximum
```

Required outputs:

```text
outputs/parquet/factor_validation_metrics.parquet
outputs/parquet/approved_factor_library.parquet
outputs/reports/factor_validation_report.md
```

## 6.6 Factor Grouping Module

Purpose:

- Group approved pure factors into factor families.

Distance metric:

```text
D_ij =
  w1 * (1 - corr(factor_returns_i, factor_returns_j))
  + w2 * (1 - corr(signal_scores_i, signal_scores_j))
  + w3 * (1 - holdings_overlap_i_j)
  + w4 * exposure_distance_i_j
  + w5 * drawdown_distance_i_j
```

Required factor groups:

At minimum, allow these canonical groups:

```text
Value
Quality
Momentum
Low Risk
Size / Liquidity
Reversal
Growth / Profitability
Dividend / Income
Composite / Other
```

Do not force every factor into a canonical group if its empirical behavior contradicts its name.

Required outputs:

```text
outputs/parquet/factor_group_map.parquet
outputs/parquet/factor_group_returns.parquet
outputs/reports/factor_grouping_report.md
```

## 6.7 Regime-Factor Mapping Module

Purpose:

- Estimate conditional expected returns and risks for factor groups and M-codes by regime.

Required metrics by `regime_id` and `factor_group_id`:

```text
mean_return
volatility
sharpe
hit_rate
max_drawdown
expected_shortfall
turnover
cost_drag
sample_size
confidence_interval_lower
confidence_interval_upper
statistical_reliability_score
```

Use shrinkage when regime sample size is small:

```text
mu_regime_shrunk = omega * mu_regime + (1 - omega) * mu_unconditional
```

Where:

```text
omega = sample_size_adjusted_confidence
```

Required outputs:

```text
outputs/parquet/regime_factor_matrix.parquet
outputs/reports/regime_factor_mapping_report.md
```

## 6.8 M-code Portfolio Factory

Purpose:

- Build role-specific multi-factor portfolios.

Required baseline:

```text
M0 = baseline diversified multi-factor portfolio with no regime overlay
```

Initial M-code prototypes:

```text
M0: Baseline diversified factor group portfolio
M1: Defensive Quality / Low Risk / Value
M2: Aggressive Momentum / Growth / Earnings-related factor groups
M3: Recovery Value / Reversal / Size
M4: Neutral Core Alpha factor-balanced portfolio
```

Each M-code must have:

```text
mcode_id
hypothesis
universe_id
benchmark_id
factor_groups_used
factor_weighting_method
stock_selection_rule
portfolio_weighting_rule
rebalance_frequency
constraints
transaction_cost_assumption
expected_regime_fit
forbidden_or_high_risk_regimes
risk_budget
version
status: research, candidate, approved, quarantined, retired
```

Required outputs:

```text
outputs/parquet/mcode_returns.parquet
outputs/parquet/mcode_holdings.parquet
outputs/parquet/mcode_specs.parquet
outputs/reports/mcode_development_report.md
```

## 6.9 Risk Manager Module

Purpose:

- Decompose risk and performance of M-codes and the total portfolio.

Required risk decomposition:

```text
portfolio_variance = a' * Sigma_M * a
marginal_risk_contribution_i = (Sigma_M * a)_i / sigma_portfolio
component_risk_contribution_i = a_i * marginal_risk_contribution_i
risk_contribution_ratio_i = component_risk_contribution_i / sigma_portfolio
```

Required report sections:

```text
performance_summary
mcode_return_attribution
factor_exposure_attribution
sector_exposure_attribution
risk_contribution
correlation_matrix
crisis_correlation_matrix
drawdown_overlap
turnover_and_cost
capacity_and_liquidity
model_risk_flags
regime_mismatch_flags
```

Required outputs:

```text
outputs/parquet/risk_manager_metrics.parquet
outputs/json/risk_manager_flags.json
outputs/reports/risk_manager_report.md
```

## 6.10 Investor Agent Module

Purpose:

- Decide allocation weights across M-code portfolios using risk manager outputs, regime probabilities, and constraints.

The investor agent must start as an explainable constrained optimizer, not a black-box reinforcement learner.

Objective example:

```text
maximize_a:
  a' * mu_blend
  - lambda / 2 * a' * Sigma * a
  - kappa * transaction_cost(delta_a)
  - psi * model_risk_penalty(a)
  - chi * drawdown_penalty(a)
```

Required constraints:

```text
sum(a) <= 1
0 <= a_i <= mcode_max_weight_i
risk_contribution_i <= max_risk_contribution_i
turnover <= turnover_limit
factor_exposure <= factor_exposure_limit
liquidity_usage <= liquidity_limit
cash_weight within allowed bounds
```

Required behavior:

- If regime confidence is low, move toward M0 or unconditional baseline.
- If risk manager flags severe risk, reduce or freeze affected M-code.
- If turnover cost is too high, delay or partial-rebalance.
- If model-risk score exceeds threshold, cap the position.
- Always produce an explanation log.

Required outputs:

```text
outputs/parquet/investor_agent_allocations.parquet
outputs/json/investor_agent_decision_log.json
outputs/reports/investor_agent_report.md
```

---

# 7. Constitution Digestion Evaluation Metrics

Codex must prove that it has understood this constitution by generating and passing the following evaluation system.

The key output is:

```text
outputs/governance/constitution_compliance_report.md
outputs/json/constitution_compliance_score.json
```

## 7.1 Constitution Compliance Score, CCS

Define:

```text
CCS = weighted average of all category scores, scaled 0 to 100
```

Minimum pass threshold:

```text
CCS >= 90
No critical category below 85
No hard-constraint violation
```

If CCS < 90, Codex must fix violations before adding new features.

## 7.2 Category 1 — Architecture Coverage Score, ACS

Measures whether the required repository structure, modules, configs, and docs exist.

Inputs:

```text
required_directories
required_config_files
required_module_files
required_docs
required_tests
```

Formula:

```text
ACS = 100 * completed_required_items / total_required_items
```

Pass threshold:

```text
ACS >= 95
```

## 7.3 Category 2 — Data Contract Compliance Score, DCCS

Measures schema validation completeness.

Required tests:

- All required tables have schema validators.
- Missing required columns fail.
- Duplicate keys fail.
- Invalid dates fail.
- Future information leakage fails.
- Data lineage fields are present or documented as unavailable.

Formula:

```text
DCCS = 100 * passing_data_contract_tests / total_data_contract_tests
```

Pass threshold:

```text
DCCS >= 95
```

## 7.4 Category 3 — Bias Defense Score, BDS

Measures defenses against investment backtest bias.

Subscores:

```text
lookahead_defense
survivorship_defense
point_in_time_defense
rebalance_alignment_defense
corporate_action_defense
universe_drift_defense
net_return_labeling_defense
```

Formula:

```text
BDS = average(subscores)
```

Critical rule:

```text
lookahead_defense must be 100
point_in_time_defense must be >= 90
```

## 7.5 Category 4 — Pure Factor Integrity Score, PFIS

Measures whether the system enforces pure-factor-first logic.

Subscores:

```text
overlay_tagging_coverage
construction_effect_tagging_coverage
pure_factor_reconstruction_coverage
neutralization_test_coverage
factor_return_lineage_coverage
overlay_dominance_detection
```

Formula:

```text
PFIS = average(subscores)
```

Pass threshold:

```text
PFIS >= 90
```

## 7.6 Category 5 — Strategy De-duplication Score, SDS

Measures whether the 2,000-strategy pool is treated as a non-independent strategy universe.

Required similarity dimensions:

```text
return_correlation
holdings_overlap
factor_exposure_distance
drawdown_correlation
turnover_similarity
```

Formula:

```text
SDS = 100 * implemented_similarity_dimensions / required_similarity_dimensions
```

Pass threshold:

```text
SDS >= 80 in early milestone
SDS >= 95 before M-code promotion
```

## 7.7 Category 6 — Robustness and Data-Mining Defense Score, RDDS

Measures whether the system penalizes data-mining risk.

Required metrics, where data permits:

```text
out_of_sample_performance
walk_forward_performance
subperiod_stability
rank_ic_stability
deflated_sharpe_ratio
probability_of_backtest_overfitting
parameter_sensitivity
transaction_cost_sensitivity
placebo_or_randomized_benchmark_test
```

Formula:

```text
RDDS = weighted average of implemented robustness diagnostics
```

Pass threshold:

```text
RDDS >= 80 in research prototype
RDDS >= 90 before production candidate
```

## 7.8 Category 7 — Cost and Capacity Score, CCS2

Measures whether performance is evaluated net of frictions.

Required elements:

```text
turnover
commission
tax_or_levy
bid_ask_proxy
slippage
market_impact_proxy
ADV_participation
capacity_score
net_return_flag
```

Formula:

```text
CCS2 = 100 * implemented_cost_elements / required_cost_elements
```

Pass threshold:

```text
CCS2 >= 85 in prototype
CCS2 >= 95 before production candidate
```

## 7.9 Category 8 — Risk Manager Completeness Score, RMCS

Required outputs:

```text
performance_summary
factor_attribution
sector_attribution
risk_contribution
correlation_matrix
crisis_correlation
drawdown_overlap
expected_shortfall
turnover_cost_report
capacity_report
model_risk_flags
regime_mismatch_flags
```

Formula:

```text
RMCS = 100 * completed_risk_outputs / required_risk_outputs
```

Pass threshold:

```text
RMCS >= 90
```

## 7.10 Category 9 — Investor Agent Explainability Score, IAES

Required explanation fields:

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
filtered_out_mcodes
reason_codes
human_readable_summary
```

Formula:

```text
IAES = 100 * completed_explanation_fields / required_explanation_fields
```

Pass threshold:

```text
IAES >= 95
```

## 7.11 Category 10 — Reproducibility Score, RS

Required elements:

```text
pinned_python_dependencies
pinned_r_dependencies_or_documented_versions
config_driven_execution
random_seed_control
synthetic_test_data_generation
unit_tests
pipeline_logs
output_manifest
```

Formula:

```text
RS = 100 * implemented_reproducibility_elements / required_elements
```

Pass threshold:

```text
RS >= 90
```

## 7.12 Category 11 — Documentation and Governance Score, DGS

Required documents:

```text
README.md
K_RAMP_SYSTEM_CONSTITUTION.md
ARCHITECTURE_BLUEPRINT.md
ARCHITECTURE_ROADMAP.md
DATA_DICTIONARY.md
VALIDATION_POLICY.md
FACTOR_APPROVAL_POLICY.md
MCODE_POLICY.md
RISK_MANAGER_POLICY.md
INVESTOR_AGENT_POLICY.md
RECURSIVE_DEVELOPMENT_PROTOCOL.md
at least one ADR for each major architecture decision
```

Formula:

```text
DGS = 100 * completed_governance_docs / required_governance_docs
```

Pass threshold:

```text
DGS >= 90
```

## 7.13 Category 12 — Recursive Improvement Discipline Score, RIDS

Measures whether Codex improves the system without uncontrolled scope expansion.

Required artifacts:

```text
outputs/governance/architecture_gap_log.md
outputs/governance/evaluation_history.parquet
outputs/governance/roadmap_status.json
docs/adr/*.md for major changes
```

Required loop:

```text
Observe
  -> Diagnose
  -> Propose
  -> Implement minimally
  -> Test
  -> Score
  -> Document
  -> Promote or revert
```

Formula:

```text
RIDS = average(loop_artifact_score, gate_respect_score, ADR_score, rollback_score)
```

Pass threshold:

```text
RIDS >= 90
```

---

# 8. Milestone Gates

Codex must implement the architecture through gates. Do not skip gates.

## Gate 0 — Constitution Parsing Gate

Goal:

- Prove the system constitution has been converted into executable requirements.

Deliverables:

```text
config/system_constitution.yml
config/validation_thresholds.yml
docs/K_RAMP_SYSTEM_CONSTITUTION.md
outputs/json/constitution_requirement_map.json
outputs/governance/constitution_compliance_report.md
```

Pass criteria:

```text
ACS >= 90
DGS >= 80
No missing hard constraints
```

## Gate 1 — Repository and Environment Gate

Goal:

- Build the repository skeleton and environment checks.

Deliverables:

```text
pyproject.toml
requirements.txt
DESCRIPTION
R/00_packages.R
python/kramp/__init__.py
scripts/python/00_check_environment.py
scripts/R/00_install_packages.R
tests/python/test_config.py
tests/R/testthat/test_data_validation.R
```

Pass criteria:

```text
Python imports pass
R package checks pass or produce clear install instructions
pytest discovers tests
testthat discovers tests
ACS >= 95
RS >= 80
```

## Gate 2 — Synthetic Data and Data Contract Gate

Goal:

- Generate synthetic Korean equity-like data and validate all schemas.

Deliverables:

```text
scripts/python/01_generate_synthetic_test_data.py
scripts/R/01_generate_synthetic_test_data.R
data_processed/synthetic/*.parquet
outputs/governance/data_validation_report.md
```

Pass criteria:

```text
DCCS >= 95
BDS >= 85
All schema tests pass
```

## Gate 3 — Strategy Inventory Gate

Goal:

- Inventory synthetic and user-provided strategies.

Deliverables:

```text
strategy_inventory.parquet
strategy_overlay_summary.csv
strategy_deduplication_report.md
```

Pass criteria:

```text
SDS >= 80
overlay fields populated
strategy IDs unique
```

## Gate 4 — Pure Factor Factory Gate

Goal:

- Extract and validate pure factor candidates.

Deliverables:

```text
pure_factor_returns.parquet
pure_factor_scores.parquet
factor_validation_metrics.parquet
approved_factor_library.parquet
pure_factor_extraction_report.md
factor_validation_report.md
```

Pass criteria:

```text
PFIS >= 90
RDDS >= 80
cost labels present
factor lineage complete
```

## Gate 5 — Factor Group and Regime Mapping Gate

Goal:

- Group factors and map conditional regime performance.

Deliverables:

```text
factor_group_map.parquet
factor_group_returns.parquet
regime_factor_matrix.parquet
factor_grouping_report.md
regime_factor_mapping_report.md
```

Pass criteria:

```text
factor groups assigned or explicitly marked as unclassified
regime sample size documented
conditional estimates shrink to unconditional when confidence is low
```

## Gate 6 — M-code Factory Gate

Goal:

- Create M0 and initial M1-M4 prototypes.

Deliverables:

```text
mcode_specs.parquet
mcode_returns.parquet
mcode_holdings.parquet
mcode_development_report.md
```

Pass criteria:

```text
M0 exists
M1-M4 exist as research prototypes
M-code specs complete
No hard regime switching
Net/gross returns labeled
```

## Gate 7 — Risk Manager Gate

Goal:

- Decompose M-code and total portfolio risk.

Deliverables:

```text
risk_manager_metrics.parquet
risk_manager_flags.json
risk_manager_report.md
```

Pass criteria:

```text
RMCS >= 90
risk contribution sums reconcile
flags generated deterministically
```

## Gate 8 — Investor Agent Gate

Goal:

- Allocate across M-codes using constrained, explainable optimization.

Deliverables:

```text
investor_agent_allocations.parquet
investor_agent_decision_log.json
investor_agent_report.md
```

Pass criteria:

```text
IAES >= 95
allocation constraints respected
low regime confidence moves toward baseline
risk flags affect weights
```

## Gate 9 — Integrated Backtest Gate

Goal:

- Run full pipeline from synthetic data and, later, user data.

Deliverables:

```text
integrated_backtest_report.md
pipeline_run_manifest.json
performance_summary.parquet
```

Pass criteria:

```text
All modules run end-to-end
No look-ahead tests pass
Performance metrics reconciled
Net returns and gross returns separately reported
```

## Gate 10 — Dashboard and Monitoring Gate

Goal:

- Provide monitoring interface for performance, risks, factor exposures, and allocation decisions.

Deliverables:

```text
shiny_app/app.R
module_performance.R
module_risk.R
module_factor_exposure.R
module_allocation.R
module_governance.R
```

Pass criteria:

```text
Dashboard loads sample outputs
No hard-coded production data paths
Modules fail gracefully if outputs are missing
```

## Gate 11 — Recursive Architecture Evolution Gate

Goal:

- Enable disciplined self-improvement.

Deliverables:

```text
docs/RECURSIVE_DEVELOPMENT_PROTOCOL.md
outputs/governance/architecture_gap_log.md
outputs/governance/evaluation_history.parquet
outputs/governance/roadmap_status.json
```

Pass criteria:

```text
RIDS >= 90
Every proposed improvement maps to a metric
Every major change has an ADR
No improvement bypasses tests
```

---

# 9. Roadmap from Blueprint to Final Architecture

## Phase 0 — Architectural Grounding

Objective:

- Convert the blueprint into an explicit constitution, repository skeleton, and measurable development plan.

Tasks:

1. Create `AGENTS.md` from this prompt.
2. Create constitution configs.
3. Create architecture roadmap.
4. Create data dictionary.
5. Create acceptance scorecard.

Exit condition:

```text
Gate 0 and Gate 1 pass.
```

## Phase 1 — Data Mart and Bias Defense

Objective:

- Establish point-in-time safe data infrastructure.

Tasks:

1. Implement data contracts.
2. Generate synthetic data.
3. Validate prices, fundamentals, universe, strategy metadata, returns, holdings, and regimes.
4. Implement no-lookahead tests.
5. Implement universe membership tests.

Exit condition:

```text
Gate 2 passes.
```

## Phase 2 — Strategy Pool Industrialization

Objective:

- Turn 2,000 backtested strategies into a governed strategy database.

Tasks:

1. Load strategy metadata.
2. Load strategy returns.
3. Load optional holdings.
4. Tag overlays.
5. Calculate similarity matrices.
6. Cluster duplicate strategies.
7. Produce strategy family report.

Exit condition:

```text
Gate 3 passes.
```

## Phase 3 — Pure Factor Library

Objective:

- Extract pure factor candidates and reject contaminated candidates.

Tasks:

1. Standardize signals.
2. Neutralize exposures.
3. Rebuild factor portfolios under common construction rules.
4. Estimate factor returns.
5. Validate IC, spread, robustness, turnover, capacity, and model risk.
6. Approve factor candidates.

Exit condition:

```text
Gate 4 passes.
```

## Phase 4 — Factor Groups and Regime Conditionality

Objective:

- Convert factors into coherent factor families and map their conditional behavior by regime.

Tasks:

1. Build factor group distance matrix.
2. Cluster factors.
3. Assign economic labels.
4. Estimate unconditional factor group performance.
5. Estimate regime-conditional factor group performance.
6. Apply shrinkage when sample size is weak.
7. Build regime-factor matrix.

Exit condition:

```text
Gate 5 passes.
```

## Phase 5 — M-code Portfolio Laboratory

Objective:

- Create role-specific multi-factor portfolios.

Tasks:

1. Build M0 baseline.
2. Build M1 defensive.
3. Build M2 offensive.
4. Build M3 recovery.
5. Build M4 neutral core.
6. Attribute M-code returns to factor groups.
7. Validate M-code independence and drawdown overlap.

Exit condition:

```text
Gate 6 passes.
```

## Phase 6 — Risk Manager

Objective:

- Build a full risk decomposition and alerting layer.

Tasks:

1. Compute M-code risk contribution.
2. Compute factor exposure attribution.
3. Compute sector and liquidity exposure.
4. Compute correlation and crisis correlation.
5. Compute drawdown overlap.
6. Compute model-risk flags.
7. Produce risk manager report.

Exit condition:

```text
Gate 7 passes.
```

## Phase 7 — Investor Agent

Objective:

- Convert risk manager and regime outputs into allocation decisions.

Tasks:

1. Implement constrained optimizer.
2. Implement baseline allocation policy.
3. Implement regime confidence blending.
4. Implement risk flag responses.
5. Implement turnover and cost controls.
6. Generate allocation decision logs.

Exit condition:

```text
Gate 8 passes.
```

## Phase 8 — Integrated System Backtest

Objective:

- Validate the entire decision system end-to-end.

Tasks:

1. Run full synthetic data pipeline.
2. Run full user data pipeline if data exists.
3. Compare investor agent to M0, equal-weight M-code, and risk parity M-code baselines.
4. Compare regime-aware allocation to no-regime allocation.
5. Run transaction-cost sensitivity.
6. Run parameter perturbation.
7. Run placebo regime test.

Exit condition:

```text
Gate 9 passes.
```

## Phase 9 — Monitoring and Governance

Objective:

- Build dashboards and governance reports.

Tasks:

1. Build Shiny dashboard skeleton.
2. Add performance module.
3. Add risk module.
4. Add factor exposure module.
5. Add allocation module.
6. Add governance module.
7. Add daily or monthly monitoring report generation.

Exit condition:

```text
Gate 10 passes.
```

## Phase 10 — Recursive Architecture Evolution

Objective:

- Enable the system to improve without uncontrolled complexity.

Tasks:

1. Implement architecture gap log.
2. Implement evaluation history table.
3. Implement roadmap status update.
4. Implement ADR generation template.
5. Implement milestone score dashboard.
6. Implement promotion/quarantine/retirement workflow for factors and M-codes.

Exit condition:

```text
Gate 11 passes.
```

---

# 10. Recursive Development Protocol

Every development cycle must follow this loop.

```text
1. Observe
   - Inspect current code, outputs, tests, and compliance report.

2. Diagnose
   - Identify the largest architecture gap or failing score.

3. Propose
   - Propose the smallest implementation that improves the failing score.

4. Implement
   - Make minimal, testable changes.

5. Test
   - Run unit tests, validation tests, and relevant pipeline tests.

6. Score
   - Update constitution compliance score.

7. Document
   - Update docs, changelog, ADR if needed, and governance report.

8. Promote or revert
   - Promote if metrics improve without breaking hard constraints.
   - Revert or quarantine if metrics degrade or tests fail.
```

## 10.1 Recursive improvement constraints

Codex must not:

- Add a new model because it is interesting.
- Add a dependency without documenting why.
- Replace a simple explainable method with a black-box method before baseline comparisons.
- Add machine learning to the investor agent before the deterministic optimizer is stable.
- Add alternative data.
- Tune parameters solely to improve historical performance.
- Proceed after failing a gate.

## 10.2 Recursive improvement priority

When multiple improvements are possible, choose in this priority order:

```text
1. Bias defense and data integrity
2. Cost and capacity realism
3. Risk decomposition completeness
4. Explainability
5. Robustness diagnostics
6. Runtime performance
7. Dashboard usability
8. Strategy complexity
```

## 10.3 Architecture Decision Record, ADR

For each major decision, create:

```text
docs/adr/YYYYMMDD-short-title.md
```

ADR template:

```markdown
# ADR: <title>

## Status
Proposed / Accepted / Rejected / Superseded

## Context
What problem are we solving?

## Decision
What did we decide?

## Alternatives considered
What else was considered?

## Consequences
Benefits, risks, and trade-offs.

## Metrics affected
Which constitution scores or performance metrics should change?

## Rollback plan
How do we reverse this if it fails?
```

---

# 11. Quantitative Evaluation Metrics for Strategies, Factors, M-codes, and Agent

## 11.1 Strategy-level metrics

For each strategy:

```text
CAGR_gross
CAGR_net
annualized_volatility
Sharpe
Sortino
Calmar
max_drawdown
hit_rate
skewness
kurtosis
expected_shortfall_95
turnover
cost_drag
market_beta
tracking_error
information_ratio
rolling_sharpe
rolling_mdd
regime_conditional_return
regime_conditional_drawdown
data_mining_risk_score
capacity_score
overlay_dominance_score
```

## 11.2 Factor-level metrics

For each pure factor:

```text
rank_ic_mean
rank_ic_ir
rank_ic_positive_ratio
quintile_spread_gross
quintile_spread_net
monotonicity_score
turnover
cost_drag
capacity_score
factor_volatility
factor_mdd
factor_expected_shortfall
factor_crash_score
cross_factor_correlation
subperiod_stability
regime_dependency_score
valuation_sensitivity_if_available
```

## 11.3 Factor-group metrics

For each factor group:

```text
group_return
net_group_return
group_volatility
group_sharpe
group_mdd
group_expected_shortfall
intra_group_correlation
inter_group_correlation
group_turnover
group_capacity
group_regime_fit
group_model_risk
```

## 11.4 M-code metrics

For each M-code:

```text
CAGR_gross
CAGR_net
annualized_volatility
Sharpe
Sortino
Calmar
max_drawdown
expected_shortfall
tracking_error
information_ratio
factor_group_contribution
sector_contribution
stock_selection_contribution
cost_contribution
turnover
capacity
liquidity_usage
correlation_with_other_mcodes
drawdown_overlap_with_other_mcodes
regime_fit_score
model_risk_score
```

## 11.5 Investor agent metrics

For the allocation engine:

```text
portfolio_CAGR_gross
portfolio_CAGR_net
portfolio_volatility
portfolio_Sharpe
portfolio_Sortino
portfolio_Calmar
portfolio_MDD
portfolio_expected_shortfall
average_turnover
average_cost_drag
cash_usage
risk_budget_breach_count
constraint_breach_count
allocation_explainability_score
regime_tilt_contribution
risk_manager_flag_response_accuracy
M0_excess_return
EW_Mcode_excess_return
RP_Mcode_excess_return
NoRegime_excess_return
placebo_regime_excess_return
```

Mandatory baseline comparisons:

```text
InvestorAgent vs M0
InvestorAgent vs equal-weight M-codes
InvestorAgent vs risk-parity M-codes
Regime-aware Agent vs No-regime Agent
Regime-aware Agent vs Random-regime Placebo
```

If the investor agent fails to beat simple baselines net of cost and with acceptable risk, mark it as **not production-ready**.

---

# 12. Promotion, Quarantine, and Retirement Rules

## 12.1 Factor promotion

A factor can be promoted from `research` to `approved` only if:

```text
economic_rationale_present == TRUE
point_in_time_safe == TRUE
net_performance_positive == TRUE
rank_ic_ir_oos > configured_minimum
turnover <= configured_maximum
capacity_score >= configured_minimum
model_risk_score <= configured_maximum
correlation_with_existing_group <= configured_maximum OR documented reason exists
```

## 12.2 Factor quarantine

A factor must be quarantined if:

```text
lookahead_risk_detected == TRUE
net_performance_collapsed == TRUE
cost_drag_exceeds_alpha == TRUE
capacity_score_below_minimum == TRUE
model_risk_score_above_limit == TRUE
```

## 12.3 M-code promotion

An M-code can be promoted from `research` to `candidate` only if:

```text
uses_only_approved_or_candidate_factors == TRUE
has_complete_mcode_spec == TRUE
net_performance_positive == TRUE
risk_metrics_within_limits == TRUE
drawdown_overlap_not_excessive == TRUE
regime_fit_documented == TRUE
transaction_costs_included == TRUE
risk_manager_report_complete == TRUE
```

## 12.4 M-code quarantine

An M-code must be quarantined if:

```text
unexpected_factor_exposure_detected == TRUE
risk_limit_breach_persistent == TRUE
drawdown_exceeds_limit == TRUE
turnover_spike_unexplained == TRUE
regime_mismatch_persistent == TRUE
```

## 12.5 Investor agent production readiness

The investor agent is production-candidate only if:

```text
IAES >= 95
risk_budget_breach_count == 0 in validation
constraint_breach_count == 0 in validation
beats_or_matches_M0_after_cost_with_lower_or_equal_risk OR documented investment reason exists
regime_placebo_test_passed == TRUE
transaction_cost_sensitivity_passed == TRUE
```

---

# 13. Initial Task for Codex

When this prompt is first given to Codex, execute the following task list.

## Task 1 — Inspect or create repository

If repository exists:

1. List current files.
2. Identify conflicts with required architecture.
3. Propose a non-destructive migration plan.

If repository is empty:

1. Create the repository structure in Section 4.
2. Add `.gitkeep` files to empty directories.
3. Create `.gitignore`.

## Task 2 — Create constitution files

Create:

```text
AGENTS.md
docs/K_RAMP_SYSTEM_CONSTITUTION.md
docs/ARCHITECTURE_BLUEPRINT.md
docs/ARCHITECTURE_ROADMAP.md
docs/RECURSIVE_DEVELOPMENT_PROTOCOL.md
config/system_constitution.yml
config/language_policy.yml
config/validation_thresholds.yml
```

## Task 3 — Create schema and validation skeleton

Create Python:

```text
python/kramp/config/schemas.py
python/kramp/data/validation.py
tests/python/test_data_contracts.py
```

Create R:

```text
R/03_data_validation.R
tests/R/testthat/test_data_validation.R
```

## Task 4 — Create synthetic data generator

Create:

```text
scripts/python/01_generate_synthetic_test_data.py
scripts/R/01_generate_synthetic_test_data.R
```

Synthetic data must include:

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
```

## Task 5 — Create constitution evaluator

Create:

```text
python/kramp/recursive/evaluator.py
scripts/python/99_generate_constitution_compliance_report.py
outputs/governance/constitution_compliance_report.md
outputs/json/constitution_compliance_score.json
```

The evaluator must compute at least these scores:

```text
ACS
DCCS
BDS
PFIS
SDS
RDDS
CCS2
RMCS
IAES
RS
DGS
RIDS
CCS_total
```

For early skeleton stages, mark unimplemented categories as `not_yet_applicable` only if the relevant gate has not been reached. Do not inflate scores by ignoring future requirements.

## Task 6 — Run tests

Run:

```bash
pytest tests/python
```

If R environment is available, run:

```bash
Rscript -e "testthat::test_dir('tests/R/testthat')"
```

If R is not available, document this in the environment report without failing Python-only scaffolding.

## Task 7 — Produce first milestone report

Create:

```text
outputs/governance/milestone_0_report.md
```

It must include:

```text
completed_items
failed_items
constitution_scores
next_required_gate
known_architecture_gaps
```

---

# 14. Final Architecture Target

The final system should support this full production-grade flow.

```text
[Raw User Tidy Data]
    -> [Data Contract Validation]
    -> [Point-in-Time Data Mart]
    -> [Strategy Inventory DB]
    -> [Overlay Tagging and De-duplication]
    -> [Pure Factor Extraction]
    -> [Factor Validation and Approval]
    -> [Factor Group Library]
    -> [Regime-Factor Conditional Matrix]
    -> [M-code Portfolio Factory]
    -> [Risk Manager]
    -> [Investor Agent]
    -> [Integrated Backtest]
    -> [Monitoring Dashboard]
    -> [Governance and Recursive Improvement]
```

The final architecture is successful only if it can answer all of these questions with generated data and reports:

1. Which of the 2,000 strategies are near-duplicates?
2. Which strategies are dominated by overlays rather than pure factors?
3. Which pure factors survive net-of-cost validation?
4. Which factor groups are economically and statistically distinct?
5. Which factor groups work or fail in each regime?
6. Why does each M-code exist?
7. Which M-code contributes how much risk?
8. Which factor exposures explain each M-code’s return?
9. Which M-codes should be reduced due to risk manager flags?
10. Why did the investor agent choose the final allocation?
11. Does the investor agent improve over simple baselines net of cost?
12. Which architecture gaps remain before production use?

---

# 15. Strict Prohibitions

Do not:

- Implement a model without tests.
- Add a feature without a config and documentation update.
- Use future data.
- Use alternative data.
- Use performance-only strategy selection.
- Treat regime labels as perfect truth.
- Suppress failing tests.
- Hard-code user-specific file paths.
- Hide assumptions in code comments only; put them in config or docs.
- Promote a factor or M-code without passing gates.
- Add reinforcement learning or deep learning to allocation before deterministic baselines are complete.
- Produce only notebooks without package modules.
- Produce only package modules without debug scripts.

---

# 16. Development Style

## 16.1 Debug-first workflow

Before implementing a loop or function that processes all dates or all strategies, create a debug script for one representative date, strategy, factor, or M-code.

Example sequence:

```text
scripts/python/03_debug_one_factor_signal_date.py
  -> python/kramp/factor/signal_processing.py
  -> tests/python/test_factor_validation.py
```

## 16.2 Config-first workflow

Every threshold must live in config.

Examples:

```text
max_strategy_return_correlation_for_uniqueness
max_factor_group_correlation
min_rank_ic_ir_oos
max_turnover
max_cost_drag
max_model_risk_score
max_mcode_weight
max_risk_contribution
regime_confidence_floor
```

## 16.3 Report-first governance

Every major module must create a report even when using synthetic data.

Reports must include:

```text
purpose
inputs
methodology
assumptions
outputs
validation checks
known limitations
next improvements
```

---

# 17. Expected First Codex Response Format

After receiving this prompt, Codex should respond with:

```markdown
# K-RAMP Initialization Plan

## Repository status
- Existing repo / Empty repo
- Files inspected

## Constitution interpretation
- Hard constraints recognized
- Language policy recognized: R and Python both allowed
- Gates recognized

## First implementation batch
- Files to create
- Tests to create
- Reports to create

## Commands to run
```bash
...
```

## Expected milestone output
- Gate 0 deliverables
- Gate 1 deliverables
```

Then Codex should proceed to implement the initial skeleton and run tests.

---

# 18. Minimum Viable Architecture Before Real User Data

Before using the user’s actual 2,000 strategy pool, the system must pass on synthetic data.

Minimum viable state:

```text
Synthetic data generation works
Data validation works
Strategy inventory works
Similarity clustering works on synthetic strategies
Pure factor extraction works on synthetic factor signals
Factor validation produces metrics
Factor grouping creates groups
Regime mapping creates conditional matrix
M0-M4 prototypes are generated
Risk manager report is generated
Investor agent allocation is generated
Constitution compliance report is generated
```

Only after this should user data be connected.

---

# 19. Human Review Checkpoint

At the end of each gate, Codex must generate a human-readable checkpoint.

Template:

```markdown
# Gate <N> Review

## Gate objective

## Completed deliverables

## Tests run

## Scores

| Score | Value | Pass/Fail |
|---|---:|---|

## Critical issues

## Non-critical issues

## Architecture gaps

## Recommendation
Proceed / Do not proceed

## Next gate plan
```

If the recommendation is `Do not proceed`, Codex must fix the gate first.

---

# 20. End State

The end state is not a single backtest. The end state is a governed portfolio operating system.

A valid final K-RAMP architecture must include:

```text
1. Repeatable data validation
2. Pure factor library
3. Factor group map
4. Regime conditional matrix
5. M-code portfolio library
6. Risk manager
7. Investor agent
8. Integrated backtester
9. Monitoring dashboard
10. Governance reports
11. Recursive architecture evaluator
```

The final system must be able to say:

```text
We know what we are buying.
We know why we are buying it.
We know which risks explain the return.
We know when the model is unreliable.
We know what changed since the last decision.
We know whether the investor agent adds value over simple baselines.
```

That is the K-RAMP standard.
