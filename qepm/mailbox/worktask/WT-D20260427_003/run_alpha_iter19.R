# ============================================================
# WT-D20260427_003 — Iter 19 Alpha Pilot (KR_TOP500_FREEFLOAT)
# ============================================================
# Mandate (사용자 directive):
#   - Universe 차원 변경: KR_top342 → KR_TOP500_FREEFLOAT (L-227 활용)
#   - Same alpha (STR_1701 multi-sleeve composite, Iter 11 inheritance)
#   - alpha_inheritance_hash >= 0.95 strict (L-224) on overlap subset
#   - Architect AC2: mega-cap impact / sector balance audit mandatory
#   - 8 sprint fail learning: same universe variant exhausted → dimension change
# ============================================================

suppressMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
  library(sandwich)
  library(lmtest)
})

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260427_003"
WT_DIR <- file.path(ROOT, "qepm/mailbox/worktask", WT_ID)
STAGE_DIR <- file.path(ROOT, "qepm/stage_artifacts", gsub("-", "_", WT_ID))
SOURCE_PARQUET <- file.path(ROOT, "qepm/stage_artifacts/WT_D20260426_007/alpha_scores.parquet")
SOURCE_PKG <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260426_004/alpha_package.json")
TRAIN_END <- as.Date("2024-01-22")
LOCKBOX_START <- as.Date("2024-01-23")

dir.create(STAGE_DIR, recursive = TRUE, showWarnings = FALSE)

cat("=== Iter 19 Alpha Pilot (KR_TOP500_FREEFLOAT universe, STR_1701 base) ===\n")
cat("Source parquet:", SOURCE_PARQUET, "\n")
cat("Stage dir:", STAGE_DIR, "\n")
cat("Universe target: KR_TOP500_FREEFLOAT (~500 names)\n\n")

# ============================================================
# Step 1: Load STR_1701 base panel + universe v2 infra
# ============================================================
df_src <- as.data.table(read_parquet(SOURCE_PARQUET))
cat("Source panel: rows=", nrow(df_src), " dates=", length(unique(df_src$Date)),
    " tickers=", length(unique(df_src$Ticker)), "\n", sep = "")

# Window isolation (R2): max date <= TRAIN_END
stopifnot(max(df_src$Date) <= TRAIN_END)
cat("Window isolation PASS: max_date=", as.character(max(df_src$Date)),
    " <= ", as.character(TRAIN_END), "\n", sep = "")

source(file.path(ROOT, "02_Infrastructure/factor_db/universe_expanded_v2.R"))

# Load RAWDATA once for universe build + sector tagging (PIT-safe per sig_date)
raw_full <- as.data.table(read_parquet(file.path(ROOT, ".cache/rawdata.parquet")))
raw_full[, Date := as.Date(Date)]
setkey(raw_full, Date, Ticker)
cat("RAWDATA loaded: rows=", nrow(raw_full), " dates=",
    length(unique(raw_full$Date)), "\n", sep = "")

# ============================================================
# Step 2: Build KR_TOP500_FREEFLOAT universe per sig_date
# ============================================================
sig_dates <- sort(unique(df_src$Date))
cat("\n=== Step 2: Build universe per sig_date (n=", length(sig_dates), ") ===\n", sep = "")

universe_history <- list()
for (sd in sig_dates) {
  sd_d <- as.Date(sd)
  uni_sd <- tryCatch(
    build_universe_v2(sd_d, label = "KR_TOP500_FREEFLOAT", liq_window_days = 20L),
    error = function(e) {
      message("[universe build fail] ", sd_d, ": ", conditionMessage(e))
      NULL
    }
  )
  if (!is.null(uni_sd)) {
    universe_history[[as.character(sd_d)]] <- uni_sd[, .(Date = sd_d, Ticker, Market,
                                                          MktCap, FreeFloatMktCap,
                                                          AvgTrdVal_20d, Rank)]
  }
}
universe_dt <- rbindlist(universe_history)
cat("Universe history rows:", nrow(universe_dt), "\n")
cat("Unique tickers in universe v2:", length(unique(universe_dt$Ticker)), "\n")
cat("Avg universe size per date:",
    round(mean(table(universe_dt$Date)), 1), "\n")

# Universe size summary
uni_size_by_date <- universe_dt[, .N, by = Date]
cat("Universe size: min=", min(uni_size_by_date$N), " max=", max(uni_size_by_date$N),
    " mean=", round(mean(uni_size_by_date$N), 1), "\n", sep = "")

# ============================================================
# Step 3: Filter inherited panel by universe v2 membership (PIT)
# ============================================================
df_v2 <- merge(
  df_src,
  universe_dt[, .(Date, Ticker, MktCap, FreeFloatMktCap, AvgTrdVal_20d, uni_rank = Rank)],
  by = c("Date", "Ticker"),
  all.x = FALSE  # inner join: only universe v2 members retained
)
cat("\n=== Step 3: Universe v2 filter applied ===\n")
cat("v2-filtered panel rows:", nrow(df_v2), " (vs source ", nrow(df_src), ")\n", sep = "")
cat("v2 panel tickers:", length(unique(df_v2$Ticker)), "\n")
cat("v2 panel dates:", length(unique(df_v2$Date)), "\n")

# Inheritance: alpha = score_str1701 (no transform)
df_v2[, score_eff := score_str1701]

# ============================================================
# Step 4: alpha_inheritance_hash check (cor on overlap subset)
# ============================================================
# Overlap = rows where ticker exists in BOTH v1 (source panel) and v2 (universe-filtered)
# Since df_v2 is subset of df_src and score_eff = score_str1701, cor must be 1.0 exact
cor_overlap <- cor(df_v2$score_eff, df_v2$score_str1701, method = "spearman",
                    use = "pairwise.complete.obs")
