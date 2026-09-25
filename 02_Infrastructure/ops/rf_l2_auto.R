#!/usr/bin/env Rscript
#==============================================================================
# rf_l2_auto.R — 2계층 무인 레인 드라이버 (2026-09-21 도훈 승인 플랜 Part 3 · D2)
#
# 흐름: 요청(l2_unit_request.json pending) → R1 결정 확인 → 자기 claim → **러너 claim**(L1 배치와 직렬화) →
#       원장 append(실행 전) → 풀 신선도/메모리 가드 → arm T/S/C 실행(run_wf_ensemble.R) → MC 게이트 → 원장 record →
#       (A 면 Judge 요청 파일) → 요청 done → 텔레그램 [2계층·강화 n] → claim 해제.
# 실패는 요청을 failed 로 남기고 exit 1 (fail-soft 위장 없음). 어떤 단계도 등급을 계산하지 않는다 — 러너 안 essence 만 옮긴다.
# 호출: Rscript 02_Infrastructure/ops/rf_l2_auto.R [--root=<data root>] [--validate-only]
#   검사 env: QVEST_L2_REQUEST · QVEST_L2_RUNNER · QVEST_L2_BUILDER · QVEST_RF_CLAIM · QVEST_L2_CLAIM · QVEST_RF_CONFIG · QVEST_RP_JLOG
#==============================================================================
ARGS <- commandArgs(trailingOnly = TRUE)
.arg <- function(flag, default = NULL) { v <- grep(paste0("^", flag, "="), ARGS, value = TRUE); if (length(v)) sub(paste0("^", flag, "="), "", v[1]) else default }
.norm <- function(p) sub("/+$", "", gsub("\\", "/", p, fixed = TRUE))
ROOT <- .norm(.arg("--root", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")))
CODE_ROOT <- local({
  a <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(a)) { cr <- sub("/02_Infrastructure/ops/?$", "", dirname(.norm(sub("^--file=", "", a[1]))))
    if (file.exists(file.path(cr, "02_Infrastructure/ops/rf_l2_lib.R"))) return(cr) }
  ov <- Sys.getenv("QVEST_L2_CODE_ROOT", ""); if (nzchar(ov)) .norm(ov) else ROOT
})
VALIDATE_ONLY <- "--validate-only" %in% ARGS
source(file.path(CODE_ROOT, "02_Infrastructure/ops/rf_l2_lib.R"))
suppressMessages(source(file.path(CODE_ROOT, "02_Infrastructure/ops/rf_claim.R")))
LED <- new.env(parent = globalenv())
invisible(capture.output(suppressMessages(suppressWarnings(sys.source(file.path(CODE_ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R"), envir = LED)))))
jl <- function(event, ...) l2_jlog(event, ..., root = ROOT)

cfg <- l2_cfg(ROOT)
if (!cfg$loop_enabled || !cfg$enabled) { jl("halt_disabled", loop = cfg$loop_enabled, lane = cfg$enabled); quit(status = 0) }
req <- l2_request_read(ROOT)
if (is.null(req) || !identical(.l2_chr(req$status), "pending")) { jl("not_due", status = .l2_chr((req %||% list())$status %||% "none")); quit(status = 0) }
if (!l2_r1_decided(cfg)) {
  jl("halt_r1_undecided", note = "config l2_auto.selection_type(chain|sweep)+decided_by+decided_at 가 기록돼야 러너에 넘긴다 — 조용한 반전 금지(플랜 Part 3 §6 R1)")
  quit(status = 0) }
led2 <- LED$rf_load(2L, ROOT)
bad <- l2_request_validate(req, led2)
if (nzchar(bad)) { jl("request_invalid", why = bad); req$status <- "failed"; req$error <- bad; req$completed_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"); l2_request_write(req, ROOT); quit(status = 1) }
if (VALIDATE_ONLY) { jl("validate_ok", base_id = req$base_id); quit(status = 0) }

# ── ★리프레시 배리어 (도훈 결정 OPS-RUNNER-REFRESH-BARRIER · 2026-09-24) — claim·원장 사전 등록 **전** ────────────────
#   arm 러너(run_wf_ensemble.R)·풀 빌더는 daily_refresh 산출물(.cache/unified_regime_signal_daily.parquet 등)을 읽는다.
#   잠금이 살아 있으면 요청을 건드리지 않고(pending 유지 · deferred_count 무증가) 물러난다 — 다음 tick 재시도.
#   판정 정본 = refresh_barrier.sh · stale = 대기 안 함 + 로그 · error = fail-closed · 잠금 없음 = 아무것도 안 한다.
.rb_l2 <- tryCatch({
  .rbx <- new.env(); sys.source(file.path(CODE_ROOT, "02_Infrastructure/ops/refresh_barrier.R"), envir = .rbx, keep.source = FALSE)
  .rbx$rb_status(ROOT)
}, error = function(e) list(state = "error", reason = conditionMessage(e), blocking = TRUE))
.rb_l2kv <- list(state = .rb_l2$state %||% "", lock = .rb_l2$lock %||% "", pid = .rb_l2$pid %||% "",
                 reason = .rb_l2$reason %||% "", path = .rb_l2$path %||% "")
if (isTRUE(.rb_l2$blocking)) { do.call(jl, c(list("halt_refresh_lock"), .rb_l2kv)); quit(status = 0) }
if (identical(.rb_l2$state, "stale")) do.call(jl, c(list("refresh_lock_stale"), .rb_l2kv, list(note = "보유자 없음 — 대기하지 않고 진행")))

# ── claim: 자기 것 → 러너 것 (L1 배치 진행 중이면 물러난다 · 다음 tick 재시도) ────────────────
OWN <- Sys.getenv("QVEST_L2_CLAIM", file.path(ROOT, ".cache/rf_l2_auto.claim"))
RUN <- Sys.getenv("QVEST_RF_CLAIM", file.path(ROOT, ".cache/reinforce_auto.claim"))
own <- rf_claim_acquire(OWN, stale_hours = 2)
if (!isTRUE(own$ok)) { jl("halt_claimed", reason = own$reason, owner_pid = own$owner_pid %||% NA); quit(status = 0) }
release_all <- function() { rf_claim_release(RUN); rf_claim_release(OWN) }
rc <- rf_claim_acquire(RUN, stale_hours = cfg$claim_stale_hours)
if (!isTRUE(rc$ok)) {
  req$deferred_count <- as.integer(req$deferred_count %||% 0L) + 1L; req$last_deferred_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  l2_request_write(req, ROOT); rf_claim_release(OWN)
  jl("halt_l1_batch_running", reason = rc$reason, owner_pid = rc$owner_pid %||% NA, deferred = req$deferred_count, note = "러너 claim 이 살아 있다 — L1 배치 종료 후 다음 tick 에 재시도")
  quit(status = 0) }
jl("l2_start", base_id = req$base_id, arms = paste(unlist(req$arms), collapse = ","), selection_type = cfg$selection_type)

main <- function() {
  req$status <- "in_progress"; req$started_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"); req$pid <- Sys.getpid(); l2_request_write(req, ROOT)
  base_id <- .l2_chr(req$base_id)
  # Step-0 지식 확인 (SKILL §0) — 직전 attempts 교훈 요약(없으면 빈 문자열)
  step0 <- tryCatch(paste(LED$rf_lessons_digest(2L, base_id, root = ROOT), collapse = " | "), error = function(e) "")
  # 풀 신선도 — 오래됐으면 정본 풀 재생성(빌더 headless · 기본 스위치)
  age <- l2_pool_age_days(ROOT); rebuilt <- FALSE
  if (is.finite(age) && age > cfg$stale_pool_days) {
    jl("pool_rebuild", age_days = age)
    rcb <- tryCatch(system2("Rscript", shQuote(l2_builder(CODE_ROOT)), stdout = FALSE, stderr = FALSE, timeout = 1800), error = function(e) 99L)
    rebuilt <- identical(as.integer(rcb), 0L); jl("pool_rebuild_done", ok = rebuilt) }
  pool_n <- .l2_num((.l2_rj(file.path(ROOT, "06_Registry/module_performance.json")) %||% list())$n_modules)
  # 메모리 가드 — 여유가 적으면 잘린 풀로 측정하고 그 사실을 원장에 남긴다
  free_gb <- l2_free_gb(); pool_truncated <- FALSE; full_pool <- ""
  cache_dir <- file.path(ROOT, ".cache/l2_pool"); dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  logd <- file.path(ROOT, ".cache/scheduler_logs"); dir.create(logd, recursive = TRUE, showWarnings = FALSE)
  if (is.finite(free_gb) && free_gb < cfg$min_free_gb) {
    tp <- file.path(cache_dir, sprintf("%s_trunc%d.json", base_id, cfg$fallback_max_modules))
    b <- l2_build_variant_pool(ROOT, CODE_ROOT, tp, defensive_route = "1", max_modules = cfg$fallback_max_modules, log_path = file.path(logd, "l2_pool_build.log"))
    if (isTRUE(b$ok)) { full_pool <- tp; pool_truncated <- TRUE; pool_n <- b$n_modules; jl("pool_truncated", free_gb = round(free_gb, 1), max_modules = cfg$fallback_max_modules) }
    else jl("pool_truncate_failed", rc = b$rc) }
  # 원장 append — 실행 **전** (원장 밖 강화는 없다)
  LED$rf_append_attempt(2L, base_id, idea = .l2_chr(req$idea), keyword_axis = .l2_chr(req$keyword_axis),
                        root_papers = req$root_papers %||% list(), axiom_injected = FALSE,
                        cell_code = sprintf("L2_%s", paste(unlist(req$arms), collapse = "")), root = ROOT)
  e2 <- Filter(function(e) identical(e$base_id, base_id), LED$rf_load(2L, ROOT)$entries)[[1]]
  n <- as.integer(e2$attempts_used); run_id <- sprintf("%s_n%d", base_id, n)
  req$attempt_n <- n; l2_request_write(req, ROOT); jl("attempt_appended", base_id = base_id, n = n, run_id = run_id)
  diag_dir <- file.path(ROOT, "04_Research/factor_rotation/output", run_id)
  # arm 실행 — T 먼저(등재), S(lag+1 · 미등재), C(floor-only · 미등재)
  runs <- list(); arms <- intersect(c("T", "S", "C"), as.character(unlist(req$arms)))
  for (a in arms) {
    A <- L2_ARMS[[a]]; mp <- full_pool
    if (identical(A$pool, "floor")) {
      fp <- file.path(cache_dir, sprintf("%s_flooronly.json", run_id))
      b <- l2_build_variant_pool(ROOT, CODE_ROOT, fp, defensive_route = "OFF", max_modules = if (pool_truncated) cfg$fallback_max_modules else NULL, log_path = file.path(logd, "l2_pool_build.log"))
      if (!isTRUE(b$ok)) { jl("arm_skipped", arm = a, why = "floor pool build failed"); next }
      mp <- fp }
    jl("arm_start", arm = a, run_id = run_id, pool = if (nzchar(mp)) basename(mp) else "module_performance.json")
    r <- l2_run_arm(A, run_id, ROOT, CODE_ROOT, cfg, diag_dir, module_perf = mp, log_path = file.path(logd, sprintf("l2_%s_%s.log", run_id, a)), extra_lag = A$lag, register = A$register)
    runs[[a]] <- r
    jl("arm_done", arm = a, rc = r$rc, ok = r$ok, minutes = r$minutes, grade = .l2_chr((r$result %||% list())$grade))
    if (a == "T" && !isTRUE(r$ok)) stop(sprintf("arm T 실패 rc=%s — 기준 측정 없이 진행하지 않는다", r$rc))
  }
  gates <- l2_mc_gates(runs$T$mc)
  lessons <- c(l2_lessons(runs, gates, cfg, pool_truncated, pool_n), if (nzchar(step0)) sprintf("step0: %s", substr(step0, 1, 300)) else character(0))
  if (l2_forbidden_label(lessons, gates)) stop("MC1 미전달인데 '국면조건부' 라벨이 교훈에 들어 있다")
  T <- runs$T$result; eT <- T$essence %||% list(); grade <- .l2_chr(T$grade)
  lc <- file.path(ROOT, "stage_artifacts/l_code/factor_rotation", sprintf("l_code_%s.json", run_id)); if (!file.exists(lc)) lc <- NULL
  LED$rf_record_result(2L, base_id, n, grade = grade,
    essence = list(port_t = .l2_num(eT$portfolio_alpha_t_nw_lag3), calmar = .l2_num(eT$calmar), cagr = .l2_num(eT$cagr), mdd = .l2_num(eT$mdd),
                   net_sharpe = .l2_num(eT$net_sharpe), oos_retention = .l2_num(eT$oos_retention), dsr = .l2_num(eT$dsr),
                   cell_code = sprintf("L2_%s", paste(arms, collapse = "")), block = "L2", source = "run_wf_ensemble.R", spec = .l2_chr(runs$T$result_path),
                   n_modules = .l2_num(T$n_modules), n_trials_cumulative = .l2_num(T$n_trials_cumulative), selection_type = cfg$selection_type,
                   mc1_delivered = gates$mc1_delivered, mc1_jaccard = gates$mc1_jaccard, pool_truncated = pool_truncated,
                   arms = lapply(runs, function(r) { e <- (r$result %||% list())$essence %||% list()
                     list(ok = r$ok, grade = .l2_chr((r$result %||% list())$grade), port_t = .l2_num(e$portfolio_alpha_t_nw_lag3), calmar = .l2_num(e$calmar), net_sharpe = .l2_num(e$net_sharpe), minutes = r$minutes) })),
    artifacts = diag_dir, l_code = lc, lessons = lessons, root = ROOT)
  jl("recorded", base_id = base_id, n = n, grade = grade, mc1 = gates$mc1_delivered)
  if (identical(grade, "A")) {
    .l2_write_atomic(list(schema = "l2_judge_request_v1", status = "pending", base_id = base_id, attempt_n = n, run_id = run_id, requested_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
                          note = "2계층 essence A — Judge(PIT) 는 세션 전용. /qvest 에서 Judge 스폰 · PASS 후 BOOK 은 도훈 confirm"), file.path(ROOT, "06_Registry/l2_judge_request.json"))
    jl("judge_requested", base_id = base_id, n = n) }
  req$status <- "done"; req$completed_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  req$result <- list(run_id = run_id, grade = grade, arms = lapply(runs, function(r) list(ok = r$ok, grade = .l2_chr((r$result %||% list())$grade), minutes = r$minutes)), mc1_delivered = gates$mc1_delivered)
  l2_request_write(req, ROOT)
  if (!identical(Sys.getenv("QVEST_L2_NOTIFY", "1"), "0")) jl("telegram", sent = l2_notify(base_id, n, runs, gates, lessons, ROOT, CODE_ROOT, grade))
  jl("l2_done", base_id = base_id, n = n, grade = grade)
  0L
}
rc <- tryCatch(main(), error = function(e) {
  jl("l2_error", err = conditionMessage(e))
  r <- tryCatch(l2_request_read(ROOT), error = function(e2) NULL)
  if (is.list(r)) { r$status <- "failed"; r$error <- conditionMessage(e); r$completed_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"); tryCatch(l2_request_write(r, ROOT), error = function(e2) NULL) }
  1L })
release_all()
quit(status = rc)
