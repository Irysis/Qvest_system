setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
options(stringsAsFactors = FALSE, warn = 1)
set.seed(20260809)
p0 <- readRDS("stage_artifacts/FQ182/p0.rds")
D  <- as.data.frame(p0$D); D$Date <- as.Date(D$Date)

mom_skew <- function(x){ x <- x[is.finite(x)]; n <- length(x); m <- mean(x); s <- sqrt(mean((x-m)^2)); sum(((x-m)/s)^3)/n }
bowley   <- function(x, p=0.25){ x <- x[is.finite(x)]; q <- as.numeric(quantile(x, c(p,0.5,1-p))); ((q[3]-q[2])-(q[2]-q[1]))/(q[3]-q[1]) }

cat("################ PART A: horizon — does the skew edge survive aggregation to the decision unit? ################\n")
cat("[why] the book rebalances MONTHLY. fwd20 (~1 month) is the horizon an allocation decision actually earns over.\n")
d20 <- D[is.finite(D$fwd20), ]
cat("[input] fwd20 rows =", nrow(d20), " range", format(range(d20$Date)), " sd =", sprintf("%.5f", sd(d20$fwd20)), "\n")
maxd20 <- d20$Date[which.max(d20$fwd20)]
rowsA <- list()
for(th in c(-0.20,-0.30)){
  for(vn in c("full","excl_live","excl_2026")){
    keep <- switch(vn, full = rep(TRUE,nrow(d20)),
                       excl_live = d20$Date <= as.Date("2026-06-30"),
                       excl_2026 = format(d20$Date,"%Y") != "2026")
    dv <- d20[keep,]
    on <- dv$dd252 <= th
    if(sum(on) < 30) next
    ro <- dv$fwd20[on]; rf <- dv$fwd20[!on]
    rowsA[[length(rowsA)+1]] <- data.frame(part="A_fwd20", thr=th, variant=vn,
      n_on=sum(on), n_off=sum(!on),
      skew_on=mom_skew(ro), skew_off=mom_skew(rf), skew_diff=mom_skew(ro)-mom_skew(rf),
      bowley_on=bowley(ro), bowley_off=bowley(rf), bowley_diff=bowley(ro)-bowley(rf),
      mean_on=mean(ro), mean_off=mean(rf), sd_on=sd(ro), sd_off=sd(rf),
      sd_ratio=sd(ro)/sd(rf))
  }
}
A <- do.call(rbind, rowsA); A[,6:16] <- round(A[,6:16],4); print(A, row.names=FALSE)

cat("\n################ PART B: is the ON-state distribution better or worse to HOLD at full exposure? ################\n")
cat("[frame] Production Constraints: long-only, Sum(w)=1 absolute. Exposure lever range is [0,1] (cannot lever up).\n")
cat("[frame] So 'expand in crisis' is only expressible as 'be at 1.0 in ON while being BELOW 1.0 in OFF'.\n")
d <- D[is.finite(D$fwd1),]
res <- list()
for(th in c(-0.20,-0.30)){
 for(vn in c("full","excl_live")){
  keep <- if(vn=="full") rep(TRUE,nrow(d)) else d$Date <= as.Date("2026-06-30")
  dv <- d[keep,]
  on <- dv$dd252 <= th
  for(c_off in c(1.0, 0.9, 0.8, 0.7, 0.5)){
    w <- ifelse(on, 1.0, c_off)
    r <- w * dv$fwd1
    nav <- cumprod(1+r)
    yrs <- as.numeric(diff(range(dv$Date)))/365.25
    cagr <- nav[length(nav)]^(1/yrs) - 1
    mdd  <- min(nav/cummax(nav) - 1)
    res[[length(res)+1]] <- data.frame(part="B_exposure_rule", thr=th, variant=vn, w_ON=1.0, w_OFF=c_off,
      cagr=cagr, vol_ann=sd(r)*sqrt(252), sharpe=mean(r)/sd(r)*sqrt(252), mdd=mdd,
      calmar=cagr/abs(mdd), avg_exposure=mean(w))
  }
  # inverse rule (de-risk in crisis = conventional overlay direction)
  for(c_on in c(0.7, 0.5)){
    w <- ifelse(on, c_on, 1.0)
    r <- w * dv$fwd1
    nav <- cumprod(1+r); yrs <- as.numeric(diff(range(dv$Date)))/365.25
    cagr <- nav[length(nav)]^(1/yrs)-1; mdd <- min(nav/cummax(nav)-1)
    res[[length(res)+1]] <- data.frame(part="B_exposure_rule", thr=th, variant=vn, w_ON=c_on, w_OFF=1.0,
      cagr=cagr, vol_ann=sd(r)*sqrt(252), sharpe=mean(r)/sd(r)*sqrt(252), mdd=mdd,
      calmar=cagr/abs(mdd), avg_exposure=mean(w))
  }
 }
}
B <- do.call(rbind, res); B[,6:11] <- round(B[,6:11],4); print(B, row.names=FALSE)

cat("\n[note] NAV built with cumprod on a synthetic exposure-scaled BENCHMARK series for diagnostic ranking only;\n")
cat("[note] metric_type = proxy (NOT build_bt_result / canonical_screen_bt). No capital claim derivable from this table.\n")

write.csv(A, "stage_artifacts/FQ182/synth_horizon_fwd20.csv", row.names=FALSE)
write.csv(B, "stage_artifacts/FQ182/synth_exposure_rule_proxy.csv", row.names=FALSE)
cat("\n[done]\n")
