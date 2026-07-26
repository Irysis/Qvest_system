# ab_canonical_fy2025.R — FY2025 DART 백필 반영 factor DB 재빌드 A/B
# (프로토콜 = stage_artifacts/q4_lag_repair_20260725/ab_canonical_port_q4.R 동일)
#
# OLD = pin .cache/pins/fy2025_rebuild_20260726/ (Jul 25 20:43~20:49 빌드, FY2025 백필 前)
# NEW = 재빌드된 .cache/factor_db/ (2026-07-26, FY2025 139,045 DART행 반영)
#   차이 월 = 202603~202607 (5개월). 그 외 월은 양측 동일 파일 → 동일 로드.
#
# 격리 설계: 방향정렬(align_factor_direction) 입력인 factor_ic_monthly / factor_registry 는
#   **양측 모두 pin(OLD) 고정** → 유일 변동 입력 = 월별 factor DB Z_Score. (§7 vintage pinning)
#
# metric_type = "canonical_screen" (proxy 손계산 없음 — build_benchmark_compare 경유,
#   calmar/CAGR/MDD = PerformanceAnalytics 표준 함수, oos_retention = approx 라벨)

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(xts); library(PerformanceAnalytics)
})
QM <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(QM)
OUT <- file.path(QM, "stage_artifacts/fy2025_rebuild_20260726")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

PIN_TAG  <- "fy2025_rebuild_20260726"
PIN_DIR  <- file.path(QM, ".cache", "pins", PIN_TAG)
SCRATCH  <- file.path(Sys.getenv("TEMP", tempdir()), "fy2025_ab_olddb")
AFFECTED <- c("202603", "202604", "202605", "202606", "202607")

# OLD 월파일을 scratch 로 복사 (pin 디렉토리에 ic_direction_cache 부산물 쓰기 방지)
dir.create(SCRATCH, recursive = TRUE, showWarnings = FALSE)
for (ym in AFFECTED) {
  f <- sprintf("factor_db_%s.parquet", ym)
  if (!file.exists(file.path(SCRATCH, f)))
    stopifnot(file.copy(file.path(PIN_DIR, f), file.path(SCRATCH, f), overwrite = TRUE))
}
cat("[setup] OLD scratch:", SCRATCH, "|", length(list.files(SCRATCH, pattern="parquet$")), "files\n")

source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/ramp/factor_validation.R")

LIVE_FDB <- FACTOR_DB_DIR                      # NEW (재빌드된 canonical)
# ★ 방향정렬 입력 고정 — 양측 동일 (OLD vintage)
FACTOR_IC_MONTHLY_PATH <- file.path(PIN_DIR, "factor_ic_monthly.parquet")
stopifnot(file.exists(FACTOR_IC_MONTHLY_PATH))
cat("[setup] IC (both sides, pinned OLD):", FACTOR_IC_MONTHLY_PATH, "\n")

# 대표 5종 = DART 전용 27 Item 소비 registry 19엔트리 중 family 분산 + coverage 스펙트럼
FACTORS5 <- c("Q08_Composite_Quality",   # quality  · cov 2947 (최고)
              "AC10_Pct_Accruals",       # accrual  · cov 2468
              "GR05_ROE_Growth",         # growth   · cov 1766
              "V10_FCF_Yield",           # value    · cov 1745
              "V07_EV_EBITDA")           # value/EV · cov 1264 (최저 — 커버리지 계단 최민감)
BOOK3 <- c("Q07_Earnings_Stability", "M08_Residual_Mom", "Q25_Ohlson_O")  # STR_1715 alpha 3팩터
ALLF  <- c(FACTORS5, BOOK3)

# ── RAWDATA month-end panel + forward returns (q4 A/B 하네스와 동일) ──────────
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
univ_dt <- rd_me[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]
cat(sprintf("[panel] months=%d stock-months=%s\n", uniqueN(returns_dt$Date),
            format(nrow(returns_dt), big.mark = ",")))

score_months <- sort(unique(returns_dt$Date))

# ── Z 패널 로더 (C15: load_month_factors 경유 — parquet 직접 read 아님) ────────
load_panel <- function(months, fdb_dir) {
  FACTOR_DB_DIR <<- fdb_dir
  out <- vector("list", length(months))
  for (i in seq_along(months)) {
    d <- months[i]
    z <- tryCatch(load_month_factors(d, factor_names = ALLF), error = function(e) NULL)
    if (is.null(z) || nrow(z) == 0) next
    z[, Date := d]
    out[[i]] <- z
  }
  rbindlist(out[!sapply(out, is.null)])
}

