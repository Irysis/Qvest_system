# run_struct_multisleeve.R — axis: structural_multisleeve
# Q: can a stock-level multi-sleeve (momentum core + orthogonal defense sleeve) OR
#    uncertainty-aware sizing within top-25 escape the momentum single-sleeve wall
#    (AX-007) AND/OR contribute book-marginal (orthogonal to STR_1715 + calmar/tail)?
# Frontier explicitly handed off by wt006 R3: "wall is at stock x cap-tier, not family
#    allocation" (P1/P2 untested = revival condition). This lane tests that stock layer.
suppressMessages({library(data.table);library(arrow);library(PerformanceAnalytics);library(xts)})
setDTthreads(1)
QM <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
source("04_Research/method_frontier/wt006_exog_forecast/eval_harness.R")

OUT <- "04_Research/method_frontier/wt006_exog_forecast"
# ---- universe: K200 u KQ150, on grid dates/oos, liquid handled by canonical ----
UNIV <- .FAM[(K200==1 | KQ150==1)]
UNIV <- UNIV[Date %in% .Rg$Date]
setkey(UNIV, Date)

# cross-sectional residualize x against z (per date); returns residual aligned to UNIV rows
resid_x_on_z <- function(dt, xcol, zcol){
  dt[, .resid := {
    x <- get(xcol); z <- get(zcol)
    ok <- is.finite(x) & is.finite(z)
    r <- rep(NA_real_, .N)
    if(sum(ok) > 5){ fit <- lm(x[ok] ~ z[ok]); r[ok] <- residuals(fit) }
    r
  }, by=Date]
  out <- dt$.resid; dt[, .resid := NULL]; out
}

# build selection score_dt for a multi-sleeve: core by score_core (top N1),
# defense by score_def among remaining (top N2). Returns (Date,Ticker,score) exactly N1+N2 per date.
build_multisleeve <- function(dt, core_col, def_col, N1, N2){
  dt <- copy(dt)
  dt[, .sel := NA_real_]
  sel_list <- dt[, {
    cc <- get(core_col); dd <- get(def_col)
    idx <- seq_len(.N)
    okc <- is.finite(cc)
    # core: top N1 by core score
    ord_c <- idx[okc][order(-cc[okc])]
    core <- head(ord_c, N1)
    rem <- setdiff(idx, core)
    okd <- rem[is.finite(dd[rem])]
    ord_d <- okd[order(-dd[okd])]
    defv <- head(ord_d, N2)
    picks <- c(core, defv)
    sc <- rep(NA_real_, .N)
    # score: core get 2000-rank, defense 1000-rank (both selected; EW so magnitude irrelevant)
    sc[core] <- 2000 - seq_along(core)
    sc[defv] <- 1000 - seq_along(defv)
    .(Ticker=Ticker, score=sc)
  }, by=Date]
  sel_list[!is.na(score), .(Date,Ticker,score)]
}

# soft composite: score = core + kappa * resid_def ; top-25 handled by canonical
build_soft <- function(dt, core_col, resid_vec, kappa){
  d <- copy(dt); d[, .rd := resid_vec]
  d[, score := get(core_col) + kappa * .rd]
  d[is.finite(score), .(Date,Ticker,score)]
}

# ---- precompute residuals ----
UNIV[, lowvol_resid := resid_x_on_z(UNIV, "low_vol", "momentum")]
UNIV[, qual_resid   := resid_x_on_z(UNIV, "quality",  "momentum")]

measure <- function(score_dt, label){
  r <- .canon(score_dt)
  a <- .active_series(r)
  lag1 <- tryCatch({
    # lag1 stress: shift scores one month (use prev-month score for this month's holding)
    s <- as.data.table(score_dt); s[,Date:=as.Date(Date)]
    dts <- sort(unique(s$Date)); lm <- data.table(Date=dts, prev=shift(dts,1))[!is.na(prev)]
    s2 <- merge(lm, s[,.(prev=Date,Ticker,score)], by="prev", allow.cartesian=TRUE)[,.(Date,Ticker,score)]
    .canon(s2)$portfolio_alpha_t_nw_lag3
  }, error=function(e) NA_real_)
  list(label=label, n=r$n_months,
       port_t=round(r$portfolio_alpha_t_nw_lag3,3),
       ew_uni_t=round(r$diag_ew_universe$portfolio_alpha_t_nw_lag3,3),
       oos_ret=round(.oos_ret_of(r$period_returns),3),
       net_sr=round(r$net_sr,3), calmar=round(.calmar_of(r$period_returns),3),
       turnover=round(r$turnover_annual,2),
       lag1_port_t=round(lag1,3),
       active=a)  # keep active series for book-marginal
}

# ---- BOOK active (authoritative STR_1715) ----
bk <- readRDS("qepm/mailbox/worktask/WT-D20260702_002/output/bt_result_C_noL4_CLEAN_ann12.rds")
bkpr <- as.data.table(bk$period_returns)[, .(date=as.Date(date), ret_net)]
bkbm <- as.data.table(bk$benchmark_returns)[, .(date=as.Date(date), bm=benchmark_ret)]
BK <- merge(bkpr, bkbm, by="date"); BK[, active := ret_net - bm]
BK[, ym := format(date, "%Y-%m")]
book_ir <- mean(BK$active)/sd(BK$active)*sqrt(12)
cat(sprintf("[book] IR=%.3f n=%d (expect 1.416)\n", book_ir, nrow(BK)))

