## aif_progress_notify.R — 텔레그램 진행 알림(승인 계획 '진행 알림'). 상태 파일을 읽어 한 통을 만들고, 보낼 때인지 스스로 판정한다.
##   실행: Rscript notify/aif_progress_notify.R [--send] [--force] [--event=start|end|error|resume|result|report] [--summary=<json>] [--note=<줄1|줄2|…>]
##     --send 가 없으면 미리보기(발송 없음 · 형식 검사만). 발송은 저장소의 단일 진입점 tg_agent_brief() 로만 한다.
##     --event=report = 종합 보고 통(요약 파일 + 1단계는 후속 연구 계획 요약 followup_plan.json + 그림). 마지막 단계(final_report · nl_report)의 결과 통도 이 모양으로 간다.
##     --note = 통에 '조치' 구획으로 덧붙일 줄(세로줄로 나눈다 · 둘 이상) — 오류 뒤 다시 띄웠을 때 원인과 조치를 알리는 데 쓴다.
##   실행 줄: 환경변수 AIF_TRACK(감시 셸이 넘긴다) — 빈 값 = 1단계 · followup = 2단계. 줄마다 상태 파일 · 단계 목록 · 직전 통 기록을 따로 쓴다.
##     두 줄이 함께 도는 동안에는 주기 통을 하나로 합친다 — 2단계 통에 '1단계 잔여' 막대 한 줄을 더하고 1단계의 주기 통은 쉰다(30분에 두 통씩 울리지 않게).
##   보내는 때: 08~23시 주기 통(설정 progress.interval_min 분마다 · 알림음) · 단계 시작/종료/오류/재개/결과(알림음) · 00~07시는 단계 전환과 오류만(무음).
##   진행률 막대는 일반 글 줄(kv 구획)로 보낸다 — code 구획은 텔레그램이 복사 단추가 달린 상자로 그린다(도훈 11-23).
##   보낸 메시지를 고치는 기능이 없으므로, 새 통이 올 때마다 더 채워진 막대가 간다.
here <- function() {   # 이 스크립트가 든 폴더의 위 폴더(연구 폴더). 경로 정규화 함수는 쓰지 않는다 — 구분자만 맞춘다
  a <- commandArgs(FALSE); f <- gsub("\\\\", "/", sub("^--file=", "", a[grepl("^--file=", a)])[1])
  if (!grepl("^([A-Za-z]:)?/", f)) f <- file.path(getwd(), f)
  dirname(dirname(f))
}
D <- here()
for (f in c("aif_common.R", "aif_status.R")) source(file.path(D, "R", f))
A <- commandArgs(TRUE); SEND <- "--send" %in% A; FORCE <- "--force" %in% A
arg1 <- function(key) sub(sprintf("^--%s=", key), "", A[grepl(sprintf("^--%s=", key), A)])[1]
EVENT <- arg1("event")
root <- aif_root(); cfg <- aif_cfg(root); setwd(root)
TRACK <- aif_track(); prog <- aif_progress_cfg(cfg)
RNAME <- prog$title %||% "AI 팩터 연구"
st <- aif_status_read(root, cfg)
NSP <- aif_track_out("notify_state.json", root = root, cfg = cfg)
ns <- if (file.exists(NSP)) tryCatch(fromJSON(NSP, simplifyVector = FALSE), error = function(e) list()) else list()
if (is.null(st$stage_key)) { cat("[aif-notify] 상태 파일에 단계가 없다 — 보낼 것이 없음\n"); quit(status = 0L) }

