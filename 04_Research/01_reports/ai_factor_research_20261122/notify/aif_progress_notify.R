## aif_progress_notify.R — 텔레그램 진행 알림(승인 계획 '진행 알림'). 상태 파일을 읽어 한 통을 만들고, 보낼 때인지 스스로 판정한다.
##   실행: Rscript notify/aif_progress_notify.R [--send] [--force] [--event=start|end|error|resume|result|report] [--summary=<json>]
##     --send 가 없으면 미리보기(발송 없음 · 형식 검사만). 발송은 저장소의 단일 진입점 tg_agent_brief() 로만 한다.
##     --event=report = 종합 보고 통(07_final_report.R 이 쓴 요약 + 후속 연구 계획 요약 followup_plan.json + 그림). 마지막 단계(final_report)의 결과 통도 이 모양으로 간다.
##   보내는 때: 08~23시 매시(무음) · 단계 시작/종료/오류/재개/결과(알림음) · 00~07시는 단계 전환과 오류만.
##   보낸 메시지를 고치는 기능이 없으므로, 새 통이 올 때마다 더 채워진 막대가 간다.
here <- function() {   # 이 스크립트가 든 폴더의 위 폴더(연구 폴더). 경로 정규화 함수는 쓰지 않는다 — 구분자만 맞춘다
  a <- commandArgs(FALSE); f <- gsub("\\\\", "/", sub("^--file=", "", a[grepl("^--file=", a)])[1])
  if (!grepl("^([A-Za-z]:)?/", f)) f <- file.path(getwd(), f)
  dirname(dirname(f))
}
D <- here()
for (f in c("aif_common.R", "aif_status.R")) source(file.path(D, "R", f))
A <- commandArgs(TRUE); SEND <- "--send" %in% A; FORCE <- "--force" %in% A
EVENT <- sub("^--event=", "", A[grepl("^--event=", A)])[1]
root <- aif_root(); cfg <- aif_cfg(root); setwd(root)
st <- aif_status_read(root, cfg)
NSP <- aif_out("notify_state.json", root = root, cfg = cfg)
ns <- if (file.exists(NSP)) tryCatch(fromJSON(NSP, simplifyVector = FALSE), error = function(e) list()) else list()
if (is.null(st$stage_key)) { cat("[aif-notify] 상태 파일에 단계가 없다 — 보낼 것이 없음\n"); quit(status = 0L) }

stages <- cfg$progress$stages; keys <- vapply(stages, function(s) s$key, "")
k <- match(st$stage_key, keys); sg <- stages[[k]]
pct <- round(100 * aif_overall(st, cfg)); spct <- round(100 * as.numeric((st$stage_progress %||% list())[[st$stage_key]] %||% 0))
state <- st$stage_state %||% "running"
now <- Sys.time(); hh <- as.integer(format(now, "%H"))

## 어떤 통인가 — 인자로 받지 않으면 직전 통과 비교해 정한다
if (is.na(EVENT)) {
  changed <- !identical(ns$stage_key, st$stage_key) || !identical(ns$stage_state, state)
  EVENT <- if (state == "error" && changed) "error" else if (changed && state == "running" && !identical(ns$stage_key, st$stage_key)) "start"
           else if (changed && state == "done") "end" else "hourly"
}
quiet <- hh %in% unlist(cfg$progress$quiet_hours)
due <- is.null(ns$sent_at) || as.numeric(difftime(now, as.POSIXct(ns$sent_at), units = "mins")) >= cfg$progress$interval_min
if (!FORCE && EVENT == "hourly" && (quiet || !due)) { cat(sprintf("[aif-notify] 보낼 때가 아니다(조용한 시간 %s · 간격 충족 %s)\n", quiet, due)); quit(status = 0L) }
if (!FORCE && EVENT == "hourly" && state == "done") { cat("[aif-notify] 단계가 끝난 상태 — 매시 통은 보내지 않는다\n"); quit(status = 0L) }

