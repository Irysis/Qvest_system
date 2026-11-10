# l1_status_send.R — 아침 면의 1계층(v10.2) 상태 한 통 · 무음 (2026-11-10 감사 레인 B · 총괄 2단계 지시)
#
# 왜: 아침 체인이 매일 보내는 브리프 5종(BOOK MTM · P3 · 레짐 · FF5 · 논문 수집)은 v10 이전 계보다 — 1계층 진척(상설 판 · 기저 풀 ·
#   강화 사슬 · 결과 원장 · 판 표식)을 매일 보여 주는 면이 없었다. 이 단계가 그 한 칸이다(8줄 이내 · 푸시 없음 · SKILL §0.4 평상 무음).
# 원칙
#   · 상태 출처는 기존 정본 함수(round_core v1 — rc_standing_status_lines · rc_p4_base_pool · rc_p4_status · rc_outcomes_read)와 등록부 파일.
#     여기서 판정을 다시 만들지 않는다. 한 칸이 실패하면 그 칸만 '판독 불가'(체인은 계속 · 종료 코드 0).
#   · ★성과 수치를 싣지 않는다(τ_D = 2022-12-31 이후 성과 포함 — 사람 면이라도 아침 요약에는 개수 · 시각 · 상태 단어만).
# 실행: Rscript --no-save -e 'source("02_Infrastructure/ops/morning_steps/l1_status_send.R")'   (morning_briefing.sh 가 부른다)
#   QVEST_TG_DRY_RUN=1 → 본문만 출력. 시험 = 08_Tests/scenarios/test_scn_tg_alert_noise.R(L 축 · 모의 발송기).
source("02_Infrastructure/ops/morning_steps/_root.R")
suppressPackageStartupMessages(library(jsonlite))
.root <- chartr("\\", "/", getwd())
.na <- "판독 불가"
.cell <- function(expr) tryCatch(expr, error = function(e) .na)
.rd <- function(p) fromJSON(file.path(.root, p), simplifyVector = FALSE)
.hm <- function(s) if (is.null(s) || !nzchar(s)) "?" else sub("^\\d{4}-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}).*$", "\\1-\\2 \\3:\\4", s)

## round_core 정본 함수 적재(실패해도 데이터 · 판 표식 · 결정 칸은 산다)
.rc_ok <- !inherits(tryCatch(invisible(capture.output(suppressMessages(
  source(file.path(.root, "04_Research/programs/_lib/round_core/v1/load.R"))))), error = function(e) e), "error")

