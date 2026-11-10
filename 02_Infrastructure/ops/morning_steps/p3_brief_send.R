# [6/6-c] P3 모닝 brief 텔레그램 발송 (morning_briefing 외부화 2026-06-13)
# 인라인 -e 의 한글/이모지(⚠️) + 캡션 한글이 코드페이지 변환에서 깨져 "Execution halted" 되던 문제 해소.
source("02_Infrastructure/ops/morning_steps/_root.R")
source("02_Infrastructure/telegram/telegram_notify.R")
suppressPackageStartupMessages(library(arrow))

brief_root <- "04_Research/decision_framework/bearish_forecast_v3/03_models/morning_brief"
sub_dirs <- list.dirs(brief_root, recursive = FALSE)
if (length(sub_dirs) == 0) {
  cat("[P2 brief] no brief dir found\n")
} else {
  latest <- sort(sub_dirs, decreasing = TRUE)[1]
  # freshness: 최신 brief dir 날짜가 직전 거래일(benchmark max Date)보다 과거면 stale -> 송출 보류 (조용한 stale 송출 차단)
  brief_date <- suppressWarnings(as.Date(basename(latest)))
  bm_max <- tryCatch(as.Date(max(as.data.frame(arrow::read_parquet(".cache/benchmark.parquet", col_select = "Date"))$Date, na.rm = TRUE)),
                     error = function(e) as.Date(NA))
  is_stale <- is.na(brief_date) || (!is.na(bm_max) && brief_date < bm_max)

  if (is_stale) {
    msg <- sprintf("⚠️ 모닝브리핑 정체 — 최신 brief %s 가 직전 거래일 %s 보다 과거. P3 inference/brief 생성 정체 의심. stale brief 송출 보류 (601_daily_inference 점검 요).",
                   as.character(brief_date), as.character(bm_max))
    cat(sprintf("[P2 brief] STALE-GATE BLOCK: %s\n", msg))
    ## (2026-11-10 감사 레인 B) tg_send 는 실패를 예외가 아니라 list(ok = FALSE) 로 돌려준다 — 반환값을 읽는다.
    .sr <- tryCatch(tg_send(msg), error = function(e) list(ok = FALSE, error = conditionMessage(e)))
    if (!isTRUE(.sr$ok)) cat(sprintf("[P2 brief] stale alert FAILED: %s\n", substr(.sr$error %||% "?", 1, 200)))
  } else {
    cat(sprintf("[P2 brief] sending from %s (fresh: brief %s >= bm %s)\n", latest, as.character(brief_date), as.character(bm_max)))
    brief_md <- file.path(latest, "brief.md")
    dist_png <- file.path(latest, "dist.png")
    trend_png <- file.path(latest, "trend.png")
    if (file.exists(brief_md)) {
      body <- paste(readLines(brief_md, encoding = "UTF-8"), collapse = "\n")
      ## (2026-11-10 감사 레인 B) 넘치면 글자 중간이 아니라 **줄 단위**로 덜어낸다(SKILL §0.3 — 숫자 · 단어 중간 절삭 금지 ·
      ##   Markdown 엔티티가 반쪽 나면 400 으로 통째 유실). 3900 = 발송기 공통 여유(telegram_notify.R .TG_FIT_CHARS · Bot API 상한 4096).
      if (nchar(body) > 3900) {
        .ln <- strsplit(body, "\n", fixed = TRUE)[[1]]
        .keep <- which(cumsum(nchar(.ln) + 1L) <= 3850L)
        body <- paste0(paste(.ln[.keep], collapse = "\n"), "\n(뒤 ", length(.ln) - length(.keep), "줄은 brief.md 에)")
      }
      .br <- tryCatch(tg_send(body, parse_mode = "Markdown"), error = function(e) list(ok = FALSE, error = conditionMessage(e)))
      if (!isTRUE(.br$ok)) cat(sprintf("[P2 brief] tg_send FAILED: %s\n", substr(.br$error %||% "?", 1, 200)))
    }
    if (file.exists(dist_png)) {
      tryCatch(tg_send_photo(dist_png, caption = "P2 - 오늘 분포 forecast"),
               error = function(e) cat(sprintf("[P2 brief] tg_send_photo dist fail: %s\n", e$message)))
    }
    if (file.exists(trend_png)) {
      tryCatch(tg_send_photo(trend_png, caption = "P2 - 22일 추세"),
               error = function(e) cat(sprintf("[P2 brief] tg_send_photo trend fail: %s\n", e$message)))
    }
    riskpro_png <- file.path(latest, "p3_9quad_riskpro.png")
    if (file.exists(riskpro_png)) {
      tryCatch(tg_send_photo(riskpro_png, caption = "P3 Risk Manager Pro Dashboard"),
               error = function(e) cat(sprintf("[P2 brief] tg_send_photo riskpro fail: %s\n", e$message)))
    }
    cat("[P2 brief] done\n")
  }
}
