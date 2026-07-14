## ============================================================================
## align_signal_return_ym.R — 신호월↔수익월 병합 표준 헬퍼 (FQ-043, 2026-07-14)
## ----------------------------------------------------------------------------
## 왜 존재하나 — 실사고 2건 (둘 다 2026-07-14 확정, 재발방지 목적):
##
##  [실사고 1 — R27, WT_D20260714_003] exact-Date 병합 = 92/255개월 value 소실.
##    pure_factor_scores.signal_date(달력 월말: 2015-06-30)와 백테 패널 Date(거래일
##    월말: 2015-06-29)가 exact-Date로는 163/255개월만 일치 → 나머지 92개월 value가
##    조용히 NA(=신호 소거)로 흘러 부정판정을 만들었다. **월 단위 병합은 ym
##    ("%Y-%m") 키 정렬이 정답** — exact-Date 병합 금지.
##
##  [실사고 2 — R29, WT_D20260714_005] 동월(off+1) factor vintage = ~1개월 look-ahead.
##    저장 268m 패널이 신호월 M+1의 factor_db(=수익과 동월)를 소비 → cap-w PORT_t
##    2.08× 부풀림(3.058→6.376). **신호는 수익월이 시작되기 전 데이터만**(pit.md C5).
##    off 파라미터를 임의로 키워 "동월" 병합을 만드는 것 = look-ahead. 명시 선언 없이
##    통과되지 않도록 본 헬퍼가 차단한다.
##
## 규약: 월 키 = format(Date, "%Y-%m"). 두 dating 컨벤션을 명시 선언해야 한다.
##   return_dating = "signal_anchor" : 수익 패널의 날짜가 *신호 anchor 월*을 라벨
##       (예: build_monthly_forward_returns의 returns_dt — Date=신호월말, Ret_1m은
##        다음달 실현 forward). 표준 off = 0.
##   return_dating = "realized_month": 수익 패널의 날짜가 *수익이 실제 벌린 달력월*을
##       라벨. 표준 off = +1 (수익월 = 신호월+1). off <= 0 은 동월/미래 신호 look-ahead
##       → allow_lookahead=TRUE(진단 전용, 라벨 강제) 없이는 stop.
##
## 소비 지점(활성 하네스)은 다음 개정에서 본 헬퍼 경유로 전환 권고 —
##   run_ramp_r6_portt_boruta.R · build_insider_factor_panel.R 등 (강제 아님, 주석 배치).
## ============================================================================
suppressWarnings(suppressMessages(library(data.table)))

ym_of <- function(d) format(as.Date(d), "%Y-%m")

## ym 문자키에 개월수 더하기 ("2015-06" + 1 -> "2015-07")
ym_shift <- function(ym, k = 0L) {
  d <- as.Date(paste0(ym, "-01"))
  m <- as.integer(format(d, "%m")) - 1L + as.integer(k)
  y <- as.integer(format(d, "%Y")) + m %/% 12L
  sprintf("%04d-%02d", y, (m %% 12L) + 1L)
}

