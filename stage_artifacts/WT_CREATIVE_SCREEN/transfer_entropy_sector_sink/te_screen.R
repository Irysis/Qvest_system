#==============================================================================
# CREATIVE SCREEN — Transfer-Entropy Sector Information-Propagation Sink
#
# Idea: within a sector, pairwise transfer entropy TE(j->i) on daily-return
#   tercile-discretized series (rolling 90d). net_TE_inflow_i = sum_j TE(j->i)
#   - sum_j TE(i->j). "Sink" stocks (high net inflow = absorb info late) are
#   hypothesized to exhibit short-term drift.
#
# SCREEN ONLY — read-only signal -> forward Rank-IC / ICIR / Harvey-t(NW) +
#   orthogonality (partial IC vs M24/L19/CR07) + subperiod stability.
#   NO backtest / NO portfolio / NO admission.
#
# PIT: all features use daily Ret strictly BEFORE sig_date (Date < sig_date,
#   C2 strict). forward label = next-H-day return via shift(...,type="lead").
#   lockbox cutoff 2023-12-22 strict (regular research). Usable_Date<=sig_date.
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(dplyr)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT  <- file.path(PROJ, "stage_artifacts/WT_CREATIVE_SCREEN/transfer_entropy_sector_sink")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

# ---- params ----
LOCKBOX   <- as.Date("2023-12-22")   # strict (regular research)
TE_WIN    <- 90L                      # rolling daily window for TE
H         <- 21L                      # forward label horizon (1 trading month)
NQ        <- 3L                       # tercile discretization
CHEAP_SECTORS <- c("반도체", "화학")  # 반도체(34), 화학(25) - largest
MIN_PAIR_OVERLAP <- 60L               # min overlapping non-NA daily obs in TE_WIN
LIQ_THRESH <- 2e8

cat("== loading rawdata ==\n")
raw <- as.data.table(arrow::open_dataset(file.path(PROJ, ".cache/rawdata.parquet")) %>%
  select(Date, Ticker, Ret, Close, Vol, Sector_Lv2, K200, KQ150) %>% collect())
raw[, Date := as.Date(Date)]
raw <- raw[!is.na(Ret) & Sector_Lv2 %in% CHEAP_SECTORS]
raw[, in_univ := (K200 == 1 | KQ150 == 1)]
setkey(raw, Ticker, Date)

# universe membership at each date (PIT: known at t)
# liquidity proxy: 20d avg traded value (Close*Vol), lagged t-1
raw[, tval := Close * Vol]
raw[, liq20 := frollmean(shift(tval, 1L, type = "lag"), 20L, na.rm = TRUE), by = Ticker]

# ---- sig_dates: month-end trading days within data, capped at LOCKBOX ----
all_dates <- sort(unique(raw$Date))
all_dates <- all_dates[all_dates <= LOCKBOX]
dt_dates <- data.table(Date = all_dates)
dt_dates[, ym := format(Date, "%Y%m")]
sig_dates <- dt_dates[, .(sig = max(Date)), by = ym]$sig
# need enough history (TE_WIN) and need >=2 sectors with stocks
sig_dates <- sig_dates[sig_dates >= (min(all_dates) + 200)]
cat("n sig_dates (<= lockbox):", length(sig_dates), " range:",
    as.character(min(sig_dates)), "to", as.character(max(sig_dates)), "\n")

# forward labels need future data beyond lockbox -> allowed (label only future)
raw_full <- as.data.table(arrow::open_dataset(file.path(PROJ, ".cache/rawdata.parquet")) %>%
  select(Date, Ticker, Ret) %>% collect())
raw_full[, Date := as.Date(Date)]
raw_full <- raw_full[!is.na(Ret)]
setkey(raw_full, Ticker, Date)

