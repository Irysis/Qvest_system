# FQ-057 debug2: reproduce est_block failure exactly over wi=25..60
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

for (wi in 25:60) {
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
  for (inner in c("lw", "nls")) {
    r <- tryCatch(est_block(Rm, tier, mkt, inner = inner),
                  error = function(e) e)
    if (inherits(r, "error")) {
      cat(sprintf("FAIL wi=%d t_end=%d inner=%s p=%d : %s\n",
                  wi, t_end, inner, ncol(Rm), conditionMessage(r)))
      # decompose: build Sig manually
      p <- ncol(Rm)
      Sig <- matrix(0, p, p, dimnames = list(colnames(Rm), colnames(Rm)))
      for (tr in unique(tier)) {
        idx <- which(tier == tr)
        Sig[idx, idx] <- if (length(idx) == 1) var(Rm[, idx])
          else if (inner == "lw") est_lw_linear(Rm[, idx, drop = FALSE])
          else est_lw_nls(Rm[, idx, drop = FALSE])
        cat(sprintf("  tier=%s p=%d nonfinite=%d max_abs=%.3e\n", tr, length(idx),
            sum(!is.finite(Sig[idx, idx])), max(abs(Sig[idx, idx]), na.rm = TRUE)))
      }
      vm <- var(mkt); b <- as.numeric(cov(Rm, mkt))/vm
      cat(sprintf("  vm=%.3e beta nonfinite=%d beta max_abs=%.3e\n",
                  vm, sum(!is.finite(b)), max(abs(b))))
      stop("stop after first failure for inspection")
    }
  }
}
cat("no failure in 25:60\n")
