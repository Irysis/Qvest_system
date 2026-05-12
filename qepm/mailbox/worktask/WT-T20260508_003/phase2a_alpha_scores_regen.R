## ============================================================================
## WT-T20260508_003 — Phase 2a: alpha_scores.parquet Regeneration
##
## Pre-condition: Phase 1 Factor DB rebuild complete (force=TRUE)
##
## Action:
##   - Re-source factor_engine_proposal.R (WT-D20260425_010 Iter 5)
##   - Generate fresh alpha_scores.parquet using rebuilt Factor DB
##   - Backup pre-regen file with timestamped suffix
##
## Boundary:
##   - alpha 정의 변경 X (Iter 5 sleeve 그대로)
##   - 단순히 갱신된 Factor DB로 score 재계산
##
## 추정 시간: ~10-30분 (269 sig_dates × per-date factor join)
## ============================================================================

cat("\n========================================================\n")
cat("  WT-T20260508_003 Phase 2a — alpha_scores.parquet Regen\n")
cat(sprintf("  Started: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat("========================================================\n\n")

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR  <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-T20260508_003")
ART_DIR <- file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260425_010")
ITER5_WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-D20260425_010")

setwd(PROJECT_ROOT)

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
  library(arrow)
})

# ─── Backup pre-regen alpha_scores.parquet ───────────────────────────────────
src <- file.path(ART_DIR, "alpha_scores.parquet")
ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
bak <- file.path(ART_DIR, paste0("alpha_scores_pre_factor_db_rebuild_", ts, ".parquet.bak"))
if (file.exists(src)) {
  file.copy(src, bak, overwrite = FALSE)
  cat(sprintf("[BACKUP] %s -> %s\n", basename(src), basename(bak)))
} else {
  cat(sprintf("[BACKUP] WARN: %s not found (will be created fresh)\n", src))
}

pre_md5 <- if (file.exists(src)) as.character(tools::md5sum(src)) else NA
cat(sprintf("[PRE-REGEN] alpha_scores.parquet md5: %s\n", substr(pre_md5, 1, 16)))

# ─── Source factor_engine_proposal.R (Iter 5 alpha computation) ──────────────
# This script reads factor_db_*.parquet and writes alpha_scores.parquet
fep_path <- file.path(ITER5_WT_DIR, "factor_engine_proposal.R")
if (!file.exists(fep_path)) stop("[FAIL] factor_engine_proposal.R not found: ", fep_path)

cat(sprintf("\n[REGEN] Sourcing factor_engine_proposal.R...\n  %s\n", fep_path))
t_start <- Sys.time()

# Run inside isolated env to avoid global var pollution
local_env <- new.env(parent = globalenv())
result <- tryCatch({
  source(fep_path, local = local_env, echo = FALSE, max.deparse.length = Inf)
  TRUE
}, error = function(e) {
  cat(sprintf("\n[FATAL] factor_engine_proposal.R error: %s\n", conditionMessage(e)))
  FALSE
})

t_end <- Sys.time()
elapsed_min <- as.numeric(difftime(t_end, t_start, units = "mins"))
cat(sprintf("\n[REGEN] Sourcing complete | elapsed %.1f min\n", elapsed_min))

# ─── Verify regenerated file ─────────────────────────────────────────────────
post_md5 <- if (file.exists(src)) as.character(tools::md5sum(src)) else NA
changed <- !is.na(pre_md5) && !is.na(post_md5) && (pre_md5 != post_md5)

a_post <- as.data.table(read_parquet(src))
cat(sprintf("\n[POST-REGEN] alpha_scores.parquet md5: %s | changed: %s\n",
            substr(post_md5, 1, 16), changed))
cat(sprintf("  rows=%s | unique_dates=%d | unique_tickers=%d\n",
            format(nrow(a_post), big.mark=","),
            length(unique(a_post$Date)),
            length(unique(a_post$Ticker))))
cat(sprintf("  Date range: %s ~ %s\n",
            as.character(min(a_post$Date)), as.character(max(a_post$Date))))

# ─── Compare score_eff distribution pre/post (proxy for impact) ──────────────
diag <- list(
  pre_md5 = pre_md5,
  post_md5 = post_md5,
  changed = changed,
  n_rows = nrow(a_post),
  n_dates = length(unique(a_post$Date)),
  n_tickers = length(unique(a_post$Ticker)),
  date_range = list(min = as.character(min(a_post$Date)),
                    max = as.character(max(a_post$Date))),
  score_eff_summary = list(
    mean = round(mean(a_post$score_eff, na.rm=TRUE), 6),
    sd = round(sd(a_post$score_eff, na.rm=TRUE), 6),
    median = round(median(a_post$score_eff, na.rm=TRUE), 6),
    min = round(min(a_post$score_eff, na.rm=TRUE), 6),
    max = round(max(a_post$score_eff, na.rm=TRUE), 6),
    n_finite = sum(is.finite(a_post$score_eff))
  ),
  recent_dates_sample = a_post[!is.na(score_eff)][order(-Date)][1:50,
                          .(Date = as.character(Date), Ticker, score_eff)],
  elapsed_min = round(elapsed_min, 2),
  status = if (isTRUE(result)) "PASS" else "FAIL",
  timestamp_end = format(t_end, "%Y-%m-%dT%H:%M:%S%z")
)

# Try to compare to backup
if (file.exists(bak)) {
  a_pre <- as.data.table(read_parquet(bak))
  setkey(a_pre, Date, Ticker)
  setkey(a_post, Date, Ticker)
  common <- merge(a_pre[, .(Date, Ticker, score_eff_pre = score_eff)],
                  a_post[, .(Date, Ticker, score_eff_post = score_eff)],
                  by = c("Date", "Ticker"))
  if (nrow(common) > 0) {
    common[, delta := score_eff_post - score_eff_pre]
    common_finite <- common[is.finite(delta)]
    diag$score_eff_delta <- list(
      n_compared = nrow(common_finite),
      mean_delta = round(mean(common_finite$delta), 6),
      mean_abs_delta = round(mean(abs(common_finite$delta)), 6),
      sd_delta = round(sd(common_finite$delta), 6),
      max_abs_delta = round(max(abs(common_finite$delta)), 6),
      pct_unchanged_lt_1e6 = round(100 * mean(abs(common_finite$delta) < 1e-6), 2),
      cor_pre_post = round(cor(common_finite$score_eff_pre, common_finite$score_eff_post,
                                use="complete.obs"), 6)
    )
    cat(sprintf("\n[DELTA] n=%d | mean_abs=%.6f | cor=%.6f | pct_unchanged=%.1f%%\n",
                diag$score_eff_delta$n_compared,
                diag$score_eff_delta$mean_abs_delta,
                diag$score_eff_delta$cor_pre_post,
                diag$score_eff_delta$pct_unchanged_lt_1e6))
  }
}

write_json(diag, file.path(WT_DIR, "phase2a_alpha_scores_regen_audit.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("\n[AUDIT] Saved: %s\n", file.path(WT_DIR, "phase2a_alpha_scores_regen_audit.json")))

cat(sprintf("\n========================================================\n"))
cat(sprintf("  Phase 2a alpha_scores Regen — DONE\n"))
cat(sprintf("  status: %s | %.1f min\n", diag$status, elapsed_min))
cat(sprintf("========================================================\n"))
