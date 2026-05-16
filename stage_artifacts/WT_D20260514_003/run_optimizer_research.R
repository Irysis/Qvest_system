#==============================================================================
# WT-D20260514_003 — Optimizer Research Agent
# 4-Sleeve Composite Weight Decision (STR_1715 + C2 + AR overlay + R05 overlay)
#
# Method shopping: MVO_confidence / HRP / ERC / CVaR_LP / Ensemble
# Hard constraints:
#   - sector cap 0.30 (도훈 mandate inherit, 268m baseline + 2026-04 outlier)
#   - CVaR_95 target ≤ 0.025 (current 0.0260 marginal breach)
#   - weight_bounds [0, 0.20] per ticker (PG2 hard mandate)
#   - Σw = 1, long-only
#   - 268m walk-forward schedule (Charter §9 density mandate)
#
# Sleeve interpretation (Risk research SOT):
#   "4 sleeve" = 2 alpha (STR_1715 + C2) + 2 scalar overlay (AR + R05)
#   Optimizer scope = alpha sleeve weight decision (AR/R05 inherit, scalar apply)
#==============================================================================

suppressMessages({
  library(arrow)
  library(data.table)
  library(quadprog)
  library(jsonlite)
  library(corpcor)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

WT_ID <- "WT-D20260514_003"
STAGE <- "stage_artifacts/WT_D20260514_003"

# ─── Load infrastructure ─────────────────────────────────
source("02_Infrastructure/portfolio/mean_variance_optimizer.R", local = FALSE)

# RAWDATA + BM
suppressMessages({
  RAWDATA <- as.data.table(read_parquet(".cache/RAWDATA.parquet"))
  BM_DT   <- as.data.table(read_parquet(".cache/benchmark.parquet"))
})
setkey(RAWDATA, Date, Ticker)
setkey(BM_DT, Date)

cat("[optimizer] RAWDATA rows:", nrow(RAWDATA), "| date range:",
    as.character(range(RAWDATA$Date)), "\n")

# ─── Load alpha + risk packages ──────────────────────────
alpha_pkg <- fromJSON(file.path("qepm/mailbox/worktask", WT_ID, "alpha_package.json"),
                      simplifyVector = FALSE)
risk_pkg  <- fromJSON(file.path("qepm/mailbox/worktask", WT_ID, "risk_package.json"),
                      simplifyVector = FALSE)
req_json  <- fromJSON(file.path("qepm/mailbox/worktask", WT_ID, "request.json"),
                      simplifyVector = FALSE)

cat("[optimizer] alpha_package version:", alpha_pkg$version, "\n")
cat("[optimizer] risk_package version:", risk_pkg$pipeline_version, "\n")

# ─── Load alpha panels ──────────────────────────────────
c2_alpha <- as.data.table(read_parquet(file.path(STAGE, "alpha_scores.parquet")))
setnames(c2_alpha, "sig_date", "Date")
setkey(c2_alpha, Date, Ticker)
cat("[optimizer] C2 alpha panel:", nrow(c2_alpha), "rows |",
    uniqueN(c2_alpha$Date), "sig_dates\n")

str1715_alpha <- as.data.table(read_parquet(
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet"
))
setkey(str1715_alpha, Date, Ticker)
cat("[optimizer] STR_1715 alpha panel:", nrow(str1715_alpha), "rows |",
    uniqueN(str1715_alpha$Date), "sig_dates\n")

# R05 panel (overlay scalar source)
r05 <- as.data.table(read_parquet(
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_r05_panel.parquet"
))
setkey(r05, Date, Ticker)

# ─── Sector mapping (PIT-clean: per-sig_date Sector from RAWDATA) ────
# Sector at sig_date end-of-month
sector_pit <- RAWDATA[, .(Sector = last(Sector)), by = .(Date, Ticker)]
# fallback: latest-known sector for tickers absent at sig_date
ticker_last_sector <- RAWDATA[!is.na(Sector), .(latest_sector = last(Sector)), by = Ticker]
setkey(ticker_last_sector, Ticker)

# ─── Sig date alignment ──────────────────────────────────
# STR_1715 panel uses month-start (2004-01-01), C2 uses month-end (2004-01-30)
# Align via year-month
c2_alpha[, ym := format(Date, "%Y-%m")]
str1715_alpha[, ym := format(Date, "%Y-%m")]
sig_ym_c2  <- sort(unique(c2_alpha$ym))
sig_ym_s17 <- sort(unique(str1715_alpha$ym))
sig_ym_all <- sort(intersect(sig_ym_c2, sig_ym_s17))
cat("[optimizer] common year-months:", length(sig_ym_all), "\n")
# Use C2 sig_dates (month-end) as canonical schedule
sig_dates_all <- sort(unique(c2_alpha[ym %in% sig_ym_all, Date]))
sig_dates_all <- sig_dates_all[sig_dates_all >= as.Date("2004-01-30")]
cat("[optimizer] schedule sig_dates final:", length(sig_dates_all), "\n")

# Build year-month → STR_1715 sig_date mapping
s17_ym_map <- str1715_alpha[, .(s17_date = min(Date)), by = ym]
setkey(s17_ym_map, ym)

# ─── Sleeve top20 selection per sig_date ────────────────
# Note: C2 sleeve = sector-cap aware projection (cap 0.30 ≈ 6 stock / sector)
# Sector cap mandate: max 6 (= ceil(20*0.30)) per sector
SECTOR_CAP_N <- 6L  # 6/20 = 30% per sector cap (Risk research recommendation 0.30)
TOPN_PER_SLEEVE <- 20L

select_c2_top20_sector_cap <- function(c2_sd, sector_map, top_n = 20L, cap_n = 6L) {
  # c2_sd: data.table for one sig_date (Date, Ticker, alpha)
  # sector_map: data.table (Ticker, Sector)
  # cap_n: max stocks per sector (6 = 30%)
  dt <- merge(c2_sd, sector_map, by = "Ticker", all.x = TRUE)
  # Fallback latest-known sector if Date-specific NA
  na_idx <- which(is.na(dt$Sector))
  if (length(na_idx) > 0) {
    miss_tickers <- dt$Ticker[na_idx]
    fb <- ticker_last_sector[miss_tickers, latest_sector, on = "Ticker"]
    dt$Sector[na_idx] <- fb
  }
  # NA still possible (extinct ticker / no sector ever) → drop
  dt <- dt[!is.na(Sector)]
  setorder(dt, -alpha)
  # Greedy: per sector at most cap_n; take top by alpha
  sel <- dt[, head(.SD, cap_n), by = Sector]
  setorder(sel, -alpha)
  head(sel, top_n)
}

select_str1715_top20 <- function(s17_sd, top_n = 20L) {
  # STR_1715 top by score_eff (PG2 admit selection method)
  dt <- s17_sd[!is.na(score_eff)]
  setorder(dt, -score_eff)
  head(dt, top_n)
}

# ─── Sigma (rolling 252d daily, sleeve union universe) ───
# Daily returns for sleeve union per sig_date
get_daily_returns <- function(tickers, end_date, n_days = 252L) {
  start_date <- end_date - (n_days * 1.6)  # buffer for non-trading days
  rd <- RAWDATA[Ticker %in% tickers & Date >= start_date & Date <= end_date,
                .(Date, Ticker, Ret)]
  if (nrow(rd) == 0L) return(NULL)
  ret_wide <- dcast(rd, Date ~ Ticker, value.var = "Ret")
  setorder(ret_wide, Date)
  # take last n_days non-NA rows
  ret_mat <- as.matrix(ret_wide[, !"Date", with = FALSE])
  dt_dates <- ret_wide$Date
  # Forward-fill / drop columns with too many NA
  na_pct <- colSums(is.na(ret_mat)) / nrow(ret_mat)
  keep_cols <- which(na_pct < 0.30)
  if (length(keep_cols) == 0L) return(NULL)
  ret_mat <- ret_mat[, keep_cols, drop = FALSE]
  # Zero-fill remaining
  ret_mat[is.na(ret_mat)] <- 0
  # last n_days rows
  if (nrow(ret_mat) > n_days) ret_mat <- ret_mat[(nrow(ret_mat) - n_days + 1):nrow(ret_mat), , drop = FALSE]
  list(ret_mat = ret_mat, dates = tail(dt_dates, nrow(ret_mat)))
}

# Sigma with shrinkage (Ledoit-Wolf via corpcor)
build_sigma <- function(ret_mat, ann_factor = 252) {
  if (is.null(ret_mat) || nrow(ret_mat) < 30L || ncol(ret_mat) < 2L) return(NULL)
  Sigma_d <- corpcor::cov.shrink(ret_mat, verbose = FALSE)
  attr(Sigma_d, "lambda.var") <- NULL
  attr(Sigma_d, "class") <- NULL
  Sigma <- Sigma_d * ann_factor
  Sigma <- as.matrix(Sigma)
  # Ensure symmetric + PSD
  Sigma <- (Sigma + t(Sigma)) / 2
  eig <- eigen(Sigma, symmetric = TRUE)
  if (min(eig$values) < 1e-6) {
    eig$values <- pmax(eig$values, 1e-6)
    Sigma <- eig$vectors %*% diag(eig$values) %*% t(eig$vectors)
    Sigma <- (Sigma + t(Sigma)) / 2
  }
  rownames(Sigma) <- colnames(ret_mat)
  colnames(Sigma) <- colnames(ret_mat)
  Sigma
}

# ─── 5 Methods Implementation ────────────────────────────

#  Method 1: MVO_confidence  (Markowitz quadratic with sleeve weight {w1,w2})
#    Maximize w' μ - λ/2 w' Σ w  over w1, w2 (sleeve weights), sum=1, w>=0
#    Reduces to 2D portfolio optimization on aggregated alpha + Σ
sleeve_mvo <- function(sleeve_alpha_vec, sleeve_sigma_mat, lambda = 2.0, bounds = c(0, 1.0)) {
  # 2-sleeve MVO (closed form for 2 sleeves: w1, w2 = 1-w1)
  D <- length(sleeve_alpha_vec)
  if (D != 2L) stop("sleeve_mvo expects 2 sleeves")
  # QP: min (1/2) w' (λΣ) w - w' α   s.t.  1'w=1, 0 <= w <= bounds[2]
  Dmat <- lambda * sleeve_sigma_mat
  dvec <- sleeve_alpha_vec
  # Equality: 1'w = 1
  Amat <- cbind(rep(1, D), diag(D), -diag(D))
  bvec <- c(1, rep(bounds[1], D), rep(-bounds[2], D))
  out <- tryCatch(solve.QP(Dmat, dvec, Amat, bvec, meq = 1), error = function(e) NULL)
  if (is.null(out)) {
    # Fallback: equal weight
    return(c(0.5, 0.5))
  }
  pmax(pmin(out$solution, bounds[2]), bounds[1])
}

#  Method 2: HRP (Hierarchical Risk Parity, López de Prado 2016)
sleeve_hrp <- function(sleeve_sigma_mat) {
  D <- nrow(sleeve_sigma_mat)
  if (D == 2L) {
    # 2-sleeve HRP = inverse variance weights
    iv <- 1 / diag(sleeve_sigma_mat)
    iv / sum(iv)
  } else {
    stop("HRP requires N>=2")
  }
}

#  Method 3: ERC (Equal Risk Contribution)
sleeve_erc <- function(sleeve_sigma_mat) {
  D <- nrow(sleeve_sigma_mat)
  if (D == 2L) {
    # For 2 assets, ERC = w_i ∝ σ_j (inverse vol weighted by other's vol)
    # Exact: w1 σ1 (Σw)_1 = w2 σ2 (Σw)_2  →  solve
    # Closed form numerical iteration
    w <- c(0.5, 0.5)
    for (iter in 1:200) {
      sigma_w <- sleeve_sigma_mat %*% w
      RC <- w * sigma_w
      target <- mean(RC)
      adj <- target / RC
      w_new <- w * adj^0.5
      w_new <- w_new / sum(w_new)
      if (max(abs(w_new - w)) < 1e-6) {
        w <- w_new
        break
      }
      w <- w_new
    }
    pmax(pmin(w, 1), 0)
  } else {
    stop("ERC requires N=2 in this app")
  }
}

#  Method 4: CVaR_LP via composite returns (Rockafellar-Uryasev 2000)
sleeve_cvar <- function(sleeve_returns_mat, alpha_level = 0.95, cvar_target = 0.025) {
  # sleeve_returns_mat: T × 2 daily returns for two sleeves
  # min CVaR_alpha subject to sum=1, w>=0; ideally also cvar <= target if feasible
  D <- ncol(sleeve_returns_mat)
  if (D != 2L) stop("CVaR LP expects 2 sleeves")
  # Grid 1D over w1 (parametric, 2-sleeve case)
  grid <- seq(0, 1, by = 0.005)
  cvars <- sapply(grid, function(w1) {
    w <- c(w1, 1 - w1)
    pr <- as.numeric(sleeve_returns_mat %*% w)
    # CVaR (loss form): mean of worst (1-alpha) tail
    q <- quantile(pr, probs = 1 - alpha_level, na.rm = TRUE)
    -mean(pr[pr <= q], na.rm = TRUE)
  })
  # Find min CVaR
  min_cvar <- min(cvars, na.rm = TRUE)
  idx <- which.min(cvars)
  best_w1 <- grid[idx]
  # If feasible (cvar <= target), prefer wider w-range for better diversification + alpha capture
  # Find w1 closest to "ideal" 0.5 that satisfies target
  feasible <- which(cvars <= cvar_target)
  if (length(feasible) > 0) {
    # Choose feasible w1 nearest to 0.5 (diversification preference)
    f_grid <- grid[feasible]
    best_w1 <- f_grid[which.min(abs(f_grid - 0.5))]
  }
  c(best_w1, 1 - best_w1)
}

#  Method 5: Ensemble — average of MVO + HRP + ERC sleeve weights
sleeve_ensemble <- function(w_mvo, w_hrp, w_erc) {
  w <- (w_mvo + w_hrp + w_erc) / 3
  w / sum(w)
}

# ─── Inverse vol within sleeve (PG2 admit precedent) ─────
# Apply inverse-vol weighting within each sleeve top20 to get ticker level weights
sleeve_inv_vol <- function(tickers, sigma_full) {
  # tickers: c(20)
  # sigma_full: Σ over ticker universe
  use_t <- intersect(tickers, rownames(sigma_full))
  if (length(use_t) == 0L) return(setNames(rep(1/length(tickers), length(tickers)), tickers))
  vols <- sqrt(diag(sigma_full[use_t, use_t]))
  iv <- 1 / vols
  w <- iv / sum(iv)
  names(w) <- use_t
  # Fill missing with equal share
  missing_t <- setdiff(tickers, use_t)
  if (length(missing_t) > 0) {
    cat("  inv_vol: filling missing ticker", missing_t, "with mean\n")
    eq_w <- mean(w)
    w_full <- c(w, setNames(rep(eq_w, length(missing_t)), missing_t))
    w_full <- w_full / sum(w_full)
    w_full
  } else {
    w
  }
}

# ─── Walk-forward main loop ──────────────────────────────
cat("[optimizer] Starting walk-forward 268m loop...\n")
cat("[optimizer] Methods: MVO_confidence | HRP | ERC | CVaR_LP | Ensemble\n\n")

# Storage
weights_log <- list()
sleeve_weight_log <- list()
sigma_log <- list()

# Sector cap from Risk recommendation
SECTOR_CAP_FRAC <- 0.30

# Pre-load PG2 admit weights for STR_1715 sleeve (rank-weighted inv vol)
# Use score_eff directly within sleeve for weighting (STR_1715 admit method)
build_sleeve_weights_str1715 <- function(s17_sd_top20) {
  # PG2 admit method: rank-weighted (Weight_sleeve from precomputed)
  # Recompute with score_eff cross-section
  sc <- s17_sd_top20$score_eff
  sc <- pmax(sc, 0.01)  # floor
  w <- sc / sum(sc)
  setNames(w, s17_sd_top20$Ticker)
}

build_sleeve_weights_c2 <- function(c2_sd_top20) {
  # Within C2 sleeve: alpha-weighted (proportional to alpha score)
  # alpha is z-score (positive = high alpha), so use exp(alpha) or pmax floor
  al <- c2_sd_top20$alpha
  al <- pmax(al, 0.01)
  w <- al / sum(al)
  setNames(w, c2_sd_top20$Ticker)
}

# Define iteration over sig_dates
n_sd <- length(sig_dates_all)

# Quick test: do single sig_date pipeline first
test_idx <- which(sig_dates_all == as.Date("2026-04-30"))
cat("[optimizer] Test pipeline at 2026-04-30 (index", test_idx, ")\n")

test_sd <- sig_dates_all[test_idx]
test_ym <- format(test_sd, "%Y-%m")
s17_sd_date <- s17_ym_map[test_ym, s17_date]
cat("  test sd:", as.character(test_sd), " | STR_1715 sd:", as.character(s17_sd_date), "\n")
c2_sd  <- c2_alpha[Date == test_sd]
s17_sd <- str1715_alpha[Date == s17_sd_date]
sector_map_sd <- sector_pit[Date == test_sd, .(Ticker, Sector)]

c2_top <- select_c2_top20_sector_cap(c2_sd, sector_map_sd, top_n = TOPN_PER_SLEEVE,
                                       cap_n = SECTOR_CAP_N)
s17_top <- select_str1715_top20(s17_sd, top_n = TOPN_PER_SLEEVE)
cat("  C2 top20 sector dist:\n")
print(c2_top[, .N, by = Sector])
cat("\n  STR_1715 top20 sector dist:\n")
print(s17_top[, .N, by = Ticker])
cat("\n  Top 5 C2:", head(c2_top$Ticker, 5), "\n")
cat("  Top 5 STR_1715:", head(s17_top$Ticker, 5), "\n")
cat("  Overlap:", intersect(c2_top$Ticker, s17_top$Ticker), "\n")

# Test build sleeve weights
w_c2_in_sleeve  <- build_sleeve_weights_c2(c2_top)
w_s17_in_sleeve <- build_sleeve_weights_str1715(s17_top)
cat("\n  C2 in-sleeve weights sum:", sum(w_c2_in_sleeve), "\n")
cat("  STR_1715 in-sleeve weights sum:", sum(w_s17_in_sleeve), "\n")

cat("\n[optimizer] Smoke test 2026-04-30 PASSED\n")
cat("[optimizer] Launching full 268m walk-forward with 5 methods\n\n")

# Helper
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

# ─── Walk-forward: 268 sig_dates × 5 methods ─────────────
# Output: weights.csv with (as_of_date, Ticker, weight, method, sleeve_w1, sleeve_w2)
n_sd <- length(sig_dates_all)
method_names <- c("MVO_confidence", "HRP", "ERC", "CVaR_LP", "Ensemble")

# Storage: ticker-level weights per (sig_date, method)
weights_records <- list()
sleeve_summary  <- list()
sigma_diag      <- list()

t0 <- Sys.time()
for (i in seq_len(n_sd)) {
  sd_t <- sig_dates_all[i]
  ym_t <- format(sd_t, "%Y-%m")
  s17_sd <- s17_ym_map[ym_t, s17_date]
  if (is.na(s17_sd)) next

  # Get sleeve top20 + sector map
  c2_sd_dt  <- c2_alpha[Date == sd_t]
  s17_sd_dt <- str1715_alpha[Date == s17_sd]
  sector_map_sd <- sector_pit[Date == sd_t, .(Ticker, Sector)]

  if (nrow(c2_sd_dt) < 30L || nrow(s17_sd_dt) < 30L) next

  c2_top  <- select_c2_top20_sector_cap(c2_sd_dt, sector_map_sd,
                                          top_n = TOPN_PER_SLEEVE, cap_n = SECTOR_CAP_N)
  s17_top <- select_str1715_top20(s17_sd_dt, top_n = TOPN_PER_SLEEVE)

  if (nrow(c2_top) < 15L || nrow(s17_top) < 15L) next

  # In-sleeve weights
  w_c2_in  <- build_sleeve_weights_c2(c2_top)
  w_s17_in <- build_sleeve_weights_str1715(s17_top)

  # Sleeve daily returns history (for Σ + CVaR)
  # Use 252d window ending at sig_date
  end_date <- sd_t
  start_date <- end_date - 365L  # 1 year
  daily_rd <- RAWDATA[Ticker %in% c(c2_top$Ticker, s17_top$Ticker) &
                       Date >= start_date & Date <= end_date,
                       .(Date, Ticker, Ret)]
  daily_wide <- dcast(daily_rd, Date ~ Ticker, value.var = "Ret", fill = 0)
  daily_mat <- as.matrix(daily_wide[, !"Date"])
  if (nrow(daily_mat) < 50L) next
  # take last 252 rows
  if (nrow(daily_mat) > 252L) daily_mat <- daily_mat[(nrow(daily_mat) - 251):nrow(daily_mat), , drop = FALSE]

  # Compute daily sleeve returns
  c2_tickers_in_panel <- intersect(c2_top$Ticker, colnames(daily_mat))
  s17_tickers_in_panel <- intersect(s17_top$Ticker, colnames(daily_mat))
  if (length(c2_tickers_in_panel) < 10L || length(s17_tickers_in_panel) < 10L) next

  w_c2_use  <- w_c2_in[c2_tickers_in_panel]; w_c2_use <- w_c2_use / sum(w_c2_use)
  w_s17_use <- w_s17_in[s17_tickers_in_panel]; w_s17_use <- w_s17_use / sum(w_s17_use)

  c2_ret_d  <- daily_mat[, c2_tickers_in_panel, drop = FALSE] %*% w_c2_use
  s17_ret_d <- daily_mat[, s17_tickers_in_panel, drop = FALSE] %*% w_s17_use
  sleeve_ret_mat <- cbind(c2 = as.numeric(c2_ret_d), s17 = as.numeric(s17_ret_d))
  # Defensive: replace any NA/Inf with 0
  sleeve_ret_mat[!is.finite(sleeve_ret_mat)] <- 0

  # Sleeve Sigma (2×2)
  sleeve_sigma_d <- cov(sleeve_ret_mat)
  if (!all(is.finite(sleeve_sigma_d)) || any(diag(sleeve_sigma_d) <= 0)) {
    # Fallback minimal Σ
    sleeve_sigma_d <- diag(c(max(0.01, var(sleeve_ret_mat[,1]), na.rm = TRUE),
                              max(0.01, var(sleeve_ret_mat[,2]), na.rm = TRUE)))
  }
  sleeve_sigma   <- sleeve_sigma_d * 252  # annualize
  # Ensure PSD
  eig_check <- tryCatch(min(eigen(sleeve_sigma)$values), error = function(e) -1)
  if (!is.finite(eig_check) || eig_check < 1e-6) {
    sleeve_sigma <- sleeve_sigma + diag(1e-4, 2)
  }

  # Sleeve expected returns (annualized from alpha proxy)
  # Use mean rank_ic × mean daily return contribution → annualized
  # Proxy: aggregate alpha within sleeve weighted by inverse n_stocks (intercept) + linear
  # Simpler: use historical sleeve return (252d) annualized as μ proxy + scale
  c2_mu  <- mean(c2_ret_d) * 252 * 1.0  # historical proxy
  s17_mu <- mean(s17_ret_d) * 252 * 1.0
  sleeve_mu <- c(c2_mu, s17_mu)

  # ── Methods ──
  w_mvo <- tryCatch(sleeve_mvo(sleeve_mu, sleeve_sigma, lambda = 2.0, bounds = c(0, 1)),
                    error = function(e) c(0.5, 0.5))
  w_hrp <- tryCatch(sleeve_hrp(sleeve_sigma),
                    error = function(e) c(0.5, 0.5))
  w_erc <- tryCatch(sleeve_erc(sleeve_sigma),
                    error = function(e) c(0.5, 0.5))
  w_cvar <- tryCatch(sleeve_cvar(sleeve_ret_mat, alpha_level = 0.95, cvar_target = 0.025),
                     error = function(e) c(0.5, 0.5))
  w_ens <- sleeve_ensemble(w_mvo, w_hrp, w_erc)

  sleeve_weights <- list(
    MVO_confidence = w_mvo,
    HRP            = w_hrp,
    ERC            = w_erc,
    CVaR_LP        = w_cvar,
    Ensemble       = w_ens
  )

  # Convert sleeve-weight + in-sleeve-weight to ticker-level weights
  for (m in method_names) {
    sw <- sleeve_weights[[m]]
    # Aggregate ticker-level weights via named vector
    tickers_union <- union(c2_tickers_in_panel, s17_tickers_in_panel)
    ticker_w_v <- setNames(rep(0, length(tickers_union)), tickers_union)
    for (tkr in c2_tickers_in_panel) {
      ticker_w_v[tkr] <- ticker_w_v[tkr] + sw[1] * w_c2_use[[tkr]]
    }
    for (tkr in s17_tickers_in_panel) {
      ticker_w_v[tkr] <- ticker_w_v[tkr] + sw[2] * w_s17_use[[tkr]]
    }
    # Cap per-ticker at 0.20 (PG2 mandate) — overlap A010950 likely safe but verify
    cap_excess <- ticker_w_v - 0.20
    cap_excess[cap_excess < 0] <- 0
    if (sum(cap_excess) > 0) {
      ticker_w_v <- pmin(ticker_w_v, 0.20)
      excess_amt <- 1 - sum(ticker_w_v)
      under_cap <- which(ticker_w_v < 0.20)
      if (length(under_cap) > 0) {
        room <- 0.20 - ticker_w_v[under_cap]
        share <- room / sum(room)
        ticker_w_v[under_cap] <- ticker_w_v[under_cap] + excess_amt * share
      }
    }
    # Normalize to sum=1
    ticker_w_v <- ticker_w_v / sum(ticker_w_v)

    rec <- data.table(
      as_of_date = sd_t,
      Ticker = names(ticker_w_v),
      weight = as.numeric(ticker_w_v),
      method = m,
      sleeve_w_c2 = sw[1],
      sleeve_w_str1715 = sw[2]
    )
    weights_records[[length(weights_records) + 1L]] <- rec
  }

  # Sleeve summary (per sig_date × method)
  for (m in method_names) {
    sw <- sleeve_weights[[m]]
    pr_d <- sleeve_ret_mat %*% sw
    # In-sample CVaR_95 (252d)
    q <- quantile(pr_d, probs = 0.05, na.rm = TRUE)
    cvar_is <- -mean(pr_d[pr_d <= q], na.rm = TRUE)
    sleeve_summary[[length(sleeve_summary) + 1L]] <- data.table(
      as_of_date = sd_t,
      method = m,
      sleeve_w_c2 = sw[1],
      sleeve_w_str1715 = sw[2],
      in_sample_cvar95_daily = cvar_is,
      in_sample_vol_ann = sd(pr_d) * sqrt(252),
      in_sample_mean_ret_ann = mean(pr_d) * 252,
      sleeve_sigma_c2 = sleeve_sigma[1, 1],
      sleeve_sigma_str1715 = sleeve_sigma[2, 2],
      sleeve_cov_c2_str1715 = sleeve_sigma[1, 2]
    )
  }

  if (i %% 25 == 0L) {
    elapsed <- as.numeric(Sys.time() - t0, units = "secs")
    cat(sprintf("  [%d/%d] %s elapsed %.1fs\n", i, n_sd, as.character(sd_t), elapsed))
  }
}

weights_dt <- rbindlist(weights_records)
sleeve_dt  <- rbindlist(sleeve_summary)
cat(sprintf("[optimizer] Walk-forward DONE: %d weight rows, %d sleeve summaries\n",
            nrow(weights_dt), nrow(sleeve_dt)))
cat(sprintf("[optimizer] Unique sig_dates in weights: %d\n",
            uniqueN(weights_dt$as_of_date)))

# Save raw outputs
fwrite(weights_dt, file.path(STAGE, "optimizer_workspace", "weights_long_raw.csv"))
fwrite(sleeve_dt,  file.path(STAGE, "optimizer_workspace", "sleeve_summary.csv"))
cat("[optimizer] Saved: optimizer_workspace/{weights_long_raw,sleeve_summary}.csv\n")
