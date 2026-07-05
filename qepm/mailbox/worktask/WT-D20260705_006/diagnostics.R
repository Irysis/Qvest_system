# Conservative-Investment composite — diagnostics (rank-IC, canonical PORT_t, subperiod, oos, orth)
Sys.setenv(LC_ALL = "English_United States.utf8")
suppressWarnings(suppressMessages({ library(data.table); library(arrow); library(sandwich); library(lmtest) }))
data.table::setDTthreads(1L)
PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(PROJ)
source("02_Infrastructure/contracts/canonical_screen_bt.R")
STA <- file.path(PROJ, "stage_artifacts/WT_D20260705_006")
bp  <- readRDS(file.path(STA,"base_panels.rds"))
FAC <- readRDS(file.path(STA,"FAC.rds"))
returns_dt <- bp$returns_dt; bench_dt <- bp$bench_dt; liq_dt <- bp$liq_dt

CORE6 <- c("GR03_Asset_Growth","AC24_NOA_Growth","AC05_NOA","AC09_NNI",
           "IN04_Net_Equity_Issuance","IN06_Investment_to_Assets")
CONS  <- c("GR03_Asset_Growth","Q06_Asset_Growth","AC24_NOA_Growth","AC05_NOA",
           "AC09_NNI","IN04_Net_Equity_Issuance","IN05_Net_Debt_Issuance",
           "IN06_Investment_to_Assets","IN01_CapEx_to_Assets","Q20_Net_Equity_Issuance")

build_composite <- function(FAC, factors, min_axes=2L) {
  sub <- FAC[Factor_Name %in% factors]
  comp <- sub[, .(score=mean(Z), n_axes=.N), by=.(Date, Ticker)]
  comp[n_axes >= min_axes, .(Date, Ticker, score)]
}
comp_core6 <- build_composite(FAC, CORE6)
comp_full  <- build_composite(FAC, CONS)

# ---- rank-IC (Spearman monthly) ----
rank_ic_series <- function(scores_dt, returns_dt) {
  m <- merge(scores_dt, returns_dt, by=c("Date","Ticker"))
  m[, .(ic=suppressWarnings(cor(score, Ret_1m, method="spearman")), n=.N), by=Date][n>=20 & is.finite(ic)]
}
ic_summary <- function(ic, label) {
  x <- ic$ic; mu <- mean(x); s <- sd(x); n <- length(x)
  nw_t <- tryCatch({ fit <- lm(x ~ 1)
    coeftest(fit, vcov.=NeweyWest(fit, lag=3, prewhite=FALSE))[1,3] }, error=function(e) mu/(s/sqrt(n)))
  data.table(composite=label, n_months=n, mean_ic=round(mu,4), icir=round(mu/s,3),
             ic_harvey_t_nw=round(nw_t,3))
}
IC_TBL <- rbindlist(list(
  ic_summary(rank_ic_series(comp_core6,returns_dt),"core6"),
  ic_summary(rank_ic_series(comp_full, returns_dt),"full10")))
cat("\n=== RANK-IC (metric_type=canonical_screen rank-IC) ===\n"); print(IC_TBL)

# ---- canonical PORT_t (AUTHORITATIVE) ----
run_canon <- function(sc, tag, sub=NULL) {
  if (!is.null(sub)) sc <- sc[eval(sub)]
  canonical_screen_bt(sc, returns_dt, bench_dt, top_n=25L, cost_bps_oneway=15,
                      liq_dt=liq_dt, liq_min=2e8, run_id=tag, strategy_id=tag)
}
canon_row <- function(cs, tag) data.table(spec=tag, n_months=cs$n_months,
  PORT_t_NW=round(cs$portfolio_alpha_t_nw_lag3,3), IR=round(cs$information_ratio,3),
  alpha_ann=round(cs$alpha_annualized,4), net_sr=round(cs$net_sr,3),
  mean_active=round(cs$mean_active_net,5), turnover=round(cs$turnover_annual,3))
cs_core <- run_canon(comp_core6,"cons_core6")
cs_full <- run_canon(comp_full, "cons_full10")
# best single component (IS-only choice; report all 6 for transparency, chain selection_type)
single_rows <- rbindlist(lapply(CORE6, function(f){
  sc <- FAC[Factor_Name==f, .(Date, Ticker, score=Z)]
  canon_row(run_canon(sc, f), f)
}))
CANON_TBL <- rbindlist(list(canon_row(cs_core,"cons_core6"), canon_row(cs_full,"cons_full10"), single_rows))
cat("\n=== CANONICAL top-25 PORT-ALPHA t (AUTHORITATIVE, metric_type=canonical_screen) ===\n"); print(CANON_TBL)

