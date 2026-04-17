# STRATEGIC SUMMARY: Liquidity Factor Cluster (P101–P120)
**Analyzed:** 2026-03-01 | **Papers:** 18 (P101-P104, P106-P113, P116-P120)

---

## 1. Best Liquidity Measure for Korean RAWDATA.parquet

**Recommendation: PRIMARY = Amihud ILLIQ + Annual Turnover (dual-measure composite)**

### Measure Rankings for Korean Daily OHLCVS Data

| Rank | Measure | Formula | Rationale | Strength |
|---|---|---|---|---|
| 1 | **Amihud ILLIQ** | `abs(ret) / (vol_krw / 1e8)` | Most cited, directly computable, captures price impact dimension | Cross-sectional (5-star), Time-series (3-star post-2000) |
| 2 | **Annual Turnover** (Ibbotson et al.) | `annual_vol / avg_shares_out` | Simplest, largest documented premium (7.26%/yr), independent of other factors | Cross-sectional (5-star), Annual (not monthly) |
| 3 | **Monthly Turnover** (Datar et al.) | `monthly_vol / shares_out` | High-frequency version; t ≈ -9 across 30 years | Cross-sectional (4-star) |
| 4 | **Liu LM12** | `(#zero_vol_days + 1/turnover/11000) × 252/n` | Captures trading gaps AND turnover; outperforms in two-factor model | Cross-sectional (4-star) |
| 5 | **Inverse Dollar Volume** | `1 / (vol_krw / 1e8)` | Drienko et al. (2019): dominates ILLIQ numerator; more robust post-2010 | Cross-sectional (3-star), More stable |
| 6 | **Roll Spread** | `2 * sqrt(-cov(Δret_t, Δret_{t-1}))` | Proxy for bid-ask spread without tick data; noisy | Microstructure (2-star) |

**Korean-specific calibration:**
- ILLIQ is near-zero for KOSPI200 large-caps post-2010 (per Drienko et al.) → use ILLIQ primarily for KOSDAQ universe
- Annual turnover remains meaningful across all capitalization sizes
- LM12 is especially powerful for KOSDAQ where zero-volume days are common

### Composite Construction

```r
# Two-measure liquidity composite for Korean stocks
compute_korea_liquidity_factor <- function(daily_data) {
  monthly_data <- daily_data %>%
    group_by(ticker, ym = format(date, "%Y-%m")) %>%
    summarise(
      # Amihud ILLIQ
      illiq = mean(abs(ret) / (volume_krw / 1e8), na.rm = TRUE),
      # Monthly turnover
      monthly_turn = sum(volume, na.rm = TRUE) / mean(shares_out, na.rm = TRUE),
      # Zero volume days (for LM12)
      n_zero_vol = sum(volume == 0 | is.na(volume)),
      n_days = n(),
      .groups = "drop"
    )

  monthly_data %>%
    group_by(ym) %>%
    mutate(
      # Cross-sectional ranks (higher rank = more illiquid = higher expected return)
      illiq_score = percent_rank(illiq),
      turn_score = 1 - percent_rank(monthly_turn),  # inverted: low turn = illiquid
      # Composite
      illiq_composite = (illiq_score + turn_score) / 2
    )
}
```

---

## 2. Screen vs. Signal: How to Use Liquidity

### Decision Framework

| Use Case | Measure | Universe | Evidence Quality |
|---|---|---|---|
| **Universe Screen** | Min ADV > 5B KRW | All | Strong: microcap exclusion (Hou et al.) |
| **Cross-sectional Signal (KOSDAQ)** | ILLIQ + LM12 composite | KOSDAQ150 | Strong |
| **Cross-sectional Signal (KOSPI200)** | Annual Turnover only | KOSPI200 | Moderate (premium weaker without microcaps) |
| **Regime Signal (aggregate)** | Market ILLIQ level | Market-wide | Strong at crisis points |
| **Position Sizing** | Square root impact model | All | Strong: industry standard |
| **Standalone L/S Factor** | Any | All | Weak (Robeco P110): avoid without other signals |

### Screen Tier (Mandatory)

