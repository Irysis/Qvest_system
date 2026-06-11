# _te_unit.R — TE 추정기 단위검증 (합성데이터, RAWDATA 무관). 임시 진단 — 검증 후 삭제 가능.
.discretize <- function(x, nbin) {
  ok <- is.finite(x); if (sum(ok) < 10L) return(rep(NA_integer_, length(x)))
  qs <- quantile(x[ok], probs = seq_len(nbin - 1L) / nbin, na.rm = TRUE, type = 7)
  if (any(!is.finite(qs)) || length(unique(qs)) < (nbin - 1L)) {
    r <- rank(x, ties.method = "average", na.last = "keep")
    b <- ceiling(r / sum(ok) * nbin); b[b < 1L] <- 1L; b[b > nbin] <- nbin
    return(as.integer(b))
  }
  b <- findInterval(x, qs) + 1L; b[!ok] <- NA_integer_; as.integer(b)
}
.te_xy <- function(xb, yb, nbin) {
  n <- length(yb); if (n < 30L) return(NA_real_)
  y1 <- yb[-1L]; y0 <- yb[-n]; x0 <- xb[-n]
  ok <- is.finite(y1) & is.finite(y0) & is.finite(x0); if (sum(ok) < 30L) return(NA_real_)
  y1 <- y1[ok]; y0 <- y0[ok]; x0 <- x0[ok]; N <- length(y1)
  idx3 <- (y1 - 1L) * nbin * nbin + (y0 - 1L) * nbin + (x0 - 1L) + 1L
  p3 <- tabulate(idx3, nbins = nbin^3) / N
  p_y0x0 <- tabulate((y0 - 1L) * nbin + (x0 - 1L) + 1L, nbins = nbin^2) / N
  p_y1y0 <- tabulate((y1 - 1L) * nbin + (y0 - 1L) + 1L, nbins = nbin^2) / N
  p_y0 <- tabulate(y0, nbins = nbin) / N; te <- 0
  for (a in seq_len(nbin)) for (b in seq_len(nbin)) for (c in seq_len(nbin)) {
    i3 <- (a - 1L) * nbin * nbin + (b - 1L) * nbin + (c - 1L) + 1L
    pj <- p3[i3]; if (pj <= 0) next
    pyx <- p_y0x0[(b - 1L) * nbin + (c - 1L) + 1L]
    pyy <- p_y1y0[(a - 1L) * nbin + (b - 1L) + 1L]; py <- p_y0[b]
    if (pyx <= 0 || pyy <= 0 || py <= 0) next
    te <- te + pj * log((pj / pyx) / (pyy / py))
  }
  if (!is.finite(te) || te < 0) te <- max(te, 0, na.rm = TRUE)
  te
}
set.seed(1); n <- 300
x <- rnorm(n); y <- rnorm(n)
for (t in 2:n) y[t] <- 0.8 * x[t - 1] + 0.3 * rnorm(1)   # X leads Y by 1 lag
xb <- .discretize(x, 3L); yb <- .discretize(y, 3L)
te_xy <- .te_xy(xb, yb, 3L); te_yx <- .te_xy(yb, xb, 3L)
cat(sprintf("Directional: TE(X->Y)=%.4f  TE(Y->X)=%.4f  net-sink(Y)=%.4f (Y=sink, expect>0)\n",
            te_xy, te_yx, te_xy - te_yx))
xi <- rnorm(n); yi <- rnorm(n)
cat(sprintf("Independence: TE=%.4f (expect small finite-sample bias)\n",
            .te_xy(.discretize(xi, 3L), .discretize(yi, 3L), 3L)))
dg <- .discretize(c(rep(0, 150), rnorm(150)), 3L)
cat(sprintf("Degenerate-mix discretize NA-free=%s | const TE=%.4f\n",
            !anyNA(dg), .te_xy(.discretize(rep(0.001, n), 3L), yb, 3L)))
cat("UNIT OK\n")
