# run_screen_ortho.R — canonical_screen_bt + grid + orthogonality
suppressMessages({ library(arrow); library(data.table); library(dplyr) })
setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260621_005")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")

P <- readRDS(file.path(OUT, "prepped.rds"))
sig <- P$sig; returns_dt <- P$returns_dt; liq_dt <- P$liq_dt; bench_dt <- P$bench_dt
month_end_dates <- P$month_end_dates

winz <- function(x, p = 0.01) { q <- quantile(x, c(p,1-p), na.rm=TRUE, type=7); pmin(pmax(x,q[1]),q[2]) }
build_scores <- function(D, cov_floor, pers_form = "mult", Lnote=40) {
  S <- copy(D)
  S[, ACC_w := winz(ACC), by = Date]
  S[, z_acc := { m<-mean(ACC_w,na.rm=TRUE); s<-sd(ACC_w,na.rm=TRUE)
      if (is.na(s)||s==0) rep(0,.N) else (ACC_w-m)/s }, by = Date]
  if (pers_form=="mult") S[, score := z_acc*(0.5+0.5*fifelse(is.na(PERS),0,PERS))]
  else if (pers_form=="none") S[, score := z_acc]
  else if (pers_form=="hardgate") S[, score := fifelse(!is.na(PERS)&PERS>=0.5, z_acc, NA_real_)]
  S[is.na(COV)|COV<cov_floor, score := NA_real_]
  S[, .(Date, Ticker, score)]
}

run_cell <- function(cov_floor, pers_form, top_n) {
  S <- build_scores(sig, cov_floor, pers_form)
  res <- tryCatch(
    canonical_screen_bt(scores_dt = S[!is.na(score)], returns_dt = returns_dt,
                        bench_dt = bench_dt, top_n = top_n, cost_bps_oneway = 15,
                        liq_dt = liq_dt, liq_min = 2e8),
    error = function(e) list(note=paste("ERR:",conditionMessage(e))))
  data.table(cov_floor=cov_floor, pers_form=pers_form, top_n=top_n,
             n_months = res$n_months %||% NA,
             port_t = res$portfolio_alpha_t_nw_lag3 %||% NA,
             IR = res$information_ratio %||% NA,
             net_sr = res$net_sr %||% NA,
             alpha_ann = res$alpha_annualized %||% NA,
             turnover = res$turnover_annual %||% NA,
             note = res$note %||% "")
}
`%||%` <- function(a,b) if (is.null(a)||length(a)==0) b else a

cat("=== PRIMARY: cov0.40, mult, top20 ===\n")
prim <- run_cell(0.40, "mult", 20L)
print(prim)
# keep full primary result for period_returns (oos/calmar)
S_prim <- build_scores(sig, 0.40, "mult")
res_prim <- canonical_screen_bt(scores_dt=S_prim[!is.na(score)], returns_dt=returns_dt,
              bench_dt=bench_dt, top_n=20L, cost_bps_oneway=15, liq_dt=liq_dt, liq_min=2e8)
saveRDS(res_prim, file.path(OUT, "res_primary.rds"))

cat("\n=== GRID (cov x pers x top_n) ===\n")
grid <- CJ(cov_floor=c(0.30,0.40,0.51), pers_form=c("mult","none","hardgate"), top_n=c(15L,20L,25L))
gres <- rbindlist(lapply(seq_len(nrow(grid)), function(i)
  run_cell(grid$cov_floor[i], grid$pers_form[i], grid$top_n[i])))
print(gres[order(-port_t)])
fwrite(gres, file.path(OUT, "grid_results.csv"))

cat("\n=== oos_retention + calmar (primary) ===\n")
pr <- as.data.table(res_prim$period_returns)  # date, ret_net, benchmark_ret
setorder(pr, date)
pr[, active := ret_net - benchmark_ret]
n <- nrow(pr)
# anchored 3-split retention v2 (median of 55/65/75 splits): SR_oos/SR_is on ACTIVE
sr_ann <- function(x) if (length(x)<6 || sd(x)==0) NA_real_ else mean(x)/sd(x)*sqrt(12)
ret_split <- function(frac) {
  k <- floor(n*frac); is_sr <- sr_ann(pr$active[1:k]); oos_sr <- sr_ann(pr$active[(k+1):n])
  if (is.na(is_sr)||is.na(oos_sr)||is_sr<=0) NA_real_ else oos_sr/is_sr
}
oos_ret <- median(c(ret_split(0.55), ret_split(0.65), ret_split(0.75)), na.rm=TRUE)
# calmar on NET portfolio nav (compounded via cumprod of net returns — diagnostic only)
nav <- cumprod(1 + pr$ret_net)
peak <- cummax(nav); dd <- nav/peak - 1; mdd <- abs(min(dd))
cagr <- nav[n]^(12/n) - 1
calmar <- if (mdd>0) cagr/mdd else NA_real_
cat("oos_retention(v2 median) =", round(oos_ret,3),
    " calmar =", round(calmar,3), " (CAGR", round(cagr,4), "/ MDD", round(mdd,4), ")\n")
cat("net_SR =", round(res_prim$net_sr,3), " port_t =", round(res_prim$portfolio_alpha_t_nw_lag3,3),
    " IR =", round(res_prim$information_ratio,3), "\n")

cat("\n=== ORTHOGONALITY vs INV01/INV03/INV09/M01/S01 ===\n")
# per sig_date cross-sectional rank-corr between primary SCORE and each factor (Z_Score_Aligned)
targets <- c("INV01_Foreign_NetBuy_20d","INV03_Inst_NetBuy_20d","INV09_Flow_Persistence",
             "M01_Mom_12_1","S01_Size","L26_Log_MktCap")
S_prim_sd <- S_prim[!is.na(score)]
ortho_rows <- list()
for (d in as.character(unique(S_prim_sd$Date))) {
  dd <- as.Date(d)
  sm <- S_prim_sd[Date==dd, .(Ticker, score)]
  if (nrow(sm) < 15) next
  fdt <- tryCatch(load_month_factors(dd, factor_names=targets), error=function(e) NULL)
  if (is.null(fdt) || nrow(fdt)==0) next
  fw <- dcast(fdt, Ticker ~ Factor_Name, value.var="Z_Score_Aligned")
  m <- merge(sm, fw, by="Ticker")
  for (tg in targets) {
    if (tg %in% names(m)) {
      v <- m[[tg]]
      if (sum(!is.na(v)) >= 15) {
        cc <- suppressWarnings(cor(m$score, v, method="spearman", use="complete.obs"))
        ortho_rows[[length(ortho_rows)+1]] <- data.table(Date=dd, factor=tg, corr=cc)
      }
    }
  }
}
ortho <- rbindlist(ortho_rows)
ortho_summary <- ortho[, .(mean_corr=mean(corr,na.rm=TRUE),
                           mean_abs=mean(abs(corr),na.rm=TRUE),
                           p10=quantile(corr,0.1,na.rm=TRUE),
                           p50=median(corr,na.rm=TRUE),
                           p90=quantile(corr,0.9,na.rm=TRUE),
                           n=.N), by=factor]
print(ortho_summary)
fwrite(ortho_summary, file.path(OUT, "ortho_summary.csv"))
saveRDS(list(oos_ret=oos_ret, calmar=calmar, cagr=cagr, mdd=mdd,
             ortho_summary=ortho_summary, grid=gres),
        file.path(OUT, "screen_ortho.rds"))
cat("=== DONE ===\n")
