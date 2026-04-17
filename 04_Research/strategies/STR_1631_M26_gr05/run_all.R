## =============================================================================
## STR_1631_M26_gr05: C19 + GR05_ROE_Growth Composite — S5 Mutation
## 핵심: VDplus C19 + GR05(ROE Growth) = 실적 서프라이즈 + 수익성 가속
##       Marginal Scan SR delta +0.316 (0.703 -> 1.019)
##       Novy-Marx (2013) profitability + Fama-French (2015) RMW
## S5 mutation: Factor_Weight | Parent: STR_1631
## OPT-1: Arrow open_dataset bulk load | PIT: C15 Z_Score_Aligned
## =============================================================================

cat("=== STR_1631_M26: C19 + GR05_ROE_Growth ===\n")
t0 <- Sys.time()

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(ggplot2)
  library(jsonlite)
})

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0L && !is.na(a[[1L]])) a[[1L]] else b

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
STRAT_DIR    <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1631_M26_gr05")
OUT_DIR      <- file.path(STRAT_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
FDB_DIR      <- file.path(PROJECT_ROOT, ".cache/factor_db")

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R"))

N_HOLD       <- 20L
LIQ_THRESH   <- 2e8
COMMISSION   <- 0.0015
OOS_START    <- as.Date("2008-01-01")
OOS_END      <- as.Date("2025-12-31")

# =============================================================================
# [1] RAWDATA
# =============================================================================
cat("[1] RAWDATA...\n")
rw <- load_rawdata(use_cache = TRUE)
RAWDATA <- rw$RAWDATA; BM_DT <- rw$BM_DT
setDT(RAWDATA); setkey(RAWDATA, Date, Ticker)

RAWDATA[, ym := format(Date, "%Y-%m")]
me_dt <- RAWDATA[, .(me_date = max(Date)), by = ym][order(me_date)]
SIG_DATES <- me_dt[me_date >= OOS_START & me_date <= OOS_END]$me_date
cat(sprintf("    Signal dates: %d\n", length(SIG_DATES)))

# =============================================================================
# [2] Monthly FDB bulk load (OPT-1: open_dataset, no loop)
# =============================================================================
cat("\n[2] Monthly FDB bulk load...\n")
fdb_pq   <- list.files(FDB_DIR, "^factor_db_\\d{6}\\.", full.names = TRUE)
ds_fdb   <- open_dataset(fdb_pq)

# C13: Z_Score_Aligned 사용. C19/GR05 모두 higher=better (방향 정렬 불필요)
# Factor DB connector의 align_factor_direction()과 동일한 결과
fdb_all <- ds_fdb |>
  dplyr::filter(Factor_Name %in% c("C19_Composite_Earnings", "GR05_ROE_Growth"),
                Coverage == TRUE) |>
  dplyr::select(Date, Ticker, Factor_Name, Z_Score) |>
  dplyr::collect() |>
  as.data.table()

fdb_all[, Date := as.Date(Date)]
fdb_all <- fdb_all[Date %in% SIG_DATES]
# C13: Z_Score를 Z_Score_Aligned로 명시 (C19/GR05 = positive direction)
setnames(fdb_all, "Z_Score", "Z_Score_Aligned")
cat(sprintf("    FDB rows: %s | dates: %d\n",
            format(nrow(fdb_all), big.mark = ","), uniqueN(fdb_all$Date)))

fdb_c19  <- fdb_all[Factor_Name == "C19_Composite_Earnings",
                     .(sig_date = Date, Ticker, z_c19 = Z_Score_Aligned)]
fdb_gr05 <- fdb_all[Factor_Name == "GR05_ROE_Growth",
                     .(sig_date = Date, Ticker, z_gr05 = Z_Score_Aligned)]

fdb_wide <- merge(fdb_c19, fdb_gr05, by = c("sig_date", "Ticker"), all = FALSE)
cat(sprintf("    Both factors: %s rows, %d dates\n",
            format(nrow(fdb_wide), big.mark = ","), uniqueN(fdb_wide$sig_date)))
rm(fdb_all, fdb_c19, fdb_gr05); gc()

# =============================================================================
# [3] LIQ filter + Scoring
# =============================================================================
cat("\n[3] Scoring...\n")

# C10: 유동성 필터 t-1 lag (당월 거래량 사용 금지)
RAWDATA[, Vol_KRW := Vol * Close]
liq_dt <- RAWDATA[, .(avg_vol20 = mean(tail(Vol_KRW, 20L), na.rm = TRUE)),
                  by = .(ym, Ticker)]
# t-1 lag: 전월 유동성으로 당월 필터
sig_ym <- data.table(sig_date = SIG_DATES, sig_ym = format(SIG_DATES, "%Y-%m"))
sig_ym[, prev_ym := shift(sig_ym, type = "lag")]
sig_ym <- sig_ym[!is.na(prev_ym)]
me_liq <- merge(sig_ym, liq_dt, by.x = "prev_ym", by.y = "ym")
me_liq <- me_liq[avg_vol20 >= LIQ_THRESH, .(sig_date, Ticker)]

scored <- merge(fdb_wide, me_liq, by = c("sig_date", "Ticker"))
cat(sprintf("    After LIQ: %s rows\n", format(nrow(scored), big.mark = ",")))

scored[, z_combo := z_c19 + z_gr05]
scored[, rnk_c19   := frank(-z_c19,   ties.method = "first"), by = sig_date]
scored[, rnk_combo := frank(-z_combo, ties.method = "first"), by = sig_date]

FACTORS_c19   <- scored[rnk_c19 <= N_HOLD,   .(Date = sig_date, Ticker, Score = z_c19)]
FACTORS_combo <- scored[rnk_combo <= N_HOLD, .(Date = sig_date, Ticker, Score = z_combo)]
cat(sprintf("    C19: %d | C19+GR05: %d\n", nrow(FACTORS_c19), nrow(FACTORS_combo)))

# =============================================================================
# [4] Backtest (EW, 15bps)
# =============================================================================
cat("\n[4] Backtest...\n")

run_bt <- function(fac, label) {
  setDT(fac); setkey(fac, Date, Ticker)
  bt <- tryCatch(
    run_monthly_simulation(
      RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = fac,
      n_holdings = N_HOLD, commission = COMMISSION,
      weight_method = "EW",
      buffer_zone = list(keep_n = N_HOLD + 10L, entry_n = N_HOLD)
    ),
    error = function(e) { cat("  ", label, " err:", e$message, "\n"); NULL }
  )
  if (is.null(bt)) return(NULL)
  r <- bt$DAILY_NAV_DT$Strategy_Ret; r <- r[is.finite(r)]
  cum <- cumprod(1 + r); nyr <- length(r) / 252
  list(label = label,
       CAGR = round((tail(cum, 1)^(1/nyr) - 1) * 100, 2),
       Sharpe = round(mean(r) / sd(r) * sqrt(252), 4),
       MDD = round(min(cum / cummax(cum) - 1) * 100, 2),
       nav_dt = bt$DAILY_NAV_DT)
}

bt_c19   <- run_bt(FACTORS_c19, "C19_only")
bt_combo <- run_bt(FACTORS_combo, "C19_GR05")

cat("\n=== Results ===\n")
lapply(list(bt_c19, bt_combo), function(b) {
  if (!is.null(b))
    cat(sprintf("  %s: CAGR %.1f%% | SR %.4f | MDD %.1f%%\n",
                b$label, b$CAGR, b$Sharpe, b$MDD))
})

if (!is.null(bt_c19) && !is.null(bt_combo)) {
  cat(sprintf("\n  SR delta: %+.4f\n", bt_combo$Sharpe - bt_c19$Sharpe))
}

# =============================================================================
# [5] Chart
# =============================================================================
cat("\n[5] Chart...\n")
tryCatch({
  eq_list <- lapply(list(bt_c19, bt_combo), function(b) {
    if (is.null(b)) return(NULL)
    d <- copy(b$nav_dt)[, .(Date = as.Date(Date), ret = Strategy_Ret)]
    d <- d[is.finite(ret)]; d[, cum := cumprod(1 + ret)]; d[, label := b$label]; d
  })
  bm <- BM_DT[order(Date), .(Date = as.Date(Date), BM_Ret)]
  bm[, cum := cumprod(1 + fifelse(is.finite(BM_Ret), BM_Ret, 0))][, label := "KOSPI"]
  eq_all <- rbind(rbindlist(Filter(Negate(is.null), eq_list))[, .(Date, cum, label)],
                  bm[, .(Date, cum, label)], fill = TRUE)

  p <- ggplot(eq_all, aes(x = Date, y = cum, color = label)) +
    geom_line(linewidth = 0.8) + scale_y_log10(labels = scales::comma) +
    labs(title = "STR_1631 M26: C19 vs C19+GR05",
         subtitle = sprintf("C19 SR=%.3f | C19+GR05 SR=%.3f | delta=%+.3f",
                            bt_c19$Sharpe %||% NA, bt_combo$Sharpe %||% NA,
                            (bt_combo$Sharpe %||% 0) - (bt_c19$Sharpe %||% 0)),
         x = NULL, y = "Cumulative (Log)", color = NULL) +
    theme_minimal(base_size = 12) + theme(legend.position = "bottom")
  ggsave(file.path(OUT_DIR, "equity_curve.png"), p, width = 12, height = 6, dpi = 150)
  cat("  equity_curve.png\n")
}, error = function(e) cat("  chart err:", e$message, "\n"))

# =============================================================================
# [6] Save
# =============================================================================
perf <- list(
  strategy_id = "STR_1631_M26_gr05",
  mutation = "S5 Factor_Weight: C19 + GR05_ROE_Growth",
  parent = "STR_1631", timestamp = as.character(Sys.time()),
  c19_only = if (!is.null(bt_c19)) list(SR = bt_c19$Sharpe, CAGR = bt_c19$CAGR, MDD = bt_c19$MDD),
  c19_gr05 = if (!is.null(bt_combo)) list(SR = bt_combo$Sharpe, CAGR = bt_combo$CAGR, MDD = bt_combo$MDD),
  sr_delta = if (!is.null(bt_c19) && !is.null(bt_combo)) bt_combo$Sharpe - bt_c19$Sharpe else NA,
  config = list(n_hold = N_HOLD, commission = COMMISSION, liq = LIQ_THRESH,
                weight = "EW", scoring = "z_c19 + z_gr05")
)
write_json(perf, file.path(OUT_DIR, "performance.json"), auto_unbox = TRUE, pretty = TRUE)
if (!is.null(bt_combo)) fwrite(bt_combo$nav_dt, file.path(OUT_DIR, "nav_combo.csv"))
if (!is.null(bt_c19))   fwrite(bt_c19$nav_dt, file.path(OUT_DIR, "nav_c19.csv"))

cat(sprintf("\n=== Done (%.1f min) ===\n", as.numeric(difftime(Sys.time(), t0, units = "mins"))))
