## STR_1652: Dynamic Factor Allocation v3
## MRS 국면별 4팩터(C19/Q07/Q03/D29) 동적 가중치 전환
## C13: Z_Score_Aligned via align_factor_direction(). 수동 반전 금지.
## C15: Arrow Dataset open_dataset() bulk load — 루프 외부 1회 로드.
## C2 : MRS t-1 lag (build_daily_regime 내부 shift(1) 처리됨)
## C10: LIQ_20d frollmean 20d + t-1 shift, 당일 거래량 직접 사용 금지

cat("[factor_engine] STR_1652: C19+Q07+Q03+D29 Dynamic Regime-Weighted Allocation\n")

# connector는 run_all.R에서 이미 source됨 (align_factor_direction, .load_registry 제공)

# ── 대상 팩터 ───────────────────────────────────────────────────────────────
NEEDED_FACTORS <- c(
  "C19_Composite_Earnings",
  "Q07_Earnings_Stability",
  "Q03_ROA",
  "D29_Accounting_Beta",
  "C08_Coverage"
)
ALPHA_FACTORS <- NEEDED_FACTORS[1:4]

# ── 국면 → 가중치 (t-1 MRS 기준) ─────────────────────────────────────────
.regime_weight_table <- data.table(
  regime = c("Normal", "Caution", "Crisis"),
  w_C19  = c(1.00,     0.60,      0.30),
  w_Q07  = c(0.00,     0.25,      0.30),
  w_Q03  = c(0.00,     0.15,      0.20),
  w_D29  = c(0.00,     0.00,      0.20)
)

get_regime_label <- function(mrs) {
  dplyr::case_when(
    is.na(mrs) | mrs < 20 ~ "Normal",
    mrs < 50               ~ "Caution",
    TRUE                   ~ "Crisis"
  )
}

# ── OPT-1: Arrow Dataset bulk load (루프 외부 1회, parquet 파일만 명시 지정) ──
# factor_registry.json 등 비-parquet 파일 제외를 위해 파일 목록 명시 전달
fdb_parquet_files <- list.files(
  file.path(CACHE_DIR, "factor_db"),
  pattern   = "^factor_db_\\d{6}\\.parquet$",
  full.names = TRUE
)
cat(sprintf("  Factor DB: %d parquet files\n", length(fdb_parquet_files)))
ds      <- open_dataset(fdb_parquet_files, format = "parquet")
FDB_RAW <- ds |>
  dplyr::filter(Factor_Name %in% NEEDED_FACTORS) |>
  dplyr::collect() |>
  as.data.table()
rm(ds, fdb_parquet_files)
cat(sprintf("  Loaded: %s rows, %d factors\n",
            format(nrow(FDB_RAW), big.mark = ","),
            uniqueN(FDB_RAW$Factor_Name)))

# ── C13: IC 방향 자동 정렬 ────────────────────────────────────────────────
registry <- .load_registry()
FDB_ALL  <- align_factor_direction(FDB_RAW, registry)
FDB_ALL[, Date := as.Date(Date)]
setkey(FDB_ALL, Date, Ticker, Factor_Name)
rm(FDB_RAW); gc(verbose = FALSE)

# ── 신호일 추출 ──────────────────────────────────────────────────────────
setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM_tmp := format(Date, "%Y-%m")]
sig_dates_all <- RAWDATA[, .(sig_date = max(Date)), by = YM_tmp][, sort(sig_date)]
sig_dates_all <- sig_dates_all[sig_dates_all >= SIGNAL_START_DATE]
cat(sprintf("  Signal dates: %d (%s ~ %s)\n",
            length(sig_dates_all), min(sig_dates_all), max(sig_dates_all)))

# ── LIQ_20d 계산 (t-1 lag, C10) ──────────────────────────────────────────
# TradingValue = Close * Vol, frollmean 20d, shift(1) 적용
RAWDATA[, TradVal_tmp := Close * Vol]
RAWDATA[, liq20_raw   := frollmean(TradVal_tmp, n = 20L, align = "right", na.rm = TRUE),
        by = Ticker]
RAWDATA[, LIQ_20d     := shift(liq20_raw, n = 1L, type = "lag"), by = Ticker]
RAWDATA[, c("TradVal_tmp", "liq20_raw") := NULL]

# ── MAX21d 계산 (t-1 lag) ────────────────────────────────────────────────
RAWDATA[, abs_ret_tmp := abs(Ret)]
RAWDATA[, mx21_raw := {
  ra <- abs_ret_tmp
  nn <- length(ra)
  if (nn < 21L) cummax(fifelse(is.na(ra), -Inf, ra))
  else frollapply(ra, N = 21L, FUN = max, fill = NA, align = "right")
}, by = Ticker]
RAWDATA[, MAX21d := shift(mx21_raw, n = 1L, type = "lag"), by = Ticker]
RAWDATA[, c("abs_ret_tmp", "mx21_raw") := NULL]

# 신호일 스냅샷 추출
SIG_SNAP <- RAWDATA[Date %in% sig_dates_all & !is.na(Close),
                     .(Date, Ticker, LIQ_20d, MAX21d)]
setkey(SIG_SNAP, Date, Ticker)
RAWDATA[, c("LIQ_20d", "MAX21d", "YM_tmp") := NULL]
setkey(RAWDATA, Date, Ticker)
gc(verbose = FALSE)

