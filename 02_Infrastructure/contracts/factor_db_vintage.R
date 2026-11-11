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
#   ★선언의 출처(G2 수리 11-10) = 측정 기록(권위 기록 authoritative_remeasure.json 의 factor_db_vintage.declared_factors ·
#     declared_factors_basis = "cell_spec") — 충실구현 러너(run_paper_replication.R::.rp_fdv_stamp)가 셀 엔진 실행이면 그 칸 사양
#     (RF_CELL_SPEC)에서 fdv_spec_declared_factors() 로 뽑아 남긴다. 구판은 산출 폴더의 cell_spec.json 만 찾았는데 어떤 측정 경로도 그
#     파일을 쓰지 않아 선언 비켜 가기가 한 번도 발화하지 않았다(팩터 목록 수리 하나가 이후 모든 측정을 낡음으로 묶었다). 폴더의
#     cell_spec.json · spec.json 은 같은 규칙으로 계속 읽는다(둘째 출처). 선언을 모르면 종전처럼 닿은 것으로 본다(보수 쪽).
#   ★진행 중 수리(completed_at = null · 원장 _doc 이 허용하는 형식): 범위에 닿는 측정은 전부 낡음 · 판 표식의 valid_from = NA(아직 유효한
#     판이 없다) · in_progress = 그 id 들 · last_completed = 완료된 수리의 마지막 완료 시각.
#   ★완료 시각 해석(G2 수리 11-10): 원장은 ISO 8601 'YYYY-MM-DDTHH:MM[:SS]' + 명시 오프셋('Z' | ±HH:MM | ±HHMM)만 받고 오프셋을 실제로
#     적용한다(구판은 오프셋을 떼고 KST 로 읽어 'Z' 표기를 9시간 앞당겼고, 'YYYY-MM-DD HH:MM' 을 자정으로 떨어뜨렸다 — 둘 다 완료 시각을
#     앞당기는 fail-open). 해석 못 하면 fdv_ledger 가 멈춘다. 측정 시각(산출물)은 오프셋이 없으면 KST 로 읽는다(산출물 관례 · 같은 규칙으로
#     오프셋이 있으면 적용) — 날짜만이면 그날 자정(측정을 앞당기는 쪽 = 보수).
#
# 쓰는 곳: A 자격 관문(rf_runner_gates.R::rf_a_eligibility 의 상시 보류 factor_db_stale · factor_db_vintage_unreadable) · P4 기저 풀(round_core v1 p4.R) ·
#   2계층 풀 관문(rf_l2_lib.R::l2_a_eligibility) · BOOK writer(book_registry.R).
# 사용: source(".../factor_db_vintage.R"); fdv_stale("<산출 폴더>", root)   # list(stale = TRUE|FALSE|NA, reason, measured_at, hits, valid_from, in_progress, last_completed)
#       Rscript 02_Infrastructure/contracts/factor_db_vintage.R <산출 폴더> [...]         # 폴더마다 한 줄
# PIT: 판정에 성과 수치를 쓰지 않는다(시각 · 선언 팩터만).
#==============================================================================
FDV_SCHEMA <- "factor_db_vintage_v1"
FDV_TZ <- "Asia/Seoul"
FDV_DECL_BASIS <- "cell_spec"     # 측정 기록의 선언 팩터를 믿는 유일한 근거 어휘(러너가 칸 사양에서 뽑았다)

