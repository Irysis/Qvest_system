# driver_valearn70_top25.R — 정책 B: valearn 0.7/0.3 long-only를 N_CAP=25(top-25 운용 baseline)로 재측정
#   - N_CAP=25 → fe_valearn이 월별 N := pmin(25, decile) 마킹 → backtest_harness Dynamic N override(line 834)
#   - 검증 직교 스크리닝(decile, driver_ls_generic, N_CAP 미부여)은 불변 — 본 driver만 N_CAP 설정
#   실행: PowerShell run_in_background, $env:W_V/$env:W_E/$env:N_CAP 선설정 후 Rscript -e source(this)
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot")
source(file.path(PROJ, "02_Infrastructure", "alpha_search", "run_alpha_search.R"))

res <- run_alpha_search(
  strategy_name      = "STR_valearn_70_top25",
  strategy_idea      = "value0.7+earnings-rev0.3 sleeve 위계, 운용 max25 baseline",
  factor_engine_path = file.path(PROJ, "02_Infrastructure", "alpha_search", "fe_valearn.R"),
  start_date         = "2005-01-01",
  universe           = "K200_KQ150",
  factor_analysis    = TRUE,
  send_telegram      = TRUE
)

cat("\n===== [driver_valearn70_top25] run_alpha_search 반환 =====\n")
cat(sprintf("strategy_id = %s\n", res$strategy_id %||% NA))
cat(sprintf("grade(hurdle proxy) = %s | score = %s | pass = %s\n",
            res$grade %||% NA, res$score %||% NA, res$pass %||% NA))
cat(sprintf("excess_cagr = %s | out_dir = %s\n", res$excess_cagr %||% NA, res$out_dir %||% NA))

# ---- essence_score 병행 산출 시도 (measurement-graduation 권위) ----
#   run_alpha_search는 hurdle proxy만 산출 → bt_result 10-component 빌드 후 essence_score 호출.
tryCatch({
  sim_rds <- file.path("04_Research", "strategies", res$strategy_id, "sim_result.rds")
  sim_rds <- file.path(PROJ, sim_rds)
  if (file.exists(sim_rds)) {
    sim <- readRDS(sim_rds)
    source(file.path(PROJ, "02_Infrastructure", "contracts", "backtest_result_contract.R"))
    source(file.path(PROJ, "02_Infrastructure", "contracts", "essence_score.R"))
    sdef <- list(strategy_id = res$strategy_id, strategy_name = "STR_valearn_70_top25",
                 universe = "K200_KQ150", commission = 0.0015)
    btr <- tryCatch(build_bt_result(sim, strategy_spec = sdef), error = function(e) {
      cat("[essence] build_bt_result 예외:", conditionMessage(e), "\n"); NULL })
    if (!is.null(btr)) {
      es <- tryCatch(essence_score(btr), error = function(e) {
        cat("[essence] essence_score 예외:", conditionMessage(e), "\n"); NULL })
      if (!is.null(es)) {
        cat("\n===== [essence_score 병행] =====\n")
        cat(sprintf("essence grade = %s | sharpe = %s | mdd = %s | calmar = %s | net_IR = %s | port_t = %s\n",
                    es$grade %||% NA, es$sharpe %||% NA, es$mdd %||% NA,
                    es$calmar %||% NA, es$net_ir %||% NA, es$port_t %||% NA))
        cat(sprintf("essence full: %s\n", paste(utils::capture.output(str(es)), collapse=" | ")))
      }
    }
  } else {
    cat(sprintf("[essence] sim_result.rds 부재: %s\n", sim_rds))
  }
}, error = function(e) cat("[essence] 병행 산출 생략:", conditionMessage(e), "\n"))

# ---- 종목수 ≤25 확인 ----
tryCatch({
  if (exists("res") && !is.null(res$out_dir)) {
    sim_rds <- file.path(PROJ, "04_Research", "strategies", res$strategy_id, "sim_result.rds")
    if (file.exists(sim_rds)) {
      sim <- readRDS(sim_rds)
      pl <- sim$PORTFOLIO_LOG
      if (!is.null(pl) && "N_stocks" %in% names(pl)) {
        cat(sprintf("\n[종목수 확인] N_stocks max=%d mean=%.1f (목표 <=25)\n",
                    max(pl$N_stocks, na.rm=TRUE), mean(pl$N_stocks, na.rm=TRUE)))
      }
    }
  }
}, error = function(e) cat("[종목수] 확인 생략:", conditionMessage(e), "\n"))

cat("\n===== driver_valearn70_top25 DONE =====\n")
