# wp4_defensive_route.R — 2계층 풀의 방어형 경로 재채점
#
# 왜: 2계층이 보는 풀의 2/3 가 등급 floor 를 못 넘고 방어형 경로로 들어온 C·F 모듈이다.
#     그 수락 규칙은 2026-09-04 일회 측정으로 넓어졌고 그 뒤 재채점된 적이 없다.
# 무엇을: 수락 사유 문자열에 실린 근거(하락월 초과·t·적중률·깊은 낙폭 초과·상승월 초과)를
#     파싱해, '방어형' 라벨이 **깊은 낙폭에서도** 성립하는지 센다.
# ★새 백테스트 0회. 풀 파일 읽기 전용.
# ★연계 기록: 작은 하락월 평균으로 붙은 방어형 라벨이 GFC·2022 에서 깨진 전례가 있다.

suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

wp4_parse_pool <- function(path = "C:/Users/99922/OneDrive/Quant_Module_Moltbot/06_Registry/module_performance.json") {
  j <- fromJSON(path, simplifyVector = FALSE)
  rows <- lapply(j$modules, function(m) {
    rs <- as.character(m$admission_reason %||% "")
    num <- function(pat) {
      x <- regmatches(rs, regexpr(pat, rs))
      if (!length(x)) return(NA_real_)
      suppressWarnings(as.numeric(gsub("[^0-9.+-]", "", sub(pat, "\\1", x))))
    }
    data.frame(
      id     = as.character(m$source_strategy_id %||% NA),
      grade  = as.character(m$grade %||% NA),
      route  = as.character(m$admission_route %||% "-"),
      role   = as.character(m$role %||% NA),
      sharpe = suppressWarnings(as.numeric(m$full_sharpe %||% NA)),
      n_down      = num("하락월 ([0-9]+)개"),
      down_excess = num("하락월 [0-9]+개: 초과 ([+-][0-9.]+)%"),
      down_t      = num("t ([0-9.+-]+) "),
      hit         = num("적중 ([0-9]+)%"),
      n_deep      = num("벤치-10% 이하 ([0-9]+)개"),
      deep_excess = num("벤치-10% 이하 [0-9]+개: 초과 ([+-][0-9.]+)%"),
      up_excess   = num("상승월 초과 ([+-][0-9.]+)%"),
      stringsAsFactors = FALSE)
  })
  d <- do.call(rbind, rows)
  attr(d, "generated") <- as.character(j$generated %||% NA)
  attr(d, "floor") <- as.character(j$grade_floor %||% NA)
  d
}