stages <- prog$stages; keys <- vapply(stages, function(s) s$key, "")
k <- match(st$stage_key, keys)
if (is.na(k)) { cat(sprintf("[aif-notify] 상태 파일의 단계(%s)가 이 줄의 단계 목록에 없다 — 보내지 않는다\n", st$stage_key)); quit(status = 0L) }
sg <- stages[[k]]
frac_of <- function(sp, key) as.numeric((sp %||% list())[[key]] %||% 0)
sp <- st$stage_progress
pct <- round(100 * aif_overall(st, cfg)); spct <- round(100 * frac_of(sp, st$stage_key))
open_names <- function(drop = character(0)) vapply(stages[vapply(keys, function(kk) !(kk %in% drop) && frac_of(sp, kk) < 1, TRUE)], function(s) s$name, "")   # 아직 안 끝난 단계
state <- st$stage_state %||% "running"
now <- Sys.time(); hh <- as.integer(format(now, "%H"))

## 다른 줄이 지금 돌고 있는가(상태가 실행 · 대기 · 일시 중지이고 20분 안에 갱신됨)
live_status <- function(track) {
  p <- aif_track_out("status.json", track = track, root = root, cfg = cfg)
  o <- if (file.exists(p)) tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL) else NULL
  if (is.null(o) || is.null(o$updated_at) || is.null(o$stage_key) || !((o$stage_state %||% "") %in% c("running", "waiting", "paused"))) return(NULL)
  if (as.numeric(difftime(now, as.POSIXct(o$updated_at), units = "mins")) > 20) return(NULL)
  o
}
other <- if (nzchar(TRACK)) live_status("") else if (!is.null(cfg$followup)) live_status("followup") else NULL

## 어떤 통인가 — 인자로 받지 않으면 직전 통과 비교해 정한다
if (is.na(EVENT)) {
  changed <- !identical(ns$stage_key, st$stage_key) || !identical(ns$stage_state, state)
  EVENT <- if (state == "error" && changed) "error" else if (changed && state == "running" && !identical(ns$stage_key, st$stage_key)) "start"
           else if (changed && state == "done") "end" else "hourly"
}
quiet <- hh %in% unlist(cfg$progress$quiet_hours)
due <- is.null(ns$sent_at) || as.numeric(difftime(now, as.POSIXct(ns$sent_at), units = "mins")) >= cfg$progress$interval_min
if (!FORCE && EVENT == "hourly" && (quiet || !due)) { cat(sprintf("[aif-notify] 보낼 때가 아니다(조용한 시간 %s · 간격 충족 %s)\n", quiet, due)); quit(status = 0L) }
if (!FORCE && EVENT == "hourly" && state == "done") { cat("[aif-notify] 단계가 끝난 상태 — 주기 통은 보내지 않는다\n"); quit(status = 0L) }
if (!FORCE && EVENT == "hourly" && !nzchar(TRACK) && !is.null(other)) { cat("[aif-notify] 2단계 통이 1단계 잔여 막대를 함께 싣는다 — 1단계 주기 통은 쉰다\n"); quit(status = 0L) }

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
if (nchar(head_txt) < 20L) head_txt <- paste0(head_txt, sprintf(" (%s 진행 알림)", RNAME))
## '다음' = 아직 안 끝난 단계(지금 단계 제외) — 설정의 단계 순서가 실제 실행 순서와 다를 수 있어 진행률에서 뽑는다
nxt <- c(open_names(drop = st$stage_key), "모든 단계가 끝나면 종합 브리핑을 보냅니다",
         if (nzchar(TRACK)) "계획서 = 연구 폴더 FOLLOWUP_PLAN.md" else "보고서 파일 = 연구 폴더 results/final/final_report.html")[seq_len(2L)]

