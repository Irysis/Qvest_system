# [6/6-c] K200 일간 위험 브리핑 텔레그램 발송 (morning_briefing 외부화 2026-06-13)
# 인라인 -e 의 한글/이모지(⚠️) + 캡션 한글이 코드페이지 변환에서 깨져 "Execution halted" 되던 문제 해소.
# (2026-11-14 · 도훈 결정 K200-RISK-H1-REPLACE-P3-20261114) 본 모형 H1 교체 — 브리핑 폴더에 brief_meta.json 이 있으면
#   사진 목록 · 설명을 거기서 읽는다(603_k200_brief.py 가 H1 | P3 대체 | 보류에 맞춰 쓴다 · 보류 = 사진 없음).
#   brief_meta.json 이 없으면 구 방식(P3 고정 설명 · 사진 3장) 그대로 — 603 이 실패해 600 으로 대신 만든 날의 경로.
#   시험: K200_BRIEF_ROOT = 브리핑 폴더 바꾸기 · K200_BRIEF_DRYRUN=1 = 보내지 않고 보낼 내용만 찍는다.
source("02_Infrastructure/ops/morning_steps/_root.R")
source("02_Infrastructure/telegram/telegram_notify.R")
suppressPackageStartupMessages(library(arrow))

.dry <- identical(Sys.getenv("K200_BRIEF_DRYRUN"), "1")
.send_text <- function(body, ...) {
  if (.dry) {
    cat(sprintf("[P2 brief][DRYRUN] text %d chars | first line: %s\n", nchar(body), strsplit(body, "\n", fixed = TRUE)[[1]][1]))
    return(list(ok = TRUE))
  }
  tg_send(body, ...)
}
.send_photo <- function(path, caption) {
  if (.dry) {
    cat(sprintf("[P2 brief][DRYRUN] photo %s (%d bytes) | %s\n", basename(path), file.size(path), caption))
    return(invisible(list(ok = TRUE)))
  }
  tg_send_photo(path, caption = caption)
}

brief_root <- Sys.getenv("K200_BRIEF_ROOT", "04_Research/decision_framework/bearish_forecast_v3/03_models/morning_brief")
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
    msg <- sprintf("⚠️ 모닝브리핑 정체 — 최신 brief %s 가 직전 거래일 %s 보다 과거. H1 · P3 inference/brief 생성 정체 의심. stale brief 송출 보류 (602 · 601 · 603 점검 요).",
                   as.character(brief_date), as.character(bm_max))
    cat(sprintf("[P2 brief] STALE-GATE BLOCK: %s\n", msg))
    ## (2026-11-10 감사 레인 B) tg_send 는 실패를 예외가 아니라 list(ok = FALSE) 로 돌려준다 — 반환값을 읽는다.
    .sr <- tryCatch(.send_text(msg), error = function(e) list(ok = FALSE, error = conditionMessage(e)))
    if (!isTRUE(.sr$ok)) cat(sprintf("[P2 brief] stale alert FAILED: %s\n", substr(.sr$error %||% "?", 1, 200)))
  } else {
    cat(sprintf("[P2 brief] sending from %s (fresh: brief %s >= bm %s)\n", latest, as.character(brief_date), as.character(bm_max)))
    brief_md <- file.path(latest, "brief.md")
    if (file.exists(brief_md)) {
      body <- paste(readLines(brief_md, encoding = "UTF-8"), collapse = "\n")
      ## (2026-11-10 감사 레인 B) 넘치면 글자 중간이 아니라 **줄 단위**로 덜어낸다(SKILL §0.3 — 숫자 · 단어 중간 절삭 금지 ·
      ##   Markdown 엔티티가 반쪽 나면 400 으로 통째 유실). 3900 = 발송기 공통 여유(telegram_notify.R .TG_FIT_CHARS · Bot API 상한 4096).
      if (nchar(body) > 3900) {
        .ln <- strsplit(body, "\n", fixed = TRUE)[[1]]
        .keep <- which(cumsum(nchar(.ln) + 1L) <= 3850L)
        body <- paste0(paste(.ln[.keep], collapse = "\n"), "\n(뒤 ", length(.ln) - length(.keep), "줄은 brief.md 에)")
      }
      .br <- tryCatch(.send_text(body, parse_mode = "Markdown"), error = function(e) list(ok = FALSE, error = conditionMessage(e)))
      if (!isTRUE(.br$ok)) cat(sprintf("[P2 brief] tg_send FAILED: %s\n", substr(.br$error %||% "?", 1, 200)))
    }
    meta_p <- file.path(latest, "brief_meta.json")
    meta <- if (file.exists(meta_p)) tryCatch(jsonlite::fromJSON(meta_p, simplifyVector = FALSE), error = function(e) NULL) else NULL
    if (!is.null(meta)) {
      cat(sprintf("[P2 brief] meta source=%s photos=%d\n", meta$source %||% "?", length(meta$photos)))
      for (ph in meta$photos) {
        fp <- file.path(latest, ph$file)
        if (file.exists(fp)) {
          tryCatch(.send_photo(fp, ph$caption),
                   error = function(e) cat(sprintf("[P2 brief] tg_send_photo %s fail: %s\n", ph$file, e$message)))
        } else {
          cat(sprintf("[P2 brief] photo 없음(생략): %s\n", ph$file))
        }
      }
    } else {
      dist_png <- file.path(latest, "dist.png")
      trend_png <- file.path(latest, "trend.png")
      if (file.exists(dist_png)) {
        tryCatch(.send_photo(dist_png, caption = "P2 - 오늘 분포 forecast"),
                 error = function(e) cat(sprintf("[P2 brief] tg_send_photo dist fail: %s\n", e$message)))
      }
      if (file.exists(trend_png)) {
        tryCatch(.send_photo(trend_png, caption = "P2 - 22일 추세"),
                 error = function(e) cat(sprintf("[P2 brief] tg_send_photo trend fail: %s\n", e$message)))
      }
      riskpro_png <- file.path(latest, "p3_9quad_riskpro.png")
      if (file.exists(riskpro_png)) {
        tryCatch(.send_photo(riskpro_png, caption = "P3 Risk Manager Pro Dashboard"),
                 error = function(e) cat(sprintf("[P2 brief] tg_send_photo riskpro fail: %s\n", e$message)))
      }
    }
    cat("[P2 brief] done\n")
  }
}
