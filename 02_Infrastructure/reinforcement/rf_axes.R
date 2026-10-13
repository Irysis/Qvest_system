#==============================================================================
# rf_axes.R — 처방 · 조립 고정 축 단정 (v10.01 · MC5 2026-10-13)
#
# 왜: 셀 엔진은 비중 단계와 cap_core 합성 뒤에 '|Σw − 1| < 1e-8'을 단정했다(rf_cell_engine.R 구 :520 · :547).
#   결정 D11(2026-10-13 도훈)은 처방 · 조립 축을 **Σw ≤ 1(잔여 현금)** 으로 바꿨다 — 현금으로 방어하는 처방을
#   엔진이 단정으로 막으면 결정이 측정에 닿지 않는다(설계 §9.3 '현금' 행 · 등록부 MC5).
# 무엇을 막나(불변): 음수 비중(long-only) · 레버리지(Σw > 1) · 빈 포트폴리오(Σw = 0) · 보유 > n_max.
# 무엇을 허용하나(신규): 0 < Σw < 1 — 나머지는 현금. 하네스는 레그 수익에 GL = Σw 를 곱하므로(replication_harness.R
#   Rg = GL·Lr) 현금 수익은 0 이다(무위험 수익 미부여 — 전략에 보수적).
# 공개: rf_assert_axes(P, n_max, tol, where)
# 검사: 08_Tests/reinforcement/test_rf_axes.R
#==============================================================================

#' 고정 축 단정 — long-only · 0 < Σw ≤ 1 · 보유 ≤ n_max (날짜별)
#' @param P      data.table(Date, Weight, ...) — 엔진 PORTFOLIO
#' @param n_max  보유 상한(NULL 이면 검사 안 함)
#' @param tol    수치 허용오차
#' @param where  오류 문구에 붙일 위치 표식
#' @return 날짜별 data.table(Date, s = Σw, n = 보유 수) — 보이지 않게
rf_assert_axes <- function(P, n_max = NULL, tol = 1e-8, where = "") {
  if (!data.table::is.data.table(P) || !all(c("Date", "Weight") %in% names(P)))
    stop("[rf_axes] PORTFOLIO(Date, Weight) 가 아니다", where)
  if (!nrow(P)) stop("[rf_axes]", where, " 빈 PORTFOLIO")
  if (any(!is.finite(P$Weight))) stop("[rf_axes]", where, " 비중에 결측 · 비유한 값")
  if (any(P$Weight < -tol)) stop(sprintf("[rf_axes]%s 음수 비중(최소 %.3g) — long-only 위반", where, min(P$Weight)))
  s <- P[, list(s = sum(Weight), n = .N), by = Date]
  if (any(s$s > 1 + tol)) stop(sprintf("[rf_axes]%s Σw > 1 (최대 %.8f) — 레버리지 금지(Σw ≤ 1 · D11)", where, max(s$s)))
  if (any(s$s <= tol)) stop(sprintf("[rf_axes]%s Σw = 0 인 날짜 %d개 — 빈 포트폴리오", where, sum(s$s <= tol)))
  if (!is.null(n_max) && any(s$n > n_max))
    stop(sprintf("[rf_axes]%s 보유 %d종 > n_max %d (날짜 %d개)", where, max(s$n), as.integer(n_max), sum(s$n > n_max)))
  invisible(s)
}

#' 상위 n 선정 — 날짜별 Score 내림차순 (MC1 동점 규칙 · 2026-10-13 · 설계 §9.4-1)
#'   tie = NULL → 구판 그대로(같은 Score 는 행 순서 = 종목코드 순으로 깨진다 · 구 측정 축 비트 동일).
#'   tie = 열 이름 → 같은 Score 를 그 열 내림차순으로 깬다(측정 축 ALL_HYG 에서 20일 거래대금 t−1) · 결측은 뒤로.
#'   ★설계의 동점 규칙 ①(절단 전 원값 순위)은 팩터 커넥터가 방향을 맞춘 z 만 내서 아직 못 쓴다 — ② 거래대금만 적용(후속).
rf_select_top <- function(P, n, tie = NULL) {
  if (is.null(tie)) return(P[order(Date, -Score)][, head(.SD, n), by = Date])
  if (!tie %in% names(P)) stop("[rf_axes] 동점 열 없음: ", tie)
  Q <- data.table::copy(P)
  Q[, .neg_tie := -as.numeric(get(tie))]
  data.table::setorderv(Q, c("Date", "Score", ".neg_tie"), order = c(1L, -1L, 1L), na.last = TRUE)
  Q <- Q[, head(.SD, n), by = Date]
  Q[, .neg_tie := NULL]
  Q[]
}
