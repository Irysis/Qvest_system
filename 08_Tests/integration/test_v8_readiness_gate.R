#==============================================================================
# test_v8_readiness_gate.R — Integration Test for v8 Design Readiness Gate
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJ)

cat("\n", strrep("=", 70), "\n", sep = "")
cat("v8 Readiness Gate Integration Test\n")
cat(strrep("=", 70), "\n", sep = "")

PASS_COUNT <- 0L
FAIL_COUNT <- 0L
RESULTS <- list()

mark_pass <- function(name, msg = "") {
  PASS_COUNT <<- PASS_COUNT + 1L
  RESULTS[[name]] <<- list(status = "PASS", message = msg)
  cat(sprintf("[PASS] %s%s\n", name,
              if (nzchar(msg)) sprintf(" — %s", msg) else ""))
}

mark_fail <- function(name, msg = "") {
  FAIL_COUNT <<- FAIL_COUNT + 1L
  RESULTS[[name]] <<- list(status = "FAIL", message = msg)
  cat(sprintf("[FAIL] %s — %s\n", name, msg))
}

# Test 1: source loads
GATE_PATH <- "02_Infrastructure/validation/v8_readiness_gate.R"
loaded <- tryCatch({
  suppressMessages(source(GATE_PATH))
  TRUE
}, error = function(e) {
  mark_fail("source_load", conditionMessage(e))
  FALSE
})
if (loaded) mark_pass("source_load", "v8_readiness_gate.R 로드 성공")

# Test 2: run returns list
res <- NULL
if (loaded) {
  res <- tryCatch(
    run_v8_readiness_gate(project_root = PROJ,
                            strict = FALSE,
                            write_report = FALSE,
                            no_write = TRUE),
    error = function(e) {
      mark_fail("run_returns_list",
                sprintf("crash: %s", conditionMessage(e)))
      NULL
    }
  )
  if (!is.null(res) && is.list(res)) {
    mark_pass("run_returns_list",
              sprintf("list with %d top-level fields", length(res)))
  }
}

# Test 3: JSON serializable
if (!is.null(res)) {
  ser <- tryCatch({
    json <- toJSON(res, auto_unbox = TRUE, null = "null")
    parsed <- fromJSON(json, simplifyVector = FALSE)
    !is.null(parsed)
  }, error = function(e) {
    mark_fail("json_serializable", conditionMessage(e))
    FALSE
  })
  if (isTRUE(ser)) mark_pass("json_serializable", "toJSON roundtrip OK")
}

# Test 4: required fields
if (!is.null(res)) {
  required_fields <- c("gate_id", "ran_at", "overall",
                        "ready_for_v8_design", "checks", "summary",
                        "next_actions")
  missing <- setdiff(required_fields, names(res))
  if (length(missing) == 0) {
    mark_pass("required_fields_present",
              sprintf("all %d fields", length(required_fields)))
  } else {
    mark_fail("required_fields_present",
              sprintf("missing: %s", paste(missing, collapse = ", ")))
  }

  if (identical(res$gate_id, "v8_design_readiness")) {
    mark_pass("gate_id_valid", "v8_design_readiness")
  } else {
    mark_fail("gate_id_valid", sprintf("got: %s", res$gate_id))
  }

  if (is.list(res$checks) && length(res$checks) >= 14) {
    mark_pass("checks_count",
              sprintf("%d checks (>= 14)", length(res$checks)))
  } else {
    mark_fail("checks_count",
              sprintf("got %d", length(res$checks %||% list())))
  }

  check_struct_ok <- all(sapply(res$checks, function(c) {
    is.list(c) && all(c("id", "name", "status", "details") %in% names(c))
  }))
  if (check_struct_ok) {
    mark_pass("check_structure",
              "all checks have id+name+status+details")
  } else {
    mark_fail("check_structure", "some checks missing fields")
  }

  summary <- res$summary %||% list()
  if (all(c("pass", "fail", "warn", "skip") %in% names(summary))) {
    mark_pass("summary_fields",
              sprintf("pass=%d fail=%d warn=%d skip=%d",
                      summary$pass, summary$fail, summary$warn,
                      summary$skip))
  } else {
    mark_fail("summary_fields", "summary missing fields")
  }
}

# Test 5: status values valid
if (!is.null(res)) {
  valid_statuses <- c("PASS", "FAIL", "WARN", "SKIP")
  invalid <- sapply(res$checks, function(c) !c$status %in% valid_statuses)
  if (sum(invalid) == 0) {
    mark_pass("status_values_valid",
              "모든 check status valid")
  } else {
    mark_fail("status_values_valid",
              sprintf("%d invalid", sum(invalid)))
  }
}

# Test 6: resolve_tool works
if (loaded) {
  for (tool_name in c("qvest_search", "qvest_wt", "qvest_observe")) {
    rt <- resolve_tool(tool_name, PROJ)
    if (rt$found) {
      mark_pass(sprintf("resolve_%s", tool_name),
                sprintf("found at %s", rt$rel))
    } else {
      mark_pass(sprintf("resolve_%s", tool_name),
                sprintf("clear FAIL (%d candidates)",
                        length(rt$candidates)))
    }
  }
}

# Final
total <- PASS_COUNT + FAIL_COUNT
cat("\n", strrep("=", 70), "\n", sep = "")
cat(sprintf("FINAL: %d pass / %d fail / %d total\n",
            PASS_COUNT, FAIL_COUNT, total))
status <- if (FAIL_COUNT == 0) "ALL PASS" else "FAIL"
cat(sprintf("STATUS: %s%s\n",
            if (FAIL_COUNT == 0) "✅ " else "❌ ", status))
cat(strrep("=", 70), "\n", sep = "")

if (FAIL_COUNT > 0) quit(status = 1)