Exclude stocks where:
- Average daily volume (20-day) < 3B KRW → cannot build/unwind position
- # zero-volume days in last month > 5 → structural liquidity problem
- Price < 1,000 KRW → penny stock dynamics

### Signal Tier (Optional, regime-conditional)

Use illiq_composite as a MODIFIER of the primary factor score:
- In normal regime: liquidity score weight = 10-20% of composite
- In liquidity crisis (VIX > 30, KRW/USD > 1,350): reduce weight to 0% (avoid liquidity traps)
- In post-crisis recovery: increase weight to 30% (illiquidity premium rebounds sharply)

---

## 3. Expected Korean Liquidity Premium

Based on the evidence across all 18 papers:

### Cross-sectional level effect (characteristic):
| Measure | US Annual Premium | Korea Estimate | Confidence |
|---|---|---|---|
| Amihud ILLIQ Q1-Q5 | 3-5% | 3-6% (KOSDAQ) / 1-2% (KOSPI200) | Medium |
| Annual Turnover Q1-Q4 | 7.26% | 4-6% | Medium |
| Monthly Turnover | ~5% | 3-5% | Medium |
| Liu LM12 D1-D10 | ~8% | 4-6% (KOSDAQ) | Medium |

**Korean premium likely lower for KOSPI200, higher for KOSDAQ** because:
1. KOSPI200 has larger, more liquid stocks → closer to where premium disappears (Hou et al.)
2. KOSDAQ has more structural illiquidity → premium should be persistent
3. Korean retail dominance creates more mispricing in illiquid names → larger premium

### Liquidity risk premium (PS-type):
| Evidence | Assessment |
|---|---|
| PS 2003 original: +7.5%/yr | Strong evidence, US 1966-1999 |
| PS out-of-sample 2000-2015: +8.2%/yr | Stronger out-of-sample |
| Pontiff-Singla 10/10 failures | Concerning |
| Korea: unknown | No published estimates |

**Korean PS gamma estimate:** Estimate expected to be positive but smaller than US. Korean market has more structural friction but PS gamma requires deep liquidity crises to show up strongly.

---

## 4. The Akbas et al. Question: Is Liquidity Unstable?

**Context:** Akbas et al. (P097, already analyzed) found that liquidity factor performance is regime-dependent and unstable across time periods.

**Evidence from P101-P120:**

| Paper | Evidence for Instability | Evidence Against |
|---|---|---|
| Drienko et al. (P119) | OUT-OF-SAMPLE ILLIQ premium largely disappears post-1997; change-point confirmed | Cross-sectional effect persists |
| Blitz et al. (P110) | "Not robust across time periods"; pre-2000 vs. post-2000 divergence | N/A |
| Pontiff-Singla (P118) | Pre-1962 premium is -2.72%/yr (negative!) | In-sample replication successful |
| Li-Novy-Marx-Velikov (P108) | Monthly rebalancing yields insignificant premium | Out-of-sample PS stronger |
| Pastor-Stambaugh (P116) | Full-sample (1932-2017) insignificant | 2008 crisis validation compelling |

**Verdict: Akbas et al. finding is SUPPORTED by the evidence.**
- Liquidity IS unstable across long time periods
- The premium is conditional on market microstructure regime (pre-HFT vs. post-HFT)
- For Korea: the premium is likely in a transition similar to US post-2001 decimalization
- **Practical implication:** Use liquidity as a regime-conditional modifier, NOT a standalone factor with fixed weight

---

## 5. Whether to Include in STR_016 Composite

**STR_016 context:** Regime-conditional multi-factor strategy targeting KOSPI200/KOSDAQ150 universe, 20-30 stock concentrated portfolio.

### Recommendation: YES, include as a SCREEN + WEAK SIGNAL

**Yes to screen:**
- Universe filter based on minimum ADV is non-negotiable for a 20-30 stock concentrated portfolio
- Position sizing using square root impact model is essential to avoid slippage eating alpha
- This adds real value regardless of whether liquidity generates alpha

**Yes to weak signal in KOSDAQ sub-universe:**
- Annual turnover signal has strong evidence (7.26%/yr premium, independent of other factors)
- LM12 is powerful for KOSDAQ where zero-volume days are meaningful
- Keep weight at 10-15% of composite to avoid overfitting

