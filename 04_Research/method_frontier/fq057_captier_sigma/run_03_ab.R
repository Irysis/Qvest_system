# =============================================================================
# FQ-057 run_03: rolling estimation-quality A/B (Phase B)
# Design:
#   - rolling 60-month window, est month t_end from 200912..(last-1)
#   - universe(t_end): K200|KQ150 members at t_end, complete 60 obs, size known
#   - tiers at t_end: size-rank MEGA(<=30) / MID(31..150) / SMALL(>150)
#     (MEGA boundary = deployment TOP30_N convention, R37/R39)
#   - 5 estimators (shopping cap 5): sample / lw_linear / lw_nls / block_lw / block_nls
#   - metrics (estimation quality ONLY):
#       cond (delivered Sigma), psd_violation_pre, frob vs fwd-12m sample cov,
#       cor off-diag RMSE vs fwd-12m, stability vs prev window,
#       MVP OOS realized vol (Return.portfolio), MVP gross leverage
#   - NO SR/IR/alpha anywhere. metric_type = estimation_quality_diagnostic.
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts); library(PerformanceAnalytics)
  library(jsonlite)
})
options(warn = 1)   # print warnings when they occur (provenance audit)
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source(file.path(ROOT, "04_Research/method_frontier/fq057_captier_sigma/estimators.R"))
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")
pin_tag <- fromJSON(file.path(OUT_DIR, "fq057_pin_tag.json"))$pin_tag

mr <- as.data.table(read_parquet(file.path(OUT_DIR, "fq057_monthly_returns.parquet")))
sn <- as.data.table(read_parquet(file.path(OUT_DIR, "fq057_monthly_snapshot.parquet")))
yms <- sort(unique(mr$ym))

ym_to_date <- function(ym) {
  y <- ym %/% 100L; m <- ym %% 100L
  as.Date(sprintf("%04d-%02d-01", y + (m == 12L), ifelse(m == 12L, 1L, m + 1L))) - 1L
}
ym_shift <- function(ym, k) {
  t <- (ym %/% 100L) * 12L + (ym %% 100L - 1L) + k
  (t %/% 12L) * 100L + t %% 12L + 1L
}

# ---- precompute cap-w market return per month (lagged month-end size, PIT) --
memb_sz <- sn[member == 1L & !is.na(size), .(Ticker, ym, size)]
memb_sz[, ym_next := ym_shift(ym, 1L)]      # weights formed at m apply to m+1
mkt_dt <- merge(mr, memb_sz[, .(Ticker, ym = ym_next, w_size = size)],
                by = c("Ticker", "ym"))
mkt_series <- mkt_dt[, .(mkt = sum(ret_m * w_size) / sum(w_size)), by = ym][order(ym)]
cat("[mkt] months:", nrow(mkt_series), "\n")

EST_NAMES <- c("sample", "lw_linear", "lw_nls", "block_lw", "block_nls")
est_ends <- yms[yms >= 200912 & yms < max(yms)]
cat("[loop] windows:", length(est_ends), "\n")

metrics_rows <- list()
mvp_store <- list()   # [[est]][[as.character(eval_ym)]] = named weights
prev_sig <- setNames(vector("list", 5), EST_NAMES)

