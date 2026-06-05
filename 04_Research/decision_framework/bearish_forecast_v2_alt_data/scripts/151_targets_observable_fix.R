#==============================================================================
# 151_targets_observable_fix.R — Cycle 54D Phase 1+2: Phantom-0 cleanup
#
# CONTEXT (Cycle 54D, 2026-05-21):
#   Cycle 56-2stage T3 audit revealed targets_long_horizon.parquet has
#   phantom-0 contamination: for end-of-data dates where ret_q126 = NaN
#   (forward window not yet observable), y_tail_q126 = 0 (not NaN) due to
#   integer cast bug in 103_compute_long_horizon_targets.R lines 78-79:
#
#     bm[, (y_col) := as.integer(!is.na(get(ret_col)) & !is.na(get(q_col)) &
#                                 get(ret_col) <= get(q_col))]
#
#   When ret_col is NA: !is.na(ret_col) = FALSE → entire AND = FALSE →
#   as.integer(FALSE) = 0 (NOT NA).
#
# AUDIT FINDINGS (this cycle):
#   - q15  : 21 phantom-0 rows (last 21 trading days)
#   - q63  : 63 phantom-0 rows (last 63 trading days)
#   - q126 : 126 phantom-0 rows (2025-11-19 ~ 2026-05-19)
#
#   Total dataset: 8955 rows; phantom-0 confined to TAIL of timeseries.
#   Brief's "Fold 5 (2016-2017): 407/410 rows phantom-0" misreads fold
#   number — Fold 5 in expanding 5-fold OOS CV (2018-01-02 ~ 2026-04-30)
#   = LAST quintile, which includes 2025-11-19 ~ 2026-04-30 phantom-0.
#
# FIX: NaN propagation (Option A, safer)
#   When ret_qH is NA → y_tail_qH = NA (NOT 0).
#   Downstream PR-AUC / IC calculations naturally exclude NA rows.
#   No row dropping → panel size + walk-forward CV splits unchanged.
#
# PIT-safe:
#   Existing predictions trained on PIT-clean features remain valid.
#   Only the EVALUATION step changes (NA rows excluded from PR/IC).
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS  <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
TGT <- file.path(WS, "outputs/02_targets")

SRC      <- file.path(TGT, "targets_long_horizon.parquet")
BACKUP   <- file.path(TGT, "targets_long_horizon.parquet.cycle54d_backup")
OUT_OBS  <- file.path(TGT, "targets_long_horizon_observable.parquet")

cat("\n========== Cycle 54D Phase 1+2: targets observable fix ==========\n")
cat(sprintf("[src]    %s\n", SRC))
cat(sprintf("[backup] %s\n", BACKUP))
cat(sprintf("[out]    %s\n", OUT_OBS))

stopifnot(file.exists(SRC))

#----------------------------------------------------------------------
# Step 1: Backup (only if no backup yet)
#----------------------------------------------------------------------
if (!file.exists(BACKUP)) {
  file.copy(SRC, BACKUP, overwrite = FALSE)
  cat("\n[backup] CREATED (preserving buggy file for historical analysis)\n")
} else {
  cat("\n[backup] EXISTS — skipping (already backed up)\n")
}

#----------------------------------------------------------------------
# Step 2: Read source + audit phantom-0 BEFORE fix
#----------------------------------------------------------------------
tgt <- as.data.table(read_parquet(SRC))
tgt[, Date := as.Date(Date)]
setorder(tgt, Date)

cat(sprintf("\n[source] rows=%d range=%s..%s\n", nrow(tgt), min(tgt$Date), max(tgt$Date)))

audit_pre <- list()
for (h in c("q15", "q63", "q126")) {
  ret_col <- sprintf("ret_%s", h)
  y_col   <- sprintf("y_tail_%s", h)
  na_ret  <- is.na(tgt[[ret_col]])
  na_y    <- is.na(tgt[[y_col]])
  phantom <- na_ret & !na_y
  audit_pre[[h]] <- list(
    n_na_ret    = sum(na_ret),
    n_na_y      = sum(na_y),
    n_phantom_0 = sum(phantom & tgt[[y_col]] == 0),
    n_phantom_1 = sum(phantom & tgt[[y_col]] == 1),
    phantom_dates = if (sum(phantom) > 0) {
      c(format(min(tgt$Date[phantom])), format(max(tgt$Date[phantom])))
    } else NA_character_
  )
}
cat("\n=== PRE-FIX phantom-0 audit ===\n")
for (h in names(audit_pre)) {
  a <- audit_pre[[h]]
  cat(sprintf("[%-5s] NA ret=%d  NA y=%d  phantom_0=%d  phantom_1=%d  range=%s..%s\n",
              h, a$n_na_ret, a$n_na_y, a$n_phantom_0, a$n_phantom_1,
              a$phantom_dates[1], a$phantom_dates[2]))
}

