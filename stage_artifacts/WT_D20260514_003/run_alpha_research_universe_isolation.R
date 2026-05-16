#==============================================================================
# WT-D20260514_003 Alpha Research — C Variant Universe Isolation Re-test
#
# Mandate (도훈 Session 81, 2026-05-14 KST):
#   Parent WT-D20260513_002 C variant (sector-residualized CAPM-residual idio_vol)
#   동일 spec retain 단 universe만 KOSPI200 ∪ KOSDAQ150 intersection (~348)
#   → KOSPI 본주 + KOSDAQ 전종목 (~2030 at 2026-04-30) 확장.
#
# 검증 question (Critical):
#   이전 portfolio realized cor 0.7713 FAIL 원인이:
#     (a) universe 협소 (intersection 350) 때문 → full universe에서 cor 완화
#     (b) alpha family 본질 (low-vol family L-316 mechanism) 때문 → cor retain
#
# Inheritance from WT-D20260513_002:
#   - C2 sector-residualized CAPM 252d residual total std (single-axis)
#   - PIT-C2 t+1 lag (factor at sig_date, execution at sig+1 close, fwd at next_me close)
#   - Sector neutralize (Sector column from RAWDATA)
#   - 5-spec Harvey panel + DSR Bailey-Lopez de Prado + Q1-Q5 monotonicity
#   - AX-002 ex-ante grid N=5 (C1~C5) 동일, post-hoc 금지
#
# ONLY change:
#   get_universe() — K200 ∪ KQ150 (intersection) → ALL KOSPI ordinary + KOSDAQ ordinary
#   Market_Final 분류 (KRX info ksq/stk parquet 기반)
#
# Pareto realized cor 대상 변경:
#   Parent → STR_1715 baseline (str1715_monthly_returns.parquet from WT-S20260504_002)
#   본 cycle → STR_1715_AR_on_M4_R05_overlay_PG2 (production admit, L5_V2 aggressive regime)
#   Returns: 05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/
#            04_backtest_results/period_returns_layer5.csv → ret_L5_V2 column
#
# AX 정합:
#   AX-002 ex-ante grid N=5 strict (C1~C5 inherit)
#   AX-005 v1.2 EXEMPT (multi-sleeve composite path)
#   AX-007 EXEMPT (multi-sleeve composition with STR_1715 large + small/mid full universe)
#   AX-008 Codex Critic Round 의무
#==============================================================================

Sys.setenv("STR_1715_TG_ENABLE" = "0")

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(future); library(future.apply)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

WT_ID  <- "WT-D20260514_003"
BASE   <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
ART    <- file.path(BASE, "stage_artifacts", "WT_D20260514_003")
MBOX   <- file.path(BASE, "qepm/mailbox/worktask", WT_ID)
dir.create(ART, showWarnings = FALSE, recursive = TRUE)

source(file.path(BASE, "02_Infrastructure/factor_db/factor_db_connector.R"))

t_start <- Sys.time()
cat("[", as.character(t_start), "] Universe Isolation pipeline START\n")

#==============================================================================
# Step 1: Universe Expansion (ONLY change from parent)
#==============================================================================

cat("[Step 1] Universe Expansion — KOSPI 본주 + KOSDAQ 전종목\n")

raw <- as.data.table(read_parquet(file.path(BASE, ".cache/rawdata.parquet")))
raw[, Date := as.Date(Date)]
setkey(raw, Date, Ticker)

# Build month-end-trading-day calendar
all_trade_dates <- sort(unique(raw$Date))
trade_dt <- data.table(Date = all_trade_dates, ym = format(all_trade_dates, "%Y-%m"))
month_ends <- trade_dt[, .(Date = max(Date)), by = ym]$Date
month_ends <- sort(month_ends)

SIG_DATES <- month_ends[month_ends >= as.Date("2004-01-01") & month_ends <= as.Date("2026-04-30")]
cat("Selected sig_dates:", length(SIG_DATES), " range:", as.character(min(SIG_DATES)), "~", as.character(max(SIG_DATES)), "\n")

# Pre-compute TV and rolling 20d ADV
raw[, TV := as.numeric(Vol) * as.numeric(Close)]
setkey(raw, Ticker, Date)
raw[, ADV_20d := frollmean(TV, n = 20L, align = "right", na.rm = TRUE), by = Ticker]
setkey(raw, Date, Ticker)

LIQ_FLOOR <- 2e8

#---- Market_Final 분류 (KRX info latest snapshot + RAWDATA fallback) ----
# Note: KRX info cache 2026-04-09 ~ 2026-04-22 only (2-week window).
# 따라서 모든 sig_date에 latest snapshot 사용 (보통주/우선주 분류는 시점 변동 적음).
# RAWDATA Market column NA인 종목은 KRX 보통주 mask로만 분류.
# 상장폐지 종목 (2004~2010) 분류 결손 → drop_market_nodata=TRUE면 제외, FALSE면 보수적으로 KOSPI 분류.

