#!/usr/bin/env Rscript
#==============================================================================
# test_rf_director_contract.R — 리서치 디렉터 진단 계약 (2026-09-21 도훈 승인 플랜 Part 3 · D0)
#
# 계약: ① 정본 값을 옮길 뿐 재계산하지 않는다(essence 항등) ② 스키마 필드 전수 ③ 날짜를 산출에 넣지 않는다
#       ④ 방향 규칙 π_dir v0 가 분기마다 정의된 행동을 낸다(양쪽 방향 — 열어야 할 때 열고, 막아야 할 때 막는다)
#       ⑤ 샌드박스 루트에서 끝까지 돈다(운영 원장·캐시 무접촉).
# 판정은 산출 파일의 값으로만 한다. 소스 문자열 단정 없음(리팩터가 옮기는 좌표를 못박지 않는다).
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- sub("/+$", "", gsub("\\", "/", ROOT, fixed = TRUE))
SCRIPT <- file.path(ROOT, "02_Infrastructure/ops/rf_director.R")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
finish <- function() { cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"rf_director_contract","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', PASS, FAIL, PASS + FAIL))
  quit(status = if (FAIL == 0L) 0L else 1L) }
DATE_RE <- "20[0-9]{2}-[0-9]{2}(-[0-9]{2})?"

# ── ① 순수 함수: 규칙 π_dir v0 (source · main 미실행) ────────────────────────────────────────
Sys.setenv(QVEST_DIRECTOR_NO_MAIN = "1")
E <- new.env(parent = globalenv())
sys.source(SCRIPT, envir = E)
cfg <- list(act = TRUE, max_units_per_day = 1L, min_adversary_n = 10L)
V_cal <- list(binding_condition = "calmar", co_binding = list(), n_lineages_bound = 5L, n_lineages = 5L, revenue_axes_met = TRUE)
OV_dead <- list(status = "dead", arms_measured = 25L, adv_pass = 0L, adv_fail = 9L, adv_other = 26L)
OV_unm  <- list(status = "unmeasured", arms_measured = 0L, adv_pass = 0L, adv_fail = 0L, adv_other = 0L)
L2 <- list(active_entry = "FR_003", attempts_used = 0, pool_n_now = 352, pool_n_at_last_run = 89, last_mc1_delivered = FALSE)
CB_done <- list(request_status = "done"); POOL <- list(n_surviving_binding_class = 177L)
r <- E$dir_rule_v0(V_cal, OV_dead, L2, CB_done, POOL, cfg, 0L, FALSE, list(busy = FALSE))
if (identical(r$action, "open_l2_unit") && identical(r$rule, "rule2_calmar_bound_overlay_dead") && identical(r$unit$kind, "l2_unit")) ok("규칙2: Calmar 구속 ∧ B5 dead ∧ L2 유휴 → open_l2_unit") else ng("규칙2 open_l2_unit", r$action)
if (isFALSE(r$executed) && length(r$alternatives) >= 3L) ok("규칙2: executed=FALSE · 대안 ≥3 기록") else ng("규칙2 대안/실행 표식")
if (any(grepl("MC1", unlist(r$proposals)))) ok("규칙4 감시: MC1 미발화 제안 동반") else ng("규칙4 제안 없음")
r <- E$dir_rule_v0(V_cal, OV_dead, L2, CB_done, POOL, cfg, 0L, FALSE, list(busy = TRUE))
if (identical(r$action, "directed_combination") && identical(r$rule, "rule3_l2_busy_combination_slot_free")) ok("규칙3: L2 진행 중 ∧ 결합 슬롯 terminal ∧ 방어형 ≥3 → directed_combination") else ng("규칙3", r$action)
r <- E$dir_rule_v0(V_cal, OV_dead, L2, list(request_status = "pending"), POOL, cfg, 0L, FALSE, list(busy = TRUE))
if (identical(r$action, "none") && identical(r$rule, "rule3_wait")) ok("규칙3 음성: 결합 슬롯 busy → none") else ng("규칙3 음성", r$action)
r <- E$dir_rule_v0(V_cal, OV_unm, L2, CB_done, POOL, cfg, 0L, FALSE, list(busy = FALSE))
if (identical(r$action, "b5_context_only") && identical(r$rule, "rule2_overlay_not_dead")) ok("규칙2 음성: 오버레이 미측정 → b5_context_only (2계층 안 연다)") else ng("규칙2 음성", r$action)
r <- E$dir_rule_v0(list(binding_condition = "port_t", co_binding = list(), revenue_axes_met = FALSE), OV_dead, L2, CB_done, POOL, cfg, 0L, FALSE, list(busy = FALSE))
if (identical(r$action, "none") && identical(r$rule, "rule1_revenue_axis_bound")) ok("규칙1: 수익 축 구속 → none(1계층 레인 소관)") else ng("규칙1", r$action)
r <- E$dir_rule_v0(V_cal, OV_dead, L2, CB_done, POOL, cfg, 1L, FALSE, list(busy = FALSE))
if (identical(r$rule, "rule0_budget")) ok("규칙0: 일 예산 소진 → none") else ng("규칙0 예산", r$rule)
r <- E$dir_rule_v0(V_cal, OV_dead, L2, CB_done, POOL, cfg, 0L, TRUE, list(busy = FALSE))
if (identical(r$rule, "rule0_stale_inputs")) ok("규칙0: 입력 낡음 → none") else ng("규칙0 stale", r$rule)
r <- E$dir_rule_v0(list(binding_condition = "oos_retention", co_binding = list(), revenue_axes_met = TRUE), OV_dead, L2, CB_done, POOL, cfg, 0L, FALSE, list(busy = FALSE))
if (identical(r$action, "proposal") && identical(r$rule, "rule5_oos_bound")) ok("규칙5: OOS 구속 → proposal") else ng("규칙5", r$action)
r <- E$dir_rule_v0(list(binding_condition = "calmar", co_binding = list("oos_retention"), n_lineages_bound = 5L, n_lineages = 5L, revenue_axes_met = TRUE), OV_dead, L2, CB_done, POOL, cfg, 0L, FALSE, list(busy = FALSE))
if (any(grepl("OOS retention", unlist(r$proposals)))) ok("공동 구속 oos → 제안에 반영") else ng("공동 구속 제안 누락")

