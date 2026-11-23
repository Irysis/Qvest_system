# l1_status_send.R — 아침 면의 1계층(v10.2) 상태 한 통 · 무음 (2026-11-10 감사 레인 B · 총괄 2단계 지시)
#
# 왜: 아침 체인이 매일 보내는 브리프 5종(BOOK MTM · P3 · 레짐 · FF5 · 논문 수집)은 v10 이전 계보다 — 1계층 진척(상설 판 · 기저 풀 ·
#   강화 사슬 · 결과 원장 · 판 표식)을 매일 보여 주는 면이 없었다. 이 단계가 그 한 칸이다(8줄 이내 · 푸시 없음 · SKILL §0.4 평상 무음).
# 원칙
#   · 상태 출처는 기존 정본 함수(round_core 마지막 출시 판 — rc_standing_status_lines · rc_p4_base_pool · rc_p4_status · rc_outcomes_read)와 등록부 파일.
#     여기서 판정을 다시 만들지 않는다. 한 칸이 실패하면 그 칸만 '판독 불가'(체인은 계속 · 종료 코드 0).
#   · ★성과 수치를 싣지 않는다(τ_D = 2022-12-31 이후 성과 포함 — 사람 면이라도 아침 요약에는 개수 · 시각 · 상태 단어만).
#   · (2026-11-24 도훈 '앞으로 Q-Lead 아침상태 텔레 메세지에 강화 계층 외에 현재 개별적으로 진행 중인 연구들에 대한 브리핑도 넣어줘')
#     '개별 연구' 구획 — 등록부 06_Registry/research_briefs.json 의 켜진 항목마다 한 줄(단계 · 상태 단어 · 진행률 · 갱신 시각 · 멈춤 표지) ·
#     줄 = morning_steps/research_brief_lines.R(시험 08_Tests/ops/test_research_brief_lines.R). ② 판 표식 칸은 원장에 열린 줄이 있으면 '진행 중'.
# 실행: Rscript --no-save -e 'source("02_Infrastructure/ops/morning_steps/l1_status_send.R")'   (morning_briefing.sh 가 부른다)
#   QVEST_TG_DRY_RUN=1 → 본문만 출력. 시험 = 08_Tests/scenarios/test_scn_tg_alert_noise.R(L 축 · 모의 발송기).
source("02_Infrastructure/ops/morning_steps/_root.R")
suppressPackageStartupMessages(library(jsonlite))
.root <- chartr("\\", "/", getwd())
.na <- "판독 불가"
.cell <- function(expr) tryCatch(expr, error = function(e) .na)
.rd <- function(p) fromJSON(file.path(.root, p), simplifyVector = FALSE)
.hm <- function(s) if (is.null(s) || !nzchar(s)) "?" else sub("^\\d{4}-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}).*$", "\\1-\\2 \\3:\\4", s)

## round_core 정본 함수 적재(실패해도 데이터 · 판 표식 · 결정 칸은 산다) — 판 = RELEASES.json 의 마지막 출시 판(11-11 판 라우팅 · round.sh 사양 없는 호출과 같은 규칙)
##   기저 풀 칸(④)은 그 판의 자격 규칙으로 센다(v2 = 상설 통과만 · 칸 단위 — 도훈 11-11 P4-BASE-POOL-GRADE-PATH-TAU-20261111 (나)). 판독 불가 = v1.
.rc_ver <- tryCatch({
  r <- fromJSON(file.path(.root, "04_Research/programs/_lib/round_core/RELEASES.json"), simplifyVector = FALSE)$releases
  v <- vapply(r, function(x) if (identical(x$status, "released") && is.character(x$version)) x$version else NA_character_, ""); v <- v[!is.na(v)]
  if (length(v)) v[length(v)] else "v1" }, error = function(e) "v1")
