#==============================================================================
# frontier_queue_io.R — alpha_frontier_queue.json 정본 read/write
#
# 2026-08-08 신설. 근거 = 같은 날 실측 census:
#   이 원장을 **쓰는 스크립트 18개** 중 `digits` 지정 9개(50%) · `pretty=1` 지정 **0개**.
#
# ★두 축이 각각 독립적으로 원장을 훼손한다:
#   ① digits 미지정 → jsonlite 기본 `digits=4` 로 **남의 항목 측정값이 반올림**된다
#      (실사고 2026-08-08: 0.009541984 → 0.0095). 파일은 유효 JSON이고 스키마도 맞아 **조용하다**.
#   ② pretty 불일치 → 이 파일의 정본 들여쓰기는 **1칸**인데 `pretty=TRUE`(2칸)로 쓰면
#      **3357추가/3333삭제** 전면 재직렬화가 난다. 데이터는 안 죽지만 **diff 를 못 읽게 되고**,
#      diff 를 못 읽으면 "순수 추가 확인"이라는 ①의 방어 규약이 **함께 무력해진다**.
#      (실사고 같은 날: 내가 검증한 13/4 가 병행 세션 재직렬화로 3417/3333 에 파묻힘.)
#
# ★★규약만으로는 안 됐다는 것이 census 의 결론이다 — `digits=NA` 규약은 메모리 카드로 전파돼
#   9/18 까지 갔지만 나머지 절반은 여전히 무방비였고, 형식 축(②)은 아무도 몰랐다.
#   ⇒ 방어를 **문서에서 함수로** 옮긴다. 앞으로 이 원장에 쓰는 모든 경로는 이 파일을 경유할 것.
#
# 사용:
#   source("02_Infrastructure/ops/frontier_queue_io.R")
#   Q <- read_frontier_queue()
#   Q$entries[[i]]$foo <- "bar"
#   write_frontier_queue(Q)                      # 손실 가드 통과해야 기록
#   write_frontier_queue(Q, allow_shrink = "FQ-999 폐기 — 도훈 confirm 20260808")   # 축소는 사유 필수
#==============================================================================

suppressMessages(library(jsonlite))

FRONTIER_QUEUE_PATH <- "06_Registry/alpha_frontier_queue.json"

## 이 파일의 정본 직렬화 설정 — 무수정 왕복이 **바이트 동일**임을 2026-08-08 실측으로 확정
##   pretty=1 → 3335줄 원본과 완전 동일 / pretty=2·TRUE → 불일치 6328줄
.fq_serialize <- function(Q) {
  toJSON(Q, auto_unbox = TRUE, pretty = 1, digits = NA, null = "null", na = "null")
}

.fq_path <- function(path) {
  if (!is.null(path)) return(path)
  root <- Sys.getenv("QM_ROOT", "")
  if (nzchar(root) && dir.exists(root)) file.path(root, FRONTIER_QUEUE_PATH) else FRONTIER_QUEUE_PATH
}

## 고정밀 리터럴(소수 5자리 이상) 집합 — ①의 검거 축.
## 값이 아니라 **리터럴 문자열**로 비교한다: 반올림되면 문자열이 사라지므로 그것만 보면 된다.
.fq_precise_literals <- function(txt) {
  m <- unlist(regmatches(txt, gregexpr("-?[0-9]+[.][0-9]{5,}", txt)))
  unique(m)
}

read_frontier_queue <- function(path = NULL) {
  p <- .fq_path(path)
  if (!file.exists(p)) stop("[fq_io] 원장 부재: ", p)
  fromJSON(p, simplifyVector = FALSE)
}

