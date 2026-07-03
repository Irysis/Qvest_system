# DART vs QuantiWise — Technical Specifications & Integration Guide

**Last Updated:** 2026-04-01 (Session 51)

---

## Part A: Data Structure & Access

### DART Raw API → Parquet Pipeline

**File:** `02_Infrastructure/data_collector_dart.R`

#### Step 1: Corp Code Mapping
```r
dart_update_corpcode()
# Output: .cache/dart/corpcode_map.parquet
# Contains: corp_code (KRX ID), Ticker (A + 6-digit code), corp_name
```

#### Step 2: Fetch Annual Financials
```r
dart_fetch_all(years = 2015:2025, reprt_code = "11011", fs_div = "CFS")
# reprt_code: "11011" = Annual (사업보고서)
# fs_div: "CFS" = Consolidated / "OFS" = Individual
# Output: .cache/dart/dart_raw_financials.parquet (raw JSON flattened)
# Raw columns: account_nm (한글), thstrm_amount, sj_div (BS/IS/CF/CIS)
```

#### Step 3: Parse to Clean Accounts
```r
dart_parse_financials(raw_dt)
# Applies account_map (한글 → English)
# Handles company-year deduplication
# Output: 36 standardized accounts (Revenue, COGS, ...)
```

#### Step 4: Compute Factors (172 total)
```r
dart_compute_factors()
# Derives: EBITDA, FCF, WorkingCapital, TotalDebt, NetDebt
# Computes: All profitability, efficiency, leverage, quality ratios
# Winsorizes: P1/P99 by year
# Date mapping: Factor_Date = Year+1 Mar 31 (PIT lag)
# Output: .cache/fundamental_dart.parquet (6,444 rows × 178 cols)
```

---

### XLSX → Parquet Pipeline

**File:** `02_Infrastructure/parse_fundamental_xlsx.R`

#### Step 1: Read XLSX Sheets
```r
parse_fundamental_xlsx(xlsx_path = "03_Universe/Fundamental.xlsx")
# Excel structure:
#   Row 10: Period headers (YYYYMM format)
#   Row 13: Column labels (duplicate Item names)
#   Row 14+: Data rows (Ticker A + 6 digits)
# Sheets: Each sheet = 1 Item (e.g., "매출액" → "Revenue")
```

#### Step 2: Long-Format Conversion + TTM
```r
compute_ttm(dt)
# TTM logic:
#   P/L, CF: frollsum(Value, n=4, align="right") by Ticker, Item
#   B/S: Use latest quarter value (point-in-time)
#   Date: Period_Date + 45 days → Factor_Date
# Output: .cache/fundamental_xlsx_ttm.parquet
```

#### Step 3: Share Counts Extraction
```r
# ISSD (발행주식수) → .cache/shares_issued.parquet
# SBB (기중취득자기주식) → .cache/stock_buyback.parquet
# Used for diluted metrics, share buyback signals
```

---

### Merge & Conflict Resolution

**File:** `02_Infrastructure/parse_fundamental_xlsx.R::merge_fundamental_all()`

```r
merge_fundamental_all()
# Sources: fundamental_dart.parquet + fundamental_xlsx.parquet
# Wide → Long conversion for DART (Ticker, Year, Factor_Date, {Item}→{Value})
# Filter common items (accounting overlap)
# Merge: XLSX + DART with source tracking

# Conflict resolution (same Ticker + Period + Item):
# Priority: DART > XLSX (DART is source-of-truth)
# setorder: by Source (DART="D", XLSX="X") → rank==1 keeps DART

# Output: .cache/fundamental_merged.parquet
# Cols: Ticker, Period, Period_Date, Factor_Date, Item, Value, Source
# 5,425,870 rows
```

---

## Part B: Account Mapping Reference

### DART Account Names (한글 → English, cleaned account_map)

#### Income Statement (IS/CIS)
| English | Korean | Variants |
|---------|--------|----------|
| Revenue | 매출액 | 수익(매출액), 영업수익 |
| COGS | 매출원가 | |
| GrossProfit | 매출총이익 | Derived: Revenue - COGS |
| SGAExpense | 판매비와관리비 | 판매비와 관리비 |
| OperatingProfit | 영업이익 | 영업이익(손실) |
| PretaxIncome | 법인세비용차감전순이익 | 법인세차감전 순이익, etc. |
| TaxExpense | 법인세비용 | |
| NetIncome | 당기순이익 | 연결당기순이익, 지배기업소유주지분순이익 |
| InterestExp | 이자비용 | 금융비용 |
| InterestIncome | 이자수익 | 금융수익 |
| DepAmort | 감가상각비 | 감가상각비와상각비, 감가상각비 및 상각비 |
| RandD | 경상연구개발비 | 연구개발비, 연구 및 개발비 |

