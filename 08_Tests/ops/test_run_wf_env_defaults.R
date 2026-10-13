#!/usr/bin/env Rscript
#==============================================================================
# test_run_wf_env_defaults.R — 2계층 러너 env 추가 4줄의 **기본값 = 구동작** 계약 (2026-09-21 플랜 Part 3 · D2)
#
# FR_MODULE_PERF(러너·.rcma_load) 미설정 = 정본 06_Registry/module_performance.json · FR_SELECTION_TYPE 미설정 =
#   essence_score 에 selection_type 미전달(구동작) + L-code 리터럴 "chain" 유지. 두 파일이 같은 env 이름을 쓴다.
# 판정: 정적(정의 줄의 기본값 표현) + 동적(작은 R 프로세스에서 같은 표현을 평가 — env 미설정/설정 양방향).
#
# (v10.01 2026-10-13) 마지막 항목 "1계층 러너는 FR_MODULE_PERF 를 모른다" 의 대상 reinforce_auto_parallel.R 이 퇴역(코드 삭제)했다 —
#   같은 불간섭 계약을 살아 있는 1계층 측정 경로(충실구현 레인 rf_replication_auto.sh → 검증기 rf_replication_verify.R →
#   측정 계약 run_paper_replication.R)로 옮겼다. 롤백 태그 pre-v10.01-prescription-20261013
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
## (v10.01) 1계층 러너 퇴역 → 살아 있는 1계층 측정 경로 3파일이 2계층 env 를 모르는가(파일 부재 = 실패 — 대상이 사라지면 조용히 통과하지 않는다)
L1 <- c("02_Infrastructure/ops/rf_replication_auto.sh", "02_Infrastructure/ops/rf_replication_verify.R",
        "02_Infrastructure/alpha_search/run_paper_replication.R")
l1_miss <- L1[!file.exists(file.path(ROOT, L1))]
l1_hit <- Filter(function(f) any(grepl("FR_MODULE_PERF", code(readLines(file.path(ROOT, f), warn = FALSE, encoding = "UTF-8")), fixed = TRUE)),
                 setdiff(L1, l1_miss))
if (!length(l1_miss) && !length(l1_hit)) ok("1계층 측정 경로(충실구현 레인·검증기·run_paper_replication)는 FR_MODULE_PERF 를 모른다(영향 0)") else
  ng("1계층 측정 경로 접촉", paste(c(if (length(l1_miss)) paste("부재:", paste(l1_miss, collapse = ",")),
                                     if (length(l1_hit)) paste("참조:", paste(l1_hit, collapse = ","))), collapse = " · "))
finish()
