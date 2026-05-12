## ============================================================================
## WT-T20260508_004 — Phase 2a: alpha_scores.parquet Regeneration
##
## Pre-condition: Phase 1 incremental SUE/ESBR/ESCR update complete
##
## Action:
##   - Re-source factor_engine_proposal.R (WT-D20260425_010 Iter 5)
##   - Generate fresh alpha_scores.parquet using updated Factor DB (consensus only)
##   - Backup pre-regen file with timestamped suffix
##
## Boundary:
##   - alpha 정의 변경 X (Iter 5 sleeve 그대로)
##   - 단순히 갱신된 Factor DB로 score 재계산 (Phase 1 incremental update 효과 propagate)
##
## Expected impact: 4월 30일 자료 lift는 ~1 sig_date (2026-05-01) score_eff에 국한.
##                  다른 268 sig_date의 PIT cutoff result는 동일 (cache_old PIT-bind retain).
##                  → cor_pre_post > 0.9999 expected
## ============================================================================

cat("\n========================================================\n")
cat("  WT-T20260508_004 Phase 2a — alpha_scores.parquet Regen\n")
cat(sprintf("  Started: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat("========================================================\n\n")

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR  <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-T20260508_004")
ART_DIR <- file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260425_010")
ITER5_WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-D20260425_010")

setwd(PROJECT_ROOT)

suppressPackageStartupMessages({
  library(jsonlite); library(data.table); library(arrow)
})

# ─── Backup pre-regen alpha_scores.parquet ───────────────────────────────────
src <- file.path(ART_DIR, "alpha_scores.parquet")
ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
bak <- file.path(ART_DIR, paste0("alpha_scores_pre_WT004_incremental_", ts, ".parquet.bak"))
if (file.exists(src)) {
  file.copy(src, bak, overwrite = FALSE)
  cat(sprintf("[BACKUP] %s -> %s\n", basename(src), basename(bak)))
}
pre_md5 <- if (file.exists(src)) as.character(tools::md5sum(src)) else NA
cat(sprintf("[PRE-REGEN] alpha_scores.parquet md5: %s\n", substr(pre_md5, 1, 16)))

# ─── Source factor_engine_proposal.R ─────────────────────────────────────────
fep_path <- file.path(ITER5_WT_DIR, "factor_engine_proposal.R")
if (!file.exists(fep_path)) stop("[FAIL] factor_engine_proposal.R not found: ", fep_path)
cat(sprintf("\n[REGEN] Sourcing factor_engine_proposal.R...\n  %s\n", fep_path))
t_start <- Sys.time()

local_env <- new.env(parent = globalenv())
result <- tryCatch({
  source(fep_path, local = local_env, echo = FALSE, max.deparse.length = Inf)
  TRUE
}, error = function(e) {
  cat(sprintf("\n[FATAL] factor_engine_proposal.R error: %s\n", conditionMessage(e)))
  FALSE
})

t_end <- Sys.time()
elapsed_min <- as.numeric(difftime(t_end, t_start, units="mins"))
cat(sprintf("\n[REGEN] Sourcing complete | elapsed %.1f min\n", elapsed_min))

# ─── Verify regenerated file ─────────────────────────────────────────────────
post_md5 <- if (file.exists(src)) as.character(tools::md5sum(src)) else NA
changed <- !is.na(pre_md5) && !is.na(post_md5) && (pre_md5 != post_md5)
a_post <- as.data.table(read_parquet(src))
cat(sprintf("\n[POST-REGEN] md5: %s | changed: %s\n",
            substr(post_md5, 1, 16), changed))
cat(sprintf("  rows=%s | unique_dates=%d | unique_tickers=%d\n",
            format(nrow(a_post), big.mark=","),
            length(unique(a_post$Date)), length(unique(a_post$Ticker))))

# ─── Compare to pre (delta diagnostic) ───────────────────────────────────────
diag <- list(
  pre_md5 = pre_md5, post_md5 = post_md5, changed = changed,
  n_rows = nrow(a_post),
  n_dates = length(unique(a_post$Date)),
  n_tickers = length(unique(a_post$Ticker)),
  date_range = list(min = as.character(min(a_post$Date)),
                    max = as.character(max(a_post$Date))),
  score_eff_summary = list(
    mean = round(mean(a_post$score_eff, na.rm=TRUE), 6),
    sd = round(sd(a_post$score_eff, na.rm=TRUE), 6),
    n_finite = sum(is.finite(a_post$score_eff))
  ),
  elapsed_min = round(elapsed_min, 2),
  status = if (isTRUE(result)) "PASS" else "FAIL",
  timestamp_end = format(t_end, "%Y-%m-%dT%H:%M:%S%z")
)

if (file.exists(bak)) {
  a_pre <- as.data.table(read_parquet(bak))
  common <- merge(a_pre[, .(Date, Ticker, score_eff_pre = score_eff)],
                  a_post[, .(Date, Ticker, score_eff_post = score_eff)],
                  by = c("Date", "Ticker"))
  if (nrow(common) > 0) {
    common[, delta := score_eff_post - score_eff_pre]
    cf <- common[is.finite(delta)]
    diag$score_eff_delta <- list(
      n_compared = nrow(cf),
      mean_abs_delta = round(mean(abs(cf$delta)), 6),
      sd_delta = round(sd(cf$delta), 6),
      max_abs_delta = round(max(abs(cf$delta)), 6),
      pct_unchanged_lt_1e6 = round(100*mean(abs(cf$delta) < 1e-6), 2),
      cor_pre_post = round(cor(cf$score_eff_pre, cf$score_eff_post, use="complete.obs"), 6)
    )

    # Per-Date delta — find sig_dates with maximum impact
    by_date <- cf[, .(mean_abs = mean(abs(delta)),
                       max_abs = max(abs(delta)),
                       n = .N), by = Date]
    setorder(by_date, -mean_abs)
    diag$dates_most_changed <- head(by_date, 10)
    cat(sprintf("\n[DELTA] n=%d | mean_abs=%.6f | cor=%.6f | pct_unchanged=%.1f%%\n",
                diag$score_eff_delta$n_compared,
                diag$score_eff_delta$mean_abs_delta,
                diag$score_eff_delta$cor_pre_post,
                diag$score_eff_delta$pct_unchanged_lt_1e6))
    cat("\n[Top 5 dates with largest mean |delta|]\n")
    print(head(by_date, 5))
  }
}

write_json(diag, file.path(WT_DIR, "phase2a_alpha_scores_regen_audit.json"),
           pretty=TRUE, auto_unbox=TRUE, na="null")
cat(sprintf("\n[AUDIT] Saved: %s\n", file.path(WT_DIR, "phase2a_alpha_scores_regen_audit.json")))
cat(sprintf("\n========================================================\n"))
cat(sprintf("  Phase 2a — %s | %.1f min\n", diag$status, elapsed_min))
cat(sprintf("========================================================\n"))
