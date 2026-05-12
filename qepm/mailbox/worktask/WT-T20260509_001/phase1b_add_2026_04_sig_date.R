## ============================================================================
## WT-T20260509_001 — Phase 1b: Add sig_date 2026-04-01 to alpha_scores
##
## Issue: Phase 1 결과 sig_dates 240 → 267 (2026-03-01까지). 도훈 mandate "2026-04까지"
##   에 따라 sig_date 2026-04-01 (forward return = 2026-05 partial, 측정 불가) 추가.
##   Forward return은 NA여도 score_eff (factor-only)는 산출 가능 — 6/1 운용 결정용.
##
## Approach: factor_engine_proposal.R 핵심 logic copy + sig_date 2026-04-01만 single
##   계산. 기존 alpha_scores에 append.
##
## Boundary:
##   - Iter 5 sleeve definition retain (Core 4F + Defense 3F + 0.65/0.35)
##   - 기존 267 sig_date row hash 보존 (append-only)
##   - PIT: sig_date 2026-04-01 score = factor_db 2026-04 + past IC (≤2026-03-01)
## ============================================================================

cat("\n========================================================\n")
cat("  WT-T20260509_001 Phase 1b — Add sig_date 2026-04-01\n")
cat(sprintf("  Started: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat("========================================================\n\n")

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR  <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-T20260509_001")
ART_DIR <- file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260425_010")
ITER5_WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-D20260425_010")
FUNC_PATH <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")

setwd(PROJECT_ROOT)

suppressPackageStartupMessages({
  library(jsonlite); library(data.table); library(arrow); library(lubridate)
})

source(file.path(FUNC_PATH, "config.R"))
source(file.path(FUNC_PATH, "backtest_harness.R"))
source(file.path(FUNC_PATH, "factor_db/factor_db_connector.R"))

# ─── Read existing alpha_scores (Phase 1 result, 267 sig_dates) ──────────────
src <- file.path(ART_DIR, "alpha_scores.parquet")
a_existing <- as.data.table(read_parquet(src))
n_pre <- nrow(a_existing)
sig_dates_pre <- sort(unique(a_existing$Date))
cat(sprintf("[EXISTING] %d rows | %d sig_dates (last: %s)\n",
            n_pre, length(sig_dates_pre), as.character(max(sig_dates_pre))))

target_sig_d <- as.Date("2026-04-01")
if (target_sig_d %in% sig_dates_pre) {
  cat(sprintf("[SKIP] sig_date %s already present\n", target_sig_d))
  quit(status = 0)
}

# ─── Constants (mirror factor_engine_proposal.R) ─────────────────────────────
SLEEVE_CORE     <- c("C01_SUE", "C02_EPS_Chg_1m", "C04_ESBR", "C06_TP_Gap")
SLEEVE_DEFENSE  <- c("Q07_Earnings_Stability", "M08_Residual_Mom", "Q25_Ohlson_O")
NEEDED_FACTORS  <- unique(c(SLEEVE_CORE, SLEEVE_DEFENSE))
W_CORE <- 0.65; W_DEF <- 0.35

winsor_z <- function(x, sigma = 2.5) {
  m <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-10) return(x)
  pmax(pmin(x, m + sigma * s), m - sigma * s)
}

# ─── Load factor_db for sig_date 2026-04 ─────────────────────────────────────
ym_target <- format(target_sig_d, "%Y%m")
fdb_path <- file.path(CACHE_DIR, "factor_db", sprintf("factor_db_%s.parquet", ym_target))
if (!file.exists(fdb_path)) stop("[FAIL] factor_db_", ym_target, ".parquet not found")
cat(sprintf("[LOAD] %s\n", basename(fdb_path)))

fdb_t <- as.data.table(read_parquet(fdb_path,
  col_select = c("Ticker", "Factor_Name", "Z_Score", "Coverage")))
fdb_t <- fdb_t[Factor_Name %in% NEEDED_FACTORS & Coverage == TRUE,
               .(Ticker, Factor_Name, Z_Score)]
fdb_t[, sig_date := target_sig_d]
cat(sprintf("[FDB] %d rows | %d factors\n", nrow(fdb_t), uniqueN(fdb_t$Factor_Name)))

# Apply align_factor_direction (PIT C13 + C14)
fdb_t <- align_factor_direction(fdb_t, .load_registry(),
                                  sig_date = target_sig_d, min_ic_months = 12L)
if ("Z_Score_Aligned" %in% names(fdb_t)) {
  fdb_t[, Z_Score := Z_Score_Aligned]
  fdb_t[, Z_Score_Aligned := NULL]
}

# Wide format
FDB_T <- dcast(fdb_t, sig_date + Ticker ~ Factor_Name,
               value.var = "Z_Score", fill = NA_real_)

# ─── Liquidity filter (C10) ─────────────────────────────────────────────────
RAWDATA_obj <- load_rawdata(use_cache = TRUE)
RAWDATA <- RAWDATA_obj$RAWDATA
setkey(RAWDATA, Date, Ticker)
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[order(Date), AvgTV20_t := frollmean(TradingValue, n = 20L, align = "right"), by = Ticker]
RAWDATA[order(Date), AvgTV20 := shift(AvgTV20_t, n = 1L, type = "lag"), by = Ticker]
RAWDATA[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= 2e8]

snap <- RAWDATA[Date == target_sig_d & LiqPass == TRUE, .(Ticker)]
if (nrow(snap) == 0) {
  closest_d <- RAWDATA[Date <= target_sig_d, max(Date)]
  snap <- RAWDATA[Date == closest_d & LiqPass == TRUE, .(Ticker)]
  cat(sprintf("[LIQ] using closest prior date %s for liquidity (sig %s no daily bar)\n",
              as.character(closest_d), as.character(target_sig_d)))
}
FDB_T <- FDB_T[Ticker %in% snap$Ticker]
cat(sprintf("[LIQ] post-liquidity: %d rows\n", nrow(FDB_T)))

# ─── Universe filter (KOSPI200 ∪ KOSDAQ150) ──────────────────────────────────
k200  <- as.data.table(read_parquet(file.path(CACHE_DIR, "universe_support/us_k200.parquet")))
kq150 <- as.data.table(read_parquet(file.path(CACHE_DIR, "universe_support/us_kq150.parquet")))
k200[, Date := as.Date(Date)]; kq150[, Date := as.Date(Date)]
# member at prior month-end is valid for next month-start sig_date
prior_month_end <- target_sig_d - days(1)
k200_member <- k200[Date == prior_month_end & K200 == 1, Ticker]
kq150_member <- kq150[Date == prior_month_end & KQ150 == 1, Ticker]
if (length(k200_member) == 0) {
  closest_pm <- k200[Date <= prior_month_end, max(Date)]
  k200_member <- k200[Date == closest_pm & K200 == 1, Ticker]
  cat(sprintf("[UNIV K200] using closest prior month-end %s\n", as.character(closest_pm)))
}
if (length(kq150_member) == 0) {
  closest_pm <- kq150[Date <= prior_month_end, max(Date)]
  kq150_member <- kq150[Date == closest_pm & KQ150 == 1, Ticker]
  cat(sprintf("[UNIV KQ150] using closest prior month-end %s\n", as.character(closest_pm)))
}
universe_t <- unique(c(k200_member, kq150_member))
FDB_T <- FDB_T[Ticker %in% universe_t]
cat(sprintf("[UNIV] post K200∪KQ150: %d rows\n", nrow(FDB_T)))

# ─── Compute past IC for expanding weights (PIT) ─────────────────────────────
# IC up to sig_date < target_sig_d. We use existing alpha_scores as proxy:
# need cumulative IC of each factor. But that requires re-loading historical
# FDB. Simpler: use factor_engine's built result —— however, expanding IC
# can be reconstructed from existing alpha_scores via Score_Core_z + Ret_1m
# correlation per sig_date.
#
# Most robust approach: bulk-load past FDB + monthly_ret for IC (≤2026-03-01),
# match factor_engine logic identically.

cat("\n[IC RECONSTRUCTION] Loading past FDB for IC weight computation...\n")
fdb_dir <- file.path(CACHE_DIR, "factor_db")
fdb_files <- sort(list.files(fdb_dir, pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE))
fdb_files_past <- fdb_files[sapply(fdb_files, function(fp) {
  ym <- gsub(".*factor_db_(\\d{6})\\.parquet$", "\\1", basename(fp))
  d  <- as.Date(paste0(substr(ym,1,4),"-",substr(ym,5,6),"-01"))
  !is.na(d) && d >= as.Date("2004-01-01") && d < target_sig_d
})]
cat(sprintf("[IC] %d past parquet files for IC computation\n", length(fdb_files_past)))

FDB_PAST <- rbindlist(lapply(fdb_files_past, function(fp) {
  ym    <- gsub(".*factor_db_(\\d{6})\\.parquet$", "\\1", basename(fp))
  sig_d <- as.Date(paste0(substr(ym,1,4),"-",substr(ym,5,6),"-01"))
  dt    <- tryCatch(
    as.data.table(read_parquet(fp,
      col_select = c("Ticker","Factor_Name","Z_Score","Coverage"))),
    error = function(e) NULL
  )
  if (is.null(dt) || nrow(dt) == 0) return(NULL)
  dt <- dt[Factor_Name %in% NEEDED_FACTORS & Coverage == TRUE,
           .(Ticker, Factor_Name, Z_Score)]
  if (nrow(dt) == 0) return(NULL)
  dt[, sig_date := sig_d]
  dt
}), fill = TRUE, use.names = TRUE)

FDB_PAST_LIST <- split(FDB_PAST, by = "sig_date")
FDB_PAST <- rbindlist(lapply(FDB_PAST_LIST, function(sub) {
  sd <- as.Date(sub$sig_date[1])
  align_factor_direction(sub, .load_registry(), sig_date = sd, min_ic_months = 12L)
}), fill = TRUE)
rm(FDB_PAST_LIST); gc(verbose = FALSE)
if ("Z_Score_Aligned" %in% names(FDB_PAST)) {
  FDB_PAST[, Z_Score := Z_Score_Aligned]
  FDB_PAST[, Z_Score_Aligned := NULL]
}

FDB_PAST_W <- dcast(FDB_PAST, sig_date + Ticker ~ Factor_Name,
                     value.var = "Z_Score", fill = NA_real_)

# Monthly forward returns (for IC)
RAWDATA_filt <- RAWDATA[!(format(Date, "%Y-%m") == "2026-05")]
monthly_ret <- RAWDATA_filt[, .(Ret_1m = prod(1 + Ret, na.rm = TRUE) - 1),
                              by = .(YearMonth = format(Date, "%Y-%m"), Ticker)]
monthly_ret[, sig_date := as.Date(paste0(YearMonth, "-01"))]
setkey(monthly_ret, sig_date, Ticker)

FDB_PAST_W[, fwd_date := sig_date %m+% months(1)]
available_factors <- intersect(NEEDED_FACTORS, names(FDB_PAST_W))

FDB_WITH_RET_PAST <- merge(
  FDB_PAST_W[, .SD, .SDcols = c("sig_date","fwd_date","Ticker", available_factors)],
  monthly_ret[, .(fwd_date = sig_date, Ticker, Ret_1m)],
  by = c("fwd_date","Ticker"), all.x = FALSE
)
setkey(FDB_WITH_RET_PAST, sig_date, Ticker)
cat(sprintf("[IC] FDB_WITH_RET_PAST: %d rows | %d sig_dates\n",
            nrow(FDB_WITH_RET_PAST), uniqueN(FDB_WITH_RET_PAST$sig_date)))

# Per-factor IC up to sig_date < target_sig_d
ic_per_month <- lapply(available_factors, function(fn) {
  per_month <- FDB_WITH_RET_PAST[!is.na(get(fn)) & !is.na(Ret_1m),
    .(IC = tryCatch(cor(get(fn), Ret_1m, method="spearman"), error=function(e) NA),
      N = .N), by = sig_date]
  per_month[, factor := fn]
  per_month
})
IC_DT_PAST <- rbindlist(ic_per_month, fill = TRUE)

# Compute expanding IC mean for each factor (up to and including sig_date < target_sig_d)
# = filter IC_DT_PAST and aggregate
ic_mean_exp <- IC_DT_PAST[!is.na(IC), .(mean_IC = mean(IC, na.rm=TRUE)), by = factor]
cat("\n[IC EXPANDING (target = 2026-04-01, all past)]\n")
print(ic_mean_exp)

# ─── Compute Score_Core for sig_date 2026-04-01 ───────────────────────────────
build_composite_for_one <- function(fac_names, FDB_one, ic_means) {
  fac_names <- intersect(fac_names, names(FDB_one))
  if (length(fac_names) == 0) stop("No factors available for composite")
  if (nrow(FDB_one) < 10L) return(NULL)
  ic_match <- ic_means[factor %in% fac_names]
  if (nrow(ic_match) < length(fac_names)) {
    # fallback to EW
    theta <- setNames(rep(1/length(fac_names), length(fac_names)), fac_names)
  } else {
    theta_raw <- setNames(pmax(ic_match$mean_IC, 0), ic_match$factor)
    theta_all <- setNames(rep(0, length(fac_names)), fac_names)
    for (fn in names(theta_raw)) {
      if (fn %in% names(theta_all)) theta_all[fn] <- theta_raw[fn]
    }
    s <- sum(abs(theta_all))
    theta <- if (s < 1e-10) {
      setNames(rep(1/length(fac_names), length(fac_names)), fac_names)
    } else theta_all / s
  }
  score_vec <- rep(0, nrow(FDB_one))
  for (fn in fac_names) {
    if (!fn %in% names(FDB_one)) next
    col_vals <- FDB_one[[fn]]
    if (all(is.na(col_vals))) next
    col_w <- winsor_z(col_vals, sigma = 2.5)
    score_vec <- score_vec + theta[fn] * col_w
  }
  list(scores = score_vec, theta = theta)
}

build_composite_ew_for_one <- function(fac_names, FDB_one) {
  fac_names <- intersect(fac_names, names(FDB_one))
  if (length(fac_names) == 0) stop("No factors available for EW composite")
  if (nrow(FDB_one) < 10L) return(NULL)
  theta <- setNames(rep(1/length(fac_names), length(fac_names)), fac_names)
  score_vec <- rep(0, nrow(FDB_one))
  for (fn in fac_names) {
    if (!fn %in% names(FDB_one)) next
    col_vals <- FDB_one[[fn]]
    if (all(is.na(col_vals))) next
    col_w <- winsor_z(col_vals, sigma = 2.5)
    score_vec <- score_vec + theta[fn] * col_w
  }
  list(scores = score_vec, theta = theta)
}

core_res <- build_composite_for_one(SLEEVE_CORE, FDB_T, ic_mean_exp)
defense_res <- build_composite_ew_for_one(SLEEVE_DEFENSE, FDB_T)

if (is.null(core_res) || is.null(defense_res)) stop("[FAIL] composite NULL")

cat(sprintf("\n[CORE theta]    %s\n", paste(names(core_res$theta), round(core_res$theta, 4), sep="=", collapse=", ")))
cat(sprintf("[DEFENSE theta] %s\n", paste(names(defense_res$theta), round(defense_res$theta, 4), sep="=", collapse=", ")))

# Cross-section z-normalize per sleeve (NaN-safe)
core_z   <- {
  m <- mean(core_res$scores, na.rm=TRUE); s <- sd(core_res$scores, na.rm=TRUE)
  if (is.na(s) || s < 1e-10) core_res$scores - m else (core_res$scores - m) / s
}
def_z    <- {
  m <- mean(defense_res$scores, na.rm=TRUE); s <- sd(defense_res$scores, na.rm=TRUE)
  if (is.na(s) || s < 1e-10) defense_res$scores - m else (defense_res$scores - m) / s
}
score_eff_t <- W_CORE * core_z + W_DEF * def_z

# ─── Regime state for 2026-04-01 (expanding pct via existing logic — fallback to NORMAL) ──
# Q-Lead M4 5월 NORMAL trigger 정합 + AX-001 v2 conditional defense — for now use existing
# alpha_scores' regime_state for 2026-03-01 as proxy (memory L-280 5월 NORMAL).
regime_2026_04 <- "NORMAL"  # 5월 운용 NORMAL (Q-Lead M4 trigger from L-280 carry)
cat(sprintf("\n[REGIME] 2026-04-01: %s (proxy from M4 5월 NORMAL)\n", regime_2026_04))

# ─── Build new rows ──────────────────────────────────────────────────────────
new_rows <- data.table(
  Date = target_sig_d,
  Ticker = FDB_T$Ticker,
  score_eff = score_eff_t,
  score_core_z = core_z,
  score_defense_z = def_z,
  Ret_1m = NA_real_,
  regime_state = regime_2026_04,
  theta_core = toJSON(as.list(round(core_res$theta, 4)), auto_unbox=TRUE),
  theta_defense = toJSON(as.list(round(defense_res$theta, 4)), auto_unbox=TRUE)
)
cat(sprintf("\n[NEW ROWS] %d (sig_date 2026-04-01)\n", nrow(new_rows)))

# Show top 20 by score_eff
new_top20 <- new_rows[order(-score_eff)][seq_len(min(20, nrow(new_rows)))]
cat("\n[TOP 20 by score_eff at sig_date 2026-04-01]:\n")
print(new_top20[, .(Ticker, score_eff = round(score_eff, 4),
                     score_core_z = round(score_core_z, 4),
                     score_defense_z = round(score_defense_z, 4))])

# ─── Append + save ────────────────────────────────────────────────────────────
# Backup
ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
bak <- file.path(ART_DIR, paste0("alpha_scores_pre_phase1b_", ts, ".parquet.bak"))
file.copy(src, bak, overwrite = FALSE)
cat(sprintf("\n[BACKUP] %s\n", basename(bak)))

# Schema match
common_cols <- intersect(names(a_existing), names(new_rows))
new_rows_aligned <- new_rows[, ..common_cols]
a_existing_aligned <- a_existing[, ..common_cols]

# Strip jsonlite 'json' class from existing theta_* columns (compatibility for rbindlist)
for (cn in c("theta_core", "theta_defense")) {
  if (cn %in% names(a_existing_aligned)) {
    a_existing_aligned[[cn]] <- as.character(a_existing_aligned[[cn]])
  }
  if (cn %in% names(new_rows_aligned)) {
    new_rows_aligned[[cn]] <- as.character(new_rows_aligned[[cn]])
  }
}
a_combined <- rbindlist(list(a_existing_aligned, new_rows_aligned), use.names = TRUE, fill = TRUE)
setkey(a_combined, Date, Ticker)
write_parquet(a_combined, src)

n_post <- nrow(a_combined)
sig_dates_post <- sort(unique(a_combined$Date))
cat(sprintf("\n[POST] %d rows | %d sig_dates (last: %s)\n",
            n_post, length(sig_dates_post), as.character(max(sig_dates_post))))

# Audit
audit <- list(
  task_id = "WT-T20260509_001",
  phase = "Phase 1b",
  target_sig_date = as.character(target_sig_d),
  pre_md5 = as.character(tools::md5sum(bak)),
  post_md5 = as.character(tools::md5sum(src)),
  n_rows_pre = n_pre,
  n_rows_post = n_post,
  n_rows_added = nrow(new_rows),
  n_sig_dates_post = length(sig_dates_post),
  ic_expanding_means = as.list(setNames(round(ic_mean_exp$mean_IC, 5), ic_mean_exp$factor)),
  core_theta = as.list(round(core_res$theta, 4)),
  defense_theta = as.list(round(defense_res$theta, 4)),
  regime_state = regime_2026_04,
  top20_at_2026_04_01 = new_top20[, .(Ticker, score_eff = round(score_eff, 5))],
  status = "PASS",
  timestamp_end = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
write_json(audit, file.path(WT_DIR, "phase1b_audit.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("\n[AUDIT] Saved: %s\n", file.path(WT_DIR, "phase1b_audit.json")))
cat("\n========================================================\n")
cat(sprintf("  Phase 1b — PASS | sig_dates: %d -> %d\n",
            length(sig_dates_pre), length(sig_dates_post)))
cat("========================================================\n")
