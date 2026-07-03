# ============================================================================
# C21 — STEP 9-12: canonical_screen_bt anchor + variants, orthogonality,
#       incrementality (rho_active vs M_linadd), robustness grid, verdict.
# ============================================================================
suppressMessages({ library(arrow); library(data.table) })
setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260621_003"
I <- readRDS(file.path(OUT, "c21_intermediate.rds"))
score_list <- I$score_list; returns_dt <- I$returns_dt
bench_dt <- I$bench_dt; liq_dt <- I$liq_dt
setnames(returns_dt, "Date", "Date")  # ensure

# assemble long tables per variant-leg
get_leg <- function(legname) rbindlist(lapply(score_list, function(x) if(is.null(x)) NULL else x[[legname]]))
anchor <- get_leg("anchor")   # blend20
eps20  <- get_leg("eps")
esbr20 <- get_leg("esbr")
b60    <- get_leg("b60")
ortho  <- get_leg("ortho")    # Date,Ticker,z_INV08,z_INV10,C19,z_C02,z_C04

# --- helper: run canonical_screen_bt for a given score column from a leg table ---
run_screen <- function(sctab, colname, top_n = 20L) {
  s <- sctab[, .(Date, Ticker, score = get(colname))][!is.na(score) & is.finite(score)]
  res <- canonical_screen_bt(scores_dt = s, returns_dt = returns_dt,
                             bench_dt = bench_dt, top_n = top_n,
                             cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8)
  res
}

cat("=== STEP 9: anchor G/20d/blend, top_n=20 ===\n")
r_G   <- run_screen(anchor, "G", 20L)
r_P   <- run_screen(anchor, "P", 20L)
r_S   <- run_screen(anchor, "S", 20L)
r_lin <- run_screen(anchor, "M_linadd", 20L)
r_rev <- run_screen(anchor, "M_revOnly", 20L)
r_flw <- run_screen(anchor, "M_flowOnly", 20L)

fmt <- function(r, lbl) sprintf("%-14s n=%d PORT_t=%.3f IR=%.3f net_SR=%.3f alpha_ann=%.4f TO=%.2f",
  lbl, r$n_months, r$portfolio_alpha_t_nw_lag3, r$information_ratio, r$net_sr, r$alpha_annualized, r$turnover_annual)
cat(fmt(r_G,"G(anchor)"),"\n"); cat(fmt(r_P,"P(raw)"),"\n"); cat(fmt(r_S,"S(signed)"),"\n")
cat(fmt(r_lin,"M_linadd"),"\n"); cat(fmt(r_rev,"M_revOnly"),"\n"); cat(fmt(r_flw,"M_flowOnly"),"\n")

# --- monthly net-active series for corr (active = ret_net - BM) ---
active_series <- function(r) {
  pr <- as.data.table(r$period_returns)
  pr[, active := ret_net - benchmark_ret]
  pr[, .(date, active)]
}
as_G   <- active_series(r_G); setnames(as_G,"active","a_G")
as_lin <- active_series(r_lin); setnames(as_lin,"active","a_lin")
as_P   <- active_series(r_P); setnames(as_P,"active","a_P")
as_S   <- active_series(r_S); setnames(as_S,"active","a_S")

cat("=== STEP 10a: INCREMENTALITY — rho_active(C21_G, M_linadd) + delta-PORT_t ===\n")
m <- merge(as_G, as_lin, by="date")
rho_active_lin <- cor(m$a_G, m$a_lin, use="complete.obs")
delta_PORT_t_lin <- r_G$portfolio_alpha_t_nw_lag3 - r_lin$portfolio_alpha_t_nw_lag3
delta_SR_lin <- r_G$net_sr - r_lin$net_sr
# also score-level Spearman per sig_date (mean over months)
sp_by_month <- anchor[is.finite(G) & is.finite(M_linadd), .(rho = cor(G, M_linadd, method="spearman")), by=Date]
rho_score_lin <- mean(sp_by_month$rho, na.rm=TRUE)
cat(sprintf("rho_active(C21_G, M_linadd) = %.4f\n", rho_active_lin))
cat(sprintf("rho_score_spearman (mean monthly) = %.4f\n", rho_score_lin))
cat(sprintf("delta-PORT_t (G - linadd) = %.4f\n", delta_PORT_t_lin))
cat(sprintf("delta-net_SR (G - linadd) = %.4f\n", delta_SR_lin))
incr_verdict <- if (rho_active_lin >= 0.85 || delta_PORT_t_lin <= 0) "INTERACTION_NOT_ADDITIVE" else "INTERACTION_ADDS"
cat("INCREMENTALITY VERDICT:", incr_verdict, "\n")

