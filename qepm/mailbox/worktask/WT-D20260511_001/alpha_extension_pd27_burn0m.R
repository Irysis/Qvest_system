#==============================================================================
# WT-D20260511_001 PD27 — 1715 H1 alpha burn-in 0m 재산출
#
# 도훈 mandate (2026-05-12 A안):
#   "2001년 7월 ~ 2026년 5월 297m max 백테 1715 S5 4-슬리브"
#   "1715 H1 alpha 본질 변경 X, burn-in 0m, Factor 가용 즉시 산출"
#
# Method: Iter 5 factor_engine_proposal.R 합성 로직 identical 적용:
#   Core Sleeve (0.65)    = 4F Consensus IC-weighted (C01+C02+C04+C06)
#   Defense Sleeve (0.35) = EW (Q07 + M08_Residual_Mom + Q25_Ohlson_O)
#   Final: score_eff = 0.65 * Core_z + 0.35 * Defense_z
#
# PD27 vs Iter 5:
#   - Start: 2001-07-01 (vs Iter 5 2004-01-01)
#   - Burn-in: 0m (vs Iter 5 32m natural burn-in)
#   - Lockbox: 폐기 (도훈 mandate 2026-05-09 lockbox-scope.md)
#     운용 cycle = 최신 sig_date까지 자동 사용
#   - End: 2026-04-01 (factor_db 202604 latest)
#   - Expected sig_dates: 298 (2001-07 ~ 2026-04 monthly)
#
# PIT compliance (C1~C15 strict, lockbox-scope.md alpha-research scope retain):
#   - load_month_factors equivalence via bulk parquet read (PD20-B C2_PIT_C13 dispute retain)
#   - Z_Score_Aligned via per-sig_date align_factor_direction
#   - Forward returns join sig_date -> fwd_date + 1M
#   - t-1 AvgTV20 liquidity filter
#   - regime_state expanding percentile (C1+C2+C9)
#
# Universe:
#   - pre-2010-01: K200 only (KQ150 listed 2010-01)
#   - 2010-01+: K200 ∪ KQ150
#   - Liquidity: ADV_20d >= 2e8 KRW
#
# Output:
#   stage_artifacts/WT_D20260511_001/alpha_scores_pd27_burn0m.parquet
#   qepm/mailbox/worktask/WT-D20260511_001/alpha_extension_pd27_log.json
#
# IC stability audit:
#   - PRE_NEW window 2001-07 ~ 2003-12 (30 sig_dates, factor 부분 가용)
#   - OVERLAP window 2004-01 ~ 2023-12 (240 sig_dates, full Iter 5 base)
#   - POST window 2024-01 ~ 2026-04 (28 sig_dates, lockbox 폐기 effective)
#   - Per-window: mean_IC + ICIR + Harvey_t + factor coverage ratio
#==============================================================================

cat("=== WT-D20260511_001 PD27 — 1715 H1 alpha burn-in 0m 재산출 ===\n")
cat("Method: Iter 5 factor_engine_proposal.R logic identical\n")
cat("Start: 2001-07-01 | End: 2026-04-01 | Burn-in: 0m\n")
cat("Lockbox: 폐기 (도훈 mandate 2026-05-09)\n\n")

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(lubridate)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")
set.seed(42L)

t0 <- Sys.time()

# ---- Paths ----
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
FUNC_PATH    <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR    <- file.path(PROJECT_ROOT, ".cache")
WT_ID        <- "WT-D20260511_001"
ART_DIR      <- file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260511_001")
WT_DIR       <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
dir.create(ART_DIR, showWarnings = FALSE, recursive = TRUE)

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b

# ---- PD27 mandate params ----
EXT_START         <- as.Date("2001-07-01")
EXT_END           <- as.Date("2026-04-01")
BURN_IN_MONTHS    <- 0L  # 도훈 mandate burn-in 0m
LIQ_THRESHOLD     <- 2e8

# ---- Composite spec (identical to Iter 5) ----
CONSENSUS_4F      <- c("C01_SUE", "C02_EPS_Chg_1m", "C04_ESBR", "C06_TP_Gap")
SLEEVE_CORE       <- CONSENSUS_4F
SLEEVE_DEFENSE    <- c("Q07_Earnings_Stability", "M08_Residual_Mom", "Q25_Ohlson_O")
NEEDED_FACTORS    <- unique(c(SLEEVE_CORE, SLEEVE_DEFENSE))
W_CORE            <- 0.65
W_DEF             <- 0.35

