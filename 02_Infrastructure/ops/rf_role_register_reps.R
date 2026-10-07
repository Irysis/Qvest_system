#==============================================================================
# rf_role_register_reps.R — 역할 대표 중 module_catalog 미등록분을 등재 (2026-10-07 · 도훈 "미등록풀도 등록해")
#   대상 = 06_Registry/strategy_roles.json 의 pool_rep_roles 보유 ∧ 카탈로그 미등재 · 원장 칸/기저만(legacy·BOOK 는 별도 경로).
#   등재 = rmm_register_measured(out_dir, role_rep_id=) — 역할 대표 경로(①')는 레지스트리를 다시 읽어 확인하고,
#   계약 floor(backtested · status OK · 재료)는 그대로 거친다. 새 측정 없음.
#   사용: cd 02_Infrastructure/ops && Rscript -e 'source("rf_role_register_reps.R")'   (RF_ROLE_REG_DRY=1 = 판정만)
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
.root <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")); setwd(.root)
source("02_Infrastructure/contracts/register_measured_module.R")
DRY <- identical(Sys.getenv("RF_ROLE_REG_DRY"), "1")
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
reg <- fromJSON("06_Registry/strategy_roles.json", simplifyVector = FALSE)$entries
cat_ <- fromJSON("06_Registry/module_catalog.json", simplifyVector = FALSE)$modules
runid <- function(x) { m <- regmatches(x, regexpr("[0-9]{8}_[0-9]{6}_[0-9]+", x)); if (length(m)) m else NA_character_ }
in_cat <- unique(na.omit(c(vapply(names(cat_), runid, ""), vapply(cat_, function(v) runid(paste(v$meta$artifacts_dir %||% "", v$bt_result_path %||% "")), ""))))
res <- list()
for (id in names(reg)) {
  e <- reg[[id]]
  if (!length(unlist(e$pool_rep_roles))) next
  if (!(e$kind %in% c("cell", "base"))) next
  if (id %in% in_cat || id %in% names(cat_)) next
  out_dir <- dirname(e$series)                      # remeasure_close_t1_* (정본) 또는 신판 최상위 — auth·계약 CSV 가 있는 곳
  r <- rmm_register_measured(out_dir, origin_mode = "replication", dry_run = DRY, role_rep_id = id,
                             meta = list(paper_key = e$lineage, strategy_idea = sprintf("[역할 대표 %s] %s %s", paste(unlist(e$pool_rep_roles), collapse = ","), e$lineage, e$cell %||% "")))
  res[[id]] <- data.table(member_id = id, kind = e$kind, lineage = substr(e$lineage, 1, 40), roles = paste(unlist(e$pool_rep_roles), collapse = ";"),
                          code = r$code, route = r$route %||% NA_character_, sid = r$strategy_id, reason = substr(r$reason, 1, 90))
}
R <- rbindlist(res, fill = TRUE)
cat(sprintf("대상 %d · %s\n", nrow(R), if (DRY) "dry-run" else "등재 실행"))
print(R[, .N, by = code])
print(R[, .(member_id, kind, lineage, roles, code, reason)])
fwrite(R, file.path(.root, "04_Research/01_reports/strategy_role_grading_20261006/classify_20261006", sprintf("register_reps_%s.csv", if (DRY) "dry" else "run")))
