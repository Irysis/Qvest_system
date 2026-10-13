#==============================================================================
# program_report.R — v10.01 1계층 리서치 보고 발송기 (2026-10-13 · 발송 규칙 v10.01)
#
# 왜: 텔레그램 감사(10-13)의 최악 10건 — 헤드라인이 이번 결과를 말하지 않음 · 실패 원인 소실 · 포인터 절삭 ·
#   숫자 중간 절삭 · 지표명/단위 혼재 · 등급 체계 3개 노출 · 내부 코드 유출 · 상태 섹션이 맨 아래 · 블록당 푸시 4~5건.
#   이 발송기는 그 반대로 짠다(규칙 정본 = .claude/skills/qvest-telegram/SKILL.md §v10.01).
# 규칙(요약):
#   ① 리서치 1단위 = 메시지 1통. 첫 줄 = 이번 결과의 판정어(강함/보통/약함/판정 불가 · 등급).
#   ② 지표 이름은 하나: 하락 포착률(위기) · 상승 포착률(강세) · 위기 방어 판정 · CAGR · 최대낙폭 · Calmar · CDaR · PORT_t.
#      낙폭은 음수 %(−41.2%), 수익률은 부호 있는 %, 비율은 소수 둘째 자리.
#   ③ 숫자를 자르지 않는다 — 넘칠 것 같으면 행 단위로 덜어내고 "외 N건"과 산출물 경로를 남긴다.
#   ④ 내부 코드(셀 코드 · entry id · 함수명 · 절대경로)를 본문에 쓰지 않는다. 경로는 마지막 '산출물:' 한 줄만.
#   ⑤ 평상 보고는 무음(mute). 판정 변화 · 실패 · 프로그램 종료만 푸시.
# 공개: prep_fmt_pct · prep_fmt_ratio · prep_verdict_word · prep_card_digest · prep_send
# 검사: 08_Tests/programs/test_program_report.R (dry-run)
#==============================================================================
suppressPackageStartupMessages({ library(data.table) })

.prep_or <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

prep_fmt_pct <- function(x, digits = 1L, signed = TRUE) {
  if (is.null(x) || !is.finite(x)) return("—")
  s <- formatC(100 * x, format = "f", digits = digits)
  if (signed && x > 0) s <- paste0("+", s)
  sub("^-", "−", paste0(s, "%"))
}
prep_fmt_ratio <- function(x, digits = 2L) {
  if (is.null(x) || !is.finite(x)) return("—")
  sub("^-", "−", formatC(x, format = "f", digits = digits))
}

PREP_VERDICT_WORD <- c(strong = "강함", normal = "보통", weak = "약함", insufficient = "판정 불가")
prep_verdict_word <- function(v) .prep_or(unname(PREP_VERDICT_WORD[v]), "판정 불가")

## 크기 · 노출 짝 대조 귀속(MC8 · contracts/matched_controls.R::mc_attribution) — 라벨 · 상태를 사람 말로(내부 코드 비노출)
PREP_DEFENSE_WORD <- c(selection_defense = "선택 방어", size_defense = "크기 방어",
                       exposure_defense = "노출 방어", no_defense = "방어 없음", insufficient = "판정 불가(위기 2번 미만)")
PREP_CONTROL_STATUS_WORD <- c(not_applicable_long_short = "롱숏 전략이라 대조 정의 밖", no_crises = "위기 구간 없음",
                              no_holdings = "보유 기록 없음", no_windows = "보유창에 수익일 없음",
                              no_basket = "크기 바스켓을 못 만듦")

# 위기 줄에 붙일 크기+노출 짝 대조의 하락 포착률(없으면 빈 문자열)
.prep_ctrl_capture <- function(ctrl, peaks) {
  out <- rep("", length(peaks))
  pc <- if (is.list(ctrl) && is.list(ctrl[["size_exposure_matched"]])) ctrl[["size_exposure_matched"]][["per_crisis"]] else NULL
  if (is.null(pc) || !NROW(pc)) return(out)
  pc <- as.data.table(pc)
  j <- match(as.Date(peaks), as.Date(pc$peak_date))
  ok <- !is.na(j)
  if (any(ok)) out[ok] <- paste0(" · 크기·노출 짝 ", vapply(pc$control_dd_capture[j[ok]], prep_fmt_ratio, character(1)))
  out
}

