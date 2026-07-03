## Efficient PKM dynamic-regime-RP runner: compute raw regime weights ONCE per
## month (cache), then derive plain + alpha-tilt variants from the cached weights
## (avoids re-running the MC for the tilt variant). CVaR (0.5) and CDaR (0.3).
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/pg2_frontier_hrp/10_frontier_measure.R")
.load_heavy()
OUT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/pg2_frontier_hrp"
WIN_HEAVY <- 60L
idxfull <- setNames(bm_m$bm_ret, bm_m$realized_ym)
S_SIM  <- 2500L

MEAS   <- Sys.getenv("MEAS", "0.5-CVaR")
METH   <- if (MEAS == "0.3-CDaR") "cdar" else "cvar"
LAB    <- if (METH == "cdar") "Regime_CDaR" else "Regime_CVaR"

## --- pass 1: cache raw regime weights per month ------------------------------
raw_w <- vector("list", length(dts))
t0 <- Sys.time()
for (i in seq_along(dts)) {
  d <- dts[i]; sel <- SEL[Date == d]; if (nrow(sel) < C$TOP_N) next
  tk <- sel$Ticker; p <- length(tk); ymt <- sel$ym[1]
  M <- trail_cov_input(ymt, tk, WIN_HEAVY)
  if (is.null(M) || ncol(M) < 3 || nrow(M) < 24) { raw_w[[i]] <- setNames(rep(1/p, p), tk); next }
  Mf <- M; Mf[!is.finite(Mf)] <- 0; cols <- colnames(Mf)
  ri <- which(rownames(RMm) == ymt)
  idxwin <- as.numeric(idxfull[rownames(RMm)[max(1, ri - nrow(Mf) + 1):ri]]); idxwin[!is.finite(idxwin)] <- 0
  if (length(idxwin) != nrow(Mf)) idxwin <- rep(0, nrow(Mf))
  wr <- tryCatch(
    dynamic_regime_rp_weights(Mf, idxwin, method = METH, measure = MEAS, K_grid = c(2L),
                              S = S_SIM, H = 10L, ub = 0.20, max_w = 0.20, denoise = TRUE,
                              seed = 20260703 + i)$weights,
    error = function(e) setNames(rep(1/ncol(Mf), ncol(Mf)), cols))
  names(wr) <- cols
  w <- setNames(rep(0, p), tk); w[cols] <- wr[cols]
  miss <- setdiff(tk, cols); if (length(miss)) w[miss] <- mean(wr, na.rm = TRUE)
  w[!is.finite(w)] <- 0; if (sum(w) <= 0) w <- setNames(rep(1/p, p), tk) else w <- w / sum(w)
  raw_w[[i]] <- w
  if (i %% 20 == 0) cat(sprintf("  [%s] month %d/%d (%.1f min)\n", LAB, i, length(dts), as.numeric(Sys.time()-t0, units="mins")))
}
saveRDS(raw_w, file.path(OUT, sprintf("raw_w_%s.rds", METH)))
cat(sprintf("[%s] weights cached, %.1f min\n", LAB, as.numeric(Sys.time()-t0, units="mins")))

## --- pass 2: build return series from cached weights (plain + tilt) ----------
build_series <- function(tilt) {
  prev_w <- NULL; rows <- vector("list", length(dts))
  for (i in seq_along(dts)) {
    d <- dts[i]; sel <- SEL[Date == d]; if (nrow(sel) < C$TOP_N) next
    tk <- sel$Ticker; p <- length(tk); rym <- sel$realized_ym[1]
    w <- raw_w[[i]]; if (is.null(w)) w <- setNames(rep(1/p, p), tk)
    w <- w[tk]; w[!is.finite(w)] <- 0; if (sum(w) <= 0) w <- setNames(rep(1/p, p), tk) else w <- w/sum(w)
    if (tilt) {
      mu <- setNames(sel$score_eff, tk); r <- rank(mu[names(w)], ties.method="average"); N <- length(r)
      centered <- (r - mean(r))/max(N-1,1); tiltf <- pmax(1 + 1.5*2*centered, 1e-6)
      w <- cap_norm(as.numeric(w)*tiltf); names(w) <- tk
    }
    rr <- merge(data.table(Ticker=names(w), w=as.numeric(w)), sel[,.(Ticker,Ret_1m)], by="Ticker", all.x=TRUE)
    rr[is.na(Ret_1m), Ret_1m:=0]; gross <- sum(rr$w*rr$Ret_1m)
    if (is.null(prev_w)) traded <- 1 else { alln<-union(names(w),names(prev_w)); wc<-setNames(rep(0,length(alln)),alln);wc[names(w)]<-w; wp<-setNames(rep(0,length(alln)),alln);wp[names(prev_w)]<-prev_w; traded<-sum(abs(wc-wp)) }
    rows[[i]] <- data.table(realized_ym=rym, ret_net_bare=gross-traded*COST, traded=traded); prev_w <- w
  }
  sl <- rbindlist(rows)
  mg <- merge(sl, p5[,.(realized_ym,beta_R05,m4,dR05)], by="realized_ym")
  mg <- merge(mg, bm_m, by="realized_ym"); setorder(mg, realized_ym)
  mg[, ret_ov := beta_R05*m4*ret_net_bare - dR05*COST]; mg[, active := ret_ov - bm_ret]; mg
}
runs <- list()
runs[[LAB]]        <- build_series(FALSE)
runs[[paste0(LAB,"_tilt")]] <- build_series(TRUE)
saveRDS(runs, file.path(OUT, sprintf("runs_regime_%s.rds", METH)))
summ <- rbindlist(lapply(names(runs), function(k) summarize_method(runs[[k]], k)))
bm   <- rbindlist(lapply(names(runs), function(k) bookmarginal(runs[[k]], k)))
fwrite(summ, file.path(OUT, sprintf("summary_regime_%s.csv", METH)))
fwrite(bm,   file.path(OUT, sprintf("bookmarginal_regime_%s.csv", METH)))
cat("\n=== SUMMARY ===\n"); print(summ); cat("\n=== BOOK-MARGINAL ===\n"); print(bm)
cat(sprintf("\n[DONE regime %s]\n", METH))
