#==============================================================================
# WT-D20260511_001 PD32 v4 — PIT-STRICT Rerun (Codex 8 concerns 해소)
#
# Codex REJECT 대응:
#   C1 JSON malformed              → fixed alpha_package_pd32_draft.json line 233 (Q-Lead 사전 fix)
#   C2 Full-sample sign infer       → load_month_factors() Z_Score_Aligned only (expanding 36m PIT)
#   C3 C13/C14/C15 audit chain      → load_month_factors() 경유 (registry direction + Usable_Date)
#   C4 Universe 3,445 tickers       → build_universe_v2(KR_top342) filter per sig_date
#   C5 Lockbox split                → decision window = pre-lockbox 271 sig_dates only
#   C6 Monotonicity 미측정          → decile-level monotonicity computed
#   C7 DSR n_trials 14→17           → recount (Iter1-5+PD24+PD27 7 + PD32 v2 4 + v3 12 + v3b 3 = 26 conservative)
#   C8 AX-007 Exception 1            → 5-sleeve hybrid path explicit, Forge PD33 strict validation deferred
#
# Strict PIT methodology:
#   - Z_Score_Aligned from load_month_factors() — directionality 자동 (registry direction + IC-inferred expanding 36m fallback)
#   - 즉, manual sign flip 절대 X. 단 KR empirical NEGATIVE sign discovery 결과 그대로 적용되는지 검증
#   - 결과 IC < 0이면 → KR contrarian alpha은 expanding 36m IC-inferred directions 자체에 의해 자동 반영됨
#
# Note: 만약 Z_Score_Aligned + composite IC가 여전히 0.04+ 가까이 산출되면, sign discovery는
#   expanding 36m IC inference에서 자체 결정되어 PIT-safe. 이 경우 v3b 결과는 사후 validation에 해당.
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})

cat("============================================================\n")
cat("WT-D20260511_001 PD32 v4 — PIT-STRICT 5th source rerun\n")
cat("Start:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("============================================================\n\n")

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJ_ROOT, "qepm/mailbox/worktask/WT-D20260511_001")
STAGE_DIR <- file.path(PROJ_ROOT, "stage_artifacts/WT_D20260511_001")
CACHE_DIR <- file.path(PROJ_ROOT, ".cache")
FACTOR_DB_DIR <- file.path(CACHE_DIR, "factor_db")

PD27_ALPHA <- file.path(STAGE_DIR, "alpha_scores_pd27_burn0m.parquet")
PD32_V4_OUT <- file.path(STAGE_DIR, "alpha_scores_pd32_v4_pit_strict.parquet")
PD32_V4_LOG <- file.path(WT_DIR, "pd32_v4_log.json")

# Lockbox per alpha-research scope
SIG_DATE_CUTOFF_LOCKBOX <- as.Date("2024-01-22")

# Universe restriction
UNIVERSE_LABEL <- "KR_top342"

# Selected composite factors (KR Behavioral Flow Sentiment)
# Critical: NO manual sign flip. align_factor_direction (PIT-mode expanding 36m IC) determines sign.
COMPOSITE_FACTORS <- c("CR11_Idiosyncratic_Return",
                       "INV10_Smart_Money_Flow",
                       "INV09_Flow_Persistence")