# 대조 한 줄 — 귀속 라벨(attribution)이 정본, 구 단일 대조(size_matched) 라벨은 하위 호환
.prep_controls_line <- function(ctrl, window) {
  if (is.null(ctrl) || identical(ctrl[["status"]], "not_provided"))
    return("크기·노출 짝 대조 없음 — 방어가 실력인지 크기·노출 효과인지 아직 모른다")
  att <- ctrl[["attribution"]]
  aw <- if (is.list(att)) att[[window]] else NULL
  if (is.list(aw) && !is.null(aw[["label"]])) {
    a <- suppressWarnings(as.numeric(.prep_or(att[["placebo_alpha"]], NA_real_)))
    top <- if (is.finite(a)) prep_fmt_pct(1 - a, 0L, signed = FALSE) else "대부분"
    return(sprintf("크기·노출 짝 대조: %s — 같은 크기 분포·평균 노출로 무작위로 고른 포트폴리오의 %s보다 덜 빠진 위기 %s · 같은 평균 노출의 시장보다 덜 빠진 위기 %s · 시장보다 덜 빠진 위기 %s (평균 노출 %s)",
                   .prep_or(unname(PREP_DEFENSE_WORD[aw[["label"]]]), "판정 불가"), top,
                   prep_fmt_pct(aw[["share_beats_size_exposure"]], 0L, signed = FALSE),
                   prep_fmt_pct(aw[["share_beats_exposure"]], 0L, signed = FALSE),
                   prep_fmt_pct(aw[["share_beats_bench"]], 0L, signed = FALSE),
                   prep_fmt_ratio(ctrl[["exposure_profile"]][["mean"]])))
  }
  sm <- ctrl[["size_matched"]]
  if (is.list(sm) && !is.null(sm[["label"]]))
    return(sprintf("크기 짝 대조: %s(위기 %s에서 대조보다 덜 빠짐)",
                   if (identical(sm[["label"]], "selection_defense")) "선택 방어" else "크기·노출 방어",
                   prep_fmt_pct(sm[["share_beats"]], 0L, signed = FALSE)))
  paste0("크기·노출 짝 대조 판정 불가 — ", .prep_or(unname(PREP_CONTROL_STATUS_WORD[.prep_or(ctrl[["status"]], "")]), "대조 생성 실패"))
}

# 경로에서 프로젝트 루트를 떼고 슬래시로 통일 — 절대경로 유출 방지(감사 10-13: 윈도 경로 혼합으로 제거 실패)
.prep_rel <- function(p, root = Sys.getenv("QM_ROOT", "")) {
  if (is.null(p) || !nzchar(p)) return("")
  p <- gsub("\\\\", "/", p); r <- gsub("\\\\", "/", root)
  if (nzchar(r)) p <- sub(paste0("^", gsub("([.|()^${}+*?\\[\\]])", "\\\\\\1", r), "/?"), "", p)
  p
}

#' 행동 카드 → 보고 재료(판정 문장 · 위기 표 · 핵심 수치)
prep_card_digest <- function(card, window = c("overall", "visible", "test"), max_rows = 8L) {
  window <- match.arg(window)
  V <- card[[window]]
  cr <- card$crises
  head <- sprintf("위기 %d번 · 하락 포착률 중앙 %s(최악 %s) · 강세 상승 포착률 중앙 %s → 위기 방어 %s",
                  .prep_or(V$n_crisis, 0L), prep_fmt_ratio(V$crisis_dd_capture_median),
                  prep_fmt_ratio(V$crisis_dd_capture_worst), prep_fmt_ratio(V$bull_up_capture_median),
                  prep_verdict_word(V$verdict))
  ## 위기 1개 = 1줄(글머리표). 공용 표 렌더러는 모바일 가독성 때문에 2열 상한이라 5열 표를 못 쓴다.
  lines <- character(0); omitted <- 0L
  if (!is.null(cr) && nrow(cr)) {
    cr <- as.data.table(cr)
    w_sel <- window
    if (w_sel != "overall") cr <- cr[cr$window == w_sel]
    lab_w <- c(visible = "보는 창", test = "시험 창", straddle = "걸침")
    if (nrow(cr)) lines <- sprintf("%s~%s(%s) 시장 %s → 전략 %s · 포착 %s%s%s",
      format(as.Date(cr$peak_date), "%y.%m"), format(as.Date(cr$trough_date), "%y.%m"), unname(lab_w[cr$window]),
      vapply(-cr$bm_dd, prep_fmt_pct, character(1), digits = 0L),
      vapply(-cr$st_dd, prep_fmt_pct, character(1), digits = 0L),
      vapply(cr$dd_capture, prep_fmt_ratio, character(1)),
      .prep_ctrl_capture(card$controls, cr$peak_date),
      ifelse(cr$ongoing, " · 진행 중", ""))
    if (length(lines) > max_rows) { omitted <- length(lines) - max_rows; lines <- utils::tail(lines, max_rows) }
  }
  S <- card$stats
  kv <- list(
    "CAGR" = prep_fmt_pct(S$cagr),
    "최대낙폭" = prep_fmt_pct(-S$mdd),
    "Calmar" = prep_fmt_ratio(S$calmar),
    "CDaR(상위 5% 낙폭 평균)" = prep_fmt_pct(-S$cdar),
    "베타 하락장 / 상승장" = sprintf("%s / %s", prep_fmt_ratio(S$beta_down), prep_fmt_ratio(S$beta_up)),
    "롤링 3년 통과율" = if (is.finite(.prep_or(card$rolling$pass_life, NA_real_))) prep_fmt_pct(card$rolling$pass_life, 0L, signed = FALSE) else "—")
  ctrl_line <- .prep_controls_line(card$controls, window)
  list(headline = head, lines = lines, omitted = omitted, kv = kv, controls = ctrl_line,
       verdict = .prep_or(V$verdict, "insufficient"))
}