# ── ② 구속 조건 산출(essence 항등 · co_binding) ───────────────────────────────────────────────
th <- list(port_t_min = 2.95, calmar_min = 0.64, oos_min = 0.7, oos_floor = 0.5, sharpe_min = 0.8, cagr_min = 0.16)
L <- data.table::data.table(lineage = c("A", "B"), sid = c("A:B1_1", "B"), source = c("l1", "cat"), grade = c("B", "B"),
                            port_t = c(3.5, 2.5), calmar = c(0.5, 0.3), cagr = c(0.2, 0.17), mdd = c(0.4, 0.6),
                            sharpe = c(1.0, 0.9), oos_retention = c(0.8, 0.1), artifacts = c("", ""))
b <- E$dir_binding(L, th)
if (identical(b$verdict$binding_condition, "calmar") && b$verdict$n_lineages_bound == 2L && isTRUE(b$verdict$revenue_axes_met)) ok("구속 = calmar(2/2) · 수익 축 충족") else ng("구속 판정", b$verdict$binding_condition)
if (identical(b$lineages[[1]]$port_t, 3.5) && identical(b$lineages[[1]]$calmar, 0.5) && identical(b$lineages[[1]]$binding, "calmar")) ok("essence 값 항등(재계산 0) · 최고 계보 binding=calmar 만") else ng("essence 항등")
if (identical(b$lineages[[2]]$binding, c("port_t", "calmar", "oos_retention"))) ok("2번 계보 binding = port_t+calmar+oos") else ng("2번 계보 binding", paste(b$lineages[[2]]$binding, collapse = ","))
if (isTRUE(all.equal(b$lineages[[1]]$gap$cagr_needed_at_mdd, 0.64 * 0.4))) ok("gap 산술 = rf_round_review 동형(calmar_min × MDD)") else ng("gap 산술")
L2t <- data.table::copy(L); L2t$oos_retention <- c(0.1, 0.1)
b2 <- E$dir_binding(L2t, th)
if (identical(b2$verdict$binding_condition, "calmar") && identical(unlist(b2$verdict$co_binding), "oos_retention")) ok("동률(calmar 2 · oos 2) → calmar 주 구속 + oos 공동 구속") else ng("공동 구속", paste(unlist(b2$verdict$co_binding), collapse = ","))

