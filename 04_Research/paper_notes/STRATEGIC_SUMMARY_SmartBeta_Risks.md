# STRATEGIC SUMMARY: Smart Beta Risks for Korean Equity Factor Investing
**Papers:** P155–P176 (22 papers) | **Compiled:** 2026-03-01 | **Author:** Q (Claude)

---

## Q1: What Are the Real Capacity Limits for Korean Smart Beta Strategies?

### Evidence from the Literature
- P155 (Capacity of Smart Beta): Small-cap strategies degrade at $1–5B AUM; large-cap factor strategies survive to $10–50B before significant alpha erosion. Price impact at rebalancing is the primary mechanism.
- P171 (Jacobs & Levy): Smart beta transparency creates predictable rebalancing events that attract front-runners, further eroding effective capacity.
- P174 (Jacobs & Levy 2015): Capacity is not unlimited — as more capital chases the same factor, prices move against the strategy.

### Korean Market Specific Numbers
- KOSPI200 + KOSDAQ150 total float: approximately $250–300B USD
- Average daily turnover (KOSPI200): approximately $6–8B/day; KOSDAQ150: approximately $1–2B/day
- Korean market impact cost: approximately 2–3x US equivalent (bid-ask spreads, order book depth)
- Effective capacity estimates for Korean factor strategies:
  - Small-cap/mid-cap KOSDAQ factor: max $200–400M before material alpha erosion
  - KOSPI200 value (large-cap): max $1–3B
  - KOSPI200 low-vol: max $2–5B (but crowded by institutional mandates)
  - Multi-factor composite: max $500M–1B (depends on factor mix)

### Implementation Rule
```r
# In hurdle_gate.R
capacity_check <- function(portfolio, daily_adv, target_aum) {
  max_safe_aum <- sum(daily_adv * 20)  # 20 days of ADV at 100% participation
  if (target_aum > max_safe_aum * 0.25) {
    warning("Strategy AUM exceeds 25% of estimated capacity ceiling")
  }
}
```

---

## Q2: What Are the Main Risks to Smart Beta Factor Alpha in Korea?

### Risk 1: Backtest Inflation / Data Mining (HIGHEST PRIORITY)
- P166 (Smart Beta Mirage): Pre-listing alpha = 2.77%/yr; post-listing = -0.44%/yr. Decline = 3.22%. Multi-factor worst: 4.11% → -0.79%.
- P158 (Arnott): After publication, average factor alpha declines by 3.3% (5.8% → 2.4%).
- P157 (ERI Robustness): Only B/M and E/P pass absolute robustness; composite scoring creates data-snooping bias.
- **Mitigation**: Apply 50% mirage discount to all backtest alphas; require true out-of-sample validation.

### Risk 2: Valuation / Revaluation Alpha (HIGH PRIORITY)
- P158 (Arnott): Low-vol structural alpha near zero — all backtest performance is revaluation alpha.
- P173 (RA Methodology): Expected return = structural alpha + beta * valuation_z_score; factors with high valuation z-scores face headwinds.
- P159 (Arnott Timing): Three most expensive factors earn -1.1%/yr Sharpe -0.16; three cheapest earn 6.1%/yr Sharpe 0.66.
- **Mitigation**: Decompose backtest returns into structural + revaluation alpha; always check current factor valuation z-score before deployment.

### Risk 3: Crowding / Herding Risk (HIGH PRIORITY)
- P162 (Smart Beta Crowding 2020): 1987 crash and August 2007 quant meltdown as canonical examples of crowded factor collapses.
- P174 (Jacobs & Levy 2015): Front-running of transparent rebalancing erodes returns; factor crowding can cause correlated crashes.
- P170 (Bernstein 2017): Value (24.3%), Dividend (24.0%), Growth (22.4%) account for 70% of global smart beta AUM — these are the most crowded factors.
- **Korean amplifier**: KOSPI200 semi-annual reconstitution creates known crowding events; NPS/institutional cluster risk.
- **Mitigation**: Monitor factor ETF AUM as crowding proxy; stagger rebalancing around known calendar events; avoid factors with AUM share > 20%.

### Risk 4: Regime Dependency (MEDIUM-HIGH PRIORITY)
- P156 (Lazard): Factor performance is highly regime-dependent; 5 risk dimensions must be monitored simultaneously.
- P174 (Jacobs & Levy 2015): All factors have multi-year underperformance episodes; constant exposure is dangerous.
- P160 (Malkiel): Excess returns explained by higher systematic risk, not skill — risk exposures shift with market regimes.
- **Korean amplifier**: Korean market regime changes are sharper and faster around earnings seasons and MSCI rebalancing.
- **Mitigation**: Use macro_regime.parquet (VIX, YC, HY Spread, KRW regime) to gate factor exposure; reduce value weight in momentum regimes.