#' 정본 기록 — 손실 가드 통과 시에만 디스크에 쓴다.
#'
#' @param allow_shrink 항목 수가 줄어드는 기록을 허용할 사유(문자열). 미지정 시 축소는 오류.
#' @return 불가시 side effect. invisible list(added=, removed=, n=)
write_frontier_queue <- function(Q, path = NULL, allow_shrink = NULL) {
  p <- .fq_path(path)
  if (is.null(Q$entries) || !length(Q$entries)) stop("[fq_io] entries 가 비어 있다 — 기록 거부")

  new_txt <- .fq_serialize(Q)
  new_ids <- vapply(Q$entries, function(e) if (is.null(e$id)) NA_character_ else as.character(e$id)[1],
                    character(1))
  if (anyNA(new_ids)) stop("[fq_io] id 없는 항목 ", sum(is.na(new_ids)), "건 — 기록 거부")
  if (anyDuplicated(new_ids)) stop("[fq_io] 중복 id: ",
                                   paste(unique(new_ids[duplicated(new_ids)]), collapse = ", "))

  added <- character(0); removed <- character(0)
  if (file.exists(p)) {
    old_txt <- paste(readLines(p, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    old <- fromJSON(p, simplifyVector = FALSE)
    old_ids <- vapply(old$entries, function(e) if (is.null(e$id)) NA_character_ else as.character(e$id)[1],
                      character(1))
    added   <- setdiff(new_ids, old_ids)
    removed <- setdiff(old_ids, new_ids)

    ## 가드 1 — 항목 소실 (병행 세션이 그 사이 등재한 항목을 덮어쓰는 사고의 검거 축)
    if (length(removed) && is.null(allow_shrink))
      stop("[fq_io] 항목 ", length(removed), "건이 사라진다: ",
           paste(head(removed, 8), collapse = ", "),
           "\n  병행 세션 등재분을 덮어쓰는 중일 수 있다 — 재-read 후 다시 적용하거나, ",
           "의도한 삭제라면 allow_shrink=<사유> 를 넘길 것.")

    ## 가드 2 — 정밀도 훼손 (digits 축). 리터럴이 사라졌으면 반올림된 것이다.
    lost <- setdiff(.fq_precise_literals(old_txt), .fq_precise_literals(new_txt))
    ## 삭제가 허용된 항목에서 유래한 소실은 정상 — 남은 텍스트에 없으면서 삭제분에도 없을 때만 위반
    if (length(lost)) {
      still <- vapply(lost, function(x) grepl(x, new_txt, fixed = TRUE), logical(1))
      lost <- lost[!still]
    }
    if (length(lost))
      stop("[fq_io] 고정밀 값 ", length(lost), "개가 소실된다 (digits 반올림 의심): ",
           paste(head(lost, 6), collapse = ", "),
           "\n  toJSON(digits=NA) 경유인지 확인할 것 — 남의 항목 측정값이 훼손된다.")
  }

  writeLines(new_txt, p, useBytes = TRUE)

  ## 기록 후 재읽기 — 쓴 것이 실제로 읽히는지 (침묵 실패 차단)
  chk <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(chk)) stop("[fq_io] ★기록 후 재읽기 실패 — 파일이 깨졌다: ", p)
  if (length(chk$entries) != length(Q$entries))
    stop("[fq_io] ★기록 후 항목 수 불일치: 의도 ", length(Q$entries), " vs 디스크 ", length(chk$entries))

  message(sprintf("[fq_io] 기록 완료 — 항목 %d (추가 %d · 삭제 %d)%s",
                  length(new_ids), length(added), length(removed),
                  if (!is.null(allow_shrink)) paste0(" · 축소사유: ", allow_shrink) else ""))
  invisible(list(added = added, removed = removed, n = length(new_ids)))
}

#' 현재 디스크 파일이 정본 형식인가 — 무수정 왕복이 바이트 동일한지 시험.
#' 거짓이면 다음 정본 기록이 1회 큰 diff 를 낸다(데이터 손실 아님, 형식 수렴).
frontier_queue_format_ok <- function(path = NULL) {
  p <- .fq_path(path)
  if (!file.exists(p)) return(NA)
  orig <- readLines(p, warn = FALSE, encoding = "UTF-8")
  rt <- strsplit(.fq_serialize(fromJSON(p, simplifyVector = FALSE)), "\n", fixed = TRUE)[[1]]
  identical(orig, rt)
}
