# Latest Paper Research Report — Scout Agent
# Date: 2026-03-14 | Search scope: 2025-01 ~ 2026-03
# Goal: Find NEW alpha ideas not yet in H-01~H-11 hypotheses

---

## Search Summary
- **Sources searched**: WebSearch (arxiv, SSRN, Google Scholar via web)
- **Queries**: 9 parallel searches across factor investing, regime switching, ML ensemble, analyst revision, low-vol anomaly, Korea governance, LLM/GenAI, vol-of-vol, sector momentum
- **Total papers identified**: 28 unique papers
- **Genuinely NEW ideas (not in H-01~H-11)**: 7

---

## Paper Findings

### Paper [1]: Drift Regimes Unlock Hidden Cross-Sectional Predictability
- **Source**: arxiv 2511.12490 (Nov 2025, Mainak Singha)
- **Finding**: Combining value + short-term reversal signals ONLY during stock-specific "drift regimes" (>60% positive days in trailing 63d) achieves OOS Sharpe >13 on S&P 500 (2004-2024). Annualized return 158.6%, vol 12.0%, MDD -11.9%. Survives 1,000 randomization trials (p<0.001) and 30% parameter perturbation.
- **Signal**: `Drift_flag_i = (positive_days_63d / 63 > 0.60)`. When flag=TRUE, apply `z(book_to_market) + z(-ret_5d)` (value+reversal). When flag=FALSE, exclude stock entirely. Stock-level regime conditioning.
- **Relevance**: This is a STOCK-LEVEL regime conditioning idea. Our H-11 (MRPA) conditions on MARKET-level regimes for stock selection. This paper conditions on INDIVIDUAL STOCK drift patterns. Fundamentally different mechanism.
- **Priority**: ★★★
- **Novel vs Existing**: **GENUINELY NEW**. H-11 uses macro regime for stock selection. This uses per-stock drift detection. Not covered by H-01~H-11. The drift indicator (fraction of positive days) is trivial to compute from RAWDATA. The combination with value+reversal during drift is novel.
- **Caution**: Sharpe 13 is almost certainly overstated (S&P 500 only, possible look-ahead in parameter selection despite claims). But the MECHANISM (stock-level regime gating) is sound and testable in Korea.

---

### Paper [2]: Factoring in the Low-Volatility Factor
- **Source**: SSRN 5295002 (Jun 2025, Soebhag, Baltussen, van Vliet)
- **Finding**: Decomposed the low-vol strategy into long and short legs. The LONG leg survives transaction costs and delivers genuine alpha. The short leg (betting against high-vol) is where most academic alpha concentrates but is unimplementable due to costs. For long-only investors, the low-vol premium is real but smaller than full-sample estimates.
- **Signal**: Standard low-vol long leg: bottom-quintile realized volatility, with explicit cost adjustment. Key insight: use ONLY the long side.
- **Relevance**: Directly validates our Defense sleeve (IdioVol+Beta long-only). Confirms long-only low-vol works after costs. No new signal construction needed.
- **Priority**: ★
- **Novel vs Existing**: **ALREADY COVERED**. This is our Defense family. Confirms existing approach is sound.

---

### Paper [3]: The Case for Low-Risk Equity Investing: Evidence from 2011-2025
- **Source**: SSRN 5372550 (Jul 2025, Leote de Carvalho, Andreis, Laplenie)
- **Finding**: Low-risk strategies maintained their edge over 2011-2025 even in rising rate environments. Sector-neutral implementation is critical to avoid unintended bets.
- **Signal**: Sector-neutral low-vol portfolio construction (already our approach).
- **Relevance**: Confirms Defense sleeve approach. No new alpha.
- **Priority**: ★
- **Novel vs Existing**: **ALREADY COVERED**. Validates existing Defense.

---

