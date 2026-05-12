## ============================================================================
## WT-T20260509_001 — Phase 3 + 4: Lockbox vs Updated Comparison
##
## Phase 3: 직전 (WT-T20260508_004 lockbox frozen 240m alpha) vs 신규 (268m updated)
##          5 family metric 비교 + 2024-2026 OOS 구간 alpha 효과
## Phase 4: 5/1 forward holdings ranking 변동 audit
##          - Lockbox (alpha sig_date 2023-12 frozen) vs Updated (sig_date 2026-03)
##          - 6/1 forward (sig_date 2026-04, only updated) 추가 audit
##
## Inputs:
##   - Lockbox baseline: WT-T20260508_004/output/5family_post_incremental/<Sx>/period_returns
##                        (or its summary_table_pre_post in forge_package.json)
##   - Updated: Phase 2 output 5family_metrics_updated.csv + 5family_OOS_metrics.csv
##   - Lockbox alpha: stage_artifacts/WT_D20260425_010/alpha_scores_LOCKBOX_SAFE_BACKUP.parquet
##                     (or alpha_scores_pre_2024_lockbox_*.parquet.bak)
##   - Updated alpha: stage_artifacts/WT_D20260425_010/alpha_scores.parquet (post Phase 1+1b)
##
## Outputs:
##   - comparison_table_lockbox_vs_updated.csv (5 family)
##   - oos_2024_2026_alpha_lift.csv
##   - forward_holdings_diff.csv (5/1 + 6/1)
##   - phase3_4_audit.json
## ============================================================================

