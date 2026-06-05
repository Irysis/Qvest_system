#==============================================================================
# WT-D20260528_003 Hypothesis A — Step 3
# - Monotonicity (decile spread)
# - Multi-sleeve vs single-sleeve improvement (RF-A2 sentinel)
# - Alpha inheritance correlation vs STR_1722 (parent alpha_package — must < 0.95)
# - Sector tilt diagnostics (RF-A4 check)
# - Liquidity / capacity check
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

t0 <- Sys.time()

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJ)

OUT_DIR <- "stage_artifacts/WT_D20260528_003_overnight_A"
panel_dt <- as.data.table(readRDS(file.path(OUT_DIR, "panel_neut.rds")))
ic_wf    <- as.data.table(readRDS(file.path(OUT_DIR, "ic_wf.rds")))
alpha_dt <- as.data.table(readRDS(file.path(OUT_DIR, "alpha_dt_sleeves.rds")))
port_ret <- as.data.table(readRDS(file.path(OUT_DIR, "port_ret.rds")))

# Limit panel to walk-forward range
wf_dates <- unique(ic_wf$sig_date)
panel_wf <- panel_dt[sig_date %in% wf_dates & !is.na(fwd_1m)]

# ---- 3.1 Monotonicity (decile spread, D43_neut + D44_neut) ----
cat("[Step 3.1] Decile spread + monotonicity\n")

build_decile <- function(panel_wf, z_col) {
  pw <- copy(panel_wf)
  pw[, deci := cut(get(z_col),
                   breaks = quantile(get(z_col), probs = seq(0, 1, 0.1),
                                     na.rm = TRUE, type = 8),
                   include.lowest = TRUE, labels = 1:10),
     by = sig_date]
  decile_ret <- pw[!is.na(deci), .(mean_fwd_1m = mean(fwd_1m, na.rm = TRUE),
                                    N = .N), by = .(sig_date, deci)]
  setorder(decile_ret, sig_date, deci)
  decile_ret
}

dec_d43 <- build_decile(panel_wf, "Z43_neut")
dec_d44 <- build_decile(panel_wf, "Z44_neut")

# Average decile return (across sig_dates)
avg_dec <- function(dec) {
  d <- dec[, .(mean_ret = mean(mean_fwd_1m, na.rm = TRUE),
               n_sigdates = .N), by = deci]
  setorder(d, deci)
  d
}

avg_43 <- avg_dec(dec_d43)
avg_44 <- avg_dec(dec_d44)
cat("  D43_neut decile mean fwd_1m:\n")
print(avg_43)
cat("  D44_neut decile mean fwd_1m:\n")
print(avg_44)

# Monotonicity = Spearman corr(decile_rank, mean_ret)
mono_43 <- cor(as.numeric(as.character(avg_43$deci)), avg_43$mean_ret, method = "spearman")
mono_44 <- cor(as.numeric(as.character(avg_44$deci)), avg_44$mean_ret, method = "spearman")

# Top-Bottom decile spread
spread_43 <- avg_43[deci == 10, mean_ret] - avg_43[deci == 1, mean_ret]
spread_44 <- avg_44[deci == 10, mean_ret] - avg_44[deci == 1, mean_ret]

cat(sprintf("  D43_neut monotonicity (Spearman dec_rank vs mean_ret) = %+.3f\n", mono_43))
cat(sprintf("  D44_neut monotonicity                                 = %+.3f\n", mono_44))
cat(sprintf("  D43_neut top10-bottom10 spread = %+.4f (monthly)\n", spread_43))
cat(sprintf("  D44_neut top10-bottom10 spread = %+.4f (monthly)\n", spread_44))

# ---- 3.2 Multi-sleeve vs single-sleeve improvement (RF-A2 sentinel) ----
cat("\n[Step 3.2] Multi-sleeve vs single-sleeve EW portfolio (top 20)\n")

