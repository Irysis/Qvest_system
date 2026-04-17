cat("=== Cycle 1: RQ-1 + RQ-2 + RQ-3 + RQ-10 (MDD 3경로 + C19 분해) ===\n")
t0_total <- Sys.time()

suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/backtest_harness.R")
  source("02_Infrastructure/factor_db_connector.R")
})
library(data.table); library(arrow)

FACTOR_DB_DIR <- file.path(CACHE_DIR, "factor_db")

# ══════════════════════════════════════════════════════════════════
# SHARED DATA
# ══════════════════════════════════════════════════════════════════
cat("[OPT] Shared data loading...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res)
setkey(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y%m")]

monthly_last <- RAWDATA[, .(sig_date = max(Date)), by = YM]
setkey(monthly_last, YM)
month_ends <- sort(monthly_last$sig_date)
month_ends <- month_ends[month_ends >= as.Date("2006-01-01")]
ym_list <- format(month_ends, "%Y%m")

# LIQ (C10: t-1 lag)
RAWDATA[, TV := Close * Vol]
LIQ_RAW <- RAWDATA[, .(AvgTV20 = mean(tail(TV, 20), na.rm = TRUE)), by = .(Ticker, YM)]
ym_all_liq <- sort(unique(LIQ_RAW$YM))
ym_shift <- data.table(YM_prev = ym_all_liq[-length(ym_all_liq)],
                       YM_use = ym_all_liq[-1])
LIQ_MONTHLY <- merge(LIQ_RAW, ym_shift, by.x = "YM", by.y = "YM_prev")
LIQ_MONTHLY <- LIQ_MONTHLY[, .(Ticker, YM = YM_use, AvgTV20)]
setkey(LIQ_MONTHLY, Ticker, YM)
rm(LIQ_RAW, ym_shift)

# Factor DB
CYC1_NEEDED <- c("C19_Composite_Earnings", "C01_SUE", "C04_ESBR",
                  "C02_EPS_Chg_1m", "C06_TP_Gap",
                  "Q01_GPA", "Q08_Composite_Quality",
                  "D01_IdioVol", "M05_Trended_Mom",
                  "XF_LL05_WorkingCapital", "XF_RI02_CapEx_proxy", "XF_A02_NOA")
fdb_files <- list.files(FACTOR_DB_DIR, pattern = "^factor_db_\\d{6}\\.parquet$",
                        full.names = TRUE)
FDB_ALL <- rbindlist(lapply(fdb_files, function(f) {
  dt <- as.data.table(read_parquet(f))
  dt[, YM := gsub(".*factor_db_(\\d{6})\\.parquet", "\\1", f)]
  dt[Factor_Name %in% CYC1_NEEDED]
}), fill = TRUE)
registry <- jsonlite::fromJSON(file.path(FACTOR_DB_DIR, "factor_registry.json"))
FDB_ALL <- align_factor_direction(FDB_ALL, registry)
setkey(FDB_ALL, YM, Ticker, Factor_Name)

# MAX_Ret
MAX_RET <- RAWDATA[, .(MAX_Ret = max(Ret, na.rm = TRUE)), by = .(Ticker, YM)]
setkey(MAX_RET, Ticker, YM)

# Regime
regime_dt <- tryCatch({
  dt <- as.data.table(read_parquet(file.path(CACHE_DIR, "regime_daily_v2.parquet")))
  dt[, Date := as.Date(Date)]
  dt[, regime_q := cut(MRS,
    breaks = quantile(MRS, c(0, .25, .5, .75, 1), na.rm = TRUE),
    labels = c("CALM", "NORMAL", "CAUTION", "CRISIS"), include.lowest = TRUE)]
  dt
}, error = function(e) NULL)

RAWDATA[, c("YM", "TV") := NULL]
gc(verbose = FALSE)
cat(sprintf("[OPT] Ready. FDB: %.0fMB\n\n", object.size(FDB_ALL) / 1e6))

# Helpers
get_wide <- function(ym, factors = CYC1_NEEDED) {
  fdt <- FDB_ALL[YM == ym & Factor_Name %in% factors]
  if (nrow(fdt) == 0) return(NULL)
  fdt_w <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  liq <- LIQ_MONTHLY[YM == ym]
  fdt_w <- merge(fdt_w, liq, by = "Ticker")
  fdt_w[!is.na(AvgTV20) & AvgTV20 >= 2e8]
}

get_regime <- function(sig_d) {
  if (is.null(regime_dt)) return("NORMAL")
  row <- regime_dt[Date <= sig_d][.N]
  if (nrow(row) > 0) as.character(row$regime_q) else "NORMAL"
}

run_save <- function(FACTORS, name, out_dir, n_hold = 30L, wm = "equal") {
  if (nrow(FACTORS) == 0) { cat("  SKIP\n"); return(NULL) }
  setorder(FACTORS, Date, -Score)
  sim <- tryCatch(
    run_monthly_simulation(RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS,
      n_holdings = n_hold, weight_method = wm, commission = 0.0015,
      buffer_zone = list(keep_n = as.integer(n_hold * 1.5), entry_n = as.integer(n_hold * 0.8))),
    error = function(e) { cat(sprintf("  ERROR: %s\n", e$message)); NULL })
  if (is.null(sim)) return(NULL)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  perf <- summarise_perf(sim$strategy_xts, name)
  cat(sprintf("  %s: SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n",
              name, perf$Sharpe, perf$CAGR, perf$MDD))
  saveRDS(sim, file.path(out_dir, "sim_result.rds"))
  tryCatch(generate_charts(sim, output_dir = out_dir, strategy_name = name),
           error = function(e) NULL)
  fwrite(perf, file.path(out_dir, "performance.csv"))
  rm(sim); gc(verbose = FALSE)
  perf
}

# C19 + MAX exclusion baseline FACTORS (공통 사용)
build_c19_max <- function(n_hold = 30L) {
  rbindlist(lapply(ym_list, function(ym) {
    fw <- get_wide(ym, "C19_Composite_Earnings")
    if (is.null(fw) || nrow(fw) < n_hold) return(NULL)
    mx <- MAX_RET[YM == ym]
    fw <- merge(fw, mx, by = "Ticker", all.x = TRUE)
    if (sum(!is.na(fw$MAX_Ret)) > 10) {
      cut_mx <- quantile(fw$MAX_Ret, 0.80, na.rm = TRUE)
      fw <- fw[is.na(MAX_Ret) | MAX_Ret < cut_mx]
    }
    if (nrow(fw) < n_hold || !("C19_Composite_Earnings" %in% names(fw))) return(NULL)
    fw[, Score := frank(C19_Composite_Earnings, na.last = "keep",
                        ties.method = "average") / sum(!is.na(C19_Composite_Earnings))]
    sig_d <- monthly_last[YM == ym, sig_date]
    fw[!is.na(Score), .(Date = sig_d, Ticker, Score)]
  }))
}

# ══════════════════════════════════════════════════════════════════
# RQ-3: C19 분해 (IC 분석 — 백테스트 불필요)
# ══════════════════════════════════════════════════════════════════
cat("━━━ RQ-3: C19 Alpha 분해 ━━━\n")
t0 <- Sys.time()

# C19 구성요소별 IC
c19_components <- c("C01_SUE", "C04_ESBR", "C02_EPS_Chg_1m", "C06_TP_Gap")
RAWDATA[, YM := format(Date, "%Y%m")]
MONTHLY_RET <- RAWDATA[, .(Fwd_Ret = sum(Ret, na.rm = TRUE)), by = .(Ticker, YM)]
setkey(MONTHLY_RET, Ticker, YM)
RAWDATA[, YM := NULL]

rq3_results <- list()
for (fc in c(c19_components, "C19_Composite_Earnings")) {
  ics <- unlist(lapply(seq_along(ym_list)[-length(ym_list)], function(i) {
    fw <- get_wide(ym_list[i], fc)
    if (is.null(fw) || nrow(fw) < 30 || !(fc %in% names(fw))) return(NA)
    fwd <- MONTHLY_RET[YM == ym_list[i + 1]]
    merged <- merge(fw[, c("Ticker", fc), with = FALSE], fwd, by = "Ticker")
    if (nrow(merged) < 20) return(NA)
    cor(merged[[fc]], merged$Fwd_Ret, use = "pairwise.complete.obs")
  }))
  ics <- ics[!is.na(ics)]
  if (length(ics) > 12) {
    # Sub-period: first half vs second half
    half <- length(ics) %/% 2
    ic_1h <- mean(ics[1:half])
    ic_2h <- mean(ics[(half + 1):length(ics)])
    # Recent 3Y
    recent_n <- min(36, length(ics))
    ic_recent <- mean(tail(ics, recent_n))

    rq3_results[[fc]] <- data.table(
      factor = fc, mean_ic = mean(ics), sd_ic = sd(ics),
      icir = mean(ics) / (sd(ics) + 1e-8),
      ic_first_half = ic_1h, ic_second_half = ic_2h,
      ic_recent_3y = ic_recent, n_months = length(ics),
      pct_positive = sum(ics > 0) / length(ics))
  }
}
rq3 <- rbindlist(rq3_results)
out_dir <- "04_Research/korea_research/RQ3_output"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
fwrite(rq3, file.path(out_dir, "c19_decomposition.csv"))
cat("[RQ-3] C19 분해:\n"); print(rq3)
cat(sprintf("[RQ-3] Done in %.1f min\n\n", difftime(Sys.time(), t0, units = "mins")))

# ══════════════════════════════════════════════════════════════════
# RQ-1: DD Brake + VT Overlay (C19+MAX base)
# ══════════════════════════════════════════════════════════════════
cat("━━━ RQ-1: DD/VT Overlay ━━━\n")
t0 <- Sys.time()

# Base: C19 + MAX exclusion, N=30
BASE_FACTORS <- build_c19_max(30L)
cat(sprintf("  Base FACTORS: %d rows\n", nrow(BASE_FACTORS)))

# Baseline (no overlay)
run_save(BASE_FACTORS, "RQ1_baseline", "04_Research/korea_research/RQ1_output/baseline")

# DD Brake variants: 5%/15%, 8%/20%, 10%/25% (C9 t-1 lag는 backtest_harness 내부 처리)
for (dd_params in list(c(5, 15), c(8, 20), c(10, 25))) {
  dd_entry <- dd_params[1]; dd_exit <- dd_params[2]
  label <- sprintf("RQ1_DD%d_%d", dd_entry, dd_exit)
  # DD brake는 backtest_harness의 dd_brake 파라미터로 전달
  FACTORS_dd <- copy(BASE_FACTORS)
  sim <- tryCatch(
    run_monthly_simulation(RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS_dd,
      n_holdings = 30L, weight_method = "equal", commission = 0.0015,
      buffer_zone = list(keep_n = 50L, entry_n = 25L),
      dd_brake = list(entry_pct = dd_entry / 100, exit_pct = dd_exit / 100)),
    error = function(e) { cat(sprintf("  %s ERROR: %s\n", label, e$message)); NULL })
  if (!is.null(sim)) {
    out_d <- sprintf("04_Research/korea_research/RQ1_output/%s", label)
    dir.create(out_d, recursive = TRUE, showWarnings = FALSE)
    perf <- summarise_perf(sim$strategy_xts, label)
    cat(sprintf("  %s: SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n",
                label, perf$Sharpe, perf$CAGR, perf$MDD))
    saveRDS(sim, file.path(out_d, "sim_result.rds"))
    fwrite(perf, file.path(out_d, "performance.csv"))
    tryCatch(generate_charts(sim, output_dir = out_d, strategy_name = label),
             error = function(e) NULL)
  }
  rm(sim, FACTORS_dd); gc(verbose = FALSE)
}
cat(sprintf("[RQ-1] Done in %.1f min\n\n", difftime(Sys.time(), t0, units = "mins")))

# ══════════════════════════════════════════════════════════════════
# RQ-2: Regime-Conditional 재무건전성 Blend
# ══════════════════════════════════════════════════════════════════
cat("━━━ RQ-2: Regime Blend ━━━\n")
t0 <- Sys.time()

defense_factors <- c("XF_LL05_WorkingCapital", "XF_RI02_CapEx_proxy", "XF_A02_NOA")
blend_configs <- list(
  c19_only = list(crisis_w = c(C19 = 1.0), normal_w = c(C19 = 1.0)),
  mild     = list(crisis_w = c(C19 = 0.6, DEF = 0.4), normal_w = c(C19 = 0.9, DEF = 0.1)),
  strong   = list(crisis_w = c(C19 = 0.4, DEF = 0.6), normal_w = c(C19 = 0.8, DEF = 0.2)),
  extreme  = list(crisis_w = c(C19 = 0.2, DEF = 0.8), normal_w = c(C19 = 0.7, DEF = 0.3))
)

rq2_results <- list()
for (cfg_name in names(blend_configs)) {
  cfg <- blend_configs[[cfg_name]]
  cat(sprintf("  %s...", cfg_name))

  FACTORS_v <- rbindlist(lapply(ym_list, function(ym) {
    fw <- get_wide(ym, c("C19_Composite_Earnings", defense_factors))
    if (is.null(fw) || nrow(fw) < 30) return(NULL)

    # MAX exclusion
    mx <- MAX_RET[YM == ym]
    fw <- merge(fw, mx, by = "Ticker", all.x = TRUE)
    if (sum(!is.na(fw$MAX_Ret)) > 10) {
      cut_mx <- quantile(fw$MAX_Ret, 0.80, na.rm = TRUE)
      fw <- fw[is.na(MAX_Ret) | MAX_Ret < cut_mx]
    }
    if (nrow(fw) < 30) return(NULL)

    sig_d <- monthly_last[YM == ym, sig_date]
    regime <- get_regime(sig_d)
    is_crisis <- regime %in% c("CRISIS", "CAUTION")
    w <- if (is_crisis) cfg$crisis_w else cfg$normal_w

    # C19 score
    c19_s <- fw$C19_Composite_Earnings; c19_s[is.na(c19_s)] <- 0
    # Defense composite (mean of available)
    def_cols <- intersect(defense_factors, names(fw))
    if (length(def_cols) > 0) {
      def_mat <- as.matrix(fw[, ..def_cols])
      def_mat[is.na(def_mat)] <- 0
      def_s <- rowMeans(def_mat)
    } else {
      def_s <- 0
    }

    c19_w <- w["C19"]; def_w <- if ("DEF" %in% names(w)) w["DEF"] else 0
    fw[, Score := c19_w * c19_s + def_w * def_s]
    fw[!is.na(Score), .(Date = sig_d, Ticker, Score)]
  }))

  perf <- run_save(FACTORS_v, paste0("RQ2_", cfg_name),
                   sprintf("04_Research/korea_research/RQ2_output/%s", cfg_name))
  if (!is.null(perf)) {
    rq2_results[[cfg_name]] <- data.table(config = cfg_name,
      CAGR = perf$CAGR, Sharpe = perf$Sharpe, MDD = perf$MDD)
  }
  rm(FACTORS_v); gc(verbose = FALSE)
}
rq2_comp <- rbindlist(rq2_results)
dir.create("04_Research/korea_research/RQ2_output", recursive = TRUE, showWarnings = FALSE)
fwrite(rq2_comp, "04_Research/korea_research/RQ2_output/comparison.csv")
cat("[RQ-2] Comparison:\n"); print(rq2_comp)
cat(sprintf("[RQ-2] Done in %.1f min\n\n", difftime(Sys.time(), t0, units = "mins")))

# ══════════════════════════════════════════════════════════════════
# RQ-10: HRP/Gerber + N grid
# ══════════════════════════════════════════════════════════════════
cat("━━━ RQ-10: HRP + N Grid ━━━\n")
t0 <- Sys.time()

# HRP 구현 (간소 — López de Prado 2016 핵심 알고리즘)
compute_hrp_weights <- function(ret_mat) {
  # ret_mat: T x N matrix of returns
  if (ncol(ret_mat) < 2 || nrow(ret_mat) < 30) {
    return(rep(1 / ncol(ret_mat), ncol(ret_mat)))
  }

  # Step 1: Correlation → Distance
  cor_mat <- cor(ret_mat, use = "pairwise.complete.obs")
  cor_mat[is.na(cor_mat)] <- 0
  dist_mat <- sqrt(0.5 * (1 - cor_mat))

  # Step 2: Hierarchical clustering
  hc <- hclust(as.dist(dist_mat), method = "single")

  # Step 3: Quasi-diagonalization (seriation)
  sort_idx <- hc$order

  # Step 4: Recursive bisection with inverse variance
  cov_mat <- cov(ret_mat, use = "pairwise.complete.obs")
  cov_mat[is.na(cov_mat)] <- 0
  diag(cov_mat)[diag(cov_mat) < 1e-10] <- 1e-10

  n <- ncol(ret_mat)
  w <- rep(1.0, n)
  names(w) <- colnames(ret_mat)

  recursive_bisect <- function(items, w_vec) {
    if (length(items) <= 1) return(w_vec)
    half <- length(items) %/% 2
    left <- items[1:half]
    right <- items[(half + 1):length(items)]

    # Cluster variance
    var_left <- sum(1 / diag(cov_mat)[left])
    var_right <- sum(1 / diag(cov_mat)[right])
    alpha <- var_left / (var_left + var_right)

    w_vec[left] <- w_vec[left] * alpha
    w_vec[right] <- w_vec[right] * (1 - alpha)

    w_vec <- recursive_bisect(left, w_vec)
    w_vec <- recursive_bisect(right, w_vec)
    w_vec
  }

  w <- recursive_bisect(sort_idx, w)
  w <- w / sum(w)
  w
}

# N grid: 20, 25, 30 × EW vs HRP
rq10_results <- list()
for (n_hold in c(20L, 25L, 30L)) {
  for (wmethod in c("ew", "hrp")) {
    label <- sprintf("RQ10_N%d_%s", n_hold, wmethod)
    cat(sprintf("  %s...", label))

    FACTORS_v <- rbindlist(lapply(ym_list, function(ym) {
      fw <- get_wide(ym, "C19_Composite_Earnings")
      if (is.null(fw) || nrow(fw) < n_hold) return(NULL)
      mx <- MAX_RET[YM == ym]
      fw <- merge(fw, mx, by = "Ticker", all.x = TRUE)
      if (sum(!is.na(fw$MAX_Ret)) > 10) {
        cut_mx <- quantile(fw$MAX_Ret, 0.80, na.rm = TRUE)
        fw <- fw[is.na(MAX_Ret) | MAX_Ret < cut_mx]
      }
      if (nrow(fw) < n_hold) return(NULL)

      # C19 기준 top N
      fw[, c19_rank := frank(-C19_Composite_Earnings, na.last = "keep")]
      top <- fw[c19_rank <= n_hold]

      if (wmethod == "hrp") {
        # HRP: 직전 126일 수익률로 가중치 계산
        sig_d <- monthly_last[YM == ym, sig_date]
        ret_sub <- RAWDATA[Ticker %in% top$Ticker & Date < sig_d &
                             Date >= sig_d - 180, .(Ticker, Date, Ret)]
        ret_wide <- dcast(ret_sub, Date ~ Ticker, value.var = "Ret")
        ret_mat <- as.matrix(ret_wide[, -1])
        if (ncol(ret_mat) >= 5 && nrow(ret_mat) >= 30) {
          hrp_w <- compute_hrp_weights(ret_mat)
          ticker_order <- colnames(ret_mat)
          top_matched <- top[match(ticker_order, Ticker)]
          top_matched <- top_matched[!is.na(Ticker)]
          top_matched[, Score := hrp_w[match(Ticker, ticker_order)]]
          top_matched <- top_matched[!is.na(Score)]
          top_matched[, Date := sig_d]
          return(top_matched[, .(Date, Ticker, Score)])
        }
      }

      # EW fallback
      top[, Score := 1 / nrow(top)]
      sig_d <- monthly_last[YM == ym, sig_date]
      top[, Date := sig_d]
      top[, .(Date, Ticker, Score)]
    }))

    wm_param <- if (wmethod == "hrp") "score" else "equal"
    perf <- run_save(FACTORS_v, label,
                     sprintf("04_Research/korea_research/RQ10_output/%s", label),
                     n_hold = n_hold, wm = wm_param)
    if (!is.null(perf)) {
      rq10_results[[label]] <- data.table(
        n_holdings = n_hold, weight = wmethod,
        CAGR = perf$CAGR, Sharpe = perf$Sharpe, MDD = perf$MDD)
    }
    rm(FACTORS_v); gc(verbose = FALSE)
  }
}
rq10_comp <- rbindlist(rq10_results)
dir.create("04_Research/korea_research/RQ10_output", recursive = TRUE, showWarnings = FALSE)
fwrite(rq10_comp, "04_Research/korea_research/RQ10_output/comparison.csv")
cat("[RQ-10] N × Weight comparison:\n"); print(rq10_comp)
cat(sprintf("[RQ-10] Done in %.1f min\n\n", difftime(Sys.time(), t0, units = "mins")))

# ══════════════════════════════════════════════════════════════════
cat(sprintf("\n━━━ Cycle 1 Complete: %.1f min ━━━\n",
            difftime(Sys.time(), t0_total, units = "mins")))