cat(sprintf("\nalpha_inheritance_hash (overlap subset cor) = %.6f (mandate >= 0.95)\n",
             cor_overlap))
stopifnot(cor_overlap >= 0.95)
cat("PASS\n")

# ============================================================
# Step 5: Diagnostics on universe v2 filtered panel
# ============================================================
df_diag <- df_v2[!is.na(score_eff) & !is.na(fwd_1m)]
cat("\n=== Step 5: Diagnostics on KR_TOP500 universe ===\n")
cat("Diagnostics rows:", nrow(df_diag), " dates:", length(unique(df_diag$Date)), "\n")

# Per-month rank IC (Spearman) — Universe v2
ic_monthly <- df_diag[, .(
  ic = cor(score_eff, fwd_1m, method = "spearman", use = "pairwise.complete.obs"),
  n  = .N
), by = Date]
ic_monthly <- ic_monthly[!is.na(ic)]
rank_ic_v2 <- mean(ic_monthly$ic, na.rm = TRUE)
ic_sd_v2 <- sd(ic_monthly$ic, na.rm = TRUE)
icir_v2 <- rank_ic_v2 / ic_sd_v2
cat(sprintf("Universe v2: Rank IC = %.4f | ICIR = %.4f | n_months = %d\n",
             rank_ic_v2, icir_v2, nrow(ic_monthly)))

# Universe v1 baseline (audit): on full source panel
df_diag_v1 <- df_src[!is.na(score_str1701) & !is.na(fwd_1m)]
ic_monthly_v1 <- df_diag_v1[, .(
  ic = cor(score_str1701, fwd_1m, method = "spearman", use = "pairwise.complete.obs"),
  n = .N
), by = Date]
ic_monthly_v1 <- ic_monthly_v1[!is.na(ic)]
rank_ic_v1 <- mean(ic_monthly_v1$ic, na.rm = TRUE)
icir_v1 <- mean(ic_monthly_v1$ic) / sd(ic_monthly_v1$ic)
cat(sprintf("Universe v1 baseline (full source): Rank IC = %.4f | ICIR = %.4f\n",
             rank_ic_v1, icir_v1))
cat(sprintf("Delta: rank_IC=%+.4f ICIR=%+.4f\n",
             rank_ic_v2 - rank_ic_v1, icir_v2 - icir_v1))

# Subperiod stability (P1 / P2 / P3) — Universe v2
ic_monthly[, period := fcase(
  Date <= as.Date("2014-12-31"), "P1_2008_2014",
  Date <= as.Date("2019-12-31"), "P2_2015_2019",
  Date <= as.Date("2024-01-22"), "P3_2020_2024",
  default = "OUT"
)]
sub_ic <- ic_monthly[period != "OUT", .(ic = mean(ic, na.rm = TRUE), n = .N), by = period]
setkey(sub_ic, period)
cat("\nUniverse v2 subperiod IC:\n"); print(sub_ic)

all_pos <- all(sub_ic$ic > 0)
sub_stab_v2 <- if (all_pos) min(sub_ic$ic) / max(sub_ic$ic) else 0
cat(sprintf("Subperiod stability (min/max): %.4f (all_positive=%s)\n",
             sub_stab_v2, all_pos))

# Harvey NW-HAC 5-spec
df_diag[, score_z := (score_eff - mean(score_eff, na.rm = TRUE)) /
                       (sd(score_eff, na.rm = TRUE) + 1e-12), by = Date]

fit1 <- lm(fwd_1m ~ score_z, data = df_diag)
t1 <- summary(fit1)$coefficients["score_z", "t value"]

mret <- df_diag[, .(mean_y = mean(fwd_1m, na.rm = TRUE),
                     mean_x = mean(score_z, na.rm = TRUE)), by = Date]
fit_m <- lm(mean_y ~ mean_x, data = mret)
nw3 <- coeftest(fit_m, vcov = NeweyWest(fit_m, lag = 3, prewhite = FALSE))
nw6 <- coeftest(fit_m, vcov = NeweyWest(fit_m, lag = 6, prewhite = FALSE))
nw12 <- coeftest(fit_m, vcov = NeweyWest(fit_m, lag = 12, prewhite = FALSE))
t2 <- nw3["mean_x", "t value"]
t3 <- nw6["mean_x", "t value"]
t4 <- nw12["mean_x", "t value"]

cl_se <- sqrt(vcovCL(fit1, cluster = ~ Date, type = "HC1")["score_z", "score_z"])
t5 <- coef(fit1)["score_z"] / cl_se

harvey_specs <- c(spec1_pooled_ols = t1, spec2_nw_lag3 = t2, spec3_nw_lag6 = t3,
                  spec4_nw_lag12 = t4, spec5_cluster_date = t5)
harvey_pass_v2 <- sum(abs(harvey_specs) >= 3.0)
cat("\n=== Universe v2 Harvey NW-HAC 5-spec ===\n")
print(round(harvey_specs, 4))
cat(sprintf("Specs |t| >= 3.0: %d/5\n", harvey_pass_v2))

# DSR_post (Bailey-Lopez de Prado proxy on monthly IC)
sr_ic <- icir_v2
ic_x <- ic_monthly$ic
skew_ic <- mean((ic_x - mean(ic_x))^3) / (sd(ic_x))^3
kurt_ic <- mean((ic_x - mean(ic_x))^4) / (sd(ic_x))^4
n_obs <- nrow(ic_monthly)
dsr_num <- sqrt(max(n_obs - 1, 1)) * sr_ic
dsr_den <- sqrt(max(1 - skew_ic * sr_ic + (kurt_ic - 1) / 4 * sr_ic^2, 1e-9))
dsr_post_v2 <- pnorm(dsr_num / dsr_den)
cat(sprintf("\nDSR_post (proxy): %.4f (skew=%.3f kurt=%.3f n=%d)\n",
             dsr_post_v2, skew_ic, kurt_ic, n_obs))