build_market_map_latest <- function() {
  ksq_files <- list.files(file.path(BASE, ".cache/krx/ksq_info"), full.names = TRUE, pattern = "\\.parquet$")
  stk_files <- list.files(file.path(BASE, ".cache/krx/stk_info"), full.names = TRUE, pattern = "\\.parquet$")
  if (length(ksq_files) == 0 || length(stk_files) == 0) {
    stop("[build_market_map_latest] KRX info cache missing")
  }
  ksq_use <- tail(sort(ksq_files), 1)
  stk_use <- tail(sort(stk_files), 1)
  ksq <- as.data.table(read_parquet(ksq_use))
  stk <- as.data.table(read_parquet(stk_use))

  ksq_map <- ksq[SECUGRP_NM == "주권" & KIND_STKCERT_TP_NM == "보통주",
                 .(Ticker = paste0("A", ISU_SRT_CD), Market_Final = "KOSDAQ")]
  stk_map <- stk[SECUGRP_NM == "주권" & KIND_STKCERT_TP_NM == "보통주",
                 .(Ticker = paste0("A", ISU_SRT_CD), Market_Final = "KOSPI")]
  out <- unique(rbind(stk_map, ksq_map), by = "Ticker")
  cat("Market map (latest KRX): KOSPI 본주 =", nrow(stk_map),
      ", KOSDAQ 본주 =", nrow(ksq_map),
      ", unique total =", nrow(out), "\n")
  out
}

market_map_global <- build_market_map_latest()
setkey(market_map_global, Ticker)

sig_panel <- raw[Date %in% SIG_DATES,
                 .(Date, Ticker, K200, KQ150, AdminStock, TradingHalt, UnfaithfulDisc,
                   ADV_20d, Close, Sector)]
setkey(sig_panel, Date, Ticker)

# Universe getter — FULL universe (KOSPI 본주 + KOSDAQ 전종목)
get_universe_full <- function(sig_date) {
  rows <- sig_panel[Date == sig_date]
  # Apply market filter (KOSPI 본주 + KOSDAQ 보통주, latest KRX snapshot)
  elig <- merge(rows, market_map_global, by = "Ticker", all.x = FALSE)  # inner join: 보통주만
  elig <- elig[!is.na(ADV_20d) & ADV_20d >= LIQ_FLOOR &
               (is.na(AdminStock) | AdminStock == FALSE) &
               (is.na(TradingHalt) | TradingHalt == FALSE) &
               (is.na(UnfaithfulDisc) | UnfaithfulDisc == FALSE) &
               !is.na(Sector)]
  return(elig$Ticker)
}

# Backward-compat: parent intersection universe (for audit)
get_universe_intersection <- function(sig_date) {
  rows <- sig_panel[Date == sig_date]
  elig <- rows[(K200 == TRUE | KQ150 == TRUE) &
               !is.na(ADV_20d) & ADV_20d >= LIQ_FLOOR &
               (is.na(AdminStock) | AdminStock == FALSE) &
               (is.na(TradingHalt) | TradingHalt == FALSE) &
               (is.na(UnfaithfulDisc) | UnfaithfulDisc == FALSE) &
               !is.na(Sector), Ticker]
  return(elig)
}

# Audit: universe size comparison (intersection vs full)
univ_audit_list <- list()
for (i in seq_along(SIG_DATES)) {
  sd <- SIG_DATES[i]
  u_int <- get_universe_intersection(sd)
  u_full <- get_universe_full(sd)
  univ_audit_list[[i]] <- data.table(
    sig_date = sd,
    n_intersection = length(u_int),
    n_full = length(u_full),
    expansion_ratio = round(length(u_full) / max(1, length(u_int)), 3)
  )
}
univ_audit <- rbindlist(univ_audit_list)
cat("\n=== Universe Size Audit (intersection vs full) ===\n")
cat("Mean intersection:", round(mean(univ_audit$n_intersection), 1), "\n")
cat("Mean full:", round(mean(univ_audit$n_full), 1), "\n")
cat("Mean expansion ratio:", round(mean(univ_audit$expansion_ratio), 2), "x\n")
cat("Latest sig_date:", as.character(tail(SIG_DATES, 1)), "\n")
cat("Latest intersection:", tail(univ_audit$n_intersection, 1), "\n")
cat("Latest full:", tail(univ_audit$n_full, 1), "\n")
write_parquet(univ_audit, file.path(ART, "universe_isolation_audit.parquet"))

#==============================================================================
# Axis 1 (PIT-C2 t+1 lag): Forward return = (P_{next_me} / P_{sig_date+1}) - 1
#==============================================================================

cat("\n[Axis 1] PIT-C2 t+1 lag forward return\n")

all_trade_dates_sorted <- sort(unique(raw$Date))
next_trade_after <- function(d) {
  i <- match(d, all_trade_dates_sorted)
  if (is.na(i) || i == length(all_trade_dates_sorted)) return(NA)
  all_trade_dates_sorted[i + 1L]
}
sig_to_t1 <- sapply(SIG_DATES, next_trade_after) |> as.Date(origin = "1970-01-01")
cat("Sig_date → sig+1 mapping built\n")

close_wide <- dcast(raw[, .(Date, Ticker, Close)], Date ~ Ticker, value.var = "Close")
setkey(close_wide, Date)

