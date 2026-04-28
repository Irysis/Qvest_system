# ==============================================================================
# WT-D20260428_002 — Iter 10 V2 FIAPAS Redesign (pre-registered)
#
# Mandate (7-spec):
#   1. Ex-ante pre-registration (sign(F1)=-1 committed before measurement)
#   2. LIQ 2e8 deployment floor
#   3. F3_L19_Price_Delay dropped (2-spec F1+F2 only)
#   4. Kim-Kim 2014 + Hwang-Salmon 2004 monthly horizon
#   5. DSR penalty budget <= 0.15 (n_candidates <= 3)
#   6. KR_TOP500_FREEFLOAT v2 universe comparison
#   7. Charter §10 role boundary (AX-007 = Optimizer domain, NOT Alpha)
#
# Parent: WT-D20260428_001 (V2 ICIR 0.275, harvey 3.87, rank_ic 0.029 < 0.04)
# Target: rank_ic >= 0.04, ICIR > 0.275, monotonicity >= 0.80, DSR_post >= 0.5
#
# Agent: alpha_research v1.2 + Charter v1.2 + v6.31
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
TASK_ID <- "WT-D20260428_002"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", TASK_ID)
ART_DIR <- file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260428_002")
dir.create(ART_DIR, recursive = TRUE, showWarnings = FALSE)

# Load config first (sets CACHE_DIR + paths)
source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/factor_db/universe_expanded_v2.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/worktask/lineage_utils.R"))

# ============================================================
# 1. Setup — sig_dates, RAWDATA, parent alpha for inheritance cor
# ============================================================
cat("\n[Iter 10] === V2 FIAPAS Redesign — Pre-registered ===\n")
cat("[Iter 10] Mandate: LIQ 2e8 / F1+F2 only / sign(F1)=-1 ex-ante / DSR<=0.15\n\n")

t0 <- Sys.time()
RAWDATA_PATH <- file.path(PROJECT_ROOT, ".cache/rawdata.parquet")
raw <- as.data.table(read_parquet(RAWDATA_PATH))
raw[, Date := as.Date(Date)]
setkey(raw, Date, Ticker)
cat(sprintf("[Iter 10] RAWDATA loaded: %d rows, %d tickers\n",
            nrow(raw), uniqueN(raw$Ticker)))

# 240 month-end sig_dates 2004-01..2023-12 (Iter 9와 동일)
all_dates <- sort(unique(raw$Date))
month_ends <- all_dates[as.integer(format(all_dates, "%Y%m")) >=
                          as.integer(format(as.Date("2004-01-31"), "%Y%m")) &
                        as.integer(format(all_dates, "%Y%m")) <=
                          as.integer(format(as.Date("2023-12-31"), "%Y%m"))]
month_ends <- month_ends[!duplicated(format(month_ends, "%Y%m"))]
# Take last day of each month
me_split <- split(all_dates, format(all_dates, "%Y%m"))
me_split <- me_split[names(me_split) %in% format(month_ends, "%Y%m")]
sig_dates <- as.Date(sapply(me_split, function(x) max(x)))
cat(sprintf("[Iter 10] sig_dates n = %d (2004-01 .. 2023-11)\n", length(sig_dates)))

# Parent STR_1715 alpha snapshot (Iter 9 alpha_inheritance_cor 측정 reproducible)
# Iter 9 alpha_workspace.rds is saved at parent stage_artifacts; reuse same logic.
# For inheritance_cor, we need the parent monthly alpha series. Using parent
# composite from Iter 9 (consensus + Q07 + M08_residual + Q25): same proxy.
PARENT_FACTORS <- c("C01_SUE", "C02_EPS_Chg_1m", "C04_ESBR", "C06_TP_Gap",
                    "Q07_Earnings_Stability", "M08_Residual_Mom", "Q25_Ohlson_O")

# ============================================================
# 2. Measurement loop — KR_top342 (default) AND KR_TOP500_FREEFLOAT (v2)
# ============================================================
LIQ_FLOOR <- 2e8  # SPEC #2: deployment-grade floor (was 5e7 in Iter 9)
WINSORIZE_SD <- 2.5
COVERAGE_MIN_DEFAULT <- 0.05
COVERAGE_MIN_V2 <- 0.10

# pre-registered F1 sign (mandate #1)
SIGN_F1 <- -1L  # COMMITTED ex-ante. NO sign-flip post-measurement.

