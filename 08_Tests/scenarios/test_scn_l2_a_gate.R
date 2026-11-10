#!/usr/bin/env Rscript
#==============================================================================
# test_scn_l2_a_gate.R — 2계층 운영 시나리오 (v10.2 감사 레인 F · 2026-11-10)
#   격리: 임시 루트 + 스텁 러너(측정 러너 미호출) · 운영 등록부 무쓰기 · 텔레그램 끔(QVEST_L2_NOTIFY=0).
#   S1  A 자격 관문 — 풀 전부 현 축 · 판 표식 최신 → eligible
#   S2  풀에 축 기록 없는 모듈(구 축) 1개 → held(pool_epoch_off_active)
#   S3  풀에 팩터 DB 수리 전 측정 1개 → held(pool_factor_db_stale)
#   S4  풀 비었음/파손 → held
#   S5  드라이버 종단: 스텁 T = A · 혼합 풀 → l2_judge_request.held.json 만 · Judge 요청 없음 · jlog judge_held
#   S6  드라이버 종단: 스텁 T = A · 깨끗한 풀 → l2_judge_request.json(v2 · a_eligibility 기록)
#   S7  모듈 산출 누락 = T arm 결과 없음(러너 rc≠0) → 요청 failed · claim 해제 · Judge 요청 없음
#   S8  재실행 — done 요청을 다시 돌리면 not_due(원장 attempt 증가 없음 · 멱등)
#   M1  [돌연변이] 관문의 축 비교를 소스 텍스트 치환으로 끄면 S2 가 eligible 로 바뀐다(관문 발화 실증)
#   P1  풀 게이트 사실 고정: l2_admit 는 essence C 를 floor 에서 거부(정상) — 그러나 운영 풀 모드 role 은 C/F 를 편입(빌더 :357)
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
self <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
CR <- gsub("\\", "/", dirname(dirname(dirname(self))), fixed = TRUE)
if (!file.exists(file.path(CR, "02_Infrastructure/ops/rf_l2_lib.R"))) stop("코드 루트 해석 실패: ", CR)
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(c, m, why = "") if (isTRUE(c)) ok(m) else ng(m, why)

S <- gsub("\\", "/", file.path(tempdir(), sprintf("scn_l2_%d", Sys.getpid())), fixed = TRUE)
for (d in c("06_Registry", "02_Infrastructure/worktask", ".cache", "04_Research/factor_rotation/output", "stubs", "art"))
  dir.create(file.path(S, d), recursive = TRUE, showWarnings = FALSE)
