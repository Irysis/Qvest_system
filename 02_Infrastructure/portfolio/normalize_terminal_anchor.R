## ============================================================================
## normalize_terminal_anchor.R — 워크포워드 종점 행의 앵커 정규화
##
## 문제 (실사고 2026-08-01):
##   run_all.R [9] OOS 확장의 마지막 행은 raw 데이터 종점(월 마지막 거래일)에 앵커된다.
##   예: …, 2026-07-01(6월 수익), 2026-07-31(7월 수익 -27.49%).
##   그런데 시리즈 규약은 anchor = 월 첫 거래일 · realized_ym = format(date,"%Y-%m") 이라
##   ① 07-01 과 07-31 이 같은 realized_ym=2026-07 로 접혀 **월간 조인에서 행이 2배 증식**
##   ② 7월 수익이 return_ym=2026-06(6월)으로 **한 달 밀려 라벨링** — 그대로 흘리면
##      벤치 조인까지 한 달 어긋나 NAV 전체가 밀린다.
##
## 규칙 (도훈 승인 2026-08-02 — "07-31 행을 08-01 앵커로 편입"):
##   마지막 행의 ym 이 직전 행과 같을 때만 개입한다 (다르면 이미 정상 앵커 — no-op).
##   - 종점 월이 **완결**됐으면 (오늘 > 그 월): date 를 다음달 1일로 재라벨.
##     → realized_ym = 다음달 / return_ym = 그 월. 다음 리밸에서 실제 첫 거래일 앵커로
##       자연 대체된다(run_all 이 확장부를 통째로 재산출).
##   - 종점 월이 **진행 중**이면 (오늘 == 그 월): 부분월 수익 — 완결월로 위장 금지, 행 제거.
##
## 사용: Rscript normalize_terminal_anchor.R <period_returns.csv>
##       또는 source 후 normalize_terminal_anchor(path)
## ============================================================================
suppressPackageStartupMessages({library(data.table)})

normalize_terminal_anchor <- function(path, today = Sys.Date(), quiet = FALSE) {
  .say <- function(...) if (!quiet) cat(sprintf(...))
  if (!file.exists(path)) stop("[anchor] 파일 부재: ", path)
  d <- fread(path)
  if (!("date" %in% names(d))) stop("[anchor] date 컬럼 부재: ", path)
  d[, date := as.Date(date)]
  setorder(d, date)
  if (nrow(d) < 2L) { .say("[anchor] 행 %d — 검사 대상 아님\n", nrow(d)); return(invisible("noop")) }

  ym  <- format(d$date, "%Y-%m")
  n   <- nrow(d)
  act <- "noop"

  if (identical(ym[n], ym[n - 1L])) {
    now_ym <- format(today, "%Y-%m")
    if (ym[n] < now_ym) {
      ## 완결월 → 다음달 1일 앵커로 재라벨 (수익월 = 종점월, 장부월 = 다음달)
      new_anchor <- seq(as.Date(paste0(ym[n], "-01")), by = "month", length.out = 2L)[2L]
      .say("[anchor] 종점 재라벨: %s → %s (수익월 %s 을 장부월 %s 로 정규화)\n",
           as.character(d$date[n]), as.character(new_anchor), ym[n], format(new_anchor, "%Y-%m"))
      d[n, date := new_anchor]
      act <- "relabel"
    } else {
      ## 진행 중인 달의 부분월 행 → 완결월로 위장 금지, 제거
      .say("[anchor] 종점 제거: %s (진행월 %s 부분수익 — 완결월 위장 금지)\n",
           as.character(d$date[n]), ym[n])
      d <- d[-n]
      act <- "drop"
    }
  } else {
    .say("[anchor] 종점 %s 정상 앵커 — 무변경\n", as.character(d$date[n]))
  }

  ## 사후 불변식: realized_ym 유일성 (조인 증식의 근원 차단)
  dup <- format(d$date, "%Y-%m")
  dup <- unique(dup[duplicated(dup)])
  if (length(dup))
    stop("[anchor] 정규화 후에도 ym 중복 잔존: ", paste(dup, collapse = ", "),
         " — 상류 산출 자체가 규약 위반. 수동 확인 필요.")

  if (act != "noop") fwrite(d, path)
  invisible(act)
}

## CLI
if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  if (length(a) < 1L) stop("사용법: Rscript normalize_terminal_anchor.R <period_returns.csv>")
  normalize_terminal_anchor(a[1])
}