t0 <- Sys.time()
for (wi in seq_along(est_ends)) {
  t_end <- est_ends[wi]
  win <- yms[yms <= t_end]; win <- tail(win, 60)
  if (length(win) < 60) next
  memb <- sn[ym == t_end & member == 1L & !is.na(size), .(Ticker, size)]
  sub <- mr[ym %in% win & Ticker %in% memb$Ticker]
  full <- sub[, .N, by = Ticker][N == 60, Ticker]
  if (length(full) < 50) next
  Wc <- dcast(sub[Ticker %in% full], ym ~ Ticker, value.var = "ret_m")
  Rm <- as.matrix(Wc[, -1]); rownames(Rm) <- Wc$ym
  p <- ncol(Rm); n <- nrow(Rm)
  sz <- memb[match(colnames(Rm), Ticker), size]
  rk <- frank(-sz, ties.method = "first")
  tier <- fifelse(rk <= 30, "MEGA", fifelse(rk <= 150, "MID", "SMALL"))
  mkt <- mkt_series[match(win, ym), mkt]
  if (anyNA(mkt)) next
  eval_ym <- ym_shift(t_end, 1L)

  # forward 12m sample cov (for frob/cor loss; NA when insufficient)
  fwd_yms <- ym_shift(t_end, 1:12)
  S_fwd <- NULL
  if (all(fwd_yms %in% yms)) {
    fsub <- mr[ym %in% fwd_yms & Ticker %in% colnames(Rm)]
    fok <- fsub[, .N, by = Ticker][N >= 10, Ticker]
    if (length(fok) >= 50) {
      Fw <- dcast(fsub[Ticker %in% fok], ym ~ Ticker, value.var = "ret_m")
      Fm <- as.matrix(Fw[, -1])
      S_fwd <- est_sample(Fm)
    }
  }

  sigs <- list()
  psd_pre <- c(sample = FALSE, lw_linear = FALSE, lw_nls = FALSE,
               block_lw = NA, block_nls = NA)
  ev_sample <- eigen(est_sample(Rm), symmetric = TRUE, only.values = TRUE)$values
  sigs$sample    <- est_sample(Rm)
  psd_pre["sample"] <- min(ev_sample) < -1e-8 * max(ev_sample)
  sigs$lw_linear <- est_lw_linear(Rm)
  sigs$lw_nls    <- est_lw_nls(Rm)
  bl_lw  <- est_block(Rm, tier, mkt, inner = "lw")
  bl_nls <- est_block(Rm, tier, mkt, inner = "nls")
  sigs$block_lw  <- bl_lw$Sig;  psd_pre["block_lw"]  <- bl_lw$psd_violated_pre
  sigs$block_nls <- bl_nls$Sig; psd_pre["block_nls"] <- bl_nls$psd_violated_pre

  for (en in EST_NAMES) {
    Sg <- sigs[[en]]
    cn <- cond_number(Sg)
    fr <- if (!is.null(S_fwd)) frob_rel(Sg, S_fwd) else NA_real_
    cr <- if (!is.null(S_fwd)) cor_offdiag_rmse(Sg, S_fwd) else NA_real_
    st <- if (!is.null(prev_sig[[en]])) {
      common <- intersect(colnames(Sg), colnames(prev_sig[[en]]))
      a <- Sg[common, common]; b <- prev_sig[[en]][common, common]
      sqrt(sum((a - b)^2)) / max(sqrt(sum(b^2)), 1e-12)
    } else NA_real_
    w <- mvp_weights(Sg)
    names(w) <- colnames(Sg)
    mvp_store[[en]][[as.character(eval_ym)]] <- w
    metrics_rows[[length(metrics_rows) + 1]] <- data.table(
      est = en, t_end = t_end, eval_ym = eval_ym, p = p, n = n,
      cond = cn, psd_violated_pre = as.logical(psd_pre[en]),
      frob_fwd12 = fr, cor_rmse_fwd12 = cr, stability_rel = st,
      mvp_gross_leverage = sum(abs(w)),
      n_mega = sum(tier == "MEGA"), n_mid = sum(tier == "MID"),
      n_small = sum(tier == "SMALL"))
    prev_sig[[en]] <- Sg
  }
  if (wi %% 24 == 0) cat("[loop]", wi, "/", length(est_ends), "elapsed",
                         round(difftime(Sys.time(), t0, units = "mins"), 1), "min\n")
}
met <- rbindlist(metrics_rows)
cat("[loop] done rows:", nrow(met), "\n")