bar <- function(p, n = 10L) {   # 0% 보다 크면 한 칸은 채운다(5% 가 빈 막대로 보이지 않게)
  f <- max(0L, min(n, as.integer(round(p / 100 * n)))); if (p > 0 && f == 0L) f <- 1L
  paste0(strrep("▰", f), strrep("▱", n - f), sprintf(" %d%%", as.integer(p)))
}
dur <- function(mins) { mins <- max(0, round(mins)); if (mins >= 60) sprintf("%d시간 %d분", mins %/% 60, mins %% 60) else sprintf("%d분", mins) }
elapsed <- if (!is.null(st$stage_started_at)) as.numeric(difftime(now, as.POSIXct(st$stage_started_at), units = "mins")) else NA_real_
run_el <- if (!is.null(st$run_started_at)) as.numeric(difftime(now, as.POSIXct(st$run_started_at), units = "mins")) else NA_real_
frac <- if (!is.null(st$unit_total) && st$unit_total > 0) (st$unit_done %||% 0) / st$unit_total else NA_real_
eta <- if (state == "done") "없음(단계 끝)" else if (is.finite(frac) && frac >= 0.05 && frac < 1 && is.finite(run_el)) sprintf("약 %s", dur(run_el * (1 - frac) / frac)) else "계산 중"
state_txt <- switch(state, running = "실행 중", waiting = sprintf("대기 — %s", st$wait_reason %||% "사유 기록 없음"), paused = sprintf("일시 중지 — %s", st$wait_reason %||% ""),
                    done = "단계 끝", error = sprintf("오류 — %s", substr(st$error %||% "기록 없음", 1L, 120L)), state)
head_txt <- switch(EVENT, start = sprintf("%d단계 시작 — %s", k, sg$name), end = sprintf("%d단계 끝 — %s", k, sg$name),
                   error = sprintf("%d단계 오류로 멈춤 — %s", k, sg$name), resume = sprintf("중단 뒤 재개 — %d단계 %s", k, sg$name),
                   result = sprintf("%d단계 중간 결과 — %s", k, sg$name), sprintf("%d단계 진행 중 — %s", k, sg$name))
if (nchar(head_txt) < 20L) head_txt <- paste0(head_txt, " (AI 팩터 연구 진행 알림)")
nxt <- if (k < length(stages)) vapply(stages[(k + 1L):min(length(stages), k + 2L)], function(s) s$name, "") else character(0)
nxt <- c(nxt, if (length(nxt) < 2L) "모든 단계가 끝나면 종합 브리핑을 보냅니다")

