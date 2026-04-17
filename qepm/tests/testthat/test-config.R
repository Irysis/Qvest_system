test_that("config.yaml exists and loads", {
  cfg_path <- file.path(
    "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
    "qepm", "inst", "config", "config.yaml"
  )
  skip_if_not(file.exists(cfg_path), "config.yaml not found")

  cfg <- yaml::read_yaml(cfg_path)
  expect_true(is.list(cfg))
  expect_equal(cfg$project$name, "QEPM Multi-Agent System")
  expect_equal(cfg$project$version, "1.4.2")
})

test_that("config has all required top-level keys", {
  cfg_path <- file.path(
    "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
    "qepm", "inst", "config", "config.yaml"
  )
  skip_if_not(file.exists(cfg_path))

  cfg <- yaml::read_yaml(cfg_path)
  required_keys <- c("project", "paths", "llm", "memory", "orchestration",
                      "research", "kpi", "simulation", "briefing", "objective_hierarchy")
  for (k in required_keys) {
    expect_true(k %in% names(cfg), info = paste("Missing key:", k))
  }
})

test_that("LLM model config has all required models", {
  cfg_path <- file.path(
    "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
    "qepm", "inst", "config", "config.yaml"
  )
  skip_if_not(file.exists(cfg_path))

  cfg <- yaml::read_yaml(cfg_path)
  models <- cfg$llm$models
  required_models <- c("distill_light", "distill_medium", "distill_heavy", "verify", "orchestrate")
  for (m in required_models) {
    expect_true(m %in% names(models), info = paste("Missing model:", m))
    expect_match(models[[m]], "claude", info = paste("Model", m, "should contain 'claude'"))
  }
})

test_that("memory token budget sums correctly", {
  cfg_path <- file.path(
    "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
    "qepm", "inst", "config", "config.yaml"
  )
  skip_if_not(file.exists(cfg_path))

  cfg <- yaml::read_yaml(cfg_path)
  budget <- cfg$memory$token_budget
  component_sum <- budget$schema + budget$stat_evidence + budget$regime_payoff +
    budget$portfolio_policy + budget$recent_digests + budget$working
  expect_equal(component_sum, budget$total)
})

test_that("objective hierarchy is correctly ordered", {
  cfg_path <- file.path(
    "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
    "qepm", "inst", "config", "config.yaml"
  )
  skip_if_not(file.exists(cfg_path))

  cfg <- yaml::read_yaml(cfg_path)
  expected <- c("Validity", "Implementability", "Robustness", "Performance", "Novelty")
  expect_equal(cfg$objective_hierarchy, expected)
})
