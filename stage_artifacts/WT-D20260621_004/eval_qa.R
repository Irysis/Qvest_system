# ============================================================================
# C22 Quiet Accumulation — STEP 8-14: canonical_screen_bt per cell, orthogonality,
#   does price-residualization help vs raw flow? (QA PORT_t vs C21 flow-only -0.638),
#   graduation gates, verdict.
# ============================================================================
suppressMessages({ library(arrow); library(data.table) })
setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/factor_db/factor_z_standard.R")
OUT <- "stage_artifacts/WT-D20260621_004"
I <- readRDS(file.path(OUT, "qa_intermediate.rds"))
qa_cells <- I$qa_cells; ortho <- I$ortho
returns_dt <- I$returns_dt; bench_dt <- I$bench_dt; liq_dt <- I$liq_dt

run_screen <- function(sctab, top_n = 20L) {
  s <- sctab[, .(Date, Ticker, score)][!is.na(score) & is.finite(score)]
  canonical_screen_bt(scores_dt = s, returns_dt = returns_dt, bench_dt = bench_dt,
                      top_n = top_n, cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8)
}
run_ortho <- function(col, top_n = 20L) {
  s <- ortho[, .(Date, Ticker, score = get(col))][!is.na(score) & is.finite(score)]
  canonical_screen_bt(scores_dt = s, returns_dt = returns_dt, bench_dt = bench_dt,
                      top_n = top_n, cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8)
}
active_series <- function(r) {
  pr <- as.data.table(r$period_returns); pr[, active := ret_net - benchmark_ret]; pr[, .(date, active)]
}
fmt <- function(r, lbl) sprintf("%-8s n=%d PORT_t=%.3f IR=%.3f net_SR=%.3f alpha_ann=%.4f TO=%.2f",
  lbl, r$n_months, r$portfolio_alpha_t_nw_lag3, r$information_ratio, r$net_sr, r$alpha_annualized, r$turnover_annual)

cat("=== STEP 8: 6-cell QA grid (LB x flow), top_n=20 ===\n")
res <- list()
for (tg in names(qa_cells)) { res[[tg]] <- run_screen(qa_cells[[tg]], 20L); cat(fmt(res[[tg]], tg), "\n") }

# anchor = FI42
anchor_tag <- "FI42"
r_anch <- res[[anchor_tag]]

cat("=== STEP 9: RAW FLOW baseline (z_flow only, no price removal) — does residualization help? ===\n")
# reconstruct raw-flow-only screen from intermediate z (re-derive flow_raw rank).
# We saved only QA residual; raw flow = QA + beta*z_pr is not stored. Instead use INV01/INV02
# (Foreign netbuy/Size) + a constructed F+Inst flow proxy.  But the cleanest raw-flow baseline
# is C21's M_flowOnly PORT_t = -0.638 (smart-money F+Inst 20d/Size, top20 long-only) — directly
# comparable (same universe/cost/period). We also run our own INV01/INV02 raw-Foreign-flow.
r_INV01 <- run_ortho("z_INV01", 20L)   # Foreign 21d/Size (raw flow, no price removal)
r_INV02 <- run_ortho("z_INV02", 20L)   # Foreign 63d/Size
cat(fmt(r_INV01, "rawF21"), "\n"); cat(fmt(r_INV02, "rawF63"), "\n")
cat("C21 M_flowOnly (F+Inst 20d/Size raw) PORT_t = -0.638 (external reference)\n")

cat("=== STEP 10: orthogonality (active -BM basis) — M01 / INV01 / INV02 / INV13 / Size ===\n")
r_M01  <- run_ortho("z_M01", 20L)
r_INV13<- run_ortho("z_INV13", 20L)
r_Size <- run_ortho("z_Size", 20L)
as_anch <- active_series(r_anch); setnames(as_anch, "active", "a_anch")
ar_corr <- function(rx) { ax <- active_series(rx); setnames(ax,"active","a_x"); mm <- merge(as_anch, ax, by="date"); cor(mm$a_anch, mm$a_x, use="complete.obs") }
arho_M01  <- ar_corr(r_M01)
arho_INV01<- ar_corr(r_INV01)
arho_INV02<- ar_corr(r_INV02)
arho_INV13<- ar_corr(r_INV13)
arho_Size <- ar_corr(r_Size)