# ── MRS 월말 스냅샷 (REGIME_DT는 run_all.R에서 로드, MRS 이미 t-1 lag) ──
mrs_snap <- REGIME_DT[Date %in% sig_dates_all, .(Date, MRS)]
mrs_snap[, Regime := get_regime_label(MRS)]
mrs_snap <- merge(mrs_snap, .regime_weight_table, by.x = "Regime", by.y = "regime", all.x = TRUE)
setkey(mrs_snap, Date)
cat(sprintf("  MRS snap: %d dates | Normal=%d Caution=%d Crisis=%d\n",
            nrow(mrs_snap),
            sum(mrs_snap$Regime == "Normal",  na.rm = TRUE),
            sum(mrs_snap$Regime == "Caution", na.rm = TRUE),
            sum(mrs_snap$Regime == "Crisis",  na.rm = TRUE)))

# ── 월별 신호 생성 (lapply → rbindlist, for 루프 없음) ───────────────────
.build_one_month <- function(sig_d) {
  # 1. SYN_05 유동성 필터 (C10: LIQ_20d t-1)
  snap <- SIG_SNAP[Date == sig_d & !is.na(LIQ_20d) & LIQ_20d >= LIQ_THRESHOLD]
  if (nrow(snap) < 30L) return(NULL)

  # 2. MAX21d 80th percentile 필터
  q80 <- quantile(snap$MAX21d, 0.80, na.rm = TRUE)
  snap <- snap[is.na(MAX21d) | MAX21d <= q80]
  if (nrow(snap) < 30L) return(NULL)

  # 3. t-1 MRS → 가중치 (C2 준수)
  mrs_row <- mrs_snap[Date == sig_d]
  if (nrow(mrs_row) == 0L) return(NULL)
  mrs_val    <- mrs_row$MRS[1L]
  regime_lbl <- mrs_row$Regime[1L]
  wC19 <- mrs_row$w_C19[1L]; wQ07 <- mrs_row$w_Q07[1L]
  wQ03 <- mrs_row$w_Q03[1L]; wD29 <- mrs_row$w_D29[1L]

  # 4. Factor DB 필터 (bulk 메모리, 루프 없음)
  fdt <- FDB_ALL[Date == sig_d & Ticker %in% snap$Ticker]
  if (nrow(fdt) == 0L) return(NULL)

  # 5. C08_Coverage >= 3 필터
  cov_sub <- fdt[Factor_Name == "C08_Coverage" & !is.na(Raw_Value) & Raw_Value >= 3L,
                  .(Ticker)]
  if (nrow(cov_sub) < 20L) return(NULL)

  # 6. Alpha 팩터 wide 피벗 → Final Score (C13: Z_Score_Aligned만)
  alpha_sub <- fdt[Factor_Name %in% ALPHA_FACTORS & Ticker %in% cov_sub$Ticker,
                    .(Ticker, Factor_Name, Z_Score_Aligned)]
  fdt_wide <- dcast(alpha_sub, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  if (!"C19_Composite_Earnings" %in% names(fdt_wide)) return(NULL)
  fdt_wide <- fdt_wide[!is.na(C19_Composite_Earnings)]
  if (nrow(fdt_wide) < 20L) return(NULL)

  # 없는 열 0으로 대체
  needed_cols <- c("C19_Composite_Earnings", "Q07_Earnings_Stability",
                   "Q03_ROA", "D29_Accounting_Beta")
  missing_cols <- setdiff(needed_cols, names(fdt_wide))
  if (length(missing_cols) > 0L) {
    fdt_wide[, (missing_cols) := 0.0]
  }
  fdt_wide[is.na(Q07_Earnings_Stability), Q07_Earnings_Stability := 0.0]
  fdt_wide[is.na(Q03_ROA),                Q03_ROA                := 0.0]
  fdt_wide[is.na(D29_Accounting_Beta),    D29_Accounting_Beta    := 0.0]

  fdt_wide[, Final_Score :=
    wC19 * C19_Composite_Earnings +
    wQ07 * Q07_Earnings_Stability  +
    wQ03 * Q03_ROA                 +
    wD29 * D29_Accounting_Beta
  ]

  fdt_wide <- fdt_wide[!is.na(Final_Score)]
  if (nrow(fdt_wide) < 20L) return(NULL)

  setorder(fdt_wide, -Final_Score)
  top <- head(fdt_wide, N_HOLD)

  data.table(
    Date   = sig_d,
    Ticker = top$Ticker,
    Score  = top$Final_Score,
    Regime = regime_lbl,
    MRS_t1 = mrs_val,
    W_C19  = wC19, W_Q07 = wQ07, W_Q03 = wQ03, W_D29 = wD29
  )
}

# lapply 방식 (for 루프 없음)
month_results <- lapply(sig_dates_all, .build_one_month)
valid_results <- month_results[!sapply(month_results, is.null)]

FACTORS    <- rbindlist(valid_results)
REGIME_LOG <- FACTORS[, .(
  N_months = .N,
  W_C19    = mean(W_C19),
  W_Q07    = mean(W_Q07),
  W_Q03    = mean(W_Q03),
  W_D29    = mean(W_D29)
), by = Regime]

n_done <- uniqueN(FACTORS$Date)
n_skip <- length(sig_dates_all) - n_done

cat(sprintf("  FACTORS: %s rows | %d signal dates (skip %d)\n",
            format(nrow(FACTORS), big.mark = ","), n_done, n_skip))
cat("  Regime distribution:\n")
print(REGIME_LOG)

rm(month_results, valid_results, FDB_ALL, SIG_SNAP, mrs_snap)
gc(verbose = FALSE)