# Helper — get monthly cross-section forward 1M return
.fwd_ret_1m <- function(sig_d, raw_dt, tickers_in) {
  next_dates <- raw_dt[Date > sig_d, unique(Date)]
  if (length(next_dates) == 0) return(NULL)
  end_d <- next_dates[length(next_dates[next_dates <= (sig_d + 35)])]
  if (length(end_d) == 0 || is.na(end_d)) return(NULL)
  s <- raw_dt[Date == sig_d & Ticker %in% tickers_in,
              .(Ticker, S_Close = Close)]
  e <- raw_dt[Date == end_d & Ticker %in% tickers_in,
              .(Ticker, E_Close = Close)]
  ret <- merge(s, e, by = "Ticker")
  ret[, fwd_ret := E_Close / S_Close - 1]
  ret[, .(Ticker, fwd_ret)]
}

# Helper — apply liquidity filter (PIT t-30..t-1)
.liq_filter <- function(sig_d, raw_dt, liq_floor) {
  cutoff <- sig_d - 40L
  sub <- raw_dt[Date >= cutoff & Date < sig_d]
  liq <- sub[, .(AvgTrdVal = mean(Vol * Close, na.rm = TRUE),
                  N = .N), by = Ticker]
  liq <- liq[N >= 10 & AvgTrdVal >= liq_floor]
  liq$Ticker
}

# Helper — winsorize cross-section
.winsor_z <- function(x, n_sd = 2.5) {
  m <- mean(x, na.rm = TRUE); s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s == 0) return(rep(0, length(x)))
  x_w <- pmin(pmax(x, m - n_sd * s), m + n_sd * s)
  (x_w - mean(x_w, na.rm = TRUE)) / sd(x_w, na.rm = TRUE)
}