**No to PS-type liquidity risk factor:**
- PS gamma requires daily OLS estimation for each stock → computationally expensive
- Evidence is contested (Pontiff-Singla: 10/10 failures)
- For concentrated 20-30 stock portfolio, factor-level beta estimation is noisy

### Implementation in STR_016

```r
# STR_016 liquidity module additions:

# 1. Universe screen (MANDATORY)
screen_liquidity <- function(universe_df) {
  universe_df %>%
    filter(
      adv_20d_krw >= 3e9,        # min 3B KRW average daily volume
      n_zero_vol_30d <= 3,        # max 3 zero-volume days in last month
      price >= 1000               # min 1000 KRW price
    )
}

# 2. Position sizing cap (MANDATORY)
max_position_krw <- function(adv_krw, sigma, target_impact_bps = 15) {
  # Square root model: G = sigma * sqrt(Q_krw / adv_krw)
  # Solve for Q_krw: Q_krw = adv_krw * (G/sigma)^2
  G <- target_impact_bps / 10000
  Q_max <- adv_krw * (G / sigma)^2
  return(Q_max)
}

# 3. Liquidity signal (OPTIONAL, 10% weight in composite)
compute_illiquidity_signal <- function(df, universe = "KOSDAQ") {
  if (universe == "KOSDAQ") {
    # KOSDAQ: use ILLIQ + LM12 composite
    df %>% mutate(liq_score = (illiq_rank + lm12_rank) / 2)
  } else {
    # KOSPI200: use annual turnover only
    df %>% mutate(liq_score = 1 - annual_turn_rank)
  }
}
```

---

## 6. Top 3 New Strategy Ideas from This Cluster

### Idea 1: Korean Liquidity Crisis Regime Strategy (HIGH PRIORITY)

**Concept:** Use aggregate market ILLIQ as a regime detector. In high-liquidity regimes, rotate to illiquid stocks (harvest premium). In low-liquidity regimes (crises), rotate to most liquid names (defensive).

**Evidence base:** Li, Mooradian & Zhang (P111) — 1 SD change in aggregate illiquidity → 4.68% quarterly return impact; Sadka (P112) — high-beta funds lose 15-18% in liquidity crises; PS 2003/2016 — aggregate gamma spikes at crisis points.

```r
# Aggregate Korean ILLIQ regime signal
market_illiq_regime <- function(market_illiq_ts, fast = 3, slow = 12) {
  market_illiq_ts %>%
    mutate(
      illiq_fast = slider::slide_dbl(avg_illiq, mean, .before = fast-1),
      illiq_slow = slider::slide_dbl(avg_illiq, mean, .before = slow-1),
      illiq_zscore = (illiq_fast - illiq_slow) / sd(avg_illiq, na.rm = TRUE),
      regime = case_when(
        illiq_zscore > 1.5  ~ "CRISIS",      # illiquidity spike: go defensive
        illiq_zscore < -0.5 ~ "NORMAL",      # normal or improving: hold illiquid
        TRUE                ~ "TRANSITION"
      )
    )
}
```

**Expected alpha:** +2-3%/year from regime timing vs. static exposure.

### Idea 2: KOSDAQ Structural Illiquidity Premium (MEDIUM PRIORITY)

**Concept:** Build a systematic KOSDAQ-focused strategy targeting structurally illiquid (but operationally sound) companies. Use LM12 + annual turnover + earnings quality screen to find illiquid stocks with improving fundamentals.

**Evidence base:** Liu (P104) — two-factor model (MKT + LM) outperforms FF3; Ibbotson et al. (P109) — 7.26% annual premium for low-turnover stocks; Blitz et al. (P110) — premium persists in small-cap universe even after adjustments.

```r
# KOSDAQ structural illiquidity strategy signals
kosdaq_illiq_universe <- function(df) {
  df %>%
    filter(exchange == "KOSDAQ") %>%
    mutate(
      # LM12: zero-volume days (strong signal for KOSDAQ)
      lm12_score = percent_rank(lm12),
      # Annual turnover: low turnover = illiquid = higher premium
      ann_turn_score = 1 - percent_rank(annual_turnover),
      # Earnings quality screen: positive ROE, positive FCF (avoid value traps)
      quality_pass = roe > 0 & fcf_yield > 0,
      # Composite
      final_score = ifelse(quality_pass, (lm12_score + ann_turn_score) / 2, NA)
    ) %>%
    filter(!is.na(final_score)) %>%
    arrange(desc(final_score))
}
```

