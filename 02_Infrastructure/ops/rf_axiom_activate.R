#!/usr/bin/env Rscript
#==============================================================================
# rf_axiom_activate.R — 공리 **자동 활성화 + 사후 통보** (도훈 지시 2026-08-30)
#
# 도훈 원문: "활성화까지도 무인화 시켜줘. 대신 활성화 시킬 때 어떤 공리를 활성화시키는지
#            텔레그램으로 알려줘. 그거 보고 내가 판단해서 잘못된 공리는 재검토 요청하면 될 듯."
#   ⇒ 정책 전환: **사전 승인(opt-in) → 자동 활성화 + 사후 검토(opt-out)**.
#
# ★기계 승인 게이트는 이미 있다 — 새로 만들지 않는다.
#   `refine_statement.R`(활성화 게이트 R0~R6)이 바로 이 목적으로 만들어졌다:
#   "사람 승인을 없애려면 승인이 하던 일 — 이 문장이 대전제로 설 자격이 있는가 — 을
#    기계가 해야 한다. ★LLM 을 쓰지 않는다." 그 게이트 통과 = needs_refinement=FALSE.
#   빠져 있던 것은 **마지막 고리**뿐이다 — 통과분을 실제로 켜는 호출.
#
# 활성화 조건 (셋 다 — 하나라도 어기면 켜지 않는다):
#   ① promotion$all_hurdles_pass == TRUE   (승격 사다리 통과)
#   ② needs_refinement == FALSE            (정제 게이트 R0~R6 통과 — 초안 문구 차단)
#   ③ 활성 상한 미초과                      (모드당 6 · 총 20 — 주입 렌더 상한 보호)
#
# ★초안(needs_refinement=TRUE)은 절대 켜지 않는다. 그 문구는 클러스터 메타데이터라
#   ("[실증 혼재(방향불명) 규칙 초안] family=..., tags=..., supporting=8건") 켜면 모든
#   에이전트 프롬프트 최상단에 초안 텍스트가 대전제로 박힌다. 대신 텔레그램으로 보고한다.
#
# 되돌리기(사후 검토): `deactivate_axiom(<id>)` 또는 `rollback_axiom(<id>)`.
#   텔레그램 본문에 그 경로를 항상 넣는다 — 알림만 하고 되돌릴 방법을 안 주면 통보가 아니다.
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT); Sys.setenv(QM_ROOT = ROOT, CLAUDE_PROJECT_DIR = ROOT)
LOG_P <- file.path(ROOT, ".cache/reinforce_auto_log.jsonl")
CFG_P <- file.path(ROOT, "06_Registry/reinforce_auto_config.json")

jlog <- function(event, ...) {
  rec <- c(list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), event = event, src = "axiom_activate"), list(...))
  cat(toJSON(rec, auto_unbox = TRUE, null = "null"), "\n", sep = "", file = LOG_P, append = TRUE)
  cat(sprintf("[ax_act] %s\n", event))
}
CFG <- if (file.exists(CFG_P)) fromJSON(CFG_P, simplifyVector = FALSE) else list()
if (!isTRUE(CFG$enabled %||% FALSE)) { jlog("halt_disabled"); quit(status = 0) }
MAX_MODE  <- as.integer(CFG$axiom_max_active_per_mode %||% 6L)
MAX_TOTAL <- as.integer(CFG$axiom_max_active_total %||% 20L)

main <- function() {
MD <- file.path(ROOT, "qepm/memory/axioms/active/modes")
fs <- list.files(MD, pattern = "^AX-.*\\.json$", full.names = TRUE, recursive = TRUE)
if (!length(fs)) { jlog("no_candidates"); return(0L) }

read1 <- function(f) { d <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(d)) return(NULL)
  list(f = f, id = d$axiom_id %||% "", mode = d$research_mode %||% "?",
       status = d$status %||% "active", pass = isTRUE((d$promotion %||% list())$all_hurdles_pass),
       refine = isTRUE(d$needs_refinement), pol = d$polarity %||% "?",
       score = suppressWarnings(as.numeric((d$promotion %||% list())$weighted_score %||% NA)),
       nsup = length(d$supporting_l_codes %||% list()),
       stmt = as.character(d$statement_inject %||% d$statement %||% "")) }
A <- Filter(Negate(is.null), lapply(fs, read1))

n_active_mode <- table(vapply(Filter(function(x) identical(x$status, "active"), A),
                              function(x) x$mode, character(1)))