# ---- MVP OOS portfolio returns via Return.portfolio -------------------------
mvp_oos <- list()
for (en in EST_NAMES) {
  ws <- mvp_store[[en]]
  eyms <- as.integer(names(ws))
  all_names <- sort(unique(unlist(lapply(ws, names))))
  Wm <- matrix(0, length(eyms), length(all_names),
               dimnames = list(NULL, all_names))
  for (i in seq_along(eyms)) Wm[i, names(ws[[i]])] <- ws[[i]]
  # weight dated at end of estimation month (= month before eval month)
  w_dates <- ym_to_date(ym_shift(eyms, -1L))
  # returns for eval months over union of names
  rsub <- mr[ym %in% eyms & Ticker %in% all_names]
  Rw <- dcast(rsub, ym ~ Ticker, value.var = "ret_m")
  Rmat <- matrix(0, length(eyms), length(all_names),
                 dimnames = list(NULL, all_names))
  rym <- Rw$ym
  Rmat[match(rym, eyms), match(colnames(Rw)[-1], all_names)] <-
    as.matrix(Rw[, -1])
  n_missing <- sum(is.na(Rmat[cbind(rep(1:nrow(Wm), ncol(Wm)),
                                    rep(1:ncol(Wm), each = nrow(Wm)))]) &
                   as.vector(Wm != 0))
  Rmat[is.na(Rmat)] <- 0   # delisted-with-held-weight -> 0 (counted above)
  r_xts <- xts(Rmat, order.by = ym_to_date(eyms))
  w_xts <- xts(Wm, order.by = w_dates)
  pr <- Return.portfolio(r_xts, weights = w_xts, verbose = FALSE)
  mvp_oos[[en]] <- data.table(eval_ym = as.integer(format(index(pr), "%Y%m")),
                              est = en, port_ret = as.numeric(pr),
                              n_missing_heldret = n_missing)
}
oos <- rbindlist(mvp_oos)
# realized OOS vol (annualized) via StdDev.annualized (PerformanceAnalytics)
vol_tbl <- oos[, .(mvp_oos_vol_ann =
    as.numeric(StdDev.annualized(xts(port_ret, order.by = ym_to_date(eval_ym)),
                                 scale = 12))), by = est]

# ---- summary + composite estimation-quality ranking -------------------------
summ <- met[, .(
  n_windows = .N,
  cond_median = median(cond[is.finite(cond)]),
  cond_inf_rate = mean(!is.finite(cond)),
  psd_viol_rate = mean(psd_violated_pre, na.rm = TRUE),
  frob_fwd12_mean = mean(frob_fwd12, na.rm = TRUE),
  cor_rmse_fwd12_mean = mean(cor_rmse_fwd12, na.rm = TRUE),
  stability_rel_median = median(stability_rel, na.rm = TRUE),
  mvp_gross_leverage_median = median(mvp_gross_leverage)
), by = est]
summ <- merge(summ, vol_tbl, by = "est")

# ranks: lower better everywhere; cond uses (median with Inf-rate penalty)
rk_of <- function(x) frank(x, ties.method = "average")
summ[, r_cond := rk_of(cond_median + cond_inf_rate * 1e12)]
summ[, r_psd  := rk_of(psd_viol_rate)]
summ[, r_frob := rk_of(frob_fwd12_mean)]
summ[, r_cor  := rk_of(cor_rmse_fwd12_mean)]
summ[, r_stab := rk_of(stability_rel_median)]
summ[, r_vol  := rk_of(mvp_oos_vol_ann)]
summ[, composite_rank := (r_cond + r_psd + r_frob + r_cor + r_stab + r_vol) / 6]
setorder(summ, composite_rank)
print(summ)

write_parquet(met, file.path(OUT_DIR, "fq057_ab_metrics.parquet"))
write_parquet(oos, file.path(OUT_DIR, "fq057_mvp_oos_returns.parquet"))
ab_summary <- list(
  pin_tag = pin_tag,
  metric_type = "estimation_quality_diagnostic",
  selection_objective = "shrinkage_quality",
  selection_rule = "equal-weight rank composite over {cond, psd_violation, frob_fwd12, cor_rmse_fwd12, stability, mvp_oos_vol}; NO return/SR/IR metrics used",
  mvp_note = "unconstrained MVP = estimation-quality instrument (Ledoit-Wolf horse-race convention), NOT an allocation proposal",
  tier_rule = "size-rank at window end: MEGA<=30 (TOP30_N deployment convention R37/R39) / MID 31..150 / SMALL >150",
  summary = summ,
  selected = summ$est[1]
)
write_json(ab_summary, file.path(OUT_DIR, "fq057_ab_summary.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 8)
cat("[done] selected (estimation quality):", summ$est[1], "\n")
