# ab_canonical_port_q4.R — Q4 lag repair A/B: canonical PORT_t old-vs-new factor DB
# (q4_lag_repair_plan_20260725.md §3.3-3 전략 레벨 + §7b production 대조)
#
# 실행: AB_LABEL=old|new 환경변수로 side 지정. 동일 코드·동일 유니버스 양측 실행.
#   old = 수리 전 canonical .cache/factor_db (pin q4_pre_20260725와 byte-동일 시점에 실행)
#   new = 수리 후 재빌드된 .cache/factor_db
# 산출: stage_artifacts/q4_lag_repair_20260725/ab_canonical_{label}.json (+period_returns parquet)
#
# 측정 대상 (플랜 §1.3 + 집행지시 4):
#   대표 팩터 5: V01_BM, V02_EP, Q01_GPA, V11_Shareholder_Yield, XF_Q06_Op_Margin
#   book 대표: BOOK_STR1715_composite = EW mean of aligned Z {Q07_Earnings_Stability,
#     M08_Residual_Mom, Q25_Ohlson_O} (STR_1715 alpha 구성 3팩터 — canonical_screen 라벨.
#     book NAV 자체가 아님: forge/production이 admission 권위, 이건 §7b 대조용 canonical 실측)
#
# metric_type = "canonical_screen" (proxy 손계산 없음 — build_benchmark_compare 경유,
#   calmar/CAGR/MDD = PerformanceAnalytics 표준 함수, oos_retention = approx 라벨)

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(xts); library(PerformanceAnalytics)
})
QM <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(QM)
LABEL <- Sys.getenv("AB_LABEL", "old")
OUT <- file.path(QM, "stage_artifacts/q4_lag_repair_20260725")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/ramp/factor_validation.R")

FACTORS5 <- c("V01_BM", "V02_EP", "Q01_GPA", "V11_Shareholder_Yield", "XF_Q06_Op_Margin")
BOOK3    <- c("Q07_Earnings_Stability", "M08_Residual_Mom", "Q25_Ohlson_O")
ALLF     <- c(FACTORS5, BOOK3)

