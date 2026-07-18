# FQ-057 debug: locate window where est_block produces non-finite entries
suppressPackageStartupMessages({library(data.table); library(arrow)})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source(file.path(ROOT, "04_Research/method_frontier/fq057_captier_sigma/estimators.R"))
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")
mr <- as.data.table(read_parquet(file.path(OUT_DIR, "fq057_monthly_returns.parquet")))
sn <- as.data.table(read_parquet(file.path(OUT_DIR, "fq057_monthly_snapshot.parquet")))
yms <- sort(unique(mr$ym))
ym_shift <- function(ym, k) { t <- (ym %/% 100L)*12L + (ym %% 100L - 1L) + k
  (t %/% 12L)*100L + t %% 12L + 1L }
memb_sz <- sn[member == 1L & !is.na(size), .(Ticker, ym, size)]
memb_sz[, ym_next := ym_shift(ym, 1L)]
mkt_dt <- merge(mr, memb_sz[, .(Ticker, ym = ym_next, w_size = size)], by = c("Ticker","ym"))
mkt_series <- mkt_dt[, .(mkt = sum(ret_m*w_size)/sum(w_size)), by = ym][order(ym)]
est_ends <- yms[yms >= 200912 & yms < max(yms)]

chk <- function(M) sum(!is.finite(M))
for (wi in 20:60) {
  t_end <- est_ends[wi]
  win <- tail(yms[yms <= t_end], 60)
  memb <- sn[ym == t_end & member == 1L & !is.na(size), .(Ticker, size)]
  sub <- mr[ym %in% win & Ticker %in% memb$Ticker]
  full <- sub[, .N, by = Ticker][N == 60, Ticker]
  Wc <- dcast(sub[Ticker %in% full], ym ~ Ticker, value.var = "ret_m")
  Rm <- as.matrix(Wc[, -1]); rownames(Rm) <- Wc$ym
  sz <- memb[match(colnames(Rm), Ticker), size]
  rk <- frank(-sz, ties.method = "first")
  tier <- fifelse(rk <= 30, "MEGA", fifelse(rk <= 150, "MID", "SMALL"))
  mkt <- mkt_series[match(win, ym), mkt]
  bad <- c(rm = chk(Rm), mkt = chk(mkt))
  # test inner estimators per tier without psd_repair
  for (tr in unique(tier)) {
    idx <- which(tier == tr)
    sub2 <- Rm[, idx, drop = FALSE]
    lw  <- tryCatch(est_lw_linear(sub2), error = function(e) matrix(NaN,1,1))
    nls <- tryCatch(est_lw_nls(sub2),   error = function(e) matrix(NaN,1,1))
    if (chk(lw) > 0 || chk(nls) > 0) {
      cat(sprintf("wi=%d t_end=%d tier=%s p=%d nonfinite lw=%d nls=%d\n",
                  wi, t_end, tr, length(idx), chk(lw), chk(nls)))
      if (chk(lw) > 0) {
        S <- cov(sub2); pp <- ncol(sub2); nn <- nrow(sub2)
        num <- (nn-2)/nn*sum(diag(S)^2) + sum(S)^2
        den <- (nn+2)*(sum(S^2) - sum(diag(S)^2)/pp)
        cat(sprintf("   lw rho parts: num=%.3e den=%.3e sd_min=%.3e\n",
                    num, den, min(apply(sub2, 2, sd))))
      }
      if (chk(nls) > 0) {
        cat("   nls: sd_min=", min(apply(sub2, 2, sd)), " any const col=",
            any(apply(sub2, 2, sd) < 1e-12), "\n")
      }
    }
  }
  if (bad["rm"] > 0) cat("wi=", wi, "Rm nonfinite\n")
}
cat("debug done\n")
