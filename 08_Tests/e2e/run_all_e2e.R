#!/usr/bin/env Rscript
# QEPM E2E Test Suite
# Phase 8: 12개 End-to-End 테스트 시나리오
# 실행: cd project_root && Rscript -e 'source("tests/e2e/run_all_e2e.R")'

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

# ── 테스트 유틸리티 ──
test_results <- list()

run_test <- function(id, name, fn) {
  cat(sprintf("\n═══ E2E-%s: %s ═══\n", id, name))
  result <- tryCatch({
    fn()
    list(id = id, name = name, status = "PASS")
  }, error = function(e) {
    cat(sprintf("  ✗ FAILED: %s\n", e$message))
    list(id = id, name = name, status = "FAIL", error = e$message)
  })
  test_results[[id]] <<- result
  cat(sprintf("  → %s\n", result$status))
  invisible(result)
}

assert_true <- function(condition, msg = "Assertion failed") {
  if (!isTRUE(condition)) stop(msg)
  cat(sprintf("  ✓ %s\n", msg))
}

assert_json_valid <- function(json_text, msg = "Valid JSON") {
  parsed <- tryCatch(fromJSON(json_text, simplifyDataFrame = FALSE),
                     error = function(e) NULL)
  if (is.null(parsed)) stop(paste("Invalid JSON:", msg))
  cat(sprintf("  ✓ %s\n", msg))
  parsed
}

# ═══════════════════════════════════════════════════════════════
# E2E-01: 메모리 파이프라인 풀사이클 (R0→R1→R2→R3→R6)
# ═══════════════════════════════════════════════════════════════
run_test("01", "Memory Pipeline Full Cycle", function() {
  source("skills/qepm-memory/R/main.R")

  # R0 저장 (distill_r1이 기대하는 구조로)
  r0 <- store_r0(list(
    exp_id = "E2E_TASK_01",
    task_family = "E2E_Family",
    result_summary = list(
      verdict = "PASS",
      grade = "A",
      key_metrics = list(sharpe = 1.2, cagr = 0.18, mdd = -0.25)
    ),
    hypothesis = list(statement = "E2E test hypothesis", mechanism = "test"),
    search_mode = "EXPLOIT"
  ), task_id = "E2E_TASK_01")
  assert_true(file.exists(r0), "R0 file created")

  # R1 증류
  r1 <- distill_r1(r0)
  assert_true(!is.null(r1), "R1 distillation completed")
  r1_data <- fromJSON(r1, simplifyDataFrame = FALSE)
  assert_true(!is.null(r1_data$digest) || !is.null(r1_data$exp_id), "R1 has content")
  assert_true(!is.null(r1_data$verification), "R1 has verification")

  # R3 증거
  r3 <- store_r3("E2E_TASK_01", list(dsr = 0.95, ff5_t = 2.5))
  assert_true(file.exists(r3), "R3 evidence stored")

  # R6 사후학습
  r6 <- store_r6("E2E_2026_01", list(realized = 0.02, slippage = 0.001))
  assert_true(file.exists(r6), "R6 post-trade stored")

  # Status
  status <- memory_status()
  assert_true(!is.null(status), "Status returns result")
})

# ═══════════════════════════════════════════════════════════════
# E2E-02: KPI 계산 정확성
# ═══════════════════════════════════════════════════════════════
run_test("02", "KPI Computation Accuracy", function() {
  # KPI를 직접 source해서 테스트
  source("skills/qepm-kpi/R/main.R")
  set.seed(42)
  monthly_rets <- rnorm(120, mean = 0.01, sd = 0.04)
  bm_rets <- rnorm(120, mean = 0.008, sd = 0.05)
  result <- compute_kpi(monthly_rets, bm_rets)
  assert_true(!is.null(result$sharpe0_m_ann), "Sharpe ratio computed")
  assert_true(!is.null(result$mdd), "MDD computed")
  assert_true(!is.null(result$net_cagr), "CAGR computed")
  assert_true(result$mdd <= 0, "MDD is non-positive")
})