### Paper [4]: Low-Risk Alpha Without Low Beta
- **Source**: SSRN 5005746 (2025, Blitz, Howard, Huang, Jansen — Robeco team)
- **Finding**: Low-risk alpha can be captured WITHOUT loading on low-beta stocks, by targeting idiosyncratic risk instead. Separating systematic (beta) from idiosyncratic (IVOL) risk components shows IVOL is the primary driver of low-vol alpha, not beta.
- **Signal**: Pure IVOL sort without beta screen. Implication: our Defense score z(IdioVol)*0.4 + z(Beta)*0.6 may be suboptimal — pure IVOL (weight 1.0) might be superior.
- **Relevance**: Direct challenge to Defense score weights. Worth testing: IVOL-only vs IVOL+Beta composite.
- **Priority**: ★★
- **Novel vs Existing**: **PARTIAL OVERLAP** with Defense. New finding is that Beta component may be unnecessary/harmful. Not a new alpha source but a refinement of existing Defense sleeve.

---

### Paper [5]: Tactical Asset Allocation with Macroeconomic Regime Detection
- **Source**: arxiv 2503.11499 (Mar 2025)
- **Finding**: Wasserstein HMM for regime detection achieves Sharpe 2.18, MDD -5.43%. During early 2025 equity selloff, dynamically reduced equity exposure toward defensive assets. Uses distributional distance (Wasserstein) instead of standard Gaussian HMM.
- **Signal**: Replace standard HMM with Wasserstein-distance HMM for regime detection. More robust to non-Gaussian return distributions common in EM markets like Korea.
- **Relevance**: Direct upgrade to our MRS regime engine. H-11 already covers regime-conditional selection but uses standard regime detection. Wasserstein HMM is a METHODOLOGY improvement.
- **Priority**: ★★
- **Novel vs Existing**: **PARTIAL OVERLAP** with H-11. The regime detection METHOD (Wasserstein HMM) is new. The application (tactical allocation) is already covered.

---

### Paper [6]: Explainable Regime Aware Investing
- **Source**: arxiv 2603.04441 (Mar 2026 — very recent)
- **Finding**: Regime-aware factor investing with explainability. Uses interpretable ML to identify which factors drive returns in each regime, then allocates accordingly. Key innovation: the regime itself is defined by factor efficacy (which factors work), not by macro indicators.
- **Signal**: Factor-efficacy-defined regimes (not macro-defined). In "value regime," overweight value; in "momentum regime," overweight momentum. The regime is ENDOGENOUS to factor returns, not exogenous macro.
- **Relevance**: Different from H-04 (Sector Entropy) and H-11 (Macro Regime). This defines regimes by FACTOR PERFORMANCE itself. Potentially circular but interesting if combined with look-back windows.
- **Priority**: ★★
- **Novel vs Existing**: **GENUINELY NEW regime definition**. Our H-04 uses sector entropy, H-11 uses macro regimes, H-06 uses cross-asset vol term structure. None defines regimes by endogenous factor efficacy. However, risk of circularity/overfitting.

---

### Paper [7]: RegimeFolio — Regime Aware ML for Sectoral Portfolio Optimization
- **Source**: arxiv 2510.14986 (Oct 2025)
- **Finding**: Sector-level regime detection outperforms market-level regime detection. Each sector has its own regime dynamics. Using sector-specific forecasters captures heterogeneous responses to volatility shocks.
- **Signal**: Per-sector regime classification + sector-specialized return forecasters. Portfolio = weighted sum of sector-optimal portfolios.
- **Relevance**: Already partially covered by H-04 (Sector Entropy) but with a different mechanism. H-04 uses entropy as a meta-signal; this paper uses per-sector regime models.
- **Priority**: ★★
- **Novel vs Existing**: **PARTIAL OVERLAP** with H-04. The per-sector regime idea adds granularity.

---

### Paper [8]: Adaptive and Regime-Aware RL for Portfolio Optimization
- **Source**: arxiv 2509.14385 (Sep 2025)
- **Finding**: Reinforcement learning agents with explicit regime awareness outperform static and regime-unaware RL agents. The agent observes latent regime probabilities as state features.
- **Signal**: RL agent with regime probability as input feature. Not directly implementable in our R framework.
- **Relevance**: Low — requires RL infrastructure we don't have. Conceptually interesting but not actionable.
- **Priority**: ★
- **Novel vs Existing**: Partially overlaps H-11. Not actionable in our setup.

---

