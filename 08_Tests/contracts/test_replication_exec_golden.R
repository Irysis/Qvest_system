# test_replication_exec_golden.R — 골든 픽스처 재현 (2026-09-24 · 플랜 P0-04 검증 ③④ · P0-03)
#   픽스처 = stage_artifacts/replication/20260921_100007_6876 (22632 promo3 B1_3 liq_price_delay · 2026-09-21 측정 · legacy 규약)
#
# ③ legacy 비트 재현 — 저장된 factors_panel.parquet(측정에 들어간 바로 그 패널) → .rp_build_weights(러너 정의 parse)
#    → run_replication_simulation(exec_price="close_d_legacy") → build_bt_result(러너와 같은 인자) → audit → essence.
#    저장 bt_result.rds 와 ret_net·nav_net·metrics·benchmark 를 identical() 로 대조하고, essence 를 저장
#    authoritative_remeasure.json(3자리)·저장 bt 재채점(전정밀도)과 대조한다.
#    ★엔진은 재실행하지 않는다 — rf_cell_engine.R 이 .cache/rf_base_signal 에 쓰고, FDB 빈티지가 바뀌어 같은 패널이 안 나온다.
#    ★RAWDATA 는 저장 산출의 마지막 날(2026-09-18)에서 자른다(측정 당시 데이터 끝). 과거 행이 개정되면(수정주가 재기준 등)
#      비트 대조가 깨질 수 있다 — 그때는 코드가 아니라 빈티지 문제이며, 이 검사는 max|Δ| 를 함께 출력해 가른다.
# ④ 같은 픽스처의 close_t1 판: 구조 단정만(관측일 = legacy − 1 · 리밸 수 동일 · 비용 기장일 = exec 다음 거래일).
#    계약 경유 수치(essence)는 QVEST_GOLDEN_REPORT_T1=1 일 때 출력만 한다(판정 없음 — 재측정·원장 반영은 P0-05/06).
#    2026-09-24 실측(이 검사 · 현 빈티지): grade B · CAGR .251 · SR 1.060 · MDD .580 · Calmar .433 · PT 3.777 · OOS .117 · IR .827
#    (legacy B · .276 · 1.138 · .551 · .501 · 4.349 · .119 · .952). 소요: legacy 계약 경유 1회 ≈ 3분.
# P0-03 — 첫 행 ret_gross = Rg₁(= ret_net₁ + Σ|w|×15bps) · 이후 행은 저장값과 부동소수 수준 일치 · integrity WARNING 상수 해소.
#
# 쓰기 0 — 운영 원장·.cache·authoritative 파일에 쓰지 않는다(essence sidecar_log=FALSE · save_bt_result 미호출).
# 재료 부재(픽스처·RAWDATA 캐시) = SKIP(미측정 — PASS 아님).
# 실행: Rscript 08_Tests/contracts/test_replication_exec_golden.R

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
root <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(root, "02_Infrastructure", "config.R")))
  root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(root)
suppressPackageStartupMessages({ library(data.table); library(xts); library(PerformanceAnalytics); library(jsonlite); library(arrow) })

pass <- 0L; fail <- 0L; skipped <- 0L
ok <- function(m) { cat(sprintf("  [PASS] %s\n", m)); pass <<- pass + 1L }
ng <- function(m) { cat(sprintf("  [FAIL] %s\n", m)); fail <<- fail + 1L }
sk <- function(m) { cat(sprintf("  [SKIP] %s\n", m)); skipped <<- skipped + 1L }
finish <- function() {
  cat(sprintf("결과: PASS=%d FAIL=%d SKIP=%d\n", pass, fail, skipped))
  cat(sprintf('{"test":"replication_exec_golden","pass":%d,"fail":%d,"total":%d,"skipped":%d}\n', pass, fail, pass + fail, skipped))
  if (fail > 0L) quit(status = 1L)
  quit(status = 0L)
}

GOLD <- "stage_artifacts/replication/20260921_100007_6876"
RAWP <- ".cache/RAWDATA.parquet"; BMP <- ".cache/benchmark.parquet"
ENGINE <- file.path(root, "02_Infrastructure/reinforcement/rf_cell_engine.R")   # 워커가 넘기는 factor_engine_path 와 같은 식
need <- c(file.path(GOLD, c("factors_panel.parquet", "bt_result.rds", "authoritative_remeasure.json", "01_strategy_spec.json")), RAWP, BMP)
if (!all(file.exists(need))) { sk(sprintf("재료 부재: %s", paste(need[!file.exists(need)], collapse = ", "))); finish() }