l1_status_lines <- function() {
  L <- list()
  ## ① 데이터 신선도 — 아침 감사 산출(morning_freshness_latest.json · 정본 freshness_audit.R)
  L$data <- .cell({
    m <- .rd("qepm/observability/morning_freshness_latest.json"); a <- m$audits$rawdata %||% list()
    sl <- a$sess_lag %||% a$session_lag %||% a$lag_sessions
    sprintf("데이터: 주가 마지막 %s · 기준 거래일 %s · 세션 지연 %s · 감사 %s", a$last_date %||% "?", m$as_of %||% "?",
            if (is.null(sl)) "미측정" else as.character(sl), .hm(m$ran_at))
  })
  ## ② 팩터 DB 최근 수리 — 판 표식 원장 마지막 줄
  L$fdv <- .cell({
    e <- .rd("06_Registry/factor_db_vintage.json")$entries
    if (!length(e)) "팩터 DB 판 표식: 기록 없음" else sprintf("팩터 DB 판 표식: %s · %s", e[[length(e)]]$id %||% "?", .hm(e[[length(e)]]$completed_at))
  })
  ## ③ 상설 판 — standing: true 인 라운드 사양마다 정본 상태 줄 첫 줄(개수만 · 성과 없음)
  L$standing <- .cell({
    if (!.rc_ok) stop("round_core 적재 실패")
    specs <- Sys.glob(file.path(.root, "04_Research/programs/*/*/round_spec.json"))
    sd <- Filter(function(p) isTRUE(tryCatch(fromJSON(p, simplifyVector = FALSE)$standing, error = function(e) FALSE)), specs)
    if (!length(sd)) "상설 판: 미등록" else paste(vapply(dirname(sd), function(d) sub("^\\[상설\\] ", "상설 판: ", rc_standing_status_lines(d, .root)[1]), ""), collapse = " / ")
  })
  ## ④ 기저 풀 — 자격 수 / 전체(정본 rc_p4_base_pool)
  L$pool <- .cell({
    if (!.rc_ok) stop("round_core 적재 실패")
    P <- rc_p4_base_pool(root = .root)
    sprintf("기저 풀: 자격 %d / 후보 %d", sum(P$eligible %in% TRUE), nrow(P))
  })
  ## ⑤ 강화 사슬 — 열린 사슬과 마지막 걸음(정본 rc_p4_status 첫 줄)
  L$chain <- .cell({
    if (!.rc_ok) stop("round_core 적재 실패")
    cd <- dirname(Sys.glob(file.path(.root, "04_Research/programs/*/*/chain_spec.json")))
    if (!length(cd)) "강화 사슬: 열린 사슬 없음" else {
      s <- vapply(cd, function(d) rc_p4_status(d, .root)[1], "")
      op <- s[!grepl("닫힘", s, fixed = TRUE)]
      if (!length(op)) sprintf("강화 사슬: 열린 사슬 없음(닫힌 %d)", length(s)) else sub("^\\[P4 사슬\\] ", "강화 사슬: ", op[1])
    }
  })
  ## ⑥ 결과 원장 — 마지막 닫기
  L$outcome <- .cell({
    if (!.rc_ok) stop("round_core 적재 실패")
    o <- rc_outcomes_read(rc_outcomes_path(.root))
    if (!length(o)) "결과 원장: 닫힌 라운드 없음" else {
      x <- o[[length(o)]]
      sprintf("결과 원장: 마지막 닫기 %s · %s · 다음 탐침 %d", x$round_id %||% "?", .hm(x$closed_at %||% x$at %||% ""), length(x$probes %||% list()))
    }
  })
  ## ⑦ 열린 결정 — decision_register 의 status = open
  L$dec <- .cell({
    it <- .rd("06_Registry/decision_register.json")$items
    sprintf("열린 결정(도훈): %d건", sum(vapply(it, function(i) identical(i$status, "open"), logical(1))))
  })
  vapply(L, function(x) if (identical(x, .na)) x else substr(gsub("\\s+", " ", x), 1L, 160L), "")
}

lines <- l1_status_lines()
## 판독 불가 칸은 이름을 붙여 남긴다(어느 칸인지 알 수 있게)
.nm <- c(data = "데이터", fdv = "팩터 DB 판 표식", standing = "상설 판", pool = "기저 풀", chain = "강화 사슬", outcome = "결과 원장", dec = "열린 결정")
lines <- ifelse(lines == .na, paste0(.nm[names(lines)], ": ", .na), lines)
cat(paste0("[l1_status] ", lines, collapse = "\n"), "\n")
if (!exists("tg_agent_brief", mode = "function"))
  invisible(capture.output(suppressMessages(source(file.path(.root, "02_Infrastructure/telegram/telegram_notify.R")))))
.r <- tryCatch(tg_agent_brief(agent = "Q-Lead", title = sprintf("[1계층] 아침 상태 — %s", format(Sys.Date(), "%m-%d")),
                              sections = list(list(type = "summary", emoji = "\U0001F9ED", body = "1계층(v10.2) 아침 상태 — 무음 일일 요약 · 7칸"),
                                              list(heading = "상태", type = "bullet", items = unname(lines))),
                              footer = "무음 · 개수 · 시각 · 상태 단어만(성과 수치 없음) · 출처 = round_core 정본 함수 · 등록부",
                              mute = TRUE, relaxed = TRUE, force = TRUE, decode_jargon = FALSE, glossary = FALSE,
                              lock_scope = sprintf("l1_status_%s", format(Sys.Date(), "%Y%m%d"))),
               error = function(e) list(ok = FALSE, error = conditionMessage(e)))
cat(sprintf("[l1_status] sent ok=%s%s\n", isTRUE(.r$ok), if (isTRUE(.r$ok)) "" else paste0(" · ", substr(.r$error %||% "?", 1, 160))))