# Build single-sleeve top 20 portfolio (D43 only top 20 / D44 only top 20)
build_single_sleeve <- function(panel_wf, z_col, k = 20) {
  pw <- copy(panel_wf)
  pw[, rank_z := frank(-get(z_col)), by = sig_date]
  pw[rank_z <= k, .(ret = mean(fwd_1m, na.rm = TRUE), N = .N),
     by = sig_date]
}

ss_d43 <- build_single_sleeve(panel_wf, "Z43_neut", 20)
ss_d44 <- build_single_sleeve(panel_wf, "Z44_neut", 20)

# Merge BM
bm_map <- port_ret[, .(sig_date, BM_next_1m)]
ss_d43 <- merge(ss_d43, bm_map, by = "sig_date", all.x = TRUE)
ss_d43[, ER := ret - BM_next_1m]
ss_d44 <- merge(ss_d44, bm_map, by = "sig_date", all.x = TRUE)
ss_d44[, ER := ret - BM_next_1m]

# Newey-West t function (re-define local)
nw_tstat <- function(x, lags = 6) {
  x <- x[!is.na(x)]
  n <- length(x)
  if (n < 12) return(list(t = NA, se = NA, n = n))
  m <- mean(x)
  ex <- x - m
  s2 <- sum(ex^2) / n
  for (k in 1:lags) {
    w <- 1 - k / (lags + 1)
    s2 <- s2 + 2 * w * sum(ex[1:(n-k)] * ex[(k+1):n]) / n
  }
  se <- sqrt(s2 / n)
  list(t = m / se, se = se, n = n)
}

perf_summary <- function(er, label) {
  er <- er[!is.na(er)]
  m  <- mean(er); s <- sd(er)
  ir <- if (s > 0) m / s else NA_real_
  sr <- ir * sqrt(12)
  nw <- nw_tstat(er, lags = 6)
  cat(sprintf("  %-20s mean_ER=%+.4f sd=%.4f SR_ann=%+.2f t_nw=%+.2f N=%d\n",
              label, m, s, sr, nw$t, nw$n))
  list(label = label, mean_er = round(m, 4), sd = round(s, 4),
       sr_ann = round(sr, 2), t_nw = round(nw$t, 2), n = nw$n)
}

p_ss_43 <- perf_summary(ss_d43$ER, "D43 single (top20)")
p_ss_44 <- perf_summary(ss_d44$ER, "D44 single (top20)")
p_multi <- perf_summary(port_ret$ER, "Multi-sleeve (10+10)")

# Composite IC weighted single (Z43*ir43 + Z44*ir44)
# Build composite top 20 portfolio using walk-forward weights
cat("\n  Composite walk-forward (top 20 by combined score):\n")
panel_wf_comp <- merge(panel_wf, ic_wf[, .(sig_date, w_43_wf, w_44_wf)],
                       by = "sig_date", all.x = TRUE)
panel_wf_comp <- panel_wf_comp[!is.na(w_43_wf)]
panel_wf_comp[, score := w_43_wf * Z43_neut + w_44_wf * Z44_neut]
panel_wf_comp[, rank_score := frank(-score), by = sig_date]

ss_comp <- panel_wf_comp[rank_score <= 20, .(ret = mean(fwd_1m, na.rm = TRUE), N = .N),
                         by = sig_date]
ss_comp <- merge(ss_comp, bm_map, by = "sig_date", all.x = TRUE)
ss_comp[, ER := ret - BM_next_1m]
p_comp <- perf_summary(ss_comp$ER, "Composite WF (top20)")

# RF-A2: composite improvement vs best single
best_single_sr <- max(p_ss_43$sr_ann, p_ss_44$sr_ann)
improvement <- (p_multi$sr_ann - best_single_sr) / pmax(abs(best_single_sr), 0.01)
cat(sprintf("\n  Multi-sleeve vs best single: improvement = %+.1f%%\n",
            improvement * 100))
