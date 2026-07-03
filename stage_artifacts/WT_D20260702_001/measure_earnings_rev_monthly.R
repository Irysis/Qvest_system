# measure_earnings_rev_monthly.R  (WT-D20260702_001)
# Alpha-research Step 4/5: earnings-revision composite, MONTHLY (1M) rebalance basis.
# Purpose: verify whether the seed candidate survives on system-authoritative monthly
#          canonical basis (seed canonical_recent_port_t=0.70 on monthly; proxy 2.58 was
#          H=3 quarterly-marking = artifact). All perf via canonical_screen_bt (contract).
# NO self-synthesis: PORT_t/IR/alpha via build_benchmark_compare (NW lag-3). ASCII only.

suppressMessages({ library(arrow); library(data.table); library(jsonlite) })

root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source(file.path(root, "02_Infrastructure", "contracts", "backtest_result_contract.R"))
source(file.path(root, "02_Infrastructure", "contracts", "canonical_screen_bt.R"))

out_dir <- file.path(root, "stage_artifacts", "WT_D20260702_001")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

SEED <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C05_ESCR","C06_TP_Gap","C19_Composite_Earnings")
TOP_N <- 25L
COST  <- 15
RECENT_LO <- "2021-01"   # seed 'recent' definition

## ---- 1. Panel (monthly, pre-C13 raw factor values + fwd_ret_1m) ----
panel <- as.data.table(read_parquet(
  file.path(root, ".cache/discovery/phase0_panel_2005-01_2026-04.parquet"),
  col_select = c("ym","Ticker","fwd_ret_1m", SEED)))
panel[, Date := as.Date(paste0(ym, "-01"))]

## ---- 2. Benchmark: daily -> monthly forward 1M return (compound within next month) ----
bm <- as.data.table(read_parquet(file.path(root, ".cache/benchmark.parquet")))
bm[, Date := as.Date(Date)]
bm <- bm[!is.na(BM_Ret)]
bm[, ym := format(Date, "%Y-%m")]
# monthly BM return = compound of daily within the month
bm_m <- bm[, .(bm_ret_m = prod(1 + BM_Ret) - 1), by = ym]   # note: this is realized MONTHLY bm return
setorder(bm_m, ym)
# forward 1M BM: return of NEXT month (aligns with fwd_ret_1m stock forward return)
bm_m[, bm_fwd_1m := shift(bm_ret_m, -1L)]
bm_m[, Date := as.Date(paste0(ym, "-01"))]

## ---- 3. Composite score (all 6 higher_better -> simple standardized sum) ----
# cross-sectional z per month per factor, then sum (equal weight, direction=+1 all).
score_dt <- copy(panel)
for (f in SEED) {
  score_dt[, (f) := {
    v <- get(f)
    mu <- mean(v, na.rm = TRUE); s <- sd(v, na.rm = TRUE)
    if (is.na(s) || s < 1e-12) rep(0, length(v)) else (v - mu) / s
  }, by = ym]
}
score_dt[, score := rowMeans(.SD, na.rm = TRUE), .SDcols = SEED]
# require at least 3 of 6 factors present to score a name
nonmiss <- score_dt[, rowSums(!is.na(.SD)), .SDcols = SEED]
score_dt[nonmiss < 3L, score := NA_real_]

## ---- 4. Assemble canonical inputs (Date, Ticker, score/Ret_1m) ----
scores  <- score_dt[!is.na(score), .(Date, Ticker, score)]
returns <- score_dt[!is.na(fwd_ret_1m), .(Date, Ticker, Ret_1m = fwd_ret_1m)]
bench   <- bm_m[!is.na(bm_fwd_1m), .(Date, BM_Ret = bm_fwd_1m)]

# restrict to overlapping dates present in all
common <- Reduce(intersect, list(as.character(scores$Date), as.character(returns$Date), as.character(bench$Date)))
scores  <- scores [as.character(Date) %in% common]
returns <- returns[as.character(Date) %in% common]
bench   <- bench  [as.character(Date) %in% common]

run_seg <- function(lo, hi, sc, rt, bn, label) {
  if (!is.null(lo)) { keep <- format(sc$Date,"%Y-%m") >= lo & format(sc$Date,"%Y-%m") <= hi
                      sc <- sc[keep]; keep2 <- format(rt$Date,"%Y-%m")>=lo & format(rt$Date,"%Y-%m")<=hi; rt<-rt[keep2]
                      keep3 <- format(bn$Date,"%Y-%m")>=lo & format(bn$Date,"%Y-%m")<=hi; bn<-bn[keep3] }
  r <- tryCatch(canonical_screen_bt(sc, rt, bn, top_n = TOP_N, cost_bps_oneway = COST),
                error = function(e) list(error = conditionMessage(e)))
  list(label = label,
       n_months = r$n_months %||% NA,
       port_t   = r$portfolio_alpha_t_nw_lag3 %||% NA,
       p_value  = r$portfolio_alpha_t_pvalue %||% NA,
       IR       = r$information_ratio %||% NA,
       alpha_ann= r$alpha_annualized %||% NA,
       net_sr   = r$net_sr %||% NA,
       turnover = r$turnover_annual %||% NA,
       error    = r$error %||% NULL)
}
`%||%` <- function(a,b) if (is.null(a) || length(a)==0 || (length(a)==1 && is.na(a))) b else a