.fdv_or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.fdv_root <- function(root = NULL) {
  for (p in c(root, Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
    if (is.null(p) || !nzchar(p)) next
    p <- gsub("\\\\", "/", p)
    if (file.exists(file.path(p, "06_Registry", "factor_db_vintage.json"))) return(p)
  }
  stop("[factor_db_vintage] 프로젝트 루트 해석 실패(06_Registry/factor_db_vintage.json 없음)", call. = FALSE)
}
.fdv_na <- function() as.POSIXct(NA, tz = FDV_TZ)
.fdv_kst <- function(loc) {                     # 'YYYY-MM-DD HH:MM:SS' 를 KST 벽시계로 — 왕복이 같아야 한다(없는 날짜 · 25시 거부)
  t <- suppressWarnings(as.POSIXct(loc, format = "%Y-%m-%d %H:%M:%S", tz = FDV_TZ))
  if (is.na(t) || !identical(format(t, "%Y-%m-%d %H:%M:%S"), loc)) .fdv_na() else t
}
.FDV_RX <- "^([0-9]{4}-[0-9]{2}-[0-9]{2})([T ])([0-9]{2}:[0-9]{2})(:[0-9]{2})?([.][0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?$"
#' 시각 해석. strict = TRUE(원장 완료 시각): 'T' 구분 · 명시 오프셋 필수 · 소수 초 금지 · 그 밖은 NA(→ fdv_ledger 가 멈춘다).
#'   strict = FALSE(측정 시각): 실행 id 'YYYYMMDD_HHMMSS' · 공백 구분 · 초 없음 · 오프셋 없음(= KST) · 날짜만(= 자정) 허용 · 소수 초는 버림(앞당김 = 보수).
#'   오프셋이 있으면 언제나 실제로 적용한다(Z = UTC).
.fdv_time <- function(x, strict = FALSE) {
  if (is.null(x) || length(x) != 1L || !is.character(x) || is.na(x) || !nzchar(x)) return(.fdv_na())
  if (!strict) {
    if (grepl("^[0-9]{8}_[0-9]{6}$", x))
      return(.fdv_kst(sprintf("%s-%s-%s %s:%s:%s", substr(x, 1, 4), substr(x, 5, 6), substr(x, 7, 8), substr(x, 10, 11), substr(x, 12, 13), substr(x, 14, 15))))
    if (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", x)) return(.fdv_kst(paste(x, "00:00:00")))
  }
  m <- regmatches(x, regexec(.FDV_RX, x, perl = TRUE))[[1]]
  if (!length(m)) return(.fdv_na())
  sep <- m[3]; sec <- m[5]; frac <- m[6]; off <- m[7]
  if (strict && (!identical(sep, "T") || !nzchar(off) || nzchar(frac))) return(.fdv_na())
  loc <- paste0(m[2], " ", m[4], if (nzchar(sec)) sec else ":00")
  if (identical(off, "")) return(.fdv_kst(loc))
  u <- suppressWarnings(as.POSIXct(loc, format = "%Y-%m-%d %H:%M:%S", tz = "UTC"))
  if (is.na(u) || !identical(format(u, "%Y-%m-%d %H:%M:%S", tz = "UTC"), loc)) return(.fdv_na())
  if (!identical(off, "Z")) {
    d <- gsub(":", "", substring(off, 2L), fixed = TRUE); hh <- as.integer(substr(d, 1, 2)); mm <- as.integer(substr(d, 3, 4))
    if (hh > 14L || mm > 59L) return(.fdv_na())
    u <- u - (if (startsWith(off, "-")) -1 else 1) * (hh * 3600 + mm * 60)
  }
  attr(u, "tzone") <- FDV_TZ
  u
}

#' 수리 원장 판독 + 검증(완료 시각 = 엄격 해석 · 해석 못 하면 멈춘다 · null = 진행 중)
fdv_ledger <- function(root = NULL, path = NULL) {
  p <- if (is.null(path)) file.path(.fdv_root(root), "06_Registry", "factor_db_vintage.json") else path
  L <- jsonlite::fromJSON(p, simplifyVector = FALSE)
  if (!identical(L$schema, FDV_SCHEMA)) stop("[factor_db_vintage] 원장 스키마 불일치: ", p, call. = FALSE)
  if (!is.list(L$entries)) stop("[factor_db_vintage] entries 가 목록이 아니다: ", p, call. = FALSE)
  for (e in L$entries) {
    if (!is.list(e) || !nzchar(as.character(.fdv_or(e$id, ""))[1])) stop("[factor_db_vintage] id 없는 항목", call. = FALSE)
    sc <- e$scope
    fl <- if (is.list(sc)) sc$factors else NULL
    if (!(identical(sc, "all") || (is.list(sc) && length(fl) > 0L &&
                                   all(vapply(fl, function(z) is.character(z) && length(z) == 1L && !is.na(z) && nzchar(z), logical(1))))))
      stop("[factor_db_vintage] scope 는 \"all\" 또는 {factors: [\"<id>\", ...]} — ", e$id, call. = FALSE)
    if (!is.null(e$completed_at) && is.na(.fdv_time(e$completed_at, strict = TRUE)))
      stop("[factor_db_vintage] completed_at 형식 — ISO 8601 'YYYY-MM-DDTHH:MM[:SS]' + 명시 오프셋('+09:00' · 'Z')만(진행 중이면 null) — ", e$id, call. = FALSE)
  }
  L
}

#' 측정 시각 — 신호 · 보유를 만든 실행의 시작 시각을 쓴다. 우선순위: 권위 기록 run_id → 폴더 경로의 실행 id → measured_at 류 필드.
#'   (보유에서 다시 잰 기록의 remeasured_at 은 쓰지 않는다 — 보유는 원 실행 때의 팩터 DB 로 만들어졌다.)
fdv_measured_at <- function(dir) {
  dir <- gsub("\\\\", "/", as.character(dir)[1])
  A <- tryCatch(jsonlite::fromJSON(file.path(dir, "authoritative_remeasure.json"), simplifyVector = FALSE), error = function(e) NULL)
  rid <- function(s) { m <- regmatches(s, regexpr("[0-9]{8}_[0-9]{6}", s, perl = TRUE)); if (length(m)) .fdv_time(m) else .fdv_na() }
  t <- rid(as.character(.fdv_or(A$run_id, ""))[1])
  if (is.na(t)) t <- rid(dir)
  if (is.na(t)) for (k in c("measured_at", "generated_at", "created_at")) { v <- A[[k]]; t <- .fdv_time(if (is.character(v)) v[1] else NULL); if (!is.na(t)) break }
  t
}

#' 칸 사양 → 선언 팩터(팩터 DB 에서 읽는 팩터 id). 셀 엔진(rf_cell_engine.R)이 팩터 DB 를 읽는 길은 factors[].kind = "db" 만이라고
#'   확인된 모양일 때만 그 id 목록(없으면 character(0) = 팩터 DB 팩터를 읽지 않음)을 낸다. 팩터 DB 를 따로 읽을 수 있는 부품이 있으면 NULL
#'   (= 알 수 없음 → 범위가 팩터 목록인 수리도 닿은 것으로):
#'   기저 = 엔진 · 엔진 결합 · 모르는 종류(허용 = 생략 | mom_12_1 — 종가만 쓴다) · engine_blend · defense_sleeve(rf_sleeve.R 가 팩터 DB 를 읽는다) ·
#'   'none' 이 아닌 오버레이 층(파일 arm 은 팩터 DB 를 읽을 수 있다 — pg2_risk_overlay) · 표본이 아닌 Σ 공급자(rf_factor_cov.R) ·
#'   팩터 종류가 db | price | null_perm | none 밖 · db 팩터의 id 없음 · cap_core 모양을 모름.
#'   cap_core 위성 = random_beta_matched ∧ beta_kind = db(기본) 이면 그 beta_factor 가 선언에 더해진다(엔진 §5.4 가 팩터 DB 에서 읽는다).
fdv_spec_declared_factors <- function(sp) {
  if (!is.list(sp) || is.null(names(sp))) return(NULL)
  bs <- sp$base_signal
  if (!is.null(bs)) {
    if (!is.list(bs)) return(NULL)
    if (!identical(as.character(.fdv_or(bs$kind, ""))[1], "mom_12_1")) return(NULL)
  }
  if (!is.null(sp$engine_blend) || !is.null(sp$defense_sleeve)) return(NULL)
  layers <- function(x) if (is.null(x)) list() else if (is.list(x) && !is.null(x$kind)) list(x) else if (is.list(x)) x else list(x)
  for (z in c(layers(sp$overlay), layers(sp$overlay_cell)))
    if (!(is.list(z) && identical(as.character(.fdv_or(z$kind, "none"))[1], "none"))) return(NULL)
  wt <- sp$weighting
  if (!is.null(wt)) {
    if (!is.list(wt)) return(NULL)
    if (!is.null(wt$sigma_provider) && !identical(as.character(wt$sigma_provider)[1], "sample")) return(NULL)
  }
  ids <- character(0)
  # ★cap_core(G2 재수리 11-10 · 검증자 지적): 위성 = random_beta_matched 이면 셀 엔진이 .load_factor(list(kind = beta_kind, id = beta_factor))
  #   로 팩터 DB 를 읽는다(rf_cell_engine.R §5.4 · beta_kind 기본 = "db" — rf_capcore.R::rf_cc_parse). 그 베타 팩터를 선언에 더한다.
  #   satellite = floor(기본)은 코어 = K200 멤버십 · 시총 · 거래대금(RAWDATA)만 쓴다. 모양을 모르면 NULL(알 수 없음 = 닿은 것으로).
  cc <- sp$cap_core
  if (!is.null(cc) && length(cc)) {
    if (!is.list(cc)) return(NULL)
    sat <- if (is.null(cc$satellite)) "floor" else cc$satellite
    if (!(is.character(sat) && length(sat) == 1L && !is.na(sat))) return(NULL)
    if (identical(sat, "random_beta_matched")) {
      bk <- if (is.null(cc$beta_kind)) "db" else cc$beta_kind
      if (!(is.character(bk) && length(bk) == 1L && !is.na(bk))) return(NULL)
      if (identical(bk, "db")) {
        bf <- cc$beta_factor
        if (!(is.character(bf) && length(bf) == 1L && !is.na(bf) && nzchar(bf))) return(NULL)
        ids <- c(ids, bf)
      } else if (!(bk %in% c("price", "none", "null_perm"))) return(NULL)
    } else if (!identical(sat, "floor")) return(NULL)
  }
  fl <- if (!is.null(sp$factors)) sp$factors else Filter(Negate(is.null), list(sp$factor2, sp$factor3))
  if (!is.list(fl)) return(NULL)
  for (f in fl) {
    if (is.null(f)) next
    if (!is.list(f)) return(NULL)
    k <- as.character(.fdv_or(f$kind, ""))[1]
    if (k %in% c("none", "price", "null_perm")) next
    if (!identical(k, "db")) return(NULL)
    id <- f$id
    if (!(is.character(id) && length(id) == 1L && !is.na(id) && nzchar(id))) return(NULL)
    ids <- c(ids, id)
  }
  unique(ids)
}

#' 측정이 선언한 팩터 목록 — ① 측정 기록(권위 기록 factor_db_vintage.declared_factors · basis = "cell_spec") ② 산출 폴더의 칸 사양
#'   (cell_spec.json · spec.json → fdv_spec_declared_factors). character(0) = 팩터 DB 팩터를 읽지 않음 · NULL = 알 수 없음.
fdv_declared_factors <- function(dir) {
  dir <- gsub("\\\\", "/", as.character(dir)[1])
  A <- tryCatch(jsonlite::fromJSON(file.path(dir, "authoritative_remeasure.json"), simplifyVector = FALSE), error = function(e) NULL)
  fv <- if (is.list(A) && is.list(A$factor_db_vintage)) A$factor_db_vintage else NULL
  basis <- if (is.list(fv)) as.character(.fdv_or(fv$declared_factors_basis, ""))[1] else ""
  if (identical(basis, "cell_spec")) {
    df <- fv$declared_factors
    if (is.list(df) && identical(as.character(.fdv_or(fv$status, ""))[1], "ok") &&
        all(vapply(df, function(z) is.character(z) && length(z) == 1L && !is.na(z) && nzchar(z), logical(1))))
      return(unique(as.character(unlist(df))))
  }
  for (f in c("cell_spec.json", "spec.json")) {
    p <- file.path(dir, f)
    if (file.exists(p)) {
      sp <- tryCatch(jsonlite::fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
      if (!is.null(sp)) return(fdv_spec_declared_factors(sp))
    }
  }
  NULL
}

#' 원장 요약 — 완료 시각(엄격 해석 · 해석 못 하면 진행 중과 같이 다룬다 = 낡음 쪽) · 진행 중 id · 유효 시작(진행 중이 있으면 NA)
.fdv_summary <- function(L) {
  done <- lapply(L$entries, function(e) if (is.null(e$completed_at)) .fdv_na() else .fdv_time(e$completed_at, strict = TRUE))
  open <- vapply(done, is.na, logical(1))
  lc <- if (any(!open)) suppressWarnings(max(do.call(c, done[!open]))) else .fdv_na()
  lc_s <- if (!is.na(lc)) format(lc, "%Y-%m-%dT%H:%M:%S", tz = FDV_TZ) else NA_character_
  list(done = done, in_progress = vapply(L$entries[open], function(e) as.character(e$id)[1], character(1)),
       last_completed = lc_s, valid_from = if (any(open)) NA_character_ else lc_s)
}

#' 낡았는가 — 측정 시각이 어느 수리의 완료보다 앞서고 그 수리 범위에 닿으면 TRUE.
#'   완료 시각이 없는 항목(진행 중)은 범위에 닿는 모든 측정을 낡은 것으로 본다. 측정 시각을 모르면 NA(판정 불가 — 호출자가 정한다).
#' @param declared 선언 팩터를 호출자가 직접 줄 때(측정 기록을 쓰기 전의 러너 — .rp_fdv_stamp). NULL = 폴더에서 읽는다(fdv_declared_factors).
fdv_stale <- function(dir, root = NULL, ledger = NULL, declared = NULL) {
  L <- if (is.null(ledger)) fdv_ledger(root) else ledger
  m <- fdv_measured_at(dir)
  S <- .fdv_summary(L)
  if (is.na(m)) return(list(stale = NA, reason = "측정 시각을 알 수 없다(실행 id · 측정 시각 필드 없음)", measured_at = NA_character_,
                            hits = character(0), valid_from = S$valid_from, in_progress = S$in_progress, last_completed = S$last_completed))
  used <- if (!is.null(declared)) unique(as.character(declared)) else fdv_declared_factors(dir)
  hits <- character(0); byp <- character(0)   # byp = 측정보다 늦게 끝났거나 진행 중이지만 선언 팩터가 범위 밖이라 비켜 간 수리
  for (i in seq_along(L$entries)) {
    e <- L$entries[[i]]
    later <- is.na(S$done[[i]]) || m < S$done[[i]]
    reach <- identical(e$scope, "all") || is.null(used) || length(intersect(used, as.character(unlist(e$scope$factors)))) > 0L
    if (!reach) { if (later) byp <- c(byp, as.character(e$id)); next }
    if (later) hits <- c(hits, as.character(e$id))
  }
  ms <- format(m, "%Y-%m-%d %H:%M", tz = FDV_TZ)
  list(stale = length(hits) > 0L,
       reason = if (length(hits)) sprintf("측정(%s)이 팩터 DB 수리 %s 보다 앞선다(진행 중 수리는 완료 전까지 닿는 측정 전부) — 재측정 전 인용 · 소비 금지",
                                          ms, paste(hits, collapse = " · "))
                else if (length(byp)) sprintf("측정(%s)은 수리 %s 보다 앞서거나 그 수리가 진행 중이지만 선언 팩터(%d개)가 그 범위(팩터 목록) 밖이다 — 닿는 수리는 모두 측정 전에 끝났다",
                                              ms, paste(byp, collapse = " · "), length(used))
                else sprintf("측정(%s)이 마지막 수리(%s) 뒤다", ms, .fdv_or(S$last_completed, "?")),
       measured_at = format(m, "%Y-%m-%dT%H:%M:%S", tz = FDV_TZ), hits = hits, valid_from = S$valid_from,
       in_progress = S$in_progress, last_completed = S$last_completed, bypassed = byp,
       declared_factors = if (is.null(used)) NULL else length(used))
}

#' 지금의 판 표식 — 새 측정 기록에 실을 요약(수리 id 와 완료 시각 · 유효 시작). 진행 중 수리가 있으면 valid_from = NA 와 in_progress 를 싣는다
#'   (완료 수리뿐이면 종전 모양 그대로 — P4 판 표식 지문(rc_p4_vintage_default)이 바뀌지 않게).
fdv_stamp <- function(root = NULL) {
  L <- fdv_ledger(root)
  S <- .fdv_summary(L)
  out <- list(schema = FDV_SCHEMA, valid_from = S$valid_from,
              repairs = lapply(L$entries, function(e) list(id = e$id, completed_at = e$completed_at)))
  if (length(S$in_progress)) out$in_progress <- as.list(S$in_progress)
  out
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  if (length(a)) for (d in a) { r <- fdv_stale(d); cat(sprintf("%s\t%s\t%s\n", if (is.na(r$stale)) "unknown" else if (r$stale) "STALE" else "ok", d, r$reason)) }
  else cat("[factor_db_vintage] Loaded — fdv_stale(dir, root) · fdv_ledger(root) · fdv_stamp(root) · fdv_spec_declared_factors(spec).\n")
}
