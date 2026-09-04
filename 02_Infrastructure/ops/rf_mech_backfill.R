## rf_mech_backfill.R — 기전(LLM 서술)이 빈 블록 L-code 를 찾아 재시도 대상으로 낸다 (2026-09-04)
##
## 실사고: 오늘 15블록 중 6블록의 '이번 블록에서 배운 것' 이 비어 있었다 — 2건은 모델(fable) API 400,
##   1건은 킬스위치, 3건은 호출부 도입 전. 기전 레인은 블록 종료 직후 **한 번만** 불리고 실패하면 영영
##   비었다 — 재개 장치가 결정론적 실패에 출구가 없듯, 일시 실패에도 재시도가 없었다.
## 규칙: L-code 파일이 있고 mechanism 이 비었고 mechanism_tries < max_tries 인 블록만. 순수 함수(파일 읽기만).
suppressMessages(library(jsonlite))
if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

rf_mech_backfill_targets <- function(base_id, root, max_tries = 2L, exclude_block = NA_character_) {
  dir <- file.path(root, "stage_artifacts/l_code/reinforcement")
  fs <- list.files(dir, pattern = sprintf("^l_code_%s_B[0-9]+[.]json$", base_id), full.names = TRUE)
  out <- character(0)
  for (f in fs) {
    b <- sub("^.*_(B[0-9]+)[.]json$", "\\1", basename(f))
    if (!is.na(exclude_block) && identical(b, exclude_block)) next
    d <- tryCatch(fromJSON(f, simplifyVector = TRUE), error = function(e) NULL)
    if (is.null(d)) next
    mech <- as.character(d$mechanism %||% "")[1]
    if (!is.na(mech) && nzchar(trimws(mech))) next
    tries <- suppressWarnings(as.integer(d$mechanism_tries %||% 0L))
    if (is.na(tries)) tries <- 0L
    if (tries >= max_tries) next
    out <- c(out, b)
  }
  ## 블록 순서대로(B1 → B5 → B2 → B3 → B4 는 러너가 정하지만 여기선 파일 순이면 충분하다)
  unique(out)
}

#' 기각/실패 시 시도 횟수를 L-code 에 남긴다 — 백필이 무한히 돌지 않게
rf_mech_note_try <- function(base_id, block, root) {
  f <- file.path(root, "stage_artifacts/l_code/reinforcement", sprintf("l_code_%s_%s.json", base_id, block))
  if (!file.exists(f)) return(invisible(FALSE))
  d <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(d)) return(invisible(FALSE))
  d$mechanism_tries <- suppressWarnings(as.integer(d$mechanism_tries %||% 0L)) + 1L
  if (is.na(d$mechanism_tries)) d$mechanism_tries <- 1L
  txt <- toJSON(d, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6)
  if (!is.null(tryCatch(fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)))
    writeLines(txt, f, useBytes = TRUE)
  invisible(TRUE)
}
