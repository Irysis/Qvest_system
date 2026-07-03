# Behavioral Finance Paper Analysis: Strategy Summary
## Papers P008–P020 | Chapter 2 Behavioral Bias Articles
**Date:** 2026-03-01 | **Universe:** KOSPI200 + KOSDAQ150 | **Analyst:** Q

---

## Overview

13 foundational behavioral finance papers (P008–P020) were analyzed for trading signal applicability in Korean markets. Papers span 1955–2007. Key context: Korean markets are ~60% retail-investor dominated, which amplifies behavioral biases relative to US/European markets. Confucian cultural dynamics further strengthen herding and conformity effects.

---

## Paper-by-Paper Applicability Summary

| ID | Paper | Bias | Korea Applicability | Feasibility | Key Signal |
|----|-------|------|---------------------|-------------|------------|
| P008 | Ellsberg (1961) | Ambiguity Aversion | MEDIUM | Medium | Low-analyst-coverage premium |
| P009 | Tversky & Kahneman (1973) | Availability Heuristic | MEDIUM | High | Short-term reversal (1-month) |
| P010 | Wason (1960) | Confirmation Bias | MEDIUM | Low | Strategy development protocol |
| P011 | Lord et al. (1979) | Biased Assimilation | MEDIUM | Medium | Analyst revision momentum |
| P012 | Crowder (1976) | Recency Bias | MEDIUM | High | 12m-1m momentum (Jegadeesh-Titman) |
| P013 | Shefrin & Statman (1985) | Disposition Effect | HIGH | High | UCGO (unrealized capital gain overhang) |
| P014 | Plott et al. (2007) | Endowment Disagreement | LOW | Low | Institutional ownership contrarian |
| P015 | Thaler (1980) | Mental Accounting | HIGH | High | Regime-conditional factor weights |
| P016 | Staw (1976) | Escalation of Commitment | HIGH | High | Capex-escalation vs. ROIC-decline |
| P017 | Tversky & Kahneman (1981) | Framing Effect | HIGH | Medium | 52-week high proximity |
| P018 | Asch (1955) | Herding / Conformity | HIGH | High | Volume-based herding signal |
| P019 | Odean (1998) | Overconfidence | HIGH | High | Abnormal volume reversal |
| P020 | Oskamp (1965) | Illusion of Knowledge | MEDIUM | Medium | Inverse analyst coverage |

---

## Strategy Ideas — Ranked by Priority

### TIER 1: Immediately Actionable (data available in current pipeline)

---

#### IDEA-A: Disposition Effect Factor — Unrealized Capital Gain Overhang (UCGO)
**Source:** P013 (Shefrin & Statman 1985), supported by P012 (Recency/Recency), P015 (Mental Accounting)
**Feasibility:** HIGH | **Data required:** OHLCVS price data only

**Theoretical basis:**
Investors with unrealized gains are reluctant to sell (loss aversion at the individual stock level). Stocks with high positive UCGO have a "supply overhang" from disposition sellers that creates selling pressure just above break-even. Conversely, stocks below average cost basis are held by loss-averse investors — creating sticky supply that paradoxically sustains prices near cost basis. The key trading insight: **positive UCGO stocks continue to outperform** because disposition sellers create price anchors below market — supply is thin above the gain threshold.

**Signal construction (R):**
```r
# UCGO: (current price - rolling 52-week avg price) / rolling 52-week avg price
# In OHLCVS parquet:
dt[, ucgo := (close - frollmean(close, 252, fill=NA)) / frollmean(close, 252, fill=NA)]
# Rank: long high positive UCGO (1st-2nd quintile) + quality filter
# Combine with: ROE > 0, DebtRatio < median
```

**Expected alpha:** Medium-term momentum (3-6 month holding period). UCGO is distinct from price momentum — it captures the behavioral supply/demand asymmetry, not trend-following.

