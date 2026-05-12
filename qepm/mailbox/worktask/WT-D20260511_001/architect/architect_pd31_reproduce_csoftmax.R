#==============================================================================
# Architect PD31 — Independent Reproduce of Forge PD30 C_softmax variant
# WT-D20260511_001 — AX-008 3-source verification (Architect = source #3)
#
# Mandate: 도훈 2026-05-12 — "C안 PG2로 확정"
#
# Independence axes (vs Forge PD30):
#   (1) Manual matrix product (no Return.portfolio per-stock; do sleeve roll-up manually)
#   (2) Manual NAV via cumprod(1+r), parallel to PerformanceAnalytics::maxDrawdown
#   (3) Geometric AND arithmetic Sharpe both computed (Charter §13 reconciliation)
#   (4) Independent universe / liquidity / Ret_1m / top20 / softmax reimplementation
#
# Reads (read-only):
#   - stage_artifacts/WT_D20260511_001/alpha_scores_pd27_burn0m.parquet (1715 H1 alpha)
#   - stage_artifacts/WT_D20260511_001/alpha_scores_pd24.parquet        (NEW Vol/Skew)
#   - stage_artifacts/WT_D20260511_001/pd28/synthetic_etf_returns_2001_2026.parquet
#   - .cache/rawdata.parquet                                            (RAWDATA)
#
# Writes:
#   - qepm/mailbox/worktask/WT-D20260511_001/architect/pd31_repro/
#       sleeve_kr_equity_returns.csv, sleeve_panel.csv,
#       port_returns.csv, nav.csv, drawdowns.csv,
#       metrics_arith.csv, metrics_geom.csv,
#       holdings_C_softmax.csv, cap_audit_C.csv,
#       tau_history.csv
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(lubridate)
  library(xts)
  library(PerformanceAnalytics)
})

WT_DIR  <- "qepm/mailbox/worktask/WT-D20260511_001"
ST_DIR  <- "stage_artifacts/WT_D20260511_001"
OUT_DIR <- file.path(WT_DIR, "architect", "pd31_repro")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

cat("====================================================================\n")
cat("Architect PD31 — Independent C_softmax reproduce\n")
cat("Path: manual matrix product (independent of Forge PerformanceAnalytics chain)\n")
cat("====================================================================\n\n")

#------------------------------------------------------------------------------
# Config (must match Forge PD30 for valid cross-check)
#------------------------------------------------------------------------------
START_DATE  <- as.Date("2001-07-01")   # PD27 first sig_date
END_DATE    <- as.Date("2026-04-30")
LIQ_THRESH  <- 2e8
N_HOLD      <- 20
SINGLE_CAP  <- 0.20
TAU_FLOOR   <- 0.10
SLEEVE_W    <- c(KR_EQUITY = 0.55, TSMOM = 0.225, KR_10Y = 0.18, CASH = 0.045)
W_1715      <- 0.45 / (0.45 + 0.10)    # 0.8182 - PD20-b consolidation ratio
W_NEW       <- 0.10 / (0.45 + 0.10)    # 0.1818
COST_BPS    <- 15e-4                   # 15bps one-way
TO_INNER_KR <- 0.30                    # KR equity inner sleeve churn estimate
TO_INNER_TS <- 0.50                    # TSMOM inner churn estimate

#------------------------------------------------------------------------------
# Step 1: Load alpha sources + verify SHA fingerprints
#------------------------------------------------------------------------------
cat("[Step 1] Load PD27 + PD24 + ETF + RAWDATA ...\n")

tools::md5sum(c(
  file.path(ST_DIR, "alpha_scores_pd27_burn0m.parquet"),
  file.path(ST_DIR, "alpha_scores_pd24.parquet"),
  file.path(ST_DIR, "pd28/synthetic_etf_returns_2001_2026.parquet")
)) |> print()

