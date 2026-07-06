# screen_nsi.R — WT-D20260706_009 Alpha Research
# Canonical screening of Net Share Issuance factor + mega-cap dual-benchmark + large-cap decomposition.
# Real-computation via canonical_screen_bt (contract-grade, NW lag-3). metric_type=canonical_screen.

suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

PAN <- file.path(ROOT, "stage_artifacts/WT-D20260706_009/panel")
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260706_009")

sc    <- as.data.table(read_parquet(file.path(PAN, "nsi_scores_monthly.parquet")))
rets  <- as.data.table(read_parquet(file.path(PAN, "returns_monthly.parquet")))
bm_cw <- as.data.table(read_parquet(file.path(PAN, "benchmark_capw.parquet")))
bm_ew <- as.data.table(read_parquet(file.path(PAN, "benchmark_ew.parquet")))
univ  <- as.data.table(read_parquet(file.path(PAN, "universe_flags.parquet")))

START <- as.Date("2005-01-01")
sc <- sc[Date >= START]; rets <- rets[Date >= START]
bm_cw <- bm_cw[Date >= START]; bm_ew <- bm_ew[Date >= START]; univ <- univ[Date >= START]
liq <- univ[, .(Date, Ticker, adv = adv20)]

# =========================================================================
# rank-IC helper (Spearman of score vs forward return) — DIAGNOSTIC, not authoritative
rank_ic_diag <- function(scoredt, scol) {
  d <- merge(scoredt[is.finite(get(scol)), .(Date, Ticker, s = get(scol))], rets, by = c("Date","Ticker"))
  icm <- d[, .(ic = suppressWarnings(cor(s, Ret_1m, method="spearman"))), by = Date][is.finite(ic)]
  list(rank_ic = mean(icm$ic),
       ic_t = mean(icm$ic)/(sd(icm$ic)/sqrt(nrow(icm))),
       icir = mean(icm$ic)/sd(icm$ic),
       n = nrow(icm), icm = icm)
}

# canonical screen runner (both benchmarks); score column selectable
run_screen <- function(scoredt, scol, months, bench, label, top_n = 25L) {
  s <- scoredt[Date %in% months & is.finite(get(scol)), .(Date, Ticker, score = get(scol))]
  r <- rets[Date %in% months]; b <- bench[Date %in% months]; l <- liq[Date %in% months]
  if (uniqueN(s$Date) < 6) return(data.table(label=label, n_months=uniqueN(s$Date), port_t=NA,ir=NA,net_sr=NA,alpha_ann=NA,turnover=NA))
  res <- canonical_screen_bt(s, r, b, top_n = top_n, cost_bps_oneway = 15,
                             liq_dt = l, liq_min = 2e8, periods_per_year = 12L,
                             run_id = paste0("nsi_", label), strategy_id = paste0("nsi_", label))
  data.table(label = label, n_months = res$n_months,
             port_t = round(res$portfolio_alpha_t_nw_lag3, 3),
             ir = round(res$information_ratio, 3),
             net_sr = round(res$net_sr, 3),
             alpha_ann = round(res$alpha_annualized, 4),
             turnover = round(res$turnover_annual, 3))
}

all_m    <- sort(unique(sc$Date))
pre17_m  <- all_m[all_m <  as.Date("2017-01-01")]
post17_m <- all_m[all_m >= as.Date("2017-01-01")]
valup_m  <- all_m[all_m >= as.Date("2024-01-01")]   # value-up era

cat("=============================================================\n")
cat("SIGNAL A: NSI_shares (split-adjusted -Δlog shares TTM), long retirement\n")
icA <- rank_ic_diag(sc, "nsi_shares")
cat(sprintf("[icA] rank-IC=%.4f  t=%.2f  ICIR=%.3f  n=%d\n", icA$rank_ic, icA$ic_t, icA$icir, icA$n))
icA_raw <- rank_ic_diag(sc, "nsi_shares_raw")
cat(sprintf("[icA-raw (no split-adj)] rank-IC=%.4f  t=%.2f  ICIR=%.3f  n=%d\n", icA_raw$rank_ic, icA_raw$ic_t, icA_raw$icir, icA_raw$n))

cat("\nSIGNAL B: NSI_cei (composite equity issuance, split-proof), long retirement\n")
icB <- rank_ic_diag(sc, "nsi_cei")
cat(sprintf("[icB] rank-IC=%.4f  t=%.2f  ICIR=%.3f  n=%d\n", icB$rank_ic, icB$ic_t, icB$icir, icB$n))

