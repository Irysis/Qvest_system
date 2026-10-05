#!/usr/bin/env Rscript
#==============================================================================
# reinforce_auto_parallel.R — 강화 무인 러너 **병렬 배치** (도훈 지시 2026-08-30 "병렬로 실행")
#
# 왜 별도 파일인가 (reinforce_auto_run.R 과의 관계):
#   순차 러너는 claim mutex 로 **한 번에 한 칸**을 강제한다. 그 상태로 동시에 띄우면
#   다음 칸이 `attempts_used + 1` 이라 **넷 다 같은 칸**을 잡는다.
#   그래서 병렬은 구조를 바꾼다 — **원장 쓰기를 실행에서 떼어낸다**:
#     ① 사전 등록  : 순차 (rf_append_attempt — 원장 단독 접근)
#     ② 실행       : 병렬 (rf_cell_worker.R — 원장 미접근, 결과를 자기 JSON 에만 기록)
#     ③ 결과 수집  : 순차 (rf_record_result)
#   read-modify-write 경합이 원천적으로 없다.
#
# ★같은 블록 안에서만 병렬화한다. 블록 경계를 넘으면 안 되는 이유:
#   B2/B3 는 B1 승자 위에 서고 B4 는 B1~B3 승자 위에 선다. 승자가 확정되기 전에
#   다음 블록을 띄우면 **결정되지 않은 값 위에서 측정**하게 된다(공허한 시도).
#   이 규칙이 없으면 2026-08-30 의 "공허한 LOO" 사고가 병렬로 4배가 된다.
#
# 사용: Rscript reinforce_auto_parallel.R        (설정의 parallel_cells 만큼)
# 하드 가드는 순차 러너와 동일 — kill switch · claim · daily_cap · 자본 경계.
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT); Sys.setenv(QM_ROOT = ROOT, CLAUDE_PROJECT_DIR = ROOT)
# ★검사가 격리 사본을 쓸 수 있게 — 공유 설정을 검사가 직접 만지면 그 창에 tick 이 끼어든다
CFG_P  <- { .c <- Sys.getenv("QVEST_RF_CONFIG", "")
            if (nzchar(.c) && file.exists(.c)) .c
            else file.path(ROOT, "06_Registry/reinforce_auto_config.json") }
PROG_P <- file.path(ROOT, "06_Registry/reinforce_program.json")
LOG_P  <- file.path(ROOT, ".cache/reinforce_auto_log.jsonl")
# ★검사가 격리 사본을 쓸 수 있게 — 공유 claim 을 검사가 지우면 그 창에 tick 이 끼어들어
#   살아있는 배치 옆에 둘째 배치가 뜼다(원장 경합). 설정 격리(QVEST_RF_CONFIG)와 같은 형태.
CLAIM  <- { .cl <- Sys.getenv("QVEST_RF_CLAIM", "")
           if (nzchar(.cl)) .cl else file.path(ROOT, ".cache/reinforce_auto.claim") }
WDIR   <- file.path(ROOT, ".cache/rf_parallel")
dir.create(dirname(LOG_P), recursive = TRUE, showWarnings = FALSE)
dir.create(WDIR, recursive = TRUE, showWarnings = FALSE)

jlog <- function(event, ...) {
  rec <- c(list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), event = event, src = "parallel"), list(...))
  cat(toJSON(rec, auto_unbox = TRUE, null = "null"), "\n", sep = "", file = LOG_P, append = TRUE)
  cat(sprintf("[rf_par] %s %s\n", event,
              paste(names(rec)[-(1:3)], unlist(lapply(rec[-(1:3)], function(z) substr(paste(z, collapse=","), 1, 80))),
                    sep = "=", collapse = " ")))
}

# ★등록 거부 누적 횟수 (entry·셀 코드 단위). 커서가 코드 기반이 된 뒤로 거부된 칸은
#   다음 tick 에 그대로 다시 잡힌다 — 회복은 되지만 **결정론적 거부에는 출구가 없다**
#   (2026-08-31 B3_11 16회 제자리 사고와 같은 형태). 그래서 상한을 두고 멈춰 세운다.
.append_fail_count <- function(code, bid) {
  if (!file.exists(LOG_P)) return(0L)
  tryCatch(sum(vapply(readLines(LOG_P, warn = FALSE), function(l) {
    if (!grepl('"append_failed"', l, fixed = TRUE)) return(FALSE)
    r <- tryCatch(fromJSON(l, simplifyVector = TRUE), error = function(e) NULL)
    !is.null(r) && identical(as.character(r$code %||% ""), code) &&
      identical(as.character(r$base_id %||% ""), bid)
  }, logical(1))), error = function(e) 0L)
}

CFG <- if (file.exists(CFG_P)) fromJSON(CFG_P, simplifyVector = FALSE) else list()
if (!isTRUE(CFG$enabled %||% FALSE)) { jlog("halt_disabled"); quit(status = 0) }
NPAR      <- as.integer(CFG$parallel_cells %||% 4L)
DAILY_CAP <- as.integer(CFG$daily_cap %||% 8L)
STALE_H   <- as.numeric(CFG$claim_stale_hours %||% 6)
# ★한 칸의 재시도 상한. 재개는 일시적 실패를 살리는 장치지 무한 재시도가 아니다.
MAX_RETRY <- as.integer(CFG$cell_max_retry %||% 2L)

done_today <- 0L
if (file.exists(LOG_P)) {
  today <- format(Sys.Date(), "%Y-%m-%d")
  done_today <- tryCatch(sum(vapply(readLines(LOG_P, warn = FALSE), function(l) {
    o <- tryCatch(fromJSON(l, simplifyVector = TRUE), error = function(e) NULL)
    isTRUE(!is.null(o) && identical(o$event, "cell_done") && startsWith(o$ts %||% "", today))
  }, logical(1))), error = function(e) 0L)
}
if (done_today >= DAILY_CAP) { jlog("halt_daily_cap", done = done_today, cap = DAILY_CAP); quit(status = 0) }

# ★리프레시 배리어 — 러너 수준 (도훈 결정 OPS-RUNNER-REFRESH-BARRIER · 2026-09-24).
#   틱 앞 레인(충실구현 검증·설계 LLM)이 오래 도는 사이 daily_refresh 가 잠금을 잡을 수 있다([0b] 퀀티 증분 ~ [3/7]
#   유니버스 매핑 사이 RAWDATA K200/KQ150 NA 창). claim·사전 등록(rf_append_attempt) **전**에 다시 본다 — held 면
#   시도 예산을 안 태우고 물러난다(다음 tick 재시도). 판정 정본 = refresh_barrier.sh(R 은 부르고 파싱만 — "/tmp" 층 차이·
#   MSYS pid 때문). stale = 대기 안 함 + 로그 · error(판정기 불능) = fail-closed · 잠금 없음 = 아무것도 안 한다.
.rb_run <- tryCatch({
  .rb_src <- file.path(ROOT, "02_Infrastructure/ops/refresh_barrier.R")
  if (!file.exists(.rb_src)) .rb_src <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/ops/refresh_barrier.R"
  .RBX <- new.env(); sys.source(.rb_src, envir = .RBX, keep.source = FALSE)
  .RBX$rb_status(ROOT)
}, error = function(e) list(state = "error", reason = conditionMessage(e), blocking = TRUE))
.rb_kv <- list(state = .rb_run$state %||% "", lock = .rb_run$lock %||% "", pid = .rb_run$pid %||% "",
               reason = .rb_run$reason %||% "", path = .rb_run$path %||% "")
if (isTRUE(.rb_run$blocking)) { do.call(jlog, c(list("halt_refresh_lock"), .rb_kv)); quit(status = 0) }
if (identical(.rb_run$state, "stale"))
  do.call(jlog, c(list("refresh_lock_stale"), .rb_kv, list(note = "보유자 없음 — 대기하지 않고 진행")))

# ★claim 획득·해제는 rf_claim.R 하나. 2026-08-30 실사고 2회 — 배치 종료 후 unlink 이 조용히
#   실패해 빈 claim 이 남았고, 그러면 stale_hours(6h) 가 찰 때까지 전 tick 이 halt_claimed 로
#   물러난다. 그 로그는 **정상 대기와 글자 그대로 같아서** 아무도 못 본다(부팅 때 본 1.5h 공백).
#   그래서 owner.json(pid) 을 남기고, 다음 실행이 그 pid 사망을 보면 나이 무관 즉시 회수한다.
suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_claim.R")))
# ★위임 호출에서는 부모가 이미 claim 을 쥐고 있다 — 자식이 다시 잡으려 하면 자기 부모에게 막혀
#   아무 일도 못 하고 끝난다(2026-08-30 실사고: halt_exhausted_delegate → halt_claimed 가 8분마다
#   2시간 반 동안 반복, 소진 전이가 영영 안 됐다). 부모가 이 플래그로 "이미 잡았다" 를 알린다.
.CLAIM_HELD <- nzchar(Sys.getenv("QVEST_RF_CLAIM_HELD", ""))
.ac <- if (.CLAIM_HELD) list(ok = TRUE, reason = "inherited", age_h = NA_real_,
                            owner_pid = NA_integer_, note = "") else
       rf_claim_acquire(CLAIM, stale_hours = STALE_H)
if (!isTRUE(.ac$ok)) {
  if (identical(.ac$reason, "race")) jlog("halt_claim_race")
  else jlog("halt_claimed", age_h = round(.ac$age_h %||% NA_real_, 2), owner_pid = .ac$owner_pid %||% NA)
  quit(status = 0)
}
if (nzchar(.ac$note %||% "")) jlog("claim_stale_reclaim", note = .ac$note)

