# test_replication_harness.R — v10 충실구현 하네스의 양방향 검증 (합성 데이터)
#
# 계약 (v10 2026-08-29):
#   ① 롱숏 부호 정확성 — 숏 레그가 하락하면 LS 수익 양(+)
#   ② 비용 실효 — commission>0 이면 NAV_net < NAV_gross
#   ③ PIT t+1 — Exec_Date = 시그널 익월 첫 거래일 (> Signal_Date)
#   ④ 종목수 무제한 — n=60 롱숏 완주 + diagnostics$n_max 정확
#   ⑤ 계약 왕복 — build_bt_result → audit: constraint_profile="replication" 이면
#      holdings_cap 이 n>25 에도 PASS(보고만), 프로파일 없으면 FAIL (양방향)
#   ⑥ L-code enum — paper_replication/reinforcement + RP/RF prefix
#
# 실행: Rscript 08_Tests/contracts/test_replication_harness.R

root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(root)
suppressPackageStartupMessages({
  library(data.table); library(xts); library(PerformanceAnalytics); library(jsonlite)
})

pass <- 0L; fail <- 0L
ok <- function(m) { cat(sprintf("  [PASS] %s\n", m)); pass <<- pass + 1L }
ng <- function(m) { cat(sprintf("  [FAIL] %s\n", m)); fail <<- fail + 1L }

# 실제 t+1 규약과 동일 (backtest_harness.R:316 — 시그널 익월 첫 거래일)
get_execution_date <- function(signal_date, all_dates) {
  ym <- format(signal_date, "%Y-%m")
  yr <- as.integer(substr(ym, 1, 4)); mo <- as.integer(substr(ym, 6, 7))
  if (mo == 12) { yr <- yr + 1; mo <- 1 } else { mo <- mo + 1 }
  cands <- all_dates[all_dates >= as.Date(sprintf("%04d-%02d-01", yr, mo))]
  if (length(cands) > 0) min(cands) else NA
}

source("02_Infrastructure/replication/replication_harness.R")

# ── 합성 데이터: 2020-01 ~ 2020-06, 평일만. UP 종목 +0.2%/일, DN 종목 −0.2%/일 ──
mk_raw <- function(n_up, n_dn) {
  dates <- seq(as.Date("2020-01-01"), as.Date("2020-06-30"), by = "day")
  dates <- dates[!format(dates, "%u") %in% c("6", "7")]
  tick <- c(sprintf("UP%03d", seq_len(n_up)), sprintf("DN%03d", seq_len(n_dn)))
  g <- CJ(Date = dates, Ticker = tick)
  g[, Ret := ifelse(grepl("^UP", Ticker), 0.002, -0.002)]
  g[, Close := 100 * cumprod(1 + Ret), by = Ticker]
  g
}
RAW <- mk_raw(3, 3)
BM <- unique(RAW[, .(Date)])[, BM_Ret := 0.0001][]
all_d <- sort(unique(RAW$Date))
sig_d <- as.Date(c("2020-01-31", "2020-02-29", "2020-03-31", "2020-04-30"))
sig_d <- as.Date(sapply(sig_d, function(d) max(all_d[format(all_d, "%Y-%m") == format(d, "%Y-%m")])))

# ① 롱숏: long UP, short DN → 양(+) 수익
W_LS <- rbindlist(lapply(sig_d, function(d) data.table(
  Date = d,
  Ticker = c("UP001", "UP002", "DN001", "DN002"),
  Weight = c(0.5, 0.5, -0.5, -0.5))))
sim <- run_replication_simulation(copy(RAW), copy(BM), W_LS, commission = 0)
tot <- as.numeric(last(sim$DAILY_NAV_DT$NAV)) - 1
if (is.finite(tot) && tot > 0) ok(sprintf("① 롱숏 부호 — LS 총수익 %+.2f%% > 0", tot * 100)) else
  ng(sprintf("① 롱숏 부호 — 총수익 %+.4f (양수 기대)", tot))
if (any(sim$HOLDINGS_LOG$Leg == "short")) ok("① 숏 레그 HOLDINGS_LOG 기록") else ng("① 숏 레그 기록 부재")

# ② 비용 실효
sim_c <- run_replication_simulation(copy(RAW), copy(BM), W_LS, commission = 0.0015)
nav_net <- as.numeric(last(sim_c$DAILY_NAV_DT$NAV))
nav_gross <- as.numeric(last(sim_c$DAILY_NAV_DT$NAV_gross))
if (nav_net < nav_gross) ok(sprintf("② 비용 실효 — net %.4f < gross %.4f", nav_net, nav_gross)) else
  ng("② 비용이 NAV 에 반영되지 않음")

