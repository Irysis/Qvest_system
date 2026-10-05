#==============================================================================
# rf_clean_lane_lib.R — 검증기(rf_replication_verify.R) 쪽 청정 모드 도우미 (결정 FA-CLEAN-BASE-PATH · 도훈 2026-09-26)
#
# 무엇: 청정 충실구현 레인(RP_LANE_MODE=clean)의 적대적 충실도 감사를 **측정 비공개 조건**으로 부른다 —
#   ① 감사 레인에 산출물 경로를 주지 않는다(rcl_audit_art — 빈 문자열 · 감사 프롬프트가 '청정 모드 — 비공개' 줄을 쓴다)
#   ② 감사 스폰 한 번에만 가드 표식(QVEST_CLEAN_LANE · QVEST_CLEAN_WDIR)을 싣는다(rcl_with_env — 끝나면 원복 · 측정·원장 쓰기에 새지 않는다)
#   ③ 재구현을 부르는 감사면 그 감사의 프롬프트·판정 파일을 작업 디렉터리 .clean_audit_src/r<n>/ 에 보존한다(rcl_archive_audit_src) —
#      다음 판 프롬프트의 감사 지적이 청정 감사에서 왔음을 사후 검사(rf_clean_base.R)가 **파일에서** 재도출한다(감사 파일은 다음 감사가 덮는다)
#   ④ 출처 기록(lane_provenance.json) audits 목록에 감사 1건을 덧붙인다(rcl_prov_audit)
# 왜 감사도: 재구현 피드백 = 감사 지적이다. 산출물(측정 t·보유)을 본 감사자의 지적은 수치를 가려도 결과 조건부 서술이 남을 수 있다
#   (축 등록부 signal 축: '부호 반전은 강한 음수 t 로 나타난다'). 청정 규칙 설정 clean_room 요건('감사는 엔진·논문만 보고 한다')과 같은 방향.
# 쓰기: 작업 디렉터리 안(.clean_audit_src/ · lane_provenance.json)만. 원장·요청 파일은 검증기 본문이 쓴다.
# 검사: 08_Tests/ops/test_rf_clean_lane.sh §V
#==============================================================================
suppressMessages(library(jsonlite))
.rcl_or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

#' 레인 모드 — 검증기 환경변수(레인 셸이 싣는다). clean 외 값은 전부 normal.
rcl_lane_mode <- function() if (identical(Sys.getenv("RP_LANE_MODE", "normal"), "clean")) "clean" else "normal"

#' 감사 레인에 넘길 산출물 경로 — 청정이면 빈 문자열(감사 프롬프트가 비공개 줄을 쓴다)
rcl_audit_art <- function(clean, art) if (isTRUE(clean)) "" else as.character(art)

#' 환경변수를 잠깐 싣고 expr 을 돌린 뒤 원복(없던 변수는 지운다) — 감사 스폰 한 번에만 가드 표식
rcl_with_env <- function(vars, expr) {
  nm <- names(vars)
  old <- Sys.getenv(nm, unset = NA_character_, names = TRUE)
  do.call(Sys.setenv, as.list(vars))
  on.exit({
    for (k in nm) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, stats::setNames(list(old[[k]]), k))
  }, add = TRUE)
  force(expr)
}

#' 청정 감사 표식 — 감사 레인(그 claude 와 훅)이 보는 값
rcl_clean_env <- function(wdir) c(QVEST_CLEAN_LANE = "1", QVEST_CLEAN_WDIR = gsub("\\\\", "/", wdir))

#' 재구현을 부른 감사의 원천 보존 — 프롬프트(단일·축별)·판정·축 파일 사본 + 매니페스트(sha256). 반환 = list(dir, rel, files)
rcl_archive_audit_src <- function(wdir, n) {
  d <- file.path(wdir, ".clean_audit_src", sprintf("r%d", as.integer(n)))
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  fs <- c(list.files(wdir, pattern = "^\\.audit_prompt_.*\\.txt$", all.files = TRUE),
          list.files(wdir, pattern = "^fidelity_axis_[A-Za-z]+\\.json$"),
          intersect(c("fidelity_prompt.txt", "fidelity_audit.json", ".audit_plan.tsv"), list.files(wdir, all.files = TRUE)))
  man <- list()
  for (f in unique(fs)) {
    ok <- file.copy(file.path(wdir, f), file.path(d, f), overwrite = TRUE, copy.date = TRUE)
    if (isTRUE(ok)) man[[f]] <- digest::digest(file.path(d, f), algo = "sha256", file = TRUE)
  }
  writeLines(toJSON(list(schema = "clean_audit_src_v1", n = as.integer(n), files = man,
                         at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")), auto_unbox = TRUE, pretty = TRUE),
             file.path(d, "manifest.json"), useBytes = TRUE)
  list(dir = d, rel = sprintf(".clean_audit_src/r%d", as.integer(n)), files = names(man))
}

#' 출처 기록에 감사 1건 덧붙이기(원자적 교체) — 기록이 없으면 만들지 않는다(레인이 실행 전 기록을 만든다)
rcl_prov_audit <- function(wdir, rec, prov_file = "lane_provenance.json") {
  p <- file.path(wdir, prov_file)
  if (!file.exists(p)) return(invisible(FALSE))
  P <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(P)) return(invisible(FALSE))
  P$audits <- c(.rcl_or(P$audits, list()), list(rec))
  tmp <- paste0(p, ".tmp", Sys.getpid())
  writeLines(toJSON(P, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"), tmp, useBytes = TRUE)
  invisible(file.rename(tmp, p))
}
