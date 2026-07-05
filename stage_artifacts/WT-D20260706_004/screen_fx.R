# screen_fx.R — WT-D20260706_004 Alpha Research
# Canonical screening of KRW/USD-beta (export-sensitivity) factor, regime-conditional.
# Real-computation via canonical_screen_bt (contract-grade, NW lag-3). metric_type=canonical_screen.

suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

PAN <- file.path(ROOT, "stage_artifacts/WT-D20260706_004/panel")
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260706_004")

fx      <- as.data.table(read_parquet(file.path(PAN, "fx_scores_monthly.parquet")))
rets    <- as.data.table(read_parquet(file.path(PAN, "returns_monthly.parquet")))
bm_cw   <- as.data.table(read_parquet(file.path(PAN, "benchmark_capw.parquet")))
bm_ew   <- as.data.table(read_parquet(file.path(PAN, "benchmark_ew.parquet")))
univ    <- as.data.table(read_parquet(file.path(PAN, "universe_flags.parquet")))
reg     <- as.data.table(read_parquet(file.path(PAN, "regime_monthly.parquet")))

# restrict to mandate window 2005+
START <- as.Date("2005-01-01")
fx   <- fx[Date >= START]; rets <- rets[Date >= START]
bm_cw<- bm_cw[Date >= START]; bm_ew <- bm_ew[Date >= START]
univ <- univ[Date >= START]; reg <- reg[Date >= START]

# liquidity table for canonical (adv at t)
liq <- univ[, .(Date, Ticker, adv = adv20)]

# ---- signal: higher beta_fx_2f = more export-sensitive (KRW-weakness beneficiary) ----
# use 2-factor FX beta (market-orthogonalized). Winsorize cross-sectionally.
sig <- fx[is.finite(beta_fx_2f), .(Date, Ticker, raw = beta_fx_2f, beta_fx_uni = beta_fx, Size)]
sig[, score := raw]   # long high-FX-beta

# quick cross-sectional rank-IC (Spearman) of score vs forward return (diagnostic, NOT authoritative)
icdt <- merge(sig[, .(Date, Ticker, score)], rets, by = c("Date","Ticker"))
ic_by_m <- icdt[, .(ic = suppressWarnings(cor(score, Ret_1m, method = "spearman"))), by = Date][is.finite(ic)]
ic_by_m <- merge(ic_by_m, reg[, .(Date, regime)], by = "Date", all.x = TRUE)

rank_ic <- mean(ic_by_m$ic)
ic_t <- rank_ic / (sd(ic_by_m$ic) / sqrt(nrow(ic_by_m)))
icir <- rank_ic / sd(ic_by_m$ic)
cat(sprintf("[screen] rank-IC full: mean=%.4f  t=%.2f  ICIR=%.3f  n=%d months\n",
            rank_ic, ic_t, icir, nrow(ic_by_m)))
for (rr in c("WEAK","STRONG")) {
  sub <- ic_by_m[regime == rr]
  if (nrow(sub) > 2) cat(sprintf("[screen]   regime %-6s IC mean=%.4f t=%.2f n=%d\n",
      rr, mean(sub$ic), mean(sub$ic)/(sd(sub$ic)/sqrt(nrow(sub))), nrow(sub)))
}

# ---- helper: run canonical screen on a subset of months, both benchmarks ----
run_screen <- function(scores_dt, months, bench, label, top_n = 25L) {
  s <- scores_dt[Date %in% months, .(Date, Ticker, score)]
  r <- rets[Date %in% months]
  b <- bench[Date %in% months]
  l <- liq[Date %in% months]
  if (uniqueN(s$Date) < 6) return(data.table(label=label, n_months=uniqueN(s$Date), port_t=NA, ir=NA, net_sr=NA, alpha_ann=NA, turnover=NA))
  res <- canonical_screen_bt(s, r, b, top_n = top_n, cost_bps_oneway = 15,
                             liq_dt = l, liq_min = 2e8, periods_per_year = 12L,
                             run_id = paste0("fx_", label), strategy_id = paste0("fx_", label))
  data.table(label = label, n_months = res$n_months,
             port_t = round(res$portfolio_alpha_t_nw_lag3, 3),
             ir = round(res$information_ratio, 3),
             net_sr = round(res$net_sr, 3),
             alpha_ann = round(res$alpha_annualized, 4),
             turnover = round(res$turnover_annual, 3))
}

