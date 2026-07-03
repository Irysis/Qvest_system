# ============================================================================
# C22 REVISE (post-Codex): controlled same-WT raw-flow baselines for ALL 6 cells,
#   subperiod ICIR (3-split), DSR, decile monotonicity, alpha_scores.parquet write.
# Addresses Codex concerns C1, C3, C4.
# ============================================================================
suppressMessages({ library(arrow); library(data.table); library(dplyr) })
setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/factor_db/factor_z_standard.R")
OUT <- "stage_artifacts/WT-D20260621_004"

# We need raw z_flow per cell (NOT residualized). Rebuild from the SAME snapshots used in build_qa.
# qa_intermediate stored only QA residual + ortho. The zsnap (z_flow,z_pr per cell per month)
# was NOT persisted. Recompute z_flow baselines directly from cached inputs (same construction).

cat("=== reload raw + inv (narrow) ===\n")
raw <- open_dataset(".cache/rawdata.parquet") %>%
  dplyr::select(Date, Ticker, Close, Vol, Size, Ret, K200, KQ150) %>%
  dplyr::filter(Date >= as.Date("2003-06-01")) %>% dplyr::collect() %>% as.data.table()
setkey(raw, Ticker, Date)
inv <- open_dataset(".cache/investor_stock/investor_wide.parquet") %>%
  dplyr::select(Date, Ticker, Foreign, Institutional) %>%
  dplyr::filter(Date >= as.Date("2003-06-01")) %>% dplyr::collect() %>% as.data.table()
setkey(inv, Ticker, Date)

I <- readRDS(file.path(OUT, "qa_intermediate.rds"))
returns_dt <- I$returns_dt; bench_dt <- I$bench_dt; liq_dt <- I$liq_dt; sig_dates <- I$sig_dates
qa_cells <- I$qa_cells

raw[, dv := Close * Vol]; raw[, adv20 := frollmean(dv,20L,align="right"), by=Ticker]; raw[, adv20_lag1 := shift(adv20,1L,type="lag"), by=Ticker]
for (lb in c(21L,42L,63L)) {
  inv[, paste0("rF",lb)  := frollsum(Foreign, lb, na.rm=TRUE, align="right"), by=Ticker]
  inv[, paste0("rFI",lb) := frollsum(Foreign+Institutional, lb, na.rm=TRUE, align="right"), by=Ticker]
}
roll_asof <- function(dt, valcol, sig_d, uts) {
  sub <- dt[Date < sig_d & Ticker %in% uts]; if (nrow(sub)==0) return(data.table(Ticker=character(0))[, (valcol):=numeric(0)])
  sub <- sub[order(Ticker,Date)]; out <- sub[, .(v=get(valcol)[.N]), by=Ticker]; setnames(out,"v",valcol); out
}
zw <- function(x) z_safe_winsorize(x)
cells <- list(c("FI21","rFI21"),c("FI42","rFI42"),c("FI63","rFI63"),c("F21","rF21"),c("F42","rF42"),c("F63","rF63"))

cat("=== build RAW FLOW scores (no price removal) per cell, same snapshots ===\n")
rawflow <- setNames(vector("list", length(cells)), sapply(cells, `[[`, 1))
for (k in seq_along(sig_dates)) {
  t <- sig_dates[k]
  usnap <- raw[Date==t & !is.na(Close) & ((K200==1)|(KQ150==1)), .(Ticker, Size)]
  usnap <- usnap[!is.na(Size) & Size>0]; if (nrow(usnap)<20) next
  uts <- usnap$Ticker
  for (cl in cells) {
    fv <- roll_asof(inv, cl[2], t, uts)
    d <- merge(usnap, fv, by="Ticker", all.x=TRUE)
    z <- zw(d[[cl[2]]] / d$Size)
    dd <- data.table(Date=t, Ticker=d$Ticker, score=z)[is.finite(score)]
    if (is.null(rawflow[[cl[1]]])) rawflow[[cl[1]]] <- vector("list", length(sig_dates))
    rawflow[[cl[1]]][[k]] <- dd
  }
}
rawflow <- lapply(rawflow, rbindlist)

run_screen <- function(sctab, top_n=20L) {
  s <- sctab[, .(Date,Ticker,score)][!is.na(score)&is.finite(score)]
  canonical_screen_bt(scores_dt=s, returns_dt=returns_dt, bench_dt=bench_dt, top_n=top_n, cost_bps_oneway=15, liq_dt=liq_dt, liq_min=2e8)
}

