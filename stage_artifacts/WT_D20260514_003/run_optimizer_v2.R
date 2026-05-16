#==============================================================================
# WT-D20260514_003 — Optimizer Research v2 — Correct 4-Sleeve Composite
#
# Architecture (PG2 admit lineage inheritance):
#   STR_1715 sleeve (with M4 + AR + R05 V2 overlay inherited):
#     β_str1715(t) × combined_overlay_V2(t) × inv_vol_top20_weights(t)
#   C2 sleeve (new, no overlay):
#     β_c2(t) × alpha_weighted_top20_sector_cap_weights(t)
#   Cash residual:
#     1 - β_str1715 × overlay - β_c2
#
# Optimizer decides: (β_str1715, β_c2) per sig_date
# Constraints: β_str1715 + β_c2 ≤ 1, both ≥ 0
# Methods: 5 (MVO / HRP / ERC / CVaR_LP / Ensemble) at sleeve allocation level
#
# Backtest Contract v1.0 (PerformanceAnalytics standard functions only)
#==============================================================================

suppressMessages({
  library(arrow); library(data.table); library(jsonlite); library(quadprog); library(corpcor)
  library(PerformanceAnalytics); library(xts)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)
WT_ID <- "WT-D20260514_003"
STAGE <- "stage_artifacts/WT_D20260514_003"
OPTWS <- file.path(STAGE, "optimizer_workspace")

# ─── Load data ────────────────────────────────────────────
suppressMessages({
  RAWDATA <- as.data.table(read_parquet(".cache/RAWDATA.parquet"))
  BM_DT   <- as.data.table(read_parquet(".cache/benchmark.parquet"))
})
setkey(RAWDATA, Date, Ticker)
setkey(BM_DT, Date)

c2_alpha      <- as.data.table(read_parquet(file.path(STAGE, "alpha_scores.parquet")))
setnames(c2_alpha, "sig_date", "Date")
setkey(c2_alpha, Date, Ticker)
c2_alpha[, ym := format(Date, "%Y-%m")]

str1715_alpha <- as.data.table(read_parquet(
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet"
))
setkey(str1715_alpha, Date, Ticker)
str1715_alpha[, ym := format(Date, "%Y-%m")]

# PG2 admit schedule
pg2_sched <- fread("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/weights_267m_timeseries.csv")
pg2_sched[, as_of_date := as.Date(as_of_date)]
pg2_sched[, decision_date := as.Date(decision_date)]
# realized_ym is the realized return month (correct sig_date match for C2's month-end dates)
# Use realized_ym as the linkage key with C2 sig_dates
pg2_sched[, sig_ym := realized_ym]
setkey(pg2_sched, sig_ym)

cat("[opt-v2] PG2 schedule rows:", nrow(pg2_sched), "\n")
cat("[opt-v2] PG2 sig_ym range:", min(pg2_sched$sig_ym), "to", max(pg2_sched$sig_ym), "\n\n")

# Sector mapping
sector_pit <- RAWDATA[, .(Sector = last(Sector)), by = .(Date, Ticker)]
ticker_last_sector <- RAWDATA[!is.na(Sector), .(latest_sector = last(Sector)), by = Ticker]
setkey(ticker_last_sector, Ticker)

# ─── Sleeve top20 selection ──────────────────────────────
SECTOR_CAP_N <- 6L; TOPN <- 20L; SECTOR_CAP_FRAC <- 0.30
PG2_LIQ_THRESHOLD <- 2e8  # PG2 admit precedent

select_c2_top20 <- function(c2_sd, sector_map_sd, top_n = 20L, cap_n = 6L) {
  dt <- merge(c2_sd, sector_map_sd, by = "Ticker", all.x = TRUE)
  na_idx <- which(is.na(dt$Sector))
  if (length(na_idx) > 0L) {
    miss <- dt$Ticker[na_idx]
    fb <- ticker_last_sector[miss, latest_sector, on = "Ticker"]
    dt$Sector[na_idx] <- fb
  }
  dt <- dt[!is.na(Sector)]
  setorder(dt, -alpha)
  sel <- dt[, head(.SD, cap_n), by = Sector]
  setorder(sel, -alpha)
  head(sel, top_n)
}

select_str1715_top20 <- function(s17_sd, top_n = 20L) {
  dt <- s17_sd[!is.na(score_eff)]
  setorder(dt, -score_eff)
  head(dt, top_n)
}

# ─── In-sleeve weights ───────────────────────────────────
# STR_1715: inv vol within top20 (PG2 admit method approximation)
build_str1715_in_sleeve <- function(s17_top, ret_panel_252d) {
  tk <- s17_top$Ticker
  if (is.null(ret_panel_252d) || ncol(ret_panel_252d) == 0L) {
    # equal weight fallback
    return(setNames(rep(1/length(tk), length(tk)), tk))
  }
  use_tk <- intersect(tk, colnames(ret_panel_252d))
  if (length(use_tk) < 5L) return(setNames(rep(1/length(tk), length(tk)), tk))
  vols <- apply(ret_panel_252d[, use_tk, drop = FALSE], 2, sd, na.rm = TRUE)
  vols[!is.finite(vols) | vols < 1e-6] <- median(vols, na.rm = TRUE)
  iv <- 1 / vols
  w_in <- setNames(iv / sum(iv), use_tk)
  # Cap each at 0.20 (PG2 weight bound)
  while (max(w_in) > 0.20) {
    over <- which(w_in > 0.20)
    excess <- sum(w_in[over] - 0.20)
    w_in[over] <- 0.20
    under <- setdiff(seq_along(w_in), over)
    if (length(under) == 0L) break
    room <- 0.20 - w_in[under]
    if (sum(room) <= 1e-10) break
    add <- excess * room / sum(room)
    w_in[under] <- w_in[under] + add
  }
  # Missing tickers → equal share fallback
  miss <- setdiff(tk, use_tk)
  if (length(miss) > 0L) {
    eq_w <- mean(w_in)
    w_full <- c(w_in, setNames(rep(eq_w, length(miss)), miss))
    w_full <- w_full / sum(w_full)
    return(w_full)
  }
  w_in / sum(w_in)
}

# C2: alpha-weighted within top20
build_c2_in_sleeve <- function(c2_top) {
  al <- pmax(c2_top$alpha, 0.01)
  w <- al / sum(al)
  setNames(w, c2_top$Ticker)
}

# ─── Sleeve daily return matrix (for Σ_sleeve + CVaR) ────
get_daily_panel <- function(tickers, end_date, n_days = 252L) {
  start_date <- end_date - 365L
  rd <- RAWDATA[Ticker %in% tickers & Date >= start_date & Date <= end_date, .(Date, Ticker, Ret)]
  if (nrow(rd) == 0L) return(NULL)
  wide <- dcast(rd, Date ~ Ticker, value.var = "Ret", fill = 0)
  m <- as.matrix(wide[, !"Date"])
  m[!is.finite(m)] <- 0
  if (nrow(m) > n_days) m <- m[(nrow(m) - n_days + 1):nrow(m), , drop = FALSE]
  m
}

# ─── 5 Methods (sleeve allocation) ───────────────────────
sleeve_mvo <- function(mu, Sigma, lambda = 2.0, bounds = c(0, 1.0)) {
  D <- length(mu)
  Dmat <- lambda * Sigma
  dvec <- mu
  Amat <- cbind(rep(1, D), diag(D), -diag(D))
  bvec <- c(1, rep(bounds[1], D), rep(-bounds[2], D))
  out <- tryCatch(solve.QP(Dmat, dvec, Amat, bvec, meq = 1), error = function(e) NULL)
  if (is.null(out)) return(c(0.5, 0.5))
  pmax(pmin(out$solution, bounds[2]), bounds[1])
}

sleeve_hrp <- function(Sigma) {
  iv <- 1 / diag(Sigma)
  iv / sum(iv)
}

sleeve_erc <- function(Sigma) {
  D <- nrow(Sigma)
  w <- rep(1/D, D)
  for (iter in 1:200) {
    sw <- Sigma %*% w
    RC <- w * sw
    target <- mean(RC)
    adj <- target / RC
    w_new <- w * adj^0.5
    w_new <- as.numeric(w_new / sum(w_new))
    if (max(abs(w_new - w)) < 1e-6) {
      w <- w_new; break
    }
    w <- w_new
  }
  pmax(pmin(w, 1), 0)
}

sleeve_cvar <- function(ret_mat, alpha_level = 0.95, cvar_target = 0.025) {
  grid <- seq(0, 1, by = 0.005)
  cvars <- sapply(grid, function(w1) {
    w <- c(w1, 1 - w1)
    pr <- as.numeric(ret_mat %*% w)
    q <- quantile(pr, probs = 1 - alpha_level, na.rm = TRUE)
    -mean(pr[pr <= q], na.rm = TRUE)
  })
  idx <- which.min(cvars)
  best_w1 <- grid[idx]
  feasible <- which(cvars <= cvar_target)
  if (length(feasible) > 0L) {
    f_grid <- grid[feasible]
    best_w1 <- f_grid[which.min(abs(f_grid - 0.5))]
  }
  c(best_w1, 1 - best_w1)
}

sleeve_ensemble <- function(w_mvo, w_hrp, w_erc) {
  w <- (w_mvo + w_hrp + w_erc) / 3
  w / sum(w)
}

# ─── Common sig_dates ────────────────────────────────────
sig_ym_c2 <- sort(unique(c2_alpha$ym))
sig_ym_s17 <- sort(unique(str1715_alpha$ym))
sig_ym_pg2 <- sort(unique(pg2_sched$sig_ym))
common_ym <- sort(Reduce(intersect, list(sig_ym_c2, sig_ym_s17, sig_ym_pg2)))
cat("[opt-v2] common sig_ym (C2 + STR1715 + PG2):", length(common_ym), "\n")

# Use C2 sig_dates (month-end) as canonical
c2_alpha_uniq <- unique(c2_alpha[ym %in% common_ym, .(Date, ym)])
setkey(c2_alpha_uniq, ym)
sig_schedule <- c2_alpha_uniq[ym %in% common_ym]
setorder(sig_schedule, Date)
cat("[opt-v2] schedule sig_dates:", nrow(sig_schedule), "| range:",
    as.character(range(sig_schedule$Date)), "\n\n")

# Map ym → str1715 sig_date
# STR_1715 sig_dates are month-start (2004-01-01); the score is the alpha
# that applies for the SAME month (decision_date = sd, alpha applies for return ym)
# C2 sig_dates are month-end (2004-01-30); applies for next-month returns
# So C2 sig at 2026-04-30 maps to STR_1715 sig at 2026-05-01 (next month start)
# But STR_1715 latest is 2026-04-01, so latest aligns C2 2026-03-31 → STR 2026-04-01
# OR we use STR_1715 at same month-start as C2: C2 2026-04-30 → STR 2026-04-01
# (Both apply to alpha for forward returns realized in May)
# Following PG2 admit lineage: STR_1715 sig at 2026-04-01 → realized return May (Jul forward)
# Since C2 sig at 2026-04-30 → realized return May too, they align on realized_ym 2026-05
# But STR_1715 last is 2026-04-01 (realized=2026-04), so we need extrapolation
# Conservative: align C2 sig_date to STR_1715 same-month sig_date (both pre-realization)
# C2 sig at 2026-04-30 = STR_1715 sig at 2026-04-01 (both pre 2026-05 realization)
s17_ym_map <- str1715_alpha[, .(s17_date = min(Date)), by = ym]
setkey(s17_ym_map, ym)

# ─── Walk-forward ────────────────────────────────────────
method_names <- c("MVO_confidence", "HRP", "ERC", "CVaR_LP", "Ensemble")
weights_records <- list()
sleeve_summary <- list()

t0 <- Sys.time()
for (i in seq_len(nrow(sig_schedule))) {
  sd_t <- sig_schedule$Date[i]; ym_t <- sig_schedule$ym[i]
  s17_sd <- s17_ym_map[ym_t, s17_date]
  pg2_row <- pg2_sched[sig_ym == ym_t]
  if (is.na(s17_sd) || nrow(pg2_row) == 0L) next

  c2_sd_dt <- c2_alpha[Date == sd_t]
  s17_sd_dt <- str1715_alpha[Date == s17_sd]
  sector_map_sd <- sector_pit[Date == sd_t, .(Ticker, Sector)]

  c2_top <- select_c2_top20(c2_sd_dt, sector_map_sd, top_n = TOPN, cap_n = SECTOR_CAP_N)
  s17_top <- select_str1715_top20(s17_sd_dt, top_n = TOPN)
  if (nrow(c2_top) < 15L || nrow(s17_top) < 15L) next

  daily_panel <- get_daily_panel(c(c2_top$Ticker, s17_top$Ticker), end_date = sd_t, n_days = 252L)
  if (is.null(daily_panel) || nrow(daily_panel) < 50L) next

  w_c2_in <- build_c2_in_sleeve(c2_top)
  w_s17_in <- build_str1715_in_sleeve(s17_top, daily_panel)

  # Sleeve daily returns (for Σ + CVaR)
  c2_tk <- intersect(names(w_c2_in), colnames(daily_panel))
  s17_tk <- intersect(names(w_s17_in), colnames(daily_panel))
  if (length(c2_tk) < 10L || length(s17_tk) < 10L) next
  w_c2_use <- w_c2_in[c2_tk]; w_c2_use <- w_c2_use / sum(w_c2_use)
  w_s17_use <- w_s17_in[s17_tk]; w_s17_use <- w_s17_use / sum(w_s17_use)

  c2_d <- daily_panel[, c2_tk, drop = FALSE] %*% w_c2_use
  s17_d <- daily_panel[, s17_tk, drop = FALSE] %*% w_s17_use
  sleeve_ret_mat <- cbind(c2 = as.numeric(c2_d), s17 = as.numeric(s17_d))
  sleeve_ret_mat[!is.finite(sleeve_ret_mat)] <- 0

  # Sleeve Σ (2×2) ann
  sleeve_sigma_d <- cov(sleeve_ret_mat)
  if (!all(is.finite(sleeve_sigma_d)) || any(diag(sleeve_sigma_d) <= 0)) {
    sleeve_sigma_d <- diag(c(max(0.0001, var(sleeve_ret_mat[,1])),
                              max(0.0001, var(sleeve_ret_mat[,2]))))
  }
  Sigma <- sleeve_sigma_d * 252
  Sigma <- (Sigma + t(Sigma)) / 2
  eig_min <- tryCatch(min(eigen(Sigma)$values), error = function(e) -1)
  if (!is.finite(eig_min) || eig_min < 1e-6) Sigma <- Sigma + diag(1e-4, 2)

  # Sleeve μ (historical annualized × discount)
  mu_c2 <- mean(c2_d) * 252
  mu_s17 <- mean(s17_d) * 252  # NOTE: this is RAW STR_1715 without overlay (overlay applies later)
  sleeve_mu <- c(mu_c2, mu_s17)

  # Methods
  w_mvo  <- tryCatch(sleeve_mvo(sleeve_mu, Sigma, lambda = 2.0), error = function(e) c(0.5, 0.5))
  w_hrp  <- tryCatch(sleeve_hrp(Sigma), error = function(e) c(0.5, 0.5))
  w_erc  <- tryCatch(sleeve_erc(Sigma), error = function(e) c(0.5, 0.5))
  w_cvar <- tryCatch(sleeve_cvar(sleeve_ret_mat, 0.95, 0.025), error = function(e) c(0.5, 0.5))
  w_ens  <- sleeve_ensemble(w_mvo, w_hrp, w_erc)

  sleeves <- list(MVO_confidence = w_mvo, HRP = w_hrp, ERC = w_erc, CVaR_LP = w_cvar, Ensemble = w_ens)

  # Build ticker-level composite weights with overlay
  overlay <- pg2_row$combined_overlay_V2[1]  # m4 × β_AR × β_R05_V2
  for (m in method_names) {
    sw <- sleeves[[m]]
    # sw[1] = β_c2, sw[2] = β_str1715  (NOTE: matches sleeve_ret_mat columns: c2, s17)
    beta_c2 <- sw[1]; beta_s17 <- sw[2]

    # STR_1715 sleeve component: β_s17 × overlay × inv_vol_weights
    str1715_component <- beta_s17 * overlay * w_s17_in[s17_tk]
    # C2 sleeve component: β_c2 × alpha_weights (no overlay)
    c2_component <- beta_c2 * w_c2_in[c2_tk]
    # Cash residual: 1 - β_s17 × overlay - β_c2
    cash_share <- 1 - beta_s17 * overlay - beta_c2
    cash_share <- pmax(cash_share, 0)

    # Aggregate ticker weights
    tickers_union <- union(s17_tk, c2_tk)
    w_v <- setNames(rep(0, length(tickers_union)), tickers_union)
    for (tkr in s17_tk) w_v[tkr] <- w_v[tkr] + str1715_component[[tkr]]
    for (tkr in c2_tk) w_v[tkr] <- w_v[tkr] + c2_component[[tkr]]
    # Now w_v + cash_share should equal 1 (modulo floating)
    # Cap each ticker at 0.20
    cap_excess <- pmax(w_v - 0.20, 0)
    if (sum(cap_excess) > 1e-10) {
      # Reduce overcaps; excess goes to cash (don't redistribute to maintain sleeve allocation)
      w_v <- pmin(w_v, 0.20)
      cash_share <- 1 - sum(w_v)
    }
    cash_share <- pmax(cash_share, 0)

    # Record (ticker level)
    rec <- data.table(
      as_of_date = sd_t,
      decision_date = pg2_row$decision_date[1],
      decision_ym = ym_t,
      Ticker = c(names(w_v), "CASH"),
      weight = c(as.numeric(w_v), cash_share),
      method = m,
      beta_c2 = beta_c2,
      beta_str1715 = beta_s17,
      overlay = overlay,
      regime = pg2_row$regime[1]
    )
    weights_records[[length(weights_records) + 1L]] <- rec
  }

  # Sleeve summary
  for (m in method_names) {
    sw <- sleeves[[m]]
    # Composite return time series (sleeve level)
    composite_d <- sleeve_ret_mat %*% sw
    q <- quantile(composite_d, probs = 0.05, na.rm = TRUE)
    cvar_is <- -mean(composite_d[composite_d <= q], na.rm = TRUE)
    sleeve_summary[[length(sleeve_summary) + 1L]] <- data.table(
      as_of_date = sd_t, decision_ym = ym_t, method = m,
      beta_c2 = sw[1], beta_str1715 = sw[2],
      overlay_inherited = overlay,
      regime = pg2_row$regime[1],
      cash_share_with_overlay = 1 - sw[2] * overlay - sw[1],
      in_sample_cvar95_daily = cvar_is,
      in_sample_vol_ann = sd(composite_d) * sqrt(252),
      in_sample_mean_ret_ann = mean(composite_d) * 252,
      sigma_c2 = Sigma[1, 1], sigma_s17 = Sigma[2, 2], cov_c2_s17 = Sigma[1, 2]
    )
  }

  if (i %% 25 == 0L) {
    cat(sprintf("  [%d/%d] %s elapsed %.1fs\n", i, nrow(sig_schedule),
                as.character(sd_t), as.numeric(Sys.time() - t0, units = "secs")))
  }
}

weights_dt <- rbindlist(weights_records)
sleeve_dt  <- rbindlist(sleeve_summary)
cat(sprintf("[opt-v2] DONE: %d weight rows, %d sleeve summaries, %d sig_dates\n",
            nrow(weights_dt), nrow(sleeve_dt), uniqueN(weights_dt$as_of_date)))

fwrite(weights_dt, file.path(OPTWS, "weights_long_v2.csv"))
fwrite(sleeve_dt,  file.path(OPTWS, "sleeve_summary_v2.csv"))
cat("[opt-v2] Saved.\n")