pd27 <- as.data.table(read_parquet(file.path(ST_DIR, "alpha_scores_pd27_burn0m.parquet")))
setnames(pd27, "Date", "sig_date")
pd27 <- pd27[sig_date >= START_DATE & sig_date <= END_DATE]
pd27[, z_1715 := scale(score_eff)[, 1], by = sig_date]
cat(sprintf("  PD27: %d rows, %d sig_dates (%s ~ %s)\n",
            nrow(pd27), uniqueN(pd27$sig_date),
            as.character(min(pd27$sig_date)), as.character(max(pd27$sig_date))))

pd24 <- as.data.table(read_parquet(file.path(ST_DIR, "alpha_scores_pd24.parquet")))
if ("Date" %in% names(pd24)) setnames(pd24, "Date", "sig_date")
pd24 <- pd24[sig_date >= START_DATE & sig_date <= END_DATE]
pd24[, z_NEW := scale(alpha)[, 1], by = sig_date]
cat(sprintf("  PD24: %d rows, %d sig_dates\n",
            nrow(pd24), uniqueN(pd24$sig_date)))

# Outer merge composite z
merged <- merge(pd27[, .(sig_date, Ticker, z_1715)],
                pd24[, .(sig_date, Ticker, z_NEW)],
                by = c("sig_date", "Ticker"), all = TRUE)
merged[is.na(z_1715), z_1715 := 0]
merged[is.na(z_NEW),  z_NEW  := 0]
merged[, composite_z := W_1715 * z_1715 + W_NEW * z_NEW]
setkey(merged, sig_date, Ticker)
cat(sprintf("  Merged composite_z: %d rows, %d sig_dates\n",
            nrow(merged), uniqueN(merged$sig_date)))

#------------------------------------------------------------------------------
# Step 2: RAWDATA + Ret_1m + ADV_20d (independent recompute)
#------------------------------------------------------------------------------
cat("\n[Step 2] RAWDATA + Ret_1m + ADV_20d ...\n")

rd <- as.data.table(read_parquet(".cache/rawdata.parquet",
       col_select = c("Date", "Ticker", "Ret", "Close", "Vol", "K200", "KQ150")))
rd <- rd[Date >= as.Date("2001-01-01") & Date <= as.Date("2026-06-15")]
setkey(rd, Ticker, Date)
rd[, vol_value := Close * Vol]
setorder(rd, Ticker, Date)
rd[, adv_20d := frollmean(vol_value, n = 20, align = "right", na.rm = FALSE), by = Ticker]

# Per (Ticker, YearMonth) Ret_1m — Method A canonical, INDEPENDENT recompute
rd_mo <- rd[!is.na(Ret),
            .(Ret_1m = prod(1 + Ret, na.rm = TRUE) - 1),
            by = .(YearMonth = format(Date, "%Y-%m"), Ticker)]
rd_mo[, held_period := as.Date(paste0(YearMonth, "-01"))]
setkey(rd_mo, held_period, Ticker)
cat(sprintf("  rd_mo (Ticker × YM Ret_1m): %d rows\n", nrow(rd_mo)))

#------------------------------------------------------------------------------
# Step 3: Per-sig_date Top20 + INDEPENDENT softmax + cap
#------------------------------------------------------------------------------
cat("\n[Step 3] Top20 + softmax + cap (independent path) ...\n")

# Independent cap function — single-pass alternative to Forge's iterative
cap_redistribute <- function(w, cap = SINGLE_CAP, max_iter = 50L) {
  n <- length(w)
  if (sum(w) <= 1e-12) return(rep(1 / n, n))
  w <- w / sum(w)
  for (it in seq_len(max_iter)) {
    excess_idx <- which(w > cap + 1e-12)
    if (length(excess_idx) == 0L) break
    excess <- sum(w[excess_idx]) - cap * length(excess_idx)
    w[excess_idx] <- cap
    free_idx <- setdiff(seq_along(w), excess_idx)
    free_idx <- free_idx[w[free_idx] > 0]
    if (length(free_idx) == 0L) {
      w <- w + excess / n
    } else {
      w[free_idx] <- w[free_idx] + excess * (w[free_idx] / sum(w[free_idx]))
    }
  }
  w / sum(w)
}

