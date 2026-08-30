#!/usr/bin/env Rscript
#==============================================================================
# reinforce_auto_next_paper.R — 20칸 소진 후 **다음 논문으로 이월** (무인화, 2026-08-30)
#
# 도훈 지시: "강화프로세스 20회 진행 후에도 개선이 없으면 다른 논문으로 옮겨가게 해줘".
#
# 호출자 = reinforce_auto_run.R (entry status=exhausted 직후, 비동기)
# 하는 일:
#   1) 소진된 entry 의 최고 셀이 기저 대비 개선을 냈는지 판정해 로그·텔레그램에 남긴다
#      (개선 유무와 무관하게 이월한다 — 상한은 20회다. 개선이 있었다면 그 사실이 기록된다)
#   2) 논문 큐(alpha-pending)에서 다음 논문 1편을 뽑는다
#      ★술어는 research_pool_predicates.py 정본을 **CLI 로 호출**한다 — 재구현 금지
#        (그 파일이 명시한 계약. 소비자 독립 구현이 같은 결함을 3번 재발시킨 전례)
#   3) 그 논문의 충실구현을 돌린다 (논문 그대로 · 유니버스만 K200∪KQ150)
#   4) 등급이 A 미만이면 rf_open_entry 로 새 강화 entry 를 열어 루프를 잇는다
#      A 면 judge_request 발행 + kill switch 정지 (도훈 confirm)
#
# ★이 파일은 논문을 고르지 않는다 — 큐 순서를 그대로 따른다. 재검색·재정렬 금지(lean-loop 규약).
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT); Sys.setenv(QM_ROOT = ROOT, CLAUDE_PROJECT_DIR = ROOT)
LOG_P <- file.path(ROOT, ".cache/reinforce_auto_log.jsonl")
CFG_P <- file.path(ROOT, "06_Registry/reinforce_auto_config.json")
PY    <- Sys.getenv("QVEST_PY", "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe")

jlog <- function(event, ...) {
  rec <- c(list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), event = event, src = "next_paper"), list(...))
  cat(toJSON(rec, auto_unbox = TRUE, null = "null"), "\n", sep = "", file = LOG_P, append = TRUE)
  cat(sprintf("[rf_next] %s\n", event))
}

CFG <- if (file.exists(CFG_P)) fromJSON(CFG_P, simplifyVector = FALSE) else list()
if (!isTRUE(CFG$enabled %||% FALSE)) { jlog("halt_disabled"); quit(status = 0) }

