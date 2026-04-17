# Paper Ensemble Hypotheses — Cross-Paper Alpha Combinations
# Generated: 2026-03-14 | Scout Agent
# Goal: Genuinely NEW alpha dimensions orthogonal to Defense (IdioVol/Beta) and IndMom

## Context
- **Existing alphas**: Defense (corr 1.00), IndMom (corr 0.687), Orthogonal Residual (candidate, corr TBD)
- **Confirmed failures**: QMJ standalone (L-402), MAX/IdioSkew (L-313), DART Value/Carry/Accruals (corr 0.81+ with Defense)
- **Korean market constraints**: Long-only, no short-selling, limited QA capital, ~0% post-pub decay (L-029)
- **Infrastructure**: RAWDATA (OHLCVS 2001-2026), DART fundamentals (2016+), macro_fred.parquet, KRX data

---

### Hypothesis H-01: Consensus Bottleneck Dispersion
- **Core**: Bordalo et al. (2012, P031) Salience Theory — investors overweight salient payoff states, creating systematic mispricing of attention-grabbing vs neglected stocks
- **Recent**: [2512.16251] Consensus-Bottleneck APM (POSTECH) — Sharpe 1.44 regime-robust; identifies stocks where analyst consensus bottlenecks (extreme agreement or disagreement) predict returns
- **Signal**: `CBDisp = z(analyst_target_price_dispersion) * z(-attention_proxy)`. Attention_proxy = 20d abnormal volume / 60d median volume. Long stocks with HIGH analyst disagreement but LOW retail attention (hidden information asymmetry). Sector-neutral z-scores. Monthly rebalancing.
- **Mechanism**: When analysts disagree strongly but the stock is NOT salient to retail investors, information is being processed by informed participants but not yet reflected in prices. This is the "bottleneck" — information exists but flows slowly. Salience theory predicts retail investors focus on vivid recent events, missing these hidden disagreements. The alpha decays as the consensus resolves (1-3 months).
- **Data**: Analyst consensus data (target price dispersion, coverage count) from FnGuide/WiseFn + RAWDATA (volume, returns)
- **Orthogonality**: Expected corr with Defense ~0.15 (disagreement != volatility), IndMom ~0.25 (partially overlaps with information flow). This is an INFORMATION ASYMMETRY dimension, fundamentally different from price-pattern alphas.
- **Priority**: ★★★

---

### Hypothesis H-02: Transfer Entropy Flow Networks
- **Core**: Kyle (1985, P053/P105) — informed traders reveal private information through trading; price impact is proportional to information content
- **Recent**: [2410.20597] Extracting Alpha from Financial Analyst Networks — analyst network centrality predicts return comovement and alpha transmission
- **Signal**: `TEFlow_i = sum(TE(j->i)) - sum(TE(i->j))` where TE = Transfer Entropy from daily returns of stock j to stock i, computed over rolling 63d windows. Long stocks that are NET INFORMATION RECEIVERS (high inbound TE, low outbound TE) — these are stocks absorbing information from the market slowly, creating predictable delayed adjustment. Sector-neutral. Biweekly rebalancing.
- **Mechanism**: Kyle's model implies information flows from informed to uninformed markets. Transfer entropy captures the DIRECTION of information flow between stocks. Net receivers are stocks where the market leads — their prices adjust with a delay to information already reflected elsewhere. This is distinct from momentum (which captures price trends) because TE measures information causality, not mere correlation.
- **Data**: RAWDATA daily returns only. TE computation is O(N^2) but feasible for top 500 liquid stocks.
- **Orthogonality**: Expected corr with Defense ~0.05 (information flow != volatility), IndMom ~0.35 (some overlap with delayed adjustment). Novel NETWORK/CAUSALITY dimension.
- **Priority**: ★★★

---