#' 한 줄(판정 · 다음)을 길이에 맞는 섹션으로 — 1줄 헤드라인(summary)은 20~100자만 받는다(tg_format_summary).
#'   범위를 벗어나면 발송 전체가 stop 으로 죽는다(10-13 dry-run 실측: '다음: 큐 다음 논문으로 넘어간다' 18자 → 1통 소실).
#'   100자 초과 = 문단(text · 문장·숫자 안 자름) · 20자 미만 = 프로그램·대상 맥락을 붙여 1줄 · 그래도 짧으면 공백 채움(내용 손실 0).
.prep_line <- function(label, body, emoji, program, target) {
  body <- as.character(body)[1]
  line <- paste0(label, ": ", body)
  if (nchar(line) > 100L) return(list(heading = label, type = "text", body = body))
  if (nchar(line) < 20L) line <- paste0(label, "(", program, "): ", body)
  if (nchar(line) < 20L) line <- paste0(label, "(", program, " · ", target, "): ", body)
  if (nchar(line) < 20L) line <- formatC(line, width = -20L)
  list(heading = "", type = "summary", emoji = emoji, body = line)
}

#' 보고 1통 발송 — 리서치 1단위 = 메시지 1통
#' @param program 프로그램 이름(예: "방어 엔진") · @param target 대상(사람이 읽는 이름)
#' @param status list(stage=, position=, previous=) — 현재 리서치 상황 4필드 중 3개(대상은 target)
#' @param verdict_line 판정 1~2줄(평문) — 없으면 카드 헤드라인
#' @param push TRUE = 푸시(판정 변화 · 실패 · 종료), FALSE = 무음
#' @param extra 추가 섹션 목록(선택)
prep_send <- function(program, target, status, card = NULL, verdict_line = NULL, next_step = NULL,
                      artifact = NULL, charts = NULL, push = FALSE, window = "overall", extra = NULL,
                      dry_run = identical(Sys.getenv("QVEST_TG_DRY_RUN", ""), "1"), root = NULL) {
  if (!exists("tg_agent_brief", mode = "function")) {
    rt <- .prep_or(root, Sys.getenv("QM_ROOT", getwd()))
    suppressMessages(source(file.path(rt, "02_Infrastructure/telegram/telegram_notify.R")))
  }
  D <- if (!is.null(card)) prep_card_digest(card, window) else NULL
  vword <- if (!is.null(D)) prep_verdict_word(D$verdict) else ""
  title <- sprintf("[1계층·%s] %s%s", program, target, if (nzchar(vword)) paste0(" — 위기 방어 ", vword) else "")
  secs <- list(list(heading = "현재 리서치 상황", type = "text",
                    body = sprintf("단계: %s\n대상: %s\n위치: %s\n직전 판정: %s",
                                   .prep_or(status$stage, "—"), target, .prep_or(status$position, "—"),
                                   .prep_or(status$previous, "—"))),
               .prep_line("판정", .prep_or(verdict_line, if (!is.null(D)) D$headline else "—"), "🎯", program, target))
  if (!is.null(D) && length(D$lines))
    secs[[length(secs) + 1L]] <- list(heading = "위기별 낙폭 (시장 대비)", type = "bullet",
                                      items = c(D$lines,
                                                if (D$omitted > 0L) sprintf("앞선 위기 %d건은 산출물에 있다", D$omitted),
                                                D$controls))
  if (!is.null(D))
    secs[[length(secs) + 1L]] <- list(heading = "핵심 수치", type = "kv", kv = D$kv)
  ## extra = 추가 섹션 목록(tg_agent_brief 섹션 형식) — 감사 지적 요약처럼 단위마다 다른 재료. 위기 표 · 핵심 수치 뒤, 다음 앞
  if (length(extra)) secs <- c(secs, extra)
  if (!is.null(next_step) && nzchar(next_step))
    secs[[length(secs) + 1L]] <- .prep_line("다음", next_step, "➡️", program, target)
  footer <- if (!is.null(artifact) && nzchar(artifact)) paste0("산출물: ", .prep_rel(artifact)) else NULL
  tg_agent_brief(agent = "AlphaSearch", title = title, sections = secs, footer = footer, charts = charts,
                 relaxed = TRUE, force = TRUE, decode_jargon = FALSE, glossary = FALSE,
                 mute = !isTRUE(push), dry_run = dry_run,
                 lock_scope = sprintf("prep_%s_%s_%s", gsub("[^A-Za-z0-9가-힣]", "_", program),
                                      gsub("[^A-Za-z0-9가-힣]", "_", target), format(Sys.time(), "%Y%m%d%H%M%S")))
}