#------------------------------------------------------------------------------
# Transfer entropy estimator (k=1 history, lag-1 source), tercile discretized.
#   TE(j->i) = sum p(i1,i0,j0) * log2[ p(i1|i0,j0) / p(i1|i0) ]
# i1 = i_{t+1}, i0 = i_t, j0 = j_t. Uses NQ x NQ x NQ contingency w/ +eps.
#------------------------------------------------------------------------------
te_pair <- function(xi, xj) {
  # xi, xj: aligned daily return vectors (same length), already filtered non-NA
  n <- length(xi)
  if (n < MIN_PAIR_OVERLAP + 1L) return(NA_real_)
  # tercile bins computed WITHIN window (rolling, self-contained -> PIT ok)
  bi <- unique(quantile(xi, probs = seq(0, 1, length.out = NQ + 1L), na.rm = TRUE, type = 7))
  bj <- unique(quantile(xj, probs = seq(0, 1, length.out = NQ + 1L), na.rm = TRUE, type = 7))
  # degenerate (ties collapse breaks) -> not enough distinct states, skip pair
  if (length(bi) < NQ + 1L || length(bj) < NQ + 1L) return(NA_real_)
  qi <- cut(xi, breaks = bi, include.lowest = TRUE, labels = FALSE)
  qj <- cut(xj, breaks = bj, include.lowest = TRUE, labels = FALSE)
  if (any(is.na(qi)) || any(is.na(qj))) return(NA_real_)
  i1 <- qi[-1]; i0 <- qi[-n]; j0 <- qj[-n]
  eps <- 1e-9
  # joint p(i1,i0,j0)
  tab3 <- table(factor(i1, 1:NQ), factor(i0, 1:NQ), factor(j0, 1:NQ)) + eps
  p3 <- tab3 / sum(tab3)
  # p(i0,j0)
  p_i0j0 <- apply(p3, c(2, 3), sum)
  # p(i1,i0)
  p_i1i0 <- apply(p3, c(1, 2), sum)
  # p(i0)
  p_i0 <- apply(p3, 2, sum)
  te <- 0
  for (a in 1:NQ) for (b in 1:NQ) for (c in 1:NQ) {
    pj <- p3[a, b, c]
    cond_full <- pj / p_i0j0[b, c]            # p(i1|i0,j0)
    cond_red  <- p_i1i0[a, b] / p_i0[b]        # p(i1|i0)
    te <- te + pj * log2(cond_full / cond_red)
  }
  max(te, 0)  # TE >= 0 in theory; clamp numerical noise
}

#------------------------------------------------------------------------------
# Compute net_TE_inflow per stock per sig_date (within sector)
#------------------------------------------------------------------------------
results <- list()
for (sd_i in sig_dates) {
  sdd <- as.Date(sd_i, origin = "1970-01-01")
  win_lo <- sdd - 200  # generous calendar lookback to gather TE_WIN trading days
  # PIT: strictly BEFORE sig_date
  hist <- raw[Date < sdd & Date >= win_lo & in_univ == TRUE & liq20 >= LIQ_THRESH]
  if (nrow(hist) == 0) next
  for (sec in CHEAP_SECTORS) {
    h <- hist[Sector_Lv2 == sec]
    # take last TE_WIN trading dates available before sig_date
    last_dates <- tail(sort(unique(h$Date)), TE_WIN)
    h <- h[Date %in% last_dates]
    tks <- h[, .N, by = Ticker][N >= MIN_PAIR_OVERLAP, Ticker]
    if (length(tks) < 4) next
    # wide matrix date x ticker of returns
    w <- dcast(h[Ticker %in% tks], Date ~ Ticker, value.var = "Ret")
    rmat <- as.matrix(w[, -1, with = FALSE])
    colnames(rmat) <- names(w)[-1]
    ntk <- ncol(rmat)
    te_mat <- matrix(NA_real_, ntk, ntk, dimnames = list(colnames(rmat), colnames(rmat)))
    for (a in 1:ntk) for (b in 1:ntk) {
      if (a == b) next
      idx <- which(!is.na(rmat[, a]) & !is.na(rmat[, b]))
      if (length(idx) < MIN_PAIR_OVERLAP + 1L) next
      te_mat[a, b] <- te_pair(rmat[idx, b], rmat[idx, a])  # te_pair(xi=target b? )
    }
    # te_mat[a,b] currently = TE with te_pair(xi=rmat[,b], xj=rmat[,a])
    #   te_pair(xi,xj) measures xj -> xi. So te_mat[a,b] = TE(a -> b).
    #   inflow to stock s = sum over sources a of TE(a -> s) = colSums.
    #   outflow from s   = sum over targets b of TE(s -> b) = rowSums.
    inflow  <- colSums(te_mat, na.rm = TRUE)
    outflow <- rowSums(te_mat, na.rm = TRUE)
    net_inflow <- inflow - outflow   # high = sink (absorbs late)
    results[[length(results) + 1]] <- data.table(
      sig_date = sdd, Sector_Lv2 = sec, Ticker = names(net_inflow),
      net_TE_inflow = as.numeric(net_inflow),
      TE_inflow = as.numeric(inflow), TE_outflow = as.numeric(outflow)
    )
  }
}
sig_dt <- rbindlist(results)
cat("signal rows:", nrow(sig_dt), " unique sig_dates with signal:",
    uniqueN(sig_dt$sig_date), "\n")