### Hypothesis H-03: Disposition-Anchored Earnings Surprise
- **Core**: Disposition Effect (Shefrin & Statman 1985, P013) — investors sell winners too early and hold losers too long, creating predictable underreaction
- **Recent**: [2512.00280] Retail Investor Horizon and Earnings Announcements — PEAD is +2.31pp stronger for stocks held predominantly by short-horizon retail investors
- **Signal**: `DAES_i = z(EPS_surprise) * z(retail_disposition_proxy)`. Retail_disposition_proxy = (proportion of shares near 52-week low held without selling) estimated from volume patterns around prior announcements. Long stocks with POSITIVE earnings surprise AND HIGH disposition effect (retail holders refusing to sell losers — they will also under-react to good news). Rebalance at earnings announcement + 2 trading days.
- **Mechanism**: Disposition effect creates asymmetric under-reaction: retail investors who hold losers are psychologically anchored to their purchase price. When positive earnings news arrives, these investors sell to "break even" rather than letting winners run. This selling pressure temporarily suppresses the post-announcement drift. The alpha is the residual PEAD amplified by disposition behavior. Event-driven timing makes this independent of monthly factor signals.
- **Data**: Earnings announcement dates (from DART or FnGuide), EPS surprise (consensus - actual), RAWDATA for volume/price patterns
- **Orthogonality**: Expected corr with Defense ~0.10 (event-driven vs cross-sectional), IndMom ~0.30 (related to PEAD but different timing). Novel EVENT x BEHAVIORAL dimension.
- **Priority**: ★★

---

### Hypothesis H-04: Regime-Conditional Sector Entropy
- **Core**: Ang & Bekaert (2002) Regime Switches — macro regimes create distinct factor payoff environments; the existing MRS/FRED regime engine captures this at the market level
- **Recent**: [2510.14986] RegimeFolio — regime-aware ML for sectoral portfolio optimization; sector-level regime detection outperforms market-level
- **Signal**: `SectorEntropy_t = -sum(w_s * log(w_s))` where w_s = sector share of top-quintile momentum stocks. When entropy is HIGH (momentum spread across many sectors), use broad factor exposure. When entropy is LOW (momentum concentrated in 1-2 sectors), use sector-dispersion tilt favoring neglected sectors (contrarian). The key innovation: use regime state to SWITCH between momentum-chasing and contrarian modes.
- **Mechanism**: Low sector entropy = crowded momentum trade in few sectors = imminent reversal risk. High entropy = broad-based momentum = sustainable trend. This is a META-SIGNAL that tells you WHEN to trust momentum vs when to fade it. Combined with existing Soft MRS (L-399), this creates a two-dimensional regime map: (market stress level) x (momentum concentration). The four quadrants each have distinct optimal strategies.
- **Data**: RAWDATA only (sector classification + returns for entropy computation)
- **Orthogonality**: Expected corr with Defense ~0.20 (regime-linked), IndMom ~0.45 (directly modifies IndMom). This is a REGIME x MOMENTUM META dimension. Not a new standalone alpha but a powerful allocation signal for the all-weather portfolio.
- **Priority**: ★★

---

### Hypothesis H-05: Intangible Capital Mispricing via R&D Persistence
- **Core**: Richardson et al. (2005, P042/P048) Accrual Decomposition — accruals (asset growth not backed by cash) are mispriced; the market treats all balance sheet growth equally
- **Recent**: Alpha Architect "Unlocking Hidden Value: Intangible Investment" (2026-03-13) — corporate language reveals intangible investment levels that accounting standards miss; intangible-adjusted valuations predict returns
- **Signal**: `IntangibleMisprice_i = z(R&D_intensity_3yr_avg) * z(-book_to_market)`. Long stocks with HIGH R&D intensity but LOW book-to-market (i.e., the market is pricing them as "expensive" despite persistent intangible investment that is being expensed, not capitalized). Add filter: R&D/Revenue must be INCREASING over 3 years (persistence = real investment, not one-time). Sector-neutral within tech/pharma/industrial sectors. Annual rebalance aligned with fiscal year.
- **Mechanism**: K-IFRS (and GAAP) expense most R&D immediately, understating true economic assets. Firms persistently investing in R&D are building intangible capital that does not appear on the balance sheet. The market applies standard PBR/PE valuation = these firms look "expensive." But the accrual anomaly logic applies in reverse: R&D expense is a "negative accrual" that OVERSTATES economic cost and UNDERSTATES economic assets. This is the mirror image of the Sloan accrual anomaly (P047) applied to intangible investment.
- **Data**: DART fundamentals (R&D expense, Revenue, BookValue, MarketCap). R&D is available in DART income statements.
- **Orthogonality**: Expected corr with Defense ~0.15 (R&D firms tend to be mid-vol), IndMom ~0.20 (weak). This is a FUNDAMENTAL MISPRICING dimension distinct from price-pattern alphas.
- **Priority**: ★★★

