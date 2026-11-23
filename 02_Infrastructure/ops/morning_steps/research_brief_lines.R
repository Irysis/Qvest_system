# research_brief_lines.R — 아침 1계층 상태 통의 '개별 연구' 줄 (2026-11-24 · 도훈 '앞으로 Q-Lead 아침상태 텔레 메세지에 강화 계층 외에
#   현재 개별적으로 진행 중인 연구들에 대한 브리핑도 넣어줘')
#
# 원천 = 06_Registry/research_briefs.json — 항목마다 상태 원천 하나(kind):
#   aif_status   AI 팩터 연구의 상태 파일(<aif_config.json paths.out_cache>/[<track>/]status.json) · 단계 이름과 가중치 = 그 연구의 aif_config.json
#                (전체 진행률 = 단계 가중치 × 단계 안 진행률 — 그 연구의 R/aif_status.R::aif_overall 과 같은 식 · 시험이 그 함수와 대조한다)
#   status_json  공통 약속(등록부 status_json_schema) — 연구 폴더의 status.json(또는 항목의 status 경로)
#   readme_state README 의 '상태:' 첫 줄 + README 갱신 시각
# 여기서 연구의 판정을 새로 만들지 않는다 — 그 연구가 쓰는 상태를 옮길 뿐이다(단계 · 상태 단어 · 진행률 · 갱신 시각).
# 원칙: 항목 하나가 실패하면 그 줄만 '판독 불가'(다른 줄 · 통은 산다) · 성과 수치 없음(소수 · 퍼센트 · 부호 달린 수가 든 세부 글은 뺀다 —
#   아침 상태 통의 '개수 · 시각 · 상태 단어만' 원칙) · 진행 · 대기인데 stale_hours_running 시간 넘게 갱신이 없으면
#   '★갱신 없음 n시간(멈춤 확인)'(도훈 11-15 '멈춰있나 싶어' — 조용하면 멈춘 줄 안다).
# 등록 안 된 연구 폴더(discover) = 맨 위 항목의 마지막 수정이 recent_days 안 · 등록 항목과 ignore 밖 → 이름만 한 줄.
# 사용: e <- new.env(); sys.source("02_Infrastructure/ops/morning_steps/research_brief_lines.R", envir = e); e$research_brief_lines(root)
# 시험 = 08_Tests/ops/test_research_brief_lines.R
suppressPackageStartupMessages(library(jsonlite))

.rb_or <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
.rb_state_word <- c(running = "진행 중", waiting = "대기", paused = "일시 중지", done = "끝", error = "오류")
## 성과 수치처럼 보이는 글 = 소수 · 퍼센트 · 낱말 앞의 부호 달린 수(날짜 '11-24' 같은 붙은 하이픈은 아니다)
.rb_numeric_rx <- "[0-9][.][0-9]|[0-9][[:space:]]*%|(^|[[:space:](=:])[+−-][0-9]"

.rb_clean <- function(s, n = 90L) {
  if (is.null(s) || !length(s) || is.na(s[1]) || !nzchar(trimws(s[1]))) return(NA_character_)
  s <- gsub("[*`]", "", gsub("[[:space:]]+", " ", trimws(as.character(s[1]))))
  if (grepl(.rb_numeric_rx, s, perl = TRUE)) return("(수치가 든 세부 글 — 생략)")
  if (nchar(s) > n) paste0(substr(s, 1L, n - 1L), "…") else s
}
.rb_time <- function(x) {   # 'YYYY-MM-DD HH:MM:SS' · 'YYYY-MM-DDTHH:MM:SS(+zone)' → POSIXct(현지 시각)
  if (is.null(x) || !length(x) || is.na(x[1]) || !nzchar(x[1])) return(as.POSIXct(NA))
  as.POSIXct(sub("T", " ", substr(as.character(x[1]), 1L, 19L)), format = "%Y-%m-%d %H:%M:%S", tz = "")
}
.rb_hm <- function(t) if (length(t) != 1L || is.na(t)) "?" else format(t, "%m-%d %H:%M")
.rb_pct <- function(x) {
  v <- suppressWarnings(as.numeric(.rb_or(x, NA)))
  if (length(v) != 1L || is.na(v)) NA_integer_ else as.integer(round(100 * min(1, max(0, v))))
}
.rb_stale <- function(state, t, now, hrs) {
  if (!(state %in% c("running", "waiting")) || is.na(t)) return("")
  h <- as.numeric(difftime(now, t, units = "hours"))
  if (is.finite(h) && h > hrs) sprintf(" · ★갱신 없음 %d시간(멈춤 확인)", as.integer(floor(h))) else ""
}
.rb_word <- function(state) { w <- .rb_state_word[state]; if (is.na(w)) state else unname(w) }

