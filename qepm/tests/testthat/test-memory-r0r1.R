# ==============================================================================
# Tests for QEPM Memory Pipeline Phase 1: R0 Store, R1 Distill, R1 Verify, Registry
# ==============================================================================

# ---- Setup: mock config for tempdir-based paths ----

setup_mock_config <- function() {
  test_root <- file.path(tempdir(), paste0("qepm_test_", as.integer(Sys.time())))
  dir.create(file.path(test_root, "qepm", "memory", "raw_artifacts"),
             recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(test_root, "qepm", "memory", "episodes"),
             recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(test_root, "qepm", "registry"),
             recursive = TRUE, showWarnings = FALSE)

  # Override config_get to return our test root
  # Works whether qepm is installed as a package or sourced directly
  qepm_env <- tryCatch(
    get(".qepm_env", envir = asNamespace("qepm")),
    error = function(e) {
      # Not installed as package — look in global env
      if (exists(".qepm_env", envir = globalenv())) {
        get(".qepm_env", envir = globalenv())
      } else {
        # Create it
        env <- new.env(parent = emptyenv())
        assign(".qepm_env", env, envir = globalenv())
        env
      }
    }
  )

  old_config <- qepm_env$config
  if (is.null(old_config)) old_config <- list()

  qepm_env$config <- modifyList(old_config, list(paths = list(project_root = test_root)))

  list(root = test_root, cleanup = function() {
    qepm_env$config <- old_config
    unlink(test_root, recursive = TRUE)
  })
}

# Helper: create dummy artifact files in a temp directory
create_dummy_artifacts <- function() {
  art_dir <- file.path(tempdir(), paste0("artifacts_", as.integer(Sys.time())))
  dir.create(art_dir, recursive = TRUE)

  # Backtest report
  bt_path <- file.path(art_dir, "backtest_report.txt")
  writeLines(c(
    "Strategy: STR_TEST_001",
    "CAGR: 0.1857",
    "Sharpe: 1.160",
    "MDD: -0.3692",
    "Turnover: 4.2"
  ), bt_path)

  # Risk audit
  ra_path <- file.path(art_dir, "risk_audit.txt")
  writeLines(c(
    "Grade: A",
    "Verdict: PASS",
    "FF5 Alpha: 7.75% (t=2.11)"
  ), ra_path)

  list(dir = art_dir, backtest = bt_path, risk_audit = ra_path)
}

# Helper: build a typical hurdle_result list
make_hurdle_result <- function(grade = "A", verdict = "PASS") {
  list(
    net_cagr       = 0.1857,
    sharpe0_m_ann  = 1.160,
    mdd            = -0.3692,
    es99_m         = -0.045,
    turnover_ann   = 4.2,
    ic_mean        = 0.032,
    icir           = 0.41,
    ff3_alpha      = 0.0812,
    ff3_t          = 2.35,
    carhart4_alpha = 0.0755,
    carhart4_t     = 2.10,
    ff5_alpha      = 0.0775,
    ff5_t          = 2.11,
    fmb_slope      = NULL,
    fmb_t          = NULL,
    grade          = grade,
    verdict        = verdict,
    fail_reasons   = if (verdict == "FAIL") list("cagr_below_hurdle") else list(),
    score          = 86.1
  )
}

# ==============================================================================
# R0 Store Tests
# ==============================================================================

test_that("r0_store creates directory and manifest", {
  env <- setup_mock_config()
  on.exit(env$cleanup())

  arts <- create_dummy_artifacts()
  exp_id <- "EXP_TEST_R0_001"

  r0_dir <- r0_store(
    exp_id = exp_id,
    artifacts = list(backtest = arts$backtest, audit = arts$risk_audit),
    metadata = list(data_snapshot_id = "snap_001", code_version = "v1.0")
  )

  # Directory exists
  expect_true(dir.exists(r0_dir))

  # Manifest exists
  manifest_path <- file.path(r0_dir, "manifest.json")
  expect_true(file.exists(manifest_path))

  # Manifest has correct structure
  manifest <- read_json_safe(manifest_path)
  expect_equal(manifest$exp_id, exp_id)
  expect_equal(manifest$artifact_count, 2)
  expect_true("backtest" %in% names(manifest$artifacts))
  expect_true("audit" %in% names(manifest$artifacts))

  # Hashes are valid SHA256 (64 hex chars)
  expect_equal(nchar(manifest$artifacts$backtest$sha256), 64)
  expect_equal(nchar(manifest$artifacts$audit$sha256), 64)

  # Metadata preserved
  expect_equal(manifest$metadata$data_snapshot_id, "snap_001")
  expect_equal(manifest$metadata$code_version, "v1.0")

  # Artifact files copied
  expect_true(file.exists(file.path(r0_dir, "backtest_report.txt")))
  expect_true(file.exists(file.path(r0_dir, "risk_audit.txt")))

  unlink(arts$dir, recursive = TRUE)
})

