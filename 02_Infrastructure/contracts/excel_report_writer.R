## ============================================================================
## excel_report_writer.R — 11-sheet Excel report writer
## Lawbook §21 (cost / trades sheet 제외)
## ============================================================================

suppressMessages({library(openxlsx); library(data.table)})

#' Write 11-sheet Excel report
#' @param bt_result list (validated, audited)
#' @param xlsx_path output path
write_excel_report <- function(bt_result, xlsx_path) {
  wb <- createWorkbook()

  # Header style
  hs <- createStyle(textDecoration = "bold", fgFill = "#4472C4",
                    fontColour = "white", halign = "center")

  add_sheet <- function(name, dt, freeze_first_row = TRUE) {
    if (is.null(dt) || nrow(dt) == 0) {
      dt <- data.table(note = "(no data)")
    }
    addWorksheet(wb, name)
    writeData(wb, name, dt, headerStyle = hs)
    if (freeze_first_row) freezePane(wb, name, firstRow = TRUE)
    setColWidths(wb, name, cols = 1:ncol(dt), widths = "auto")
  }

  # 00_Run_Summary (manifest transposed for readability)
  manifest_dt <- bt_result$manifest
  if (!is.null(manifest_dt) && nrow(manifest_dt) > 0) {
    run_summary <- data.table(
      Field = names(manifest_dt),
      Value = as.character(unlist(manifest_dt[1, ]))
    )
    add_sheet("00_Run_Summary", run_summary)
  }

  # 01_Performance_Summary (official metrics 만, wide format)
  m <- bt_result$metrics
  if (!is.null(m) && nrow(m) > 0) {
    official <- m[is_official == TRUE & metric_type == "backtested",
                  .(metric_group, metric_name, metric_value, metric_unit,
                    observation_count, calculation_method)]
    add_sheet("01_Performance_Summary", official)
  } else {
    add_sheet("01_Performance_Summary", NULL)
  }

  # 02_Benchmark_Compare
  add_sheet("02_Benchmark_Compare", bt_result$benchmark_compare)

  # 03_NAV
  add_sheet("03_NAV", bt_result$nav)

  # 04_Period_Returns
  add_sheet("04_Period_Returns", bt_result$period_returns)

  # 05_Monthly_Returns matrix (year × month)
  pr <- bt_result$period_returns
  if (!is.null(pr) && nrow(pr) > 0 && "ret_net" %in% names(pr)) {
    pr_copy <- copy(pr)
    pr_copy[, year := format(date, "%Y")]
    pr_copy[, month := as.integer(format(date, "%m"))]
    monthly_compound <- pr_copy[, .(ret = prod(1 + ret_net) - 1),
                                  by = .(year, month)]
    monthly_matrix <- dcast(monthly_compound, year ~ month,
                             value.var = "ret", fill = 0)
    setnames(monthly_matrix, c("year",
                                paste0("M", sprintf("%02d", 1:12))[
                                  as.integer(setdiff(names(monthly_matrix), "year"))]))
    add_sheet("05_Monthly_Returns", monthly_matrix)
  } else {
    add_sheet("05_Monthly_Returns", NULL)
  }

  # 06_Rolling_Metrics
  add_sheet("06_Rolling_Metrics", bt_result$rolling_metrics)

  # 07_Drawdowns
  add_sheet("07_Drawdowns", bt_result$drawdowns)

  # 08_Holdings
  add_sheet("08_Holdings", bt_result$holdings)

  # 09_Exposure (period_returns의 cash_weight, leverage, n_holdings 추출)
  if (!is.null(pr) && nrow(pr) > 0) {
    exposure_cols <- intersect(c("date", "cash_weight", "leverage", "n_holdings", "turnover"),
                                names(pr))
    add_sheet("09_Exposure", pr[, ..exposure_cols])
  } else {
    add_sheet("09_Exposure", NULL)
  }

  # 10_Audit
  add_sheet("10_Audit", bt_result$audit)

  # 11_Notes (Contract reference + caveats)
  notes_dt <- data.table(
    Field = c("Contract Version", "Lawbook", "AX 정합", "측정 기준",
              "PIT 검증", "자체 합성 금지", "Cost 처리", "Trades 처리"),
    Value = c(
      "Backtest Result Contract v1.0",
      "00_Lawbook/Multi_Agent/backtest_result_contract.md",
      "AX-002 (프로세스 우회 = 미래참조 동급)",
      "Charter v1.4 §12 학술 표준 Sharpe = mean(ER)/sd(ER)*sqrt(N)",
      paste("strategy_spec$lookahead_prevention:",
            bt_result$strategy_spec$lookahead_prevention[1] %||% "N/A"),
      "PerformanceAnalytics 표준 함수만 (prod/cumprod 자체 합성 금지)",
      "백테스트 입력 commission=0.0015 (매수/매도 각 15bps) — ret_net 차감 반영",
      "Qvest 리서치 시스템 — 거래 내역 별도 저장 안 함"
    )
  )
  add_sheet("11_Notes", notes_dt)

  saveWorkbook(wb, xlsx_path, overwrite = TRUE)
  cat(sprintf("[excel_report_writer] Saved: %s (12 sheets)\n", xlsx_path))
  invisible(xlsx_path)
}

`%||%` <- function(a, b) if (!is.null(a)) a else b

cat("[excel_report_writer.R] Loaded — write_excel_report() (11-sheet)\n")
