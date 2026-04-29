## ============================================================================
## audit_bt_result.R — Backtest Result Contract v1.0 audit (10 checks)
## L3 hard block trigger: Critical FAIL 시 metrics is_official=FALSE 강제
## Lawbook §20
## ============================================================================

suppressMessages({library(data.table)})

#' Audit bt_result — 10 checks
#' @param bt_result list (10 components)
#' @return bt_result with audit table populated AND metrics is_official adjusted
audit_bt_result <- function(bt_result) {
  audit_rows <- list()
  add_check <- function(group, name, status, details, affected = "", severity = "low") {
    audit_rows[[length(audit_rows) + 1]] <<- data.table(
      run_id = bt_result$manifest$run_id[1],
      check_group = group, check_name = name, status = status,
      details = details, affected_metrics = affected, severity = severity
    )
  }

  # Check 1: realized_return_vector_exists
  pr <- bt_result$period_returns
  if (is.null(pr) || nrow(pr) == 0 || !"ret_net" %in% names(pr) ||
      all(is.na(pr$ret_net))) {
    add_check("return", "realized_return_vector_exists", "FAIL",
              "period_returns$ret_net 부재 또는 모두 NA",
              "Sharpe,Sortino,CVaR,WinRate", "critical")
  } else {
    add_check("return", "realized_return_vector_exists", "PASS",
              sprintf("n=%d ret_net obs", nrow(pr)), "", "low")
  }

  # Check 2: nav_path_exists
  nav <- bt_result$nav
  if (is.null(nav) || nrow(nav) == 0 || !"nav_net" %in% names(nav)) {
    add_check("nav", "nav_path_exists", "FAIL",
              "nav$nav_net 부재", "CAGR,MDD,Calmar", "critical")
  } else {
    add_check("nav", "nav_path_exists", "PASS",
              sprintf("n=%d nav obs", nrow(nav)), "", "low")
  }

  # Check 3: rebalance_path_executed
  hd <- bt_result$holdings
  if (is.null(hd) || nrow(hd) == 0) {
    add_check("rebalance", "rebalance_path_executed", "WARN",
              "holdings 부재 — turnover NA", "Turnover", "medium")
  } else {
    n_dates <- uniqueN(hd$date)
    if (n_dates < 2) {
      add_check("rebalance", "rebalance_path_executed", "WARN",
                sprintf("holdings 단일 시점 (n=%d)", n_dates),
                "Turnover", "medium")
    } else {
      add_check("rebalance", "rebalance_path_executed", "PASS",
                sprintf("%d rebalance dates", n_dates), "", "low")
    }
  }

  # Check 4: transaction_cost_param_recorded
  cb <- bt_result$manifest$transaction_cost_bps
  if (is.null(cb) || is.na(cb) || cb == 0) {
    add_check("cost", "transaction_cost_param_recorded", "WARN",
              "manifest$transaction_cost_bps 부재 또는 0 — gross == net 가능",
              "Cost reproducibility", "medium")
  } else {
    add_check("cost", "transaction_cost_param_recorded", "PASS",
              sprintf("commission_bps=%s", cb), "", "low")
  }

  # Check 5: benchmark_aligned
  bm <- bt_result$benchmark_returns
  if (is.null(bm) || nrow(bm) == 0) {
    add_check("benchmark", "benchmark_aligned", "WARN",
              "benchmark_returns 부재", "IR,Beta,Alpha", "medium")
  } else {
    common_dates <- intersect(pr$date, bm$date)
    if (length(common_dates) < min(nrow(pr), nrow(bm)) * 0.9) {
      add_check("benchmark", "benchmark_aligned", "WARN",
                sprintf("date alignment %d / %d (90%% 미달)",
                        length(common_dates), min(nrow(pr), nrow(bm))),
                "IR,Beta,Alpha", "medium")
    } else {
      add_check("benchmark", "benchmark_aligned", "PASS",
                sprintf("alignment %d dates", length(common_dates)), "", "low")
    }
  }

  # Check 6: risk_free_rate_defined
  rf_src <- bt_result$manifest$risk_free_rate_source
  if (is.null(rf_src) || is.na(rf_src) || rf_src == "") {
    add_check("rf", "risk_free_rate_defined", "WARN",
              "manifest$risk_free_rate_source 부재",
              "Sharpe,Sortino,IR", "medium")
  } else {
    add_check("rf", "risk_free_rate_defined", "PASS",
              sprintf("source=%s", rf_src), "", "low")
  }

  # Check 7: point_in_time_checked
  spec <- bt_result$strategy_spec
  lp <- spec$lookahead_prevention
  if (is.null(lp) || is.na(lp) || lp == "") {
    add_check("PIT", "point_in_time_checked", "FAIL",
              "strategy_spec$lookahead_prevention 부재 (PIT 검증 방식 명시 필요)",
              "All metrics", "high")
  } else {
    add_check("PIT", "point_in_time_checked", "PASS",
              sprintf("lookahead_prevention=%s", lp), "", "low")
  }

  # Check 8: lookahead_bias_checked (PIT C1~C15 명시 또는 기본 통과)
  lp_str <- as.character(lp)
  c_ref_pattern <- grepl("C\\d+", lp_str)
  if (!is.na(c_ref_pattern) && c_ref_pattern) {
    add_check("PIT", "lookahead_bias_checked", "PASS",
              "C1-C15 reference 명시", "", "low")
  } else {
    add_check("PIT", "lookahead_bias_checked", "WARN",
              "C1-C15 명시적 reference 부재", "All metrics", "medium")
  }

  # Check 9: survivorship_bias_checked
  sbc <- spec$survivorship_bias_control
  if (is.null(sbc) || is.na(sbc) || sbc == "") {
    add_check("data", "survivorship_bias_checked", "WARN",
              "strategy_spec$survivorship_bias_control 부재",
              "All metrics", "medium")
  } else {
    add_check("data", "survivorship_bias_checked", "PASS",
              sprintf("control=%s", sbc), "", "low")
  }

  # Check 10: estimated_metrics_separated_from_backtested
  m <- bt_result$metrics
  if (is.null(m) || nrow(m) == 0 || !"metric_type" %in% names(m)) {
    add_check("metric", "estimated_metrics_separated_from_backtested", "FAIL",
              "metrics$metric_type 컬럼 부재",
              "official metrics", "critical")
  } else {
    invalid <- setdiff(unique(m$metric_type),
                       c("backtested", "estimated", "proxy", "unavailable"))
    if (length(invalid) > 0) {
      add_check("metric", "estimated_metrics_separated_from_backtested", "FAIL",
                sprintf("invalid metric_type: %s", paste(invalid, collapse = ",")),
                "official metrics", "critical")
    } else {
      add_check("metric", "estimated_metrics_separated_from_backtested", "PASS",
                sprintf("metric_type 유효: %s",
                        paste(unique(m$metric_type), collapse = ",")), "", "low")
    }
  }

  audit_tbl <- rbindlist(audit_rows, use.names = TRUE, fill = TRUE)
  bt_result$audit <- audit_tbl

  # Critical FAIL 시 official metrics 차단
  critical_fails <- audit_tbl[severity == "critical" & status == "FAIL"]
  if (nrow(critical_fails) > 0) {
    cat(sprintf("[audit_bt_result] %d critical FAILs — disabling official metrics\n",
                nrow(critical_fails)))
    if (!is.null(bt_result$metrics) && nrow(bt_result$metrics) > 0) {
      affected_metrics_str <- paste(critical_fails$affected_metrics, collapse = ",")
      affected_list <- unlist(strsplit(affected_metrics_str, "[,\\s]+"))
      affected_list <- affected_list[nchar(affected_list) > 0]
      bt_result$metrics[metric_name %in% affected_list, `:=`(
        is_official = FALSE,
        metric_type = "unavailable"
      )]
    }
    bt_result$manifest[, integrity_status := "FAIL"]
  } else if (nrow(audit_tbl[status == "FAIL"]) > 0) {
    bt_result$manifest[, integrity_status := "WARNING"]
  } else if (nrow(audit_tbl[status == "WARN"]) > 0) {
    bt_result$manifest[, integrity_status := "WARNING"]
  } else {
    bt_result$manifest[, integrity_status := "PASS"]
  }

  cat(sprintf("[audit_bt_result] Audit complete — %d checks | PASS=%d FAIL=%d WARN=%d | integrity=%s\n",
              nrow(audit_tbl),
              nrow(audit_tbl[status == "PASS"]),
              nrow(audit_tbl[status == "FAIL"]),
              nrow(audit_tbl[status == "WARN"]),
              bt_result$manifest$integrity_status[1]))

  bt_result
}

cat("[audit_bt_result.R] Loaded — audit_bt_result() (10 checks, L3 trigger)\n")