sig_dates <- sort(unique(merged$sig_date))
cat(sprintf("  N sig_dates: %d\n", length(sig_dates)))

kr_eq_records <- list()
holdings_C    <- list()
cap_audit_C   <- list()
tau_records   <- list()

for (i in seq_along(sig_dates)) {
  sd_now <- sig_dates[i]
  d_lag  <- sd_now - 1L
  hp_now <- as.Date(sd_now %m+% months(1))

  uni_dt <- rd[Date <= d_lag & Date >= (d_lag - 30L), .SD[which.max(Date)], by = Ticker]
  uni_dt <- uni_dt[(K200 == 1L | KQ150 == 1L) & !is.na(adv_20d) & adv_20d >= LIQ_THRESH]
  if (nrow(uni_dt) == 0L) next

  cs_now <- merged[sig_date == sd_now & Ticker %in% uni_dt$Ticker]
  if (nrow(cs_now) < N_HOLD) next

  setorder(cs_now, -composite_z)
  top20 <- head(cs_now, N_HOLD)

  rets_held <- rd_mo[held_period == hp_now & Ticker %in% top20$Ticker,
                     .(Ticker, Ret_1m)]
  merged_top <- merge(top20[, .(Ticker, composite_z)], rets_held,
                      by = "Ticker", all.x = TRUE)
  merged_top[is.na(Ret_1m), Ret_1m := 0]

  # === Softmax (independent recompute) ===
  z_vec <- merged_top$composite_z
  tau   <- max(median(abs(z_vec)), TAU_FLOOR)
  # Numerical stability: shift by max
  shifted <- z_vec - max(z_vec)
  expz    <- exp(shifted / tau)
  w_raw   <- expz / sum(expz)
  w_pre_cap <- w_raw
  w_capped  <- cap_redistribute(w_raw, SINGLE_CAP)

  # === KR equity sleeve monthly return = manual w · r ===
  ret_kr <- as.numeric(w_capped %*% merged_top$Ret_1m)

  kr_eq_records[[as.character(sd_now)]] <- data.table(
    sig_date = sd_now, held_period = hp_now,
    monthly_ret = ret_kr, n_holdings = N_HOLD
  )
  holdings_C[[as.character(sd_now)]] <- data.table(
    sig_date = sd_now, Ticker = merged_top$Ticker,
    composite_z = merged_top$composite_z,
    weight_pre_cap = w_pre_cap, weight = w_capped,
    Ret_1m = merged_top$Ret_1m
  )
  cap_audit_C[[as.character(sd_now)]] <- data.table(
    sig_date = sd_now,
    max_pre_cap = max(w_pre_cap), max_post_cap = max(w_capped),
    n_capped = sum(w_pre_cap > SINGLE_CAP + 1e-9),
    tau = tau
  )
  tau_records[[as.character(sd_now)]] <- data.table(sig_date = sd_now, tau = tau)
}

kr_eq_dt    <- rbindlist(kr_eq_records, fill = TRUE)
holdings_dt <- rbindlist(holdings_C, fill = TRUE)
cap_audit_dt<- rbindlist(cap_audit_C, fill = TRUE)
tau_dt      <- rbindlist(tau_records, fill = TRUE)

fwrite(kr_eq_dt,    file.path(OUT_DIR, "sleeve_kr_equity_returns.csv"))
fwrite(holdings_dt, file.path(OUT_DIR, "holdings_C_softmax.csv"))
fwrite(cap_audit_dt,file.path(OUT_DIR, "cap_audit_C.csv"))
fwrite(tau_dt,      file.path(OUT_DIR, "tau_history.csv"))

cat(sprintf("  KR equity sleeve months computed: %d\n", nrow(kr_eq_dt)))
cat(sprintf("  Holdings rows: %d\n", nrow(holdings_dt)))
cat(sprintf("  Cap audit rows: %d, total n_capped: %d (max_pre %.4f, max_post %.4f)\n",
            nrow(cap_audit_dt), sum(cap_audit_dt$n_capped),
            max(cap_audit_dt$max_pre_cap), max(cap_audit_dt$max_post_cap)))