gauge <- list("전체" = bar(pct), "이 단계" = bar(spct))      # 일반 글 줄로 보낸다(도훈 11-23 — code 구획은 텔레그램이 복사 상자로 그린다)
if (nzchar(TRACK) && !is.null(other)) {                      # 2단계 통에 1단계 잔여 막대를 더한다
  k1 <- match(other$stage_key, vapply(cfg$progress$stages, function(s) s$key, ""))
  nm1 <- if (is.na(k1)) other$stage_key else cfg$progress$stages[[k1]]$name
  gauge[[sprintf("1단계 잔여(%s)", nm1)]] <- bar(round(100 * frac_of(other$stage_progress, other$stage_key)))
}
secs <- list(
  list(type = "summary", body = substr(head_txt, 1L, 100L)),
  list(type = "kv", emoji = "\U0001F4CA", heading = "진행률", kv = gauge),
  list(type = "bullet", emoji = "\U0001F52C", heading = "연구 내용",
       items = c(prog$about %||% "원자료와 기존 팩터 DB(월간 값이 있는 290개)에서 새 팩터를 자동으로 만들고 성과를 잽니다", sprintf("지금 단계: %s", sg$what))),
  list(type = "kv", emoji = "\U0001F9ED", heading = "현재 단계",
       kv = list("단위" = sprintf("%s %s / %s%s", st$unit_name %||% "단위", st$unit_done %||% 0, st$unit_total %||% "?", if (!is.null(st$detail)) sprintf(" (%s)", st$detail) else ""),
                 "경과" = if (is.finite(elapsed)) dur(elapsed) else "기록 없음",
                 "남은 시간" = eta,
                 "상태" = sprintf("%s%s", state_txt, if (state == "running" && !is.null(st$ram_gb)) sprintf(" · 메모리 %.1fGB · 스레드 %s", st$ram_gb, st$threads %||% "?") else ""))),
  list(type = "bullet", emoji = "⏭", heading = "다음", items = nxt)
)
note <- arg1("note")
if (!is.na(note) && nzchar(note)) {                          # 원인 · 조치 같은 덧붙임(둘 이상의 줄)
  nl <- trimws(strsplit(note, "|", fixed = TRUE)[[1]]); nl <- nl[nzchar(nl)]
  if (length(nl) == 1L) nl <- c(nl, "자세한 기록은 연구 폴더 README.md 에 있습니다")
  secs <- append(secs, list(list(type = "bullet", emoji = "\U0001F6E0", heading = "조치", items = nl)), after = 1L)
}
charts <- NULL
sf <- arg1("summary")
sm <- if (!is.na(sf) && file.exists(sf)) fromJSON(sf, simplifyVector = FALSE) else NULL
if (EVENT %in% c("end", "result") && st$stage_key %in% c("final_report", "nl_report") && !is.null(sm)) EVENT <- "report"   # 마지막 단계의 결과 통은 종합 보고 통으로 보낸다
if (EVENT %in% c("end", "result") && !is.null(sm)) {
  secs <- append(secs, list(list(type = "bullet", emoji = "\U0001F4C8", heading = sm$title %||% "이 단계 결과", items = unlist(sm$lines))), after = 2L)
  cp <- unlist(sm$charts); cn <- unlist(sm$chart_names); ex <- file.exists(cp)
  if (any(ex)) charts <- setNames(cp[ex], cn[ex])
}
title <- sprintf("[무인] %s — %s · 전체 %d%%%s", RNAME, sg$name, pct, switch(EVENT, start = " · 시작", end = " · 끝", error = " · 오류", resume = " · 재개", result = " · 결과", ""))
## 종합 보고 통(--event=report --summary=<요약>) — 지금 도는 단계와 무관하게 끝난 묶음 전체의 결론 · 진행 · (1단계는) 후속 연구 계획 요약 · 그림을 보낸다
if (EVENT == "report") {
  if (is.null(sm)) { cat("[aif-notify] 종합 보고 통에는 --summary 가 필요하다\n"); quit(status = 2L) }
  left <- open_names()
  head_txt <- sm$headline %||% sprintf("%s — %s", sm$title %||% "종합 보고", if (nzchar(TRACK)) "비선형 멀티팩터 연구의 결과 요약" else "AI 팩터 연구에서 만든 신규 팩터 전체의 성과 요약")
  secs <- list(list(type = "summary", body = substr(head_txt, 1L, 100L)),
               list(type = "bullet", emoji = "\U0001F4C8", heading = "결론", items = unlist(sm$lines)),
               list(type = "kv", emoji = "\U0001F4CA", heading = "진행률", kv = list("전체" = bar(pct), "남은 단계" = if (length(left)) paste(left, collapse = " · ") else "없음")))
  cp <- unlist(sm$charts); cn <- unlist(sm$chart_names); ex <- file.exists(cp); if (any(ex)) charts <- setNames(cp[ex], cn[ex])
  pf <- file.path(D, "followup_plan.json")
  if (!nzchar(TRACK) && file.exists(pf)) {                   # 1단계 종합 보고에는 후속 연구 계획 요약을 함께 싣는다
    pl <- fromJSON(pf, simplifyVector = FALSE)
    secs <- c(secs, list(list(type = "bullet", emoji = "\U0001F5FA", heading = pl$title %||% "후속 연구 계획(안)", items = unlist(pl$items))))
    pc <- vapply(pl$charts %||% list(), function(p) file.path(D, p), ""); pc <- pc[file.exists(pc)]; if (length(pc)) charts <- c(charts, pc)
  }
  secs <- c(secs, list(list(type = "bullet", emoji = "⏭", heading = "다음", items = c(if (length(left)) sprintf("남은 단계(%s)가 끝나면 최종판을 다시 보냅니다", paste(left, collapse = " · ")) else "모든 단계가 끝났습니다 — 이 통이 최종판입니다",
                                                                                   sm$report_file_line %||% (if (nzchar(TRACK)) "보고서 파일 = 연구 폴더 results/nl_report/ · 계획서 = FOLLOWUP_PLAN.md" else "보고서 파일 = 연구 폴더 results/final/final_report.html · 계획서 = FOLLOWUP_PLAN.md")))))
  title <- sprintf("[무인] %s — 종합 보고 · 전체 %d%%", RNAME, pct)
}
mute <- quiet   # 낮에는 주기 통도 알림음으로 보낸다(도훈 11-23 '30분마다 · 알림음 켬') · 밤(00~07시)에 보내는 통은 종류와 무관하게 알림음 없이 채팅에만 남긴다
if (!SEND) Sys.setenv(QVEST_TG_DRY_RUN = "1")
invisible(capture.output(suppressMessages(source(file.path(root, "02_Infrastructure", "telegram", "telegram_notify.R")))))
r <- tryCatch(tg_agent_brief(agent = "Q-Lead", title = title, sections = secs, charts = charts, relaxed = TRUE, mute = mute, glossary = FALSE),
              error = function(e) { cat("[aif-notify] 발송 함수 오류:", conditionMessage(e), "\n"); NULL })
