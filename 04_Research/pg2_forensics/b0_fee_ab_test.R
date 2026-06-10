# b0_fee_ab_test.R — 매도 수수료 결함 A/B 정량화 (2026-06-10)
# 사용법: Rscript b0_fee_ab_test.R <harness_path> <out_json>
#   동일 입력(합성 2케이스 + 실데이터 2케이스)을 pre/post-patch 하니스로 각각 실행.
# 합성: 가격 고정(Close=10000, Ret=0) → NAV 감소 = 순수 거래비용.
# 실데이터: 저회전(Size top20) vs 고회전(21d 리버설 top20), 시그널 2019-12~2023-12.
# 주의: 본 스크립트는 엔진 비용회계 A/B 테스트 전용 — 전략 리서치 아님(레지스트리 미등재).

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) stop("usage: Rscript b0_fee_ab_test.R <harness_path> <out_json>")
harness_path <- args[1]
out_json     <- args[2]

Sys.setenv(CLAUDE_PROJECT_DIR = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/config.R")
source(harness_path)

# ── 스모크: 핵심 함수 존재 확인 ──────────────────────────────────────────────
smoke <- c(
  run_monthly_simulation = exists("run_monthly_simulation"),
  summarise_perf         = exists("summarise_perf"),
  calc_turnover          = exists("calc_turnover"),
  load_rawdata           = exists("load_rawdata"),
  get_execution_date     = exists("get_execution_date")
)
cat("[smoke]", paste(names(smoke), smoke, sep = "=", collapse = " | "), "\n")
if (!all(smoke)) stop("smoke FAIL: missing functions")

results <- list(harness = harness_path, smoke = as.list(smoke))

run_case <- function(RAWDATA, BM_DT, FACTORS, n_hold, label) {
  sim <- run_monthly_simulation(RAWDATA, BM_DT, FACTORS,
                                n_holdings  = n_hold,
                                commission  = 0.0015,
                                initial_cap = 1e8,
                                weight_method = "equal")
  nav <- sim$DAILY_NAV_DT
  perf <- summarise_perf(sim$strategy_xts, label)
  list(
    label      = label,
    n_rebal    = nrow(sim$PORTFOLIO_LOG),
    nav_end    = tail(nav$NAV, 1),
    total_ret  = tail(nav$NAV, 1) / 1e8 - 1,
    cagr_pct   = perf$CAGR,
    annvol_pct = perf$AnnVol,
    sharpe     = perf$Sharpe,
    mdd_pct    = perf$MDD,
    ann_turnover_pct = calc_turnover(sim$PORTFOLIO_LOG, nav),
    period     = paste(min(nav$Date), "~", max(nav$Date))
  )
}

# ════════════════ 1. 합성 케이스 (산술 검증) ════════════════
syn_dates <- seq(as.Date("2020-01-01"), as.Date("2021-06-30"), by = "day")
syn_dates <- syn_dates[as.integer(format(syn_dates, "%u")) <= 5]
tk_all <- sprintf("T%02d", 1:10)

SYN_RAW <- CJ(Ticker = tk_all, Date = syn_dates)
SYN_RAW[, `:=`(Close = 10000, Ret = 0, Name = Ticker, Sector = "SYN")]
SYN_BM <- data.table(Date = syn_dates, BM_Ret = 0)

syn_me <- SYN_RAW[, .(d = max(Date)), by = .(ym = format(Date, "%Y-%m"))]
syn_sig <- sort(syn_me$d)

# 저회전: 매월 동일 5종목 (name turnover 0%)
f_low <- rbindlist(lapply(syn_sig, function(d)
  data.table(Date = d, Ticker = tk_all[1:5], Score = 5:1)))
# 고회전: 매월 5종목 전체 교체 (name turnover 100%)
f_high <- rbindlist(lapply(seq_along(syn_sig), function(i) {
  set_i <- if (i %% 2 == 1) tk_all[1:5] else tk_all[6:10]
  data.table(Date = syn_sig[i], Ticker = set_i, Score = 5:1)
}))

results$syn_low  <- run_case(copy(SYN_RAW), SYN_BM, f_low,  5, "SYN_lowTO_0pct")
results$syn_high <- run_case(copy(SYN_RAW), SYN_BM, f_high, 5, "SYN_highTO_100pct")

# ════════════════ 2. 실데이터 케이스 ════════════════
real_ok <- tryCatch({
  res <- load_rawdata(use_cache = TRUE)
  RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
  need_cols <- c("Date", "Ticker", "Close", "Ret", "Size")
  miss <- setdiff(need_cols, names(RAWDATA))
  if (length(miss) > 0) stop("RAWDATA missing cols: ", paste(miss, collapse = ","))
  if (!"Name" %in% names(RAWDATA))   RAWDATA[, Name := Ticker]
  if (!"Sector" %in% names(RAWDATA)) RAWDATA[, Sector := NA_character_]

  me <- RAWDATA[, .(d = max(Date)), by = .(ym = format(Date, "%Y-%m"))]
  sig_dates <- sort(me$d)
  sig_dates <- sig_dates[sig_dates >= as.Date("2019-12-01") &
                         sig_dates <= as.Date("2023-12-31")]

  # 저회전: 시그널일 Size 상위 (대형주 — 구성 안정적)
  sig_dt <- data.table(Date = sig_dates)
  f_rlow <- RAWDATA[sig_dt, on = "Date", nomatch = 0][
    !is.na(Size) & !is.na(Close), .(Date, Ticker, Score = Size)]

  # 고회전: 21일 리버설 (직전 21거래일 수익률 낮은 순 — name turnover 高)
  setkey(RAWDATA, Ticker, Date)
  RAWDATA[, ret21 := Close / shift(Close, 21) - 1, by = Ticker]
  f_rhigh <- RAWDATA[sig_dt, on = "Date", nomatch = 0][
    !is.na(ret21) & !is.na(Close), .(Date, Ticker, Score = -ret21)]
  RAWDATA[, ret21 := NULL]

  results$real_low  <<- run_case(RAWDATA, BM_DT, f_rlow,  20, "REAL_lowTO_size20")
  results$real_high <<- run_case(RAWDATA, BM_DT, f_rhigh, 20, "REAL_highTO_rev21")
  TRUE
}, error = function(e) {
  results$real_error <<- conditionMessage(e)
  cat("[real-data] FAILED:", conditionMessage(e), "\n")
  FALSE
})
results$real_ok <- real_ok

jsonlite::write_json(results, out_json, auto_unbox = TRUE, digits = 10)
cat("[done] →", out_json, "\n")
