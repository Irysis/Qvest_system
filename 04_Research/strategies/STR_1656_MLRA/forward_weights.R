## STR_1656_MLRA M05 Forward Weights Wrapper (Phase 1, Plan v1.0 2026-04-29)
##
## STATUS: STUB — full ML inference 인프라 부재
##
## 본 STR_1656_MLRA M05는 XGBoost ML model + DD brake regime + cash overlay 구조.
## 현재 산출물: output/s5_mutations/M05/nav.csv (NAV only, no holdings/weights).
## ticker-level weights schedule을 저장하지 않음 — Phase 1.6 (별도) 작업 필요.
##
## 임시 stub:
##   1. nav.csv 시계열 + tg_send (alert)
##   2. holdings/weights는 manual extraction (s5_phase1_3.R 재실행 후 추가 patch 필요)
##   3. as_of_date forward production은 ML model retrain (S5 phase1) 선행 필요
##
## TODO Phase 1.6:
##   - s5_phase1_3.R 안 ML predict 결과 (xgb_predict)에서 ticker × score 추출 patch
##   - Top-N EW + DD brake regime + cash overlay 적용 후 weights.csv 저장
##   - daily_refresh.sh 에서 매월 ML retrain + predict + production weights

suppressMessages({
  library(data.table); library(jsonlite)
})
options(scipen = 999)

generate_forward_weights_str1656_mlra <- function(
  as_of_date         = NULL,
  apply_mandate_cap  = c("cap_0.20", "no_cap"),
  output_root        = NULL
) {
  apply_mandate_cap <- match.arg(apply_mandate_cap)

  STRAT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
  PROJECT_ROOT <- normalizePath(file.path(STRAT_DIR, "..", "..", ".."))
  if (is.null(output_root)) output_root <- file.path(STRAT_DIR, "production_weights")
  dir.create(output_root, recursive = TRUE, showWarnings = FALSE)

  nav_path <- file.path(STRAT_DIR, "output/s5_mutations/M05/nav.csv")

  manifest <- list(
    strategy_id = "STR_1656_MLRA_M05",
    method = "XGBoost_ML_DD_brake_cash_regime",
    as_of_date = if (is.null(as_of_date)) "PENDING" else as.character(as_of_date),
    mandate = apply_mandate_cap,
    status = "STUB_NOT_IMPLEMENTED",
    available_artifacts = list(
      nav_csv = nav_path,
      nav_csv_exists = file.exists(nav_path),
      ic_timeseries_A = file.path(STRAT_DIR, "output/ic_timeseries_A.csv"),
      ic_timeseries_B = file.path(STRAT_DIR, "output/ic_timeseries_B.csv")
    ),
    blocker = "weights.csv schedule 자체 미저장. ML predict 결과에서 ticker × score 추출 patch 필요.",
    todo_phase_1_6 = list(
      step_1 = "s5_phase1_3.R XGBoost predict 산출물에서 ticker × score 추출",
      step_2 = "Top-N EW + DD brake regime + cash overlay 적용",
      step_3 = "production_weights/{as_of_date}_weights.csv 저장",
      step_4 = "daily_refresh.sh에서 매월 ML retrain + production"
    ),
    measurement_basis_primary = "forge_realized_share_based",
    notes = "Phase 1 STUB. 실 구현은 Phase 1.6 별도 진행 필요."
  )

  out_path <- file.path(output_root, "stub_status.json")
  write_json(manifest, out_path, pretty = TRUE, auto_unbox = TRUE, null = "null")

  cat("[STR_1656_MLRA] STUB — full implementation pending Phase 1.6\n")
  cat(sprintf("  manifest: %s\n", out_path))
  cat(sprintf("  blocker: %s\n", manifest$blocker))

  invisible(list(manifest = manifest, paths = list(stub = out_path)))
}

if (!interactive() && sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  as_of <- if (length(args) >= 1) args[1] else NULL
  cap_mode <- if (length(args) >= 2) args[2] else "cap_0.20"
  generate_forward_weights_str1656_mlra(as_of_date = as_of, apply_mandate_cap = cap_mode)
}