#----------------------------------------------------------------------
# Step 3: Apply NaN propagation fix
#   For each horizon h in {q15, q63, q126}:
#     y_tail_qH <- NA_integer_ where ret_qH is NA
#----------------------------------------------------------------------
tgt_obs <- copy(tgt)

for (h in c("q15", "q63", "q126")) {
  ret_col <- sprintf("ret_%s", h)
  y_col   <- sprintf("y_tail_%s", h)
  na_idx  <- is.na(tgt_obs[[ret_col]])
  n_fixed <- sum(na_idx)
  if (n_fixed > 0) {
    # Use bracket subscript (NOT data.table := with row index) for clarity
    tgt_obs[[y_col]][na_idx] <- NA_integer_
  }
  cat(sprintf("[fix %s] %d rows set to NA (where ret_%s is NA)\n", y_col, n_fixed, h))
}

#----------------------------------------------------------------------
# Step 4: POST-fix audit (verify no phantom remaining)
#----------------------------------------------------------------------
cat("\n=== POST-FIX audit (phantom must be 0) ===\n")
audit_post <- list()
for (h in c("q15", "q63", "q126")) {
  ret_col <- sprintf("ret_%s", h)
  y_col   <- sprintf("y_tail_%s", h)
  na_ret  <- is.na(tgt_obs[[ret_col]])
  na_y    <- is.na(tgt_obs[[y_col]])
  phantom <- na_ret & !na_y
  events  <- sum(tgt_obs[[y_col]] == 1, na.rm=TRUE)
  zeros   <- sum(tgt_obs[[y_col]] == 0, na.rm=TRUE)
  audit_post[[h]] <- list(
    n_na_ret  = sum(na_ret),
    n_na_y    = sum(na_y),
    n_phantom = sum(phantom),
    events    = events,
    zeros     = zeros,
    base_rate = events / max(events + zeros, 1)
  )
  cat(sprintf("[%-5s] NA ret=%d  NA y=%d  phantom=%d  events=%d  zeros=%d  base_rate=%.4f\n",
              h, sum(na_ret), sum(na_y), sum(phantom), events, zeros,
              audit_post[[h]]$base_rate))
}

# Hard assertion: phantom-0 must be 0
all_clean <- all(sapply(audit_post, function(x) x$n_phantom == 0))
if (!all_clean) {
  stop("[ERROR] Phantom-0 NOT cleaned — abort save")
}
cat("\n[ASSERT] all 3 horizons clean (phantom=0) — PASS\n")

# Critical assertion (mirror NEW_CYCLE_CHECKLIST M6 new):
cat("\n[ASSERT M6] sum(is.na(ret_q126) & !is.na(y_tail_q126)) == 0\n")
assert_m6_q126 <- sum(is.na(tgt_obs$ret_q126) & !is.na(tgt_obs$y_tail_q126))
stopifnot(assert_m6_q126 == 0L)
cat(sprintf("[ASSERT M6] PASS (q126 assertion: %d)\n", assert_m6_q126))

#----------------------------------------------------------------------
# Step 5: Save observable parquet
#----------------------------------------------------------------------
write_parquet(tgt_obs, OUT_OBS)
cat(sprintf("\n[saved] %s\n", OUT_OBS))
cat(sprintf("[shape] %d rows × %d cols\n", nrow(tgt_obs), ncol(tgt_obs)))

# Sanity: row count unchanged
stopifnot(nrow(tgt_obs) == nrow(tgt))
cat(sprintf("[verify] row count unchanged: %d == %d ✓\n", nrow(tgt_obs), nrow(tgt)))

#----------------------------------------------------------------------
# Step 6: Save audit json
#----------------------------------------------------------------------
audit_summary <- list(
  cycle      = "54D_Phase1_2",
  timestamp  = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  src        = SRC,
  backup     = BACKUP,
  out        = OUT_OBS,
  fix_method = "NaN_propagation",
  n_rows     = nrow(tgt_obs),
  pre_fix    = audit_pre,
  post_fix   = audit_post,
  m6_assertion_passed = TRUE
)
audit_json_path <- file.path(WS, "outputs/04_evaluation/cycle54d_phase1_audit.json")
jsonlite::write_json(audit_summary, audit_json_path, auto_unbox=TRUE, pretty=TRUE)
cat(sprintf("\n[audit] saved: %s\n", audit_json_path))

cat("\n========== Phase 1+2 DONE — proceed to Phase 3 (152_observable_reeval) ==========\n")
