#==============================================================================
# factor_db_vintage.R — 측정이 어느 팩터 DB 판 위에서 났는가 (v10.2 · 2026-11-10)
#
# 왜: 11-08~11-10 사이 팩터 DB 가 세 번 크게 고쳐졌다(재무 v2 전환 · 방향/저장 규약 수리 · 총부채 0 수리). 그 전에 잰 등급은
#   "인용 전 재측정"이라고 결정 기록과 문서에 적혀 있지만(FUND-V2-PRIOR-GRADES-REMEASURE-ON-CITE-20261109 · DIRECTION_POLICY §6 ·
#   factor_db_debt_fix_20261110/README), 그 표식을 **읽는 코드가 없었다** — 낡은 등급이 A 자격 관문 · 기저 풀 · 상설 판으로
#   그대로 흘러갈 수 있었다(전수점검 배선 감사 Q2 · Q3). 여기서 그 판정을 기계가 하게 한다.
#
# 무엇: 수리 원장 06_Registry/factor_db_vintage.json(수리마다 완료 시각 · 범위 = 전체 | 팩터 목록)과 측정 산출 폴더의 측정 시각을 견준다.
#   측정이 수리 완료보다 앞서고 그 수리의 범위에 닿으면 낡은 것이다. 범위가 팩터 목록인 수리는, 측정이 자기 팩터 목록을 **선언**했고
#   (칸 사양 · 엔진 기저 아님) 겹치지 않을 때만 비켜 간다 — 임의 코드 엔진은 무엇을 읽었는지 알 수 없으므로 닿은 것으로 본다(보수적).
#
# 쓰는 곳: A 자격 관문(rf_runner_gates.R::rf_a_eligibility 의 상시 보류 factor_db_stale) · P4 기저 풀(round_core v1 p4.R).
# 사용: source(".../factor_db_vintage.R"); fdv_stale("<산출 폴더>", root)   # list(stale = TRUE|FALSE|NA, reason, measured_at, hits, valid_from)
#       Rscript 02_Infrastructure/contracts/factor_db_vintage.R <산출 폴더> [...]         # 폴더마다 한 줄
# PIT: 판정에 성과 수치를 쓰지 않는다(시각 · 선언 팩터만).
#==============================================================================
FDV_SCHEMA <- "factor_db_vintage_v1"
FDV_TZ <- "Asia/Seoul"

