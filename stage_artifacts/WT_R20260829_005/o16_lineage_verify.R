setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressPackageStartupMessages({library(jsonlite); library(data.table)})

## ---------- R11 lineage ----------
source("02_Infrastructure/worktask/lineage_utils.R")
lin <- record_package_lineage(
  task_id = "WT-R20260829_005",
  package_type = "optimization_package",
  method_selected = "EW_top25",
  input_file_paths = c(
    "qepm/mailbox/worktask/WT-R20260829_005/alpha_package.json",
    "qepm/mailbox/worktask/WT-R20260829_005/risk_package.json",
    "stage_artifacts/WT_R20260829_005/alpha_scores.parquet",
    "stage_artifacts/WT_R20260829_005/covariance.parquet",
    "stage_artifacts/WT_R20260829_005/benchmark_covariance.parquet",
    "stage_artifacts/WT_R20260829_005/exposure_matrix.parquet",
    "stage_artifacts/WT_R20260829_005/tail_risk.json",
    "stage_artifacts/WT_R20260829_005/period_returns_production.csv"),
  windows = list(schedule = "2005-01-31 .. 2026-07-31 (259 sig_dates)",
                 trailing_second_moment = "rolling 60M, min 24M (optimizer-side PIT input)",
                 sigma_asof = "2023-06-22 .. 2026-07-31 (risk 원본, as-of 보고 전용)"),
  random_seed = 20260829L,
  extra = list(selection_objective = "net_ir", n_methods_compared = 5L,
               weights_csv = "stage_artifacts/WT_R20260829_005/weights.csv",
               schedule_density_ratio = 1.0))
cat("lineage recorded:", !is.null(lin), "\n")

## ---------- R3/P4 challenge review ----------
src <- try(source("02_Infrastructure/worktask/worktask_manager.R"), silent = TRUE)
if (!inherits(src, "try-error") && exists("wt_record_challenge_review")) {
  r <- try(wt_record_challenge_review(task_id = "WT-R20260829_005", from_agent = "optimizer",
        objection = FALSE,
        targets_reviewed = c("alpha_vector","alpha_lower_bound_vector","confidence_vector",
                             "risk_sigma","bound_feasibility","liquidity_floor","turnover_cap")), silent = TRUE)
  cat("challenge_review:", if (inherits(r,"try-error")) paste("ERR", attr(r,"condition")$message) else "OK", "\n")
} else cat("challenge_review: manager unavailable\n")

## ---------- 최종 산출물 검증 (재도출 — 진술 재기술 아님) ----------
P <- "qepm/mailbox/worktask/WT-R20260829_005/optimization_package.json"
pk <- fromJSON(P, simplifyVector = FALSE)
tw <- unlist(pk$target_weights)
cat("\n=== FINAL VERIFY (파일에서 재도출) ===\n")
cat("parse OK | required fields present:",
    all(c("task_id","as_of_date","method_selected","expected_tracking_error") %in% names(pk)), "\n")
cat("optional_v62 present:", all(c("deploy_cutoff","method_shopping_log","weights_csv_ref") %in% names(pk)), "\n")
cat(sprintf("n=%d  sum=%.15f  min=%.6f  max=%.6f\n", length(tw), sum(tw), min(tw), max(tw)))
stopifnot(length(tw) <= 25, abs(sum(tw)-1) < 1e-9, min(tw) >= 0)

wc <- fread("stage_artifacts/WT_R20260829_005/weights.csv")
chk <- wc[, .(n=.N, s=sum(weight), mn=min(weight)), by=sig_date]
cat(sprintf("weights.csv: rows=%d dates=%d  n_max=%d  max|sum-1|=%.2e  min_w=%.6f\n",
    nrow(wc), uniqueN(wc$sig_date), max(chk$n), max(abs(chk$s-1)), min(chk$mn)))
stopifnot(max(chk$n) <= 25, max(abs(chk$s-1)) < 1e-9, min(chk$mn) >= 0)
cat("first col name (훅이 세는 열):", names(wc)[1], "\n")
cat("as-of row count:", nrow(wc[sig_date == max(sig_date)]), "\n")
cat("\nfiles:\n"); for (f in c(P, "stage_artifacts/WT_R20260829_005/weights.csv",
  "stage_artifacts/WT_R20260829_005/weight_method_selected.md",
  "stage_artifacts/WT_R20260829_005/challenge_note_optimizer.md"))
  cat(sprintf("  %-88s %8d bytes\n", f, file.size(f)))
