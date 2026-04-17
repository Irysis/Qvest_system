# Strategic Summary: Factor Anomaly Survival — Implications for Korean Equity Pipeline
**Date:** 2026-03-01
**Papers Covered:** P078, P079, P080, P081, P082, P083, P084, P085, P091, P092, P097
**Synthesized by:** Q (Claude)
**Context:** 11 strategies tested, 1 PASS (STR_011: Macro-Gated LowVol, CAGR 14.81%, Sharpe 0.907)

---

## Part I: Answer to the 5 Key Questions

### Q1. Which anomalies survive across the most papers?

Ranked by consensus across all 11 papers (survival = significant, replicable, international):

| Rank | Anomaly/Factor | Papers Supporting | Evidence Quality |
|------|---------------|-------------------|-----------------|
| 1 | **Gross Profitability** (Revenue-COGS)/Assets | P080, P082, P085, P097, P092 | STRONGEST — survives all methodology corrections |
| 2 | **Investment-to-Assets / Asset Growth** | P080 (74% survival), P082, P097, P092 | Very strong — q-theory support |
| 3 | **Return on Assets (ROA)** | P080, P082, P085, P091, P097 | Strong — simple and robust |
| 4 | **Momentum** (12-1 month) | P080 (62%), P082, P085, P097 | Strong empirically, weak theoretically (Ross P084) |
| 5 | **Low Volatility / Min Vol** | P085, P083 | Strong empirically, behavioral theory only |
| 6 | **Value (B/M, E/P, CF/P)** | P080 (42%), P082, P083, P085, P092 | Moderate — lower replication rate than profitability |
| 7 | **Accruals (Total Accruals)** | P082, P081, P097 | Moderate — affected by dumb money flows |
| 8 | **Net Stock Issues** | P082, P097 | Moderate — straightforward signal, partly known |
| 9 | **Size (SMB)** | P080, P083, P085, P092 (70%+ selection rate) | Strong individually, long cycles |
| 10 | **Financial Distress (O-score / Z-score)** | P082, P097 | Moderate — complex to compute |

**TOP 3 CONFIRMED SURVIVORS**: Gross Profitability, Investment-to-Assets, ROA
These three consistently appear across replication studies (P080), international validity (P082), institutional flow analysis (P097), and factor selection (P092).

---

### Q2. Which anomaly TYPES are most durable?

From Hou et al. (P080) category-level replication rates + confirmation from other papers:

**TIER 1 — Most Durable (75%+ replication + international confirmed)**
- **Investment/Capex factors**: 73.7% replication rate (Hou et al.) + confirmed in P082 internationally
  - Asset growth, investment-to-assets, capex/sales, net operating assets
  - Theory: q-theory of investment (risk-based AND behavioral interpretation)
  - Why durable: fundamental balance sheet data, slow-moving, requires quarterly data processing

**TIER 2 — Durable (55-75% replication + good international evidence)**
- **Momentum**: 62.2% replication rate + confirmed in P082, P085, P083
  - Cross-sectional price momentum
  - Theory: weak (Ross P084 skeptical) but empirically undeniable
  - Caveat: behavioral, potentially vulnerable to crowding; use RESIDUAL momentum
- **Profitability**: ~44% replication (Hou) but gross profitability specifically ~90%+ when measured correctly
  - Gross profitability (P082 t=3.72 FF4) is the most robust individual factor
  - ROA, ROE also strong when properly constructed

**TIER 3 — Moderate (40-55% replication + decent international evidence)**
- **Value**: 42% replication rate (Hou et al.) + confirmed internationally
  - Weaker replication partly due to measurement: book value is noisy
  - E/P and CF/P more robust than B/M
  - Very low turnover (20% annually per MSCI) = cost-efficient

**TIER 4 — Weaker (25-40% replication, more vulnerable)**
- **Quality composites** (earnings quality, low accruals): mixed evidence
- **Financial distress**: works but complex to compute and maintain
- **Intangibles-based factors**: 25.2% replication — avoid unless on micro-cap-free universe

**TIER 5 — Do Not Use**
- **Trading Frictions / Illiquidity anomalies**: 3.8% replication rate (Hou et al.) — almost entirely microcap artifact
- **Growth factors** (earnings growth, revenue growth): NOT persistent per MSCI P085
- **Liquidity factors** (turnover-based): NOT persistent per MSCI P085
- **CFROI and complex cash flow adjustments**: inferior to simple ROA/ROC per P091

