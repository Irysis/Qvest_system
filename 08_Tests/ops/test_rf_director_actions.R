#!/usr/bin/env Rscript
#==============================================================================
# test_rf_director_actions.R — 디렉터 실행기 D3 (2026-09-21 도훈 승인 플랜 Part 3)
#
# 샌드박스 root 에서 dir_execute() 를 직접 검사한다(운영 무접촉).
#   ① act=false → 실행 0 · executed=FALSE   ② open_l2_unit → l2_unit_request.json pending 발행 · executed=TRUE
#   ③ 같은 슬롯 pending 이면 재발행 0   ④ directed_combination → 실제 결합 런처(--directed) 가 요청을 발행(적격 재료)
#   ⑤ directed 재료가 적격 풀 밖(파킹/음수 t) → halt_directed_ineligible · unreachable 표식 · 요청 미발행
#   ⑥ 런처 --dry-run --directed → directed_pair + dry_run, 요청 미발행
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- sub("/+$", "", gsub("\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"), fixed = TRUE))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
finish <- function() { cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"rf_director_actions","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', PASS, FAIL, PASS + FAIL)); quit(status = if (FAIL == 0L) 0L else 1L) }
S <- gsub("\\", "/", file.path(tempdir(), sprintf("rf_dir_act_%d", Sys.getpid())), fixed = TRUE)
for (d in c("06_Registry", "02_Infrastructure/reinforcement", ".cache", "eng", "art/A", "art/B", "art/P")) dir.create(file.path(S, d), recursive = TRUE, showWarnings = FALSE)
writeLines("# marker", file.path(S, "02_Infrastructure/config.R"))
# ★결합 런처는 코드 루트와 데이터 루트를 가르지 않는다(ROOT 하나) — 샌드박스에 원장 모듈 사본을 둔다(코드는 실제 파일 그대로)
invisible(file.copy(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R"), file.path(S, "02_Infrastructure/reinforcement/reinforce_ledger.R")))
Sys.setenv(QVEST_DIRECTOR_NO_MAIN = "1")
E <- new.env(parent = globalenv()); sys.source(file.path(ROOT, "02_Infrastructure/ops/rf_director.R"), envir = E)
E$DR_ROOT <- S; E$DR_CODE_ROOT <- ROOT
# ── 원장 픽스처: A(최고 계보 · combo 아님 · t 3.0) · B(방어형 논문 · t 1.5 · exhausted) · P(파킹 · 음수 t) — 엔진 파일 존재 · url 보유 ──
for (k in c("A", "B", "P")) { writeLines("x", file.path(S, "eng", paste0(k, ".R")))
  writeLines(toJSON(list(replication = list(source_paper = list(url = paste0("https://arxiv.org/abs/", k), title = paste0("paper ", k))), essence = list(portfolio_alpha_t_nw_lag3 = if (k == "P") -0.5 else 1.0)), auto_unbox = TRUE), file.path(S, "art", k, "authoritative_remeasure.json")) }
ent <- function(id, key, st, t) list(base_id = id, status = st, paper_key = key, engine_path = file.path(S, "eng", paste0(key, ".R")), base_artifacts = file.path(S, "art", key), attempts_used = 1,
                                     attempts = list(list(n = 1, cell_code = "B1_1", grade = "B", essence = list(port_t = t, calmar = 0.5, cagr = 0.2, mdd = 0.4, net_sharpe = 1, oos_retention = 0.8, cell_code = "B1_1"))))
led <- list(schema_version = "reinforce_ledger_v2", layer = 1, max_attempts = 25, entries = list(ent("RP_A", "A", "exhausted", 3.0), ent("RP_B", "B", "exhausted", 1.5), ent("RP_P", "P", "parked", -0.5)),
            combination_review = list(papers_since_last_review = 0, last_review_date = "", history = list()), last_updated = "")
writeLines(toJSON(led, auto_unbox = TRUE, pretty = TRUE), file.path(S, "06_Registry/reinforce_ledger_l1.json"))
writeLines(toJSON(list(modules = list(STR_B = list(strategy_id = "STR_B", meta = list(paper_key = "B")), STR_P = list(strategy_id = "STR_P", meta = list(paper_key = "P")))), auto_unbox = TRUE), file.path(S, "06_Registry/module_catalog.json"))
mp <- function(sid) writeLines(toJSON(list(n_modules = 1, modules = list(M = list(source_strategy_id = sid, admission_route = "defensive_specialist", admission_reason = "등급 C 이나 방어형 자격 — 하락월 100개: 초과 +1.00%/월 (t 3.0 · 적중 60%) · 벤치-10% 이하 9개: 초과 +2.00%/월 · 상승월 초과 -0.5%/월"))), auto_unbox = TRUE), file.path(S, "06_Registry/module_performance.json"))
writeLines(toJSON(list(enabled = TRUE, combination = list(enabled = TRUE, enumerate_top_items = 12), director = list(act = TRUE)), auto_unbox = TRUE), file.path(S, "06_Registry/reinforce_auto_config.json"))
writeLines(toJSON(list(status = "done", source = "t"), auto_unbox = TRUE), file.path(S, "06_Registry/replication_request.json"))
out <- list(program_best = list(sid = "RP_A:B1_1"), verdict = list(note = "t"))
cfg_off <- list(act = FALSE); cfg_on <- list(act = TRUE)
rec_l2 <- list(action = "open_l2_unit", rule = "rule2", unit = list(kind = "l2_unit", base_id = "FR_003", axis = "strategy_combination", arms = c("T", "S", "C"), idea = "풀 재측정"))

cat("=== ① act=false ===\n")
r <- E$dir_execute(rec_l2, out, cfg_off, S, ROOT)
if (isFALSE(r$executed) && !file.exists(file.path(S, "06_Registry/l2_unit_request.json"))) ok("① act=false → 실행 0") else ng("① act=false 에서 실행됨")
cat("=== ② open_l2_unit ===\n")
r <- E$dir_execute(rec_l2, out, cfg_on, S, ROOT)
q <- if (file.exists(file.path(S, "06_Registry/l2_unit_request.json"))) fromJSON(file.path(S, "06_Registry/l2_unit_request.json"), simplifyVector = FALSE) else NULL
if (isTRUE(r$executed) && !is.null(q) && identical(q$status, "pending") && identical(q$base_id, "FR_003") && identical(q$requested_by, "rf_director") && length(q$next_probe) == 2L) ok("② 요청 발행: pending · FR_003 · requested_by=rf_director · next_probe 2") else ng("② 요청 발행", paste(r$executed, r$execute_note))
cat("=== ③ 슬롯 busy ===\n")
r <- E$dir_execute(rec_l2, out, cfg_on, S, ROOT)
if (isFALSE(r$executed) && grepl("busy|pending", r$execute_note)) ok("③ pending 슬롯 → 재발행 0") else ng("③ 재발행 억제", r$execute_note)
cat("=== ④ directed_combination (적격) ===\n")
mp("STR_B")
rec_dc <- list(action = "directed_combination", rule = "rule3", unit = list(kind = "directed_combination"))
r <- E$dir_execute(rec_dc, out, cfg_on, S, ROOT)
rq <- fromJSON(file.path(S, "06_Registry/replication_request.json"), simplifyVector = FALSE)
if (isTRUE(r$executed) && identical(rq$status, "pending") && identical(rq$source, "rf_combination_launch") && identical(rq$combo$setkey, "A+B")) ok(sprintf("④ 지시 결합 요청 발행 setkey=%s · 방어형 %s", rq$combo$setkey, r$unit$defensive_sid)) else ng("④ 지시 결합", paste(r$executed, r$execute_note, r$unit$launcher_event))
cat("=== ⑤ directed_combination (부적격: 파킹·음수 t) ===\n")
writeLines(toJSON(list(status = "done", source = "t"), auto_unbox = TRUE), file.path(S, "06_Registry/replication_request.json")); mp("STR_P")
r <- E$dir_execute(rec_dc, out, cfg_on, S, ROOT)
rq <- fromJSON(file.path(S, "06_Registry/replication_request.json"), simplifyVector = FALSE)
if (isFALSE(r$executed) && identical(r$unit$launcher_event, "halt_directed_ineligible") && isTRUE(r$unit$unreachable) && identical(rq$status, "done")) ok("⑤ 파킹 재료 → halt_directed_ineligible · unreachable · 요청 미발행") else ng("⑤ 부적격 처리", paste(r$executed, r$unit$launcher_event, r$execute_note))
cat("=== ⑥ 런처 --dry-run --directed ===\n")
Sys.setenv(QVEST_RF_ROOT = S)
o <- suppressWarnings(system2("Rscript", c(shQuote(file.path(ROOT, "02_Infrastructure/ops/rf_combination_launch.R")), "--directed=A,B", "--dry-run"), stdout = TRUE, stderr = TRUE))
Sys.unsetenv("QVEST_RF_ROOT")
rq <- fromJSON(file.path(S, "06_Registry/replication_request.json"), simplifyVector = FALSE)
if (any(grepl("^\\[combo\\] directed_pair", o)) && any(grepl("^\\[combo\\] dry_run", o)) && identical(rq$status, "done")) ok("⑥ dry-run: directed_pair + dry_run · 요청 미발행") else ng("⑥ dry-run", paste(grep("^\\[combo\\]", o, value = TRUE), collapse = " | "))
unlink(S, recursive = TRUE)
finish()