# ── 정의 적재 (쓰기 없는 것만) ──
bex <- parse("02_Infrastructure/backtest_harness.R", encoding = "UTF-8", keep.source = FALSE)
.def <- function(exprs, nm, env) {
  hit <- Filter(function(e) is.call(e) && identical(as.character(e[[1]]), "<-") && identical(as.character(e[[2]]), nm), as.list(exprs))
  if (length(hit) != 1L) stop(sprintf("정의 %s %d건", nm, length(hit)))
  eval(hit[[1]], envir = env)
}
.def(bex, "get_execution_date", globalenv())                       # 러너가 쓰는 정본 집행일 함수
source("02_Infrastructure/replication/replication_harness.R")
suppressMessages({
  source("02_Infrastructure/contracts/backtest_result_contract.R")
  source("02_Infrastructure/contracts/audit_bt_result.R")
  source("02_Infrastructure/contracts/essence_score.R")
})
rpx <- parse("02_Infrastructure/alpha_search/run_paper_replication.R", encoding = "UTF-8", keep.source = FALSE)
rp <- new.env(parent = globalenv())
rp$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
rp$.RP_NMAX_DEFAULT <- 25L
for (nm in c(".rp_build_weights", ".rp_abs_path", ".rp_strategy_spec")) .def(rpx, nm, rp)

# ── 픽스처 입력 ──
auth <- fromJSON(file.path(GOLD, "authoritative_remeasure.json"), simplifyVector = TRUE)
spec0 <- fromJSON(file.path(GOLD, "01_strategy_spec.json"), simplifyVector = TRUE)
bt0 <- readRDS(file.path(GOLD, "bt_result.rds"))
END <- max(as.Date(bt0$nav$date))
FAC <- as.data.table(read_parquet(file.path(GOLD, "factors_panel.parquet")))
pspec <- list(construction = spec0$construction, n_long = auth$replication$n_max, n_max = auth$replication$n_max,
              weighting = spec0$weight_method, rebalance = spec0$rebalance)       # 워커 portfolio_spec 과 같은 모양
W <- rp$.rp_build_weights(FAC, NULL, pspec)
t0 <- Sys.time()
RAW <- as.data.table(read_parquet(RAWP, col_select = c("Date", "Ticker", "Ret")))
RAW <- RAW[Date <= END]
BM <- as.data.table(read_parquet(BMP, col_select = c("Date", "BM_Ret")))
cat(sprintf("  (RAWDATA %d행 · 끝 %s · 적재 %.1fs)\n", nrow(RAW), END, as.numeric(difftime(Sys.time(), t0, units = "secs"))))

# 비중 = 저장 보유(04_holdings: exec 일자·종목·비중)와 같은가 — 재현 입력 검증
all_d <- sort(unique(RAW$Date))
Wx <- copy(W)[, Exec := as.Date(vapply(Date, function(d) as.numeric(get_execution_date(d, all_d)), numeric(1)))]
H0 <- as.data.table(bt0$holdings)[, .(Exec = as.Date(date), Ticker = ticker, Weight = actual_weight)]
cmpW <- merge(Wx[, .(Exec, Ticker, Weight)], H0, by = c("Exec", "Ticker"), all = TRUE)
if (nrow(cmpW) == nrow(H0) && !anyNA(cmpW) && max(abs(cmpW$Weight.x - cmpW$Weight.y)) < 1e-12)
  ok(sprintf("재현 입력: factors_panel → 비중 = 저장 보유 (%d 리밸 · %d행 · 비중 일치)", uniqueN(H0$Exec), nrow(H0))) else
  ng(sprintf("재현 입력 불일치 — 병합 %d행 · 저장 %d행 · NA %s", nrow(cmpW), nrow(H0), anyNA(cmpW)))