if (is.null(r)) quit(status = 2L)
if (SEND && is.list(r) && isFALSE(r$ok)) { cat("[aif-notify] 발송 실패(응답 ok = FALSE)\n"); quit(status = 3L) }
if (!SEND) { cat("[aif-notify] 미리보기(발송 없음) — 형식 검사 통과\n"); if (is.character(r)) cat(r, "\n") else if (!is.null(r$body)) cat(r$body, "\n") else str(r, max.level = 1); quit(status = 0L) }
tryCatch(aif_write_json(list(sent_at = format(now, "%Y-%m-%d %H:%M:%S"), stage_key = st$stage_key, stage_state = state, pct = pct, stage_pct = spct, event = EVENT), NSP),
         error = function(e) cat("[aif-notify] 직전 통 기록을 쓰지 못했다(발송은 됨):", conditionMessage(e), "\n"))
nfail <- length(r$charts_failed) + length(r$charts_missing)       # 그림은 글 다음에 한 장씩 간다 — 못 보낸 장수를 로그에 남긴다
cat(sprintf("[aif-notify] 보냄 — %s · 전체 %d%% · %s · 그림 %d장%s\n", EVENT, pct, if (mute) "무음" else "알림음", length(charts), if (nfail) sprintf("(실패 %d)", nfail) else ""))
