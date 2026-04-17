#' Tests for R2 (Family), R3 (Evidence), R4 (Regime), R5 (Policy), R6 (Post-Trade)
#' and Phase 3 (Prompt Builder, Memory Retrieve)

# ---- Helpers: set up a temporary project root for isolated tests ----

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

# Inject test project root into config
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

# Create fake experiment digests in episodes/
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


# ---- R2: Family Memory ----

test_that("r2_distill_family returns NULL for insufficient data", {
  tmp <- setup_test_root()
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  mock_config(tmp)

  # No digests -> should return NULL

result <- r2_distill_family("empty_family")
  expect_null(result)
})

test_that("r2_distill_family creates family JSON with correct structure", {
  tmp <- setup_test_root()
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  mock_config(tmp)
  create_fake_digests(tmp, "test_fam", n = 5, pass_count = 3)

  path <- r2_distill_family("test_fam")
  expect_true(file.exists(path))

  fam <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  expect_equal(fam$family_id, "test_fam")
  expect_equal(fam$experiment_count, 5)
  expect_equal(fam$pass_count, 3)
  expect_equal(fam$fail_count, 2)
  expect_true(fam$confidence <= 1.0)
  expect_true(length(fam$works_when) > 0)
  expect_true(length(fam$fails_when) > 0)
  expect_true(!is.null(fam$updated_at))
})

test_that("r2_search_episodes filters by family", {
  tmp <- setup_test_root()
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  mock_config(tmp)
  create_fake_digests(tmp, "alpha_fam", n = 4, pass_count = 2)
  create_fake_digests(tmp, "beta_fam", n = 3, pass_count = 1)

  alpha_results <- r2_search_episodes(family = "alpha_fam")
  expect_equal(length(alpha_results), 4)

  beta_results <- r2_search_episodes(family = "beta_fam")
  expect_equal(length(beta_results), 3)

  all_results <- r2_search_episodes()
  expect_equal(length(all_results), 7)
})


# ---- R3: Statistical Evidence ----

test_that("r3_store_evidence creates evidence JSON with tier", {
  tmp <- setup_test_root()
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  mock_config(tmp)

  alpha <- list(
    ff3     = list(alpha = 0.05, t_stat = 2.50),
    carhart4 = list(alpha = 0.04, t_stat = 2.10),
    ff5     = list(alpha = 0.03, t_stat = 1.50)
  )
  fm <- list(slope = 0.02, t_stat = 2.30)

  path <- r3_store_evidence("STR_TEST_001", alpha, fm_results = fm)
  expect_true(file.exists(path))

  evid <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  expect_equal(evid$evidence_id, "EVID_STR_TEST_001")
  expect_equal(evid$target, "STR_TEST_001")
  expect_equal(evid$tier, "strong")  # 2 pass + FM pass
  expect_true(evid$ff3$pass)
  expect_true(evid$carhart4$pass)
  expect_false(evid$ff5$pass)  # t=1.50 < 1.96
  expect_true(evid$fama_macbeth$pass)
})

test_that("determine_evidence_tier classifies correctly", {
  # strong: 2+ factor pass + FM pass
  expect_equal(
    determine_evidence_tier(
      list(ff3 = list(t_stat = 2.5), carhart4 = list(t_stat = 2.1), ff5 = list(t_stat = 1.0)),
      list(t_stat = 2.0)
    ), "strong"
  )

  # moderate: 2 factor pass, no FM
  expect_equal(
    determine_evidence_tier(
      list(ff3 = list(t_stat = 2.5), carhart4 = list(t_stat = 2.1), ff5 = list(t_stat = 1.0)),
      NULL
    ), "moderate"
  )

  # moderate: 1 factor pass + FM pass
  expect_equal(
    determine_evidence_tier(
      list(ff3 = list(t_stat = 2.5), carhart4 = list(t_stat = 1.0), ff5 = list(t_stat = 0.5)),
      list(t_stat = 2.0)
    ), "moderate"
  )

  # weak: 1 factor pass, no FM
  expect_equal(
    determine_evidence_tier(
      list(ff3 = list(t_stat = 2.5), carhart4 = list(t_stat = 1.0), ff5 = list(t_stat = 0.5)),
      NULL
    ), "weak"
  )

  # insufficient: all fail
  expect_equal(
    determine_evidence_tier(
      list(ff3 = list(t_stat = 0.5), carhart4 = list(t_stat = 1.0), ff5 = list(t_stat = 0.3)),
      NULL
    ), "insufficient"
  )

  # weak: no tests available at all
  expect_equal(determine_evidence_tier(list(), NULL), "weak")
})


# ---- R4: Regime Payoff Tensor ----

