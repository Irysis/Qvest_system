#!/usr/bin/env Rscript
#==============================================================================
# test_rf_l2_driver.R — 2계층 무인 레인 드라이버 (2026-09-21 도훈 승인 플랜 Part 3 · D2)
#
# 샌드박스 root + 스텁 러너/빌더(env 로 조종되는 실제 러너 계약을 흉내) 로 끝까지 돈다. 운영 원장·풀·claim 무접촉.
#   A 성공 경로: 원장 append→T/S/C→MC 게이트→record→요청 done · C arm 이 floor-only 변형 풀을 받는다(FR_MODULE_PERF) ·
#                T 등재/S·C 미등재 · selection_type 전달 · 라벨 게이트 block · 교훈에 regime_channel_not_delivered
#   B L1 배치 진행 중(살아있는 owner pid 의 러너 claim): halt_l1_batch_running · 요청 deferred_count+1 · 원장 불변
#   C R1 미결(selection_type 공백): halt_r1_undecided · 원장 불변
#   D 요청 무효(idea 공백): request_invalid · status failed · exit 1
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- sub("/+$", "", gsub("\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"), fixed = TRUE))
DRV <- file.path(ROOT, "02_Infrastructure/ops/rf_l2_auto.R")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
finish <- function() { cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"rf_l2_driver","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', PASS, FAIL, PASS + FAIL)); quit(status = if (FAIL == 0L) 0L else 1L) }
S <- gsub("\\", "/", file.path(tempdir(), sprintf("rf_l2_%d", Sys.getpid())), fixed = TRUE)
for (d in c("06_Registry", "02_Infrastructure", ".cache", "04_Research/factor_rotation/output", "stubs")) dir.create(file.path(S, d), recursive = TRUE, showWarnings = FALSE)
writeLines("# marker", file.path(S, "02_Infrastructure/config.R"))
# ── 스텁 러너: run_wf_ensemble.R 의 env 계약(FR_RUN_ID·FR_ARM_TAG·FR_REGISTER·FR_DIAG_DIR·FR_MODULE_PERF·FR_SELECTION_TYPE·FR_EXTRA_REGIME_LAG·QVEST_LABEL_GATE_MODE) 만 흉내 ──
writeLines(c(
  'PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR"); id <- Sys.getenv("FR_RUN_ID"); tag <- Sys.getenv("FR_ARM_TAG", ""); fr <- if (nzchar(tag)) paste0(id, "_", tag) else id',
  'od <- file.path(PROJ, "04_Research/factor_rotation/output"); dir.create(od, recursive = TRUE, showWarnings = FALSE)',
  'mp <- Sys.getenv("FR_MODULE_PERF", ""); pool <- jsonlite::fromJSON(if (nzchar(mp)) mp else file.path(PROJ, "06_Registry/module_performance.json"), simplifyVector = FALSE)',
  'nm <- pool$n_modules; lag <- as.integer(Sys.getenv("FR_EXTRA_REGIME_LAG", "0"))',
  'pt <- if (nzchar(tag) && startsWith(tag, "C")) 1.6 else if (lag > 0) 0.8 else 0.85; sr <- if (lag > 0) 0.80 else 0.82',
  'res <- list(fr_id = fr, grade = "C", essence = list(net_sharpe = sr, net_ir = 0.1, portfolio_alpha_t_nw_lag3 = pt, oos_retention = 0.3, dsr = 0.07, mdd = 0.4, calmar = 0.399, cagr = 0.16),',
  '            n_modules = nm, n_trials_cumulative = nm + 5, selection_type_seen = Sys.getenv("FR_SELECTION_TYPE", ""), register = Sys.getenv("FR_REGISTER", "1"), label_gate = Sys.getenv("QVEST_LABEL_GATE_MODE", ""), pool_path = mp)',
  'jsonlite::write_json(res, file.path(od, paste0(fr, "_result.json")), auto_unbox = TRUE)',
  'dd <- Sys.getenv("FR_DIAG_DIR", ""); if (nzchar(dd)) { dir.create(dd, recursive = TRUE, showWarnings = FALSE)',
  '  jsonlite::write_json(list(fr_id = fr, MC1_membership = list(n_pairs = 51, jaccard_median = 0.974, delivered = FALSE), MC2_weights = list(retention_median = 0.3, delivered = TRUE)), file.path(dd, paste0(fr, "_manipulation_check.json")), auto_unbox = TRUE) }',
  'cat("stub runner", fr, "\\n")'), file.path(S, "stubs/runner.R"))
writeLines(c(
  'out <- Sys.getenv("QVEST_L2_DRY_RUN_OUT"); route <- Sys.getenv("QVEST_L2_DEFENSIVE_ROUTE", "1"); mx <- Sys.getenv("FR_MAX_MODULES", "")',
  'n <- if (route == "OFF") 2L else 3L; if (nzchar(mx)) n <- min(n, as.integer(mx))',
  'mods <- setNames(lapply(seq_len(n), function(i) list(source_strategy_id = paste0("M", i))), paste0("M", seq_len(n)))',
  'jsonlite::write_json(list(schema_version = "v3.1", generated = format(Sys.Date(), "%Y-%m-%d"), n_modules = n, defensive_route = (route != "OFF"), modules = mods), out, auto_unbox = TRUE)'),
  file.path(S, "stubs/builder.R"))
cfg <- function(sel = "chain", by = "test", at = "2026-09-21T00:00:00+0900", enabled = TRUE)
  list(schema = "t", enabled = TRUE, claim_stale_hours = 6, l2_auto = list(enabled = enabled, selection_type = sel, decided_by = by, decided_at = at, arms = list("T", "S", "C"), arm_timeout_min = 5, min_free_gb = 0, fallback_max_modules = 200, stale_pool_days = 7, label_gate = "block"))
write_cfg <- function(...) writeLines(toJSON(cfg(...), auto_unbox = TRUE), file.path(S, "06_Registry/reinforce_auto_config.json"))
write_led <- function() writeLines(toJSON(list(schema_version = "reinforce_ledger_v2", layer = 2, note = "t", entries = list(list(base_id = "FR_003", status = "active", base_grade = "C", attempts_used = 0, attempts = list(), opened_at = "2026-09-12")), last_updated = ""), auto_unbox = TRUE, pretty = TRUE), file.path(S, "06_Registry/reinforce_ledger_l2.json"))
write_req <- function(idea = "풀 3 위 π₀ 재측정 + floor-only 대조") writeLines(toJSON(list(schema = "l2_unit_request_v1", status = "pending", requested_at = "2026-09-21T08:00:00+0900", requested_by = "test", base_id = "FR_003", keyword_axis = "strategy_combination", idea = idea, arms = list("T", "S", "C"), next_probe = list("a", "b"), root_papers = list(), deferred_count = 0), auto_unbox = TRUE), file.path(S, "06_Registry/l2_unit_request.json"))
writeLines(toJSON(list(schema_version = "v3.1", generated = format(Sys.Date(), "%Y-%m-%d"), n_modules = 3, modules = list(M1 = list(a = 1), M2 = list(a = 1), M3 = list(a = 1))), auto_unbox = TRUE), file.path(S, "06_Registry/module_performance.json"))
JL <- file.path(S, ".cache/jlog.jsonl")
Sys.setenv(QVEST_L2_RUNNER = file.path(S, "stubs/runner.R"), QVEST_L2_BUILDER = file.path(S, "stubs/builder.R"),
           QVEST_RF_CLAIM = file.path(S, ".cache/reinforce_auto.claim"), QVEST_L2_CLAIM = file.path(S, ".cache/rf_l2_auto.claim"),
           QVEST_RF_CONFIG = file.path(S, "06_Registry/reinforce_auto_config.json"), QVEST_RP_JLOG = JL,
           QVEST_L2_NOTIFY = "0", QVEST_TG_DRY_RUN = "1", QVEST_L2_REQUEST = file.path(S, "06_Registry/l2_unit_request.json"))
run <- function(extra = character(0)) { o <- suppressWarnings(system2("Rscript", c(shQuote(DRV), sprintf("--root=%s", S), extra), stdout = TRUE, stderr = TRUE)); attr(o, "status") %||% 0L; o }
events <- function() { if (!file.exists(JL)) return(character(0)); vapply(readLines(JL, warn = FALSE), function(l) tryCatch(fromJSON(l)$event, error = function(e) ""), character(1)) }
led <- function() fromJSON(file.path(S, "06_Registry/reinforce_ledger_l2.json"), simplifyVector = FALSE)
req <- function() fromJSON(file.path(S, "06_Registry/l2_unit_request.json"), simplifyVector = FALSE)

cat("=== A 성공 경로 ===\n")
write_cfg(); write_led(); write_req(); unlink(JL)
o <- run()
ev <- events()
e <- led()$entries[[1]]
if (identical(e$attempts_used, 1L) || isTRUE(e$attempts_used == 1)) ok("A 원장 attempts_used=1") else ng("A 원장 append", paste(tail(o, 8), collapse = " | "))
a <- if (length(e$attempts)) e$attempts[[1]] else list()
if (identical(a$grade, "C") && isTRUE(abs(a$essence$port_t - 0.85) < 1e-9) && isTRUE(a$essence$mc1_delivered == FALSE)) ok("A record: grade C · essence 항등(T PORT_t 0.85) · mc1_delivered=FALSE") else ng("A record", paste(a$grade, a$essence$port_t))
ls_ <- unlist(a$lessons)
if (any(grepl("regime_channel_not_delivered", ls_)) && any(grepl("붙이지 않는다", ls_))) ok("A 교훈: MC1 미전달 → '국면조건부' 라벨 금지 문구") else ng("A 교훈 MC1", paste(ls_, collapse = " / "))
if (any(grepl("\\[C floor-only 2모듈\\]", ls_)) && any(grepl("희석", ls_))) ok("A 교훈: C arm floor-only 2모듈 · T−C 음수 → 희석 판정") else ng("A 교훈 C arm", paste(grep("floor", ls_, value = TRUE), collapse = " / "))
if (any(grepl("\\[S lag\\+1\\]", ls_))) ok("A 교훈: S arm 스트레스 줄") else ng("A 교훈 S arm")
od <- file.path(S, "04_Research/factor_rotation/output")
rT <- fromJSON(file.path(od, "FR_003_n1_result.json"), simplifyVector = FALSE); rS <- fromJSON(file.path(od, "FR_003_n1_S_lag1_result.json"), simplifyVector = FALSE); rC <- fromJSON(file.path(od, "FR_003_n1_C_flooronly_result.json"), simplifyVector = FALSE)
if (identical(rT$register, "1") && identical(rS$register, "0") && identical(rC$register, "0")) ok("A 등재: T 만 등재 · S/C 미등재") else ng("A 등재 플래그", paste(rT$register, rS$register, rC$register))
if (identical(rT$selection_type_seen, "chain") && identical(rT$label_gate, "block")) ok("A 러너 env: FR_SELECTION_TYPE=chain · QVEST_LABEL_GATE_MODE=block 전달") else ng("A 러너 env", paste(rT$selection_type_seen, rT$label_gate))
if (isTRUE(rC$n_modules == 2) && grepl("flooronly", rC$pool_path, fixed = TRUE) && isTRUE(rT$n_modules == 3) && !nzchar(rT$pool_path)) ok("A 풀: C=floor-only 변형 풀(2) · T=정본 풀(3)") else ng("A 풀 경로", paste(rC$n_modules, rC$pool_path, rT$n_modules))
r <- req()
if (identical(r$status, "done") && identical(r$result$run_id, "FR_003_n1") && isTRUE(r$attempt_n == 1)) ok("A 요청 done · run_id FR_003_n1") else ng("A 요청 상태", paste(r$status, r$result$run_id))
need <- c("l2_start", "attempt_appended", "arm_start", "arm_done", "recorded", "l2_done")
if (all(need %in% ev) && sum(ev == "arm_done") == 3L) ok("A jlog 이벤트 전수 · arm_done 3") else ng("A jlog", paste(unique(ev), collapse = ","))
cl <- function(p) !dir.exists(p) || file.exists(file.path(p, "released.json"))
if (cl(file.path(S, ".cache/reinforce_auto.claim")) && cl(file.path(S, ".cache/rf_l2_auto.claim"))) ok("A claim 해제(러너·자기)") else ng("A claim 잔존")
if (!file.exists(file.path(S, "06_Registry/l2_judge_request.json"))) ok("A grade C → Judge 요청 없음") else ng("A Judge 요청이 C 에서 생김")

cat("\n=== B L1 배치 진행 중 ===\n")
write_req(); unlink(JL)
cd <- file.path(S, ".cache/reinforce_auto.claim"); dir.create(cd, showWarnings = FALSE)
writeLines(toJSON(list(pid = Sys.getpid(), started_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), host = "t"), auto_unbox = TRUE), file.path(cd, "owner.json"))
o <- run(); ev <- events()
if ("halt_l1_batch_running" %in% ev && !("l2_start" %in% ev)) ok("B 살아있는 러너 claim → halt_l1_batch_running · 실행 0") else ng("B 직렬화", paste(unique(ev), collapse = ","))
if (isTRUE(req()$deferred_count == 1) && identical(req()$status, "pending")) ok("B 요청 deferred_count=1 · pending 유지") else ng("B deferred", as.character(req()$deferred_count))
if (isTRUE(led()$entries[[1]]$attempts_used == 1)) ok("B 원장 불변(attempts_used 1)") else ng("B 원장 변경됨")
if (dir.exists(cd) && file.exists(file.path(cd, "owner.json")) && !file.exists(file.path(cd, "released.json"))) ok("B 남의 claim 을 건드리지 않음") else ng("B 남의 claim 훼손")
unlink(cd, recursive = TRUE)

cat("\n=== C R1 미결 ===\n")
write_cfg(sel = ""); write_req(); unlink(JL)
o <- run(); ev <- events()
if ("halt_r1_undecided" %in% ev && !("l2_start" %in% ev) && isTRUE(led()$entries[[1]]$attempts_used == 1)) ok("C selection_type 공백 → halt_r1_undecided · 원장 불변") else ng("C R1", paste(unique(ev), collapse = ","))

cat("\n=== D 요청 무효 ===\n")
write_cfg(); write_req(idea = ""); unlink(JL)
o <- run(); ev <- events()
if ("request_invalid" %in% ev && identical(req()$status, "failed")) ok("D idea 공백 → request_invalid · status failed") else ng("D 무효 요청", paste(unique(ev), collapse = ","))
unlink(S, recursive = TRUE)
finish()
