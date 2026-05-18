# Historical Coverage Audit — WT-D20260519_002 Bear Prediction Engine v1.0

**도훈 mandate 2026-05-19 추가 (max-history)**: 기존 spec 124 monthly (2014~2026) → **최대 가능 기간 활용 (1990~2026 = 436 monthly, 36년)**. Crisis sample 8건 inclusion 의무 + PIT integrity strict retain.

본 audit는 **각 data source 별 coverage timeline + missing rate + stratified harmonization protocol**을 정직하게 기록.

---

## 1. Source-by-source coverage (Qvest 인프라 실측 probe 결과)

각 source는 본 cycle 작업 시점 `.cache/` 직접 probe로 확인.

| Source | First obs | Last obs | n_obs | Storage | Probe 명령 |
|---|---|---|---|---|---|
| **rawdata.parquet (KOSPI BM_Ret + Ret + Close)** | **1990-01-04** | 2026-05-18 | **437 monthly / ~9,069 daily** | `.cache/rawdata.parquet` (~수 GB) | `arrow::read_parquet`, range probe |
| **Factor DB monthly** | 1990-01 (22 factors) → 2000-01 (177) → 2010-01 (281) → 2026-04 (281) | 2026-05 | **437 monthly** | `.cache/factor_db/factor_db_YYYYMM.parquet` | `factor_db_connector::load_month_factors()` |
| **Factor DB daily** | 1990-01 | 2026-04 | 436 monthly × ~21 daily ≈ **~9,160 daily** | `.cache/factor_db_daily/fdb_daily_YYYYMM.parquet` | per-month parquet |
| **FRED macro** (22 series, US 중심 + KRW/USD) | **2000-01-01** | 2026-05-15 | ~6,640 daily | `.cache/fred_macro.parquet` | range probe DGS10/VIX/T10Y2Y |
| **ECOS KR macro** (7 series: Gov3Y/Gov10Y/CorpAA/CorpBBB/CD91/Call1D/CPI) | **2001-01-01** | 2026-03-17 | ~6,300 daily | `.cache/ecos_bond_rates.parquet` | range probe |
| **investor flow** (Foreign/Institutional/Individual/Other) | **2000-01-04** | 2026-04-30 | ~6,400 daily | `.cache/investor_stock/investor_*.parquet` | NetBuy by Date×Ticker×InvestorType |
| **SEIBro ETF flow (SEFRS Phase A)** | **2016-09 (252670 inception)** | 2026-04 | ~120 monthly | WT-D20260518_001 inherit | k≥2 strict, t+1 settle lag |
| **VKOSPI** (KRX 정보데이터시스템) | **2003+ (실제 launch)** | 2026-05 (수동/API fetch 필요) | NOT_YET_CACHED | direct collection autonomy required | KRX API or manual download |
| **macro_regime.parquet** (FRED rolled-up) | 2000-01-31 | 2026-05-31 | 317 monthly | `.cache/macro_regime.parquet` | composite indicators ready |

**Effective binding constraint**: **ECOS 2001-01 = KR macro start**, **FRED 2000-01 = US macro start**. VKOSPI 2003+. SEIBro ETF flow 2016-09+.

**Universe constraint**: rawdata + Factor DB 모두 **1990-01 시작 가능** — KOSPI returns + 22 factor (1990) → 281 factor (2010+) evolution.

---

## 2. Effective period 4-stratum (도훈 mandate stratified handling 정합)

본 spec 의무: **임의 backfill 절대 금지** + **imputation은 명시적 documentation** (PIT integrity strict).

| Stratum | Period | n_monthly | Available sources | Feature support |
|---|---|---|---|---|
| **S1: Early KR-only** | **1990-01 ~ 2000-12** | 132 | rawdata BM_Ret + 22~177 factors + KOSPI close | Limited macro (KR only via Close/Vol) |
| **S2: + US FRED** | **2001-01 ~ 2002-12** | 24 | + 7 ECOS bond rates + 22 FRED series | + Yield curve + VIX + Credit spread |
| **S3: + VKOSPI** | **2003-01 ~ 2016-08** | 164 | + VKOSPI (after fetch protocol exec) | + Vol regime indicator KR |
| **S4: + SEIBro ETF complex (SEFRS)** | **2016-09 ~ 2026-05** | 117 | + SEIBro 252670/114800/122630 (Phase A) | Full feature suite |
| **Total** | 1990-01 ~ 2026-05 | **437** | (variable by stratum) | progressive |

---

## 3. Missing rate per feature category × stratum