rf_a2_trigger <- improvement < 0.05  # < 5% improvement
cat(sprintf("  RF-A2 trigger: %s\n", if (rf_a2_trigger) "YES (composite ~ single)" else "NO"))

# ---- 3.3 Alpha inheritance vs STR_1722 parent (must < 0.95) ----
cat("\n[Step 3.3] Alpha inheritance vs STR_1722 (parent — D43 was 1 of 3 factors)\n")

# Parent: WT-D20260528_003/alpha_package.json (already exists, STR_1722)
parent_path <- "qepm/mailbox/worktask/WT-D20260528_003/alpha_package.json"
parent <- fromJSON(parent_path)
parent_alpha <- parent$alpha_vector
parent_alpha_dt <- data.table(Ticker = names(parent_alpha),
                              alpha_parent = unlist(parent_alpha))
cat(sprintf("  parent (STR_1722) top alpha N=%d\n", nrow(parent_alpha_dt)))

# Current hypothesis A: use most recent valid sig_date alpha (single snapshot for inheritance)
last_sd <- max(alpha_dt$sig_date)
ha_alpha_dt <- alpha_dt[sig_date == last_sd, .(Ticker, alpha_A = alpha)]
cat(sprintf("  hypothesis_A snapshot sig_date=%s, N=%d\n",
            as.character(last_sd), nrow(ha_alpha_dt)))

inh_dt <- merge(parent_alpha_dt, ha_alpha_dt, by = "Ticker", all = FALSE)
cat(sprintf("  inheritance intersection N=%d\n", nrow(inh_dt)))
if (nrow(inh_dt) >= 5) {
  cor_inh <- cor(inh_dt$alpha_parent, inh_dt$alpha_A, method = "spearman")
  cat(sprintf("  Spearman corr(parent, hypothesis_A) = %+.3f\n", cor_inh))
} else {
  cor_inh <- NA_real_
  cat("  Too few intersect — corr undefined\n")
}
inh_pass <- !is.na(cor_inh) && cor_inh < 0.95

# Overlap rate (top 20 ↔ top 20)
parent_top20 <- parent_alpha_dt[order(-alpha_parent), Ticker][1:20]
hypothesis_top20 <- ha_alpha_dt[, Ticker]   # already top 20 from multi-sleeve
overlap_count <- length(intersect(parent_top20, hypothesis_top20))
cat(sprintf("  Top 20 overlap: %d / 20 (= %.0f%%)\n", overlap_count, overlap_count * 5))

# ---- 3.4 Sector tilt diagnostics (RF-A4) ----
cat("\n[Step 3.4] Sector tilt diagnostics (raw IC vs post-neut IC retention)\n")

# Already in ic_wf: IC_43_raw, IC_43_neut etc.
retain_43 <- mean(ic_wf$IC_43_neut, na.rm = TRUE) / pmax(abs(mean(ic_wf$IC_43_raw, na.rm = TRUE)), 1e-6)
retain_44 <- mean(ic_wf$IC_44_neut, na.rm = TRUE) / pmax(abs(mean(ic_wf$IC_44_raw, na.rm = TRUE)), 1e-6)
cat(sprintf("  D43 post-neut IC retention = %+.2f (>=0.5 PASS RF-A4)\n", retain_43))
cat(sprintf("  D44 post-neut IC retention = %+.2f\n", retain_44))

# Sector concentration in alpha portfolio (top 20)
sec_conc <- alpha_dt[, .N, by = .(sig_date, Sector_Lv2)]
sec_conc[, share := N / sum(N), by = sig_date]
max_sec_share <- sec_conc[, .(max_share = max(share)), by = sig_date]
cat(sprintf("  Max sector share (across sig_dates): mean=%.2f median=%.2f max=%.2f\n",
            mean(max_sec_share$max_share),
            median(max_sec_share$max_share),
            max(max_sec_share$max_share)))