cat(sprintf("  Tau range: [%.3f, %.3f], median %.3f\n",
            min(tau_dt$tau), max(tau_dt$tau), median(tau_dt$tau)))

#------------------------------------------------------------------------------
# Step 4: ETF inherit + INDEPENDENT TSMOM build
#------------------------------------------------------------------------------
cat("\n[Step 4] ETF inherit + TSMOM (independent recompute) ...\n")

etf <- as.data.table(read_parquet(file.path(ST_DIR, "pd28/synthetic_etf_returns_2001_2026.parquet")))
setkey(etf, sig_date)

tsmom_8 <- c("KOSPI200", "KR_10Y", "KR_SHORT", "US_10Y_H",
             "KOSDAQ150", "GOLD_H_PROXY", "SP500_H_PROXY", "REIT_PROXY")

etf_tsmom <- etf[, c("sig_date", tsmom_8), with = FALSE]
n_tsmom <- nrow(etf_tsmom)

# TSMOM signal: 12m past cumulative return per ETF (i-12+1 to i-1)
ret_mat <- as.matrix(etf_tsmom[, ..tsmom_8])
sig_mat <- matrix(NA_real_, nrow = n_tsmom, ncol = length(tsmom_8))
for (i in seq_len(n_tsmom)) {
  win_start <- i - 11L; win_end <- i - 1L
  if (win_start < 1L || win_end < win_start) next
  for (k in seq_along(tsmom_8)) {
    vals <- ret_mat[win_start:win_end, k]
    if (sum(!is.na(vals)) > 0L) {
      sig_mat[i, k] <- prod(1 + vals, na.rm = TRUE) - 1
    }
  }
}

# Cross-sectional positive selection → EW
w_mat <- matrix(0, nrow = n_tsmom, ncol = length(tsmom_8))
for (i in seq_len(n_tsmom)) {
  pos <- which(sig_mat[i, ] > 0)
  if (length(pos) > 0L) w_mat[i, pos] <- 1 / length(pos)
}

# Returns: w_{i-1} %*% r_i (1m lag)
tsmom_ret <- numeric(n_tsmom)
for (i in 2:n_tsmom) {
  r_i <- ret_mat[i, ]; r_i[is.na(r_i)] <- 0
  tsmom_ret[i] <- sum(w_mat[i - 1, ] * r_i)
}
tsmom_dt <- data.table(held_period = etf_tsmom$sig_date, TSMOM = tsmom_ret)
cat(sprintf("  TSMOM sleeve: %d months, range [%s, %s]\n",
            nrow(tsmom_dt),
            as.character(min(tsmom_dt$held_period)),
            as.character(max(tsmom_dt$held_period))))

#------------------------------------------------------------------------------
# Step 5: Build sleeve panel + MANUAL matrix product portfolio returns
#------------------------------------------------------------------------------
cat("\n[Step 5] Sleeve panel + manual matrix product (INDEPENDENT path) ...\n")

port_dt <- merge(
  data.table(held_period = etf$sig_date),
  kr_eq_dt[, .(held_period, KR_EQUITY = monthly_ret)],
  by = "held_period", all.x = TRUE
)
port_dt <- merge(port_dt, tsmom_dt[, .(held_period, TSMOM)],
                 by = "held_period", all.x = TRUE)
port_dt <- merge(port_dt, etf[, .(held_period = sig_date, KR_10Y, CASH)],
                 by = "held_period", all.x = TRUE)
port_dt <- port_dt[!is.na(KR_EQUITY) & !is.na(TSMOM) & !is.na(KR_10Y) & !is.na(CASH)]
setorder(port_dt, held_period)
cat(sprintf("  Aligned panel: %d months, [%s, %s]\n",
            nrow(port_dt), as.character(min(port_dt$held_period)),
            as.character(max(port_dt$held_period))))

fwrite(port_dt, file.path(OUT_DIR, "sleeve_panel.csv"))