run_all <- function(ep) {
  sim <- run_replication_simulation(copy(RAW), BM, W, commission = 0.0015, start_date = "2005-01-01", exec_price = ep)
  sp <- rp$.rp_strategy_spec(spec0$strategy_name, spec0$strategy_idea, pspec, spec0$universe, sim,
                             spec0$source_paper_url, ENGINE)
  bt <- build_bt_result(sim, sp, run_id = auth$run_id, strategy_id = auth$strategy_id,
                        benchmark_id = "KOSPI200", benchmark_name = "KOSPI 200",
                        transaction_cost_bps = 15, slippage_bps = 0, frequency = "daily", annualization_factor = 252,
                        universe_id = spec0$universe, code_version = "run_paper_replication_v10",
                        created_by_agent = "Replication")
  bt <- audit_bt_result(bt)
  es <- essence_score(bt, n_trials_cumulative = 1L, selection_type = "chain", sidecar_log = FALSE)
  list(sim = sim, bt = bt, es = es)
}
quiet <- function(expr) { out <- NULL; capture.output(out <- suppressWarnings(suppressMessages(expr))); out }
t1 <- Sys.time(); L <- quiet(run_all("close_d_legacy")); tL <- as.numeric(difftime(Sys.time(), t1, units = "secs"))

# ── ③ legacy 비트 재현 ──
pr1 <- L$bt$period_returns; pr0 <- as.data.table(bt0$period_returns)
bit <- c(
  ret_net   = identical(pr1$ret_net, pr0$ret_net) && identical(pr1$date, pr0$date),
  nav_net   = identical(L$bt$nav$nav_net, bt0$nav$nav_net),
  metrics   = identical(L$bt$metrics$metric_value, bt0$metrics$metric_value),
  benchmark = identical(L$bt$benchmark_returns$benchmark_ret, bt0$benchmark_returns$benchmark_ret),
  bench_cmp = identical(L$bt$benchmark_compare$strategy_value, bt0$benchmark_compare$strategy_value))
dmx <- if (nrow(pr1) == nrow(pr0)) max(abs(pr1$ret_net - pr0$ret_net)) else NA_real_
if (all(bit)) ok(sprintf("③ legacy 비트 재현: ret_net·nav_net·metrics·benchmark·benchmark_compare identical (%d일 · %.0fs)", nrow(pr1), tL)) else
  ng(sprintf("③ 비트 불일치 — %s · ret_net max|Δ| %s (빈티지 개정이면 ≤1e-12 수준)",
             paste(names(bit)[!bit], collapse = ","), format(dmx)))
es0 <- quiet(essence_score(bt0, n_trials_cumulative = 1L, selection_type = "chain", sidecar_log = FALSE))
keys <- c("cagr", "net_sharpe", "mdd", "calmar", "portfolio_alpha_t_nw_lag3", "oos_retention", "net_ir")
v1 <- unlist(L$es$essence[keys]); v0 <- unlist(es0$essence[keys]); va <- unlist(auth$essence[keys])
if (identical(v1, v0) && identical(L$es$grade, es0$grade))
  ok(sprintf("③ essence 전정밀도 = 저장 bt 재채점 (grade %s · CAGR %.4f · SR %.4f · MDD %.4f · Calmar %.4f · PT %.4f)",
             L$es$grade, v1["cagr"], v1["net_sharpe"], v1["mdd"], v1["calmar"], v1["portfolio_alpha_t_nw_lag3"])) else
  ng(sprintf("③ essence 불일치 — 재현 %s vs 저장 재채점 %s", paste(signif(v1, 6), collapse = "/"), paste(signif(v0, 6), collapse = "/")))
if (identical(L$es$grade, auth$essence_grade) && all(abs(round(v1, 3) - va) < 1e-9))
  ok(sprintf("③ 저장 authoritative_remeasure.json 과 일치(3자리): grade %s · CAGR %.3f · SR %.3f · MDD %.3f · Calmar %.3f · PT %.3f",
             auth$essence_grade, va["cagr"], va["net_sharpe"], va["mdd"], va["calmar"], va["portfolio_alpha_t_nw_lag3"])) else
  ng(sprintf("③ authoritative 불일치 — %s vs %s", paste(round(v1, 3), collapse = "/"), paste(va, collapse = "/")))