**Korean edge:** Korean retail investors are among the most disposition-biased globally (KRX documented). Effect should be materially stronger than US estimates.

**Caution:** Avoid stocks in deep loss territory with deteriorating fundamentals (disposition + distress = compounding risk).

---

#### IDEA-B: Overconfidence / Abnormal Volume Reversal Factor
**Source:** P019 (Odean 1998), supported by P009 (Availability), P018 (Herding)
**Feasibility:** HIGH | **Data required:** OHLCVS volume + price data

**Theoretical basis:**
Overconfident retail investors generate abnormal trading volume. High abnormal volume combined with recent positive returns signals overconfidence-driven overvaluation — investors are trading on private signals they believe are more valuable than they are. This creates a predictable reversal pattern as the overconfident demand subsides.

**Signal construction (R):**
```r
# Abnormal volume: log ratio of recent volume to 90-day average
dt[, vol_ratio := log(frollmean(volume, 5, fill=NA) / frollmean(volume, 90, fill=NA))]
# Combine with recent 1-month return for overconfidence detection
dt[, overconf_signal := vol_ratio * ret_1m]  # high vol + high ret = overconfidence
# Alpha signal: short high overconf_signal (top quintile), long low (bottom quintile)
# Note: confirm fundamental filter — avoid shorting fundamentally strong stocks
```

**Expected alpha:** 1-3 month reversal horizon. Korea-specific: KOSDAQ retail activity makes this signal stronger in KOSDAQ names.

**Korean edge:** Korean retail investor turnover on KOSDAQ is among the highest in the world. Overconfidence signal should have higher IC on KOSDAQ150 sub-universe than KOSPI200.

---

#### IDEA-C: Escalation-of-Commitment Capital Destruction Factor
**Source:** P016 (Staw 1976), supported by P015 (Mental Accounting / Sunk Cost)
**Feasibility:** HIGH | **Data required:** DART fundamentals (capex, ROIC/ROA)

**Theoretical basis:**
Corporate managers exhibit escalation of commitment — continuing to increase capital investment in failing projects due to sunk cost fallacy and personal accountability. This creates systematic value destruction: companies with declining returns on capital but increasing capital investment are destroying value at the margin. Markets are slow to price this because confirmation bias (P010, P011) leads analysts to interpret continued investment as confidence rather than entrapment.

**Signal construction (R):**
```r
# Escalation score: high capex growth + negative ROIC trend
# Using DART: OperatingCF/TotalAssets as ROIC proxy
dt[, roic_trend := roic - lag(roic, 2)]  # 2-year ROIC change
dt[, capex_trend := (capex_t / assets_t) - (capex_t2 / assets_t2)]  # 2-year capex/assets change
dt[, escalation_flag := (capex_trend > 0) & (roic_trend < 0)]
# Long: capex_trend < 0 AND roic_trend > 0 (rational capital allocators)
# Short: escalation_flag = TRUE AND roic < 0 (confirmed value destroyers)
```

**Expected alpha:** 12-month holding period. Factor is slow-moving — quarterly rebalance sufficient. Strong overlap with Asset Growth factor (STR being planned) but adds the ROIC-deterioration condition.

**Korean edge:** Chaebol affiliates are particularly prone to escalation bias — group-level accountability dynamics amplify the effect. Exclude parent holding companies but include listed subsidiaries.

---

#### IDEA-D: 52-Week High Proximity (Framing) Factor
**Source:** P017 (Tversky & Kahneman 1981 Framing), supported by P009 (Availability), P013 (Disposition)
**Feasibility:** HIGH | **Data required:** OHLCVS price data only

**Theoretical basis:**
George & Hwang (2004) documented that 52-week high proximity is a stronger predictor of returns than traditional momentum. The behavioral mechanism (from P017) is framing: investors use the 52-week high as a reference point ("anchor"). Stocks near the 52-week high face resistance — sellers frame a sale at peak as "getting all their money back." Stocks far from the 52-week high are framed as "losers" even if fundamentally sound, creating undervaluation.

