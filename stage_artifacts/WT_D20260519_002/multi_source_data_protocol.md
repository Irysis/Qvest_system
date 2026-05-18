# Multi-Source Data Protocol — Step 2.2

**WT-D20260519_002 Bear Prediction Engine v1.0**

**도훈 mandate "자율성 발휘"** 정합 — Qvest 인프라 적극 활용 + 직접 수집 protocol design.

본 protocol은 **각 source PIT lag rule + Coverage timeline + Missing rate + Fetch path** 명시.

---

## 1. Source Inventory — Qvest 인프라 + 직접 수집 (12 sources)

| ID | Source | Type | Qvest infra | Direct fetch | Coverage | Cache path |
|---|---|---|---|---|---|---|
| S01 | **Factor DB monthly** | KR equity factor | ✅ active | n/a | 1990-01~2026-05 | `.cache/factor_db/factor_db_*.parquet` |
| S02 | **Factor DB daily** | KR equity factor | ✅ active | n/a | 1990-01~2026-04 | `.cache/factor_db_daily/fdb_daily_*.parquet` |
| S03 | **rawdata.parquet** (price/vol/sector/BM) | KR universe | ✅ active | n/a | 1990-01~2026-05 | `.cache/rawdata.parquet` |
| S04 | **FRED macro** (22 series) | US/global macro | ✅ active | mcp__fred backup | 2000-01~2026-05 | `.cache/fred_macro.parquet` |
| S05 | **ECOS bond rates** (7 series) | KR macro | ✅ active | direct 한국은행 API | 2001-01~2026-03 | `.cache/ecos_bond_rates.parquet` |
| S06 | **ECOS macro extended** (PMI/CPI/IP) | KR macro | partial (CPI only cached) | mcp__fred backup + 통계청 | 2000+ partial | `.cache/macro_fred.parquet` partial overlap |
| S07 | **investor_wide** (foreign/inst/indiv/other net buy) | KR flow | ✅ active | KRX direct fallback | 2000-01~2026-04 | `.cache/investor_stock/investor_*.parquet` |
| S08 | **SEIBro ETF complex** (252670/114800/122630) | KR ETF flow | SEFRS Phase A protocol inherit | direct download fallback A/B/C | 2016-09~2026 | inherit WT-D20260518_001 |
| S09 | **VKOSPI** | KR vol | ❌ not cached | KRX 정보데이터시스템 fetch | 2003~ (after fetch) | NEW fetch protocol |
| S10 | **macro_regime composite** (pre-computed FRED rolled-up) | regime indicators | ✅ active | derived from S04 | 2000-01~2026-05 | `.cache/macro_regime.parquet` |
| S11 | **MSM regime engine** | regime probability | ✅ active | `02_Infrastructure/regime/regime_*.R` | 1990+ derivable | engine on-demand |
| S12 | **M4 BOCPD inherit** (STR_1715 Layer 3) | regime overlay | ✅ active | inherit Session 80 | 2000~2026-05 | STR_1715 lineage |

**Total**: 12 sources active. **VKOSPI (S09)** = direct fetch mandate.

---

## 2. PIT lag rule per source (Charter §1 + C1~C15 정합)

각 source의 정확한 lag rule + 본 cycle에서 사용 시점 명시:

### S01/S02/S03 — Factor DB + rawdata
- **Lag rule**: t-1 close strict (price/vol/return)
- **C2**: same-day circular 금지 — t-1 mandatory
- **C9**: VT/DD/FM lag c(0, [-n]) for any aggregation
- **Usable**: bear prediction features F14 (KOSPI realized vol), F31/F32 (defensive rotation)
- **본 cycle 사용**:
  ```r
  source("02_Infrastructure/factor_db/factor_db_connector.R")
  rd <- load_rawdata(use_cache=TRUE)
  # filter Date <= sig_date - 1
  rd_pit <- rd[Date <= sig_date - 1]
  ```

### S04 — FRED macro
- **Publish lag**: FRED data has **publish-date vs reference-date** distinction
  - Daily series (DGS10/VIX/T10Y2Y): publish T+1 (next business day EOD)
  - Monthly series (UNRATE/CPI/INDPRO): publish T+1m+~5d (BLS/BEA release calendar)
  - Weekly series (Init_Claims): publish T+5d (Thursday for prior week)