# ── ③ 샌드박스 e2e (운영 무접촉) ─────────────────────────────────────────────────────────────
S <- file.path(tempdir(), sprintf("rf_director_%d", Sys.getpid()))
for (d in c("06_Registry", "02_Infrastructure/worktask", ".cache", "art/top", "04_Research/strategies/STR_T")) dir.create(file.path(S, d), recursive = TRUE, showWarnings = FALSE)
invisible(file.copy(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), file.path(S, "02_Infrastructure/worktask/constraint_defaults.json")))
# 합성 NAV: 120개월 · 30% 낙폭 8개월 · 회복 — 벤치 20% 낙폭
dts <- seq(as.Date("2015-01-31"), by = "month", length.out = 120)
nav <- cumprod(c(1, rep(1.01, 39), rep(0.9564, 8), rep(1.02, 20), rep(1.005, 51)))[1:120]
bnv <- cumprod(c(1, rep(1.008, 39), rep(0.9725, 8), rep(1.015, 20), rep(1.004, 51)))[1:120]
data.table::fwrite(data.frame(date = dts, nav_net = nav), file.path(S, "art/top/02_nav.csv"))
data.table::fwrite(data.frame(date = dts, benchmark_nav = bnv), file.path(S, "art/top/05_benchmark_returns.csv"))
art <- gsub("\\", "/", file.path(S, "art/top"), fixed = TRUE)
led1 <- list(schema_version = "reinforce_ledger_v2", layer = 1, max_attempts = 25, entries = list(
  list(base_id = "RP_T_ONE", status = "active", attempts_used = 2, search_adaptive = TRUE, block_order_reason = "Calmar 미달 → 위험 축 먼저", attempts = list(
    list(n = 1, cell_code = "B1_1", grade = "B", artifacts = art, essence = list(cell_code = "B1_1", block = "B1", port_t = 3.5, calmar = 0.5, cagr = 0.2, mdd = 0.4, net_sharpe = 1.0, oos_retention = 0.8)),
    list(n = 2, cell_code = "B1_2", grade = "C", artifacts = art, essence = list(cell_code = "B1_2", block = "B1", port_t = 1.2, calmar = 0.2, cagr = 0.1, mdd = 0.5, net_sharpe = 0.5, oos_retention = 0.3)))),
  list(base_id = "RP_T_PARKED", status = "parked", attempts_used = 0, attempts = list())),
  combination_review = list(papers_since_last_review = 1, last_review_date = "2026-09-17", history = list()))
writeLines(toJSON(led1, auto_unbox = TRUE, pretty = TRUE), file.path(S, "06_Registry/reinforce_ledger_l1.json"))
writeLines(toJSON(list(schema_version = "reinforce_ledger_v2", layer = 2, entries = list(list(base_id = "FR_003", status = "active", attempts_used = 0, attempts = list()))), auto_unbox = TRUE), file.path(S, "06_Registry/reinforce_ledger_l2.json"))
cat_j <- list(modules = list(STR_T = list(strategy_id = "STR_T", grade = "B", module_hash = "h1", sim_result_path = "04_Research/strategies/STR_T/sim_result.rds",
  meta = list(authoritative_essence = list(portfolio_alpha_t_nw_lag3 = 2.5, calmar = 0.3, cagr = 0.17, mdd = 0.6, net_sharpe = 0.9, oos_retention = 0.1)))))
writeLines(toJSON(cat_j, auto_unbox = TRUE), file.path(S, "06_Registry/module_catalog.json"))
mp <- list(schema_version = "v3.1", generated = format(Sys.Date(), "%Y-%m-%d"), grade_floor = "B", n_modules = 3, admission_codes = list(grade_floor = 1, defensive_specialist = 2), modules = list(
  M1 = list(source_strategy_id = "M1", grade = "B", admission_route = "grade_floor", admission_reason = "등급 B — 등급 floor 통과 등재"),
  M2 = list(source_strategy_id = "M2", grade = "C", admission_route = "defensive_specialist", admission_reason = "등급 C 이나 방어형 자격 — 하락월 111개: 초과 +1.54%/월 (t 5.37 · 적중 71%) · 벤치-10% 이하 9개: 초과 +1.23%/월 · 상승월 초과 -0.67%/월"),
  M3 = list(source_strategy_id = "M3", grade = "F", admission_route = "defensive_specialist", admission_reason = "등급 F 이나 방어형 자격 — 하락월 100개: 초과 +0.90%/월 (t 3.10 · 적중 60%) · 벤치-10% 이하 9개: 초과 -0.50%/월 · 상승월 초과 -1.00%/월")))
