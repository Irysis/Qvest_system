# 스키마 검증 기록 전용 — 우회하지 않는다. 실패하면 실패 사유를 그대로 적는다.
Sys.setenv(QM_ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- Sys.getenv("QM_ROOT")
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
source(file.path(ROOT, "02_Infrastructure/config.R"))
setwd(ROOT)   # WT_ROOT 가 상대경로라 루트에서 돌려야 한다 (stage dir 에서 돌리면 file_missing 오탐)
source(file.path(ROOT, "02_Infrastructure/worktask/worktask_manager.R"))
WT <- "WT-R20260829_005"
out <- list(probe_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"), task_id = WT)
for (p in c("alpha_package", "risk_package", "optimization_package")) {
  r <- tryCatch(wt_validate_package(WT, p), error = function(e) list(valid = NA, reason = conditionMessage(e)))
  out[[p]] <- r
  cat(sprintf("%-22s valid=%s reason=%s\n", p, as.character(r$valid %||% NA),
              paste(unlist(r[setdiff(names(r), "valid")]), collapse = "; ")))
}
sc <- fromJSON(file.path(ROOT, "02_Infrastructure/worktask/schema.json"), simplifyVector = FALSE)
.req <- sc$definitions$work_task_request$properties
.pat <- .req$task_id$pattern %||% "(pattern 미발견)"
.enum <- unlist(.req$wt_type$enum)
out$schema_gap <- list(
  schema_path = "02_Infrastructure/worktask/schema.json :: definitions.work_task_request",
  task_id_pattern = .pat,
  task_id_matches_v10 = isTRUE(grepl(.pat, WT)),
  wt_type_enum = .enum,
  wt_type_reinforcement_allowed = "reinforcement" %in% .enum,
  note = paste("v10 reinforcement 접두 R 과 wt_type 'reinforcement' 가 스키마에 없다.",
               "forge 는 우회하지 않았다 — 패턴 수정도 task_id 변경도 하지 않았고 사실만 기록한다.",
               "내용 기반 검증(10-component 계약 / audit_bt_result 19-check / essence_score)은 완주했다.",
               "수리는 별건 태스크."))
cat("\ntask_id pattern:", out$schema_gap$task_id_pattern,
    "| matches:", out$schema_gap$task_id_matches_v10, "\n")
cat("wt_type enum:", paste(out$schema_gap$wt_type_enum, collapse = ","),
    "| reinforcement allowed:", out$schema_gap$wt_type_reinforcement_allowed, "\n")
st <- tryCatch(fromJSON(file.path(ROOT, "qepm/mailbox/worktask", WT, "status.json")), error = function(e) NULL)
out$status_json_current_phase <- st$current_phase %||% NA
out$forge_observations <- list(
  wt_validate_package_result = "3종 전부 valid=TRUE. 이 함수는 required 필드만 보고 task_id 정규식을 참조하지 않는다 — 인계받은 'alpha_package 가 INVALID' 는 이 경로에서는 재현되지 않는다(다른 소비지점의 스키마 검증일 것).",
  task_id_regex_gap_confirmed = "^WT-[DPSH][0-9]{8}_[0-9]{3}$ 에 R 없음 — grepl FALSE 로 실증.",
  wt_type_enum_gap_confirmed = "enum 4값(discovery/deployment/sizing_only/hyperparameter_sweep)에 reinforcement 없음 — 인계 노트에 없던 두 번째 간극.",
  current_phase_observed = paste("status.json 은 ALPHA_REVISE_REQUIRED 다(인계 노트의 ALPHA_DONE 과 다름).",
                                 "forge 는 전이를 시도하지 않았고 값을 바꾸지 않았다 — 관측만 기록한다."),
  cwd_trap = "wt_validate_package 은 WT_ROOT 가 상대경로라 프로젝트 루트에서 돌려야 한다. stage dir 에서 돌리면 file_missing 오탐이 난다(1회차 실측)."
)
cat("status.json current_phase:", out$status_json_current_phase, "(전이 미시도 — 우회 금지 지시 준수)\n")
write_json(out, file.path(ROOT, "stage_artifacts/WT_R20260829_005/forge_schema_probe.json"),
           auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
cat("[probe] forge_schema_probe.json written\n")
