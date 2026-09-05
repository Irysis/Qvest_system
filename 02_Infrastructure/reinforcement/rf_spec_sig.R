#==============================================================================
# rf_spec_sig.R — 스펙 서명·처치 전달 판정 헬퍼 **정본** (v10.2 2026-09-03 추출)
#
# ★왜 파일로 뽑았나: 이 함수들이 reinforce_auto_parallel.R 과 reinforce_auto_run.R 에
#   각각 정의돼 있었고(.fkeys 는 실제로 두 곳에 중복), 커버리지 색인이 세 번째 복제본을
#   만들 참이었다. 서명이 갈리는 순간 "같은 포트폴리오" 판정이 소비자마다 달라진다.
#   본문은 러너에서 **그대로 옮겼다** — 거동 변경 0.
#
# 제공: .rf_attempt_code / .rf_taken_codes / .rf_free_cells / .fkey / .fkeys / .dedup_factors / .same_axis / .rp_all_factors / .spec_sig / .ov_layers / .ov_stack / .ov_arm_ids
# 요구: jsonlite(toJSON) · %||%
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

# ── 처치 전달 판정 헬퍼 ──────────────────────────────────────────────────────
# 팩터 동일성은 kind+식별자로 본다. 라벨·주석 차이는 같은 팩터를 다르게 보이게 할 뿐이다.
.fkey <- function(f) paste0(f$kind %||% "", ":",
                            f$id %||% f$catalog_id %||% f$label %||% f$flag %||% "")
.fkeys <- function(fs) sort(vapply(fs %||% list(), .fkey, character(1)))
.dedup_factors <- function(fs) { seen <- character(0); out <- list()
  for (f in fs %||% list()) { k <- .fkey(f)
    if (!(k %in% seen)) { seen <- c(seen, k); out[[length(out) + 1L]] <- f } }
  out }
# ── 오버레이 층 합성 (v10.2 중첩) ────────────────────────────────────────────
# 오버레이는 단수 객체 · 층 리스트 · NULL 세 형태로 온다. 이 둘이 그 셋을 정규화한다.
# ★단층이면 **구판 단수 형태 그대로** 돌려준다 — 시그니처(toJSON)가 바뀌면 기존 측정이
#   전부 미측정으로 되살아나 격자가 같은 칸을 다시 태운다.
.ov_layers <- function(x) {
  if (is.null(x)) return(list())
  if (!is.null(x$kind)) return(list(x))
  Filter(function(z) is.list(z) && !is.null(z$kind), x)
}
#' 오버레이(단수·리스트·NULL)에서 arm_id 를 전부 뽑는다. 제외 목록의 정본.
.ov_arm_ids <- function(ov) {
  L <- .ov_layers(ov)
  v <- as.character(unlist(lapply(L, function(z) z$arm_id %||% "")))
  v[nzchar(v)]
}
.ov_stack <- function(...) {
  L <- unlist(lapply(list(...), .ov_layers), recursive = FALSE)
  L <- Filter(function(z) !identical(as.character(z$kind %||% "none"), "none"), L)
  if (!length(L)) return(NULL)
  # 같은 arm 을 두 번 얹지 않는다(부모가 깔아둔 것을 자식이 또 곱하면 이중 축소).
  L <- L[!duplicated(vapply(L, function(z) paste0(z$kind, "~", z$arm_id %||% ""), character(1)))]
  if (length(L) == 1L) L[[1]] else L
}

.same_axis <- function(a, b) identical(as.character(toJSON(a %||% list(), auto_unbox = TRUE)),
                                       as.character(toJSON(b %||% list(), auto_unbox = TRUE)))
