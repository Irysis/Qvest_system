# pg2_w2_measure.R — PG2 강화 P1 측정단 (contract-grade)
#
# 입력: stage_artifacts/pg2_w2_earnings3m/panel_signals.parquet (Python 신호구성 산출)
# 측정: 모든 헤드라인(SR/CAGR/MDD/PORT_t/IR/turnover)은 canonical_screen_bt(계약, NW lag-3) 경유.
#       보유밴드는 band-aware weight 구성 후 build_benchmark_compare로 계약-grade PORT_t 산출.
# 비교: 각 정제/composite vs BASE_earn3m를 paired NW-t로.
# 규율: proxy 손계산 금지(헤드라인). 월간(ppy=12) + 분기 native(ppy=4, 3M horizon 정합) 병행.
#       lag1 스트레스 동시 산출(동월 누출 자가검증).
suppressMessages({
  library(data.table); library(arrow)
})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUTDIR <- file.path(ROOT, "stage_artifacts/pg2_w2_earnings3m")
suppressMessages(source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R")))
suppressMessages(source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R")))

pan <- as.data.table(read_parquet(file.path(OUTDIR, "panel_signals.parquet")))
pan[, Date := as.Date(Date)]
cat(sprintf("[load] panel rows=%d months=%d\n", nrow(pan), uniqueN(pan$ym)))

# 벤치마크(월간, KOSPI200 total)
bm <- as.data.table(read_parquet(file.path(ROOT, ".cache/benchmark.parquet")))
bmcol <- intersect(c("BM_Ret", "Ret"), names(bm))[1]
bm[, ym := format(as.Date(Date), "%Y-%m")]
bm <- bm[!is.na(get(bmcol))]
bmm <- bm[, .(BM_Ret = exp(sum(log1p(get(bmcol)))) - 1), by = ym]     # 월간 복리 벤치
# panel의 EOM Date에 맞춘 bench Date 매핑
eom <- unique(pan[, .(ym, Date)])
bench_m <- merge(eom, bmm, by = "ym")[, .(Date, BM_Ret)]

SIGS <- c("BASE_earn3m", "S1_innovrev", "S2_tpsect", "S3_consensus",
          "COMP_S1", "COMP_S2", "COMP_S3", "COMP_ALL")
TOP_N <- 25L; COST <- 15

# returns_dt: Date,Ticker,Ret_1m(=forward)  / liq_dt: Date,Ticker,adv
ret_dt <- pan[, .(Date, Ticker, Ret_1m = fwd_ret_1m)]
liq_dt <- pan[, .(Date, Ticker, adv = adv_lag1)]

# ---- helper: NW t of a mean ----
nw_t <- function(x, lag = 3L) {
  x <- x[!is.na(x)]; n <- length(x)
  if (n < 5) return(NA_real_)
  e <- x - mean(x); s <- sum(e * e) / n
  for (l in seq_len(lag)) s <- s + 2 * (1 - l / (lag + 1)) * (sum(e[(l + 1):n] * e[1:(n - l)]) / n)
  mean(x) / sqrt(s / n)
}
mdd <- function(r) { nav <- cumprod(1 + r); 1 - min(nav / cummax(nav)) }

# ---- canonical top-N screen for a signal column, restricted to date range ----
run_screen <- function(sigcol, ppy = 12L, band = FALSE, lo = NULL, hi = NULL) {
  s <- pan[!is.na(get(sigcol)), .(Date, Ticker, score = get(sigcol))]
  if (!is.null(lo)) s <- s[Date >= as.Date(lo)]
  if (!is.null(hi)) s <- s[Date <= as.Date(hi)]
  if (!band) {
    res <- canonical_screen_bt(s, ret_dt, bench_m, top_n = TOP_N, cost_bps_oneway = COST,
                               liq_dt = liq_dt, liq_min = 2e8,
                               run_id = sigcol, strategy_id = sigcol, periods_per_year = ppy)
    return(res)
  }
  # ---- 보유밴드(Blitz 2023): top-25 진입 + 상위 BAND_KEEP 백분위 잔류 시 보유 ----
  BAND_KEEP <- 0.45   # 상위 45% 안에 있으면 계속 보유(사전 고정)
  # 유동성 필터 적용
  sl <- merge(s, liq_dt, by = c("Date", "Ticker"), all.x = TRUE)
  sl <- sl[is.na(adv) | adv >= 2e8]
  dts <- sort(unique(sl$Date))
  held <- character(0)
  rows <- vector("list", length(dts))
  prev_w <- data.table(Ticker = character(0), w = numeric(0))
  for (i in seq_along(dts)) {
    d <- dts[i]
    cur <- sl[Date == d][order(-score)]
    if (nrow(cur) < TOP_N) { rows[[i]] <- NULL; next }
    cur[, toprank := frank(-score, ties.method = "first")]   # 1 = best score
    cur[, topfrac := toprank / .N]                            # 상위 백분위(0=best)
    top25 <- cur[toprank <= TOP_N, Ticker]
    keep_pool <- cur[topfrac <= BAND_KEEP, Ticker]           # 상위 45% (잔류 자격)
    # 보유밴드: (1) 기존 held 중 keep_pool 잔류자 = 우선 보유(회전 억제), (2) 남은 슬롯을 top25 신규진입으로 채움.
    retain <- intersect(held, keep_pool)
    if (length(retain) > TOP_N) {
      # 잔류자만으로 25 초과 시 score 상위 25 유지
      retain <- cur[Ticker %in% retain][order(-score)][1:TOP_N, Ticker]
    }
    slots <- TOP_N - length(retain)
    fill <- character(0)
    if (slots > 0) {
      cand <- setdiff(top25, retain)                          # 신규 진입 후보(top25 중 미보유)
      if (length(cand) > 0) {
        fill <- cur[Ticker %in% cand][order(-score)][seq_len(min(slots, length(cand))), Ticker]
      }
    }
    newsel <- unique(c(retain, fill))
    held <- newsel
    w <- data.table(Ticker = held, w = 1 / length(held))
    # gross = sum(w * Ret_1m)
    rr <- merge(w, ret_dt[Date == d, .(Ticker, Ret_1m)], by = "Ticker", all.x = TRUE)
    rr[is.na(Ret_1m), Ret_1m := 0]
    gross <- sum(rr$w * rr$Ret_1m)
    # traded = sum(|w_t - w_{t-1}|)
    m <- merge(w[, .(Ticker, w_cur = w)], prev_w[, .(Ticker, w_prev = w)], by = "Ticker", all = TRUE)
    m[is.na(w_cur), w_cur := 0]; m[is.na(w_prev), w_prev := 0]
    traded <- sum(abs(m$w_cur - m$w_prev))
    rows[[i]] <- data.table(date = d, ret_net = gross - traded * COST / 1e4, traded = traded)
    prev_w <- w
  }
  port <- rbindlist(rows)
  pr <- merge(port[, .(date, ret_net)], bench_m[, .(date = Date, benchmark_ret = BM_Ret)], by = "date")
  prt <- data.table(date = pr$date, ret_net = pr$ret_net, frequency = "monthly")
  brt <- data.table(date = pr$date, benchmark_ret = pr$benchmark_ret, benchmark_id = "KOSPI200_total_return")
  bc <- build_benchmark_compare(prt, brt, run_id = paste0(sigcol, "_band"),
                                strategy_id = paste0(sigcol, "_band"), annualization_factor = ppy)
  getbc <- function(nm) { v <- bc[metric_name == nm, active_value]; if (length(v) == 0) NA_real_ else as.numeric(v[1]) }
  active <- pr$ret_net - pr$benchmark_ret
  list(metric_type = "canonical_screen_band", n_months = nrow(pr), top_n = TOP_N,
       portfolio_alpha_t_nw_lag3 = getbc("Portfolio_Alpha_t_NW_lag3"),
       information_ratio = getbc("Information_Ratio"),
       alpha_annualized = getbc("Alpha_Annualized"),
       net_sr = mean(active) / sd(active) * sqrt(ppy),
       turnover_annual = mean(port$traded, na.rm = TRUE) * ppy,
       period_returns = pr)
}

# ---- perf summary from period_returns (SR/CAGR/MDD/calmar on net absolute) ----
perf <- function(pr, ppy = 12L) {
  r <- pr$ret_net; n <- length(r)
  cagr <- prod(1 + r)^(ppy / n) - 1; m <- mdd(r)
  list(absSR = mean(r) / sd(r) * sqrt(ppy), CAGR = cagr, MDD = m, calmar = cagr / m,
       benchcor = cor(pr$ret_net, pr$benchmark_ret))
}

rowify <- function(tag, sigcol, res, ppy) {
  pr <- res$period_returns
  p <- perf(pr, ppy)
  data.table(variant = tag, signal = sigcol, ppy = ppy, n = res$n_months,
             PORT_t_NW = round(res$portfolio_alpha_t_nw_lag3, 3),
             IR = round(res$information_ratio, 3),
             absSR = round(p$absSR, 3), CAGR = round(p$CAGR, 4),
             MDD = round(p$MDD, 4), calmar = round(p$calmar, 3),
             turnover = round(res$turnover_annual, 2), benchcor = round(p$benchcor, 3),
             alpha_ann = round(res$alpha_annualized, 4))
}

results <- list(); pr_store <- list()
cat("[measure] monthly (ppy=12), top-25 EW, 15bps delta, contract-grade\n")

for (sc in SIGS) {
  # (A) plain, full
  r_full <- run_screen(sc, ppy = 12L, band = FALSE)
  results[[length(results) + 1]] <- rowify("plain_full", sc, r_full, 12L)
  pr_store[[paste0(sc, "_plain")]] <- r_full$period_returns
  # recent 2021+
  r_rec <- run_screen(sc, ppy = 12L, band = FALSE, lo = "2021-01-01")
  results[[length(results) + 1]] <- rowify("plain_2021+", sc, r_rec, 12L)
  # (B) band, full
  r_band <- run_screen(sc, ppy = 12L, band = TRUE)
  results[[length(results) + 1]] <- rowify("band_full", sc, r_band, 12L)
  pr_store[[paste0(sc, "_band")]] <- r_band$period_returns
  r_bandrec <- run_screen(sc, ppy = 12L, band = TRUE, lo = "2021-01-01")
  results[[length(results) + 1]] <- rowify("band_2021+", sc, r_bandrec, 12L)
  # (C) lag1 스트레스(plain, full) — 동월 누출 자가검증
  lc <- paste0(sc, "__lag1")
  if (lc %in% names(pan)) {
    r_lag <- run_screen(lc, ppy = 12L, band = FALSE)
    r_lag_row <- rowify("lag1_plain_full", sc, r_lag, 12L)
    results[[length(results) + 1]] <- r_lag_row
  }
  # (D) 분기 native(3M horizon 정합): 분기말만 리밸·측정 (월간 신호를 quarter-end에서만)
  #     ppy=4. quarter-end = ym month %% 3 == 0
  sq <- pan[!is.na(get(sc)) & (as.integer(substr(ym, 6, 7)) %% 3 == 0),
            .(Date, Ticker, score = get(sc))]
  rq <- canonical_screen_bt(sq, ret_dt, bench_m, top_n = TOP_N, cost_bps_oneway = COST,
                            liq_dt = liq_dt, liq_min = 2e8, run_id = paste0(sc, "_q"),
                            strategy_id = paste0(sc, "_q"), periods_per_year = 4L)
  # NOTE: 분기 리밸이나 수익측정은 여전히 월간 forward 1M — 분기 리밸/월간마킹(Round8 방식).
  #       (엄밀 분기수익 측정은 아님; 분기 리밸 turnover 효과 확인용 진단.)
  results[[length(results) + 1]] <- rowify("qtr_rebal_full", sc, rq, 4L)
  cat(sprintf("  done %s\n", sc))
}

restab <- rbindlist(results)
fwrite(restab, file.path(OUTDIR, "measure_results.csv"))
cat("\n=== RESULTS (contract-grade) ===\n")
print(restab[order(signal, variant)])

# ---- paired NW-t vs BASE_earn3m (plain, full 월간 active series) ----
cat("\n=== paired NW-t vs BASE_earn3m (plain full, monthly active net) ===\n")
base_pr <- pr_store[["BASE_earn3m_plain"]]
base_active <- data.table(date = base_pr$date, ba = base_pr$ret_net - base_pr$benchmark_ret)
pair_rows <- list()
for (sc in SIGS) {
  if (sc == "BASE_earn3m") next
  for (variant in c("plain", "band")) {
    pr <- pr_store[[paste0(sc, "_", variant)]]
    a <- data.table(date = pr$date, xa = pr$ret_net - pr$benchmark_ret)
    mg <- merge(base_active, a, by = "date")
    diff <- mg$xa - mg$ba     # (variant active) - (baseline active)
    t_paired <- nw_t(diff, 3L)
    pair_rows[[length(pair_rows) + 1]] <- data.table(
      signal = sc, variant = variant, n = nrow(mg),
      mean_diff_active = round(mean(diff), 5),
      paired_NW_t = round(t_paired, 3))
  }
}
pairtab <- rbindlist(pair_rows)
fwrite(pairtab, file.path(OUTDIR, "paired_vs_baseline.csv"))
print(pairtab[order(-paired_NW_t)])

# save period returns of key variants for charts
saveRDS(pr_store, file.path(OUTDIR, "period_returns_store.rds"))
cat("\n[saved] measure_results.csv / paired_vs_baseline.csv / period_returns_store.rds\n")