# ---- 3.5 Turnover estimate ----
cat("\n[Step 3.5] Portfolio turnover estimate (monthly rebalance)\n")
setorder(alpha_dt, sig_date, Ticker)
sd_list <- sort(unique(alpha_dt$sig_date))
turnover_v <- numeric(length(sd_list) - 1)
for (i in 2:length(sd_list)) {
  prev_t <- alpha_dt[sig_date == sd_list[i-1], unique(Ticker)]
  curr_t <- alpha_dt[sig_date == sd_list[i],   unique(Ticker)]
  turnover_v[i-1] <- length(setdiff(curr_t, prev_t)) / 20
}
mean_to <- mean(turnover_v, na.rm = TRUE)
ann_to  <- mean_to * 12 * 2  # one-way → annualized 2-way
cat(sprintf("  Monthly one-way turnover: mean=%.3f median=%.3f\n",
            mean_to, median(turnover_v)))
cat(sprintf("  Annualized 2-way turnover: %.2f (cost @ 15bps = %.0fbps)\n",
            ann_to, ann_to * 15))

# Cost-adjusted alpha
cost_drag_monthly <- (mean_to * 2 * 0.0015)
mean_er_monthly_net <- mean(port_ret$ER, na.rm = TRUE) - cost_drag_monthly
sr_ann_net <- (mean_er_monthly_net / sd(port_ret$ER, na.rm = TRUE)) * sqrt(12)
cat(sprintf("  Cost-adjusted mean ER monthly = %+.4f (gross %+.4f - %.4f cost)\n",
            mean_er_monthly_net,
            mean(port_ret$ER, na.rm = TRUE),
            cost_drag_monthly))
cat(sprintf("  Cost-adjusted SR_ann = %+.2f\n", sr_ann_net))

# ---- Save artifacts ----
step3_summary <- list(
  monotonicity = list(
    D43_neut = round(mono_43, 3),
    D44_neut = round(mono_44, 3),
    D43_decile_spread_monthly = round(spread_43, 4),
    D44_decile_spread_monthly = round(spread_44, 4),
    D43_avg_decile = avg_43,
    D44_avg_decile = avg_44
  ),
  single_vs_multi = list(
    D43_single_top20 = p_ss_43,
    D44_single_top20 = p_ss_44,
    Multi_sleeve_10_10 = p_multi,
    Composite_WF_top20 = p_comp,
    improvement_pct = round(improvement * 100, 1),
    rf_a2_trigger = rf_a2_trigger
  ),
  alpha_inheritance = list(
    parent = "STR_1722 (WT-D20260528_003 prior, 3-factor composite)",
    snapshot_sig_date = as.character(last_sd),
    intersect_n = nrow(inh_dt),
    spearman_corr = round(cor_inh, 3),
    top20_overlap = overlap_count,
    inh_pass = inh_pass
  ),
  sector_diagnostics = list(
    D43_post_neut_retention = round(retain_43, 2),
    D44_post_neut_retention = round(retain_44, 2),
    rf_a4_d43_trigger = retain_43 < 0.5,
    rf_a4_d44_trigger = retain_44 < 0.5,
    max_sector_share = list(
      mean = round(mean(max_sec_share$max_share), 2),
      median = round(median(max_sec_share$max_share), 2),
      max = round(max(max_sec_share$max_share), 2)
    )
  ),
  turnover = list(
    monthly_mean_one_way = round(mean_to, 3),
    annualized_2way = round(ann_to, 2),
    cost_15bps_drag_monthly = round(cost_drag_monthly, 4),
    cost_adjusted_mean_er_monthly = round(mean_er_monthly_net, 4),
    cost_adjusted_sr_ann = round(sr_ann_net, 2)
  )
)
write_json(step3_summary, file.path(OUT_DIR, "step3_summary.json"),
           pretty = TRUE, auto_unbox = TRUE)

cat("\n[Step 3 DONE] elapsed:", round(as.numeric(Sys.time() - t0, units = "secs"), 1), "s\n")
cat("  summary:", file.path(OUT_DIR, "step3_summary.json"), "\n")
