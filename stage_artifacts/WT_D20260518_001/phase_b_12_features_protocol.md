# Phase B 12 Features Direct Collection Protocol — v2.0

## 1. Rationale (v1.0 deferred features inherit)

v1.0 (WT-D20260519_002) Forge cycle built only 20 of planned 32 features:
- **Built (20)**: F11~F14 (VIX/realized vol), F17~F19 (asym cor/FX), F24 (US credit), F29~F32 (foreign flow/defensive), F01~F02 (US yield curve), F06~F09 (US LEI), F20~F21 (NFCI/StL), F22 (Bank Lending)
- **Deferred (12)**: F04 (KR yield curve), F10 (KR CPI), F15~F16 (VKOSPI), F23 (KR credit), F25 (KR credit deterioration), F26~F28 (SEFRS ETF flow — Phase A schema only)

v1.0 root cause analysis (Forge): KR-specific bear regime features missing. US macro signals (VIX/yield curve/LEI) capture global risk-off but **KR domestic regime drivers (KR yield curve / KRX VKOSPI / KR credit spread)** are critical for KR-specific bear month classification. Phase B inheritance from v1.0 design.

## 2. Phase B 12 Features (v2.0 mandate)

| # | Feature ID | Description | Source | Publish Lag | Usable_Date Rule | Coverage Stratum |
|---|---|---|---|---|---|---|
| **PB01** | `VKOSPI_level` | KRX implied vol, KOSPI200 ATM 30-day | KRX 정보데이터시스템 / pykrx | T+1 BD | Date ≤ sig_date - 1 BD | S3+ (2003-04~) |
| **PB02** | `VKOSPI_zscore_252d` | VKOSPI rolling z-score | derived from PB01 | inherit | inherit | S3+ |
| **PB03** | `SEIBro_foreign_bond_net_flow` | 외인 채권 net buy/sell daily | SEIBro 한국예탁결제원 | T+1 BD | Date ≤ sig_date - 1 BD | S2+ (2001-06~) |
| **PB04** | `KR_credit_spread_AA_minus_A` | KR 회사채 AA- vs A 등급별 spread | KAP/KIS 한국기업평가 | T+5 BD | Date ≤ sig_date - 5 BD | S2+ (2001-01~) |
| **PB05** | `KR_LEI_composite_yoy` | 통계청 경기선행지수 yoy growth | KOSIS 통계청 | T+1 month + 25 days | Date ≤ sig_date %m-% months(1) - days(25) | S1+ (1981-01~) |
| **PB06** | `KRX_foreign_equity_net_flow_intensity_20d` | KRX 외국인 일별 net buy zscore | KRX 정보데이터시스템 | T+2 BD (settlement) | Date ≤ sig_date - 2 BD | S2+ (1992-01~) |
| **PB07** | `KOSPI200_PE_12mFwd` | KOSPI200 12-month forward P/E consensus | FnGuide / 자체 DART aggregation | T+1 BD (consensus update) | Date ≤ sig_date - 1 BD | S3+ (2003~ FnGuide stable) |
| **PB08** | `KRW_USD_implied_vol_30d` | KRW/USD options implied vol 30-day | KRX FX options (KOSDAQ150 leg derive) / 자체 GARCH proxy | T+1 BD | Date ≤ sig_date - 1 BD | S3+ (2005~) |
| **PB09** | `KR_5y_minus_3m_yield_slope` | KR 국고채 5y - CD 3m | ECOS 한국은행 | T+5 BD | Date ≤ sig_date - 5 BD | S1+ (1995~) |
| **PB10** | `KOSPI200_dy_minus_KR_10y` | KOSPI200 dividend yield minus KR 10y bond yield | FnGuide + ECOS | T+5 BD | Date ≤ sig_date - 5 BD | S2+ (2001~) |
| **PB11** | `KOSPI200_EPS_revision_breadth_3m` | KOSPI200 consensus EPS revision count up vs down 3-month | FnGuide / DataGuide | T+5 BD | Date ≤ sig_date - 5 BD | S3+ (2003~) |
| **PB12** | `KR_M2_yoy_growth` | KR M2 money supply yoy | ECOS 한국은행 | T+1 month + 25 days | Date ≤ sig_date %m-% months(1) - days(25) | S1+ (1981~) |

## 3. Collection Path A/B/C (each feature)