**Signal construction (R):**
```r
# 52-week high ratio: current price / 52-week high
dt[, high_52w := frollapply(high, 252, max, fill=NA)]
dt[, high52_ratio := close / high_52w]
# Long: high high52_ratio (near 52-week high but not already broken out) + positive momentum
# This is a distinct signal from pure momentum — captures reference-point psychology
```

**Expected alpha:** 3-6 month holding period. Research shows this factor has higher IC than 12-month momentum in several Asian markets.

**Korean edge:** Korean retail investors are particularly anchored to round numbers and historical highs (consistent with Confucian respect for precedent/history as reference points).

---

### TIER 2: Promising but Requires Additional Data or Refinement

---

#### IDEA-E: Mental Accounting Regime-Conditional Factor Weighting
**Source:** P015 (Thaler 1980), supported by P012 (Recency), P017 (Framing)
**Feasibility:** MEDIUM | **Data required:** Macro regime data (already in macro_regime.parquet)

**Theoretical basis:**
Mental accounting's "house money effect" implies risk tolerance is state-dependent: after gains, investors are more risk-seeking (momentum strategies work); after losses, more risk-averse (value/reversal strategies work). This provides a behavioral justification for the regime-conditional factor weighting already partially implemented in STR_011.

**Implementation:**
Extend the existing macro regime framework (macro_regime.parquet) to condition factor weights based on prior 3-month market return:
- Bull regime (positive 3-month market return): increase weight on momentum factors (UCGO, 52-week high)
- Bear regime (negative 3-month market return): increase weight on value/quality factors (escalation-fade, ROE)

**Note:** This is an enhancement to the existing infrastructure rather than a new standalone strategy.

---

#### IDEA-F: Herding Intensity as Momentum Amplifier / Reversal Predictor
**Source:** P018 (Asch 1955)
**Feasibility:** MEDIUM | **Data required:** Institutional buy/sell transaction data (not currently in pipeline)

**Theoretical basis:**
LSV (Lakonishok-Shleifer-Vishny 1992) herding measure requires institutional transaction-level data (buy count / total trade count per stock per quarter). Korean data may be accessible via KRX institutional trading data if procured.

**Proxy approach (with current data):**
```r
# Herding proxy: abnormal institutional volume (if available)
# Alternative: use relative volume + price correlation as herding proxy
# High-volume + high cross-stock correlation among sector peers = herding signal
```

**Status:** Promising but requires KRX institutional block-trade data. Flag for future data procurement.

---

#### IDEA-G: Analyst Coverage Asymmetry (Ambiguity + Illusion of Knowledge)
**Source:** P008 (Ellsberg 1961) + P020 (Oskamp 1965)
**Feasibility:** MEDIUM | **Data required:** Proxy via DART filing frequency

**Theoretical basis:**
Two complementary papers point to the same tradeable anomaly:
- P008 (Ambiguity Aversion): Low-coverage stocks are undervalued because investors demand an ambiguity premium
- P020 (Illusion of Knowledge): High-coverage stocks may be MORE overconfident (analysts have more information but not more accuracy), creating overvaluation

Combined: **low analyst coverage = undervalued / high analyst coverage = potentially overconfident and overvalued**. This is the "neglected firm" anomaly with dual theoretical backing.

**Proxy signal:**
```r
# DART filing frequency as coverage proxy
# Count DART filings per ticker per year from data_collector_dart.R output
# Low filers (bottom tercile) = high ambiguity = potentially undervalued
# Combine with fundamental quality screen to avoid distressed neglected firms
```

**Caution:** Liquidity must be strictly controlled — low-coverage firms may have insufficient liquidity for KOSPI200+KOSDAQ150 universe execution.

---

### TIER 3: Theoretical Interest Only (No Immediate Implementation Path)