# ── P0-03 (legacy 산출에서) ──
g1 <- pr1$ret_gross; g0 <- pr0$ret_gross
if (abs(g1[1] - (pr1$ret_net[1] + 0.0015)) < 1e-15 && abs(pr1$cost_ret[1] - 0.0015) < 1e-15 && g0[1] == 0)
  ok(sprintf("P0-03 첫 행 복원: ret_gross %.7f(저장 0) · cost_ret %.4f = Σ|w|×15bps(저장 %.7f = −ret_net)",
             g1[1], pr1$cost_ret[1], pr0$cost_ret[1])) else
  ng(sprintf("P0-03 첫 행 — ret_gross %s cost_ret %s", g1[1], pr1$cost_ret[1]))
dg <- max(abs(g1[-1] - g0[-1]))
if (dg < 1e-12) ok(sprintf("P0-03 2행 이후 ret_gross = 저장값(되짚기 경로) 부동소수 수준 max|Δ| %.1e — 등급 입력(ret_net) 불변", dg)) else
  ng(sprintf("P0-03 2행 이후 ret_gross 차 %.3e", dg))
wr <- sort(L$bt$audit[status != "PASS", check_name])
if (identical(L$bt$manifest$integrity_status, "PASS") && !nrow(L$bt$audit[check_name == "cost_sign_nonnegative" & status != "PASS"]))
  ok(sprintf("P0-03 integrity PASS (저장본 WARNING — WARN 4종 해소) · cost_model_version=%s", L$bt$manifest$cost_model_version)) else
  ng(sprintf("P0-03 integrity %s — 비PASS: %s", L$bt$manifest$integrity_status, paste(wr, collapse = ",")))

# ── ④ close_t1 판 — 구조 단정은 항상(sim 만) · 계약 경유 수치는 QVEST_GOLDEN_REPORT_T1=1 일 때만 ──
#   (계약 경유 1회 ≈ 3분 — 배터리 기본 실행에선 legacy 1회만 돈다. 수치 판정은 없다: 보고용.)
t2 <- Sys.time(); simT <- quiet(run_replication_simulation(copy(RAW), BM, W, commission = 0.0015,
                                                            start_date = "2005-01-01", exec_price = "close_t1"))
tT <- as.numeric(difftime(Sys.time(), t2, units = "secs"))
plT <- simT$PORTFOLIO_LOG
nxt <- vapply(plT$Exec_Date, function(d) as.numeric(min(all_d[all_d > d])), numeric(1))
if (NROW(simT$strategy_xts) == NROW(L$sim$strategy_xts) - 1L && nrow(plT) == nrow(L$sim$PORTFOLIO_LOG) &&
    all(as.numeric(plT$Cost_Date) == nxt) && identical(simT$diagnostics$exec_price, "close_t1"))
  ok(sprintf("④ close_t1 구조: 관측 %d일(= legacy − 1) · 리밸 %d · 비용 기장 = exec 다음 거래일 (%.0fs)",
             NROW(simT$strategy_xts), nrow(plT), tT)) else
  ng("④ close_t1 구조 단정 실패")
cat(sprintf("  [INFO] ④ legacy 판   — grade %s · CAGR %.4f · SR %.4f · MDD %.4f · Calmar %.4f · PT %.4f · OOS %.4f · IR %.4f\n",
            L$es$grade, v1["cagr"], v1["net_sharpe"], v1["mdd"], v1["calmar"], v1["portfolio_alpha_t_nw_lag3"],
            v1["oos_retention"], v1["net_ir"]))
if (identical(Sys.getenv("QVEST_GOLDEN_REPORT_T1", "0"), "1")) {
  T1 <- quiet(run_all("close_t1"))
  e <- T1$es$essence
  cat(sprintf("  [INFO] ④ close_t1 판 — grade %s · CAGR %.4f · SR %.4f · MDD %.4f · Calmar %.4f · PT %.4f · OOS %.4f · IR %.4f · integrity %s\n",
              T1$es$grade, e$cagr, e$net_sharpe, e$mdd, e$calmar, e$portfolio_alpha_t_nw_lag3, e$oos_retention, e$net_ir,
              T1$bt$manifest$integrity_status))
} else cat("  [INFO] ④ close_t1 계약 경유 수치는 QVEST_GOLDEN_REPORT_T1=1 로 산출(보고용 · 판정 없음)\n")
finish()
