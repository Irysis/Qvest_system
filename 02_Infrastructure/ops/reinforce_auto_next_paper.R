#!/usr/bin/env Rscript
#==============================================================================
# reinforce_auto_next_paper.R — 25칸 소진 후 **다음 논문으로 이월** (무인화, 2026-08-30)
#
# 도훈 지시: "강화프로세스 20회 진행 후에도 개선이 없으면 다른 논문으로 옮겨가게 해줘".
#
# 호출자 = reinforce_auto_run.R (entry status=exhausted 직후, 비동기)
# 하는 일:
#   1) 소진된 entry 의 최고 셀이 기저 대비 개선을 냈는지 판정해 로그·텔레그램에 남긴다
#      (개선 유무와 무관하게 이월한다 — 상한은 25회다(원장 max_attempts). 개선이 있었다면 그 사실이 기록된다)
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
# ★칸 상한은 원장이 정본이다 — 메시지에 숫자를 박으면 상한을 바꿔도 안 따라온다
#   (2026-08-31 도훈 지적: 상한이 25 인데 텔레그램이 계속 "20칸" 이라고 말했다).
MAXA <- as.integer(led$max_attempts %||% 25L)   # 전역 기본값 — 아래에서 소진 entry 값으로 덮는다

# 이미 active 가 있으면 이월할 필요 없음 (중복 개설 방지)
if (length(Filter(function(e) identical(e$status, "active"), led$entries))) {
  jlog("halt_active_exists"); return(invisible(0L))
}

# ── 1. 소진 entry 의 성적 요약 (개선 유무 판정 — 이월은 무조건) ──────────────
# ★이미 이월을 끝낸 entry 는 다시 요약하지 않는다. 구판은 exhausted 목록의 마지막을
#   매 tick 다시 집어 exhausted_summary/promote 판정을 반복했고, 그때마다 "N회 소진"
#   텔레그램이 나갔다(2026-08-31: 27076 한 건에 대해 4회 반복 — 도훈이 "텔레가 섞여서
#   온다" 고 지적한 소음의 절반이 이것이다).
ex <- Filter(function(e) identical(e$status, "exhausted") && !isTRUE(e$handed_off), led$entries)
best <- NULL
.already <- FALSE
if (length(ex)) {
  E <- ex[[length(ex)]]
  # ★예산은 **entry 별**이다 (2026-09-04 도훈 지적: 텔레그램이 계속 "25회" 라고 말했다).
  #   B1 설계가 격자 5칸을 k칸으로 늘리면 그 entry 예산은 25+(k-5) 가 된다 — 오늘 실제로
  #   34였다. 전역 max_attempts 를 읽으면 **실제로 태운 횟수와 다른 숫자**를 보고하게 된다.
  #   구판이 "20 vs 25" 로 틀렸던 것과 같은 병이고, 이번엔 분모가 entry 마다 다르다.
  MAXA <- as.integer(E$max_attempts %||% led$max_attempts %||% 25L)
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
  .already <- rf_is_summarized(E)
  if (!.already) {
    jlog("exhausted_summary", base_id = E$base_id, attempts = length(E$attempts),
         best_port_t = best$port_t %||% NA, best_grade = best$grade %||% "NA",
         improved = isTRUE(!identical(best$grade %||% "F", E$base_grade %||% "F")))
    tryCatch(rf_mark_summarized(1L, E$base_id, ROOT),
             error = function(e) jlog("summarized_mark_failed", err = conditionMessage(e)))
  }
}