#------------------------------------------------------------------------------
# Forward label: H-day forward cumulative return from sig_date (FORWARD)
#   build per-ticker forward return = prod(1+Ret) over next H trading days.
#   Use index-based shift on dates (no future contamination of signal).
#------------------------------------------------------------------------------
# forward H-day simple return via log-sum on raw_full
raw_full[, logret := log1p(Ret)]
raw_full[, fwd_logsum := {
  n <- .N
  cs <- cumsum(logret)
  # forward sum over (t+1 .. t+H): cs[t+H] - cs[t]
  shifted <- shift(cs, n = -H, type = "lag")  # cs at t+H (FORWARD per convention table)
  out <- shifted - cs
  out
}, by = Ticker]
raw_full[, fwd_ret := expm1(fwd_logsum)]

lab <- raw_full[, .(Ticker, sig_date = Date, fwd_ret)]
panel <- merge(sig_dt, lab, by = c("Ticker", "sig_date"), all.x = TRUE)
panel <- panel[is.finite(net_TE_inflow) & is.finite(fwd_ret)]
cat("panel rows w/ label:", nrow(panel), "\n")

saveRDS(panel, file.path(OUT, "te_panel.rds"))

#------------------------------------------------------------------------------
# Cross-sectional Rank-IC per sig_date (Spearman), pooled across cheap sectors
#------------------------------------------------------------------------------
ic_by_date <- panel[, {
  if (.N >= 6 && length(unique(net_TE_inflow)) > 2) {
    list(rank_ic = cor(net_TE_inflow, fwd_ret, method = "spearman"), n = .N)
  } else list(rank_ic = NA_real_, n = .N)
}, by = sig_date][!is.na(rank_ic)]
setorder(ic_by_date, sig_date)
cat("n sig_dates with IC:", nrow(ic_by_date), "\n")

# ---- Harvey-t (NW) on rank-IC time series ----
nw_t <- function(x, lag = NULL) {
  x <- x[is.finite(x)]; n <- length(x)
  if (n < 5) return(c(t = NA, se = NA, lag = NA))
  if (is.null(lag)) lag <- floor(4 * (n / 100)^(2/9))
  mu <- mean(x); e <- x - mu
  g0 <- sum(e^2) / n
  v <- g0
  if (lag >= 1) for (l in 1:lag) {
    wgt <- 1 - l / (lag + 1)
    gl <- sum(e[(l+1):n] * e[1:(n-l)]) / n
    v <- v + 2 * wgt * gl
  }
  se <- sqrt(v / n)
  c(t = mu / se, se = se, lag = lag)
}
ts_ic <- ic_by_date$rank_ic
mean_ic <- mean(ts_ic)
sd_ic   <- sd(ts_ic)
icir    <- mean_ic / sd_ic
naive_t <- mean_ic / (sd_ic / sqrt(length(ts_ic)))
nw <- nw_t(ts_ic)