# offset-scan align: construction active (indexed by sig_date, forward ret realized next month)
# vs book. Match on ym after shifting construction date by k months; pick k max bench corr.
# construction bench = .BMg BM_Ret at sig_date; realized month = sig_date month (grid_returns Ret_1m is
# labeled at sig_date but is forward). We align by trying k in -3..3.
book_marginal <- function(cons_active){
  ca <- as.data.table(cons_active)[, .(date=as.Date(date), active, ret_net)]
  # attach construction benchmark for corr check
  cb <- .BMg[, .(date=Date, cbm=BM_Ret)]
  ca <- merge(ca, cb, by="date", all.x=TRUE)
  best <- list(k=NA, bcorr=-2, acorr=NA, dIR_max=NA, lam=NA, blend_ir=NA, overlapn=0)
  for(k in -3:3){
    cca <- copy(ca); cca[, mdate := as.Date(cut(date, "month")) ]
    # shift by k months via ym
    cca[, ym := format(seq_dt <- as.Date(paste0(format(date,"%Y-%m"),"-01")) %m+% months(k), "%Y-%m")]
    mg <- merge(cca[,.(ym, cactive=active, cbm)], BK[,.(ym, bactive=active, bbm=bm)], by="ym")
    if(nrow(mg) < 24) next
    bc <- suppressWarnings(cor(mg$cbm, mg$bbm, use="complete.obs"))
    if(is.na(bc)) next
    if(bc > best$bcorr){
      ac <- suppressWarnings(cor(mg$cactive, mg$bactive, use="complete.obs"))
      # lambda sweep blend
      dmax <- -Inf; lbest <- NA; irb <- NA
      for(lam in seq(0,1,0.05)){
        bl <- (1-lam)*mg$bactive + lam*mg$cactive
        ir <- mean(bl)/sd(bl)*sqrt(12)
        base_ir <- mean(mg$bactive)/sd(mg$bactive)*sqrt(12)
        d <- ir - base_ir
        if(d > dmax){ dmax <- d; lbest <- lam; irb <- ir }
      }
      best <- list(k=k, bcorr=round(bc,3), acorr=round(ac,3), dIR_max=round(dmax,3),
                   lam=lbest, blend_ir=round(irb,3), overlapn=nrow(mg),
                   base_ir=round(mean(mg$bactive)/sd(mg$bactive)*sqrt(12),3))
    }
  }
  best
}
require(lubridate)

# ============ RUN VARIANTS ============
variants <- list()
variants[["mom_single"]] <- measure(UNIV[is.finite(momentum), .(Date,Ticker,score=momentum)], "mom_single_top25")
variants[["MS_lv_20_5"]] <- measure(build_multisleeve(UNIV,"momentum","lowvol_resid",20,5), "MS_lowvol_20+5")
variants[["MS_lv_18_7"]] <- measure(build_multisleeve(UNIV,"momentum","lowvol_resid",18,7), "MS_lowvol_18+7")
variants[["MS_lv_15_10"]]<- measure(build_multisleeve(UNIV,"momentum","lowvol_resid",15,10),"MS_lowvol_15+10")
variants[["MS_ql_18_7"]] <- measure(build_multisleeve(UNIV,"momentum","qual_resid",18,7), "MS_qualresid_18+7")
variants[["soft_lv_k05"]]<- measure(build_soft(UNIV,"momentum",UNIV$lowvol_resid,0.5), "soft_lowvol_k0.5")
variants[["soft_lv_k10"]]<- measure(build_soft(UNIV,"momentum",UNIV$lowvol_resid,1.0), "soft_lowvol_k1.0")

# summary table + book-marginal for each
summ <- rbindlist(lapply(names(variants), function(nm){
  v <- variants[[nm]]
  bm <- book_marginal(v$active)
  data.table(variant=nm, label=v$label, n=v$n, port_t=v$port_t, ew_uni_t=v$ew_uni_t,
             oos_ret=v$oos_ret, net_sr=v$net_sr, calmar=v$calmar, turnover=v$turnover,
             lag1_port_t=v$lag1_port_t,
             bk_k=bm$k, bk_bcorr=bm$bcorr, bk_acorr=bm$acorr, bk_dIRmax=bm$dIR_max,
             bk_lam=bm$lam, bk_overlapn=bm$overlapn)
}))
cat("\n===== STRUCTURAL MULTISLEEVE RESULTS (cap-w KOSPI200 top-25 EW, 15bps, liq 2e8) =====\n")
print(summ)
cat(sprintf("\nbaseline factor-momentum(family) port_t=%.3f | momentum-crash gate=2.95 | book IR=%.3f\n",
            .BASELINE_MOM_PORT_T, book_ir))
saveRDS(list(summ=summ, book_ir=book_ir, variants=lapply(variants,function(v){v$active<-NULL;v})),
        file.path(OUT,"struct_multisleeve_results.rds"))
fwrite(summ, file.path(OUT,"struct_multisleeve_results.csv"))
cat("[saved] struct_multisleeve_results.{rds,csv}\n")