# ---- CANONICAL SCREEN: both signals, both benchmarks, sub-periods ----
runset <- function(scol, tag) {
  cat(sprintf("\n=== CANONICAL SCREEN [%s] — cap-w KOSPI200 benchmark ===\n", tag))
  cw <- rbindlist(list(
    run_screen(sc, scol, all_m,    bm_cw, "FULL_capw"),
    run_screen(sc, scol, pre17_m,  bm_cw, "PRE2017_capw"),
    run_screen(sc, scol, post17_m, bm_cw, "POST2017_capw"),
    run_screen(sc, scol, valup_m,  bm_cw, "VALUEUP2024_capw")
  ), fill=TRUE); print(cw)
  cat(sprintf("\n=== CANONICAL SCREEN [%s] — EW-universe benchmark (mega-cap diagnostic) ===\n", tag))
  ew <- rbindlist(list(
    run_screen(sc, scol, all_m,    bm_ew, "FULL_ew"),
    run_screen(sc, scol, pre17_m,  bm_ew, "PRE2017_ew"),
    run_screen(sc, scol, post17_m, bm_ew, "POST2017_ew"),
    run_screen(sc, scol, valup_m,  bm_ew, "VALUEUP2024_ew")
  ), fill=TRUE); print(ew)
  list(cw=cw, ew=ew)
}
resA <- runset("nsi_shares", "NSI_shares")
resB <- runset("nsi_cei", "NSI_cei")

# ---- DECILE realized-alpha profile (monotonicity) for signal A ----
cat("\n=== DECILE realized forward-return profile [NSI_shares] (D10=most retirement) ===\n")
dd <- merge(sc[is.finite(nsi_shares), .(Date, Ticker, s=nsi_shares)], rets, by=c("Date","Ticker"))
dd[, dec := cut(frank(s)/.N, breaks=seq(0,1,0.1), labels=1:10, include.lowest=TRUE), by=Date]
decprof <- dd[, .(mean_fwd = mean(Ret_1m, na.rm=TRUE), n=.N), by=dec][order(dec)]
print(decprof)
# EW benchmark mean for reference
bm_ref <- mean(bm_ew$BM_Ret, na.rm=TRUE)
cat(sprintf("[decile] EW-uni mean fwd ret = %.4f\n", bm_ref))
mono <- suppressWarnings(cor(as.numeric(decprof$dec), decprof$mean_fwd, method="spearman"))
cat(sprintf("[decile] monotonicity (Spearman dec vs mean_fwd) = %.3f\n", mono))

# ---- LARGE-CAP CONDITIONAL decomposition ----
# Split universe each month into LARGE (size top 40%) vs SMALL (bottom 60%), run screen within each.
cat("\n=== LARGE-CAP-CONDITIONAL decomposition [NSI_shares] ===\n")
sc[, size_grp := fifelse(size_pctile >= 0.60, "LARGE", "SMALL")]
run_within <- function(grp, bench, blabel, months=all_m) {
  s <- sc[Date %in% months & is.finite(nsi_shares) & size_grp==grp, .(Date, Ticker, score=nsi_shares)]
  r <- rets[Date %in% months]; b <- bench[Date %in% months]; l <- liq[Date %in% months]
  res <- canonical_screen_bt(s, r, b, top_n=25L, cost_bps_oneway=15, liq_dt=l, liq_min=2e8,
                             periods_per_year=12L, run_id=paste0("nsi_",grp), strategy_id=paste0("nsi_",grp))
  data.table(group=grp, bench=blabel, n_months=res$n_months,
             port_t=round(res$portfolio_alpha_t_nw_lag3,3), ir=round(res$information_ratio,3),
             net_sr=round(res$net_sr,3), alpha_ann=round(res$alpha_annualized,4))
}
lc <- rbindlist(list(
  run_within("LARGE", bm_cw, "capw"), run_within("LARGE", bm_ew, "ew"),
  run_within("SMALL", bm_cw, "capw"), run_within("SMALL", bm_ew, "ew")
), fill=TRUE); print(lc)

# size x issuance interaction: rank-IC within large vs small
icL <- rank_ic_diag(sc[size_grp=="LARGE"], "nsi_shares")
icS <- rank_ic_diag(sc[size_grp=="SMALL"], "nsi_shares")
cat(sprintf("[size-cond IC] LARGE rank-IC=%.4f t=%.2f  |  SMALL rank-IC=%.4f t=%.2f\n",
            icL$rank_ic, icL$ic_t, icS$rank_ic, icS$ic_t))

# ---- mega-cap composition of top-25 (are picks mega-cap?) ----
setorder(sc, Date, -nsi_shares)
top25 <- sc[is.finite(nsi_shares), .SD[seq_len(min(25L,.N))], by=Date]
cat(sprintf("\n[megacap] top-25 median size-rank=%.0f (1=largest); median size-pctile=%.1f%% (100=largest); frac top-40 by size=%.3f\n",
    median(top25$size_rank), 100*median(top25$size_pctile), mean(top25$size_pctile>=0.60)))

saveRDS(list(icA=icA[c("rank_ic","ic_t","icir","n")], icA_raw=icA_raw[c("rank_ic","ic_t","icir","n")],
             icB=icB[c("rank_ic","ic_t","icir","n")],
             resA=resA, resB=resB, decprof=decprof, mono=mono, lc=lc,
             icL=icL[c("rank_ic","ic_t")], icS=icS[c("rank_ic","ic_t")],
             top25_med_size_rank=median(top25$size_rank),
             top25_med_size_pctile=100*median(top25$size_pctile),
             icm_A_shares=icA$icm),
        file.path(OUT, "screen_results.rds"))
cat("\n[screen] DONE — saved screen_results.rds\n")