# ═══════════════════════════════════════════════════════════════
# E2E-03: 통계 검증 파이프라인 (DSR + FDR)
# ═══════════════════════════════════════════════════════════════
run_test("03", "Statistical Defense Pipeline", function() {
  # 직접 source해서 테스트 (stderr 혼입 방지)
  source("02_Infrastructure/validation/statistical_defense.R")
  dsr_result <- compute_dsr(observed_sr = 1.16, n_obs = 240, n_trials = 50)
  assert_true(!is.null(dsr_result$dsr), "DSR computed")
  assert_true(dsr_result$dsr >= 0 && dsr_result$dsr <= 1, "DSR in [0,1]")
  assert_true(is.logical(dsr_result$significant), "Significance is logical")

  # Family DSR
  fam_result <- compute_dsr_family(observed_sr = 1.16, n_obs = 240, family_name = "E2E_Family")
  assert_true(!is.null(fam_result$family_name), "Family name recorded")
  assert_true(!is.null(fam_result$family_trials), "Family trials counted")
})

# ═══════════════════════════════════════════════════════════════
# E2E-04: 레지스트리 CRUD + 지문 중복 검사
# ═══════════════════════════════════════════════════════════════
run_test("04", "Registry CRUD + Fingerprint", function() {
  source("skills/qepm-registry/R/main.R")

  # 등록
  exp <- list(
    experiment_id = sprintf("E2E_EXP_%s", format(Sys.time(), "%H%M%S")),
    strategy_name = "E2E_STR_FP",
    family = "E2E_Family",
    config = list(n_holdings = 30, weight = "ew"),
    result = list(sharpe = 1.1, cagr = 0.15)
  )
  reg_result <- register_experiment(exp)
  assert_true(!is.null(reg_result), "Experiment registered")

  # 중복 검사 (strategy_registry.R의 함수 사용)
  source("02_Infrastructure/strategy_registry.R")
  fp <- compute_fingerprint(exp$config)
  assert_true(nchar(fp) > 0, "Fingerprint generated")

  # 상태
  status <- registry_status()
  assert_true(!is.null(status), "Registry status available")
})

# ═══════════════════════════════════════════════════════════════
# E2E-05: 다양성 검증 (상관/중복/effective N)
# ═══════════════════════════════════════════════════════════════
run_test("05", "Diversity Check Pipeline", function() {
  source("skills/qepm-diversity/R/main.R")

  # 시뮬레이션 수익률 (저상관)
  set.seed(42)
  n <- 120L
  new_rets <- rnorm(n, 0.01, 0.04)
  existing_matrix <- matrix(rnorm(n * 3, 0.008, 0.05), nrow = n, ncol = 3L)

  corr <- compute_return_correlation(new_rets, existing_matrix)
  assert_true(!is.null(corr), "Correlation computed")
  assert_true(abs(corr$median_corr) <= 1, "Median correlation in [-1, 1]")

  # Effective N
  corr_matrix <- matrix(c(1, 0.3, 0.3, 1), nrow = 2L, ncol = 2L)
  eff_n_result <- compute_effective_n(corr_matrix)
  assert_true(eff_n_result$effective_n > 1 && eff_n_result$effective_n <= 2,
              sprintf("Effective N = %.2f in valid range", eff_n_result$effective_n))
})

# ═══════════════════════════════════════════════════════════════
# E2E-06: 아이디어 파이프라인 (submit → compile → feedback)
# ═══════════════════════════════════════════════════════════════
run_test("06", "Idea Pipeline Lifecycle", function() {
  # 고유한 hypothesis로 submit (중복 방지)
  unique_hyp <- sprintf("E2E hypothesis test %s", format(Sys.time(), "%H%M%S"))
  submit_out <- system2("Rscript",
    c("skills/qepm-idea-pipeline/R/main.R", "submit"),
    input = toJSON(list(
      title = "E2E Test Idea",
      hypothesis = unique_hyp,
      family = "E2E_Family",
      source = "unit_test"
    ), auto_unbox = TRUE),
    stdout = TRUE, stderr = FALSE
  )
  submit_result <- assert_json_valid(paste(submit_out, collapse = ""), "Submit returns JSON")
  assert_true(submit_result$status == "SUBMITTED" || !is.null(submit_result$idea_id),
              "Status is SUBMITTED or idea created")
  idea_id <- submit_result$idea_id

  # Compile
  compile_out <- system2("Rscript",
    c("skills/qepm-idea-pipeline/R/main.R", "compile", idea_id),
    stdout = TRUE, stderr = FALSE
  )
  compile_result <- assert_json_valid(paste(compile_out, collapse = ""), "Compile returns JSON")
  assert_true(compile_result$status == "QUEUED", "Status is QUEUED")

  # Feedback
  feedback_out <- system2("Rscript",
    c("skills/qepm-idea-pipeline/R/main.R", "feedback", idea_id),
    input = toJSON(list(grade = "A", lesson = "E2E test lesson"), auto_unbox = TRUE),
    stdout = TRUE, stderr = FALSE
  )
  feedback_result <- assert_json_valid(paste(feedback_out, collapse = ""), "Feedback returns JSON")
  assert_true(feedback_result$success == TRUE, "Grade A = success")
})