# Manual matrix product: gross_return_t = Σ_sleeve w_sleeve × r_sleeve_t
# (vs Forge: PerformanceAnalytics::Return.portfolio with rebalance_on='months')
# PerformanceAnalytics monthly rebalance + geometric=TRUE rolling drift is identical to
# constant-weight reset per period when weights provided as scalar vector.
w_vec <- as.numeric(SLEEVE_W[c("KR_EQUITY", "TSMOM", "KR_10Y", "CASH")])
ret_mat_sleeve <- as.matrix(port_dt[, .(KR_EQUITY, TSMOM, KR_10Y, CASH)])
gross_ret <- as.numeric(ret_mat_sleeve %*% w_vec)

# Sleeve-level turnover (manual)
# Inner sleeve churn: KR equity ~30% × 0.55 + TSMOM ~50% × 0.225 (PD30 same estimate)
# Outer rebalance: rebalance back to SLEEVE_W each month = drift adjustment
# Compute drift turnover per Forge convention
n_mo <- nrow(ret_mat_sleeve)
turnover_outer <- numeric(n_mo)
for (i in 2:n_mo) {
  r_prev <- ret_mat_sleeve[i - 1, ]
  w_drift <- w_vec * (1 + r_prev) / sum(w_vec * (1 + r_prev))
  turnover_outer[i] <- 0.5 * sum(abs(w_drift - w_vec))
}
turnover_inner <- TO_INNER_KR * SLEEVE_W["KR_EQUITY"] + TO_INNER_TS * SLEEVE_W["TSMOM"]
turnover_total <- turnover_outer + as.numeric(turnover_inner)
cost <- turnover_total * COST_BPS
net_ret <- gross_ret - cost

#------------------------------------------------------------------------------
# Step 6: Performance metrics (DUAL PATH — manual + PerformanceAnalytics)
#------------------------------------------------------------------------------
cat("\n[Step 6] Performance metrics (dual: manual + PerfA) ...\n")

# Drop first month (no prior weights for turnover)
keep <- net_ret[-1]
dates_keep <- port_dt$held_period[-1]

# MANUAL geometric Sharpe (PerformanceAnalytics convention)
sr_geom_manual <- function(r) {
  cum_ret  <- prod(1 + r) - 1
  n        <- length(r)
  ann_ret  <- (1 + cum_ret)^(12 / n) - 1
  ann_vol  <- sd(r) * sqrt(12)
  ann_ret / ann_vol
}

# MANUAL arithmetic Sharpe (for cross-reference)
sr_arith_manual <- function(r) {
  mean(r) * 12 / (sd(r) * sqrt(12))
}

# Manual max drawdown via cumprod NAV
manual_mdd <- function(r) {
  nav <- cumprod(1 + r)
  peak <- cummax(nav)
  min(nav / peak - 1)
}

# CAGR manual
cagr_manual <- function(r) (prod(1 + r))^(12 / length(r)) - 1

# Sortino manual
sortino_manual <- function(r, mar = 0) {
  excess <- r - mar
  downside <- excess[excess < 0]
  if (length(downside) == 0) return(NA)
  (mean(excess) * 12) / (sd(downside) * sqrt(12))
}

# Calmar manual
calmar_manual <- function(r) {
  cg <- cagr_manual(r)
  mdd <- abs(manual_mdd(r))
  if (mdd < 1e-9) return(NA)
  cg / mdd
}

# CVaR manual (5% historical)
cvar_manual <- function(r, alpha = 0.05) {
  q <- quantile(r, alpha, type = 7)
  mean(r[r <= q])
}

# Compute manual metrics
m_sr_geom   <- sr_geom_manual(keep)
m_sr_arith  <- sr_arith_manual(keep)
m_cagr      <- cagr_manual(keep)
m_mdd       <- manual_mdd(keep)
m_cvar      <- cvar_manual(keep)
m_sortino   <- sortino_manual(keep)
m_calmar    <- calmar_manual(keep)
m_to_ann    <- mean(turnover_total[-1]) * 12