cat("[load] NEW panel (live canonical)...\n")
Z_new <- load_panel(score_months, LIVE_FDB)
Z_new <- merge(Z_new, univ_dt, by = c("Date", "Ticker"))

aff_dates <- score_months[format(score_months, "%Y%m") %in% AFFECTED]
cat(sprintf("[load] OLD panel — %d affected months from pin: %s\n",
            length(aff_dates), paste(format(aff_dates, "%Y-%m"), collapse=", ")))
Z_old_aff <- load_panel(aff_dates, SCRATCH)
Z_old_aff <- merge(Z_old_aff, univ_dt, by = c("Date", "Ticker"))
FACTOR_DB_DIR <<- LIVE_FDB

Z_old <- rbindlist(list(Z_new[!Date %in% aff_dates], Z_old_aff), use.names = TRUE)
setorder(Z_old, Date, Factor_Name, Ticker); setorder(Z_new, Date, Factor_Name, Ticker)

cat(sprintf("[panel] Z_old %s rows / Z_new %s rows | months old=%d new=%d\n",
            format(nrow(Z_old), big.mark=","), format(nrow(Z_new), big.mark=","),
            uniqueN(Z_old$Date), uniqueN(Z_new$Date)))

# ── 위반 주입 통제(sanity): 비영향 월은 양측 bit-동일이어야 함 ────────────────
ctrl <- merge(Z_old[!Date %in% aff_dates, .(Date, Ticker, Factor_Name, zo = Z_Score_Aligned)],
              Z_new[!Date %in% aff_dates, .(Date, Ticker, Factor_Name, zn = Z_Score_Aligned)],
              by = c("Date","Ticker","Factor_Name"), all = TRUE)
ctrl_diff <- ctrl[!(is.na(zo) & is.na(zn)) & (is.na(zo) | is.na(zn) | abs(zo - zn) > 0)]
cat(sprintf("[control] 비영향 월 불일치 행수 = %d (0이어야 정상)\n", nrow(ctrl_diff)))

# ── 커버리지 계단 점검 (작업 7) ──────────────────────────────────────────────
cov_old <- Z_old[!is.na(Z_Score_Aligned), .(n_old = uniqueN(Ticker)), by = .(Date, Factor_Name)]
cov_new <- Z_new[!is.na(Z_Score_Aligned), .(n_new = uniqueN(Ticker)), by = .(Date, Factor_Name)]
cov <- merge(cov_old, cov_new, by = c("Date","Factor_Name"), all = TRUE)
cov[is.na(n_old), n_old := 0L][is.na(n_new), n_new := 0L]
cov[, delta := n_new - n_old]
cov_win <- cov[Date >= as.Date("2025-10-01")][order(Factor_Name, Date)]
cat("\n=== 커버리지 (K200∪KQ150 내 유효 종목수), 2025-10~ ===\n")
print(cov_win, nrows = 200)

# ── 측정 ─────────────────────────────────────────────────────────────────────
make_scores <- function(Z, fn) Z[Factor_Name == fn & !is.na(Z_Score_Aligned),
                                 .(Date, Ticker, score = Z_Score_Aligned)]
make_book <- function(Z) {
  b <- Z[Factor_Name %in% BOOK3 & !is.na(Z_Score_Aligned)]
  comp <- b[, .(score = mean(Z_Score_Aligned), n_avail = .N), by = .(Date, Ticker)]
  comp[n_avail >= 2L, .(Date, Ticker, score)]
}