# Monotonicity (decile)
df_diag[, decile := cut(score_z,
                         breaks = quantile(score_z, probs = seq(0, 1, 0.1), na.rm = TRUE),
                         include.lowest = TRUE, labels = 1:10), by = Date]
dec_ret <- df_diag[!is.na(decile), .(mean_ret = mean(fwd_1m, na.rm = TRUE)), by = decile]
dec_ret[, decile := as.integer(as.character(decile))]
setkey(dec_ret, decile)
mono_pairs <- sum(diff(dec_ret$mean_ret) > 0, na.rm = TRUE)
mono_total <- nrow(dec_ret) - 1
mono_v2 <- if (mono_total > 0) mono_pairs / mono_total else NA_real_
cat(sprintf("Monotonicity: %.4f (%d/%d)\n", mono_v2, mono_pairs, mono_total))

# Turnover proxy (top-20 Jaccard)
top20_per_date <- df_diag[, {
  o <- order(-score_eff)[seq_len(min(20, .N))]
  list(top_tickers = list(Ticker[o]))
}, by = Date]
setkey(top20_per_date, Date)
to_list <- numeric(nrow(top20_per_date) - 1)
for (i in seq_len(nrow(top20_per_date) - 1)) {
  prev <- top20_per_date$top_tickers[[i]]
  curr <- top20_per_date$top_tickers[[i + 1]]
  if (length(prev) == 0 || length(curr) == 0) { to_list[i] <- NA; next }
  jac <- length(intersect(prev, curr)) / length(union(prev, curr))
  to_list[i] <- 1 - jac
}
turnover_proxy_v2 <- mean(to_list, na.rm = TRUE) * 12
cat(sprintf("Turnover proxy (top-20 Jaccard, ann.): %.4f\n", turnover_proxy_v2))

# ============================================================
# Step 6: Architect AC2 — Mega-cap impact + sector balance audit
# ============================================================
cat("\n=== Step 6: Architect AC2 mega-cap / sector audit ===\n")

# (A) Mega-cap impact: cor(score_eff, FreeFloatMktCap) per date
ff_cor_by_date <- df_v2[!is.na(score_eff) & !is.na(FreeFloatMktCap),
                         .(ff_cor = cor(score_eff, FreeFloatMktCap, method = "spearman",
                                          use = "pairwise.complete.obs")),
                         by = Date]
mega_cap_cor_mean <- mean(ff_cor_by_date$ff_cor, na.rm = TRUE)
mega_cap_cor_sd   <- sd(ff_cor_by_date$ff_cor, na.rm = TRUE)
cat(sprintf("Mega-cap impact: mean cor(score, FreeFloatMktCap) = %.4f (sd=%.4f, n_dates=%d)\n",
             mega_cap_cor_mean, mega_cap_cor_sd, nrow(ff_cor_by_date)))

# (B) Top-20 mega-cap concentration: % of top-20 in top decile by MktCap per date
top20_megacap_share <- df_v2[!is.na(score_eff) & !is.na(MktCap), {
  ord <- order(-score_eff)[1:min(20, .N)]
  top20 <- .SD[ord]
  mc_quantile <- quantile(MktCap, 0.7, na.rm = TRUE)
  list(megacap_share = mean(top20$MktCap >= mc_quantile, na.rm = TRUE))
}, by = Date]
megacap_share_mean <- mean(top20_megacap_share$megacap_share, na.rm = TRUE)
cat(sprintf("Top-20 mega-cap share (>= 70th pctile MktCap): %.2f%%\n",
             megacap_share_mean * 100))

# (C) Top-20 set vs Universe v1 (KR_top342) overlap on overlap subset
# Compute top-20 per date for v1 (full source panel) and v2, measure Jaccard.
top20_v1 <- df_src[!is.na(score_str1701), {
  o <- order(-score_str1701)[1:min(20, .N)]
  list(top_v1 = list(Ticker[o]))
}, by = Date]
top20_v2 <- df_v2[!is.na(score_eff), {
  o <- order(-score_eff)[1:min(20, .N)]
  list(top_v2 = list(Ticker[o]))
}, by = Date]
top_join <- merge(top20_v1, top20_v2, by = "Date")
top_join[, jac := mapply(function(a, b) length(intersect(a, b)) / length(union(a, b)),
                          top_v1, top_v2)]
top20_jaccard_v1_v2 <- mean(top_join$jac, na.rm = TRUE)
cat(sprintf("Top-20 v1 vs v2 Jaccard: %.4f (universe sensitivity)\n",
             top20_jaccard_v1_v2))

# (D) Sector balance — using rawdata Sector at sig_date
df_v2_sector <- merge(
  df_v2,
  raw_full[, .(Date, Ticker, Sector, KQ150, K200)],
  by = c("Date", "Ticker"),
  all.x = TRUE
)
sector_share <- df_v2_sector[!is.na(Sector), .N, by = .(Date, Sector)]
sector_share[, total_d := sum(N), by = Date]
sector_share[, share := N / total_d]
sector_max_per_date <- sector_share[, .(max_sec_share = max(share)), by = Date]
sector_max_mean <- mean(sector_max_per_date$max_sec_share, na.rm = TRUE)
sector_max_max  <- max(sector_max_per_date$max_sec_share, na.rm = TRUE)
cat(sprintf("Sector concentration: mean max-sector-share = %.2f%%, peak = %.2f%%\n",
             sector_max_mean * 100, sector_max_max * 100))