test_that("r0_store skips if directory already exists", {
  env <- setup_mock_config()
  on.exit(env$cleanup())

  arts <- create_dummy_artifacts()
  exp_id <- "EXP_TEST_R0_DUP"

  # First call
  r0_dir <- r0_store(exp_id, list(bt = arts$backtest), list())
  expect_true(dir.exists(r0_dir))

  # Second call — should warn and return existing dir
  expect_warning(
    r0_dir2 <- r0_store(exp_id, list(bt = arts$backtest), list()),
    "already exists"
  )
  expect_equal(r0_dir, r0_dir2)

  unlink(arts$dir, recursive = TRUE)
})

test_that("r0_store errors when no valid artifacts", {
  env <- setup_mock_config()
  on.exit(env$cleanup())

  expect_error(
    r0_store("EXP_TEST_EMPTY", list(bad = "/nonexistent/file.txt"), list()),
    "No valid artifacts"
  )
})

# ==============================================================================
# R1 Distill Local Tests
# ==============================================================================

test_that("r1_distill_local creates valid digest from hurdle_result", {
  env <- setup_mock_config()
  on.exit(env$cleanup())

  hr <- make_hurdle_result(grade = "A", verdict = "PASS")
  exp_id <- "EXP_TEST_R1_001"

  digest <- r1_distill_local(
    exp_id = exp_id,
    hurdle_result = hr,
    strategy_name = "STR_654",
    family = "idiovol_beta",
    construction = list(rebalance = "monthly", weighting = "equal",
                        buffer_zone = TRUE, cooldown = 2L, neutralization = "sector"),
    role = "core"
  )

  # Basic structure
  expect_type(digest, "list")
  expect_equal(digest$exp_id, exp_id)
  expect_equal(digest$strategy_id, "STR_654")
  expect_equal(digest$family, "idiovol_beta")
  expect_equal(digest$grade, "A")
  expect_equal(digest$verdict, "PASS")
  expect_equal(digest$role, "core")
  expect_equal(digest$distill_method, "local")

  # Metrics match input
  expect_equal(digest$metrics$net_cagr, 0.1857)
  expect_equal(digest$metrics$sharpe0_m_ann, 1.160)
  expect_equal(digest$metrics$mdd, -0.3692)
  expect_equal(digest$metrics$es99_m, -0.045)
  expect_equal(digest$metrics$turnover_ann, 4.2)

  # Alpha tests
  expect_equal(digest$alpha_tests$ff5_alpha, 0.0775)
  expect_equal(digest$alpha_tests$ff5_t, 2.11)
  expect_null(digest$alpha_tests$fmb_slope)

  # Construction
  expect_equal(digest$construction$rebalance, "monthly")
  expect_true(digest$construction$buffer_zone)
  expect_equal(digest$construction$cooldown, 2L)

  # Score
  expect_equal(digest$score, 86.1)

  # Saved to episodes
  episode_path <- file.path(env$root, "qepm", "memory", "episodes", paste0(exp_id, ".json"))
  expect_true(file.exists(episode_path))
})

test_that("r1_distill_local handles FAIL verdict with fail_reasons", {
  env <- setup_mock_config()
  on.exit(env$cleanup())

  hr <- make_hurdle_result(grade = "F", verdict = "FAIL")
  digest <- r1_distill_local(
    exp_id = "EXP_TEST_FAIL",
    hurdle_result = hr,
    strategy_name = "STR_999",
    family = "momentum"
  )

  expect_equal(digest$grade, "F")
  expect_equal(digest$verdict, "FAIL")
  expect_true(length(digest$fail_reasons) > 0)
  expect_equal(digest$fail_reasons[[1]], "cagr_below_hurdle")
})