n_active_tot  <- sum(vapply(A, function(x) identical(x$status, "active"), logical(1)))

elig <- Filter(function(x) identical(x$status, "proposed") && x$pass && !x$refine, A)
blocked_draft <- Filter(function(x) identical(x$status, "proposed") && x$refine, A)

# 점수 높은 순 — 상한 안에서만
elig <- elig[order(vapply(elig, function(x) -(x$score %||% -Inf), numeric(1)))]
approved <- list(); skipped_cap <- list()
for (x in elig) {
  cm <- as.integer(n_active_mode[[x$mode]] %||% 0L)
  if (n_active_tot >= MAX_TOTAL || cm >= MAX_MODE) { skipped_cap[[length(skipped_cap)+1L]] <- x; next }
  approved[[length(approved)+1L]] <- x
  n_active_mode[[x$mode]] <- cm + 1L; n_active_tot <- n_active_tot + 1L
}

if (length(approved)) {
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/axiom/promote.R")))
  ids <- vapply(approved, function(x) x$id, character(1))
  r <- tryCatch(approve_axiom(ids, approved_by = "auto_runner_2026-08-30_dohoon_policy", root = ROOT),
                error = function(e) { jlog("approve_failed", err = conditionMessage(e)); NULL })
  jlog("activated", n = length(ids), ids = paste(ids, collapse = ","))
} else {
  jlog("nothing_eligible", n_proposed = length(Filter(function(x) identical(x$status,"proposed"), A)),
       n_blocked_draft = length(blocked_draft), n_skipped_cap = length(skipped_cap))
}

# ── 텔레그램: 켠 것 + 왜 안 켰는지. 되돌리기 경로를 반드시 포함한다 ───────────
if (length(approved) || length(blocked_draft)) tryCatch({
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R")))
  .act <- if (length(approved))
    vapply(utils::head(approved, 4), function(x)
      substr(sprintf("%s [%s] 근거 %d건 · 점수 %.2f — %s", x$id, x$mode, x$nsup, x$score,
                     gsub("\\s+", " ", substr(x$stmt, 1, 40))), 1, 78), character(1))
  else character(0)
  secs <- list(
    list(type = "bullet", emoji = "\U0001F3AF", heading = "현재 리서치 상황",
         items = c("단계: 공리 승격 체계 — 무인 활성화",
                   sprintf("대상: 후보 %d건(제안 상태) 검사", length(Filter(function(x) identical(x$status,"proposed"), A))),
                   sprintf("위치: 활성 %d/%d · 모드당 상한 %d", n_active_tot, MAX_TOTAL, MAX_MODE),
                   sprintf("직전 판정: 정제 게이트 미통과 %d건 보류", length(blocked_draft)))),
    list(type = "summary", emoji = "\U0001F4CC",
         body = if (length(approved))
           sprintf("공리 %d건을 자동 활성화했습니다 — 검토 후 필요하면 되돌리십시오", length(approved))
         else sprintf("활성화 0건 — 정제 게이트 미통과 %d건이 초안 상태입니다", length(blocked_draft))))
  if (length(.act) >= 2L)
    secs <- c(secs, list(list(type = "bullet", emoji = "\u2705", heading = "활성화된 공리", items = .act)))
  else if (length(.act) == 1L)
    secs <- c(secs, list(list(type = "text", emoji = "\u2705", heading = "활성화된 공리", body = .act[1])))
  secs <- c(secs, list(
    list(type = "bullet", emoji = "\U0001F6A9", heading = "주의",
         items = c(sprintf("초안 문구 %d건은 켜지 않았습니다 — 클러스터 요약이지 규칙이 아닙니다", length(blocked_draft)),
                   "활성 상한은 주입 렌더 한도(모드당 2줄)를 보호합니다")),
    list(type = "bullet", emoji = "\u27A1\uFE0F", heading = "되돌리기",
         items = c("잘못된 공리는 deactivate_axiom(<id>) 로 즉시 끕니다",
                   "이력까지 되돌리려면 rollback_axiom(<id>) 를 씁니다"))))
  tg_agent_brief(agent = "AlphaSearch",
    title = sprintf("[1계층] 공리 자동 활성화 — %d건", length(approved)), sections = secs)
}, error = function(e) jlog("telegram_failed", err = conditionMessage(e)))
0L
}
rc <- tryCatch(main(), error = function(e) { jlog("fatal", err = conditionMessage(e)); 1L })
quit(status = if (is.numeric(rc)) as.integer(rc) else 0L)