- **C11**: 데이터 시간축 검증 mandate. FRED 표시 Date = reference Date (not publish Date).
- **본 cycle handling**:
  ```r
  # Daily: lag 1 business day (t-1 read)
  fred_daily_pit <- fred_data[Date <= sig_date - 1]
  # Monthly: lag at least 1 month + 5 days (use prior month data, never current month until release date)
  fred_monthly_pit <- fred_monthly[Date <= sig_date %m-% months(1) - days(5)]
  ```
- **C5**: regime overlay t-1 → macro features feeding regime model must be t-1

### S05 — ECOS bond rates
- **Publish lag**: ECOS publishes T+1 ~ T+5 (한국은행 release calendar varies)
- **본 cycle handling**:
  ```r
  ecos_pit <- ecos_data[Date <= sig_date - 5]  # conservative t-5 to cover any delay
  ```
- Note: 2026-03-17 = last cached. 2026-04~05 fetch needed for current month sig_dates → 본 cycle 정합 (only design phase, Forge cycle fetch).

### S06 — ECOS macro extended (PMI/IP)
- KR PMI: HSBC/Markit publish T+1 (1st business day of next month)
- KR CPI: 통계청 publish ~5th of next month
- KR IP: 통계청 publish ~end of next month
- **본 cycle handling**: lag at least 1 month + 5 days. Some features may use lag of 2 months for conservative buffer.

### S07 — investor_wide (foreign flow)
- **Publish lag**: KRX publishes T+1 (settlement-based)
- **본 cycle handling**:
  ```r
  inv_pit <- investor_foreign[Date <= sig_date - 2]  # k=2 (publish T+1 + read T+2 buffer)
  ```

### S08 — SEIBro ETF complex
- **Publish lag**: SEFRS Phase A protocol k≥2 strict
- **본 cycle handling**: inherit WT-D20260518_001 protocol (`stage_artifacts/WT_D20260518_001/pit_audit_protocol.md`)

