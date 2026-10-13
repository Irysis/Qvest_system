#!/usr/bin/env Rscript
#==============================================================================
# mechanism_atlas.R — 메커니즘 지도 writer · 검증기 (v10.01 · 2026-10-13)
#
# 왜: 논문 파이프라인 조사(10-13)에서 "논문이 보고한 시장 · 기간 · 효과크기 · 위기 행동"을 담는 저장소가 어디에도
#   없었다(KR 실측 지식만 있다). v10.01 은 논문을 엔진별 재료로 쓰는데, 재료가 무엇을 주장하는지 구조로 남지 않으면
#   처방 담당이 매번 원문을 다시 읽거나 기억 없이 처방한다. 이 지도가 그 '문헌 쪽 기억'이다.
# 원칙: LLM 은 추출을 제안만 한다(스테이징 JSON). 지도(06_Registry/mechanism_atlas.jsonl)는 이 파일만 쓴다 —
#   스키마 검사 통과분만, 키(paper_key + extract_version) 중복 없이, 원자적 교체로.
#   숫자를 지어내지 않는다 — 원문에 없으면 null + 사유. 원문 위치(section/page)가 없는 수치 주장은 거부한다.
# 공개: ma_path · ma_load · ma_validate · ma_ingest · ma_pending
# CLI: Rscript mechanism_atlas.R --ingest <staging.json> | --pending [N]
# 검사: 08_Tests/programs/test_mechanism_atlas.R
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })

MA_ENGINES <- c("return", "defense", "construction")
MA_REQUIRED <- c("paper_key", "extract_version", "engine", "mechanism", "market", "period", "claims", "extraction")
MA_CRISIS_LABELS <- c("reported", "not_reported")

.ma_or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.ma_root <- function(root = NULL) {
  for (p in c(root, Sys.getenv("QM_ROOT", ""), getwd())) {
    if (is.null(p) || !nzchar(p)) next
    p <- gsub("\\\\", "/", p)
    if (dir.exists(file.path(p, "06_Registry"))) return(p)
  }
  stop("[mechanism_atlas] 프로젝트 루트 해석 실패")
}
ma_path <- function(root = NULL) file.path(.ma_root(root), "06_Registry/mechanism_atlas.jsonl")

ma_load <- function(root = NULL, path = NULL) {
  p <- .ma_or(path, ma_path(root))
  if (!file.exists(p)) return(list())
  L <- readLines(p, encoding = "UTF-8", warn = FALSE)
  L <- L[nzchar(trimws(L))]
  lapply(L, function(x) fromJSON(x, simplifyVector = FALSE))
}

#' 레코드 1건 검사 — 문제 목록(빈 벡터 = 통과)
#' 스키마(요약): paper_key · extract_version · engine ∈ {return,defense,construction} · mechanism{name, family, description} ·
#'   market{country, universe} · period{start, end} · frequency? ·
#'   claims[{metric, value|null, t|null, net_of_cost|null, where}] — value 가 있으면 where(원문 위치) 필수 ·
#'   crisis{label ∈ reported/not_reported, episodes[{name, metric, value, vs_benchmark, where}]} ·
#'   construction{n_names, weighting, turnover, capacity}? · data_needed[]? · extraction{model, confidence ∈ [0,1], source_url}
ma_validate <- function(r) {
  e <- character(0)
  miss <- setdiff(MA_REQUIRED, names(r))
  if (length(miss)) e <- c(e, paste("필수 필드 없음:", paste(miss, collapse = ",")))
  if (!is.null(r$engine) && !(r$engine %in% MA_ENGINES)) e <- c(e, paste("engine 어휘 밖:", r$engine))
  if (!is.null(r$mechanism) && !nzchar(.ma_or(r$mechanism$name, ""))) e <- c(e, "mechanism.name 비어 있음")
  for (c in .ma_or(r$claims, list())) {
    v <- c$value
    if (!is.null(v) && !(is.numeric(v) && length(v) == 1L && is.finite(v))) e <- c(e, paste("claims.value 가 수치가 아님:", .ma_or(c$metric, "?")))
    if (!is.null(v) && !nzchar(.ma_or(c$where, ""))) e <- c(e, paste("수치 주장에 원문 위치(where) 없음:", .ma_or(c$metric, "?")))
  }
  cr <- r$crisis
  if (!is.null(cr)) {
    if (!(.ma_or(cr$label, "") %in% MA_CRISIS_LABELS)) e <- c(e, "crisis.label 어휘 밖")
    for (ep in .ma_or(cr$episodes, list()))
      if (!is.null(ep$value) && !nzchar(.ma_or(ep$where, ""))) e <- c(e, paste("위기 수치에 원문 위치 없음:", .ma_or(ep$name, "?")))
  }
  conf <- r$extraction$confidence
  if (!is.null(conf) && !(is.numeric(conf) && conf >= 0 && conf <= 1)) e <- c(e, "extraction.confidence 범위 밖")
  e
}