# ---- subperiod stability (split halves + yearly sign) ----
h1 <- ts_ic[1:floor(length(ts_ic)/2)]
h2 <- ts_ic[(floor(length(ts_ic)/2)+1):length(ts_ic)]
ic_by_date[, yr := format(sig_date, "%Y")]
yearly <- ic_by_date[, .(yic = mean(rank_ic)), by = yr]
sign_consistency <- mean(sign(yearly$yic) == sign(mean_ic))
min_over_mean <- if (abs(mean(c(mean(h1), mean(h2)))) > 1e-12)
  min(abs(mean(h1)), abs(mean(h2))) / abs(mean(c(mean(h1), mean(h2)))) else NA

#------------------------------------------------------------------------------
# Orthogonality: partial / residual IC controlling for M24/L19/CR07
#   Regress net_TE_inflow on controls (cross-sectionally per date), take
#   residual signal, recompute forward Rank-IC. Reported as incremental IC.
#------------------------------------------------------------------------------
cat("== loading control factors (monthly factor DB) ==\n")
CTRLS <- c("M24_Sector_Rel_Mom", "L19_Price_Delay", "CR07_Momentum_Crowding")
load_ctrl_month <- function(sdd) {
  ym <- format(sdd, "%Y%m")
  fp <- file.path(PROJ, ".cache/factor_db", paste0("factor_db_", ym, ".parquet"))
  if (!file.exists(fp)) {
    avail <- list.files(file.path(PROJ, ".cache/factor_db"),
                        pattern = "^factor_db_\\d{6}\\.parquet$")
    yma <- sort(gsub("factor_db_(\\d{6})\\.parquet", "\\1", avail))
    cl <- yma[yma <= ym]; if (!length(cl)) return(NULL)
    fp <- file.path(PROJ, ".cache/factor_db", paste0("factor_db_", max(cl), ".parquet"))
  }
  d <- as.data.table(read_parquet(fp))
  d <- d[Factor_Name %in% CTRLS, .(Ticker, Factor_Name, Z_Score)]
  if (!nrow(d)) return(NULL)
  dcast(d, Ticker ~ Factor_Name, value.var = "Z_Score")
}

resid_ic_list <- c(); raw_ctrl_ic <- list(); spearman_ctrl <- list()
for (cf in CTRLS) { raw_ctrl_ic[[cf]] <- c(); spearman_ctrl[[cf]] <- c() }
n_resid_dates <- 0
for (sdd in sort(unique(panel$sig_date))) {
  sddd <- as.Date(sdd, origin = "1970-01-01")
  pp <- panel[sig_date == sddd]
  cm <- load_ctrl_month(sddd)
  if (is.null(cm)) next
  m <- merge(pp, cm, by = "Ticker", all.x = TRUE)
  avail_ctrls <- intersect(CTRLS, names(m))
  m <- m[stats::complete.cases(m[, c("net_TE_inflow", "fwd_ret", avail_ctrls), with = FALSE])]
  if (nrow(m) < 8 || length(avail_ctrls) == 0) next
  # spearman corr of signal vs each control + control raw IC
  for (cf in avail_ctrls) {
    spearman_ctrl[[cf]] <- c(spearman_ctrl[[cf]],
                             cor(m$net_TE_inflow, m[[cf]], method = "spearman"))
    raw_ctrl_ic[[cf]] <- c(raw_ctrl_ic[[cf]],
                           cor(m[[cf]], m$fwd_ret, method = "spearman"))
  }
  # residualize net_TE_inflow on controls (cross-sectional OLS)
  fm <- as.formula(paste("net_TE_inflow ~", paste(avail_ctrls, collapse = " + ")))
  res <- tryCatch(residuals(lm(fm, data = m)), error = function(e) NULL)
  if (is.null(res)) next
  if (length(unique(res)) > 2) {
    resid_ic_list <- c(resid_ic_list, cor(res, m$fwd_ret, method = "spearman"))
    n_resid_dates <- n_resid_dates + 1
  }
}
resid_mean <- mean(resid_ic_list)
resid_sd   <- sd(resid_ic_list)
resid_icir <- resid_mean / resid_sd
resid_nw   <- nw_t(resid_ic_list)
retention  <- if (abs(mean_ic) > 1e-12) resid_mean / mean_ic else NA