### Paper [9]: Combined ML for Stock Selection with Dynamic Weighting
- **Source**: arxiv 2508.18592 (Aug 2025)
- **Finding**: Dynamic weighting of multiple ML models (random forest, XGBoost, LSTM) using recent model performance (model momentum). Each model's weight is proportional to its rolling OOS IC. Ensemble Sharpe exceeds the weighted average of constituents.
- **Signal**: Model momentum ensemble: weight each factor/model by its trailing 63d IC. Apply to our factor scores — instead of fixed weights (0.4/0.6 for IVOL/Beta), use IC-weighted combination.
- **Relevance**: This is a METHODOLOGY for combining signals, applicable to any multi-factor strategy. Could improve Defense score weighting and multi-sleeve allocation.
- **Priority**: ★★
- **Novel vs Existing**: **GENUINELY NEW methodology** for signal combination. Not in H-01~H-11. IC-momentum weighting of factor scores is a practical and testable idea.

---

### Paper [10]: ML Enhanced Multi-Factor Quantitative Trading with Bias Correction
- **Source**: arxiv 2507.07107 (Jul 2025)
- **Finding**: Cross-sectional portfolio optimization using factor interactions with explicit bias correction. Key: factor INTERACTIONS (not just levels) carry independent alpha. The interaction between momentum and value within sector/size cohorts is distinct from standalone momentum or value.
- **Signal**: Interaction terms: `z(momentum) * z(value)` within sector-size buckets. Bias correction: subtract rolling mean of interaction to remove look-ahead.
- **Relevance**: Already partially explored in H-08 (DuPont x Industry Mom interaction). This paper generalizes to any factor pair interaction.
- **Priority**: ★★
- **Novel vs Existing**: **PARTIAL OVERLAP** with H-08 (factor interaction concept). The systematic approach to ALL factor interactions and bias correction is new.

---

### Paper [11]: Decision by Supervised Learning with Deep Ensembles (DSL)
- **Source**: arxiv 2503.13544 (Mar 2025)
- **Finding**: Formulating portfolio weight estimation directly as a supervised learning problem (predicting optimal weights, not returns) reduces error accumulation. Deep Ensembles (averaging multiple independently trained models) produce more robust portfolio weights.
- **Signal**: Direct weight prediction instead of return prediction + optimization. Not directly actionable in our R-only framework.
- **Relevance**: Conceptually interesting but requires deep learning infrastructure.
- **Priority**: ★
- **Novel vs Existing**: New methodology, not actionable in our R setup.

---

### Paper [12]: Generative AI for Stock Selection
- **Source**: arxiv 2602.00196 (Jan 2026)
- **Finding**: LLM-generated features from analyst estimate patterns achieve Sharpe 0.965 standalone. Ensemble with traditional analyst features: Sharpe 1.142 (+49% over baseline). LLMs extract non-obvious patterns from consensus data (revision timing, estimate clustering, language patterns).
- **Signal**: Use LLM to process analyst estimate text/patterns into features. Not directly replicable without API access, but the INSIGHT is: analyst consensus data contains more information than simple revision direction.
- **Relevance**: Supports H-01 (Consensus Bottleneck Dispersion) thesis that consensus data is under-exploited. The specific LLM approach needs API infrastructure we lack, but the finding that higher-order consensus features (dispersion, timing, clustering) matter is actionable.
- **Priority**: ★★
- **Novel vs Existing**: Supports H-01 direction. The LLM extraction method is new but the underlying alpha (analyst consensus patterns) overlaps with H-01.

---

### Paper [13]: AlphaAgents: LLM-based Multi-Agents for Equity Portfolio Construction
- **Source**: arxiv 2508.11152 (Aug 2025)
- **Finding**: Multi-agent LLM system with role-based specialization (analyst, risk manager, portfolio manager) for equity selection. Proof-of-concept for agentic quant research but performance claims modest.
- **Signal**: Multi-agent architecture for quant research (we already have this in our agent_team_config).
- **Relevance**: Low — confirms our multi-agent approach but doesn't offer new alpha.
- **Priority**: ★
- **Novel vs Existing**: Already covered by our OpenClaw architecture.

