#!/usr/bin/env Rscript
#==============================================================================
# test_run_wf_env_defaults.R — 2계층 러너 env 추가 4줄의 **기본값 = 구동작** 계약 (2026-09-21 플랜 Part 3 · D2)
#
# FR_MODULE_PERF(러너·.rcma_load) 미설정 = 정본 06_Registry/module_performance.json · FR_SELECTION_TYPE 미설정 =
#   essence_score 에 selection_type 미전달(구동작) + L-code 리터럴 "chain" 유지. 두 파일이 같은 env 이름을 쓴다.
# 판정: 정적(정의 줄의 기본값 표현) + 동적(작은 R 프로세스에서 같은 표현을 평가 — env 미설정/설정 양방향).
#==============================================================================
ROOT <- sub("/+$", "", gsub("\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"), fixed = TRUE))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
finish <- function() { cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"run_wf_env_defaults","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', PASS, FAIL, PASS + FAIL)); quit(status = if (FAIL == 0L) 0L else 1L) }
R <- readLines(file.path(ROOT, "04_Research/factor_rotation/run_wf_ensemble.R"), encoding = "UTF-8", warn = FALSE)
A <- readLines(file.path(ROOT, "02_Infrastructure/portfolio/regime_module_admission.R"), encoding = "UTF-8", warn = FALSE)
code <- function(L) L[!grepl("^\\s*#", L)]
r <- code(R); a <- code(A)
if (any(grepl('FR_MODULE_PERF <- Sys.getenv("FR_MODULE_PERF", "")', r, fixed = TRUE)) && any(grepl('if (nzchar(FR_MODULE_PERF)) FR_MODULE_PERF else file.path(PROJ,"06_Registry/module_performance.json")', r, fixed = TRUE)))
  ok("러너 FR_MODULE_PERF: 미설정 → 정본 경로") else ng("러너 FR_MODULE_PERF 기본값")
if (any(grepl('Sys.getenv("FR_MODULE_PERF", "")', a, fixed = TRUE)) && any(grepl('else file.path(proj,"06_Registry/module_performance.json")', a, fixed = TRUE)))
  ok(".rcma_load FR_MODULE_PERF: 미설정 → 정본 경로 (러너와 같은 env 이름)") else ng(".rcma_load FR_MODULE_PERF 기본값")
if (any(grepl('FR_SELECTION_TYPE <- Sys.getenv("FR_SELECTION_TYPE", "")', r, fixed = TRUE)) && any(grepl('else essence_score(bt, n_trials_cumulative = N_TRIALS)', r, fixed = TRUE)))
  ok("러너 FR_SELECTION_TYPE: 미설정 → essence_score 에 selection_type 미전달(구동작)") else ng("러너 selection_type 기본값")
if (any(grepl('selection_type = if (nzchar(FR_SELECTION_TYPE)) FR_SELECTION_TYPE else "chain"', r, fixed = TRUE)))
  ok("L-code selection_type: 미설정 → 리터럴 \"chain\" 유지 · 설정 시 essence 와 동일 값") else ng("L-code selection_type")
if (!any(grepl('essence_score(bt, n_trials_cumulative = N_TRIALS, selection_type = "', r, fixed = TRUE))) ok("러너가 selection_type 리터럴을 박아 넣지 않는다(결정은 config 에서만)") else ng("selection_type 리터럴 주입")
# 동적: 같은 표현을 자식 R 에서 env 유무로 평가
expr <- 'FR_MODULE_PERF <- Sys.getenv("FR_MODULE_PERF", ""); PROJ <- "X"; cat(if (nzchar(FR_MODULE_PERF)) FR_MODULE_PERF else file.path(PROJ,"06_Registry/module_performance.json"))'
o1 <- system2("Rscript", c("-e", shQuote(expr)), stdout = TRUE); Sys.setenv(FR_MODULE_PERF = "Y/pool.json"); o2 <- system2("Rscript", c("-e", shQuote(expr)), stdout = TRUE); Sys.unsetenv("FR_MODULE_PERF")
if (identical(trimws(o1[length(o1)]), "X/06_Registry/module_performance.json") && identical(trimws(o2[length(o2)]), "Y/pool.json")) ok("동적: env 없음 → 정본 · env 있음 → 변형 풀") else ng("동적 평가", paste(o1, o2))
if (!any(grepl("FR_MODULE_PERF", code(readLines(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R"), warn = FALSE)), fixed = TRUE))) ok("1계층 러너는 FR_MODULE_PERF 를 모른다(영향 0)") else ng("1계층 러너 접촉")
finish()