#------------------------------------------------------------------------------
# Emit screen JSON
#------------------------------------------------------------------------------
round3 <- function(x, d = 5) if (is.finite(x)) round(x, d) else NA
out <- list(
  idea = "Transfer-Entropy sector information-propagation SINK: within-sector pairwise TE(j->i) on tercile-discretized daily returns (rolling 90d) -> net_TE_inflow_i = sum_j TE(j->i) - sum_j TE(i->j). High net inflow = info-sink (absorbs late) hypothesized short-term drift.",
  estimator = "k=1 history, lag-1 source transfer entropy (NQ=3 tercile bins, within-window contingency + eps Laplace smoothing, log2). NOT continuous KSG; cheap-test on 2 largest sectors only.",
  data_feasible = TRUE,
  universe = "KOSPI200 union KOSDAQ150 (K200==1|KQ150==1), liq20(t-1)>=2e8; cheap-test sectors = 반도체(~34)+화학(~25)",
  te_window_days = TE_WIN, horizon_days = H, n_quantiles = NQ,
  lockbox_cutoff = "2023-12-22",
  n_sig_dates_signal = uniqueN(sig_dt$sig_date),
  n_sig_dates_ic = nrow(ic_by_date),
  n_obs_panel = nrow(panel),
  rank_ic = round3(mean_ic), icir = round3(icir),
  naive_t = round3(naive_t),
  harvey_t_rankic_NW = round3(unname(nw["t"]), 3), nw_lag = unname(nw["lag"]),
  subperiod = list(h1_ic = round3(mean(h1)), h2_ic = round3(mean(h2)),
                   min_over_mean = round3(min_over_mean, 4),
                   yearly_sign_consistency = round3(sign_consistency, 4)),
  orthogonality = list(
    controls = CTRLS,
    method = "cross-sectional OLS residualization of net_TE_inflow on controls, then forward Rank-IC of residual (incremental/partial IC)",
    n_resid_dates = n_resid_dates,
    residual_rank_ic = round3(resid_mean), residual_icir = round3(resid_icir),
    residual_harvey_t = round3(unname(resid_nw["t"]), 3),
    retention_ratio = round3(retention, 4),
    spearman_corr = lapply(spearman_ctrl, function(z) round3(mean(z, na.rm = TRUE), 4)),
    control_raw_ic = lapply(raw_ctrl_ic, function(z) round3(mean(z, na.rm = TRUE), 5))
  ),
  pit_notes = "TE features Date<sig_date strict (C2); within-window tercile bins (no full-sample). forward label = H-day fwd via cs[t+H]-cs[t] (shift n=-H type=lag, FORWARD per data_table_shift_convention). lockbox<=2023-12-22 strict (regular research). controls Z_Score via factor DB (Usable_Date<=sig_date by construction of monthly snapshot).",
  caveat = "rank-IC is SCREEN/advisory ONLY, NOT tradeable alpha (Cycle2: rank-IC t >> portfolio-alpha t). cheap-test 2 sectors. Pass => recommend formal canonical_screen_bt + forge + full-universe TE.",
  generated = as.character(Sys.time())
)
jsonlite::write_json(out, file.path(OUT, "screen_result.json"),
                     auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")
cat("\n==== SCREEN RESULT ====\n")
cat("rank_ic:", round3(mean_ic), " icir:", round3(icir),
    " harvey_t:", round3(unname(nw["t"]),3), " naive_t:", round3(naive_t), "\n")
cat("n_sig_dates_ic:", nrow(ic_by_date), " n_obs:", nrow(panel), "\n")
cat("residual_rank_ic:", round3(resid_mean), " residual_harvey_t:",
    round3(unname(resid_nw["t"]),3), " retention:", round3(retention,3), "\n")
cat("subperiod h1/h2:", round3(mean(h1)), round3(mean(h2)),
    " min/mean:", round3(min_over_mean,3), " sign_consist:", round3(sign_consistency,3), "\n")
cat("written:", file.path(OUT, "screen_result.json"), "\n")