main <- function() {
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R")))
led <- rf_load(1L, ROOT)

# 이미 active 가 있으면 이월할 필요 없음 (중복 개설 방지)
if (length(Filter(function(e) identical(e$status, "active"), led$entries))) {
  jlog("halt_active_exists"); return(invisible(0L))
}

# ── 1. 소진 entry 의 성적 요약 (개선 유무 판정 — 이월은 무조건) ──────────────
ex <- Filter(function(e) identical(e$status, "exhausted"), led$entries)
best <- NULL
if (length(ex)) {
  E <- ex[[length(ex)]]
  pts <- vapply(E$attempts, function(a) {
    v <- tryCatch(as.numeric(a$essence$port_t), error = function(e) NA_real_)
    if (length(v) != 1L) NA_real_ else v
  }, numeric(1))
  if (any(is.finite(pts))) {
    i <- which.max(replace(pts, !is.finite(pts), -Inf))
    best <- list(base_id = E$base_id, n = E$attempts[[i]]$n,
                 port_t = pts[i], grade = E$attempts[[i]]$grade,
                 base_grade = E$base_grade,
                 cell_code = E$attempts[[i]]$essence$cell_code %||% NA_character_,
                 spec      = E$attempts[[i]]$essence$spec %||% NA_character_,
                 artifacts = E$attempts[[i]]$artifacts %||% NA_character_)
  }
  jlog("exhausted_summary", base_id = E$base_id, attempts = length(E$attempts),
       best_port_t = best$port_t %||% NA, best_grade = best$grade %||% "NA",
       improved = isTRUE(!identical(best$grade %||% "F", E$base_grade %||% "F")))
}

# ── ★1.5 B등급 이상 승격 분기 (도훈 지시 2026-08-30) ─────────────────────────
#   구판의 유일한 배선은 "20칸 소진 → 다음 논문" 하나였다. 그러면 B 를 낸 구성이
#   더 파보지도 못하고 큐 뒤로 밀린다 — 20칸은 상한이지 그 신호의 한계가 아니다.
#   그래서 소진 시점에 승자가 B+ 면 그 구성을 carry 로 물려 **새 20칸**을 연다.
#   ★승격은 자기 값을 증명해야 이어진다 — 부모 최고 PORT_t 를 넘지 못하면 승격하지 않는다.
#     (넘지 못한 승격은 같은 실패의 재생산이고, 그게 20회 상한의 존재 이유다)
#   ★깊이 상한은 큐 정체 방지 — 한 논문이 승격 사슬로 무한히 예산을 먹지 않게 한다.
# ★판정은 rf_promote.R 의 순수 함수 하나 — 인라인으로 두면 검사가 못 건드린다.
if (length(ex)) {
  E2 <- ex[[length(ex)]]
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_promote.R")))
  PD    <- rf_promote_decide(E2, best, CFG)
  MAXD  <- as.integer(CFG$promote_max_depth %||% 3L)
  depth <- PD$depth
  sp    <- best$spec %||% NA_character_

  if (!isTRUE(PD$ok)) {
    # ★조용히 넘어가지 않는다 — 자격이 있었는데 못 한 것(스펙 부재)과 자격이 없어서
    #   안 한 것(등급 미달)은 다른 사건이고, 사유가 없으면 둘을 구분할 수 없다.
    jlog("promote_skipped", reason = PD$reason, base_id = E2$base_id, depth = PD$depth,
         best_grade = best$grade %||% "NA", best_port_t = best$port_t %||% NA_real_)
  } else {
    ws <- tryCatch(fromJSON(sp, simplifyVector = FALSE), error = function(e) NULL)
    cf <- if (!is.null(ws)) ws$factors else NULL
    if (is.null(cf) && !is.null(ws)) {
      cf <- list()
      if (!is.null(ws$factor2) && !identical(ws$factor2$kind, "none")) cf <- c(cf, list(ws$factor2))
      if (!is.null(ws$factor3)) cf <- c(cf, list(ws$factor3))
    }
    if (is.null(ws)) {
      jlog("promote_skipped", reason = "winner_spec_unreadable", spec = sp)
    } else {
      carry <- list(factors = cf %||% list(), weighting = ws$weighting, universe = ws$universe,
                    source_cell = best$cell_code %||% "NA", source_spec = sp)
      nid <- PD$new_base_id
      rf_open_entry(1L, nid, base_grade = best$grade,
                    paper_key = E2$paper_key %||% "", paper_id = E2$paper_id %||% "",
                    base_artifacts = if (is.na(best$artifacts)) (E2$base_artifacts %||% "") else best$artifacts,
                    engine_path = E2$engine_path %||% "",
                    carry = carry,
                    parent = list(base_id = E2$base_id, depth = depth,
                                  cell = best$cell_code %||% "NA", best_port_t = best$port_t,
                                  promoted_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
                    count_paper = FALSE, root = ROOT)
      jlog("promoted", base_id = nid, parent = E2$base_id, depth = depth,
           cell = best$cell_code %||% "NA", grade = best$grade, port_t = best$port_t,
           carry_factors = length(carry$factors))
      tryCatch({
        suppressMessages(source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R")))
        tg_agent_brief(agent = "AlphaSearch",
          lock_scope = sprintf("rf_promote_%s", nid),
          title = sprintf("[1계층·승격] %s 등급 구성 추가 강화 개시 (깊이 %d)", best$grade, depth),
          sections = list(
            list(type = "bullet", emoji = "\U0001F3AF", heading = "현재 리서치 상황",
                 items = c("단계: 1계층 강화 — B등급 이상 승격 레인",
                           sprintf("대상: %s (부모 %s)", nid, E2$base_id),
                           sprintf("승자 셀: %s · 다중검정 t값 %.3f", best$cell_code %||% "NA", best$port_t),
                           sprintf("물려받은 팩터 %d종 · 비중 %s · 유니버스 %s",
                                   length(carry$factors),
                                   (carry$weighting$kind %||% "ew"), (carry$universe$kind %||% "k200_kq150")))),
            list(type = "summary", emoji = "\U0001F4CC",
                 body = "20칸 소진 시 승자가 B등급 이상이라 그 구성을 기저로 물려 새 20칸을 엽니다. 다음 논문은 이 사슬이 끝난 뒤로 밀립니다."),
            list(type = "bullet", emoji = "\u27A1\uFE0F", heading = "다음",
                 items = c(sprintf("깊이 상한 %d — 부모 최고치를 못 넘으면 승격 중단", MAXD),
                           "처분: 자본 배정 없음 — 등재는 Judge(PIT) + 도훈 confirm"))))
      }, error = function(e) jlog("telegram_failed", err = conditionMessage(e)))
      return(invisible(0L))   # ★다음 논문으로 넘어가지 않는다 — 승격이 우선
    }
  }
}

# ── 2. 큐에서 다음 논문 (술어 정본 CLI — 재구현 금지) ────────────────────────
stage <- file.path(ROOT, "stage_artifacts/paper_recharge")
n_pending <- suppressWarnings(as.integer(system2(PY,
  c(shQuote(file.path(ROOT, "02_Infrastructure/ops/research_pool_predicates.py")),
    "alpha-pending", shQuote(stage)), stdout = TRUE, stderr = FALSE)[1]))
if (is.na(n_pending) || n_pending <= 0L) {
  jlog("halt_queue_empty", n_pending = n_pending %||% NA,
       note = "논문 큐가 비었다 — paper_recharge 수집이 채울 때까지 대기. 러너는 정지가 아니라 무동작.")
  return(invisible(0L))
}

# 큐 상단 1편 (재정렬 금지 — lean-loop 규약)
pick <- tryCatch(fromJSON(system2(PY, c(shQuote(file.path(ROOT, "02_Infrastructure/ops/rf_next_paper_pick.py")),
                                        shQuote(stage)), stdout = TRUE), simplifyVector = FALSE),
                 error = function(e) NULL)
if (is.null(pick) || is.null(pick$url) || !nzchar(pick$url)) {
  jlog("halt_pick_failed", n_pending = n_pending,
       note = "큐 상단 논문에서 원문 링크를 못 얻었다 — 근거 논문 없는 착수는 금지(v10)")
  return(invisible(0L))
}
jlog("paper_picked", title = substr(pick$title %||% "", 1, 100), url = pick$url, paper_key = pick$paper_key %||% "")

# ── ★결합 검토 (논문 3편마다 의무 — 2026-08-30 배선). 이월 시점이 논문 소비 지점이다.
#   구판은 원장이 "★결합 검토 도래" 를 stdout 에 출력하는 데서 끝났고 호출자가 0개였다
#   (소비자 없는 계기). 여기서 동기 호출한다 — 수 초짜리고 실패해도 이월을 막지 않는다.
tryCatch(system2("Rscript", shQuote(file.path(ROOT, "02_Infrastructure/ops/rf_combination_review.R")),
                 wait = TRUE, stdout = TRUE, stderr = TRUE),
         error = function(e) jlog("combination_review_failed", err = conditionMessage(e)))

# ── 3. 충실구현은 세션 소관으로 넘긴다 ────────────────────────────────────────
# ★경계: 충실구현은 "논문 그대로"(롱숏·종목수·비중·리밸)를 읽어 구현해야 하므로
#   규칙 격자로 환원되지 않는다 — 여기서 무인 LLM 개시를 하지 않는다.
#   대신 착수 요청을 큐에 남기고 텔레그램으로 도훈에게 알린다. 세션이 소비하면
#   rf_open_entry 가 열리고 그때부터 다시 무인 강화가 돈다.
REQ <- file.path(ROOT, "06_Registry/replication_request.json")
write(toJSON(list(requested_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                  source = "reinforce_auto_next_paper",
                  reason = "직전 논문 강화 20회 소진 — 큐 다음 논문 충실구현 대기",
                  prev = best, paper = pick, status = "pending"),
             auto_unbox = TRUE, pretty = TRUE, null = "null"), REQ)
jlog("replication_requested", path = REQ)

tryCatch({
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R")))
  tg_agent_brief(agent = "AlphaSearch",
    # ★lock_scope 를 논문별로 준다 — 기본 scope 는 "agent + 표제 40자"인데 이 표제가
    #   고정이라 서로 다른 논문의 이월이 30분 창 안에서 한 건으로 뭉갰다(2026-08-30 실측:
    #   2608.24703 이월이 차단됨). 중복 차단은 재발송을 막으라는 장치이지 **다른 사건을**
    #   막으라는 장치가 아니다.
    lock_scope = sprintf("rf_next_paper_%s", pick$paper_key %||% "unknown"),
    title = "[1계층] 강화 20회 소진 — 다음 논문 충실구현 대기",
    sections = list(
      list(type = "bullet", emoji = "\U0001F3AF", heading = "현재 리서치 상황",
           items = c("단계: 1계층 강화 프로세스 — 무인 러너",
                     sprintf("대상: %s 소진(20회)", best$base_id %||% "직전 논문"),
                     sprintf("위치: 논문 큐 대기 %d편 · 다음 1편 선정 완료", n_pending),
                     sprintf("직전 판정: 최고 등급 %s · 다중검정 t값 %.3f",
                             best$grade %||% "NA", best$port_t %||% NA_real_))),
      list(type = "summary", emoji = "\U0001F4CC",
           body = "강화 20회를 소진해 다음 논문으로 이월합니다. 충실구현 착수를 기다립니다."),
      # ★선정 논문 소개 (도훈 지시 2026-08-30) — 제목·출처·후보 팩터·트리아지 사유
      list(type = "bullet", emoji = "\U0001F4D6", heading = "선정 논문",
           items = {
             .it <- c(substr(sprintf("제목: %s", pick$paper_title %||% pick$title %||% "?"), 1, 78),
                      substr(sprintf("출처: %s · %s", toupper(pick$source %||% "?"), pick$url), 1, 78))
             if (nzchar(pick$factor_name %||% "")) .it <- c(.it,
               substr(sprintf("후보 팩터: %s", pick$factor_name), 1, 78))
             if (nzchar(pick$factor_def %||% "")) .it <- c(.it,
               substr(sprintf("정의: %s", pick$factor_def), 1, 78))
             if (nzchar(pick$reason %||% "")) .it <- c(.it,
               substr(sprintf("선정 사유: %s", pick$reason), 1, 78))
             utils::head(.it, 5)
           }),
      list(type = "bullet", emoji = "\U0001F6A9", heading = "주의",
           items = c("충실구현은 논문 원문을 읽어야 해서 무인 규칙으로 환원되지 않습니다",
                     "세션이 착수하면 그 다음부터 강화는 다시 무인으로 돕니다")),
      list(type = "bullet", emoji = "\u27A1\uFE0F", heading = "다음",
           items = c("처분: 자본 배정 없음 — 소진은 상한 도달이지 실패 판정이 아닙니다",
                     sprintf("대기 파일: %s", "06_Registry/replication_request.json")))))
}, error = function(e) jlog("telegram_failed", err = conditionMessage(e)))
invisible(0L)
}

rc <- tryCatch(main(), error = function(e) { jlog("fatal", err = conditionMessage(e)); 1L })
quit(status = if (is.numeric(rc)) as.integer(rc) else 0L)
