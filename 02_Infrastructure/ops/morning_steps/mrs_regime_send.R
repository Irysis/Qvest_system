# mrs_regime_send.R — MRS Daily 레짐 브리핑 발송 (mrs_daily_briefing.sh 외부화 2026-06-18)
#
# 외부화 이유 (root cause, 2026-06-18 Q 진단):
#   기존 mrs_daily_briefing.sh 는 멀티라인 `Rscript -e '...'` 블록으로 레짐 브리핑을 실행했는데,
#   Windows Git Bash → Rscript.exe 인자 전달에서 멀티라인 -e 는 **첫 줄만 실행**된다(실증:
#   `Rscript -e $'cat("A\n")\ncat("B\n")'` → A만 출력). 블록 첫 줄이 `invisible(NULL)` 이라
#   config/telegram source · freshness gate · tg_regime_briefing() 이 한 번도 실행되지 않고
#   조용히 no-op + exit 0 (cat 부재 + 레짐 차트 미재생으로 확인). daily_refresh.sh 의 run_r()
#   temp-file 패턴 + morning_steps 외부화(p3_brief_send.R)와 동일한 회피책을 적용한다.
#   외부 .R 파일은 단일줄 `Rscript -e 'source(...)'` 로 호출 → 전 줄 정상 실행 + UTF-8(한글/이모지) 정상 read.
#
# _root.R: setwd(프로젝트 루트) + config.R source + 상속 QM_ROOT 오염 방지 (p3_brief_send.R 와 동일).
source("02_Infrastructure/ops/morning_steps/_root.R")
source("02_Infrastructure/telegram/telegram_notify.R")

# [④ freshness 게이트 2026-06-01 도훈] morning_briefing 이 쓴 manifest 기준 — 레짐 컴포넌트
#   stale 이면 발송 보류 + 알림 (P3 와 동일 원칙: partial-stale 송출 차단).
.gate_ok <- TRUE; .stale <- character(0); .asof <- "?"
.mpath <- "qepm/observability/morning_freshness_latest.json"
if (file.exists(.mpath)) {
  .m <- tryCatch(jsonlite::fromJSON(.mpath, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.null(.m)) {
    if (!is.null(.m$as_of)) .asof <- as.character(.m$as_of)
    if (!is.null(.m$audits)) {
      .rc <- c("regime_daily", "msm_daily", "ktri_v3_signals")
      for (.a in .m$audits) {
        if (!is.null(.a$name) && .a$name %in% .rc && isTRUE(.a$status %in% c("STALE", "MISSING"))) {
          .gate_ok <- FALSE; .stale <- c(.stale, sprintf("%s(%s)", .a$name, .a$status))
        }
      }
    }
  }
}

## ★2026-11-13 (도훈 "최신데이터로 계산되서 발송되게"): 기대 기준일(= 신선도 감사 as_of · 직전 거래일)을 브리핑에 넘긴다 —
##   자료 기준일이 그보다 이르면 tg_regime_briefing 이 본문 첫머리와 차트 부제에 '낡음'과 원천별 마지막 날짜를 적는다.
## QVEST_TG_DRY_RUN=1 → 발송 0(본문 · 차트 경로만 로그) — 보류 경보도 보내지 않는다.
.dry <- identical(Sys.getenv("QVEST_TG_DRY_RUN", ""), "1")
.exp <- suppressWarnings(tryCatch(as.Date(.asof), error = function(e) as.Date(NA)))
## 감사 as_of 는 거래일 달력이 아직 덮지 못한 평일 휴장일(그 다음 날 아침)을 그대로 둔다(regime_data_gate.R '한계' 주석) —
##   KRX 휴장일 정본(06_Registry/krx_holidays.json · 신선도 감사 세션 축과 같은 원천)으로 직전 개장일까지 물려 거짓 '낡음'을 막는다.
##   정본 판독 실패 · 수록 연도 밖이면 물리지 않는다(구판 동작 = 감사 as_of 그대로).
.hol <- tryCatch({ .h <- jsonlite::fromJSON("06_Registry/krx_holidays.json")
  list(years = as.integer(unlist(.h$years)), days = as.Date(names(.h$holidays))) }, error = function(e) NULL)
if (!is.null(.hol) && !is.na(.exp))
  while (as.integer(format(.exp, "%Y")) %in% .hol$years && (format(.exp, "%u") %in% c("6", "7") || .exp %in% .hol$days)) .exp <- .exp - 1L
if (!.gate_ok) {
  .msg <- sprintf("⚠️ 레짐 브리핑 보류 — 컴포넌트 stale: %s (as_of=%s). regime 데이터 점검 요.",
                  paste(.stale, collapse = ", "), .asof)
  cat(sprintf("[mrs_daily] STALE-GATE BLOCK: %s\n", .msg))
  ## (2026-11-10 감사 레인 B) tg_send 는 실패를 예외가 아니라 list(ok = FALSE) 로 돌려준다 — tryCatch(error=) 만으로는 못 본다.
  .sr <- if (.dry) list(ok = TRUE, dry_run = TRUE) else
    tryCatch(tg_send(.msg), error = function(e) list(ok = FALSE, error = conditionMessage(e)))
  if (.dry) cat("[mrs_daily] DRYRUN — 보류 경보 발송 없음\n")
  if (!isTRUE(.sr$ok)) cat(sprintf("[mrs_daily] stale alert FAILED: %s\n", substr(.sr$error %||% "?", 1, 200)))
} else tryCatch({
  .br <- tg_regime_briefing(expected_date = if (is.na(.exp)) NULL else .exp, dry_run = .dry)
  ## 구판은 반환값과 무관하게 'sent OK' 를 찍었다(400 · 429 거부도 성공으로 기록 · superfan 감시도 그 줄을 믿는다).
  if (is.list(.br) && isTRUE(.br$dry_run)) {
    cat(sprintf("[mrs_daily] briefing DRYRUN — 발송 없음 (자료 기준일 %s%s)\n", format(.br$ref_date),
                if (is.null(.br$stale)) "" else sprintf(" · 낡음 — 기대 %s", format(.br$stale$expected))))
  } else if (is.list(.br) && identical(.br$sent_ok, FALSE)) {
    cat(sprintf("[mrs_daily] briefing SEND FAILED: %s (원장 qepm/observability/telegram_send_failures.jsonl)\n",
                substr(.br$send_error %||% "?", 1, 200)))
  } else if (is.null(.br)) {
    cat("[mrs_daily] briefing skipped (tg_regime_briefing 이 데이터 부재로 NULL 반환)\n")
  } else {
    cat(sprintf("[mrs_daily] briefing sent OK (charts %s)\n", .br$charts_sent %||% "?"))
  }
}, error = function(e) {
  cat(sprintf("[mrs_daily] ERR: %s\n", conditionMessage(e)))
})
