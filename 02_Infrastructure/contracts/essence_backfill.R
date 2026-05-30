#!/usr/bin/env Rscript
#==============================================================================
# essence_backfill.R — PORT_t 백필 + 본질 재등급 (Dual-Mode SOT §3.5, 옵션 나)
#
# 목적: 구 스키마 bt_result(benchmark_compare에 Portfolio_Alpha_t_NW_lag3 부재)를
#   재백테 없이 재등급. bt_result에 *이미 들어있는* 실현 net 수익률(period_returns)
#   + 벤치마크(benchmark_returns)에 현 build_benchmark_compare()를 재실행 → PORT_t/IR
#   산출 → essence_score() 재등급. 전략 재실행 0 (회귀뿐, OOM 무관).
#
# 정직성: PORT_t는 전략의 *실현 net 시계열*에 계약 회귀(NW lag-3)를 적용한 값 →
#   metric_type=backtested 정당. 단 시계열 출처(legacy 엔진)는 series_source로 기록.
#   DSR은 n_trials 필요 → 미제공 시 NA → 등급 A 불가(B 이하). 추정 금지.
#
# essence_backfill(bt_result, n_trials_cumulative = NULL)
#==============================================================================

suppressPackageStartupMessages({ library(data.table) })

local({
  .here <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) NA)
  root  <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
  src <- function(p) if (file.exists(file.path(root, p))) sys.source(file.path(root, p), envir = globalenv())
  if (!exists("build_benchmark_compare")) src("02_Infrastructure/contracts/backtest_result_contract.R")
  if (!exists("essence_score"))           src("02_Infrastructure/contracts/essence_score.R")
})

essence_backfill <- function(bt_result, n_trials_cumulative = NULL) {
  base <- tryCatch(essence_score(bt_result, n_trials_cumulative), error = function(e) NULL)
  base_grade <- if (is.null(base)) "error" else base$grade

  pr <- tryCatch(as.data.table(bt_result$period_returns),    error = function(e) NULL)
  br <- tryCatch(as.data.table(bt_result$benchmark_returns), error = function(e) NULL)
  has_series <- !is.null(pr) && !is.null(br) &&
    all(c("date", "ret_net") %in% names(pr)) &&
    all(c("date", "benchmark_ret") %in% names(br)) &&
    nrow(pr) >= 12 && nrow(br) >= 12

  if (!has_series) {
    return(list(status = "no_series", base_grade = base_grade, grade = base_grade,
                port_t = NA_real_, net_ir = NA_real_,
                essence = if (is.null(base)) NULL else base$essence))
  }

  freq <- if ("frequency" %in% names(pr)) tolower(as.character(pr$frequency[1])) else "monthly"
  af <- if (grepl("month", freq)) 12 else if (grepl("week", freq)) 52 else if (grepl("day|dai", freq)) 252 else 12
  if (!"benchmark_id" %in% names(br)) br[, benchmark_id := "KOSPI200"]

  bc <- tryCatch(
    build_benchmark_compare(pr, br, run_id = "essence_backfill",
                            strategy_id = "essence_backfill", annualization_factor = af),
    error = function(e) NULL)
  if (is.null(bc) || nrow(bc) == 0) {
    return(list(status = "bc_fail", base_grade = base_grade, grade = base_grade,
                port_t = NA_real_, net_ir = NA_real_, essence = if (is.null(base)) NULL else base$essence))
  }

  bt2 <- bt_result
  bt2$benchmark_compare <- bc
  s <- essence_score(bt2, n_trials_cumulative = n_trials_cumulative)
  list(status = "backfilled", base_grade = base_grade, grade = s$grade,
       port_t = s$essence$portfolio_alpha_t_nw_lag3, net_ir = s$essence$net_ir,
       af = af, essence = s$essence, reasons = s$reasons)
}

# ── CLI: 모든 bt_result.rds 스캔 → 재등급 테이블 ────────────────────────────
if (sys.nframe() == 0) {
  root <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
  files <- list.files(root, pattern = "^bt_result.*\\.rds$", recursive = TRUE, full.names = TRUE)
  files <- files[!grepl("/\\.git/", files)]
  rows <- list()
  for (f in files) {
    r <- tryCatch(readRDS(f), error = function(e) NULL)
    if (is.null(r) || !is.list(r) || is.null(r$metrics)) {
      rows[[length(rows)+1]] <- data.table(file = sub(paste0(root, "/"), "", f),
        status = "load_fail", base_grade = NA, grade = "uncertain", port_t = NA, net_ir = NA); next
    }
    bf <- tryCatch(essence_backfill(r), error = function(e) NULL)
    if (is.null(bf)) {
      rows[[length(rows)+1]] <- data.table(file = sub(paste0(root, "/"), "", f),
        status = "score_err", base_grade = NA, grade = "uncertain", port_t = NA, net_ir = NA); next
    }
    rows[[length(rows)+1]] <- data.table(file = sub(paste0(root, "/"), "", f),
      status = bf$status, base_grade = bf$base_grade, grade = bf$grade,
      port_t = bf$port_t, net_ir = bf$net_ir)
  }
  res <- rbindlist(rows, fill = TRUE)
  out <- file.path(root, "stage_artifacts", "essence_backfill_results.csv")
  fwrite(res, out)
  cat(sprintf("\n[essence_backfill] %d bt_result 스캔 -> %s\n", nrow(res), out))
  cat("\n=== base_grade(백필 전) 분포 ===\n"); print(res[, .N, by = base_grade][order(-N)])
  cat("\n=== grade(백필 후) 분포 ===\n");      print(res[, .N, by = grade][order(-N)])
  cat("\n=== uncertain -> 실등급 전환 (backfilled, base=uncertain) ===\n")
  conv <- res[status == "backfilled" & base_grade == "uncertain" & grade != "uncertain"]
  print(conv[order(-port_t)][, .(file, grade, port_t = round(port_t,3), net_ir = round(net_ir,3))])
  cat(sprintf("\n전환 %d건 / 백필성공 %d건 / 시계열無 %d건\n",
              nrow(conv), nrow(res[status=="backfilled"]), nrow(res[status=="no_series"])))
}