---

### Q3. Average post-publication decay — what are realistic numbers?

**US market (reference point):**
- McLean & Pontiff (P081): 58% average post-publication decline in predictor returns
- In-sample → out-of-sample (pre-pub): ~15-26% decay (statistical bias)
- Post-publication additional decay: ~32% minimum (arbitrage/market-learning)
- Recent US (2004-2015): only 16 bps/month VW remaining (Jacobs & Muller P079)

**International markets (38 countries excl. US):**
- Jacobs & Muller (P079): NO statistically significant post-publication decline
- International recent period (2004-2015): 38 bps/month VW — still highly significant
- Range: -6% to +36% post-publication change — NOT negative on average

**Korea-specific estimate (inferred from international evidence):**
- Korea likely falls in the "international" category (NOT the US exception)
- Short selling restrictions → limits to arbitrage → slower correction
- Small QA industry → less publication-driven arbitrage
- Conservative baseline: **25-40 bps/month gross alpha** from diversified anomaly composite
- Statistical bias correction (26% haircut from P081): ~20-30 bps/month
- NO ADDITIONAL publication-effect haircut for Korea (unlike US)
- Net of transaction costs (~15 bps/trade, monthly rebalance): **15-25 bps/month net alpha**

**Decay by factor type:**
| Factor Type | US Post-Pub Decay | Korea Expected Decay |
|-------------|------------------|---------------------|
| Investment (asset growth, capex) | ~30-40% | ~10-15% |
| Profitability (gross profit, ROA) | ~40-50% | ~10-20% |
| Momentum | ~50-60% | ~15-25% |
| Value | ~40-50% | ~10-20% |
| Accruals | ~55-65% | ~15-25% |
| Trading Frictions | ~70-80% (+ microcap bias) | AVOID |

---

### Q4. Korea-specific vs US survival rates — key differences

**Structural factors making Korea BETTER than US for factor investing:**

1. **Short selling restrictions** (KRX periodic bans, limited stock borrow market):
   - Anomalies on the short side persist longer → more uncorrected mispricing
   - Our LONG-ONLY strategy benefits directly: short-side premium is trapped, long-side captures full signal

2. **Small Korean hedge fund sector**:
   - Korean hedge funds: ~20-30 trillion KRW AUM
   - US hedge funds: ~$4 trillion = ~5,500 trillion KRW equivalent
   - Roughly 1/200th the scale relative to market size
   - Less arbitrage capital → slower correction of anomalies (P078 Calluzzo mechanism)

3. **Retail investor dominance**:
   - Korean retail: ~50-60% of trading volume
   - Retail = "dumb money" (Akbas P097) that EXACERBATES anomalies
   - More dumb money → anomalies are larger AND last longer

4. **Institutional composition**:
   - NPS (National Pension Service) and insurance companies are long-term holders
   - Long-term institutions do NOT drive post-publication decay (P078 Calluzzo finding)
   - Transient/HFT institutions: less prevalent in Korea than US

5. **Lower quantitative research penetration**:
   - Far fewer Korean quantitative equity strategies vs US
   - Published anomalies are less crowded in Korea

**Bottom line**: Korean factor alpha is likely 2-3x more persistent than US factor alpha for the same published signals.

---

### Q5. What characteristics predict factor SURVIVAL?

From synthesis of all 11 papers:

**Characteristics that PREDICT SURVIVAL (longer-lived factors):**

1. **Strong theoretical foundation** (both risk AND behavioral explanations):
   - Profitability: Novy-Marx (2013) gross profitability — economic theory + behavioral
   - Investment: q-theory (Cochrane) — risk-based + behavioral
   - Value: fundamental valuation theory — strongest theoretical backing
   - Low Volatility: BEHAVIORAL ONLY (no risk theory) but still persists → behavioral theory alone can be sufficient

2. **Low idiosyncratic volatility (IVOL) arbitrage risk** — INVERTED:
   - Anomalies in HIGH-IVOL stocks persist LONGER (McLean & Pontiff P081)
   - Arbitrageurs avoid high-IVOL stocks → mispricing uncorrected
   - Korea: KOSDAQ150 stocks are high-IVOL → anomalies persist more

3. **Low institutional ownership / hedge fund coverage**:
   - Lower HF ownership → less arbitrage deployment → longer alpha (Calluzzo P078)
   - Korean mid-cap and KOSDAQ → low HF coverage → longer alpha persistence