test_that("r1_distill_local handles missing optional fields gracefully", {
  env <- setup_mock_config()
  on.exit(env$cleanup())

  minimal_hr <- list(
    net_cagr      = 0.12,
    sharpe0_m_ann = 0.8,
    mdd           = -0.40,
    grade         = "C",
    verdict       = "NEAR_MISS"
  )

  digest <- r1_distill_local(
    exp_id = "EXP_TEST_MINIMAL",
    hurdle_result = minimal_hr,
    strategy_name = "STR_MIN",
    family = "value"
  )

  expect_equal(digest$metrics$net_cagr, 0.12)
  expect_null(digest$metrics$es99_m)
  expect_null(digest$alpha_tests$ff5_alpha)
  expect_equal(digest$construction$rebalance, "monthly")  # default
})

# ==============================================================================
# R1 Verify Tests
# ==============================================================================

test_that("r1_verify PASS for valid digest", {
  env <- setup_mock_config()
  on.exit(env$cleanup())

  hr <- make_hurdle_result()
  digest <- r1_distill_local(
    exp_id = "EXP_TEST_VERIFY_PASS",
    hurdle_result = hr,
    strategy_name = "STR_654",
    family = "idiovol_beta"
  )

  result <- r1_verify(digest)
  expect_equal(result$verdict, "PASS")
  expect_equal(result$action, "accept")
  expect_false(result$details$hallucination$detected)
  expect_false(result$details$information_loss$detected)
  expect_false(result$details$distortion$detected)
})

test_that("r1_verify catches missing required fields", {
  env <- setup_mock_config()
  on.exit(env$cleanup())

  # Digest missing critical fields
  bad_digest <- list(
    exp_id      = "EXP_BAD",
    strategy_id = NULL,     # missing
    metrics     = list(
      net_cagr      = NULL, # missing
      sharpe0_m_ann = 1.0,
      mdd           = -0.30
    ),
    verdict     = "PASS",
    grade       = "A"
  )

  result <- r1_verify(bad_digest)
  expect_true(result$details$information_loss$detected)
  expect_true("strategy_id" %in% result$details$information_loss$missing_fields)
  expect_true("metrics.net_cagr" %in% result$details$information_loss$missing_fields)
  expect_true(result$verdict %in% c("FAIL_MINOR", "FAIL_SEVERE"))
})

test_that("r1_verify catches grade/verdict distortion", {
  env <- setup_mock_config()
  on.exit(env$cleanup())

  # Grade F with PASS verdict
  distorted <- list(
    exp_id      = "EXP_DISTORT",
    strategy_id = "STR_BAD",
    metrics     = list(net_cagr = 0.05, sharpe0_m_ann = 0.3, mdd = -0.50),
    grade       = "F",
    verdict     = "PASS"   # distorted: F grade shouldn't PASS
  )

  # Create a raw artifacts dir for cross-reference
  arts <- create_dummy_artifacts()
  r0_dir <- r0_store("EXP_DISTORT", list(bt = arts$backtest), list())

  result <- r1_verify(distorted, raw_artifacts_dir = r0_dir)
  expect_true(result$details$distortion$detected)
  expect_true(result$verdict %in% c("FAIL_MINOR", "FAIL_SEVERE"))

  unlink(arts$dir, recursive = TRUE)
})

test_that("r1_verify catches FAIL verdict without fail_reasons", {
  env <- setup_mock_config()
  on.exit(env$cleanup())

  digest <- list(
    exp_id       = "EXP_NOREASONS",
    strategy_id  = "STR_NR",
    metrics      = list(net_cagr = 0.10, sharpe0_m_ann = 0.5, mdd = -0.45),
    grade        = "F",
    verdict      = "FAIL",
    fail_reasons = list()  # empty — should flag info loss
  )

  result <- r1_verify(digest)
  expect_true(result$details$information_loss$detected)
  expect_true(any(grepl("fail_reasons", result$details$information_loss$missing_fields)))
})

# ==============================================================================
# Registry Tests
# ==============================================================================

test_that("registry_add_experiment adds record to experiments.json", {
  env <- setup_mock_config()
  on.exit(env$cleanup())

  hr <- make_hurdle_result()
  digest <- r1_distill_local(
    exp_id = "EXP_REG_001",
    hurdle_result = hr,
    strategy_name = "STR_654",
    family = "idiovol_beta"
  )

  registry_add_experiment(digest)

  # Verify file exists and has the entry
  exp_path <- file.path(env$root, "qepm", "registry", "experiments.json")
  expect_true(file.exists(exp_path))

  experiments <- read_json_safe(exp_path)
  expect_equal(length(experiments), 1)
  expect_equal(experiments[[1]]$exp_id, "EXP_REG_001")
  expect_equal(experiments[[1]]$strategy_id, "STR_654")
  expect_equal(experiments[[1]]$grade, "A")
})

