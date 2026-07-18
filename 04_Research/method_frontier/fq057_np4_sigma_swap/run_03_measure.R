# =============================================================================
# FQ-057 NP4 run_03: 실측 — Return.portfolio 기반 net active 시계열 + 사전등록 지표
# - 포트 수익 구성 = PerformanceAnalytics::Return.portfolio(verbose=TRUE)만
#   (월말 t 비중 -> 월 t+1 적용; 자체합성 금지)
# - 비용: 15bps one-way delta 과금 — TO_m = sum|BOP_m - EOP_{m-1}|, cost = 0.0015*TO
# - 벤치: cap-w K200|KQS150 fresh (Size 비례, Return.portfolio 월간 재적용;
#   rawdata.BM_Ret 미사용)
# - 지표: 각 arm PORT_t(NW lag-3, net active) / paired NW lag-3 t(diff = B - A) /
#   SR / calmar / oos_retention v2 / 연간 회전율(캘린더 연 실합산, x12 금지) / DSR(진단)
# Output: np4_series_{S1,S2}.parquet + np4_metrics.json
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(xts); library(PerformanceAnalytics)
  library(sandwich); library(lmtest)
})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")

mr   <- as.data.table(read_parquet(file.path(OUT_DIR, "fq057_monthly_returns.parquet")))
snap <- as.data.table(read_parquet(file.path(OUT_DIR, "fq057_monthly_snapshot.parquet")))
W    <- as.data.table(read_parquet(file.path(OUT_DIR, "np4_weights.parquet")))

ym2date <- function(ym) {
  y <- ym %/% 100L; m <- ym %% 100L
  nx <- ifelse(m == 12L, (y + 1L) * 10000L + 101L, y * 10000L + (m + 1L) * 100L + 1L)
  as.Date(as.character(nx), format = "%Y%m%d") - 1L
}

reb_yms <- sort(unique(W$ym))
all_yms <- sort(unique(mr$ym))
span_yms <- all_yms[all_yms >= min(reb_yms) & all_yms <= max(all_yms)]

# ---- 월간 수익 행렬 (xts, month-end index) ----------------------------------
Mw  <- dcast(mr[ym %in% span_yms], ym ~ Ticker, value.var = "ret_m")
Rmat <- as.matrix(Mw[, -1, drop = FALSE])
Rdates <- ym2date(Mw$ym)
na_count_total <- sum(is.na(Rmat))
Rmat[is.na(Rmat)] <- 0   # NA->0 (양 arm·벤치 동일 적용; 카운트 기록)
R_all <- xts(Rmat, order.by = Rdates)

# ---- 전략 포트 (scenario x arm) --------------------------------------------
build_port <- function(sc, arm) {
  wsub <- W[scenario == sc & arm == !!arm]
  tks <- sort(unique(wsub$Ticker))
  Wmw <- dcast(wsub, ym ~ Ticker, value.var = "w", fill = 0)
  wm <- as.matrix(Wmw[, -1, drop = FALSE])
  wd <- ym2date(Wmw$ym)
  # held인데 다음달 수익 NA였던 횟수 (NA->0 전 원행렬 기준)
  Wx <- xts(wm[, tks, drop = FALSE], order.by = wd)
  Rx <- R_all[, tks, drop = FALSE]
  pf <- Return.portfolio(Rx, weights = Wx, verbose = TRUE)
  ret <- pf$returns
  bop <- pf$BOP.Weight; eop <- pf$EOP.Weight
  stopifnot(identical(colnames(bop), colnames(eop)))
  bm_ <- as.matrix(bop); em_ <- as.matrix(eop)
  n <- nrow(bm_)
  eop_lag <- rbind(matrix(0, 1, ncol(em_)), em_[-n, , drop = FALSE])
  to <- rowSums(abs(bm_ - eop_lag))            # one-way turnover per month
  cost <- 0.0015 * to
  net <- as.numeric(ret) - cost
  data.table(date = index(ret), gross = as.numeric(ret), to_oneway = to,
             cost = cost, ret_net = net)
}

# ---- 벤치: cap-w K200|KQ150 fresh -------------------------------------------
bsnap <- snap[ym %in% reb_yms & member == 1L & !is.na(size) & size > 0]
bsnap <- bsnap[Ticker %in% colnames(R_all)]
bsnap[, wb := size / sum(size), by = ym]
Bw <- dcast(bsnap, ym ~ Ticker, value.var = "wb", fill = 0)
bm_mat <- as.matrix(Bw[, -1, drop = FALSE])
bm_dates <- ym2date(Bw$ym)
btks <- colnames(bm_mat)
Bx <- xts(bm_mat, order.by = bm_dates)
bench_pf <- Return.portfolio(R_all[, btks, drop = FALSE], weights = Bx, verbose = FALSE)
bench_dt <- data.table(date = index(bench_pf), benchmark_ret = as.numeric(bench_pf))
cat("[bench] months:", nrow(bench_dt), " members avg:",
    round(mean(bsnap[, .N, by = ym]$N)), "\n")