cat("=== STEP 10b: ORTHOGONALITY vs INV08 / C19 / INV10 + marginals C02/C04 ===\n")
# score-level Spearman: anchor G score vs ortho factor scores (per month mean)
o <- merge(anchor[, .(Date, Ticker, G)], ortho, by=c("Date","Ticker"))
score_rho <- function(col) {
  bym <- o[is.finite(G) & is.finite(get(col)), .(rho=cor(G, get(col), method="spearman")), by=Date]
  mean(bym$rho, na.rm=TRUE)
}
rho_INV08 <- score_rho("z_INV08")
rho_INV10 <- score_rho("z_INV10")
rho_C19   <- score_rho("C19")
rho_C02   <- score_rho("z_C02")
rho_C04   <- score_rho("z_C04")
cat(sprintf("rho_score(C21_G, INV08) = %.4f  [target |rho|<0.5]\n", rho_INV08))
cat(sprintf("rho_score(C21_G, C19)   = %.4f  [target |rho|<0.5]\n", rho_C19))
cat(sprintf("rho_score(C21_G, INV10) = %.4f  [target |rho|<0.6]\n", rho_INV10))
cat(sprintf("rho_score(C21_G, C02)   = %.4f  [marginal]\n", rho_C02))
cat(sprintf("rho_score(C21_G, C04)   = %.4f  [marginal]\n", rho_C04))

# active-return-series corr vs INV08/C19/INV10 (run screens for each)
r_INV08 <- run_screen(ortho, "z_INV08", 20L)
r_INV10 <- run_screen(ortho, "z_INV10", 20L)
r_C19   <- run_screen(ortho, "C19", 20L)
as_I8 <- active_series(r_INV08); setnames(as_I8,"active","a_I8")
as_I10<- active_series(r_INV10); setnames(as_I10,"active","a_I10")
as_C19<- active_series(r_C19); setnames(as_C19,"active","a_C19")
ar_corr <- function(asx, col) { mm<-merge(as_G, asx, by="date"); cor(mm$a_G, mm[[col]], use="complete.obs") }
arho_INV08 <- ar_corr(as_I8,"a_I8")
arho_INV10 <- ar_corr(as_I10,"a_I10")
arho_C19   <- ar_corr(as_C19,"a_C19")
cat(sprintf("rho_active(C21_G, INV08) = %.4f\n", arho_INV08))
cat(sprintf("rho_active(C21_G, INV10) = %.4f\n", arho_INV10))
cat(sprintf("rho_active(C21_G, C19)   = %.4f\n", arho_C19))
cat(sprintf("INV08 PORT_t=%.3f  INV10 PORT_t=%.3f  C19 PORT_t=%.3f\n",
  r_INV08$portfolio_alpha_t_nw_lag3, r_INV10$portfolio_alpha_t_nw_lag3, r_C19$portfolio_alpha_t_nw_lag3))

cat("=== STEP 11: robustness grid (variant x window x rev_leg x top_n) ===\n")
grid <- list()
add_cell <- function(tab, col, leg, tn) {
  r <- run_screen(tab, col, tn)
  grid[[length(grid)+1]] <<- data.table(variant=col, leg=leg, top_n=tn,
    n=r$n_months, PORT_t=r$portfolio_alpha_t_nw_lag3, IR=r$information_ratio,
    net_SR=r$net_sr, TO=r$turnover_annual, alpha_ann=r$alpha_annualized)
}
for (tn in c(15L,20L,25L)) for (v in c("P","G","S")) add_cell(anchor, v, "blend20", tn)
for (v in c("P","G","S")) { add_cell(eps20, v, "eps20", 20L); add_cell(esbr20, v, "esbr20", 20L); add_cell(b60, v, "blend60", 20L) }
GRID <- rbindlist(grid)
setorder(GRID, -PORT_t)
print(GRID)
fwrite(GRID, file.path(OUT, "c21_robustness_grid.csv"))

