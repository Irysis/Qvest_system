test_that("lawbook_load finds unified lawbook", {
  lawbook_path <- file.path(
    "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
    "00_qepm_multiagent_lawbook", "v1.4", "v1.4.2", "lawbook_v142_unified.md"
  )
  skip_if_not(file.exists(lawbook_path), "Lawbook file not found")

  # Clear cache first
  lawbook_clear_cache()
  parsed <- lawbook_load(lawbook_path)

  expect_true(is.list(parsed))
  expect_true(length(parsed) > 0)
  # Chapter 00 should exist
  expect_true("00" %in% names(parsed))
})

test_that("lawbook_lookup returns chapter 25 (Memory Distillation)", {
  lawbook_path <- file.path(
    "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
    "00_qepm_multiagent_lawbook", "v1.4", "v1.4.2", "lawbook_v142_unified.md"
  )
  skip_if_not(file.exists(lawbook_path))

  lawbook_clear_cache()
  lawbook_load(lawbook_path)

  result <- lawbook_lookup("25")
  expect_type(result$content, "character")
  expect_true(nchar(result$content) > 100)
  expect_true(grepl("Memory Distillation", result$chapter_title, ignore.case = TRUE))
})

test_that("lawbook_lookup concise mode truncates", {
  lawbook_path <- file.path(
    "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
    "00_qepm_multiagent_lawbook", "v1.4", "v1.4.2", "lawbook_v142_unified.md"
  )
  skip_if_not(file.exists(lawbook_path))

  lawbook_clear_cache()
  lawbook_load(lawbook_path)

  full <- lawbook_lookup("25", format = "full")
  concise <- lawbook_lookup("25", format = "concise", max_tokens = 100)

  # Concise should be shorter
  expect_true(nchar(concise$content) <= nchar(full$content))
})

test_that("lawbook_search returns results for 'memory'", {
  lawbook_path <- file.path(
    "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
    "00_qepm_multiagent_lawbook", "v1.4", "v1.4.2", "lawbook_v142_unified.md"
  )
  skip_if_not(file.exists(lawbook_path))

  lawbook_clear_cache()
  lawbook_load(lawbook_path)

  results <- lawbook_search("memory distillation pipeline", top_k = 5)
  expect_true(length(results) > 0)
  expect_true(any(sapply(results, function(r) r$chapter == "25")))
})

test_that("lawbook_lookup returns not-found for invalid chapter", {
  lawbook_path <- file.path(
    "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
    "00_qepm_multiagent_lawbook", "v1.4", "v1.4.2", "lawbook_v142_unified.md"
  )
  skip_if_not(file.exists(lawbook_path))

  lawbook_clear_cache()
  lawbook_load(lawbook_path)

  result <- lawbook_lookup("99999")
  expect_true(grepl("not found", result$content))
})