4. **Requires complex processing or fundamental data**:
   - Accruals (balance sheet method): complex, quarterly data → slower arbitrage
   - Gross profitability: requires COGS breakdown → not in price data alone
   - Capital investment: requires balance sheet → fundamental data advantage

5. **Published BEFORE heavy quantitative adoption** (pre-2000 anomalies):
   - Akbas et al. (P097): hedge funds trade composites of PRE-1997 anomalies
   - Old, established anomalies are already "priced in" by composite quant funds — limited additional exploitation
   - New anomalies: fewer funds exploit them → more alpha remaining

6. **Cross-country validated**:
   - Works in international markets (P082 Stambaugh, P079 Jacobs & Muller)
   - Not data-mined from US alone → genuine economic signal

7. **Low turnover**:
   - Value (20% annual turnover per P085): survives because implementation cost is low
   - High-turnover factors: gross alpha gets eroded by trading costs
   - Net alpha survival probability is higher for low-turnover factors

**Characteristics that PREDICT DECAY:**

1. Simple to compute from widely available price data (easy to replicate → easy to arbitrage)
2. Large-cap liquid stock concentration (where HF activity is highest)
3. Published in top academic journals with high citation count (McLean & Pontiff P081)
4. High turnover → implementation cost drag eliminates alpha
5. No theoretical foundation (purely empirical) → Ross P084 skepticism justified
6. Requires only price and volume data → any quant can implement instantly

---

## Part II: Factor Survival Ranking for Our Pipeline

Specific ranking requested for: Quality / Low-Vol / Liquidity / Accrual / Asset Growth / Value / Momentum

| Rank | Factor | Survival Score (1-10) | Priority | Key Risk |
|------|--------|----------------------|----------|---------|
| 1 | **Asset Growth / Investment** | 9/10 | INCLUDE IMMEDIATELY | Requires DART balance sheet data |
| 2 | **Quality (Gross Profitability + ROA)** | 9/10 | INCLUDE IMMEDIATELY | Data quality (DART consistency) |
| 3 | **Low Volatility** | 8/10 | ALREADY IN (STR_011) | Long underperformance cycles |
| 4 | **Value (E/P, CF/P preferred over B/M)** | 7/10 | INCLUDE | Lower replication than profitability |
| 5 | **Accrual (Balance Sheet)** | 6/10 | INCLUDE WITH CAUTION | Dumb money effect; accrual manipulation in Korea |
| 6 | **Momentum (Residual only)** | 6/10 | INCLUDE AS REGIME-DEPENDENT | Must be residual/macro-adjusted |
| 7 | **Liquidity** | 2/10 | DO NOT INCLUDE | MSCI confirms non-persistent; Hou 3.8% replication |

**Detailed justifications:**

**Asset Growth / Investment (Rank 1, Score 9/10)**
- Hou et al.: 73.7% replication rate — highest category
- Stambaugh et al.: confirmed internationally, all significant
- q-theory: strong theoretical foundation (risk-based interpretation available)
- Low turnover: balance sheet data quarterly → ~40-60% annual turnover
- Korea: DART provides capex, total assets quarterly → DIRECTLY COMPUTABLE
- Recommendation: include investment-to-assets + asset growth in fundamental composite

**Quality — Gross Profitability + ROA (Rank 2, Score 9/10)**
- Gross Profitability: t=3.72 FF4 (Akbas P097), confirmed internationally (Stambaugh P082)
- ROA: S&P500 top-50 returns 16.0% (Subramanian P091); confirmed in Hou et al.
- MSCI Quality factor: highest total return 10.9% over 25 years (P085)
- Theory: strong (Novy-Marx earnings quality theory)
- Korea: NTS revenue and COGS from DART → gross profitability directly computable
- STR_011 (the passing strategy) is LowVol — ADDING Quality is the natural next step
- Recommendation: Quality composite = Gross Profitability + ROA + low leverage

**Low Volatility (Rank 3, Score 8/10)**
- ALREADY the core of STR_011 (the only passing strategy)
- MSCI Min Vol: lowest risk (11.6%), positive active return (+1.4%)
- Only behavioral theory (no risk-based) — but still persistent globally
- Korea short-selling restrictions: volatility-sorted portfolios harder to short → long-side premium persists
- Recommendation: maintain as core, add macro gating (already done), consider combining with Quality