#### Balance Sheet (BS)
| English | Korean | Variants |
|---------|--------|----------|
| TotalAssets | 자산총계 | |
| CurrentAssets | 유동자산 | |
| NonCurrentAssets | 비유동자산 | |
| CashAndEquiv | 현금및현금성자산 | 현금 및 현금성자산 |
| Inventory | 재고자산 | |
| AccountsRecv | 매출채권 | 매출채권 및 기타유동채권, 매출채권및기타유동채권 |
| TangibleAssets | 유형자산 | |
| IntangibleAssets | 무형자산 | |
| TotalLiab | 부채총계 | |
| CurrentLiab | 유동부채 | |
| NonCurrentLiab | 비유동부채 | |
| ShortTermBorr | 단기차입금 | |
| LongTermBorr | 장기차입금 | 사채 |
| AccountsPay | 매입채무 | 매입채무 및 기타유동채무, 매입채무및기타유동채무 |
| TotalEquity | 자본총계 | |
| CapitalStock | 자본금 | |
| RetainedEarnings | 이익잉여금 | |

#### Cash Flow (CF)
| English | Korean | Variants |
|---------|--------|----------|
| OperatingCF | 영업활동현금흐름 | 영업활동 현금흐름, 영업활동으로인한현금흐름, 영업활동으로 인한 현금흐름 |
| InvestCF | 투자활동현금흐름 | 투자활동 현금흐름, 투자활동으로인한현금흐름 |
| FinanceCF | 재무활동현금흐름 | 재무활동 현금흐름, 재무활동으로인한현금흐름 |
| Dividends | 배당금지급 | 배당금 지급, 배당금 |

---

## Part C: XLSX Item List (KR_EN_MAP, 34 items)

Complete mapping from Fundamental.xlsx sheet names to English factor names:

```r
KR_EN_MAP <- c(
  "매출액"           = "Revenue",
  "매출원가"         = "COGS",
  "매출총이익"       = "GrossProfit",
  "판관비"           = "SGAExpense",
  "영업이익"         = "OperatingProfit",
  "세전이익"         = "PretaxIncome",
  "법인세비용"       = "TaxExpense",
  "이자비용"         = "InterestExp",
  "순이자비용"       = "NetInterestExp",
  "총순이자비용"     = "TotalNetInterestExp",
  "이자수익"         = "InterestIncome",
  "감가상각비"       = "DepAmort",
  "연구개발비"       = "RandD",
  "경상연구개발비"   = "OrdRandD",
  "자산총계"         = "TotalAssets",
  "유동자산"         = "CurrentAssets",
  "비유동자산"       = "NonCurrentAssets",
  "현금및현금성자산" = "CashAndEquiv",
  "재고자산"         = "Inventory",
  "매출채권"         = "AccountsRecv",
  "장기매출채권"     = "LongTermRecv",
  "유형자산"         = "TangibleAssets",
  "무형자산"         = "IntangibleAssets",
  "부채총계"         = "TotalLiab",
  "유동부채"         = "CurrentLiab",
  "비유동부채"       = "NonCurrentLiab",
  "단기차입금"       = "ShortTermBorr",
  "장기차입금"       = "LongTermBorr",
  "매입채무"         = "AccountsPay",
  "장기매입채무"     = "LongTermPay",
  "자본총계"         = "TotalEquity",
  "자본금"           = "CapitalStock",
  "이익잉여금"       = "RetainedEarnings",
  "영업활동현금흐름" = "OperatingCF",
  "투자활동현금흐름" = "InvestCF",
  "재무활동현금흐름" = "FinanceCF",
  "배당금지급액"     = "Dividends",
  "FCF1"             = "FCF1",
  "FCF2"             = "FCF2",
  "ISSD"             = "ISSD",
  "SBB"              = "SBB"
)
```

**Note:** XLSX has ~34 raw items (sheet names). When parsed, produces 181 unique items (after merging with DART-derived factors).

---

## Part D: Derived Items Not in Raw Data

### Generated in dart_compute_factors()

#### Flow Aggregation (for averaging)
- AvgAssets = (TotalAssets + Lag(TotalAssets)) / 2
- AvgEquity = (TotalEquity + Lag(TotalEquity)) / 2
- AvgInventory = (Inventory + Lag(Inventory)) / 2
- AvgRecv = (AccountsRecv + Lag(AccountsRecv)) / 2
- AvgPay = (AccountsPay + Lag(AccountsPay)) / 2