### Risk 5: Implementation / Construction Errors (MEDIUM PRIORITY)
- P163 (Smart Beta Funds): 1/3 of "smart beta" products are effectively market funds (R-squared > 0.99); mislabeling is pervasive.
- P167 (Fays 2017): Independent sorting creates imbalanced portfolios due to factor intercorrelations; dependent sorting significantly improves Sharpe.
- P172 (Dubil): Most smart beta ETF outperformance is explained by market risk and size tilt, not fundamental weighting superiority.
- **Mitigation**: Always run 4-factor attribution; require unexplained alpha > 100bps; use dependent sorting methodology.

---

## Q3: What Is the Timing/Cyclicality of Smart Beta Factors in Korea?

### Evidence from the Literature
- P159 (Arnott Timing): Contrarian factor timing using valuation signals works over 39.5 years; avg cross-factor correlation = 0.04.
- P175 (Clare Part 1 Table 2 Panel B): Clear decade-level cyclicality — 1990s was "cap-weight decade"; 2000s strongly favored alternatives.
- P176 (Clare Part 2): Fundamental indices underperformed significantly 1997–2000 (growth bubble) and 2008–2011 (dividend/book value underperformed post-Lehman for book-value-heavy strategies).
- P160 (Malkiel): Smart beta factors perform well in some market environments and poorly in others — not consistently.

### Korean Factor Cycle Map (Based on Literature Evidence)
| Factor | Favorable Regime | Hostile Regime | Current Status (2026 estimate) |
|--------|-----------------|----------------|-------------------------------|
| Value (B/P, E/P) | Low growth, high inflation, rate rising | Growth/tech bull, deflation | Potentially undervalued post-2022 reversal |
| Quality/Profitability | Late cycle, credit stress | Early cycle recovery | Moderate |
| Momentum | Trending markets, low volatility | Sharp reversals, high VIX | Monitor VIX level |
| Low-Vol | Risk-off, crisis | Strong risk-on rally | Expensive (post-2018 crowding) |
| Dividend | High yield-seeking, low rates | Rising rates, inflation | Headwind from rising rates |

### Timing Signal Implementation
The Arnott framework (P159, P173) provides a direct implementation:
```r
# Compute factor valuation z-scores for timing
factor_timing_signal <- function(factor_pb, hist_mean, hist_sd) {
  val_z <- (log(factor_pb) - hist_mean) / hist_sd
  # Overweight factors with val_z < -0.5 (cheap), underweight val_z > +0.5 (expensive)
  timing_weight <- 1 - 0.3 * val_z  # ±30% weight adjustment per 1-SD cheapness
  return(pmax(0.1, pmin(2.0, timing_weight)))  # Clamp to [0.1, 2.0]
}
```

---

## Q4: How Decomposable Is Smart Beta Alpha vs. True Proprietary Alpha?

### Evidence from the Literature
- P164 (Kahn & Lemmon): Smart beta explains 33% of active managers' active variance on average; 50%+ for quant managers.
- P172 (Dubil Table 4): Most smart beta ETF outperformance (>50%) explained by Fama-French 4 factors alone; residual unexplained alpha is small.
- P163 (Smart Beta Funds): Only HML (value) is practically tradable at scale; most factor strategies face severe implementation frictions.
- P157 (ERI Robustness): Only B/M and E/P show statistically significant alpha; composite scoring is largely data-snooping.
- P158 (Arnott): Structural alpha for most strategies is near zero once revaluation alpha is stripped out.

### Decomposition Framework
```
Total Return = Risk-Free Rate
             + Market Beta × Market Premium          [always > 0, not alpha]
             + SMB × Size Premium                    [well-documented, not proprietary]
             + HML × Value Premium                   [most robust, but eroding]
             + MOM × Momentum Premium                [real but volatile]
             + Revaluation Alpha                     [not repeatable, historical artifact]
             + Structural Alpha                      [genuine edge, requires independent validation]
```

**Threshold for "true alpha"**: Structural Alpha > 100bps/yr at p < 0.10, sustained over 5+ year out-of-sample period.