main <- function() {
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R")))
# ── 처치 전달 판정 헬퍼 — ★정본은 rf_spec_sig.R (2026-09-03 추출)
#   .fkeys 가 이 파일과 reinforce_auto_run.R 에 중복 정의돼 있었고, 커버리지 색인이
#   세 번째 복제본을 만들 참이었다. 서명이 갈리면 "같은 포트폴리오" 판정이 소비자마다 달라진다.
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R"), local = TRUE))
# ★기전 회피 표적 판정 — 정본은 rf_avoid.R (2026-09-05 추출 · 실사고 사연은 그 파일 머리)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_avoid.R"), local = TRUE))
PROG <- fromJSON(PROG_P, simplifyVector = FALSE)
led <- rf_load(1L, ROOT)
## ── ★레인 순서 (결정 D-G 2026-09-23 · 플랜 P1-08 · 2026-09-25 · 판정 정본 rf_lane_rules.R) ─────────────────────────────────
##   구판은 원장 순서 첫 active(act[[1]])를 돌렸다 — 반사실(파킹분 기저 관문 측정) active 1건이 신규 논문 요청을 16시간 막았다(감사 D8-02).
##   이제: prereg > 신규 논문 > 승격 > 반사실(순서·우선순위 어휘 = config lanes) · 사전등록 실험 entry(experiment)는 격자로 돌리지 않는다
##   (칸은 사전등록이 정한다 — 전용 실행기 별판 · 현재 live 경로 없음). lanes 설정이 깨졌으면 구판 거동 그대로(로그).
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_lane_rules.R"), local = TRUE))
.LANE <- rf_lane_cfg(CFG)
if (!isTRUE(.LANE$ok)) jlog("lane_cfg_unavailable", why = .LANE$why %||% "", note = "lanes 설정 판독 불가 — 구판 거동(원장 순서 첫 active · 전부 차단)")
.REQ_P <- file.path(ROOT, "06_Registry/replication_request.json")
.req_now <- function() if (file.exists(.REQ_P)) tryCatch(fromJSON(.REQ_P, simplifyVector = FALSE), error = function(e) NULL) else NULL
.sel <- rf_lane_select(led$entries, .LANE)
if (length(.sel$excluded_experiment))
  jlog("experiment_entries_excluded", ids = paste(.sel$excluded_experiment, collapse = ","),
       note = "사전등록 실험 entry 는 격자 러너가 돌리지 않는다(전용 실행기 별판) — 개설도 막지 않는다")
## ★반사실(비차단 우선순위)만 active 면 먼저 next_paper 에 위임한다 — 승격 자식·신규 논문 요청이 반사실에 막히지 않게.
##   next_paper 는 러너 claim 을 상속받아(QVEST_RF_CLAIM_HELD) 원장을 쓴다. 돌아오면 원장을 다시 읽고 다시 고른다.
if (length(.sel$entries) && !length(rf_blocking_active(led$entries, .LANE))) {
  jlog("lane_delegate_nonblocking", n_active = length(.sel$entries), top = as.character(.sel$entries[[1]]$base_id %||% ""),
       note = "active 가 전부 비차단(반사실) — next_paper 선위임(승격·신규 논문이 먼저)")
  Sys.setenv(QVEST_RF_CLAIM_HELD = "1")
  on.exit(Sys.unsetenv("QVEST_RF_CLAIM_HELD"), add = TRUE)
  system2("Rscript", shQuote(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_next_paper.R")), wait = TRUE)
  Sys.unsetenv("QVEST_RF_CLAIM_HELD")
  led <- rf_load(1L, ROOT); .sel <- rf_lane_select(led$entries, .LANE)
}
act <- .sel$entries
if (length(act) > 1L)
  jlog("lane_selected", base_id = as.character(act[[1]]$base_id %||% ""), lane = as.character(.sel$lanes[1] %||% NA),
       n_active = length(act), order = paste(sprintf("%s:%s", vapply(act, function(e) as.character(e$base_id %||% ""), character(1)),
                                                     as.character(.sel$lanes)), collapse = ","))
if (!length(act)) {
  ## ★active 가 없으면 **다음 논문을 연다** (2026-09-05 실사고). 구판은 여기서 멈췄다 — 새 요청의 유일한 생산자
  ##   (reinforce_auto_next_paper.R)를 부르는 자리가 소진 위임뿐이라, entry 를 park 로 닫으면(소진 아님)
  ##   아무도 큐 상단을 열지 않고 8분마다 halt_no_active_entry + no_pending_request 만 반복됐다.
  ##   next_paper 는 자기 가드(enabled · active_exists · queue_empty)를 갖고 있어 중복 개설이 없다.
  jlog("halt_no_active_entry", note = "next_paper 에 위임 — 큐 상단 논문 개설 시도")
  Sys.setenv(QVEST_RF_CLAIM_HELD = "1")
  on.exit(Sys.unsetenv("QVEST_RF_CLAIM_HELD"), add = TRUE)
  system2("Rscript", shQuote(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_next_paper.R")), wait = TRUE)
  Sys.unsetenv("QVEST_RF_CLAIM_HELD"); return(0L)
}
E <- act[[1]]; BID <- E$base_id
## ★반사실 양보 — 충실구현 요청이 진행 중(lanes.request_inflight_statuses)이면 비차단 entry 는 이 tick 에 원장을 쓰지 않는다.
##   충실구현 레인(rf_replication_auto.sh)은 비차단 active 를 세지 않고 돈다 — 그 레인의 원장 개설(rf_replication_verify.R)과
##   러너 쓰기가 겹치지 않게 하는 쪽이 여기다. 요청 발행은 next_paper 가 러너 claim 아래서만 한다(배치가 떠 있는 동안 발행 없음).
if (isTRUE(.LANE$ok) && rf_entry_priority(E) %in% .LANE$nonblocking && isTRUE(rf_request_inflight(.req_now(), .LANE))) {
  jlog("yield_nonblocking_to_replication", base_id = BID, request_status = as.character((.req_now() %||% list())$status %||% ""),
       note = "반사실 entry 양보 — 신규 논문 충실구현이 진행 중(원장 동시 쓰기 차단 · 레인 순서 신규 논문 > 반사실)")
  return(0L)
}
## ── ★측정 규약·후보 자격 문맥 (P0-10·11·12 · 규약 혼합 가드 · 2026-09-24 도훈 승인 플랜 qvest-1-drifting-eclipse) ──────────
##   현행 규약 = constraint_defaults.json::execution.exec_price(결정 EXEC-PRICE) — 바닥·carry 기준선·블록 승자·A 는 이 규약의 칸만
##   소비한다(과도기 = config close_t1 → 신규 칸 close_t1 → 과거 칸 rebase(P0-06) → current_axis 교체. rebase 전에는 legacy 칸이
##   전부 빠져 진행 중 entry 는 halt_no_b1_winner 로 멈춘다 = 혼합 대신 정지 · 로그 candidates_excluded). 판정 정본 = rf_runner_gates.R.
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_runner_gates.R"), local = TRUE))
.RCTX <- rf_runner_ctx(ROOT)
if (is.na(.RCTX$regime))
  jlog("regime_current_unknown", why = .RCTX$regime_why, source = .RCTX$regime_source,
       note = "현행 측정 규약 판독 불가 — 후보 전부 regime 미판정(fail-closed) · A 발행 보류")
## >>> O0a 시행 로그(P1-02 · 2026-09-25 · 설계 organic_design_final §3 G1) — 생산자 7곳 중 러너 5곳(블록 승자·바닥·b1/b2/b5 pick) + 칸 설계 출처.
##   판정 불변 — 기록만 더한다(.TLW 는 .winner_of·바닥 절이 남기는 단계별 후보 메모 · 기록 실패 = jlog trial_log_failed · 러너는 계속).
tryCatch(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_trial_producers.R"), local = TRUE)),
         error = function(e) jlog("trial_log_load_failed", err = conditionMessage(e),
                                  note = "시행 로그 생산자 적재 실패 — 러너는 계속(기록 호출은 전부 trial_log_failed 로 남는다 · 판정 불변)"))
.TLW <- new.env(parent = emptyenv())
.tlw_note <- function(key, stage, cand, v = NULL, by = NULL) tryCatch({
  cd <- vapply(cand, function(a) { x <- .rf_attempt_code(a, cells); if (is.na(x)) "" else x }, character(1))
  cur <- if (exists(key, envir = .TLW, inherits = FALSE)) get(key, envir = .TLW) else list()
  if (identical(stage, "win")) { cur$chosen <- cd[1]; cur$vals <- as.numeric(v); cur$vcodes <- cur$c2 %||% character(0); cur$by <- by }
  else cur[[stage]] <- cd
  assign(key, cur, envir = .TLW); invisible(NULL) }, error = function(e) invisible(NULL))
.tl_try <- function(what, expr) tryCatch({ force(expr); TRUE },
  error = function(e) { jlog("trial_log_failed", what = what, err = conditionMessage(e)); FALSE })
## <<< O0a
.now_ts <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

## ── ★Grade A 발행·보류 1벌 (P0-12 A 자격 관문 · 2026-09-24) ────────────────────────────────────────────────────
##   발행 = qepm/mailbox/judge_request_<BID>_<n>.json(★후보별 — 구판 단일 judge_request.json 은 A 가 둘이면 앞 후보를 덮어 지웠다) +
##          grade_a_queue status=awaiting_judge + 팡파레·텔레그램 (+ 해제 경로면 entry 졸업).
##   보류 = grade_a_queue status='held:<코드+코드>'(같은 칸은 갱신 — 줄이 늘지 않는다) + 산출물의 judge_request.json(충실구현 러너가
##          A 면 무조건 쓴다 — 관문 우회 경로) → judge_request.held.json 으로 치움 + entry active 유지(rf_record_result(graduate=FALSE)).
##   판정 = rf_runner_gates.R::rf_a_eligibility(순수) · 결정 기록 = rf_record_decision(kind = "a_eligibility") · 보류 코드 on/off =
##   06_Registry/a_eligibility_gate.json. 발행 경로는 셋(수집 · B5 경계 적대검증 해제 · tick 시작 재평가)이고 전부 이 함수들을 쓴다.
.GAQ_P <- file.path(ROOT, "06_Registry/grade_a_queue.json")
.gaq_load <- function() {
  if (!file.exists(.GAQ_P)) return(list(schema = "grade_a_queue_v1",
    note = "essence Grade A 후보 대기열. Judge(PIT) 검증 + 도훈 confirm 후 BOOK 등재. 러너는 여기 쌓기만 하고 멈추지 않는다. status = awaiting_judge | held:<A 자격 관문 보류 코드>(P0-12).",
    entries = list()))
  q <- tryCatch(fromJSON(.GAQ_P, simplifyVector = FALSE), error = function(e) NULL)
  # ★파손 큐를 빈 큐로 덮지 않는다(구판은 덮었다 — 대기 중인 A 기록이 소실된다). 멈추고 호출자가 로그로 남긴다.
  if (is.null(q)) stop("grade_a_queue.json 파싱 실패 — 덮어쓰지 않는다(수동 확인)")
  if (is.null(q$entries)) q$entries <- list()
  q
}
.gaq_write <- function(q) {
  tmp <- paste0(.GAQ_P, ".tmp_", Sys.getpid())
  write(toJSON(q, auto_unbox = TRUE, pretty = TRUE, null = "null"), tmp)
  if (!isTRUE(file.rename(tmp, .GAQ_P))) { file.copy(tmp, .GAQ_P, overwrite = TRUE); unlink(tmp) }
}
.gaq_idx <- function(q, n) which(vapply(q$entries, function(x) identical(as.character(x$base_id %||% ""), BID) &&
  identical(suppressWarnings(as.integer(x$attempt %||% NA)), as.integer(n)), logical(1)))
.gaq_status <- function(n) {
  q <- tryCatch(.gaq_load(), error = function(e) NULL); if (is.null(q)) return("")
  k <- .gaq_idx(q, n); if (length(k)) as.character(q$entries[[k[1]]]$status %||% "") else ""
}
.gaq_upsert <- function(n, code, artifacts, fields) {
  q <- .gaq_load(); k <- .gaq_idx(q, n)
  rec <- if (length(k)) q$entries[[k[1]]] else list(queued_at = .now_ts(), base_id = BID, attempt = as.integer(n),
                                                    cell = code, artifacts = artifacts, grade = "A")
  for (nm in names(fields)) rec[[nm]] <- fields[[nm]]
  rec$updated_at <- .now_ts()
  if (length(k)) q$entries[[k[1]]] <- rec else q$entries[[length(q$entries) + 1L]] <- rec
  .gaq_write(q); invisible(rec)
}
## 산출물 디렉터리의 judge_request.json — run_paper_replication.R §11 이 A 면 관문과 무관하게 쓴다. 보류 중에는 치우고(held) 발행 때 되돌린다.
.a_art_request <- function(artifacts, action, codes = character(0)) tryCatch({
  d <- .rfg_art_dir(artifacts, ROOT)
  if (!is.na(d)) {
    live <- file.path(d, "judge_request.json"); held <- file.path(d, "judge_request.held.json")
    if (identical(action, "park") && file.exists(live)) {
      j <- tryCatch(fromJSON(live, simplifyVector = FALSE), error = function(e) list())
      j$held <- list(codes = as.list(codes), at = .now_ts(), by = "reinforce_auto_parallel · A 자격 관문(P0-12)")
      write(toJSON(j, auto_unbox = TRUE, pretty = TRUE, null = "null"), held)
      if (file.exists(held)) unlink(live)
      jlog("judge_request_parked", artifacts = d, codes = paste(codes, collapse = "+"),
           note = "충실구현 러너가 쓴 산출물 요청을 보류 표식으로 치웠다(관문 우회 차단)")
    } else if (identical(action, "restore") && !file.exists(live) && file.exists(held)) {
      j <- tryCatch(fromJSON(held, simplifyVector = FALSE), error = function(e) list())
      j$held <- NULL; j$released_at <- .now_ts()
      write(toJSON(j, auto_unbox = TRUE, pretty = TRUE, null = "null"), live)
      if (file.exists(live)) unlink(held)
    }
  }
  invisible(NULL)
}, error = function(e) jlog("judge_request_park_failed", action = action, err = conditionMessage(e)))
.grade_a_enqueue <- function(n, code, artifacts, essence, elig = NULL) {
  # ★중복 발행 금지 — 해제 경로가 둘(B5 경계 · tick 시작)이라 같은 칸이 이미 awaiting_judge 면 다시 쓰지 않는다
  if (identical(.gaq_status(n), "awaiting_judge")) {
    jlog("grade_a_already_queued", n = n, code = code); return(invisible(FALSE)) }
  .jdir <- file.path(ROOT, "qepm/mailbox"); dir.create(.jdir, recursive = TRUE, showWarnings = FALSE)
  jr <- file.path(.jdir, sprintf("judge_request_%s_%d.json", gsub("[^A-Za-z0-9_.-]", "_", BID), as.integer(n)))
  .req <- list(schema = "judge_request_v2", status = "pending", requested_at = .now_ts(), source = "reinforce_auto_parallel",
               strategy_id = sprintf("%s:%s", BID, code), layer = 1L, grade = "A",
               base_id = BID, attempt = as.integer(n), cell = code, artifacts = artifacts,
               engine_path = file.path(ROOT, "02_Infrastructure/reinforcement/rf_cell_engine.R"),
               base_engine_path = E$engine_path %||% "", spec = (essence %||% list())$spec %||% "",
               a_eligibility = list(eligible = TRUE, checked_at = (elig %||% list())$evaluated_at %||% .now_ts(),
                                    regime = (elig %||% list())$regime_current %||% .RCTX$regime,
                                    inactive = as.list((elig %||% list())$inactive %||% character(0)),
                                    gate = (elig %||% list())$gate_source %||% ""),
               note = "v10: Grade A → Judge(PIT 전담) 스폰 요청 — 세션(Q-Lead)이 Agent 스폰. A 자격 관문(P0-12) 통과분만 발행된다.")
  .tmp <- paste0(jr, ".tmp")
  write(toJSON(.req, auto_unbox = TRUE, pretty = TRUE, null = "null"), .tmp)
  if (!isTRUE(file.rename(.tmp, jr))) { file.copy(.tmp, jr, overwrite = TRUE); unlink(.tmp) }
  .a_art_request(artifacts, "restore")
  # ★Grade A 는 **리서치를 멈추지 않는다** (도훈 지시 2026-08-30 "A등급 달성하더라도 리서치가 이어지게").
  #   구판은 enabled=false 로 전 루프를 세웠는데, 그건 **리서치 루프**와 **BOOK 등재 관문**을 뒤섞은 것이다.
  #   후보 하나가 A 를 찍었다고 나머지 칸·다음 논문이 설 이유가 없다. A 는 큐에 쌓이고 루프는 계속 돈다.
  #   ★불변: BOOK 등재는 여전히 Judge(PIT) + 도훈 confirm 을 거친다 — 자동 등재는 없다(헌법).
  .gaq_upsert(n, code, artifacts, list(status = "awaiting_judge", judge_request = jr, hold_codes = NULL, hold_detail = NULL,
                                       released_at = .now_ts()))
  jlog("grade_a_queued", n = n, code = code, judge_request = jr, note = "루프 계속 — Judge/BOOK 만 confirm 대기")
  tryCatch({ source(file.path(ROOT, "02_Infrastructure/ops/rf_auto_notify.R"))
             ## ★A 는 즉시 경로에서도 팡파레를 앞세운다 (중복은 마커가 막는다)
             tryCatch({ source(file.path(ROOT, "02_Infrastructure/ops/rf_grade_fanfare.R"))
                        .EA <- rf_load(1L, ROOT); .iA <- .rf_find(.EA, BID)
                        if (!is.na(.iA)) rf_grade_fanfare(BID, "A", code,
                          essence %||% list(), n = n, maxa = MAXA,
                          title = .rf_target_label(.EA$entries[[.iA]]),
                          base_grade = .EA$entries[[.iA]]$base_grade %||% "", root = ROOT) },
                      error = function(e) jlog("grade_fanfare_failed", err = conditionMessage(e)))
             rf_auto_notify(BID, n, kind = "grade_a") }, error = function(e) jlog("telegram_failed", err = conditionMessage(e)))
  invisible(TRUE)
}
.a_hold_record <- function(n, code, artifacts, elig, phase) {
  codes <- as.character(elig$codes %||% character(0))
  tryCatch(.gaq_upsert(n, code, artifacts, list(status = paste0("held:", paste(codes, collapse = "+")),
                         hold_codes = as.list(codes),
                         hold_detail = (elig$detail %||% list())[intersect(codes, names(elig$detail %||% list()))],
                         hold_inactive = as.list(elig$inactive %||% character(0)), hold_phase = phase,
                         held_at = .now_ts(), regime_current = elig$regime_current %||% NA_character_)),
           error = function(e) jlog("grade_a_queue_failed", n = n, err = conditionMessage(e)))
  .a_art_request(artifacts, "park", codes)
  jlog("grade_a_held", n = n, code = code, phase = phase, codes = paste(codes, collapse = "+"),
       inactive = paste(elig$inactive %||% character(0), collapse = "+"),
       note = "A 자격 관문 보류 — 등급 불변 · 발행만 미룸 · entry active 유지(다음 tick 칸 소비 · tick 시작 재평가)")
}
.a_decision <- function(n, code, elig, action, phase) tryCatch({
  .src <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_runner_gates.R")
  rf_record_decision("a_eligibility", BID,
    candidates = list(
      list(id = "publish", rank = if (identical(action, "publish")) 1L else 2L,
           reason = if (identical(action, "publish")) "활성 보류 코드 없음" else "활성 보류 코드 있음"),
      list(id = "hold", rank = if (identical(action, "hold")) 1L else 2L,
           reason = paste(elig$codes %||% character(0), collapse = "+"))),
    chosen = action,
    rule = list(src = "02_Infrastructure/reinforcement/rf_runner_gates.R::rf_a_eligibility",
                sha = tryCatch(unname(as.character(tools::md5sum(.src))), error = function(e) ""),
                knobs = list(gate = elig$gate_source %||% "", active = as.list(elig$gate_active %||% character(0)))),
    scope = list(n = as.integer(n), cell = code, phase = phase, regime_current = elig$regime_current %||% NA_character_,
                 codes = as.list(elig$codes %||% character(0)), inactive = as.list(elig$inactive %||% character(0)),
                 facts = (elig$facts %||% list())[intersect(c("regime", "regime_basis", "window_dev", "window_source", "n_trials",
                                                               "selection_type", "inherited_unverified", "vintage_flags"),
                                                             names(elig$facts %||% list()))]),
    root = ROOT)
  invisible(TRUE)
}, error = function(e) jlog("decision_record_failed", kind = "a_eligibility", n = n, err = conditionMessage(e)))
## 관문 평가 — 오류는 보류(fail-closed · gate_error). entries = 계보 검증 층 키의 원천(보통 tick 시작 원장).
.a_eval <- function(att, spec, axes = NULL, entries = led$entries, entry = E)
  tryCatch(rf_a_eligibility(entry, att, spec, rf_a_ctx(.RCTX, entries, BID, axes = axes)),
           error = function(e) list(eligible = FALSE, codes = "gate_error", inactive = character(0), fired = "gate_error",
                                    detail = list(gate_error = conditionMessage(e)), facts = list(), gate_source = "",
                                    gate_active = character(0), regime_current = .RCTX$regime, self_unverified = FALSE,
                                    evaluated_at = .now_ts()))
## 원장에서 다시 읽은 attempt 로 재평가 (B5 경계 — 적대검증 verdict 반영). 원장에 없으면 수집 시점 모양으로.
.a_recheck <- function(h, aL, L) {
  att <- if (length(aL)) aL[[1]] else list(n = h$n, cell_code = h$code, grade = "A", essence = h$essence, artifacts = h$artifacts)
  k <- if (!is.null(L)) .rf_find(L, BID) else NA
  .a_eval(att, .rfg_spec_read(att), entries = (L %||% led)$entries, entry = if (!is.na(k)) L$entries[[k]] else E)
}
.a_route <- function(n, code, artifacts, essence, elig, phase) {
  if (isTRUE(elig$eligible)) {
    .grade_a_enqueue(n, code, artifacts, essence, elig); .a_decision(n, code, elig, "publish", phase); TRUE
  } else {
    .a_hold_record(n, code, artifacts, elig, phase); .a_decision(n, code, elig, "hold", phase); FALSE
  }
}
.a_graduate <- function(n, why) tryCatch({ rf_graduate_entry(1L, BID, n, why, root = ROOT); TRUE },
  error = function(e) { jlog("graduate_failed", n = n, err = conditionMessage(e)); FALSE })

# ── ★적대검증 연기분 재실행 (OPS-RUNNER-REFRESH-BARRIER 수리 · 2026-09-24 적대검증 3인 BLOCKING) ──────────────
#   리프레시 배리어로 적대검증(G2)이 멈추면 rf_overlay_adversary_run 이 그 블록 칸에 verdict "deferred_refresh_lock" 을
#   남긴다. pass 가 아니므로 소비 보류다(rf_adversary_ok·rf_grade_a_hold·rf_promote 가 이미 그렇게 읽는다 — 승자·B4 바닥·
#   carry·A 발행 전부). 표식은 판정이 아니라 '다시 돌려라' 다 — 적대검증은 블록 경계 배치에서만 돌아서(아래 B5 적대 반증)
#   다음 tick 은 다른 블록이라 다시 안 선다. 그래서 이 entry 를 다시 잡은 tick 에 **승자 해석보다 앞에서** 재실행한다
#   (러너 진입 배리어를 지난 뒤다). 또 막히면 표식이 다시 남고 다음 tick 에 또 돈다. 표식이 없으면 이 블록은 아무것도
#   하지 않는다(잠금 없음 경로 비트 동일). ★P0-12(2026-09-24) 이후 보류 A 의 entry 는 active 로 남으므로(graduate=FALSE) 여기로 다시
#   온다 — 재실행이 pass 를 내면 바로 아래 '보류 A 재평가'가 발행·졸업한다(구판: graduated 로 닫혀 영구 미결이었다).
.adv_def_blk <- unique(unlist(lapply(E$attempts %||% list(), function(a) {
  .v <- a$adversary %||% list()
  if (identical(as.character(.v$verdict %||% "")[1], "deferred_refresh_lock")) as.character(.v$block %||% "B5")[1] else NULL })))
#   ★I2(2026-09-24 · 통합 검증): 규약 거부 error(regime_*) 가 그 판정 **뒤의** rebase(P0-06)로 풀릴 수 있으면 같은 자리에서 재실행한다
#   (rebase 전 native close_t1 B5 칸이 legacy 바닥과 짝지어져 받은 error — 구판은 다시 검정하는 경로가 없었다). 판정은 순수 함수
#   rf_runner_gates.R::rf_adversary_rerun_blocks(include_deferred = FALSE — 연기분은 위 술어가 종전대로 맡는다 · 표식 문자열 패리티 검사 G8m 불변).
.adv_rr <- rf_adversary_rerun_blocks(E, include_deferred = FALSE)
.adv_rg_blk <- setdiff(.adv_rr$blocks, .adv_def_blk)
if (length(c(.adv_def_blk, .adv_rg_blk))) {
  for (.bk in c(.adv_def_blk, .adv_rg_blk)) {
    .rg <- .bk %in% .adv_rg_blk
    jlog(if (.rg) "adversary_rerun_regime" else "adversary_rerun_deferred", base_id = BID, block = .bk,
         cells = if (.rg) paste(.adv_rr$why[[.bk]], collapse = ",") else "",
         note = if (.rg) "rebase 뒤 규약 거부 error 칸의 적대검증 재실행 — 승자 해석 전" else "리프레시 배리어로 연기된 적대검증 재실행 — 승자 해석 전")
    .advR <- tryCatch({
      suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_overlay_adversary.R"), local = TRUE))
      rf_overlay_adversary_run(BID, .bk, 1L, root = ROOT)
    }, error = function(e) { jlog("adversary_rerun_failed", base_id = BID, block = .bk, err = conditionMessage(e)); NULL })
    if (!is.null(.advR))
      jlog("adversary_rerun_done", base_id = BID, block = .bk, n = NROW(.advR),
           verdicts = if (NROW(.advR)) paste(sprintf("%s=%s", .advR$code, .advR$verdict), collapse = ",") else "")
  }
  led <- rf_load(1L, ROOT)
  E <- Filter(function(e) identical(e$base_id, BID), led$entries)[[1]]
}
## ── ★보류 A 재평가 (P0-12 · 2026-09-24) — tick 시작 · 승자 해석·예산 판정 **앞** ─────────────────────────────────────
##   A 자격 관문이 보류한 A 는 entry 를 active 로 남긴다(rf_record_result(graduate = FALSE) → attempt$graduate_deferred). 보류 사유가
##   풀렸는지(위 연기분 재실행의 pass · rebase 로 규약 일치 · 표식 해소)는 매 tick 여기서 다시 판정한다 — 풀리면 발행 + 졸업
##   (구판 즉시 경로와 같은 끝)하고 이 tick 을 닫는다. 그대로 보류면 사유가 **바뀔 때만** 큐·결정 기록을 갱신한다(매 tick 소음 금지).
##   ★구판(적대검증 보류만 있던 때)은 A 를 적는 순간 entry 가 graduated 로 닫혀 이 경로 자체가 없었다 — 같은 tick 에 못 풀면 영구 미결.
.held_prev <- Filter(function(a) identical(as.character(a$grade %||% "")[1], "A") && isTRUE(a$graduate_deferred) &&
                       is.null(a$graduate_released_at), E$attempts %||% list())
if (length(.held_prev)) {
  .rel_any <- FALSE
  for (.ha in .held_prev) {
    .hc <- .rfg_s1(.rf_attempt_code(.ha)); .hs0 <- .gaq_status(.ha$n)
    .he <- .a_eval(.ha, .rfg_spec_read(.ha))
    if (isTRUE(.he$eligible)) {
      jlog("grade_a_released", n = .ha$n, code = .hc, phase = "tick_start", was = .hs0,
           verdict = as.character((.ha$adversary %||% list())$verdict %||% ""), note = "보류 사유 해소 — judge_request·grade_a_queue 발행 + 졸업")
      .grade_a_enqueue(.ha$n, .hc, .ha$artifacts, .ha[["essence"]], .he)
      .a_decision(.ha$n, .hc, .he, "publish", "tick_start")
      if (.a_graduate(.ha$n, sprintf("A 자격 관문 해제 — tick 시작 재평가(이전 %s)", .hs0))) .rel_any <- TRUE
    } else if (!identical(.hs0, paste0("held:", paste(.he$codes, collapse = "+")))) {
      .a_hold_record(.ha$n, .hc, .ha$artifacts, .he, "tick_start")
      .a_decision(.ha$n, .hc, .he, "hold", "tick_start")
    }
  }
  if (.rel_any) {
    jlog("entry_graduated_on_release", base_id = BID,
         note = "보류 A 해제로 졸업 — 이 tick 종료(다음 tick 은 다른 active entry 또는 다음 논문)")
    return(0L)
  }
}
used <- as.integer(E$attempts_used %||% 0L)
# ★entry 별 상한 (2026-09-04 도훈 지시). B1 이 설계에 따라 가변 길이가 되면서,
#   전역 25 를 그대로 두면 B1 이 쓴 만큼 뒤 블록이 잘린다 — 실측: B1 14칸 -> B4(결합)가
#   아예 못 돌았다. 각 블록 승자를 합치는 칸을 못 보면 그 entry 는 A 로 갈 길이 없다.
#   "칸 수 제한을 두지 마라" 를 B1 에만 적용하고 총예산에 안 적용한 비대칭을 닫는다.
MAXA <- as.integer(E$max_attempts %||% led$max_attempts %||% 25L)
cells <- do.call(c, lapply(PROG$blocks, function(b) lapply(b$cells, function(c) { c$block <- b$id; c$axis <- b$axis; c })))
## ── ★축 등록부 ↔ 격자 계약 · 격자 기본 예산 (결정 B4-SIX-AXIS-AND-CARRY-AXES · 도훈 2026-09-26 · 정본 rf_spec_axes.R) ─────────────
##   ① 계약 — 등록부 소유 블록 = 격자 블록(결합 블록 제외) · 결합 칸 = 전결합 + 축별 LOO · 승자 기준 존재. 어긋나면 매 tick 로그 1줄
##      (정지는 안 한다 — 어긋난 축은 B4 에서 승자 없음 → 등록부 b4_base 로 돈다 · 조용한 통과 없음).
##   ② 기본 예산 — 원장 파일 max_attempts(35 = 7블록×5 시절 격자 크기의 사본)는 격자가 늘면 낡는다(B4 6축 = 7칸 → 격자 37). 그대로면 설계 초과가
##      없는 entry 에서 B4 마지막 칸이 used ≥ MAXA 로 잘린다. **이 tick 안에서만** 격자 칸 합으로 올린다(파일은 쓰지 않는다 · 내리지 않는다) —
##      아래 예산 재도출(rf_budget_auto(led$max_attempts …))이 이 값을 기본으로 쓰고, .cur 은 원장 게이트(rf_append_attempt: entry max_attempts →
##      파일 값)가 실제로 보는 값(.led_max_file)이라 둘이 다르면 entry 예산이 기록된다(기록이 없으면 원장 게이트가 파일 값에서 칸을 거부하고
##      entry 를 exhausted 로 닫는다).
.axc <- tryCatch(rf_axes_grid_contract(PROG), error = function(e) paste("계약 판정 실패:", conditionMessage(e)))
if (length(.axc)) jlog("spec_axes_contract_violation", base_id = BID, problems = paste(.axc, collapse = " | "),
                       note = "축 등록부(rf_spec_axes.R)와 격자(reinforce_program.json)가 어긋난다 — 어긋난 축은 B4 에서 승자 없음(b4_base)으로 돈다")
.led_max_file <- led$max_attempts
led$max_attempts <- rf_budget_base(led$max_attempts, PROG)
##   ③ 승계 순서 — config spec_axes.inherit_order(부재 = 등록부 기본 floor > carry · 구판 재현 = ["carry","floor"] · 도훈 결정 항목).
##      무효값(두 원천이 아니거나 중복)은 기본으로 돌고 로그 1줄 — 조용한 통과 없음.
.axio <- rf_axes_inherit_order(CFG)
if (!isTRUE(.axio$valid)) jlog("spec_axes_inherit_order_invalid", base_id = BID, source = .axio$source, used = paste(.axio$order, collapse = ">"))

# ── ★B1 설계 소비 (도훈 지시 2026-09-04 "블록 진입 시 1회만 LLM 설계") ────────
#   설계가 있으면 격자의 B1 칸을 **통째로** 갈아 끼운다. 칸 수가 5가 아니어도 뒤 블록의
#   코드(B2_6…)는 밀리지 않는다 — 커서가 위치가 아니라 **기록된 셀 코드**에서 나오기 때문이다
#   (2026-09-04 커서 수리). 구판 개수 커서였다면 B1 이 6칸인 순간 격자가 통째로 어긋났다.
#   설계가 없거나 검증에 떨어졌으면 이 블록은 아무것도 하지 않고, B1 은 규칙 선정으로 돈다.
.b1_design <- tryCatch({
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_b1_design_lib.R"), local = TRUE))
  rf_b1_design_cells(BID, root = ROOT)
}, error = function(e) { jlog("b1_design_load_failed", err = conditionMessage(e)); NULL })
# ★블록 전이 설계 소비 (도훈 지시 ④ · 2026-09-04) — B2/B3/B5 도 설계가 있으면 그것으로 돈다.
#   설계는 앞 블록 기전 에이전트가 낸 것이고, 검증(카탈로그 실재성·중복)을 통과한 것만 저장돼 있다.
#   없으면 이 블록은 그냥 규칙 선정으로 돈다 — 폴백은 조용하지 않고 로그에 남는다.
.blk_design <- tryCatch({
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_block_design.R"), local = TRUE))
  .out <- list()
  for (.bb in RFBD_BLOCKS) { .cc <- rfbd_cells(ROOT, BID, .bb); if (length(.cc)) .out[[.bb]] <- .cc }
  .out }, error = function(e) { jlog("block_design_load_failed", err = conditionMessage(e)); list() })
if (length(.blk_design)) for (.bb in names(.blk_design)) {
  .rest2 <- Filter(function(c) !identical(as.character(c$block %||% ""), .bb), cells)
  .new2  <- lapply(.blk_design[[.bb]], function(c) { c$block <- .bb
    c$axis <- switch(.bb, B2 = "weighting", B3 = "universe", B5 = "risk_overlay", "multifactor"); c })
  cells <- c(Filter(function(c) identical(as.character(c$block %||% ""), "B1"), .rest2),
             .new2,
             Filter(function(c) !identical(as.character(c$block %||% ""), "B1"), .rest2))
  jlog("block_design_applied", base_id = BID, block = .bb, cells = length(.new2),
       note = "앞 블록 기전이 낸 설계로 이 블록을 돈다")
}
if (length(.b1_design)) {
  .rest <- Filter(function(c) !identical(as.character(c$block %||% ""), "B1"), cells)
  cells <- c(lapply(.b1_design, function(c) { c$block <- "B1"; c$axis <- "multifactor"; c }), .rest)
  jlog("b1_design_applied", base_id = BID, cells = length(.b1_design),
       note = "설계 칸으로 B1 교체 — 칸 수는 설계가 정한다")
}
## >>> O0a 칸 설계 출처 표식 — 조립 지점에서 붙인다(설계 파일 존재로 사후 도출하면 entry 단위가 돼 폴백 칸을 LLM 칸으로 센다 · E3).
##   설계가 적용된 블록의 칸 = 전부 설계 칸(위 두 절이 블록을 통째로 갈아 끼운다). 나머지 = 격자(표식 없음 · 상주 칸은 standing 필드로 판정).
if (length(.b1_design)) cells <- lapply(cells, function(c) { if (identical(as.character(c$block %||% ""), "B1")) c$design_origin <- "llm_b1"; c })
for (.bb in names(.blk_design)) cells <- lapply(cells, function(c) { if (identical(as.character(c$block %||% ""), .bb)) c$design_origin <- "llm_block"; c })
## <<< O0a

# ── ★상주 칸 (WP-R · 도훈 지시 2026-09-17 · 격자 정본 reinforce_program.json::standing_cells) ────────
#   BOOK_0001 PG2 오버레이의 동결 사양(pg2_risk_overlay_v1)을 **매 세대 B5 마다** 자기 코드(B5_31)로 한 번 잰다 —
#   설계·규칙 선정·회피 목록과 무관한 대조 칸이다. 판정은 rf_runner_gates.R::rf_standing_decision (순수 함수):
#   (a) 그 코드의 시도가 이미 있으면 항상 얹는다(재개·승자 해석이 **코드로** 칸을 찾는다 — 없으면 그 칸을 잃는다)
#   (b) B5 시도가 아직 없고 ∧ arm 이 카탈로그 active ∧ carry 에 없으면 얹는다
#   (c) 재설계 라운드(E$b5_redesign.active · B5 설계 레인이 쓴다)가 열려 있고 그 코드의 시도가 없으면 얹는다.
#   그 밖은 standing_cell_skipped 로 사유를 남긴다(조용한 통과 없음). B5 의 **첫 칸**에 넣어 첫 B5 배치에서 돈다.
#   예산은 아래 재도출식이 +1 로 센다(격자 25 밖의 칸이다).
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_runner_gates.R"), local = TRUE))
.n_standing_inserted <- 0L
.redesign_on <- rf_b5_redesign_active(E)
for (.sc in tryCatch(rfbd_standing_cells(ROOT),
                     error = function(e) { jlog("standing_cells_load_failed", err = conditionMessage(e)); list() })) {
  if (!identical(as.character(.sc$block %||% "B5"), "B5")) {
    jlog("standing_cell_skipped", code = as.character(.sc$code %||% ""), reason = "block_not_b5"); next }
  .dec <- rf_standing_decision(.sc, E$attempts, carry_overlay = E$carry$overlay,
                               catalog = tryCatch(.rfbd_b5_raw(ROOT), error = function(e) list()),
                               redesign_active = .redesign_on)
  if (!isTRUE(.dec$insert)) {
    jlog("standing_cell_skipped", code = as.character(.sc$code), arm = as.character(.sc$overlay_pick %||% ""),
         reason = .dec$reason); next }
  .cellS <- rf_standing_cell(.sc, .dec$kind, basis = .dec$basis)
  .kB5 <- which(vapply(cells, function(c) identical(as.character(c$block %||% ""), "B5"), logical(1)))
  cells <- if (length(.kB5)) append(cells, list(.cellS), after = .kB5[1] - 1L) else c(cells, list(.cellS))
  .n_standing_inserted <- .n_standing_inserted + 1L
  jlog("standing_cell_inserted", base_id = BID, code = .cellS$code, arm = .cellS$overlay$arm_id,
       kind = .cellS$overlay$kind, reason = .dec$reason, redesign = .redesign_on,
       note = "상주 칸 — B5 첫 칸으로 삽입(설계·규칙 선정과 무관 · 승격 carry 제외)")
}
## ── ★통제 칸 (P1-06 · 2026-09-25 · 격자 정본 reinforce_program.json::standing_cells[control]) ──────────────────────────────
##   carry 가 있는 entry 의 B1 머리에 carry 재현(B1_0 · E3) + null-factor 희석(B1_N*)을 넣는다. 판정·셀 조립 = rf_runner_gates.R::rf_control_plan
##   (순수) · 여기는 삽입·로그만. 예산은 상주 삽입 수로 센다(아래 재도출식 · 격자 밖 칸). 선정·승계·dedup 제외는 전부 gates 술어가 한다.
.ctlP <- tryCatch(rf_control_plan(E, rfbd_control_cells(ROOT), cells),
                  error = function(e) { jlog("control_cells_failed", base_id = BID, err = conditionMessage(e)); NULL })
.ctl_replay_codes <- tryCatch(vapply(Filter(function(x) identical(as.character(x$control %||% ""), "carry_replay"), rfbd_control_cells(ROOT)),
                                     function(x) as.character(x$code %||% ""), character(1)), error = function(e) character(0))
.ctl_null_codes <- tryCatch(vapply(Filter(function(x) identical(as.character(x$control %||% ""), "null_factor"), rfbd_control_cells(ROOT)),
                                   function(x) as.character(x$code %||% ""), character(1)), error = function(e) character(0))
if (!is.null(.ctlP)) {
  ## carry 없는 entry(no_carry)는 적용 범위 밖이라 로그하지 않는다 — 그 밖의 건너뜀(중간 삽입 금지·형식 오류·inactive)은 1줄로 남긴다.
  .ctl_sk <- Filter(function(z) !identical(z$reason, "no_carry"), .ctlP$skipped)
  if (length(.ctl_sk))
    jlog("control_cells_skipped", base_id = BID, n = length(.ctl_sk),
         reasons = paste(unique(vapply(.ctl_sk, function(z) z$reason, character(1))), collapse = ","),
         codes = paste(vapply(.ctl_sk, function(z) sprintf("%s=%s", z$code, z$reason), character(1)), collapse = ","))
  if (length(.ctlP$cells)) {
    cells <- rf_control_insert(cells, .ctlP$cells)
    .n_standing_inserted <- .n_standing_inserted + length(.ctlP$cells)
    jlog("control_cells_inserted", base_id = BID, n = length(.ctlP$cells),
         codes = paste(vapply(.ctlP$cells, function(z) sprintf("%s=%s", z$code, z$.reason), character(1)), collapse = ","),
         note = "통제 칸 — B1 머리 삽입(선정 후보 아님 · 서명 dedup·승계·무처치 면제 · 예산 = 상주 삽입 수)")
  }
}

# ── ★entry 예산 — **매 tick 재도출** (도훈 2026-09-04 · 2026-09-17 "예산 상한은 신경쓰지말고 반영") ────────
#   자동 = 기본(원장 max_attempts) + B1 설계 초과 + B5 설계 초과 + 상주 삽입 + 재설계 추가(E$b5_redesign.cells_added).
#   구판은 B1 설계가 있을 때만 셌다 — B5 설계가 7칸이거나 상주 칸이 얹히면 그만큼 뒤 블록(B4 결합)이 잘렸다.
#   실제 상한 = max(자동, 수동): 수동 상향은 덮지 않고(구판은 매 tick 되돌려 써 추가 칸이 1개만 돌았다),
#   자동은 자동식 위로 못 올린다. 바뀔 때만 원장에 쓴다. 산식 정본 = rf_runner_gates.R::rf_budget_auto/rf_budget_want.
## ── ★격자 구조 상태 · D-G B5 적응 축소 — **최종 칸 목록**에 적용 (2026-09-25 · 사람 규칙 · 정본 rf_lane_rules.R) ─────────────────
##   (가) B3-STRUCTURAL-TRIM(결정 2026-09-25): program structure_rules 의 diag 블록 = 격자 진단 칸만 · 결합 블록은 그 블록을 참조하는 칸을
##       뺀다(전 승자 결합 칸 보존). 절단 전 계획으로 진입한 블록은 동결 · 시도 있는 코드 보존 · 빈 칸이 남는데 used ≥ 칸 수면 항등(정지 방지).
##   (나) D-G B5 축소(ORGANIC-DE Q②′(α) 고정 사람 규칙 예외): G2 유효 pass 0 ∧ compose_only 연속 라운드 ≥ K → B5 = 상주 + standing_plus 칸.
##       판정 입력(적대검증 판정·라운드)은 전기간 파생이다 — 결정마다 증거 칸 수(n_evidence)를 로그에 싣는다(N_program 계상).
##   예산은 아래 재도출이 **이 목록의** B5 칸 수로 센다(축소분 재가산 차단). 둘 다 설정이 없으면 항등.
cells <- rf_structure_cells(cells, E, PROG)
.st <- attr(cells, "structure_trim")
if (length(.st$invalid)) jlog("structure_rules_invalid", base_id = BID, invalid = paste(.st$invalid, collapse = " | "),
                              note = "무효 구조 규칙은 적용하지 않는다(program structure_rules 확인)")
if (isTRUE(.st$applied) || grepl("identity$", .st$reason %||% ""))
  jlog("structure_trim", base_id = BID, reason = .st$reason, rules = paste(.st$rules, collapse = ","),
       removed = paste(.st$removed, collapse = ","), inserted = paste(.st$inserted, collapse = ","),
       frozen = paste(unique(.st$frozen), collapse = ","), n_cells = length(cells),
       note = if (grepl("identity$", .st$reason %||% "")) "불변식 위반 — 구조 절단 취소(항등)" else "구조 상태 적용(사람 규칙)")
.b5d <- rf_b5_budget_decide(led$entries, get0("CFG", ifnotfound = list()), gate_fn = function() rf_a_gate_config(ROOT))
cells <- rf_b5_budget_cells(cells, E, .b5d)
.b5b <- attr(cells, "b5_budget")
if (isTRUE(.b5b$applied) || identical(.b5b$reason, "inv4_identity"))
  jlog("b5_budget_decision", base_id = BID, reason = .b5b$reason, removed = paste(.b5b$removed, collapse = ","),
       why = .b5d$why, run_len = .b5d$run_len, run_start = .b5d$run_start, k = .b5d$k, standing_plus = .b5d$standing_plus,
       n_valid_pass = .b5d$n_valid_pass, n_pass_flagged = .b5d$n_pass_flagged, n_evidence = .b5d$n_evidence,
       note = "D-G B5 축소 — 성과 소비 고정 사람 규칙(ORGANIC-DE Q②′(α)) · n_evidence = 이 결정이 소비한 적대검증 판정 칸 수(N_program)")
.nB1d <- length(.b1_design)
.b5c  <- rf_b5_design_counts(length(.blk_design[["B5"]] %||% list()), E)
.slot_of <- function(id) { for (b in PROG$blocks) if (identical(b$id, id)) return(as.integer(b$n %||% length(b$cells))); 5L }
.nB5c <- rf_block_cell_count(cells, "B5")   # ★최종 목록의 B5 칸(설계·상주·재설계·D-G 축소 적용 뒤) — 가산 차단(2026-09-25)
.nB1c <- rf_block_cell_count(cells, "B1")   # ★최종 목록의 B1 칸(설계·통제 칸 삽입 뒤) — B1 도 초과분만(P1 · 2026-09-26)
.auto <- rf_budget_auto(led$max_attempts %||% 25L, .nB1d, .b5c$n_base, .n_standing_inserted, .b5c$n_redesign,
                        slot_b1 = .slot_of("B1"), slot_b5 = .slot_of("B5"), n_b5_cells = .nB5c, n_b1_cells = .nB1c)
.want <- rf_budget_want(.auto, E$max_attempts)
.cur  <- as.integer(E$max_attempts %||% .led_max_file %||% 25L)   # ★원장 게이트가 실제로 보는 값(entry → 파일) — 위 격자 기본 예산과 다르면 기록된다
if (.want != .cur) {
  ok_b <- tryCatch({ rf_record_entry_budget(1L, BID, .want,
            sprintf("예산 재도출 %d -> %d = 기본 %d + B1 격자 초과 %d(최종 B1 %d칸 · 설계 %d) + B5 격자 초과 %d(최종 B5 %d칸 = 설계 %d · 상주 %d · 재설계 추가 %d · D-G 축소 −%d) — 뒤 블록이 잘리지 않도록",
                    .cur, .want, as.integer(led$max_attempts %||% 25L), max(0L, .nB1c - .slot_of("B1")), .nB1c, .nB1d,
                    max(0L, .nB5c - .slot_of("B5")), .nB5c, .b5c$n_design, .n_standing_inserted, .b5c$n_redesign,
                    length(.b5b$removed %||% character(0))),
            root = ROOT); TRUE },
          error = function(e) { jlog("entry_budget_failed", err = conditionMessage(e)); FALSE })
  if (isTRUE(ok_b)) { MAXA <- .want
    jlog("entry_budget_raised", base_id = BID, max_attempts = .want, auto = .auto, b1_cells = .nB1c, b1_design = .nB1d,
         b5_cells = .b5c$n_design, standing = .n_standing_inserted, redesign = .b5c$n_redesign) }
} else MAXA <- .cur
## ── ★B4 결합 칸 재도출 — 결합 대상 축 = 축 등록부 − 진단 모드 블록 (B4-SIX-AXIS · 2026-09-26 · 정본 rf_spec_axes.R::rf_axes_combo_cells) ─────
##   격자 blocks[B4].cells 는 코드·라벨 목록(진단 블록 없을 때의 전결합 1 + 축별 LOO)이다. 진단 모드 블록 = 사람 구조 규칙(rf_structure_rules —
##   B3-STRUCTURAL-TRIM 등 · 그 판독기가 없으면 없음). 모드 = config b4_combo.diag_mode(부재 = exclude_axis: 진단 블록을 결합 축에서 뺀다 ·
##   drop_referencing: 진단 블록 참조 칸 절단(구조 규칙 현행) · keep_loo: 절단 없음 — 기본 = exclude_axis = 결정 B3-TRIM-VS-B4-SIX (A) · [위임] 2026-09-26).
##   ★동결 — 이 entry 에 결합 칸 시도가 있으면 그 칸 스펙에 기록된 계획(combo_plan)을 쓴다(진행 중 결합 블록의 계획을 바꾸지 않는다).
##   ★위치 — 예산 재도출 **뒤**(예산 기본 = 격자 칸 합 · 결합 칸이 줄면 격자 소진이 닫는다) · 구조 규칙 적용(rf_structure_cells) 뒤에도 결합 블록은
##     이 계획이 대체한다(같은 판단을 두 번 하지 않는다 — 통합 시 rf_structure_cells 의 결합 절단은 이 계획과 같은 모드여야 한다).
.b4_trim <- if (exists("rf_structure_rules", mode = "function"))
  tryCatch(as.character(unlist(lapply(rf_structure_rules(PROG)$rules, function(r) r$block))),
           error = function(e) { jlog("b4_combo_rules_failed", base_id = BID, err = conditionMessage(e)); character(0) }) else character(0)
.b4_mode <- rf_axes_diag_mode(CFG)
if (!isTRUE(.b4_mode$valid)) jlog("b4_combo_mode_invalid", base_id = BID, source = .b4_mode$source, used = .b4_mode$mode)
.b4_fz <- rf_axes_combo_frozen(E$attempts, function(a) {
  .p <- as.character((a[["essence"]] %||% list())$spec %||% "")[1]
  if (is.na(.p) || !nzchar(.p) || !file.exists(.p))
    .p <- file.path(WDIR, sprintf("spec_%s__%s.json", as.character(a$cell_code %||% "")[1], substr(BID, 1, 48)))
  if (file.exists(.p)) tryCatch(fromJSON(.p, simplifyVector = FALSE), error = function(e) NULL) else NULL })
##   ★동결 판정 불가(결합 칸 시도의 스펙을 하나도 못 읽음 · source = unreadable) = 현 계획으로 돈다 — '기록 없는 수리 전 칸'(keep_loo)과 구분(10-03).
if (!is.null(.b4_fz) && is.na(.b4_fz$mode)) {
  jlog("b4_combo_frozen_unreadable", base_id = BID, n = .b4_fz$n, note = "결합 칸 시도의 스펙을 하나도 못 읽었다 — 동결 판정 불가 · 현 계획으로 돈다")
  .b4_fz <- NULL
}
.b4_plan <- tryCatch(rf_axes_combo_cells(PROG, if (is.null(.b4_fz)) .b4_trim else .b4_fz$trimmed,
                                         mode = if (is.null(.b4_fz)) .b4_mode$mode else .b4_fz$mode),
                     error = function(e) { jlog("b4_combo_plan_failed", base_id = BID, err = conditionMessage(e)); NULL })
if (!is.null(.b4_plan)) {
  cells <- c(Filter(function(c) !identical(as.character(c$block %||% ""), RF_AXES_COMBO_BLOCK), cells), .b4_plan$cells)
  if (length(.b4_plan$trimmed) || length(.b4_plan$drop) || !is.null(.b4_fz))
    jlog("b4_combo_plan", base_id = BID, mode = .b4_plan$mode, mode_source = if (is.null(.b4_fz)) .b4_mode$source else .b4_fz$source,
         trimmed = paste(.b4_plan$trimmed, collapse = ","), axes = paste(.b4_plan$axes, collapse = ","),
         drop = paste(.b4_plan$drop, collapse = ","), projected = paste(.b4_plan$projected, collapse = ","),
         n_cells = length(.b4_plan$cells), note = "결합 칸 = 등록부 축 − 진단 모드 블록(모드 스위치 b4_combo.diag_mode)")
}

# ★미측정(등록만 된) 칸 — **소진 판정보다 먼저** 본다. 등록됐는데 실행이 실패한 칸을
#   exhausted 로 넘기면 그 칸이 영구 소실된다(2026-08-30 실사고: 워커 4개 미기동으로 17~20 이 빈 채 소비).
# ★단 terminal 로 닫힌 칸은 제외한다. 재개는 *일시적* 실패만 상정한 장치였는데, 구조적 실패
#   (같은 스펙이면 같은 자리에서 죽는 것)에는 출구가 없어 루프가 제자리를 돌았다
#   (2026-08-31 실사고: B3_11 이 00:16~07:46 사이 16회 동일 실패, used 15 고정).
#   terminal 은 성공 위장이 아니다 — essence 는 여전히 없고, 재개 대상에서만 빠진다.
pending <- Filter(function(a) (is.null(a$essence) || is.null(a$essence$port_t)) && !isTRUE(a$terminal),
                  E$attempts)

## ── ★기전 백필 (2026-09-04) — 블록 L-code 는 있는데 기전(LLM 서술)이 빈 블록을 한 번 더 시도한다 ──
##   실사고: 15블록 중 6블록의 '배운 것' 이 비었다(모델 400 · 킬스위치 · 호출부 도입 전). 기전 레인은 블록 종료
##   직후 한 번만 불리고 실패하면 영영 비었다. 상한 2회(mechanism_tries) · 레인 스위치가 꺼져 있으면 안 부른다.
if (isTRUE(CFG$enabled) && isTRUE((CFG$lcode_mechanism %||% list())$enabled)) tryCatch({
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_mech_backfill.R"), local = TRUE))
  .bf <- rf_mech_backfill_targets(BID, ROOT)
  for (.b in utils::head(.bf, 2L)) {
    jlog("mechanism_backfill", base_id = BID, block = .b, note = "기전이 빈 블록 — 레인 재시도(상한 2회)")
    system2("bash", c(shQuote(file.path(ROOT, "02_Infrastructure/ops/rf_lcode_mechanism.sh")), BID, .b),
            stdout = FALSE, stderr = FALSE)
  }
}, error = function(e) jlog("mechanism_backfill_failed", err = conditionMessage(e)))

## ── ★경계 백필 + 격자 재도출 대조 (B5FIX · 2026-09-26 · 도훈 승인 "1번 진행") ─────────────────────────────────────────────
##   실사고 09-25 RP_20260924_052517_7308 B5: 이 tick 이 위 기전 백필(B6)을 동기로 돌리는 사이 기전 레인이 B5 설계 파일을 덮었다
##   (8칸 레인 설계 → 5칸 · 그 writer 는 이제 rf_lcode_mechanism_lib.R 저장 관문이 막는다). 격자(cells)는 tick 머리에 읽은 8칸이라
##   배치 뒤 경계 판정이 '3칸 남음' 을 셌고 B5 적대검증(G2)·블록 L-code·블록 텔레그램이 증발했다 — 다음 tick 은 5칸 격자로 B5 를
##   완결로 읽고 넘어갔다. 경계 처리는 배치 끝 한 자리에서만 불려, 그 순간을 놓치면(격자 변경 · 경계 도중 러너 사망 · 텔레그램/G2
##   실패) 다시 돌 길이 없었다(같은 entry B6 텔레그램도 09-24 러너 정지로 없다).
##   ① 경계 백필 — **현재 격자**(방금 설계 파일에서 재도출한 cells)·원장·L-code 파일·로그로 "칸은 다 쟀는데 흔적이 없는 블록" 을 찾아
##      빠진 부품만 다시 돈다: G2(B5) → L-code → 기전 → 텔레그램(지연 표기 · 그 블록 시점 표). 판정 정본 = rf_boundary_backfill.R.
##      상한 = boundary_backfill.max_tries(부재 2 · 시작 표식 수) · tick 당 블록 = boundary_backfill.max_blocks_per_tick(부재 2) ·
##      끄기 = boundary_backfill.enabled=false. 소진 판정 **앞**이다 — 마지막 블록(B4) 경계를 놓친 entry 가 흔적 없이 소진되지 않게.
##   ② 격자 재도출 대조 — 이 tick 의 설계 파일을 다시 읽어 격자를 만든 설계(.blk_design)와 다르면 **배치를 열지 않고 tick 을 닫는다**
##      (위 기전 백필·아래 경계 백필이 다음 블록 설계를 저장했다 = 이 tick 격자가 낡았다). 다음 tick 이 파일에서 새 격자를 만든다.
##   등급·원장 칸은 건드리지 않는다(G2 표식 · L-code · 텔레그램 · 로그만).
.bbc <- CFG$boundary_backfill %||% list()
if (!identical(.bbc$enabled, FALSE)) tryCatch({
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_boundary_backfill.R"), local = TRUE))
  .bbT <- rfbb_targets(E, cells, ROOT, LOG_P, max_tries = .bbc$max_tries %||% 2L,
                       adv_status = function(a) rf_adversary_status(a, carry_overlay = E$carry$overlay)$status)
  for (.g in .bbT$gave_up)
    jlog("boundary_backfill_gave_up", base_id = BID, block = .g$block, tries = .g$tries, need = paste(.g$need, collapse = "+"),
         note = "경계 백필 상한 도달 — 더 돌지 않는다(흔적 누락은 그대로 남는다 · 수동 확인)")
  .bb_g2 <- FALSE
  for (.t in utils::head(.bbT$todo, max(1L, as.integer(.bbc$max_blocks_per_tick %||% 2L)))) {
    .tb <- .t$block; .tn <- as.integer(.t$n_last)
    jlog("boundary_backfill", base_id = BID, block = .tb, n = .tn, need = paste(.t$need, collapse = "+"), tries = .t$tries + 1L,
         evidence = paste(.t$evidence, collapse = " · "), note = "칸은 다 쟀는데 경계 흔적이 없다 — 빠진 부품만 다시 돈다")
    if ("g2" %in% .t$need) {
      .advB <- tryCatch({
        suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_overlay_adversary.R"), local = TRUE))
        rf_overlay_adversary_run(BID, "B5", 1L, root = ROOT)
      }, error = function(e) { jlog("adversary_failed", base_id = BID, block = "B5", phase = "boundary_backfill", err = conditionMessage(e)); NULL })
      if (!is.null(.advB)) { .bb_g2 <- TRUE
        jlog("adversary_done", base_id = BID, block = "B5", n = NROW(.advB), phase = "boundary_backfill",
             verdicts = if (NROW(.advB)) paste(sprintf("%s=%s", .advB$code, .advB$verdict), collapse = ",") else "") }
      if (.redesign_on)
        tryCatch({ rf_record_b5_redesign(1L, BID, list(active = FALSE, closed_at = .now_ts(), closed_by = "reinforce_auto_parallel:boundary_backfill",
                                                       adversary_ran = !is.null(.advB)), root = ROOT)
                   jlog("b5_redesign_closed", base_id = BID, adversary_ran = !is.null(.advB), phase = "boundary_backfill") },
                 error = function(e) jlog("b5_redesign_close_failed", base_id = BID, err = conditionMessage(e)))
    }
    if ("lcode" %in% .t$need) {
      .lcB <- tryCatch({ source(file.path(ROOT, "02_Infrastructure/ops/rf_block_lcode.R")); rf_emit_block_lcode(BID, .tn, root = ROOT) },
                       error = function(e) { jlog("lcode_failed", phase = "boundary_backfill", err = conditionMessage(e)); NULL })
      jlog("lcode_block", n = .tn, l_code = as.character(.lcB %||% "NA"), base_id = BID, block = .tb, phase = "boundary_backfill")
      if (!is.null(.lcB) && nzchar(as.character(.lcB)))
        tryCatch(system2("bash", c(shQuote(file.path(ROOT, "02_Infrastructure/ops/rf_lcode_mechanism.sh")), shQuote(BID), shQuote(.tb)),
                         wait = TRUE, stdout = TRUE, stderr = TRUE),
                 error = function(e) jlog("lcode_mechanism_failed", phase = "boundary_backfill", err = conditionMessage(e)))
    }
    if ("telegram" %in% .t$need) {
      .okB <- tryCatch({ source(file.path(ROOT, "02_Infrastructure/ops/rf_auto_notify.R"))
                         isTRUE(rf_auto_notify(BID, .tn, kind = "block", delayed = TRUE)) },
                       error = function(e) { jlog("telegram_failed", phase = "boundary_backfill", err = conditionMessage(e)); FALSE })
      jlog("telegram_block", n = .tn, sent = .okB, base_id = BID, block = .tb, phase = "boundary_backfill")
    }
  }
  if (.bb_g2) { led <- rf_load(1L, ROOT); E <- Filter(function(e) identical(e$base_id, BID), led$entries)[[1]] }
}, error = function(e) jlog("boundary_backfill_failed", base_id = BID, err = conditionMessage(e)))
.drift <- tryCatch({
  if (!exists("rfbb_design_drift", mode = "function"))
    suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_boundary_backfill.R"), local = TRUE))
  rfbb_design_drift(ROOT, BID, .blk_design) }, error = function(e) { jlog("design_drift_check_failed", err = conditionMessage(e)); character(0) })
if (length(.drift)) {
  jlog("tick_closed_design_drift", base_id = BID, blocks = paste(.drift, collapse = ","),
       note = "tick 도중 설계 파일이 바뀌었다(격자가 낡음) — 배치를 열지 않고 닫는다 · 다음 tick 이 파일에서 격자를 다시 만든다")
  return(0L)
}

## ★소진 루틴 하나 — 예산 소진(used >= MAXA)과 격자 소진(빈 칸 0 · 아래 halt_no_jobs 자리) 두 입구가 같은 출구를 쓴다.
##   구판은 퇴역된 reinforce_auto_run.R 에 위임했는데 그 파일은 안내문만 찍고 종료해 promo2 소진 → 승격이 조용히 실패했다.
##   퇴역 러너가 하던 루틴 그대로: exhaust_reached → status=exhausted(writer) → entry_exhausted → next_paper(동기).
.exhaust_and_delegate <- function(why) {
  # ★Windows 에서 system2(env=) 는 무시된다(실측 2026-08-30: 자식이 로그 한 줄도 안 남겼다).
  #   부모 환경에 심어 자식이 상속하게 한다.
  Sys.setenv(QVEST_RF_CLAIM_HELD = "1")
  on.exit(Sys.unsetenv("QVEST_RF_CLAIM_HELD"), add = TRUE)
  jlog("exhaust_reached", base_id = BID, used = used, why = why)
  tryCatch(rf_exhaust_entry(1L, BID, root = ROOT),
           error = function(e) jlog("exhaust_mark_failed", base_id = BID, err = conditionMessage(e)))
  jlog("entry_exhausted", base_id = BID)
  ## ★wait=TRUE — 부모가 먼저 끝나면 자식이 함께 죽어 이월이 조용히 안 된다(2026-08-30 실사고).
  system2("Rscript", shQuote(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_next_paper.R")),
          wait = TRUE)
  Sys.unsetenv("QVEST_RF_CLAIM_HELD"); 0L
}
if (!length(pending) && used >= MAXA) { jlog("halt_exhausted_delegate", used = used)
  return(.exhaust_and_delegate("budget")) }

# 기저 논문 — 전략의 출처. B1 등록부 셀(계열 맵에 없는 계열)과 B5 오버레이 셀의 근거로 쓴다.
# ★배치 선정보다 **앞에** 둔다 — B1 picker 가 fallback_paper 로 받아야 하기 때문이다.
.base_paper <- tryCatch({
  ap <- file.path(E$base_artifacts %||% "", "authoritative_remeasure.json")
  if (nzchar(ap) && file.exists(ap)) fromJSON(ap, simplifyVector = FALSE)$replication$source_paper else NULL
}, error = function(e) NULL)

# ── ★블록 순서 적응 (C층 · 도훈 승인 2026-09-03) ─────────────────────────────
#   실측 근거: B1 승자 port_t 1.578 위에 오버레이를 마지막에 얹자 다섯 칸이 -0.78~0.72 로 무너졌다.
#   구판 순서는 **오버레이 없는 구성**을 최적화한 뒤 위험 통제를 나중에 붙인다 —
#   그런데 출하되는 구성에는 오버레이가 있다. 최적화 대상과 출하 대상이 어긋나 있었다.
#   규칙은 사전 선언(rf_block_order_decide)이고, 결정은 다음 배치 **전에** 원장에 한 번만 쓴다.
.blk_order <- as.character(E$block_order %||% character(0))
if (!length(.blk_order) && used >= 5L && !length(pending)) {
  .dec <- tryCatch({
    suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_lesson.R"), local = TRUE))
    rf_block_order_decide(E, PROG, root = ROOT)
  }, error = function(e) { jlog("block_order_decide_failed", err = conditionMessage(e)); NULL })
  if (!is.null(.dec) && length(.dec$order)) {
    ok_rec <- tryCatch({ rf_record_block_order(1L, BID, .dec$order, .dec$reason,
                                               adaptive = isTRUE(.dec$adaptive), root = ROOT); TRUE },
                       error = function(e) { jlog("block_order_record_failed", err = conditionMessage(e)); FALSE })
    if (isTRUE(ok_rec)) {
      .blk_order <- .dec$order
      jlog("block_order_decided", order = paste(.dec$order, collapse = ">"),
           adaptive = isTRUE(.dec$adaptive), reason = substr(.dec$reason, 1, 130))
    }
  }
}
if (length(.blk_order)) {
  # 안정 정렬 — 블록 안 칸 순서는 그대로. 소비된 B1 은 순서 1이라 자리를 지킨다.
  .bk  <- vapply(cells, function(c) as.character(c$block %||% ""), character(1))
  .rnk <- match(.bk, .blk_order); .rnk[is.na(.rnk)] <- 99L
  cells <- cells[order(.rnk, seq_along(cells))]
}

# ── ★블록 경계 강제: 같은 블록 안에서만 묶는다 (재개분이 없을 때만 신규 배치) ──
batch <- list(); first <- NULL
if (!length(pending) && used < length(cells)) {
  # ★커서는 개수가 아니라 **아직 자리가 빈 셀 코드**에서 뽑는다 (2026-09-04 · 정본 rf_spec_sig.R).
  #   구판 `cells[[used + 1L]]` 은 등록 거부 1건에 격자 위치가 영구히 어긋났다 —
  #   그 칸은 영영 안 재고 다른 칸이 두 번 탄다(실측 사연은 rf_spec_sig.R 주석).
  .free <- .rf_free_cells(cells, E$attempts)
  if (!length(.free)) { jlog("halt_no_free_cell", used = used,
                             taken = length(.rf_taken_codes(E$attempts, cells))); return(0L) }
  first <- cells[[.free[1]]]
  for (k in .free) {
    if (length(batch) >= NPAR) break
    if (!identical(cells[[k]]$block, first$block)) break
    batch[[length(batch) + 1L]] <- cells[[k]]
  }
  # ★예산 축이 둘이다 — 하루 상한과 25칸 상한. 상한을 넘겨 등록하면 원장이 거부하고,
  #   그 거부가 곧 격자 훼손이었다. 넘길 일을 애초에 만들지 않는다.
  room <- max(0L, min(DAILY_CAP - done_today, MAXA - used))
  if (length(batch) > room) batch <- batch[seq_len(room)]

# ★B1(멀티팩터) 칸도 격자에 박힌 값이 아니라 **등록부에서 배치 시점에 뽑는다**
#   (도훈 2026-09-01). 구판은 팩터 5종이 격자에 문자로 박혀 있어 **모든 논문이 같은 5팩터**를
#   썼다 — 331종을 등록해 두고 5종만 쓴 셈이다. 격자의 B1 cells 는 스냅샷일 뿐 정본이 아니다.
#   ★시드 오프셋 = 원장 누적 entry 수. 이게 없으면 그리디가 결정론이라 전 논문이 같은 사슬을
#     받아 총 조합이 entry 수와 무관하게 5개로 고정된다(계열 라운드로빈으로 회전).
# ★설계가 있으면 규칙 선정기를 부르지 않는다 — 두 선정이 겹치면 설계가 조용히 덮인다.
# ★통제 칸(P1-06)은 자리를 내주지 않는다 — 픽커는 **비상주 슬롯만** 채운다(B5 픽커와 같은 정본 rf_batch_open_slots). 통제 칸뿐인 배치는 픽커를 안 부른다.
.b1_slots <- if (length(batch)) rf_batch_open_slots(batch) else integer(0)
if (length(batch) && identical(first$block, "B1") && !length(.b1_design) && length(.b1_slots)) {
  .done_fsets <- unique(unlist(lapply(E$attempts, function(a) {
    sp <- a$essence$spec
    if (is.null(sp) || !nzchar(sp) || !file.exists(sp)) return(NULL)
    s0 <- tryCatch(fromJSON(sp, simplifyVector = FALSE), error = function(z) NULL)
    if (is.null(s0)) NULL else paste(sort(vapply(.rp_all_factors(s0),
      function(f) as.character(f$id %||% ""), character(1))), collapse = "+")
  })))
  .fp <- tryCatch({ suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_factor_arms.R")))
                    rf_pick_factor_sets(length(.b1_slots), exclude = .done_fsets %||% character(0),
                                        seed_offset = length(led$entries),
                                        depths = unlist(PROG$blocks[[1]]$depths %||% list()),
                                        fallback_paper = .base_paper, root = ROOT) },
                  error = function(e) { jlog("factor_pick_failed", err = conditionMessage(e)); NULL })
  if (!is.null(.fp) && length(.fp$cells)) {
    for (jj in seq_along(.b1_slots)) if (jj <= length(.fp$cells)) {
      j <- .b1_slots[jj]
      .c <- .fp$cells[[jj]]; .c$code <- batch[[j]]$code; .c$block <- "B1"; .c$axis <- "multifactor"
      batch[[j]] <- .c
    }
    jlog("factor_arms_picked", seed = .fp$seed_id, offset = .fp$seed_offset,
         chain = paste(.fp$picked_ids, collapse = ","), pool = .fp$n_available,
         max_rho = round(.fp$max_rho %||% NA_real_, 4), asof = .fp$substrate_asof,
         excl_no_ic = length(.fp$excluded_no_ic), excl_axis = length(.fp$excluded_axis))
    ## >>> O0a b1_factor_pick 기록 · 칸 출처(rule_factor + 선정기 selection_basis) — 기각 = 이미 측정·IC 없음·축 제외
    ## ★픽 칸 = 픽커가 채운 비상주 슬롯(.b1_slots · P1-06 통제 칸은 B1 머리에 standing 으로 남는다) — 위치 1..n 으로 세면 통제 칸에
    ##   rule_factor 가 찍히고 실제 픽 칸은 grid 로 남는다(10-03 시스템 렌즈 · probe_b1_provenance). .b1_slots 없는 판 = 구판 위치(1..n).
    .tl_b1s <- if (exists(".b1_slots", inherits = FALSE)) .b1_slots else seq_along(batch)
    .tl_b1s <- .tl_b1s[seq_len(min(length(.tl_b1s), length(.fp$cells)))]
    for (j in .tl_b1s) batch[[j]]$design_origin <- "rule_factor"
    if (exists(".tl_try", mode = "function")) .tl_try("b1_factor_pick", rf_tp_pick("b1_factor_pick", BID,
      vapply(batch[.tl_b1s], rf_tp_fset_key, character(1)),
      excluded = list("이미 측정한 팩터 집합" = .done_fsets, "IC 없음(as-of)" = .fp$excluded_no_ic, "축 제외" = .fp$excluded_axis),
      batch = batch, rule_src = "02_Infrastructure/ops/rf_factor_arms.R::rf_pick_factor_sets",
      scope = list(block = "B1", by = as.character(.fp$selection_basis %||% "")[1]), root = ROOT))
    ## <<< O0a
  } else {
    # ★P0-14 수리 2판(2026-09-25 · 적대검증 PIT B1) 격자 스냅샷 폴백 = 전표본 선정 — 선정 기저를 칸에 싣는다(아래 SPEC 부기가 옮긴다).
    #   격자 B1 cells 는 구판 규칙 선정기의 스냅샷이다(basis '… substrate 2026-07-31' · reinforce_program.json B1.selection_asof.note
    #   "구판 = 전기간 |ic_all|·전기간 상관"). 필드 없이 돌면 A 관문이 as-of 미증명으로만 보고 자기 표식을 내지 않아 스냅샷 접두 집합
    #   ({D42}…{D42,SE02,L38,Q18})의 칸과 그 승격 자식이 A 를 통과했다(운영 로그 2026-09-03 10:10 폴백 1건 = RP_20260903_093807_combo).
    #   selection_asof = 스냅샷 substrate 일자(basis 에서 읽는다 · 없으면 grid_snapshot) — as-of 가 아니라 **선정에 쓴 표본의 끝**이다.
    for (.j in seq_along(batch)) {
      if (isTRUE(batch[[.j]]$standing)) next   # ★P1-06 통제 칸은 격자 스냅샷 칸이 아니다 — 선정 기저 표식을 싣지 않는다
      .bs <- as.character(batch[[.j]]$basis %||% "")[1]; if (is.na(.bs)) .bs <- ""
      .sa <- regmatches(.bs, regexpr("substrate [0-9]{4}-[0-9]{2}-[0-9]{2}", .bs))
      batch[[.j]]$selection_basis <- "full_sample_ic"
      batch[[.j]]$selection_asof <- if (length(.sa)) sub("^substrate ", "", .sa) else "grid_snapshot"
    }
    jlog("factor_arms_fallback", note = "picker 미산출 — 격자 스냅샷 셀로 진행(측정은 계속된다) · selection_basis=full_sample_ic(A 보류)",
         cells = paste(vapply(batch, function(c) as.character(c$code %||% "")[1], character(1)), collapse = ","))
    ## >>> O0a b1_factor_pick 기록(폴백) — 격자 스냅샷 = 전표본 선정(rule_full_ic)
    batch <- lapply(batch, function(c) { if (!isTRUE(c$standing)) c$design_origin <- "rule_factor_fallback"; c })   # 통제(상주) 칸은 격자 스냅샷 칸이 아니다(P1-06)
    if (exists(".tl_try", mode = "function")) .tl_try("b1_factor_pick", rf_tp_pick("b1_factor_pick", BID, vapply(Filter(function(c) !isTRUE(c$standing), batch), rf_tp_fset_key, character(1)),
      excluded = list("이미 측정한 팩터 집합" = .done_fsets), batch = batch,
      rule_src = "reinforce_program.json::B1 격자 스냅샷(picker 미산출 폴백 · selection_basis=full_sample_ic)",
      scope = list(block = "B1", by = "full_sample_ic"), root = ROOT))
    ## <<< O0a
  }
}

# ★B5(오버레이) 칸은 격자에 박힌 값이 아니라 **등록부에서 배치 시점에 뽑는다**
#   (도훈 2026-08-30 "오버레이 방법론을 특정하는건 별로인데"). 이미 측정한 팔은 제외하므로
#   승격 사슬·다음 논문에서 같은 다섯 개를 반복 측정하지 않는다. 격자의 B5 cells 는 스냅샷일 뿐이다.
if (length(batch) && identical(first$block, "B5") && is.null(.blk_design[["B5"]])) {
  # ★중첩(v10.2) 이후 overlay 는 단수 객체 또는 층 리스트다. 구판 s$overlay$arm_id 는
  #   리스트에서 NULL 을 내 제외 목록이 통째로 비고, 이미 측정한 팔이 다시 뽑힌다.
  .arm_ids <- .ov_arm_ids   # 정본 = rf_spec_sig.R
  .done_arms <- unique(c(
    unlist(lapply(E$attempts, function(a) {
      sp <- a$essence$spec
      if (is.null(sp) || !nzchar(sp) || !file.exists(sp)) return(NULL)
      s <- tryCatch(fromJSON(sp, simplifyVector = FALSE), error = function(z) NULL)
      if (is.null(s)) NULL else .arm_ids(s$overlay)
    })),
    # ★carry 에 이미 깔린 팔도 제외한다 — 같은 팔을 또 뽑으면 .ov_stack 이 중복을 지워
    #   그 칸이 무처치로 닫힌다(측정 0으로 칸 하나 소각).
    .arm_ids(E$carry$overlay),
    # ★상주 arm 도 뺀다 (2026-09-17 · WP-R) — 상주 칸(B5_31)이 자기 코드로 매 세대 이미 잰다(같은 팔 두 번 = 칸 소각).
    tryCatch(rfbd_standing_picks(ROOT), error = function(e) character(0))))
  .done_arms <- .done_arms[nzchar(.done_arms)]
  # ★상주 칸은 자리를 내주지 않는다 — 픽커는 **비상주 슬롯만** 채운다(정본 rf_runner_gates.R::rf_batch_open_slots).
  .slots <- rf_batch_open_slots(batch)
  .pk <- if (!length(.slots)) NULL else
         tryCatch({ suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_overlay_arms.R")))
                    rf_pick_overlay_arms(length(.slots), exclude = .done_arms %||% character(0), root = ROOT) },
                  error = function(e) { jlog("overlay_pick_failed", err = conditionMessage(e)); NULL })
  if (!is.null(.pk) && length(.pk$cells)) {
    for (j in seq_along(.slots)) if (j <= length(.pk$cells)) {
      .c <- .pk$cells[[j]]; .c$code <- batch[[.slots[j]]]$code; .c$block <- "B5"; .c$axis <- "risk_overlay"
      batch[[.slots[j]]] <- .c
    }
    jlog("overlay_arms_picked", ids = paste(.pk$picked_ids, collapse = ","),
         excluded = paste(.done_arms %||% character(0), collapse = ","),
         standing_slots = length(batch) - length(.slots))
    ## >>> O0a b5_overlay_pick 기록 · 칸 출처(rule_catalog) — 상주 슬롯은 standing 그대로 · 기각 = 이미 측정·carry·상주 arm
    for (j in seq_len(min(length(.slots), length(.pk$cells)))) batch[[.slots[j]]]$design_origin <- "rule_overlay"
    if (exists(".tl_try", mode = "function")) .tl_try("b5_overlay_pick", rf_tp_pick("b5_overlay_pick", BID, .pk$picked_ids[seq_len(min(length(.slots), length(.pk$cells)))],
      excluded = list("이미 측정·carry·상주 arm" = .done_arms), batch = batch,
      rule_src = "02_Infrastructure/ops/rf_overlay_arms.R::rf_pick_overlay_arms", scope = list(block = "B5"), root = ROOT))
    ## <<< O0a
  }
}
# ★B2(비중) 칸도 등록부에서 뽑는다 (2026-09-03). B1·B5 와 같은 형태 —
#   격자의 B2 cells 는 스냅샷일 뿐이고, 이미 측정한 label 은 제외해 반복 측정을 막는다.
#   구판은 이 호출이 아예 없어 카탈로그 52종이 격자에 한 번도 닿지 않았다.
if (length(batch) && identical(first$block, "B2") && is.null(.blk_design[["B2"]])) {
  .done_wt <- unique(unlist(lapply(E$attempts, function(a) {
    sp <- a$essence$spec
    if (is.null(sp) || !nzchar(sp) || !file.exists(sp)) return(NULL)
    s <- tryCatch(fromJSON(sp, simplifyVector = FALSE), error = function(z) NULL)
    if (is.null(s)) NULL else (s$weighting$label %||% s$weighting$catalog_id)
  })))
  .wk <- tryCatch({ suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_weight_arms.R")))
                    rf_pick_weight_arms(length(batch), exclude = .done_wt %||% character(0)) },
                  error = function(e) { jlog("weight_pick_failed", err = conditionMessage(e)); NULL })
  if (!is.null(.wk) && length(.wk$cells)) {
    for (j in seq_along(batch)) if (j <= length(.wk$cells)) {
      .c <- .wk$cells[[j]]; .c$code <- batch[[j]]$code; .c$block <- "B2"; .c$axis <- "weighting"
      batch[[j]] <- .c
    }
    jlog("weight_arms_picked",
         ids = paste(vapply(.wk$cells, function(c) as.character(c$weighting$label %||% ""), character(1)),
                     collapse = ","),
         excluded = paste(.done_wt %||% character(0), collapse = ","))
    ## >>> O0a b2_weight_pick 기록 · 칸 출처(rule_catalog) — 기각 = 이미 측정한 label
    for (j in seq_len(min(length(batch), length(.wk$cells)))) batch[[j]]$design_origin <- "rule_weight"
    if (exists(".tl_try", mode = "function")) .tl_try("b2_weight_pick", rf_tp_pick("b2_weight_pick", BID,
      vapply(.wk$cells[seq_len(min(length(batch), length(.wk$cells)))], function(c) as.character(c$weighting$label %||% c$weighting$catalog_id %||% "")[1], character(1)),
      excluded = list("이미 측정한 label" = .done_wt), batch = batch,
      rule_src = "02_Infrastructure/ops/rf_weight_arms.R::rf_pick_weight_arms", scope = list(block = "B2"), root = ROOT))
    ## <<< O0a
  }
}
  if (!length(batch)) { jlog("halt_no_room", room = room); return(0L) }
  jlog("batch_start", block = first$block, n_cells = length(batch),
       codes = paste(vapply(batch, function(c) c$code, character(1)), collapse = ","))
}

# ── 승자 해석 (배치 전체가 같은 승자 위에 선다) ───────────────────────────────
.metric <- function(a, key) { es <- a$essence
  if (is.list(es) && !is.null(es[[key]])) as.numeric(es[[key]]) else NA_real_ }
.cell_by_code <- function(cd) { k <- which(vapply(cells, function(c) identical(c$code, cd), logical(1)))
  if (length(k)) cells[[k[1]]] else NULL }
.winner_of <- function(bid, by = "port_t", gate = NULL) {
  idx <- which(vapply(cells, function(c) identical(c$block, bid), logical(1)))
  cand <- Filter(function(a) { if (is.null(a$essence)) return(FALSE); cd <- a$essence$cell_code
    if (!is.null(cd) && nzchar(cd)) startsWith(cd, paste0(bid, "_")) else (a$n %in% idx) }, E$attempts)
  if (exists(".tlw_note", mode = "function")) .tlw_note(bid, "c0", cand)   ## O0a 시행 로그 — 측정 후보
  # ★규약 혼합 가드 (2026-09-24 · P0-12 동반): 현행 측정 규약과 regime 이 다른 칸(rebase 전 legacy · C11 비편입 칸)은 승자 후보가
  #   아니다 — 한 argmax 에 두 규약의 PORT_t 를 섞지 않는다. 블록 승자는 규약만 본다(B3 승자의 유니버스는 처치 축이다 · RF_ROLE_CHECKS).
  cand <- rf_candidates_keep(cand, .RCTX, role = paste0("winner_", bid), log = jlog, base_id = BID)
  if (exists(".tlw_note", mode = "function")) .tlw_note(bid, "c1", cand)   ## O0a — 규약 자격 통과
  # ★소비 술어 (2026-09-17 · 적대검증 G2 · 2026-09-24 P0-11): 게이트가 있으면 통과한 시도만 승자 후보다 — pass, 또는 verdict 가 없는데
  #   자기 오버레이 층이 없는 칸만. 자기 층 B5 의 verdict 부재는 'unverified'(검증 전 = 소비 보류).
  #   fail/error/not_candidate/unverified 는 등급 불변 · **소비만 보류**(블록 승자·B4 바닥·carry 에서 제외). 제외는 로그로 드러낸다.
  if (!is.null(gate) && length(cand)) {
    .keep <- vapply(cand, gate, logical(1))
    for (a in cand[!.keep])
      jlog("winner_excluded_adversary", block = bid, n = a$n, code = a$essence$cell_code %||% "",
           verdict = as.character(rf_adversary_status(a)$status %||% ""),
           note = "적대검증 pass 아님(미검증 포함) — 블록 승자·B4 바닥에서 제외(등급 불변 · 소비 보류)")
    cand <- cand[.keep]
  }
  if (exists(".tlw_note", mode = "function")) .tlw_note(bid, "c2", cand)   ## O0a — 적대검증 소비 술어 통과
  if (!length(cand)) return(NULL)
  v <- vapply(cand, function(a) .metric(a, by), numeric(1)); if (all(is.na(v))) return(NULL)
  w <- cand[[which.max(replace(v, !is.finite(v), -Inf))]]; cd <- w$essence$cell_code
  if (exists(".tlw_note", mode = "function")) .tlw_note(bid, "win", list(w), v = v, by = by)   ## O0a — 선택(argmax · 판정 불변)
  # ★승자는 **측정된 spec 파일**에서 읽는다 — 격자에서 코드로 조회하면 안 된다(2026-09-01).
  #   B1·B5 셀은 이제 배치 시점에 등록부에서 뽑히므로 **격자에 존재하지 않는다**.
  #   격자를 조회하면 실제로 이긴 구성이 아니라 스냅샷 셀이 나오고, B2/B3/B4 가 이기지도 않은
  #   구성 위에 서게 된다. 격자를 손보는 순간 조용히 엇갈리는 것과 같은 계통의 병이다.
  #   spec 은 factors/weighting/universe/overlay/root_paper 를 그대로 들고 있어 드롭인이다.
  out <- NULL
  .sp <- w$essence$spec
  if (!is.null(.sp) && nzchar(.sp) && file.exists(.sp))
    out <- tryCatch(fromJSON(.sp, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(out) && !is.null(cd) && nzchar(cd)) out <- .cell_by_code(cd)   # 구 entry 폴백
  if (is.null(out) && w$n <= length(cells)) out <- cells[[w$n]]
  # 승자의 지표를 함께 실어 보낸다 — 채택 여부(기준선 초과)를 호출부가 판정할 수 있게.
  if (!is.null(out)) attr(out, "best_val") <- max(replace(v, !is.finite(v), -Inf))
  out
}

# ── ★carry 기준선 게이트 (도훈 지시 2026-08-31 "기준선 미달이면 carry 유지") ──
#   승계 entry 의 기준선은 **부모 승자 성능**이다. 블록 승자가 그걸 못 넘었다면 그 블록은
#   개선을 찾지 못한 것이고, 그런 승자를 다음 블록에 얹으면 뒤 블록 전체가 **더 나쁜 구성**
#   위에서 측정된다. 실측 2026-08-31: 기저 신호가 강한 논문에서 팩터를 하나 얹으면 등가중
#   컴포짓이 기저 가중을 1/2 -> 1/3 로 낮춰, B1 다섯 칸 어느 것도 기준선(2.63)을 못 넘었다
#   (최고 0.814). 그런데도 승자를 얹으면 B2~B4 가 전부 희석된 구성 위에서 돈다.
#   ★carry 가 없는 최초 entry 에는 기준선이 없다 — 항상 채택한다(게이트 무발화).
#   ★기준선은 **비교가 성립할 때만** 쓴다 (2026-09-24 · 규약 혼합 가드 · D2-08 · D-C · 정본 rf_runner_gates.R::rf_carry_base_info):
#     부모 승자 칸이 현행 규약 · k200_kq150(carry 는 유니버스를 리셋한다) · 창 허용 안이어야 한다. 아니면 NA(게이트 무발화) + 사유 로그 —
#     모르는 기준선으로 막지도, 섞인 기준선으로 통과시키지도 않는다(rebase 가 부모 값을 새 규약으로 바꾸면 다시 선다).
.carry_bi <- rf_carry_base_info(E, led$entries, .RCTX)
## ★P1-06: 같은 regime 의 carry 재현 칸(B1_0) PT 가 있고 E3 가 red 가 아니면 그것이 기준선이다(부모 시점 값 = 빈티지 혼합) —
##   정본 rf_runner_gates.R::rf_carry_base_resolve(재현 칸이 없거나 red 면 위 rf_carry_base_info 결과 그대로 · 반환 모양 동일).
.carry_bi <- rf_carry_base_resolve(E, led$entries, .RCTX, base = .carry_bi)
.carry_base <- .carry_bi$value
if (!is.null(E$carry) && !identical(.carry_bi$why, "ok"))
  jlog("carry_base_unavailable", base_id = BID, why = .carry_bi$why, parent = as.character((E$parent %||% list())$base_id %||% ""),
       recorded = suppressWarnings(as.numeric(E$parent$best_port_t %||% NA)),
       note = "carry 기준선 비교 불가 — 게이트 무발화(규약·유니버스·창이 현행과 다르다)")
.beats_carry <- function(w, tag) {
  if (is.null(w) || !is.finite(.carry_base)) return(TRUE)
  bv <- suppressWarnings(as.numeric(attr(w, "best_val") %||% NA))
  okv <- is.finite(bv) && bv > .carry_base
  if (!okv) jlog("winner_below_carry_base", block = tag, best_val = bv, carry_base = .carry_base,
                 note = "블록이 개선을 못 찾음 — 그 축은 carry 유지(승자 미채택)")
  okv
}
.blk <- if (!is.null(first)) first$block else "B4"   # 재개분은 스펙이 이미 있어 승자를 다시 안 쓴다
w1 <- if (!identical(.blk, "B1")) .winner_of("B1", "port_t") else NULL
if (!length(pending) && !identical(.blk, "B1") && is.null(w1)) {
  jlog("halt_no_b1_winner", block = .blk); return(1L) }
## ★B4 결합 입력 = 축 등록부(rf_spec_axes.R)의 소유 블록마다 승자 하나 (결정 B4-SIX-AXIS-AND-CARRY-AXES · 도훈 2026-09-26)
##   승자 기준 = 격자 blocks[].select_winner_by(하드코딩 금지 · 구판은 w2 = B2 port_t · w3 = B3 calmar · w5 = B5 calmar 를 여기 박았다 — 값은 격자와 같다).
##   구판은 B6·B7 승자를 아예 안 뽑아 B4 가 집행 주기·방어 슬리브 축을 영영 못 봤다. B1 은 위 w1 을 그대로 쓴다(중복 판정·중복 로그 금지).
##   ★대조 칸(격자 control 태그 — P1-06 B1_0·B1_N* · B7_40 무신호 · B7_41 부호 반전)은 .winner_of 의 rf_candidates_keep 이 뺀다(rf_candidate_facts →
##     control_cell · 정본 rf_runner_gates.R::rf_is_control). 7308 실측: 빼지 않으면 B7 승자(calmar)가 부호 반전 대조 B7_41(0.247 > B7_37 0.246)이다.
# ★B5 승자의 오버레이 — .winner_of 가 이미 승자의 spec 을 돌려주므로 그 안의 overlay 를 쓴다.
#   (격자 B5 cells 는 스냅샷이라 실제로 돈 arm 과 다를 수 있다 — 승자 기준 = calmar,
#    오버레이의 목적이 낙폭이기 때문이다. 격자 B5.select_winner_by 와 정합.)
#   ★적대검증 게이트 (2026-09-17 · G2): pass 또는 verdict 부재(구 attempt)만 승자 후보. 전부 탈락이면 B5 승자 없음 —
#     B4 의 'B5 포함' 칸은 carry 오버레이(부모 위험통제)만 깐다(승자 없음 ≠ 부모 통제 해제 · LOO 대조 보존 · 등록부 b4_base = carry).
#   ★게이트는 전 블록 공통으로 건다 — 적대검증 verdict 는 B5 칸에만 붙는다(rf_overlay_adversary_run 블록 패턴) → 다른 블록 승자는 구판과 같다.
.b4_win <- rf_axes_block_winners(PROG, function(b, by) if (identical(b, "B1")) w1 else .winner_of(b, by, gate = rf_adversary_ok))
if (length(attr(.b4_win, "missing_blocks")))
  jlog("b4_axis_block_missing", base_id = BID, blocks = paste(attr(.b4_win, "missing_blocks"), collapse = ","),
       note = "격자에 블록·승자 기준이 없다 — 그 축은 B4 에서 승자 없음(b4_base)으로 돈다")

# 승자의 팩터 축을 집합으로 정규화 — 등록부 셀은 factors(복수), 구 격자 셀은 factor2(단수)
.win_factors <- function(w) {
  if (is.null(w)) return(NULL)
  if (!is.null(w$factors) && length(w$factors)) return(w$factors)
  if (!is.null(w$factor2)) return(list(w$factor2))
  NULL
}

# ★B5(오버레이)는 블록 승자가 아니라 **지금까지의 전체 최고 구성** 위에 얹는 층이다.
#   격자 셀은 자기가 바꾼 축만 들고 있으므로(예: B3_12 는 universe 만) 승자의 **실제 스펙 파일**을
#   읽어 그대로 깐다 — 그래야 "그 전략에 오버레이를 얹었을 때" 를 재는 것이 된다.
.wbest_spec <- NULL
.wbest_code <- NA_character_   # ★바닥 attempt 의 코드 — B5 스펙 floor_code(적대검증 바닥 식별 1순위 · 2026-09-17)
.wbest_val  <- NA_real_        # ★바닥 칸의 PORT_t — P0-10 carry 게이트가 읽는다(2026-09-24)
.wbest_src  <- "none"          # ★바닥 출처 — "attempt"(entry 안 자격 칸) | "carry"(P0-10 고정) | "none"
{ .cd0 <- Filter(function(a) !is.null(a$essence), E$attempts)
  if (exists(".tlw_note", mode = "function")) .tlw_note("floor", "c0", .cd0)   ## O0a 시행 로그 — 바닥 측정 후보
  # ★바닥 후보 자격 (2026-09-24 · 규약 혼합 가드 · P0-12 D2-08 · D-C): 현행 규약 칸만 · spec.universe == k200_kq150 만 ·
  #   창 허용(12개월 · D-C) 안만. 구판은 B3 처치 유니버스(KQ150 단독 · 2010~) 칸이 PORT_t 최고면 그 유니버스가 B5·B6·B7 바닥으로
  #   **승계**됐다(감사 P0-02 실측: B5 칸 보유 99.6% 비멤버). 제외는 역할당 로그 1줄(candidates_excluded role=floor).
  .cd0 <- rf_candidates_keep(.cd0, .RCTX, role = "floor", log = jlog, base_id = BID)
  if (exists(".tlw_note", mode = "function")) .tlw_note("floor", "c1", .cd0)   ## O0a — 바닥 자격(규약·유니버스·창) 통과
  # ★바닥도 적대검증 판정을 따른다 (2026-09-17 · WP-R 사후 지적). 판정 fail/error/not_candidate 인 B5 칸이
  #   PORT_t 최고면 그 오버레이가 뒤 블록(B2·B3)의 바닥으로 **승계**돼 소비 보류가 새어 나갔다 — 승자·carry·A 후보만
  #   막고 누적 바닥은 안 막은 비대칭. ★P0-11(2026-09-24): verdict 가 없어도 자기 층 B5 칸이면 'unverified' 로 제외한다
  #   (구판은 부재 = 통과였다). 자기 층이 없는 칸(B1~B4·B6·B7)은 그대로 후보다(rf_adversary_ok).
  .cd0_all <- .cd0
  .cd0 <- Filter(rf_adversary_ok, .cd0)
  if (exists(".tlw_note", mode = "function")) .tlw_note("floor", "c2", .cd0)   ## O0a — 적대검증 소비 술어 통과
  if (length(.cd0_all) > length(.cd0)) {
    .va <- vapply(.cd0_all, function(a) .metric(a, "port_t"), numeric(1))
    .ba <- .cd0_all[[which.max(replace(.va, !is.finite(.va), -Inf))]]
    if (!rf_adversary_ok(.ba))
      jlog("floor_excluded_adversary", base_id = BID, n = .ba$n, code = .ba$essence$cell_code %||% "",
           verdict = as.character(rf_adversary_status(.ba)$status %||% ""),
           note = "PORT_t 최고였지만 적대검증 미통과(미검증 포함) — 누적 바닥에서 제외(오버레이 승계 차단)")
  }
  if (length(.cd0)) {
    .v0 <- vapply(.cd0, function(a) .metric(a, "port_t"), numeric(1))
    if (!all(is.na(.v0))) {
      .w0 <- .cd0[[which.max(replace(.v0, !is.finite(.v0), -Inf))]]
      if (exists(".tlw_note", mode = "function")) .tlw_note("floor", "win", list(.w0), v = .v0, by = "port_t")   ## O0a — 바닥 선택(argmax · 판정 불변)
      .sp0 <- .w0$essence$spec
      if (!is.null(.sp0) && nzchar(.sp0) && file.exists(.sp0)) {
        .wbest_spec <- tryCatch(fromJSON(.sp0, simplifyVector = FALSE), error = function(e) NULL)
        if (!is.null(.wbest_spec)) { .wbest_code <- .rf_attempt_code(.w0, cells)
          .wbest_val <- max(replace(.v0, !is.finite(.v0), -Inf)); .wbest_src <- "attempt" }
      }
    } } }
## ── ★P0-10 carry 기준선 게이트 — **바닥**에도 건다 (2026-09-24 · 감사 D2-05 · 정본 rf_runner_gates.R::rf_floor_carry_gate) ────
##   구판은 B1 승자에만 게이트를 걸었다(아래 SPEC factors: 실패 → NULL). 그런데 block_accumulate 가 비운 factors 를 .wbest_spec
##   (entry 안 PORT_t 최대 — carry 는 후보가 아니다)으로 다시 채워, 게이트에 떨어진 **바로 그 승자**가 뒤 블록의 바닥이 됐다
##   (운영 로그 winner_below_carry_base 164건 · 14760 promo3: B1_3 3.133 < carry 3.589 인데 B5·B2·B3 가 carry 4팩터 + 3팩터 희석
##   구성 위에서 돌았고 프로그램 최고 Calmar 칸 B5_19 가 그 위에서 나왔다). 수리: 기준선이 성립하는데 바닥이 그것을 넘지 못하면
##   (또는 자격 칸이 없으면) 바닥 = carry 구성(E$carry — 유니버스 리셋·탈락 층 제거 후의 물려받은 구성 · source_spec 은 출처로만).
##   carry 를 가상 시도로 후보 집합에 넣지 않는다(비평 권고 6 — .carry_base 는 부모 시점 값이라 승자·A·승격 후보로 새면 빈티지가 섞인다).
.wbest_gate <- rf_floor_carry_gate(.wbest_spec, .wbest_val, E$carry, .carry_base)
if (isTRUE(.wbest_gate$use_carry)) {
  # 로그는 바닥을 실제로 소비하는 배치(B1·B4 밖 신규 배치)에서만 — B1 배치·재개 tick 마다 같은 줄을 찍지 않는다
  if (!is.null(first) && !(as.character(first$block %||% "") %in% c("B1", "B4")))
    jlog("floor_fixed_to_carry", base_id = BID, block = as.character(first$block %||% ""), why = .wbest_gate$why,
         floor_code = .wbest_code, floor_val = .wbest_val, carry_base = .carry_base,
         carry_cell = as.character(E$carry$source_cell %||% ""), carry_factors = length(E$carry$factors %||% list()),
         note = "바닥이 carry 기준선을 못 넘음 — 바닥 = carry 구성(P0-10 · 미달 승자 위 누적 금지)")
  .wbest_spec <- .wbest_gate$spec; .wbest_code <- NA_character_; .wbest_src <- "carry"
}

# ── ★arm × 유니버스 양립성 관문 — 등록·재개 **두 경로가 같은 함수** (2026-09-13) ──────────
#   실사고 2002.06975 promo3: B4_21/22/25 의 lean:hrp × KQ150 은 첫 조우라 등록 시점 장부에 기록이 없었다.
#   엔진이 커버리지로 끊은 뒤 **재개 경로는 장부를 안 읽고** 같은 spec 을 다시 돌려 두 번째 실패 = terminal
#   로 닫힐 참이었다. 강등 규칙이 있어도 재개가 안 부르면 첫 조우 칸에는 출구가 없다(이월 경로가 둘이면
#   표식도 둘이 같아야 한다). 판정·기록 순서의 정본은 rf_arm_compat::rac_gate_apply — 여기는 부작용을 주입만 한다.
#   @return "run" | "closed"   (강등이면 spec 파일을 고쳐 쓰고 carry_degraded 를 로그에 남긴다)
.rac_gate_apply <- function(spec, sp, CELL, n, path) {
  ok <- tryCatch({ suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_arm_compat.R"), local = TRUE))
                   TRUE },
                 error = function(e) { jlog("arm_compat_gate_failed", code = CELL$code, path = path,
                                            err = conditionMessage(e)); FALSE })
  if (!ok) return("run")   # 관문 고장은 차단 사유가 아니다 — 엔진 가드가 최종선이다(구판 거동과 동일)
  rac_gate_apply(spec, sp, CELL, n, path, cells = cells, root = ROOT,
                 record_fn = function(n, ...) rf_record_result(1L, BID, n, ..., root = ROOT),
                 log_fn = jlog)
}

# ── ①-0 재개 검사: 등록됐으나 essence 없는 칸이 있으면 **그 칸부터 다시 실행**한다 ──
#   병렬은 등록 → 실행 순서라 실행이 실패하면 칸이 측정 없이 소비된다.
#   재개가 없으면 무인 상태에서 실패 1회 = 칸 영구 소실 (2026-08-30 실사고).
jobs <- list()
if (length(pending)) {
  jlog("resume_pending", n_pending = length(pending),
       ns = paste(vapply(pending, function(a) as.character(a$n), character(1)), collapse = ","))
  for (a in pending) {
    ## ★코드로 찾는다 — 정본 rf_spec_sig.R::rf_resume_cell (2026-09-05). 구판은 essence 없는 실패 칸을
    ##   cells[[a$n]] 위치로 떨어뜨려, B3 설계 4칸(cells 24개)에서 n=21→B4_22 · n=25→NULL 로 밀렸다.
    .rc <- rf_resume_cell(a, cells, .cell_by_code)
    CELL <- .rc$cell
    if (identical(.rc$how, "positional_legacy")) jlog("resume_positional_fallback", n = a$n, code = CELL$code %||% "",
         note = "attempt 에 cell_code 가 없어 위치로 찾았다 — 구 entry 호환 폴백")
    if (is.null(CELL)) { jlog("resume_skip_unknown_cell", n = a$n, how = .rc$how); next }
    # entry 별 spec 이 정본. 구 이름(spec_<code>.json)은 이 수리 이전 entry 호환용 폴백이다.
    sp <- file.path(WDIR, sprintf("spec_%s__%s.json", CELL$code, substr(BID, 1, 48)))
    if (!file.exists(sp)) sp <- file.path(WDIR, sprintf("spec_%s.json", CELL$code))
    if (!file.exists(sp)) { jlog("resume_skip_no_spec", n = a$n, code = CELL$code); next }
    ## ★재개도 양립성 관문을 지난다 (2026-09-13) — 첫 조우 커버리지 실패는 ③이 장부에 적은 뒤 여기서 강등된다.
    .rsp <- tryCatch(fromJSON(sp, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(.rsp) && identical(.rac_gate_apply(.rsp, sp, CELL, as.integer(a$n), "resume"), "closed")) next
    jobs[[length(jobs) + 1L]] <- list(n = as.integer(a$n), code = CELL$code, spec = sp,
      name = sprintf("RF_PAR_%s_%s", CELL$code, gsub("[^A-Za-z0-9]", "", CELL$label)),
      out = file.path(WDIR, sprintf("result_%s.json", CELL$code)),
      resume = TRUE)   # ★재개분 표식 — 실행 절이 기존 결과 재사용 여부를 이 표식으로만 판단한다(신규 job 은 항상 재실행)
  }
  if (length(jobs) > NPAR) jobs <- jobs[seq_len(NPAR)]
}

# ── ① 사전 등록 (순차 — 원장 단독 접근). 재개분이 있으면 건너뛴다 ────────────
# ★이미 측정된 칸들의 서명. 새 칸이 여기 걸리면 같은 포트폴리오를 다시 재는 것이다.
.seen_sig <- list()
for (.a in E$attempts) {
  .sp <- .a$essence$spec
  if (is.null(.sp) || !nzchar(.sp) || !file.exists(.sp)) next
  .so <- tryCatch(fromJSON(.sp, simplifyVector = FALSE), error = function(z) NULL)
  # ★P1-06: 통제 칸의 서명은 등록하지 않는다 — 재현 칸 서명 = carry 서명이라 정규 칸이 그 결과를 승계하는 경로를 만들지 않는다.
  if (!is.null(.so) && !rf_control_exempt(.so)) .seen_sig[[.spec_sig(.so)]] <- .a$essence$cell_code %||% paste0("n", .a$n)
}
## ── ★시행 회계 (2026-09-23 · 강화 전수감사 D3-01 · 플랜 P0-01) ─────────────────────
##   구판은 모든 셀을 chain·n_trials=1 로 채점했다(run_paper_replication.R 하드코딩). 그러나 이 러너는 열거 격자에서
##   전기간 지표 argmax 로 승자·바닥·승격을 고른다 = sweep. 셀마다 **계보 누적 측정 시행수**를 spec 에 싣고
##   워커가 sweep 으로 넘긴다. 계보 = 이 entry + parent 사슬(승격 carry 가 부모 승자를 물려받으므로 부모의 선택도
##   이 칸의 선택 이력이다). 측정된 칸(essence$port_t 수치)만 센다 — 미측정(NA 종결)은 평가되지 않은 시행이다.
##   ★등록 시점 값이다(도착 순서 의존). A 판정의 최종 가족 N 재산출은 A 서류(플랜 P1-04)가 맡는다.
##   ★.spec_sig 는 명시 키만 보므로 이 필드는 서명을 바꾸지 않는다(rf_spec_sig.R:95-117).
##   판정 정본 = rf_runner_gates.R::rf_lineage_ids / rf_lineage_measured / rf_selection_accounting (순수 함수 · 검사 대상).
.lineage_ids <- rf_lineage_ids(led$entries, BID)
.n_measured_prior <- rf_lineage_measured(led$entries, .lineage_ids, exclude_codes = rf_control_codes(ROOT))   # ★P1-06 통제 칸은 시행이 아니다
## ★배치 균일 N (2026-09-23 적대 리뷰) — 한 배치의 칸은 같은 가족 크기로 채점한다(등록 순서 무관).
.n_batch_size <- length(batch)
.tl_nreg <- 0L   ## O0a — 이 tick 에 원장 등록된 칸 수(승자·바닥 결정 기록의 조건)
if (!length(jobs)) for (CELL in batch) {
  .no_treatment <- FALSE
  SPEC <- c(list(code = CELL$code, label = CELL$label, block = CELL$block,
               fixed_axes = PROG$fixed_axes,
               # ★기저 신호는 원장의 충실구현 engine_path 에서 물려받는다 — 논문이 바뀌면 기저도 바뀐다.
               #   경로가 없거나 파일이 없으면 mom_12_1 로 떨어진다(구 entry 하위호환).
               # ★entry 가 base_signal 을 명시하면 그것이 정본이다(결합 entry 는 engine_blend 로
               #   엔진 두 개를 물린다). 명시가 없을 때만 engine_path 하나로 떨어진다 —
               #   구판은 이 분기가 없어 결합 entry 가 단일 엔진으로 **조용히** 돌 뻔했다.
               base_signal = if (!is.null(E$base_signal)) E$base_signal else { .ep <- E$engine_path %||% ""
                 if (nzchar(.ep) && file.exists(.ep)) list(kind = "engine", path = .ep)
                 else list(kind = "mom_12_1") },
               # ★기저 가중 — 등가중이면 팩터 n개에서 논문신호가 1/(1+n) 로 떨어져 결합 깊이와
               #   기저 희석이 교락된다. 격자 fixed_axes 가 정본이고 엔진은 값이 없으면 등가중이다.
               base_weight = PROG$fixed_axes$base_weight,
               # ★팩터 축은 **집합**이다(2026-09-01). 등록부 셀은 factors(복수)를 들고 오고,
               #   구 격자 셀의 factor2(단수)는 길이 1 집합으로 정규화한다.
               factors = (if (!is.null(CELL$factors) && length(CELL$factors)) CELL$factors
                          else if (!is.null(CELL$factor2)) list(CELL$factor2)
                          else if (.beats_carry(w1, "B1")) .win_factors(w1) else NULL)),
            # ★교체 축(비중·유니버스·집행 주기·방어 슬리브 — 축 목록 = 등록부 rf_spec_axes.R · 2026-09-26)은 셀 값 그대로 · 없으면 등록부 default
            #   (비중 ew · 유니버스 k200_kq150 · 그 밖 키는 두고 값 NULL — 구판 list(…) 와 같은 키·순서). 빠지면 그 칸은 **조용한 무처치**가 된다
            #   (B6: 엔진이 월간 그대로 · B7: 알파 단독 — 처치 미전달). 구판은 네 축을 여기 리터럴로 적었다.
            rf_axes_cell_init(CELL))
  # ★P0-14(2026-09-25) 선정 기저 부기 — 규칙 선정기(rf_factor_arms.R::rf_pick_factor_sets) 칸만 selection_basis(asof_ic | full_sample_ic)·
  #   selection_asof 를 든다. A 자격 관문 재도출(rf_lineage_flags.R)이 as-of 로 고른 팩터를 오염 승계 판정에서 빼는 **유일한 증거 필드**다
  #   (없으면 as-of 미증명 = 보수 · 설계 레인 칸은 필드가 없다 · 격자 스냅샷 폴백 칸 = full_sample_ic — 위 factor_arms_fallback). 부기 필드 — .spec_sig 는 명시 키만 접으므로 서명 불변.
  if (!is.null(CELL[["selection_basis"]])) {
    SPEC$selection_basis <- CELL[["selection_basis"]]; SPEC$selection_asof <- CELL[["selection_asof"]]
  }
  # ★P1-06 통제 칸 부기(control · control_seed) — 후보 술어·A 관문의 영속 표식(격자에서 코드가 바뀌어도 남는다). .spec_sig 는 명시 키만 접으므로 서명 불변.
  if (rf_control_exempt(CELL)) { SPEC$control <- CELL[["control"]]; SPEC$control_seed <- CELL[["control_seed"]] }
  # ── ★블록 누적 — 실행 순서를 따라간다 (도훈 지시 2026-09-04) ────────────────
  #   구판은 B2·B3 가 **B1 승자만** 물었다. 블록 순서가 고정(B1→B2→B3→B5→B4)일 때는
  #   맞았지만, 교훈 재귀가 순서를 적응시키면서(2026-09-04 B5 를 2번째로) 전제가 깨졌다.
  #   실측: B5_18 이 Calmar 0.405 를 냈는데 그 다음에 돈 B2·B3 는 overlay=none 으로 돌았다 —
  #   **순서는 바뀌었는데 누적 규칙이 안 따라갔다.** 궤적이 언덕이 아니라 부채꼴이 된 이유다
  #   (블록 최고 1.454 → 1.163 → 1.472 → 1.147 → 1.167, 34칸 쓰고 첫 블록 대비 +0.018).
  #
  #   그래서 축 목록을 나열하지 않는다 — **지금까지 최고 구성**을 바닥으로 깔고 자기 축만 덮는다.
  #   순서가 또 바뀌어도 어긋나지 않는다(개수 대신 격자에서 재도출한 것과 같은 원리).
  #   ★정정(2026-09-24 · P0-10 · 감사 D2-05): 구판 주석은 "지금까지 최고이므로 더 나쁜 구성 위에 서는 일이 원리상 없다" 였다 — 틀렸다.
  #     '지금까지 최고' 는 **이 entry 안** 최고였고 carry(부모 승자)는 후보가 아니었다. 승계 entry 에서 B1 승자가 carry 기준선에
  #     못 미치면 위 factors 게이트가 NULL 로 비운 자리를 이 블록이 **그 미달 승자**로 다시 채웠다(로그 winner_below_carry_base 164건).
  #     이제 바닥 자체가 게이트를 지난다(위 .wbest_gate — 못 넘으면 바닥 = carry 구성). 바닥 후보는 현행 규약·k200_kq150·창 허용 칸만.
  #     기준은 port_t — Grade A 두 축 중 더 멀리 있는 쪽이다(1.47/2.95 vs 0.42/0.64).
  #     이 기본값을 뒤집을 근거는 설계 레인이 처방으로 낸다(예: 낙폭이 구속이면 Calmar 기준).
  #   ★구판의 `B3 는 weighting 을 EW 로 되돌린다` 줄은 여기서 폐기된다 — 그 줄이 B2 승자를
  #     매번 버렸다. 유니버스를 재려고 비중을 리셋하면 그건 통제가 아니라 누적 파괴다.
  .floor_axes <- character(0)   # ★이 칸에서 바닥이 값을 준 축 — 아래 carry 병합이 덮지 않는다(등록부 승계 순서 floor > carry)
  if (!(CELL$block %in% c("B1", "B4")) && !is.null(.wbest_spec)) {
    # ★축 목록 = 등록부(rf_spec_axes.R · 결정 B4-SIX-AXIS-AND-CARRY-AXES 2026-09-26) — 자기 축만 셀 값, 나머지는 바닥 · 팩터(union)는 비었을 때만.
    #   구판은 여기 여섯 축을 줄마다 적었다(09-21 B6·B7 은 여기만 갱신되고 carry 병합·B4 에는 빠졌다 — 같은 병). 등록부 함수는 전 축을
    #   정확 일치([[ ]])로 읽는다(2026-09-17 WP-R: `$overlay` 가 부분 일치로 overlay_cell 빈 리스트를 집던 사고).
    .acc <- rf_axes_accumulate(SPEC, .wbest_spec, CELL$block)
    SPEC <- .acc$spec; .own <- .acc$own; .floor_axes <- .acc$from_floor
    jlog("block_accumulate", code = CELL$code, own_axis = .own %||% "-",
         w = (SPEC$weighting$kind %||% "?"), u = (SPEC$universe$kind %||% "?"),
         ov = length(.ov_layers(SPEC$overlay)), floor = .wbest_src, floor_code = .wbest_code,
         f = length(SPEC$factors %||% list()),
         note = "직전까지 최고 구성을 바닥으로 — 순서 무관 누적(floor=carry 면 P0-10 게이트가 carry 구성으로 고정)")
    SPEC$floor_source <- .wbest_src   # ★부기 필드 — .spec_sig 는 명시 키만 접으므로 서명 불변
  } else if (identical(CELL$block, "B3") && is.null(.wbest_spec)) {
    SPEC$weighting <- list(kind = "ew")   # 측정이 아직 없을 때만 구판 기본값
  }
  if (identical(CELL$block, "B4")) {
    use <- unlist(CELL$combo$use)
    # ★B4 에는 carry 기준선 게이트를 걸지 않는다. 게이트의 취지는 "개선 못 찾은 승자를
    #   **다음 탐색의 바닥**으로 깔지 말라" 인데(B2·B3 가 B1 위에 서는 자리), B4 는 탐색이
    #   아니라 **분해**다 — 축을 합치고 하나씩 빼서 기여를 가른다. 승자가 기준선을 못
    #   넘었어도 합쳤을 때 어떤지가 이 블록이 재려는 값이다.
    #   ★2026-08-31 실사고: 게이트를 여기까지 걸었더니 아무것도 안 얹혀 네 칸이 같은 t(2.241)를 냈다.
    # ★2026-09-01 4축 → ★2026-09-26 6축(결정 B4-SIX-AXIS-AND-CARRY-AXES) — 축 목록 = 등록부(rf_spec_axes.R). 구판은 B1·B2·B3·B5 네 줄이었고
    #   09-21 신설 B6(집행 주기)·B7(방어 슬리브)이 빠져 결합이 두 축을 영영 못 봤다(빈 곳은 칸이 아니라 축 — 09-01 교훈의 재발).
    #   축마다: 소유 블록 ∈ use ∧ 승자 있음 → 승자의 그 축 값 / 아니면 등록부 b4_base(carry → default). ★B5 승자 스펙은 이미 carry 를 포함한
    #   중첩판이라 그대로 쓴다(이중 적용 없음) · B5 를 뺀 칸도 부모 오버레이는 기저로 남긴다(두 겹 처치 방지 — 그 원리를 전 축에 편다: 승격 entry 의
    #   비중 LOO 도 EW 가 아니라 carry 비중). 결합 칸 use 는 위 결합 칸 재도출(진단 모드 블록 제외)의 결과이고 계획은 스펙 combo_plan 에 남긴다.
    .b4a <- rf_axes_b4_assemble(SPEC, use, .b4_win, E$carry)
    SPEC <- .b4a$spec
    if (!is.null(CELL$combo_plan)) SPEC$combo_plan <- CELL$combo_plan   # ★부기 필드(동결 판정 원천 · .spec_sig 는 명시 키만 접으므로 서명 불변)
    jlog("b4_axes", code = CELL$code, use = paste(use, collapse = "+"),
         f = length(SPEC$factors %||% list()), w = SPEC$weighting$kind %||% "?",
         u = SPEC$universe$kind %||% "?", ov = rf_ov_txt(SPEC$overlay),   # ★스택도 전 층을 적는다(구판은 리스트면 "none")
         rb = as.character((SPEC[["rebalance"]] %||% list())$label %||% "none")[1],
         ds = as.character((SPEC[["defense_sleeve"]] %||% list())$kind %||% "none")[1],
         src = paste(sprintf("%s=%s", names(.b4a$src), .b4a$src), collapse = ","))
  }
  # ── ★승격 entry 의 carry 병합 (도훈 지시 2026-08-30 "B등급 이상 추가 강화") ──
  #   승격은 B+ 를 낸 승자 구성을 **기저로 물려받아** 그 위에서 25칸을 다시 탐색한다.
  #   기저 신호(engine_path)는 그대로다 — 바뀌는 것은 그 위에 깔린 팩터·비중·유니버스다.
  #   축 소유권: 자기 축을 탐색하는 블록은 carry 를 덮는다(B2=비중 · B3=유니버스),
  #   B4 는 **이 entry 안의 승자**를 조합하는 블록이라 carry 가 그 선택을 덮지 않는다.
  if (!is.null(E$carry)) {
    .cur <- SPEC$factors
    if (is.null(.cur)) {
      .cur <- list()
      if (!is.null(SPEC$factor2) && !identical(SPEC$factor2$kind, "none")) .cur <- c(.cur, list(SPEC$factor2))
      if (!is.null(SPEC$factor3)) .cur <- c(.cur, list(SPEC$factor3))
    }
    # ★중복 제거. 스코어는 rowMeans(zb, z1, z2, ...) 등가중이라 같은 팩터가 두 번 들어가면
    #   **기저 신호 가중이 조용히 깎인다**(1/2 -> 1/3). 실측 2026-08-31: 부모 B3_12
    #   factors=[Amihud] PORT_t 2.63 -> 자식 factors=[Amihud,Amihud] 2.251, 기저 캐시 md5 동일.
    #   승계가 물려받은 구성을 희석하면 promote 조건(부모 최고 초과)은 원리상 만족될 수 없다.
    SPEC$factors <- .dedup_factors(c(E$carry$factors %||% list(), .cur))
    SPEC$factor2 <- NULL; SPEC$factor3 <- NULL
    # ★비소유 축 carry 병합 — 축 목록 = 등록부(rf_spec_axes.R::rf_axes_carry_fill · 결정 B4-SIX-AXIS-AND-CARRY-AXES 2026-09-26).
    #   구판은 weighting·universe·overlay 세 줄이었다 — 09-21 신설 rebalance(B6)·defense_sleeve(B7)가 빠져 승격 entry 의 B1 칸(바닥 없는 칸)이
    #   carry 의 집행 주기·방어 슬리브를 벗고 돌았다(실사례 RP_20260913_084807_skipped_base_promo1 · carry = buffer_2x · B1_1..7 월간 리밸 ·
    #   P1-06 CTRL 실데이터 E3 fail_spec). ★2026-09-03 오버레이 승계 사연(자식 B1/B2/B3 가 부모 위험 통제를 벗고 돌았다)과 같은 병이다 —
    #   승계 목록에서 빠진 축은 없는 축이 된다. 자기 축은 셀 처치(B5 오버레이는 아래에서 **중첩**) · B4 는 조립이 carry 를 기저로 이미 넣었다.
    #   ★승계 순서(등록부 RF_AXES_INHERIT_ORDER · 권고 floor > carry): 바닥이 이미 준 축은 덮지 않는다. 구판은 여기서 바닥의 비중·오버레이를
    #     carry 로 덮어 승격 entry 의 B3 칸이 B2 승자 비중 없이 돌았다(원장 실측 720_promo1 B3 4칸 = carry lean:ivol · 바닥 B2_10 = lean:score_pure).
    #   순서 스위치 = config spec_axes.inherit_order(부재 = 권고 floor > carry · 구판 재현 = ["carry","floor"]) — 여기서 순수 함수로 해석한다
    #   (무효값 로그는 위 계약 절 ③이 tick 당 1회 · 이 자리는 등록 루프만 떼어 도는 검사에서도 CFG 없이 기본값으로 선다).
    SPEC <- rf_axes_carry_fill(SPEC, E$carry, CELL$block, from_floor = .floor_axes,
                               order = rf_axes_inherit_order(get0("CFG", ifnotfound = list()))$order)
  }
  # ★B5 오버레이 — 전체 최고 구성을 그대로 깔고 그 위에 노출 스케일만 얹는다
  if (identical(CELL$block, "B5")) {
    if (!is.null(.wbest_spec)) {
      SPEC$factors   <- .wbest_spec$factors
      SPEC$factor2   <- .wbest_spec$factor2
      SPEC$factor3   <- .wbest_spec$factor3
      SPEC$weighting <- .wbest_spec$weighting %||% list(kind = "ew")
      SPEC$universe  <- .wbest_spec$universe  %||% list(kind = "k200_kq150")
    }
    # ★중첩 — carry 의 오버레이를 지우지 않고 그 위에 이 칸의 arm 을 얹는다(v10.2).
    #   구판은 덮어쓰기라 부모가 낙폭을 30% 깎아 승격됐어도 자식 B5 는 그 30% 를 버리고
    #   처음부터 다시 깎았다. 노출은 곱으로 합성된다(rf_cell_engine .ov_compose).
    SPEC$overlay <- .ov_stack(E$carry$overlay, CELL$overlay)
    # ★자기 층·바닥 표식 (2026-09-17 · 적대검증 G2 소비): overlay_cell = 이 칸이 **직접 얹은** 층(엔진 층별 처치 가드 ·
    #   기전 지도·승격 carry·적대검증의 '자기 층' 정본) · floor_code = 이 칸이 깔린 바닥 attempt 의 코드(적대검증 바닥
    #   식별 1순위 · 서명 대조는 2순위). 둘 다 부기 필드다 — .spec_sig 는 factors/base_weight/weighting/universe/overlay/
    #   base_signal 만 접으므로 서명 불변(test_rf_runner_standing_adversary.R 이 실제 스펙으로 대조한다).
    SPEC$overlay_cell <- CELL$overlay
    if (!is.na(.wbest_code)) SPEC$floor_code <- .wbest_code
    # ★바닥 출처 부기 (2026-09-24 · P0-10) — carry 로 고정된 바닥은 이 entry 의 attempt 가 아니다(floor_code 없음). 적대검증 바닥 식별이
    #   서명·PORT_t 폴백으로 entry 칸을 잘못 짚지 않게 출처를 남긴다(부기 필드 — 서명 불변).
    SPEC$floor_source <- .wbest_src
    if (identical(.wbest_src, "carry")) SPEC$floor_carry_cell <- as.character(E$carry$source_cell %||% "")
    SPEC$overlay_basis <- CELL$basis %||% ""
    if (!is.null(.base_paper)) SPEC$root_paper <- .base_paper
  }
  # ★B1~B3·B6·B7 은 자기 층이 없다 — 오버레이는 전부 승계분(carry · block_accumulate 바닥)이다. 빈 리스트로 **명시**해
  #   하류(.ov_own_layers 의 'overlay − carry' 폴백)가 바닥의 B5 층을 이 칸의 처치로 오귀속하지 않게 한다.
  #   엔진은 overlay_cell 이 비면 층별 처치 가드를 승계 층에 걸지 않는다(합성 가드는 그대로 · rf_cell_engine .OV_OWN).
  #   ★대상 = 등록부의 stack 축(오버레이)이 아닌 축의 소유 블록(rf_axes_no_layer_blocks · 2026-09-26). 구판 목록(B1·B2·B3)에 09-21 신설 B6·B7 이
  #     빠져 바닥 B5 층이 집행 주기·슬리브 칸의 '자기 층'으로 오귀속됐다(엔진 층별 가드가 승계 층에 걸림 · 기전 지도 과대). B4 는 구판 그대로(표식 없음).
  if (CELL$block %in% rf_axes_no_layer_blocks()) SPEC$overlay_cell <- list()
  # ★무처치 판정은 **조립이 끝난 뒤** 한다. 구판은 carry 병합 블록 안에서 쟀는데,
  #   B5(오버레이)는 그 뒤에 overlay 를 붙이므로 판정 시점엔 팩터·비중·유니버스가 carry 와
  #   같아 전부 "무처치" 로 닫혔다 — 정작 처치인 오버레이가 아직 없을 때 판정한 것이다.
  #   2026-08-31 실사고: B5 다섯 칸이 측정 0건으로 소비돼 25 소진이 찍히고 다음 논문으로
  #   넘어갔다. 계기가 재려는 것(처치가 있나)이 아니라 재기 쉬운 것(그 시점 세 축)을 쟀다.
  #   ★overlay 는 carry 에 없는 축이므로, 오버레이가 붙은 칸은 자동으로 처치 있음이 된다.
  # ★P1-06: 통제 칸은 무처치 판정에서 뺀다 — carry 재현 칸은 정의상 carry 와 같다(여기서 닫히면 측정 0회 = E3 공허 통과).
  if (!is.null(E$carry) && !rf_control_exempt(CELL)) {
    # ★축 목록 = 등록부(rf_axes_same_as_carry · 2026-09-26) — 구판 여섯 줄(팩터 키 집합 · 비중·유니버스·오버레이·집행 주기·슬리브 .same_axis)과
    #   같은 식을 등록부 축마다 돈다. 축이 늘 때 여기서 빠지면 '그 축만 다른 칸'이 무처치로 닫힌다(측정 0회 소비 — 2026-08-31 B5 사고 모양).
    .no_treatment <- rf_axes_same_as_carry(SPEC, E$carry)
  }
  # ★근거 논문 (2026-09-02 수리). 구판의 폴백 사슬(셀 논문 → B1 승자 논문)은
  #   ①B1 이 시드 계열 논문 하나만 붙이고(사슬이 접두 집합 → 4계열 컴포짓 5칸 전부 Amihud 2002)
  #   ②B5 는 자체 논문이 없어 **B1 승자 논문을 차용**했다 — 낙폭 브레이크가 유동성 논문을 인용했고,
  #     위 B5 분기가 넣은 기저 논문(SPEC$root_paper <- .base_paper)은 여기서 덮어써져 죽은 코드였다.
  #   그래서 "같은 root_papers 3회 연속" WARN 이 20칸 연속 발화했다 — 표기 결함을 재고 있었다.
  #   현행: source_paper(단수) = **기저 논문**(이 entry 가 강화하는 논문 — 모든 셀은 그 변형이다).
  #         원장 root_papers(복수) = 기저 + 셀 자체 처치 논문(B2 비중·B3 유니버스) + 팩터 **전 계열** 논문
  #         (+ risk_overlay 는 method 항목 선두). 매핑 없는 계열은 버리지 않고 이름으로 남긴다.
  rp <- .base_paper %||% CELL$root_paper %||% w1$root_paper
  SPEC$root_paper <- rp
  .rpz <- tryCatch({
    if (!exists("rf_root_papers_for")) suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_factor_arms.R")))
    rf_root_papers_for(SPEC, base_paper = rp, cell_paper = CELL$root_paper, root = ROOT)
  }, error = function(e) { jlog("root_papers_failed", code = CELL$code, err = conditionMessage(e))
    list(papers = Filter(function(z) is.list(z) && nzchar(as.character(z$url %||% "")), list(rp, CELL$root_paper)),
         families = character(0), unmapped_families = character(0)) })
  .root_papers <- .rpz$papers
  if (identical(CELL$axis, "risk_overlay"))
    .root_papers <- c(list(list(method = CELL$basis %||% CELL$label, url = rp$url %||% "")), .root_papers)
  SPEC$root_papers <- .root_papers
  SPEC$root_paper_families <- .rpz$families
  SPEC$unmapped_families <- .rpz$unmapped_families
  if (length(.rpz$unmapped_families))
    jlog("root_paper_unmapped_family", code = CELL$code, families = paste(.rpz$unmapped_families, collapse = ","))
  # ★sprintf 영길이 붕괴 방어 (2026-09-03). 인자 하나가 NULL/character(0)/NA 면 sprintf 는
  #   경고 없이 character(0) 을 돌려주고, 그 값이 원장에 idea=[] 로 박힌다.
  #   모든 조각을 길이 1 문자열로 강제한 뒤에만 조립한다.
  .s1 <- function(x, alt = "?") {
    x <- suppressWarnings(as.character(x))
    if (!length(x) || is.na(x[[1L]]) || !nzchar(x[[1L]])) alt else x[[1L]]
  }
  SPEC$idea <- sprintf("[무인 병렬 %s] %s — %s/%s · factor2=%s · weighting=%s · universe=%s · overlay=%s",
                       .s1(CELL$code), .s1(CELL$label), .s1(CELL$block), .s1(CELL$axis),
                       .s1(SPEC$factor2$id %||% SPEC$factor2$kind, "none"),
                       .s1(SPEC$weighting$kind, "ew"), .s1(SPEC$universe$kind, "k200_kq150"),
                       .s1(rf_ov_txt(SPEC$overlay), "none"))   # ★오버레이 스택(a × b) — 원장 서술에 전 층이 남는다(2026-09-17)
  # ★지식 주입(착수 전 의무) — hypothesis_index 죽은 선례 + 직전 교훈. 차단 아님, 기록.
  SPEC <- tryCatch({ source(file.path(ROOT, "02_Infrastructure/ops/rf_preflight.R"))
                     rf_preflight(SPEC, BID) },
                   error = function(e) { jlog("preflight_failed", code = CELL$code, err = conditionMessage(e)); SPEC })
  .pf <- SPEC$preflight
  if (!is.null(.pf) && length(.pf$dead_precedents))
    jlog("preflight_dead_precedent", code = CELL$code,
         kw = paste(names(.pf$dead_precedents), collapse = ","),
         note = "죽은 선례 존재 — 실행은 진행(AX-000: 사실 기록이지 금지 목록 아님)")
  # ★spec 경로에 entry 식별자를 넣는다. 구판은 spec_<code>.json 고정이라 다음 entry 가
  #   같은 이름으로 덮어썼고, 원장이 그 경로를 가리키는 채로 **부모 스펙이 소실**됐다
  #   (2026-08-31: 부모 B3_12 의 spec 을 열면 자식 것이 나온다 — 사후 재현 불가).
  sp <- file.path(WDIR, sprintf("spec_%s__%s.json", CELL$code, substr(BID, 1, 48)))
  # ★등록이 먼저다 (2026-09-03). 구판은 spec 을 먼저 쓰고 등록을 시도해서, 거부된 칸의
  #   산출물이 디스크에 남았다(실측: spec 5 vs 원장 4 — 산출물만 보면 5칸을 돈 것처럼 보인다).
  #   원장이 정본이므로 원장에 없는 칸의 흔적을 남기지 않는다.
  ## O0a 칸 설계 출처(P1-02 · E3) — 조립 지점 표식에서 도출해 등록 시점에 원장 attempt$design 으로 박는다(판정 불변 · 실패 = unknown)
  .ds_cell <- if (!exists("rf_cell_design_source", mode = "function")) NULL else tryCatch(rf_cell_design_source(CELL, BID, ROOT),
                       error = function(e) list(code = as.character(CELL$code %||% "")[1], design_source = "unknown", design_lane = "error"))
  att <- tryCatch(rf_append_attempt(1L, BID, SPEC$idea, CELL$axis, .root_papers, wt_id = NULL, root = ROOT,
                                    unmapped_families = .rpz$unmapped_families,
                                    # ★실제 적재 여부를 넘긴다 — 상수 TRUE 는 거짓 기록이었다
                                    axiom_injected = isTRUE(SPEC$preflight$axiom_injected),
                                    # ★격자 좌표를 등록 시점에 박는다 — 커서의 정본(2026-09-04)
                                    cell_code = CELL$code, design = .ds_cell),
                  error = function(e) { jlog("append_failed", base_id = BID, code = CELL$code,
                                             err = conditionMessage(e)); NULL })
  if (is.null(att)) {
    unlink(sp, force = TRUE)
    # ★거부된 칸은 자리를 잃지 않는다 — 커서가 코드 집합 기반이라 다음 tick 에 다시 잡힌다.
    #   다만 같은 사유로 계속 거부되면 근면하게 제자리를 돌 뿐이므로 상한에서 멈춰 세운다.
    .afc <- .append_fail_count(CELL$code, BID)
    if (.afc >= MAX_RETRY) {
      jlog("halt_append_stuck", code = CELL$code, fails = .afc,
           note = "등록 반복 거부 — 조용히 건너뛰지 않는다. 거부 사유를 고치고 재개할 것")
      break
    }
    next
  }
  if (exists(".tl_nreg")) .tl_nreg <- .tl_nreg + 1L; if (exists(".tl_try", mode = "function")) .tl_try("cell_registered", rf_tp_cell_registered(BID, att$n, .ds_cell, CELL$block, ROOT))   ## O0a 시행 로그 — 등록된 칸(출처 포함)
  ## ── ★기전 회피 집행은 **등록 뒤** (2026-09-05 이동) ──────────────────────────────
  ##   실사고 09:14: 이 블록이 등록(att <- rf_append_attempt) 앞에 있어 att$n 을 미정의로
  ##   읽고 러너가 fatal 로 죽었다 — 8분마다 같은 자리에서 반복되는 결정론적 정지.
  ##   "예산은 쓰되 측정은 안 한다" 는 등록이 먼저라는 뜻이다. 건너뛴 칸은 spec 을 남기지 않는다.
  ## ── ★기전 회피 목록 집행 (2026-09-04) ──────────────────────────────────────
  ##   실측: avoid 를 읽는 코드가 rf_b1_design_lib.R 하나뿐이었다(B1 설계 프롬프트).
  ##   러너는 안 읽으므로 격자 기본 칸에는 **원리상 안 걸렸다** — 기전이 무엇을 쓰지
  ##   말라고 적든 그대로 돌았다(실사고: B3_11 KOSDAQ150 단독).
  ##   ★건너뛰는 것은 **측정 무효 사유**뿐이다. "성과가 나빴다" 는 금지 목록이 아니라
  ##     사실 기록이므로(AX-000) 그건 로그만 남기고 실행한다.
  .avoid_hit <- tryCatch({
    lcd <- file.path(ROOT, "stage_artifacts/l_code/reinforcement")
    fs2 <- list.files(lcd, pattern = "[.]json$", full.names = TRUE)
    ## ★부모 사슬을 함께 본다 — 승격이 **구성은 물려받는데 교훈은 안 물려받았다**.
    ##   실사고 2026-09-04 21:50: B3_11 회피가 부모(rescued_rulefast) L-code 에 있는데
    ##   promo1 것만 보느라 안 걸렸고, 그 칸이 두 번 돌아 terminal 이 됐다.
    ##   (같은 계통: "승계 목록에서 빠진 축은 없는 축이 된다" — 오버레이가 세대마다 리셋됐던 건)
    .chain <- BID
    { .e0 <- tryCatch(rf_load(1L, ROOT), error = function(e) NULL); .cur <- BID; .n <- 0L
      while (!is.null(.e0) && .n < 5L) {
        .k <- .rf_find(.e0, .cur); if (is.na(.k)) break
        .pp <- as.character((.e0$entries[[.k]]$parent %||% list())$base_id %||% "")
        if (!nzchar(.pp) || .pp %in% .chain) break
        .chain <- c(.chain, .pp); .cur <- .pp; .n <- .n + 1L
      } }
    fs2 <- fs2[vapply(basename(fs2), function(b)
                 any(startsWith(b, paste0("l_code_", .chain, "_B"))), logical(1))]
    hit <- NULL
    if (length(fs2)) {
      fs2 <- fs2[order(file.info(fs2)$mtime)]
      for (f2 in rev(fs2)) {
        L2 <- tryCatch(fromJSON(f2, simplifyVector = TRUE), error = function(e) NULL)
        av2 <- as.character(unlist((L2 %||% list())$avoid %||% list()))
        ## ★표적 판정은 rf_avoid.R 하나 (2026-09-05). 구판은 셀 코드가 문장 **어디에든** 나오면
        ##   표적으로 읽어, 조부모 B4 회피문("세 칸이 전부 B2_6 아래이고 … 생존편향")이 손자
        ##   B2_6(CDaR_LP · 설계 머리 칸)을 측정 무효로 잡았다 — 비교 기준으로 언급된 코드였다.
        ##   같은 문장의 "B3_13 이 대체한다" 도 표적으로 읽혀 **권고 칸**을 건너뛸 뻔했다.
        .at <- rf_avoid_target(av2, CELL$code)
        for (x in .at$noted)
          jlog("avoid_noted", code = CELL$code, why = substr(x, 1, 120),
               note = "기전 회피 목록에 있으나 **성과 사유** — 실행한다(AX-000: 사실 기록이지 금지 목록 아님)")
        if (!is.null(.at$hit)) { hit <- .at$hit; break }
      }
    }
    hit
  }, error = function(e) NULL)
  ## ★상주 칸은 회피 목록으로 건너뛰지 않는다 (2026-09-17 · WP-R) — 매 세대 재는 대조 칸이라 기전이 '쓰지 말 것' 이라
  ##   적어도 측정은 남긴다(AX-000: 사실 기록이지 금지 목록 아님). 무시했다는 사실은 로그로 드러낸다.
  if (!is.null(.avoid_hit) && isTRUE(CELL$standing)) {
    jlog("avoid_exempt_standing", n = att$n, code = CELL$code, why = substr(.avoid_hit, 1, 130),
         note = "상주 칸 — 회피 지정을 무시하고 측정한다(대조 칸은 매 세대 잰다)")
    .avoid_hit <- NULL
  }
  if (!is.null(.avoid_hit)) {
    rf_record_result(1L, BID, att$n, grade = "NA (미결 — 기전 회피: 측정 무효 사유)",
      lessons = sprintf("%s: 기전이 측정 무효 사유로 회피 지정 — %s",
                        CELL$code, substr(.avoid_hit, 1, 160)),
      terminal = TRUE,
      terminal_reason = sprintf("기전 회피 집행 — %s", substr(.avoid_hit, 1, 160)),
      root = ROOT)
    jlog("avoid_enforced", n = att$n, code = CELL$code, why = substr(.avoid_hit, 1, 130),
         note = "측정 무효 사유 — 예산은 쓰되 측정은 안 한다(결과가 무효라 재도 소용없다)")
    next
  }

  SPEC$selection_accounting <- rf_selection_accounting(.lineage_ids, .n_measured_prior, .n_batch_size)
  write(toJSON(SPEC, auto_unbox = TRUE, pretty = TRUE, null = "null"), sp)
  # ★중복 판정 — 배치 안 · entry 안 · **전 entry**(2026-09-03 확장) 세 층을 본다.
  #   먼저 온 칸 하나는 측정하고 나머지를 닫는다. 같은 포트폴리오에 다른 이름을 붙이지 않는다.
  #   전 entry 층을 넓힌 근거: 258 측정 중 고유 서명 230 — 28칸이 이미 잰 구성의 재측정이었고
  #   한 구성은 3개 entry 에 걸쳐 7회 반복됐다. 25칸 예산에서 그만큼이 그냥 날아간 것이다.
  .sig <- .spec_sig(SPEC)
  # ★P1-06 통제 칸 — 서명 dedup(배치·entry·전 entry 커버리지)·중복 승계 면제. 면제하지 않으면 재현 칸은 부모 서명과 같아 측정 0회로 닫힌다.
  .ctl_cell <- rf_control_exempt(CELL)
  .dup <- if (.ctl_cell) NULL else .seen_sig[[.sig]]
  if (is.null(.dup) && !isTRUE(.no_treatment) && !.ctl_cell) {
    .xh <- tryCatch({
      if (!exists(".COVIDX")) {
        suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_coverage.R"), local = TRUE))
        .COVIDX <<- rf_coverage_index(ROOT)
      }
      rf_coverage_find(.sig, .COVIDX, exclude_base = BID)
    }, error = function(e) { jlog("coverage_lookup_failed", err = conditionMessage(e)); NULL })
    if (!is.null(.xh) && nrow(.xh))
      .dup <- sprintf("%s/%s(전 entry · Grade %s)", .xh$base_id[1], .xh$cell_code[1], .xh$grade[1])
  }
  if (!isTRUE(.no_treatment) && !is.null(.dup)) {
    ## ★같은 entry 안의 중복이면 **기존 결과를 승계**한다 (도훈 지시 2026-09-04).
    ##   중복 판정은 옳다 — 같은 포트폴리오를 두 번 재지 않는다. 문제는 **답이 있는데
    ##   NA 로 남는 것**이었다: B4 전결합(=B3_11)과 유니버스 LOO(=B2_6)가 NA 로 끝나
    ##   35칸을 태운 결론(4축 LOO 표)을 사람이 손으로 재구성해야 했다.
    ##   ★뿌리는 설계 모순이다 — block_accumulate 가 앞 승자를 물려주므로 마지막 블록의
    ##     승자가 이미 전결합이고, B4 의 전결합 칸은 구조적으로 항상 중복이다.
    ##     여기서 승계하면 그 모순이 정보 손실로 바뀌지 않는다(측정은 여전히 0회).
    .prev_code <- if (!is.null(.seen_sig[[.sig]])) as.character(.seen_sig[[.sig]]) else NA_character_
    .prev_att <- NULL
    if (!is.na(.prev_code)) {
      .E9 <- tryCatch(rf_load(1L, ROOT), error = function(e) NULL)
      .i9 <- if (!is.null(.E9)) .rf_find(.E9, BID) else NA
      if (!is.na(.i9)) {
        .cands <- Filter(function(a) identical(as.character(a$cell_code %||% ""), .prev_code),
                         .E9$entries[[.i9]]$attempts %||% list())
        if (length(.cands)) .prev_att <- .cands[[length(.cands)]]
      }
    }
    if (!is.null(.prev_att) && !is.null(.prev_att$essence) &&
        is.finite(suppressWarnings(as.numeric(.prev_att$essence$port_t %||% NA)))) {
      rf_record_result(1L, BID, att$n,
        grade = as.character(.prev_att$grade %||% "NA (승계)"),
        essence = c(.prev_att$essence, list(inherited_from = .prev_code)),
        artifacts = .prev_att$artifacts,
        lessons = sprintf("%s: 스펙이 %s 과 동일 — 측정하지 않고 그 결과를 승계한다(같은 포트폴리오다). block_accumulate 아래서 결합 칸이 앞 블록 승자와 같아지는 것은 구조적이다.",
                          CELL$code, .prev_code),
        terminal = TRUE,
        terminal_reason = sprintf("스펙 중복(%s) — 측정 생략, 결과 승계", .prev_code),
        root = ROOT)
      jlog("cell_duplicate_inherited", n = att$n, code = CELL$code, same_as = .prev_code,
           grade = as.character(.prev_att$grade %||% ""),
           note = "같은 entry 안 중복 — 기존 결과 승계(측정 0회, 답은 남는다)")
      next
    }
    rf_record_result(1L, BID, att$n, grade = "NA (미결 — 기존 칸과 동일 스펙)",
      lessons = sprintf("%s: 스펙 서명이 %s 과 동일 — 같은 포트폴리오를 다시 재지 않는다", CELL$code, .dup),
      terminal = TRUE,
      terminal_reason = sprintf("스펙 중복(%s 와 동일) — factors=%s weighting=%s universe=%s overlay=%s",
        .dup, paste(.fkeys(SPEC$factors), collapse = "+"),
        SPEC$weighting$kind %||% "?", SPEC$universe$kind %||% "?", rf_ov_txt(SPEC$overlay)),
      root = ROOT)
    jlog("cell_duplicate_spec", n = att$n, code = CELL$code, same_as = .dup,
         note = "기존 칸과 스펙 동일 — 미결 종결(실행 안 함)")
    next
  }
  if (!.ctl_cell) .seen_sig[[.sig]] <- CELL$code
  if (isTRUE(.no_treatment)) {
    # 원장에는 칸이 남되(격자 번호 대응 유지) 측정은 없다. essence 가 없으므로
    # .winner_of 후보에서 자동으로 빠진다 — 무처치 칸이 승자가 되는 경로가 닫힌다.
    rf_record_result(1L, BID, att$n, grade = "NA (미결 — carry 와 동일·처치 미전달)",
      lessons = sprintf("%s: 중복 제거 후 구성이 carry 와 동일 — 같은 포트폴리오에 다른 이름을 붙이지 않는다", CELL$code),
      terminal = TRUE,
      terminal_reason = sprintf("무처치(carry 동일) — factors=%s weighting=%s universe=%s overlay=%s",
        paste(.fkeys(SPEC$factors), collapse = "+"), SPEC$weighting$kind %||% "?", SPEC$universe$kind %||% "?",
        rf_ov_txt(SPEC$overlay)),
      root = ROOT)
    jlog("cell_no_treatment", n = att$n, code = CELL$code,
         note = "carry 와 동일 — 미결 종결(실행 안 함)")
    next
  }
  # ── ★arm × 유니버스 양립성 사전 검사 (도훈 지시 ③ · 2026-09-04) ──
  #   실사고: 비중 arm entropy 가 KQ150 단독 위에서 커버리지 77%(<80%) 로 막혔다.
  #   엔진 가드는 옷게 발화했지만 **백테를 다 돌린 뒤**였고, 결정론이라 재시도까지 태웠다
  #   (3칸 × 2회). 같은 조합은 몇 번을 돌려도 같은 자리에서 죽는다.
  #   ⇒ 이미 막힌 적 있는 조합이면 스폰하지 않고 미결로 닫는다. 판정 근거는 **실행 기록**
  #     뿐이고 추정하지 않는다 — 첫 조합은 여전히 한 번 태운다(정직한 비용).
  ## ★승계 비중이 이 유니버스에서 불가면 칸을 닫지 않고 EW 로 강등해 측정한다 (2026-09-04 · B4 포함 2026-09-13).
  ##   판정 = rf_arm_compat::rac_gate (차단 → rac_degrade_plan → 강등 spec 재검사). 재개 경로와 같은 헬퍼다.
  ##   ⚠강등은 위 중복 판정 **뒤**에 일어난다 — B4 전결합이 강등되면 같은 배치의 '−비중' 칸과 같은 구성이
  ##     되어 두 칸 모두 측정된다(의도: 죽은 칸보다 측정된 중복 · loo_equivalent 가 동치를 명시한다).
  if (identical(.rac_gate_apply(SPEC, sp, CELL, att$n, "register"), "closed")) next
  jobs[[length(jobs) + 1L]] <- list(n = as.integer(att$n), code = CELL$code, spec = sp,
    name = sprintf("RF_PAR_%s_%s", CELL$code, gsub("[^A-Za-z0-9]", "", CELL$label)),
    out = file.path(WDIR, sprintf("result_%s.json", CELL$code)))
}
## >>> O0a 블록 승자·바닥 결정 기록 — 새 배치가 칸을 등록한 tick 에 1회(그 배치가 소비한 값 · 재개 tick·B1 배치는 소비 없음).
##   B4 = 이 배치 칸들의 combo.use 블록(축 등록부·격자 재도출 — 진단 모드 블록 제외) 승자를 조합한다 · 그 밖(B2·B3·B5·B6·B7) = B1 승자(팩터) + 누적 바닥(.wbest_spec · P0-10 게이트 뒤). 판정 불변.
##   ★존재 검사를 먼저(10-03 시스템 렌즈) — 등록 루프만 추출 실행하는 검사(test_rf_control_cells D5·D7·D9)에는 pending·.TLW 가 없다. 러너 main 안에서는 값 불변.
if (exists(".TLW") && exists(".tl_nreg") && !length(pending) && !is.null(first) && .tl_nreg > 0L && !identical(as.character(first$block %||% ""), "B1")) {
  .tcb <- as.character(first$block %||% "")
  ## ★B4 가 소비한 블록 = 이 배치 칸들의 combo.use 합집합(격자·축 등록부가 정본 · 하드코딩 금지 — 10-03 시스템 렌즈: B4-SIX(B6·B7 축 · 진단 B3 제외)에서 고정 목록은 기록을 틀리게 한다)
  .tl_b4use <- tryCatch(unique(as.character(unlist(lapply(batch, function(c) c$combo$use)))), error = function(e) character(0))
  ## ★고정 목록 폴백 없음(10-03 최종 통합 P5A) — combo.use 가 비면 틀린 블록을 기록하지 않고 사실만 남긴다(판정 불변).
  if (identical(.tcb, "B4") && !length(.tl_b4use)) jlog("trial_log_b4use_empty", base_id = BID, n_batch = length(batch),
                                                      note = "B4 배치 칸에 combo.use 가 없다 — 블록 승자 기록 생략")
  for (.twb in if (identical(.tcb, "B4")) .tl_b4use else "B1")
    if (exists(".tl_try", mode = "function")) .tl_try(paste0("block_winner_", .twb), rf_tp_winner(BID, .twb, if (exists(.twb, envir = .TLW, inherits = FALSE)) get(.twb, envir = .TLW) else NULL, .tcb, ROOT))
  if (!identical(.tcb, "B4"))
    if (exists(".tl_try", mode = "function")) .tl_try("floor", rf_tp_floor(BID, if (exists("floor", envir = .TLW, inherits = FALSE)) get("floor", envir = .TLW) else NULL,
                                 .wbest_src, .wbest_code, .wbest_gate$why %||% "", .tcb, ROOT))
}
## <<< O0a
if (!length(jobs)) {
  ## ★격자 소진 (2026-09-05 실사고): B1 설계 9칸으로 예산 25→29, B3 설계 4칸이라 격자 총합 28 → used 28 < 29 로
  ##   예산 소진이 영영 안 서고 매 tick halt_no_jobs — 승격·다음 논문 모두 정지(무동작이 대기로 보였다).
  ##   빈 칸이 없고 재개 대상도 없으면 예산이 남아도 소진이다(정본 rf_spec_sig.R::rf_grid_consumed — 커서와 같은 정의).
  if (isTRUE(rf_grid_consumed(cells, E$attempts))) {
    jlog("grid_consumed", base_id = BID, used = used, max_attempts = MAXA, n_cells = length(cells),
         note = "격자 전 칸 측정 완료 — 예산 미달이어도 소진 처리")
    return(.exhaust_and_delegate("grid"))
  }
  jlog("halt_no_jobs"); return(1L)
}

# ── ② 실행 (병렬 — 워커는 원장 미접근) ────────────────────────────────────────
for (j in jobs) {
  ## ★재개 job — **신뢰할 수 있는 기존 결과는 다시 재지 않는다** (2026-09-07 · 정본 rf_spec_sig.R::rf_result_reusable).
  ##   실사고 2026-09-05 23:14: 워커 5개 스폰 직후 절전으로 부모만 죽었는데(SCHED_S_TASK_TERMINATED) 워커 4개는
  ##   result_B2_{6,8,9,10}.json 을 정상 완료했다. 다음 tick 이 아래 unlink 로 그 파일을 지우고 5칸을 전부 재실행 —
  ##   8분 낭비 + 같은 칸의 중복 산출물·L-code. 조건(ok · 같은 칸 · 같은 spec · spec 보다 새것 · essence ·
  ##   artifacts/authoritative_remeasure.json 실재) 하나라도 어긋나면 현행대로 지우고 다시 돈다.
  ##   재사용한 결과는 ③ 수집 절이 평소대로 읽어 원장에 기록한다(워커 미스폰 · 대기 루프는 파일 존재로 곧장 통과).
  if (isTRUE(j$resume)) {
    .ru <- rf_result_reusable(j, ROOT)
    if (isTRUE(.ru$reuse)) {
      jlog("resume_reuse_result", n = j$n, code = j$code, artifacts = .ru$artifacts,
           note = "완료된 워커 결과 재사용 — 재측정 없이 수집 절로")
      next
    }
    jlog("resume_rerun", n = j$n, code = j$code, why = .ru$why)
  }
  unlink(j$out, force = TRUE)
  # ★stderr 는 파일명/TRUE/FALSE 만 받는다. "2>&1"(셸 관용구)을 넘기면 R 이 **파일명으로 해석**하고
  #   Windows 에서 '>' 는 부정 문자라 실행이 조용히 죽는다(2026-08-30 실사고 — 워커 4개 전부 미기동).
  .wlog <- file.path(WDIR, sprintf("log_%s.txt", j$code))
  system2("Rscript", c(shQuote(file.path(ROOT, "02_Infrastructure/ops/rf_cell_worker.R")),
                       shQuote(j$spec), j$n, shQuote(j$name), shQuote(j$out)),
          wait = FALSE, stdout = .wlog, stderr = .wlog)
  jlog("worker_spawn", n = j$n, code = j$code)
}
TIMEOUT_S <- as.integer(CFG$worker_timeout_sec %||% 5400L)
t0 <- Sys.time()
repeat {
  ndone <- sum(vapply(jobs, function(j) file.exists(j$out), logical(1)))
  if (ndone >= length(jobs)) break
  if (as.numeric(difftime(Sys.time(), t0, units = "secs")) > TIMEOUT_S) {
    jlog("worker_timeout", done = ndone, total = length(jobs)); break }
  Sys.sleep(20)
}

# ── ③ 결과 수집 (순차 — 원장 단독 접근) ──────────────────────────────────────
# ★fail_count 는 **지금 원장**에서 읽는다. main() 초입의 E 스냅샷은 신규 배치에서
#   등록(rf_append_attempt)보다 앞서 찍혀 그 칸을 아예 모른다 — 스냅샷을 뒤지면
#   재개분에서만 맞고 신규분에서는 subscript 오류로 배치 전체가 fatal 로 떨어진다.
.fail_count_of <- function(n) {
  e <- tryCatch(Filter(function(x) identical(x$base_id, BID), rf_load(1L, ROOT)$entries)[[1]],
                error = function(z) NULL)
  if (is.null(e)) return(0L)
  a <- Filter(function(x) identical(as.integer(x$n), as.integer(n)), e$attempts)
  if (!length(a)) 0L else as.integer(a[[1]]$fail_count %||% 0L)
}
## ── ★Grade A 발행 함수(.grade_a_enqueue)는 main 머리(entry 선택 직후)로 옮겼다 (2026-09-24 · P0-12) — tick 시작 재평가가
##   수집 루프보다 먼저 발행해야 해서다. 발행 경로 셋(수집 · B5 경계 · tick 시작)이 같은 함수를 쓴다(표식도 셋이 같다).
.held_a <- list()   # ★적대검증 보류 중인 A (이 tick) — 블록 경계에서 verdict 로 풀거나 막는다
nb <- 0L
for (j in jobs) {
  if (!file.exists(j$out)) {
    .fc0 <- .fail_count_of(j$n)
    .term <- (.fc0 + 1L) >= MAX_RETRY
    rf_record_result(1L, BID, j$n, grade = "NA (등급 미발행 — 병렬 워커 미완료/시간초과)",
                     lessons = sprintf("워커 산출 부재: %s (로그 %s)", j$out, file.path(WDIR, sprintf("log_%s.txt", j$code))),
                     terminal = .term,
                     terminal_reason = if (.term) sprintf("워커 산출 부재 %d회 연속 — 재시도 상한 %d 도달", .fc0 + 1L, MAX_RETRY) else NULL,
                     root = ROOT)
    jlog("cell_missing", n = j$n, code = j$code, fail_count = .fc0 + 1L, terminal = .term); next
  }
  R <- fromJSON(j$out, simplifyVector = FALSE)
  # ★리프레시 배리어 미측정 종료 (2026-09-24) — 워커가 셀 시작 대기 상한 뒤에도 잠금이 살아 있었거나 RAWDATA 적재 직후
  #   재판정에서 잠금을 보고 **측정 없이** 끝낸 칸이다. 실패가 아니라 미착수다: 원장에 등급·교훈·fail_count 를 쓰지 않는다
  #   (등록만 된 칸으로 남아 pending → 다음 tick 이 재개 · 시도 예산 무소모). F·NA 기록 금지 · 구조적 판정 경로 미진입.
  if (identical(as.character(R$deferred %||% ""), "refresh_lock")) {
    .rbd <- R$barrier %||% list()
    jlog("cell_deferred_refresh_lock", n = j$n, code = j$code, state = as.character(.rbd$state %||% ""),
         lock = as.character(.rbd$lock %||% ""), pid = as.character(.rbd$pid %||% ""),
         reason = as.character(.rbd$reason %||% ""), waited_s = R$waited_s %||% NA,
         note = "측정·등급 기록 없이 종료 — 등록 칸 유지, 다음 tick 재개(예산 무소모)")
    next
  }
  if (!isTRUE(R$ok)) {
    .err <- R$err %||% "?"
    # ★두 종류의 실패를 가른다. 재개는 하나에만 의미가 있다.
    #   ① 구조적(결정론) — rf_cell_engine 의 "측정 무효" 계열. 처치가 전달되지 않았거나
    #      기저가 그 변환을 지지하지 않는다. 스펙이 그대로면 재실행해도 같은 자리에서 죽는다.
    #      이건 실행 실패가 아니라 **판정**이다 — 미결(미측정)로 닫는다.
    #   ② 일시적 — 워커 미기동·시간초과·자원. 재개가 존재하는 이유. 단 무한은 아니다:
    #      같은 칸이 cell_max_retry 회 실패하면 닫는다(무한 루프는 침묵과 같다).
    .structural <- grepl("측정 무효|처치 미전달", .err)
    .fc0 <- .fail_count_of(j$n)
    .term <- .structural || (.fc0 + 1L) >= MAX_RETRY
    .reason <- if (.structural) sprintf("구조적 미결(결정론) — %s", .err)
               else sprintf("일시 실패 %d회 연속 — 재시도 상한 %d 도달: %s", .fc0 + 1L, MAX_RETRY, .err)
    rf_record_result(1L, BID, j$n,
                     grade = if (.structural) "NA (미결 — 처치 미전달·측정 무효)"
                             else "NA (등급 미발행 — 병렬 실행 실패)",
                     lessons = sprintf("%s 실패: %s", j$code, .err),
                     terminal = .term, terminal_reason = if (.term) .reason else NULL,
                     root = ROOT)
    # ★커버리지 실패를 장부에 남긴다 — 다음부터는 백테 전에 막힌다.
    #   다른 실패는 기록하지 않는다(과잉 차단 금지) — 엔진 메시지가 정본이다.
    if (grepl("커버리지", .err, fixed = TRUE))
      tryCatch({ suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_arm_compat.R"), local = TRUE))
                 .sp3 <- tryCatch(fromJSON(j$spec, simplifyVector = FALSE), error = function(e) NULL)
                 if (!is.null(.sp3)) rac_record(.sp3, "coverage_fail", ROOT,
                                                detail = substr(.err, 1, 160), cell = j$code) },
               error = function(e) jlog("arm_compat_record_failed", err = conditionMessage(e)))
    jlog("cell_error", n = j$n, code = j$code, err = .err,
         structural = .structural, fail_count = .fc0 + 1L, terminal = .term); next
  }
  es <- R$essence
  # ★교훈은 지표 되풀이가 아니라 **기전 서술**이다 (2026-09-03). essence 의 숫자를 그대로
  #   옮겨 적으면 한계 정보량이 0이고, 그게 무인 교훈 269건 중 247건(92%)의 상태였다.
  #   무엇이 막았고 carry 대비 위험·수익이 어느 쪽으로 더 움직였는지를 적는다 — LLM 불필요.
  .carry_es <- tryCatch({
    .cw <- Filter(function(a) is.list(a$essence) && !is.null(a$essence$port_t), E$attempts)
    if (length(.cw)) .cw[[length(.cw)]]$essence else NULL
  }, error = function(e) NULL)
  .lsn <- tryCatch({
    source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_lesson.R"))
    rf_lesson_text(j$code, R$grade, es, carry_es = .carry_es, root = ROOT)
  }, error = function(e) sprintf("[%s] Grade %s (기전 서술 생성 실패: %s)",
                                 j$code, R$grade, conditionMessage(e)))
  ## ★강등 표식을 원장 교훈 머리에도 (2026-09-13) — spec.carry_degraded 에만 있으면 원장·텔레그램 독자는
  ##   "전 요소 결합(4축)" 이 실제로는 비중을 EW 로 바꿔 잰 칸인 줄 모른다. 조용한 통과 금지.
  .cdg <- tryCatch(fromJSON(j$spec, simplifyVector = FALSE)$carry_degraded, error = function(e) NULL)
  if (is.list(.cdg)) .lsn <- tryCatch({
    suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_arm_compat.R"), local = TRUE))
    paste(rac_degrade_note(.cdg), .lsn) }, error = function(e) .lsn)
  .spJ <- tryCatch(fromJSON(j$spec, simplifyVector = FALSE), error = function(e) NULL)
  # ★고정 축 사후 검증 — 공리를 주입하는 대신 산출물에서 재도출해 확인한다(P0-02 재도출 정본 rf_preflight_verify_axes).
  #   ★2026-09-24: 원장 기록 **앞**으로 옮겼다(판정 불변 · 순서만) — A 자격 관문이 그 결과(라벨)를 읽고, 기록 호출이 관문 결과
  #   (graduate)를 받는다. spec 을 넘긴다 — B3 처치 유니버스(all_listed·size_band)는 위반이 아니라 라벨(universe_treatment:*)이다.
  .vf <- tryCatch({ source(file.path(ROOT, "02_Infrastructure/ops/rf_preflight.R"))
                    rf_preflight_verify_axes(file.path(R$artifacts, "authoritative_remeasure.json"),
                                             PROG$fixed_axes, spec = .spJ) },
                  error = function(e) list(ok = NA, note = conditionMessage(e)))
  # ── ★A 자격 관문 (P0-12 · 2026-09-24 · 정본 rf_runner_gates.R::rf_a_eligibility) ──────────────────────────────────────
  #   등급은 불변이다 — 관문은 **발행**(judge_request · grade_a_queue awaiting_judge · entry 졸업)만 가른다. 보류면
  #   rf_record_result(graduate = FALSE): 등급 A 는 그대로 적고 entry 는 active 로 남아 다음 tick 도 칸을 소비한다
  #   (구판은 A 를 적는 순간 graduated — 보류 동안 그 계보의 탐색이 멈췄다). 관문 오류 = 보류(fail-closed · gate_error).
  .elA <- NULL
  if (identical(R$grade, "A"))
    .elA <- .a_eval(list(n = j$n, cell_code = j$code, grade = "A", essence = es, artifacts = R$artifacts), .spJ, axes = .vf)
  rf_record_result(1L, BID, j$n, grade = R$grade, essence = es, artifacts = R$artifacts,
    lessons = .lsn, root = ROOT, graduate = is.null(.elA) || isTRUE(.elA$eligible))
  if (identical(.vf$ok, FALSE))
    jlog("AXIS_VIOLATION", n = j$n, code = j$code, violations = paste(.vf$violations, collapse = "; "))
  # ★장부 기록 — 통과한 (arm, universe) 조합을 남긴다. 실패만 모으면 장부가 금지 목록이 되고,
  #   금지 목록은 AX-000 위반이다. 성공도 같이 남겨야 "막힌 적 있다" 가 의미를 갖는다.
  tryCatch({ suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_arm_compat.R"), local = TRUE))
             .sp2 <- tryCatch(fromJSON(j$spec, simplifyVector = FALSE), error = function(e) NULL)
             if (!is.null(.sp2)) rac_record(.sp2, "ok", ROOT, detail = "cell_done", cell = j$code) },
           error = function(e) jlog("arm_compat_record_failed", err = conditionMessage(e)))
  jlog("cell_done", n = j$n, code = j$code, grade = R$grade,
       port_t = es$port_t, calmar = es$calmar, axes_ok = .vf$ok,
       axes_labels = paste(.vf$labels %||% character(0), collapse = ","), axes_holds = paste(.vf$holds %||% character(0), collapse = ","),
       artifacts = R$artifacts)
  nb <- nb + 1L
  if (identical(R$grade, "A")) {
    # ★A 발행/보류 — 관문(위 .elA)이 정한다(P0-12). 적대검증 보류(2026-09-17 · G2 · 구 rf_grade_a_hold)는 그 관문의
    #   adversary_unverified(자기 층) 성분으로 흡수됐다: 자기 오버레이 층을 가진 B5 칸의 A 는 반증(lag-1 · strict-PIT · 노출 짝지은
    #   placebo · 정적 등가)을 지나야 Judge 큐에 오른다 — 동월 누출로 낸 A 를 Judge 앞에 세우지 않는다.
    #   자기 층이 미검증이면 이 tick 의 B5 경계 블록(아래)이 적대검증을 돌리도록 .held_a 에 싣는다(verdict 로 재평가).
    .routed <- .a_route(j$n, j$code, R$artifacts, es, .elA, "collect")
    if (!isTRUE(.routed) && isTRUE(.elA$self_unverified)) {
      .held_a[[length(.held_a) + 1L]] <- list(n = j$n, code = j$code, artifacts = R$artifacts, essence = es)
      jlog("grade_a_hold_adversary", n = j$n, code = j$code,
           note = "B5 자기 층 A — 적대검증 pass 전엔 judge_request·grade_a_queue awaiting_judge 미발행(등급 불변)")
    }
  }
}

# ── ★P1-06 E3 · null 희석 요약 — 통제 칸이 이번 tick 배치·재개에 있었으면 1회 판정해 남긴다(기록만 · 차단 없음) ─────────────
#   판정 정본 = rf_runner_gates.R::rf_carry_replay_check(계열 대조 포함) · rf_null_dilution_values. 원장에서 다시 읽는다(방금 기록한 칸 포함).
#   red(측정 0회 종결 · 승계로 닫힘 · 스펙 불일치 · 같은 판본 불일치)는 carry_replay_e3 의 red=TRUE 로 드러난다 — 기준선은 부모 기록으로 떨어진다.
.ctl_codes_now <- unique(c(vapply(jobs, function(z) as.character(z$code %||% ""), character(1)),
                           vapply(batch, function(z) as.character(z$code %||% ""), character(1))))
if (length(intersect(.ctl_codes_now, c(.ctl_replay_codes, .ctl_null_codes)))) tryCatch({
  .LC <- rf_load(1L, ROOT); .EC <- Filter(function(e) identical(e$base_id, BID), .LC$entries)[[1]]
  if (length(intersect(.ctl_codes_now, .ctl_replay_codes))) {
    .e3 <- rf_carry_replay_check(.EC, .LC$entries, .RCTX, series = TRUE)
    .e3f <- .e3$facts %||% list()
    jlog("carry_replay_e3", base_id = BID, verdict = .e3$verdict, red = isTRUE(.e3$red), e3_strict = .e3$e3_strict,
         e3_history = .e3$e3_history, pt_replay = .e3f$pt_replay %||% NA, pt_ref = .e3f$pt_ref %||% NA, dpt = .e3f$dpt %||% NA,
         ref = as.character(.e3f$ref_code %||% ""), diff_axes = paste(.e3f$spec_diff_axes %||% character(0), collapse = ","),
         vintage = paste(c(.e3f$vintage_replay %||% "NA", .e3f$vintage_ref %||% "NA"), collapse = " vs "),
         series_max_dret = (.e3f$series %||% list())$max_abs_dret %||% NA, use_as_carry_base = isTRUE(.e3$use_as_carry_base),
         tol = .e3$tolerance, reasons = paste(.e3$reasons, collapse = " | "),
         note = "P1-06 E3 — carry 재현 칸 판정(기록만). red 면 기준선은 부모 기록 경로(rf_carry_base_info)로 떨어진다")
  }
  if (length(intersect(.ctl_codes_now, .ctl_null_codes))) {
    .nv <- rf_null_dilution_values(.EC, .RCTX, "port_t")
    .nd <- .nv$delta[is.finite(.nv$delta)]
    jlog("null_dilution_summary", base_id = BID, metric = "port_t", status = .nv$status, n_finite = .nv$n_finite,
         mean_delta = if (length(.nd)) mean(.nd) else NA, sd_delta = if (length(.nd) >= 2L) stats::sd(.nd) else NA,
         replay_value = .nv$replay$value, reasons = paste(.nv$reasons, collapse = " | "),
         note = "P1-06 null 희석 — 재현 칸 대비 PT 차(기술 요약 · SE 정본 = rf_prereg.R::rf_prereg_se_null)")
  }
}, error = function(e) jlog("control_e3_failed", base_id = BID, err = conditionMessage(e)))

# ── 텔레그램: 블록 경계를 넘었으면 1회 ────────────────────────────────────────
led2 <- rf_load(1L, ROOT)
E2 <- Filter(function(e) identical(e$base_id, BID), led2$entries)[[1]]
u2 <- as.integer(E2$attempts_used %||% 0L)
# ★조건에 `u2 > used` 를 걸면 **재개 경로에서 영영 안 나간다**(재개는 used 가 이미 최종값).
#   2026-08-30 실사고: 17~20 을 재개로 측정하고도 20/20 텔레그램이 0건이었다.
#   판정 축을 "칸 수가 늘었나" 가 아니라 "이번 배치가 실제로 기록했나(nb>0)" 로 바꾼다.
# ★블록 경계는 **격자에서 재도출**한다 (2026-09-04). 구판은 `u2 %% 5L == 0L` — 개수였다.
#   B1 이 설계에 따라 가변 길이가 된 순간 그 판정이 틀린다: 실측으로 B1 설계 14칸에서
#   5칸·10칸(블록 **한가운데**)에 쏘고 14칸(진짜 경계)에는 **안 쐈다** — 그 블록의 텔레그램과
#   L-code 가 통째로 증발했다. 격자 커서를 코드 기반으로 바꾼 것과 같은 병이 알림 층에 남아 있었다.
#   판정 축: "이 블록에 아직 빈 칸이 남았는가". 남지 않았으면 그게 경계다.
.blk_now <- if (!is.null(first)) as.character(first$block %||% "") else {
  .cc <- vapply(E2$attempts %||% list(),
                function(a) as.character(a$cell_code %||% (a$essence$cell_code %||% "")), character(1))
  .cc <- .cc[nzchar(.cc)]
  if (length(.cc)) sub("_.*$", "", .cc[length(.cc)]) else ""
}
.blk_left <- if (nzchar(.blk_now)) {
  .fr2 <- .rf_free_cells(cells, E2$attempts %||% list())
  sum(vapply(cells[.fr2], function(c) identical(as.character(c$block %||% ""), .blk_now), logical(1)))
} else 0L

# ── ★B5 적대 반증 (G2 · 2026-09-17) — B5 블록이 닫혔거나 보류된 A 가 있으면 L-code **앞에서** 돈다 ─────────
#   pass 만 블록 승자·carry·Grade A 후보로 소비된다(rf_overlay_adversary.R 소비자 규약 · 표식은 원장 attempt$adversary).
#   실패는 러너를 세우지 않는다(adversary_failed 로 남긴다). 자기 층이 미검증인 보류 A 가 있으면 블록 미완이어도 돈다 —
#   verdict 를 **이 tick 에** 받아 바로 재평가한다. (구판 사연: A 를 낸 순간 entry 가 graduated 로 닫혀 같은 tick 에 못 풀면 영구 미결이었다.
#   P0-12(2026-09-24) 이후 보류 A 의 entry 는 active 로 남아 못 푼 것은 tick 시작 재평가가 다시 본다.)
.adv_ran <- FALSE
if (nb > 0L && ((identical(.blk_now, "B5") && .blk_left == 0L) || length(.held_a))) {
  .adv <- tryCatch({
    suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_overlay_adversary.R"), local = TRUE))
    rf_overlay_adversary_run(BID, "B5", 1L, root = ROOT)
  }, error = function(e) { jlog("adversary_failed", base_id = BID, block = "B5", err = conditionMessage(e)); NULL })
  if (!is.null(.adv)) { .adv_ran <- TRUE
    jlog("adversary_done", base_id = BID, block = "B5", n = NROW(.adv),
         verdicts = if (NROW(.adv)) paste(sprintf("%s=%s", .adv$code, .adv$verdict), collapse = ",") else "",
         held_a = length(.held_a)) }
  # 보류된 A — verdict 는 **원장에서 다시 읽는다**(러너 지역 목록은 n·산출물만 든다). ★2026-09-24(P0-12): pass 만으로 발행하지 않고
  #   관문 **전체**를 다시 판정한다(.a_recheck) — 적대검증이 풀려도 규약·창·회계·승계 층 보류가 남을 수 있다. 발행이면 졸업까지.
  #   발행 못 한 A 는 entry active 로 남아(graduate=FALSE) tick 시작 재평가가 다시 본다(구판: graduated 로 닫혀 영구 미결).
  if (length(.held_a)) {
    .EH <- tryCatch(rf_load(1L, ROOT), error = function(e) NULL); .iH <- if (!is.null(.EH)) .rf_find(.EH, BID) else NA
    for (h in .held_a) {
      .aH <- if (!is.na(.iH)) Filter(function(a) identical(as.integer(a$n), as.integer(h$n)), .EH$entries[[.iH]]$attempts %||% list()) else list()
      .vH <- if (length(.aH)) as.character((.aH[[1]]$adversary %||% list())$verdict %||% "")[1] else ""
      .eH <- .a_recheck(h, .aH, .EH)
      if (isTRUE(.eH$eligible)) {
        jlog("grade_a_released", n = h$n, code = h$code, verdict = .vH, phase = "b5_boundary",
             note = "적대검증 pass · 관문 전체 통과 — judge_request·grade_a_queue 발행 + 졸업")
        .grade_a_enqueue(h$n, h$code, h$artifacts, h$essence, .eH)
        .a_decision(h$n, h$code, .eH, "publish", "b5_boundary")
        .a_graduate(h$n, sprintf("A 자격 관문 해제 — B5 경계 적대검증 %s", .vH))
      } else if (.vH %in% c("fail", "error", "not_candidate")) {
        jlog("grade_a_adversary_blocked", n = h$n, code = h$code, verdict = .vH, codes = paste(.eH$codes, collapse = "+"),
             note = "적대검증 미통과 — Judge 큐 미발행(등급 불변 · 소비 보류). 수리·재측정 후 재검증")
        .a_hold_record(h$n, h$code, h$artifacts, .eH, "b5_boundary")
      } else if (!("adversary_unverified" %in% .eH$codes)) {
        jlog("grade_a_hold_other", n = h$n, code = h$code, verdict = .vH, codes = paste(.eH$codes, collapse = "+"),
             note = "적대검증은 풀렸지만 다른 보류(규약·창·회계·표식)가 남았다 — 발행 보류 유지(tick 시작 재평가)")
        .a_hold_record(h$n, h$code, h$artifacts, .eH, "b5_boundary")
      } else jlog("grade_a_hold_unresolved", n = h$n, code = h$code, adversary_ran = .adv_ran,
                  note = "verdict 없음(적대검증 미완) — 발행 보류 유지. entry active 유지 → tick 시작 재평가(수동: rf_overlay_adversary_run)")
    }
  }
  # ★재설계 라운드 종료 표식 (B5 설계 레인 계약) — 재설계 배치가 다 돌고 적대검증까지 지나면 러너가 닫는다.
  if (.redesign_on && identical(.blk_now, "B5") && .blk_left == 0L)
    tryCatch({ rf_record_b5_redesign(1L, BID, list(active = FALSE, closed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                                                   closed_by = "reinforce_auto_parallel:b5_boundary", adversary_ran = .adv_ran),
                                     root = ROOT)
               jlog("b5_redesign_closed", base_id = BID, adversary_ran = .adv_ran) },
             error = function(e) jlog("b5_redesign_close_failed", base_id = BID, err = conditionMessage(e)))
}
if (nb > 0L && (.blk_left == 0L || u2 >= MAXA)) {
  # ★순서 (2026-09-04): L-code -> 기전 -> **텔레그램**.
  #   구판은 텔레그램이 먼저라 기전·처방이 메시지에 영원히 못 들어갔다 — 도훈이 받는 보고에
  #   "무엇을 배웠고 다음에 뭘 할 것인가" 가 빠져 있었다. 발송을 뒤로 옮긴다.
  lc <- tryCatch({ source(file.path(ROOT, "02_Infrastructure/ops/rf_block_lcode.R"))
                   rf_emit_block_lcode(BID, u2, root = ROOT) },
                 error = function(e) { jlog("lcode_failed", err = conditionMessage(e)); NULL })
  jlog("lcode_block", n = u2, l_code = as.character(lc %||% "NA"))
  # 기전 서술 — 규칙이 적은 수치 척추 위에 "왜" 한 문단 + 다음 블록 처방.
  #   재료에 이 전략의 앞선 블록 L-code 를 함께 넣는다(누적 교훈 참조).
  #   병합은 R 이 하고 구조 검증(셀 인용·금칙어·처방 존재)을 통과해야 얹힌다.
  if (!is.null(lc) && nzchar(as.character(lc))) {
    .mblk <- if (!is.na(.blk_now) && nzchar(.blk_now)) .blk_now else NA_character_
    if (!is.na(.mblk)) tryCatch(system2("bash",
        c(shQuote(file.path(ROOT, "02_Infrastructure/ops/rf_lcode_mechanism.sh")),
          shQuote(BID), shQuote(.mblk)), wait = TRUE, stdout = TRUE, stderr = TRUE),
      error = function(e) jlog("lcode_mechanism_failed", err = conditionMessage(e)))
  }
  # ★등급 팡파레 — 블록 보고 **앞에** 짧은 이펙트 하나 (도훈 지시 2026-09-04).
  #   이번 블록이 이 entry 의 **첫 B(또는 A)** 를 냈을 때만. 원장에서 재도출한다 —
  #   "B 가 있다" 가 아니라 "이번 블록이 처음 만들었다" 여야 한다. 그러지 않으면
  #   B 하나 나온 뒤 매 블록 축포가 울려 소음이 된다(적응형 절이 밟은 그 병).
  tryCatch({
    source(file.path(ROOT, "02_Infrastructure/ops/rf_grade_fanfare.R"))
    .E3 <- rf_load(1L, ROOT); .i3 <- .rf_find(.E3, BID)
    if (!is.na(.i3)) {
      .en3 <- .E3$entries[[.i3]]
      .bc  <- vapply(cells, function(c) as.character(c$code %||% ""), character(1))
      .bc  <- .bc[startsWith(.bc, paste0(.blk_now, "_")) & !(.bc %in% rf_control_codes(ROOT))]   # ★통제·대조 칸(P1-06 · B7 격자 control 태그 — 정본 rf_control_codes)은 축포 대상 아님
      .ng  <- rf_fanfare_new_grade(.en3, .bc)
      if (!is.na(.ng)) {
        .hit <- Filter(function(a) identical(toupper(substr(as.character(a$grade %||% ""), 1, 1)), .ng) &&
                         as.character(a$cell_code %||% "") %in% .bc, .en3$attempts %||% list())
        if (length(.hit)) {
          .h1 <- .hit[[which.max(vapply(.hit, function(a)
                    suppressWarnings(as.numeric((a$essence %||% list())$port_t %||% NA)), numeric(1)))]]
          .fok <- rf_grade_fanfare(BID, .ng, as.character(.h1$cell_code %||% ""),
                    .h1$essence %||% list(), n = u2, maxa = MAXA,
                    title = .rf_target_label(.en3), base_grade = .en3$base_grade %||% "",
                    root = ROOT)
          jlog("grade_fanfare", grade = .ng, code = as.character(.h1$cell_code %||% ""), sent = .fok)
        }
      }
    }
  }, error = function(e) jlog("grade_fanfare_failed", err = conditionMessage(e)))
  # ★"보냈다" 를 예외 부재로 지어내지 않는다 — rf_auto_notify 가 실제 발송 결과를 돌려준다.
  ok <- tryCatch({ source(file.path(ROOT, "02_Infrastructure/ops/rf_auto_notify.R"))
                   isTRUE(rf_auto_notify(BID, u2, kind = "block")) },
                 error = function(e) { jlog("telegram_failed", err = conditionMessage(e)); FALSE })
  if (!ok) jlog("telegram_send_failed", n = u2,
                note = "발송 실패 — lock 미생성이므로 다음 tick 이 재발송을 시도한다")
  jlog("telegram_block", n = u2, sent = ok, base_id = BID, block = .blk_now)   # ★base_id·block — 경계 백필의 흔적 판정이 읽는다(B5FIX)
  # ★증류 주기 맞춤 (도훈 지시 2026-09-04) — corpus 는 부팅마다 갱신되는데 증류
  #   (cluster_extractor)는 주간 cleaner 안에서만 돌았다. 강화는 하루에 블록 L-code 를
  #   5~6건 내므로 주 1회로는 못 따라간다 — 실측: 강화 75건이 corpus 에 있는데
  #   distilled 에는 0건이었다(오늘 수동 실행하자 후보 7건이 바로 나왔다).
  #   ⇒ 블록 L-code 를 낸 자리에서 증류도 같이 돈다. 실패해도 루프는 안 선다.
  tryCatch(system2(Sys.getenv("QVEST_PY", "python"),
      c(shQuote(file.path(ROOT, "02_Infrastructure/axiom/lcode_harvester.py"))),
      env = character(0), wait = TRUE, stdout = FALSE, stderr = FALSE),
    error = function(e) jlog("harvest_failed", err = conditionMessage(e)))
  .dz <- tryCatch(system2(Sys.getenv("QVEST_PY", "python"),
      c(shQuote(file.path(ROOT, "02_Infrastructure/axiom/cluster_extractor.py"))),
      wait = TRUE, stdout = TRUE, stderr = TRUE), error = function(e) NULL)
  jlog("distill_ran", n = u2,
       new_cands = length(grep("CAND_", as.character(.dz %||% character(0)), value = TRUE)),
       note = "블록 L-code 발행 직후 증류 — 주간 주기가 강화 속도를 못 따라간다")
}
jlog("batch_done", block = (if (!is.null(first)) first$block else "resume"), recorded = nb, used = u2)
0L
}

rc <- tryCatch(main(), error = function(e) { jlog("fatal", err = conditionMessage(e)); 1L })
.rel <- if (.CLAIM_HELD) list(ok = TRUE, reason = "inherited") else rf_claim_release(CLAIM)
# ★표식이 남은 해제는 실패가 아니다(2026-09-19) — 다음 tick 이 released.json 을 보고 즉시 제자리 인수한다.
#   구판은 이것을 claim_release_failed 로 찍어 09-13~17 에만 19건 상시 오탐이 됐다(진짜 실패를 가린다).
if (identical(.rel$reason, "marker_left")) jlog("claim_release_marker", reason = .rel$reason,
     note = "디렉터리는 못 지웠지만 해제 표식을 남겼다 — 다음 tick 이 즉시 제자리 인수한다(정보)")
if (!isTRUE(.rel$ok)) jlog("claim_release_failed", reason = .rel$reason, err = .rel$err %||% "",
     note = "디렉터리도 표식도 남았다 — owner.json 의 pid 가 죽으면(빈 고아면 60초 뒤) 다음 tick 이 회수한다")
quit(status = if (is.numeric(rc)) as.integer(rc) else 0L)
