# Vol-Managed MARKET Portfolio — Literature Re-Verification

**Task**: verify whether the "MARKET portfolio is the cost-after exception" corollary is real,
and with what qualifications. Generated 2026-07-02. All claims sourced from primary-text extraction
(pymupdf on published/working-paper PDFs) + verified abstracts. Unverified items flagged.

## 1. Moreira & Muir (JF 2017) — the origin claim
- **Published**: Journal of Finance 72(4), 1611-1644, 2017. DOI 10.1111/jofi.12513.
- **Method (exact, from published PDF eq. 1-2)**:
  - Managed factor: `f^σ_{t+1} = (c / σ̂²_t(f)) · f_{t+1}` (eq. 1). `c` chosen so managed series has the
    **same unconditional std** as buy-and-hold. **Footnote 6: `c` has NO effect on the Sharpe ratio** (pure scale).
  - `σ̂²_t(f) = RV²_t(f) = Σ_{d=1..22} (f_{t,d} − mean_t)²` (eq. 2) — demeaned sum of squared *daily*
    returns within the previous month. No hard cap in base spec (can lever > 1).
- **MARKET result (verbatim)**: *"For the market portfolio our strategy produces an alpha of 4.9%,
  an appraisal ratio of 0.33, and an overall 25% increase in the buy-and-hold Sharpe ratio."*
- **CRITICAL SCOPE**: US, 1926-2015, **GROSS of costs, IN-SAMPLE spanning regression** (managed on
  buy-hold, full-sample). This is the number the deep-research corollary rests on — but it is *gross + in-sample*.

## 2. Cederburg, O'Doherty, Wang, Yan (JFE 2020) — OOS / real-time kill
- **Published**: JFE 138 (2020) 95-117. 103 equity strategies.
- **Finding (verbatim abstract)**: *"Volatility-managed portfolios do not systematically outperform
  their corresponding unmanaged portfolios in direct comparisons ... the trading strategies implied by
  these [spanning] regressions are not implementable in real time, and reasonable out-of-sample versions
  generally earn LOWER certainty equivalent returns and Sharpe ratios than ... the original, unmanaged
  portfolios."* Cause = **structural instability in the spanning regressions**.
- **MARKET specifically (verbatim, decisive)**: *"The out-of-sample strategy combining the
  volatility-managed market portfolio and the unmanaged market portfolio ... earns an annualized
  Sharpe ratio of 0.42 compared with 0.46 for the strategy that limits its risky investment set to the
  unmanaged market portfolio. This combination strategy also leads to a reduction in CER."*
  → **Vol-timing the MARKET HURTS out-of-sample** (SR 0.42 < 0.46). OOS positives were only for
  MOM, ROE, BAB — NOT the market.

## 3. Barroso & Detzel (JFE 2021) — the cost-after MARKET exception (the corollary's source)
- **Published**: JFE 140(3), 744-767, 2021. DOI as EconPapers v140 i3 p744-767.
- **Finding (verbatim abstract)**: *"After accounting for transaction costs, volatility management of
  common asset-pricing factors besides the market return generally produces zero abnormal returns and
  significantly reduces Sharpe ratios. However, abnormal returns of the volatility-managed market
  portfolio ARE robust to transaction costs and concentrated in the most easily arbitraged stocks,
  those with low arbitrage risk and impediments to short selling. The managed-market strategy only
  provides superior performance when sentiment is high."*
- **So the MARKET exception is REAL — but heavily qualified**:
  1. It is a **cost-adjusted spanning/abnormal-return** result (in-sample framing), NOT an OOS SR win.
  2. It is a **limits-to-arbitrage / sentiment** story: gains concentrate in *easily arbitraged*,
     short-sale-constrained stocks, and appear *only when sentiment is high* — i.e. a behavioral
     mispricing that arbitrageurs would compete away where they can.
- **Six cost-mitigation strategies**: named in abstract but not quantified in the free abstract text
  (behind paywall). **UNVERIFIED**: exact per-strategy net-alpha figures for the market.

## 4. DeMiguel, Martín-Utrera & Uppal (JF 2024) — reconciliation
- **Published**: JF 2024, DOI 10.1111/jofi.13395 (open access).
- **Finding (verbatim intro)**: *"Cederburg et al. show that these strategies fail out-of-sample, and
  Barroso and Detzel show they do not survive transaction costs. We propose a conditional MULTIFACTOR
  portfolio that outperforms its unconditional counterpart even out-of-sample and net of costs."*
- Interpretation: DeMiguel **accepts** that (a) standalone vol-timing fails OOS (Cederburg) and (b)
  does not survive costs (Barroso-Detzel). The rescue is a *joint conditional multifactor* construction —
  NOT single-market vol-timing. So even the pro-vol-timing 2024 paper concedes the *standalone market*
  timing strategy does not survive OOS+cost on its own.

## 5. Angelidis & Tessaromatis (Journal of Financial Markets 2023) — decay
- *"The disappearing profitability of volatility-managed equity factors"*, JFM 65(C). 11 factors + 110 anomalies, US.
- **Finding**: timing alphas **disappeared** once the early-2000s trading/information environment made
  arbitrage cheaper; decay is larger for small-cap (illiquid, costly-to-short) portfolios — consistent
  with limits-to-arbitrage. Notes *"only the managed market and momentum strategies are partially robust
  to transaction costs."* → even the decay literature keeps the **market as a *partial* exception**, but
  frames the whole phenomenon as a fading, cost-and-arbitrage-driven mispricing.

## VERDICT (Track A)
The MARKET exception is **real but fragile and in-sample-flavored**:
- ✅ EXISTS in Barroso-Detzel (cost-adjusted abnormal return survives for the market where it dies for factors).
- ⚠️ It is a **limits-to-arbitrage / high-sentiment** effect concentrated in easily-arbitraged US stocks —
  a behavioral mispricing, not a robust risk premium.
- ❌ It does **NOT** hold **out-of-sample / real-time**: Cederburg finds vol-timing the market gives
  OOS SR 0.42 < 0.46 (buy-hold). DeMiguel 2024 concurs the standalone strategy fails OOS+cost.
- Net: the corollary should be read as "the market is the *last factor standing* under an in-sample
  cost adjustment, driven by US retail-sentiment mispricing" — a weak, non-transferable exception,
  not a green light for a deployable vol-timing overlay.

## Sources
- Moreira & Muir 2017: https://onlinelibrary.wiley.com/doi/abs/10.1111/jofi.12513 · https://amoreira2.github.io/alan-moreira.github.io/VolPortfolios_published.pdf
- Cederburg et al. 2020: https://www.lehigh.edu/~xuy219/research/COWY.pdf (JFE 138, 2020)
- Barroso & Detzel 2021: https://ideas.repec.org/a/eee/jfinec/v140y2021i3p744-767.html · https://papers.ssrn.com/sol3/papers.cfm?abstract_id=3088828
- DeMiguel et al. 2024: https://onlinelibrary.wiley.com/doi/full/10.1111/jofi.13395
- Angelidis & Tessaromatis 2023: https://ideas.repec.org/a/eee/finmar/v65y2023ics1386418123000551.html