## ---- 5. Full, recent, subperiods ----
res <- list()
res$full   <- run_seg(NULL, NULL, scores, returns, bench, "full")
res$recent <- run_seg(RECENT_LO, "2026-12", scores, returns, bench, paste0("recent(",RECENT_LO,"+)"))
res$p1     <- run_seg("2010-01","2015-12", scores, returns, bench, "sub 2010-2015")
res$p2     <- run_seg("2016-01","2020-12", scores, returns, bench, "sub 2016-2020")
res$p3     <- run_seg("2021-01","2026-04", scores, returns, bench, "sub 2021-2026")

## ---- 6. Placebo: random score (seed fixed) ----
set.seed(20260702)
sc_plac <- copy(scores); sc_plac[, score := runif(.N)]
res$placebo_full   <- run_seg(NULL, NULL, sc_plac, returns, bench, "placebo(random) full")
res$placebo_recent <- run_seg(RECENT_LO, "2026-12", sc_plac, returns, bench, "placebo recent")

## ---- 7. Single-factor comparison (C19 composite alone, C01 SUE alone) ----
for (single in c("C19_Composite_Earnings","C01_SUE")) {
  sd1 <- score_dt[!is.na(get(single)), .(Date, Ticker, score = get(single))]
  sd1 <- sd1[as.character(Date) %in% common]
  res[[paste0("single_", single, "_full")]]   <- run_seg(NULL, NULL, sd1, returns, bench, paste0(single," full"))
  res[[paste0("single_", single, "_recent")]] <- run_seg(RECENT_LO,"2026-12", sd1, returns, bench, paste0(single," recent"))
}

## ---- 8. rank-IC of composite (for reporting IC vs PORT_t divergence) ----
ic_dt <- merge(scores, returns, by = c("Date","Ticker"))
ic_by_m <- ic_dt[, .(ic = suppressWarnings(cor(score, Ret_1m, method = "spearman"))), by = Date][!is.na(ic)]
rank_ic  <- mean(ic_by_m$ic)
ic_sd    <- sd(ic_by_m$ic)
icir     <- rank_ic / ic_sd
harvey_t <- rank_ic / ic_sd * sqrt(nrow(ic_by_m))   # naive IC t (not NW); reported as rank-IC t
ic_recent <- ic_by_m[format(Date,"%Y-%m") >= RECENT_LO]
rank_ic_recent <- mean(ic_recent$ic)

diag <- list(
  rank_ic_full = round(rank_ic, 4),
  icir_full = round(icir, 3),
  rank_ic_t_full = round(harvey_t, 2),
  rank_ic_recent = round(rank_ic_recent, 4),
  n_ic_months = nrow(ic_by_m),
  metric_type_ic = "rank_ic (spearman, cross-sectional, monthly)"
)

out <- list(
  wt = "WT-D20260702_001",
  basis = "MONTHLY (1M rebalance, top-25 EW long-only, 15bps, contract build_benchmark_compare NW lag-3)",
  metric_type = "canonical_screen",
  seed_reference = list(proxy_recent_port_t = 2.58, canonical_recent_port_t = 0.6958,
                        note = "proxy=H3 quarterly non-overlap (artifact); canonical=monthly; this run=monthly authoritative"),
  n_common_months = length(common),
  results = res,
  diagnostics = diag
)
write_json(out, file.path(out_dir, "alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE, na = "null")

# also persist alpha scores (latest month) as parquet for downstream
latest_date <- max(scores$Date)
sc_latest <- score_dt[Date == latest_date & !is.na(score), .(Date, Ticker, score)]
write_parquet(sc_latest, file.path(out_dir, "alpha_scores.parquet"))

cat("=== EARNINGS-REV MONTHLY (canonical_screen, contract-grade) ===\n")
cat(sprintf("common months: %d  (%s .. %s)\n", length(common), min(common), max(common)))
pr <- function(x) cat(sprintf("  %-26s n=%-4s port_t=%-7s p=%-7s IR=%-7s alpha_ann=%-8s net_sr=%-7s TO=%s\n",
  x$label, x$n_months, round(x$port_t,3), signif(x$p_value,3), round(x$IR,3),
  round(x$alpha_ann,4), round(x$net_sr,3), round(x$turnover,2)))
for (k in names(res)) pr(res[[k]])
cat("\n--- rank-IC diagnostics ---\n")
cat(sprintf("  rank_ic_full=%.4f  icir=%.3f  rank_ic_t=%.2f  n=%d  rank_ic_recent=%.4f\n",
    diag$rank_ic_full, diag$icir_full, diag$rank_ic_t_full, diag$n_ic_months, diag$rank_ic_recent))
cat("\nWROTE:", file.path(out_dir, "alpha_validation.json"), "\n")
cat("WROTE:", file.path(out_dir, "alpha_scores.parquet"), "\n")
