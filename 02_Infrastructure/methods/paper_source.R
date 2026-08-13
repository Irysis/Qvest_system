#==============================================================================
# paper_source.R — 큐 논문의 **원문 PDF 해석기** (2026-08-13 신설)
#
# 왜: 어댑터를 쓰려면 원문을 읽어야 하는데, 큐의 `pdf` 필드를 따라가면 파일이 없다.
#   실측 2026-08-13: pdf 필드 기재 4건 중 **실재 1건**. 라우터가 `MCP_2606.14798.pdf`(점)로
#   적는데 실제 파일은 `MCP_2606_14798.pdf`(밑줄)이다 — 구분자 규약이 갈렸다.
#   ★그런데 원문 자체는 다 있다: id 로 숫자만 뽑아 대조하면 **75/75 전부 찾아진다.**
#   즉 "원문 없음"이 아니라 "경로 표기가 틀렸음"이다. 이 구분이 중요하다 — 전자면 구현을
#   포기해야 하고, 후자면 그냥 찾으면 된다. 경로를 못 찾은 에이전트가 메모만 보고 구현하면
#   그게 **날조의 시작점**이다(어댑터 헤더가 요구하는 "충실한 재구성"이 성립하지 않는다).
#
# 설계: 파일명 구분자를 신뢰하지 않고 **숫자열만** 비교한다(2606.14798 / 2606_14798 /
#   arXiv:2606.14798v2 → 모두 260614798). 못 찾으면 NULL 이 아니라 **이름을 부르고** NULL —
#   조용한 부재는 "원문 없음"과 "안 찾아봄"을 구분 불가하게 만든다.
#
# 사용:
#   source("02_Infrastructure/methods/paper_source.R")
#   p <- paper_pdf("arxiv:2606.14798")   # → 01_Literature/.../MCP_2606_14798.pdf
#==============================================================================

.ps_root <- function() {
  for (c in c(Sys.getenv("QM_ROOT"), Sys.getenv("CLAUDE_PROJECT_DIR"), getwd()))
    if (nzchar(c) && dir.exists(file.path(c, "01_Literature"))) return(c)
  getwd()
}

.ps_key <- function(x) gsub("[^0-9]", "", sub("v[0-9]+$", "", tolower(trimws(as.character(x)))))

# 파일명 정규화 — curated(기관 리서치) 논문은 숫자 id 가 없고 파일명이 곧 id 다.
#   ★숫자 키만 쓰면 이들이 통째로 미발견이 된다(실측: 86건 중 8건, 전부 institutional_research/
#   에 **정확한 파일명으로 존재**했다). "원문 없음"이 아니라 "키가 안 맞음"이었다.
.ps_name <- function(x) gsub("[^a-z0-9]", "", tolower(sub("\\.pdf$", "", basename(as.character(x)))))

.ps_index <- local({
  cache <- NULL
  function(root = .ps_root(), refresh = FALSE) {
    if (!is.null(cache) && !refresh) return(cache)
    fs <- list.files(file.path(root, "01_Literature"), pattern = "\\.pdf$",
                     recursive = TRUE, full.names = TRUE)
    k <- vapply(basename(fs), .ps_key, character(1))
    nm <- vapply(fs, .ps_name, character(1))
    cache <<- list(num  = stats::setNames(fs[nzchar(k)], k[nzchar(k)]),
                   name = stats::setNames(fs, nm))
    cache
  }
})

#' 논문 id → 원문 PDF 경로. 못 찾으면 이름 부르고 NULL.
#' @param id  "2606.14798" / "arxiv:2606.14798" / "2606_14798v2" 모두 허용.
paper_pdf <- function(id, root = .ps_root(), quiet = FALSE) {
  idx <- .ps_index(root)
  k <- .ps_key(id)
  # ★`idx[[k]]` 는 이름이 없으면 **에러**(subscript out of bounds)다 — NULL 이 아니다.
  #   하필 그게 "원문 미발견" 분기라, 날조를 막아야 할 경로가 예외로 죽는다.
  #   (음성 케이스를 안 쟀으면 못 봤다 — 정상 id 4종은 전부 통과했다.)
  hit <- if (nzchar(k) && k %in% names(idx$num)) unname(idx$num[[k]]) else NULL
  if (is.null(hit) && nzchar(k)) {
    # 접미/접두가 붙은 변형(예: 버전 표기 포함 파일명) 부분일치 1건이면 채택
    cand <- idx$num[grepl(k, names(idx$num), fixed = TRUE)]
    if (length(cand) == 1L) hit <- unname(cand[[1]])
  }
  # 숫자 id 가 없거나(=curated) 숫자로 못 찾으면 **파일명**으로 찾는다.
  if (is.null(hit)) {
    nk <- .ps_name(id)
    if (nzchar(nk) && nk %in% names(idx$name)) hit <- unname(idx$name[[nk]])
  }
  if (is.null(hit) && !nzchar(k)) {
    if (!quiet) cat(sprintf("[paper_source] id 해석 실패(숫자·파일명 모두 불일치): %s\n", id))
    return(NULL)
  }
  if (is.null(hit)) {
    if (!quiet) cat(sprintf("[paper_source] ★원문 미발견: %s (key=%s) — 메모만으로 구현하지 말 것\n", id, k))
    return(NULL)
  }
  hit
}

#' 큐 항목 리스트에 대해 도달률을 찍는다(착수 전 확인용).
paper_pdf_coverage <- function(ids, root = .ps_root()) {
  ids <- unique(ids[nzchar(ids)])
  hit <- vapply(ids, function(i) !is.null(paper_pdf(i, root, quiet = TRUE)), logical(1))
  cat(sprintf("[paper_source] 원문 도달 %d/%d\n", sum(hit), length(hit)))
  if (any(!hit)) cat(sprintf("  미발견: %s\n", paste(ids[!hit], collapse = ", ")))
  invisible(data.frame(id = ids, found = hit, row.names = NULL))
}