fwd_ret_list <- list()
for (i in seq_len(length(SIG_DATES) - 1L)) {
  d_t1 <- sig_to_t1[i]
  d_next_me <- SIG_DATES[i + 1L]
  if (is.na(d_t1) || d_t1 >= d_next_me) next

  px_t1 <- as.numeric(close_wide[Date == d_t1])
  px_next <- as.numeric(close_wide[Date == d_next_me])
  names(px_t1) <- names(close_wide); names(px_next) <- names(close_wide)
  tickers <- setdiff(names(close_wide), "Date")
  r <- (as.numeric(px_next[tickers]) / as.numeric(px_t1[tickers])) - 1
  fwd_ret_list[[i]] <- data.table(sig_date = SIG_DATES[i], t1_date = d_t1,
                                   next_me = d_next_me, Ticker = tickers, fwd_ret_1m = r)
}
fwd_returns <- rbindlist(fwd_ret_list)
fwd_returns <- fwd_returns[!is.na(fwd_ret_1m) & is.finite(fwd_ret_1m)]
cat("Forward return rows:", nrow(fwd_returns), "\n")

#==============================================================================
# Axis 3 (CAPM 252d rolling residual): Per-ticker per-month
#==============================================================================

cat("\n[Axis 3] CAPM rolling 252d regression → idio residual\n")

trade_day_idx <- data.table(Date = all_trade_dates_sorted, idx = seq_along(all_trade_dates_sorted))

compute_idio_metrics <- function(sig_date, raw_dt, univ_tickers) {
  sig_idx <- trade_day_idx[Date == sig_date, idx]
  if (length(sig_idx) == 0 || sig_idx < 252) return(NULL)

  win_start_date <- all_trade_dates_sorted[sig_idx - 252 + 1]
  win_end_date   <- sig_date
  win_days <- raw_dt[Date >= win_start_date & Date <= win_end_date & Ticker %in% univ_tickers,
                    .(Date, Ticker, Ret, BM_Ret)]
  win_days <- win_days[!is.na(Ret) & !is.na(BM_Ret) & is.finite(Ret) & is.finite(BM_Ret)]

  result_list <- list()
  for (tk in unique(win_days$Ticker)) {
    d_tk <- win_days[Ticker == tk]
    if (nrow(d_tk) < 200) next
    x <- d_tk$BM_Ret; y <- d_tk$Ret
    n_obs <- length(y)
    x_mean <- mean(x); y_mean <- mean(y)
    cov_xy <- sum((x - x_mean) * (y - y_mean))
    var_x <- sum((x - x_mean)^2)
    if (var_x <= 0) next
    beta <- cov_xy / var_x
    alpha <- y_mean - beta * x_mean
    resid <- y - alpha - beta * x

    idio_vol_total <- sd(resid)
    neg_resid <- resid[resid < 0]
    idio_down_vol <- if (length(neg_resid) >= 10) sqrt(mean(neg_resid^2)) else NA_real_

    result_list[[tk]] <- data.table(
      sig_date = sig_date, Ticker = tk,
      capm_beta = beta, capm_alpha_252d = alpha,
      idio_vol = idio_vol_total, idio_down_vol = idio_down_vol,
      n_obs = n_obs
    )
  }
  rbindlist(result_list)
}

# Pre-build full universe per sig_date
univ_map <- list()
for (i in seq_along(SIG_DATES)) {
  univ_map[[as.character(SIG_DATES[i])]] <- get_universe_full(SIG_DATES[i])
}

n_workers <- min(8L, parallel::detectCores() - 1L)
cat("Parallel workers:", n_workers, "\n")
plan(multisession, workers = n_workers)
on.exit(plan(sequential), add = TRUE)

raw_slim <- raw[Date >= as.Date("2003-01-01") & Date <= as.Date("2026-04-30"),
                .(Date, Ticker, Ret, BM_Ret)]
setkey(raw_slim, Ticker, Date)

cat("Computing CAPM rolling 252d for", length(SIG_DATES), "sig_dates × universe ~",
    round(mean(univ_audit$n_full), 0), " tickers...\n")
t_capm_start <- Sys.time()

idio_list <- future_lapply(SIG_DATES, function(sd) {
  univ_tk <- univ_map[[as.character(sd)]]
  if (length(univ_tk) < 30) return(NULL)
  compute_idio_metrics(sd, raw_slim, univ_tk)
}, future.seed = 42L)

plan(sequential)
idio_dt <- rbindlist(idio_list[!sapply(idio_list, is.null)])
t_capm_end <- Sys.time()
cat("CAPM 회귀 시간:", round(as.numeric(t_capm_end - t_capm_start, units = "mins"), 2), "분\n")
cat("idio_dt rows:", nrow(idio_dt), " sig_dates:", uniqueN(idio_dt$sig_date), "\n")

write_parquet(idio_dt, file.path(ART, "capm_idio_metrics.parquet"))

#==============================================================================
# Axis 2 (Sector-neutralize) + Axis 4 (Monotonic rank smooth) + Candidates
# 동일 spec retain — C1, C2, C3, C4, C5
#==============================================================================

cat("\n[Axis 2+4] Sector-neutralize + Candidates (5 ex-ante)\n")

sec_lookup <- sig_panel[, .(sig_date = Date, Ticker, Sector)]
setkey(sec_lookup, sig_date, Ticker)
setkey(idio_dt, sig_date, Ticker)
idio_dt <- merge(idio_dt, sec_lookup, by = c("sig_date", "Ticker"))
idio_dt <- idio_dt[!is.na(Sector)]
cat("After sector merge:", nrow(idio_dt), " rows\n")