---

### Hypothesis H-06: Cross-Asset Volatility Term Structure Signal
- **Core**: VRP (Variance Risk Premium) concept — the spread between implied and realized volatility reflects risk compensation
- **Recent**: [2402.05272] Downside Risk Reduction Using Regime-Switching Signals — regime signals from derivative markets improve equity drawdown control; [2410.14841] Dynamic Factor Allocation with regime-switching
- **Signal**: `CAVTS_t = z(VKOSPI_1m - VKOSPI_3m) * sign(term_spread_change_5d)`. When near-term implied vol is ELEVATED relative to longer-term (inverted vol term structure) AND interest rate term spread is narrowing, this signals imminent stress. Use as a TIMING OVERLAY: scale factor exposure by `max(0, 1 - 2*z(CAVTS))`. Unlike existing MRS which is binary or linear, this combines TWO different cross-asset signals multiplicatively for higher precision.
- **Mechanism**: Inverted vol term structure = market participants hedging near-term risk more than long-term (fear of imminent crash). Combined with flattening yield curve = macro deterioration. The multiplicative combination creates a high-specificity crisis detector. The existing MRS (L-399) uses CrossAsset z-score additively; this hypothesis uses term-structure SLOPE and CHANGE, which are derivative (second-order) signals.
- **Data**: VKOSPI (or V-KOSPI200) term structure data (1m/3m), macro_fred.parquet (term spread already available)
- **Orthogonality**: This is not a stock-selection alpha but a PORTFOLIO-LEVEL TIMING signal. Expected to reduce MDD by 3-5pp without CAGR drag (precision timing vs broad regime). Enhances Defense overlay, not correlated with stock-level alphas.
- **Priority**: ★★

---

### Hypothesis H-07: Overconfidence Decay Cycle
- **Core**: Odean (1998, P019) Overconfidence — overconfident investors trade too much, generating predictable patterns of excess volume followed by poor returns
- **Recent**: [2511.15214] Corporate Earnings Calls and Analyst Beliefs — analyst belief updating after earnings calls shows systematic overreaction followed by correction; [2602.00196] Generative AI for Stock Selection — AI-extracted analyst confidence features predict returns
- **Signal**: `OCDecay_i = z(abnormal_volume_post_earnings_5d) * z(-return_post_earnings_20d)`. Long stocks where earnings announcement triggered HIGH volume (overconfident reaction) but price REVERSED within 20 days (the overconfidence correction). Wait for correction to complete (20d post-earnings), then enter LONG for the next 40 trading days (the "resumption" phase where fundamental value reasserts). This is NOT standard PEAD — it specifically targets the POST-OVERREACTION resumption.
- **Mechanism**: Odean's overconfidence predicts excessive trading around information events. The 5d abnormal volume captures the overconfident reaction. The 20d reversal captures the correction. After the correction, the stock resumes its fundamental trajectory. This three-phase cycle (overreaction -> correction -> resumption) creates a predictable entry point distinct from both momentum and reversal.
- **Data**: RAWDATA (volume, returns) + earnings announcement dates (DART)
- **Orthogonality**: Expected corr with Defense ~0.05 (event-driven timing), IndMom ~0.15 (different cycle phase). Novel BEHAVIORAL CYCLE dimension.
- **Priority**: ★★

---