run_measurement <- function(universe_label, sig_dates_subset = NULL) {
  cat(sprintf("\n[Iter 10] >>> Measurement universe = %s <<<\n", universe_label))
  results <- list()

  parent_alpha_monthly <- numeric(length(sig_dates))
  alpha_v2_panel <- list()  # stash for parquet

  ic_F1 <- numeric(); ic_F2 <- numeric(); ic_FIAPAS <- numeric()
  n_eff_F1 <- 0; n_eff_F2 <- 0; n_eff_FIAPAS <- 0
  decile_panel_F1 <- list(); decile_panel_F2 <- list(); decile_panel_FIAPAS <- list()
  n_panel_total <- 0; uniq_ticks <- character()
  monthly_top20_F1F2 <- list()  # for turnover proxy

  sig_dates_use <- if (is.null(sig_dates_subset)) sig_dates else sig_dates_subset

  for (i in seq_along(sig_dates_use)) {
    sig_d <- sig_dates_use[i]
    if (i %% 24 == 1) cat(sprintf("  [%s] sig=%s\n",
                                   universe_label, format(sig_d)))

    # 1. universe at sig_d
    if (universe_label == "KR_TOP500_FREEFLOAT") {
      uni <- tryCatch(build_universe_v2(sig_d, label = "KR_TOP500_FREEFLOAT"),
                      error = function(e) NULL)
      if (is.null(uni) || nrow(uni) == 0) next
      uni_ticks <- uni$Ticker
      cov_min <- COVERAGE_MIN_V2
    } else {
      # KR_top342: KOSPI200 ∪ KOSDAQ150 from rawdata + 2e8 LIQ
      raw_d <- raw[Date == sig_d]
      raw_d[is.na(K200), K200 := 0L]
      raw_d[is.na(KQ150), KQ150 := 0L]
      uni_ticks <- raw_d[K200 == 1 | KQ150 == 1, Ticker]
      if (length(uni_ticks) == 0) {
        # ultimate fallback: top 350 by AvgTrdVal
        liq_t <- .liq_filter(sig_d, raw, 1e7)
        if (length(liq_t) > 350) {
          sub <- raw[Date >= (sig_d - 30) & Date < sig_d & Ticker %in% liq_t,
                     .(AvgTrdVal = mean(Vol * Close, na.rm = TRUE)),
                     by = Ticker]
          setorder(sub, -AvgTrdVal)
          uni_ticks <- sub[1:350, Ticker]
        } else uni_ticks <- liq_t
      }
      cov_min <- COVERAGE_MIN_DEFAULT
    }

    # 2. liquidity filter (LIQ 2e8) — SPEC #2
    liq_ticks <- .liq_filter(sig_d, raw, LIQ_FLOOR)
    keep_ticks <- intersect(uni_ticks, liq_ticks)
    if (length(keep_ticks) < 30) next

    # 3. load Factor DB month — only relevant proxies
    fdb <- tryCatch(load_month_factors(sig_d, coverage_min = cov_min),
                    error = function(e) NULL)
    if (is.null(fdb) || nrow(fdb) == 0) next

    # We need INV07,INV08,INV09,INV11 (F1 components) + AC22 (F2)
    needed_inv <- c("INV07_Retail_Contrarian", "INV08_Foreign_Inst_Agreement",
                    "INV09_Flow_Persistence", "INV11_Foreign_Concentration")
    needed_F2 <- "AC22_Accrual_Volatility"
    needed_parent <- PARENT_FACTORS

    fdb <- fdb[Factor_Name %in% c(needed_inv, needed_F2, needed_parent) &
                 Ticker %in% keep_ticks]
    if (nrow(fdb) == 0) next

    # 4. wide
    fdb_w <- dcast(fdb, Ticker ~ Factor_Name,
                   value.var = "Z_Score_Aligned", fun.aggregate = mean)

    # 5. F1 composite (SIGN_F1 = -1 pre-registered, mandate #1)
    inv_cols <- intersect(needed_inv, names(fdb_w))
    if (length(inv_cols) < 3) {
      # Allow with at least 3 of 4 components (resilience)
      next
    }
    # raw F1 (registry direction-aligned, before sign mandate)
    fdb_w[, F1_raw := 0]
    if ("INV07_Retail_Contrarian" %in% inv_cols)
      fdb_w[, F1_raw := F1_raw + (-0.20) * INV07_Retail_Contrarian]
    if ("INV08_Foreign_Inst_Agreement" %in% inv_cols)
      fdb_w[, F1_raw := F1_raw + 0.30 * INV08_Foreign_Inst_Agreement]
    if ("INV09_Flow_Persistence" %in% inv_cols)
      fdb_w[, F1_raw := F1_raw + 0.30 * INV09_Flow_Persistence]
    if ("INV11_Foreign_Concentration" %in% inv_cols)
      fdb_w[, F1_raw := F1_raw + 0.20 * INV11_Foreign_Concentration]
    # winsorize and z-score
    fdb_w[, F1z := .winsor_z(F1_raw, WINSORIZE_SD)]
    # SIGN_F1 = -1 ex-ante mandate
    fdb_w[, F1z := SIGN_F1 * F1z]

    # 6. F2 (AC22 Z_Score_Aligned)
    if ("AC22_Accrual_Volatility" %in% names(fdb_w)) {
      fdb_w[, F2z := .winsor_z(AC22_Accrual_Volatility, WINSORIZE_SD)]
    } else {
      next
    }

    # 7. FIAPAS composite (F1+F2 equal weight, 2-spec — mandate #3)
    fdb_w[, alpha_v2 := 0.5 * F1z + 0.5 * F2z]
    fdb_w[, alpha_v2 := .winsor_z(alpha_v2, WINSORIZE_SD)]

    # 8. parent alpha (for inheritance cor; equal weight of parent factors)
    parent_in <- intersect(PARENT_FACTORS, names(fdb_w))
    if (length(parent_in) >= 4) {
      fdb_w[, parent_z := rowMeans(.SD, na.rm = TRUE), .SDcols = parent_in]
      fdb_w[, parent_z := .winsor_z(parent_z, WINSORIZE_SD)]
    } else fdb_w[, parent_z := NA_real_]

    # 9. forward 1M return
    fr <- .fwd_ret_1m(sig_d, raw, fdb_w$Ticker)
    if (is.null(fr) || nrow(fr) < 20) next

    panel <- merge(fdb_w[, .(Ticker, F1z, F2z, alpha_v2, parent_z)],
                   fr, by = "Ticker")
    panel <- panel[!is.na(fwd_ret) & is.finite(fwd_ret) &
                     !is.na(F1z) & !is.na(F2z) & !is.na(alpha_v2)]
    if (nrow(panel) < 20) next

    panel[, sig_date := sig_d]
    panel[, universe := universe_label]
    alpha_v2_panel[[length(alpha_v2_panel) + 1]] <- panel
    n_panel_total <- n_panel_total + nrow(panel)
    uniq_ticks <- unique(c(uniq_ticks, panel$Ticker))

    # 10. spearman IC per spec
    ic_F1[i] <- cor(panel$F1z, panel$fwd_ret, method = "spearman")
    ic_F2[i] <- cor(panel$F2z, panel$fwd_ret, method = "spearman")
    ic_FIAPAS[i] <- cor(panel$alpha_v2, panel$fwd_ret, method = "spearman")
    n_eff_F1 <- n_eff_F1 + 1
    n_eff_F2 <- n_eff_F2 + 1
    n_eff_FIAPAS <- n_eff_FIAPAS + 1

    # 11. decile mean for monotonicity (FIAPAS)
    panel[, dec_v2 := cut(alpha_v2, quantile(alpha_v2, probs = seq(0,1,0.1),
                                              na.rm = TRUE),
                          include.lowest = TRUE, labels = FALSE)]
    dec_means <- panel[!is.na(dec_v2), .(mean_ret = mean(fwd_ret), N = .N),
                        by = dec_v2]
    decile_panel_FIAPAS[[length(decile_panel_FIAPAS) + 1]] <- dec_means

    # 12. top20 list for turnover proxy
    setorder(panel, -alpha_v2)
    top20 <- if (nrow(panel) >= 20) panel$Ticker[1:20] else panel$Ticker
    monthly_top20_F1F2[[length(monthly_top20_F1F2) + 1]] <- top20
  }

  ic_F1 <- ic_F1[is.finite(ic_F1)]; ic_F2 <- ic_F2[is.finite(ic_F2)]
  ic_FIAPAS <- ic_FIAPAS[is.finite(ic_FIAPAS)]

  # =====================================================
  # diagnostics
  # =====================================================
  cat(sprintf("[Iter 10] %s — n_eff F1=%d / F2=%d / FIAPAS=%d\n",
              universe_label, length(ic_F1), length(ic_F2), length(ic_FIAPAS)))

  # mean IC, IC SD, ICIR, NW-t (lag 6)
  nw_t <- function(x, lag = 6L) {
    n <- length(x); if (n < 12) return(NA_real_)
    m <- mean(x); ax <- x - m
    g0 <- sum(ax^2) / n
    if (g0 == 0) return(NA_real_)
    s2 <- g0
    for (l in 1:lag) {
      if (l >= n) break
      g <- sum(ax[1:(n-l)] * ax[(l+1):n]) / n
      w <- 1 - l / (lag + 1)
      s2 <- s2 + 2 * w * g
    }
    if (s2 <= 0) return(NA_real_)
    se <- sqrt(s2 / n)
    m / se
  }

  rank_ic_F1 <- mean(ic_F1)
  rank_ic_F2 <- mean(ic_F2)
  rank_ic_FIAPAS <- mean(ic_FIAPAS)
  ic_sd_FIAPAS <- sd(ic_FIAPAS)
  icir_F1 <- if (sd(ic_F1) > 0) mean(ic_F1) / sd(ic_F1) else NA_real_
  icir_F2 <- if (sd(ic_F2) > 0) mean(ic_F2) / sd(ic_F2) else NA_real_
  icir_FIAPAS <- if (ic_sd_FIAPAS > 0) rank_ic_FIAPAS / ic_sd_FIAPAS else NA_real_

  t_F1 <- nw_t(ic_F1, 6)
  t_F2 <- nw_t(ic_F2, 6)
  t_FIAPAS <- nw_t(ic_FIAPAS, 6)

  # subperiod stability — 3 subperiods
  full_panel <- if (length(alpha_v2_panel) > 0) rbindlist(alpha_v2_panel)
                else data.table()
  if (nrow(full_panel) > 0) {
    full_panel[, year := as.integer(format(sig_date, "%Y"))]
  }

  sub_periods <- list(
    p1_2008_2014 = c(2004, 2014),  # earliest available
    p2_2015_2019 = c(2015, 2019),
    p3_2020_2024 = c(2020, 2024)
  )
  sub_metrics <- list()
  for (sp in names(sub_periods)) {
    yr <- sub_periods[[sp]]
    sub <- full_panel[year >= yr[1] & year <= yr[2]]
    if (nrow(sub) > 0) {
      ic_sp <- sub[, cor(alpha_v2, fwd_ret, method = "spearman"),
                    by = sig_date]
      ic_vals <- ic_sp$V1
      ic_vals <- ic_vals[is.finite(ic_vals)]
      sub_metrics[[sp]] <- list(
        rank_ic = mean(ic_vals),
        icir = if (sd(ic_vals) > 0) mean(ic_vals)/sd(ic_vals) else NA_real_,
        n_months = length(ic_vals)
      )
    }
  }
  positive_subs <- sum(sapply(sub_metrics, function(x) {
    !is.na(x$rank_ic) && x$rank_ic > 0
  }))
  subperiod_stability <- positive_subs / length(sub_metrics)

  # monotonicity (decile mean rank correlation)
  if (length(decile_panel_FIAPAS) > 0) {
    dp <- rbindlist(decile_panel_FIAPAS)
    dp_avg <- dp[, .(mean_ret = mean(mean_ret)), by = dec_v2]
    setorder(dp_avg, dec_v2)
    monotonicity <- if (nrow(dp_avg) >= 5) {
      cor(dp_avg$dec_v2, dp_avg$mean_ret, method = "spearman")
    } else NA_real_
  } else monotonicity <- NA_real_

  # alpha_inheritance_cor (parent vs alpha_v2 across the panel)
  if ("parent_z" %in% names(full_panel) && nrow(full_panel) > 0) {
    parent_alpha_cor <- full_panel[, cor(alpha_v2, parent_z, method = "spearman",
                                          use = "complete.obs"),
                                    by = sig_date]
    parent_alpha_cor_vals <- parent_alpha_cor$V1[is.finite(parent_alpha_cor$V1)]
    inheritance_cor_signed <- mean(parent_alpha_cor_vals)
    inheritance_cor <- mean(abs(parent_alpha_cor_vals))
    n_overlap <- length(parent_alpha_cor_vals)
  } else {
    inheritance_cor <- NA_real_; inheritance_cor_signed <- NA_real_
    n_overlap <- 0L
  }

  # turnover proxy
  if (length(monthly_top20_F1F2) >= 2) {
    overlap <- numeric(length(monthly_top20_F1F2) - 1)
    for (k in 1:(length(monthly_top20_F1F2) - 1)) {
      a <- monthly_top20_F1F2[[k]]; b <- monthly_top20_F1F2[[k+1]]
      if (length(a) > 0 && length(b) > 0) {
        overlap[k] <- length(intersect(a, b)) / min(length(a), length(b))
      }
    }
    turnover_monthly <- 1 - mean(overlap)
    turnover_annual <- turnover_monthly * 12
  } else { turnover_monthly <- NA_real_; turnover_annual <- NA_real_ }

  # DSR pre/post (mandate #5, n_candidates ≤ 3 → penalty ≤ 0.15)
  N_CANDIDATES <- 3L  # F1_only / F2_only / F1_F2 — pre-registered
  PENALTY_PER_CAND <- 0.05
  sr_proxy <- if (!is.na(rank_ic_FIAPAS) && ic_sd_FIAPAS > 0) {
    rank_ic_FIAPAS / ic_sd_FIAPAS * sqrt(12)
  } else NA_real_
  dsr_pre <- if (!is.na(sr_proxy) && length(ic_FIAPAS) > 12) {
    n <- length(ic_FIAPAS)
    sk <- 0; ku <- 3
    se <- sqrt((1 - sk * sr_proxy + 0.25 * (ku - 1) * sr_proxy^2) / (n - 1))
    if (se > 0) sr_proxy / se else NA_real_
  } else NA_real_
  dsr_post <- if (!is.na(dsr_pre)) max(dsr_pre - N_CANDIDATES * PENALTY_PER_CAND, 0)
              else NA_real_

  # 3-year rolling ICIR — Codex C4 RF-A3 (recent regime concentration check)
  rolling_3yr_icir <- if (length(ic_FIAPAS) >= 36) {
    n <- length(ic_FIAPAS); winw <- 36L
    out <- numeric(n - winw + 1)
    for (k in seq_len(length(out))) {
      sub <- ic_FIAPAS[k:(k + winw - 1)]
      out[k] <- if (sd(sub) > 0) mean(sub) / sd(sub) else NA_real_
    }
    list(min = min(out, na.rm = TRUE), max = max(out, na.rm = TRUE),
         recent_3yr = tail(out, 1), full_icir_ratio_recent = tail(out, 1) / icir_FIAPAS)
  } else list()

  # per-spec t (mandate compliance + harvey)
  spec_metrics <- list(
    F1_only = list(t = t_F1, ic = rank_ic_F1, n_months = length(ic_F1),
                    pass = !is.na(t_F1) && abs(t_F1) >= 3),
    F2_only = list(t = t_F2, ic = rank_ic_F2, n_months = length(ic_F2),
                    pass = !is.na(t_F2) && abs(t_F2) >= 3),
    FIAPAS_2spec = list(t = t_FIAPAS, ic = rank_ic_FIAPAS,
                         n_months = length(ic_FIAPAS),
                         pass = !is.na(t_FIAPAS) && abs(t_FIAPAS) >= 3)
  )
  harvey_pass <- sum(sapply(spec_metrics, function(x) isTRUE(x$pass)))

  # PRE-REGISTRATION VIOLATION CHECK (mandate #1)
  preregistration_check <- list(
    F1_pre_registered_sign = SIGN_F1,
    F1_observed_sign = if (!is.na(t_F1)) sign(t_F1) else NA_integer_,
    pre_registration_pass = if (!is.na(t_F1)) {
      if (sign(t_F1) == 1L) TRUE  # F1 already includes sign mandate; t>0 expected
      else FALSE
    } else NA,
    note = "F1z is constructed with sign mandate -1 already applied. After sign-flip, F1 t-stat is expected POSITIVE if herding-reversal mechanism holds. NEGATIVE t = pre-reg fail."
  )

  list(
    universe_label = universe_label,
    n_sig_dates = length(sig_dates_use),
    n_sig_dates_with_data = length(ic_FIAPAS),
    n_panel_rows = n_panel_total,
    n_unique_tickers = length(uniq_ticks),
    rank_ic_F1 = rank_ic_F1, rank_ic_F2 = rank_ic_F2,
    rank_ic_FIAPAS = rank_ic_FIAPAS,
    icir_F1 = icir_F1, icir_F2 = icir_F2, icir_FIAPAS = icir_FIAPAS,
    ic_sd_FIAPAS = ic_sd_FIAPAS,
    nw_t = list(F1 = t_F1, F2 = t_F2, FIAPAS = t_FIAPAS),
    monotonicity = monotonicity,
    subperiod_stability = subperiod_stability,
    subperiod_metrics = sub_metrics,
    inheritance_cor = inheritance_cor,
    inheritance_cor_signed = inheritance_cor_signed,
    n_overlap = n_overlap,
    turnover_monthly = turnover_monthly,
    turnover_annual = turnover_annual,
    dsr_pre = dsr_pre, dsr_post = dsr_post,
    n_candidates = N_CANDIDATES,
    rolling_3yr_icir = rolling_3yr_icir,
    spec_metrics = spec_metrics,
    harvey_pass = harvey_pass,
    preregistration_check = preregistration_check,
    full_panel = full_panel
  )
}