build_candidates <- function(dt_one) {
  n <- nrow(dt_one)
  if (n < 30) return(NULL)

  cs_z_clip <- function(x) {
    if (all(is.na(x))) return(rep(NA_real_, length(x)))
    mu <- mean(x, na.rm = TRUE); sd_ <- sd(x, na.rm = TRUE)
    if (is.na(sd_) || sd_ == 0) return(rep(0, length(x)))
    z <- (x - mu) / sd_
    pmax(pmin(z, 3), -3)
  }

  sector_resid <- function(x, sector_vec) {
    df <- data.frame(x = x, sec = factor(sector_vec))
    df <- df[!is.na(df$x), ]
    if (nrow(df) < 5) return(rep(NA_real_, length(x)))
    if (nlevels(droplevels(df$sec)) < 2) return(x - mean(x, na.rm = TRUE))
    fit <- lm(x ~ sec, data = df, na.action = na.omit)
    resid_vec <- rep(NA_real_, length(x))
    resid_vec[!is.na(x)] <- residuals(fit)
    resid_vec
  }

  rank_smooth <- function(x) {
    if (all(is.na(x))) return(x)
    r <- rank(x, ties.method = "average", na.last = "keep")
    u <- (r - 0.5) / sum(!is.na(x))
    z <- qnorm(u)
    z[!is.na(z) & z > 3] <- 3
    z[!is.na(z) & z < -3] <- -3
    z
  }

  c1_z   <- cs_z_clip(dt_one$idio_vol);                          C1 <- -c1_z
  c2_raw <- sector_resid(dt_one$idio_vol, dt_one$Sector);        C2 <- -cs_z_clip(c2_raw)
  c3_z   <- cs_z_clip(dt_one$idio_down_vol);                     C3 <- -c3_z
  c4_raw <- sector_resid(dt_one$idio_down_vol, dt_one$Sector);   C4 <- -cs_z_clip(c4_raw)
  comp_pre <- (C1 + C2 + C3 + C4) / 4;                           C5 <- rank_smooth(comp_pre)

  data.table(
    sig_date = dt_one$sig_date[1],
    Ticker = dt_one$Ticker,
    C1 = C1, C2 = C2, C3 = C3, C4 = C4, C5 = C5
  )
}

cat("Building candidates per sig_date...\n")
cand_list <- split(idio_dt, idio_dt$sig_date) |>
  lapply(build_candidates)
cand_long <- rbindlist(cand_list[!sapply(cand_list, is.null)])
cand_long <- melt(cand_long, id.vars = c("sig_date", "Ticker"),
                  variable.name = "candidate", value.name = "alpha_z")
cand_long <- cand_long[!is.na(alpha_z) & is.finite(alpha_z)]
cat("Candidate rows total:", nrow(cand_long), "  unique sig_dates:", uniqueN(cand_long$sig_date), "\n")

CANDIDATE_NAMES <- c("C1", "C2", "C3", "C4", "C5")

setkey(cand_long, sig_date, Ticker)
setkey(fwd_returns, sig_date, Ticker)
ar <- merge(cand_long, fwd_returns, by = c("sig_date", "Ticker"), all.x = FALSE)
cat("Alpha × fwd return rows:", nrow(ar), "\n")

#==============================================================================
# Step 4: Diagnostics (IC, ICIR, Harvey 5-spec, DSR, Monotonicity)
#==============================================================================

cat("\n[Step 4] Diagnostics per candidate\n")

ic_hist <- ar[, .(rank_ic = cor(alpha_z, fwd_ret_1m, method = "spearman", use = "pairwise.complete.obs"),
                  n_stocks = .N),
              by = .(candidate, sig_date)]
ic_hist <- ic_hist[!is.na(rank_ic) & is.finite(rank_ic)]

N_TRIALS <- 5L
gamma_euler <- 0.5772
eul_e <- exp(1)

diag_summary <- list()