cat("=== STEP 11b: OOS retention (anchor G, anchored 3-split median, v2) ===\n")
# essence_score oos_stat_version=v2: anchored expanding splits {55/65/75} median of (OOS_SR/IS_SR)
oos_retention_v2 <- function(active_dt) {
  a <- active_dt[order(date)]; n <- nrow(a)
  sr <- function(x) if(length(x)<6 || sd(x)==0) NA_real_ else mean(x)/sd(x)*sqrt(12)
  rets <- numeric(0)
  for (q in c(0.55,0.65,0.75)) {
    cut <- floor(n*q); is_sr <- sr(a$active[1:cut]); oos_sr <- sr(a$active[(cut+1):n])
    if (!is.na(is_sr) && is_sr>0) rets <- c(rets, oos_sr/is_sr)
  }
  median(rets, na.rm=TRUE)
}
oos_G <- oos_retention_v2(as_G[, .(date, active=a_G)])
cat(sprintf("oos_retention_v2(C21_G) = %.4f  [graduation HARD>=0.7]\n", oos_G))

# calmar from active series (annualized active / maxDD of cum active) — approximate screening
calmar_approx <- function(active) {
  cum <- cumprod(1+active); peak <- cummax(cum); dd <- (cum-peak)/peak
  ann <- mean(active)*12; mdd <- abs(min(dd))
  if (mdd<1e-6) NA_real_ else ann/mdd
}
calmar_G <- calmar_approx(as_G$a_G)
cat(sprintf("calmar_approx(C21_G active) = %.3f  [graduation HARD>=0.64; net-active basis]\n", calmar_G))

cat("=== SAVE results json ===\n")
results <- list(
  anchor = list(variant="G", flow_window="20d", revision_leg="blend", top_n=20,
    metric_type="canonical_screen",
    PORT_t_nw_lag3=r_G$portfolio_alpha_t_nw_lag3, PORT_t_pvalue=r_G$portfolio_alpha_t_pvalue,
    information_ratio=r_G$information_ratio, net_sr=r_G$net_sr,
    alpha_annualized=r_G$alpha_annualized, turnover_annual=r_G$turnover_annual,
    n_months=r_G$n_months, oos_retention_v2=oos_G, calmar_approx=calmar_G),
  variants = list(
    P=list(PORT_t=r_P$portfolio_alpha_t_nw_lag3, net_sr=r_P$net_sr),
    S=list(PORT_t=r_S$portfolio_alpha_t_nw_lag3, net_sr=r_S$net_sr)),
  marginals = list(
    M_revOnly=list(PORT_t=r_rev$portfolio_alpha_t_nw_lag3, net_sr=r_rev$net_sr),
    M_flowOnly=list(PORT_t=r_flw$portfolio_alpha_t_nw_lag3, net_sr=r_flw$net_sr),
    M_linadd=list(PORT_t=r_lin$portfolio_alpha_t_nw_lag3, net_sr=r_lin$net_sr)),
  incrementality = list(rho_active_vs_linadd=rho_active_lin, rho_score_spearman=rho_score_lin,
    delta_PORT_t=delta_PORT_t_lin, delta_net_SR=delta_SR_lin, verdict=incr_verdict),
  orthogonality = list(
    score_rho = list(INV08=rho_INV08, C19=rho_C19, INV10=rho_INV10, C02=rho_C02, C04=rho_C04),
    active_rho = list(INV08=arho_INV08, C19=arho_C19, INV10=arho_INV10),
    target_PORT_t = list(INV08=r_INV08$portfolio_alpha_t_nw_lag3,
                         INV10=r_INV10$portfolio_alpha_t_nw_lag3, C19=r_C19$portfolio_alpha_t_nw_lag3))
)
jsonlite::write_json(results, file.path(OUT, "c21_eval_results.json"),
                     auto_unbox=TRUE, pretty=TRUE, digits=6)
saveRDS(list(as_G=as_G, GRID=GRID, results=results), file.path(OUT,"c21_eval_obj.rds"))
cat("EVAL-DONE\n")
