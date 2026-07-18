# =============================================================================
# WT-D20260718_001 run_01: 크래시 피처 패널 구축 (PIT: 월말 t 이하 데이터만)
#   ym별 eligible 유니버스 → mom_12_1/mom_6_1 + dbeta/semivol/ncskew/mdd12
# Output: wt001_signal_panel.parquet
# =============================================================================
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/WT_D20260718_001/wt001_lib.R")

SIG_FROM <- 200511L; SIG_TO <- 202605L
LIQ_MIN <- 2e8
MIN_DAILY <- 200L; MIN_DOWN_MKT <- 60L; MIN_DOWN_OWN <- 30L

P <- load_panels_wt()
D <- load_daily_wt()
B <- load_bench_daily_wt()

sig_yms <- ym_seq_w(SIG_FROM, SIG_TO)
cat("[run_01] signal months:", length(sig_yms), "range", sig_yms[1], "..", sig_yms[length(sig_yms)], "\n")

# bench 일간 sanity (사용 구간)
b_used <- B[ym >= ym_shift_w(SIG_FROM, -11L) & ym <= SIG_TO]
cat("[bench daily] n =", nrow(b_used), " max|mret| =", round(max(abs(b_used$mret)), 4), "\n")

res <- vector("list", length(sig_yms))
t0 <- Sys.time()
for (k in seq_along(sig_yms)) {
  t_ym <- sig_yms[k]
  idx <- match(t_ym, P$yms)
  stopifnot(!is.na(idx), idx >= 12L)

  # -- eligibility --
  members <- P$snap[ym == t_ym & member == 1L, Ticker]
  liq_ok  <- P$liq[ym == t_ym & !is.na(avgtv20) & avgtv20 >= LIQ_MIN, Ticker]
  cand <- intersect(intersect(members, liq_ok), colnames(P$mat))
  if (length(cand) < 40L) next
  # mom window t-11..t-1 (11개월) 전부 non-NA
  mrows <- (idx - 11L):(idx - 1L)
  msub <- P$mat[mrows, cand, drop = FALSE]
  cand <- cand[colSums(!is.na(msub)) == 11L]
  if (length(cand) < 40L) next

  # -- momentum --
  msub <- P$mat[mrows, cand, drop = FALSE]
  mom12 <- expm1(colSums(log1p(msub)))
  m6rows <- (idx - 6L):(idx - 1L)
  m6sub <- P$mat[m6rows, cand, drop = FALSE]
  mom6 <- expm1(colSums(log1p(m6sub)))   # 6개월 window 내 NA 있으면 NA 허용(robustness 재료)

  # -- daily window: 직전 12개월 (t-11..t, 월말 t 이하) --
  w_from <- ym_shift_w(t_ym, -11L)
  ds <- D[ym >= w_from & ym <= t_ym & Ticker %chin% cand]
  bs <- B[ym >= w_from & ym <= t_ym, .(Date, mret)]
  mu_m <- mean(bs$mret)
  down_dates <- bs[mret < mu_m, Date]
  ds <- merge(ds, bs, by = "Date", all.x = TRUE)

  feat <- ds[order(Date), {
    r <- Ret; n <- length(r)
    if (n < MIN_DAILY) {
      list(n_daily = n, dbeta = NA_real_, semivol = NA_real_, ncskew = NA_real_, mdd12 = NA_real_)
    } else {
      # semivol
      rd <- r[r < 0]
      sv <- if (length(rd) >= MIN_DOWN_OWN) sd(rd) else NA_real_
      # ncskew
      rc <- r - mean(r); S2 <- sum(rc^2); S3 <- sum(rc^3)
      nc <- if (S2 > 1e-12) -(n * (n - 1)^1.5 * S3) / ((n - 1) * (n - 2) * S2^1.5) else NA_real_
      # downside beta (market down days, paired obs)
      dm <- !is.na(mret) & (Date %in% down_dates)
      db <- NA_real_
      if (sum(dm) >= MIN_DOWN_MKT) {
        rm_ <- mret[dm]; ri_ <- r[dm]
        vv <- var(rm_)
        if (is.finite(vv) && vv > 1e-12) db <- cov(ri_, rm_) / vv
      }
      # trailing mdd (일간 누적)
      nav <- cumprod(1 + r)
      mdd <- max(1 - nav / cummax(nav))
      list(n_daily = n, dbeta = db, semivol = sv, ncskew = nc, mdd12 = mdd)
    }
  }, by = Ticker]

  feat <- feat[n_daily >= MIN_DAILY]
  keep <- intersect(cand, feat$Ticker)
  if (length(keep) < 40L) next

  out <- data.table(ym = t_ym, Ticker = keep,
                    mom_12_1 = mom12[keep], mom_6_1 = mom6[keep])
  out <- merge(out, feat, by = "Ticker")
  res[[k]] <- out

  if (k %% 24L == 0L) cat(sprintf("  .. %d/%d (%s) elig=%d elapsed=%.1fm\n",
      k, length(sig_yms), t_ym, length(keep), as.numeric(difftime(Sys.time(), t0, units = "mins"))))
}

PANEL <- rbindlist(res)
setcolorder(PANEL, c("ym", "Ticker"))
write_parquet(PANEL, file.path(OUT_WT, "wt001_signal_panel.parquet"))

# coverage 요약
cov_tab <- PANEL[, .(n_elig = .N,
                     na_dbeta = sum(is.na(dbeta)), na_sv = sum(is.na(semivol)),
                     na_nc = sum(is.na(ncskew))), by = ym]
cat("[run_01] panel rows:", nrow(PANEL), " months:", uniqueN(PANEL$ym),
    " elig/month mean:", round(mean(cov_tab$n_elig), 1),
    " range:", min(cov_tab$n_elig), "-", max(cov_tab$n_elig), "\n")
cat("[run_01] feature NA rates: dbeta", round(sum(cov_tab$na_dbeta)/nrow(PANEL), 4),
    " semivol", round(sum(cov_tab$na_sv)/nrow(PANEL), 4),
    " ncskew", round(sum(cov_tab$na_nc)/nrow(PANEL), 4), "\n")
cat("[done] run_01\n")
