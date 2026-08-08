# ============================================================================
# run_contract_regression.R - core contract code regression suite runner
# (audit HYG-06, established 2026-07-04)
#
# Targets (all read-only):
#   02_Infrastructure/contracts/essence_score.R
#   02_Infrastructure/contracts/canonical_screen_bt.R
#   02_Infrastructure/contracts/register_module.R
#   02_Infrastructure/hurdle_gate.R
#
# Usage:  Rscript 08_Tests/contract_regression/run_contract_regression.R
# Exit:   0 = all checks PASS (spec-DEFECTs, if any, are listed but tracked
#             as target-code bugs, not test failures)
#         1 = at least one regression FAIL (or a test file crashed)
#
# Each test file runs in its own vanilla Rscript child process for isolation
# (independent PROJECT_ROOT sandboxes under tempdir(), no cross-test state).
# ============================================================================

tests <- c("test_essence_score.R",
           "test_canonical_screen_bt.R",
           "test_register_module.R",
           "test_hurdle_gate.R",
           "test_required_effect_size.R")

.this_file <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
here <- dirname(normalizePath(.this_file, winslash = "/"))
rscript <- file.path(R.home("bin"),
                     if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")

total_pass <- 0L; total_fail <- 0L; total_defect <- 0L; crashed <- character(0)
fail_lines <- character(0); defect_lines <- character(0)

for (tf in tests) {
  cat(sprintf("\n===== %s =====\n", tf))
  out <- suppressWarnings(system2(rscript,
                                  args = c("--vanilla", shQuote(file.path(here, tf))),
                                  stdout = TRUE, stderr = TRUE))
  status <- attr(out, "status"); if (is.null(status)) status <- 0L

  marks <- grep("^\\[(PASS|FAIL|DEFECT)\\]", out, value = TRUE)
  cat(paste(marks, collapse = "\n"), "\n")
  summ <- grep("^TESTSUMMARY ", out, value = TRUE)
  if (length(summ)) cat(summ[1], "\n")

  sel_fail   <- marks[startsWith(marks, "[FAIL]")]
  sel_defect <- marks[startsWith(marks, "[DEFECT]")]
  total_pass <- total_pass + sum(startsWith(marks, "[PASS]"))
  total_fail <- total_fail + length(sel_fail)
  total_defect <- total_defect + length(sel_defect)
  n_fail <- length(sel_fail)
  if (length(sel_fail))   fail_lines   <- c(fail_lines,   paste(tf, sel_fail))
  if (length(sel_defect)) defect_lines <- c(defect_lines, paste(tf, sel_defect))

  if (length(summ) == 0L || (status != 0L && n_fail == 0L)) {
    # child crashed before reaching its summary (source error etc.)
    crashed <- c(crashed, tf)
    cat(sprintf("[CRASH] %s (exit=%d) - last output lines:\n", tf, status))
    cat(paste(tail(out, 12), collapse = "\n"), "\n")
  }
}

cat("\n================ CONTRACT REGRESSION SUMMARY ================\n")
cat(sprintf("files=%d  cases=%d  pass=%d  fail=%d  spec_defect=%d  crashed=%d\n",
            length(tests), total_pass + total_fail + total_defect,
            total_pass, total_fail, total_defect, length(crashed)))
if (length(fail_lines))   cat("FAILURES:\n", paste(" -", fail_lines, collapse = "\n"), "\n")
if (length(defect_lines)) {
  cat("SPEC DEFECTS (target-code bugs, tracked upstream - do not fix here):\n")
  cat(paste(" -", defect_lines, collapse = "\n"), "\n")
}
if (length(crashed)) cat("CRASHED:", paste(crashed, collapse = ", "), "\n")

ok <- (total_fail == 0L && length(crashed) == 0L)
cat(sprintf("RESULT: %s\n", if (ok) "PASS" else "FAIL"))
quit(save = "no", status = if (ok) 0L else 1L)
