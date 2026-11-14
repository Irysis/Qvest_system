#==============================================================================
# price_continuity.R — 팩터 빌더용 연속 가격 배율(px_cont) · 2026-11-13 (도훈 "1번은 다시 계산해주고")
#
# 왜: RAWDATA 의 수정주가는 원천 이음매에서 조정 기준이 끊긴다(2026-03-30 퀀티 base → 증분 수출본 · 362종 · ×5 · ×2 · ×0.1 …).
#   수익률(Ret)은 이음매 처분(seam_scale_guard.R 배율 정정 · 차단, rawdata_seam_audit.R 차단)으로 고쳐졌지만, Close **수준**은 그대로라
#   날짜를 넘는 가격 비율을 쓰는 팩터(52주 고 · 저점 대비 · 로그가격 기울기 · 이평 괴리 · MACD · RSI · 시가 갭 · ADX · 가격 수익)가
#   창이 03-30 을 지나는 동안(2026-03 ~ 2027-03) 틀린 값을 냈다(예: 10:1 분할 종목의 52주 고점 대비 ≈ 0.1).
#
# 무엇: 종목마다 '저장 Ret 이 생가격 비율과 다른 자리'에서만 1 이 아닌 보정 계수를 누적한 배율 px_cont 를 만든다.
#   m_t = (1 + Ret_t) / (Close_t / Close_{t-1})   Ret 유한 ∧ Ret ≠ 생비율(배율 정정된 이음매)
#       = 1 / (Close_t / Close_{t-1})             Ret NA ∧ 생비율 유한(미측정 처리 — 그날 움직임 0 = 측정 하네스가 NA 를 0 으로 읽는 것과 같다)
#       = 1                                       그 밖(정확히 1 — 곱해도 값이 비트 단위로 같다)
#   px_cont_t = Π_{s ≤ t} m_s (종목 안) · 연속 가격 = Close × px_cont · Open/High/Low 도 같은 배율 · 거래량 = Vol / px_cont(거래대금 불변).
#   ★날짜를 넘는 비율 = (1 + Ret) 의 연쇄와 같아진다. 같은 날 비율(고가/저가 · 종가/시가)은 배율이 약분돼 그대로다.
#   ★PIT: m_t 는 그날까지의 값(Close_t · Close_{t-1} · Ret_t)만 쓴다. 정정 자리 이전 행은 배율이 정확히 1 이다 — 실측(2026-11-13):
#     전 기간에서 Ret 이 생비율과 다른 행 = 2026년 355행뿐(배율 정정 281 · 미측정 74) → 2025년 이전(IS 전체) 팩터 값은 비트 단위로 같다.
#   ★가격 수준 자체(로그 가격 · 동전주 바닥 · 주당 지표 ÷ 가격)는 이 배율을 쓰지 않는다 — 수준의 PIT 경계(이후 기업행위 반영)는 별개 결정이다.
#
# 소비: factor_db_builder.R::.load_base_data 가 RAWDATA 에 px_cont 열을 붙인다 · 모듈은 열이 있을 때만 쓴다(없으면 1 — 시험 · 구 호출 호환).
#   compute_momentum(M05 · M06 · M16 · M17 · M19 · M20) · compute_technical(가격 · 거래량 계열) · compute_defense(D40 Yang-Zhang) ·
#   compute_liquidity(L39 야간 스프레드) · compute_value(V21 복합 지분발행) · compute_crowding(TR01 ADX) · compute_custom_factors(가격 템플릿).
# 시험: 08_Tests/factor_db/test_price_continuity.R
#==============================================================================
suppressPackageStartupMessages(library(data.table))

#' 연속 가격 배율 열 px_cont 를 붙인다(제자리 · 반환도 같은 표). 필요 열 = Ticker · Date · Close · Ret.
#' @param tol 'Ret ≠ 생비율' 판정의 상대 허용오차(같은 식으로 센 값은 정확히 같다 — rawdata_seam_audit_config.json::RET_MATCH_TOL 과 같은 뜻)
fdb_px_cont <- function(dt, tol = 1e-9) {
  stopifnot(is.data.table(dt), all(c("Ticker", "Date", "Close", "Ret") %in% names(dt)))
  k0 <- key(dt)                           # ★키(빌더 = Date 키 조인 RAWDATA[.(d)])와 원래 행 순서를 끝에서 되돌린다
  dt[, .pc_i := .I]
  setorder(dt, Ticker, Date)
  dt[, .pc_prev := shift(Close), by = Ticker]
  rr <- dt$Close / dt$.pc_prev
  ret <- as.numeric(dt$Ret)
  ok <- is.finite(rr) & rr > 0
  m <- rep(1, nrow(dt))
  fixed <- ok & is.finite(ret) & abs(ret - (rr - 1)) > tol * pmax(1, abs(ret))
  m[fixed] <- (1 + ret[fixed]) / rr[fixed]
  blocked <- ok & !is.finite(ret)
  m[blocked] <- 1 / rr[blocked]
  hit <- fixed | blocked
  info <- list(n_fixed = sum(fixed), n_blocked = sum(blocked), n_tickers = length(unique(dt$Ticker[hit])),
               first_date = if (any(hit)) as.character(min(dt$Date[hit])) else NA_character_)
  dt[, .pc_m := m]
  dt[, px_cont := cumprod(.pc_m), by = Ticker]
  setorder(dt, .pc_i)
  dt[, c(".pc_prev", ".pc_m", ".pc_i") := NULL]
  if (length(k0)) setkeyv(dt, k0)
  attr(dt, "px_cont_info") <- info
  dt
}
