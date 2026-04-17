# STR_1622_M9_synthesis: 3F IC-weighted + Regime v7.1 (synthesis_tested = TRUE)
# Mutation M9: C19+V14+Q01. RISK_OFF(regime_score_lag > 70) → Q01_GPA ×1.5 renorm.
# DD Brake는 run_all.R에서 처리. 팩터 가중만 Regime 조건부 조정.
# PIT: C1(no full-sample), C5(Regime t-1 lag), C13(Z_Score_Aligned), C14(Usable_Date<=sig_d), C15(bulk preload)
# Arnott 2019 + DeMiguel 2009 + Barroso & Santa-Clara 2015 (factor risk mgmt)

cat("[factor_engine] STR_1622_M9_synthesis: 3F IC-weighted + Regime v7.1 (synthesis_tested=TRUE)...\n")
set.seed(1622)
suppressPackageStartupMessages(library(dplyr))

LIQ_THRESHOLD <- 2e8
N_FACTORS    <- 3L
FLOOR_W      <- 0.10   # 3F floor
CAP_W        <- 0.50   # 3F cap
N_FACTORS_EW <- 1.0 / N_FACTORS
REGIME_RISKOFF_THRESH <- 70   # Regime_Score > 70 → RISK_OFF
Q01_BOOST_FACTOR      <- 1.5  # RISK_OFF 시 Q01_GPA 가중 부스트

NEEDED_FACTORS <- c("C19_Composite_Earnings", "V14_EBIT_EV", "Q01_GPA")

# C15: bulk preload — 루프 밖에서 한 번만 (OPT-1 준수)
pq_files <- list.files(file.path(CACHE_DIR, "factor_db"),
                       pattern = "\\.parquet$", full.names = TRUE)
ds <- open_dataset(pq_files, format = "parquet")
FDB_ALL <- ds |>
  filter(Factor_Name %in% NEEDED_FACTORS) |>
  select(Date, Ticker, Factor_Name, Z_Score, Coverage) |>
  collect() |> as.data.table()
FDB_ALL[, Date := as.Date(Date)]
FDB_ALL[, Usable_Date := Date]
setnames(FDB_ALL, "Z_Score", "Z_Score_Aligned")   # C13: no manual flip
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
setkey(FDB_ALL, Date, Ticker)
cat(sprintf("  FDB: %d rows | factors: %s\n", nrow(FDB_ALL),
            paste(unique(FDB_ALL$Factor_Name), collapse = ", ")))

# Regime v7.1 로드 (C5: t-1 lag 적용 — signal은 전월 기준)
REGIME_DIR <- file.path(INFRA_DIR, "regime")
source(file.path(REGIME_DIR, "regime_signal.R"))
regime_dt <- tryCatch(load_regime_signal(), error = function(e) {
  cat("[M9] Regime signal 로드 실패:", e$message, "— Regime 조정 비활성화\n")
  NULL
})
if (!is.null(regime_dt) && "Regime_Score" %in% names(regime_dt)) {
  setorder(regime_dt, Date)
  # C5: t-1 lag — 전월 Regime_Score를 당월 적용
  n_r <- nrow(regime_dt)
  regime_dt[, regime_score_lag := c(0, Regime_Score[-.N])]
  cat(sprintf("  Regime v7.1: %d months | score_lag range [%.1f, %.1f]\n",
              n_r, min(regime_dt$regime_score_lag), max(regime_dt$regime_score_lag)))
} else {
  regime_dt <- NULL
  cat("  Regime v7.1: 비활성화 (캐시 없음)\n")
}

setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
monthly_dates <- sort(RAWDATA[, .(SD = max(Date)), by = YM]$SD)
all_dates     <- sort(unique(RAWDATA$Date))
monthly_dates <- monthly_dates[monthly_dates >= all_dates[min(253L, length(all_dates))]]
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n = 20L, align = "right"),
                            n = 1L, type = "lag"), by = Ticker]
setorder(RAWDATA, Ticker, Date)
RAWDATA[, FwdRet := shift(Ret, n = -1L, type = "lead"), by = Ticker]

fdb_dates   <- sort(unique(FDB_ALL$Date))
factor_list <- vector("list", length(monthly_dates))
n_done <- 0L; n_skipped <- 0L
n_riskoff <- 0L

# IC history accumulator (expanding window, 12M rolling)
# 루프 내 DB 재로드 없음 — FDB_ALL 메모리 슬라이스 사용 (OPT-1 준수)
ic_history <- list()

