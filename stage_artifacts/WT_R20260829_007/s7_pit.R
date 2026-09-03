# S7 — PIT 하드 게이트 (detect_lookahead 전 스크립트 스캔)
suppressWarnings(suppressMessages({library(data.table); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT, "02_Infrastructure/validation/lookahead_detector.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_007")
files <- c("s1_panel.R","s2_power.R","s3_primary_fm.R","s4_confound.R","s4b_reattribution.R",
           "s4c_prior_returnpath.R","s4d_universe_reattribution.R","s5_production.R","s6_side.R")
out <- lapply(files, function(f) {
  p <- file.path(OUT, f)
  r <- tryCatch(detect_lookahead(p, verbose = FALSE), error = function(e) list(clean = NA, error = conditionMessage(e)))
  list(file = f, scanned = isTRUE(r$scanned), clean = r$clean, n_violations = r$n_violations %||% 0L,
       violations = if (length(r$violations)) lapply(r$violations, function(v)
         list(code = v$code %||% NA_character_, line = v$line %||% NA_integer_,
              text = substr(v$text %||% "", 1, 200))) else list()) })
names(out) <- files
for (f in files) cat(sprintf("  %-28s scanned=%s clean=%s viol=%d\n", f, out[[f]]$scanned, out[[f]]$clean, out[[f]]$n_violations))
sig_path <- c("s1_panel.R","s3_primary_fm.R","s4_confound.R","s5_production.R")
sig_clean <- all(vapply(sig_path, function(f) isTRUE(out[[f]]$clean), logical(1)))
write_json(list(
  meta = list(wt_id = "WT-R20260829_007", tool = "02_Infrastructure/validation/lookahead_detector.R::detect_lookahead"),
  per_file = out,
  signal_path_files = sig_path, signal_path_clean = sig_clean,
  note = "신호·선별 경로(s1/s3/s4/s5)가 clean 이어야 한다. 보고 경로(s2/s4b/s4c/s4d/s6)의 플래그는 사후 요약통계(sd()*sqrt() 등)일 수 있으므로 코드별로 판독한다."),
  file.path(OUT, "s7_pit.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
cat(sprintf("\n[S7] 신호 경로 clean = %s\n", sig_clean))