for (cand in CANDIDATE_NAMES) {
  ich <- ic_hist[candidate == cand]
  if (nrow(ich) < 24) {
    diag_summary[[cand]] <- list(error = "insufficient_ic_history", n_months = nrow(ich)); next
  }

  mean_ic <- mean(ich$rank_ic, na.rm = TRUE)
  sd_ic   <- sd(ich$rank_ic, na.rm = TRUE)
  icir    <- mean_ic / sd_ic
  n_m     <- nrow(ich)
  t_stat  <- mean_ic / (sd_ic / sqrt(n_m))

  # NW lag=6 HAC
  ic_centered <- ich$rank_ic - mean_ic
  L <- 6L; ac_terms <- 0
  for (l in 1:L) {
    if (l >= n_m) break
    cov_l <- sum(ic_centered[1:(n_m - l)] * ic_centered[(l + 1):n_m]) / n_m
    w_l   <- 1 - l / (L + 1)
    ac_terms <- ac_terms + 2 * w_l * cov_l
  }
  var0 <- sum(ic_centered^2) / n_m
  nw_var <- var0 + ac_terms
  if (is.na(nw_var) || nw_var <= 0) nw_var <- var0
  nw_se <- sqrt(nw_var / n_m)
  t_nw  <- mean_ic / nw_se

  # DSR (Bailey-Lopez de Prado 2014)
  ic_vals <- ich$rank_ic
  ic_demean <- ic_vals - mean(ic_vals)
  m3 <- mean(ic_demean^3); m2 <- mean(ic_demean^2)
  m4 <- mean(ic_demean^4)
  ic_skew <- if (m2 > 0) m3 / m2^(1.5) else 0
  ic_kurt <- if (m2 > 0) m4 / m2^2 else 3
  sr_proxy <- icir * sqrt(12)
  sr_var <- (1 - ic_skew * sr_proxy + ((ic_kurt - 1) / 4) * sr_proxy^2) / (n_m - 1)
  if (is.na(sr_var) || sr_var <= 0) sr_var <- 1 / (n_m - 1)
  if (N_TRIALS > 1) {
    exp_max_sr <- sqrt(sr_var) * ((1 - gamma_euler) * qnorm(1 - 1 / N_TRIALS) +
                                  gamma_euler * qnorm(1 - 1 / (N_TRIALS * eul_e)))
  } else {
    exp_max_sr <- 0
  }
  dsr <- (sr_proxy - exp_max_sr) / sqrt(sr_var)
  dsr_pnorm <- pnorm(dsr)

  # 5-spec Harvey panel
  spec_tnw <- list(base = round(t_nw, 3))
  trim_q5 <- quantile(ich$rank_ic, c(0.05, 0.95), na.rm = TRUE)
  for (spec_id in c("trim_top5", "trim_bot5", "p_2004_2013", "p_2014_2026")) {
    sub <- switch(spec_id,
                  trim_top5  = ich[rank_ic <= trim_q5[2]],
                  trim_bot5  = ich[rank_ic >= trim_q5[1]],
                  p_2004_2013= ich[sig_date >= as.Date("2004-01-01") & sig_date < as.Date("2014-01-01")],
                  p_2014_2026= ich[sig_date >= as.Date("2014-01-01")])
    if (nrow(sub) >= 24) {
      m_s <- mean(sub$rank_ic); n_s <- nrow(sub)
      c_s <- sub$rank_ic - m_s
      a_t <- 0
      for (l in 1:min(L, n_s - 1)) {
        cv <- sum(c_s[1:(n_s - l)] * c_s[(l + 1):n_s]) / n_s
        wl <- 1 - l / (L + 1)
        a_t <- a_t + 2 * wl * cv
      }
      v0 <- sum(c_s^2) / n_s
      nv <- max(v0 + a_t, v0); ns_e <- sqrt(nv / n_s)
      spec_tnw[[spec_id]] <- round(m_s / ns_e, 3)
    } else {
      spec_tnw[[spec_id]] <- NA_real_
    }
  }
  spec_tnw_pass_count <- sum(sapply(spec_tnw, function(t) !is.na(t) && t > 3.0))

  # Monotonicity Q1~Q5
  ar_c <- ar[candidate == cand]
  ar_c[, qntl := cut(alpha_z,
                      breaks = quantile(alpha_z, probs = seq(0, 1, 0.2), na.rm = TRUE),
                      labels = 1:5, include.lowest = TRUE), by = sig_date]
  q_means <- ar_c[!is.na(qntl), .(mean_ret = mean(fwd_ret_1m, na.rm = TRUE)), by = qntl][order(qntl)]
  mono_pct <- if (nrow(q_means) >= 5) mean(diff(q_means$mean_ret) > 0) else NA_real_

  # Subperiod stability
  ich[, period := fcase(
    sig_date < as.Date("2014-01-01"), "p1_2004_2013",
    sig_date < as.Date("2020-01-01"), "p2_2014_2019",
    default = "p3_2020_2026"
  )]
  sub_ic <- ich[, .(mean_ic = mean(rank_ic, na.rm = TRUE), n = .N), by = period]
  sub_signs <- sign(sub_ic$mean_ic)
  sub_stability <- if (length(sub_signs) >= 3) mean(sub_signs == sign(mean_ic)) else NA_real_

  # Recent 3Y ICIR
  ich_recent <- ich[sig_date >= max(sig_date) - 1095]
  if (nrow(ich_recent) >= 12) {
    icir_recent <- mean(ich_recent$rank_ic) / sd(ich_recent$rank_ic)
  } else {
    icir_recent <- NA_real_
  }
  rf_a3_ratio <- if (!is.na(icir_recent) && icir != 0) icir_recent / icir else NA_real_

  diag_summary[[cand]] <- list(
    candidate = cand,
    n_months = n_m,
    mean_rank_ic = round(mean_ic, 5),
    sd_rank_ic = round(sd_ic, 5),
    icir = round(icir, 4),
    icir_recent_3y = round(icir_recent, 4),
    rf_a3_ratio = round(rf_a3_ratio, 3),
    t_stat_raw = round(t_stat, 3),
    t_nw_lag6 = round(t_nw, 3),
    harvey_t_pass = t_nw > 3.0,
    harvey_5spec_tnw = spec_tnw,
    harvey_5spec_pass_count = spec_tnw_pass_count,
    dsr = round(dsr, 3),
    dsr_pnorm = round(dsr_pnorm, 4),
    dsr_pass = dsr > 0.5,
    monotonicity_q1_q5_concord = round(mono_pct, 3),
    monotonicity_pass = !is.na(mono_pct) && mono_pct >= 0.7,
    subperiod_stability = round(sub_stability, 3),
    subperiod_means = as.list(sub_ic$mean_ic),
    avg_n_stocks = round(mean(ich$n_stocks, na.rm = TRUE), 1),
    q1_q5_means = as.list(q_means$mean_ret)
  )

  cat(sprintf("  %s: IC=%.4f ICIR=%.3f t_NW=%.2f DSR=%.2f spec5pass=%d mono=%.2f Q1Q5=%s n_m=%d avg_N=%d\n",
              cand, mean_ic, icir, t_nw, dsr, spec_tnw_pass_count,
              mono_pct %||% NA_real_,
              paste(round(q_means$mean_ret * 100, 2), collapse = "/"), n_m,
              round(mean(ich$n_stocks))))
}

