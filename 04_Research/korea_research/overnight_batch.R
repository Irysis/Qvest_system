cat("=== Overnight Batch: RQ-1 fix + RQ-10 Gerber + Cycle 2-3 ===\n")
t0_total <- Sys.time()

suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/backtest_harness.R")
  source("02_Infrastructure/factor_db_connector.R")
})
library(data.table); library(arrow)

FACTOR_DB_DIR <- file.path(CACHE_DIR, "factor_db")

# ══════════════════════════════════════════════════════════════════
# SHARED DATA (1회)
# ══════════════════════════════════════════════════════════════════
cat("[OPT] Loading shared data...\n")
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res)
setkey(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y%m")]

monthly_last <- RAWDATA[, .(sig_date = max(Date)), by = YM]
setkey(monthly_last, YM)
month_ends <- sort(monthly_last$sig_date)
month_ends <- month_ends[month_ends >= as.Date("2006-01-01")]
ym_list <- format(month_ends, "%Y%m")

# LIQ (C10 t-1)
RAWDATA[, TV := Close * Vol]
LIQ_RAW <- RAWDATA[, .(AvgTV20 = mean(tail(TV, 20), na.rm = TRUE)), by = .(Ticker, YM)]
ym_all_l <- sort(unique(LIQ_RAW$YM))
ym_sh <- data.table(YM_prev = ym_all_l[-length(ym_all_l)], YM_use = ym_all_l[-1])
LIQ_MONTHLY <- merge(LIQ_RAW, ym_sh, by.x = "YM", by.y = "YM_prev")
LIQ_MONTHLY <- LIQ_MONTHLY[, .(Ticker, YM = YM_use, AvgTV20)]
setkey(LIQ_MONTHLY, Ticker, YM)
rm(LIQ_RAW, ym_sh)

# Factor DB
ALL_F <- c("C19_Composite_Earnings", "C01_SUE", "C02_EPS_Chg_1m", "C04_ESBR",
           "Q01_GPA", "D01_IdioVol", "M05_Trended_Mom", "M01_12M_Momentum",
           "V14_EBIT_EV", "D02_Beta")
fdb_files <- list.files(FACTOR_DB_DIR, pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE)
FDB_ALL <- rbindlist(lapply(fdb_files, function(f) {
  dt <- as.data.table(read_parquet(f))
  dt[, YM := gsub(".*factor_db_(\\d{6})\\.parquet", "\\1", f)]
  dt[Factor_Name %in% ALL_F]
}), fill = TRUE)
registry <- jsonlite::fromJSON(file.path(FACTOR_DB_DIR, "factor_registry.json"))
FDB_ALL <- align_factor_direction(FDB_ALL, registry)
setkey(FDB_ALL, YM, Ticker, Factor_Name)

MAX_RET <- RAWDATA[, .(MAX_Ret = max(Ret, na.rm = TRUE)), by = .(Ticker, YM)]
setkey(MAX_RET, Ticker, YM)

RAWDATA[, c("YM", "TV") := NULL]
gc(verbose = FALSE)
cat(sprintf("[OPT] Ready. FDB: %.0fMB\n\n", object.size(FDB_ALL) / 1e6))

# Helpers
get_wide <- function(ym, factors = ALL_F) {
  fdt <- FDB_ALL[YM == ym & Factor_Name %in% factors]
  if (nrow(fdt) == 0) return(NULL)
  fdt_w <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  liq <- LIQ_MONTHLY[YM == ym]
  fdt_w <- merge(fdt_w, liq, by = "Ticker")
  fdt_w[!is.na(AvgTV20) & AvgTV20 >= 2e8]
}

run_save <- function(FACTORS, name, out_dir, n_hold = 20L, wm = "equal",
                     dd = NULL, vt = NULL) {
  if (nrow(FACTORS) == 0) { cat("  SKIP\n"); return(NULL) }
  setorder(FACTORS, Date, -Score)
  sim <- tryCatch(
    run_monthly_simulation(RAWDATA = RAWDATA, BM_DT = BM_DT, FACTORS = FACTORS,
      n_holdings = n_hold, weight_method = wm, commission = 0.0015,
      dd_brake = dd, vol_target = vt,
      buffer_zone = list(keep_n = as.integer(n_hold * 1.5),
                         entry_n = as.integer(n_hold * 0.8))),
    error = function(e) { cat(sprintf("  %s ERROR: %s\n", name, e$message)); NULL })
  if (is.null(sim)) return(NULL)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  perf <- summarise_perf(sim$strategy_xts, name)
  cat(sprintf("  %s: SR=%.3f CAGR=%.2f%% MDD=%.1f%%\n",
              name, perf$Sharpe, perf$CAGR, perf$MDD))
  saveRDS(sim, file.path(out_dir, "sim_result.rds"))
  fwrite(perf, file.path(out_dir, "performance.csv"))
  tryCatch(generate_charts(sim, output_dir = out_dir, strategy_name = name),
           error = function(e) NULL)
  rm(sim); gc(verbose = FALSE)
  perf
}

# C19+MAX base (N=20)
build_c19_max_n <- function(n = 20L) {
  rbindlist(lapply(ym_list, function(ym) {
    fw <- get_wide(ym, "C19_Composite_Earnings")
    if (is.null(fw) || nrow(fw) < n) return(NULL)
    mx <- MAX_RET[YM == ym]
    fw <- merge(fw, mx, by = "Ticker", all.x = TRUE)
    if (sum(!is.na(fw$MAX_Ret)) > 10) {
      cut_mx <- quantile(fw$MAX_Ret, 0.80, na.rm = TRUE)
      fw <- fw[is.na(MAX_Ret) | MAX_Ret < cut_mx]
    }
    if (nrow(fw) < n) return(NULL)
    fw[, Score := frank(C19_Composite_Earnings, na.last = "keep",
                        ties.method = "average") / sum(!is.na(C19_Composite_Earnings))]
    sig_d <- monthly_last[YM == ym, sig_date]
    fw[!is.na(Score), .(Date = sig_d, Ticker, Score)]
  }))
}

# ══════════════════════════════════════════════════════════════════
# RQ-1 FIX: DD Brake + Vol Target (N=20 base)
# ══════════════════════════════════════════════════════════════════
cat("━━━ RQ-1: DD Brake + VT (fixed) ━━━\n")
t0 <- Sys.time()
BASE20 <- build_c19_max_n(20L)

# Baseline N=20
run_save(BASE20, "RQ1_N20_base", "04_Research/korea_research/RQ1_fix/baseline")

# DD Brake variants
for (dd_p in list(c(5,15), c(8,20), c(10,25), c(6,18))) {
  lab <- sprintf("RQ1_DD%d_%d", dd_p[1], dd_p[2])
  run_save(BASE20, lab, sprintf("04_Research/korea_research/RQ1_fix/%s", lab),
           dd = list(entry_pct = dd_p[1]/100, exit_pct = dd_p[2]/100))
}

# Vol Target variants
for (vt_val in c(0.12, 0.15, 0.18, 0.20)) {
  lab <- sprintf("RQ1_VT%.0f", vt_val * 100)
  run_save(BASE20, lab, sprintf("04_Research/korea_research/RQ1_fix/%s", lab),
           vt = vt_val)
}

# DD + VT combo
run_save(BASE20, "RQ1_DD8_VT15", "04_Research/korea_research/RQ1_fix/DD8_VT15",
         dd = list(entry_pct = 0.08, exit_pct = 0.20), vt = 0.15)
run_save(BASE20, "RQ1_DD6_VT18", "04_Research/korea_research/RQ1_fix/DD6_VT18",
         dd = list(entry_pct = 0.06, exit_pct = 0.18), vt = 0.18)

rm(BASE20); gc(verbose = FALSE)
cat(sprintf("[RQ-1] Done in %.1f min\n\n", difftime(Sys.time(), t0, units = "mins")))

# ══════════════════════════════════════════════════════════════════
# RQ-10 FIX: Gerber Statistic + HRP
# ══════════════════════════════════════════════════════════════════
cat("━━━ RQ-10: Gerber HRP ━━━\n")
t0 <- Sys.time()

# Gerber statistic correlation
gerber_cor <- function(ret_mat, threshold = 0.5) {
  n <- ncol(ret_mat); T_ <- nrow(ret_mat)
  if (T_ < 10 || n < 2) return(cor(ret_mat, use = "pairwise.complete.obs"))
  # Threshold: median absolute deviation
  sds <- apply(ret_mat, 2, sd, na.rm = TRUE)
  sds[sds < 1e-8] <- 1e-8

  gcor <- matrix(0, n, n)
  for (i in seq_len(n)) {
    for (j in i:n) {
      xi <- ret_mat[, i]; xj <- ret_mat[, j]
      valid <- !is.na(xi) & !is.na(xj)
      xi <- xi[valid]; xj <- xj[valid]
      if (length(xi) < 10) { gcor[i, j] <- 0; gcor[j, i] <- 0; next }
      ti <- threshold * sds[i]; tj <- threshold * sds[j]
      concordant <- sum((xi > ti & xj > tj) | (xi < -ti & xj < -tj))
      discordant <- sum((xi > ti & xj < -tj) | (xi < -ti & xj > tj))
      total <- concordant + discordant
      if (total == 0) { gcor[i, j] <- 0 } else { gcor[i, j] <- (concordant - discordant) / total }
      gcor[j, i] <- gcor[i, j]
    }
  }
  diag(gcor) <- 1
  colnames(gcor) <- colnames(ret_mat); rownames(gcor) <- colnames(ret_mat)
  gcor
}

# HRP with custom correlation
compute_hrp_gerber <- function(ret_mat, use_gerber = TRUE) {
  if (ncol(ret_mat) < 2 || nrow(ret_mat) < 30) return(rep(1/ncol(ret_mat), ncol(ret_mat)))
  cor_mat <- if (use_gerber) gerber_cor(ret_mat) else cor(ret_mat, use = "pairwise.complete.obs")
  cor_mat[is.na(cor_mat)] <- 0
  dist_mat <- sqrt(0.5 * (1 - cor_mat))
  hc <- hclust(as.dist(dist_mat), method = "single")
  sort_idx <- hc$order

  cov_mat <- cov(ret_mat, use = "pairwise.complete.obs")
  cov_mat[is.na(cov_mat)] <- 0
  diag(cov_mat)[diag(cov_mat) < 1e-10] <- 1e-10

  w <- rep(1.0, ncol(ret_mat)); names(w) <- colnames(ret_mat)
  bisect <- function(items, wv) {
    if (length(items) <= 1) return(wv)
    h <- length(items) %/% 2
    L <- items[1:h]; R <- items[(h+1):length(items)]
    vL <- sum(1/diag(cov_mat)[L]); vR <- sum(1/diag(cov_mat)[R])
    a <- vL / (vL + vR)
    wv[L] <- wv[L] * a; wv[R] <- wv[R] * (1 - a)
    wv <- bisect(L, wv); wv <- bisect(R, wv); wv
  }
  w <- bisect(sort_idx, w)
  w / sum(w)
}

# N=20, Gerber HRP vs Standard HRP vs EW
for (wmethod in c("ew", "hrp_std", "hrp_gerber")) {
  lab <- sprintf("RQ10g_N20_%s", wmethod)
  cat(sprintf("  %s...", lab))

  FACTORS_v <- rbindlist(lapply(ym_list, function(ym) {
    fw <- get_wide(ym, "C19_Composite_Earnings")
    if (is.null(fw) || nrow(fw) < 20) return(NULL)
    mx <- MAX_RET[YM == ym]
    fw <- merge(fw, mx, by = "Ticker", all.x = TRUE)
    if (sum(!is.na(fw$MAX_Ret)) > 10) {
      cut_mx <- quantile(fw$MAX_Ret, 0.80, na.rm = TRUE)
      fw <- fw[is.na(MAX_Ret) | MAX_Ret < cut_mx]
    }
    if (nrow(fw) < 20) return(NULL)
    fw[, c19_rank := frank(-C19_Composite_Earnings, na.last = "keep")]
    top <- fw[c19_rank <= 20]
    sig_d <- monthly_last[YM == ym, sig_date]

    if (wmethod != "ew") {
      ret_sub <- RAWDATA[Ticker %in% top$Ticker & Date < sig_d & Date >= sig_d - 180,
                         .(Ticker, Date, Ret)]
      ret_wide <- dcast(ret_sub, Date ~ Ticker, value.var = "Ret")
      ret_mat <- as.matrix(ret_wide[, -1])
      if (ncol(ret_mat) >= 5 && nrow(ret_mat) >= 30) {
        use_g <- (wmethod == "hrp_gerber")
        hrp_w <- compute_hrp_gerber(ret_mat, use_gerber = use_g)
        top_m <- top[match(colnames(ret_mat), Ticker)]
        top_m <- top_m[!is.na(Ticker)]
        top_m[, Score := hrp_w[match(Ticker, names(hrp_w))]]
        top_m <- top_m[!is.na(Score)]
        top_m[, Date := sig_d]
        return(top_m[, .(Date, Ticker, Score)])
      }
    }
    top[, Score := 1 / nrow(top)]
    top[, Date := sig_d]
    top[, .(Date, Ticker, Score)]
  }))

  wm_p <- if (wmethod == "ew") "equal" else "score"
  run_save(FACTORS_v, lab, sprintf("04_Research/korea_research/RQ10_gerber/%s", lab),
           wm = wm_p)
  rm(FACTORS_v); gc(verbose = FALSE)
}
cat(sprintf("[RQ-10g] Done in %.1f min\n\n", difftime(Sys.time(), t0, units = "mins")))

# ══════════════════════════════════════════════════════════════════
# CYCLE 2: RQ-5 Multi-Horizon + RQ-6 기관 신호
# ══════════════════════════════════════════════════════════════════
cat("━━━ RQ-5: Multi-Horizon C19 ━━━\n")
t0 <- Sys.time()
# C19의 SUE를 5d/21d/63d lookback으로 z-score 변환 → IC 비교
# SUE 자체가 이미 일간이므로, rolling mean of SUE로 multi-resolution
RAWDATA[, YM := format(Date, "%Y%m")]
MONTHLY_RET <- RAWDATA[, .(Fwd_Ret = sum(Ret, na.rm = TRUE)), by = .(Ticker, YM)]
setkey(MONTHLY_RET, Ticker, YM)
RAWDATA[, YM := NULL]

horizons <- c(1, 3, 6, 12)  # months lookback for IC
rq5_results <- list()
for (h in horizons) {
  ics <- unlist(lapply(seq_along(ym_list), function(i) {
    if (i + 1 > length(ym_list) || i - h < 1) return(NA)
    fw <- get_wide(ym_list[i], "C19_Composite_Earnings")
    if (is.null(fw) || nrow(fw) < 30) return(NA)
    fwd <- MONTHLY_RET[YM == ym_list[i + 1]]
    m <- merge(fw[, .(Ticker, C19_Composite_Earnings)], fwd, by = "Ticker")
    if (nrow(m) < 20) return(NA)
    cor(m$C19_Composite_Earnings, m$Fwd_Ret, use = "pairwise.complete.obs")
  }))
  ics <- ics[!is.na(ics)]
  if (length(ics) > 12) {
    rq5_results[[as.character(h)]] <- data.table(
      horizon_m = h, mean_ic = mean(ics), icir = mean(ics) / (sd(ics) + 1e-8),
      n = length(ics))
  }
}
rq5 <- rbindlist(rq5_results)
dir.create("04_Research/korea_research/RQ5_output", recursive = TRUE, showWarnings = FALSE)
fwrite(rq5, "04_Research/korea_research/RQ5_output/horizon_ic.csv")
cat("[RQ-5] Horizon IC:\n"); print(rq5)
cat(sprintf("[RQ-5] Done in %.1f min\n\n", difftime(Sys.time(), t0, units = "mins")))

# ── RQ-6: 기관 매수 신호 ──
cat("━━━ RQ-6: INV Signal ━━━\n")
t0 <- Sys.time()
# INV03_Inst_NetBuy가 FDB에 있는지 확인
inv_check <- FDB_ALL[Factor_Name %like% "INV", uniqueN(Factor_Name)]
cat(sprintf("  INV factors in FDB: %d\n", inv_check))
if (inv_check > 0) {
  inv_names <- FDB_ALL[Factor_Name %like% "INV", unique(Factor_Name)]
  cat(sprintf("  Available: %s\n", paste(inv_names, collapse = ", ")))
  # IC 계산
  rq6_results <- list()
  for (inv_f in inv_names) {
    ics <- unlist(lapply(seq_along(ym_list)[-length(ym_list)], function(i) {
      fw <- get_wide(ym_list[i], inv_f)
      if (is.null(fw) || nrow(fw) < 30 || !(inv_f %in% names(fw))) return(NA)
      fwd <- MONTHLY_RET[YM == ym_list[i + 1]]
      m <- merge(fw[, c("Ticker", inv_f), with = FALSE], fwd, by = "Ticker")
      if (nrow(m) < 20) return(NA)
      cor(m[[inv_f]], m$Fwd_Ret, use = "pairwise.complete.obs")
    }))
    ics <- ics[!is.na(ics)]
    if (length(ics) > 12) {
      rq6_results[[inv_f]] <- data.table(
        factor = inv_f, mean_ic = mean(ics),
        icir = mean(ics) / (sd(ics) + 1e-8), n = length(ics))
    }
  }
  rq6 <- rbindlist(rq6_results)
  dir.create("04_Research/korea_research/RQ6_output", recursive = TRUE, showWarnings = FALSE)
  fwrite(rq6, "04_Research/korea_research/RQ6_output/inv_ic.csv")
  cat("[RQ-6] INV IC:\n"); print(rq6)
} else {
  cat("  No INV factors in FDB. Skipping.\n")
}
cat(sprintf("[RQ-6] Done in %.1f min\n\n", difftime(Sys.time(), t0, units = "mins")))

# ══════════════════════════════════════════════════════════════════
# CYCLE 3: RQ-7 TIE + RQ-8 Axiom + RQ-9 Spectrum
# ══════════════════════════════════════════════════════════════════

# ── RQ-7: TIE (4팩터 Ising) ──
cat("━━━ RQ-7: TIE Hamiltonian ━━━\n")
t0 <- Sys.time()
tie_factors <- c("V14_EBIT_EV", "Q01_GPA", "M05_Trended_Mom", "D01_IdioVol")

FACTORS_tie <- rbindlist(lapply(ym_list, function(ym) {
  fw <- get_wide(ym, tie_factors)
  if (is.null(fw) || nrow(fw) < 20) return(NULL)
  avail <- intersect(tie_factors, names(fw))
  if (length(avail) < 3) return(NULL)
  mat <- as.matrix(fw[, ..avail])
  mat[is.na(mat)] <- 0

  # Pairwise coupling (rolling cor는 사전 계산 어려우므로 당월 횡단면 cor 사용)
  n_f <- ncol(mat)
  H <- rep(0, nrow(mat))
  for (a in seq_len(n_f - 1)) {
    for (b in (a + 1):n_f) {
      J_ab <- cor(mat[, a], mat[, b], use = "pairwise.complete.obs")
      if (is.na(J_ab)) J_ab <- 0
      H <- H - J_ab * mat[, a] * mat[, b]
    }
  }
  fw[, Score := -H]  # 낮은 에너지 = 유리한 조합
  sig_d <- monthly_last[YM == ym, sig_date]
  fw[!is.na(Score), .(Date = sig_d, Ticker, Score)]
}))

run_save(FACTORS_tie, "RQ7_TIE", "04_Research/korea_research/RQ7_output")
rm(FACTORS_tie); gc(verbose = FALSE)
cat(sprintf("[RQ-7] Done in %.1f min\n\n", difftime(Sys.time(), t0, units = "mins")))

# ── RQ-9: Spectrum Risk (ASR) ──
cat("━━━ RQ-9: Absorption Spectrum Risk ━━━\n")
t0 <- Sys.time()

RAWDATA[, YM := format(Date, "%Y%m")]
FACTORS_asr <- rbindlist(lapply(ym_list, function(ym) {
  sig_d <- monthly_last[YM == ym, sig_date]
  # 직전 252일 수익률
  ret_sub <- RAWDATA[Date < sig_d & Date >= sig_d - 365, .(Ticker, Date, Ret)]
  tickers <- ret_sub[, .N, by = Ticker][N >= 200, Ticker]
  if (length(tickers) < 30) return(NULL)

  # LIQ 필터
  liq <- LIQ_MONTHLY[YM == ym]

  asr_list <- lapply(tickers, function(tk) {
    r <- ret_sub[Ticker == tk, Ret]
    if (length(r) < 200 || all(is.na(r))) return(NULL)
    r[is.na(r)] <- 0
    # FFT
    ps <- Mod(fft(r))^2
    ps <- ps[2:(length(ps) %/% 2)]  # positive frequencies
    list(Ticker = tk, mean_power = mean(ps), low_freq_power = mean(head(ps, 10)))
  })
  asr_dt <- rbindlist(asr_list[!sapply(asr_list, is.null)])
  if (nrow(asr_dt) < 20) return(NULL)

  # 시장 중앙값 대비 흡수
  med_lf <- median(asr_dt$low_freq_power, na.rm = TRUE)
  asr_dt[, absorption := pmax(0, med_lf - low_freq_power) / (med_lf + 1e-8)]
  asr_dt[, Score := -absorption]  # 흡수 큰 종목 = 숨겨진 리스크 → 회피

  asr_dt <- merge(asr_dt, liq, by = "Ticker")
  asr_dt <- asr_dt[!is.na(AvgTV20) & AvgTV20 >= 2e8]
  asr_dt[, Date := sig_d]
  asr_dt[!is.na(Score), .(Date, Ticker, Score)]
}))
RAWDATA[, YM := NULL]

if (nrow(FACTORS_asr) > 0) {
  run_save(FACTORS_asr, "RQ9_ASR", "04_Research/korea_research/RQ9_output")
} else {
  cat("  ASR FACTORS empty\n")
}
rm(FACTORS_asr); gc(verbose = FALSE)
cat(sprintf("[RQ-9] Done in %.1f min\n\n", difftime(Sys.time(), t0, units = "mins")))

# ── RQ-8: Axiom 정량화 (IC freshness) ──
cat("━━━ RQ-8: Factor Freshness Index ━━━\n")
t0 <- Sys.time()
# 각 팩터의 IC 반감기 계산
key_factors <- c("C19_Composite_Earnings", "Q01_GPA", "V14_EBIT_EV",
                 "M05_Trended_Mom", "D01_IdioVol")
rq8_results <- list()
for (fc in key_factors) {
  # IC at 1m, 3m, 6m horizons (expanding window)
  ic_by_h <- sapply(c(1, 3, 6), function(h) {
    ics <- unlist(lapply(seq_along(ym_list), function(i) {
      if (i + h > length(ym_list)) return(NA)
      fw <- get_wide(ym_list[i], fc)
      if (is.null(fw) || nrow(fw) < 30 || !(fc %in% names(fw))) return(NA)
      # h-month forward return
      fwd_yms <- ym_list[(i + 1):min(i + h, length(ym_list))]
      fwd <- MONTHLY_RET[YM %in% fwd_yms, .(Fwd_Ret = sum(Fwd_Ret)), by = Ticker]
      m <- merge(fw[, c("Ticker", fc), with = FALSE], fwd, by = "Ticker")
      if (nrow(m) < 20) return(NA)
      cor(m[[fc]], m$Fwd_Ret, use = "pairwise.complete.obs")
    }))
    mean(ics, na.rm = TRUE)
  })

  if (all(!is.na(ic_by_h))) {
    # Decay rate: IC(h) ≈ IC(1) * exp(-lambda * h)
    if (ic_by_h[1] > 0.001) {
      ratios <- ic_by_h / ic_by_h[1]
      ratios[ratios <= 0] <- 0.001
      lambda_est <- -mean(log(ratios) / c(1, 3, 6))
      half_life <- log(2) / max(lambda_est, 0.001)
    } else {
      half_life <- NA
    }
    rq8_results[[fc]] <- data.table(
      factor = fc, ic_1m = ic_by_h[1], ic_3m = ic_by_h[2], ic_6m = ic_by_h[3],
      half_life_months = half_life)
  }
}
rq8 <- rbindlist(rq8_results)
dir.create("04_Research/korea_research/RQ8_output", recursive = TRUE, showWarnings = FALSE)
fwrite(rq8, "04_Research/korea_research/RQ8_output/factor_freshness.csv")
cat("[RQ-8] Factor Freshness:\n"); print(rq8)
cat(sprintf("[RQ-8] Done in %.1f min\n\n", difftime(Sys.time(), t0, units = "mins")))

# ══════════════════════════════════════════════════════════════════
elapsed <- difftime(Sys.time(), t0_total, units = "mins")
cat(sprintf("\n━━━ Overnight Batch Complete: %.1f min ━━━\n", elapsed))
cat(sprintf("Finished at: %s\n", Sys.time()))
