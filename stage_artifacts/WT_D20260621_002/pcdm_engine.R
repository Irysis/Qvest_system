#==============================================================================
# PCDM — Peer-Cluster Defection Momentum (WT-D20260621_002)
# Alpha Research Agent — α̂ ONLY (no cov, no weights, no optimization)
#
# CONCEPT: per stock i learn dynamic co-movement peer group (rolling-corr top-K,
#   Date<=sig_date ONLY). defection d_i,t = r_i,t - mean(r_peers(i),t).
#   signal = momentum of defection series (12-1, skip 21d). PIT-safe.
#
# Outputs per (sig_date, Ticker): PCDM variants (K x window x horizon), gates,
#   and reference factors M01/M08/M24 computed from SAME rawdata for fair
#   orthogonality + forward Ret_1m label.
#
# PIT: peers learned from Date<=sig_date daily returns (C1 rolling, C7 no full-sample).
#   forward Ret_1m is realized next-month (label only; never in signal). C2 no same-day.
#==============================================================================
# --- single-thread everything (segfault guard: BLAS/OpenMP multithread = crash on this box) ---
Sys.setenv(OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1",
           VECLIB_MAXIMUM_THREADS = "1", ARROW_NUM_THREADS = "2")
suppressMessages({library(arrow); library(data.table)})
setDTthreads(1); arrow::set_cpu_count(1)
try(RhpcBLASctl::blas_set_num_threads(1), silent = TRUE)

ROOT <- "."
RAW  <- file.path(ROOT, ".cache/rawdata.parquet")
BMF  <- file.path(ROOT, ".cache/benchmark.parquet")
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260621_002")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

LOG <- function(...) { cat(sprintf("[%s] %s\n", format(Sys.time(), "%H:%M:%S"), paste0(...))); flush.console() }

#--- 1. Load rawdata (daily) restricted columns + date range ------------------
LOG("loading rawdata ...")
START_DATE <- as.Date("2002-06-01")   # pre-load 2.5y burn-in before 2005-01 signals
ds <- open_dataset(RAW)
RD <- ds |>
  dplyr::filter(Date >= START_DATE) |>
  dplyr::select(Date, Ticker, Close, Vol, Size, Ret, Sector, K200, KQ150,
                AdminStock, TradingHalt) |>
  dplyr::collect() |> as.data.table()
RD[, Date := as.Date(Date)]
setorder(RD, Ticker, Date)
LOG("rawdata rows=", nrow(RD), " tickers=", uniqueN(RD$Ticker),
    " range ", as.character(min(RD$Date)), "..", as.character(max(RD$Date)))

#--- benchmark daily (real KOSPI200 TR) ---------------------------------------
BM <- as.data.table(read_parquet(BMF))
BM[, Date := as.Date(Date)]
BM <- BM[, .(Date, BM_Ret)][!is.na(BM_Ret)]
setkey(BM, Date)

#--- 2. Monthly rebalance grid (month-end trading days) -----------------------
all_dates <- sort(unique(RD$Date))
RD[, ym := year(Date) * 100L + month(Date)]   # integer yearmonth (fast, no format())
month_ends <- RD[, .(Date = max(Date)), by = ym]$Date
month_ends <- sort(month_ends[month_ends >= as.Date("2005-01-01") &
                              month_ends <= as.Date("2026-05-31")])
LOG("rebalance months=", length(month_ends),
    " (", as.character(month_ends[1]), "..", as.character(tail(month_ends,1)), ")")

# next-month-end map for forward return label
me_all <- sort(RD[, .(Date = max(Date)), by = ym]$Date)
nxt_of <- function(d) { i <- which(me_all == d); if (i < length(me_all)) me_all[i+1L] else as.Date(NA) }

#--- 3. Per-stock daily return matrix builder (window) ------------------------
# returns wide matrix [date x ticker] over [sig_date-Wmax, sig_date]
WMAX <- 504L

#--- helper: cumulative product return over index range ------------------------
cumret <- function(r) prod(1 + r) - 1

#--- 4. Core per-month computation --------------------------------------------
# Variants A/B test grid:
#   K in {10,20,40}; window in {252,504}; horizon in {12-1, 6-1}
# Gating: defection persistence = fraction of recent ~12 months with monthly d>0
GRID <- CJ(K = c(10L,20L,40L), W = c(252L,504L), H = c("12_1","6_1"))

