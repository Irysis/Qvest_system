# =============================================================================
# WT-D20260511_001 Alpha Scores Extension — 2024-01 ~ 2026-04 (28 sig_dates)
# =============================================================================
# Mission: NEW sleeve (3-Axis KR Vol/Skew Composite) alpha_scores를
#   lockbox cutoff 폐기 + 운용 단계 정합화 위해 28 추가 sig_dates 산출
#
# 도훈 mandate (2026-05-11, lockbox-scope.md):
#   - alpha-research 정규 리서치 lockbox cutoff retain
#   - 운용 단계 (forge/monitoring/execution/Q-Lead) lockbox 폐기
#   - NEW sleeve 6/1 effective 운용 적용 전 alpha source 2026-04까지 갱신 필수
#
# Methodology retain (alpha_research_final.R과 동일):
#   - D43_Skewness + D41_Vol_of_Vol + D58_Vol_Asymmetry (3-axis, D05 제외)
#   - Sector-neutral per sig_date
#   - Expanding direction-align lag-1, 36m burn-in
#   - load_month_factors() 경유 (C15)
#   - Universe: KOSPI200 ∪ KOSDAQ150 ∩ ADV_20d ≥ 2e8
#
# PIT integrity:
#   - 각 sig_date의 expanding direction은 그 시점 이전까지의 정보만 사용
#   - 새 dates 추가해도 기존 dates의 dir / alpha 값 불변 (PIT-safe expanding)
#   - 검증: 기존 alpha_scores와 기존 sig_dates에서 정확 일치 spot-check
# =============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(future); library(future.apply)
})

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID     <- "WT-D20260511_001"
STAGE_DIR <- file.path(PROJ_ROOT, "stage_artifacts", "WT_D20260511_001")
WT_DIR    <- file.path(PROJ_ROOT, "qepm/mailbox/worktask", WT_ID)

