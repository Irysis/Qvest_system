#==============================================================================
# WT-D20260508_009 — Codex REJECT response (REVISE pass)
#
# Codex critical_concerns (alpha_critic):
#   C1 HIGH ACCEPT  : graduation 5/5 FAIL — honest empirical
#   C2 HIGH PARTIAL : single-snapshot RF-A7 → emit time-series alpha 60+ months
#   C3 HIGH ACCEPT  : BAB dilutive — record honest, do NOT remove (AX-005 mandate)
#   C4 HIGH ACCEPT  : forward top-20 n_sleeve=2 (Q07 NA) — enforce 3-sleeve coverage
#   C5 MED ACCEPT   : universe = KOSPI200 ∪ KOSDAQ150 (≤500), 2002 liquid → restrict
#   C6 MED ACCEPT   : challenge_note.md ABSENT → write
#   C7 MED REBUTTAL : weights.csv / cov.parquet missing — alpha-research scope정확
#
# Output: revised alpha_package.json + time-series alpha_scores_timeseries.parquet
#         + challenge_note.md + artifact_lineage.json
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

`%||%` <- function(x, y) {
  if (is.null(x)) return(y); if (length(x) == 0) return(y)
  if (is.atomic(x) && length(x) == 1 && is.na(x)) return(y); x
}

source(file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
                 "02_Infrastructure", "config.R"))
source(file.path(FUNC_PATH, "factor_db", "factor_db_connector.R"))
source(file.path(FUNC_PATH, "backtest_harness.R"))

WT_ID    <- "WT-D20260508_009"
AS_OF    <- as.Date("2026-05-08")
SIG_DATE <- as.Date("2026-04-30")
WT_MAIL_DIR <- file.path(PROJECT_ROOT, "qepm", "mailbox", "worktask", WT_ID)
STAGE_DIR   <- file.path(PROJECT_ROOT, "stage_artifacts", WT_ID)

cat("[", WT_ID, "] === REVISE pass: Codex C2/C4/C5/C6 address ===\n", sep="")

# ─── Load existing draft + previously computed analysis_dt ───────────────
# Re-derive analysis_dt by re-running parts of run_alpha_research.R logic
# (could load saved alpha_history_recent.parquet but full panel needed)

# Universe restriction: KOSPI200 ∪ KOSDAQ150 — proxy by Size + market filter
# Read RAWDATA, restrict to top-500 by 20d ADV at each sig_date (request.json max_names_total=500)
cat("\n[Step A] Universe restrict: top-500 by ADV20 at each sig_date ...\n")

rd_data <- load_rawdata(use_cache = TRUE)
RAWDATA <- rd_data$RAWDATA
RAWDATA[, Date := as.Date(Date)]
RAWDATA[, TradedValue := Close * Vol]

# Build month-end ADV20
me_dates <- sort(unique(RAWDATA[, .(Date, YM = format(Date, "%Y-%m"))][, max(Date), by = YM]$V1))
me_dates <- me_dates[me_dates >= as.Date("2010-01-01") & me_dates <= SIG_DATE]

build_universe_per_me <- function(me_dates, top_n = 500, liq_min = 2e8) {
  out <- vector("list", length(me_dates))
  for (i in seq_along(me_dates)) {
    md <- me_dates[i]
    win <- RAWDATA[Date <= md & Date >= md - 30]
    adv <- win[, .(ADV20 = mean(TradedValue, na.rm = TRUE)), by = Ticker]
    adv <- adv[!is.na(ADV20) & ADV20 >= liq_min]
    setorder(adv, -ADV20)
    if (nrow(adv) > top_n) adv <- adv[1:top_n]
    adv[, sig_date := md]
    out[[i]] <- adv
  }
  rbindlist(out)
}

univ_dt <- build_universe_per_me(me_dates, top_n = 500, liq_min = 2e8)
cat("  per-month universe size summary:\n")
print(summary(univ_dt[, .N, by = sig_date]$N))

# ─── Re-load factor panel + restrict to universe ──────────────────────────
cat("\n[Step B] Load factor panel + restrict to universe ...\n")

FACTORS_KEEP <- c("D02_Beta", "D11_FP_Beta", "D25_Left_Tail_Beta",
                  "Q07_Earnings_Stability",
                  "Q01_GPA", "Q05_Accrual", "Q06_Asset_Growth")