compute_month <- function(sig_date) {
  res <- tryCatch({
    win_lo <- sig_date - (WMAX + 40L)          # generous daily window
    w <- RD[Date <= sig_date & Date > win_lo]
    if (nrow(w) == 0L) return(NULL)

    # universe at sig_date: K200 or KQ150, tradeable
    snap <- RD[Date == sig_date]
    if (nrow(snap) == 0L) return(NULL)
    univ <- snap[(K200 == 1 | KQ150 == 1) &
                 (is.na(AdminStock) | AdminStock == 0) &
                 (is.na(TradingHalt) | TradingHalt == 0) &
                 !is.na(Close) & Close > 0, Ticker]
    univ <- unique(univ)
    if (length(univ) < 30L) return(NULL)

    # ADTV proxy (won) = mean(Vol*Close) over trailing 20 trading days, PIT t-1..t
    liq <- w[Ticker %in% univ & Date <= sig_date]
    setorder(liq, Ticker, Date)
    adtv <- liq[, {
      n <- .N; k <- min(20L, n)
      list(adv = mean(tail(Vol, k) * tail(Close, k), na.rm = TRUE))
    }, by = Ticker]

    # daily returns wide matrix over window (only univ)
    wr <- w[Ticker %in% univ & !is.na(Ret), .(Date, Ticker, Ret)]
    # require >= 120 obs in last W for a name to be eligible peer/target
    dcast_ret <- dcast(wr, Date ~ Ticker, value.var = "Ret")
    rdates <- dcast_ret$Date
    M <- as.matrix(dcast_ret[, -1, with = FALSE])     # [days x tickers]
    rownames(M) <- as.character(rdates)
    tick <- colnames(M)

    # --- reference factors from SAME rawdata (M01, M08, M24) ---
    # build per-ticker daily series aligned (use full w, not just univ for sector avg)
    bm_w <- BM[Date %in% rdates]
    setkey(bm_w, Date)
    ref <- w[Ticker %in% univ & !is.na(Ret) & !is.na(Close)]
    setorder(ref, Ticker, Date)
    reff <- ref[, {
      n <- .N; rr <- Ret; pr <- Close
      # M01 12-1 (252d skip 21)
      m01 <- NA_real_
      if (n > 252L) { i0 <- n-252L+1L; i1 <- n-21L; if (i1>i0) m01 <- cumret(rr[i0:i1]) }
      # M02-style 6-1 not needed; M08 residual mom
      m08 <- NA_real_
      if (n >= 252L) {
        td <- data.table(Date = Date, Ret = rr)
        mg <- bm_w[td, on = "Date"][!is.na(Ret) & !is.na(BM_Ret)]
        if (nrow(mg) >= 252L) {
          fit <- .lm.fit(cbind(1, mg$BM_Ret), mg$Ret); rs <- fit$residuals; nr <- length(rs)
          i1 <- nr - 21L; i0 <- max(1L, nr-252L+1L); if (i1>i0) m08 <- sum(rs[i0:i1])
        }
      }
      list(M01 = m01, M08 = m08)
    }, by = Ticker]
    # M24 sector-relative: M01 - sector avg M01
    secmap <- snap[Ticker %in% univ, .(Ticker, Sector)]
    reff <- merge(reff, secmap, by = "Ticker", all.x = TRUE)
    reff[, sec_avg := mean(M01, na.rm = TRUE), by = Sector]
    reff[, M24 := fifelse(!is.na(M01) & !is.na(sec_avg), M01 - sec_avg, NA_real_)]

    # --- forward 1M return label ---
    nd <- nxt_of(sig_date)
    fwd <- NULL
    if (!is.na(nd)) {
      fw <- RD[Ticker %in% univ & Date > sig_date & Date <= nd & !is.na(Ret)]
      fwd <- fw[, .(Ret_1m = cumret(Ret)), by = Ticker]
    }

    # --- PCDM variant loop (each variant hardened in tryCatch returning NULL on skip) ---
    out_list <- vector("list", nrow(GRID))
    for (gi in seq_len(nrow(GRID))) {
     out_list[[gi]] <- tryCatch({
      K <- GRID$K[gi]; W <- GRID$W[gi]; H <- GRID$H[gi]
      hlen <- if (H == "12_1") 252L else 126L
      if (nrow(M) < 60L) return(NULL)
      wkeep <- tail(seq_len(nrow(M)), min(W, nrow(M)))
      Mw <- M[wkeep, , drop = FALSE]
      ok <- colSums(!is.na(Mw)) >= 60L
      if (sum(ok) < 30L) return(NULL)
      Mok <- Mw[, ok, drop = FALSE]
      tk_ok <- colnames(Mok)
      C <- suppressWarnings(stats::cor(Mok, use = "pairwise.complete.obs"))
      C[!is.finite(C)] <- 0
      diag(C) <- NA_real_
      hkeep <- tail(seq_len(nrow(M)), hlen)
      Mh <- M[hkeep, tk_ok, drop = FALSE]
      ndh <- nrow(Mh)
      sk_end <- ndh - 21L                      # skip last 21d
      if (sk_end <= 1L) return(NULL)
      hor_idx <- 1:sk_end
      nT <- length(tk_ok)
      # peer adjacency A[p, j] = 1 if p is a top-K corr neighbor of j
      A <- matrix(0, nT, nT)
      for (j in seq_len(nT)) {
        cj <- C[, j]
        ord <- order(cj, decreasing = TRUE, na.last = NA)
        kk <- ord[seq_len(min(K, length(ord)))]
        if (length(kk) >= 3L) A[kk, j] <- 1
      }
      cs <- colSums(A); good <- cs >= 3L
      if (sum(good) < 10L) return(NULL)
      An <- A
      An[, good] <- sweep(A[, good, drop = FALSE], 2, cs[good], "/")  # col-normalized
      Mhh <- Mh[hor_idx, , drop = FALSE]
      obs_ct <- colSums(is.finite(Mhh))
      Mh0 <- Mhh; Mh0[!is.finite(Mh0)] <- 0
      PeerMean <- Mh0 %*% An                 # [days x stocks] peer-mean per day
      Dmat <- Mh0 - PeerMean
      pcdm_vec <- colSums(Dmat)
      nb <- floor(nrow(Dmat) / 21L)
      persist_vec <- rep(NA_real_, nT)
      if (nb >= 3L) {
        blk_idx <- rep(seq_len(nb), each = 21L)[seq_len(nb*21L)]
        Dblk <- rowsum(Dmat[seq_len(nb*21L), , drop = FALSE], blk_idx)
        persist_vec <- colMeans(Dblk > 0)
      }
      # cumret per stock via colSums(log1p) — vectorized, no apply() (segfault-safe)
      Lg <- log1p(Mh0); Lg[!is.finite(Lg)] <- 0
      cumr <- expm1(colSums(Lg))
      breadth_vec <- rep(NA_real_, nT)
      gj <- which(good)
      for (j in gj) {
        peers <- which(A[, j] == 1)
        if (length(peers) > 0) breadth_vec[j] <- mean(cumr[j] > cumr[peers], na.rm = TRUE)
      }
      vals <- data.table(Ticker = tk_ok, pcdm = pcdm_vec,
                         persist = persist_vec, breadth = breadth_vec,
                         obs = obs_ct, good = good)
      vals <- vals[good == TRUE & obs >= 40L][, `:=`(good = NULL, obs = NULL)]
      if (nrow(vals) == 0L) return(NULL)
      vals[, `:=`(K = K, W = W, H = H, sig_date = sig_date)]
      vals
     }, error = function(e) { LOG("  variant ", gi, " skip @", as.character(sig_date), ": ", conditionMessage(e)); NULL })
    }
    pcdm_all <- rbindlist(out_list, use.names = TRUE, fill = TRUE)
    if (nrow(pcdm_all) == 0L) return(NULL)

    list(pcdm = pcdm_all, ref = reff[, .(Ticker, M01, M08, M24)],
         fwd = fwd, adtv = adtv, sig_date = sig_date)
  }, error = function(e) { LOG("ERR ", as.character(sig_date), ": ", conditionMessage(e)); NULL })
  res
}

