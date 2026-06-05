## ============================================================================
## factor_rotation_registry.R — FR_XXXX 운용체계 등급 카탈로그 writer.
## STR(개별 모듈)과 분리된 *운용체계* 레지스트리: {module pool + regime engine ver + 배분정책 + 등급}.
## register_fr_result(fr) → upsert 06_Registry/factor_rotation_registry.json (fr_id 중복=update).
## ★실측-only: fr$metric_type=backtested(build_bt_result) 아니면 등재 거부(dispatch_measurement_gate 정합).
## 발효 2026-06-05. registry_writer.R 패턴.
## ============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||(length(a)==1&&is.na(a))) b else a
.FRR_ROOT <- function() if(exists("PROJECT_ROOT")) get("PROJECT_ROOT") else Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT","G:/Quant_Module_Moltbot"))
FR_REGISTRY_PATH <- file.path(.FRR_ROOT(), "06_Registry", "factor_rotation_registry.json")

#' Register an FR operational system into the FR registry.
#' @param fr list (run_wf_ensemble 산출): fr_id, grade, metric_type, essence(list), module_pool, n_trials_cumulative, ...
#' @param regime_engine_version 사용 레짐엔진 버전 라벨
#' @param allocation_policy 배분정책 라벨 (예 "module_dispatcher rp+IR shrink + RCMA")
register_fr_result <- function(fr, regime_engine_version = "unified_regime_signal_daily Category(t-1)",
                               allocation_policy = "module_dispatcher rp+IR shrink + RCMA admitted",
                               path = FR_REGISTRY_PATH) {
  stopifnot(!is.null(fr$fr_id))
  mtype <- fr$metric_type %||% "unknown"
  if (!identical(mtype, "backtested")) {
    cat(sprintf("[factor_rotation_registry] BLOCK — fr_id=%s metric_type=%s (backtested 아님). 실측-only 위반, 등재 거부.\n", fr$fr_id, mtype))
    return(invisible(list(blocked = TRUE, reason = "metric_type != backtested")))
  }
  es <- fr$essence %||% list()
  entry <- list(
    fr_id = fr$fr_id, grade = fr$grade %||% "F", metric_type = mtype,
    essence = list(
      net_sharpe = es$net_sharpe %||% fr$net_sharpe %||% NA,
      portfolio_alpha_t_nw_lag3 = es$portfolio_alpha_t_nw_lag3 %||% fr$port_t %||% NA,
      dsr = es$dsr %||% fr$dsr %||% NA, oos_retention = fr$oos_retention %||% es$oos_retention %||% NA,
      calmar = es$calmar %||% NA, cagr = es$cagr %||% NA, mdd = es$mdd %||% NA),
    n_modules = fr$n_modules %||% NA, module_pool = fr$module_pool %||% list(),
    n_trials_cumulative = fr$n_trials_cumulative %||% NA,
    regime_engine_version = regime_engine_version, allocation_policy = allocation_policy,
    date_range = fr$date_range %||% NA, registered_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S+09:00"))

  reg <- if (file.exists(path)) tryCatch(fromJSON(path, simplifyVector = FALSE), error = function(e) NULL) else NULL
  if (is.null(reg) || is.null(reg$factor_rotations)) reg <- list(
    schema_version = "v1.0",
    note = "FR_XXXX 운용체계 등급 카탈로그(STR 모듈과 분리). register_fr_result() 적재. 실측-only. governor admit은 수동.",
    factor_rotations = list())
  reg$factor_rotations[[fr$fr_id]] <- entry
  reg$last_updated <- entry$registered_at; reg$n_fr <- length(reg$factor_rotations)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write_json(reg, path, auto_unbox = TRUE, pretty = TRUE, na = "null", digits = 4)
  cat(sprintf("[factor_rotation_registry] %s (grade=%s, SR=%s) 등재 → factor_rotation_registry.json (n=%d)\n",
              fr$fr_id, entry$grade, as.character(entry$essence$net_sharpe), reg$n_fr))
  invisible(list(blocked = FALSE, entry = entry, n_fr = reg$n_fr))
}

cat("[factor_rotation_registry.R] Loaded — register_fr_result(fr, ...)\n")