## AI 팩터 연구 상태 파일
.rb_aif <- function(it, root, now, hrs) {
  dir <- file.path(root, it$dir)
  cfg <- fromJSON(file.path(dir, "aif_config.json"), simplifyVector = FALSE)
  track <- .rb_or(it$track, "")
  prog <- if (nzchar(track)) cfg[[track]]$progress else cfg$progress
  out <- file.path(root, cfg$paths$out_cache)
  st <- fromJSON(if (nzchar(track)) file.path(out, track, "status.json") else file.path(out, "status.json"), simplifyVector = FALSE)
  sg <- prog$stages
  keys <- vapply(sg, function(s) s$key, "")
  w <- vapply(sg, function(s) as.numeric(s$weight), 0)
  f <- vapply(keys, function(k) as.numeric(.rb_or(st$stage_progress[[k]], 0)), 0)
  overall <- sum(w * pmin(1, pmax(0, f))) / sum(w)
  k <- match(.rb_or(st$stage_key, ""), keys)
  stage <- if (is.na(k)) .rb_or(st$stage_key, "?") else .rb_or(sg[[k]]$name, keys[k])
  state <- .rb_or(st$stage_state, "running")
  t <- .rb_time(st$updated_at)
  why <- if (identical(state, "waiting")) .rb_clean(st$wait_reason) else NA_character_
  det <- .rb_clean(st$detail)
  parts <- c(sprintf("%s %s%s", stage, .rb_word(state), if (is.na(k)) "" else sprintf("(단계 %d%%)", .rb_pct(f[[k]]))),
             sprintf("전체 %d%%", .rb_pct(overall)),
             if (!is.na(why)) paste0("대기 사유 ", why),
             if (!is.na(det)) det,
             sprintf("갱신 %s", .rb_hm(t)))
  paste0(it$name, ": ", paste(parts, collapse = " · "), .rb_stale(state, t, now, hrs))
}

## 공통 약속 status.json
.rb_status_json <- function(it, root, now, hrs) {
  st <- fromJSON(file.path(root, .rb_or(it$status, file.path(it$dir, "status.json"))), simplifyVector = FALSE)
  state <- .rb_or(st$state, "running")
  t <- .rb_time(st$updated_at)
  sp <- .rb_pct(st$stage_progress); op <- .rb_pct(st$progress)
  det <- .rb_clean(st$detail); nx <- .rb_clean(st[["next"]])
  parts <- c(sprintf("%s %s%s", .rb_or(st$stage, "?"), .rb_word(state), if (is.na(sp)) "" else sprintf("(단계 %d%%)", sp)),
             if (!is.na(op)) sprintf("전체 %d%%", op),
             if (!is.na(det)) det,
             if (!is.na(nx)) paste0("다음 ", nx),
             sprintf("갱신 %s", .rb_hm(t)))
  paste0(it$name, ": ", paste(parts, collapse = " · "), .rb_stale(state, t, now, hrs))
}

## README '상태:' 첫 줄
.rb_readme <- function(it, root, now, hrs) {
  p <- file.path(root, it$dir, .rb_or(it$readme, "README.md"))
  x <- readLines(p, encoding = "UTF-8", warn = FALSE)
  rx <- "^[[:space:]]*(\\*\\*)?상태(\\*\\*)?[[:space:]]*[:：][[:space:]]*"
  i <- grep(rx, x, perl = TRUE)[1]
  s <- if (is.na(i)) "(README 에 '상태:' 줄 없음)" else .rb_or(.rb_clean(sub(rx, "", x[i], perl = TRUE), 100L), "(빈 상태 줄)")
  sprintf("%s: %s · README 갱신 %s", it$name, s, .rb_hm(file.info(p)$mtime))
}

## 등록 안 된 최근 연구 폴더
.rb_discover <- function(reg, root, now) {
  d <- reg$discover
  if (is.null(d)) return(character(0))
  base <- file.path(root, .rb_or(d$root, "04_Research/01_reports"))
  days <- as.numeric(.rb_or(d$recent_days, 3))
  known <- c(vapply(.rb_or(reg$items, list()), function(it) basename(.rb_or(it$dir, "")), ""),
             vapply(.rb_or(d$ignore, list()), function(g) .rb_or(g$dir, ""), ""))
  dirs <- list.dirs(base, recursive = FALSE, full.names = TRUE)
  dirs <- dirs[!(basename(dirs) %in% known)]
  recent <- vapply(dirs, function(dd) {
    m <- file.info(list.files(dd, full.names = TRUE, no.. = TRUE))$mtime
    m <- m[!is.na(m)]
    length(m) > 0L && as.numeric(difftime(now, max(m), units = "days")) <= days
  }, logical(1))
  basename(dirs[recent])
}

research_brief_lines <- function(root, reg_path = file.path(root, "06_Registry", "research_briefs.json"), now = Sys.time()) {
  reg <- fromJSON(reg_path, simplifyVector = FALSE)
  hrs <- as.numeric(.rb_or(reg$stale_hours_running, 6))
  items <- Filter(function(it) isTRUE(it$active), .rb_or(reg$items, list()))
  rd <- list(aif_status = .rb_aif, status_json = .rb_status_json, readme_state = .rb_readme)
  out <- vapply(items, function(it) {
    f <- rd[[.rb_or(it$kind, "")]]
    if (is.null(f)) return(sprintf("%s: 판독 불가(상태 원천 종류 '%s' 모름)", .rb_or(it$name, "?"), .rb_or(it$kind, "")))
    tryCatch(f(it, root, now, hrs),
             error = function(e) sprintf("%s: 판독 불가(%s)", .rb_or(it$name, "?"), substr(gsub("[[:space:]]+", " ", conditionMessage(e)), 1L, 60L)))
  }, "")
  if (!length(out)) out <- "개별 연구: 진행 중으로 등록된 항목 없음"
  nd <- tryCatch(.rb_discover(reg, root, now), error = function(e) character(0))
  if (length(nd))
    out <- c(out, sprintf("등록 안 된 최근 연구 폴더 %d개: %s(06_Registry/research_briefs.json 에 올리면 줄이 생긴다)",
                          length(nd), paste(head(nd, 4L), collapse = " · ")))
  vapply(out, function(x) substr(gsub("[[:space:]]+", " ", x), 1L, 160L), "", USE.NAMES = FALSE)
}