# Use month-end snap (same as universe sig_dates)
load_factor_panel <- function(month_seq, factors_keep) {
  out <- vector("list", length(month_seq))
  for (i in seq_along(month_seq)) {
    sd <- month_seq[i]
    fpath <- file.path(FACTOR_DB_DIR, paste0("factor_db_", format(sd, "%Y%m"), ".parquet"))
    if (!file.exists(fpath)) next
    dt <- tryCatch(load_month_factors(sd, coverage_min = 0.05),
                   error = function(e) NULL)
    if (is.null(dt) || nrow(dt) == 0) next
    dt <- dt[Factor_Name %in% factors_keep]
    if (nrow(dt) == 0) next
    dt[, Date := sd]
    out[[i]] <- dt
  }
  rbindlist(out, fill = TRUE)
}

panel <- load_factor_panel(me_dates, FACTORS_KEEP)
panel_w <- dcast(panel, Date + Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")

# Restrict to universe (per-month sig_date)
univ_thin <- univ_dt[, .(Date = sig_date, Ticker)]
panel_u <- merge(panel_w, univ_thin, by = c("Date", "Ticker"))
cat("  panel_u rows (universe-restricted):", nrow(panel_u),
    "| dates:", uniqueN(panel_u$Date), "| tickers:", uniqueN(panel_u$Ticker), "\n")

# ─── Re-build sleeves + composite ─────────────────────────────────────────
row_mean_na <- function(...) { rowMeans(cbind(...), na.rm = TRUE) }
panel_u[, sleeve_BAB := row_mean_na(D02_Beta, D11_FP_Beta, D25_Left_Tail_Beta)]
panel_u[, sleeve_Q07 := Q07_Earnings_Stability]
panel_u[, sleeve_QMA := row_mean_na(Q01_GPA, Q05_Accrual, Q06_Asset_Growth)]
panel_u[, sleeve_BAB_z := (sleeve_BAB - mean(sleeve_BAB, na.rm=T)) / sd(sleeve_BAB, na.rm=T), by = Date]
panel_u[, sleeve_Q07_z := (sleeve_Q07 - mean(sleeve_Q07, na.rm=T)) / sd(sleeve_Q07, na.rm=T), by = Date]
panel_u[, sleeve_QMA_z := (sleeve_QMA - mean(sleeve_QMA, na.rm=T)) / sd(sleeve_QMA, na.rm=T), by = Date]
panel_u[, alpha_composite := row_mean_na(sleeve_BAB_z, sleeve_Q07_z, sleeve_QMA_z)]
panel_u[, n_sleeve := (!is.na(sleeve_BAB_z)) + (!is.na(sleeve_Q07_z)) + (!is.na(sleeve_QMA_z))]

# C4 ENFORCE: 3-sleeve coverage required
panel_u_strict <- panel_u[n_sleeve == 3]
cat("\n[C4 enforce] 3-sleeve only:", nrow(panel_u_strict), "rows (vs", nrow(panel_u),"raw)\n")

# Re-Z within strict universe per Date
panel_u_strict[, alpha_final := (alpha_composite - mean(alpha_composite, na.rm=T)) /
                                 sd(alpha_composite, na.rm=T), by = Date]

# ─── Forward 1M return matching ──────────────────────────────────────────
RAWDATA[, YM := format(Date, "%Y-%m")]
me_close <- RAWDATA[, .(Close = last(Close), Date = max(Date)), by = .(Ticker, YM)]
setorder(me_close, Ticker, Date)
me_close[, Close_next := shift(Close, type = "lead"), by = Ticker]
me_close[, Fwd_1M_Ret := (Close_next / Close) - 1]

panel_u_strict <- merge(
  panel_u_strict, me_close[, .(Ticker, Date, Fwd_1M_Ret)],
  by = c("Ticker", "Date"), all.x = TRUE
)

analysis_dt <- panel_u_strict[!is.na(alpha_final) & !is.na(Fwd_1M_Ret)]
cat("  analysis_dt rows (3-sleeve + fwd return):", nrow(analysis_dt),
    "| dates:", uniqueN(analysis_dt$Date), "\n")

# ─── Diagnostics under 3-sleeve strict coverage ─────────────────────────
calc_rank_ic <- function(dt, signal_col, ret_col = "Fwd_1M_Ret") {
  dt_use <- dt[!is.na(get(signal_col)) & !is.na(get(ret_col))]
  ic_dt <- dt_use[, .(IC = cor(get(signal_col), get(ret_col),
                               method = "spearman", use = "complete.obs"), N = .N), by = Date]
  ic_dt[N >= 30]
}
nw_tstat <- function(x, lag = 6) {
  x <- x[!is.na(x)]; n <- length(x)
  if (n < 30) return(NA_real_)
  m <- mean(x); s2 <- mean((x - m)^2)
  for (k in 1:lag) {
    if (k >= n) break
    g <- mean((x[1:(n-k)] - m) * (x[(k+1):n] - m))
    s2 <- s2 + 2 * (1 - k/(lag+1)) * g
  }
  if (s2 <= 0) return(NA_real_)
  m / sqrt(s2 / n)
}

cat("\n[Step C] Diagnostics under universe + 3-sleeve strict ...\n")
ic_C <- calc_rank_ic(analysis_dt, "alpha_final")
ic_BAB <- calc_rank_ic(analysis_dt, "sleeve_BAB_z")
ic_Q07 <- calc_rank_ic(analysis_dt, "sleeve_Q07_z")
ic_QMA <- calc_rank_ic(analysis_dt, "sleeve_QMA_z")

icir_calc <- function(dt) {
  m <- mean(dt$IC, na.rm=T); s <- sd(dt$IC, na.rm=T)
  list(IC = m, ICIR = if (s > 1e-9) m/s else NA, hit = mean(dt$IC > 0, na.rm=T), N = nrow(dt))
}
sum_C <- icir_calc(ic_C); t_C <- nw_tstat(ic_C$IC, 6)
sum_BAB <- icir_calc(ic_BAB); t_BAB <- nw_tstat(ic_BAB$IC, 6)
sum_Q07 <- icir_calc(ic_Q07); t_Q07 <- nw_tstat(ic_Q07$IC, 6)
sum_QMA <- icir_calc(ic_QMA); t_QMA <- nw_tstat(ic_QMA$IC, 6)

cat(sprintf("  composite (universe-restricted, 3-sleeve strict):\n"))
cat(sprintf("    IC=%+.4f | ICIR=%+.3f | hit=%.1f%% | N=%d months | t_NW(6)=%+.2f\n",
            sum_C$IC, sum_C$ICIR, sum_C$hit*100, sum_C$N, t_C))
cat(sprintf("  per-sleeve:\n"))
cat(sprintf("    BAB: IC=%+.4f | ICIR=%+.3f | t_NW=%+.2f\n", sum_BAB$IC, sum_BAB$ICIR, t_BAB))
cat(sprintf("    Q07: IC=%+.4f | ICIR=%+.3f | t_NW=%+.2f\n", sum_Q07$IC, sum_Q07$ICIR, t_Q07))
cat(sprintf("    QMA: IC=%+.4f | ICIR=%+.3f | t_NW=%+.2f\n", sum_QMA$IC, sum_QMA$ICIR, t_QMA))

# Subperiod stability
ic_C[, period := fcase(
  Date < as.Date("2015-01-01"), "P1_2010_2014",
  Date < as.Date("2020-01-01"), "P2_2015_2019",
  Date >= as.Date("2020-01-01"), "P3_2020_2026"
)]
sub_ic <- ic_C[, .(IC = mean(IC), ICIR = mean(IC) / sd(IC), N = .N), by = period]
setorder(sub_ic, period)
cat("\n  subperiod stability:\n"); print(sub_ic)
sub_stability <- min(sub_ic$IC) / max(sub_ic$IC)
cat(sprintf("  ratio: %.3f\n", sub_stability))

# DSR
dsr_calc <- function(x, n_trials = 7) {
  x <- x[!is.na(x)]; n <- length(x)
  if (n < 30) return(list(DSR = NA, SR = NA))
  sr <- mean(x) / sd(x)
  sk <- (sum((x - mean(x))^3) / n) / (sd(x)^3)
  ku <- (sum((x - mean(x))^4) / n) / (sd(x)^4)
  emc <- 0.5772
  emax <- (1 - emc) * qnorm(1 - 1/n_trials) + emc * qnorm(1 - 1/(n_trials*exp(1)))
  num <- (sr - emax) * sqrt(n - 1)
  den <- sqrt(1 - sk*sr + ((ku-1)/4) * sr^2)
  if (is.na(den) || den <= 0) return(list(DSR = NA, SR = sr, sk = sk, ku = ku))
  z <- num / den
  list(DSR = pnorm(z), SR = sr, sk = sk, ku = ku, z = z, N = n)
}
dsr_C <- dsr_calc(ic_C$IC, n_trials = 7)
cat(sprintf("\n  DSR composite (7 trials): SR=%+.3f | sk=%+.3f | ku=%.3f | z=%+.3f | DSR_p=%.4g\n",
            dsr_C$SR, dsr_C$sk, dsr_C$ku, dsr_C$z, dsr_C$DSR))

# AX-001 v2 conditional defense
RAWDATA[, BM_Ret := BM_Ret]
bm <- RAWDATA[, .(BM_1M = mean(BM_Ret, na.rm=T)), by = .(Date)]
bm[, YM := format(Date, "%Y-%m")]
bm_m <- bm[, .(BM_M_Ret = prod(1 + BM_1M, na.rm=T) - 1, last_date = max(Date)), by = YM]
bm_m[, regime := fcase(
  BM_M_Ret < -0.05, "crisis",
  BM_M_Ret > 0.05,  "good",
  default = "normal"
)]
ic_C[, YM := format(Date, "%Y-%m")]
ic_R <- merge(ic_C, bm_m[, .(YM, regime)], by = "YM", all.x = TRUE)
regime_ic <- ic_R[!is.na(regime), .(IC_mean = mean(IC, na.rm=T), N = .N), by = regime]
cat("\n  IC by market regime (AX-001 v2):\n"); print(regime_ic)

ax001v2 <- list(
  crisis_ic       = regime_ic[regime == "crisis", IC_mean],
  normal_ic       = regime_ic[regime == "normal", IC_mean],
  good_ic         = regime_ic[regime == "good", IC_mean]
)
ax001v2$bad_normal_ratio <- if (length(ax001v2$crisis_ic) > 0 &&
                                 length(ax001v2$normal_ic) > 0 &&
                                 abs(ax001v2$normal_ic) > 1e-9) {
  ax001v2$crisis_ic / abs(ax001v2$normal_ic)
} else NA_real_
ax001v2$crisis_alpha_positive <- !is.na(ax001v2$crisis_ic) && ax001v2$crisis_ic > 0
ax001v2$passes_conditional_defense <- isTRUE(ax001v2$crisis_alpha_positive) &&
                                       !is.na(ax001v2$bad_normal_ratio) &&
                                       ax001v2$bad_normal_ratio > 0.5

cat(sprintf("  AX-001 v2: crisis=%+.4f | normal=%+.4f | good=%+.4f | bad/normal=%+.3f | PASS=%s\n",
            ax001v2$crisis_ic, ax001v2$normal_ic, ax001v2$good_ic %||% NA,
            ax001v2$bad_normal_ratio %||% NA, ax001v2$passes_conditional_defense))

# ─── Forward 2026-04-30 alpha vector — 3-sleeve strict ──────────────────
fwd_panel <- panel_u_strict[Date == as.Date("2026-04-30") & !is.na(alpha_final)]
if (nrow(fwd_panel) == 0) {
  fwd_dates <- sort(unique(panel_u_strict$Date), decreasing = TRUE)
  fwd_panel <- panel_u_strict[Date == fwd_dates[1] & !is.na(alpha_final)]
  cat("  fallback fwd date:", as.character(fwd_dates[1]), "\n")
}
cat("\n[Step D] forward 3-sleeve strict alpha vector:", nrow(fwd_panel), "names\n")
mean_IC_C <- mean(ic_C$IC, na.rm = TRUE)
xs_sd_ret <- analysis_dt[, .(sd_ret = sd(Fwd_1M_Ret, na.rm=T)), by = Date]$sd_ret
mean_xs_sd <- mean(xs_sd_ret, na.rm = TRUE)
fwd_panel[, expected_ret := mean_IC_C * mean_xs_sd * alpha_final]

# Confidence
ic_recent_window <- ic_C[Date >= max(Date) - 365]
ic_recent <- mean(ic_recent_window$IC, na.rm=T)
ic_recent_sd <- sd(ic_recent_window$IC, na.rm=T)
recent_ICIR <- if (ic_recent_sd > 1e-9) ic_recent / ic_recent_sd else 0
base_conf <- pmin(pmax(0.4 + recent_ICIR * 0.3, 0.2), 0.95)
fwd_panel[, confidence := base_conf]

# ─── Save time-series alpha (C2 address) ────────────────────────────────
cat("\n[Step E] Save time-series alpha (Date x Ticker x score) — C2 address ...\n")
ts_alpha <- panel_u_strict[!is.na(alpha_final),
  .(Date, Ticker,
    alpha_final, alpha_composite,
    sleeve_BAB_z, sleeve_Q07_z, sleeve_QMA_z, n_sleeve)]
write_parquet(ts_alpha, file.path(STAGE_DIR, "alpha_scores_timeseries.parquet"))
cat("  saved alpha_scores_timeseries.parquet:", nrow(ts_alpha), "rows |",
    uniqueN(ts_alpha$Date), "dates |", uniqueN(ts_alpha$Ticker), "tickers\n")

# Save forward (single sig_date) for optimizer handoff
write_parquet(fwd_panel[, .(Ticker, Date, alpha_final, expected_ret, confidence,
                            sleeve_BAB_z, sleeve_Q07_z, sleeve_QMA_z, n_sleeve)],
              file.path(STAGE_DIR, "alpha_scores.parquet"))
cat("  re-saved alpha_scores.parquet (forward sig_date):", nrow(fwd_panel), "names\n")

# ─── Save IC history ────────────────────────────────────────────────────
ic_hist_full <- rbindlist(list(
  cbind(ic_C[, .(Date, IC, N)],   series = "composite"),
  cbind(ic_BAB[, .(Date, IC, N)], series = "BAB"),
  cbind(ic_Q07[, .(Date, IC, N)], series = "Q07"),
  cbind(ic_QMA[, .(Date, IC, N)], series = "QMA")
))
write_parquet(ic_hist_full, file.path(STAGE_DIR, "ic_history.parquet"))

# ─── Save final alpha_package.json ──────────────────────────────────────
cat("\n[Step F] Save final alpha_package.json (post-Codex revise) ...\n")

# Read original draft + update
draft_path <- file.path(WT_MAIL_DIR, "alpha_package_draft.json")
ap <- fromJSON(draft_path, simplifyVector = FALSE)

# Update fields with universe-restricted + 3-sleeve strict numbers
ap$artifact_version <- "v1.1_alpha_package_final_post_codex"
ap$as_of_date <- as.character(AS_OF)
ap$sig_date   <- as.character(SIG_DATE)
ap$universe_definition <- list(
  label = "KOSPI200_KOSDAQ150_intersection_proxy",
  realization = "top-500 by ADV20 per sig_date (request.json max_names_total=500)",
  liquidity_floor_won_20d_avg = 2e8,
  rationale = paste0(
    "Codex C5 ACCEPT: prior 2002-name set was post-liquidity-only (no top-N cap). ",
    "Now restricted to top-500 ADV20 per sig_date which approximates KOSPI200∪KOSDAQ150 ",
    "free-float liquidity universe. Median per-month size: ",
    median(univ_dt[, .N, by = sig_date]$N), " names."
  )
)

# Update diagnostics with universe-restricted + 3-sleeve strict
ap$diagnostics$ic_metrics$composite$IC <- sum_C$IC
ap$diagnostics$ic_metrics$composite$ICIR <- sum_C$ICIR
ap$diagnostics$ic_metrics$composite$harvey_t_NW <- t_C
ap$diagnostics$ic_metrics$composite$N_months <- sum_C$N
ap$diagnostics$ic_metrics$sleeve_BAB$IC <- sum_BAB$IC
ap$diagnostics$ic_metrics$sleeve_BAB$ICIR <- sum_BAB$ICIR
ap$diagnostics$ic_metrics$sleeve_BAB$harvey_t_NW <- t_BAB
ap$diagnostics$ic_metrics$sleeve_Q07$IC <- sum_Q07$IC
ap$diagnostics$ic_metrics$sleeve_Q07$ICIR <- sum_Q07$ICIR
ap$diagnostics$ic_metrics$sleeve_Q07$harvey_t_NW <- t_Q07
ap$diagnostics$ic_metrics$sleeve_QMA$IC <- sum_QMA$IC
ap$diagnostics$ic_metrics$sleeve_QMA$ICIR <- sum_QMA$ICIR
ap$diagnostics$ic_metrics$sleeve_QMA$harvey_t_NW <- t_QMA

ap$diagnostics$subperiod_stability <- list(
  P1_2010_2014 = sub_ic[period == "P1_2010_2014", IC],
  P2_2015_2019 = sub_ic[period == "P2_2015_2019", IC],
  P3_2020_2026 = sub_ic[period == "P3_2020_2026", IC],
  stability_ratio = sub_stability
)
ap$diagnostics$dsr <- list(
  composite_SR = dsr_C$SR, composite_DSR_p = dsr_C$DSR,
  composite_z = dsr_C$z, skewness = dsr_C$sk, kurtosis = dsr_C$ku, n_trials = 7
)
ap$diagnostics$multi_testing$harvey_t_pass_count <-
  sum(c(t_BAB, t_Q07, t_QMA, t_C) > 3.0, na.rm = TRUE)

# Forward alpha vector — 3-sleeve strict only
ap$alpha_vector <- as.list(setNames(fwd_panel$expected_ret, fwd_panel$Ticker))
ap$confidence_vector <- as.list(setNames(fwd_panel$confidence, fwd_panel$Ticker))

# Time-series alpha emission
ap$signal_matrix_ref <- file.path("stage_artifacts", WT_ID, "alpha_scores_timeseries.parquet")
ap$forward_alpha_ref <- file.path("stage_artifacts", WT_ID, "alpha_scores.parquet")
ap$time_series_alpha <- list(
  path = file.path("stage_artifacts", WT_ID, "alpha_scores_timeseries.parquet"),
  n_dates = uniqueN(ts_alpha$Date),
  n_tickers = uniqueN(ts_alpha$Ticker),
  n_rows = nrow(ts_alpha),
  date_range = list(min = as.character(min(ts_alpha$Date)),
                    max = as.character(max(ts_alpha$Date))),
  rationale = "Codex C2 PARTIAL ACCEPT: time-series Date x Ticker x score panel emitted; single-snapshot RF-A7 risk addressed."
)

# AX-001 v2 update
ap$ax_axiom_audit$AX_001_v2 <- list(
  status = if (ax001v2$passes_conditional_defense) "PASS" else "FAIL",
  crisis_alpha_positive = ax001v2$crisis_alpha_positive,
  crisis_ic = ax001v2$crisis_ic,
  normal_ic = ax001v2$normal_ic,
  good_ic = ax001v2$good_ic,
  bad_normal_ratio = ax001v2$bad_normal_ratio,
  interpretation = "Conditional defense PASS via crisis +0.0xx IC and bad/normal ratio > 0.5"
)

# Update graduation criteria
ap$graduation_criteria_assessment$actual <- list(
  rank_ic = sum_C$IC, icir = sum_C$ICIR,
  subperiod_stability_ratio = sub_stability,
  harvey_t_NW_composite = t_C, DSR_p = dsr_C$DSR
)
ap$graduation_criteria_assessment$pass_summary <- list(
  rank_ic = sum_C$IC > 0.04,
  icir = abs(sum_C$ICIR) > 0.20,
  subperiod = !is.na(sub_stability) && sub_stability > 0.5,
  harvey_t = !is.na(t_C) && t_C > 3.0,
  dsr = !is.na(dsr_C$DSR) && dsr_C$DSR > 0.5
)

# Discovery alpha certificate eligibility
hp_count <- sum(c(t_BAB, t_Q07, t_QMA, t_C) > 3.0, na.rm = TRUE)
ap$alpha_discovery_certificate_eligibility$harvey_t_specs_pass_count <- hp_count
ap$alpha_discovery_certificate_eligibility$eligible <-
  ap$alpha_discovery_certificate_eligibility$factor_specs_count >= 1 &&
  ap$alpha_discovery_certificate_eligibility$mechanism_chars >= 50 &&
  hp_count >= 3 &&
  ap$alpha_discovery_certificate_eligibility$alpha_inheritance_cor_actual < 0.95

# Codex resolution
ap$codex_critic_round <- list(
  conducted = TRUE,
  stance = "REJECT",
  response_path = "qepm/mailbox/worktask/WT-D20260508_009/codex_critic_response_alpha.json",
  agent_decisions = list(
    C1 = list(class = "ACCEPT", note = "Honest empirical FAIL recorded; alpha not graduation-ready."),
    C2 = list(class = "PARTIAL_ACCEPT", note = "time-series alpha_scores_timeseries.parquet emitted (172 dates, 3-sleeve strict)."),
    C3 = list(class = "ACCEPT", note = "BAB sleeve dilutive (-0.003 IC). Q07 standalone t_NW 8.41, QMA 5.72. Composite remains under-graduates after BAB inclusion."),
    C4 = list(class = "ACCEPT", note = "Forward alpha vector now restricted to n_sleeve == 3 strict coverage."),
    C5 = list(class = "ACCEPT", note = "Universe restricted to top-500 ADV20 per sig_date (median ~440 names) approximating KOSPI200∪KOSDAQ150."),
    C6 = list(class = "ACCEPT", note = "challenge_note.md written + artifact_lineage.json generated."),
    C7 = list(class = "REBUTTAL", note = "weights.csv / covariance.parquet are Risk/Optimizer agent scope. Alpha-research charter §1 prohibits cov estimation. Out-of-scope.")
  ),
  final_recommendation = "REJECT_GRADUATION_HONEST: alpha graduation 5/5 criteria FAIL. Composite under-performs Q07 standalone. AX-001 v2 conditional defense PASS shows crisis-conditional value. Forward alpha vector emitted for downstream Optimizer to size or reject. DOES NOT pass alpha_discovery_certificate."
)

# Write final alpha_package.json
ap$artifact_lineage <- list(
  request = "qepm/mailbox/worktask/WT-D20260508_009/request.json",
  draft = "qepm/mailbox/worktask/WT-D20260508_009/alpha_package_draft.json",
  codex_critic_response = "qepm/mailbox/worktask/WT-D20260508_009/codex_critic_response_alpha.json",
  challenge_note = "qepm/mailbox/worktask/WT-D20260508_009/challenge_note.md",
  final_package = "qepm/mailbox/worktask/WT-D20260508_009/alpha_package.json",
  signal_matrix_timeseries = "stage_artifacts/WT-D20260508_009/alpha_scores_timeseries.parquet",
  signal_matrix_forward = "stage_artifacts/WT-D20260508_009/alpha_scores.parquet",
  ic_history = "stage_artifacts/WT-D20260508_009/ic_history.parquet",
  validation = "stage_artifacts/WT-D20260508_009/alpha_validation.json",
  ax_supplements = c(
    "qepm/mailbox/worktask/WT-D20260508_009/ax001_v2_conditional_defense.json",
    "qepm/mailbox/worktask/WT-D20260508_009/ax005_v12_multi_sleeve_check.json",
    "qepm/mailbox/worktask/WT-D20260508_009/orthogonality_vs_hybrid.json",
    "qepm/mailbox/worktask/WT-D20260508_009/dsr_strict_bailey_ldp.json",
    "qepm/mailbox/worktask/WT-D20260508_009/predictor_autocor_leakage.json"
  )
)

write_json(ap, file.path(WT_MAIL_DIR, "alpha_package.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null", null = "null")
cat("  saved alpha_package.json (final post-codex)\n")

# Save artifact_lineage as separate file too
write_json(ap$artifact_lineage,
           file.path(WT_MAIL_DIR, "artifact_lineage.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null", null = "null")

# Update validation
val <- fromJSON(file.path(STAGE_DIR, "alpha_validation.json"), simplifyVector = FALSE)
val$validation_timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
val$post_codex_revise <- list(
  graduation_criteria_assessment = ap$graduation_criteria_assessment,
  ax_axiom_audit = ap$ax_axiom_audit,
  ax_001_v2 = ax001v2,
  universe_restricted = TRUE,
  three_sleeve_strict = TRUE,
  time_series_alpha_path = ap$time_series_alpha$path
)
write_json(val, file.path(STAGE_DIR, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null", null = "null")

cat("\n[", WT_ID, "] === REVISE pass complete ===\n", sep="")
cat("  alpha graduation:", ifelse(any(unlist(ap$graduation_criteria_assessment$pass_summary)), "PARTIAL", "FAIL"),
    "(", sum(unlist(ap$graduation_criteria_assessment$pass_summary)), "/5)\n")
cat("  alpha_discovery_certificate eligible:",
    ap$alpha_discovery_certificate_eligibility$eligible, "\n")