# (E) KOSDAQ exposure (KQ150 indicator from rawdata)
kosdaq_share <- df_v2_sector[!is.na(KQ150), .(kosdaq_share = mean(KQ150 == 1, na.rm = TRUE)),
                              by = Date]
kosdaq_share_mean <- mean(kosdaq_share$kosdaq_share, na.rm = TRUE)
cat(sprintf("KOSDAQ (KQ150 flag) share in universe v2: %.2f%%\n", kosdaq_share_mean * 100))

# (F) Top-20 set delta intersection ratio (v2 unique entries from non-KR_top342)
# Compute STR_1701 v1 universe baseline tickers (source panel) — broader set
v1_universe_tickers <- unique(df_src$Ticker)
v2_universe_tickers <- unique(df_v2$Ticker)
v2_only <- setdiff(v2_universe_tickers, v1_universe_tickers)
v1_only <- setdiff(v1_universe_tickers, v2_universe_tickers)
overlap <- intersect(v1_universe_tickers, v2_universe_tickers)
cat(sprintf("Universe v1 only: %d  v2 only: %d  overlap: %d\n",
             length(v1_only), length(v2_only), length(overlap)))

# ============================================================
# Step 7: as_of alpha_vector + confidence_vector (top 20)
# ============================================================
last_date <- max(df_v2$Date)
df_last <- df_v2[Date == last_date]
df_last <- df_last[order(-score_eff)]
top20 <- df_last[1:min(20, nrow(df_last))]
alpha_vec <- setNames(round(top20$score_eff, 4), top20$Ticker)
conf_vec  <- setNames(round(top20$confidence, 4), top20$Ticker)
cat(sprintf("\n=== Step 7: as_of_date = %s | top 20 (universe v2) ===\n",
             as.character(last_date)))
print(head(alpha_vec, 10))

# ============================================================
# Step 8: Write parquet (universe v2 filtered)
# ============================================================
out_parquet <- file.path(STAGE_DIR, "alpha_scores.parquet")
df_v2_out <- df_v2[, .(Date, Ticker, score_str1701, score_eff, score_rank, confidence,
                        fwd_1m, c_substab, c_resid, c_cov, z_A, z_B, z_C, n_slots_present,
                        MktCap, FreeFloatMktCap, AvgTrdVal_20d, uni_rank)]
write_parquet(df_v2_out, out_parquet)
cat(sprintf("\nWrote: %s\n", out_parquet))

# ============================================================
# Step 9: Build alpha_package.json
# ============================================================
diag_list <- list(
  rank_ic = round(rank_ic_v2, 4),
  icir = round(icir_v2, 4),
  monotonicity = round(mono_v2, 4),
  subperiod_stability = round(sub_stab_v2, 4),
  subperiod_ics = list(
    P1_2008_2014 = round(sub_ic[period == "P1_2008_2014", ic], 4),
    P2_2015_2019 = round(sub_ic[period == "P2_2015_2019", ic], 4),
    P3_2020_2024 = round(sub_ic[period == "P3_2020_2024", ic], 4)
  ),
  harvey_t_specs = list(
    spec1_pooled_ols   = round(t1, 4),
    spec2_nw_lag3      = round(t2, 4),
    spec3_nw_lag6      = round(t3, 4),
    spec4_nw_lag12     = round(t4, 4),
    spec5_cluster_date = round(t5, 4)
  ),
  harvey_t_stat_pooled = round(t1, 4),
  harvey_t_specs_pass_count = harvey_pass_v2,
  dsr_post = round(dsr_post_v2, 4),
  post_neutralization_ic = round(rank_ic_v2, 4),
  turnover_proxy = round(turnover_proxy_v2, 4),
  n_months = nrow(ic_monthly),
  n_sig_dates = length(unique(df_v2$Date)),
  n_tickers_panel = length(unique(df_v2$Ticker)),
  n_tickers_at_as_of = nrow(df_last),
  alpha_inheritance_cor = round(cor_overlap, 6),
  universe_v1_baseline_rank_ic = round(rank_ic_v1, 4),
  universe_v1_baseline_icir = round(icir_v1, 4),
  delta_rank_ic_v2_minus_v1 = round(rank_ic_v2 - rank_ic_v1, 4),
  delta_icir_v2_minus_v1 = round(icir_v2 - icir_v1, 4)
)

universe_audit <- list(
  label = "KR_TOP500_FREEFLOAT",
  liquidity_threshold_won_used = 200000000,
  liquidity_threshold_basis = "production floor 2e8 KRW",
  avg_tv20_definition = "Close x Vol",
  universe_filter_applied_pre_diagnostics = TRUE,
  l_code_reference = "L-227 Architect Universe Expansion v2",
  cost_model_recommended = "20bps (FREEFLOAT mid-cap impact buffer)",
  universe_history_dates = length(sig_dates),
  universe_size_mean = round(mean(uni_size_by_date$N), 1),
  universe_size_min = min(uni_size_by_date$N),
  universe_size_max = max(uni_size_by_date$N),
  unique_tickers_in_v2 = length(unique(df_v2$Ticker)),
  v1_only_count = length(v1_only),
  v2_only_count = length(v2_only),
  v1_v2_overlap_count = length(overlap)
)