# ★측정에 영향을 주는 축 전부를 한 줄 서명으로 접는다. 두 칸의 서명이 같으면 **같은
#   포트폴리오**다 — 이름이 달라도 그렇다. carry 대조만으로는 부족하다는 것이 실증됐다:
#   2026-08-31 B4_16~19 는 carry 와도 다르고(유니버스가 격자 기본값으로 떨어졌다)
#   **서로는 같아서** 같은 t(2.241)를 네 번 냈는데 어떤 가드도 발화하지 않았다.
# ★팩터는 두 자리에 담긴다. 승계 entry 는 factors(복수), **carry 없는 최초 entry 는
#   factor2/factor3**(carry 병합 블록이 안 돌아 factors 가 설정되지 않는다).
#   factors 만 보면 최초 entry 의 B1 다섯 칸이 전부 "팩터 없음" 으로 같은 서명이 되어
#   1칸만 남고 4칸이 중복으로 닫힌다(2026-08-31 실사고: B1_2~B1_5 소실).
#   중복 가드가 정상 칸을 죽인 것이다 — 서명은 **실제로 측정에 들어가는 축 전부**를 봐야 한다.
.rp_all_factors <- function(sp) {
  fs <- sp$factors
  if (!is.null(fs) && length(fs)) return(fs)
  out <- list()
  if (!is.null(sp$factor2) && !identical(sp$factor2$kind %||% "", "none")) out <- c(out, list(sp$factor2))
  if (!is.null(sp$factor3) && !identical(sp$factor3$kind %||% "", "none")) out <- c(out, list(sp$factor3))
  out
}
.spec_sig <- function(sp) paste(c(
  paste(.fkeys(.rp_all_factors(sp)), collapse = "+"),
  # ★기저 가중은 측정에 들어가는 축이다 — w0 만 다른 두 칸은 다른 포트폴리오다(2026-09-01)
  as.character(sp$base_weight %||% "ew"),
  as.character(toJSON(sp$weighting %||% list(kind = "ew"),          auto_unbox = TRUE)),
  as.character(toJSON(sp$universe  %||% list(kind = "k200_kq150"),  auto_unbox = TRUE)),
  as.character(toJSON(sp$overlay   %||% list(),                     auto_unbox = TRUE)),
  as.character(sp$base_signal$path %||% sp$base_signal$kind %||% "")), collapse = "|")

# ── ★격자 커서 — 자리를 차지한 셀 코드 집합 (2026-09-04 신설) ────────────────
# 구판 커서는 `cells[[attempts_used + 1L]]` — **개수**였다. 등록이 한 건 거부되면
# (rf_append_attempt 의 stop) 배치는 안 서고 그 칸만 조용히 빠지는데, 개수 기반이라
# 격자 위치와 시도 수가 그 순간부터 **영구히** 어긋난다.
#   실측 2026-09-03: root_papers 의무(그날 도훈이 해제한 바로 그것)가 B1_1 을 세 번 거부 →
#   B1_1 은 영영 미측정, B1_5 는 두 번 소각(서로 다른 spec·다른 t). spec 파일 이름이 셀 코드라
#   재실행분이 원본을 덮었고, RP_20260903_105808_combo 는 승자 B1_5(t 1.578·5팩터)의 스펙이
#   1팩터(t 1.025)로 바뀐 채 B2~B4 20칸이 그 위에 섰다. 축 검사는 전부 통과했다.
# 그래서 커서는 개수가 아니라 **기록된 코드 집합**에서 뽑는다. 개수(used)는 예산이지 위치가 아니다.
#
# 출처 우선순위 — 등록 필드 > 측정 산출 > 서술 접두 > 격자 위치(구 레코드 폴백).
.rf_attempt_code <- function(a, cells = NULL) {
  .one <- function(x) { x <- suppressWarnings(as.character(x))
                        x <- x[!is.na(x) & nzchar(x)]
                        if (length(x)) x[1] else NA_character_ }
  cc <- .one(a$cell_code);            if (!is.na(cc)) return(cc)
  cc <- .one(a$essence$cell_code);    if (!is.na(cc)) return(cc)
  ide <- .one(a$idea)
  # ★기본 regexpr 은 POSIX ERE 라 \b(단어 경계)가 없다 — 쓰면 매칭이 조용히 실패한다.
  if (!is.na(ide)) { m <- regmatches(ide, regexpr("B[0-9]+_[0-9]+", ide))
                     if (length(m) && nzchar(m[1])) return(m[1]) }
  if (!is.null(cells)) { n <- suppressWarnings(as.integer(a$n %||% NA_integer_))
    if (!is.na(n) && n >= 1L && n <= length(cells)) return(.one(cells[[n]]$code)) }
  NA_character_
}
#' @return 이 entry 가 이미 자리를 차지한 셀 코드(중복·NA 제거)
.rf_taken_codes <- function(attempts, cells = NULL) {
  if (!length(attempts %||% list())) return(character(0))
  v <- vapply(attempts, .rf_attempt_code, character(1), cells = cells)
  unique(v[!is.na(v) & nzchar(v)])
}
#' 아직 자리가 비어 있는 격자 셀의 **인덱스** (격자 순서 유지 — 블록 순서 정렬 후 호출할 것)
.rf_free_cells <- function(cells, attempts) {
  tk <- .rf_taken_codes(attempts, cells)
  which(!vapply(cells, function(c) as.character(c$code %||% "") %in% tk, logical(1)))
}