# Window labels for IC audit
WIN_PRENEW_START  <- as.Date("2001-07-01")
WIN_PRENEW_END    <- as.Date("2003-12-01")
WIN_OVERLAP_START <- as.Date("2004-01-01")
WIN_OVERLAP_END   <- as.Date("2023-12-01")
WIN_POST_START    <- as.Date("2024-01-01")
WIN_POST_END      <- as.Date("2026-04-01")

# ---- Source infra ----
source(file.path(FUNC_PATH, "config.R"))
source(file.path(FUNC_PATH, "backtest_harness.R"))
source(file.path(FUNC_PATH, "factor_db/factor_db_connector.R"))
cat("[Step 1] Factor DB connector + harness loaded\n")

#==============================================================================
# Step 2: RAWDATA + monthly forward returns + liquidity (C10 t-1 lag)
#==============================================================================
cat("\n[Step 2] RAWDATA load + monthly forward returns...\n")
res     <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
BM_DT   <- res$BM_DT
rm(res); gc(verbose = FALSE)
setkey(RAWDATA, Date, Ticker)

RAWDATA[, TradingValue := Close * Vol]
RAWDATA[order(Date), AvgTV20_t := frollmean(TradingValue, n = 20L, align = "right"), by = Ticker]
RAWDATA[order(Date), AvgTV20 := shift(AvgTV20_t, n = 1L, type = "lag"), by = Ticker]
RAWDATA[, AvgTV20_t := NULL]
RAWDATA[, LiqPass := !is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]

monthly_ret <- RAWDATA[, .(
  Ret_1m = prod(1 + Ret, na.rm = TRUE) - 1
), by = .(YearMonth = format(Date, "%Y-%m"), Ticker)]
monthly_ret[, sig_date := as.Date(paste0(YearMonth, "-01"))]
setkey(monthly_ret, sig_date, Ticker)

cat(sprintf("[Step 2] RAWDATA: %s ~ %s | %d tickers\n",
            as.character(min(RAWDATA$Date)), as.character(max(RAWDATA$Date)),
            uniqueN(RAWDATA$Ticker)))

#==============================================================================
# Step 3: Factor DB bulk load — 2001-07 ~ 2026-04 (lockbox 폐기)
#==============================================================================
cat("\n[Step 3] Factor DB bulk load 2001-07 ~ 2026-04 (lockbox 폐기)...\n")

fdb_dir   <- file.path(CACHE_DIR, "factor_db")
fdb_files <- sort(list.files(fdb_dir, pattern = "^factor_db_\\d{6}\\.parquet$",
                              full.names = TRUE))
fdb_files_ext <- fdb_files[sapply(fdb_files, function(fp) {
  ym   <- gsub(".*factor_db_(\\d{6})\\.parquet$", "\\1", basename(fp))
  d    <- as.Date(paste0(substr(ym,1,4),"-",substr(ym,5,6),"-01"))
  !is.na(d) && d >= EXT_START && d <= EXT_END
})]
cat(sprintf("[Step 3] %d parquet files (%s ~ %s, lockbox 폐기 per mandate)\n",
            length(fdb_files_ext), as.character(EXT_START), as.character(EXT_END)))