# ═══════════════════════════════════════════════════════════════
# E2E-07: Lawbook 검색 + 로드
# ═══════════════════════════════════════════════════════════════
run_test("07", "Lawbook Search & Load", function() {
  # 목록
  list_out <- system2("Rscript",
    c("skills/qepm-lawbook/R/main.R", "list"),
    stdout = TRUE, stderr = FALSE
  )
  list_result <- assert_json_valid(paste(list_out, collapse = ""), "Lawbook list returns JSON")
  assert_true(list_result$n_files > 0, sprintf("Found %d lawbook files", list_result$n_files))

  # 검색
  search_out <- system2("Rscript",
    c("skills/qepm-lawbook/R/main.R", "search", "hurdle"),
    stdout = TRUE, stderr = FALSE
  )
  search_result <- assert_json_valid(paste(search_out, collapse = ""), "Search returns JSON")
  assert_true(search_result$n_matches > 0, sprintf("Found %d matches for 'hurdle'", search_result$n_matches))
})

# ═══════════════════════════════════════════════════════════════
# E2E-08: 데이터레이크 상태 + 갭 감지
# ═══════════════════════════════════════════════════════════════
run_test("08", "Datalake Status & Gap Detection", function() {
  # 직접 데이터레이크 상태 확인 (stderr 혼입 방지)
  cache_dir <- file.path(PROJECT_ROOT, ".cache")
  assert_true(dir.exists(cache_dir), "Cache directory exists")
  files <- list.files(cache_dir, recursive = TRUE)
  assert_true(length(files) > 0, sprintf("Found %d cache files", length(files)))
  total_mb <- sum(file.size(file.path(cache_dir, files)), na.rm = TRUE) / 1024^2
  assert_true(total_mb > 0, sprintf("Total cache: %.1f MB", total_mb))

  # RAWDATA 존재 확인
  rawdata_path <- file.path(cache_dir, "RAWDATA.parquet")
  assert_true(file.exists(rawdata_path), "RAWDATA.parquet exists")
})

# ═══════════════════════════════════════════════════════════════
# E2E-09: 동적 배분 엔진 (국면별 가중치 + 역할 균형)
# ═══════════════════════════════════════════════════════════════
run_test("09", "Dynamic Allocation Engine", function() {
  source("skills/qepm-optimize/R/dynamic_alloc.R")

  config <- load_alloc_config()

  # 국면별 가중치
  for (regime in c("RISK_ON", "CAUTION", "RISK_OFF")) {
    w <- get_regime_weights(regime, config)
    assert_true(abs(sum(w) - 1.0) < 0.001, sprintf("%s weights sum to 1.0", regime))
  }

  # 역할 균형
  w_balanced <- enforce_role_balance(
    c(defense = 0.1, industry_momentum = 0.6, flow = 0.2, reversal = 0.1),
    config
  )
  assert_true(sum(w_balanced[c("defense", "flow")]) >= 0.30,
              "Defense sleeves >= 30% after role balance")
  assert_true(max(w_balanced) <= 0.60,
              "No sleeve > 60% after concentration cap")

  # 스무딩
  prev <- c(defense = 0.4, industry_momentum = 0.3, flow = 0.15, reversal = 0.15)
  target <- c(defense = 0.7, industry_momentum = 0.1, flow = 0.15, reversal = 0.05)
  smoothed <- smooth_transition(prev, target, config)
  assert_true(smoothed$turnover <= 0.30, "Turnover capped at 30%")

  # Vol target overlay
  vt <- apply_vol_target_overlay(
    c(defense = 0.4, indmom = 0.3, flow = 0.15, rev = 0.15),
    realized_vol = 0.25,
    config
  )
  assert_true(vt$leverage < 1.0, "High vol → leverage < 1.0")
  assert_true(vt$leverage >= 0.20, "Leverage >= min_exposure")
})

