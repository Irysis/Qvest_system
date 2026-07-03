## Heavy fidelity-PASS methods: Paolella heavy-tail-DCC (COMFORT-RSDC ES-RP) and
## PKM dynamic-regime-RP (MS-GARCH-t + stdMNTS + CVaR/CDaR LP).
## These estimators are data-hungry (paper T~1500). We use a 60m trailing window
## (PIT-valid) and fall back to the elliptical iid/no-GARCH fit when <48m or the
## dynamic EM is ill-conditioned. Window differs from the 36m used for cheap
## methods — reported honestly; it does NOT change the sleeve selection.
## METHOD env: heavytail | heavytail_tilt | regime_cvar | regime_cdar | regime_tilt
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/pg2_frontier_hrp/10_frontier_measure.R")
.load_heavy()
OUT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/pg2_frontier_hrp"
WIN_HEAVY <- 60L

## monthly index (realized KOSPI200) keyed by realized ym for regime/DCC
idxfull <- setNames(bm_m$bm_ret, bm_m$realized_ym)

## --- heavy-tail-DCC weight fn (Paolella) -------------------------------------
heavy_paolella <- function(sel, M_unused, mu_score, rym, i) {
  tk <- sel$Ticker; p <- length(tk); ymt <- sel$ym[1]
  M <- trail_cov_input(ymt, tk, WIN_HEAVY)
  if (is.null(M) || ncol(M) < 3) return(setNames(rep(1/p, p), tk))
  Mf <- M; Mf[!is.finite(Mf)] <- 0; cols <- colnames(Mf)
  Tn <- nrow(Mf)
  wpd <- tryCatch({
    if (Tn >= 48L) {
      phd_risk_parity_portfolio(Mf, dist = "Mt", N_regimes = 2L, alpha = 0.05,
                                garch = TRUE, weight_cap = 0.20, also_rm = FALSE)$weights
    } else stop("short")
  }, error = function(e) {
    tryCatch(phd_risk_parity_portfolio(Mf, dist = "Mt", N_regimes = 1L, alpha = 0.05,
                                       garch = FALSE, iid = TRUE, weight_cap = 0.20,
                                       also_rm = FALSE)$weights,
             error = function(e2) setNames(rep(1/ncol(Mf), ncol(Mf)), cols))
  })
  names(wpd) <- cols
  w <- setNames(rep(0, p), tk); w[cols] <- wpd[cols]
  miss <- setdiff(tk, cols); if (length(miss)) w[miss] <- mean(wpd, na.rm = TRUE)
  w[!is.finite(w)] <- 0; if (sum(w) <= 0) return(setNames(rep(1/p, p), tk))
  w / sum(w)
}

## --- regime-RP weight fn (PKM CVaR/CDaR) -------------------------------------
make_regime_fn <- function(measure = "0.5-CVaR", method = "cvar") {
  function(sel, M_unused, mu_score, rym, i) {
    tk <- sel$Ticker; p <- length(tk); ymt <- sel$ym[1]
    M <- trail_cov_input(ymt, tk, WIN_HEAVY)
    if (is.null(M) || ncol(M) < 3 || nrow(M) < 24) return(setNames(rep(1/p, p), tk))
    Mf <- M; Mf[!is.finite(Mf)] <- 0; cols <- colnames(Mf)
    ri <- which(rownames(RMm) == ymt)
    idxwin <- idxfull[rownames(RMm)[max(1, ri - nrow(Mf) + 1):ri]]
    idxwin <- as.numeric(idxwin); idxwin[!is.finite(idxwin)] <- 0
    if (length(idxwin) != nrow(Mf)) idxwin <- rep(0, nrow(Mf))
    wr <- tryCatch(
      dynamic_regime_rp_weights(Mf, idxwin, method = method,
                                measure = measure, K_grid = c(2L),
                                S = 3000L, H = 10L, ub = 0.20, max_w = 0.20,
                                denoise = TRUE, seed = 20260703 + i)$weights,
      error = function(e) setNames(rep(1/ncol(Mf), ncol(Mf)), cols))
    names(wr) <- cols
    w <- setNames(rep(0, p), tk); w[cols] <- wr[cols]
    miss <- setdiff(tk, cols); if (length(miss)) w[miss] <- mean(wr, na.rm = TRUE)
    w[!is.finite(w)] <- 0; if (sum(w) <= 0) return(setNames(rep(1/p, p), tk))
    w / sum(w)
  }
}

METHOD <- Sys.getenv("METHOD", "heavytail")
runs <- list()
t0 <- Sys.time()
if (METHOD == "heavytail") {
  runs[["HeavyTail_DCC_RP"]]      <- run_method("heavytail", heavy = heavy_paolella)
  runs[["HeavyTail_DCC_RP_tilt"]] <- run_method("heavytail", heavy = heavy_paolella, alpha_tilt = TRUE)
} else if (METHOD == "regime_cvar") {
  runs[["Regime_CVaR"]]      <- run_method("regime", heavy = make_regime_fn("0.5-CVaR","cvar"))
  runs[["Regime_CVaR_tilt"]] <- run_method("regime", heavy = make_regime_fn("0.5-CVaR","cvar"), alpha_tilt = TRUE)
} else if (METHOD == "regime_cdar") {
  runs[["Regime_CDaR"]]      <- run_method("regime", heavy = make_regime_fn("0.3-CDaR","cdar"))
}
cat(sprintf("[heavy %s] elapsed %.1f min\n", METHOD, as.numeric(Sys.time()-t0, units="mins")))
saveRDS(runs, file.path(OUT, sprintf("runs_%s.rds", METHOD)))
summ <- rbindlist(lapply(names(runs), function(k) summarize_method(runs[[k]], k)))
bm   <- rbindlist(lapply(names(runs), function(k) bookmarginal(runs[[k]], k)))
fwrite(summ, file.path(OUT, sprintf("summary_%s.csv", METHOD)))
fwrite(bm,   file.path(OUT, sprintf("bookmarginal_%s.csv", METHOD)))
cat("\n=== SUMMARY ===\n"); print(summ)
cat("\n=== BOOK-MARGINAL ===\n"); print(bm)
cat(sprintf("\n[DONE heavy %s]\n", METHOD))
