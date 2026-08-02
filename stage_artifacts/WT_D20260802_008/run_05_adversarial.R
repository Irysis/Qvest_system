## run_05_adversarial.R — Self-Adversarial Challenge 실측 (v8.2)
##   C-A: 정수 동률 분할 임의성 — 경계 동률 규모 + 티커역순 동률처리 재측정
##   C-B: as-of 스테일 창(30d) 민감도 — 60d 재측정
##   C-C: 원천 관측 밀도 (30d 창이 실제로 물리는 달)
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
setDTthreads(2); try(arrow::set_io_thread_count(2), silent = TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
TD <- "stage_artifacts/WT_D20260802_008"
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

SI   <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
fwd  <- as.data.table(SI$fwd_ret); bench <- as.data.table(SI$bench); liqf <- as.data.table(SI$liqf)
SIZE <- as.data.table(SI$SIZE)
BASE <- as.data.table(read_parquet(file.path(TD, "cov_panel.parquet")))
BASE[, Date := as.Date(Date)]
LIQ_MIN <- 2e8; TOPN <- 25L; COST <- 15

half <- function(dt, var, desc = TRUE) {
  d <- copy(dt)
  d[, .r := frank(if (desc) -get(var) else get(var), ties.method = "first"), by = Date]
  d[, .n := .N, by = Date]
  out <- d[.r <= ceiling(.n / 2)]
  out[, c(".r", ".n") := NULL][]
}
run_arm <- function(nm, dt) {
  r <- canonical_screen_bt(dt[, .(Date, Ticker, score)], fwd, bench, top_n = TOPN,
                           cost_bps_oneway = COST, liq_dt = liqf, liq_min = LIQ_MIN,
                           size_dt = SIZE, run_id = paste0("fq084np2_adv_", nm),
                           strategy_id = paste0("FQ084NP2_ADV_", nm), diag_dual_basis = FALSE)
  r$portfolio_alpha_t_nw_lag3
}

## C-A1: 경계 동률 규모 — 월별 컷 값과 동률 종목 수
setorder(BASE, Date, Ticker)
tie <- BASE[, {
  n <- .N; k <- ceiling(n / 2)
  v <- sort(cov_l0, decreasing = TRUE)
  cutv <- v[k]
  .(cut_val = cutv, n_at_cut = sum(cov_l0 == cutv), n = n)
}, by = Date]
cat(sprintf("[C-A1] 경계 동률: 컷값 중앙값=%.0f  동률 종목수 평균=%.1f (전체의 %.1f%%)  동률>10 인 달=%d/268\n",
            median(tie$cut_val), mean(tie$n_at_cut), 100 * mean(tie$n_at_cut / tie$n), sum(tie$n_at_cut > 10), nrow(tie)))

## C-A2: 티커 역순 동률 처리 재측정
BASEr <- copy(BASE); setorder(BASEr, Date, -Ticker)
t_rev <- run_arm("B_cov_tierev", half(BASEr, "cov_l0", TRUE))
cat(sprintf("[C-A2] B_cov 티커역순 동률판 PORT_t = %+.3f (원판 +3.922, 차이 = %+.3f)\n", t_rev, t_rev - 3.921785))

## C-B: as-of 60d 창 재구축 + 재측정
cov <- as.data.table(read_parquet(".cache/consensus/coverage.parquet"))
cov[, Date := as.Date(Date)]; setkey(cov, Ticker, Date)
KEY <- unique(BASE[, .(Date, Ticker)])
qq <- KEY[, .(Ticker, Date)]
j <- cov[qq, on = .(Ticker, Date), roll = 60]
stopifnot(nrow(j) == nrow(KEY), identical(j$Ticker, qq$Ticker))
K60 <- copy(KEY)[, cov60 := fifelse(is.na(j$coverage), 0, j$coverage)]
B60 <- merge(BASE, K60, by = c("Date", "Ticker"))
setorder(B60, Date, Ticker)
agree <- mean((B60$cov_l0 == 0) == (B60$cov60 == 0))
t_60 <- run_arm("B_cov_60d", half(B60, "cov60", TRUE))
cat(sprintf("[C-B] 60d 창: cov0 일치율=%.4f  B_cov(60d) PORT_t = %+.3f (30d 판 +3.922)\n", agree, t_60))

## C-C: 원천 관측 밀도 — d0 시점 30일 창 내 관측일 수 (창이 물리는 달 식별)
dts <- sort(unique(cov$Date))
d0s <- sort(unique(BASE$Date))
dens <- data.table(d0 = d0s)
dens[, n_obs_30d := sapply(d0, function(x) sum(dts > x - 30 & dts <= x))]
cat(sprintf("[C-C] d0 기준 직전 30일 원천 관측일: min=%d q05=%.0f med=%.0f | <5일인 d0 = %d/268\n",
            min(dens$n_obs_30d), quantile(dens$n_obs_30d, .05), median(dens$n_obs_30d), sum(dens$n_obs_30d < 5)))
print(dens[n_obs_30d < 5])

adv <- list(tie_cut_median = median(tie$cut_val), tie_at_cut_mean = mean(tie$n_at_cut),
            tie_share_mean = mean(tie$n_at_cut / tie$n), tie_gt10_months = sum(tie$n_at_cut > 10),
            port_t_tierev = t_rev, port_t_60d = t_60, cov0_agree_30_60 = agree,
            d0_obs30_min = min(dens$n_obs_30d), d0_obs30_lt5 = sum(dens$n_obs_30d < 5),
            d0_low_density = dens[n_obs_30d < 5])
saveRDS(adv, file.path(TD, "adversarial.rds"))
write_json(adv, file.path(TD, "adversarial.json"), auto_unbox = TRUE, pretty = TRUE, digits = 6)
cat("[SAVED] adversarial.rds / adversarial.json\n[DONE]\n")