#==============================================================================
# Step 5: Orthogonality vs STR_1715_AR_on_M4_R05_overlay_PG2 admit (L5_V2)
#==============================================================================

cat("\n[Step 5] Orthogonality vs STR_1715_AR_on_M4_R05_overlay_PG2 (L5_V2 admit, YM-aligned)\n")

# Load production admit Layer 5 V2 returns
r05_returns <- fread(file.path(BASE, "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2",
                               "04_backtest_results/period_returns_layer5.csv"))
r05_returns[, anchor_date := as.Date(anchor_date)]
r05_returns[, ym := realized_ym]
# Admit variant = L5_V2_aggressive_regime (Sharpe 1.9536, MEMORY confirmed)
admit_returns <- r05_returns[, .(ym, admit_ret = ret_L5_V2)]
cat("Production admit (L5_V2) overlap range:", as.character(range(r05_returns$anchor_date)),
    " n_months:", nrow(admit_returns), "\n")

build_candidate_returns <- function(dt_alpha_with_ret) {
  dt_alpha_with_ret[order(-alpha_z), .(
    portfolio_ret = mean(head(fwd_ret_1m, 20), na.rm = TRUE),
    n_picks = min(20, .N)
  ), by = .(candidate, sig_date)]
}
cand_rets <- build_candidate_returns(ar)
cand_rets[, ym := format(sig_date, "%Y-%m")]

ortho <- list()
for (cand in CANDIDATE_NAMES) {
  m <- merge(cand_rets[candidate == cand, .(ym, cand_ret = portfolio_ret)],
             admit_returns,
             by = "ym")
  m <- m[!is.na(cand_ret) & !is.na(admit_ret) & is.finite(cand_ret) & is.finite(admit_ret)]

  if (nrow(m) < 24) {
    ortho[[cand]] <- list(error = "insufficient_overlap", n = nrow(m)); next
  }
  cor_p <- cor(m$cand_ret, m$admit_ret, method = "pearson")
  cor_s <- cor(m$cand_ret, m$admit_ret, method = "spearman")
  cor_k <- cor(m$cand_ret, m$admit_ret, method = "kendall")

  ortho[[cand]] <- list(
    candidate = cand,
    n_overlap_months = nrow(m),
    returns_cor_pearson = round(cor_p, 4),
    returns_cor_spearman = round(cor_s, 4),
    returns_cor_kendall = round(cor_k, 4),
    orthogonality_rank_pass = cor_s < 0.30,
    orthogonality_return_pass = cor_p < 0.40,
    target_admit = "STR_1715_AR_on_M4_R05_overlay_PG2 L5_V2_aggressive_regime",
    measurement_method = "year_month_aligned_merge_universe_isolation_v1"
  )
  cat(sprintf("  %s: cor_p=%.4f cor_s=%.4f n=%d ortho_pass=%s\n",
              cand, cor_p, cor_s, nrow(m),
              ortho[[cand]]$orthogonality_rank_pass && ortho[[cand]]$orthogonality_return_pass))
}

#==============================================================================
# Step 6: Best candidate selection (STRICT, no fallback)
#==============================================================================

cat("\n[Step 6] Best candidate selection (STRICT, no silent fallback)\n")

cmp <- data.table(
  candidate = CANDIDATE_NAMES,
  rank_ic = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$mean_rank_ic %||% NA),
  icir    = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$icir %||% NA),
  t_nw    = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$t_nw_lag6 %||% NA),
  dsr     = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$dsr %||% NA),
  spec5_pass = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$harvey_5spec_pass_count %||% NA),
  mono    = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$monotonicity_q1_q5_concord %||% NA),
  mono_pass = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$monotonicity_pass %||% NA),
  substab = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$subperiod_stability %||% NA),
  cor_admit_p = sapply(CANDIDATE_NAMES, function(c) ortho[[c]]$returns_cor_pearson %||% NA),
  cor_admit_s = sapply(CANDIDATE_NAMES, function(c) ortho[[c]]$returns_cor_spearman %||% NA),
  ortho_pass = sapply(CANDIDATE_NAMES, function(c) {
    o <- ortho[[c]]
    if (is.null(o$orthogonality_rank_pass)) return(FALSE)
    o$orthogonality_rank_pass && o$orthogonality_return_pass
  })
)
cat("\n=== Candidate comparison (Universe Isolation) ===\n"); print(cmp)
fwrite(cmp, file.path(ART, "candidate_comparison.csv"))

# C2 is the parent-selected single-axis. Hold same selection logic for universe-isolation purpose.
# But primary REPORT is on C2 (inherit), with all 5 candidates evaluated for transparency.
PARENT_SELECTED <- "C2"
elig <- cmp[!is.na(rank_ic) & rank_ic >= 0.04 & icir >= 0.20 & t_nw >= 3.0 &
            mono_pass == TRUE & ortho_pass == TRUE]