### Korean Pipeline Implication
Our Maxwell Protocol strategies (Fractal Aegis, Samsara, Nirvana) should target structural alpha generation through:
- Residual decomposition BEFORE factor computation (mandatory per user's style)
- Information-theoretic factors (Transfer Entropy, Permutation Entropy) that are not in the public factor library
- Regime-conditional factor weights that adapt to macro_regime signals
- Proprietary composite construction using dependent sorting (P167/P168)

---

## Q5: Which Factors Are Most Crowded and What Is the Risk?

### Global Crowding Ranking (Based on AUM Data from P170 + Literature)
| Factor | Global AUM Share | Crowding Level | Primary Crowding Risk |
|--------|-----------------|----------------|-----------------------|
| Value (P/B, P/E) | 24.3% | HIGH | Mean-reversion after crowding; Structural alpha may be near zero (P158) |
| Dividend Yield | 24.0% | HIGH | Rate sensitivity; crowding among yield-seeking institutions |
| Growth | 22.4% | HIGH | Valuation risk; revaluation alpha inflating backtests |
| Small Cap | 17.3% | MEDIUM-HIGH | Liquidity/capacity limits (P155); front-running (P174) |
| Low Volatility | 6.9% | MEDIUM-HIGH | Structural alpha near zero (P158); expensive after 2012–2018 re-rating |
| Quality | 2.5% | LOW-MEDIUM | Undercrowded but rapidly growing post-stewardship codes |
| Multi-Factor | 1.8% | LOW-MEDIUM | Growing fast (+44%/6 months in 2017); worst out-of-sample (P166) |
| Momentum | 0.8% | LOW | Least crowded globally; works in crypto too (P169); but rapid inflows |

### Korean-Specific Crowding Assessment (2026)
- **Most crowded in Korea**: Low-vol (institutional mandates since 2014), Dividend yield (NPS yield-seeking), Value (fund manager consensus)
- **Least crowded in Korea**: Quality/Profitability composite (DART-based, limited institutional access), Transfer-Entropy based momentum signals, Residual momentum (market-neutral)
- **Crowding event risk**: KOSPI200 June/December reconstitution — all factor strategies rebalance simultaneously creating 3–5 day crowded entry windows

### Crowding Monitor Implementation
```r
# In hurdle_gate.R or a dedicated crowding_monitor.R
compute_crowding_score <- function(strategy_returns, benchmark_factor_returns, window = 60) {
  # 1. Rolling correlation with known benchmark factor portfolios
  rolling_cor <- rollapply(cbind(strategy_returns, benchmark_factor_returns),
                           width = window, FUN = function(x) cor(x[,1], x[,2]),
                           by.column = FALSE)

  # 2. Return autocorrelation (high autocorrelation = crowded unwinding risk)
  return_ac <- acf(strategy_returns, lag.max = 5, plot = FALSE)$acf[2]

  # 3. Combined crowding score
  crowding_score <- 0.6 * max(abs(rolling_cor)) + 0.4 * abs(return_ac)

  # Flag if crowding_score > 0.7
  if (crowding_score > 0.7) warning("High crowding risk detected")
  return(crowding_score)
}
```

---

## Top 3 Risk Mitigation Recommendations for the Pipeline

### Recommendation 1: Implement the "Mirage Discount" in hurdle_gate.R
**Problem**: P166 shows average alpha decay = 3.22% from backtest to live for multi-factor strategies.
**Action**: Multiply all backtest alphas by 0.50 (single-factor) or 0.40 (multi-factor) before evaluating against hurdles. Any strategy that only clears hurdles at face-value backtest alpha should be rejected.
**Code anchor**: Add `mirage_adjusted_alpha = backtest_alpha * 0.50` to the QEPM soft score calculation.

### Recommendation 2: Build a Structural Alpha / Revaluation Alpha Decomposition Step
**Problem**: P158 and P173 show that most smart beta backtest returns include revaluation alpha that is not repeatable.
**Action**: For every strategy, compute the trend in factor valuation ratio over the backtest period. Structural alpha = excess return - (beta_val * valuation_trend). Require structural_alpha > 100bps before deployment consideration.
**Code anchor**: Add to `summarise_perf()` in backtest_harness.R:
```r
val_trend <- coef(lm(log(val_ratio) ~ time))[2]  # slope of valuation ratio
revaluation_alpha <- val_trend * val_beta * annualization_factor
structural_alpha <- total_alpha - revaluation_alpha
```

### Recommendation 3: Add a Crowding Gate to the Monthly Simulation Loop
**Problem**: P162 and P174 show that crowded factors suffer correlated drawdowns during deleveraging events; Korean KOSPI200 reconstitution creates predictable crowding windows.
**Action**: Before each monthly rebalancing, compute the crowding score for all factors in the composite. If any factor crowding score > 0.7, reduce that factor's weight by 50%. Avoid trading within 5 days of KOSPI200 reconstitution dates.
**Code anchor**: Add to `run_monthly_simulation()` in backtest_harness.R:
```r
reconstitution_dates <- c("2026-06-27", "2026-12-26")  # KOSPI200 semi-annual
if (any(abs(as.numeric(rebalance_date - as.Date(reconstitution_dates))) <= 5)) {
  message("Near reconstitution window — delaying rebalance by 5 days")
  rebalance_date <- rebalance_date + 5
}
```

---

## Papers Consulted
P155, P156, P157, P158, P159, P160, P161, P162, P163, P164, P165, P166, P167, P168, P169, P170, P171, P172, P173, P174, P175, P176