#' 재개(resume) 대상 attempt 가 어느 셀인가 — **코드로** 찾는다 (2026-09-05).
#'   실사고 promo2 B4 재시도: 실패 칸은 essence 가 없어 구판이 cells[[a$n]] **위치**로 떨어졌는데,
#'   B3 설계가 4칸이라 cells 가 24개뿐 → n=21→B4_22 · n=22→B4_23 · n=25→NULL. n=22(B4_22) 에 B4_23 결과가
#'   중복 기록되고 n=25 는 영구 pending(소진 불가). 등록 시점에 박은 a$cell_code 를 안 읽었다.
#' @return list(cell, how) — how ∈ essence_code / registered_code / positional_legacy / unknown
rf_resume_cell <- function(a, cells, by_code) {
  cd <- a$essence$cell_code %||% a$cell_code %||% NULL
  if (!is.null(cd) && nzchar(as.character(cd))) {
    cell <- by_code(as.character(cd))
    if (!is.null(cell)) return(list(cell = cell, how = if (!is.null(a$essence$cell_code)) "essence_code" else "registered_code"))
    return(list(cell = NULL, how = "unknown"))
  }
  ## 코드가 전혀 없는 구 entry 만 위치로 — 그리고 그 사실을 남긴다(조용한 폴백 아님)
  n <- suppressWarnings(as.integer(a$n))
  if (!is.na(n) && n >= 1L && n <= length(cells)) return(list(cell = cells[[n]], how = "positional_legacy"))
  list(cell = NULL, how = "unknown")
}

#' 격자 소진 판정 — 격자의 모든 칸에 시도(측정 또는 terminal)가 있고 미측정(재개 대상) 시도가 없으면 TRUE.
#'   ★예산(max_attempts)과 별개다 (2026-09-05 실사고): B1 설계 9칸으로 예산이 25→29 로 올랐는데 B3 설계가 4칸이라
#'   격자 총합이 28 — used 28 < 29 라 소진 판정(used >= MAXA)이 영영 안 서고 러너가 매 tick halt_no_jobs 만 찍었다
#'   (승격·다음 논문 모두 정지). 격자가 다 찼으면 예산이 남아도 소진이다.
#' @param cells 격자 칸 목록(list of list(code=...)) — 설계 적용 후 전 블록
#' @param attempts 원장 entry 의 attempts
rf_grid_consumed <- function(cells, attempts) {
  if (!length(cells %||% list())) return(FALSE)
  if (length(.rf_free_cells(cells, attempts))) return(FALSE)          # 빈 칸이 남았다 — 커서와 같은 정의
  pending <- Filter(function(a) (is.null(a$essence) || is.null(a$essence$port_t)) && !isTRUE(a$terminal),
                    attempts %||% list())
  !length(pending)                                                     # 재개 대상이 남았으면 아직 아니다
}