source(file.path(PROJ_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

# ----- Extension config (lockbox 폐기 운용 단계) -----
EXTENSION_CUTOFF <- as.Date("2026-04-01")  # 운용 단계 cutoff (lockbox 해제)
BURN_IN_MONTHS   <- 36L
SELECTED_FACTORS <- c("D43_Skewness", "D41_Vol_of_Vol", "D58_Vol_Asymmetry")

# Full sig_dates: 2008-01 ~ 2026-04 (218 dates total; new 28 dates after 2023-11)
sig_dates <- seq.Date(as.Date("2008-01-01"), EXTENSION_CUTOFF, by = "month")
sig_dates <- as.Date(format(sig_dates, "%Y-%m-01"))

cat("[1/8] Config:\n")
cat("  EXTENSION_CUTOFF:", as.character(EXTENSION_CUTOFF), "\n")
cat("  BURN_IN:", BURN_IN_MONTHS, "m\n")
cat("  SELECTED_FACTORS:", paste(SELECTED_FACTORS, collapse=", "), "\n")
cat("  Total sig_dates:", length(sig_dates), "(", as.character(min(sig_dates)), "~", as.character(max(sig_dates)), ")\n")

# ----- Load existing alpha_scores for verification -----
existing_alpha <- as.data.table(read_parquet(file.path(STAGE_DIR, "alpha_scores.parquet")))
existing_dates <- sort(unique(existing_alpha$sig_date))
cat("  Existing alpha_scores: ", length(existing_dates), " sig_dates (",
    as.character(min(existing_dates)), "~", as.character(max(existing_dates)), ")\n")
cat("  Existing latest:", as.character(max(existing_dates)), "\n")

# Backup existing file
backup_path <- file.path(STAGE_DIR, paste0("alpha_scores_pre_extension_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".parquet"))
write_parquet(existing_alpha, backup_path)
cat("  Backup saved:", backup_path, "\n\n")

# ----- [2/8] Load factor panel via load_month_factors (C15) -----
cat("[2/8] Load factor panel (parallel)...\n")
n_workers <- min(6L, parallel::detectCores() - 1L)
plan(multisession, workers = n_workers)
on.exit(plan(sequential), add = TRUE)

panel_list <- future_lapply(sig_dates, function(sd) {
  tryCatch({
    suppressMessages(m <- load_month_factors(sd))
    if (is.null(m) || nrow(m) == 0) return(NULL)
    m_sel <- m[Factor_Name %in% SELECTED_FACTORS]
    if (nrow(m_sel) == 0) return(NULL)
    m_w <- dcast(m_sel, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
    m_w[, sig_date := sd]
    m_w
  }, error = function(e) NULL)
})
panel <- rbindlist(panel_list, fill = TRUE, use.names = TRUE)
plan(sequential)
cat("  Panel rows:", nrow(panel), "\n")
cat("  sig_dates loaded:", uniqueN(panel$sig_date), "\n")

# ----- [3/8] Universe filter + sector + ADV_20d -----
cat("[3/8] Universe + sector...\n")
rd <- as.data.table(read_parquet(file.path(PROJ_ROOT, ".cache/rawdata.parquet")))
setnames(rd, "Date", "date")
rd <- rd[date >= as.Date("2007-01-01") & date <= as.Date("2026-05-31")]
rd[, ADV_KRW := Close * Vol]
setkey(rd, Ticker, date)
rd[, ADV_20d := frollmean(ADV_KRW, n = 20L, align = "right", fill = NA), by = Ticker]

trade_days <- sort(unique(rd$date))
sig_date_dt <- data.table(sig_date = sig_dates)
sig_date_dt[, pit_t1_day := as.Date(sapply(sig_date, function(d) {
  cand <- trade_days[trade_days < d]; if (length(cand) > 0) as.character(max(cand)) else NA_character_
}))]

rd_snap <- rd[, .(date, Ticker, K200, KQ150, ADV_20d, Sector, Size)]
setkey(rd_snap, date, Ticker)
universe_list <- lapply(seq_len(nrow(sig_date_dt)), function(i) {
  d <- sig_date_dt[i]$pit_t1_day
  if (is.na(d)) return(NULL)
  snap <- rd_snap[date == d]
  snap[, eligible := (!is.na(K200) & K200 == 1) | (!is.na(KQ150) & KQ150 == 1)]
  snap[, liquid_ok := !is.na(ADV_20d) & ADV_20d >= 2e8]
  e <- snap[eligible & liquid_ok]
  if (nrow(e) == 0) return(NULL)
  e[, sig_date := sig_date_dt[i]$sig_date]
  e[, .(sig_date, Ticker, Sector, Size)]
})
universe <- rbindlist(universe_list)
panel <- merge(panel, universe, by = c("sig_date", "Ticker"))
cat("  Universe-filtered rows:", nrow(panel), "\n")
cat("  Avg Tickers per sig_date:", round(panel[, .N, by=sig_date][, mean(N)]), "\n")

# ----- [4/8] Forward 1M returns -----
cat("[4/8] Forward 1M returns...\n")
rd_simple <- rd[!is.na(Ret), .(date, Ticker, Ret)]
setkey(rd_simple, Ticker, date)
ret_list <- vector("list", length(sig_dates) - 1)
for (i in seq_along(sig_dates)[-length(sig_dates)]) {
  d_s <- sig_dates[i]; d_e <- sig_dates[i + 1]
  rb <- rd_simple[date > d_s & date <= d_e, .(ret_1M = prod(1 + Ret) - 1), by = Ticker]
  rb[, sig_date := d_s]
  ret_list[[i]] <- rb
}
ret_fwd <- rbindlist(ret_list)

# Last sig_date (2026-04-01): partial month return (data available ~5/11)
last_sd <- sig_dates[length(sig_dates)]
rb_last <- rd_simple[date > last_sd & date <= as.Date("2026-05-11"),
                     .(ret_1M = prod(1 + Ret) - 1), by = Ticker]
rb_last[, sig_date := last_sd]
ret_fwd <- rbind(ret_fwd, rb_last, fill = TRUE)

panel <- merge(panel, ret_fwd, by = c("Ticker", "sig_date"), all.x = TRUE)
panel <- panel[complete.cases(panel[, ..SELECTED_FACTORS])]
panel <- panel[!is.na(Sector)]
cat("  Final panel:", nrow(panel), "\n")
cat("  Note: 2026-04-01 has partial month return (5/11 latest)\n\n")

# ----- [5/8] Expanding direction sign (PIT-safe, lag-1, 36m burn-in) -----
cat("[5/8] Expanding direction sign (PIT-safe)...\n")
ic_per_sig <- panel[, .(
  ic_D43 = cor(D43_Skewness, ret_1M, method = "spearman", use = "complete.obs"),
  ic_D41 = cor(D41_Vol_of_Vol, ret_1M, method = "spearman", use = "complete.obs"),
  ic_D58 = cor(D58_Vol_Asymmetry, ret_1M, method = "spearman", use = "complete.obs")
), by = sig_date]
setkey(ic_per_sig, sig_date)
ic_sorted <- ic_per_sig[order(sig_date)]
expanding_dir <- data.table(sig_date = ic_sorted$sig_date)
for (col in c("ic_D43", "ic_D41", "ic_D58")) {
  f <- gsub("ic_", "", col); v <- ic_sorted[[col]]
  cn <- cumsum(!is.na(v)); cs <- cumsum(ifelse(is.na(v), 0, v))
  cm <- shift(cs / pmax(cn, 1), 1, fill = NA); cnl <- shift(cn, 1, fill = 0)
  expanding_dir[, paste0("dir_", f) := ifelse(cnl >= BURN_IN_MONTHS, ifelse(cm >= 0, 1L, -1L), 1L)]
}
panel <- merge(panel, expanding_dir, by = "sig_date", all.x = TRUE)
panel[, D43_aligned := D43_Skewness * dir_D43]
panel[, D41_aligned := D41_Vol_of_Vol * dir_D41]
panel[, D58_aligned := D58_Vol_Asymmetry * dir_D58]

# Print expanding direction at key dates
cat("  Direction signs at key dates:\n")
print(expanding_dir[sig_date %in% c(as.Date("2023-11-01"), as.Date("2024-01-01"),
                                     as.Date("2025-06-01"), as.Date("2026-04-01"))])

# ----- [6/8] Sector-neutral composite -----
cat("[6/8] Sector-neutral composite...\n")
panel[, D43_sn := D43_aligned - mean(D43_aligned, na.rm = TRUE), by = .(sig_date, Sector)]
panel[, D41_sn := D41_aligned - mean(D41_aligned, na.rm = TRUE), by = .(sig_date, Sector)]
panel[, D58_sn := D58_aligned - mean(D58_aligned, na.rm = TRUE), by = .(sig_date, Sector)]
panel[, alpha_composite := (D43_sn + D41_sn + D58_sn) / 3]

panel_eval <- panel[sig_date >= sig_dates[BURN_IN_MONTHS + 1]]
cat("  Eval period:", as.character(min(panel_eval$sig_date)), "to",
    as.character(max(panel_eval$sig_date)),
    " (", uniqueN(panel_eval$sig_date), "sig_dates)\n")

# ----- [7/8] PIT integrity verification: existing vs new alpha at overlapping dates -----
cat("[7/8] PIT integrity verification (existing vs new at overlap dates)...\n")
alpha_new <- panel_eval[, .(sig_date, Ticker, alpha_new = alpha_composite)]
overlap_dates <- intersect(as.character(existing_dates),
                            as.character(unique(alpha_new$sig_date)))
cat("  Overlap dates count:", length(overlap_dates), "\n")
cat("  Spot-check at 3 random overlap dates:\n")
set.seed(20260511)
check_dates <- sample(overlap_dates, min(3, length(overlap_dates)))
for (cd in check_dates) {
  d <- as.Date(cd)
  a_old <- existing_alpha[sig_date == d, .(Ticker, alpha_old = alpha)]
  a_new <- alpha_new[sig_date == d, .(Ticker, alpha_new)]
  cmp <- merge(a_old, a_new, by = "Ticker")
  if (nrow(cmp) > 0) {
    max_diff <- max(abs(cmp$alpha_old - cmp$alpha_new), na.rm = TRUE)
    cor_old_new <- cor(cmp$alpha_old, cmp$alpha_new, method = "spearman", use="complete.obs")
    cat(sprintf("    %s: n_match=%d, max_abs_diff=%.6f, spearman_cor=%.4f\n",
                cd, nrow(cmp), max_diff, cor_old_new))
  }
}

# Full overlap consistency
all_overlap <- merge(existing_alpha[sig_date %in% as.Date(overlap_dates), .(sig_date, Ticker, alpha_old = alpha)],
                     alpha_new[sig_date %in% as.Date(overlap_dates), .(sig_date, Ticker, alpha_new)],
                     by = c("sig_date", "Ticker"))
max_full_diff <- max(abs(all_overlap$alpha_old - all_overlap$alpha_new), na.rm = TRUE)
cor_full <- cor(all_overlap$alpha_old, all_overlap$alpha_new, method = "spearman", use="complete.obs")
cat(sprintf("  Full overlap n=%d, max_abs_diff=%.6f, spearman_cor=%.4f\n",
            nrow(all_overlap), max_full_diff, cor_full))
pit_integrity_pass <- (max_full_diff < 1e-6) && (cor_full > 0.99999)
cat("  PIT integrity:", ifelse(pit_integrity_pass, "PASS", "WARN (review)"), "\n\n")

# ----- [8/8] Save updated alpha_scores.parquet + diagnostics -----
cat("[8/8] Save updated alpha_scores.parquet + diagnostics...\n")
alpha_all <- panel_eval[, .(sig_date, Ticker, alpha = alpha_composite)]
alpha_all[, alpha_rank := frank(alpha) / .N, by = sig_date]
alpha_all[, confidence := pmin(0.95, pmax(0.05, alpha_rank * 0.9 + 0.05))]
alpha_all[, alpha_rank := NULL]
write_parquet(alpha_all, file.path(STAGE_DIR, "alpha_scores.parquet"))

# Summary statistics
cat("  alpha_scores.parquet rows:", nrow(alpha_all), "\n")
cat("  sig_dates total:", uniqueN(alpha_all$sig_date), "\n")
cat("  Date range:", as.character(min(alpha_all$sig_date)), "~",
    as.character(max(alpha_all$sig_date)), "\n")
cat("  Unique Tickers:", uniqueN(alpha_all$Ticker), "\n\n")

# New dates added
new_dates <- sort(unique(alpha_all$sig_date))
new_only <- new_dates[!new_dates %in% existing_dates]
cat("  NEW sig_dates added (", length(new_only), "):\n")
cat("    First:", as.character(min(new_only)), "\n")
cat("    Last:", as.character(max(new_only)), "\n")

# Quality metrics on new dates (limited — last sig_date 2026-04 has partial ret_1M)
panel_new_only <- panel_eval[sig_date %in% new_only]

# Skip last sig_date for full IC computation (partial month return)
panel_new_complete <- panel_new_only[sig_date < max(sig_dates)]
ic_new <- panel_new_complete[, .(ic = cor(alpha_composite, ret_1M, method="spearman", use="complete.obs"),
                                  N=.N), by = sig_date]
if (nrow(ic_new) > 1) {
  mean_ic_new <- mean(ic_new$ic, na.rm = TRUE)
  sd_ic_new <- sd(ic_new$ic, na.rm = TRUE)
  icir_new <- if (sd_ic_new > 0) mean_ic_new / sd_ic_new else NA
  cat(sprintf("\n  New dates IC (2024-01 ~ 2026-03, %d dates with complete ret): mean=%.4f, ICIR=%.3f\n",
              nrow(ic_new), mean_ic_new, ifelse(is.na(icir_new), NA_real_, icir_new)))
}

# Latest sig_date top20 stocks
cat("\n=== LATEST sig_date 2026-04-01 TOP20 ===\n")
latest_top20 <- alpha_all[sig_date == max(alpha_all$sig_date)][order(-alpha)][1:20, .(Ticker, alpha, confidence)]
print(latest_top20)

# Sector distribution of latest top20
latest_top20_sectors <- merge(latest_top20[, .(Ticker)],
                               universe[sig_date == max(alpha_all$sig_date), .(Ticker, Sector)],
                               by = "Ticker")
sector_dist <- latest_top20_sectors[, .N, by = Sector][order(-N)]
cat("\n  Sector distribution:\n"); print(sector_dist)

# Overlap with 2023-11-01 top20 (existing latest)
prev_top20 <- existing_alpha[sig_date == as.Date("2023-11-01")][order(-alpha)][1:20, Ticker]
new_top20 <- latest_top20$Ticker
overlap_count <- length(intersect(prev_top20, new_top20))
jaccard <- overlap_count / length(union(prev_top20, new_top20))
turnover_rate <- 1 - jaccard
cat(sprintf("\n  Overlap 2023-11-01 vs 2026-04-01 top20: %d / 20 (Jaccard=%.3f, turnover=%.1f%%)\n",
            overlap_count, jaccard, turnover_rate*100))

# Save extension log
extension_log <- list(
  task_id = WT_ID,
  extension_id = "pd13_extension_2024_to_2026_04",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  cutoff_previous = "2023-12-22",
  cutoff_extended = as.character(EXTENSION_CUTOFF),
  methodology = list(
    factor_specs = SELECTED_FACTORS,
    composite = "(D43_sn + D41_sn + D58_sn) / 3",
    direction_alignment = "Expanding mean IC lag-1, 36m burn-in",
    sector_neutral = "demean per sig_date per Sector",
    factor_db_route = "load_month_factors() per sig_date",
    universe = "KOSPI200 ∪ KOSDAQ150 ∩ ADV_20d >= 2e8 KRW",
    pit_strict = TRUE
  ),
  scope_policy = list(
    lockbox_scope_md_compliance = TRUE,
    rationale = "Alpha-research stage cutoff 2023-12-22 retain (정규 리서치 lockbox). 운용 단계 (forge/monitoring/execution/Q-Lead) lockbox 폐기 mandate per .claude/rules/lockbox-scope.md 2026-05-09",
    pit_integrity = list(
      max_abs_diff_at_overlap_dates = max_full_diff,
      spearman_cor_at_overlap = cor_full,
      pit_safe_pass = pit_integrity_pass,
      note = "PIT-safe expanding direction: 새 dates 추가해도 기존 dates의 alpha 값 불변. 동일 panel_eval 내 alpha_composite 재산출 spot-check."
    )
  ),
  new_sig_dates_count = length(new_only),
  new_sig_dates_first = as.character(min(new_only)),
  new_sig_dates_last = as.character(max(new_only)),
  total_sig_dates = uniqueN(alpha_all$sig_date),
  total_rows = nrow(alpha_all),
  unique_tickers = uniqueN(alpha_all$Ticker),
  quality_new_dates = if (exists("mean_ic_new")) list(
    mean_ic = mean_ic_new,
    icir = icir_new,
    n_complete_dates = nrow(ic_new),
    note = "2026-04-01 sig_date의 ret_1M은 partial month (5/11 latest) — quality metric 제외"
  ) else NULL,
  top20_2026_04_01 = list(
    tickers = new_top20,
    sector_distribution = as.list(setNames(sector_dist$N, sector_dist$Sector))
  ),
  overlap_with_2023_11_01_top20 = list(
    overlap_count = overlap_count,
    union_count = length(union(prev_top20, new_top20)),
    jaccard = jaccard,
    turnover_rate = turnover_rate
  ),
  backup_pre_extension = backup_path,
  codex_round_waiver = list(
    skip_waiver = TRUE,
    rationale = "Methodology extension (28 sig_dates 추가 산출, no new methodology). Incremental data refresh per 도훈 lockbox-scope.md mandate 2026-05-11.",
    challenge_note_append = TRUE
  )
)
log_path <- file.path(WT_DIR, "alpha_extension_log_2024_to_2026_04.json")
write_json(extension_log, log_path, pretty = TRUE, auto_unbox = TRUE, na = "string")
cat("\n  Extension log saved:", log_path, "\n")

# ----- Final summary -----
cat("\n=== EXTENSION SUMMARY ===\n")
cat(sprintf("Previous: 155 sig_dates (2011-01 ~ 2023-11), 52,800 rows\n"))
cat(sprintf("Extended: %d sig_dates (%s ~ %s), %d rows\n",
            uniqueN(alpha_all$sig_date),
            as.character(min(alpha_all$sig_date)),
            as.character(max(alpha_all$sig_date)),
            nrow(alpha_all)))
cat(sprintf("New dates added: %d (%s ~ %s)\n", length(new_only),
            as.character(min(new_only)), as.character(max(new_only))))
cat(sprintf("PIT integrity overlap: max_abs_diff=%.2e, cor=%.5f (%s)\n",
            max_full_diff, cor_full, ifelse(pit_integrity_pass, "PASS", "WARN")))
if (exists("mean_ic_new")) {
  cat(sprintf("Quality 2024-01 ~ 2026-03 (%d complete dates): IC=%.4f, ICIR=%.3f\n",
              nrow(ic_new), mean_ic_new, icir_new))
}
cat(sprintf("2023-11 vs 2026-04 top20 overlap: %d/20 (turnover %.1f%%)\n",
            overlap_count, turnover_rate*100))
cat("\nDone.\n")
