# r2_captier_pit.R — PIT walk-forward captier_translate deliverable.
# Translatability estimated expanding IS-only (cap-w one-hot port_t on OOS-prefix < refit boundary),
# annual refit, applied to NEXT year's momentum-timing theta. Burn-in 2013-2014 -> plain momentum.
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressMessages({library(data.table); library(arrow)})
source("04_Research/method_frontier/wt006_exog_forecast/eval_harness.R")

fams <- c("value","quality","momentum","low_vol","size","dividend")
oos  <- get(".oos_dates", envir=globalenv())
FEAT <- get(".FEAT", envir=globalenv())
FAM  <- get(".FAM", envir=globalenv())
score_from_theta <- get(".score_from_theta", envir=globalenv())
canon <- get(".canon", envir=globalenv())

build_mom_theta <- function(dates){
  FEAT[is.finite(tr_12m) & date %in% dates,
       {z<-(tr_12m-mean(tr_12m))/(sd(tr_12m)+1e-9); w<-exp(2*z); .(family=family, mom=w/sum(w))}, by=date]
}
# IS-only one-hot cap-w port_t for family f over oos dates strictly < boundary
is_translat <- function(f, boundary){
  isd <- oos[oos < boundary]; if(length(isd) < 18) return(NA_real_)
  th  <- data.table(date=isd, family=f, theta=1.0)
  r   <- tryCatch(canon(score_from_theta(th))$portfolio_alpha_t_nw_lag3, error=function(e) NA_real_)
  r
}

years <- 2015:2026
k <- 0.5  # gentle softmax (best oracle temperature)
theta_list <- list()
tr_hist <- list()
for(y in years){
  b <- as.Date(sprintf("%d-01-01", y))
  tr <- setNames(sapply(fams, is_translat, boundary=b), fams)
  tr_hist[[as.character(y)]] <- tr
  yr_dates <- oos[format(oos,"%Y")==as.character(y)]
  if(length(yr_dates)==0) next
  mom <- build_mom_theta(yr_dates)
  if(all(is.finite(tr))){
    mult <- exp(k*tr); mult <- mult/mean(mult)
    mom[, mu:=mult[family]]; mom[, raw:=mom*mu]; mom[, theta:=raw/sum(raw), by=date]
    theta_list[[as.character(y)]] <- mom[,.(date,family,theta)]
  } else {
    mom[, theta:=mom]; theta_list[[as.character(y)]] <- mom[,.(date,family,theta)]
  }
}
# burn-in years (2012-2014) -> plain momentum
burn <- oos[as.integer(format(oos,"%Y")) < 2015]
if(length(burn)>0){
  mb <- build_mom_theta(burn); mb[, theta:=mom]; theta_list[["burn"]] <- mb[,.(date,family,theta)]
}
theta_pit <- rbindlist(theta_list, use.names=TRUE)
setorder(theta_pit, date, family)

cat("\n===== IS-estimated translatability by refit year (port_t on expanding OOS-prefix) =====\n")
th_tab <- rbindlist(lapply(names(tr_hist), function(y) data.table(year=y, t(tr_hist[[y]]))), fill=TRUE)
print(th_tab)

write_parquet(theta_pit, "04_Research/method_frontier/wt006_exog_forecast/theta_R2_captier_translate.parquet")
m <- eval_theta(theta_pit, "captier_translate")
cat("\n===== PIT WALK-FORWARD captier_translate =====\n")
print(unlist(m))
cat(sprintf("\nbaseline momentum port_t=%.3f | beats_momentum(paired>1.0)=%s\n",
            get(".BASELINE_MOM_PORT_T", envir=globalenv()), m$paired_vs_mom_t > 1.0))
saveRDS(m, "04_Research/method_frontier/wt006_exog_forecast/r2_captier_pit_result.rds")
cat("\n[pit] done.\n")