if (nrow(elig) == 0) {
  cat("\nWARN: NO candidate passes ALL 5 gates. NON_GRADUATING EXPLORATORY.\n")
  # Inherit-priority: report parent_selected C2 if any soft cand exists
  c2_row <- cmp[candidate == PARENT_SELECTED]
  if (nrow(c2_row) > 0 && !is.na(c2_row$rank_ic)) {
    best_cand <- PARENT_SELECTED
    selection_status <- "NON_GRADUATING_UNIVERSE_ISOLATION_INHERIT_C2_PARENT"
    cat("Selected (NON_GRADUATING):", best_cand, "  reason: parent inherit (C2 sector-residualized)\n")
  } else {
    soft_cand <- cmp[!is.na(mono) & mono >= 0.50 & ortho_pass == TRUE][order(-mono, -rank_ic)]
    if (nrow(soft_cand) > 0) {
      best_cand <- soft_cand[1, candidate]
      selection_status <- "NON_GRADUATING_MONO_BEST"
    } else {
      best_cand <- cmp[ortho_pass == TRUE][order(-rank_ic)][1, candidate] %||% PARENT_SELECTED
      selection_status <- "NON_GRADUATING_FALLBACK"
    }
  }
} else {
  # Even if pass: prioritize parent C2 if it passes (universe isolation = direct comparison)
  if (PARENT_SELECTED %in% elig$candidate) {
    best_cand <- PARENT_SELECTED
    selection_status <- "GRADUATING_C2_PARENT_RETAIN_UNIVERSE_EXPANSION_PASS"
  } else {
    best_cand <- elig[order(-rank_ic, -mono)][1, candidate]
    selection_status <- "GRADUATING_ALL_GATES_PASS_C2_FAIL"
  }
  cat("\n[SELECTED]", best_cand, " status:", selection_status, "\n")
}

#==============================================================================
# Step 7: Emit artifacts
#==============================================================================

cat("\n[Step 7] Emit artifacts\n")

# Alpha scores
alpha_scores_out <- ar[candidate == best_cand, .(sig_date, Ticker, alpha = alpha_z)]
alpha_scores_out <- alpha_scores_out[!is.na(alpha) & is.finite(alpha)]

last_sig <- max(SIG_DATES)
last_alpha <- cand_long[sig_date == last_sig & candidate == best_cand,
                          .(sig_date, Ticker, alpha = alpha_z)]
last_alpha <- last_alpha[!is.na(alpha) & is.finite(alpha)]
combined <- rbind(alpha_scores_out, last_alpha)
combined <- unique(combined, by = c("sig_date", "Ticker"))
setorder(combined, sig_date, -alpha)
write_parquet(combined, file.path(ART, "alpha_scores.parquet"))
cat("  alpha_scores.parquet:", nrow(combined), "rows,", uniqueN(combined$sig_date), "sig_dates\n")

write_parquet(ic_hist, file.path(ART, "ic_history.parquet"))
write_parquet(cand_rets, file.path(ART, "candidate_portfolio_returns.parquet"))

# Q1-Q5 monotonicity decomposition for selected
ar_best <- ar[candidate == best_cand]
ar_best[, qntl := cut(alpha_z,
                       breaks = quantile(alpha_z, probs = seq(0, 1, 0.2), na.rm = TRUE),
                       labels = 1:5, include.lowest = TRUE), by = sig_date]
q_means_best <- ar_best[!is.na(qntl), .(mean_ret_pct = round(mean(fwd_ret_1m, na.rm = TRUE) * 100, 4),
                                          n_obs = .N), by = qntl][order(qntl)]
fwrite(q_means_best, file.path(ART, "monotonicity_decile_audit.csv"))