secs <- list(
  list(type = "summary", body = substr(head_txt, 1L, 100L)),
  list(type = "code", emoji = "\U0001F4CA", heading = "진행률",
       body = sprintf("전체     %s\n이 단계  %s", bar(pct), bar(spct))),
  list(type = "bullet", emoji = "\U0001F52C", heading = "연구 내용",
       items = c("원자료와 기존 팩터 DB(월간 값이 있는 290개)에서 새 팩터를 자동으로 만들고 성과를 잽니다", sprintf("지금 단계: %s", sg$what))),
  list(type = "kv", emoji = "\U0001F9ED", heading = "현재 단계",
       kv = list("단위" = sprintf("%s %s / %s%s", st$unit_name %||% "단위", st$unit_done %||% 0, st$unit_total %||% "?", if (!is.null(st$detail)) sprintf(" (%s)", st$detail) else ""),
                 "경과" = if (is.finite(elapsed)) dur(elapsed) else "기록 없음",
                 "남은 시간" = eta,
                 "상태" = sprintf("%s%s", state_txt, if (state == "running" && !is.null(st$ram_gb)) sprintf(" · 메모리 %.1fGB · 스레드 %s", st$ram_gb, st$threads %||% "?") else ""))),
  list(type = "bullet", emoji = "⏭", heading = "다음", items = nxt[seq_len(2L)])
)
charts <- NULL
sf <- sub("^--summary=", "", A[grepl("^--summary=", A)])[1]
sm <- if (!is.na(sf) && file.exists(sf)) fromJSON(sf, simplifyVector = FALSE) else NULL
if (EVENT %in% c("end", "result") && identical(st$stage_key, "final_report") && !is.null(sm)) EVENT <- "report"   # 마지막 단계의 결과 통은 종합 보고 통으로 보낸다
if (EVENT %in% c("end", "result") && !is.null(sm)) {
  secs <- append(secs, list(list(type = "bullet", emoji = "\U0001F4C8", heading = sm$title %||% "이 단계 결과", items = unlist(sm$lines))), after = 2L)
  cp <- unlist(sm$charts); cn <- unlist(sm$chart_names); ex <- file.exists(cp)
  if (any(ex)) charts <- setNames(cp[ex], cn[ex])
}
title <- sprintf("[무인] AI 팩터 연구 — %s · 전체 %d%%%s", sg$name, pct, switch(EVENT, start = " · 시작", end = " · 끝", error = " · 오류", resume = " · 재개", result = " · 결과", ""))
## 종합 보고 통(--event=report --summary=<07 이 쓴 요약>) — 지금 도는 단계와 무관하게 끝난 묶음 전체의 결론 · 진행 · 후속 연구 계획 요약(followup_plan.json 이 있으면) · 그림을 보낸다
if (EVENT == "report") {
  if (is.null(sm)) { cat("[aif-notify] 종합 보고 통에는 --summary 가 필요하다\n"); quit(status = 2L) }
  sp <- st$stage_progress %||% list(); left <- vapply(stages[vapply(keys, function(kk) as.numeric(sp[[kk]] %||% 0) < 1, TRUE)], function(s) s$name, "")
  head_txt <- sprintf("%s — AI 팩터 연구에서 만든 신규 팩터 전체의 성과 요약", sm$title %||% "종합 보고")
  secs <- list(list(type = "summary", body = substr(head_txt, 1L, 100L)),
               list(type = "bullet", emoji = "\U0001F4C8", heading = "결론", items = unlist(sm$lines)),
               list(type = "code", emoji = "\U0001F4CA", heading = "진행률", body = sprintf("전체     %s\n남은 단계 %s", bar(pct), if (length(left)) paste(left, collapse = " · ") else "없음")))
  cp <- unlist(sm$charts); cn <- unlist(sm$chart_names); ex <- file.exists(cp); if (any(ex)) charts <- setNames(cp[ex], cn[ex])
  pf <- file.path(D, "followup_plan.json")
  if (file.exists(pf)) {
    pl <- fromJSON(pf, simplifyVector = FALSE)
    secs <- c(secs, list(list(type = "bullet", emoji = "\U0001F5FA", heading = pl$title %||% "후속 연구 계획(안)", items = unlist(pl$items))))
    pc <- vapply(pl$charts %||% list(), function(p) file.path(D, p), ""); pc <- pc[file.exists(pc)]; if (length(pc)) charts <- c(charts, pc)
  }
  secs <- c(secs, list(list(type = "bullet", emoji = "⏭", heading = "다음", items = c(if (length(left)) sprintf("남은 단계(%s)가 끝나면 최종판을 다시 보냅니다", paste(left, collapse = " · ")) else "모든 단계가 끝났습니다 — 이 통이 최종판입니다",
                                                                                   "보고서 파일 = 연구 폴더 results/final/final_report.html · 계획서 = FOLLOWUP_PLAN.md"))))
  title <- sprintf("[무인] AI 팩터 연구 — 종합 보고 · 전체 %d%%", pct)
}
mute <- EVENT == "hourly" || quiet   # 밤(00~07시)에 보내는 통은 종류와 무관하게 알림음 없이 채팅에만 남긴다
if (!SEND) Sys.setenv(QVEST_TG_DRY_RUN = "1")
invisible(capture.output(suppressMessages(source(file.path(root, "02_Infrastructure", "telegram", "telegram_notify.R")))))
r <- tryCatch(tg_agent_brief(agent = "Q-Lead", title = title, sections = secs, charts = charts, relaxed = TRUE, mute = mute, glossary = FALSE),
              error = function(e) { cat("[aif-notify] 발송 함수 오류:", conditionMessage(e), "\n"); NULL })
if (is.null(r)) quit(status = 2L)
if (SEND && is.list(r) && isFALSE(r$ok)) { cat("[aif-notify] 발송 실패(응답 ok = FALSE)\n"); quit(status = 3L) }
if (!SEND) { cat("[aif-notify] 미리보기(발송 없음) — 형식 검사 통과\n"); if (is.character(r)) cat(r, "\n") else if (!is.null(r$body)) cat(r$body, "\n") else str(r, max.level = 1); quit(status = 0L) }
aif_write_json(list(sent_at = format(now, "%Y-%m-%d %H:%M:%S"), stage_key = st$stage_key, stage_state = state, pct = pct, stage_pct = spct, event = EVENT), NSP)
nfail <- length(r$charts_failed) + length(r$charts_missing)       # 그림은 글 다음에 한 장씩 간다 — 못 보낸 장수를 로그에 남긴다
cat(sprintf("[aif-notify] 보냄 — %s · 전체 %d%% · %s · 그림 %d장%s\n", EVENT, pct, if (mute) "무음" else "알림음", length(charts), if (nfail) sprintf("(실패 %d)", nfail) else ""))
