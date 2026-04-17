test_that("now_kst returns ISO 8601 KST timestamp", {
  ts <- now_kst()
  expect_type(ts, "character")
  expect_match(ts, "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\+09:00$")
})

test_that("today_str returns YYYYMMDD", {
  d <- today_str()
  expect_type(d, "character")
  expect_equal(nchar(d), 8L)
  expect_match(d, "^\\d{8}$")
})

test_that("artifact_hash returns SHA256 hex", {
  tmp <- tempfile()
  writeLines("hello world", tmp)
  h <- artifact_hash(tmp)
  expect_type(h, "character")
  expect_equal(nchar(h), 64L)
  unlink(tmp)
})

test_that("artifact_hash errors on missing file", {
  expect_error(artifact_hash("/nonexistent/file.txt"), "not found")
})

test_that("object_hash is deterministic", {
  h1 <- object_hash(list(a = 1, b = "x"))
  h2 <- object_hash(list(a = 1, b = "x"))
  expect_equal(h1, h2)
})

test_that("read_json_safe returns NULL for missing file", {
  expect_null(read_json_safe("/nonexistent.json"))
})

test_that("write_json_safe + read_json_safe roundtrip", {
  tmp <- tempfile(fileext = ".json")
  obj <- list(a = 1, b = "hello", c = list(d = TRUE))
  write_json_safe(obj, tmp)
  result <- read_json_safe(tmp)
  expect_equal(result$a, 1)
  expect_equal(result$b, "hello")
  expect_true(result$c$d)
  unlink(tmp)
})

test_that("generate_task_id has correct format", {
  id <- generate_task_id("TEST")
  expect_match(id, "^TEST_\\d{8}_\\d{4}$")
})

test_that("generate_exp_id has correct format", {
  id <- generate_exp_id()
  expect_match(id, "^EXP_\\d{4}-\\d{2}-\\d{2}_\\d{6}_\\d{4}$")
})

test_that("strategy_fingerprint is deterministic", {
  spec <- list(
    universe = "KR_ALL",
    factor_family = "idiovol",
    signal_formula = "z(-idiovol)",
    rebalance_rule = "monthly",
    n_holdings = 30,
    weighting_rule = "equal",
    benchmark = "KOSPI200_TR"
  )
  fp1 <- strategy_fingerprint(spec)
  fp2 <- strategy_fingerprint(spec)
  expect_equal(fp1, fp2)
  expect_equal(nchar(fp1), 64L)
})

test_that("strategy_fingerprint differs for different specs", {
  spec1 <- list(factor_family = "idiovol", n_holdings = 30)
  spec2 <- list(factor_family = "momentum", n_holdings = 30)
  expect_false(strategy_fingerprint(spec1) == strategy_fingerprint(spec2))
})

test_that("estimate_tokens returns reasonable count", {
  expect_equal(estimate_tokens(""), 0L)
  expect_equal(estimate_tokens(NULL), 0L)
  # English: ~4 chars/token => 100 chars ~ 40 tokens
  # Our formula: nchar/2.5 => 100/2.5 = 40
  expect_equal(estimate_tokens(strrep("a", 100)), 40L)
})

test_that("ensure_dir creates nested directory", {
  tmp <- file.path(tempdir(), "qepm_test", "nested", "dir")
  if (dir.exists(tmp)) unlink(tmp, recursive = TRUE)
  ensure_dir(tmp)
  expect_true(dir.exists(tmp))
  unlink(file.path(tempdir(), "qepm_test"), recursive = TRUE)
})
