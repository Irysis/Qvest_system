#==============================================================================
# 47_3m_5pct_deep_validation.R — Cycle 17 3m/-5%% deep validation
#
# Parts:
#   1. Extended grid (windows 1.5/2/3/6 × thresholds -3/-5/-7/-10)
#      → 검증: 3m/-5%%가 grid edge가 아닌 robust local optimum 확인
#   2. 3-window test for 3m/-5%% best (267m / 255m / 110m)
#   3. Walk-forward 36m rolling
#   4. LOO year sensitivity
#   5. Per-episode breakdown
#   6. Bootstrap CI (B=2000)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(xts);
  library(PerformanceAnalytics); library(ggplot2); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
PROD_DIR <- file.path(PROJECT_ROOT, "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")
CHART_DIR <- file.path(WS, "outputs/06_reports/charts")

# ── (1) Load data ──
bt <- readRDS(file.path(PROD_DIR, "04_backtest_results/bt_result_layer5_R05.rds"))
nav <- as.data.table(bt$nav)
nav[, anchor_date := as.Date(anchor_date)]
baseline <- nav[, .(anchor_date, realized_ym, nav_L5_V5)]
setorder(baseline, anchor_date)
baseline[, ret_L5_V5 := c(nav_L5_V5[1] - 1, diff(nav_L5_V5) / head(nav_L5_V5, -1))]

bm <- as.data.table(read_parquet(
  file.path(WS, "outputs/02_targets/targets_full.parquet")))
bm[, Date := as.Date(Date)]; bm[, ym := format(Date, "%Y-%m")]
setorder(bm, Date)
eom <- bm[, .(close_eom = BM_Close[which.max(Date)]), by = ym]
setorder(eom, ym)
eom[, ret_kospi := shift(close_eom, n = 1L, type = "lead") / close_eom - 1]
eom[, realized_ym := shift(ym, n = 1L, type = "lead")]

panel_base <- merge(baseline, eom[, .(realized_ym, ret_kospi)],
                     by = "realized_ym", all.x = TRUE)
setorder(panel_base, anchor_date)
panel_base[, kospi_log_cum := cumsum(log(1 + replace(ret_kospi, is.na(ret_kospi), 0)))]
panel_base[, kospi_lvl := exp(kospi_log_cum)]

# Helpers
compute_m <- function(ret_vec, dates) {
  ok <- !is.na(ret_vec) & is.finite(ret_vec)
  r <- ret_vec[ok]; d <- dates[ok]
  if (length(r) < 12) return(c(SR = NA, MDD = NA, CAGR = NA))
  xret <- xts::xts(r, order.by = d)
  ann <- table.AnnualizedReturns(xret, scale = 12, Rf = 0)
  c(SR = as.numeric(ann[3, 1]),
    MDD = -as.numeric(maxDrawdown(xret)),
    CAGR = as.numeric(ann[1, 1]))
}
nw_t <- function(x, lag = 4) {
  n <- length(x); xbar <- mean(x); resid <- x - xbar
  if (n < 10) return(NA)
  S <- sum(resid^2) / n
  for (l in seq_len(lag)) {
    w <- 1 - l / (lag + 1)
    S <- S + 2 * w * sum(resid[(l + 1):n] * resid[1:(n - l)]) / n
  }
  xbar / sqrt(S / n)
}