# ③ t+1 실행
if (all(sim$PORTFOLIO_LOG$Exec_Date > sim$PORTFOLIO_LOG$Signal_Date)) ok("③ Exec > Signal (t+1 규약)") else
  ng("③ Exec_Date <= Signal_Date 존재 — PIT 위반")
exp_exec <- get_execution_date(sig_d[1], all_d)
got_exec <- sim$PORTFOLIO_LOG[Signal_Date == sig_d[1], Exec_Date]
if (identical(as.Date(got_exec), as.Date(exp_exec))) ok("③ Exec = 익월 첫 거래일 (하네스 규약 일치)") else
  ng(sprintf("③ Exec 불일치: %s vs 기대 %s", got_exec, exp_exec))

# ④ n=60 롱숏 완주
RAW60 <- mk_raw(30, 30)
BM60 <- unique(RAW60[, .(Date)])[, BM_Ret := 0.0001][]
W60 <- rbindlist(lapply(sig_d, function(d) data.table(
  Date = d,
  Ticker = c(sprintf("UP%03d", 1:30), sprintf("DN%03d", 1:30)),
  Weight = c(rep(1 / 30, 30), rep(-1 / 30, 30)))))
sim60 <- run_replication_simulation(copy(RAW60), copy(BM60), W60, commission = 0)
if (identical(sim60$diagnostics$n_max, 60L) || sim60$diagnostics$n_max == 60) ok("④ n=60 완주 + n_max=60 (상한 없음 실증)") else
  ng(sprintf("④ n_max=%s (60 기대)", sim60$diagnostics$n_max))

# ⑤ 계약 왕복 — audit holdings_cap 프로파일 양방향
suppressMessages({
  source("02_Infrastructure/contracts/backtest_result_contract.R")
  source("02_Infrastructure/contracts/audit_bt_result.R")
})
spec_rp <- list(strategy_name = "RP_TEST", constraint_profile = "replication",
                weight_method = "ew", rebalance = "monthly")
bt_rp <- build_bt_result(sim60, spec_rp, run_id = "TEST_RP", strategy_id = "RP_TEST",
                         transaction_cost_bps = 0, frequency = "daily",
                         created_by_agent = "test")
bt_rp <- audit_bt_result(bt_rp)
cap_rp <- bt_rp$audit[check_name == "holdings_cap"]
if (nrow(cap_rp) == 1L && cap_rp$status == "PASS" && grepl("replication", cap_rp$detail)) {
  ok("⑤ replication profile: n=60 인데 holdings_cap PASS(보고만)")
} else ng(sprintf("⑤ replication profile 판정 이상: %s", paste(cap_rp$status, collapse = ",")))

spec_no <- list(strategy_name = "NO_PROFILE", weight_method = "ew", rebalance = "monthly")
bt_no <- build_bt_result(sim60, spec_no, run_id = "TEST_NO", strategy_id = "NO_PROFILE",
                         transaction_cost_bps = 0, frequency = "daily",
                         created_by_agent = "test")
bt_no <- audit_bt_result(bt_no)
cap_no <- bt_no$audit[check_name == "holdings_cap"]
if (nrow(cap_no) == 1L && cap_no$status == "FAIL") {
  ok("⑤ 프로파일 부재: n=60 → holdings_cap FAIL (실투형 경로 무변경 — 양방향)")
} else ng(sprintf("⑤ 실투형 경로 판정 이상: %s", paste(cap_no$status, collapse = ",")))

# ⑥ L-code enum
source("02_Infrastructure/axiom/lcode_schema.R")
if (all(c("paper_replication", "reinforcement") %in% LCODE_VALID_MODES)) ok("⑥ LCODE_VALID_MODES 신규 2종") else
  ng("⑥ enum 에 paper_replication/reinforcement 부재")
emit_txt <- paste(readLines("02_Infrastructure/axiom/lcode_emit.R", warn = FALSE, encoding = "UTF-8"), collapse = "\n")
if (grepl('paper_replication = "RP"', emit_txt, fixed = TRUE) &&
    grepl('reinforcement = "RF"', emit_txt, fixed = TRUE)) ok("⑥ RP/RF prefix 배선") else
  ng("⑥ RP/RF prefix 부재")

cat(sprintf("결과: PASS=%d FAIL=%d\n", pass, fail))
if (fail > 0L) quit(status = 1L)