source(file.path(PROJ_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
source(file.path(PROJ_ROOT, "02_Infrastructure/factor_db/universe_expanded_v2.R"))

# ---- Step 1: Load PD27 base + sig dates ----
cat("[STEP 1] Load PD27 base alpha + sig dates\n")
pd27 <- as.data.table(read_parquet(PD27_ALPHA))
sig_dates <- sort(unique(pd27$Date))
cat("PD27 base sig dates:", length(sig_dates), "\n")

# Pre-lockbox decision window
sig_dates_pre <- sig_dates[sig_dates <= SIG_DATE_CUTOFF_LOCKBOX]
sig_dates_lockbox <- sig_dates[sig_dates > SIG_DATE_CUTOFF_LOCKBOX & sig_dates <= as.Date("2026-01-23")]
sig_dates_post <- sig_dates[sig_dates > as.Date("2026-01-23")]
cat("pre-lockbox (decision):", length(sig_dates_pre),
    "| lockbox (audit):", length(sig_dates_lockbox),
    "| post-lockbox (audit):", length(sig_dates_post), "\n\n")

fwd_ret <- pd27[, .(sig_date = Date, Ticker, Ret_1m)]
setkey(fwd_ret, sig_date, Ticker)
pd27_key <- pd27[, .(sig_date = Date, Ticker, score_pd27 = score_eff)]
setkey(pd27_key, sig_date, Ticker)

# ---- Step 2: PIT-strict composite via load_month_factors() ----
cat("[STEP 2] PIT-strict composite via load_month_factors() + KR_top342 universe\n")

build_composite_pit <- function(sig_d) {
  # PIT-strict factor load (Z_Score_Aligned — expanding 36m IC-inferred direction, registry fallback)
  fdt <- tryCatch(load_month_factors(sig_d, coverage_min = 0.05),
                  error = function(e) NULL)
  if(is.null(fdt) || nrow(fdt) == 0) return(NULL)
  setDT(fdt)

  # Filter to composite factors
  fsub <- fdt[Factor_Name %in% COMPOSITE_FACTORS, .(Ticker, Factor_Name, Z_Score_Aligned)]
  if(nrow(fsub) == 0) return(NULL)
  fwide <- dcast(fsub, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")

  # Universe filter (KR_top342)
  uni <- tryCatch(build_universe_v2(sig_d, label = UNIVERSE_LABEL),
                  error = function(e) NULL)
  if(is.null(uni) || nrow(uni) == 0) {
    # If universe build fails for this date, retain unfiltered (rare) + flag
    universe_filter_applied <- FALSE
    fwide_uni <- fwide
  } else {
    universe_filter_applied <- TRUE
    fwide_uni <- fwide[Ticker %in% uni$Ticker]
  }
  if(nrow(fwide_uni) == 0) return(NULL)

  # Re-zscore (cross-section within universe)
  avail <- intersect(COMPOSITE_FACTORS, names(fwide_uni))
  if(length(avail) == 0) return(NULL)
  for(f in avail) {
    v <- fwide_uni[[f]]
    mu <- mean(v, na.rm=TRUE); sg <- sd(v, na.rm=TRUE)
    if(!is.na(sg) && sg > 1e-10) fwide_uni[[f]] <- (v - mu)/sg
    else fwide_uni[[f]] <- NA_real_
  }
  mat <- as.matrix(fwide_uni[, ..avail])
  comp_raw <- rowMeans(mat, na.rm=TRUE)
  comp_raw[is.nan(comp_raw)] <- NA
  mu <- mean(comp_raw, na.rm=TRUE); sg <- sd(comp_raw, na.rm=TRUE)
  comp_z <- if(!is.na(sg) && sg > 1e-10) (comp_raw - mu)/sg else NA_real_
  out <- data.table(
    sig_date = sig_d,
    Ticker = fwide_uni$Ticker,
    composite_z = comp_z,
    n_factors_used = length(avail),
    n_universe = nrow(fwide_uni),
    universe_filter_applied = universe_filter_applied
  )
  out[!is.na(composite_z)]
}

t0 <- Sys.time()
rows <- vector("list", length(sig_dates))
for(i in seq_along(sig_dates)) {
  r <- tryCatch(build_composite_pit(sig_dates[i]),
                error = function(e) {
                  cat("  sig_date", as.character(sig_dates[i]), "error:", conditionMessage(e), "\n")
                  NULL
                })
  if(!is.null(r) && nrow(r) > 0) rows[[i]] <- r
}
all_comp <- rbindlist(rows[!sapply(rows, is.null)], fill=TRUE)
cat(sprintf("Total composite rows: %d | unique sig_dates: %d | unique tickers: %d\n",
            nrow(all_comp), uniqueN(all_comp$sig_date), uniqueN(all_comp$Ticker)))
cat(sprintf("PIT-strict elapsed: %.2f min\n", as.numeric(difftime(Sys.time(), t0, units="mins"))))

# Universe filter stats
uni_stats <- all_comp[, .(n_uni_per_date = mean(n_universe)), by = sig_date]
cat(sprintf("Avg universe size per sig_date: %.0f (KR_top342 target)\n", mean(uni_stats$n_uni_per_date)))

# ---- Step 3: Diagnostics per window (pre-lockbox / lockbox / post / full) ----
nw_t <- function(x) {
  n <- length(x); if(n < 12) return(NA_real_)
  mu <- mean(x); e <- x - mu; L <- 6L
  g0 <- sum(e^2)/n; s <- g0
  for(l in seq_len(L)) {
    w <- 1 - l/(L+1)
    gl <- sum(e[(l+1):n] * e[1:(n-l)])/n
    s <- s + 2*w*gl
  }
  if(s <= 0) return(NA_real_)
  mu / sqrt(s/n)
}

compute_window_stats <- function(comp_dt, fwd_ret, window_dates, window_label) {
  sub <- comp_dt[sig_date %in% window_dates]
  if(nrow(sub) == 0) return(list(label=window_label, n_months=0))
  setkey(sub, sig_date, Ticker)
  m <- merge(sub, fwd_ret, by=c("sig_date","Ticker"))[!is.na(composite_z) & !is.na(Ret_1m)]
  if(nrow(m) == 0) return(list(label=window_label, n_months=0))
  ic_per <- m[, .(ic = if(.N >= 20) cor(composite_z, Ret_1m, method="spearman") else NA_real_),
              by=sig_date][!is.na(ic)]
  mean_ic <- mean(ic_per$ic); sd_ic <- sd(ic_per$ic)
  icir <- if(sd_ic > 1e-10) mean_ic/sd_ic else NA
  t_nw <- nw_t(ic_per$ic)
  return(list(
    label = window_label,
    n_months = nrow(ic_per),
    mean_IC = mean_ic, sd_IC = sd_ic, ICIR = icir, t_NW_lag6 = t_nw,
    pos_share = mean(ic_per$ic > 0)
  ))
}

cat("\n[STEP 3] Per-window diagnostics (PIT-strict, KR_top342 universe)\n")
ws_pre  <- compute_window_stats(all_comp, fwd_ret, sig_dates_pre, "pre_lockbox_decision_window")
ws_lb   <- compute_window_stats(all_comp, fwd_ret, sig_dates_lockbox, "lockbox_audit_only")
ws_post <- compute_window_stats(all_comp, fwd_ret, sig_dates_post, "post_lockbox_audit_only")
ws_full <- compute_window_stats(all_comp, fwd_ret, sig_dates, "full_window_forge_input")

print_ws <- function(w) {
  if(w$n_months == 0) { cat(sprintf("  %s: NO DATA\n", w$label)); return() }
  cat(sprintf("  %s: n_months=%d IC=%.4f ICIR=%.3f t_NW=%.2f pos=%.2f\n",
              w$label, w$n_months, w$mean_IC, w$ICIR, w$t_NW_lag6, w$pos_share))
}
print_ws(ws_pre); print_ws(ws_lb); print_ws(ws_post); print_ws(ws_full)

# ---- Step 4: cor vs PD27 base (pre-lockbox only for alpha decision) ----
cat("\n[STEP 4] cor vs PD27 1715 H1 base (pre-lockbox decision window)\n")
sub_pre <- all_comp[sig_date %in% sig_dates_pre]
setkey(sub_pre, sig_date, Ticker)
m_pd <- merge(sub_pre[, .(sig_date, Ticker, composite_z)], pd27_key,
              by=c("sig_date","Ticker"))[!is.na(composite_z) & !is.na(score_pd27)]
c_per <- m_pd[, .(c = if(.N >= 20) cor(composite_z, score_pd27, method="spearman") else NA_real_),
              by=sig_date][!is.na(c)]
cor_pre_mean <- mean(c_per$c); cor_pre_sd <- sd(c_per$c)
cor_pre_overall <- cor(m_pd$composite_z, m_pd$score_pd27, method="spearman")
cat(sprintf("  pre-lockbox: cor_overall=%.4f cor_per_mean=%.4f sd=%.4f | <0.30: %s\n",
            cor_pre_overall, cor_pre_mean, cor_pre_sd,
            abs(cor_pre_mean) < 0.30))

# ---- Step 5: Monotonicity (decile) ----
cat("\n[STEP 5] Monotonicity decile diagnostic (pre-lockbox)\n")
m_pre <- merge(sub_pre, fwd_ret, by=c("sig_date","Ticker"))[!is.na(composite_z) & !is.na(Ret_1m)]
m_pre[, decile := cut(rank(composite_z) / .N, breaks = seq(0, 1, 0.1), labels=1:10, include.lowest=TRUE),
      by=sig_date]
decile_ret <- m_pre[, .(mean_ret = mean(Ret_1m, na.rm=TRUE), N=.N), by=decile]
decile_ret <- decile_ret[!is.na(decile)][order(as.integer(decile))]
print(decile_ret)
# Monotonicity: # of upward steps / 9
mono_steps <- sum(diff(decile_ret$mean_ret) > 0) / 9
top_minus_bot <- decile_ret[decile == 10, mean_ret] - decile_ret[decile == 1, mean_ret]
cat(sprintf("Monotonicity steps (up): %d/9 = %.3f | top10-bot1 spread: %.4f\n",
            sum(diff(decile_ret$mean_ret) > 0), mono_steps, top_minus_bot))

# Per-date top-decile > bot-decile share
date_dec_share <- m_pre[!is.na(decile), .(top_better = mean(Ret_1m[decile == 10], na.rm=TRUE) >
                                            mean(Ret_1m[decile == 1], na.rm=TRUE)),
                        by=sig_date]
top_better_share <- mean(date_dec_share$top_better, na.rm=TRUE)
cat(sprintf("Top-decile-better-than-bot share: %.4f (of %d sig_dates)\n",
            top_better_share, nrow(date_dec_share)))

# ---- Step 6: Crisis hedge AX-001 v2 (pre-lockbox) ----
cat("\n[STEP 6] AX-001 v2 crisis hedge (pre-lockbox)\n")
crisis_windows <- list(c("2008-09-01","2009-03-31"), c("2011-08-01","2011-12-31"),
                       c("2015-06-01","2016-02-29"), c("2020-02-01","2020-04-30"),
                       c("2022-05-01","2022-10-31"))
is_crisis <- function(d) {
  out <- rep(FALSE, length(d))
  for(w in crisis_windows) out <- out | (d >= as.Date(w[1]) & d <= as.Date(w[2]))
  out
}
m_pre[, regime := ifelse(is_crisis(sig_date), "crisis", "normal")]
ic_r <- m_pre[, .(ic = if(.N >= 20) cor(composite_z, Ret_1m, method="spearman") else NA_real_),
              by=.(sig_date, regime)][!is.na(ic)]
cris_ic <- ic_r[regime=="crisis", mean(ic)]
norm_ic <- ic_r[regime=="normal", mean(ic)]
cat(sprintf("  pre-lockbox: crisis_IC=%.4f normal_IC=%.4f ratio=%.2f | AX-001 v2 pass=%s\n",
            cris_ic, norm_ic, cris_ic/norm_ic, cris_ic > 0))

# ---- Step 7: Subperiod stability (3 windows, pre-lockbox) ----
cat("\n[STEP 7] Subperiod stability (3 windows, pre-lockbox)\n")
windows <- list(P1=c("2001-07-01","2008-08-31"), P2=c("2009-04-01","2017-12-31"),
                P3=c("2018-01-01","2024-01-22"))  # truncate P3 at lockbox cutoff
sp_ic <- list()
for(wn in names(windows)) {
  w <- windows[[wn]]
  sub <- m_pre[sig_date >= as.Date(w[1]) & sig_date <= as.Date(w[2])]
  if(nrow(sub) < 200) { sp_ic[[wn]] <- NA; next }
  sp_ic[[wn]] <- sub[, .(ic = if(.N >= 20) cor(composite_z, Ret_1m, method="spearman") else NA_real_),
                     by=sig_date][!is.na(ic), mean(ic)]
}
sp_vec <- unlist(sp_ic)
mmr <- if(all(!is.na(sp_vec)) && max(abs(sp_vec)) > 1e-6) min(sp_vec)/max(sp_vec) else NA
cat(sprintf("  P1=%.4f P2=%.4f P3=%.4f | min/max=%.3f | pass>=0.50=%s\n",
            sp_vec[1], sp_vec[2], sp_vec[3], mmr, !is.na(mmr) && mmr >= 0.50))

# ---- Step 8: Save PIT-strict alpha + Log JSON ----
cat("\n[STEP 8] Save PIT-strict alpha + log\n")
all_comp[, sleeve_label := "KR_Behavioral_Flow_Sentiment_PIT_strict"]
write_parquet(all_comp, PD32_V4_OUT)
cat("Parquet:", PD32_V4_OUT, "\n")

log_obj <- list(
  task_id = "WT-D20260511_001",
  pd_phase = "PD32_v4_PIT_strict",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  pit_methodology = list(
    factor_load_method = "load_month_factors() — Z_Score_Aligned only",
    sign_alignment = "align_factor_direction PIT-mode expanding 36m IC inference (Factor DB connector built-in)",
    no_manual_sign_flip = TRUE,
    universe_filter = UNIVERSE_LABEL,
    universe_method = "build_universe_v2(sig_d, label=KR_top342) per sig_date"
  ),
  composite_factors = COMPOSITE_FACTORS,
  windows = list(
    pre_lockbox_decision = list(n_dates = length(sig_dates_pre),
                                 range = c(as.character(min(sig_dates_pre)),
                                           as.character(max(sig_dates_pre)))),
    lockbox_audit = list(n_dates = length(sig_dates_lockbox)),
    post_lockbox_audit = list(n_dates = length(sig_dates_post)),
    full_forge_input = list(n_dates = length(sig_dates))
  ),
  diagnostics_per_window = list(
    pre_lockbox = ws_pre,
    lockbox = ws_lb,
    post_lockbox = ws_post,
    full = ws_full
  ),
  cor_vs_pd27_pre_lockbox = list(
    cor_overall = cor_pre_overall,
    cor_per_date_mean = cor_pre_mean,
    cor_per_date_sd = cor_pre_sd,
    n_dates = nrow(c_per),
    pass_lt_0_30 = abs(cor_pre_mean) < 0.30
  ),
  monotonicity_pre_lockbox = list(
    decile_returns = as.list(decile_ret),
    mono_steps_up = sum(diff(decile_ret$mean_ret) > 0),
    mono_ratio = mono_steps,
    top10_minus_bot1_spread = top_minus_bot,
    top_better_share_per_date = top_better_share,
    pass_mono_0_80 = mono_steps >= 0.80,
    pass_top_better_0_60 = top_better_share >= 0.60
  ),
  crisis_hedge_ax001_v2_pre_lockbox = list(
    crisis_IC = cris_ic, normal_IC = norm_ic,
    ratio = cris_ic / norm_ic, ax001_v2_pass = cris_ic > 0
  ),
  subperiod_3_window_pre_lockbox = list(
    P1 = sp_vec[1], P2 = sp_vec[2], P3 = sp_vec[3],
    min_max_ratio = mmr, pass = !is.na(mmr) && mmr >= 0.50
  ),
  output_parquet = PD32_V4_OUT,
  avg_universe_size_per_date = mean(uni_stats$n_uni_per_date)
)
write_json(log_obj, PD32_V4_LOG, pretty=TRUE, auto_unbox=TRUE)
cat("Log:", PD32_V4_LOG, "\n")

cat("\n============================================================\n")
cat("PD32 v4 PIT-strict complete.\n")
cat("End:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat("============================================================\n")