### PB01-PB02: VKOSPI (KRX implied vol)
- **Path A (primary)**: `pykrx` Python package — `pykrx.stock.get_index_ohlcv("VKOSPI200", start, end)`
- **Path B (secondary)**: KRX 정보데이터시스템 manual CSV download (vkospi.kr 지수 검색 → 일별 데이터)
- **Path C (fallback)**: Self-compute via Black-Scholes IV inversion on KOSPI200 options chain (`02_Infrastructure/data/krx_options_fetch.py` — KRX options data exists)
- **Forge Stage 1 binding**: try A → B → C. If all fail, omit PB01-PB02 (degrade to 30 features). Document attempt log in `phase_b_fetch_audit.json`.

### PB03: SEIBro Foreign Bond Flow
- **Path A**: SEIBro `https://seibro.or.kr` public API (한국예탁결제원 — bond clearing data)
- **Path B**: KOFIA `https://kofia.or.kr` (금융투자협회 — daily bond stats)
- **Path C**: Naver Finance investor flow scrape (`02_Infrastructure/data/naver_investor_collector.R`) — equity only, NOT bond. SKIP if Path A/B fail.

### PB04: KR Credit Spread (AA- minus A)
- **Path A**: KAP 한국기업평가 daily yield curve data (private subscription)
- **Path B**: KIS 한국신용평가 daily yield (private subscription)
- **Path C**: ECOS 한국은행 회사채 yield series (`02_Infrastructure/data/data_collector_ecos.R`) — AA/BBB only, derive AA-/A spread via interpolation
- **Fallback**: if all fail, use US HY-IG spread (F24 from v1.0) as proxy, document limitation

### PB05: KR LEI Composite
- **Path A**: KOSIS `https://kosis.kr` 통계청 경기종합지수 (월별 발표)
- **Path B**: ECOS 한국은행 경기선행지수 (similar, monthly)
- **Path C**: Manual construction from 6 sub-components (재고출하순환선, 소비자기대지수, 종합주가지수, 장단기금리차, 수출입물가비율, 자본재수입액)

### PB06: KRX Foreign Equity Flow
- **Path A**: `investor_wide.parquet` already in cache (`.cache/investor_stock/investor_wide.parquet`) — daily foreign net buy per ticker
- Computation: aggregate to KOSPI200 universe daily total → 20d rolling z-score
- **Already available**. No external fetch needed.

### PB07: KOSPI200 Forward P/E
- **Path A**: FnGuide DataGuide consensus database (private, our cache `.cache/consensus/` may have it)
- **Path B**: DART aggregation — sum top-200 market cap × consensus EPS / index
- **Path C**: Bloomberg Terminal (offline manual update monthly)
- **Forge Stage 1**: probe `.cache/consensus/` for `kospi200_fwd_pe.parquet` first

### PB08: KRW/USD Implied Vol
- **Path A**: KRX FX options daily implied vol (limited liquidity 2015~)
- **Path B**: Self-compute 30-day realized vol from `FRED_DEXKOUS` daily (already available, proxy)
- **Path C**: GARCH(1,1) one-step-ahead vol forecast from DEXKOUS daily returns
- **Default**: Path B (realized vol proxy) — implied unavailable in KR market reliably

### PB09: KR Yield Slope
- **Path A**: ECOS `02_Infrastructure/data/data_collector_ecos.R` — KR Gov 5y + CD 3m daily
- **Already available** via existing ECOS pipeline. Just need to extract.

### PB10: KOSPI200 DY vs KR 10y
- **Path A**: FnGuide KOSPI200 dividend yield monthly + ECOS KR 10y yield
- **Path B**: Manual: sum_top200 (DPS × shares) / index_value / index_level
- **Forge Stage 1**: probe `.cache/consensus/kospi200_dy.parquet`

### PB11: EPS Revision Breadth
- **Path A**: FnGuide DataGuide consensus history — count up-revisions vs down-revisions 3-month rolling
- **Path B**: DART forecast filings (less granular)
- **Path C**: SKIP if both fail (downgrade to 11 features)

### PB12: KR M2 Growth
- **Path A**: ECOS 한국은행 M2 monthly series
- **Already available** via existing ECOS pipeline.

## 4. Coverage Stratum Update (vs v1.0)