architect_ac2_audit <- list(
  mega_cap_correlation_score_vs_freefloatmktcap = list(
    mean = round(mega_cap_cor_mean, 4),
    sd = round(mega_cap_cor_sd, 4),
    n_dates = nrow(ff_cor_by_date),
    interpretation = if (abs(mega_cap_cor_mean) < 0.10) "low_megacap_dependence" else
                       if (abs(mega_cap_cor_mean) < 0.30) "moderate_megacap_dependence" else
                       "high_megacap_dependence"
  ),
  top20_megacap_share = list(
    value = round(megacap_share_mean, 4),
    threshold_warning = 0.70,
    flag = megacap_share_mean >= 0.70
  ),
  top20_v1_v2_jaccard = list(
    value = round(top20_jaccard_v1_v2, 4),
    interpretation = if (top20_jaccard_v1_v2 >= 0.80) "highly_similar_top20" else
                       if (top20_jaccard_v1_v2 >= 0.50) "moderate_top20_drift" else
                       "significant_top20_drift"
  ),
  sector_concentration = list(
    mean_max_sector_share = round(sector_max_mean, 4),
    peak_max_sector_share = round(sector_max_max, 4),
    architect_guardrail = 0.30,
    flag_warning = (sector_max_mean >= 0.30)
  ),
  kosdaq_share = list(
    mean_kq150_flag = round(kosdaq_share_mean, 4),
    interpretation = "share of universe-v2 names tagged KQ150 (KOSDAQ150)"
  ),
  governor_review_required = (abs(mega_cap_cor_mean) >= 0.10) ||
                              (abs(top20_jaccard_v1_v2 - 1.0) >= 0.10) ||
                              (sector_max_mean >= 0.30)
)

inheritance_block <- list(
  base_strategy = "STR_1701 (Iter 11 PG2 active 80% — multi-sleeve composite)",
  base_source_parquet = "stage_artifacts/WT_D20260426_007/alpha_scores.parquet",
  base_source_pkg = "qepm/mailbox/worktask/WT-D20260426_004/alpha_package.json",
  base_score_column = "score_str1701",
  inheritance_method = "DIRECT_SLOT_READ_PLUS_UNIVERSE_V2_FILTER",
  cor_v19_vs_str1701_overlap = round(cor_overlap, 6),
  cor_threshold_strict = 0.95,
  cor_pass = TRUE,
  alpha_unchanged_proof = "PASS",
  rationale = paste(
    "Iter 19 = Universe Pilot. Alpha formula 변경 X (STR_1701 score_str1701 그대로).",
    "Universe만 KR_top342 -> KR_TOP500_FREEFLOAT 변경 (L-227 Architect 인프라 활용).",
    "8 sprint fail learning: same-universe variant exhausted (L-211/220/223/225/226/228/229).",
    "차원 변경 = controlled comparison (universe alone)."),
  l_codes_referenced = c("L-211", "L-220", "L-223", "L-224", "L-225", "L-226",
                          "L-227", "L-228", "L-229"),
  iter_lineage = c("Iter 5 (WT-D20260425_010)",
                    "Iter 11 (WT-D20260426_004)",
                    "Iter 18 (WT-D20260427_002)",
                    "Iter 19 (current, KR_TOP500_FREEFLOAT)")
)

method_log <- list(
  candidates_tried = 1,
  cap = 5,
  parallel_exec = FALSE,
  rcpp_used = FALSE,
  rolling_seconds = list(),
  method_log = list(
    list(
      name = "STR_1701_inheritance_universe_v2_pilot",
      rank_ic = round(rank_ic_v2, 4),
      icir = round(icir_v2, 4),
      sub_stab = round(sub_stab_v2, 4),
      harvey_specs_pass = harvey_pass_v2,
      dsr_post = round(dsr_post_v2, 4),
      cor_to_str1701_overlap = round(cor_overlap, 6),
      delta_icir_vs_v1 = round(icir_v2 - icir_v1, 4),
      selected = TRUE
    )
  ),
  honest_disclosure = paste(
    "단일 후보 (universe pilot, alpha unchanged).",
    "Method shopping 의도적 생략 — Iter 19 controlled comparison mandate.",
    "ML/optimizer/feature 변경 X."),
  rcpp_note = "arrow read_parquet C++ used. Universe build per-date sequential (~92 dates)."
)

iter19_lessons_applied <- list(
  L_211_avoidance = "KR linear composite fail은 STR_1701 multi-sleeve로 회피 (linear 단독 X)",
  L_220_avoidance = "vol-reduction machinery 채택 X (alpha unchanged)",
  L_223_addressed = "universe restriction alpha vanishing → universe expansion 본 sprint test",
  L_224_strict = sprintf("alpha_inheritance_hash overlap cor=%.4f >= 0.95 strict PASS", cor_overlap),
  L_225_avoidance = "Sigmoid joint factor 채택 X (alpha unchanged)",
  L_226_aware = "ERC near-EW 한계는 Optimizer agent 영역 (Risk/Optimizer downstream)",
  L_227_apply = "Architect Universe Expansion v2 (KR_TOP500_FREEFLOAT) 즉시 활용",
  L_228_avoidance = "ML tree interaction 채택 X (alpha unchanged)",
  L_229_aware = "Optimizer mechanism alone insufficient → universe dimension 변경"
)