# score-level Spearman per month (anchor QA vs ortho z)
qa_a <- qa_cells[[anchor_tag]]
o2 <- merge(qa_a, ortho, by=c("Date","Ticker"))
score_rho <- function(col) { bym <- o2[is.finite(score) & is.finite(get(col)), .(rho=cor(score, get(col), method="spearman")), by=Date]; mean(bym$rho, na.rm=TRUE) }
srho_M01  <- score_rho("z_M01")
srho_INV01<- score_rho("z_INV01")
srho_INV02<- score_rho("z_INV02")
srho_INV13<- score_rho("z_INV13")
srho_Size <- score_rho("z_Size")
cat(sprintf("M01   active_rho=%.4f score_rho=%.4f  [target |active|<=0.30, anti-corr expected]\n", arho_M01, srho_M01))
cat(sprintf("INV01 active_rho=%.4f score_rho=%.4f  [target |.|<=0.55]\n", arho_INV01, srho_INV01))
cat(sprintf("INV02 active_rho=%.4f score_rho=%.4f  [target |.|<=0.55]\n", arho_INV02, srho_INV02))
cat(sprintf("INV13 active_rho=%.4f score_rho=%.4f  [target |.|<=0.50]\n", arho_INV13, srho_INV13))
cat(sprintf("Size  active_rho=%.4f score_rho=%.4f  [target |.|<=0.40]\n", arho_Size, srho_Size))

cat("=== STEP 11: rank-IC diagnostics for anchor QA ===\n")
ic_by_month <- merge(qa_a, returns_dt, by=c("Date","Ticker"))[is.finite(score) & is.finite(Ret_1m)]
icm <- ic_by_month[, .(ic = cor(score, Ret_1m, method="spearman")), by=Date]
rank_ic <- mean(icm$ic, na.rm=TRUE); icir <- rank_ic / sd(icm$ic, na.rm=TRUE)
# Harvey t (NW lag-3 on IC series)
ic_ser <- icm[order(Date), ic]; nn <- length(ic_ser)
m_ic <- mean(ic_ser); dem <- ic_ser - m_ic; g0 <- mean(dem^2)
nw <- g0; for (L in 1:3) { w <- 1 - L/4; g <- mean(dem[1:(nn-L)]*dem[(L+1):nn]); nw <- nw + 2*w*g }
harvey_t <- m_ic / sqrt(nw/nn)
cat(sprintf("anchor QA: rank_ic=%.4f icir=%.4f harvey_t=%.3f n=%d\n", rank_ic, icir, harvey_t, nn))

cat("=== STEP 12: graduation gates (anchor FI42) — oos_retention v2 + calmar ===\n")
oos_retention_v2 <- function(active) {
  a <- active[order(date)]; n <- nrow(a)
  sr <- function(x) if(length(x)<6 || sd(x)==0) NA_real_ else mean(x)/sd(x)*sqrt(12)
  rets <- numeric(0)
  for (q in c(0.55,0.65,0.75)) { cut <- floor(n*q); is_sr <- sr(a$active[1:cut]); oos_sr <- sr(a$active[(cut+1):n]); if (!is.na(is_sr)&&is_sr>0) rets <- c(rets, oos_sr/is_sr) }
  median(rets, na.rm=TRUE)
}
calmar_approx <- function(active) { cum <- cumprod(1+active); peak <- cummax(cum); dd <- (cum-peak)/peak; ann <- mean(active)*12; mdd <- abs(min(dd)); if (mdd<1e-6) NA_real_ else ann/mdd }
oos_anch <- oos_retention_v2(as_anch[, .(date, active=a_anch)])
calmar_anch <- calmar_approx(as_anch$a_anch)
cat(sprintf("oos_retention_v2=%.4f [HARD>=0.7]  calmar=%.3f [HARD>=0.64]  PORT_t=%.3f [HARD>=2.95]\n",
  oos_anch, calmar_anch, r_anch$portfolio_alpha_t_nw_lag3))