.fdv_or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.fdv_root <- function(root = NULL) {
  for (p in c(root, Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
    if (is.null(p) || !nzchar(p)) next
    p <- gsub("\\\\", "/", p)
    if (file.exists(file.path(p, "06_Registry", "factor_db_vintage.json"))) return(p)
  }
  stop("[factor_db_vintage] 프로젝트 루트 해석 실패(06_Registry/factor_db_vintage.json 없음)", call. = FALSE)
}
.fdv_time <- function(x) {
  x <- as.character(.fdv_or(x, NA_character_))[1]
  if (is.na(x) || !nzchar(x)) return(as.POSIXct(NA, tz = FDV_TZ))
  s <- sub("([+-][0-9]{2}):?([0-9]{2})$", "", x)                       # 시간대 표기는 떼고 한국 시각으로 읽는다(원장 · 산출물 모두 KST)
  for (f in c("%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M", "%Y%m%d_%H%M%S", "%Y-%m-%d")) {
    t <- suppressWarnings(as.POSIXct(s, format = f, tz = FDV_TZ)); if (!is.na(t)) return(t)
  }
  as.POSIXct(NA, tz = FDV_TZ)
}

#' 수리 원장 판독 + 검증
fdv_ledger <- function(root = NULL, path = NULL) {
  p <- if (is.null(path)) file.path(.fdv_root(root), "06_Registry", "factor_db_vintage.json") else path
  L <- jsonlite::fromJSON(p, simplifyVector = FALSE)
  if (!identical(L$schema, FDV_SCHEMA)) stop("[factor_db_vintage] 원장 스키마 불일치: ", p, call. = FALSE)
  for (e in L$entries) {
    if (!nzchar(as.character(.fdv_or(e$id, "")))) stop("[factor_db_vintage] id 없는 항목", call. = FALSE)
    sc <- e$scope
    if (!(identical(sc, "all") || (is.list(sc) && length(sc$factors) > 0L)))
      stop("[factor_db_vintage] scope 는 \"all\" 또는 {factors: [...]} — ", e$id, call. = FALSE)
    if (!is.null(e$completed_at) && is.na(.fdv_time(e$completed_at))) stop("[factor_db_vintage] completed_at 형식 — ", e$id, call. = FALSE)
  }
  L
}

#' 측정 시각 — 신호 · 보유를 만든 실행의 시작 시각을 쓴다. 우선순위: 권위 기록 run_id → 폴더 경로의 실행 id → measured_at 류 필드.
#'   (보유에서 다시 잰 기록의 remeasured_at 은 쓰지 않는다 — 보유는 원 실행 때의 팩터 DB 로 만들어졌다.)
fdv_measured_at <- function(dir) {
  dir <- gsub("\\\\", "/", as.character(dir)[1])
  A <- tryCatch(jsonlite::fromJSON(file.path(dir, "authoritative_remeasure.json"), simplifyVector = FALSE), error = function(e) NULL)
  rid <- function(s) { m <- regmatches(s, regexpr("[0-9]{8}_[0-9]{6}", s)); if (length(m)) .fdv_time(m) else as.POSIXct(NA, tz = FDV_TZ) }
  t <- rid(as.character(.fdv_or(A$run_id, "")))
  if (is.na(t)) t <- rid(dir)
  if (is.na(t)) for (k in c("measured_at", "generated_at", "created_at")) { t <- .fdv_time(A[[k]]); if (!is.na(t)) break }
  t
}

#' 측정이 선언한 팩터 목록 — 칸 사양(factors[].id)이 있고 기저가 엔진이 아닐 때만. 그 밖은 NULL(= 알 수 없음).
fdv_declared_factors <- function(dir) {
  dir <- gsub("\\\\", "/", as.character(dir)[1])
  sp <- NULL
  for (f in c("cell_spec.json", "spec.json")) {
    p <- file.path(dir, f)
    if (file.exists(p)) { sp <- tryCatch(jsonlite::fromJSON(p, simplifyVector = FALSE), error = function(e) NULL); if (!is.null(sp)) break }
  }
  if (is.null(sp)) return(NULL)
  bs <- sp$base_signal
  if (is.list(bs) && identical(as.character(.fdv_or(bs$kind, "")), "engine")) return(NULL)        # 엔진 기저 — 엔진이 읽은 팩터를 알 수 없다
  if (!is.null(sp$engine_blend)) return(NULL)
  ids <- vapply(.fdv_or(sp$factors, list()), function(z) as.character(.fdv_or(if (is.list(z)) z$id else z, NA_character_))[1], character(1))
  ids <- ids[!is.na(ids) & nzchar(ids)]
  if (!length(ids)) return(NULL)
  unique(ids)
}

#' 낡았는가 — 측정 시각이 어느 수리의 완료보다 앞서고 그 수리 범위에 닿으면 TRUE.
#'   완료 시각이 없는 항목(진행 중)은 범위에 닿는 모든 측정을 낡은 것으로 본다. 측정 시각을 모르면 NA(판정 불가 — 호출자가 정한다).
fdv_stale <- function(dir, root = NULL, ledger = NULL) {
  L <- if (is.null(ledger)) fdv_ledger(root) else ledger
  m <- fdv_measured_at(dir)
  done <- lapply(L$entries, function(e) if (is.null(e$completed_at)) as.POSIXct(NA, tz = FDV_TZ) else .fdv_time(e$completed_at))
  vf <- suppressWarnings(max(do.call(c, done), na.rm = TRUE))
  vf_s <- if (is.finite(vf)) format(vf, "%Y-%m-%dT%H:%M:%S") else NA_character_
  if (is.na(m)) return(list(stale = NA, reason = "측정 시각을 알 수 없다(실행 id · 측정 시각 필드 없음)", measured_at = NA_character_,
                            hits = character(0), valid_from = vf_s))
  used <- fdv_declared_factors(dir)
  hits <- character(0)
  for (i in seq_along(L$entries)) {
    e <- L$entries[[i]]
    reach <- identical(e$scope, "all") || is.null(used) || length(intersect(used, as.character(unlist(e$scope$factors)))) > 0L
    if (!reach) next
    if (is.na(done[[i]]) || m < done[[i]]) hits <- c(hits, as.character(e$id))
  }
  list(stale = length(hits) > 0L,
       reason = if (length(hits)) sprintf("측정(%s)이 팩터 DB 수리 %s 보다 앞선다 — 재측정 전 인용 · 소비 금지", format(m, "%Y-%m-%d %H:%M"), paste(hits, collapse = " · "))
                else sprintf("측정(%s)이 마지막 수리(%s) 뒤다", format(m, "%Y-%m-%d %H:%M"), .fdv_or(vf_s, "?")),
       measured_at = format(m, "%Y-%m-%dT%H:%M:%S"), hits = hits, valid_from = vf_s,
       declared_factors = if (is.null(used)) NULL else length(used))
}

#' 지금의 판 표식 — 새 측정 기록에 실을 요약(수리 id 와 완료 시각 · 유효 시작)
fdv_stamp <- function(root = NULL) {
  L <- fdv_ledger(root)
  list(schema = FDV_SCHEMA, valid_from = fdv_stale(tempdir(), ledger = L)$valid_from,
       repairs = lapply(L$entries, function(e) list(id = e$id, completed_at = e$completed_at)))
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  if (length(a)) for (d in a) { r <- fdv_stale(d); cat(sprintf("%s\t%s\t%s\n", if (is.na(r$stale)) "unknown" else if (r$stale) "STALE" else "ok", d, r$reason)) }
  else cat("[factor_db_vintage] Loaded — fdv_stale(dir, root) · fdv_ledger(root) · fdv_stamp(root).\n")
}