#' 신호월-수익월 표준 병합 (ym 키 + 명시 off + coverage assert + vintage 라벨)
#'
#' @param signal_dt  data.table — 신호 패널 (signal_date_col + id_col + 신호 컬럼들)
#' @param return_dt  data.table — 수익 패널 (return_date_col + id_col + ret_col)
#' @param signal_date_col,return_date_col 날짜 컬럼명
#' @param id_col     증권 식별자 컬럼명 (양쪽 동일명; 다르면 사전 rename)
#' @param off        정수(개월). 병합 키: ym(signal)+off == ym(return_dt 날짜).
#'                   "signal_anchor" 표준 0 / "realized_month" 표준 +1. 기본값 없음(명시 강제).
#' @param return_dating "signal_anchor" | "realized_month" (위 헤더 참조. 명시 강제)
#' @param coverage_min 신호월 중 수익 매칭 성공 월 비율 하한 (기본 0.95) — 미달 시 stop
#'                   (실사고 1의 92/255 소실 = 0.64로 즉사했을 값)
#' @param allow_lookahead FALSE(기본). realized_month에서 off<=0(동월/역방향) 시도 시
#'                   stop — 진단 전용으로만 TRUE 허용(vintage 라벨에 LOOKAHEAD 강제 표기)
#' @param vintage_label 산출 vintage_label 컬럼 값. NULL이면 자동 생성
#' @return merged data.table (signal_dt 좌측 기준) + signal_ym / return_ym /
#'         vintage_off / vintage_label 컬럼. attr: align_coverage_month / align_coverage_row
align_signal_return_ym <- function(signal_dt, return_dt,
                                   signal_date_col = "signal_date",
                                   return_date_col = "Date",
                                   id_col = "Ticker",
                                   off,
                                   return_dating,
                                   coverage_min = 0.95,
                                   allow_lookahead = FALSE,
                                   vintage_label = NULL) {
  stopifnot(is.data.frame(signal_dt), is.data.frame(return_dt))
  if (missing(off) || length(off) != 1L || !is.finite(off))
    stop("[align] off 는 명시 필수 (signal_anchor: 0 / realized_month: +1). 실사고 2(R29 동월 vintage) 참조.")
  off <- as.integer(off)
  return_dating <- match.arg(return_dating, c("signal_anchor", "realized_month"))

  ## PIT guard (실사고 2 재발방지): realized_month에서 off<=0 = 동월(또는 미래신호) 병합
  if (return_dating == "realized_month" && off <= 0L && !allow_lookahead)
    stop(sprintf(paste0("[align] return_dating='realized_month' 인데 off=%d (<=0) — 수익월과 동월(이후) ",
                        "신호 병합 = look-ahead (pit.md C5, R29 실사고). 진단 전용이면 allow_lookahead=TRUE."), off))
  if (return_dating == "signal_anchor" && off > 0L && !allow_lookahead)
    stop(sprintf(paste0("[align] return_dating='signal_anchor' 인데 off=%d (>0) — forward 수익 anchor를 ",
                        "미래 신호와 병합 = look-ahead. 진단 전용이면 allow_lookahead=TRUE."), off))

  s <- as.data.table(signal_dt); r <- as.data.table(return_dt)
  for (cc in c(signal_date_col, id_col)) if (!cc %in% names(s)) stop("[align] signal_dt에 없음: ", cc)
  for (cc in c(return_date_col, id_col)) if (!cc %in% names(r)) stop("[align] return_dt에 없음: ", cc)

  s[, signal_ym := ym_of(get(signal_date_col))]
  s[, .join_ym := ym_shift(signal_ym, off)]
  r[, .join_ym := ym_of(get(return_date_col))]
  if (anyDuplicated(r, by = c(".join_ym", id_col)))
    stop("[align] return_dt (ym, ", id_col, ") 중복 — 월 패널이 아님(사전 집계 필요)")

  m <- merge(s, r[, c(".join_ym", id_col, setdiff(names(r), c(".join_ym", id_col, return_date_col))), with = FALSE],
             by = c(".join_ym", id_col), all.x = TRUE, suffixes = c("", ".ret"))

  ## coverage: 실사고 1 유형(월 단위 조용한 소실) 검출 — 월/행 이중 산출
  ret_probe <- setdiff(names(r), c(".join_ym", id_col, return_date_col))[1]
  if (is.na(ret_probe)) stop("[align] return_dt에 수익/값 컬럼이 없음")
  cov_m_dt <- m[, .(hit = any(!is.na(get(ret_probe)))), by = signal_ym]
  cov_month <- cov_m_dt[, mean(hit)]
  cov_row <- m[, mean(!is.na(get(ret_probe)))]
  msg <- sprintf("[align] off=%+d dating=%s | month-coverage=%.3f (%d/%d) row-coverage=%.3f",
                 off, return_dating, cov_month, cov_m_dt[, sum(hit)], nrow(cov_m_dt), cov_row)
  cat(msg, "\n")
  if (cov_month < coverage_min)
    stop(sprintf(paste0("[align] month-coverage %.3f < %.2f — 병합 실패월 과다 (실사고 1: exact-Date 92/255 소실 ",
                        "= 0.64). 날짜 컨벤션(달력 vs 거래일 월말)·off·키를 점검."), cov_month, coverage_min))

  if (is.null(vintage_label))
    vintage_label <- sprintf("ym_align_off%+d_%s%s", off, return_dating,
                             if (allow_lookahead) "_LOOKAHEAD_DIAG_ONLY" else "")
  m[, return_ym := .join_ym][, .join_ym := NULL]
  m[, vintage_off := off]
  m[, vintage_label := vintage_label]
  setattr(m, "align_coverage_month", cov_month)
  setattr(m, "align_coverage_row", cov_row)
  m[]
}

cat("[align_signal_return_ym.R] loaded — ym_of / ym_shift / align_signal_return_ym (FQ-043)\n")