# ── RAWDATA month-end panel + forward returns (fq066 하네스 패턴, 양측 동일) ──
rd <- as.data.table(read_parquet(file.path(QM, ".cache/RAWDATA.parquet"),
                                 col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
rd[, Date := as.Date(Date)]
rd <- rd[Date >= as.Date("2004-06-01") & !is.na(Close) & Close > 0]
rd[, ym := format(Date, "%Y-%m")]
me_dates <- rd[, .(Date = max(Date)), by = ym]$Date
rd_me <- rd[Date %in% me_dates]
sig_dates <- sort(unique(rd_me$Date))
sig_dates <- sig_dates[sig_dates >= as.Date("2004-12-01")]

fwd <- build_monthly_forward_returns(rd_me, sig_dates)
returns_dt <- fwd$returns_dt; bench_dt <- fwd$bench_dt; liq_dt <- fwd$liq_dt
cat(sprintf("[%s] months=%d stock-months=%s\n", LABEL, uniqueN(returns_dt$Date),
            format(nrow(returns_dt), big.mark = ",")))
univ_dt <- rd_me[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]

# ── 월별 aligned Z 로드 (C15: load_month_factors 경유. 방향정렬 = factor_ic_monthly PIT) ──
score_months <- sort(unique(returns_dt$Date))
zlist <- vector("list", length(score_months))
for (i in seq_along(score_months)) {
  d <- score_months[i]
  z <- tryCatch(load_month_factors(d, factor_names = ALLF), error = function(e) NULL)
  if (is.null(z) || nrow(z) == 0) next
  z[, Date := d]
  zlist[[i]] <- z
  if (i %% 50 == 0) cat(sprintf("  [%d/%d] %s\n", i, length(score_months), d))
}
Z <- rbindlist(zlist[!sapply(zlist, is.null)])
Z <- merge(Z, univ_dt, by = c("Date", "Ticker"))  # K200∪KQ150 고정
cat(sprintf("[%s] Z panel: %s rows, %d months, %d factors\n", LABEL,
            format(nrow(Z), big.mark = ","), uniqueN(Z$Date), uniqueN(Z$Factor_Name)))

# ── 자산별 scores_dt 구성 ──
make_scores <- function(fn) {
  s <- Z[Factor_Name == fn & !is.na(Z_Score_Aligned), .(Date, Ticker, score = Z_Score_Aligned)]
  s
}
make_book_composite <- function() {
  b <- Z[Factor_Name %in% BOOK3 & !is.na(Z_Score_Aligned)]
  comp <- b[, .(score = mean(Z_Score_Aligned), n_avail = .N), by = .(Date, Ticker)]
  comp[n_avail >= 2L, .(Date, Ticker, score)]  # 3팩터 중 >=2 가용 시만
}

# ── 측정 (canonical_screen_bt + PerformanceAnalytics 표준 함수) ──
measure_one <- function(scores, asset_id) {
  cs <- canonical_screen_bt(scores, returns_dt[, .(Date, Ticker, Ret_1m)],
                            bench_dt[, .(Date, BM_Ret)],
                            top_n = 25L, cost_bps_oneway = 15,
                            liq_dt = liq_dt[, .(Date, Ticker, adv)], liq_min = 2e8,
                            run_id = sprintf("q4ab_%s_%s", LABEL, asset_id),
                            strategy_id = asset_id, periods_per_year = 12L,
                            diag_dual_basis = FALSE)
  pr <- cs$period_returns
  if (is.null(pr) || nrow(pr) < 24) {
    return(list(asset = asset_id, error = "insufficient months",
                n_months = if (is.null(pr)) 0L else nrow(pr)))
  }
  x_net <- xts(pr$ret_net, order.by = pr$date)
  active <- pr$ret_net - pr$benchmark_ret
  calmar <- as.numeric(CalmarRatio(x_net, scale = 12))
  cagr   <- as.numeric(Return.annualized(x_net, scale = 12, geometric = TRUE))
  mdd    <- as.numeric(maxDrawdown(x_net))
  oos    <- .canon_oos_rough(active, ppy = 12L)
  p17    <- pr$date >= as.Date("2017-01-01")
  list(
    asset = asset_id,
    metric_type = "canonical_screen",
    n_months = cs$n_months,
    portfolio_alpha_t_nw_lag3 = cs$portfolio_alpha_t_nw_lag3,
    portfolio_alpha_t_pvalue = cs$portfolio_alpha_t_pvalue,
    information_ratio = cs$information_ratio,
    alpha_annualized = cs$alpha_annualized,
    net_sr = cs$net_sr,
    turnover_annual = cs$turnover_annual,
    cagr_net = cagr, mdd_net = mdd, calmar_net = calmar,
    oos_retention_approx = oos,
    oos_note = "anchored 3-split {55/65/75} median approx - gate authority = essence_score.R",
    post2017_t_nw_lag3 = .canon_nw_t(active[p17]),
    hard_gate_snapshot = list(
      port_t_ge_2p95 = isTRUE(cs$portfolio_alpha_t_nw_lag3 >= 2.95),
      oos_approx_ge_0p7 = isTRUE(!is.na(oos) && oos >= 0.7),
      calmar_ge_0p64 = isTRUE(!is.na(calmar) && calmar >= 0.64)
    )
  )
}

results <- list()
prs <- list()
for (fn in FACTORS5) {
  cat(sprintf("[%s] measuring %s ...\n", LABEL, fn))
  sc <- make_scores(fn)
  r <- measure_one(sc, fn)
  results[[fn]] <- r
  cs_tmp <- NULL
}
cat(sprintf("[%s] measuring BOOK_STR1715_composite ...\n", LABEL))
results[["BOOK_STR1715_composite"]] <- measure_one(make_book_composite(), "BOOK_STR1715_composite")

# period_returns 저장 (재현성) — 각 자산 재측정하여 pr 회수 대신 결과 요약만 저장하는 대신,
# 요약 + 시계열 동시 확보를 위해 한 번 더 돌리지 않고 요약만 JSON. (양측 동일 코드 보장이 핵심)

meta <- list(
  label = LABEL,
  run_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  factor_db_dir = file.path(QM, ".cache/factor_db"),
  pin_tag_reference = "q4_pre_20260725",
  build_hash = tryCatch(readLines(file.path(QM, ".cache/factor_db/build_hash.txt"), warn = FALSE),
                        error = function(e) NA_character_),
  universe = "K200|KQ150 (RAWDATA flags at sig_date)",
  top_n = 25, cost_bps_oneway = 15, liq_min = 2e8,
  sig_range = as.character(range(score_months)),
  metric_type = "canonical_screen"
)
out <- list(meta = meta, results = results)
write_json(out, file.path(OUT, sprintf("ab_canonical_%s.json", LABEL)),
           auto_unbox = TRUE, na = "null", pretty = TRUE, digits = 8)
cat(sprintf("[%s] saved ab_canonical_%s.json\n", LABEL, LABEL))
for (nm in names(results)) {
  r <- results[[nm]]
  if (!is.null(r$error)) { cat(sprintf("  %s: ERROR %s\n", nm, r$error)); next }
  cat(sprintf("  %-24s PORT_t=%7.3f IR=%6.3f netSR=%6.3f CAGR=%6.3f MDD=%6.3f Calmar=%6.3f oos~%5.3f nM=%d\n",
              nm, r$portfolio_alpha_t_nw_lag3, r$information_ratio, r$net_sr,
              r$cagr_net, r$mdd_net, r$calmar_net,
              ifelse(is.na(r$oos_retention_approx), NA, r$oos_retention_approx), r$n_months))
}