**Value (Rank 4, Score 7/10)**
- Hou et al.: only 42% replication for value-growth category (weakest of surviving categories)
- BUT internationally confirmed (P082, P083, P085)
- MSCI Value: 8.6% total return, 20% turnover — most cost-efficient factor
- E/P preferred over B/M: earnings are more current than book value (accounting adjustments distort book)
- Korea: DART P/E, P/B readily available; earnings estimates available from consensus
- Recommendation: use E/P (earnings yield) + CF/P (cash flow yield) rather than B/M; include in composite

**Accrual (Rank 5, Score 6/10)**
- Confirmed internationally (P082)
- BUT: heavily known since Sloan 1996 → more arbitrage-vulnerable even in Korea
- Akbas P097: mutual fund dumb money exacerbates accrual anomaly → volatile
- Korea risk: earnings management / accrual manipulation is a known issue in Korean small caps
- Recommendation: include in composite signal (dampened weight), NOT as standalone factor; use balance sheet accruals method (NOA change / Total Assets), not cash-flow method

**Momentum — Residual Only (Rank 6, Score 6/10)**
- Empirically strong (t=4.37 FF4 in Akbas P097; 62% replication in Hou et al.)
- BUT: theoretically weak (Ross P084 skepticism; no APT explanation after 30 years)
- MSCI Momentum: highest turnover (127.5% annually) — implementation cost drag
- Akbas P097: hedge funds heavily exploit momentum → most vulnerable to smart-money decay
- Our pipeline principle: NEVER raw price momentum
- Recommendation: use ONLY as residual momentum (after market + sector + macro regime adjustment); include in regime-conditional composite only when macro signal is favorable

**Liquidity (Rank 7, Score 2/10)**
- MSCI P085 explicitly states: Liquidity does NOT generate persistent long-term premia
- Hou et al. P080: Trading Frictions category (includes liquidity) — 3.8% replication rate
- Exclusion is confirmed by multiple papers from multiple angles
- Any observed liquidity premium in Korea is likely microcap bias → eliminate from universe construction
- Recommendation: DO NOT use as alpha factor. Use as a FILTER (minimum liquidity threshold) not a signal.

---

## Part III: Most Durable Anomaly Types (Summary Table)

| Anomaly Type | Durability | Theory Strength | Korea Premium | Action |
|-------------|------------|-----------------|---------------|--------|
| Investment (asset growth, capex) | Very High | Strong (q-theory) | High | Implement immediately |
| Gross Profitability | Very High | Strong (Novy-Marx) | High | Implement immediately |
| Low Volatility / Min Vol | High | Behavioral only | High (restrictions) | Already implemented |
| Value (E/P, CF/P) | Moderate-High | Strong | Moderate-High | Include in composite |
| Momentum (residual) | Moderate | Weak theory | Moderate | Conditional only |
| Accruals | Moderate | Moderate | Moderate | Dampened weight only |
| Financial Distress | Moderate | Moderate | Moderate | Include in composite |
| Net Stock Issues | Moderate | Moderate | Moderate | Include in composite |
| Trading Frictions / Liquidity | Very Low | Weak | Low | EXCLUDE |
| Growth (earnings/revenue) | Very Low | Weak | Low | EXCLUDE |

---

## Part IV: Fast-Decaying Anomaly Types to Avoid

**DO NOT build strategies around:**

1. **Liquidity / Trading Frictions**: 3.8% replication (Hou), not persistent (MSCI). Any apparent Korean liquidity premium is microcap contamination.

2. **Revenue/Earnings Growth Rate**: MSCI confirms no long-term premium. Growth stocks outperform only in specific regimes, not across full cycles.

3. **Complex proprietary metrics (CFROI, FCFF yield)**: P091 confirms inferior to simple ROA/ROC. Complexity adds noise without alpha.

4. **Pure price momentum**: Ross skepticism (P084) + high turnover cost + hedge fund crowding (P078, P097). Use only as residual momentum with macro conditioning.

5. **Short-term reversal**: Microcap-driven, high transaction cost, no persistent premium in liquid universe.

6. **Volume-based signals (turnover anomalies)**: Subsumed by size (SMB) per Feng et al. (P092). Not independent signal.

---

## Part V: Paper Cluster Priorities for 200+ Unread Papers

Based on synthesis of the 11 papers, the most valuable UNREAD paper clusters for the Korean equity pipeline are:

**CLUSTER 1 — HIGHEST PRIORITY: International Factor Studies**
- Papers testing US anomalies in Asian markets (Japan, China, Hong Kong, India, Korea)
- Stambaugh-Yu-Yuan's composite mispricing approach applied to Asia
- Any paper on Korean-specific factor premia
- Search terms: "anomaly Korea", "factor premium Asia emerging market", "mispricing international"
- Why: P079 confirms US decay doesn't apply internationally, but we need Korean-specific data

**CLUSTER 2 — HIGH PRIORITY: Gross Profitability and Profitability Factors**
- Novy-Marx (2013) "The Other Side of Value" — the original gross profitability paper
- Fama-French (2015) "A Five-Factor Asset Pricing Model" — theoretical backing for RMW
- Papers on profitability decomposition (revenue vs cost efficiency)
- Search terms: "gross profitability", "quality factor", "earnings quality"
- Why: gross profitability is the #1 individual factor from our synthesis

**CLUSTER 3 — HIGH PRIORITY: Investment Factor / q-theory**
- Hou, Xue, Zhang q-factor model papers
- "Investment and Expected Returns" (Cochrane type papers)
- Asset growth anomaly papers beyond Hou et al.
- Search terms: "q-factor", "asset growth anomaly", "investment factor"
- Why: investment category has 73.7% replication — strongest category

**CLUSTER 4 — HIGH PRIORITY: Composite Mispricing / Multi-Signal**
- Stambaugh, Yu, Yuan (2012) — the composite mispricing paper underlying P082 and P097
- Papers on factor combination and composite signal construction
- Machine learning factor combination papers
- Search terms: "composite mispricing", "multi-factor composite", "factor combination"
- Why: Stambaugh composite delivers 118 bps/month internationally; most actionable strategy idea

**CLUSTER 5 — MEDIUM PRIORITY: Low Volatility / Min Volatility Mechanism**
- Baker, Bradley, Wurgler (2011) "Benchmarks as Limits to Arbitrage"
- Frazzini-Pedersen "Betting Against Beta" (BAB factor)
- Low volatility in emerging markets papers
- Search terms: "low volatility anomaly", "min vol", "beta anomaly"
- Why: our best strategy (STR_011) is LowVol — need deeper theoretical grounding

**CLUSTER 6 — MEDIUM PRIORITY: Macro Regime and Factor Cyclicality**
- Papers on conditional factor models (regime-switching)
- Factor performance across economic cycles
- Regime detection methods (HMM, MSM) applied to factor returns
- Search terms: "conditional factor model", "regime factor", "time-varying factor premium"
- Why: macro gating is the key differentiator of STR_011; need more regime-factor interaction papers

**CLUSTER 7 — MEDIUM PRIORITY: Korean Accounting Specifics**
- Korean IFRS adoption effects on accounting anomalies
- Earnings management in Korean conglomerates
- Chaebol group structure and factor anomalies
- Search terms: "Korea IFRS", "Korean accounting anomaly", "chaebol"
- Why: accounting quality determines reliability of DART-based factors

**CLUSTER 8 — LOW PRIORITY: Additional Methodology Papers**
- Harvey, Liu, Zhu (2016) — t-stat hurdles for multiple testing (endorsed by Ross P084)
- Correlation structure of factor returns
- Factor momentum (momentum of factors themselves)
- Search terms: "multiple testing factors", "factor correlation", "factor momentum"

---

## Part VI: Immediate Strategy Implications

**Context**: Only STR_011 (Macro-Gated LowVol) passed. 10 strategies failed.

**What the 11 papers tell us about why and what to do next:**

### Why STR_011 is the Only Passing Strategy
1. Low Volatility has NO risk-based theory (P085, P084) → it's a pure behavioral premium
2. In Korea, behavioral premia are MORE persistent (less arbitrage correction)
3. The MACRO GATING is the differentiator: it avoids the 2-3 year underperformance cycles (P085)
4. Long-only structure benefits from short-selling restrictions → full capture of behavioral premium

### The Most Promising Next Strategy: Quality-LowVol Hybrid
Evidence from papers:
- Quality factor: 10.9% total return (HIGHEST of all MSCI factors, P085)
- Low Volatility: 8.5% total return, lowest risk (already in STR_011)
- Correlation: Quality and Low Volatility are positively correlated (P085) → smooth cycle
- Quality + LowVol composite: expected to deliver Quality's return with LowVol's lower risk