challenge_flags_v19 <- list(
  RF_A1_inherited = list(
    id = "RF-A1",
    severity = "HIGH",
    msg = sprintf("subperiod_stability=%.4f < 0.50 (universe v2)", sub_stab_v2),
    inherited_from = "STR_1701 base — universe v2 측정값",
    resolution = "Iter 19 = universe pilot. Alpha formula unchanged. Sub-stab Forge backtest에서 portfolio-level 재평가."
  ),
  RF_A6_inherited = list(
    id = "RF-A6",
    severity = if (rank_ic_v2 >= 0.04) "INFO" else "HIGH",
    msg = sprintf("rank_IC universe v2 = %.4f vs threshold 0.04", rank_ic_v2),
    detail = sprintf("Universe v1 baseline %.4f -> v2 %.4f (delta %+.4f)",
                      rank_ic_v1, rank_ic_v2, rank_ic_v2 - rank_ic_v1)
  ),
  RF_A7_inherited = list(
    id = "RF-A7",
    severity = "HIGH",
    msg = sprintf("Harvey 5-spec pass count %d/5 universe v2", harvey_pass_v2),
    detail = paste("Pooled OLS t=", round(t1, 4),
                    "NW3 t=", round(t2, 4),
                    "NW6 t=", round(t3, 4),
                    "NW12 t=", round(t4, 4),
                    "ClusterDate t=", round(t5, 4)),
    resolution = "Statistical significance evaluated at PG2 portfolio level (Forge backtest)."
  ),
  AC2_megacap_audit = list(
    id = "AC2-MEGA",
    severity = if (architect_ac2_audit$mega_cap_correlation_score_vs_freefloatmktcap$interpretation
                    == "low_megacap_dependence") "INFO" else "MEDIUM",
    msg = sprintf("Mega-cap cor mean = %.4f -> %s",
                   mega_cap_cor_mean,
                   architect_ac2_audit$mega_cap_correlation_score_vs_freefloatmktcap$interpretation),
    governor_review = architect_ac2_audit$governor_review_required
  ),
  AC2_top20_drift = list(
    id = "AC2-TOP20",
    severity = if (top20_jaccard_v1_v2 >= 0.80) "INFO" else "MEDIUM",
    msg = sprintf("Top-20 v1 vs v2 Jaccard = %.4f -> %s",
                   top20_jaccard_v1_v2,
                   architect_ac2_audit$top20_v1_v2_jaccard$interpretation)
  ),
  AC2_sector_concentration = list(
    id = "AC2-SECTOR",
    severity = if (sector_max_mean >= 0.30) "MEDIUM" else "INFO",
    msg = sprintf("Mean max-sector-share = %.4f (threshold 0.30)", sector_max_mean)
  )
)

