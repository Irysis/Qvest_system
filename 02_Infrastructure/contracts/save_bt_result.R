## ============================================================================
## save_bt_result.R — Backtest Result Contract v1.0 저장 함수
## RDS + CSV × 10 + JSON × 2
## ============================================================================

suppressMessages({library(data.table); library(jsonlite)})

#' Save complete bt_result to standardized output directory
#' @param bt_result list (10 components)
#' @param output_dir 출력 디렉토리 (예: "04_Research/strategies/STR_XXX/output")
#' @return invisible(list of saved file paths)
save_bt_result <- function(bt_result, output_dir, save_xlsx = TRUE) {
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  saved_files <- list()

  # 1. RDS — R 재사용 원본
  rds_path <- file.path(output_dir, "bt_result.rds")
  saveRDS(bt_result, rds_path)
  saved_files$rds <- rds_path

  # 2. JSON — manifest + strategy_spec (사람용 + 외부 시스템)
  manifest_json_path <- file.path(output_dir, "00_manifest.json")
  jsonlite::write_json(as.list(bt_result$manifest[1, ]),
                        manifest_json_path,
                        auto_unbox = TRUE, pretty = TRUE, na = "null")
  saved_files$manifest_json <- manifest_json_path

  spec_json_path <- file.path(output_dir, "01_strategy_spec.json")
  jsonlite::write_json(as.list(bt_result$strategy_spec[1, ]),
                        spec_json_path,
                        auto_unbox = TRUE, pretty = TRUE, na = "null")
  saved_files$spec_json <- spec_json_path

  # 3. CSV × 10 (manifest + strategy_spec은 JSON에 있으므로 CSV로 동시 저장)
  csv_files <- list(
    "00_manifest.csv"          = bt_result$manifest,
    "01_strategy_spec.csv"     = bt_result$strategy_spec,
    "02_nav.csv"               = bt_result$nav,
    "03_period_returns.csv"    = bt_result$period_returns,
    "04_holdings.csv"          = bt_result$holdings,
    "05_benchmark_returns.csv" = bt_result$benchmark_returns,
    "06_metrics.csv"           = bt_result$metrics,
    "07_benchmark_compare.csv" = bt_result$benchmark_compare,
    "08_rolling_metrics.csv"   = bt_result$rolling_metrics,
    "09_drawdowns.csv"         = bt_result$drawdowns,
    "10_audit.csv"             = bt_result$audit
  )

  for (nm in names(csv_files)) {
    path <- file.path(output_dir, nm)
    dt <- csv_files[[nm]]
    if (!is.null(dt) && nrow(dt) >= 0) {
      fwrite(dt, path)
      saved_files[[nm]] <- path
    }
  }

  # 4. XLSX — 11-sheet report (excel_report_writer.R는 별도 source 필요)
  if (save_xlsx) {
    xlsx_path <- file.path(output_dir, "report.xlsx")
    tryCatch({
      if (!exists("write_excel_report", mode = "function")) {
        contracts_dir <- if (exists("PROJECT_ROOT")) {
          file.path(PROJECT_ROOT, "02_Infrastructure/contracts")
        } else {
          "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure/contracts"
        }
        source(file.path(contracts_dir, "excel_report_writer.R"))
      }
      write_excel_report(bt_result, xlsx_path)
      saved_files$xlsx <- xlsx_path
    }, error = function(e) {
      message(sprintf("[save_bt_result] XLSX skip: %s", conditionMessage(e)))
    })
  }

  cat(sprintf("[save_bt_result] Saved %d files to %s\n", length(saved_files), output_dir))
  invisible(saved_files)
}

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) {
    if (is.null(a) || length(a) == 0) return(b)
    a
  }
}

cat("[save_bt_result.R] Loaded — save_bt_result()\n")
