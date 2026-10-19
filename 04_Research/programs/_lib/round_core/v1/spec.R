## round_core v1 · spec — 라운드 사양(round_spec.json) 적재 · 구조 검사
##   라운드가 새로 쓰는 것은 이 사양 하나(+ DESIGN.md 사고 기록 · 필요할 때만 round_ext.R)다. 판정 · 사전등록 문장 · 표는 사양에서 생성된다.
##   검사는 등록 전 check 단계와 판정 시작이 같은 함수를 쓴다 — 형식 결함(예: P1R01 의 이름 없는 배열을 이름으로 순회해 0행이 된 결함)을
##   측정 · 판정 전에 잡는다.

RC_SPEC_SCHEMA <- "round_spec_v1"
RC_TEMPLATES   <- c("p1_qualification", "p2_device", "p3_construction", "custom")
RC_CELL_ROLES  <- c("variant", "reference", "diagnostic")

.rc_spec_err <- function(msg) stop(paste0("[round_core spec] ", msg), call. = FALSE)

rc_spec_validate <- function(s, root = rc_root(), check_files = TRUE) {
  if (!identical(s[["schema"]], RC_SPEC_SCHEMA)) .rc_spec_err(paste("schema 는", RC_SPEC_SCHEMA))
  for (k in c("program", "round_id", "template", "core_version", "tau_d"))
    if (is.null(s[[k]]) || !is.character(s[[k]]) || !nzchar(s[[k]])) .rc_spec_err(paste(k, "없음"))
  if (!grepl("^P[0-9]_[A-Z_]+$", s[["program"]])) .rc_spec_err(paste("program 형식:", s[["program"]]))
  if (!grepl("^P[0-9]+[A-Z]*[0-9]+_[a-z0-9_]+$", s[["round_id"]])) .rc_spec_err(paste("round_id 형식(P<n>R<nn>_이름 · 소문자):", s[["round_id"]]))
  if (!s[["template"]] %in% RC_TEMPLATES) .rc_spec_err(paste("template 은", paste(RC_TEMPLATES, collapse = "|")))
  if (is.na(suppressWarnings(as.Date(s[["tau_d"]])))) .rc_spec_err("tau_d 날짜 형식")
  if (!is.list(s[["cells"]]) || !length(s[["cells"]]) || !is.null(names(s[["cells"]]))) .rc_spec_err("cells 는 이름 없는 목록(배열) 1개 이상")
  codes <- character(0)
  for (c in s[["cells"]]) {
    if (!is.list(c) || is.null(c[["code"]]) || !nzchar(c[["code"]])) .rc_spec_err("칸에 code 없음")
    if (!(c[["role"]] %||% "") %in% RC_CELL_ROLES) .rc_spec_err(paste0(c[["code"]], ": role 은 ", paste(RC_CELL_ROLES, collapse = "|")))
    if (is.null(c[["engine"]]) || !nzchar(c[["engine"]])) .rc_spec_err(paste0(c[["code"]], ": engine 없음"))
    has_spec <- !is.null(c[["spec"]]); has_src <- !is.null(c[["source_results"]])
    if (has_spec == has_src) .rc_spec_err(paste0(c[["code"]], ": spec(측정할 칸 사양) 또는 source_results(공유 측정) 중 정확히 하나"))
    if (check_files && has_spec && !file.exists(rc_abs(c[["spec"]], root))) .rc_spec_err(paste0(c[["code"]], ": 칸 사양 파일 없음 ", c[["spec"]]))
    if (check_files && has_src && !dir.exists(rc_abs(c[["source_results"]], root))) .rc_spec_err(paste0(c[["code"]], ": 공유 측정 결과 디렉터리 없음 ", c[["source_results"]]))
    codes <- c(codes, c[["code"]])
  }
  if (anyDuplicated(codes)) .rc_spec_err(paste("칸 code 중복:", paste(codes[duplicated(codes)], collapse = ",")))
  rc_rules_validate(s[["rules"]])
  if (!is.list(s[["selection"]]) || is.null(s[["selection"]][["rule"]])) .rc_spec_err("selection.rule 없음(선택 없음이면 'none')")
  if (is.null(s[["exposures"]])) .rc_spec_err("exposures 없음(노출 없음이어도 빈 배열로 적는다 — τ_D 노출 고지)")
  invisible(TRUE)
}

rc_spec_load <- function(path, root = rc_root(), check_files = TRUE) {
  s <- rc_json_read(path)
  rc_spec_validate(s, root = root, check_files = check_files)
  s$.path <- path; s$.md5 <- rc_md5(path)
  s
}