---

### Paper [14]: Momentum Factor Investing: Evidence and Evolution
- **Source**: SSRN 5561720 (Aug 2025, Bart van Vliet, Baltussen, Dom, Vidojevic)
- **Finding**: Factor momentum fully subsumes industry momentum. Cross-sectional factor momentum (trailing factor returns predict future factor returns) is stronger and more persistent than industry rotation. Post-2000 factor momentum is indistinguishable from pre-2000.
- **Signal**: Factor momentum: rank factors by trailing 12-1 month return, overweight top-performing factors. Already used in our IndMom sleeve (L-344).
- **Relevance**: Confirms our Factor Momentum approach (already implemented in STR_789+). Factor momentum subsumes industry momentum — our IndMom is on the right track.
- **Priority**: ★
- **Novel vs Existing**: **ALREADY COVERED** by IndMom / Factor Momentum implementation.

---

### Paper [15]: Korea's 2025 Governance Revolution: Unlocking Shareholder Value
- **Source**: SSRN 5374843 (Aug 2025, Song & Chun)
- **Finding**: Korea Value-Up program and governance reforms (Commercial Act amendments Jul 2025) create a structural shift. KVI (Korea Value-Up Index) outperformed KOSPI 200 by 30%+ since launch. Governance quality now a significant factor in Korean equity returns. Tax incentives for high-dividend Value-Up participants.
- **Signal**: `Governance_Score = z(dividend_payout_change) + z(ROE_improvement) + z(treasury_share_cancellation) + z(shareholder_communication_score)`. Long stocks actively participating in Value-Up program with improving governance metrics. This is a STRUCTURAL ALPHA specific to Korea 2025-2026.
- **Relevance**: **HIGHLY RELEVANT** to our Korean equity portfolio. This is a regime-specific, Korea-specific alpha source that is GENUINELY NEW and not covered by any H-01~H-11 hypothesis. The Value-Up program creates a government-induced factor premium.
- **Priority**: ★★★
- **Novel vs Existing**: **GENUINELY NEW**. No existing hypothesis covers Korea-specific governance reform alpha. This is a structural break in Korean equity market dynamics. Time-sensitive — the Value-Up premium may decay as it becomes widely known, but currently in early stages.

---

### Paper [16]: Cross-Sectional Factor Momentum: Evidence from Multiple Formation Periods
- **Source**: Applied Economics Letters (2025, doi: 10.1080/13504851.2025.2472032)
- **Finding**: Factor momentum is robust across multiple formation periods (1, 3, 6, 12 months). Strategies using intermediate past returns yield highest mean returns for industry momentum.
- **Signal**: Multi-horizon factor momentum (already explored in our 13612W approach).
- **Relevance**: Confirms existing approach. Minor methodological note.
- **Priority**: ★
- **Novel vs Existing**: **ALREADY COVERED**.

---

### Paper [17]: Generating Alpha: Hybrid AI-Driven Trading System for Regime-Adaptive Strategies
- **Source**: arxiv 2601.19504 (Jan 2026, accepted at ComSIA 2026)
- **Finding**: Hybrid system combining technical analysis, ML, and financial sentiment for regime-adaptive equity strategies. Integrates multiple signal types with regime conditioning.
- **Signal**: Multi-signal regime-adaptive system. General framework, not specific signals.
- **Relevance**: General framework confirmation, not new alpha.
- **Priority**: ★
- **Novel vs Existing**: Framework overlap with our existing regime + factor approach.

---

### Paper [18]: Variance Risk Premium Over Trading and Nontrading Periods
- **Source**: Journal of Futures Markets (2025, Papagelis, doi: 10.1002/fut.22589)
- **Finding**: VRP decomposition: overnight VRP is significantly NEGATIVE (risk compensation), intraday VRP is POSITIVE and often insignificant. Overnight component predicts longer horizons; intraday component predicts shorter horizons.
- **Signal**: `Overnight_VRP = implied_vol_close_to_open - realized_vol_overnight`. Use overnight VRP as a stress predictor for portfolio timing. Better than standard VRP (which mixes the two components).
- **Relevance**: Enhancement to H-06 (Cross-Asset Vol Term Structure). The overnight/intraday decomposition adds a new dimension to volatility-based timing.
- **Priority**: ★★
- **Novel vs Existing**: **GENUINELY NEW dimension** within VRP analysis. H-06 uses vol term structure (1m vs 3m); this paper decomposes by TRADING PERIOD (overnight vs intraday). Orthogonal dimension.