# ---- 지표 헬퍼 ---------------------------------------------------------------
nw_t <- function(x, lag = 3L) {
  x <- as.numeric(x); x <- x[!is.na(x)]
  fit <- lm(x ~ 1)
  ct <- lmtest::coeftest(fit, vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))
  list(mean_m = unname(ct[1, 1]), t = unname(ct[1, 3]), n = length(x))
}
ann_sr <- function(x) { x <- as.numeric(x); mean(x) / sd(x) * sqrt(12) }
oos_v2 <- function(x, splits = c(0.55, 0.65, 0.75)) {
  x <- as.numeric(x); N <- length(x)
  rr <- sapply(splits, function(f) {
    n1 <- floor(f * N)
    s_is <- ann_sr(x[1:n1]); s_oos <- ann_sr(x[(n1 + 1):N])
    if (!is.finite(s_is) || abs(s_is) < 1e-9) return(NA_real_)
    s_oos / s_is
  })
  list(splits = as.list(setNames(round(rr, 4), paste0("f", splits * 100))),
       median = median(rr, na.rm = TRUE))
}
psr <- function(x, sr0 = 0) {
  x <- as.numeric(x); n <- length(x)
  sr <- mean(x) / sd(x)
  g3 <- PerformanceAnalytics::skewness(x, method = "moment")
  g4 <- PerformanceAnalytics::kurtosis(x, method = "moment")  # raw kurtosis
  pnorm(((sr - sr0) * sqrt(n - 1)) / sqrt(1 - g3 * sr + (g4 - 1) / 4 * sr^2))
}

measure_cell <- function(sc, arm, port_dt) {
  m <- merge(port_dt, bench_dt, by = "date", all.x = TRUE)
  stopifnot(!anyNA(m$benchmark_ret))
  m[, active := ret_net - benchmark_ret]
  net_x <- xts(m$ret_net, order.by = m$date)
  act   <- m$active
  pt <- nw_t(act)
  cagr <- as.numeric(Return.annualized(net_x, scale = 12, geometric = TRUE))
  mdd  <- as.numeric(maxDrawdown(net_x))
  # 연간 회전율: 캘린더 연 실합산(one-way), full year만 평균; round-trip = x2
  m[, yr := year(date)]
  yr_to <- m[, .(to = sum(to_oneway), n = .N), by = yr][n == 12]
  list(scenario = sc, arm = arm,
       n_months = nrow(m),
       port_t_nw_lag3 = round(pt$t, 4),
       mean_active_monthly = round(pt$mean_m, 6),
       active_sr_ann = round(ann_sr(act), 4),
       net_sr_ann = round(ann_sr(m$ret_net), 4),
       cagr = round(cagr, 4), mdd = round(mdd, 4),
       calmar = round(cagr / mdd, 4),
       oos_retention_v2 = oos_v2(act),
       turnover_oneway_annual_mean = round(mean(yr_to$to), 3),
       turnover_roundtrip_annual_mean = round(mean(yr_to$to) * 2, 3),
       avg_monthly_cost_bps = round(mean(m$cost) * 1e4, 2),
       series = m[, .(date, gross, ret_net, benchmark_ret, active, to_oneway, cost)])
}

results <- list(); series_out <- list()
for (sc in c("S1", "S2")) {
  cellA <- measure_cell(sc, "lw_linear", build_port(sc, "lw_linear"))
  cellB <- measure_cell(sc, "lw_nls",    build_port(sc, "lw_nls"))
  dA <- cellA$series; dB <- cellB$series
  stopifnot(identical(dA$date, dB$date))
  diff <- dB$active - dA$active
  pt_diff <- nw_t(diff)
  # DSR 진단 (2-arm; 게이트 아님): sr* = sd(2 arm 월간 SR) 기반 Bailey-LdP
  srA <- mean(dA$active) / sd(dA$active); srB <- mean(dB$active) / sd(dB$active)
  gamma_e <- 0.5772156649; Ntr <- 2
  sr_star <- sd(c(srA, srB)) * ((1 - gamma_e) * qnorm(1 - 1 / Ntr) +
                                gamma_e * qnorm(1 - 1 / (Ntr * exp(1))))
  dsr_best <- psr(if (srB >= srA) dB$active else dA$active, sr0 = sr_star)
  results[[sc]] <- list(
    arms = list(lw_linear = cellA[setdiff(names(cellA), "series")],
                lw_nls    = cellB[setdiff(names(cellB), "series")]),
    paired = list(diff_def = "active_lw_nls - active_lw_linear (net)",
                  mean_diff_monthly = round(pt_diff$mean_m, 6),
                  nw_t_lag3 = round(pt_diff$t, 4),
                  n = pt_diff$n,
                  ann_diff = round(pt_diff$mean_m * 12, 4)),
    dsr_diagnostic = list(note = "2-arm 가설주도 — 게이트 비대상, 진단 기록",
                          sr_star_monthly = round(sr_star, 4),
                          dsr_better_arm = round(dsr_best, 4)))
  sA <- copy(dA)[, `:=`(scenario = sc, arm = "lw_linear")]
  sB <- copy(dB)[, `:=`(scenario = sc, arm = "lw_nls")]
  series_out[[sc]] <- rbind(sA, sB)
}

SER <- rbindlist(series_out)
write_parquet(SER, file.path(OUT_DIR, "np4_series.parquet"))
metrics <- list(pin_tag = "fq057_20260718_171024",
                measured_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                metric_type = "optimizer_lane_ab_diagnostic",
                na_to_zero_cells_full_matrix = na_count_total,
                bench = "cap-w K200|KQ150 fresh (Size, Return.portfolio monthly reweight)",
                results = results)
write_json(metrics, file.path(OUT_DIR, "np4_metrics.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 8)
cat("[done] run_03 complete\n")
print(str(results, max.level = 3))