| Stratum | Period | n_months | v1.0 features active | v2.0 features active (after Phase B) |
|---|---|---|---|---|
| **S1 (1990-2000)** | 132m | 3 (F14, F31, F32) | 3 + PB05, PB09, PB12 = **6** universal features |
| **S2 (2001-2002)** | 24m | 24 (S1 + US LEI + yield curve + foreign flow + credit) | 24 + PB03 (SEIBro) + PB04 (KR credit) + PB06 (KRX flow already) + PB10 (KOSPI DY vs KR 10y) = **27~28** |
| **S3 (2003-2016)** | 164m | 29 (S2 + VIX) | 29 + PB01-PB02 (VKOSPI) + PB07 (KOSPI200 fwd PE) + PB08 (KRW/USD vol) + PB11 (EPS revision) = **33~34** |
| **S4 (2016-09 ~ 2026)** | 117m | 32 (S3 + SEFRS) | 33~34 + SEFRS retain = **36~38** |

**Net effect**: S1 era coverage 3→6 features (2× expansion) directly addresses v1.0 Codex C5 concern (S1 underrepresented).

## 5. PIT C11 Compliance (publish-lag awareness)

All Phase B features include explicit publish lag in `feature_usable_date_table_v2.json` (Forge Stage 1 binding). Critical:
- **ECOS monthly** (KR M2, LEI): T+25 days after month-end (한국은행 publish convention)
- **KOSIS monthly** (LEI sub-components): T+25 days
- **SEIBro daily** (bond flow): T+1 BD (next-day settlement)
- **FnGuide consensus**: T+1 BD (intraday revision, conservative t-1)
- **KAP/KIS credit**: T+5 BD (corporate bond yields published with delay)

## 6. Forge Stage 1 Audit Binding

Per feature, Forge cycle Stage 1 runs:
```r
# For each Phase B feature PBxx
source("02_Infrastructure/validation/lookahead_detector.R")
source("02_Infrastructure/validation/pit_enforcement.R")

audit <- lookahead_audit(
  feature_data = pb01_vkospi_panel,
  sig_dates = sig_date_panel,
  usable_date_rule = "Date <= sig_date - 1 BD"
)
stopifnot(audit$pass == TRUE)
```

Failure of any feature audit → `phase_b_fetch_audit.json` log + degrade feature count + Forge Stage 1 abort if > 4 features fail.

## 7. v2.0 Feature Catalog Total

| Source | Count | Stratum reach |
|---|---|---|
| v1.0 built (20) | 20 | S2+ |
| v1.0 deferred → v2.0 Phase B (12) | 12 | S1+~S3+ |
| **v2.0 total target** | **32** | **S1~S4 all** |

S1 universal features 3 → 6 (with PB05/PB09/PB12) is the **most critical change** for v2.0 — extends academic backbone coverage to pre-2001 KR market (IMF crisis, dotcom).

## 8. References

- **Brown, D., Davies, S., & Ringgenberg, M. (2021)**. ETF non-fundamental demand and equity returns. *RFS* (SEIBro/SEFRS inherit)
- **Gilchrist, S., & Zakrajsek, E. (2012)**. Credit spreads and business cycle fluctuations. *AER* (PB04 KR credit)
- **Estrella, A., & Hardouvelis, G. A. (1991)**. The term structure as a predictor of real economic activity. *JF* (PB09 KR yield slope)
- **Stock, J. H., & Watson, M. W. (2003)**. Forecasting output and inflation: the role of asset prices. *JEL* (PB05 KR LEI, PB11 EPS breadth)
- **Whaley, R. E. (2009)**. Understanding the VIX. *JPM* (PB01-PB02 VKOSPI KR equivalent)
- **Bollerslev, T. (1986)**. Generalized autoregressive conditional heteroskedasticity. *J. Econometrics* (PB08 GARCH IV proxy)

## 9. Honest Disclosure

**Path B fallbacks accepted for v2.0 Phase A design phase** — actual fetch attempts and success/failure documented in Forge Stage 1 `phase_b_fetch_audit.json`. Self_synthesis prohibition (AX-002) strict: **no synthetic generation of unfetched features**. If Path A+B+C all fail for a feature, **drop the feature** and document in `phase_b_fetch_audit.json` — degrade to N<32 features, not synthesize fake data.

Forge Stage 1 expected outcome: 28~32 of 32 features successfully built (some Path C fallback). Realistic target: 28+ (12 of 32 may degrade to proxy or be dropped).
