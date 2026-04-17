## =============================================================================
## ML Logistic Regression — L-123 Tier 1 분류형 baseline
## IC prefilter(50) + 일간 5yr window + 200K 서브샘플 + walk-forward
## =============================================================================

cat("=== ML Logistic Regression Research ===\n")
cat("시작:", as.character(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(glmnet)
  library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
DAILY_DB_DIR <- file.path(PROJECT_ROOT, ".cache/factor_db_daily")
OUTPUT_DIR   <- file.path(PROJECT_ROOT, "04_Research/ml_logistic_output")
dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R"))

LIQ_THRESHOLD <- 2e8
LAMBDA_GRID <- c(0.1, 0.01, 0.001, 0.0001, 0.00001)
MAX_IS_ROWS <- 200000L  # binomial IRLS 속도를 위한 서브샘플

# --- RAWDATA + Target ---
cat("[1] RAWDATA + Target...\n")
rw_list <- load_rawdata(use_cache = TRUE)
RAWDATA <- rw_list$RAWDATA; BM_DT <- rw_list$BM_DT
setDT(RAWDATA); setkey(RAWDATA, Date, Ticker)

ret_dt <- RAWDATA[Date >= as.Date("2003-01-01"), .(Date, Ticker, Ret, Size)]
setkey(ret_dt, Ticker, Date)
ret_dt[, log_ret := log(1 + Ret)]
ret_dt[, fwd_ret_21d := {
  n <- .N
  if (n <= 21L) rep(NA_real_, n)
  else { cl <- cumsum(log_ret); fwd <- c(cl[22:n], rep(NA_real_, 21L)) - cl; exp(fwd) - 1 }
}, by = Ticker]
ret_dt[, log_ret := NULL]
ret_dt <- ret_dt[!is.na(fwd_ret_21d)]

# --- FDB 구조 ---
EXCLUDE_PREFIXES <- c("RE_", "dps_1y", "bps_1y", "eps_1y", "target_price")
all_files <- sort(list.files(DAILY_DB_DIR, pattern = "fdb_daily_\\d{6}\\.parquet$", full.names = TRUE))
ym_int <- as.integer(sub("fdb_daily_([0-9]{6})\\.parquet", "\\1", basename(all_files)))
sample_dt <- as.data.table(read_parquet(all_files[which(ym_int == 200301)]))
excl_cols <- c(grep(paste(EXCLUDE_PREFIXES, collapse = "|"), names(sample_dt), value = TRUE),
               grep("\\.x$", names(sample_dt), value = TRUE))
keep_cols <- setdiff(names(sample_dt), excl_cols)
FACTOR_COLS_BASE <- setdiff(keep_cols, c("Date", "Ticker"))
rm(sample_dt); gc()

load_daily_chunk <- function(s, e) {
  idx <- which(ym_int >= s & ym_int <= e)
  if (length(idx) == 0) return(NULL)
  dt <- rbindlist(lapply(all_files[idx], function(f) {
    tmp <- as.data.table(read_parquet(f))
    tmp[, intersect(keep_cols, names(tmp)), with = FALSE]
  }), use.names = TRUE, fill = TRUE)
  old_y <- grep("\\.y$", names(dt), value = TRUE)
  new_y <- sub("\\.y$", "", old_y)
  al <- new_y[new_y %in% setdiff(names(dt), old_y)]
  if (length(old_y[new_y %in% al]) > 0) dt[, (old_y[new_y %in% al]) := NULL]
  ry <- old_y[!(new_y %in% al)]
  if (length(ry) > 0) setnames(dt, ry, sub("\\.y$", "", ry), skip_absent = TRUE)
  dup <- names(dt)[duplicated(names(dt))]
  if (length(dup) > 0) dt[, (dup) := NULL]
  setkey(dt, Date, Ticker); dt
}

build_mat <- function(dt, cols) { m <- as.matrix(dt[, cols, with=FALSE]); m[!is.finite(m)] <- 0; m }

# --- Walk-Forward ---
cat("\n[2] Walk-Forward Logistic (18 OOS years)...\n")
oos_years <- as.character(2008:2025)
logit_scores <- list()

for (yi in seq_along(oos_years)) {
  oos_yr <- as.integer(oos_years[yi])
  cat("  [", oos_yr, "] ")

  is_end_yr <- oos_yr - 2L
  is_start_ym <- max(200301, (is_end_yr - 4L) * 100 + 1)
  val_yr <- oos_yr - 1L

  is_chunk <- tryCatch(load_daily_chunk(is_start_ym, is_end_yr * 100 + 12), error = function(e) NULL)
  if (is.null(is_chunk) || nrow(is_chunk) < 10000) { cat("skip\n"); next }

  is_merged <- merge(is_chunk, ret_dt[, .(Date, Ticker, fwd_ret_21d, Size)],
                     by = c("Date", "Ticker"), all.x = FALSE)
  is_merged <- is_merged[!is.na(fwd_ret_21d) & !is.na(Size) & Size >= LIQ_THRESHOLD]
  rm(is_chunk); gc()

  FACTOR_COLS <- intersect(FACTOR_COLS_BASE, names(is_merged))

  # 서브샘플 (Logistic 속도)
  if (nrow(is_merged) > MAX_IS_ROWS) {
    set.seed(oos_yr)
    is_merged <- is_merged[sample(.N, MAX_IS_ROWS)]
  }
  cat("IS:", nrow(is_merged), "| ")

  # IC prefilter
  me <- is_merged[, .SD[Date == max(Date)], by = format(Date, "%Y-%m")]
  ics <- sapply(FACTOR_COLS, function(f) {
    x <- me[[f]]; y <- me$fwd_ret_21d
    v <- is.finite(x) & is.finite(y)
    if (sum(v) < 50) return(NA_real_)
    tryCatch(cor(x[v], y[v], method = "spearman"), error = function(e) NA_real_)
  })
  ics <- ics[!is.na(ics)]
  top50 <- names(sort(abs(ics), decreasing = TRUE))[seq_len(min(50, length(ics)))]
  cat("top50 | ")

  X_is <- build_mat(is_merged, top50)
  y_is <- is_merged$fwd_ret_21d

  # Binary target: top 20% per cross-section
  is_merged[, y_bin := as.integer(fwd_ret_21d >= quantile(fwd_ret_21d, 0.80, na.rm = TRUE)),
            by = format(Date, "%Y-%m")]
  y_bin <- is_merged$y_bin

  # Val (월말)
  val_chunk <- tryCatch(load_daily_chunk(val_yr * 100 + 1, val_yr * 100 + 12), error = function(e) NULL)
  if (is.null(val_chunk)) { cat("skip(val)\n"); rm(X_is, is_merged); gc(); next }
  val_chunk[, ym := format(Date, "%Y-%m")]
  val_me <- val_chunk[, .SD[Date == max(Date)], by = ym]
  val_m <- merge(val_me, ret_dt[, .(Date, Ticker, fwd_ret_21d, Size)],
                 by = c("Date", "Ticker"), all.x = FALSE)
  val_m <- val_m[!is.na(fwd_ret_21d) & !is.na(Size) & Size >= LIQ_THRESHOLD]
  rm(val_chunk, val_me); gc()
  X_val <- build_mat(val_m, top50)
  y_val <- val_m$fwd_ret_21d

  # OOS (월말)
  oos_chunk <- tryCatch(load_daily_chunk(oos_yr * 100 + 1, oos_yr * 100 + 12), error = function(e) NULL)
  if (is.null(oos_chunk)) { cat("skip(oos)\n"); rm(X_is, X_val, is_merged, val_m); gc(); next }
  oos_chunk[, ym := format(Date, "%Y-%m")]
  oos_me <- oos_chunk[, .SD[Date == max(Date)], by = ym]
  oos_m <- merge(oos_me, ret_dt[, .(Date, Ticker, fwd_ret_21d, Size)],
                 by = c("Date", "Ticker"), all.x = FALSE)
  oos_m <- oos_m[!is.na(fwd_ret_21d)]
  rm(oos_chunk, oos_me); gc()
  X_oos <- build_mat(oos_m, top50)

  # --- Logistic (alpha=0.5, binomial, fixed lambda) ---
  fit <- tryCatch({
    glmnet(X_is, y_bin, alpha = 0.5, family = "binomial", lambda = LAMBDA_GRID)
  }, error = function(e) NULL)

  if (!is.null(fit)) {
    vp <- predict(fit, X_val, type = "response")
    vic <- apply(vp, 2, function(p) tryCatch(cor(p, y_val, method = "spearman"), error = function(e) NA))
    best_l <- LAMBDA_GRID[which.max(vic)]
    pred <- as.numeric(predict(fit, X_oos, s = best_l, type = "response"))
    logit_val_ic <- max(vic, na.rm = TRUE)

    dt_out <- oos_m[, .(Date, Ticker, fwd_ret_21d, Size)]
    dt_out[, Score := pred]
    logit_scores[[yi]] <- dt_out
    cat("Logit:", round(logit_val_ic, 3), "(lam=", best_l, ")\n")
  } else {
    cat("Logit: err\n")
  }

  rm(X_is, X_val, X_oos, is_merged, val_m, oos_m, fit)
  gc()
}

# --- IC 분석 ---
cat("\n[3] OOS IC...\n")
logit_all <- rbindlist(logit_scores, fill = TRUE)
logit_all[, YearMonth := format(Date, "%Y-%m")]
ic_m <- logit_all[, .(IC = cor(Score, fwd_ret_21d, method = "spearman", use = "complete.obs")),
                  by = YearMonth]
ic_mean <- mean(ic_m$IC, na.rm = TRUE)
ic_sd <- sd(ic_m$IC, na.rm = TRUE)
icir <- ic_mean / ic_sd

cat("Logistic IC:", round(ic_mean, 4), " ICIR:", round(icir, 4), "\n")
fwrite(ic_m, file.path(OUTPUT_DIR, "logit_oos_ic_monthly.csv"))

# --- 백테스트 ---
cat("\n[4] 백테스트...\n")
logit_bt <- merge(logit_all, RAWDATA[, .(Date, Ticker, Size)],
                  by = c("Date", "Ticker"), all.x = TRUE, suffixes = c("", ".raw"))
if ("Size.raw" %in% names(logit_bt)) { logit_bt[is.na(Size), Size := Size.raw]; logit_bt[, Size.raw := NULL] }
logit_bt <- logit_bt[!is.na(Score) & !is.na(Size) & Size >= LIQ_THRESHOLD]
logit_bt[, rank := frank(-Score, ties.method = "first"), by = Date]
logit_bt <- logit_bt[rank <= 30]
FACTORS <- logit_bt[, .(Date, Ticker, Score)]

bt <- tryCatch({
  run_monthly_simulation(RAWDATA, BM_DT, FACTORS, n_holdings = 20,
    commission = 0.0015, weight_method = "EW",
    buffer_zone = list(keep_n = 20, entry_n = 30))
}, error = function(e) { cat("BT error:", e$message, "\n"); NULL })

if (!is.null(bt)) {
  ret <- bt$DAILY_NAV_DT$Strategy_Ret[is.finite(bt$DAILY_NAV_DT$Strategy_Ret)]
  cum <- cumprod(1 + ret)
  n_yr <- length(ret) / 252
  cat("CAGR:", round((tail(cum,1)^(1/n_yr)-1)*100, 2), "%\n")
  cat("SR:", round(mean(ret)/sd(ret)*sqrt(252), 3), "\n")
  cat("MDD:", round(min(cum/cummax(cum)-1)*100, 2), "%\n")
  fwrite(bt$DAILY_NAV_DT, file.path(OUTPUT_DIR, "logit_nav.csv"))
}

result <- list(model = "Logistic", IC = round(ic_mean, 4), ICIR = round(icir, 4),
               training = "일간 5yr window, 200K subsample", prefilter = "IC top50")
write_json(result, file.path(OUTPUT_DIR, "result.json"), auto_unbox = TRUE, pretty = TRUE)

cat("\n=== Logistic Research 완료:", as.character(Sys.time()), "===\n")
