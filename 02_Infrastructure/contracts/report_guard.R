## report_guard.R — 보고 줄의 **무음 증발** 차단 (2026-08-09 실사고)
## 기전: 존재하지 않는 리스트 필드 → NULL → 산술 결과 numeric(0) →
##   sprintf(fmt, numeric(0)) = character(0) → cat() 이 **줄 전체를 출력하지 않는다**.
##   오류도 경고도 없다. "쟀는데 산출물엔 없다" 의 가장 조용한 판본.
##   실사고: 귀무 창 게이트가 두 스크립트 연속 침묵 — nl$observed 는 없는 필드였다.
## ★규약: 측정 스크립트의 보고 함수는 반드시 이 가드를 경유한다.
say_guarded <- function(fmt, ..., prefix = "", strict = TRUE) {
  a <- list(...)
  bad <- which(vapply(a, function(z) length(z) == 0L, logical(1)))
  if (length(bad)) {
    msg <- sprintf("%s보고 인자 %s 가 길이 0 — 줄이 증발할 뻔했습니다 (fmt: %s)",
                   prefix, paste(bad, collapse=","), substr(fmt, 1, 60))
    if (isTRUE(strict)) stop(msg) else { warning(msg); return(invisible(FALSE)) }
  }
  cat(sprintf(paste0(prefix, fmt, "\n"), ...)); flush.console(); invisible(TRUE)
}
## 리스트 필드 접근 가드 — 오타/개명된 필드를 NULL 로 흘리지 않는다
field <- function(x, nm) {
  if (!nm %in% names(x))
    stop(sprintf("필드 '%s' 부재. 실제 필드: %s", nm, paste(names(x), collapse=",")))
  x[[nm]]
}
message("[report_guard.R] Loaded — say_guarded() / field()")