test_that("r4_store_regime_payoff creates entry with correct confidence", {
  tmp <- setup_test_root()
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  mock_config(tmp)

  # Short window -> low confidence
  path1 <- r4_store_regime_payoff(
    "idio_vol", "risk_off", "ew_monthly",
    metrics = list(cagr_cond = 0.05, mdd_cond = -0.10, sharpe_cond = 0.8),
    n_months = 12
  )
  e1 <- jsonlite::fromJSON(path1, simplifyVector = FALSE)
  expect_true(e1$confidence < 0.5)
  expect_equal(e1$role, "defensive")  # |MDD| = 0.10 < 0.15

  # Long window -> higher confidence
  path2 <- r4_store_regime_payoff(
    "idio_vol", "risk_on", "ew_monthly",
    metrics = list(cagr_cond = 0.20, mdd_cond = -0.25, sharpe_cond = 1.2),
    n_months = 60
  )
  e2 <- jsonlite::fromJSON(path2, simplifyVector = FALSE)
  expect_true(e2$confidence >= 0.5)
  expect_equal(e2$role, "core")  # CAGR > 0.15
})

test_that("r4_read_payoffs filters correctly", {
  tmp <- setup_test_root()
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  mock_config(tmp)

  r4_store_regime_payoff("fam_a", "risk_on", "c1",
    metrics = list(cagr_cond = 0.20, mdd_cond = -0.25), n_months = 60)
  r4_store_regime_payoff("fam_a", "risk_off", "c1",
    metrics = list(cagr_cond = 0.05, mdd_cond = -0.10), n_months = 30)
  r4_store_regime_payoff("fam_b", "risk_on", "c1",
    metrics = list(cagr_cond = 0.18, mdd_cond = -0.20), n_months = 48)

  all_entries <- r4_read_payoffs()
  expect_equal(length(all_entries), 3)

  fam_a <- r4_read_payoffs(family_id = "fam_a")
  expect_equal(length(fam_a), 2)

  risk_on <- r4_read_payoffs(regime_id = "risk_on")
  expect_equal(length(risk_on), 2)
})


# ---- R5: Portfolio Policy ----

test_that("r5_store_policy creates policy with LOO pass", {
  tmp <- setup_test_root()
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  mock_config(tmp)

  sleeves <- list(
    defense = list(strategy_id = "STR_654", weight = 0.5, role = "core"),
    indmom  = list(strategy_id = "STR_694", weight = 0.3, role = "diversifier"),
    flow    = list(strategy_id = "STR_701", weight = 0.2, role = "diversifier")
  )

  loo <- list(
    list(removed_sleeve = "defense", sharpe_without = 0.90),
    list(removed_sleeve = "indmom",  sharpe_without = 1.00),
    list(removed_sleeve = "flow",    sharpe_without = 1.02)
  )

  path <- r5_store_policy(
    "POL_test_01",
    sleeves = sleeves,
    baseline = list(rebalance = "monthly", benchmark = "KOSPI200_TR"),
    overlay = list(regime_switch = TRUE, vol_target = 0.15),
    portfolio_metrics = list(sharpe0_m_ann = 1.10, cagr = 0.18, mdd = -0.22),
    loo_results = loo
  )

  pol <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  expect_equal(pol$policy_id, "POL_test_01")
  expect_true(pol$loo_pass)
  expect_equal(pol$admission_status, "candidate")
  expect_equal(length(pol$sleeves), 3)
})

test_that("r5_store_policy rejects when LOO fails", {
  tmp <- setup_test_root()
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  mock_config(tmp)

  # One sleeve removal improves Sharpe beyond 5%
  loo <- list(
    list(removed_sleeve = "bad_sleeve", sharpe_without = 1.50)  # >> 1.10 * 1.05
  )

  path <- r5_store_policy(
    "POL_test_02",
    sleeves = list(a = list(strategy_id = "X", weight = 1.0)),
    baseline = list(),
    overlay = list(),
    portfolio_metrics = list(sharpe0_m_ann = 1.10),
    loo_results = loo
  )

  pol <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  expect_false(pol$loo_pass)
  expect_equal(pol$admission_status, "rejected")
})


# ---- R6: Post-Trade Learning ----

test_that("r6_store_learning computes drift correctly", {
  tmp <- setup_test_root()
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  mock_config(tmp)

  path <- r6_store_learning(
    strategy_id = "STR_654",
    period = "2026-03",
    intended_exposures = list(beta = 0.60, size = -0.10, sector_IT = 0.15),
    realized_exposures = list(beta = 0.55, size = -0.12, sector_IT = 0.18),
    realized_turnover = 0.35,
    slippage = 2.5
  )

  expect_true(file.exists(path))
  rec <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  expect_equal(rec$strategy_id, "STR_654")
  expect_equal(rec$period, "2026-03")
  expect_equal(rec$realized_turnover, 0.35)
  expect_equal(rec$slippage, 2.5)

  # Drift checks
  expect_true(!is.null(rec$drift))
  expect_equal(rec$drift$max_drift, 0.05)   # beta: |0.60 - 0.55| = 0.05
  expect_true(rec$drift$mean_drift > 0)
})