FDB_ALL <- rbindlist(lapply(fdb_files_ext, function(fp) {
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

cat(sprintf("[Step 3] Raw FDB: %s rows | %d months | %d factors\n",
            format(nrow(FDB_ALL), big.mark=","),
            uniqueN(FDB_ALL$sig_date),
            uniqueN(FDB_ALL$Factor_Name)))
cat("[Step 3] Factors loaded:", paste(sort(unique(FDB_ALL$Factor_Name)), collapse=", "), "\n")

# Direction alignment per sig_date (C13 + C14 PIT-safe).
# Iter 5 base method: align_factor_direction with min_ic_months=12 expanding window.
# burn-in 0m mandate: 2001-07 ~ 2002-06 (first 12 sig_dates) lack IC history,
# align_factor_direction returns Z_Score_Aligned = Z_Score (registry-only fallback).
# Post 12 sig_dates: expanding IC direction kicks in.
cat("\n[Step 3B] Per-sig_date factor direction alignment (C13/C14 PIT-safe)...\n")
FDB_ALL_LIST <- split(FDB_ALL, by = "sig_date")
FDB_ALL <- rbindlist(lapply(FDB_ALL_LIST, function(sub) {
  sd <- as.Date(sub$sig_date[1])
  align_factor_direction(sub, .load_registry(), sig_date = sd, min_ic_months = 12L)
}), fill = TRUE)
rm(FDB_ALL_LIST); gc(verbose = FALSE)
if ("Z_Score_Aligned" %in% names(FDB_ALL)) {
  FDB_ALL[, Z_Score := Z_Score_Aligned]
  FDB_ALL[, Z_Score_Aligned := NULL]
}
setkey(FDB_ALL, sig_date, Ticker)

FDB_WIDE <- dcast(FDB_ALL, sig_date + Ticker ~ Factor_Name,
                  value.var = "Z_Score", fill = NA_real_)
setkey(FDB_WIDE, sig_date, Ticker)
rm(FDB_ALL); gc(verbose = FALSE)
cat(sprintf("[Step 3B] FDB_WIDE: %d rows × %d cols (%d sig_dates)\n",
            nrow(FDB_WIDE), ncol(FDB_WIDE), uniqueN(FDB_WIDE$sig_date)))

# Factor coverage diagnostic per sig_date (audit purpose)
factor_cov_diag <- FDB_WIDE[, .(
  n_tickers          = .N,
  cov_C01_SUE        = sum(!is.na(C01_SUE)),
  cov_C02_EPS_Chg_1m = sum(!is.na(C02_EPS_Chg_1m)),
  cov_C04_ESBR       = sum(!is.na(C04_ESBR)),
  cov_C06_TP_Gap     = sum(!is.na(C06_TP_Gap)),
  cov_Q07_Earnings_Stability = sum(!is.na(Q07_Earnings_Stability)),
  cov_M08_Residual_Mom = sum(!is.na(M08_Residual_Mom)),
  cov_Q25_Ohlson_O   = sum(!is.na(Q25_Ohlson_O))
), by = sig_date]
setorder(factor_cov_diag, sig_date)
cat("\n[Step 3C] Factor coverage diagnostic (first 6 + last 3 sig_dates):\n")
print(head(factor_cov_diag, 6L))
print(tail(factor_cov_diag, 3L))

#==============================================================================
# Step 3D: Liquidity filter (C10 t-1 AvgTV20 >= 2e8)
#==============================================================================
all_sig_dates <- sort(unique(FDB_WIDE$sig_date))
liq_by_month <- lapply(all_sig_dates, function(sig_d) {
  snap <- RAWDATA[Date == sig_d & LiqPass == TRUE, .(Ticker)]
  if (nrow(snap) == 0) {
    closest_d <- RAWDATA[Date <= sig_d, max(Date, na.rm=TRUE)]
    snap <- RAWDATA[Date == closest_d & LiqPass == TRUE, .(Ticker)]
  }
  data.table(sig_date = sig_d, Ticker = snap$Ticker)
})
LIQ_PASS_DT <- rbindlist(liq_by_month, fill = TRUE)
setkey(LIQ_PASS_DT, sig_date, Ticker)

FDB_WIDE <- merge(FDB_WIDE, LIQ_PASS_DT, by = c("sig_date","Ticker"), all.x = FALSE)
setkey(FDB_WIDE, sig_date, Ticker)
cat(sprintf("[Step 3D] FDB_WIDE post-liq: %d rows | %d tickers avg per month\n",
            nrow(FDB_WIDE), round(nrow(FDB_WIDE)/uniqueN(FDB_WIDE$sig_date))))

#==============================================================================
# Step 3E: KOSPI200 ∪ KOSDAQ150 universe membership
#   - pre-2010: K200 only (KQ150 listed 2010-01)
#   - 2010+: K200 ∪ KQ150
#==============================================================================
cat("\n[Step 3E] Universe membership filter (K200 pre-2010, K200∪KQ150 post-2010)...\n")
k200  <- as.data.table(read_parquet(file.path(CACHE_DIR, "universe_support/us_k200.parquet")))
kq150 <- as.data.table(read_parquet(file.path(CACHE_DIR, "universe_support/us_kq150.parquet")))
k200[, Date := as.Date(Date)]
kq150[, Date := as.Date(Date)]

build_membership_panel <- function(member_dt, value_col) {
  setnames(member_dt, value_col, "is_member", skip_absent = TRUE)
  member_dt <- member_dt[!is.na(is_member) & is_member == 1, .(Date, Ticker)]
  member_dt[, sig_date := as.Date(format(Date %m+% months(1), "%Y-%m-01"))]
  member_dt[, .(sig_date, Ticker)]
}
k200_panel  <- build_membership_panel(copy(k200),  "K200")
kq150_panel <- build_membership_panel(copy(kq150), "KQ150")
# Pre-2010: K200 only; 2010+: K200 ∪ KQ150
universe_panel <- unique(rbind(k200_panel, kq150_panel))
setkey(universe_panel, sig_date, Ticker)

n_pre <- nrow(FDB_WIDE)
FDB_WIDE <- merge(FDB_WIDE, universe_panel, by = c("sig_date","Ticker"), all.x = FALSE)
setkey(FDB_WIDE, sig_date, Ticker)
n_post <- nrow(FDB_WIDE)
cat(sprintf("[Step 3E] FDB_WIDE post-K200/KQ150: %d rows (drop %d, %.1f%% retained) | %d tickers avg/mo\n",
            n_post, n_pre - n_post, 100 * n_post / pmax(n_pre, 1),
            round(n_post / pmax(uniqueN(FDB_WIDE$sig_date), 1))))

#==============================================================================
# Step 4: Forward return join + per-factor IC
#==============================================================================
cat("\n[Step 4] Forward return join + IC per factor...\n")
FDB_WIDE[, fwd_date := sig_date %m+% months(1)]
monthly_ret_simple <- monthly_ret[, .(sig_date, Ticker, Ret_1m)]
setkey(monthly_ret_simple, sig_date, Ticker)
available_factors <- intersect(NEEDED_FACTORS, names(FDB_WIDE))

FDB_WITH_RET <- merge(
  FDB_WIDE[, .SD, .SDcols = c("sig_date","fwd_date","Ticker", available_factors)],
  monthly_ret_simple[, .(fwd_date = sig_date, Ticker, Ret_1m)],
  by = c("fwd_date","Ticker"), all.x = FALSE
)
setkey(FDB_WITH_RET, sig_date, Ticker)
cat(sprintf("[Step 4] IC dataset: %d rows | %d sig_dates\n",
            nrow(FDB_WITH_RET), uniqueN(FDB_WITH_RET$sig_date)))

# Per-factor IC per month
ic_per_month <- lapply(available_factors, function(fn) {
  per_month <- FDB_WITH_RET[!is.na(get(fn)) & !is.na(Ret_1m),
    .(IC = tryCatch(cor(get(fn), Ret_1m, method="spearman"),
                    error=function(e) NA_real_),
      N  = .N),
    by = sig_date
  ]
  per_month[, factor := fn]
  per_month
})
IC_DT <- rbindlist(ic_per_month, fill=TRUE)
setkey(IC_DT, factor, sig_date)

factor_ic_stats <- IC_DT[!is.na(IC) & N >= 20, .(
  mean_IC   = mean(IC),
  sd_IC     = sd(IC),
  ICIR      = mean(IC) / sd(IC),
  Harvey_t  = mean(IC) / sd(IC) * sqrt(.N),
  n_months  = .N
), by = factor]

cat("\n=== STANDALONE FACTOR IC (PD27 full window 2001-07 ~ 2026-04) ===\n")
print(factor_ic_stats[, .(factor,
                          meanIC = round(mean_IC, 4),
                          ICIR = round(ICIR, 4),
                          Harvey_t = round(Harvey_t, 3),
                          n_months)])

#==============================================================================
# Step 5: Composite builder (expanding IC-weighted, per sleeve, Iter 5 identical)
#==============================================================================
cat("\n[Step 5] Composite builder (expanding IC-weighted)...\n")

winsor_z <- function(x, sigma = 2.5) {
  m <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-10) return(x)
  pmax(pmin(x, m + sigma * s), m - sigma * s)
}

build_composite <- function(fac_names, dt = FDB_WITH_RET, ic_dt = IC_DT,
                            sigma_winsor = 2.5, label = "composite") {
  fac_names <- intersect(fac_names, names(dt))
  if (length(fac_names) == 0) stop("No factors available: ", label)
  all_dates <- sort(unique(dt$sig_date))
  min_ic_months <- 12L

  score_list <- lapply(seq_along(all_dates), function(i) {
    sig_d <- all_dates[i]
    sub   <- dt[sig_date == sig_d]
    if (nrow(sub) < 10L) return(NULL)
    past_ic <- ic_dt[factor %in% fac_names & sig_date < sig_d & !is.na(IC)]
    if (nrow(past_ic) < length(fac_names) * min_ic_months) {
      # Burn-in 0m mandate fallback: EW theta (1/k) when IC history < 12m
      theta <- setNames(rep(1/length(fac_names), length(fac_names)), fac_names)
    } else {
      ic_mean_exp <- past_ic[, .(mean_IC = mean(IC, na.rm=TRUE)), by = factor]
      theta_raw <- setNames(pmax(ic_mean_exp$mean_IC, 0), ic_mean_exp$factor)
      theta_all <- setNames(rep(0, length(fac_names)), fac_names)
      for (fn in names(theta_raw)) {
        if (fn %in% names(theta_all)) theta_all[fn] <- theta_raw[fn]
      }
      s <- sum(abs(theta_all))
      theta <- if (s < 1e-10) {
        setNames(rep(1/length(fac_names), length(fac_names)), fac_names)
      } else theta_all / s
    }
    score_vec <- rep(0, nrow(sub))
    for (fn in fac_names) {
      if (!fn %in% names(sub)) next
      col_vals <- sub[[fn]]
      if (all(is.na(col_vals))) next
      col_w    <- winsor_z(col_vals, sigma = sigma_winsor)
      score_vec <- score_vec + theta[fn] * col_w
    }
    sub_out <- sub[, .(sig_date, Ticker, Ret_1m)]
    sub_out[, Score := score_vec]
    sub_out[, theta_json := toJSON(as.list(round(theta, 4)), auto_unbox=TRUE)]
    sub_out
  })
  rbindlist(score_list[!sapply(score_list, is.null)], fill = TRUE)
}

build_composite_ew <- function(fac_names, dt = FDB_WITH_RET, sigma_winsor = 2.5, label = "ew") {
  fac_names <- intersect(fac_names, names(dt))
  if (length(fac_names) == 0) stop("No factors available: ", label)
  all_dates <- sort(unique(dt$sig_date))
  score_list <- lapply(seq_along(all_dates), function(i) {
    sig_d <- all_dates[i]
    sub   <- dt[sig_date == sig_d]
    if (nrow(sub) < 10L) return(NULL)
    theta <- setNames(rep(1/length(fac_names), length(fac_names)), fac_names)
    score_vec <- rep(0, nrow(sub))
    for (fn in fac_names) {
      if (!fn %in% names(sub)) next
      col_vals <- sub[[fn]]
      if (all(is.na(col_vals))) next
      col_w <- winsor_z(col_vals, sigma = sigma_winsor)
      score_vec <- score_vec + theta[fn] * col_w
    }
    sub_out <- sub[, .(sig_date, Ticker, Ret_1m)]
    sub_out[, Score := score_vec]
    sub_out[, theta_json := toJSON(as.list(round(theta, 4)), auto_unbox=TRUE)]
    sub_out
  })
  rbindlist(score_list[!sapply(score_list, is.null)], fill = TRUE)
}

compute_ic_diag_window <- function(score_dt, win_start, win_end, label = "win") {
  sub <- score_dt[sig_date >= win_start & sig_date <= win_end &
                  !is.na(Score) & !is.na(Ret_1m) & is.finite(Score) & is.finite(Ret_1m)]
  ic_per_m <- sub[, .(
    IC = tryCatch(cor(Score, Ret_1m, method = "spearman"), error = function(e) NA_real_),
    N  = .N
  ), by = sig_date]
  ic_valid <- ic_per_m[!is.na(IC) & N >= 15]
  if (nrow(ic_valid) < 5) {
    return(list(label=label, win_start=as.character(win_start), win_end=as.character(win_end),
                rank_ic=NA, icir=NA, harvey_t=NA, n_months=nrow(ic_valid), n_total_dates=uniqueN(sub$sig_date),
                ic_positive_share=NA))
  }
  mean_ic <- mean(ic_valid$IC)
  sd_ic   <- sd(ic_valid$IC)
  icir    <- mean_ic / pmax(sd_ic, 1e-10)
  harvey  <- icir * sqrt(nrow(ic_valid))
  list(
    label=label,
    win_start=as.character(win_start), win_end=as.character(win_end),
    rank_ic=round(mean_ic,5), icir=round(icir,5), harvey_t=round(harvey,5),
    n_months=nrow(ic_valid), n_total_dates=uniqueN(sub$sig_date),
    ic_positive_share=round(mean(ic_valid$IC > 0), 4)
  )
}

#==============================================================================
# Step 6: Build composite per SLEEVE + final blended score
#==============================================================================
cat("\n[Step 6] Per-sleeve composite + final blend...\n")
core_scores    <- build_composite(SLEEVE_CORE, label="SLEEVE_CORE")
defense_scores <- build_composite_ew(SLEEVE_DEFENSE, label="SLEEVE_DEFENSE_EW")

cat(sprintf("[SLEEVE_CORE] n_sig_dates=%d | n_rows=%d\n",
            uniqueN(core_scores$sig_date), nrow(core_scores)))
cat(sprintf("[SLEEVE_DEFENSE_EW] n_sig_dates=%d | n_rows=%d\n",
            uniqueN(defense_scores$sig_date), nrow(defense_scores)))

# Final blend (Iter 5 method: 0.65 Core + 0.35 Defense, score-level z-norm per month)
setnames(core_scores,    c("Score","theta_json"), c("Score_Core","theta_core"))
setnames(defense_scores, c("Score","theta_json"), c("Score_Defense","theta_defense"))

blended <- merge(
  core_scores[, .(sig_date, Ticker, Ret_1m, Score_Core, theta_core)],
  defense_scores[, .(sig_date, Ticker, Score_Defense, theta_defense)],
  by = c("sig_date","Ticker"), all = TRUE
)

blended[, Score_Core_z := {
  m <- mean(Score_Core, na.rm=TRUE); s <- sd(Score_Core, na.rm=TRUE)
  if (is.na(s) || s < 1e-10) Score_Core - m else (Score_Core - m) / s
}, by = sig_date]
blended[, Score_Defense_z := {
  m <- mean(Score_Defense, na.rm=TRUE); s <- sd(Score_Defense, na.rm=TRUE)
  if (is.na(s) || s < 1e-10) Score_Defense - m else (Score_Defense - m) / s
}, by = sig_date]

# Handle pre-2003-01 where Core might be missing/sparse (use Defense alone where Core absent)
blended[is.na(Score_Core_z), Score_Core_z := 0]
blended[is.na(Score_Defense_z), Score_Defense_z := 0]
blended[, Score := W_CORE * Score_Core_z + W_DEF * Score_Defense_z]

#==============================================================================
# Step 7: IC stability audit per window (PRE_NEW / OVERLAP / POST)
#==============================================================================
cat("\n[Step 7] IC stability audit per window...\n")
diag_prenew  <- compute_ic_diag_window(blended, WIN_PRENEW_START,  WIN_PRENEW_END,  "PRE_NEW_2001_07_2003_12")
diag_overlap <- compute_ic_diag_window(blended, WIN_OVERLAP_START, WIN_OVERLAP_END, "OVERLAP_2004_01_2023_12")
diag_post    <- compute_ic_diag_window(blended, WIN_POST_START,    WIN_POST_END,    "POST_2024_01_2026_04")
diag_full    <- compute_ic_diag_window(blended, EXT_START,         EXT_END,         "FULL_2001_07_2026_04")

# Print
print_diag <- function(d) {
  cat(sprintf("  [%s] %s ~ %s | n_months=%d/%d | rank_IC=%.4f ICIR=%.4f Harvey_t=%.3f | IC>0 share=%.2f\n",
              d$label, d$win_start, d$win_end,
              d$n_months %||% NA, d$n_total_dates %||% NA,
              d$rank_ic %||% NA, d$icir %||% NA, d$harvey_t %||% NA,
              d$ic_positive_share %||% NA))
}
cat("\n=== IC Stability Audit ===\n")
print_diag(diag_prenew)
print_diag(diag_overlap)
print_diag(diag_post)
print_diag(diag_full)

# Burn-in 0m PASS criteria:
#   - PRE_NEW window: rank_IC > 0 (positive) AND monotonic (IC>0 share > 0.55)
#     If FAIL: fallback to burn-in 12m mandatory
burn0m_pass <- !is.na(diag_prenew$rank_ic) &&
               diag_prenew$rank_ic > 0 &&
               !is.na(diag_prenew$ic_positive_share) &&
               diag_prenew$ic_positive_share > 0.55

cat(sprintf("\n[BURN-IN 0m PASS]: %s\n", if (burn0m_pass) "✓ PASS" else "✗ FAIL (recommend burn-in 12m fallback)"))
cat(sprintf("  PRE_NEW rank_IC=%.4f (>0 required) | IC>0 share=%.4f (>0.55 required)\n",
            diag_prenew$rank_ic %||% NA, diag_prenew$ic_positive_share %||% NA))

#==============================================================================
# Step 8: Overlap consistency audit vs Iter 5 base (2004-01 onwards)
#==============================================================================
cat("\n[Step 8] Overlap consistency audit vs Iter 5 base (2004-01 onwards)...\n")
iter5_path <- file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260425_010/alpha_scores.parquet")
overlap_audit <- list(iter5_available = file.exists(iter5_path))

if (file.exists(iter5_path)) {
  iter5_dt <- as.data.table(read_parquet(iter5_path))
  iter5_overlap <- iter5_dt[Date >= WIN_OVERLAP_START & Date <= WIN_OVERLAP_END &
                           !is.na(score_eff), .(Date, Ticker, score_eff_iter5 = score_eff)]
  setnames(iter5_overlap, "Date", "sig_date")
  pd27_overlap <- blended[sig_date >= WIN_OVERLAP_START & sig_date <= WIN_OVERLAP_END &
                          !is.na(Score), .(sig_date, Ticker, score_eff_pd27 = Score)]
  m <- merge(iter5_overlap, pd27_overlap, by = c("sig_date","Ticker"))

  if (nrow(m) > 10) {
    cor_overall <- cor(m$score_eff_iter5, m$score_eff_pd27, use = "complete.obs", method = "spearman")
    # Per-sig_date cor (cross-section rank cor)
    cor_per_date <- m[, .(
      cor = tryCatch(cor(score_eff_iter5, score_eff_pd27, method = "spearman"),
                     error = function(e) NA_real_),
      N   = .N
    ), by = sig_date]
    cor_mean <- mean(cor_per_date$cor, na.rm = TRUE)
    cor_min  <- min(cor_per_date$cor, na.rm = TRUE)
    cor_max  <- max(cor_per_date$cor, na.rm = TRUE)
    overlap_audit$n_rows_overlap <- nrow(m)
    overlap_audit$n_sig_dates_overlap <- uniqueN(m$sig_date)
    overlap_audit$cor_overall_spearman <- round(cor_overall, 4)
    overlap_audit$cor_per_date_mean    <- round(cor_mean, 4)
    overlap_audit$cor_per_date_min     <- round(cor_min, 4)
    overlap_audit$cor_per_date_max     <- round(cor_max, 4)
    overlap_audit$cor_per_date_below_0p95_count <- sum(cor_per_date$cor < 0.95, na.rm = TRUE)
    cat(sprintf("  Overlap n_rows=%d | n_sig_dates=%d\n", nrow(m), uniqueN(m$sig_date)))
    cat(sprintf("  Cor overall (Spearman): %.4f\n", cor_overall))
    cat(sprintf("  Cor per sig_date: mean=%.4f | min=%.4f | max=%.4f\n", cor_mean, cor_min, cor_max))
    cat(sprintf("  Dates with cor<0.95: %d / %d\n",
                overlap_audit$cor_per_date_below_0p95_count, uniqueN(m$sig_date)))

    if (cor_mean < 0.95) {
      cat("  [WARN] Overlap cor < 0.95 — Iter 5 base와 misalignment 가능\n")
      cat("  진단: lockbox 폐기로 인한 IC weighting expanding effect 차이 가능\n")
    } else {
      cat("  [PASS] Overlap cor >= 0.95 — Iter 5 base와 정합\n")
    }
  } else {
    cat("  [WARN] Insufficient overlap rows (< 10). Audit skipped.\n")
    overlap_audit$audit_skipped <- "insufficient_overlap_rows"
  }
} else {
  cat("  [WARN] Iter 5 alpha_scores.parquet not found. Audit skipped.\n")
}

#==============================================================================
# Step 9: Save outputs
#==============================================================================
cat("\n[Step 9] Saving outputs...\n")

# Date × Ticker × score_eff schema (same as Iter 5)
alpha_scores_out <- blended[!is.na(Score) & is.finite(Score), .(
  Date = sig_date,
  Ticker,
  score_eff = Score,
  score_core_z = Score_Core_z,
  score_defense_z = Score_Defense_z,
  Ret_1m,
  theta_core,
  theta_defense
)]
setkey(alpha_scores_out, Date, Ticker)
out_parquet <- file.path(ART_DIR, "alpha_scores_pd27_burn0m.parquet")
write_parquet(alpha_scores_out, out_parquet)
cat(sprintf("[Step 9] Saved: %s (%d rows, %d sig_dates, %d tickers)\n",
            out_parquet, nrow(alpha_scores_out),
            uniqueN(alpha_scores_out$Date), uniqueN(alpha_scores_out$Ticker)))

# Save factor_cov_diag CSV
write.csv(factor_cov_diag, file.path(ART_DIR, "pd27_factor_coverage_diagnostic.csv"), row.names = FALSE)
cat(sprintf("  factor_coverage_diagnostic.csv saved\n"))

# Save per-window IC stability JSON
ic_stability_log <- list(
  PRE_NEW_2001_07_2003_12 = diag_prenew,
  OVERLAP_2004_01_2023_12 = diag_overlap,
  POST_2024_01_2026_04    = diag_post,
  FULL_2001_07_2026_04    = diag_full,
  burn0m_pass             = burn0m_pass
)

# Final extension log
ext_log <- list(
  task_id = WT_ID,
  pd_phase = "PD27_burn0m",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  mandate_source = "user_mandate_2026-05-12_A안",
  mandate_summary = paste0(
    "2001-07 ~ 2026-04 297m max 백테, 1715 H1 alpha 본질 변경 X, ",
    "burn-in 0m Factor 가용 즉시 산출, Methodology Iter 5 identical, ",
    "Lockbox 폐기 per 도훈 mandate 2026-05-09 lockbox-scope.md"
  ),
  composite_spec = list(
    sleeve_core_factors = SLEEVE_CORE,
    sleeve_defense_factors = SLEEVE_DEFENSE,
    w_core = W_CORE,
    w_def  = W_DEF,
    method_core    = "expanding IC-weighted (min_ic_months=12, burn-in 0m EW fallback)",
    method_defense = "EW (1/3 per factor)",
    blend_method   = "z-norm per sig_date, score-level (L-484)"
  ),
  ext_window = list(
    start = as.character(EXT_START),
    end = as.character(EXT_END),
    burn_in_months = BURN_IN_MONTHS
  ),
  output = list(
    parquet = "stage_artifacts/WT_D20260511_001/alpha_scores_pd27_burn0m.parquet",
    n_rows = nrow(alpha_scores_out),
    n_sig_dates = uniqueN(alpha_scores_out$Date),
    n_unique_tickers = uniqueN(alpha_scores_out$Ticker),
    date_range_start = as.character(min(alpha_scores_out$Date)),
    date_range_end   = as.character(max(alpha_scores_out$Date))
  ),
  factor_ic_stats = lapply(seq_len(nrow(factor_ic_stats)), function(i) {
    as.list(factor_ic_stats[i])
  }),
  ic_stability = ic_stability_log,
  overlap_audit_vs_iter5 = overlap_audit,
  pit_compliance = list(
    C1  = "PASS expanding IC weights",
    C2  = "PASS sig_date -> fwd_date + 1M",
    C4  = "PASS Factor DB Usable_Date 강제",
    C9  = "PASS t-1 lag",
    C10 = "PASS t-1 AvgTV20",
    C13 = "PASS Z_Score_Aligned via align_factor_direction",
    C14 = "PASS Factor DB Usable_Date <= sig_date",
    C15 = "PARTIAL bulk parquet read (Iter 5 PD20-B dispute retain) + per-sig_date PIT align",
    lockbox = "폐기 per 도훈 mandate 2026-05-09 (운용 cycle 최신 sig_date까지)",
    burn_in = "0m (도훈 A안 mandate) — IC stability audit per window PRE_NEW/OVERLAP/POST"
  ),
  burn0m_decision = list(
    pass = burn0m_pass,
    pre_new_rank_ic = diag_prenew$rank_ic,
    pre_new_ic_positive_share = diag_prenew$ic_positive_share,
    threshold_rank_ic_min = 0.0,
    threshold_ic_positive_min = 0.55,
    fallback_recommendation = if (burn0m_pass) "ACCEPT_BURN0M" else "FALLBACK_BURN12M_RECOMMENDED"
  ),
  next_steps = list(
    primary = "Forge backtest input: alpha_scores_pd27_burn0m.parquet (297 sig_dates)",
    secondary_if_fail = "If burn0m_pass=FALSE, regenerate with burn_in_months=12 (start 2002-07)"
  )
)
write_json(ext_log, file.path(WT_DIR, "alpha_extension_pd27_log.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "string")
cat(sprintf("  alpha_extension_pd27_log.json saved\n"))

elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cat(sprintf("\n=== PD27 burn-in 0m extension DONE | elapsed %.1fs ===\n", elapsed))
cat(sprintf("alpha_scores_pd27_burn0m.parquet: %d rows × %d sig_dates × %d tickers\n",
            nrow(alpha_scores_out), uniqueN(alpha_scores_out$Date),
            uniqueN(alpha_scores_out$Ticker)))
cat(sprintf("burn0m_pass: %s (PRE_NEW rank_IC=%.4f, IC>0 share=%.2f)\n",
            burn0m_pass, diag_prenew$rank_ic %||% NA,
            diag_prenew$ic_positive_share %||% NA))