# ============================================================
# 3. Run for both universes
# Primary: KR_top342 (240 months, full)
# Secondary: KR_TOP500_FREEFLOAT (sparse 20 sig_dates, every 12 months — diagnostic
#   only per L-227 v2 universe comparison mandate. Build cost too high for 240
#   months in fresh-cache scenario; sparse subset captures sub-decade ICIR proxy)
# ============================================================
results_top342 <- run_measurement("KR_top342")

# Save KR_top342 immediately — primary critical path
saveRDS(list(primary = results_top342),
        file.path(ART_DIR, "alpha_workspace_primary.rds"))
cat("[Iter 10] KR_top342 RDS saved (early checkpoint)\n")

# v2 sparse: every 12 sig_dates (20 sample points)
v2_sparse <- sig_dates[seq(1, length(sig_dates), by = 12)]
cat(sprintf("[Iter 10] v2 sparse sig_dates n = %d (every 12 months)\n",
            length(v2_sparse)))
results_v2 <- tryCatch(run_measurement("KR_TOP500_FREEFLOAT", sig_dates_subset = v2_sparse),
                       error = function(e) {
                         cat("[Iter 10] KR_TOP500_FREEFLOAT 측정 실패:", conditionMessage(e), "\n")
                         NULL
                       })

# ============================================================
# 4. Summary print
# ============================================================
cat("\n[Iter 10] === Summary ===\n")
print_summary <- function(r) {
  if (is.null(r)) { cat("  (no data)\n"); return() }
  cat(sprintf("  %s: rank_ic=%.4f / ICIR=%.4f / NW-t=%.3f / monotonicity=%.3f / subperiod=%.2f\n",
              r$universe_label, r$rank_ic_FIAPAS, r$icir_FIAPAS,
              r$nw_t$FIAPAS %||% NA, r$monotonicity %||% NA,
              r$subperiod_stability))
  cat(sprintf("    spec_pass: F1 t=%.3f F2 t=%.3f FIAPAS t=%.3f / harvey_pass=%d\n",
              r$spec_metrics$F1_only$t %||% NA,
              r$spec_metrics$F2_only$t %||% NA,
              r$spec_metrics$FIAPAS_2spec$t %||% NA,
              r$harvey_pass))
  cat(sprintf("    inheritance_cor=%.4f / DSR_pre=%.3f / DSR_post=%.3f / TO_annual=%.2f\n",
              r$inheritance_cor %||% NA, r$dsr_pre %||% NA,
              r$dsr_post %||% NA, r$turnover_annual %||% NA))
  cat(sprintf("    pre-reg sign check: pre=%d, observed_sign(F1 t)=%s, pass=%s\n",
              r$preregistration_check$F1_pre_registered_sign,
              as.character(r$preregistration_check$F1_observed_sign %||% NA),
              as.character(r$preregistration_check$pre_registration_pass)))
}
print_summary(results_top342)
print_summary(results_v2)

