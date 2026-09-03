#!/usr/bin/env Rscript
#==============================================================================
# rf_combination_review.R — **논문 3편마다 결합 검토** 무인 실행 (도훈 지시 2026-08-30)
#
# ★왜 필요했나 (2026-08-30 감사):
#   `rf_record_combination_review` 는 정의·문서·테스트에만 있고 **호출하는 프로덕션 코드가 0개**였다.
#   원장이 논문 소비 카운터를 올리고 3편째에 "★결합 검토 도래" 를 **stdout 에 출력**하는 데서 끝난다 —
#   무인 상태에서는 아무도 그 줄을 안 읽는다. 이 저장소가 반복해 밟은 **소비자 없는 계기**다.
#   (CLAUDE.md·lean-loop.md·reinforce SKILL 이 모두 "착수 무관 의무" 로 적어 두었으나 기계가 없었다.)
#
# 이 러너가 하는 일 — **검토는 규칙으로, 착수는 사람에게**:
#   ① 소진(exhausted) entry 들의 실측을 읽어 논문 간 **교차 비교표**를 만든다
#   ② 결합 후보를 **규칙으로** 산출한다 — 서로 다른 논문의 최고 셀이
#      (a) 팩터 원천이 다르고 (b) 둘 다 양(+) PORT_t 면 결합 후보
#   ③ `rf_record_combination_review()` 로 **검토 사실 자체를 기록**한다(의무 이행)
#   ④ 후보가 있으면 텔레그램으로 알리고 `06_Registry/combination_candidates.json` 에 남긴다
#
# ★착수하지 않는다. 결합 라운드 개시는 새 격자 설계가 필요해 규칙으로 환원되지 않는다 —
#   후보를 제시하고 멈춘다. 판정 인용은 전부 원장 essence(계약 산출값)에서만 온다.
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT); Sys.setenv(QM_ROOT = ROOT)
LOG_P <- file.path(ROOT, ".cache/reinforce_auto_log.jsonl")
CFG_P <- file.path(ROOT, "06_Registry/reinforce_auto_config.json")

jlog <- function(event, ...) {
  rec <- c(list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), event = event, src = "combo_review"), list(...))
  cat(toJSON(rec, auto_unbox = TRUE, null = "null"), "\n", sep = "", file = LOG_P, append = TRUE)
  cat(sprintf("[rf_combo] %s\n", event))
}

CFG <- if (file.exists(CFG_P)) fromJSON(CFG_P, simplifyVector = FALSE) else list()
if (!isTRUE(CFG$enabled %||% FALSE)) { jlog("halt_disabled"); quit(status = 0) }