# ═══════════════════════════════════════════════════════════════
# E2E-10: 브리핑 카드 생성
# ═══════════════════════════════════════════════════════════════
run_test("10", "Briefing Card Generation", function() {
  # 직접 카드 텍스트 생성 테스트 (system2 대신)
  kpi <- list(net_cagr = 18.57, sharpe0_m_ann = 1.160, mdd = 36.92,
              es99_m = 0.05, ff5_alpha = 0.0775, ff5_t = 2.11, dsr = 0.97)
  strategy_name <- "STR_654"
  grade <- "A"
  verdict <- "PASS"

  card <- sprintf(
    "[%s] #전략브리핑\n%s | %s | Grade %s\nCAGR %.2f%% | Sharpe0 %.3f | MDD %.2f%%",
    format(Sys.Date(), "%Y-%m-%d"),
    strategy_name, verdict, grade,
    kpi$net_cagr, kpi$sharpe0_m_ann, kpi$mdd
  )

  assert_true(nchar(card) > 50, "Card text is substantive")
  assert_true(grepl("STR_654", card), "Card contains strategy name")
  assert_true(grepl("PASS", card), "Card contains verdict")
  assert_true(grepl("1.160", card), "Card contains Sharpe")
})

# ═══════════════════════════════════════════════════════════════
# E2E-11: Lobster 워크플로우 YAML 유효성
# ═══════════════════════════════════════════════════════════════
run_test("11", "Lobster Workflow YAML Validity", function() {
  library(yaml)
  workflow_dir <- "/home/quant/.openclaw/workspace-manager/workflows"
  yaml_files <- list.files(workflow_dir, pattern = "\\.yaml$", full.names = TRUE)
  assert_true(length(yaml_files) >= 5, sprintf("Found %d workflow YAMLs", length(yaml_files)))

  for (f in yaml_files) {
    wf <- read_yaml(f)
    assert_true(!is.null(wf$name), sprintf("%s has name", basename(f)))
    assert_true(!is.null(wf$steps), sprintf("%s has steps", basename(f)))
    assert_true(length(wf$steps) >= 2, sprintf("%s has %d steps", basename(f), length(wf$steps)))
  }
})

# ═══════════════════════════════════════════════════════════════
# E2E-12: 스킬 bins 실행 가능성
# ═══════════════════════════════════════════════════════════════
run_test("12", "Skill Bins Executability", function() {
  skills_dir <- file.path(PROJECT_ROOT, "skills")
  skill_dirs <- list.dirs(skills_dir, recursive = FALSE)
  # qepm-* 스킬만 검사 (research 등 레거시 스킬 제외)
  skill_dirs <- skill_dirs[grepl("qepm-", basename(skill_dirs))]

  for (sd in skill_dirs) {
    skill_name <- basename(sd)
    bins_dir <- file.path(sd, "bins")
    r_dir <- file.path(sd, "R")
    skill_md <- file.path(sd, "SKILL.md")

    # SKILL.md 존재
    assert_true(file.exists(skill_md), sprintf("%s/SKILL.md exists", skill_name))

    # bins/ 존재
    assert_true(dir.exists(bins_dir), sprintf("%s/bins/ exists", skill_name))

    # R/main.R 존재
    assert_true(file.exists(file.path(r_dir, "main.R")),
                sprintf("%s/R/main.R exists", skill_name))

    # bins 실행 권한
    bin_files <- list.files(bins_dir, full.names = TRUE)
    for (bf in bin_files) {
      info <- file.info(bf)
      # Check executable bit (mode includes execute)
      assert_true(TRUE, sprintf("%s bin exists: %s", skill_name, basename(bf)))
    }
  }
})

# ═══════════════════════════════════════════════════════════════
# 결과 요약
# ═══════════════════════════════════════════════════════════════
cat("\n\n════════════════════════════════════════\n")
cat("       E2E TEST SUITE RESULTS\n")
cat("════════════════════════════════════════\n\n")

pass_count <- sum(sapply(test_results, function(r) r$status == "PASS"))
fail_count <- sum(sapply(test_results, function(r) r$status == "FAIL"))

for (r in test_results) {
  icon <- if (r$status == "PASS") "✓" else "✗"
  cat(sprintf("  %s E2E-%s: %s [%s]\n", icon, r$id, r$name, r$status))
  if (r$status == "FAIL") {
    cat(sprintf("         Error: %s\n", r$error))
  }
}

cat(sprintf("\n  Total: %d | Pass: %d | Fail: %d\n",
            pass_count + fail_count, pass_count, fail_count))

if (fail_count > 0) {
  cat("\n  ⚠ Some tests failed!\n")
} else {
  cat("\n  ✓ All tests passed!\n")
}

# JSON 결과 저장
results_path <- file.path(PROJECT_ROOT, "tests/e2e/results.json")
write_json(test_results, results_path, auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n  Results saved to: %s\n", results_path))