# ---- subperiod (core6) ----
sub_run <- function(lo, hi, lbl) {
  sc <- comp_core6[Date>=lo & Date<hi]
  if (uniqueN(sc$Date)<12) return(data.table(period=lbl, n_months=uniqueN(sc$Date), PORT_t_NW=NA_real_))
  cs <- run_canon(sc, lbl)
  data.table(period=lbl, n_months=cs$n_months, PORT_t_NW=round(cs$portfolio_alpha_t_nw_lag3,3),
             IR=round(cs$information_ratio,3), net_sr=round(cs$net_sr,3), mean_active=round(cs$mean_active_net,5))
}
SUB_TBL <- rbindlist(list(sub_run(as.Date("1900-01-01"),as.Date("2017-01-01"),"pre2017"),
                          sub_run(as.Date("2017-01-01"),as.Date("2100-01-01"),"post2017")), fill=TRUE)
cat("\n=== SUBPERIOD (core6) ===\n"); print(SUB_TBL)

# ---- oos_retention (anchored 55/65/75 median, net-active SR OOS/IS) ----
oos_ret <- function(sc) {
  cs <- run_canon(sc, "oos"); pr <- as.data.table(cs$period_returns); setorder(pr, date)
  pr[, active := ret_net - benchmark_ret]; n <- nrow(pr)
  sr <- function(a) if (length(a)<6 || sd(a)==0) NA_real_ else mean(a)/sd(a)*sqrt(12)
  rr <- sapply(c(0.55,0.65,0.75), function(f){ k<-floor(n*f)
    is_sr<-sr(pr$active[1:k]); oos_sr<-sr(pr$active[(k+1):n])
    if (is.na(is_sr)||is.na(oos_sr)||is_sr<=0) NA_real_ else oos_sr/is_sr })
  list(splits=setNames(round(rr,3),c("55","65","75")), median=round(median(rr,na.rm=TRUE),3), n=n)
}
OOS <- oos_ret(comp_core6)
cat("\n=== OOS RETENTION (core6) ===\n")
cat("splits:", paste(names(OOS$splits),OOS$splits,sep="="), "| median:", OOS$median, "\n")

# ---- orthogonality to incumbent momentum (M04) ----
mom_dt <- FAC[Factor_Name=="M04_Mom_1", .(Date, Ticker, mom=Z)]
orth <- merge(comp_core6, mom_dt, by=c("Date","Ticker"))
orth_m <- orth[, .(rho=suppressWarnings(cor(score,mom,method="spearman")), n=.N), by=Date][n>=20 & is.finite(rho)]
orth_pooled <- suppressWarnings(cor(orth$score, orth$mom, method="spearman"))
cat(sprintf("\n=== ORTHOGONALITY to incumbent momentum (M04_Mom_1) ===\n"))
cat(sprintf("pooled rank-rho=%.3f | mean monthly rho=%.3f (n=%d months)\n",
            orth_pooled, mean(orth_m$rho), nrow(orth_m)))
# also vs M01 (12-1 momentum, the classic)
mom1 <- FAC[Factor_Name=="M01_Mom_12_1", .(Date, Ticker, mom=Z)]
orth1 <- merge(comp_core6, mom1, by=c("Date","Ticker"))
orth1_pooled <- suppressWarnings(cor(orth1$score, orth1$mom, method="spearman"))
cat(sprintf("pooled rank-rho vs M01_Mom_12_1=%.3f\n", orth1_pooled))

# ---- save ----
DIAG <- list(ic=IC_TBL, canonical=CANON_TBL, subperiod=SUB_TBL, oos=OOS,
             orth=list(vs_M04_pooled=orth_pooled, vs_M04_mean_monthly=mean(orth_m$rho),
                       vs_M01_pooled=orth1_pooled))
saveRDS(DIAG, file.path(STA,"DIAG.rds"), compress=TRUE)
# alpha_scores.parquet (latest month core6)
last_d <- max(comp_core6$Date)
write_parquet(as_arrow_table(comp_core6[Date==last_d]), file.path(STA,"alpha_scores.parquet"))
cat("\nSAVED DIAG.rds + alpha_scores.parquet\n")