#### Derived Accounts (core)
- **GrossProfit** = Revenue - COGS (if missing from raw)
- **EBITDA** = OperatingProfit + DepAmort
- **EBIT** = OperatingProfit (alias)
- **WorkingCapital** = CurrentAssets - CurrentLiab
- **TotalDebt** = ShortTermBorr + LongTermBorr
- **NetDebt** = TotalDebt - CashAndEquiv
- **FCF** = OperatingCF + InvestCF
- **NetInterest** = InterestIncome - InterestExp
- **NOPAT** = OperatingProfit × (1 - TaxExpense / PretaxIncome)

#### Winsorizing (P1/P99 by year)
All ratio columns winsorized to remove extreme outliers per bsns_year.

---

## Part E: Coverage & Lag Specifications

### Data Availability by Source

| Source | Start Year | Granularity | Latest | Coverage |
|--------|-----------|-------------|--------|----------|
| DART Annual | 2015 | Annual | 2025 | ~180 companies |
| DART Quarterly | 2015 | 4Q + 1Q/2Q/3Q | 2025 Q4 | ~180 companies |
| XLSX | 1998 | Quarterly | 2026 Q1 | ~1,500 tickers |
| Merged | 1998 | Mixed | 2026 Q1 | Both sources |

### Lag Compliance (PIT Enforcement, C4)

**DART:**
- Period: Calendar year (bsns_year)
- Announcement: Annual report published ~Mar 31 next year
- Factor_Date: Year + 1 → Mar 31 (41+ days post-12/31)
- ✅ Complies with C4 (45-day lag assumed, actual ~90 days)

**XLSX:**
- Period: YYYYMM (quarter-end: 03, 06, 09, 12)
- Reported: ~45 days post-period-end
- Factor_Date: Period_Date + 45 days (explicit)
- ✅ Complies with C4

**Quarterly (New):**
- 1Q: 3/31 + 45d → 5/15
- 2Q: 6/30 + 45d → 8/15
- 3Q: 9/30 + 45d → 11/15
- 4Q: 12/31 + 45d → 3/31 (next year)
- ✅ Complies with C4

---

## Part F: Factor Registry Integration

### Current Structure (factor_registry.json)

Expected format for fundamental factors:
```json
{
  "factor_id": "F001",
  "name": "ROE",
  "module": "Fundamental",
  "family": "Profitability",
  "raw_items": ["NetIncome", "TotalEquity"],
  "calculation": "NetIncome / AvgEquity",
  "lookback_months": 12,
  "coverage_threshold_pct": 50,
  "source_priority": ["DART", "XLSX"],
  "data_lag_days": 90,
  "yoy_change": true
}
```

### Recommended for New Factors

When adding a new fundamental factor to Factor DB:

1. **Query raw_items from merged DB:**
   ```r
   required_items <- c("NetIncome", "OperatingCF", "TotalAssets")
   coverage <- merged[Item %in% required_items, 
                      .(coverage_pct = mean(!is.na(Value))), 
                      by = Item]
   ```

2. **Check historical availability:**
   ```r
   merged[Item == "NetIncome", 
          .(min_year = min(year(Period_Date)), 
            max_year = max(year(Period_Date)))]
   ```

3. **Compute coverage by year:**
   ```r
   factor_dt[, coverage_by_year := mean(!is.na(Factor)),
             by = bsns_year]
   ```

4. **Register in factor_registry.json** with:
   - ✅ raw_items (exact names from merged DB)
   - ✅ source_priority (DART/XLSX)
   - ✅ coverage_threshold (e.g., 50%)
   - ✅ data_lag_days (90+ for fundamentals)

---

## Part G: Common Integration Patterns

### Pattern 1: Load Fundamental Data with Latest Coverage

```r
# Load all available fundamental data
fund <- as.data.table(read_parquet(".cache/fundamental_merged.parquet"))

# Filter to required items
items_needed <- c("Revenue", "OperatingCF", "TotalAssets", "NetIncome")
fund_subset <- fund[Item %in% items_needed]

# Pivot wide (Ticker, Factor_Date, Item → Ticker, Factor_Date, {Item})
fund_wide <- dcast(fund_subset, 
                    Ticker + Factor_Date ~ Item, 
                    value.var = "Value")

# Check coverage
coverage <- fund_wide[, lapply(.SD, function(x) mean(!is.na(x))), 
                       .SDcols = items_needed]
```

### Pattern 2: Use DART for Annual, XLSX for Quarterly

```r
# Annual signals (strong data quality)
annual <- as.data.table(read_parquet(".cache/fundamental_dart.parquet"))
annual[, signal := ROE / shift(ROE, 1) - 1, by = Ticker]

# Quarterly signals (more frequent updates)
qtr <- as.data.table(read_parquet(".cache/fundamental_xlsx_ttm.parquet"))
qtr_wide <- dcast(qtr, Ticker + Factor_Date ~ Item, value.var = "TTM_Value")
qtr_wide[, signal := ROE / shift(ROE, 4) - 1, by = Ticker]  # 4 quarters = 1 year lag
```