cat("=== CONTROLLED COMPARISON: QA (price-removed) vs RAW FLOW (same cell, same window) ===\n")
comp <- list()
for (cl in cells) {
  tg <- cl[1]
  r_qa  <- run_screen(qa_cells[[tg]], 20L)
  r_raw <- run_screen(rawflow[[tg]], 20L)
  comp[[tg]] <- list(QA_PORT_t=r_qa$portfolio_alpha_t_nw_lag3, QA_net_sr=r_qa$net_sr,
                     RAW_PORT_t=r_raw$portfolio_alpha_t_nw_lag3, RAW_net_sr=r_raw$net_sr,
                     delta_PORT_t=r_qa$portfolio_alpha_t_nw_lag3 - r_raw$portfolio_alpha_t_nw_lag3)
  cat(sprintf("%-5s : QA PORT_t=%.3f | RAW PORT_t=%.3f | delta(QA-RAW)=%.3f\n",
      tg, comp[[tg]]$QA_PORT_t, comp[[tg]]$RAW_PORT_t, comp[[tg]]$delta_PORT_t))
}

cat("=== subperiod ICIR (3-split) + DSR + monotonicity for anchor FI42 QA ===\n")
qa_a <- qa_cells[["FI42"]]
icm <- merge(qa_a, returns_dt, by=c("Date","Ticker"))[is.finite(score)&is.finite(Ret_1m)][, .(ic=cor(score,Ret_1m,method="spearman")), by=Date][order(Date)]
n <- nrow(icm); sp <- split(icm$ic, cut(seq_len(n), 3, labels=FALSE))
sub_icir <- sapply(sp, function(x) mean(x)/sd(x))
cat("subperiod ICIR (3):", paste(sprintf("%.3f", sub_icir), collapse=" / "), "\n")
sub_stability <- mean(sign(sub_icir)==sign(mean(icm$ic)))   # fraction same sign as overall
cat("subperiod stability (frac same sign):", sub_stability, "\n")

# DSR on anchor net active SR (single strategy but sweep=6 -> n_trials=6)
as_a <- as.data.table(run_screen(qa_a,20L)$period_returns); as_a[, active := ret_net - benchmark_ret]
sr_obs <- mean(as_a$active)/sd(as_a$active)*sqrt(12)
# Bailey-LdP DSR: deflate by n_trials=6, skew/kurt of active
library(moments)
sk <- moments::skewness(as_a$active); ku <- moments::kurtosis(as_a$active); Tn <- nrow(as_a)
sr_m <- sr_obs/sqrt(12)  # monthly SR
# expected max SR under n trials (var of SR across trials approx) — conservative: use SR0 from variance of cell SRs
cell_srs <- sapply(qa_cells, function(c) { r<-run_screen(c,20L); r$net_sr/sqrt(12) })
sr0 <- sd(cell_srs)  # cross-trial SR dispersion (monthly)
emax <- sr0 * ( (1-0.5772)*qnorm(1-1/6) + 0.5772*qnorm(1-1/(6*exp(1))) )
dsr <- pnorm( ((sr_m - emax)*sqrt(Tn-1)) / sqrt(1 - sk*sr_m + ((ku-1)/4)*sr_m^2) )
cat(sprintf("anchor net_SR(ann)=%.3f  DSR(n_trials=6)=%.4f  [HARD>=0.5 sweep]\n", sr_obs, dsr))

# decile monotonicity
dec <- merge(qa_a, returns_dt, by=c("Date","Ticker"))[is.finite(score)&is.finite(Ret_1m)]
dec[, decile := cut(frank(score)/.N, breaks=seq(0,1,0.1), labels=FALSE, include.lowest=TRUE), by=Date]
decret <- dec[, .(mret=mean(Ret_1m)), by=decile][order(decile)]
mono <- cor(decret$decile, decret$mret, method="spearman")
cat("decile mean returns (1=low score .. 10=high):", paste(sprintf("%.4f", decret$mret), collapse=" "), "\n")
cat(sprintf("decile monotonicity (spearman decile vs ret) = %.3f\n", mono))

cat("=== write alpha_scores.parquet (anchor FI42 QA, Date/Ticker/score) ===\n")
scores_out <- qa_cells[["FI42"]][, .(Date, Ticker, score)]
write_parquet(scores_out, file.path(OUT, "alpha_scores.parquet"))
cat("alpha_scores.parquet rows:", nrow(scores_out), "\n")

revise <- list(
  controlled_comparison = comp,
  controlled_verdict = "Same-WT, same-cell, same-window QA vs RAW-FLOW: delta(QA-RAW) sign decides whether price-removal helps.",
  subperiod_icir = as.numeric(sub_icir), subperiod_stability = sub_stability,
  dsr_n6 = dsr, net_sr_ann = sr_obs,
  decile_returns = as.numeric(decret$mret), decile_monotonicity = mono
)
jsonlite::write_json(revise, file.path(OUT, "qa_revise_results.json"), auto_unbox=TRUE, pretty=TRUE, digits=6)
cat("REVISE-DONE\n")