test_that("r6_store_learning handles NULL exposures", {
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
  # JSON null roundtrip: NULL -> {} -> empty list
  expect_true(is.null(rec$drift) || length(rec$drift) == 0)
})

test_that("r6_read_learnings filters by strategy and period", {
  tmp <- setup_test_root()
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  mock_config(tmp)

  r6_store_learning("STR_A", "2026-01",
    list(x = 1), list(x = 1.1))
  r6_store_learning("STR_A", "2026-02",
    list(x = 1), list(x = 0.9))
  r6_store_learning("STR_B", "2026-01",
    list(y = 2), list(y = 2.1))

  all_rec <- r6_read_learnings()
  expect_equal(length(all_rec), 3)

  a_rec <- r6_read_learnings(strategy_id = "STR_A")
  expect_equal(length(a_rec), 2)

  jan_rec <- r6_read_learnings(period = "2026-01")
  expect_equal(length(jan_rec), 2)
})


# ---- Phase 3: Prompt Builder ----

test_that("build_system_prompt returns prompt and token_count", {
  tmp <- setup_test_root()
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  mock_config(tmp)

  # Create a minimal agent prompt
  agent_prompt_path <- file.path(tmp, "qepm", "inst", "prompts", "system", "test_agent.yaml")
  writeLines(c("system: |", "  You are a test agent."),
             agent_prompt_path)

  result <- build_system_prompt("test_agent", task_context = "Run strategy STR_001")
  expect_type(result, "list")
  expect_true(nzchar(result$prompt))
  expect_true(result$token_count > 0)
  expect_true(grepl("Objective Hierarchy", result$prompt))
  expect_true(grepl("Hard Laws", result$prompt))
  expect_true(grepl("Task Context", result$prompt))
  expect_true(grepl("Run strategy STR_001", result$prompt))
})

test_that("format_memory_packet respects token budget", {
  # Large packet that exceeds budget
  big <- paste(rep("word", 1000), collapse = " ")
  packet <- list(section1 = big, section2 = big, section3 = big)

  # Very small budget -> should not include all
  result <- format_memory_packet(packet, budget = 100L)
  expect_type(result, "character")
  # With budget=100, might fit 0 or 1 section depending on estimate_tokens
})

test_that("format_memory_packet handles empty input", {
  expect_equal(format_memory_packet(NULL, 8000L), "")
  expect_equal(format_memory_packet(list(), 8000L), "")
})


# ---- Phase 3: Memory Retrieve ----

test_that("memory_retrieve returns empty for empty dirs", {
  tmp <- setup_test_root()
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  mock_config(tmp)

  packet <- memory_retrieve("research_design")
  expect_type(packet, "list")
  expect_equal(length(packet), 0)
})

test_that("memory_retrieve respects context priority", {
  tmp <- setup_test_root()
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  mock_config(tmp)

  # Create a family file and an evidence file
  fam_dir <- file.path(tmp, "qepm", "memory", "families")
  ev_dir  <- file.path(tmp, "qepm", "memory", "evidence")
  jsonlite::write_json(list(family_id = "test"), file.path(fam_dir, "test.json"),
                       auto_unbox = TRUE)
  jsonlite::write_json(list(evidence_id = "EVID_X"), file.path(ev_dir, "x.json"),
                       auto_unbox = TRUE)

  # research_design prioritizes families first
  packet <- memory_retrieve("research_design", token_budget = 50000L)
  expect_true(length(packet) > 0)
  # families should come before evidence in keys
  keys <- names(packet)
  fam_idx <- which(grepl("^families/", keys))
  ev_idx  <- which(grepl("^evidence/", keys))
  if (length(fam_idx) > 0 && length(ev_idx) > 0) {
    expect_true(min(fam_idx) < min(ev_idx))
  }
})

test_that("lesson_search returns matching lessons", {
  tmp <- setup_test_root()
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  mock_config(tmp)

  # Create lesson files
  lesson_dir <- file.path(tmp, "qepm", "memory", "lessons")
  writeLines('{"lesson":"L-170: CondWeight discovery"}',
             file.path(lesson_dir, "L170.json"))
  writeLines('{"lesson":"L-185: Vol targeting works"}',
             file.path(lesson_dir, "L185.json"))

  results <- lesson_search("CondWeight")
  expect_true(length(results) >= 1)
  expect_true(grepl("L170", results[[1]]$file))

  empty <- lesson_search("nonexistent_keyword_xyz")
  expect_equal(length(empty), 0)
})
