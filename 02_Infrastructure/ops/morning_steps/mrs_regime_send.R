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

if (!.gate_ok) {
  .msg <- sprintf("⚠️ 레짐 브리핑 보류 — 컴포넌트 stale: %s (as_of=%s). regime 데이터 점검 요.",
                  paste(.stale, collapse = ", "), .asof)
  cat(sprintf("[mrs_daily] STALE-GATE BLOCK: %s\n", .msg))
  ## (2026-11-10 감사 레인 B) tg_send 는 실패를 예외가 아니라 list(ok = FALSE) 로 돌려준다 — tryCatch(error=) 만으로는 못 본다.
  .sr <- tryCatch(tg_send(.msg), error = function(e) list(ok = FALSE, error = conditionMessage(e)))
  if (!isTRUE(.sr$ok)) cat(sprintf("[mrs_daily] stale alert FAILED: %s\n", substr(.sr$error %||% "?", 1, 200)))
} else tryCatch({
  .br <- tg_regime_briefing()
  ## 구판은 반환값과 무관하게 'sent OK' 를 찍었다(400 · 429 거부도 성공으로 기록 · superfan 감시도 그 줄을 믿는다).
  if (is.list(.br) && identical(.br$sent_ok, FALSE)) {
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
