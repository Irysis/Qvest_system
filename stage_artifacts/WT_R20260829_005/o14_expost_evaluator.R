## EX-POST EVALUATOR ONLY — o7_methods.R 행 
## 141-197
## ---------- 평가 (v2.4 delta, no-drift — alpha 재현 실증 규약) ----------
eval_sched <- function(W, cost_bps = 15) {
  W2 <- merge(W, RET, by = c("Date","Ticker"), all.x = TRUE); W2[is.na(Ret_1m), Ret_1m := 0]
  ds <- sort(unique(W2$Date)); prev <- data.table(Ticker = character(), wp = numeric())
  out <- vector("list", length(ds))
  for (i in seq_along(ds)) {
    d <- ds[i]; cur <- W2[Date == d, .(Ticker, w, Ret_1m)]
    m <- merge(cur[, .(Ticker, w)], prev, by = "Ticker", all = TRUE)
    m[is.na(w), w := 0]; m[is.na(wp), wp := 0]
    to <- sum(abs(m$w - m$wp)); g <- sum(cur$w * cur$Ret_1m)
    out[[i]] <- data.table(Date = d, gross = g, cost = (cost_bps/1e4)*to, net = g - (cost_bps/1e4)*to,
                           to = to, hhi = sum(cur$w^2), wmax = max(cur$w), n = nrow(cur))
    prev <- cur[, .(Ticker, wp = w)]
  }
  rbindlist(out)
}

stats_of <- function(R) {
  r <- merge(R, BM, by = "Date")
  act <- r$net - r$BM_Ret
  cum <- cumprod(1 + r$net); yrs <- nrow(r)/12
  mdd <- min(cum/cummax(cum) - 1)
  cagr <- cum[length(cum)]^(1/yrs) - 1
  list(net_ir       = mean(act)*12 / (sd(act)*sqrt(12)),
       mean_act_ann = mean(act)*12,
       te_ann       = sd(act)*sqrt(12),
       sr_total     = mean(r$net)*12 / (sd(r$net)*sqrt(12)),
       cagr = cagr, mdd = mdd, calmar = cagr/abs(mdd),
       vol_ann = sd(r$net)*sqrt(12),
       to_ann = mean(R$to)*12, to_roundtrip = mean(R$to)*12*2,
       cost_ann = mean(R$cost)*12,
       hhi = mean(R$hhi), wmax = max(R$wmax), n_max = max(R$n),
       act_cvar95 = -mean(sort(act)[1:ceiling(0.05*length(act))]),
       gross_ir = (mean(r$gross - r$BM_Ret)*12)/(sd(r$gross - r$BM_Ret)*sqrt(12)))
}

METH <- list(
  EW       = list(fn = w_ew,      needs_R = FALSE, needs_alb = FALSE),
  IVP      = list(fn = w_ivp,     needs_R = TRUE,  needs_alb = FALSE),
  HRP      = list(fn = w_hrp,     needs_R = TRUE,  needs_alb = FALSE),
  MinCVaR  = list(fn = w_mincvar, needs_R = TRUE,  needs_alb = FALSE),
  ALB_tilt = list(fn = w_alb,     needs_R = FALSE, needs_alb = TRUE)
)

res <- list(); sched <- list()
for (nm in names(METH)) {
  t0 <- Sys.time()
  b <- build(METH[[nm]]$fn, METH[[nm]]$needs_R, METH[[nm]]$needs_alb, nm)
  R <- eval_sched(b$W); st <- stats_of(R)
  st$fallback_n <- b$fallback_n; st$secs <- as.numeric(difftime(Sys.time(), t0, units="secs"))
  res[[nm]] <- st; sched[[nm]] <- list(W = b$W, R = R)
  cat(sprintf("%-9s netIR %7.4f | actAnn %7.4f | TE %6.4f | TO %6.3f | CAGR %6.4f | MDD %7.4f | Calmar %5.3f | HHI %.4f | wmax %.3f | fb %3d | %4.1fs\n",
      nm, st$net_ir, st$mean_act_ann, st$te_ann, st$to_ann, st$cagr, st$mdd, st$calmar, st$hhi, st$wmax, st$fallback_n, st$secs))
}
saveRDS(list(res = res, sched = sched, dates = dates, WIN = WIN, MINOBS = MINOBS),
        "stage_artifacts/WT_R20260829_005/opt_r7.rds")
cat("\nsaved.\n")