Design sketch:
```
Quality Score = w1 × GrossProfit/Assets + w2 × ROA + w3 × (1/Leverage)
LowVol Score = Negative(252-day realized volatility)
Composite = α × Quality + (1-α) × LowVol
Macro Gate: VIX/YC regime (already in STR_011)
```

### The Composite Mispricing Strategy: Stambaugh 9-Factor Composite
Evidence: 118 bps/month internationally (P082); all 11 factors significant (P097)
- Korean implementation: 9 factors from DART fundamentals
- Expected gross alpha in Korea: 40-80 bps/month (conservatively 1/3 to 2/3 of international)
- This is the SINGLE HIGHEST EXPECTED ALPHA strategy from the 11 papers

Design sketch:
```
Composite_Rank = average of percentile ranks of:
  1. Gross Profitability (Revenue-COGS)/Assets [DART: 매출총이익/자산]
  2. ROA (Net Income/Total Assets) [DART: 당기순이익/자산]
  3. Asset Growth (ΔTotal Assets / Assets_t-1) [DART: 자산 YoY]
  4. Investment-to-Assets (Capex/Assets) [DART: 투자활동/자산]
  5. Accruals ((ΔNet Operating Assets) / Average Assets) [DART: balance sheet accruals]
  6. Net Stock Issues (Δln(Shares Outstanding)) [DART: 자본금 변화]
  7. Composite Equity Issues (net external finance) [DART: 자금조달 변화]
  8. Momentum (12-1 month return) [RAWDATA.parquet]
  9. Financial Distress (Altman Z-score or O-score) [DART: computed]
Long: top quintile. Monthly rebalance. Macro-gated.
```

### What Strategies to Build Next (Priority Order)
1. **STR_012**: Quality-LowVol Hybrid (Quality composite + LowVol, macro-gated) — IMMEDIATE
2. **STR_013**: Stambaugh 9-Factor Composite Mispricing — HIGH PRIORITY
3. **STR_014**: Investment + Profitability Factor (q-factor approach, asset growth + gross profit) — HIGH PRIORITY
4. **STR_015**: Value-Momentum Composite (E/P + residual momentum, regime-conditional) — MEDIUM PRIORITY

---

## Part VII: Key Caveats and Warnings

1. **Korean data quality risk**: DART fundamentals have reporting delays (up to 90 days for annual reports). Construct factors using ONLY publicly available data at rebalance date. Avoid look-ahead bias.

2. **Small sample problem**: Korean market (350 stocks) means factor portfolios will be small (70 stocks in top quintile). Statistical significance harder to achieve — use composite signals to increase power.

3. **Chaebol/holding company contamination**: Holding companies were filtered (per MEMORY.md). But affiliated subsidiaries may show anomalous factor values due to intra-group transactions. Consider filtering top 10 chaebol heavily cross-held names.

4. **Korean accounting manipulation**: Accruals and earnings management are higher risk in Korean mid-cap stocks. Use gross profitability (harder to manipulate) over earnings-based profitability.

5. **Factor crowding monitor**: Korean quantitative industry is growing. If AUM in Korean quant funds doubles in next 2 years, expect US-style decay to begin emerging. Monitor quarterly.

6. **Composite correlation**: When combining 9 factors, they are NOT independent. In crisis periods (2008, 2020), all factors may correlate → tail risk increases. Use macro regime gating to reduce exposure in crisis regimes.

---

## Summary Table: Most Actionable Findings

| Finding | Source | Action |
|---------|--------|--------|
| Investment factor: 73.7% replication | P080 Hou et al. | Add asset growth + capex/assets to pipeline |
| Gross profitability: t=3.72 FF4 | P082, P097 | Top-priority individual factor for STR_012/013 |
| US post-pub decay: 58% BUT international: near-zero | P079, P081 | Use published factors in Korea without decay haircut |
| Short selling restrictions → anomaly persistence | P079, P081 | Long-only strategy is optimal for Korea |
| Composite mispricing: 118 bps/month | P082, P097 | Build composite > individual factor strategies |
| Smart money trades COMPOSITES not individual factors | P097, P078 | Our composite is less crowded than individual factors |
| Quality: highest total return (10.9%) | P085 | Build STR_012 Quality-LowVol hybrid |
| Growth/Liquidity factors NOT persistent | P085, P080 | Remove any growth/liquidity factor candidates |
| Factor zoo: most factors redundant | P092, P084 | Limit to 5-7 independent factors; use LASSO screening |
| CFROI inferior to ROA | P091 | Use ROA, not complex CF adjustments |