writeLines("# marker", file.path(S, "02_Infrastructure/config.R"))
file.copy(file.path(CR, "02_Infrastructure/worktask/constraint_defaults.json"), file.path(S, "02_Infrastructure/worktask/constraint_defaults.json"))
ACT <- fromJSON(file.path(S, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = FALSE)$measurement_axis$active
write_json(list(schema = "factor_db_vintage_v1", entries = list(list(id = "T1", completed_at = "2026-11-10T12:00:00+0900", scope = "all"))),
           file.path(S, "06_Registry/factor_db_vintage.json"), auto_unbox = TRUE)
## 합성 모듈 산출물: id → (실행 id · epoch)
mk_art <- function(run, epoch) {
  d <- file.path(S, "art", run); dir.create(d, showWarnings = FALSE)
  a <- list(essence_grade = "B", run_id = run); if (!is.null(epoch)) a$measurement_axis <- list(epoch = epoch)
  write_json(a, file.path(d, "authoritative_remeasure.json"), auto_unbox = TRUE); sprintf("art/%s/bt_result.rds", run)
}
mk_pool <- function(spec, path = file.path(S, "06_Registry/module_performance.json")) {
  mods <- list(); cat_m <- list()
  for (id in names(spec)) { bt <- mk_art(spec[[id]]$run, spec[[id]]$epoch)
    mods[[id]] <- list(source_strategy_id = id, grade = "B", registered_sim_result_path = sprintf("x/%s/sim_result.rds", id))
    cat_m[[id]] <- list(strategy_id = id, bt_result_path = bt) }
  write_json(list(schema_version = "v3.1", generated = format(Sys.Date()), n_modules = length(mods), modules = mods), path, auto_unbox = TRUE)
  write_json(list(modules = cat_m), file.path(S, "06_Registry/module_catalog.json"), auto_unbox = TRUE)
  path
}
L2 <- new.env(); sys.source(file.path(CR, "02_Infrastructure/ops/rf_l2_lib.R"), envir = L2)
clean <- list(M1 = list(run = "20261111_010000_1", epoch = ACT), M2 = list(run = "20261111_020000_2", epoch = ACT))

cat("=== S1~S4 관문 단위 ===\n")
invisible(mk_pool(clean)); e1 <- L2$l2_a_eligibility(S, CR)
chk(isTRUE(e1$eligible) && !length(e1$reasons), "S1 현 축 · 판 최신 2모듈 → eligible", paste(e1$reasons, collapse = ","))
invisible(mk_pool(c(clean, list(M3 = list(run = "20261112_030000_3", epoch = NULL))))); e2 <- L2$l2_a_eligibility(S, CR)
chk(!isTRUE(e2$eligible) && any(grepl("^pool_epoch_off_active:1/3", e2$reasons)), "S2 축 기록 없는 구 축 모듈 1 → held(pool_epoch_off_active:1/3)", paste(e2$reasons, collapse = ","))
invisible(mk_pool(c(clean, list(M4 = list(run = "20261101_010000_4", epoch = ACT))))); e3 <- L2$l2_a_eligibility(S, CR)
chk(!isTRUE(e3$eligible) && any(grepl("^pool_factor_db_stale:1/3", e3$reasons)) && !any(grepl("epoch", e3$reasons)),
    "S3 수리 전 측정 1 (같은 축) → held(pool_factor_db_stale:1/3) · 축 사유 없음", paste(e3$reasons, collapse = ","))
writeLines("{broken", file.path(S, "06_Registry/module_performance.json")); e4 <- L2$l2_a_eligibility(S, CR)
chk(!isTRUE(e4$eligible) && identical(e4$reasons, "pool_unreadable_or_empty"), "S4 풀 파손 → held(pool_unreadable_or_empty)")

cat("\n=== M1 돌연변이 — 축 비교 끄기 ===\n")
src <- readLines(file.path(CR, "02_Infrastructure/ops/rf_l2_lib.R"), warn = FALSE, encoding = "UTF-8")
pat <- "off <- sum(ep != act)"; nhit <- sum(grepl(pat, src, fixed = TRUE))
mut <- file.path(S, "stubs/rf_l2_lib_mut.R"); writeLines(gsub(pat, "off <- 0L", src, fixed = TRUE), mut, useBytes = TRUE)
chk(nhit == 1L, "M1 치환 성사 1곳", as.character(nhit))
LM <- new.env(); sys.source(mut, envir = LM)
invisible(mk_pool(c(clean, list(M3 = list(run = "20261112_030000_3", epoch = NULL))))); em <- LM$l2_a_eligibility(S, CR)
chk(isTRUE(em$eligible), "M1 돌연변이 사본은 구 축 혼합 풀을 eligible 로 통과시킨다 → 원본 관문이 판별한다")

cat("\n=== S5~S8 드라이버 종단 ===\n")
DRV <- file.path(CR, "02_Infrastructure/ops/rf_l2_auto.R")
writeLines(c(
  'PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR"); id <- Sys.getenv("FR_RUN_ID"); tag <- Sys.getenv("FR_ARM_TAG", ""); fr <- if (nzchar(tag)) paste0(id, "_", tag) else id',
  'if (file.exists(file.path(PROJ, "stubs/FAIL_T")) && !nzchar(tag)) { cat("module series missing\\n"); quit(status = 1) }',
  'od <- file.path(PROJ, "04_Research/factor_rotation/output"); dir.create(od, recursive = TRUE, showWarnings = FALSE)',
  'res <- list(fr_id = fr, grade = if (nzchar(tag)) "C" else "A", essence = list(net_sharpe = 1, portfolio_alpha_t_nw_lag3 = 3.1, calmar = 0.9, cagr = 0.2, mdd = 0.2, dsr = 0.6, oos_retention = 0.8), n_modules = 2, n_trials_cumulative = 7)',
  'jsonlite::write_json(res, file.path(od, paste0(fr, "_result.json")), auto_unbox = TRUE)'), file.path(S, "stubs/runner.R"))
writeLines('jsonlite::write_json(list(generated = format(Sys.Date()), n_modules = 2, modules = list()), Sys.getenv("QVEST_L2_DRY_RUN_OUT"), auto_unbox = TRUE)', file.path(S, "stubs/builder.R"))
write_json(list(schema = "t", enabled = FALSE, claim_stale_hours = 6, l2_auto = list(enabled = TRUE, selection_type = "sweep", decided_by = "test", decided_at = "2026-09-23",
                arms = list("T"), arm_timeout_min = 5, min_free_gb = 0, fallback_max_modules = 200, stale_pool_days = 7, label_gate = "block")),
           file.path(S, "06_Registry/reinforce_auto_config.json"), auto_unbox = TRUE)
write_led <- function() write_json(list(schema_version = "reinforce_ledger_v2", layer = 2, note = "t", entries = list(list(base_id = "FR_T", status = "active", base_grade = "C", attempts_used = 0, attempts = list(), opened_at = "2026-11-10")), last_updated = ""),
                                   file.path(S, "06_Registry/reinforce_ledger_l2.json"), auto_unbox = TRUE, pretty = TRUE)
write_req <- function() write_json(list(schema = "l2_unit_request_v1", status = "pending", requested_at = "2026-11-10T08:00:00+0900", requested_by = "test", base_id = "FR_T",
                                        keyword_axis = "strategy_combination", idea = "합성 A 경로", arms = list("T"), next_probe = list("a", "b"), root_papers = list(), deferred_count = 0),
                                   file.path(S, "06_Registry/l2_unit_request.json"), auto_unbox = TRUE)
JL <- file.path(S, ".cache/jlog.jsonl")
Sys.setenv(QVEST_L2_RUNNER = file.path(S, "stubs/runner.R"), QVEST_L2_BUILDER = file.path(S, "stubs/builder.R"),
           QVEST_RF_CLAIM = file.path(S, ".cache/reinforce_auto.claim"), QVEST_L2_CLAIM = file.path(S, ".cache/rf_l2_auto.claim"),
           QVEST_RF_CONFIG = file.path(S, "06_Registry/reinforce_auto_config.json"), QVEST_RP_JLOG = JL,
           QVEST_L2_NOTIFY = "0", QVEST_TG_DRY_RUN = "1", QVEST_L2_REQUEST = file.path(S, "06_Registry/l2_unit_request.json"))
run <- function() { o <- suppressWarnings(system2("Rscript", c(shQuote(DRV), sprintf("--root=%s", S)), stdout = TRUE, stderr = TRUE)); list(out = o, rc = attr(o, "status") %||% 0L) }
events <- function() if (!file.exists(JL)) character(0) else vapply(readLines(JL, warn = FALSE), function(l) tryCatch(fromJSON(l)$event, error = function(e) ""), character(1))
JR <- file.path(S, "06_Registry/l2_judge_request.json"); JH <- file.path(S, "06_Registry/l2_judge_request.held.json")
reset <- function() { unlink(c(JR, JH, JL)); write_led(); write_req() }
claims_free <- function() all(vapply(c(".cache/reinforce_auto.claim", ".cache/rf_l2_auto.claim"), function(p) { p <- file.path(S, p); !dir.exists(p) || file.exists(file.path(p, "released.json")) }, logical(1)))

reset(); invisible(mk_pool(c(clean, list(M3 = list(run = "20261112_030000_3", epoch = NULL))))); r <- run(); ev <- events()
h <- if (file.exists(JH)) fromJSON(JH, simplifyVector = FALSE) else list()
chk(file.exists(JH) && !file.exists(JR) && identical(h$status, "held") && "judge_held" %in% ev && !("judge_requested" %in% ev),
    "S5 A · 혼합 풀 → held 파일만 · Judge 요청 없음 · jlog judge_held", paste(c(r$rc, tail(r$out, 4)), collapse = " | "))
chk(any(grepl("pool_epoch_off_active", unlist(h$a_eligibility$reasons))), "S5 held 사유 = pool_epoch_off_active")

reset(); invisible(mk_pool(clean)); r <- run(); ev <- events()
j <- if (file.exists(JR)) fromJSON(JR, simplifyVector = FALSE) else list()
chk(file.exists(JR) && !file.exists(JH) && identical(j$schema, "l2_judge_request_v1") && identical(j$status, "pending") && isTRUE(j$a_eligibility$eligible) && "judge_requested" %in% ev,
    "S6 A · 깨끗한 풀 → l2_judge_request.json(v1 + a_eligibility · pending · a_eligibility.eligible)", paste(c(r$rc, tail(r$out, 4)), collapse = " | "))
chk(identical(fromJSON(file.path(S, "06_Registry/l2_unit_request.json"))$status, "done"), "S6 요청 done")

cat("\n")
reset(); invisible(mk_pool(clean)); invisible(file.create(file.path(S, "stubs/FAIL_T"))); r <- run(); ev <- events(); unlink(file.path(S, "stubs/FAIL_T"))
rq <- fromJSON(file.path(S, "06_Registry/l2_unit_request.json"))
chk(r$rc == 1L && identical(rq$status, "failed") && grepl("arm T", rq$error %||% "") && "l2_error" %in% ev, "S7 T arm 산출 누락 → rc 1 · 요청 failed(사유 arm T) · l2_error", paste(r$rc, rq$status))
chk(!file.exists(JR) && !file.exists(JH) && claims_free(), "S7 Judge 요청/보류 없음 · claim 2종 해제")
led <- fromJSON(file.path(S, "06_Registry/reinforce_ledger_l2.json"), simplifyVector = FALSE)$entries[[1]]
chk(isTRUE(led$attempts_used == 1) && is.null(led$attempts[[1]]$grade), "S7 원장: 시행은 실행 전 계상(attempts_used 1) · 결과 미기록(grade 없음) — 실패 시행도 시행 수에 남는다")

unlink(JL); r <- run(); ev <- events()
chk("not_due" %in% ev && !("l2_start" %in% ev), "S8 failed 요청 재실행 → not_due(자동 재시도 없음 · 사람이 새 요청)")
led2 <- fromJSON(file.path(S, "06_Registry/reinforce_ledger_l2.json"), simplifyVector = FALSE)$entries[[1]]
chk(isTRUE(led2$attempts_used == 1), "S8 재실행이 시행 수를 늘리지 않는다(멱등)")

cat("\n=== D 배분기 가중 ===\n")
DP <- new.env(); invisible(capture.output(sys.source(file.path(CR, "02_Infrastructure/portfolio/module_dispatcher.R"), envir = DP)))
set.seed(1); ir <- setNames(c(0.5, -0.2, NA, 1.2, 0.1, 0.3), paste0("m", 1:6)); vo <- setNames(c(0.01, 0.02, NA, 0.015, 0, 0.012), names(ir))
w <- suppressWarnings(DP$compute_regime_module_weights(ir, vo, n_regime = setNames(c(40, 10, NA, 80, 5, 30), names(ir))))
chk(all(is.finite(w)) && all(w >= 0) && abs(sum(w) - 1) < 1e-9 && all(w <= 0.25 + 1e-9), "D1 6모듈(NA IR · NA/0 vol 포함) → 유한 · w≥0 · Σw=1 · cap 0.25", paste(round(w, 4), collapse = ","))
w1 <- DP$compute_regime_module_weights(setNames(0.3, "m1"), setNames(0.01, "m1"))
chk(identical(unname(w1), 1) && length(DP$compute_regime_module_weights(setNames(numeric(0), character(0)), numeric(0))) == 0L, "D2 모듈 1개 → 1 · 0개 → 빈 벡터")
w3 <- suppressWarnings(DP$compute_regime_module_weights(setNames(c(1, 0, 0), c("a", "b", "c")), setNames(c(0.01, 0.01, 0.01), c("a", "b", "c"))))
chk(abs(sum(w3) - 1) < 1e-9 && any(w3 > 0.25), "D3 [사실 고정] 모듈 ≤3 이면 cap 0.25 는 Σw=1 과 양립 불가 — 렌옴이 cap 을 넘긴다(조용히 · 경고 없음)")

cat("\n=== P1 풀 게이트 사실 ===\n")
Sys.setenv(CLAUDE_PROJECT_DIR = CR)
PA <- new.env(); sys.source(file.path(CR, "02_Infrastructure/regime/l2_pool_admission.R"), envir = PA)
aC <- PA$l2_admit(list(essence_grade = "C", meta = list(has_short = FALSE)), floor = "B", defensive_route = FALSE)
aB <- PA$l2_admit(list(essence_grade = "B", meta = list(has_short = FALSE)), floor = "B", defensive_route = FALSE)
chk(!isTRUE(aC$eligible) && isTRUE(aB$eligible), "P1a l2_admit: essence C 거부 · B 편입(legacy floor 정상)")
bsrc <- readLines(file.path(CR, "02_Infrastructure/regime/build_module_performance.R"), warn = FALSE, encoding = "UTF-8")
chk(any(grepl('eligible = TRUE, route = "role_rep"', bsrc, fixed = TRUE)),
    "P1b [사실 고정] 운영 풀 모드 role 은 역할 대표를 essence 무관 eligible=TRUE 로 편입(문서의 'essence B+ 2단 게이트'와 다름 — 보고서 F-2)")
unlink(S, recursive = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"scn_l2_a_gate","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
