#==============================================================================
# stat_redactor.R — 수치 가림 규칙 정본 (v10.01 · 2026-10-13 · 구 ops/rf_b1_design_lib.R 에서 원문 그대로 이관)
#
# 왜 옮겼나: 구 B1 설계 레인(rf_b1_design_lib.R)이 고정 격자 강화와 함께 퇴역했는데, 그 파일의 가림 규칙 상수 4개
#   (RF_B1_STAT_PROTECT · RULES · METRIC · MASK)는 등록 훅 arm_gen_read_guard.sh 가 이름으로 읽는 정본이다
#   (hooks/policies/arm_gen_read_guard.json::catalog_view.redactor_source). 규칙 · 이름은 바꾸지 않는다 — 훅 · 청정 레인 ·
#   파이썬↔R 가림 동치 검사(§Q Q29)가 이 이름을 쓴다.
# v10.01 용도: 교훈 카드 · 논문 간 기억에 τ_D(2022-12-31) 이후 수치가 실리지 않게 가린다(개선안 §3.5 · R4).
# 공개: RF_B1_STAT_PROTECT · RF_B1_STAT_RULES · RF_B1_STAT_METRIC · RF_B1_STAT_MASK · rf_b1_redact_stats · rf_b1_has_stats
#==============================================================================
RF_B1_STAT_PROTECT <- c(
  arxiv   = "(?<![A-Za-z0-9_.])\\d{4}\\.\\d{4,5}(v\\d+)?(?![A-Za-z0-9_])",
  version = "(?<![A-Za-z0-9_.])[vV]\\d+(\\.\\d+)+(?![A-Za-z0-9_])",
  yymm    = "(?<![A-Za-z0-9_.])(19[89]\\d|20[0-3]\\d)\\.(0[1-9]|1[0-2])(?![0-9])")
RF_B1_STAT_RULES <- c(
  pct = "[-+\u2212]?\\d+(\\.\\d+)?\\s?(%p?|pp(?![A-Za-z]))",   # (R2 적대 검증 09-25) pp = 퍼센트포인트 — L-code 1,483문장 재현: "5.5pp·2.5pp·3.8pp·4pp" 가 dec(뒤 글자 금지)·%p 둘 다 비껴갔다
  dec = "(?<![A-Za-z0-9_.])[-+\u2212]?\\d*\\.\\d+(?![A-Za-z0-9_])")
## 지표 이름 바로 뒤 정수(PORT_t 3 · IC 1) — 이름은 남기고 수만 가린다(치환 = \\1\\2<stat>)
RF_B1_STAT_METRIC <- "(?i)(?<![A-Za-z0-9_])(port_t|calmar|cagr|mdd|sharpe|icir|ic|dsr|sortino)(\\s*[=:]?\\s*)[-+\u2212]?\\d+(?![A-Za-z0-9_.])"
RF_B1_STAT_MASK <- "<stat>"

#' 전기간 수치 가림 — 식별자 보존 · 소수·백분율·지표 뒤 정수 → <stat>
rf_b1_redact_stats <- function(x) {
  x <- as.character(x)
  if (!length(x)) return(x)
  vapply(x, function(s) {
    if (is.na(s) || !nzchar(s)) return(s)
    keep <- character(0)
    for (rx in RF_B1_STAT_PROTECT) {
      hits <- regmatches(s, gregexpr(rx, s, perl = TRUE))[[1]]
      for (h in hits) { keep <- c(keep, h); s <- sub(h, sprintf("\u27E6%d\u27E7", length(keep)), s, fixed = TRUE) }
    }
    for (rx in RF_B1_STAT_RULES) s <- gsub(rx, RF_B1_STAT_MASK, s, perl = TRUE)
    s <- gsub(RF_B1_STAT_METRIC, paste0("\\1\\2", RF_B1_STAT_MASK), s, perl = TRUE)
    for (k in rev(seq_along(keep))) s <- sub(sprintf("\u27E6%d\u27E7", k), keep[k], s, fixed = TRUE)
    s
  }, character(1), USE.NAMES = FALSE)
}

#' 가림 검증(재도출) — 식별자를 뺀 뒤 소수·백분율·지표 뒤 정수가 하나라도 남았으면 TRUE
rf_b1_has_stats <- function(x) {
  x <- as.character(x); x <- x[!is.na(x)]
  if (!length(x)) return(FALSE)
  for (rx in RF_B1_STAT_PROTECT) x <- gsub(rx, " ", x, perl = TRUE)
  any(vapply(c(RF_B1_STAT_RULES, RF_B1_STAT_METRIC), function(rx) any(grepl(rx, x, perl = TRUE)), logical(1)))
}