.rc_ok <- !inherits(tryCatch(invisible(capture.output(suppressMessages(
  source(file.path(.root, "04_Research/programs/_lib/round_core", .rc_ver, "load.R"))))), error = function(e) e), "error")

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
    op <- Filter(function(x) !is.character(x$completed_at) || !nzchar(x$completed_at), e)   # 열린 줄 = 수리 진행 중(completed_at 없음)
    if (!length(e)) "팩터 DB 판 표식: 기록 없음"
    else if (length(op)) sprintf("팩터 DB 판 표식: %s · 진행 중(열린 줄 %d)", op[[length(op)]]$id %||% "?", length(op))
    else sprintf("팩터 DB 판 표식: %s · %s", e[[length(e)]]$id %||% "?", .hm(e[[length(e)]]$completed_at))
  })
  ## ③ 상설 판 — standing: true 인 라운드 사양마다 정본 상태 줄 첫 줄(개수만 · 성과 없음)
  L$standing <- .cell({
    if (!.rc_ok) stop("round_core 적재 실패")
    specs <- Sys.glob(file.path(.root, "04_Research/programs/*/*/round_spec.json"))
    sd <- Filter(function(p) isTRUE(tryCatch(fromJSON(p, simplifyVector = FALSE)$standing, error = function(e) FALSE)), specs)
    ## 판마다 그 판의 코어로 읽는다(11-11 판 라우팅) — 한 프로세스엔 코어 판 하나만 적재되고, 상설 상태 함수는 판의 핀(코어 판 · 매니페스트)을 대조한다.
    ##   같은 판이면 적재한 코어로 바로, 다른 판(예: P1S01 = v1)이면 round.sh <판> standing-status(사양 core_version 라우팅) 자식 실행의 첫 줄.
    one <- function(d) {
      cv <- tryCatch(fromJSON(file.path(d, "round_spec.json"), simplifyVector = FALSE)$core_version, error = function(e) NULL)
      cv <- if (is.character(cv) && length(cv) == 1L && grepl("^v[0-9]+$", cv)) cv else "v1"
      ln <- if (identical(cv, .rc_ver)) rc_standing_status_lines(d, .root)[1] else {
        old <- Sys.getenv(c("RC_ROOT_WIN", "RC_ROOT_POSIX"), unset = NA)
        on.exit(for (k in names(old)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, stats::setNames(list(old[[k]]), k)), add = TRUE)
        Sys.setenv(RC_ROOT_WIN = .root, RC_ROOT_POSIX = sub("^([A-Za-z]):", "/\\L\\1", .root, perl = TRUE))   # round.sh 가 이 루트에서 돈다(system2 env 인자는 Windows 에서 안 먹는다)
        o <- tryCatch(suppressWarnings(system2(qv_bash(), c(shQuote(file.path(.root, "04_Research/programs/_lib/round_core/round.sh")), shQuote(rc_rel(d, .root)), "standing-status"),
                                               stdout = TRUE, stderr = FALSE)), error = function(e) character(0))
        o <- o[grepl("^\\[상설\\] ", o)]; if (length(o)) o[1] else stop("판 ", basename(d), " 상태 판독 불가(", cv, ")") }
      sub("^\\[상설\\] ", "상설 판: ", ln)
    }
    if (!length(sd)) "상설 판: 미등록" else paste(vapply(dirname(sd), one, ""), collapse = " / ")
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
## 개별 연구 — 1계층 라운드 · 강화 사슬 밖에서 개별로 진행 중인 연구(등록부 06_Registry/research_briefs.json · 줄 = research_brief_lines.R)
##   항목 하나가 실패하면 그 줄만 판독 불가 · 줄 함수 자체를 못 읽으면 구획 한 줄이 판독 불가(통은 그대로 간다)
rlines <- .cell({
  .rb_env <- new.env()
  sys.source(file.path(.root, "02_Infrastructure/ops/morning_steps/research_brief_lines.R"), envir = .rb_env)
  .rb_env$research_brief_lines(.root)
})
if (identical(rlines, .na)) rlines <- paste0("개별 연구: ", .na)
cat(paste0("[l1_status] ", rlines, collapse = "\n"), "\n")
if (!exists("tg_agent_brief", mode = "function"))
  invisible(capture.output(suppressMessages(source(file.path(.root, "02_Infrastructure/telegram/telegram_notify.R")))))
.r <- tryCatch(tg_agent_brief(agent = "Q-Lead", title = sprintf("[1계층] 아침 상태 — %s", format(Sys.Date(), "%m-%d")),
                              sections = list(list(type = "summary", emoji = "\U0001F9ED", body = "1계층(v10.2) 아침 상태 — 무음 일일 요약 · 7칸 + 개별 연구"),
                                              list(heading = "상태", type = "bullet", items = unname(lines)),
                                              list(heading = "개별 연구", type = "bullet", items = unname(rlines))),
                              footer = "무음 · 개수 · 시각 · 상태 단어만(성과 수치 없음) · 출처 = round_core 정본 함수 · 등록부 · 개별 연구 = 06_Registry/research_briefs.json",
                              mute = TRUE, relaxed = TRUE, force = TRUE, decode_jargon = FALSE, glossary = FALSE,
                              lock_scope = sprintf("l1_status_%s", format(Sys.Date(), "%Y%m%d"))),
               error = function(e) list(ok = FALSE, error = conditionMessage(e)))
cat(sprintf("[l1_status] sent ok=%s%s\n", isTRUE(.r$ok), if (isTRUE(.r$ok)) "" else paste0(" · ", substr(.r$error %||% "?", 1, 160))))