### Pattern 3: Share Dilution Check

```r
# Get share counts from XLSX
shares <- as.data.table(read_parquet(".cache/shares_issued.parquet"))
buyback <- as.data.table(read_parquet(".cache/stock_buyback.parquet"))

# Compute net dilution
shares_net <- merge(shares[, .(Ticker, Factor_Date, 
                                ISSD = Value)],
                    buyback[, .(Ticker, Factor_Date, 
                                SBB = Value)],
                    by = c("Ticker", "Factor_Date"), all = TRUE)
shares_net[, net_dilution := (ISSD - shift(ISSD) - SBB) / shift(ISSD),
           by = Ticker]
```

### Pattern 4: Impute Missing with Peer Average

```r
# For factors with <50% coverage, impute with sector median
fund_wide[, InventoryTurnover_filled := 
          fifelse(is.na(InventoryTurnover),
                  median(InventoryTurnover, na.rm = TRUE),  # overall median
                  InventoryTurnover)]
```

---

## Part H: Troubleshooting & QA

### Issue: Missing data for a required item

**Diagnosis:**
```r
merged[Item == "LongTermRecv", .(source_count = .N), by = Source]
# If output shows only XLSX (no DART), item is XLSX-only
```

**Solution:**
- Use XLSX data exclusively
- Check if DART alternative exists (e.g., "AccountsRecv" includes long-term)
- Or use estimation method (e.g., AR growth rates)

### Issue: Date mismatch (Factor_Date vs Usable_Date)

**Compliance check:**
```r
# For IC calculation (C14 rule):
ic_dt[, valid := Usable_Date <= sig_date]
# Ensure all IC values have valid==TRUE
```

**Solution:**
- Use Factor_Date from parquets (already lag-compliant)
- NEVER use Period_Date directly (too early)

### Issue: TTM vs Annual comparison

**When to use TTM:**
```r
# For continuous signal (monthly rebalance)
qtr_ttm[, signal := ROE_ttm / shift(ROE_ttm, 4)]  # 4 qtrs ago = YoY

# For annual snapshot
annual[, signal := ROE / shift(ROE)]  # 1 year ago
```

### Coverage thresholds by factor

| Factor Type | Minimum Coverage | Rationale |
|------------|------------------|-----------|
| Profitability (ROE, ROA, GPA) | 60% | Core requirement |
| Efficiency (Turnover, CCC) | 50% | Mixed data quality |
| Quality (Piotroski, Accrual) | 50% | Signal strength OK at 50% |
| Growth (YoY changes) | 40% | Growth proxies less critical |
| Leverage (DR, ICR) | 60% | Risk factor - high bar |

---

## Part I: Performance Notes

### Data Load Times (Session startup)
- `read_parquet(fundamental_merged.parquet)` → 5.4M rows: **~2-3 sec** (4GB RAM)
- `read_parquet(fundamental_dart.parquet)` → 6.4K rows × 178 cols: **<0.5 sec**
- `read_parquet(fundamental_xlsx.parquet)` → dcast to wide: **~5-10 sec**

### Memory Usage
- fundamental_merged in memory: ~400-500 MB (long-format)
- Dcast to wide (all tickers, all dates): ~1-2 GB
- Suggested workflow: **Filter first, dcast second**

### Query Optimization
```r
# SLOW: Load all, then filter
fund <- read_parquet("...")
fund_filtered <- fund[Item %in% needs]

# FAST: Use parquet filters (if supported)
fund <- read_parquet("...", 
                      filters = list(Item = needs))
```

---

## Part J: Checklist for S1 Factor Implementation

- [ ] Define required raw accounting items
- [ ] Verify availability in merged DB: `merged[Item %in% {items}, unique(Source)]`
- [ ] Check coverage by year: `fund[Item==X, .N, by=bsns_year]`
- [ ] Design TTM conversion (if quarterly): flow vs stock items
- [ ] Set Factor_Date correctly: DART=Year+1/3/31, XLSX=Period+45d
- [ ] Compute signal with forward-looking checks
- [ ] Validate Usable_Date <= sig_date (C14 compliance)
- [ ] Register factor_id, raw_items, data_lag_days in registry
- [ ] Run coverage report: `mean(!is.na(factor_values)) >= threshold`
- [ ] Backtest 2005~2024 historical (XLSX) or 2015~2024 (DART)
- [ ] S1 submission

---

**End of Technical Specifications**