---

### Paper [19]: Dynamic Factor Allocation Leveraging Regime-Switching Signals
- **Source**: arxiv 2410.14841 (Oct 2024, but relevant to 2025 framework)
- **Finding**: Dynamic allocation among 7 factor indices (market, value, size, momentum, quality, etc.) using regime-switching signals. US equity focus. Factors have cyclical performance tied to macro regimes.
- **Signal**: Regime-dependent factor weights using HMM on macro indicators. Already partially covered by our FM (Factor Momentum) and MRS.
- **Relevance**: Confirms our FM + regime approach.
- **Priority**: ★
- **Novel vs Existing**: **ALREADY COVERED** by our Factor Momentum + Soft MRS.

---

### Paper [20]: Sentiment-Aware Stock Price Prediction with LLM-Generated Formulaic Alpha
- **Source**: arxiv 2508.04975 (Aug 2025)
- **Finding**: LLMs generate formulaic alpha factors from text sentiment that add ~15% incremental Sharpe to price-based factors. The key is converting unstructured sentiment to structured, testable factor formulas.
- **Signal**: LLM-generated sentiment factors. Requires NLP infrastructure.
- **Relevance**: Conceptually interesting but needs NLP pipeline.
- **Priority**: ★
- **Novel vs Existing**: New methodology, not directly actionable.

---

## Synthesis: Genuinely NEW Ideas Not in H-01~H-11

| # | Paper | New Idea | Actionable? | Priority |
|---|-------|----------|-------------|----------|
| 1 | **Drift Regime (2511.12490)** | Stock-level drift detection (>60% positive days) as gate for value+reversal signals | **YES — RAWDATA only** | ★★★ |
| 2 | **Korea Governance Value-Up (SSRN 5374843)** | Korea-specific governance reform alpha (Value-Up participation, dividend/ROE improvement) | **YES — DART + KRX** | ★★★ |
| 3 | **Explainable Regime Aware (2603.04441)** | Factor-efficacy-defined regimes (endogenous, not macro-based) | **YES — RAWDATA** | ★★ |
| 4 | **IC-Momentum Signal Weighting (2508.18592)** | Weight factor scores by trailing IC instead of fixed weights | **YES — simple** | ★★ |
| 5 | **IVOL-Only Defense (SSRN 5005746)** | Pure IVOL without Beta may outperform IVOL+Beta composite | **YES — one-line change** | ★★ |
| 6 | **Overnight VRP Decomposition (Papagelis 2025)** | Overnight vs intraday VRP decomposition for timing | **MAYBE — needs intraday data** | ★★ |
| 7 | **Wasserstein HMM Regime (2503.11499)** | Distributional-distance regime detection replacing Gaussian HMM | **YES — R package available** | ★★ |

### Top 5 Recommendations for Implementation

1. **H-12: Stock-Level Drift Regime Gating** (Paper 1) — ★★★
   - Construct: `drift_flag = (sum(ret > 0, 63d) / 63 > 0.60)`
   - When flag=TRUE: apply `z(BM) + z(-ret_5d)` value+reversal score
   - When flag=FALSE: exclude stock from universe
   - RAWDATA only, trivially implementable, completely novel
   - Expected orthogonality: Defense ~0.15, IndMom ~0.25 (different mechanism)

2. **H-13: Korea Value-Up Governance Alpha** (Paper 15) — ★★★
   - Construct: `ValueUp_Score = z(div_payout_change_YoY) + z(ROE_delta) + z(treasury_cancel_flag) + z(foreign_own_change)`
   - Long top-quintile Value-Up improvers, sector-neutral
   - Time-sensitive structural alpha (Korean policy-driven)
   - DART fundamentals + KRX ownership data
   - Expected orthogonality: Defense ~0.10, IndMom ~0.15 (governance != price patterns)

