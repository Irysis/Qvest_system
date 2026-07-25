# distill_stats.R — weekly/monthly distill 공용 통계 소스 (2026-07-25 신규)
#
# 배경: weekly_distill/monthly_distill의 두 스텝이 죽은 소스를 참조하고 있었음.
#   ① `qepm/registry/experiments.json` — 파일 자체가 부재 → 주간 실험 요약이 항상 0건
#   ② `update_memory_summary()` — methodology_active.md 등 구 경로 부재(v2 Ledger 이관)로
#      "No methodology file found" no-op. 게다가 MEMORY.md를 정규식으로 덮어쓰는 함수라
#      무인 루틴이 호출할 대상이 아님(사용자 메모리 인덱스 훼손 위험) → 호출 제거.
# 현행 권위 소스:
#   - `06_Registry/hypothesis_index.json` — 가설/검증 Ledger(entries[].date/verdict/grade)
#   - `06_Registry/knowledge_index.json`  — counts{active_law, active_distilled, lcode_corpus, archived}
# 둘 다 weekly_cleaner_sweep(inv_hypothesis_index / knowledge_index 스텝)이 주간 재생성.

suppressWarnings(suppressMessages(library(jsonlite)))

.qv_root <- function() {
  r <- Sys.getenv("QM_ROOT", unset = Sys.getenv("CLAUDE_PROJECT_DIR", ""))
  if (nzchar(r) && dir.exists(r)) return(r)
  if (exists("PROJECT_ROOT", inherits = TRUE) &&
      dir.exists(file.path(get("PROJECT_ROOT", inherits = TRUE), "06_Registry"))) {
    return(get("PROJECT_ROOT", inherits = TRUE))
  }
  getwd()
}

#' 지식 Ledger 카운트 (knowledge_index.json)
#' @return list(law, distilled, lcode, archived, generated_at) — 파일 부재 시 NA + source="missing"
qv_ledger_stats <- function(root = .qv_root()) {
  p <- file.path(root, "06_Registry", "knowledge_index.json")
  if (!file.exists(p)) return(list(law = NA_integer_, distilled = NA_integer_,
                                   lcode = NA_integer_, archived = NA_integer_,
                                   generated_at = NA_character_, source = "missing"))
  j <- fromJSON(p, simplifyVector = FALSE)
  c0 <- j$counts %||% list()
  list(law          = as.integer(c0$active_law       %||% NA),
       distilled    = as.integer(c0$active_distilled %||% NA),
       lcode        = as.integer(c0$lcode_corpus     %||% NA),
       archived     = as.integer(c0$archived         %||% NA),
       generated_at = as.character(j$generated_at    %||% NA),
       source       = "knowledge_index.json")
}

#' 최근 N일 리서치 판정 요약 (hypothesis_index.json)
#' @param days 조회 창(일). 기본 7 = 주간.
#' @return list(n, verdicts(정렬 table), since, generated_at, source)
qv_recent_research <- function(days = 7L, root = .qv_root()) {
  p <- file.path(root, "06_Registry", "hypothesis_index.json")
  since <- format(Sys.Date() - days, "%Y-%m-%d")
  if (!file.exists(p)) return(list(n = 0L, verdicts = integer(0), since = since,
                                   generated_at = NA_character_, source = "missing"))
  j <- fromJSON(p, simplifyVector = FALSE)
  e <- j$entries %||% list()
  d <- vapply(e, function(x) as.character(x$date    %||% ""),   character(1))
  v <- vapply(e, function(x) as.character(x$verdict %||% "NA"), character(1))
  sel <- nzchar(d) & d >= since
  list(n = sum(sel),
       verdicts = sort(table(v[sel]), decreasing = TRUE),
       since = since,
       generated_at = as.character(j$generated_at %||% NA),
       source = "hypothesis_index.json")
}

#' 콘솔 한 줄 요약 (verdict 상위 k종)
qv_verdict_line <- function(rr, k = 4L) {
  if (!length(rr$verdicts)) return("(판정 기록 없음)")
  tv <- head(rr$verdicts, k)
  paste(names(tv), as.integer(tv), sep = ":", collapse = " ")
}