| Idea | Source | Reason for Tier 3 |
|------|--------|-------------------|
| Confirmation Bias Strategy Protocol | P010 | Development methodology, not a trading signal |
| Biased Assimilation / Analyst Revision | P011 | Requires sell-side consensus data (not in pipeline) |
| Endowment Effect / Institutional Ownership Contrarian | P014 | Requires institutional ownership data (KRX) |
| Availability Reversal (short-term) | P009 | Already partially captured by existing momentum/reversal signals |

---

## Composite Strategy Proposal: "Behavioral Alpha Composite"

**Combining Tier 1 ideas into a single factor composite:**

| Factor | Weight | Direction | Holding Period |
|--------|--------|-----------|----------------|
| UCGO (Disposition) | 30% | Long positive UCGO | 3-6 months |
| Overconfidence / Abnormal Volume | 25% | Short high vol+ret | 1-3 months |
| Escalation-Fade (Capex vs. ROIC) | 25% | Short escalators | 12 months |
| 52-Week High Proximity | 20% | Long near-high | 3-6 months |

**Regime gate:** Apply only in non-crisis regimes (STR_011 macro gate logic). In VIX crisis: cash out behaviorally-driven factors first (they lose IC in crisis as behavior becomes uniform).

**Expected properties:**
- Low overlap with existing factors (STR_001–011): UCGO and Overconfidence are not currently implemented
- Complements LowVol + Macro Gate (STR_011) as an alpha layer
- Moderate turnover (quarterly rebalance for escalation; monthly for UCGO and volume)
- Korean retail dominance provides durable edge — structural rather than arbitrage-away risk

**Suggested strategy ID:** STR_014 candidate after STR_012 (Accrual) and STR_013 (QMJ) are completed.

---

## Key Cross-Paper Insights for Korea

1. **Retail dominance amplifies all biases**: Korean market's 60% retail composition means biases documented in US (with ~25% retail) will be 1.5–2x stronger in Korea. Factor ICs should be higher.

2. **KOSDAQ vs. KOSPI differentiation**: Overconfidence (P019) and Availability (P009) effects will be stronger in KOSDAQ150. Quality filters are essential to avoid KOSDAQ distress.

3. **Chaebol structure amplifies escalation bias (P016)**: Corporate governance weakness in chaebol affiliates means the escalation-fade factor should have particular strength in the Korean listed universe.

4. **Recency + Framing interaction (P012 + P017)**: The 52-week high anchor effect (P017) is reinforced by recency bias (P012) — investors both remember recent highs AND give them disproportionate weight as reference points. This double mechanism makes the 52-week-high factor more robust in Korea.

5. **Herding + Mental Accounting (P018 + P015)**: The Confucian group-harmony dynamic in Korea makes Asch-style herding (P018) particularly strong institutionally. Combined with house-money mental accounting (P015), bull markets in Korea tend to overshoot more than developed markets, and bear markets revert more sharply — supporting the regime-gating approach of STR_011.

---

## Lessons for Strategy Development Process

From P010 (Confirmation Bias / Wason) applied to our own process:
- Pre-register factor hypotheses before computing IC
- Actively test in failing regimes (2008, 2020) not just in-sample bull periods
- The hurdle_gate.R D062 (OOS validation) and D063 (IC Stability) exist precisely to counter confirmation bias in strategy selection
- Do not stop testing after the first passing scenario — run the full temporal stress suite

---

## Registry Update
- **Papers updated:** P008–P020 → status: "analyzed" in paper_registry.json
- **Notes written:** research_output/paper_notes/P008.md through P020.md
- **Strategy ideas generated:** 7 (IDEA-A through IDEA-G)
- **Immediate next steps:** Implement IDEA-A (UCGO) and IDEA-B (Abnormal Volume) as alpha factors in next strategy after STR_013

---
*Generated by Q — Quant Module Moltbot research pipeline*