#' 스테이징(LLM 산출 JSON 배열) → 검사 통과분만 지도에 합친다. 반환 = list(added, rejected(사유 포함), duplicate)
ma_ingest <- function(staging, root = NULL, path = NULL) {
  recs <- tryCatch(fromJSON(staging, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(recs)) stop("[mechanism_atlas] 스테이징 판독 불가: ", staging)
  if (!is.null(recs$records)) recs <- recs$records
  p <- .ma_or(path, ma_path(root))
  cur <- ma_load(path = p)
  keyset <- vapply(cur, function(x) paste(x$paper_key, x$extract_version, sep = "@"), character(1))
  add <- list(); rej <- list(); dup <- 0L
  for (r in recs) {
    bad <- ma_validate(r)
    if (length(bad)) { rej[[length(rej) + 1L]] <- list(paper_key = .ma_or(r$paper_key, "?"), problems = bad); next }
    k <- paste(r$paper_key, r$extract_version, sep = "@")
    if (k %in% keyset) { dup <- dup + 1L; next }
    r$ingested_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
    add[[length(add) + 1L]] <- r; keyset <- c(keyset, k)
  }
  if (length(add)) {
    lines <- c(if (file.exists(p)) readLines(p, encoding = "UTF-8", warn = FALSE) else character(0),
               vapply(add, function(x) as.character(toJSON(x, auto_unbox = TRUE, null = "null", digits = NA)), character(1)))
    lines <- lines[nzchar(trimws(lines))]
    tmp <- paste0(p, ".tmp"); writeLines(lines, tmp, useBytes = TRUE)
    if (!file.rename(tmp, p)) stop("[mechanism_atlas] 원자적 교체 실패: ", p)
  }
  list(added = length(add), rejected = rej, duplicate = dup)
}

#' 지도에 아직 없는 프로그램 재료(논문) — 추출 레인의 일감 목록
ma_pending <- function(n = 5L, root = NULL, registry_path = NULL, atlas_path = NULL) {
  rt <- .ma_root(root)
  if (!exists("pr_load", mode = "function")) source(file.path(rt, "02_Infrastructure/programs/program_registry.R"))
  reg <- pr_load(rt, registry_path)
  have <- vapply(ma_load(path = .ma_or(atlas_path, ma_path(rt))), function(x) .ma_or(x$paper_key, ""), character(1))
  out <- list()
  for (p in reg$programs) for (q in .ma_or(p$queue, list())) {
    if (!identical(.ma_or(q$kind, ""), "paper")) next
    if (q$key %in% have) next
    out[[length(out) + 1L]] <- list(paper_key = q$key, title = .ma_or(q$title, ""), id = .ma_or(q$id, ""),
                                    engine = .ma_or(q$engine, ""), program = p$id)
    if (length(out) >= n) return(out)
  }
  out
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  ## --root <dir>: ★~/.Renviron 의 QM_ROOT 가 호출자 환경변수를 덮는다(메모리 카드 · 10-13 재발 — 검사가 운영 등록부에 씀).
  ##   샌드박스 · 검사 · 레인은 반드시 --root 로 루트를 명시한다.
  rt <- NULL; ri <- match("--root", a)
  if (!is.na(ri) && length(a) > ri) { rt <- a[ri + 1L]; a <- a[-c(ri, ri + 1L)] }
  if (length(a) >= 2L && a[1] == "--ingest") {
    res <- ma_ingest(a[2], root = rt)
    cat(sprintf("[mechanism_atlas] 추가 %d · 거부 %d · 중복 %d\n", res$added, length(res$rejected), res$duplicate))
    for (r in res$rejected) cat(sprintf("  거부 %s: %s\n", r$paper_key, paste(r$problems, collapse = " | ")))
  } else if (length(a) >= 1L && a[1] == "--pending") {
    n <- if (length(a) >= 2L) as.integer(a[2]) else 5L
    cat(toJSON(ma_pending(n, root = rt), auto_unbox = TRUE, pretty = TRUE), "\n")
  } else cat("usage: mechanism_atlas.R --ingest <staging.json> | --pending [N]  [--root <dir>]\n")
}