build_hybrid <- function(panel_dt, W_dd, thr, cost = 0.003) {
  pc <- copy(panel_dt)
  # DD computation
  if (W_dd == 1.5) {
    # 1.5m approximated by 2m (close approximation, monthly granularity limited)
    W_use <- 2
  } else {
    W_use <- W_dd
  }
  max_col <- paste0("max_", W_use, "m_v")
  dd_col <- paste0("dd_", W_use, "m_v")
  pc[[max_col]] <- frollapply(pc$kospi_lvl, W_use, max, align = "right")
  pc[[dd_col]] <- pc$kospi_lvl / pc[[max_col]] - 1
  pc[, dd_lag := shift(get(dd_col), 1, fill = 0)]
  pc[, bear_trigger := !is.na(get(dd_col)) & get(dd_col) <= thr]
  pc[, bear_trigger_lag1 := shift(bear_trigger, 1, fill = FALSE)]
  pc[, trig_run := 0L]
  for (i in seq_len(nrow(pc))) {
    if (pc$bear_trigger_lag1[i]) {
      pc[i, trig_run := ifelse(i > 1 && pc$bear_trigger_lag1[i - 1],
                                 pc$trig_run[i - 1] + 1L, 1L)]
    }
  }
  pc[, active := bear_trigger_lag1 & trig_run <= 2]
  pc[, pos_combo := pmax(0.0, 0.7 - 3.0 * pmax(0, -(dd_lag + 0.10)))]
  pc[, ret_active := pos_combo * ret_kospi]
  pc[, state := fifelse(active, "BEAR", "BULL")]
  pc[, state_change := state != shift(state, 1, fill = "BULL")]
  pc[, ret_hyb := fifelse(active, ret_active, ret_L5_V5)]
  pc[state_change == TRUE, ret_hyb := ret_hyb - cost]
  pc
}

# ── (2) Extended grid ──
cat(sprintf("━━━ Extended grid (3m/-5%% local optimum check) ━━━\n"))
ext_dt <- data.table()
m_base_267 <- compute_m(panel_base$ret_L5_V5, panel_base$anchor_date)
for (W_dd in c(2, 3, 6)) for (thr in c(-0.03, -0.05, -0.07, -0.10)) {
  pc <- build_hybrid(panel_base, W_dd, thr)
  mm <- compute_m(pc$ret_hyb, pc$anchor_date)
  diff_ret <- pc$ret_hyb - pc$ret_L5_V5
  ht <- nw_t(diff_ret, 4)
  ext_dt <- rbind(ext_dt, data.table(
    DD_window = W_dd, DD_threshold = thr,
    n_active = sum(pc$active),
    SR = round(mm["SR"], 4), MDD = round(mm["MDD"], 4),
    CAGR = round(mm["CAGR"], 4),
    dSR = round(mm["SR"] - m_base_267["SR"], 4),
    dMDD = round(mm["MDD"] - m_base_267["MDD"], 4),
    harvey_t = round(ht, 3)))
}
ext_dt[, verdict := fcase(
  dSR >= 0.05 & dMDD >= 0 & abs(harvey_t) > 3.0, "ADMIT_STRICT_HARVEY",
  dSR >= 0.05 & dMDD >= 0 & abs(harvey_t) > 2.0, "ADMIT_STRICT",
  dSR >= 0.05 & dMDD >= 0, "ADMIT_WEAK",
  dSR > 0, "MARGINAL",
  default = "REJECT")]
setorder(ext_dt, -dSR)
cat("TOP 8 extended grid:\n")
print(head(ext_dt, 8))

best_ext <- ext_dt[1]
cat(sprintf("\nBest variant: %dm DD ≤ %.0f%%%% / SR %.4f / dSR %+.4f / MDD %+.4f / Harvey-t %+.3f\n",
            best_ext$DD_window, 100 * best_ext$DD_threshold, best_ext$SR, best_ext$dSR,
            best_ext$MDD, best_ext$harvey_t))

# Check: 3m/-5%% in top 5? Or grid edge?
position_3m5pct <- which(ext_dt$DD_window == 3 & ext_dt$DD_threshold == -0.05)
cat(sprintf("\n3m/-5%%%% position in ranked grid: %d / %d\n",
            position_3m5pct, nrow(ext_dt)))

# Local optimum check: 3m/-5%% better than 3m/-3%%, 3m/-7%%, 2m/-5%%, 6m/-5%%?
neighbors <- ext_dt[(DD_window == 3 & DD_threshold == -0.03) |
                     (DD_window == 3 & DD_threshold == -0.07) |
                     (DD_window == 2 & DD_threshold == -0.05) |
                     (DD_window == 6 & DD_threshold == -0.05)]