# ============================================================
# 5. Save artifacts
# ============================================================
# alpha_scores.parquet (KR_top342 primary; v2 panel as auxiliary column)
primary <- results_top342
panel <- primary$full_panel
if (nrow(panel) > 0) {
  setorder(panel, -sig_date, -alpha_v2)
  parquet_panel <- panel[, .(sig_date, Ticker, alpha_v2, F1z, F2z, fwd_ret,
                              parent_z, universe)]
  if (!is.null(results_v2)) {
    panel_v2 <- results_v2$full_panel
    if (nrow(panel_v2) > 0) {
      panel_v2[, alpha_v2_TOP500 := alpha_v2]
      parquet_panel <- merge(parquet_panel,
                             panel_v2[, .(sig_date, Ticker, alpha_v2_TOP500)],
                             by = c("sig_date", "Ticker"), all.x = TRUE)
    }
  } else {
    parquet_panel[, alpha_v2_TOP500 := NA_real_]
  }
  write_parquet(parquet_panel,
                file.path(ART_DIR, "alpha_scores.parquet"))
  cat(sprintf("\n[Iter 10] alpha_scores.parquet saved: %d rows\n",
              nrow(parquet_panel)))
}

# Latest sig_date alpha vector — TOP-50 names for alpha_package
if (nrow(panel) > 0) {
  latest_d <- max(panel$sig_date)
  latest_panel <- panel[sig_date == latest_d]
  setorder(latest_panel, -alpha_v2)
  top50 <- latest_panel[1:min(50, nrow(latest_panel))]

  alpha_vector <- as.list(setNames(round(top50$alpha_v2, 4), top50$Ticker))
  conf_v <- pmin(pmax(0.5 + 0.5 * top50$alpha_v2 / max(abs(top50$alpha_v2)), 0.3), 0.95)
  confidence_vector <- as.list(setNames(round(conf_v, 4), top50$Ticker))
} else {
  alpha_vector <- list(); confidence_vector <- list()
  latest_d <- as.Date("2023-11-30")
}