writeLines(toJSON(mp, auto_unbox = TRUE), file.path(S, "06_Registry/module_performance.json"))
writeLines(toJSON(list(factor_rotations = list(list(fr_id = "FR_003", grade = "C", n_modules = 89, essence = list(calmar = 0.399, port_t = 0.853)))), auto_unbox = TRUE), file.path(S, "06_Registry/factor_rotation_registry.json"))
writeLines(toJSON(list(candidates = list(list(a = 1), list(a = 2))), auto_unbox = TRUE), file.path(S, "06_Registry/combination_candidates.json"))
writeLines(toJSON(list(status = "done", source = "t"), auto_unbox = TRUE), file.path(S, "06_Registry/replication_request.json"))
writeLines(toJSON(list(enabled = TRUE, director = list(enabled = TRUE, act = FALSE, top_k = 5, min_adversary_n = 10)), auto_unbox = TRUE), file.path(S, "06_Registry/reinforce_auto_config.json"))
Sys.setenv(QVEST_DIRECTOR_NO_MAIN = "")
out <- suppressWarnings(system2("Rscript", c(shQuote(SCRIPT), sprintf("--root=%s", gsub("\\", "/", S, fixed = TRUE))), stdout = TRUE, stderr = TRUE))
J <- file.path(S, ".cache/rf_director_latest.json"); M <- file.path(S, "06_Registry/layer_bottleneck_map.md")
if (file.exists(J) && file.exists(M)) ok("샌드박스 e2e: 캐시 + 지도 생성") else { ng("샌드박스 e2e 산출 부재", paste(tail(out, 5), collapse = " | ")); finish() }
d <- fromJSON(J, simplifyVector = FALSE)
need <- c("schema", "as_of", "thresholds", "program_best", "lineages", "verdict", "dd_episodes", "lever_health", "pool_inventory", "unreachable", "recommendation", "boot_line", "inputs_age")
miss <- setdiff(need, names(d)); if (!length(miss)) ok("스키마 필드 전수") else ng("스키마 결손", paste(miss, collapse = ","))
if (identical(d$program_best$port_t, 3.5) && identical(d$program_best$calmar, 0.5) && identical(d$program_best$sid, "RP_T_ONE:B1_1")) ok("최고 계보 = 원장 B1_1 · 값 항등") else ng("최고 계보/항등", paste(d$program_best$sid, d$program_best$port_t))
if (identical(d$verdict$binding_condition, "calmar") && d$verdict$n_lineages == 2L) ok("verdict calmar · 계보 2(원장+카탈로그 합집합)") else ng("verdict", d$verdict$binding_condition)
if (identical(d$thresholds$calmar_min, 0.64) && grepl("constraint_defaults.json", d$thresholds$source)) ok("문턱 = constraint_defaults.json 정본") else ng("문턱 출처", d$thresholds$source)
ep <- d$dd_episodes$per_lineage[[1]]$episodes
if (length(ep) >= 1L && abs(ep[[1]]$depth - 0.30) < 0.02 && isTRUE(ep[[1]]$recovered)) ok(sprintf("낙폭 해부: 최심 %.1f%% · 회복 (b5_drawdown_episodes 재사용)", 100 * ep[[1]]$depth)) else ng("낙폭 해부", if (length(ep)) as.character(ep[[1]]$depth) else "없음")
if (identical(d$lever_health$overlay_B5$status, "unmeasured") && identical(d$recommendation$action, "b5_context_only")) ok("오버레이 미측정 → 권고 b5_context_only (2계층 안 연다)") else ng("권고", paste(d$lever_health$overlay_B5$status, d$recommendation$action))
if (isFALSE(d$recommendation$executed)) ok("D0: executed=FALSE") else ng("executed 표식")
if (identical(d$lever_health$L2$last_fr, "FR_003") && isTRUE(d$lever_health$L2$pool_n_at_last_run == 89) && isTRUE(d$lever_health$L2$pool_n_now == 3)) ok("L2: FR_003 · 풀 89→3") else ng("L2 필드", paste(d$lever_health$L2$last_fr, d$lever_health$L2$pool_n_at_last_run, d$lever_health$L2$pool_n_now))
if (identical(d$pool_inventory$defensive_n, 2L) && isTRUE(all.equal(d$pool_inventory$defensive_deep_dd_excess_median, 0.365)) && identical(d$pool_inventory$n_surviving_binding_class, 1L)) ok("풀 파서: 방어형 2 · 깊은낙폭 초과 중앙 +0.365 · 생존 1") else ng("풀 파서", paste(d$pool_inventory$defensive_n, d$pool_inventory$defensive_deep_dd_excess_median))
if (identical(d$unreachable$l1_parked, 1L) && identical(d$unreachable$l1_active, 1L)) ok("unreachable 집계") else ng("unreachable")
if (nchar(d$boot_line, type = "chars") <= 120L && startsWith(d$boot_line, "Director:")) ok(sprintf("boot_line ≤120자 (%d)", nchar(d$boot_line, type = "chars"))) else ng("boot_line", d$boot_line)
if (!grepl(DATE_RE, d$boot_line)) ok("boot_line 에 날짜 없음") else ng("boot_line 날짜 노출")
mdtxt <- paste(readLines(M, encoding = "UTF-8", warn = FALSE), collapse = "\n")
if (!grepl(DATE_RE, mdtxt)) ok("지도에 날짜 없음(연속성 가드 sha 신선도 규약)") else ng("지도 날짜 노출")
if (grepl("\\| 1계층 \\| calmar", mdtxt) && grepl("\\| 2계층 \\| FR FR_003", mdtxt)) ok("지도 표 행: 1계층·2계층") else ng("지도 표 행")
unlink(S, recursive = TRUE)
finish()