### Hypothesis H-08: DuPont Efficiency Divergence x Industry Momentum
- **Core**: KB DuPont ROE-Delta (P186, IDEA_037) — delta in DuPont components (margin, turnover, leverage) predicts Korean returns with IR 0.84
- **Recent**: [2507.07107] ML Enhanced Multi-Factor Quantitative Trading — cross-sectional portfolio optimization using factor interactions; factor INTERACTIONS (not just levels) carry independent alpha
- **Signal**: `DuPontDiv_i = z(delta_asset_turnover_i - median(delta_asset_turnover_sector)) * z(industry_momentum_63d)`. Long stocks where asset turnover is IMPROVING relative to sector peers AND the industry is in a positive momentum phase. The key insight: operational efficiency improvement is only rewarded when the industry tailwind allows the efficiency gain to translate to revenue growth. Without industry momentum, efficiency gains may reflect cost-cutting in a declining market (value trap).
- **Mechanism**: DuPont decomposition isolates operational efficiency from financial leverage. Delta_asset_turnover captures genuine operational improvement. Industry momentum provides the macro context. The INTERACTION is the novel signal: efficiency gain + industry tailwind = sustainable earnings growth. This is different from standalone quality (L-402 confirmed quality fails in Korea) because the interaction term captures a CONDITIONAL relationship.
- **Data**: DART fundamentals (Revenue, TotalAssets — 2 consecutive years), RAWDATA (industry returns for momentum)
- **Orthogonality**: Expected corr with Defense ~0.20 (fundamental + price), IndMom ~0.40 (industry momentum component). Partially overlaps with IndMom but the EFFICIENCY CONDITIONING creates a genuinely different selection mechanism.
- **Priority**: ★★

---

### Hypothesis H-09: Herding-Contrarian Asymmetry (HCA)
- **Core**: Herding (Asch 1955, P018) — conformity bias leads institutional investors to follow each other, creating crowded positions and subsequent reversals
- **Recent**: Alpha Architect "Defensive Strategies: Two Centuries" (2026-03-09) — defensive strategies work best precisely when behavioral biases (herding into growth) are strongest
- **Signal**: `HCA_i = z(-corr(stock_i_returns, sector_avg_returns, 63d)) * z(foreign_ownership_change_3m)`. Long stocks where (a) returns are DECORRELATED from sector average (contrarian positioning — NOT herding) AND (b) foreign institutional ownership is INCREASING (smart money accumulating while herd ignores). This captures stocks being accumulated by informed investors AGAINST the herd.
- **Mechanism**: Korean market has extreme herding behavior (retail dominance, media-driven attention). When foreign institutions (traditionally better-informed in Korean equities) buy stocks that are NOT moving with their sector, they are expressing a view that the stock's fundamentals diverge from sector sentiment. The decorrelation filters out stocks being sold due to sector rotation (noise) from those with genuine idiosyncratic alpha being recognized by sophisticated investors. Two centuries of evidence (Alpha Architect) confirms defensive/contrarian strategies persistently exploit behavioral biases.
- **Data**: RAWDATA (returns for correlation), KRX foreign ownership data (available quarterly from KRX/DART disclosure)
- **Orthogonality**: Expected corr with Defense ~0.25 (low-corr stocks may overlap with low-vol), IndMom ~-0.10 (contrarian to industry direction). This is a CROWDING/CONTRARIAN dimension with institutional flow confirmation.
- **Priority**: ★★★

---

### Hypothesis H-10: Variance Ratio Information Speed
- **Core**: Lo & MacKinlay (1988) Variance Ratio — deviations from random walk indicate predictability; variance ratio < 1 implies mean reversion, > 1 implies trending
- **Recent**: [2208.14267] Beyond Volatility: Common Factors in Idiosyncratic Quantile Risks — idiosyncratic quantile risks have common structure; the SHAPE of return distribution (not just variance) carries cross-sectional information
- **Signal**: `VRSpeed_i = z(VR(5d/1d)_i - VR(20d/5d)_i)`. VR = variance ratio. Long stocks where SHORT-TERM VR > LONG-TERM VR, meaning the stock trends at the daily level but mean-reverts at the weekly level. This pattern indicates that information is being incorporated QUICKLY at high frequency but the weekly price discovery is dominated by liquidity/noise. The SPREAD between timeframes captures "information processing speed."
- **Mechanism**: Stocks with fast short-term information incorporation (VR>1 at 5d/1d) but slow long-term adjustment (VR<1 at 20d/5d) are priced efficiently for news but inefficiently for fundamentals. This creates a persistent cross-sectional alpha: buy stocks that process information quickly (less mispricing risk) but still have mean-reversion at lower frequency (reversion to fair value). This is theoretically distinct from both IdioVol (level of noise) and momentum (direction of trend).
- **Data**: RAWDATA daily returns only. Computationally trivial.
- **Orthogonality**: Expected corr with Defense ~0.10 (VR != volatility), IndMom ~0.20 (weak). Novel MICROSTRUCTURE/INFORMATION SPEED dimension.
- **Priority**: ★★

