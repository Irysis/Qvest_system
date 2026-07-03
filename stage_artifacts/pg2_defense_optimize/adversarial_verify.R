## Adversarial re-verification of 5-candidate defense recon marginal.
## Independent recompute: paired NW-t (lag3), base-series identity, SE band check.
suppressWarnings(suppressMessages({library(data.table); library(sandwich); library(lmtest)}))
DIR <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/pg2_defense_optimize"

nw_paired_t <- function(d, lag=3){
  # regress diff series on intercept, NW HAC lag-3 t on the mean
  m <- lm(d ~ 1)
  vc <- NeweyWest(m, lag=lag, prewhite=FALSE, adjust=TRUE)
  ct <- coeftest(m, vcov.=vc)
  c(mean=unname(coef(m)[1]), t_nw=unname(ct[1,3]), p_nw=unname(ct[1,4]),
    t_ord=unname(summary(m)$coefficients[1,3]))
}

ann_sr <- function(r) mean(r)/sd(r)*sqrt(12)

cat("=== BASE-SERIES IDENTITY across candidates (must be IDENTICAL) ===\n")
c2 <- fread(file.path(DIR,"c2_swap_RE07_monthly_ic.csv"))
c3 <- fread(file.path(DIR,"c3_swap_D45_monthly_ic.csv"))
c4 <- fread(file.path(DIR,"c4_augment4_monthly.csv"))
c5 <- fread(file.path(DIR,"c5_regime_monthly_paired.csv"))
# unify base col name
b2 <- c2$ret_base; b3 <- c3$ret_cur; b4 <- c4$ret_base; b5 <- c5$ret_base
cat(sprintf("  n: c2=%d c3=%d c4=%d c5=%d\n", nrow(c2),nrow(c3),nrow(c4),nrow(c5)))
cat(sprintf("  max|b2-b3|=%.2e  max|b2-b4|=%.2e  max|b2-b5|=%.2e\n",
            max(abs(b2-b3)), max(abs(b2-b4)), max(abs(b2-b5))))
cat(sprintf("  base SR (ann, IC recon): c2=%.4f c3=%.4f c4=%.4f c5=%.4f\n",
            ann_sr(b2), ann_sr(b3), ann_sr(b4), ann_sr(b5)))

cat("\n=== CANDIDATE SR (ann) independent recompute ===\n")
cat(sprintf("  c2 cand SR=%.4f  c3 cand SR=%.4f  c4 cand SR=%.4f  c5 cand SR=%.4f\n",
            ann_sr(c2$ret_cand), ann_sr(c3$ret_cand), ann_sr(c4$ret_cand), ann_sr(c5$ret_cand)))
cat(sprintf("  d_SR: c2=%+.4f c3=%+.4f c4=%+.4f c5=%+.4f\n",
            ann_sr(c2$ret_cand)-ann_sr(b2), ann_sr(c3$ret_cand)-ann_sr(b3),
            ann_sr(c4$ret_cand)-ann_sr(b4), ann_sr(c5$ret_cand)-ann_sr(b5)))

cat("\n=== PAIRED NW-t (lag3) on monthly (cand - base) ===\n")
for(nm in c("c2","c3","c4","c5")){
  d <- switch(nm,
    c2=c2$ret_cand-c2$ret_base,
    c3=c3$ret_cand-c3$ret_cur,
    c4=c4$ret_cand-c4$ret_base,
    c5=c5$ret_cand-c5$ret_base)
  r <- nw_paired_t(d, lag=3)
  cat(sprintf("  %s: mean_d=%+.6f  t_ord=%+.3f  t_NW3=%+.3f  p_NW3=%.4f  nonzero=%d\n",
              nm, r["mean"], r["t_ord"], r["t_nw"], r["p_nw"], sum(d!=0)))
}

cat("\n=== dSR SE band (Lo 2002 approx, iid): SE(SR_ann) ~ sqrt((1+0.5*SR^2)/n)*sqrt(12) ===\n")
# But we want SE of the DIFFERENCE in SR. Use bootstrap on paired monthly for d_SR distribution.
set.seed(42)
boot_dsr <- function(rc, rb, B=2000){
  n <- length(rc); out <- numeric(B)
  for(i in 1:B){ idx <- sample.int(n, n, replace=TRUE)
    out[i] <- ann_sr(rc[idx]) - ann_sr(rb[idx]) }
  out
}
for(nm in c("c2","c3","c4","c5")){
  dt <- switch(nm, c2=c2, c3=c3, c4=c4, c5=c5)
  rc <- dt$ret_cand
  rb <- if(nm=="c3") dt$ret_cur else dt$ret_base
  bd <- boot_dsr(rc, rb)
  cat(sprintf("  %s: d_SR=%+.4f  boot_SE=%.4f  95%%CI=[%+.4f,%+.4f]  P(dSR>0)=%.3f\n",
              nm, mean(bd), sd(bd), quantile(bd,0.025), quantile(bd,0.975), mean(bd>0)))
}
cat("\n[done]\n")