measure_one <- function(scores, asset_id, label) {
  cs <- canonical_screen_bt(scores, returns_dt[, .(Date, Ticker, Ret_1m)],
                            bench_dt[, .(Date, BM_Ret)],
                            top_n = 25L, cost_bps_oneway = 15,
                            liq_dt = liq_dt[, .(Date, Ticker, adv)], liq_min = 2e8,
                            run_id = sprintf("fy25ab_%s_%s", label, asset_id),
                            strategy_id = asset_id, periods_per_year = 12L,
                            diag_dual_basis = FALSE)
  pr <- cs$period_returns
  if (is.null(pr) || nrow(pr) < 24)
    return(list(asset = asset_id, error = "insufficient months"))
  x_net  <- xts(pr$ret_net, order.by = pr$date)
  active <- pr$ret_net - pr$benchmark_ret
  calmar <- as.numeric(CalmarRatio(x_net, scale = 12))
  cagr   <- as.numeric(Return.annualized(x_net, scale = 12, geometric = TRUE))
  mdd    <- as.numeric(maxDrawdown(x_net))
  oos    <- .canon_oos_rough(active, ppy = 12L)
  p17    <- pr$date >= as.Date("2017-01-01")
  list(asset = asset_id, metric_type = "canonical_screen", n_months = cs$n_months,
       portfolio_alpha_t_nw_lag3 = cs$portfolio_alpha_t_nw_lag3,
       information_ratio = cs$information_ratio,
       alpha_annualized = cs$alpha_annualized,
       net_sr = cs$net_sr, turnover_annual = cs$turnover_annual,
       cagr_net = cagr, mdd_net = mdd, calmar_net = calmar,
       oos_retention_approx = oos,
       oos_note = "anchored 3-split {55/65/75} median approx — gate authority = essence_score.R",
       post2017_t_nw_lag3 = .canon_nw_t(active[p17]),
       hard_gate_snapshot = list(
         port_t_ge_2p95    = isTRUE(cs$portfolio_alpha_t_nw_lag3 >= 2.95),
         oos_approx_ge_0p7 = isTRUE(!is.na(oos) && oos >= 0.7),
         calmar_ge_0p64    = isTRUE(!is.na(calmar) && calmar >= 0.64)))
}

res <- list(old = list(), new = list())
for (fn in FACTORS5) {
  cat(sprintf("[measure] %s ...\n", fn))
  res$old[[fn]] <- measure_one(make_scores(Z_old, fn), fn, "old")
  res$new[[fn]] <- measure_one(make_scores(Z_new, fn), fn, "new")
}
cat("[measure] BOOK_STR1715_composite ...\n")
res$old[["BOOK_STR1715_composite"]] <- measure_one(make_book(Z_old), "BOOK_STR1715_composite", "old")
res$new[["BOOK_STR1715_composite"]] <- measure_one(make_book(Z_new), "BOOK_STR1715_composite", "new")

# ── 판정 tipping 표 ──────────────────────────────────────────────────────────
cat("\n=== A/B (canonical_screen · top-25 EW · 15bps · K200∪KQ150) ===\n")
rows <- list()
for (a in names(res$old)) {
  o <- res$old[[a]]; n <- res$new[[a]]
  if (!is.null(o$error) || !is.null(n$error)) { cat(a, ": ERROR\n"); next }
  tip <- c(
    if (o$hard_gate_snapshot$port_t_ge_2p95    != n$hard_gate_snapshot$port_t_ge_2p95)    "PORT_t",
    if (o$hard_gate_snapshot$oos_approx_ge_0p7 != n$hard_gate_snapshot$oos_approx_ge_0p7) "oos",
    if (o$hard_gate_snapshot$calmar_ge_0p64    != n$hard_gate_snapshot$calmar_ge_0p64)    "calmar")
  rows[[a]] <- data.table(
    asset = a, n_m_old = o$n_months, n_m_new = n$n_months,
    port_t_old = round(o$portfolio_alpha_t_nw_lag3, 4),
    port_t_new = round(n$portfolio_alpha_t_nw_lag3, 4),
    d_port_t   = round(n$portfolio_alpha_t_nw_lag3 - o$portfolio_alpha_t_nw_lag3, 4),
    oos_old = round(o$oos_retention_approx, 4), oos_new = round(n$oos_retention_approx, 4),
    calmar_old = round(o$calmar_net, 4), calmar_new = round(n$calmar_net, 4),
    sr_old = round(o$net_sr, 4), sr_new = round(n$net_sr, 4),
    tipping = if (length(tip)) paste(tip, collapse = "+") else "none")
}
tab <- rbindlist(rows)
print(tab, nrows = 50)
cat(sprintf("\n[TIPPING] HARD 3종 교차 발생 자산 = %d / %d\n",
            sum(tab$tipping != "none"), nrow(tab)))

write_parquet(cov, file.path(OUT, "coverage_old_vs_new.parquet"))
write_json(list(
  meta = list(run = "FY2025 backfill factor DB rebuild A/B",
              created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S KST"),
              pin_tag = PIN_TAG, affected_months = AFFECTED,
              metric_type = "canonical_screen",
              ic_vintage = "pinned OLD (both sides — direction alignment held fixed)",
              control_nonaffected_mismatch_rows = nrow(ctrl_diff),
              factors5 = FACTORS5, book3 = BOOK3),
  ab_table = tab, old = res$old, new = res$new),
  file.path(OUT, "ab_fy2025_result.json"), auto_unbox = TRUE, pretty = TRUE, digits = 8)
cat("\n[saved]", file.path(OUT, "ab_fy2025_result.json"), "\n")