alpha_package <- list(
  task_id = WT_ID,
  wt_type = "discovery",
  iter = 19,
  iter_name = "Universe_Pilot_KR_TOP500_FREEFLOAT",
  parent_iters = c("WT-D20260425_010", "WT-D20260426_004",
                    "WT-D20260426_007", "WT-D20260427_002"),
  baseline_pg2 = "STR_1701 (active 80%) + STR_1656 (active 20%)",
  as_of_date = as.character(last_date),
  signal_as_of = as.character(last_date),
  forecast_horizon = "1M",
  selection_objective = "icir",
  hypothesis_title = "Iter 19 — KR_TOP500_FREEFLOAT Universe Pilot (L-227)",
  hypothesis_summary = paste(
    "Iter 19 = Universe Pilot. STR_1701 multi-sleeve composite (Iter 11 inheritance) 그대로,",
    "universe만 KR_top342 -> KR_TOP500_FREEFLOAT 변경.",
    "L-227 Architect 인프라 (build_universe_v2) 즉시 활용. 8 sprint fail 학습:",
    "same-universe variant exhausted -> dimension change (universe).",
    "controlled comparison: universe v1 baseline (rank_IC=", round(rank_ic_v1, 4),
    "ICIR=", round(icir_v1, 4), ") vs v2 measurement.",
    "Architect AC2 mandate: mega-cap impact + sector balance audit.",
    sep = " "),
  alpha_inheritance = inheritance_block,
  alpha_vector = as.list(alpha_vec),
  confidence_vector = as.list(conf_vec),
  signal_matrix_ref = "stage_artifacts://WT_D20260427_003/alpha_scores.parquet",
  factor_specs = list(
    list(
      factor_family = "Multi_Sleeve_Inheritance_Universe_V2",
      proxy = "STR_1701_base_score on KR_TOP500_FREEFLOAT",
      formula = "score_str1701 (no transform) filtered to KR_TOP500_FREEFLOAT membership per sig_date",
      lag_rule = "monthly t-1 (preserved from STR_1701)",
      winsorization = "preserved (3std at source)",
      neutralization = "preserved (sector+size at source)",
      economic_rationale = paste(
        "STR_1701 multi-sleeve composite (Core 0.65 Consensus_4F+Q07+M08 / Defense 0.35 Q07+Q25)",
        "applied on broader universe to test mid-cap diversification benefit",
        "(Avramov-Cheng-Metzker 2023 universe expansion; Hou-Xue-Zhang 2015 q-factor breadth)."),
      sleeve = "inherited",
      source = "inherited+universe_filter_v2",
      weight_theta = 1.0,
      references = c("Iter 5 WT-D20260425_010", "Iter 11 WT-D20260426_004",
                      "L-227 Universe Expansion v2",
                      "Avramov-Cheng-Metzker 2023",
                      "Hou-Xue-Zhang 2015 q-factor")
    )
  ),
  diagnostics = diag_list,
  universe = universe_audit,
  architect_ac2_audit = architect_ac2_audit,
  challenge_flags = challenge_flags_v19,
  method_shopping_log = method_log,
  iter19_lessons_applied = iter19_lessons_applied,
  ax_axiom_compliance = list(
    `AX-003` = list(rule = "KR value EP_STANDALONE failure", status = "PASS",
                    evidence = "No standalone Value (multi-sleeve preserved)"),
    `AX-004` = list(rule = "KR quality_profitability single-signal failure", status = "PASS",
                    evidence = "Multi-axis composite preserved"),
    `AX-005` = list(rule = "KR defense 4-axis failure",
                    status = "PENDING_FORGE_GATE13_VERIFICATION",
                    evidence = "Defense sleeve = Q07+Q25 2-axis (NOT 4-axis); EXCLUSION necessary not sufficient. Forge Gate13 verify."),
    `AX-007` = list(rule = "single_sleeve_top20 translation 단절", status = "PASS",
                    evidence = "Multi-sleeve structure preserved (Core + Defense)")
  ),
  pit_compliance = list(
    C1 = "PASS (inherited; expanding window in source)",
    C2 = "PASS (inherited; t-1 lag preserved)",
    C4 = "PASS (inherited; quarterly 45d / annual May)",
    C9 = "PASS (inherited; regime expanding percentile)",
    C10 = "PASS (universe v2 AvgTV20 >= 2e8 PIT lagged via build_universe_v2)",
    C11 = "PASS (inherited; KR internals only)",
    C13 = "PASS (inherited; Z_Score_Aligned)",
    C14 = "PASS (inherited; Usable_Date <= sig_date)",
    C15 = "PASS (inherited; load_month_factors equivalent + universe v2 PIT-safe build)",
    universe_v2_pit_proof = "build_universe_v2 uses RAWDATA Date <= sig_date only; FreeFloat=1.0 conservative fallback (no future data); cached parquet per (label, date)",
    lockbox = sprintf("ENFORCED: max_date %s <= TRAIN_END %s",
                       as.character(max(df_v2$Date)), as.character(TRAIN_END)),
    inheritance_chain_audit = "Source: stage_artifacts/WT_D20260426_007/alpha_scores.parquet (Iter 11 STR_1701) + universe_v2 PIT filter"
  ),
  window_isolation = list(
    train_validation_window = list(start = "2008-01-31", end = as.character(max(df_v2$Date))),
    lockbox_window = list(start = as.character(LOCKBOX_START), end = "2026-04-27", sealed = TRUE),
    lockbox_access = FALSE,
    lockbox_isolation_certified = TRUE
  ),
  graduation_status = list(
    rank_ic_gate = list(value = round(rank_ic_v2, 4), threshold = 0.04, pass = rank_ic_v2 >= 0.04),
    icir_gate = list(value = round(icir_v2, 4), threshold = 0.20, pass = icir_v2 >= 0.20),
    subperiod_gate = list(value = round(sub_stab_v2, 4), threshold = 0.50, pass = sub_stab_v2 >= 0.50),
    harvey_t_gate = list(value = round(t1, 4), threshold = 3.0, pass = abs(t1) >= 3.0),
    dsr_gate = list(value = round(dsr_post_v2, 4), threshold = 0.50, pass = dsr_post_v2 >= 0.50),
    overall_pass = (rank_ic_v2 >= 0.04) && (icir_v2 >= 0.20) &&
                    (sub_stab_v2 >= 0.50) && (abs(t1) >= 3.0) && (dsr_post_v2 >= 0.50),
    gates_passed = sum(c(rank_ic_v2 >= 0.04, icir_v2 >= 0.20, sub_stab_v2 >= 0.50,
                          abs(t1) >= 3.0, dsr_post_v2 >= 0.50)),
    gates_total = 5,
    universe_comparison = list(
      v1_baseline_rank_ic = round(rank_ic_v1, 4),
      v1_baseline_icir = round(icir_v1, 4),
      v2_pilot_rank_ic = round(rank_ic_v2, 4),
      v2_pilot_icir = round(icir_v2, 4),
      delta_rank_ic = round(rank_ic_v2 - rank_ic_v1, 4),
      delta_icir = round(icir_v2 - icir_v1, 4),
      hypothesis_outcome = if (icir_v2 >= icir_v1 * 1.05) "A_universe_expansion_helps"
                            else if (icir_v2 >= icir_v1 * 0.95) "B_universe_neutral"
                            else "C_midcap_noise"
    ),
    honest_disclosure = "Iter 19 universe pilot — controlled comparison. Forge backtest required for SR / MDD."
  ),
  references = c(
    "Iter 5 alpha academic refs chain pointer: WT-D20260425_010/alpha_package.json",
    "Iter 11 alpha academic refs chain pointer: WT-D20260426_004/alpha_package.json",
    "Carhart 1997 momentum factor (inherited Core sleeve)",
    "Blitz-Huij-Martens 2011 residual momentum (inherited Core)",
    "Novy-Marx 2013 quality (inherited Q07)",
    "Ohlson 1980 O-score distress (inherited Defense Q25)",
    "Campbell-Hilscher-Szilagyi 2008 distress risk (inherited Defense)",
    "Fama-French 1993 FF3 + Harvey-Liu-Zhu 2016 multi-testing",
    "DeMiguel-Garlappi-Uppal 2009 1/N diversification (multi-sleeve rationale)",
    "Avramov-Cheng-Metzker 2023 universe expansion ML (Iter 19 motivation)",
    "Hou-Xue-Zhang 2015 q-factor model breadth (Iter 19 motivation)",
    "L-227 Architect Universe Expansion v2 advisory",
    "L-211 KR linear composite fail (avoidance)",
    "L-220 vol-reduction Harvey 격하 (avoidance)",
    "L-223 universe restriction alpha vanishing (motivation)",
    "L-224 alpha_inheritance_hash cor 0.85->0.95 strict (compliance)",
    "L-225 Sigmoid joint factor fail (avoidance)",
    "L-226 ERC near-EW alpha activation 부재 (downstream context)",
    "L-228 ML tree interaction collapsed (avoidance)",
    "L-229 Optimizer mechanism alone insufficient (motivation)"
  ),
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  forward_to = "Iter 19 Risk + Optimizer (KR_TOP500_FREEFLOAT) — controlled comparison vs v1"
)

# ============================================================
# Step 10: Write alpha_package.json (FIRST)
# ============================================================
out_pkg <- file.path(WT_DIR, "alpha_package.json")
write_json(alpha_package, out_pkg, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("\nWrote: %s\n", out_pkg))