test_that("registry_add_experiment rejects duplicate exp_id", {
  env <- setup_mock_config()
  on.exit(env$cleanup())

  hr <- make_hurdle_result()
  digest <- r1_distill_local(
    exp_id = "EXP_DUP",
    hurdle_result = hr,
    strategy_name = "STR_001",
    family = "test_family"
  )

  registry_add_experiment(digest)

  # Second add with same exp_id should warn
  expect_warning(registry_add_experiment(digest), "Duplicate")

  # Should still have only 1 record
  exp_path <- file.path(env$root, "qepm", "registry", "experiments.json")
  experiments <- read_json_safe(exp_path)
  expect_equal(length(experiments), 1)
})

test_that("registry_search filters correctly", {
  env <- setup_mock_config()
  on.exit(env$cleanup())

  # Add multiple experiments
  for (i in 1:5) {
    grade <- if (i <= 3) "A" else "B"
    verdict <- if (i <= 3) "PASS" else "NEAR_MISS"
    family <- if (i <= 2) "idiovol" else "momentum"
    hr <- make_hurdle_result(grade = grade, verdict = verdict)
    d <- r1_distill_local(
      exp_id = paste0("EXP_SEARCH_", sprintf("%03d", i)),
      hurdle_result = hr,
      strategy_name = paste0("STR_S", i),
      family = family
    )
    registry_add_experiment(d)
  }

  # Search by grade
  grade_a <- registry_search(grade = "A")
  expect_equal(length(grade_a), 3)

  # Search by family
  idiovol <- registry_search(family = "idiovol")
  expect_equal(length(idiovol), 2)

  # Search by verdict
  pass <- registry_search(verdict = "PASS")
  expect_equal(length(pass), 3)

  # Combined filter
  idiovol_pass <- registry_search(family = "idiovol", verdict = "PASS")
  expect_equal(length(idiovol_pass), 2)

  # top_k limit
  limited <- registry_search(top_k = 2L)
  expect_equal(length(limited), 2)
})

test_that("registry_family_update tracks trials and streaks", {
  env <- setup_mock_config()
  on.exit(env$cleanup())

  family <- "test_family_track"

  # Initial state
  stats <- registry_family_trials(family)
  expect_equal(stats$trial_count, 0L)
  expect_equal(stats$pass_count, 0L)
  expect_equal(stats$fail_streak, 0L)

  # PASS
  registry_family_update(family, "PASS")
  stats <- registry_family_trials(family)
  expect_equal(stats$trial_count, 1)
  expect_equal(stats$pass_count, 1)
  expect_equal(stats$fail_streak, 0)

  # FAIL
  registry_family_update(family, "FAIL")
  stats <- registry_family_trials(family)
  expect_equal(stats$trial_count, 2)
  expect_equal(stats$pass_count, 1)
  expect_equal(stats$fail_streak, 1)

  # Another FAIL
  registry_family_update(family, "FAIL")
  stats <- registry_family_trials(family)
  expect_equal(stats$trial_count, 3)
  expect_equal(stats$fail_streak, 2)

  # PASS resets fail_streak
  registry_family_update(family, "PASS")
  stats <- registry_family_trials(family)
  expect_equal(stats$trial_count, 4)
  expect_equal(stats$pass_count, 2)
  expect_equal(stats$fail_streak, 0)
  expect_equal(stats$last_verdict, "PASS")
})

test_that("registry_add_experiment auto-updates families.json", {
  env <- setup_mock_config()
  on.exit(env$cleanup())

  hr <- make_hurdle_result(grade = "A", verdict = "PASS")
  digest <- r1_distill_local(
    exp_id = "EXP_FAM_AUTO",
    hurdle_result = hr,
    strategy_name = "STR_FAM",
    family = "auto_track_family"
  )

  registry_add_experiment(digest)

  # Family should now have 1 trial, 1 pass

  stats <- registry_family_trials("auto_track_family")
  expect_equal(stats$trial_count, 1)
  expect_equal(stats$pass_count, 1)
})