for (i in seq_along(monthly_dates)) {
  sig_d <- as.Date(monthly_dates[i])

  # C14: Usable_Date <= sig_d
  valid_fdb <- fdb_dates[fdb_dates <= sig_d]
  if (length(valid_fdb) == 0L) { n_skipped <- n_skipped + 1L; next }
  fdb_d <- max(valid_fdb)

  fdt <- FDB_ALL[Date == fdb_d & Coverage == TRUE & Usable_Date <= sig_d]
  if (nrow(fdt) == 0L) fdt <- FDB_ALL[Date == fdb_d & Coverage == TRUE]
  if (nrow(fdt) == 0L) { n_skipped <- n_skipped + 1L; next }

  fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")

  liq      <- RAWDATA[Date == sig_d, .(Ticker, AvgTV20, FwdRet)]
  fdt_wide <- merge(fdt_wide, liq, by = "Ticker")
  fdt_wide <- fdt_wide[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(fdt_wide) < 20L) { n_skipped <- n_skipped + 1L; next }

  # IC 계산: lapply 패턴 (루프 내 DB 재로드 없음)
  ic_vals <- lapply(NEEDED_FACTORS, function(fn) {
    if (!fn %in% names(fdt_wide)) return(NA_real_)
    vals <- fdt_wide[[fn]]; fwd <- fdt_wide$FwdRet
    mask <- !is.na(vals) & !is.na(fwd)
    if (sum(mask) >= 20L) cor(rank(vals[mask]), rank(fwd[mask]), method = "spearman")
    else NA_real_
  })
  ic_current <- setNames(unlist(ic_vals), NEEDED_FACTORS)

  # t-1 lag 저장
  ic_history[[as.character(sig_d)]] <- ic_current

  past_dates <- names(ic_history)[as.Date(names(ic_history)) < sig_d]

  if (length(past_dates) == 0L) {
    weights <- setNames(rep(N_FACTORS_EW, N_FACTORS), NEEDED_FACTORS)
  } else {
    window_dates <- tail(past_dates, 12L)
    ic_mat  <- do.call(rbind, lapply(window_dates, function(d) ic_history[[d]]))
    ic_mean <- colMeans(ic_mat, na.rm = TRUE)

    ic_abs  <- abs(ic_mean); ic_abs[is.na(ic_abs)] <- 0
    ic_sum  <- sum(ic_abs)
    ic_norm <- if (ic_sum > 0) ic_abs / ic_sum else rep(N_FACTORS_EW, N_FACTORS)
    wraw    <- 0.5 * ic_norm + 0.5 * N_FACTORS_EW
    wraw    <- pmax(wraw, FLOOR_W)
    wraw    <- pmin(wraw, CAP_W)
    weights <- wraw / sum(wraw)
    names(weights) <- NEEDED_FACTORS
  }

  # Regime v7.1 조건부 팩터 가중 조정 (C5: t-1 lag regime_score_lag 사용)
  # RISK_OFF: regime_score_lag > 70 → Q01_GPA ×1.5 후 renormalize
  if (!is.null(regime_dt)) {
    past_regime <- regime_dt[Date <= sig_d]
    if (nrow(past_regime) > 0) {
      rs_lag <- tail(past_regime$regime_score_lag, 1)
      if (!is.na(rs_lag) && rs_lag > REGIME_RISKOFF_THRESH) {
        if ("Q01_GPA" %in% names(weights)) {
          weights["Q01_GPA"] <- weights["Q01_GPA"] * Q01_BOOST_FACTOR
          weights <- weights / sum(weights)  # renormalize
          n_riskoff <- n_riskoff + 1L
        }
      }
    }
  }

  # 랭크 스코어: lapply 패턴
  score_parts <- lapply(NEEDED_FACTORS, function(fn) {
    w <- weights[fn]
    if (fn %in% names(fdt_wide) && sum(!is.na(fdt_wide[[fn]])) > 10L) {
      rnk <- frank(fdt_wide[[fn]], na.last = "keep", ties.method = "average") /
             sum(!is.na(fdt_wide[[fn]]))
      list(s = w * rnk, w = w)
    } else {
      list(s = rep(0, nrow(fdt_wide)), w = 0)
    }
  })
  total_w <- sum(sapply(score_parts, `[[`, "w"))
  if (total_w == 0) { n_skipped <- n_skipped + 1L; next }

  fdt_wide[, Score := Reduce("+", lapply(score_parts, `[[`, "s")) / total_w]
  fdt_wide[, Date  := sig_d]
  factor_list[[i]] <- fdt_wide[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done + 1L
}

FACTORS <- rbindlist(factor_list[!sapply(factor_list, is.null)])
setorder(FACTORS, Date, -Score)
cat(sprintf("  Regime RISK_OFF 발동: %d/%d 월 (%.1f%%)\n",
            n_riskoff, n_done, 100 * n_riskoff / max(n_done, 1)))

if ("YM"    %in% names(RAWDATA)) RAWDATA[, YM     := NULL]
if ("FwdRet" %in% names(RAWDATA)) RAWDATA[, FwdRet := NULL]
for (col in c("TradingValue", "AvgTV20")) if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
rm(FDB_ALL, ic_history); gc(verbose = FALSE)
cat(sprintf("  FACTORS: %s rows | %d dates (skip %d)\n",
            format(nrow(FACTORS), big.mark = ","), n_done, n_skipped))