# also best-cell by PORT_t (sweep argmax) for DSR awareness
pt_vec <- sapply(res, function(r) r$portfolio_alpha_t_nw_lag3)
best_tag <- names(which.max(pt_vec))
cat(sprintf("best cell by PORT_t = %s (%.3f); sweep across 6 cells -> selection_type='sweep'\n", best_tag, max(pt_vec)))

cat("=== SAVE eval json ===\n")
results <- list(
  anchor = list(tag=anchor_tag, flow_window="42d", flow="F+Inst", top_n=20, metric_type="canonical_screen",
    PORT_t_nw_lag3=r_anch$portfolio_alpha_t_nw_lag3, PORT_t_pvalue=r_anch$portfolio_alpha_t_pvalue,
    information_ratio=r_anch$information_ratio, net_sr=r_anch$net_sr, alpha_annualized=r_anch$alpha_annualized,
    turnover_annual=r_anch$turnover_annual, n_months=r_anch$n_months,
    rank_ic=rank_ic, icir=icir, harvey_t=harvey_t,
    oos_retention_v2=oos_anch, calmar_approx=calmar_anch),
  grid = lapply(names(res), function(tg) list(tag=tg, PORT_t=res[[tg]]$portfolio_alpha_t_nw_lag3,
    net_sr=res[[tg]]$net_sr, IR=res[[tg]]$information_ratio, TO=res[[tg]]$turnover_annual,
    alpha_ann=res[[tg]]$alpha_annualized, n=res[[tg]]$n_months)),
  raw_flow_baseline = list(
    C21_M_flowOnly_PORT_t = -0.637539,
    rawF21_PORT_t = r_INV01$portfolio_alpha_t_nw_lag3, rawF21_net_sr = r_INV01$net_sr,
    rawF63_PORT_t = r_INV02$portfolio_alpha_t_nw_lag3, rawF63_net_sr = r_INV02$net_sr),
  orthogonality = list(
    active_rho = list(M01=arho_M01, INV01=arho_INV01, INV02=arho_INV02, INV13=arho_INV13, Size=arho_Size),
    score_rho  = list(M01=srho_M01, INV01=srho_INV01, INV02=srho_INV02, INV13=srho_INV13, Size=srho_Size),
    target_PORT_t = list(M01=r_M01$portfolio_alpha_t_nw_lag3, INV13=r_INV13$portfolio_alpha_t_nw_lag3, Size=r_Size$portfolio_alpha_t_nw_lag3)),
  graduation_gates = list(
    port_t_nw = list(value=r_anch$portfolio_alpha_t_nw_lag3, hard=2.95, pass=(r_anch$portfolio_alpha_t_nw_lag3>=2.95)),
    oos_retention_v2 = list(value=oos_anch, hard=0.7, pass=(!is.na(oos_anch)&&oos_anch>=0.7)),
    calmar_approx = list(value=calmar_anch, hard=0.64, pass=(!is.na(calmar_anch)&&calmar_anch>=0.64))),
  sweep = list(best_tag=best_tag, best_PORT_t=max(pt_vec), selection_type="sweep", n_cells=6)
)
jsonlite::write_json(results, file.path(OUT, "qa_eval_results.json"), auto_unbox=TRUE, pretty=TRUE, digits=6)
saveRDS(list(res=res, as_anch=as_anch, results=results), file.path(OUT,"qa_eval_obj.rds"))
cat("EVAL-DONE\n")