3. **H-14: IC-Momentum Factor Weighting** (Paper 9) — ★★
   - Replace fixed weights (0.4/0.6 for IVOL/Beta) with rolling 63d IC-weighted combination
   - Generalizable: apply to ANY multi-factor score, not just Defense
   - One-line change in backtest_harness
   - Expected improvement: +0.05~0.10 Sharpe from adaptive weighting

4. **H-15: Factor-Efficacy Regimes** (Paper 6) — ★★
   - Define regimes by which factors work (trailing 63d factor IC), not by macro
   - In "IVOL works" regime: overweight Defense; in "Momentum works": overweight IndMom
   - Endogenous regime avoids macro data lag
   - Risk: circularity if formation = holding period. Use lag.
   - Expected orthogonality: different regime definition than MRS/FRED

5. **H-16: Pure IVOL Defense** (Paper 4) — ★★
   - Test Defense score = z(IdioVol)*1.0 (no Beta component)
   - Blitz et al. (2025): IVOL is the primary driver, Beta adds noise
   - One-line change: replace 0.4/0.6 weights with 1.0/0.0
   - If confirmed: simplifies Defense and may improve Sharpe

---

## Implementation Priority Matrix

| Batch | Ideas | Data Required | Complexity |
|-------|-------|---------------|------------|
| **Immediate** | H-12 (Drift Regime), H-14 (IC-Momentum), H-16 (Pure IVOL) | RAWDATA only | Low |
| **Short-term** | H-15 (Factor-Efficacy Regime) | RAWDATA only | Medium |
| **Medium-term** | H-13 (Value-Up Governance) | DART + KRX ownership | Medium |
| **Long-term** | H-06 enhancement (Overnight VRP), Wasserstein HMM | Intraday data, new R packages | High |

---

## Sources
- [Drift Regimes (arxiv 2511.12490)](https://arxiv.org/abs/2511.12490)
- [Factoring in Low-Vol (SSRN 5295002)](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=5295002)
- [Low-Risk Equity 2011-2025 (SSRN 5372550)](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=5372550)
- [Low-Risk Alpha Without Low Beta (SSRN 5005746)](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=5005746)
- [Tactical AA with Macro Regime (arxiv 2503.11499)](https://arxiv.org/abs/2503.11499)
- [Explainable Regime Aware Investing (arxiv 2603.04441)](https://arxiv.org/abs/2603.04441)
- [RegimeFolio (arxiv 2510.14986)](https://arxiv.org/abs/2510.14986)
- [Adaptive RL Portfolio (arxiv 2509.14385)](https://arxiv.org/abs/2509.14385)
- [Combined ML Dynamic Weighting (arxiv 2508.18592)](https://arxiv.org/abs/2508.18592)
- [ML Enhanced Multi-Factor (arxiv 2507.07107)](https://arxiv.org/abs/2507.07107)
- [DSL Deep Ensembles (arxiv 2503.13544)](https://arxiv.org/abs/2503.13544)
- [Generative AI Stock Selection (arxiv 2602.00196)](https://arxiv.org/abs/2602.00196)
- [AlphaAgents (arxiv 2508.11152)](https://arxiv.org/abs/2508.11152)
- [Momentum Factor Evidence (SSRN 5561720)](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=5561720)
- [Korea Governance Revolution (SSRN 5374843)](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=5374843)
- [Factor Momentum Formation Periods (doi: 10.1080/13504851.2025.2472032)](https://www.tandfonline.com/doi/full/10.1080/13504851.2025.2472032)
- [Regime-Adaptive Hybrid AI (arxiv 2601.19504)](https://arxiv.org/abs/2601.19504)
- [VRP Overnight/Intraday (doi: 10.1002/fut.22589)](https://onlinelibrary.wiley.com/doi/full/10.1002/fut.22589)
- [Dynamic Factor Allocation (arxiv 2410.14841)](https://arxiv.org/abs/2410.14841)
- [Sentiment + LLM Alpha (arxiv 2508.04975)](https://arxiv.org/abs/2508.04975)