focal <- ext_dt[DD_window == 3 & DD_threshold == -0.05]
cat(sprintf("\n3m/-5%% local optimum check:\n"))
cat(sprintf("  Focal 3m/-5%%: SR %.3f / dSR %+.3f\n", focal$SR, focal$dSR))
for (i in seq_len(nrow(neighbors))) {
  cat(sprintf("  Neighbor %dm/%.0f%%: SR %.3f / dSR %+.3f (vs focal Δ %+.3f)\n",
              neighbors$DD_window[i], 100 * neighbors$DD_threshold[i],
              neighbors$SR[i], neighbors$dSR[i], focal$SR - neighbors$SR[i]))
}
local_opt <- focal$SR >= max(neighbors$SR)
cat(sprintf("\n  Local optimum: %s\n",
            ifelse(local_opt, "YES (focal SR ≥ all neighbors)", "NO (a neighbor better)")))

# ── (3) 3-window test for 3m/-5%% ──
cat(sprintf("\n━━━ 3-window test for 3m/-5%% ━━━\n"))
pc_best <- build_hybrid(panel_base, 3, -0.05)
res_3win <- list()
for (win_name in c("full267", "adm255", "fx110")) {
  win_p <- switch(win_name,
                   full267 = pc_best[realized_ym >= "2004-02" & realized_ym <= "2026-04"],
                   adm255 = pc_best[realized_ym >= "2005-02" & realized_ym <= "2026-04"],
                   fx110 = pc_best[anchor_date >= as.Date("2017-03-01")])
  m_b <- compute_m(win_p$ret_L5_V5, win_p$anchor_date)
  m_h <- compute_m(win_p$ret_hyb, win_p$anchor_date)
  ht <- nw_t(win_p$ret_hyb - win_p$ret_L5_V5, 4)
  dSR <- m_h["SR"] - m_b["SR"]; dMDD <- m_h["MDD"] - m_b["MDD"]
  verdict <- fcase(
    dSR >= 0.05 & dMDD >= 0 & abs(ht) > 3.0, "ADMIT_STRICT_HARVEY",
    dSR >= 0.05 & dMDD >= 0 & abs(ht) > 2.0, "ADMIT_STRICT",
    dSR >= 0.05 & dMDD >= 0, "ADMIT_WEAK",
    default = "REJECT")
  res_3win[[win_name]] <- list(n = nrow(win_p),
                                base_SR = m_b["SR"], hyb_SR = m_h["SR"],
                                base_MDD = m_b["MDD"], hyb_MDD = m_h["MDD"],
                                base_CAGR = m_b["CAGR"], hyb_CAGR = m_h["CAGR"],
                                dSR = dSR, dMDD = dMDD, ht = ht, verdict = verdict)
  cat(sprintf("  %s (n=%d): SR %.3f→%.3f (Δ%+.3f) MDD %+.3f→%+.3f (Δ%+.3f) t=%+.2f / %s\n",
              win_name, nrow(win_p), m_b["SR"], m_h["SR"], dSR,
              m_b["MDD"], m_h["MDD"], dMDD, ht, verdict))
}

# ── (4) Walk-forward 36m ──
cat(sprintf("\n━━━ Walk-forward 36m rolling (3m/-5%%, 267m) ━━━\n"))
W <- 36
wf <- list()
for (i in seq_len(nrow(pc_best) - W + 1)) {
  win <- pc_best[i:(i + W - 1)]
  if (sum(!is.na(win$ret_hyb)) < 24) next
  m_b <- compute_m(win$ret_L5_V5, win$anchor_date)
  m_h <- compute_m(win$ret_hyb, win$anchor_date)
  wf[[i]] <- data.table(win_end = win$anchor_date[W],
                        dSR = round(m_h["SR"] - m_b["SR"], 4),
                        dMDD = round(m_h["MDD"] - m_b["MDD"], 4),
                        n_trig = sum(win$active))
}
wf_dt <- rbindlist(wf)
win_rate <- mean(wf_dt$dSR > 0)
cat(sprintf("  n=%d windows / win rate %.0f%%%% / median dSR %+.4f / IQR [%+.4f, %+.4f]\n",
            nrow(wf_dt), 100 * win_rate, median(wf_dt$dSR),
            quantile(wf_dt$dSR, 0.25), quantile(wf_dt$dSR, 0.75)))
