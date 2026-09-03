## WT-R20260829_006 — schema.json 인계 이슈 실측 기록 (우회 아님)
Sys.setenv(QM_ROOT = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- Sys.getenv("QM_ROOT")
suppressPackageStartupMessages({library(jsonlite)})
SD <- file.path(ROOT, "stage_artifacts/WT_R20260829_006")
WT_ID <- "WT-R20260829_006"

sch <- fromJSON(file.path(ROOT, "02_Infrastructure/worktask/schema.json"), simplifyVector = FALSE)
pat <- sch$definitions$request$properties$task_id$pattern %||% sch$request$properties$task_id$pattern
if (is.null(pat)) {
  txt <- readLines(file.path(ROOT, "02_Infrastructure/worktask/schema.json"), warn = FALSE)
  pat <- regmatches(txt[17], regexpr('\\^WT[^"]*', txt[17]))
}
cat("task_id pattern =", pat, "\n")
id_ok <- grepl(pat, WT_ID)
cat("WT-R20260829_006 matches pattern:", id_ok, "\n")

txt <- readLines(file.path(ROOT, "02_Infrastructure/worktask/schema.json"), warn = FALSE)
enum_line <- grep('"discovery", "deployment"', txt, value = TRUE)[1]
cat("wt_type enum line:", trimws(enum_line), "\n")
type_ok <- grepl("reinforcement", enum_line %||% "")
cat("'reinforcement' in wt_type enum:", type_ok, "\n")

# forge_package 정의 존재 여부 + required 필드
fp_def <- sch$definitions$forge_package %||% sch$forge_package
cat("forge_package definition present:", !is.null(fp_def), "\n")
req <- fp_def$required
cat("forge_package required:", paste(unlist(req), collapse = ", "), "\n")
fp <- fromJSON(file.path(ROOT, "qepm/mailbox/worktask", WT_ID, "forge_package.json"),
               simplifyVector = FALSE)
missing <- setdiff(unlist(req), names(fp))
cat("missing required fields in emitted forge_package.json:",
    if (length(missing)) paste(missing, collapse = ", ") else "(none)", "\n")

# 공식 validator 호출 — ★WT_ROOT 가 상대경로("qepm/mailbox/worktask")라 cwd 를 ROOT 로 맞춘다.
#   (맞추지 않으면 file_missing 이 뜨는데 그건 계기 결함이 아니라 호출자의 cwd 문제다.)
.owd <- setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/worktask/worktask_manager.R"))
v_bad  <- tryCatch(wt_validate_package(WT_ID, "forge"),
                   error = function(e) list(error = conditionMessage(e)))
v      <- tryCatch(wt_validate_package(WT_ID, "forge_package"),
                   error = function(e) list(error = conditionMessage(e)))
cat("\n[wt_validate_package(.., 'forge')] ->\n"); print(v_bad)
cat("[wt_validate_package(.., 'forge_package')] ->\n"); print(v)
# ★validator 의 switch 에 forge_package 분기가 아예 없다 -> required_fields = character(0)
#   -> 어떤 내용이든 valid=TRUE. 통과가 아니라 **검사 부재**다.
vs_src <- paste(deparse(wt_validate_package), collapse = " ")
has_forge_branch <- grepl("forge", vs_src)
cat("validator switch 에 forge 분기 존재:", has_forge_branch, "\n")
# wt_list 정규식도 WT-R 을 못 본다
wl_src <- paste(deparse(wt_list), collapse = " ")
wl_pat <- regmatches(wl_src, regexpr('\\^WT[^"]*', wl_src))
cat("wt_list pattern =", wl_pat, "| matches WT-R20260829_006:", grepl(wl_pat, WT_ID), "\n")
setwd(.owd)

out <- list(
  wt_id = WT_ID,
  finding = "우회하지 않음 — 사실만 기록한다. 내용 기반 검증(10-component · audit 19 · essence)은 완주했다.",
  task_id_pattern = pat,
  task_id_matches = id_ok,
  wt_type_enum_line = trimws(enum_line %||% NA_character_),
  wt_type_reinforcement_in_enum = type_ok,
  forge_package_definition_present = !is.null(fp_def),
  forge_package_required = unlist(req),
  forge_package_missing_required = if (length(missing)) missing else character(0),
  wt_validate_package_result = v,
  wt_validate_package_wrong_type_result = v_bad,
  wt_validate_package_has_forge_branch = has_forge_branch,
  wt_list_pattern = wl_pat,
  wt_list_matches_wt_r = grepl(wl_pat, WT_ID),
  reading = paste("① schema.json:17 task_id 정규식 ^WT-[DPSH][0-9]{8}_[0-9]{3}$ 에 v10 접두 'R' 이 없다.",
                  "② wt_type enum 에 'reinforcement' 가 없다. 두 축 모두 v10 WT-R 계열을 INVALID 로 만든다.",
                  "③ 더 나아가 wt_validate_package 의 switch 에는 forge_package 분기 자체가 없어",
                  "required_fields = character(0) -> 내용 무관 valid=TRUE 다. 그건 통과가 아니라 **검사 부재**다",
                  "(5/20 이 'required 필드만 봐서 valid=TRUE' 라 적은 것보다 한 단계 더 비어 있다).",
                  "④ wt_list 정규식도 WT-R 을 못 본다. 우회하지 않았고 수리는 별건 태스크다."))
write_json(out, file.path(SD, "forge_schema_probe.json"), auto_unbox = TRUE, pretty = TRUE,
           null = "null", na = "null")
cat("\n[probe] forge_schema_probe.json written\n")