# ── ★1.5 B등급 이상 승격 분기 (도훈 지시 2026-08-30) ─────────────────────────
#   구판의 유일한 배선은 "20칸 소진 → 다음 논문" 하나였다. 그러면 B 를 낸 구성이
#   더 파보지도 못하고 큐 뒤로 밀린다 — 25칸은 상한이지 그 신호의 한계가 아니다.
#   그래서 소진 시점에 승자가 B+ 면 그 구성을 carry 로 물려 **새 25칸**을 연다.
#   ★승격은 자기 값을 증명해야 이어진다 — 부모 최고 PORT_t 를 넘지 못하면 승격하지 않는다.
#     (넘지 못한 승격은 같은 실패의 재생산이고, 그게 25회 상한의 존재 이유다)
#   ★깊이 상한은 큐 정체 방지 — 한 논문이 승격 사슬로 무한히 예산을 먹지 않게 한다.
# ★판정은 rf_promote.R 의 순수 함수 하나 — 인라인으로 두면 검사가 못 건드린다.
if (length(ex)) {
  E2 <- ex[[length(ex)]]
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_promote.R")))
  PD    <- rf_promote_decide(E2, best, CFG)
  MAXD  <- as.integer(CFG$promote_max_depth %||% 3L)
  depth <- PD$depth
  sp    <- best$spec %||% NA_character_

  if (!isTRUE(PD$ok) && isTRUE(.already)) {
    # 이미 한 번 판정한 entry — 이월만 다시 시도한다(아래 합류). 로그는 반복하지 않는다.
  } else if (!isTRUE(PD$ok)) {
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
      ## ★overlay 도 실는다 (2026-09-04): 소비자(러너 carry 병합)는 E$carry$overlay 를 읽는데 생산자가 안 실었다 —
      ##   승자가 B5/B4 칸이면 위험 통제가 세대마다 리셋된다(승계 목록에서 빠진 축은 없는 축이 된다).
      carry <- list(factors = cf %||% list(), weighting = ws$weighting, universe = ws$universe,
                    overlay = ws$overlay,
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
      ## ★승격 안내 대신 **라운드 종료 리뷰** 를 보낸다 (도훈 지시 2026-09-04).
      ##   종료 시점에 두 통이 나갔고(마지막 블록 리뷰 + 승격 쪽지) 어느 쪽도
      ##   35칸 전체의 결론이 아니었다. 라운드를 닫는 메시지가 라운드를 요약해야 한다.
      ##   승격 정보는 그 리뷰의 마지막 절로 들어간다 — 두 통을 한 통으로 합치는 것이다.
      tryCatch({
        suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_round_review.R")))
        rf_round_review(E2, promo = list(base_id = nid, depth = depth,
                          cell = best$cell_code %||% "NA", grade = best$grade,
                          port_t = best$port_t), root = ROOT)
      }, error = function(e) jlog("round_review_failed", err = conditionMessage(e)))
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

# ── ★결합 **착수** (2026-08-31 도훈 지시 "착수해주고") ───────────────────────
#   검토기는 후보만 쌓았고 소비자가 없었다(4회 · 10쌍이 그대로 남아 있었다).
#   여기서 착수기를 부른다. 자체 가드가 다 들어 있어 조건이 안 맞으면 즉시 물러난다:
#     · active entry 존재 → halt   · 새 쌍 없음 → halt   · 양수 t 쌍 없음 → halt
#   ★결합이 열리면 **이월을 하지 않는다**. 결합 entry 가 곧 active 라, 이월까지 하면
#     충실구현이 돌아도 그 결과로 entry 를 못 연다(active 중복). 둘 중 하나만 간다.
.combo_opened <- FALSE
tryCatch({
  .out <- system2("Rscript", shQuote(file.path(ROOT, "02_Infrastructure/ops/rf_combination_launch.R")),
                  wait = TRUE, stdout = TRUE, stderr = TRUE)
  # ★2026-09-04: 결합은 entry 를 여는 대신 **설계 요청**을 발행한다.
  #   그 요청도 "처리됨" 이다 — 아래 이월이 같은 파일을 다음 논문으로 덮어쓰면
  #   결합 설계가 발행 즉시 사라진다(생산자만 있고 소비자가 없던 구판 결함의 변종).
  .combo_opened <- any(grepl("combo_entry_opened", .out, fixed = TRUE)) ||
                   any(grepl("combination_design_requested", .out, fixed = TRUE))
  jlog("combination_launch", opened = .combo_opened,
       note = if (.combo_opened) "결합 처리(entry 개설 또는 설계 요청) — 이월 생략" else "조건 미충족 — 이월 진행")
}, error = function(e) jlog("combination_launch_failed", err = conditionMessage(e)))
if (isTRUE(.combo_opened)) return(invisible(0L))

# ── 3. 충실구현은 세션 소관으로 넘긴다 ────────────────────────────────────────
# ★경계: 충실구현은 "논문 그대로"(롱숏·종목수·비중·리밸)를 읽어 구현해야 하므로
#   규칙 격자로 환원되지 않는다 — 여기서 무인 LLM 개시를 하지 않는다.
#   대신 착수 요청을 큐에 남기고 텔레그램으로 도훈에게 알린다. 세션이 소비하면
#   rf_open_entry 가 열리고 그때부터 다시 무인 강화가 돈다.
REQ <- file.path(ROOT, "06_Registry/replication_request.json")
write(toJSON(list(requested_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                  source = "reinforce_auto_next_paper",
                  reason = sprintf("직전 논문 강화 %d회 소진 — 큐 다음 논문 충실구현 대기", MAXA),
                  prev = best, paper = pick, status = "pending"),
             auto_unbox = TRUE, pretty = TRUE, null = "null"), REQ)
jlog("replication_requested", path = REQ)
  # 이월 완료 표식 — 이 entry 는 다음 tick 부터 요약 대상이 아니다
  if (!is.null(best$base_id)) tryCatch({
    .o <- rf_load(1L, ROOT)
    .k <- which(vapply(.o$entries, function(z) identical(z$base_id, best$base_id), logical(1)))
    if (length(.k)) { .o$entries[[.k[1]]]$handed_off <- TRUE
      .o$entries[[.k[1]]]$handed_off_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
      .txt <- toJSON(.o, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6)
      if (!is.null(fromJSON(.txt, simplifyVector = FALSE)$entries))
        writeLines(.txt, file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"), useBytes = TRUE)
      jlog("handed_off", base_id = best$base_id) }
  }, error = function(e) jlog("handoff_mark_failed", err = conditionMessage(e)))

tryCatch({
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R")))
  tg_agent_brief(agent = "AlphaSearch", relaxed = TRUE, glossary = FALSE, decode_jargon = FALSE, decode_mode = "off",
    # ★lock_scope 를 논문별로 준다 — 기본 scope 는 "agent + 표제 40자"인데 이 표제가
    #   고정이라 서로 다른 논문의 이월이 30분 창 안에서 한 건으로 뭉갰다(2026-08-30 실측:
    #   2608.24703 이월이 차단됨). 중복 차단은 재발송을 막으라는 장치이지 **다른 사건을**
    #   막으라는 장치가 아니다.
    lock_scope = sprintf("rf_next_paper_%s", pick$paper_key %||% "unknown"),
    title = sprintf("[1계층] 강화 %d회 소진 — 다음 논문 충실구현 대기", MAXA),
    sections = list(
      list(type = "bullet", emoji = "\U0001F3AF", heading = "현재 리서치 상황",
           items = c("단계: 1계층 강화 프로세스 — 무인 러너",
                     sprintf("대상: %s 소진(%d회)", best$base_id %||% "직전 논문", MAXA),
                     sprintf("위치: 논문 큐 대기 %d편 · 다음 1편 선정 완료", n_pending),
                     sprintf("직전 판정: 최고 등급 %s · 다중검정 t값 %.3f",
                             best$grade %||% "NA", best$port_t %||% NA_real_))),
      list(type = "summary", emoji = "\U0001F4CC",
           body = sprintf("강화 %d회를 소진해 다음 논문으로 이월합니다. 충실구현 착수를 기다립니다.", MAXA)),
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