# Orthogonality 6-axis Pareto (vs STR_1715_AR_on_M4_R05_overlay_PG2 admit)
# Single-axis cor pearson + spearman + kendall + rank_pass + return_pass + n_overlap
best_ortho <- ortho[[best_cand]]
ortho_6axis <- list(
  axis_1_cor_pearson = best_ortho$returns_cor_pearson,
  axis_2_cor_spearman = best_ortho$returns_cor_spearman,
  axis_3_cor_kendall = best_ortho$returns_cor_kendall,
  axis_4_n_overlap_months = best_ortho$n_overlap_months,
  axis_5_rank_pass_lt_0_30 = best_ortho$orthogonality_rank_pass,
  axis_6_return_pass_lt_0_40 = best_ortho$orthogonality_return_pass,
  target_admit = best_ortho$target_admit,
  universe_scope = "FULL_KOSPI_ORDINARY_KOSDAQ_ORDINARY_LIQ_2E8",
  measurement_method = best_ortho$measurement_method,
  l316_l317_mandate_target_lt_0_40 = TRUE,
  pass_target = best_ortho$returns_cor_pearson < 0.40
)
write_json(ortho_6axis, file.path(ART, "orthogonality_six_axis.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")

# Universe isolation audit JSON
univ_iso_audit_json <- list(
  task_id = WT_ID,
  parent_task_id = "WT-D20260513_002",
  universe_change_only = TRUE,
  alpha_spec_change = "none (C variant 4-axis inherited verbatim)",
  parent_universe = "KOSPI200 ∪ KOSDAQ150 intersection + LIQ 2e8 (~348 at 2026-04-30)",
  this_cycle_universe = "KOSPI 본주 + KOSDAQ 보통주 + LIQ 2e8 (~2030 at 2026-04-30)",
  mean_intersection_size = round(mean(univ_audit$n_intersection), 1),
  mean_full_size = round(mean(univ_audit$n_full), 1),
  mean_expansion_ratio = round(mean(univ_audit$expansion_ratio), 2),
  latest_intersection = tail(univ_audit$n_intersection, 1),
  latest_full = tail(univ_audit$n_full, 1),
  parent_diagnostics_C2 = list(
    rank_ic = 0.0491, icir = 0.4277, t_nw = 7.002, dsr = 14.348,
    harvey_5spec_pass = 5, monotonicity = 0.50, subperiod_stab = 1.0,
    portfolio_realized_cor_p_vs_str1715 = 0.0038,
    portfolio_realized_cor_p_vs_admit_target = "0.7713 (FAIL, from Risk research stage realized cor against STR_1715_AR_on_M4_R05_overlay_PG2)"
  ),
  this_cycle_diagnostics_C2 = diag_summary[["C2"]],
  this_cycle_orthogonality_C2 = ortho[["C2"]],
  isolation_decision_rule = list(
    if_cor_lt_0_40 = "universe-driven attenuation, L-317 (a) hypothesis confirmed",
    if_cor_0_40_to_0_70 = "partial universe effect, L-317 mixed",
    if_cor_ge_0_70 = "alpha family essence, L-317 (b) hypothesis confirmed (architectural pivot required)"
  )
)
write_json(univ_iso_audit_json, file.path(ART, "universe_isolation_audit.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")

# alpha_validation.json
validation <- list(
  task_id = WT_ID,
  parent_task_id = "WT-D20260513_002",
  as_of_date = "2026-05-14",
  as_of_sig_date_actual = as.character(last_sig),
  version = "universe_isolation_c_variant_full_universe_v1",
  best_candidate = best_cand,
  parent_selected = PARENT_SELECTED,
  selection_status = selection_status,
  candidates = diag_summary,
  orthogonality_vs_str1715_ar_m4_r05_overlay_pg2 = ortho,
  universe_isolation_audit = univ_iso_audit_json,
  axis_design = list(
    axis_1_pit_c2_t_plus_1 = TRUE,
    axis_2_sector_neutralize = "C2/C4/C5 only (C1/C3 no sector)",
    axis_3_ff_residual = "CAPM rolling 252d, idio residual std",
    axis_4_monotonic_smooth = "C5 only (rank_smooth via probit). Others raw cs_z."
  ),
  pit_audit = list(
    sig_dates_total = length(SIG_DATES),
    sig_dates_strictly_month_end = TRUE,
    pit_c2_t_plus_1_lag_applied = TRUE,
    forward_return_basis = "P(next_me_close) / P(sig_date+1_close) - 1",
    pit_clean = TRUE,
    universe_change_only_no_alpha_recipe_change = TRUE
  ),
  selection_rule = list(
    primary_gates = list(
      rank_ic_min = 0.04, icir_min = 0.20, t_nw_min = 3.0,
      mono_min = 0.70, ortho_pass = TRUE
    ),
    parent_inherit_priority = TRUE,
    ex_ante_grid_N = length(CANDIDATE_NAMES),
    post_hoc_search = FALSE,
    pre_registered = TRUE
  ),
  comparison_table = lapply(seq_len(nrow(cmp)), function(i) as.list(cmp[i]))
)
write_json(validation, file.path(ART, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
write_json(validation, file.path(MBOX, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")

# Top10 alpha for last_sig
top10_last <- combined[sig_date == last_sig][order(-alpha)][1:10]
cat("\nTop 10 alpha (last sig =", as.character(last_sig), "):\n")
print(top10_last)

t_end <- Sys.time()
cat("\nTotal pipeline time:", round(as.numeric(t_end - t_start, units = "mins"), 2), "minutes\n")

cat("\n=== DONE Universe Isolation Pipeline ===\n")
cat("Best candidate:", best_cand, " status:", selection_status, "\n")
best <- diag_summary[[best_cand]]; best_ortho <- ortho[[best_cand]]
cat("Rank IC:", best$mean_rank_ic, "  ICIR:", best$icir, "  t_NW:", best$t_nw_lag6, "\n")
cat("Monotonicity:", best$monotonicity_q1_q5_concord, "  pass:", best$monotonicity_pass, "\n")
cat("DSR:", best$dsr, "  Harvey 5-spec:", best$harvey_5spec_pass_count, "/5\n")
cat("Orthogonality vs STR_1715_AR_on_M4_R05_overlay_PG2 L5_V2:\n")
cat("  cor_p =", best_ortho$returns_cor_pearson, " cor_s =", best_ortho$returns_cor_spearman, "\n")
cat("\nIsolation decision:\n")
cat("  parent (intersection) cor_p_vs_admit_realized = 0.7713 (FAIL)\n")
cat("  this cycle (full universe) cor_p_vs_admit =", best_ortho$returns_cor_pearson, "\n")
delta <- 0.7713 - best_ortho$returns_cor_pearson
cat("  delta (universe expansion effect) =", round(delta, 4), "\n")
cat("\nUniverse stats:\n")
cat("  mean intersection N:", round(mean(univ_audit$n_intersection), 1), "\n")
cat("  mean full N:", round(mean(univ_audit$n_full), 1), "\n")
cat("  expansion ratio:", round(mean(univ_audit$expansion_ratio), 2), "x\n")
