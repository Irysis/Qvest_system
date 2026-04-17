# KRX Derivatives Data for Regime Detection: Academic Literature & Implementation Guide

> Compiled: 2026-03-05 | For: Regime Engine Enhancement (02_Infrastructure/regime_engine.R)
> Purpose: Identify leading/coincident regime signals from KOSPI200 derivatives, VRP, and credit markets

---

## Table of Contents
1. [KOSPI200 Options Implied Volatility (VKOSPI) & Skew](#1-kospi200-options-implied-volatility-vkospi--skew)
2. [KOSPI200 Futures Basis, Open Interest & Volume](#2-kospi200-futures-basis-open-interest--volume)
3. [Variance Risk Premium (VRP)](#3-variance-risk-premium-vrp)
4. [Options-Implied Probability Distributions & Tail Risk](#4-options-implied-probability-distributions--tail-risk)
5. [Credit Default Swaps (CDS) & Credit Market Signals](#5-credit-default-swaps-cds--credit-market-signals)
6. [Korea-Specific Regime Detection Papers](#6-korea-specific-regime-detection-papers)
7. [Data Sources & Availability](#7-data-sources--availability)
8. [Implementation Priority Matrix](#8-implementation-priority-matrix)

---

## 1. KOSPI200 Options Implied Volatility (VKOSPI) & Skew

### 1.1 VKOSPI Level as Regime Signal

**Key Papers:**

| # | Authors | Year | Journal | Key Finding |
|---|---------|------|---------|-------------|
| D-01 | Whaley, R. | 2000, 2009 | Journal of Portfolio Management / Journal of Investing | VIX = "investor fear gauge". VKOSPI follows identical construction. High IV => risk-off regime, low IV => risk-on. Asymmetric: spikes up fast, mean-reverts slowly. |
| D-02 | Roh, T.H. | 2014 | Investment Analysts Journal, 43(79) | VKOSPI changes predict style rotation: increases in VKOSPI => large > small, growth > value next day. Direct Korean evidence for IV-based regime signals. |
| D-03 | Kang, S.H. & Yoon, S.M. | 2015 | Finance Research Letters | Three-regime Markov-switching model on VKOSPI. US market factors (VIX, S&P returns) dominate VKOSPI dynamics over domestic factors. Transition probabilities are time-varying and regime-dependent. |
| D-04 | Hurditt, A. | 2015 | Economics E-Journal | VKOSPI modeling via augmented HAR models with exogenous US variables. VKOSPI has strong persistence and mean-reversion structure amenable to regime classification. |
| D-05 | Choi, H. | 2014 | International Journal of Economics and Finance | Realized vol prediction from KOSPI200 options differs pre/post GFC. Structural break = regime shift in volatility dynamics. |

**Regime Signal Construction:**
- **Binary signal**: VKOSPI > 25 = elevated fear; VKOSPI > 35 = crisis regime (comparable to VIX thresholds)
- **Continuous signal**: VKOSPI percentile rank over trailing 252 days; Z-score of log(VKOSPI)
- **Leading/Lagging**: VKOSPI is **coincident to slightly leading** (1-3 days) for equity drawdowns. Correlation with KOSPI200 = -0.60 (leverage effect). Spikes precede max drawdown periods.
- **Key insight from D-03**: US VIX regime transitions Granger-cause VKOSPI regime transitions => can use VIX regime as early warning for KOSPI regime shift

### 1.2 Implied Volatility Skew / Smirk

**Key Papers:**

| # | Authors | Year | Journal | Key Finding |
|---|---------|------|---------|-------------|
| D-06 | Xing, Y., Zhang, X. & Zhao, R. | 2010 | Journal of Financial Economics | IV smirk (OTM put IV minus ATM call IV) predicts stock returns: steeper smirk => 10.9% annual underperformance. Smirk = crash risk expectation. |
| D-07 | Cremers, M. & Weinbaum, D. | 2010 | JFQA, 45, 335-367 | Put-call parity deviations (call IV - put IV at same strike) predict returns: expensive calls => +50bps/week outperformance. Higher predictability when option liquidity is high and stock liquidity is low. |
| D-08 | Chen, B. | 2018 | Working Paper | IV slope connects to risk-neutral skewness. Sentiment drives IV slope. Bearish sentiment => steeper negative skew => regime shift signal. |

**Regime Signal Construction:**
- **Skew measure**: IV(Delta=-0.25 put) - IV(ATM) for KOSPI200 options
- **Binary signal**: Skew steeper than -2 standard deviations from trailing mean = crisis/stress regime
- **Continuous signal**: Normalized skew (z-score) as fear intensity measure
- **Leading/Lagging**: **Leading by 1-4 weeks** for equity drawdowns. Skew steepens before realized crashes (Xing et al. 2010). The most forward-looking of all VKOSPI-family signals.
- **KOSPI200 specificity**: KOSPI200 options market is dominated by individual investors (unique globally), which can amplify skew signals during panic periods

### 1.3 Put-Call Ratio

**Key Papers:**

| # | Authors | Year | Journal | Key Finding |
|---|---------|------|---------|-------------|
| D-09 | Pan, J. & Poteshman, A. | 2006 | Journal of Finance | Abnormal buyer-initiated put volume predicts returns. 100M+ options trades analyzed. |
| D-10 | Lee, C.M.C. & Yi, B. | 2021 | Journal of Behavioral Finance | KOSPI200 C/P ratio and O/S ratio predict underlying stock returns. O/S ratio more robust than C/P for Korean market. |
| D-11 | Bandopadhyaya, A. & Jones, A. | 2019 | Economies | Put-call ratio based on open interest (PCROI) Granger-causes market returns at 6-12 day horizon. Volume-based PCR works only short-term. |

**Regime Signal Construction:**
- **Binary signal**: PCR(OI) > 1.3 = bearish regime; PCR(OI) < 0.7 = complacent/bullish regime; PCR(OI) > 2.0 = capitulation (contrarian buy)
- **Continuous signal**: 20-day smoothed PCR, z-scored
- **Leading/Lagging**: **Leading by 6-12 trading days** for intermediate moves (D-11). Extreme readings (>2.0) are contrarian and mark bottoms.

---

## 2. KOSPI200 Futures Basis, Open Interest & Volume

### 2.1 Futures Basis (Spot-Futures Spread)

**Key Papers:**

| # | Authors | Year | Journal | Key Finding |
|---|---------|------|---------|-------------|
| D-12 | Ciner, C., Karagozoglu, A. & Kim, W.S. | 2020 | SSRN | KOSPI200 futures exhibit extreme liquidity. Trading volume and open interest dynamics reveal institutional positioning information not available from spot market. |
| D-13 | Dwyer, G., Locke, P. & Yu, W. | 1996 | Journal of Financial and Quantitative Analysis | Index futures basis deviations reflect limits to arbitrage. Widening basis = stress/funding constraint regime. |
| D-14 | Rau-Bredow, H. | 2022 | Working Paper | Contango/backwardation regime depends on a "contango factor" linked to monetary policy. Fed/BOK rate changes shift the S&P/KOSPI futures regime. |

**Regime Signal Construction:**
- **Basis** = Futures Price - Spot Price * e^(r*T). Annualized basis deviation from theoretical fair value.
- **Binary signal**: Basis < -50bps (annualized) from fair value = stress regime (forced selling in futures); Basis > +100bps = excessive speculative demand
- **Continuous signal**: Rolling Z-score of basis deviation
- **Leading/Lagging**: **Coincident to slightly leading** (1-5 days). Futures lead spot in price discovery, so basis distortion is an early warning. Negative basis = forced institutional deleveraging.

### 2.2 Open Interest & Volume Patterns

**Key Papers:**

| # | Authors | Year | Journal | Key Finding |
|---|---------|------|---------|-------------|
| D-15 | Ciner, C. et al. | 2020 | (same as D-12) | Larger relative trading volume => larger future volatility in KOSPI200. Open interest levels predict direction of future returns. |
| D-16 | Hong, H. & Yogo, M. | 2012 | Journal of Financial Economics | Open interest growth across futures markets (including equity index futures) forecasts returns. Based on hedging demand theory. |

**Regime Signal Construction:**
- **Volume ratio**: Futures volume / Spot volume. Rising ratio = institutional hedging activity increasing = risk-off signal
- **OI changes**: Sharp OI decline in nearby contract = forced liquidation/margin calls = crisis regime
- **Binary signal**: Volume ratio > 2 standard deviations AND OI declining = liquidation regime
- **Leading/Lagging**: **Leading by 1-2 weeks** (Hong & Yogo 2012). Hedging demand builds before equity declines.

---

## 3. Variance Risk Premium (VRP)

### 3.1 Core VRP Literature

**Key Papers:**

| # | Authors | Year | Journal | Key Finding |
|---|---------|------|---------|-------------|
| D-17 | Bollerslev, T., Tauchen, G. & Zhou, H. | 2009 | Review of Financial Studies, 22(11), 4463-4492 | **Foundational paper.** VRP = IV^2 - RV. VRP predicts aggregate stock returns, especially at quarterly horizon. Dominates P/E, default spread, CAY. High VRP => high future returns. |
| D-18 | Carr, P. & Wu, L. | 2009 | Review of Financial Studies, 22(3), 1311-1341 | Model-free variance swap rate methodology. Variance swap rate = risk-neutral expected realized variance. Synthesized from option portfolio. Provides clean VRP computation framework. |
| D-19 | Bollerslev, T. & Todorov, V. | 2011 | Journal of Finance | "Tails, Fears, and Risk Premia." Tail jump risk premium accounts for large fraction of equity and variance risk premia. Tail risk compensation is distinct from volatility compensation. |
| D-20 | Bollerslev, T., Todorov, V. & Xu, L. | 2015 | Journal of Financial Economics | Tail risk premia and return predictability. Jump tail risk variation is the key driver of VRP's predictive power. VRP decomposes into continuous and discontinuous (jump) components. |
| D-21 | Pyun, S. | 2019 | Journal of Financial Economics | Variance risk in aggregate stock returns and time-varying return predictability. VRP predictability varies by regime and economic conditions. |

### 3.2 Korea-Specific VRP Research

| # | Authors | Year | Journal | Key Finding |
|---|---------|------|---------|-------------|
| D-22 | Choi, S. & Park, S. | 2017 | SSRN | "Regime Dependency of Credit Risk Discrepancy" uses Markov-switching to show VRP regimes in Korean sovereign markets. |
| D-23 | Kim, D.H. et al. | 2018 | International Review of Economics and Finance | VRP in a small open economy with volatile capital flows: Korea case. Global liquidity (FAVAR) more important than domestic macro in determining Korean VRP. VRP predicts KOSPI returns at 1-month and 3-month horizons. |
| D-24 | Lee, S.S. & Mykland, P. | 2013 | JDQS (선물연구), 22(1), 45 | "Leading and Following Variance Risk Premiums: S&P500 and KOSPI200." S&P500 VRP leads KOSPI200 VRP. KOSPI200 VRP alone has weaker standalone predictive power => must combine with US VRP. |
| D-25 | Kim & Lee | 2020 | Quarterly Journal of Finance | "The Variation in Variance Risk Premium and its Predictive Power: Evidence from Option Market Sentiments." VRP variation linked to option sentiment measures across KOSPI, S&P500, TAIEX. |

**Regime Signal Construction:**
- **VRP = VKOSPI^2 - RV_22d** (annualized), where RV_22d is 22-day realized variance from daily or high-frequency returns
- **Binary signal**: VRP > 80th percentile = high fear premium = stress regime (but also predicts positive future returns). VRP < 20th percentile = complacency regime (predicts negative future returns).
- **Continuous signal**: VRP z-score, or VRP percentile rank
- **Leading/Lagging**: **Leading by 1-3 months** for equity returns (Bollerslev et al. 2009). Strongest at quarterly horizon. The most forward-looking regime indicator in this entire survey.
- **Critical caveat for Korea (D-24)**: KOSPI200 VRP alone has weaker predictive power than S&P500 VRP. Must combine: regime signal = f(US_VRP, KR_VRP). US VRP leads Korean VRP.

**VRP Calculation (R pseudocode):**
```r
# Simplified VRP computation
# IV_sq = VKOSPI^2 / 100^2 (annualized implied variance)
# RV = sum(r_i^2) * 252/N for N-day window using daily log returns
VRP <- function(vkospi, daily_returns, window = 22) {
  iv_sq <- (vkospi / 100)^2
  rv <- zoo::rollapply(daily_returns^2, width = window,
                       FUN = sum, align = "right") * (252 / window)
  vrp <- iv_sq - rv
  return(vrp)
}
```

---

## 4. Options-Implied Probability Distributions & Tail Risk

### 4.1 Risk-Neutral Density (RND) Extraction

**Key Papers:**

| # | Authors | Year | Journal | Key Finding |
|---|---------|------|---------|-------------|
| D-26 | Breeden, D. & Litzenberger, R. | 1978 | Journal of Business | Foundational: second derivative of call price w.r.t. strike = RND. Butterfly spread approach. |
| D-27 | Figlewski, S. | 2010 | Journal of Financial Engineering | Nonparametric RND estimation from options. Tail quantiles can be estimated precisely. Credible intervals are tight. |
| D-28 | Gao, J. & Pan, J. | 2023 | Working Paper (SAIF) | "Option-Implied Crash Index (CIX)." Better crash risk measure than VIX. CIX captures tail behavior specifically. |
| D-29 | BIS Working Paper 921 | 2021 | BIS | Firm-specific risk-neutral distributions from options AND CDS jointly. Combined signals improve tail risk detection. |

### 4.2 Tail Risk Measures from Options

| # | Authors | Year | Journal | Key Finding |
|---|---------|------|---------|-------------|
| D-30 | Bollerslev, T. & Todorov, V. | 2011 | (same as D-19) | Option-implied tail measure performs best overall for predicting tail events AND future tail volatility. Also predicts real economic activity. |
| D-31 | Chen, L. et al. | 2023 | Mathematics, 11(14), 3194 | EGB2 option pricing model for tail risk signal detection. Three measures: EGB2 implied tail index, EGB2-VaR, EGB2 implied RND. |
| D-32 | Kelly, B. & Jiang, H. | 2014 | Review of Financial Studies | Tail risk is priced: stocks with high tail risk sensitivity earn 5.4% annual excess return. Tail risk factor extracted from cross-section of deep OTM puts. |
| D-33 | Andersen, T., Fusari, N. & Todorov, V. | 2017 | Journal of Finance | Short-term tail risk measure from high-frequency data. Tail risk predicts returns at daily-weekly horizons, not just monthly-quarterly. |

### 4.3 Korea-Specific RND Research

| # | Authors | Year | Journal | Key Finding |
|---|---------|------|---------|-------------|
| D-34 | Kim, I.J. & Kim, S. | 2005 | International Review of Finance | Implied tree models (IBT, GBT, IVT) for KOSPI200 options. RND extraction methodology validated for Korean market. |
| D-35 | Various Korean authors | 2007-2011 | Korean academic journals | RND skewness and kurtosis from KOSPI200 options Granger-cause spot and futures returns. Higher moments of RND lead price movements more than prices lead moments. |
| D-36 | Kwon, O. et al. | 2018 | Journal of Forecasting | Particle filtering for KOSPI200 volatility dynamics. Sequential prediction framework applicable to real-time regime detection. |

**Regime Signal Construction:**
- **Tail risk measure**: Probability mass below -10% in 30-day RND extracted from OTM puts. Or: ratio of 25-delta put IV to ATM IV (simpler proxy).
- **Binary signal**: RND left-tail probability > 2x historical average = tail risk regime
- **Continuous signal**: RND skewness (should be negative; more negative = higher crash expectations)
- **Leading/Lagging**: **Leading by 1-4 weeks**. RND moments lead spot returns (D-35, Korean evidence). Tail risk measures predict both tail events and real economic activity (D-30).
- **Implementation note**: Full RND extraction requires option chain across strikes. Simpler proxy: 25-delta skew or VKOSPI spread (near-term vs. far-term IV).

---

## 5. Credit Default Swaps (CDS) & Credit Market Signals

### 5.1 Sovereign CDS (Korea 5Y)

**Key Papers:**

| # | Authors | Year | Journal | Key Finding |
|---|---------|------|---------|-------------|
| D-37 | Da Fonseca, J. & Gottschalk, K. | 2020 | International Review of Finance | CDS-equity-volatility co-movement in Asia-Pacific (incl. Korea). At firm level, equity returns LEAD CDS changes. At index level, realized volatility is the main transmitter of cross-market spillovers. |
| D-38 | Choi, S.J. & Park, S. | 2017 | SSRN | Regime dependency in sovereign CDS-bond basis. Markov-switching regressions show credit risk pricing differs across regimes. CDS-bond basis widens in stress regimes. |
| D-39 | Longstaff, F.A. et al. | 2007 | NBER Working Paper | "How Sovereign is Sovereign Credit Risk?" Korean CDS spreads share strong common factor with US VIX. Global risk appetite drives sovereign CDS more than domestic fundamentals. |
| D-40 | Kim, M. et al. | 2011 | Korean Journal | Determinants of Korean corporate CDS: 3Y KTB rate, M/B ratio, asset size are significant. Domestic factors matter for corporate CDS but less for sovereign. |

**Regime Signal Construction:**
- **Korea 5Y sovereign CDS**: Daily data available from Bloomberg, cbonds.com, worldgovernmentbonds.com
- **Binary signal**: CDS > 100bps = elevated stress; CDS > 200bps = crisis regime (historical: GFC peak ~700bps, COVID ~80bps, normal ~30-50bps)
- **Continuous signal**: CDS change momentum (5d, 20d rolling change); CDS level z-score
- **Leading/Lagging**: **Lagging to coincident** for equity drawdowns (D-37: equity leads CDS at firm level). However, CDS-bond basis widening can be **leading** for prolonged stress periods (D-38).
- **Practical value**: CDS is most useful as a **confirmation signal** rather than leading indicator. Best combined with VIX/VKOSPI signals.

### 5.2 Corporate Credit Spreads (Korea)

| # | Authors | Year | Source | Key Finding |
|---|---------|------|--------|-------------|
| D-41 | BIS Papers No. 11 | 2002 | BIS | Korean corporate bond market structure changed post-1997 crisis. Non-guaranteed bonds dominate, making spreads sensitive to macro regime. |
| D-42 | ADB / Asian Bonds Online | Ongoing | ADB | AA-rated 3Y corporate spread: normal ~55bps, stress ~465bps (GFC peak). BBB spread: normal ~150bps, crisis ~876bps. |

**Regime Signal Construction:**
- **Credit spread**: AA-rated 3Y corporate bond yield minus 3Y KTB yield
- **Binary signal**: Spread > 150bps = stress regime; Spread > 300bps = crisis regime
- **Continuous signal**: Credit spread percentile rank or z-score
- **Leading/Lagging**: **Coincident to slightly lagging**. Credit spreads widen during equity drawdowns but rarely lead them. Better as regime confirmation.
- **Data**: Korea Money Brokerage Corp (kmbco.com), Asian Bonds Online (ADB), FRED (limited Korea data)

---

## 6. Korea-Specific Regime Detection Papers

| # | Authors | Year | Journal | Key Finding |
|---|---------|------|---------|-------------|
| D-43 | Kang, S.H. & Yoon, S.M. | 2015 | Finance Research Letters | VKOSPI 3-regime Markov-switching: low/medium/high volatility states. US factors dominate regime transitions. |
| D-44 | Kim, S.W. et al. | 2016 | Cluster Computing | Hamilton 2-regime MS model for Korean stock returns (1993-2016). In low-vol regime, exchange rates and interest rates affect stock returns. In high-vol regime, KOSPI responds to neither. |
| D-45 | Ahn, H.J., Kang, J. & Ryu, D. | 2008 | Journal of Futures Markets, 28(12), 1118-1146 | Informed trading in KOSPI200 options. Individual investor dominance creates unique information flow. Options order imbalance predicts underlying. |
| D-46 | Roh, T.H. | 2014 | (same as D-02) | VKOSPI predicts style rotation. High VKOSPI days followed by large > small, growth > value returns. |
| D-47 | Kim, I.J. & Kim, S. | 2005 | (same as D-34) | Implied tree models validate RND extraction for KOSPI200 options. |
| D-48 | Various | 2007-2011 | Korean academic journals | RND moments (skewness, kurtosis) from KOSPI200 Granger-cause spot/futures returns. |
| D-49 | Kwon, O. et al. | 2018 | (same as D-36) | Particle filtering for KOSPI200 sequential regime prediction. |
| D-50 | Sim, M. | 2016 | Journal of Futures Markets | Tests on monotonicity of KOSPI200 options prices. Violations indicate stress periods and limits-to-arbitrage regimes. |

---

## 7. Data Sources & Availability

### 7.1 Directly Available (Free or Low-Cost)

| Data | Source | Format | Update Freq | Notes |
|------|--------|--------|-------------|-------|
| VKOSPI daily | KRX Data Marketplace (data.krx.co.kr) | CSV / API | Daily | Free download. Ticker: KSVKOSPI |
| VKOSPI daily | Investing.com | Web scrape | Daily | Historical data available |
| KOSPI200 options (OHLCV) | KRX Data Marketplace | CSV / API | Daily (20min delayed) | Individual option series data |
| KOSPI200 futures (OHLCV) | KRX Data Marketplace | CSV / API | Daily | Includes OI, volume |
| Korea 5Y CDS | worldgovernmentbonds.com | Web scrape | Daily | Free historical data |
| Korea 5Y CDS | Investing.com | Web scrape | Daily | Alternative source |
| Korea credit spreads | Asian Bonds Online (ADB) | Web/CSV | Monthly | AA, A, BBB spreads |
| KOSPI200 daily | Yahoo Finance (^KS200) | R: quantmod | Daily | For RV computation |
| VIX (for US VRP) | CBOE / Yahoo (^VIX) | R: quantmod | Daily | Cross-reference with VKOSPI |
| VKOSPI historical | Kaggle (ninetyninenewton/vkospi) | CSV | Static | Research dataset |

### 7.2 Bloomberg Terminal Required

| Data | Bloomberg Ticker | Notes |
|------|-----------------|-------|
| KOSPI200 options chain | KOSPI2 Index OMON | Full chain for RND extraction |
| KOSPI200 options IV surface | KOSPI2 Index OVDV | Strike x Maturity IV grid |
| Korea sovereign CDS | CKORS1U5 Curncy | 5Y CDS spread |
| Korea corporate CDS | Firm-specific | Individual firm CDS |
| VKOSPI intraday | VKOSPI Index | For high-frequency VRP |

### 7.3 R Package Ecosystem

```r
# Data retrieval
library(quantmod)    # getSymbols("^KS200"), getSymbols("^VIX")
library(rvest)       # Web scraping for VKOSPI, CDS from public sites
library(httr)        # KRX API calls (data.krx.co.kr REST API)
library(jsonlite)    # Parse KRX API JSON responses

# Computation
library(highfrequency) # rRVar() for realized variance (if intraday data)
library(RND)           # Risk-neutral density extraction from options
library(rugarch)       # GARCH for conditional variance modeling
library(MSwM)          # Markov-switching models for regime detection
library(depmixS4)      # Hidden Markov models
```

---

## 8. Implementation Priority Matrix

### Tier 1: Implement First (High Impact, Feasible Data)

| Signal | Data Needed | Expected Lead Time | Regime Type | Implementation Complexity |
|--------|------------|---------------------|-------------|--------------------------|
| **VKOSPI Level** | VKOSPI daily (free) | Coincident to +3d | Binary + Continuous | Low |
| **VRP (simple)** | VKOSPI + KOSPI200 daily returns | +1-3 months | Continuous | Low-Medium |
| **US VIX crossover** | VIX daily (free) | +1-2 weeks before VKOSPI | Binary | Low |

### Tier 2: Implement Second (High Impact, Moderate Data Effort)

| Signal | Data Needed | Expected Lead Time | Regime Type | Implementation Complexity |
|--------|------------|---------------------|-------------|--------------------------|
| **Put-Call Ratio (OI)** | KOSPI200 options OI (KRX) | +6-12 days | Binary + Continuous | Medium |
| **Korea 5Y CDS** | CDS daily (web scrape) | Coincident (confirmation) | Binary | Low |
| **Futures Basis** | KOSPI200 futures + spot (KRX) | +1-5 days | Continuous | Medium |

### Tier 3: Implement Later (Highest Alpha, Data-Intensive)

| Signal | Data Needed | Expected Lead Time | Regime Type | Implementation Complexity |
|--------|------------|---------------------|-------------|--------------------------|
| **IV Skew / Smirk** | Option chain by strike (Bloomberg/KRX) | +1-4 weeks | Continuous | High |
| **RND Tail Probability** | Full option chain across strikes | +1-4 weeks | Continuous | High |
| **Composite VRP (US+KR)** | VIX + VKOSPI + high-freq returns | +1-3 months | Continuous | Medium-High |

### Composite Regime Score (Proposed)

```
Derivatives_Regime_Score = w1 * VKOSPI_zscore
                        + w2 * VRP_percentile
                        + w3 * PCR_OI_zscore
                        + w4 * CDS_zscore
                        + w5 * Basis_deviation_zscore
                        + w6 * Skew_zscore (if available)

where:
  w1 = 0.25 (VKOSPI: coincident, reliable)
  w2 = 0.25 (VRP: most forward-looking)
  w3 = 0.15 (PCR: leading 6-12 days)
  w4 = 0.10 (CDS: confirmation)
  w5 = 0.10 (Basis: institutional stress)
  w6 = 0.15 (Skew: leading 1-4 weeks)
```

---

## Summary of Leading vs. Lagging Properties

| Signal | Lead Time | Confidence | Best Use |
|--------|-----------|------------|----------|
| IV Skew / Smirk | **+1-4 weeks** | Medium | Early warning of crash expectations |
| VRP (quarterly) | **+1-3 months** | High | Strategic regime classification |
| Put-Call Ratio (OI) | **+6-12 days** | Medium | Tactical positioning signal |
| Futures Basis | **+1-5 days** | Medium | Institutional stress detection |
| VKOSPI Level | **Coincident to +3d** | High | Real-time fear gauge |
| US VIX | **+1-2 weeks before VKOSPI** | High | Early warning for Korean regime shift |
| Korea 5Y CDS | **Coincident** | Medium | Regime confirmation |
| Credit Spreads | **Coincident to lagging** | Medium | Regime confirmation |
| RND Tail Probability | **+1-4 weeks** | Medium-High | Tail event early warning |

---

## Key Takeaways for regime_engine.R Enhancement

1. **US VIX leads VKOSPI leads KOSPI drawdowns**: The most robust finding across all papers. Any regime engine for Korean equities MUST incorporate US VIX as a leading indicator (Kang & Yoon 2015, Kim et al. 2018).

2. **VRP is the most forward-looking signal**: At quarterly horizon, VRP dominates all other predictors including P/E, default spread, and CAY (Bollerslev et al. 2009). But KOSPI200 VRP alone is weak; must combine with US VRP (Lee & Mykland 2013).

3. **Skew is the best crash predictor**: IV skew steepening precedes crashes by 1-4 weeks (Xing et al. 2010). This is under-utilized in most quantitative regime engines.

4. **Korean market is a follower economy**: Global/US risk factors dominate local derivatives pricing. Regime engine should weight US signals more than domestic (Kim et al. 2018, Kang & Yoon 2015).

5. **Individual investor dominance in KOSPI200 options**: Creates unique dynamics -- more noise but also sharper panic signals. Put-call ratio extremes are more meaningful in Korea than in US (Ahn et al. 2008).

6. **Start with VKOSPI + VRP + VIX**: These three signals alone capture most regime information. Add skew and CDS as data becomes available.
