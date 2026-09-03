#==============================================================================
# rf_spec_sig.R — 스펙 서명·처치 전달 판정 헬퍼 **정본** (v10.2 2026-09-03 추출)
#
# ★왜 파일로 뽑았나: 이 함수들이 reinforce_auto_parallel.R 과 reinforce_auto_run.R 에
#   각각 정의돼 있었고(.fkeys 는 실제로 두 곳에 중복), 커버리지 색인이 세 번째 복제본을
#   만들 참이었다. 서명이 갈리는 순간 "같은 포트폴리오" 판정이 소비자마다 달라진다.
#   본문은 러너에서 **그대로 옮겼다** — 거동 변경 0.
#
# 제공: .fkey / .fkeys / .dedup_factors / .same_axis / .rp_all_factors / .spec_sig
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