### S09 — VKOSPI
- **Publish lag**: KRX EOD T+1 (next business day publish)
- **본 cycle handling**: lag 1 business day strict (t-1 close)
- **Direct fetch path** (3 fallback):
  - **Path A (preferred)**: KRX 정보데이터시스템 API (https://data.krx.co.kr/) — VKOSPI historical CSV download
  - **Path B**: pykrx Python library `pykrx.stock.get_index_ohlcv_by_date("VKOSPI", ...)` (auto)
  - **Path C (manual fallback)**: KRX 정보데이터시스템 web manual CSV export
- **Forge cycle execution**:
  ```bash
  # Path B (Python automated)
  python -c "
  from pykrx import stock
  vkospi = stock.get_index_ohlcv_by_date('20030101', '20260518', '1009')  # VKOSPI ticker
  vkospi.to_parquet('.cache/vkospi_daily.parquet')
  "
  ```
- **Fallback if all fails**: F11~F14 (VIX/FRED + F14 KOSPI realized vol KR-side) proxy. VKOSPI optional.

### S10/S11/S12 — Composite & regime
- macro_regime.parquet pre-computed (t-1 inputs strict)
- MSM regime engine: rolling expanding, no look-ahead
- M4 BOCPD inherit Session 80 (already PIT-validated for STR_1715)

---

## 3. Direct collection autonomy execution plan

본 cycle scope **alpha-research design phase only** — Forge cycle 시 직접 collection 수행.

### Forge cycle data collection tasks (Stage 1 mandate)

| Task | Path | Estimated time | Owner |
|---|---|---|---|
| 1. ECOS refresh 2026-04~05 | `02_Infrastructure/data/data_collector_ecos.R` | 5min | Forge agent |
| 2. FRED refresh 2026-05-15~present | `02_Infrastructure/data/data_collector_fred.R` | 5min | Forge agent |
| 3. VKOSPI initial fetch + cache | `02_Infrastructure/data/krx_data_collector.R` + pykrx | 15min | Forge agent |
| 4. SEFRS Phase A 데이터 (252670/114800/122630) | inherit WT-D20260518_001 | 20min | Forge agent |
| 5. investor_wide refresh 2026-05 | `02_Infrastructure/data/krx_data_collector.R` | 5min | Forge agent |

**Total Stage 1 data collection**: ~50min.

**Fallback paths declared**:
- VKOSPI 실패 시 → VIX (FRED) + F14 (KOSPI realized vol) proxy retain
- ECOS 실패 시 → 한국은행 API direct curl + manual parse
- SEFRS 실패 시 → SEFRS Phase A 12 sub-features omit, base feature pool retain (29 features)

---

## 4. Coverage timeline + Missing rate per source

### S04 FRED macro 22 series

| Series | First obs | Coverage % (in 2000-01~2026-05) | Lag |
|---|---|---|---|
| DGS10 (10y treasury) | 2000-01 | 99.5% | t-1 |
| DGS2 (2y treasury) | 2000-01 | 99.5% | t-1 |
| VIX (CBOE volatility) | 2000-01 | 99.5% | t-1 |
| T10Y2Y (spread) | 2000-01 | 99.5% | t-1 |
| INDPRO (IP) | 2000-01 monthly | 100% | t-1m+5d |
| UNRATE | 2000-01 monthly | 100% | t-1m+5d |
| ICSA (claims) | 2000-01 weekly | 100% | t-5d |
| UMCSENT (sentiment) | 2000-01 monthly | 100% | t-1m+5d |
| DEXKOUS (KRW/USD) | 2000-01 daily | 99% | t-1 |
| HY/BBB spreads (BAMLH0A0HYM2 etc) | 2001-01+ | 95% | t-1 |
| NFCI / STLFSI4 | 2001-01+ | 95% | t-1 weekly |
| Bank lending std (DRTSCILM) | 2001-01+ quarterly | 100% | t-1Q+30d |
| Housing permits (PERMIT) | 2000-01+ monthly | 100% | t-1m+15d |
| Fed funds rate (FEDFUNDS) | 2000-01+ monthly | 100% | next-day |

### S05 ECOS bond rates 7 series

| Series | First obs | Coverage |
|---|---|---|
| KR_Gov10Y | 2001-01 | 100% |
| KR_Gov3Y | 2001-01 | 100% |
| KR_CorpAA | 2001-01 | 100% |
| KR_CorpBBB | 2001-01 | 100% |
| KR_CD91 | 2001-01 | 100% |
| KR_Call1D | 2001-01 | 100% |
| KR_CPI | 2001-01 monthly | 100% |

### S07 investor_wide

- foreign net buy: 2000-01-04 ~ 2026-04-30, 99% coverage (business days only)
- 4 investor types × ~3500 tickers × 6650 days = 31.5M rows

### S08 SEIBro ETF complex

- 252670 inception: **2016-09-22** (binding constraint)
- 114800 inception: 2010-09
- 122630 inception: 2012-04
- Common period: **2016-09~2026** (~120 monthly / ~2500 daily)
- AUM/shares: monthly cache (Forge Stage 1 fetch)

### S09 VKOSPI (post-fetch projected)

- VKOSPI launch: **2003-04-29** (KRX official start)
- Coverage 2003-04 ~ 2026-05: ~5800 daily
- Missing rate: <1% (continuous KRX index)

---

## 5. Feature × Source mapping

| Feature ID | Required source(s) | Stratum availability |
|---|---|---|
| F01~F05 (yield curve) | S04 (FRED DGS10/DGS2/T10Y2Y) + S05 (ECOS Gov10Y/Gov3Y) | S2+ (2001~) |
| F06~F10 (leading indicators) | S04 (INDPRO/PERMIT/ICSA/UMCSENT) + S05 (CPI) | S2+ |
| F11~F13 (VIX + term structure) | S04 (VIXCLS) | S2+ |
| F14 (KOSPI realized vol) | S03 (rawdata BM_Ret) | **S1+ all strata** ★ |
| F15~F16 (VKOSPI) | S09 direct fetch | S3+ (2003~) |
| F17 (asymmetric cor KOSPI-USD) | S03 + S04 (proxy via VIX/SP500) | S2+ |
| F18~F19 (KRW/USD) | S04 (DEXKOUS) | S2+ |
| F20~F22 (systemic risk proxy) | S04 (NFCI/STLFSI4/DRTSCILM) | S2+ |
| F23~F25 (credit spread) | S04 (HY/BBB) + S05 (KR_CorpAA/BBB) | S2+ |
| F26~F28 (SEFRS ETF flow) | S08 (SEIBro inherit) | S4 only (2016-09+) |
| F29~F30 (foreign flow) | S07 (investor_foreign) | S2+ (2000~) |
| F31~F32 (defensive rotation) | S03 (rawdata Sector_Lv2) | **S1+ all strata** ★ |

---

## 6. Sample expansion validation (도훈 mandate "25x daily" 정합)

**v5 monthly**: 124 sig_dates × ~30 bad months
**v1 monthly**: **437 sig_dates × ~81 bad months** (3.5× sample, 2.7× positive class)

**v1 daily** (alternative): ~9000 daily × bad days
- bad_day defined as: day t where forward 20-day BM_Ret < -3% OR realized vol > 95th pct
- Estimated ~1500~2000 bad days at -3% threshold over 9000 trading days
- 25× sample expansion proxy 정합

**Recommendation**: **monthly aggregation primary** (1M forecast horizon spec 정합) + **daily as auxiliary** (Forge cycle compare). Daily-frequency uplift evidence via G1 5-subgate Recall.

---

## 7. Data integrity checks (PIT audit pre-execution)

본 cycle scope = design phase, but **Forge cycle PIT audit checklist** pre-declare:

| Check | Test |
|---|---|
| C1 full-sample | No statistic using future data — rolling/expanding only |
| C2 same-day circular | All feature uses Date ≤ sig_date - 1 |
| C4 fundamental lag | Q+45d annual May (irrelevant for bear prediction, no fundamental features) |
| C5 overlay t-1 | regime overlay (F03 dummy etc.) uses t-1 strict |
| C9 VT/DD lag | F14 realized vol uses `c(NA, [-n])` shift, no same-day |
| C11 macro time-axis | FRED Date = reference, not publish; explicit lag |
| C13 NEGATE/FLIP | No Z_Score_Aligned manipulation; all features defined natural direction |
| C14 IC Usable_Date | n/a for bear prediction (time-series, no cross-sectional IC) |
| C15 Factor DB load | `load_month_factors()` 경유 |

**Forge cycle audit script** (pre-declare):
```r
source("02_Infrastructure/validation/pit_enforcement.R")
source("02_Infrastructure/validation/lookahead_detector.R")
# Per-feature audit
for (feat in F01:F32) {
  audit <- lookahead_detector(feature_data = ..., sig_dates = sig_dates_full)
  stopifnot(audit$pass == TRUE)
}
```

---

## 8. Audit conclusion

도훈 mandate **"Qvest 인프라 적극 활용 + 직접 수집 protocol"** 정합 PASS:

1. ✅ 12 sources inventory (10 Qvest cached + 1 VKOSPI direct fetch + 1 SEFRS Phase A inherit)
2. ✅ Per-source PIT lag rule 명시 (FRED publish T+1 / ECOS T+1~5 / KRX investor T+2 / SEIBro k≥2)
3. ✅ Coverage timeline + missing rate per source × stratum
4. ✅ Direct collection path A/B/C 명시 (VKOSPI 3-fallback)
5. ✅ Forge cycle data collection ~50min estimated
6. ✅ Feature × Source mapping 32 features
7. ✅ Sample expansion 437 monthly + 9000 daily ≥ 25× v5
8. ✅ PIT audit checklist pre-declared

**Forge cycle 의무 binding**:
- Stage 1: ECOS + FRED refresh + VKOSPI fetch + SEFRS + investor_wide refresh (~50min)
- Stage 2: PIT audit C1~C15 per-feature
- Stage 3: feature engineering 32 features computed
- Stage 4: ML model training (5-model ensemble)

---

## 참조

- 도훈 mandate 2026-05-19 (max-history + 자율성 발휘 + 직접 수집)
- WT-D20260518_001 SEFRS Phase A (S08 inherit)
- L-274 (STR_1715 PG2 F2 official algo F1 268m + F4 forward_weights 4-Layer)
- L-330 (v5 RC scope retire)
- `.claude/rules/factor-db.md` (C13~C15 + load_month_factors 경유)
- `02_Infrastructure/validation/pit_enforcement.R`
- `02_Infrastructure/data/data_collector_fred.R`
- `02_Infrastructure/data/data_collector_ecos.R`
- `02_Infrastructure/data/krx_data_collector.R`
- `02_Infrastructure/regime/regime_engine_daily.R` (MSM)