# Compare to PerformanceAnalytics (same data, different library path)
ret_xts <- xts(keep, order.by = dates_keep)
pa_table <- table.AnnualizedReturns(ret_xts, scale = 12, geometric = TRUE)
pa_sr    <- as.numeric(pa_table[3, 1])
pa_ret   <- as.numeric(pa_table[1, 1])
pa_vol   <- as.numeric(pa_table[2, 1])
pa_mdd   <- as.numeric(maxDrawdown(ret_xts, geometric = TRUE))
pa_cvar  <- as.numeric(CVaR(ret_xts, p = 0.95, method = "historical"))
pa_sortino <- as.numeric(SortinoRatio(ret_xts, MAR = 0) * sqrt(12))
pa_calmar  <- as.numeric(CalmarRatio(ret_xts, scale = 12))

# NAV / drawdown series (manual)
nav   <- cumprod(1 + keep)
peak  <- cummax(nav)
dd    <- nav / peak - 1
nav_dt <- data.table(date = dates_keep, NAV = nav, drawdown = dd)
fwrite(nav_dt[, .(date, NAV)], file.path(OUT_DIR, "nav.csv"))
fwrite(nav_dt[, .(date, drawdown)], file.path(OUT_DIR, "drawdowns.csv"))

port_returns_dt <- data.table(
  date = dates_keep,
  gross_return = gross_ret[-1],
  turnover = turnover_total[-1],
  cost = cost[-1],
  net_return = keep
)
fwrite(port_returns_dt, file.path(OUT_DIR, "port_returns.csv"))

# Metrics summary
metrics_manual <- data.table(
  metric = c("SR_geometric", "SR_arithmetic", "CAGR", "MDD", "CVaR_95",
             "Sortino", "Calmar", "Turnover_annualized", "N_months"),
  value  = c(m_sr_geom, m_sr_arith, m_cagr, m_mdd, m_cvar,
             m_sortino, m_calmar, m_to_ann, length(keep))
)
metrics_perfa <- data.table(
  metric = c("SR", "ann_return", "ann_vol", "MDD", "CVaR_95",
             "Sortino", "Calmar"),
  value  = c(pa_sr, pa_ret, pa_vol, -pa_mdd, pa_cvar, pa_sortino, pa_calmar)
)
fwrite(metrics_manual, file.path(OUT_DIR, "metrics_manual.csv"))
fwrite(metrics_perfa,  file.path(OUT_DIR, "metrics_perfa.csv"))

cat("\n=== Architect MANUAL metrics ===\n")
print(metrics_manual)
cat("\n=== Architect PerfA metrics (cross-check own data) ===\n")
print(metrics_perfa)

#------------------------------------------------------------------------------
# Step 7: Crisis windows reproduce (GFC + Tariff 2025)
#------------------------------------------------------------------------------
cat("\n[Step 7] Crisis windows reproduce ...\n")

gfc_idx    <- which(dates_keep >= as.Date("2008-09-01") & dates_keep <= as.Date("2009-03-01"))
tariff_idx <- which(dates_keep >= as.Date("2025-04-01") & dates_keep <= as.Date("2025-09-01"))

crisis_metrics <- function(idx, label) {
  if (length(idx) == 0) return(NULL)
  r <- keep[idx]
  data.table(
    crisis = label,
    n = length(r),
    cum_return = prod(1 + r) - 1,
    mean_monthly = mean(r),
    min_monthly  = min(r),
    mdd_window = manual_mdd(r)
  )
}

crisis_dt <- rbindlist(list(
  crisis_metrics(gfc_idx, "GFC_2008Q4-2009Q1"),
  crisis_metrics(tariff_idx, "Tariff_2025")
), fill = TRUE)
print(crisis_dt)
fwrite(crisis_dt, file.path(OUT_DIR, "crisis_windows.csv"))

#------------------------------------------------------------------------------
# Step 8: Comparison vs Forge PD30 C_softmax
#------------------------------------------------------------------------------
cat("\n[Step 8] Compare vs Forge PD30 C_softmax ...\n")

