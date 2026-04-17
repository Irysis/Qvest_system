# Extracted from test-memory-advanced.R:361

# prequel ----------------------------------------------------------------------
setup_test_root <- function() {
  tmp <- file.path(tempdir(), paste0("qepm_test_", sprintf("%04d", sample(1:9999, 1))))
  qepm_root <- file.path(tmp, "qepm")
  dirs <- c("memory/episodes", "memory/families", "memory/evidence",
            "memory/regime_payoff", "memory/portfolio_policy", "memory/post_trade",
            "memory/lessons", "inst/prompts/system")
  for (d in dirs) dir.create(file.path(qepm_root, d), recursive = TRUE, showWarnings = FALSE)
  # Fake _base.yaml
  writeLines(c(
    "objective_hierarchy: |",
    "  1. Validity",
    "hard_laws: |",
    "  NEVER violate PIT",
    "artifact_standard: |",
    "  All outputs must include artifact",
    "kpi_standard: |",
    "  Primary Sharpe: Sharpe0_m_ann"
  ), file.path(qepm_root, "inst", "prompts", "system", "_base.yaml"))
  tmp
}
mock_config <- function(tmp_root) {
  # Find .qepm_env: try global (source'd), then package namespace
  cfg_env <- tryCatch(
    get(".qepm_env", envir = .GlobalEnv),
    error = function(e) {
      tryCatch(
        get(".qepm_env", envir = asNamespace("qepm")),
        error = function(e2) {
          env <- parent.env(environment(config_get))
          if (exists(".qepm_env", envir = env)) {
            get(".qepm_env", envir = env)
          } else {
            stop("Cannot locate .qepm_env")
          }
        }
      )
    }
  )
  if (is.null(cfg_env$config)) cfg_env$config <- list()
  cfg_env$config$paths$project_root <- tmp_root
  cfg_env$config$memory$token_budget$total <- 8000L
}
create_fake_digests <- function(qepm_root, family, n = 5, pass_count = 3) {
  episodes_dir <- file.path(qepm_root, "qepm", "memory", "episodes")
  for (i in seq_len(n)) {
    is_pass <- i <= pass_count
    digest <- list(
      exp_id = paste0("EXP_", family, "_", sprintf("%03d", i)),
      strategy_id = paste0("STR_TEST_", i),
      family = family,
      construction = list(
        rebalance = "monthly",
        weighting = "equal",
        buffer_zone = (i %% 2 == 0),
        cooldown = 0L,
        neutralization = if (i == 1) "sector" else "none"
      ),
      metrics = list(
        sharpe0_m_ann = if (is_pass) 1.0 + i * 0.1 else 0.3,
        net_cagr = if (is_pass) 0.15 + i * 0.01 else 0.05,
        mdd = if (is_pass) -0.20 else -0.45
      ),
      grade = if (is_pass) "A" else "F",
      role = if (i == 1) "core" else if (i == 2) "defensive" else NULL,
      verdict = if (is_pass) "PASS" else "FAIL",
      fail_reasons = if (!is_pass) list("mdd_too_high") else list(),
      distilled_at = now_kst()
    )
    jsonlite::write_json(digest, file.path(episodes_dir, paste0(digest$exp_id, ".json")),
                         auto_unbox = TRUE, pretty = TRUE)
  }
}

# test -------------------------------------------------------------------------
tmp <- setup_test_root()
on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
mock_config(tmp)
path <- r6_store_learning(
    strategy_id = "STR_700",
    period = "2026-02",
    intended_exposures = NULL,
    realized_exposures = NULL
  )
rec <- jsonlite::fromJSON(path, simplifyVector = FALSE)
expect_null(rec$drift)