**Expected alpha:** +3-5%/year vs. KOSDAQ benchmark (conditional on quality screen).

### Idea 3: Liquidity-Momentum Interaction Strategy (MEDIUM PRIORITY)

**Concept:** Pastor-Stambaugh (P117) found that the PS liquidity factor accounts for half of momentum profits. This suggests: momentum works best in illiquid stocks (price takes longer to fully react → momentum persists longer). Build a strategy that specifically combines momentum signals with illiquidity screens.

**Evidence base:** PS 2003 — liquidity beta accounts for 50% of momentum alpha; Subrahmanyam (P120) — Avramov et al. 2007: momentum profits derive primarily from low-credit-quality (=illiquid) stocks; Ibbotson et al. (P109) — within each momentum quartile, low-liquidity stocks outperform.

```r
# Liquidity-conditioned momentum
illiquid_momentum <- function(df, mom_lookback = 12, mom_skip = 1) {
  df %>%
    # Step 1: compute standard momentum
    group_by(ticker) %>%
    mutate(
      mom_signal = lag(
        slider::slide_dbl(ret, ~ prod(1 + .x) - 1, .before = mom_lookback - 1),
        mom_skip + 1
      )
    ) %>%
    ungroup() %>%
    # Step 2: cross-sectional rank within illiquidity bucket
    group_by(date) %>%
    mutate(
      illiq_tertile = ntile(illiq, 3),
      # Only apply momentum in most illiquid tertile
      # (momentum works better in illiquid stocks)
      effective_signal = ifelse(illiq_tertile == 3, mom_signal, mom_signal * 0.5)
    )
}
```

**Expected alpha:** +1-2%/year incremental vs. standard momentum, lower volatility in liquid stocks.

---

## 7. Summary Matrix: Papers by Implementation Priority

| Paper | Measure | Priority | Use |
|---|---|---|---|
| P117 (PS 2003) | PS Gamma | HIGH | Regime signal, not standalone factor |
| P109 (Ibbotson) | Annual Turnover | HIGH | Primary cross-sectional signal |
| P104 (Liu) | LM12 | HIGH | KOSDAQ zero-day measure |
| P101 (AM 1986) | Bid-ask spread | MEDIUM | Screen framework; use ILLIQ as proxy |
| P113 (Datar) | Monthly Turnover | MEDIUM | Monthly signal update |
| P111 (Li et al.) | Market ILLIQ | MEDIUM | Aggregate regime indicator |
| P107/P114 (Kyle-Obj.) | Impact formula | HIGH | Position sizing (mandatory) |
| P110 (Robeco) | Skeptical review | HIGH | Guardrail: no standalone factor |
| P119 (Drienko) | ILLIQ review | MEDIUM | Calibration: ILLIQ weaker post-2010 |
| P116/P117/P118 | PS debate | MEDIUM | Understand construction sensitivity |

---

## 8. Final Verdict

**Liquidity is best used as a three-layer module:**

1. **LAYER 1 (Mandatory Screen):** Min ADV filter + position sizing via square root model. No alpha, but prevents implementation disasters.

2. **LAYER 2 (Weak Signal):** Annual turnover composite (KOSPI200 + KOSDAQ). Weight: 10-15% in composite. Expected Korea contribution: +1-2%/year.

3. **LAYER 3 (Regime Signal):** Aggregate market ILLIQ as crisis detector. When market ILLIQ spikes → reduce illiquid stock exposure. This is the highest-confidence use of liquidity theory.

**What NOT to do:**
- Do not build a standalone L/S liquidity factor for KOSPI200 universe (Robeco finding: 95/102 measures insignificant without microcaps)
- Do not use ILLIQ alone as a predictor for KOSPI200 large-caps (premium nearly gone post-2010)
- Do not ignore the PS gamma crisis pattern (the 2008 GFC, 2020 COVID events are the most valuable signals)