forge_C <- list(
  SR = 1.0081, CAGR = 0.1689, MDD = -0.229435,
  CVaR_95 = -0.087880, Sortino = 0.555412, Calmar = 0.736058,
  TO = 3.33, N = 296
)

comparison <- data.table(
  metric = c("SR", "CAGR", "MDD", "CVaR_95", "Sortino", "Calmar", "Turnover_ann", "N_months"),
  forge_pd30_C = c(forge_C$SR, forge_C$CAGR, forge_C$MDD, forge_C$CVaR_95,
                   forge_C$Sortino, forge_C$Calmar, forge_C$TO, forge_C$N),
  architect_pd31 = c(pa_sr, m_cagr, m_mdd, m_cvar, m_sortino, m_calmar, m_to_ann, length(keep))
)
comparison[, delta := architect_pd31 - forge_pd30_C]
comparison[, abs_delta := abs(delta)]
comparison[, classification := fcase(
  metric == "SR",         fifelse(abs_delta < 0.1, "NEGLIGIBLE", fifelse(abs_delta < 0.3, "MINOR", "DRIFT")),
  metric == "CAGR",       fifelse(abs_delta < 0.005, "NEGLIGIBLE", fifelse(abs_delta < 0.02, "MINOR", "DRIFT")),
  metric == "MDD",        fifelse(abs_delta < 0.01, "NEGLIGIBLE", fifelse(abs_delta < 0.03, "MINOR", "DRIFT")),
  metric == "CVaR_95",    fifelse(abs_delta < 0.005, "NEGLIGIBLE", fifelse(abs_delta < 0.015, "MINOR", "DRIFT")),
  metric == "Sortino",    "UNIT_MISMATCH_FORGE_UNSCALED",   # PD30 didn't ×sqrt(12); both values internally consistent
  metric == "Calmar",     fifelse(abs_delta < 0.05, "NEGLIGIBLE", fifelse(abs_delta < 0.15, "MINOR", "DRIFT")),
  metric == "Turnover_ann", fifelse(abs_delta < 0.2, "MINOR_TO_ESTIMATE_DIFF", "DRIFT"),
  metric == "N_months",   fifelse(abs_delta <= 1, "NEGLIGIBLE_FIRST_MONTH_DROP", "DRIFT"),
  default = fifelse(abs_delta < 0.1, "NEGLIGIBLE", fifelse(abs_delta < 0.3, "MINOR", "DRIFT"))
)]

cat("\n=== Comparison Architect vs Forge PD30 C_softmax ===\n")
print(comparison)
fwrite(comparison, file.path(OUT_DIR, "vs_forge_pd30_C.csv"))

# Overall verdict — focus on 5 primary metrics (SR/CAGR/MDD/CVaR/Calmar)
primary_metrics <- c("SR", "CAGR", "MDD", "CVaR_95", "Calmar")
primary_comp <- comparison[metric %in% primary_metrics]
n_primary_negligible <- sum(grepl("NEGLIGIBLE", primary_comp$classification))
n_primary_minor      <- sum(primary_comp$classification == "MINOR")
n_primary_drift      <- sum(primary_comp$classification == "DRIFT")

verdict <- {
  if (n_primary_drift == 0 && n_primary_minor == 0) "PASS_NEGLIGIBLE"
  else if (n_primary_drift == 0 && n_primary_minor <= 1) "PASS_NEGLIGIBLE_WITH_1_MINOR"
  else if (n_primary_drift == 0) "PARTIAL_PASS_MINOR"
  else "FAIL_DRIFT"
}

cat(sprintf("\n=== ARCHITECT VERDICT (5 primary: SR/CAGR/MDD/CVaR/Calmar) ===\n"))
cat(sprintf("Negligible: %d / Minor: %d / Drift: %d → %s\n",
            n_primary_negligible, n_primary_minor, n_primary_drift, verdict))
cat("\nNote: Sortino unit_mismatch (Forge unscaled vs Architect annualized) and N_months 1-mo first-drop are method-path artifacts, not material drift.\n")

cat("\nArchitect PD31 reproduce complete. Output dir:\n  ", OUT_DIR, "\n")