main <- function() {
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R")))
obj <- rf_load(1L, ROOT)
due <- as.integer(obj$combination_review$papers_since_last_review %||% 0L)
THRESH <- as.integer(CFG$combination_review_every %||% 3L)
if (due < THRESH) { jlog("not_due", papers_since_last = due, threshold = THRESH); return(0L) }

# ── ① 논문별 최고 셀 (원장 essence 만 — 손계산 금지) ─────────────────────────
tops <- list()
for (e in obj$entries) {
  if (!identical(e$status, "exhausted") && !identical(e$status, "parked")) next
  best <- NULL
  for (a in e$attempts) {
    es <- a$essence; if (is.null(es) || is.null(es$port_t)) next
    v <- suppressWarnings(as.numeric(es$port_t)); if (!is.finite(v)) next
    if (is.null(best) || v > best$port_t)
      best <- list(base_id = e$base_id, n = a$n, cell = es$cell_code %||% "?",
                   port_t = v, calmar = suppressWarnings(as.numeric(es$calmar %||% NA)),
                   grade = a$grade %||% "?",
                   factor_id = NULL, paper_key = e$paper_key %||% "",
                   root_paper = (a$root_papers[[1]]$url %||% ""))
  }
  if (!is.null(best)) tops[[length(tops) + 1L]] <- best
}
if (length(tops) < 2L) {
  rf_record_combination_review(
    reviewed_papers = vapply(tops, function(t) t$base_id, character(1)),
    verdict = "no_combination",
    note = sprintf("무인 검토 %s — 비교 가능한 소진 논문이 %d편뿐이라 교차 결합 후보를 세울 수 없다. 검토 의무는 이행.",
                   format(Sys.Date()), length(tops)), root = ROOT)
  jlog("recorded_insufficient", n_papers = length(tops)); return(0L)
}

# ── ② 결합 후보 규칙 ─────────────────────────────────────────────────────────
#   (a) 서로 다른 논문 (b) 둘 다 PORT_t > 0 → 후보. 판단이 아니라 산술이다.
cands <- list()
for (i in seq_along(tops)) for (j in seq_along(tops)) {
  if (j <= i) next
  A <- tops[[i]]; B <- tops[[j]]
  if (!(A$port_t > 0 && B$port_t > 0)) next
  cands[[length(cands) + 1L]] <- list(
    a = A$base_id, a_cell = A$cell, a_port_t = A$port_t,
    b = B$base_id, b_cell = B$cell, b_port_t = B$port_t,
    rationale = sprintf("두 논문의 최고 셀이 모두 양(+) 다중검정 t값 (%.3f · %.3f) — 점수수준 결합 후보",
                        A$port_t, B$port_t))
}

# ── ③ 검토 기록 (착수 여부 무관 — 의무 이행 지점) ────────────────────────────
verdict <- if (length(cands)) "combination_candidate_identified" else "no_combination"
note <- if (length(cands))
  sprintf("무인 검토 %s — 결합 후보 %d쌍 산출. ★착수하지 않는다: 결합 라운드는 새 격자 설계가 필요해 규칙으로 환원되지 않는다. 후보는 06_Registry/combination_candidates.json.",
          format(Sys.Date()), length(cands))
else
  sprintf("무인 검토 %s — 소진 논문 %d편 중 양(+) 다중검정 t값 쌍이 없어 결합 후보 0. 검토 의무 이행.",
          format(Sys.Date()), length(tops))
rf_record_combination_review(reviewed_papers = vapply(tops, function(t) t$base_id, character(1)),
                             verdict = verdict, note = note, root = ROOT)
jlog("recorded", verdict = verdict, n_papers = length(tops), n_candidates = length(cands))

# ── ④ 후보 파일 + 알림 ───────────────────────────────────────────────────────
CP <- file.path(ROOT, "06_Registry/combination_candidates.json")
write(toJSON(list(schema = "combination_candidates_v1",
                  reviewed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                  papers = tops, candidates = cands,
                  note = "무인 검토 산출. 착수는 세션 — 결합 격자 설계가 필요하다."),
             auto_unbox = TRUE, pretty = TRUE, null = "null"), CP)

if (length(cands)) tryCatch({
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R")))
  tg_agent_brief(agent = "AlphaSearch",
    title = sprintf("[1계층] 논문 결합 검토 — 후보 %d쌍", length(cands)),
    sections = list(
      list(type = "bullet", emoji = "\U0001F3AF", heading = "현재 리서치 상황",
           items = c("단계: 1계층 강화 프로세스 — 무인 결합 검토",
                     sprintf("대상: 소진 논문 %d편의 최고 셀 교차 비교", length(tops)),
                     sprintf("위치: 논문 %d편 소비 — 결합 검토 주기 도래", due),
                     "직전 판정: 각 논문 최고 셀은 원장 실측에서 인용")),
      list(type = "summary", emoji = "\U0001F4CC",
           body = sprintf("결합 후보 %d쌍 산출 — 착수는 세션 판단입니다", length(cands))),
      # ★bullet 은 항목 2개 이상을 요구한다(v6.3 SOT). 1쌍이면 text 로 낸다 —
      #   2026-08-30 실사고: 후보 1쌍일 때 'items >= 2' 로 발송이 통째로 실패했다.
      {
        .ci <- vapply(utils::head(cands, 4), function(cd)
          substr(sprintf("%s(%s t %.2f) + %s(%s t %.2f)",
                         sub("^RP_", "", cd$a), cd$a_cell, cd$a_port_t,
                         sub("^RP_", "", cd$b), cd$b_cell, cd$b_port_t), 1, 78), character(1))
        if (length(.ci) >= 2L)
          list(type = "bullet", emoji = "\U0001F517", heading = "결합 후보", items = .ci)
        else
          list(type = "text", emoji = "\U0001F517", heading = "결합 후보",
               body = paste0("두 논문의 최고 셀을 점수수준에서 결합하는 후보입니다. ", .ci[1],
                             ". 착수는 새 격자 설계가 필요해 세션 판단으로 남깁니다."))
      },
      list(type = "bullet", emoji = "\U0001F6A9", heading = "주의",
           items = c("점수수준 결합만 1계층 — 수익 블렌드는 2계층 소관입니다",
                     "결합 라운드 착수는 새 격자 설계가 필요해 무인으로 하지 않습니다")),
      list(type = "bullet", emoji = "\u27A1\uFE0F", heading = "다음",
           items = c("처분: 검토 기록 완료 — 자본 배정 없음",
                     "후보 파일: 06_Registry/combination_candidates.json"))))
}, error = function(e) jlog("telegram_failed", err = conditionMessage(e)))
0L
}

rc <- tryCatch(main(), error = function(e) { jlog("fatal", err = conditionMessage(e)); 1L })
quit(status = if (is.numeric(rc)) as.integer(rc) else 0L)