cat(sprintf("  range [%+.4f, %+.4f]\n", min(wf_dt$dSR), max(wf_dt$dSR)))

# ── (5) LOO ──
cat(sprintf("\n━━━ LOO year sensitivity ━━━\n"))
pc_best[, yr := format(anchor_date, "%Y")]
loo_res <- list()
for (yr_iter in sort(unique(pc_best$yr))) {
  sub <- pc_best[yr != yr_iter]
  if (nrow(sub) < 24) next
  m_b <- compute_m(sub$ret_L5_V5, sub$anchor_date)
  m_h <- compute_m(sub$ret_hyb, sub$anchor_date)
  loo_res[[yr_iter]] <- data.table(year_excluded = yr_iter,
                                    dSR = round(m_h["SR"] - m_b["SR"], 4))
}
loo_dt <- rbindlist(loo_res)
cat(sprintf("  dSR range: [%+.4f, %+.4f] / all positive: %s\n",
            min(loo_dt$dSR), max(loo_dt$dSR),
            ifelse(all(loo_dt$dSR > 0), "YES", "NO")))

# ── (6) Per-episode ──
pc_best[, trig_group := cumsum(state != shift(state, 1, fill = "BULL"))]
ep_dt <- pc_best[active == TRUE,
                  .(period = sprintf("%s~%s",
                                     format(min(anchor_date), "%y%m"),
                                     format(max(anchor_date), "%y%m")),
                    n_months = .N,
                    cum_base = prod(1 + ret_L5_V5) - 1,
                    cum_hyb = prod(1 + ret_hyb) - 1,
                    edge = (prod(1 + ret_hyb) - 1) - (prod(1 + ret_L5_V5) - 1)),
                 by = trig_group]
cat(sprintf("\n━━━ Per-episode (3m/-5%%, %d episodes) ━━━\n", nrow(ep_dt)))
cat(sprintf("  Wins: %d / %d (%.0f%%%%) / avg edge %+.2fpp\n",
            sum(ep_dt$edge > 0), nrow(ep_dt), 100 * mean(ep_dt$edge > 0),
            100 * mean(ep_dt$edge)))
cat(sprintf("  Worst 3 episodes:\n"))
print(head(ep_dt[order(edge), .(period, n_months,
                                 cum_base_pct = round(100 * cum_base, 2),
                                 cum_hyb_pct = round(100 * cum_hyb, 2),
                                 edge_pp = round(100 * edge, 2))], 3))

# ── (7) Bootstrap ──
cat(sprintf("\n━━━ Bootstrap CI (B=2000) ━━━\n"))
set.seed(42)
B <- 2000
boot_dSR <- numeric(B)
for (b in seq_len(B)) {
  idx <- sample(nrow(pc_best), nrow(pc_best), replace = TRUE)
  sub <- pc_best[idx]
  sr_b <- compute_m(sub$ret_L5_V5, sub$anchor_date)["SR"]
  sr_h <- compute_m(sub$ret_hyb, sub$anchor_date)["SR"]
  boot_dSR[b] <- sr_h - sr_b
}
boot_dSR <- boot_dSR[!is.na(boot_dSR)]
boot_lo <- quantile(boot_dSR, 0.025); boot_hi <- quantile(boot_dSR, 0.975)
cat(sprintf("  Mean dSR %+.4f / CI [%+.4f, %+.4f]\n",
            mean(boot_dSR), boot_lo, boot_hi))
cat(sprintf("  CI excludes 0: %s\n",
            ifelse(boot_lo > 0 || boot_hi < 0, "YES (significant)", "NO")))

# ── (8) Verdict ──
all_admit <- (res_3win$full267$verdict %in% c("ADMIT_STRICT", "ADMIT_STRICT_HARVEY") &&
               res_3win$adm255$verdict %in% c("ADMIT_STRICT", "ADMIT_STRICT_HARVEY") &&
               res_3win$fx110$verdict %in% c("ADMIT_STRICT", "ADMIT_STRICT_HARVEY") &&
               win_rate >= 0.6 && all(loo_dt$dSR > 0) && boot_lo > 0)
