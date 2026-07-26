#==============================================================================
# ic_pair_completeness.R — IC month-pair 완결성 판정 (순수 함수)
#
# 정체: compute_all_factor_ic_monthly() 의 incomplete-terminal-pair guard 판정부.
#       입력만 보고 판정하는 순수 함수 — 파일 I/O·전역 상태·Sys.Date() 암묵 참조 없음
#       (today 를 인자로 받는다). 따라서 단독 호출·주입 검증이 가능하다.
#
# 왜 분리했나 (2026-07-26, R-ICGUARD):
#   판정이 빌더 함수 안의 인라인 코드였던 동안에는 단독 실행이 불가능해
#   **위반 주입 테스트**(일부러 틀린 입력을 넣어 잡히는지 확인)를 걸 수 없었다.
#   검사가 걸리지 않은 가드는 나중에 조용히 무력화돼도 아무 신호를 내지 않는다.
#   상설 검사: 08_Tests/factor_db/test_ic_completion_guard.R
#
# 계약 — 두 명제는 서로 다르다 (둘 중 하나라도 아니면 미완결):
#   (a) 달력 종료  : "그 달의 달력이 끝났나"          → cal_end <= today
#   (b) 파일 도달  : "이 파일이 그 달을 끝까지 담았나" → sig_d_t1 >= 그 달 RAWDATA 최종 거래일
#   (a)만 보던 구 판정은 월말 재빌드가 지연·실패했을 때 sig 가 월중 스냅샷인 채로
#   달력만 넘어가, **부분월 forward-return IC 가 '완결'로 기록**되고 Usable_Date 도
#   과소 기록된다(vintage 불안정 — 월말 재빌드 시 IC 값이 조용히 바뀜).
#
# fail-closed 원칙: 판정 불가(날짜 파손)면 '완결'이 아니라 '미완결'로 떨어뜨린다.
#   IC 한 행을 잃는 비용 < 오염된 IC 한 행을 쓰는 비용.
#==============================================================================

.IC_NA_DATE <- structure(NA_real_, class = "Date")

#' 무엇이 들어오든 길이-1 Date 로 정규화. 실패·비유한값(-Inf 등)은 NA Date.
#' (max() 를 빈 Date 벡터에 적용하면 -Inf 가 나온다 — 그 경로가 여기서 죽으면 안 된다)
.ic_as_date1 <- function(x) {
  if (is.null(x) || length(x) == 0L) return(.IC_NA_DATE)
  x <- x[1L]
  if (inherits(x, "Date")) {
    if (!is.finite(as.numeric(x))) return(.IC_NA_DATE)
    return(x)
  }
  if (inherits(x, "POSIXt")) return(as.Date(x))
  if (is.numeric(x)) {
    if (!is.finite(x)) return(.IC_NA_DATE)
    return(as.Date(x, origin = "1970-01-01"))
  }
  if (is.logical(x)) return(.IC_NA_DATE)
  out <- suppressWarnings(tryCatch(as.Date(as.character(x)),
                                   error = function(e) .IC_NA_DATE))
  if (length(out) != 1L || is.na(out)) .IC_NA_DATE else out
}

#' 해당 날짜가 속한 달의 달력 마지막 날.
.ic_month_cal_end <- function(d) {
  seq(as.Date(format(d, "%Y-%m-01")), by = "month", length.out = 2L)[2L] - 1L
}

#' IC month-pair 의 forward 월(=t+1 파일의 월)이 완결됐는지 판정.
#'
#' @param sig_d_t1       t+1 factor_db 파일의 sig date (Date/POSIXct/문자 허용)
#' @param today          판정 기준일 (기본 Sys.Date(); 테스트는 명시 주입)
#' @param raw_month_last 그 달 RAWDATA 최종 거래일. 미상(-Inf/NA/NULL) 허용 —
#'                       그 경우 (b) 를 검사할 수 없으므로 달력-only 로 후퇴하고
#'                       reason 에 그 사실을 남긴다(조용히 넘어가지 않는다).
#' @return list(complete, reason, detail, month, cal_end, raw_known)
#'         reason ∈ {complete, complete_calendar_only,
#'                   calendar_not_ended, file_partial, sig_date_invalid}
.ic_pair_complete <- function(sig_d_t1, today = Sys.Date(), raw_month_last = NULL) {
  sig <- .ic_as_date1(sig_d_t1)
  now <- .ic_as_date1(today)

  if (is.na(sig) || is.na(now)) {
    return(list(
      complete  = FALSE,
      reason    = "sig_date_invalid",
      detail    = sprintf("sig=%s today=%s — 날짜 판정 불가, fail-closed 로 미완결 처리",
                          as.character(sig), as.character(now)),
      month     = NA_character_,
      cal_end   = .IC_NA_DATE,
      raw_known = FALSE
    ))
  }

  month    <- format(sig, "%Y-%m")
  cal_end  <- .ic_month_cal_end(sig)
  raw_last <- .ic_as_date1(raw_month_last)
  raw_known <- !is.na(raw_last)

  # (a) 달력이 아직 안 끝났다 — 진행 중인 달
  if (cal_end > now) {
    return(list(
      complete  = FALSE,
      reason    = "calendar_not_ended",
      detail    = sprintf("calendar end %s > today %s", cal_end, now),
      month     = month,
      cal_end   = cal_end,
      raw_known = raw_known
    ))
  }

  # (b) 달력은 끝났는데 파일이 그 달 끝까지 못 갔다 — 월말 재빌드 지연/실패
  if (raw_known && sig < raw_last) {
    return(list(
      complete  = FALSE,
      reason    = "file_partial",
      detail    = sprintf("file sig %s < month last trading day %s (월말 재빌드 대기)",
                          sig, raw_last),
      month     = month,
      cal_end   = cal_end,
      raw_known = TRUE
    ))
  }

  list(
    complete  = TRUE,
    reason    = if (raw_known) "complete" else "complete_calendar_only",
    detail    = if (raw_known) {
      sprintf("calendar end %s <= today %s, file sig %s >= month last %s",
              cal_end, now, sig, raw_last)
    } else {
      sprintf("calendar end %s <= today %s (RAWDATA %s 최종 거래일 미상 — 달력-only 판정)",
              cal_end, now, month)
    },
    month     = month,
    cal_end   = cal_end,
    raw_known = raw_known
  )
}
