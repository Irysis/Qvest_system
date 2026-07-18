# r2_captier_strategy.R — captier_translate: reweight momentum-timing theta toward cap-w-translatable families.
# Two tiers:
#  (A) ORACLE ceiling: translatability from full-OOS one-hot port_t (LOOK-AHEAD, ceiling only — not a claim).
#  (B) PIT walk-forward: translatability estimated expanding IS-only (cap-w port_t on OOS-prefix), annual refit.
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressMessages({library(data.table); library(arrow)})
source("04_Research/method_frontier/wt006_exog_forecast/eval_harness.R")

fams <- c("value","quality","momentum","low_vol","size","dividend")
oos  <- get(".oos_dates", envir=globalenv())
FEAT <- get(".FEAT", envir=globalenv())

# momentum-timing theta builder (same recipe as baseline .mom_theta) for a given date-set
build_mom_theta <- function(dates){
  FEAT[is.finite(tr_12m) & date %in% dates,
       {z<-(tr_12m-mean(tr_12m))/(sd(tr_12m)+1e-9); w<-exp(2*z); .(family=family, mom=w/sum(w))}, by=date]
}
mom_all <- build_mom_theta(oos)

# translatability multiplier applier: theta = mom * mult(family), renormalized per date
apply_mult <- function(mom_dt, mult){  # mult = named vector over fams
  m <- copy(mom_dt); m[, mu := mult[family]]; m[, raw := mom*mu]
  m[, theta := raw/sum(raw), by=date]
  m[, .(date, family, theta)]
}

# ---------- (A) ORACLE translatability from full-OOS one-hot ----------
diag <- readRDS("04_Research/method_frontier/wt006_exog_forecast/r2_captier_family_diag.rds")
tr_oracle <- setNames(diag$port_t, diag$family)[fams]

variants <- list()
# softmax tilt on translatability (k = temperature)
for(k in c(0.5,1.0,2.0)){
  mult <- exp(k*tr_oracle); mult <- mult/mean(mult)
  variants[[sprintf("oracle_soft_k%.1f",k)]] <- apply_mult(mom_all, mult)
}
# hard gate: only families with oracle port_t>0 (momentum,value), momentum-weighted within
mult_gate <- ifelse(tr_oracle>0, 1, 0.0001); names(mult_gate)<-fams
variants[["oracle_hardgate_pos"]] <- apply_mult(mom_all, mult_gate)
# top-2 translatable only
top2 <- names(sort(tr_oracle, decreasing=TRUE))[1:2]
mult_t2 <- ifelse(fams %in% top2, 1, 0.0001); names(mult_t2)<-fams
variants[["oracle_top2"]] <- apply_mult(mom_all, mult_t2)

cat("\n===== (A) ORACLE CEILING (look-ahead translatability) =====\n")
res_or <- rbindlist(lapply(names(variants), function(nm){
  m<-eval_theta(variants[[nm]], nm)
  data.table(variant=nm, port_t=m$port_t, ew_uni_t=m$ew_uni_t, oos_ret=m$oos_ret,
             net_sr=m$net_sr, calmar=m$calmar, turnover=m$turnover,
             paired_vs_mom_t=m$paired_vs_mom_t, lag1_port_t=m$lag1_port_t, n=m$n_months)
}))
print(res_or)
cat(sprintf("\n(baseline momentum port_t=%.3f)\n", get(".BASELINE_MOM_PORT_T", envir=globalenv())))

saveRDS(res_or, "04_Research/method_frontier/wt006_exog_forecast/r2_oracle_ceiling.rds")
cat("\n[oracle] done.\n")