#--- 5. Run over all months (sequential, single-process; future for parallel) -
LOG("computing PCDM over ", length(month_ends), " months ...")
results <- vector("list", length(month_ends))
for (mi in seq_along(month_ends)) {
  results[[mi]] <- compute_month(month_ends[mi])
  if (mi %% 6L == 0L) LOG("  ... ", mi, "/", length(month_ends), " (", as.character(month_ends[mi]), ")")
  if (mi %% 30L == 0L) {                       # checkpoint (crash resilience)
    saveRDS(Filter(Negate(is.null), results), file.path(OUT, "results_checkpoint.rds"))
  }
}
results <- Filter(Negate(is.null), results)
saveRDS(results, file.path(OUT, "results_checkpoint.rds"))
LOG("non-null months=", length(results))

#--- 6. Assemble long panels --------------------------------------------------
pcdm_panel <- rbindlist(lapply(results, function(x) x$pcdm), use.names = TRUE, fill = TRUE)
ref_panel  <- rbindlist(lapply(results, function(x) {
  r <- copy(x$ref); r[, sig_date := x$sig_date]; r
}), use.names = TRUE, fill = TRUE)
fwd_panel  <- rbindlist(lapply(results, function(x) {
  if (is.null(x$fwd)) return(NULL); f <- copy(x$fwd); f[, sig_date := x$sig_date]; f
}), use.names = TRUE, fill = TRUE)
adtv_panel <- rbindlist(lapply(results, function(x) {
  a <- copy(x$adtv); a[, sig_date := x$sig_date]; a
}), use.names = TRUE, fill = TRUE)

write_parquet(pcdm_panel, file.path(OUT, "pcdm_panel.parquet"))
write_parquet(ref_panel,  file.path(OUT, "ref_panel.parquet"))
write_parquet(fwd_panel,  file.path(OUT, "fwd_panel.parquet"))
write_parquet(adtv_panel, file.path(OUT, "adtv_panel.parquet"))
LOG("panels written. pcdm rows=", nrow(pcdm_panel),
    " ref rows=", nrow(ref_panel), " fwd rows=", nrow(fwd_panel))
LOG("DONE")