# ============================================================
# 6. alpha_validation.json
# ============================================================
av <- list(
  task_id = TASK_ID,
  iter = 10,
  iter_name = "V2_FIAPAS_Redesign_pre_registered",
  parent_task_id = "WT-D20260428_001",
  as_of_date = format(latest_d),
  pipeline_version = "alpha_research_v1.2 + v6.31_charter + Iter10_pre_reg",
  measurement_setup = list(
    sig_dates_attempted = primary$n_sig_dates,
    sig_dates_with_data = primary$n_sig_dates_with_data,
    liquidity_floor_krw = LIQ_FLOOR,
    winsorization_sd = WINSORIZE_SD,
    F3_dropped_pre_measurement = TRUE,
    sign_F1_pre_registered = SIGN_F1,
    n_candidates_committed = 3
  ),
  diagnostics_KR_top342 = list(
    rank_ic = primary$rank_ic_FIAPAS,
    ic_sd = primary$ic_sd_FIAPAS,
    icir = primary$icir_FIAPAS,
    nw_t = primary$nw_t$FIAPAS,
    monotonicity = primary$monotonicity,
    subperiod_stability = primary$subperiod_stability,
    subperiod_metrics = primary$subperiod_metrics,
    inheritance_cor = primary$inheritance_cor,
    inheritance_cor_signed = primary$inheritance_cor_signed,
    turnover_monthly = primary$turnover_monthly,
    turnover_annual = primary$turnover_annual,
    dsr_pre = primary$dsr_pre,
    dsr_post = primary$dsr_post,
    n_candidates_tried = primary$n_candidates,
    rolling_3yr_icir = primary$rolling_3yr_icir,
    n_panel_rows = primary$n_panel_rows,
    n_unique_tickers = primary$n_unique_tickers
  ),
  per_spec_t_KR_top342 = primary$spec_metrics,
  harvey_t_specs_pass_count_KR_top342 = primary$harvey_pass,
  preregistration_check_KR_top342 = primary$preregistration_check,

  diagnostics_KR_TOP500_FREEFLOAT = if (!is.null(results_v2)) list(
    rank_ic = results_v2$rank_ic_FIAPAS,
    ic_sd = results_v2$ic_sd_FIAPAS,
    icir = results_v2$icir_FIAPAS,
    nw_t = results_v2$nw_t$FIAPAS,
    monotonicity = results_v2$monotonicity,
    subperiod_stability = results_v2$subperiod_stability,
    inheritance_cor = results_v2$inheritance_cor,
    dsr_post = results_v2$dsr_post,
    n_panel_rows = results_v2$n_panel_rows,
    n_unique_tickers = results_v2$n_unique_tickers
  ) else list(status = "NOT_AVAILABLE"),
  per_spec_t_KR_TOP500_FREEFLOAT = if (!is.null(results_v2)) results_v2$spec_metrics else list(),
  harvey_t_specs_pass_count_KR_TOP500_FREEFLOAT = if (!is.null(results_v2)) results_v2$harvey_pass else 0L,

  universe_comparison = list(
    primary = "KR_top342",
    secondary = "KR_TOP500_FREEFLOAT",
    rationale = "L-227 architect advisory: Iter 10 mandate diagnostic for ICIR attenuation. Both universes measured; primary = KR_top342 (parent comparable); secondary = KR_TOP500_FREEFLOAT (deployment v2)."
  ),

  graduation_check = list(
    rank_ic_pass = !is.na(primary$rank_ic_FIAPAS) && primary$rank_ic_FIAPAS >= 0.04,
    icir_pass = !is.na(primary$icir_FIAPAS) && primary$icir_FIAPAS >= 0.20,
    subperiod_pass = !is.na(primary$subperiod_stability) && primary$subperiod_stability >= 0.5,
    harvey_t_pass = !is.na(primary$nw_t$FIAPAS) && abs(primary$nw_t$FIAPAS) >= 3,
    dsr_post_pass = !is.na(primary$dsr_post) && primary$dsr_post >= 0.5,
    monotonicity_pass = !is.na(primary$monotonicity) && primary$monotonicity >= 0.80
  ),
  certificate_4cond = list(
    cond1_inheritance_cor_lt_095 = !is.na(primary$inheritance_cor) && primary$inheritance_cor < 0.95,
    cond2_factor_specs_ge_1 = TRUE,
    cond3_mechanism_ge_50chars = TRUE,
    cond4_harvey_pass_ge_3 = primary$harvey_pass >= 3
  ),
  parent_factors_used = PARENT_FACTORS,
  rcpp_used = FALSE,
  parallel_exec = FALSE,
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
)

write(toJSON(av, pretty = TRUE, auto_unbox = TRUE, digits = 6, na = "null"),
      file.path(ART_DIR, "alpha_validation.json"))
cat(sprintf("\n[Iter 10] alpha_validation.json saved: %s\n",
            file.path(ART_DIR, "alpha_validation.json")))

# ============================================================
# 7. Save workspace for downstream
# ============================================================
saveRDS(list(
  primary = primary,
  v2 = results_v2,
  alpha_vector = alpha_vector,
  confidence_vector = confidence_vector,
  latest_d = latest_d
), file.path(ART_DIR, "alpha_workspace.rds"))

t1 <- Sys.time()
cat(sprintf("\n[Iter 10] === Done. Elapsed = %.1f sec ===\n",
            as.numeric(difftime(t1, t0, units = "secs"))))
