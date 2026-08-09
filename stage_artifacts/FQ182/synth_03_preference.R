setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
options(stringsAsFactors = FALSE, warn = 1)
set.seed(20260809)
p0 <- readRDS("stage_artifacts/FQ182/p0.rds")
D  <- as.data.frame(p0$D); D$Date <- as.Date(D$Date)
d  <- D[is.finite(D$fwd1), ]

has_pa <- requireNamespace("PerformanceAnalytics", quietly = TRUE)
cat("[env] PerformanceAnalytics available:", has_pa, "\n")

cat("\n######## C: how much bigger would the SKEW term have to be to justify raising exposure? ########\n")
cat("[method] CRRA 3rd-order expansion of dE[U]/dw at w=1:  mu - g*sd^2 + g(g+1)/2 * m3\n")
cat("[method] required_multiple = (OFF advantage in the mu+variance terms) / (ON-OFF skew term)\n")
rows <- list()
for(th in c(-0.20,-0.30)){
 for(vn in c("full","excl_live","excl_top1","excl_2026")){
  maxday <- d$Date[which.max(d$fwd1)]
  keep <- switch(vn, full=rep(TRUE,nrow(d)),
                     excl_live = d$Date <= as.Date("2026-06-30"),
                     excl_top1 = d$Date != maxday,
                     excl_2026 = format(d$Date,"%Y") != "2026")
  dv <- d[keep,]; on <- dv$dd252 <= th
  ro <- dv$fwd1[on]; rf <- dv$fwd1[!on]
  for(g in c(2,5,10)){
    f <- function(r){ mu<-mean(r); s<-sd(r); m3<-mean((r-mu)^3)
                      c(mu=mu, varp=-g*s^2, skb=(g*(g+1)/2)*m3) }
    a <- f(ro); b <- f(rf)
    d_mu   <- a["mu"]  - b["mu"]
    d_varp <- a["varp"]- b["varp"]
    d_skb  <- a["skb"] - b["skb"]
    gap    <- d_mu + d_varp            # ON's handicap before skew credit
    req    <- if(d_skb > 0) -gap/d_skb else NA_real_
    rows[[length(rows)+1]] <- data.frame(thr=th, variant=vn, gamma=g,
      d_mean=as.numeric(d_mu), d_varpen=as.numeric(d_varp), d_skewterm=as.numeric(d_skb),
      handicap=as.numeric(gap), skew_credit_pct_of_handicap=as.numeric(100*d_skb/abs(gap)),
      required_skew_multiple=as.numeric(req))
  }
 }
}
C <- do.call(rbind, rows)
C$d_mean <- signif(C$d_mean,3); C$d_varpen <- signif(C$d_varpen,3); C$d_skewterm <- signif(C$d_skewterm,3)
C$handicap <- signif(C$handicap,3); C$skew_credit_pct_of_handicap <- round(C$skew_credit_pct_of_handicap,2)
C$required_skew_multiple <- round(C$required_skew_multiple,1)
print(C, row.names=FALSE)
write.csv(C, "stage_artifacts/FQ182/synth_pref_required_skew.csv", row.names=FALSE)

cat("\n######## D: convexity sign of the proposed rule (does 'add as it falls' buy or SELL convexity?) ########\n")
cat("[method] monthly aggregation, regress rule return on mkt and mkt^2. b2>0 = long gamma (convex), b2<0 = short gamma.\n")
d$ym <- format(d$Date, "%Y-%m")
Dres <- list()
for(th in c(-0.20,-0.30)){
  on <- d$dd252 <= th
  w_add  <- ifelse(on, 1.0, 0.7)   # proposed: expand in crisis
  w_cut  <- ifelse(on, 0.7, 1.0)   # conventional: de-risk in crisis
  agg <- function(w){
    r <- w * d$fwd1
    tapply(r, d$ym, function(z) prod(1+z)-1)
  }
  mkt <- tapply(d$fwd1, d$ym, function(z) prod(1+z)-1)
  for(nm in c("add","cut")){
    rr <- agg(if(nm=="add") w_add else w_cut)
    ok <- is.finite(rr) & is.finite(mkt)
    fit <- lm(rr[ok] ~ mkt[ok] + I(mkt[ok]^2))
    cf <- summary(fit)$coefficients
    Dres[[length(Dres)+1]] <- data.frame(thr=th, rule=nm,
      beta1=cf[2,1], beta2=cf[3,1], t_beta2=cf[3,3], n_months=sum(ok))
  }
}
Dd <- do.call(rbind, Dres); Dd[,3:5] <- round(Dd[,3:5],4); print(Dd, row.names=FALSE)
cat("[read] beta2 < 0 with |t| large  =>  the rule is CONCAVE in the market (short gamma / sells convexity).\n")
write.csv(Dd, "stage_artifacts/FQ182/synth_convexity.csv", row.names=FALSE)

cat("\n######## E: contract-compliant exposure-rule metrics (PerformanceAnalytics standard functions) ########\n")
if(has_pa){
  suppressPackageStartupMessages({library(xts); library(PerformanceAnalytics)})
  Ep <- list()
  for(th in c(-0.20,-0.30)){
   for(vn in c("full","excl_live")){
    keep <- if(vn=="full") rep(TRUE,nrow(d)) else d$Date <= as.Date("2026-06-30")
    dv <- d[keep,]; on <- dv$dd252 <= th
    Rm <- xts(cbind(MKT = dv$fwd1, CASH = 0), order.by = dv$Date)
    for(sc in list(c(1.0,1.0), c(1.0,0.7), c(0.7,1.0), c(0.5,1.0))){
      wv <- ifelse(on, sc[1], sc[2])
      W  <- xts(cbind(MKT = wv, CASH = 1-wv), order.by = dv$Date)
      pr <- Return.portfolio(Rm, weights = W, rebalance_on = NA)
      ta <- table.AnnualizedReturns(pr, scale = 252)
      md <- as.numeric(maxDrawdown(pr))
      Ep[[length(Ep)+1]] <- data.frame(thr=th, variant=vn, w_ON=sc[1], w_OFF=sc[2],
        ann_ret = as.numeric(ta[1,1]), ann_sd = as.numeric(ta[2,1]),
        ann_sharpe = as.numeric(ta[3,1]), maxDD = md,
        calmar = as.numeric(ta[1,1])/md, avg_exposure = mean(wv))
    }
   }
  }
  E <- do.call(rbind, Ep); E[,5:10] <- round(E[,5:10],4); print(E, row.names=FALSE)
  write.csv(E, "stage_artifacts/FQ182/synth_exposure_rule_PA.csv", row.names=FALSE)
  cat("[label] metric_type = proxy  (single-asset exposure overlay on the BENCHMARK series; not a book backtest,\n")
  cat("[label]  not build_bt_result/canonical_screen_bt). Directional ranking only - no capital claim.\n")
} else {
  cat("[skip] PerformanceAnalytics not installed - Part E omitted rather than hand-synthesised.\n")
}
cat("\n[done]\n")
