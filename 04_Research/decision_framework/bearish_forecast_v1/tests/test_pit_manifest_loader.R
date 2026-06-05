#==============================================================================
# test_pit_manifest_loader.R — Unit test (fail-closed mandate)
#
# Mock leakage data로 stop() 호출 검증.
# Plan v0.4.2 S1 첫 gate — PASS 없이 backtest 불가.
#
# Run:
#   Rscript 04_Research/decision_framework/bearish_forecast_v1/tests/test_pit_manifest_loader.R
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(testthat)
})

# Source loader
LOADER_PATH <- "04_Research/decision_framework/bearish_forecast_v1/scripts/00_pit_manifest_loader.R"
source(LOADER_PATH)

cat("\n=== PIT Manifest Loader Unit Tests ===\n\n")

# Temp dir
TMP_DIR <- tempdir()

# ── Test 1: fwd_* column 자동 stop ──────────────────────────────
test_that("fwd_* column detection → stop()", {
  bad_df <- data.table(
    Date = as.Date("2026-01-01") + 0:9,
    Ticker = "AAA",
    safe_feature = 1:10,
    fwd_returns_21d = 11:20   # 의도적 forward — STOP 의무
  )
  bad_path <- file.path(TMP_DIR, "test_bad_fwd.parquet")
  write_parquet(bad_df, bad_path)

  expect_error(
    validate_no_leakage(bad_path),
    regexp = "PIT VIOLATION.*fwd_"
  )
  cat("  ✅ Test 1 PASS: fwd_returns_21d detected → stop()\n")
})

# ── Test 2: future_* / lead_* / next_* / forward_* 패턴 모두 catch ──
test_that("multi-pattern leakage detection", {
  for (bad_col in c("future_price", "lead_volume", "next_day_ret", "forward_eps_5d", "ahead_signal")) {
    bad_df <- data.table(Date = as.Date("2026-01-01"), safe = 1)
    bad_df[[bad_col]] <- 99
    bad_path <- file.path(TMP_DIR, paste0("test_bad_", bad_col, ".parquet"))
    write_parquet(bad_df, bad_path)
    expect_error(validate_no_leakage(bad_path), regexp = "PIT VIOLATION")
    cat(sprintf("  ✅ Test 2 PASS: '%s' detected → stop()\n", bad_col))
  }
})

# ── Test 3: 정상 column만 → PASS ────────────────────────────────
test_that("safe columns → PASS", {
  good_df <- data.table(
    Date = as.Date("2026-01-01") + 0:9,
    Ticker = "AAA",
    vkospi_z = rnorm(10),
    kr_term_spread = rnorm(10),
    foreign_netbuy_20d_z = rnorm(10)
  )
  good_path <- file.path(TMP_DIR, "test_good.parquet")
  write_parquet(good_df, good_path)

  expect_silent(validate_no_leakage(good_path))
  expect_true(validate_no_leakage(good_path))
  cat("  ✅ Test 3 PASS: safe columns → no stop\n")
})

# ── Test 4: 알려진 STR_1678 forward target allowlist (allow) ──────
test_that("STR_1678 fwd_inst_foreign_netbuy_21d allowlist", {
  # PIT_KNOWN_LEAKAGE에 등록된 column은 통과
  str1678_df <- data.table(
    Date = as.Date("2026-01-01"),
    inst_netbuy_20d = 1,
    foreign_netbuy_20d = 2,
    fwd_inst_foreign_netbuy_21d = 3,    # allowlist
    fwd_flow_top20 = 4                  # allowlist
  )
  # 파일명은 정확히 flow_features_daily.parquet 매치 필요
  str1678_path <- file.path(TMP_DIR, "flow_features_daily.parquet")
  write_parquet(str1678_df, str1678_path)

  expect_true(validate_no_leakage(str1678_path))
  cat("  ✅ Test 4 PASS: STR_1678 forward target 2건 allowlist 적용\n")
})

# ── Test 5: file not found → stop ───────────────────────────────
test_that("file not found → stop", {
  expect_error(
    validate_no_leakage("/nonexistent/path.parquet"),
    regexp = "File not found"
  )
  cat("  ✅ Test 5 PASS: missing file → stop()\n")
})

# ── Test 6: load_feature_lag_table 정상 동작 ────────────────────
test_that("feature_lag_table.csv load", {
  config <- "04_Research/decision_framework/bearish_forecast_v1/config/feature_lag_table.csv"
  if (file.exists(config)) {
    manifest <- load_feature_lag_table(config)
    expect_s3_class(manifest, "data.table")
    expect_true("feature_name" %in% names(manifest))
    expect_true("publish_timing_kst" %in% names(manifest))
    expect_true(nrow(manifest) >= 10)
    cat(sprintf("  ✅ Test 6 PASS: manifest loaded %d features\n", nrow(manifest)))
  } else {
    cat("  ⚠️  Test 6 SKIP: feature_lag_table.csv missing\n")
  }
})

# ── Test 7: get_decision_time_kst — close vs next_open ──────────
test_that("decision_time_kst close vs next_open", {
  trade_date <- as.Date("2026-05-19")  # Tuesday
  close_t <- get_decision_time_kst(trade_date, "close")
  next_open_t <- get_decision_time_kst(trade_date, "next_open")

  expect_true(format(close_t, "%H:%M") == "15:30")
  expect_true(format(next_open_t, "%H:%M") == "09:00")
  expect_true(as.Date(next_open_t) > as.Date(close_t))
  cat("  ✅ Test 7 PASS: close=15:30 KST / next_open=익영업일 09:00 KST\n")
})

cat("\n=== ALL UNIT TESTS COMPLETED ===\n")
cat("PIT Loader fail-closed semantics 검증 완료. S1 진입 ready.\n\n")