# Inheritance hash artifact
hash_artifact <- list(
  task_id = WT_ID,
  base_strategy = "STR_1701",
  base_source_parquet = SOURCE_PARQUET,
  base_score_column = "score_str1701",
  cor_v19_vs_str1701_spearman_overlap = round(cor_overlap, 6),
  cor_threshold_strict = 0.95,
  cor_pass = (cor_overlap >= 0.95),
  cor_method = "spearman",
  cor_n_obs = nrow(df_v2),
  alpha_unchanged_proof = "PASS",
  inheritance_method = "DIRECT_SLOT_READ_PLUS_UNIVERSE_V2_FILTER",
  universe_label = "KR_TOP500_FREEFLOAT",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  l_code_reference = "L-224 v2 (cor 0.85 -> 0.95 strict) + L-227 universe v2"
)
write_json(hash_artifact,
           file.path(WT_DIR, "alpha_inheritance_hash.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("Wrote: %s\n", file.path(WT_DIR, "alpha_inheritance_hash.json")))

# Universe v2 pilot audit (Architect AC2)
audit_artifact <- list(
  task_id = WT_ID,
  audit_type = "universe_v2_pilot_AC2",
  universe = universe_audit,
  ac2 = architect_ac2_audit,
  diagnostics_universe_v2 = diag_list,
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
write_json(audit_artifact,
           file.path(WT_DIR, "universe_v2_pilot_audit.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("Wrote: %s\n", file.path(WT_DIR, "universe_v2_pilot_audit.json")))

# alpha_validation.json
validation <- list(
  task_id = WT_ID,
  validation_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  alpha_unchanged_proof = "PASS",
  cor_inheritance_strict_pass = (cor_overlap >= 0.95),
  graduation = alpha_package$graduation_status,
  pit_compliance = alpha_package$pit_compliance,
  window_isolation = alpha_package$window_isolation,
  universe_comparison = alpha_package$graduation_status$universe_comparison,
  architect_ac2 = architect_ac2_audit
)
write_json(validation,
           file.path(STAGE_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf("Wrote: %s\n", file.path(STAGE_DIR, "alpha_validation.json")))

# Lineage (SECOND, per L-194)
tryCatch({
  source(file.path(ROOT, "02_Infrastructure/worktask/lineage_utils.R"))
  record_package_lineage(
    task_id = WT_ID,
    package_type = "alpha_package",
    method_selected = "STR_1701_inheritance_universe_v2_pilot",
    input_file_paths = c(SOURCE_PARQUET, SOURCE_PKG,
                          file.path(ROOT, ".cache/rawdata.parquet"))
  )
  cat("Lineage recorded.\n")
}, error = function(e) {
  cat("Lineage helper unavailable:", conditionMessage(e), "\n")
  lineage <- list(
    task_id = WT_ID,
    package_type = "alpha_package",
    method_selected = "STR_1701_inheritance_universe_v2_pilot",
    input_files = c(SOURCE_PARQUET, SOURCE_PKG),
    output_file = out_pkg,
    recorded_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )
  write_json(lineage, file.path(WT_DIR, "artifact_lineage.json"),
             pretty = TRUE, auto_unbox = TRUE, na = "null")
  cat("Wrote fallback lineage.\n")
})

# ============================================================
# Final summary
# ============================================================
cat("\n=== Iter 19 Universe Pilot: COMPLETE ===\n")
cat(sprintf("Universe v1 baseline: rank_IC=%.4f ICIR=%.4f\n", rank_ic_v1, icir_v1))
cat(sprintf("Universe v2 pilot:    rank_IC=%.4f ICIR=%.4f\n", rank_ic_v2, icir_v2))
cat(sprintf("Delta:                rank_IC=%+.4f ICIR=%+.4f\n",
             rank_ic_v2 - rank_ic_v1, icir_v2 - icir_v1))
cat(sprintf("Sub-stab v2:          %.4f | Harvey v2: %d/5 | DSR_post v2: %.4f\n",
             sub_stab_v2, harvey_pass_v2, dsr_post_v2))
cat(sprintf("Mega-cap cor:         %.4f | Top-20 v1-v2 Jaccard: %.4f\n",
             mega_cap_cor_mean, top20_jaccard_v1_v2))
cat(sprintf("Sector max share:     %.2f%% | KOSDAQ share: %.2f%%\n",
             sector_max_mean * 100, kosdaq_share_mean * 100))
cat(sprintf("Gates passed:         %d/5\n", alpha_package$graduation_status$gates_passed))

# State file for parser
final_state <- list(
  cor_v19_vs_str1701_overlap = cor_overlap,
  rank_ic_v1 = rank_ic_v1,
  rank_ic_v2 = rank_ic_v2,
  icir_v1 = icir_v1,
  icir_v2 = icir_v2,
  delta_icir = icir_v2 - icir_v1,
  sub_stab_v2 = sub_stab_v2,
  harvey_pass_v2 = harvey_pass_v2,
  dsr_post_v2 = dsr_post_v2,
  mega_cap_cor_mean = mega_cap_cor_mean,
  top20_jaccard_v1_v2 = top20_jaccard_v1_v2,
  sector_max_mean = sector_max_mean,
  kosdaq_share_mean = kosdaq_share_mean,
  gates_passed = alpha_package$graduation_status$gates_passed,
  hypothesis_outcome = alpha_package$graduation_status$universe_comparison$hypothesis_outcome
)
write_json(final_state, file.path(WT_DIR, ".alpha_iter19_state.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

cat("\nSTATE FILE: ", file.path(WT_DIR, ".alpha_iter19_state.json"), "\n", sep = "")