cat(sprintf("\n━━━ Final verdict ━━━\n"))
cat(sprintf("  All 3 windows ADMIT_STRICT+: %s\n",
            ifelse(all_admit, "✅", "❌")))
cat(sprintf("  Local optimum (not grid edge): %s\n",
            ifelse(local_opt, "✅", "❌")))
cat(sprintf("  Walkforward win rate ≥60%%: %s (%.0f%%%%)\n",
            ifelse(win_rate >= 0.6, "✅", "❌"), 100 * win_rate))
cat(sprintf("  LOO all positive: %s\n", ifelse(all(loo_dt$dSR > 0), "✅", "❌")))
cat(sprintf("  Bootstrap CI excludes 0: %s\n",
            ifelse(boot_lo > 0, "✅", "❌")))
cat(sprintf("  Episodes win ≥70%%: %s (%.0f%%%%)\n",
            ifelse(mean(ep_dt$edge > 0) >= 0.7, "✅", "❌"),
            100 * mean(ep_dt$edge > 0)))

all_pass <- all_admit && local_opt && win_rate >= 0.6 && all(loo_dt$dSR > 0) &&
             boot_lo > 0 && mean(ep_dt$edge > 0) >= 0.7
cat(sprintf("\n[VERDICT] %s\n",
            ifelse(all_pass, "✅ ALL PASS — 3m/-5%% UPGRADE to PRIMARY ADMIT candidate",
                   "⚠️ PARTIAL — retain canonical 6m/-10%% as primary")))

# ── (9) Save ──
out <- list(
  best_grid = list(
    DD_window = best_ext$DD_window,
    DD_threshold = best_ext$DD_threshold,
    SR = best_ext$SR, dSR = best_ext$dSR,
    MDD = best_ext$MDD, dMDD = best_ext$dMDD,
    harvey_t = best_ext$harvey_t, verdict = best_ext$verdict),
  local_optimum_check = list(focal = "3m/-5%%",
                              is_local_opt = local_opt),
  three_windows = res_3win,
  walkforward = list(n = nrow(wf_dt), win_rate = win_rate,
                      median_dSR = median(wf_dt$dSR)),
  loo = list(all_positive = all(loo_dt$dSR > 0),
              dSR_range = c(min(loo_dt$dSR), max(loo_dt$dSR))),
  per_episode = list(n = nrow(ep_dt), win_rate = mean(ep_dt$edge > 0),
                      avg_edge = mean(ep_dt$edge)),
  bootstrap = list(B = B, mean_dSR = mean(boot_dSR),
                    ci_lo = unname(boot_lo), ci_hi = unname(boot_hi)),
  final_verdict = ifelse(all_pass, "PASS_UPGRADE_TO_PRIMARY", "PARTIAL_RETAIN_CANONICAL"),
  timestamp = as.character(Sys.time())
)
write_json(out, file.path(EVAL_DIR, "v1a_v3_3m_5pct_validation.json"),
           auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[JSON] %s/v1a_v3_3m_5pct_validation.json\n", EVAL_DIR))

# Chart
g <- ggplot(wf_dt, aes(x = win_end, y = dSR)) +
  geom_line(color = "#073B4C", linewidth = 0.4) +
  geom_point(aes(color = dSR > 0), size = 1) +
  geom_hline(yintercept = 0, color = "red", linetype = "dashed") +
  scale_color_manual(values = c("TRUE" = "#06D6A0", "FALSE" = "#EF476F"), name = NULL) +
  labs(title = "3m/-5%% V1a+V3 — 36m rolling ΔSR (267m, n=232)",
       subtitle = sprintf("Win rate %.0f%%%% / median %+.3f / verdict: %s",
                          100 * win_rate, median(wf_dt$dSR),
                          ifelse(all_pass, "UPGRADE", "RETAIN_CANONICAL")),
       x = NULL, y = "ΔSR") + theme_minimal(base_size = 11)
ggsave(file.path(CHART_DIR, "26_3m_5pct_validation.png"),
       plot = g, width = 13, height = 5, dpi = 120)
cat(sprintf("[Chart 26] %s/26_3m_5pct_validation.png\n", CHART_DIR))

cat("\n[DONE]\n")