# regime months (regime@t drives holding over t->t+1; forward return already aligned to t)
weak_m   <- reg[regime == "WEAK", Date]
strong_m <- reg[regime == "STRONG", Date]
all_m    <- sort(unique(sig$Date))
post17_m <- all_m[all_m >= as.Date("2017-01-01")]

cat("\n=== CANONICAL SCREEN — cap-w benchmark (KOSPI200) ===\n")
res_cw <- rbindlist(list(
  run_screen(sig, all_m,    bm_cw, "FULL_capw"),
  run_screen(sig, post17_m, bm_cw, "POST2017_capw"),
  run_screen(sig, weak_m,   bm_cw, "REGIME_WEAK_capw"),
  run_screen(sig, strong_m, bm_cw, "REGIME_STRONG_capw")
), fill = TRUE)
print(res_cw)

cat("\n=== CANONICAL SCREEN — EW benchmark (mega-cap diagnostic) ===\n")
res_ew <- rbindlist(list(
  run_screen(sig, all_m,    bm_ew, "FULL_ew"),
  run_screen(sig, post17_m, bm_ew, "POST2017_ew"),
  run_screen(sig, weak_m,   bm_ew, "REGIME_WEAK_ew"),
  run_screen(sig, strong_m, bm_ew, "REGIME_STRONG_ew")
), fill = TRUE)
print(res_ew)

# ---- INVERSE test: low-FX-beta long (defensive / domestic) — is the sign flipped? ----
cat("\n=== INVERSE (long LOW FX-beta) — cap-w benchmark ===\n")
sig_inv <- copy(sig); sig_inv[, score := -raw]
res_inv <- rbindlist(list(
  run_screen(sig_inv, all_m,    bm_cw, "INV_FULL_capw"),
  run_screen(sig_inv, post17_m, bm_cw, "INV_POST2017_capw"),
  run_screen(sig_inv, weak_m,   bm_cw, "INV_REGIME_WEAK_capw"),
  run_screen(sig_inv, strong_m, bm_cw, "INV_REGIME_STRONG_capw")
), fill = TRUE)
print(res_inv)

# ---- mega-cap recapture diagnostic ----
sig[, size_rank := frank(-Size, ties.method = "first"), by = Date]
sig[, n_names := .N, by = Date]
setorder(sig, Date, -score)
top25 <- sig[, .SD[seq_len(min(25L, .N))], by = Date]
top25[, mega := size_rank <= 10]
mega_frac  <- top25[, .(mega_share = mean(mega)), by = Date]
top25_pctile <- top25[, .(pctl = 1 - (size_rank - 1) / n_names)]
cat(sprintf("\n[megacap] top-25 mega-cap(top10 size) share: mean=%.3f\n", mean(mega_frac$mega_share)))
cat(sprintf("[megacap] top-25 median size-rank: %.0f (1=largest); median size percentile: %.1f%% (100=largest)\n",
            median(top25$size_rank), 100 * median(top25_pctile$pctl, na.rm = TRUE)))

# save results
saveRDS(list(res_cw = res_cw, res_ew = res_ew, res_inv = res_inv, ic_by_m = ic_by_m,
             rank_ic = rank_ic, ic_t = ic_t, icir = icir,
             mega_share = mean(mega_frac$mega_share),
             top25_med_size_rank = median(top25$size_rank),
             top25_med_size_pctile = 100 * median(top25_pctile$pctl, na.rm = TRUE)),
        file.path(OUT, "screen_results.rds"))
cat("\n[screen] DONE — saved screen_results.rds\n")