---

### Hypothesis H-11: Macro Regime Payoff Asymmetry (MRPA)
- **Core**: Existing regime engine (MRS, FRED, CrossAsset) — regime detection for portfolio-level risk management
- **Recent**: [2503.11499] Tactical Asset Allocation with Macroeconomic Regime Detection; [2601.05428] Dynamic Inclusion and Bounded Multi-Factor Tilts — risk budgeting + drawdown control via dynamic factor tilts
- **Signal**: `MRPA_i = Sharpe_expansion_i / Sharpe_contraction_i` computed over expanding window. Long stocks with HIGHEST payoff asymmetry: stocks that perform disproportionately well in expansion regimes relative to contraction regimes. Combined with regime probability: exposure = `w_i * P(expansion) + 0 * P(contraction)`. In expansion, hold the asymmetric winners. In contraction, reduce to zero.
- **Mechanism**: Most factor strategies implicitly assume stationary factor premia. MRPA explicitly selects stocks whose alpha is regime-DEPENDENT. By overweighting stocks with the highest expansion/contraction Sharpe ratio during expansions and cutting them during contractions, we capture the conditional alpha that static strategies miss. This is different from the existing Soft MRS (which scales PORTFOLIO exposure) because MRPA changes the STOCK SELECTION within each regime.
- **Data**: RAWDATA + regime classification (already available from regime_engine.R)
- **Orthogonality**: Expected corr with Defense ~0.30 (regime-linked), IndMom ~0.35. This is a REGIME x STOCK SELECTION interaction. Not fully independent but captures a genuinely different dimension than current regime overlays (which only adjust exposure level, not stock selection).
- **Priority**: ★★

---

## Priority Summary

| Rank | Hypothesis | Name | Priority | Novelty | Feasibility |
|------|-----------|------|----------|---------|-------------|
| 1 | H-01 | Consensus Bottleneck Dispersion | ★★★ | Information Asymmetry | Needs consensus data |
| 2 | H-02 | Transfer Entropy Flow Networks | ★★★ | Network/Causality | RAWDATA only |
| 3 | H-05 | Intangible Capital Mispricing | ★★★ | Fundamental Mispricing | DART available |
| 4 | H-09 | Herding-Contrarian Asymmetry | ★★★ | Crowding/Contrarian | KRX ownership needed |
| 5 | H-03 | Disposition-Anchored Earnings | ★★ | Behavioral x Event | Needs earnings dates |
| 6 | H-04 | Regime-Conditional Sector Entropy | ★★ | Regime x Momentum Meta | RAWDATA only |
| 7 | H-06 | Cross-Asset Vol Term Structure | ★★ | Portfolio Timing | VKOSPI needed |
| 8 | H-07 | Overconfidence Decay Cycle | ★★ | Behavioral Cycle | Needs earnings dates |
| 9 | H-08 | DuPont Efficiency x Industry Mom | ★★ | Fundamental x Momentum | DART available |
| 10 | H-10 | Variance Ratio Information Speed | ★★ | Microstructure | RAWDATA only |
| 11 | H-11 | Macro Regime Payoff Asymmetry | ★★ | Regime x Selection | Available now |

## Implementation Recommendation

**Batch 1 (immediate — RAWDATA only):**
- H-02 Transfer Entropy Flow Networks
- H-10 Variance Ratio Information Speed
- H-04 Regime-Conditional Sector Entropy
- H-11 Macro Regime Payoff Asymmetry

**Batch 2 (after DART/consensus data alignment):**
- H-05 Intangible Capital Mispricing (R&D from DART)
- H-08 DuPont Efficiency x Industry Mom (DART)
- H-01 Consensus Bottleneck Dispersion (consensus data required)

**Batch 3 (after event data pipeline):**
- H-03 Disposition-Anchored Earnings Surprise
- H-07 Overconfidence Decay Cycle
- H-09 Herding-Contrarian Asymmetry (KRX ownership data)

**Batch 4 (overlay/timing):**
- H-06 Cross-Asset Vol Term Structure (VKOSPI data)
