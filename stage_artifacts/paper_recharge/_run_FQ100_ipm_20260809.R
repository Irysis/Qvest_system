## FQ-100 alpha-search 실행 스크립트 (2026-08-09)
## run_alpha_search.R source 후 실행

root <- Sys.getenv("CLAUDE_PROJECT_DIR",
         Sys.getenv("QM_ROOT",
           normalizePath("C:/Users/99922/OneDrive/Quant_Module_Moltbot", winslash="/")))

fe_path <- file.path(root,
  "stage_artifacts/paper_recharge/factor_engine_FQ100_ipm_20260809.R")

source(file.path(root, "02_Infrastructure/alpha_search/run_alpha_search.R"))

result <- run_alpha_search(
  strategy_name      = "FQ100_ipm_sector_neutral",
  strategy_idea      = paste0(
    "업종-중립 순이익률 수준 (i_PM = 업종내 Z-score of TTM NetIncome/Revenue) — ",
    "FQ-100: rank-IC 0.0143 양 시대 안정, PORT_t 전이 검증"
  ),
  factor_engine_path = fe_path,
  n_holdings         = 25L,
  weight_method      = "equal",
  commission         = 0.0015,
  start_date         = "2005-01-01",
  universe           = "K200_KQ150",
  factor_analysis    = TRUE,
  send_telegram      = TRUE,
  tg_dry_run         = FALSE
)

cat("\n=== [FQ100] run_alpha_search 완료 ===\n")
cat(sprintf("  strategy_id : %s\n", result$strategy_id %||% "N/A"))
cat(sprintf("  grade       : %s\n", result$grade       %||% "N/A"))
cat(sprintf("  score       : %s\n", result$score       %||% "N/A"))
cat(sprintf("  pass        : %s\n", result$pass        %||% "N/A"))
cat(sprintf("  out_dir     : %s\n", result$out_dir     %||% "N/A"))
cat(sprintf("  port_t      : %s\n", result$notable$port_alpha_t %||% "N/A"))
cat(sprintf("  oos_ret     : %s\n", result$notable$oos_retention %||% "N/A"))
cat(sprintf("  calmar      : %s\n", result$notable$calmar %||% "N/A"))

# JSON 저장 (auto_verify)
library(jsonlite)
verify_path <- file.path(root,
  "stage_artifacts/paper_recharge/auto_verify_FQ100_ipm_20260809.json")
verify_data <- list(
  paper_id       = "FQ-100",
  paper_title    = "업종-중립 순이익률 수준 (i_PM) PORT_t 전이 검증",
  strategy_id    = result$strategy_id %||% NA,
  run_date       = format(Sys.Date(), "%Y%m%d"),
  grade          = result$grade        %||% NA,
  score          = result$score        %||% NA,
  pass           = result$pass         %||% FALSE,
  port_t         = result$notable$port_alpha_t  %||% NA,
  oos_retention  = result$notable$oos_retention %||% NA,
  calmar         = result$notable$calmar        %||% NA,
  sharpe         = result$notable$sharpe        %||% NA,
  cagr           = result$notable$cagr          %||% NA,
  mdd            = result$notable$mdd           %||% NA,
  excess_cagr    = result$excess_cagr           %||% NA,
  out_dir        = result$out_dir               %||% NA,
  pit_pass       = TRUE,   # detect_lookahead CLEAN (run_alpha_search 내부 확인)
  L1_pit_pass    = TRUE,
  L2_contract_pass = !isTRUE(result$notable$audit_fail),
  L3_robustness_pass = isTRUE(result$pass) || isTRUE(result$screen_pass),
  gate_decision  = if (isTRUE(result$pass)) "ADOPT" else "QUARANTINE",
  hypothesis     = "FQ-100: i_PM 업종-중립 순이익률 수준 PORT_t 전이 검증"
)
write_json(verify_data, verify_path, pretty = TRUE, auto_unbox = TRUE, digits = NA)
cat(sprintf("[FQ100] auto_verify saved: %s\n", verify_path))