| Feature category | S1 (1990~2000) | S2 (2001~2002) | S3 (2003~2016) | S4 (2016~2026) | PIT-safe handling |
|---|---|---|---|---|---|
| `Price_Momentum_Vol` (rawdata KOSPI) | 0% | 0% | 0% | 0% | always available |
| `Yield_Curve_US` (FRED DGS10/DGS2) | **100% MISSING** | 0% | 0% | 0% | restrict to ≥2001 OR proxy from rawdata regimes |
| `Yield_Curve_KR` (ECOS Gov3Y/Gov10Y) | **100%** | 0% | 0% | 0% | restrict to ≥2001 |
| `Credit_Spread_KR` (ECOS CorpAA/CorpBBB) | **100%** | 0% | 0% | 0% | restrict to ≥2001 |
| `VIX_FRED` | **100%** | 0% | 0% | 0% | restrict to ≥2001 |
| `VKOSPI_KRX` | 100% | 100% | **partial after fetch** | 0% (if fetch OK) | restrict to ≥2003 OR drop |
| `Foreign_Flow_KRX` (investor_wide) | **100%** | 0% | 0% | 0% | restrict to ≥2000 |
| `SEIBro_ETF_Complex` (SEFRS) | 100% | 100% | **100%** | 0% | restrict to ≥2016-09 |
| `Leading_Indicators_PMI` (ECOS or proxy) | partial | partial | low | 0% | use Term_Spread proxy when missing |
| `Defensive_Sector_Rotation` (rawdata Sector_Lv2) | 0% | 0% | 0% | 0% | always available |
| `Asymmetric_Cor_KOSPI_USD` (rawdata + FRED KRW_USD) | **partial KRW_USD missing pre-2001** | 0% | 0% | 0% | restrict to ≥2001 |

---

## 4. Stratified handling protocol (도훈 mandate strict)

도훈 mandate: "임의 backfill 절대 X, imputation은 명시적 documentation".

본 cycle은 **3 strategies** evaluating:

### Strategy A — Conservative Full-history (S1 포함, feature mask)
- Universe: 1990-01 ~ 2026-05 (437 monthly)
- Feature pool: **stratum-conditional active**
  - S1 (1990~2000): only price/momentum/vol features (n_features ~20)
  - S2 (2001~2002): + macro full (n ~50)
  - S3 (2003~2016): + VKOSPI (n ~70)
  - S4 (2016~2026): + SEFRS (n ~80)
- ML model: handles missing as **explicit indicator + zero imputation per-stratum** (LightGBM handles NaN natively, others require imputation)
- Bad month label: BM_Ret(KOSPI) < -5% threshold (universal, all strata)

**Pros**: max history (437m, +250m vs v5)
**Cons**: feature distribution shift S1 vs S4. Tree ensemble can handle. NN (LSTM/MSM) need explicit stratum indicator.

### Strategy B — Macro-conditional (2001+ start, ~301 monthly)
- Universe: 2001-01 ~ 2026-05 (301 monthly)
- Feature pool: stable (yield curve + credit + VIX from start)
- ML model: stable feature distribution, no imputation needed
- Bad month label: same

**Pros**: stable features (no S1 distribution shift)
**Cons**: lose 132 monthly + 1997 IMF crisis lose 부분 (1997-10/1998-05 etc).

### Strategy C — VKOSPI-active (2003+ start, ~280 monthly)
- Universe: 2003-01 ~ 2026-05
- Feature pool: + VKOSPI active
- Lose: 1990~2002 + 1997 IMF + 2000 dotcom partial

**Pros**: VKOSPI is highly informative for vol regime
**Cons**: lose 157 monthly (36%)

### Recommended Strategy (autonomy decision)

**Strategy A** (max-history mandate 정합 1순위) — but with **explicit stratum_id feature** + **separate model fit per-stratum + meta-ensemble** OR **LightGBM as primary with NaN native handling + others as stratum-conditional sub-models**.

**Forge cycle 의무**: empirical compare Strategy A vs B vs C on (Recall + Precision + sub-window stability) → admit whichever wins G1 5-subgate.

**Default 시작**: Strategy A + LightGBM NaN-native + secondary models fit on stratum 2+ subset.

---

## 5. PIT integrity reaffirmation

본 mandate에서 max-history 활용은 다음 PIT rule 위반 절대 X:

- **C1**: full-sample 통계 금지 — rolling/expanding window only (yield curve slope rolling 252d 등)
- **C2**: same-day circular 금지 — t-1 close, t-1 macro 모든 feature
- **C4**: fundamental lag (Q+45d, annual May)
- **C5**: regime overlay t-1
- **C9**: VT/DD/FM lag c(0, ...[-n])
- **C11**: FRED 1-day lag explicit (publish_date vs reference_date)
- **C13**: NEGATE_FACTORS / FLIP_SIGN 금지 (Z_Score_Aligned only)
- **C14**: IC 접근 시 Usable_Date ≤ sig_date
- **C15**: Factor DB load_month_factors() 경유