cat("\n========================================================\n")
cat("  WT-T20260509_001 Phase 3+4 — Lockbox vs Updated Comparison\n")
cat(sprintf("  Started: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
cat("========================================================\n\n")

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR  <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-T20260509_001")
OUT_DIR <- file.path(WT_DIR, "output")
ART_DIR <- file.path(PROJECT_ROOT, "stage_artifacts/WT_D20260425_010")

setwd(PROJECT_ROOT)

suppressPackageStartupMessages({
  library(jsonlite); library(data.table); library(arrow)
  library(PerformanceAnalytics); library(xts)
})

# ─── Phase 3: lockbox vs updated metrics ─────────────────────────────────────
cat("--- Phase 3: 5-family metrics lockbox vs updated ---\n\n")

# Updated metrics (Phase 2 output)
updated_full <- fread(file.path(OUT_DIR, "5family_metrics_updated.csv"))
updated_oos  <- fread(file.path(OUT_DIR, "5family_OOS_metrics.csv"))

# Lockbox baseline metrics (WT-T20260508_004 forge_package.json summary_table_pre_post)
lockbox_pkg_path <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask/WT-T20260508_004/forge_package.json")
lockbox_pkg <- fromJSON(lockbox_pkg_path, simplifyVector = FALSE)
lockbox_table <- lockbox_pkg$phase_4_comparison_pre_post$comparison_table

lockbox_dt <- rbindlist(lapply(names(lockbox_table), function(nm) {
  x <- lockbox_table[[nm]]
  data.table(family = nm,
             Sharpe_lockbox = x$Sharpe_post,  # post-incremental SUE/ESBR/ESCR but pre-lockbox-release
             CAGR_lockbox   = x$CAGR_post,
             MDD_lockbox    = x$MDD_post)
}), fill = TRUE)

cat("[LOCKBOX BASELINE] 5 family metrics (WT-T20260508_004 256m, 240 sig_dates frozen):\n")
print(lockbox_dt)

# Updated metrics
updated_dt <- updated_full[, .(family,
                                Sharpe_updated = Sharpe,
                                CAGR_updated   = CAGR,
                                MDD_updated    = abs(MDD),  # MDD as positive magnitude
                                Sortino_updated = Sortino,
                                Calmar_updated  = Calmar,
                                Turnover_ann_updated = Turnover_ann,
                                Cost_ann_updated     = Cost_ann,
                                n_months_updated     = n_months,
                                period_updated       = period)]
cat("\n[UPDATED] 5 family metrics (post Phase 1+1b lockbox release, alpha 268m):\n")
print(updated_dt)

# ─── Comparison table ────────────────────────────────────────────────────────
cmp <- merge(lockbox_dt, updated_dt, by = "family", all = TRUE)
cmp[, delta_Sharpe := Sharpe_updated - Sharpe_lockbox]
cmp[, delta_CAGR_pp := (CAGR_updated - CAGR_lockbox) * 100]
cmp[, delta_MDD_pp := (MDD_updated - MDD_lockbox) * 100]
fwrite(cmp, file.path(OUT_DIR, "comparison_table_lockbox_vs_updated.csv"))
cat("\n[COMPARISON TABLE] (lockbox baseline vs updated):\n")
print(cmp[, .(family, Sharpe_lockbox, Sharpe_updated, delta_Sharpe,
              MDD_lockbox, MDD_updated, delta_MDD_pp,
              CAGR_lockbox, CAGR_updated, delta_CAGR_pp)])

# ─── OOS 2024-2026 alpha lift ────────────────────────────────────────────────
cat("\n[OOS 2024-2026 ALPHA LIFT] (lockbox release 효과 — updated only):\n")
print(updated_oos)
fwrite(updated_oos, file.path(OUT_DIR, "oos_2024_2026_alpha_lift.csv"))

# ─── Phase 4: 5/1 + 6/1 forward holdings diff ────────────────────────────────
cat("\n--- Phase 4: 5/1 + 6/1 forward holdings ranking diff ---\n\n")

# Lockbox alpha (240 sig_dates, last = 2023-12-01)
lockbox_alpha_path <- file.path(ART_DIR, "alpha_scores_LOCKBOX_SAFE_BACKUP.parquet")
if (!file.exists(lockbox_alpha_path)) {
  # Fallback to most recent .bak
  baks <- list.files(ART_DIR, pattern = "alpha_scores_pre_2024_lockbox_.*\\.bak$", full.names = TRUE)
  if (length(baks) == 0) {
    baks <- list.files(ART_DIR, pattern = "alpha_scores_pre_.*lockbox.*\\.bak$", full.names = TRUE)
  }
  if (length(baks) > 0) {
    lockbox_alpha_path <- sort(baks, decreasing = TRUE)[1]
    cat(sprintf("[FALLBACK] lockbox alpha = %s\n", basename(lockbox_alpha_path)))
  } else {
    stop("[FAIL] lockbox alpha source not found")
  }
}

a_lockbox <- as.data.table(read_parquet(lockbox_alpha_path))
last_lockbox_d <- max(a_lockbox$Date)
cat(sprintf("[LOCKBOX ALPHA] last sig_date: %s (n_tickers: %d)\n",
            as.character(last_lockbox_d),
            uniqueN(a_lockbox[Date == last_lockbox_d, Ticker])))

# Updated alpha (268 sig_dates, last = 2026-04-01)
a_updated <- as.data.table(read_parquet(file.path(ART_DIR, "alpha_scores.parquet")))
last_updated_d <- max(a_updated$Date)
cat(sprintf("[UPDATED ALPHA] last sig_date: %s (n_tickers: %d)\n",
            as.character(last_updated_d),
            uniqueN(a_updated[Date == last_updated_d, Ticker])))

# Top-20 (sleeve simulation — STR_1715 expand_str1715_holdings logic 간소)
get_top20_by_score <- function(alpha_dt, sig_d, top_n = 20) {
  panel <- alpha_dt[Date == sig_d & !is.na(score_eff)]
  if (nrow(panel) == 0) return(NULL)
  setorder(panel, -score_eff)
  panel[seq_len(min(top_n, nrow(panel))),
        .(rank = .I, Ticker, score_eff = round(score_eff, 4),
          score_core_z = round(score_core_z, 4),
          score_defense_z = round(score_defense_z, 4))]
}

# 5/1 forward (sig_date 2023-12-01 lockbox vs sig_date 2026-03-01 updated)
top20_lockbox_5_1 <- get_top20_by_score(a_lockbox, last_lockbox_d)
top20_updated_5_1 <- get_top20_by_score(a_updated, as.Date("2026-03-01"))

# 6/1 forward (only updated, sig_date 2026-04-01)
top20_updated_6_1 <- get_top20_by_score(a_updated, as.Date("2026-04-01"))

cat("\n=== TOP-20 LOCKBOX (sig_date 2023-12-01) vs UPDATED (sig_date 2026-03-01) ===\n")
cat("\n[LOCKBOX 5/1 forward Top 20]:\n")
print(top20_lockbox_5_1)
cat("\n[UPDATED 5/1 forward Top 20]:\n")
print(top20_updated_5_1)
cat("\n[UPDATED 6/1 forward Top 20] (sig_date 2026-04-01):\n")
print(top20_updated_6_1)

# Overlap analysis
overlap_5_1 <- intersect(top20_lockbox_5_1$Ticker, top20_updated_5_1$Ticker)
new_in_5_1 <- setdiff(top20_updated_5_1$Ticker, top20_lockbox_5_1$Ticker)
exit_in_5_1 <- setdiff(top20_lockbox_5_1$Ticker, top20_updated_5_1$Ticker)
jaccard_5_1 <- length(overlap_5_1) / length(union(top20_lockbox_5_1$Ticker, top20_updated_5_1$Ticker))

overlap_5_6_updated <- intersect(top20_updated_5_1$Ticker, top20_updated_6_1$Ticker)
new_in_6 <- setdiff(top20_updated_6_1$Ticker, top20_updated_5_1$Ticker)
exit_in_6 <- setdiff(top20_updated_5_1$Ticker, top20_updated_6_1$Ticker)
jaccard_5_6_updated <- length(overlap_5_6_updated) / length(union(top20_updated_5_1$Ticker, top20_updated_6_1$Ticker))

cat(sprintf("\n[5/1 LOCKBOX vs UPDATED] Jaccard overlap: %.3f (%d common, %d new, %d exit)\n",
            jaccard_5_1, length(overlap_5_1), length(new_in_5_1), length(exit_in_5_1)))
cat(sprintf("  Overlap tickers: %s\n", paste(overlap_5_1, collapse = ", ")))
cat(sprintf("  New in updated:  %s\n", paste(new_in_5_1, collapse = ", ")))
cat(sprintf("  Exit lockbox:    %s\n", paste(exit_in_5_1, collapse = ", ")))

cat(sprintf("\n[5/1 UPDATED vs 6/1 UPDATED] Jaccard overlap: %.3f (%d common, %d new, %d exit)\n",
            jaccard_5_6_updated, length(overlap_5_6_updated), length(new_in_6), length(exit_in_6)))
cat(sprintf("  New in 6/1:      %s\n", paste(new_in_6, collapse = ", ")))
cat(sprintf("  Exit at 5/1:     %s\n", paste(exit_in_6, collapse = ", ")))

# Save consolidated diff CSV
diff_dt <- rbindlist(list(
  cbind(scenario = "lockbox_5_1_2023_12_01", top20_lockbox_5_1),
  cbind(scenario = "updated_5_1_2026_03_01", top20_updated_5_1),
  cbind(scenario = "updated_6_1_2026_04_01", top20_updated_6_1)
), fill = TRUE)
fwrite(diff_dt, file.path(OUT_DIR, "forward_holdings_diff.csv"))

# ─── Phase 3+4 audit JSON ────────────────────────────────────────────────────
audit_3_4 <- list(
  task_id = "WT-T20260509_001",
  phase = "Phase 3+4",
  phase_3_5family_comparison = list(
    n_families = nrow(cmp),
    comparison_table = cmp,
    interpretation = paste0(
      "5 family lockbox baseline (WT-T20260508_004 256m, 240 sig_dates frozen) vs ",
      "updated (Phase 1+1b 268m, 268 sig_dates with 28 new sig_dates 2024-01 ~ 2026-04). ",
      "Lockbox release effect = (1) 4-layer overlay 28m extension (2024-01 ~ 2026-04 OOS to live) + ",
      "(2) STR_1715 base alpha re-rank. Pure Function R12 정합 (기존 240 row hash invariance 5/5)."
    )
  ),
  phase_3_oos_lift = list(
    period = "2024-01 ~ 2026-04",
    metrics = updated_oos
  ),
  phase_4_forward_holdings = list(
    lockbox_5_1 = list(
      sig_date = as.character(last_lockbox_d),
      n_top20 = nrow(top20_lockbox_5_1),
      tickers = top20_lockbox_5_1$Ticker
    ),
    updated_5_1 = list(
      sig_date = "2026-03-01",
      n_top20 = nrow(top20_updated_5_1),
      tickers = top20_updated_5_1$Ticker
    ),
    updated_6_1 = list(
      sig_date = "2026-04-01",
      n_top20 = nrow(top20_updated_6_1),
      tickers = top20_updated_6_1$Ticker
    ),
    diff_5_1 = list(
      jaccard = round(jaccard_5_1, 4),
      n_overlap = length(overlap_5_1),
      n_new = length(new_in_5_1),
      n_exit = length(exit_in_5_1),
      overlap = overlap_5_1, new = new_in_5_1, exit = exit_in_5_1
    ),
    diff_6_1_vs_5_1 = list(
      jaccard = round(jaccard_5_6_updated, 4),
      n_overlap = length(overlap_5_6_updated),
      n_new = length(new_in_6),
      n_exit = length(exit_in_6),
      new = new_in_6, exit = exit_in_6
    )
  ),
  status = "PASS",
  timestamp_end = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
write_json(audit_3_4, file.path(WT_DIR, "phase3_4_audit.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("\n[AUDIT] Saved: %s\n", file.path(WT_DIR, "phase3_4_audit.json")))
cat(sprintf("\n========================================================\n"))
cat(sprintf("  Phase 3+4 — PASS\n"))
cat(sprintf("========================================================\n"))