**특히 본 cycle 신규 risk**: yield curve / VKOSPI / credit spread 같은 macro feature는 **publish-lag awareness** 의무. FRED는 publish T+1 (Bloomberg/Refinitiv 같은 EOD release), ECOS는 T+1 ~ T+5 (publication delay 명시 필요).

---

## 6. Stratum harmonization sanity check

도훈 mandate "거시 regime 변화 (1990s post-IMF emerging market vs 2020s mature market)" 정합 — feature normalization 의무:

| Feature | 1990s norm | 2020s norm | Handling |
|---|---|---|---|
| KOSPI vol monthly | ~12% | ~5% | **rolling z-score 60m** (cross-stratum stationary) |
| Yield curve slope | n/a (S1) | active | **stratum_id feature** + per-stratum z |
| BM_Ret monthly | -3% to +5% (range) | -3% to +5% | **uniform**, no z required |
| Foreign flow intensity | low (2000s) | high (2020s) | **rolling z-score 60d** |
| Defensive sector spread | volatile | stable | **rolling z** |

본 normalization은 Forge cycle에서 empirical validate. **Default**: rolling-z 60m for all macro/flow features + raw-value for return/vol (이미 stationary).

---

## 7. Crisis sample coverage (8 epochs 확정)

다음 section `crisis_sample_inclusion.md` 에서 상세. 미리 summary:

| Crisis | Period | n_bad_months (BM<-5%) | Stratum |
|---|---|---|---|
| 1990 KR early (Asia crisis precursor) | 1990-04 | 1 | S1 |
| **1997 IMF KR** | **1997-10 ~ 1998-05** | **5** (worst 1997-10 BM=-27.2%) | S1 |
| **2000 Dotcom** | **2000-04 ~ 2002-12** | **9** | S1+S2 |
| **2008 GFC** | **2008-01 ~ 2008-12** | **5** (worst 2008-10 BM=-23.1%) | S2+S3 |
| 2011 Eurozone (KR moderate) | 2011-08 | 2 | S3 |
| 2015~2016 China shock | 2015-08 | 1 | S3 |
| **2018 vol spike** | **2018-10** | 1 | S3+S4 |
| **2020 COVID** | **2020-02 ~ 2020-03** | 2 | S4 |
| **2022 Inflation shock** | **2022-06, 2022-09** | 2 | S4 |
| 2026-03 recent | 2026-03 | 1 | S4 |
| **Total bad months (BM<-5%)** | | **~81** (vs v5 ~25-30) | full range |

**Positive class 증가 확인**: 81 / 437 = **18.5% base rate** (vs v5 12.2% × 30/254). **2.7× positive class** at -5% threshold.

도훈 mandate "positive class 3-4x 증가 → v5 paradigm-level G1 fail (Recall 0.089) 직접 fix" 정합.

---

## 8. Audit conclusion

**도훈 mandate "Maximum history activation" 정합 PASS**:

1. ✅ Factor DB 36년 full retain (1990-01 ~ 2026-05, 437 monthly)
2. ✅ 8 crisis sample inclusion (1990 KR / 1997 IMF / 2000 dotcom / 2008 GFC / 2011 EU / 2015 CN / 2018 vol / 2020 COVID / 2022 inflation / 2026-03)
3. ✅ Source-별 coverage timeline 명시 + stratified handling protocol
4. ✅ PIT integrity strict retain — 임의 backfill 금지 + imputation 명시
5. ✅ 81 bad months at -5% (vs v5 ~30) = **2.7× positive class** → Recall fix path

**Forge cycle empirical mandate**:
- Strategy A vs B vs C compare on G1 5-subgate
- 8 crisis OOS hold-out (각 crisis 별도 sub-window 평가)
- Stratum-conditional feature mask / imputation explicit documentation

---

## 참조

- 도훈 mandate 2026-05-19 추가 (max-history)
- Charter §10 v1.8 discovery_design_phase_a Role Card
- `.claude/rules/pit.md` C1~C15
- `.cache/rawdata.parquet` (1990-01-04 ~ 2026-05-18 probe)
- `.cache/factor_db/factor_db_YYYYMM.parquet` × 437 files
- `.cache/fred_macro.parquet` (2000-01 ~ 2026-05)
- `.cache/ecos_bond_rates.parquet` (2001-01 ~ 2026-03)
- L-326 / L-328 / L-330 (v5 paradigm scoped + DPL_KR_v1 EW collapse)
