#==============================================================================
# WT-D20260428_003 Iter 10 B — Multi-Axis Growth Quality Composite (MAQGC)
#
# Hypothesis: KR Multi-Axis Growth Quality Composite — AFP 2019 QMJ KR adapted
#
# Family: quality_multi_axis × growth (FIAPAS family-orthogonal)
#   FIAPAS family = investor_flow / liquidity_diffusion / accrual
#   MAQGC family = quality_multi_axis / growth
#
# AX-004 EXCLUSION: multi-axis quality composite is named EXCLUSION 예외
# AFP 2019 QMJ paper validates multi-axis composite (single-axis fails in KR).
#
# Ex-ante 4 axes (signs declared BEFORE measurement):
#   A1 = Profitability (sign +1) = z(Q01_GPA + Q17_ROIC + Q11_Net_Margin) / 3
#   A2 = Growth (sign +1) = z(Q21_Revenue_Growth + Q22_Earnings_Growth + Q23_Sustainable_Growth) / 3
#   A3 = Safety (sign +1) = z(-Q15_Debt_to_Equity + Q07_Earnings_Stability) / 2
#   A4 = CashFlow Quality (sign +1) = z(Q09_CFOA + (-Q05_Accrual)) / 2  # Sloan inverse
#
# Composite: alpha = mean(A1, A2, A3, A4)  # equal-weight ex-ante (no tuning)
#
# Pre-registered:
#   - All 4 axes signs +1 declared a priori
#   - No spec tuning beyond equal-weight composite
#   - n_candidates_tried = 1 (no method-shopping)
#   - Mandate 7-spec compliant
#
# Output: alpha_vector (signal_as_of=2023-11-30) + diagnostics + 3 specs
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260428_003")
FDB_DIR <- file.path(ROOT, ".cache/factor_db")
RAW_PATH <- file.path(ROOT, ".cache/rawdata.parquet")
INV_PATH <- file.path(ROOT, ".cache/investor_wide.parquet")

# PIT-safe utility
clip_z <- function(x, lower = -3, upper = 3) {
  pmin(pmax(x, lower), upper)
}

xs_z <- function(x) {
  s <- sd(x, na.rm = TRUE)
  if (is.na(s) || s < 1e-9) return(rep(NA_real_, length(x)))
  clip_z((x - mean(x, na.rm = TRUE)) / s)
}

cat("=== WT-D20260428_003 Iter 10 B — MAQGC Evaluation ===\n")
cat(sprintf("Started: %s\n\n", Sys.time()))

# ---- Universe (KR_top342 default per request) ----
cat("[1/8] Building universe (KOSPI200 ∪ KOSDAQ150 + 5e7 KRW LIQ)...\n")
RAWDATA <- as.data.table(read_parquet(RAW_PATH))
setkey(RAWDATA, Date, Ticker)

# Months for backtest: 2008-01 ~ 2023-11 (≈191 months) — match Iter 10 A
months_seq <- seq(as.Date("2008-01-31"), as.Date("2023-11-30"), by = "month")
months_seq <- as.Date(format(months_seq, "%Y-%m-01"))
months_seq <- as.Date(sapply(months_seq, function(d) {
  # last calendar day of each month
  as.character(seq(d, length.out = 2, by = "month")[2] - 1)
}))

# ---- Build alpha for each month ----
build_alpha_one_month <- function(sig_d) {
  ym_tag <- format(sig_d, "%Y%m")
  fpath <- file.path(FDB_DIR, paste0("factor_db_", ym_tag, ".parquet"))
  if (!file.exists(fpath)) return(NULL)

  fdb <- as.data.table(read_parquet(fpath))
  fdb <- fdb[Coverage == TRUE]

  # Pivot wide: Ticker × Factor_Name -> Z_Score
  fwide <- dcast(fdb, Ticker ~ Factor_Name, value.var = "Z_Score", fun.aggregate = mean)

  # Required factors check
  needed <- c(
    "Q01_GPA", "Q17_ROIC", "Q11_Net_Margin",
    "Q21_Revenue_Growth", "Q22_Earnings_Growth", "Q23_Sustainable_Growth",
    "Q15_Debt_to_Equity", "Q07_Earnings_Stability",
    "Q09_CFOA", "Q05_Accrual"
  )
  available <- intersect(needed, names(fwide))
  if (length(available) < 7) return(NULL)  # need at least 7/10 factors

  # Universe: KOSPI200 ∪ KOSDAQ150 + liquidity 5e7 (mandate per request.json)
  d20_start <- sig_d - 30
  univ_dt <- RAWDATA[Date >= d20_start & Date <= sig_d,
                 .(AvgTrdVal = mean(Vol * Close, na.rm = TRUE),
                   In_K200 = any(K200 == TRUE, na.rm = TRUE),
                   In_KQ150 = any(KQ150 == TRUE, na.rm = TRUE)), by = Ticker]
  univ_dt <- univ_dt[!is.na(AvgTrdVal) & AvgTrdVal >= 5e7 & (In_K200 | In_KQ150)]
  uni <- univ_dt[, .(Ticker)]

  fwide <- fwide[Ticker %in% uni$Ticker]
  if (nrow(fwide) < 50) return(NULL)

  # ---- A1 Profitability: GPA + ROIC + NM ----
  prof_cols <- intersect(c("Q01_GPA", "Q17_ROIC", "Q11_Net_Margin"), names(fwide))
  if (length(prof_cols) == 0) return(NULL)
  fwide[, Z_A1 := rowMeans(.SD, na.rm = TRUE), .SDcols = prof_cols]
  fwide[, Z_A1 := xs_z(Z_A1)]

  # ---- A2 Growth: Revenue G + Earnings G + Sustainable G ----
  grow_cols <- intersect(c("Q21_Revenue_Growth", "Q22_Earnings_Growth", "Q23_Sustainable_Growth"), names(fwide))
  if (length(grow_cols) == 0) return(NULL)
  fwide[, Z_A2 := rowMeans(.SD, na.rm = TRUE), .SDcols = grow_cols]
  fwide[, Z_A2 := xs_z(Z_A2)]

  # ---- A3 Safety: -D/E + ES (low leverage + stable earnings) ----
  safe_dt <- data.table(Ticker = fwide$Ticker)
  if ("Q15_Debt_to_Equity" %in% names(fwide)) safe_dt[, neg_DE := -fwide$Q15_Debt_to_Equity]
  if ("Q07_Earnings_Stability" %in% names(fwide)) safe_dt[, ES := fwide$Q07_Earnings_Stability]
  safe_cols <- setdiff(names(safe_dt), "Ticker")
  if (length(safe_cols) == 0) return(NULL)
  safe_dt[, Z_A3 := rowMeans(.SD, na.rm = TRUE), .SDcols = safe_cols]
  fwide[, Z_A3 := xs_z(safe_dt$Z_A3)]

  # ---- A4 CashFlow Quality: CFOA + (-Accrual) (Sloan inverse) ----
  cfq_dt <- data.table(Ticker = fwide$Ticker)
  if ("Q09_CFOA" %in% names(fwide)) cfq_dt[, CFOA := fwide$Q09_CFOA]
  if ("Q05_Accrual" %in% names(fwide)) cfq_dt[, neg_Accr := -fwide$Q05_Accrual]
  cfq_cols <- setdiff(names(cfq_dt), "Ticker")
  if (length(cfq_cols) == 0) return(NULL)
  cfq_dt[, Z_A4 := rowMeans(.SD, na.rm = TRUE), .SDcols = cfq_cols]
  fwide[, Z_A4 := xs_z(cfq_dt$Z_A4)]

  # ---- Composite alpha = mean(A1, A2, A3, A4) ----
  axis_cols <- c("Z_A1", "Z_A2", "Z_A3", "Z_A4")
  fwide[, alpha_raw := rowMeans(.SD, na.rm = TRUE), .SDcols = axis_cols]
  fwide[, alpha := xs_z(alpha_raw)]

  # Drop NA alpha
  fwide <- fwide[!is.na(alpha)]

  # Spec 1 = Composite ALL (default)
  # Spec 2 = Profitability + Safety only (drop Growth + CFQ)
  # Spec 3 = Profitability + Growth only (AFP 2019 narrow QMJ)
  fwide[, alpha_S2_PS := xs_z(rowMeans(.SD, na.rm = TRUE)), .SDcols = c("Z_A1", "Z_A3")]
  fwide[, alpha_S3_PG := xs_z(rowMeans(.SD, na.rm = TRUE)), .SDcols = c("Z_A1", "Z_A2")]

  fwide[, sig_date := sig_d]
  return(fwide[, .(sig_date, Ticker, Z_A1, Z_A2, Z_A3, Z_A4, alpha, alpha_S2_PS, alpha_S3_PG)])
}

cat("[2/8] Building alpha for each month...\n")
alpha_panel_list <- list()
n_done <- 0
for (sig_d in months_seq) {
  res <- tryCatch(build_alpha_one_month(as.Date(sig_d)), error = function(e) NULL)
  if (!is.null(res)) {
    alpha_panel_list[[length(alpha_panel_list) + 1]] <- res
    n_done <- n_done + 1
  }
}
alpha_panel <- rbindlist(alpha_panel_list)
cat(sprintf("  -> Built %d months × avg %.0f stocks\n", n_done, nrow(alpha_panel) / max(n_done, 1)))

# ---- Forward returns ----
cat("[3/8] Computing forward 1M returns...\n")
ret_panel <- alpha_panel[, .(sig_date, Ticker)]
ret_panel[, sig_date := as.Date(sig_date)]
ret_list <- vector("list", nrow(ret_panel))

# Pre-build month-end NAV map
RAWDATA[, YearMonth := format(Date, "%Y-%m")]
month_close <- RAWDATA[, .(MEnd = max(Date)), by = YearMonth]
month_close[, sig_date := as.Date(MEnd)]

# Compute next month return per Ticker, sig_date
RAWDATA_eom <- RAWDATA[Date %in% month_close$MEnd, .(Date, Ticker, Close)]
setkey(RAWDATA_eom, Ticker, Date)
RAWDATA_eom[, Ret_fwd1M := shift(Close, type = "lead") / Close - 1, by = Ticker]
RAWDATA_eom[, sig_date := Date]

alpha_panel <- merge(alpha_panel, RAWDATA_eom[, .(sig_date, Ticker, Ret_fwd1M)],
                     by = c("sig_date", "Ticker"), all.x = TRUE)
alpha_panel <- alpha_panel[!is.na(Ret_fwd1M)]
cat(sprintf("  -> Panel after forward return: %d obs\n", nrow(alpha_panel)))

# ---- IC computation per month ----
cat("[4/8] Computing IC per month per spec...\n")
ic_dt <- alpha_panel[, .(
  rank_ic_S1 = cor(alpha,       Ret_fwd1M, method = "spearman", use = "complete.obs"),
  rank_ic_S2 = cor(alpha_S2_PS, Ret_fwd1M, method = "spearman", use = "complete.obs"),
  rank_ic_S3 = cor(alpha_S3_PG, Ret_fwd1M, method = "spearman", use = "complete.obs"),
  N = .N
), by = sig_date]
ic_dt <- ic_dt[!is.na(rank_ic_S1)]
cat(sprintf("  -> IC months: %d\n", nrow(ic_dt)))

# Diagnostics for each spec
diagnose_spec <- function(ic_vec, name) {
  n <- length(ic_vec)
  if (n < 24) return(NULL)
  ic_mean <- mean(ic_vec, na.rm = TRUE)
  ic_sd <- sd(ic_vec, na.rm = TRUE)
  icir <- ic_mean / ic_sd * sqrt(12)
  # Newey-West t (HAC) approximation: simple t with lag-3 adjustment
  hac_t <- function(x, lag = 3) {
    n <- length(x)
    m <- mean(x, na.rm = TRUE)
    e <- x - m
    g0 <- sum(e^2, na.rm = TRUE) / n
    s2 <- g0
    for (k in 1:lag) {
      gk <- sum(e[(k+1):n] * e[1:(n-k)], na.rm = TRUE) / n
      w <- 1 - k / (lag + 1)
      s2 <- s2 + 2 * w * gk
    }
    se <- sqrt(s2 / n)
    m / se
  }
  nw_t <- hac_t(ic_vec, lag = 3)
  list(
    spec = name,
    n_months = n,
    rank_ic = round(ic_mean, 5),
    ic_sd = round(ic_sd, 5),
    icir = round(icir, 4),
    nw_t = round(nw_t, 4),
    pct_pos_months = round(mean(ic_vec > 0, na.rm = TRUE), 4)
  )
}

spec_diag <- list(
  S1_ALL = diagnose_spec(ic_dt$rank_ic_S1, "S1_ALL_4axes"),
  S2_PS = diagnose_spec(ic_dt$rank_ic_S2, "S2_Prof_Safety"),
  S3_PG = diagnose_spec(ic_dt$rank_ic_S3, "S3_Prof_Growth")
)
print(spec_diag)

# ---- Subperiod stability ----
cat("[5/8] Subperiod stability analysis...\n")
ic_dt[, period := fcase(
  sig_date < as.Date("2015-01-01"), "p1_2008_2014",
  sig_date < as.Date("2020-01-01"), "p2_2015_2019",
  default = "p3_2020_2023"
)]
sub_stab <- ic_dt[, .(
  S1_rank_ic = mean(rank_ic_S1, na.rm = TRUE),
  S1_icir = mean(rank_ic_S1, na.rm = TRUE) / sd(rank_ic_S1, na.rm = TRUE) * sqrt(12),
  N = .N
), by = period]
print(sub_stab)
sub_pos_S1 <- mean(sub_stab$S1_rank_ic > 0, na.rm = TRUE)
cat(sprintf("  -> Subperiod stability S1 (>0): %.2f\n", sub_pos_S1))

# ---- Monotonicity (decile spread) ----
cat("[6/8] Decile monotonicity (S1 ALL)...\n")
alpha_panel[, decile := cut(alpha,
                            breaks = quantile(alpha, probs = seq(0, 1, 0.1), na.rm = TRUE),
                            labels = 1:10, include.lowest = TRUE),
            by = sig_date]
dec_ret <- alpha_panel[!is.na(decile), .(MeanRet = mean(Ret_fwd1M, na.rm = TRUE)), by = decile]
dec_ret[, decile_num := as.integer(as.character(decile))]
setorder(dec_ret, decile_num)
print(dec_ret)
mono_cor <- cor(dec_ret$decile_num, dec_ret$MeanRet, method = "spearman")
cat(sprintf("  -> Decile rank-correlation: %.4f\n", mono_cor))

# ---- Inheritance correlation (vs WT-D20260428_001 V2_FIAPAS, STR_1631/1656/1701/1715) ----
cat("[7/8] Inheritance correlation vs FIAPAS V2 + parents...\n")

# As-of date alpha for inheritance test (signal_as_of = 2023-11-30)
asof_alpha <- alpha_panel[sig_date == as.Date("2023-11-30")]
cat(sprintf("  -> As-of (2023-11-30) alpha names: %d\n", nrow(asof_alpha)))

# Load FIAPAS V2 alpha for cor comparison
fiapas_path <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260428_001/alpha_package.json")
inh_cors <- list()
if (file.exists(fiapas_path)) {
  fiapas <- fromJSON(fiapas_path, simplifyVector = FALSE)
  fiapas_alpha <- fiapas$alpha_vector
  fiapas_dt <- data.table(
    Ticker = names(fiapas_alpha),
    alpha_FIAPAS = unlist(fiapas_alpha)
  )
  comb <- merge(asof_alpha[, .(Ticker, alpha)], fiapas_dt, by = "Ticker")
  if (nrow(comb) >= 20) {
    inh_cors$vs_FIAPAS_V2_pearson <- round(cor(comb$alpha, comb$alpha_FIAPAS, use = "complete.obs"), 4)
    inh_cors$vs_FIAPAS_V2_spearman <- round(cor(comb$alpha, comb$alpha_FIAPAS, method = "spearman", use = "complete.obs"), 4)
  }
}

# Time-series inheritance: rank-IC of MAQGC vs FIAPAS-style synthetic
# For STR_1631/1656/1701/1715, we approximate via Q-quality factors used as parents proxy
# Here we use Q08_Composite_Quality from factor DB as "parent quality alpha proxy"
parent_proxy <- list()
parent_panel_list <- list()
for (sig_d in unique(alpha_panel$sig_date)) {
  ym_tag <- format(as.Date(sig_d), "%Y%m")
  fp <- file.path(FDB_DIR, paste0("factor_db_", ym_tag, ".parquet"))
  if (!file.exists(fp)) next
  fdb <- as.data.table(read_parquet(fp))
  fdb <- fdb[Coverage == TRUE & Factor_Name == "Q08_Composite_Quality"]
  if (nrow(fdb) == 0) next
  fdb[, sig_date := as.Date(sig_d)]
  parent_panel_list[[length(parent_panel_list) + 1]] <- fdb[, .(sig_date, Ticker, parent_alpha = Z_Score)]
}
parent_panel <- rbindlist(parent_panel_list)
inh_panel <- merge(alpha_panel[, .(sig_date, Ticker, alpha, alpha_S2_PS, alpha_S3_PG, Ret_fwd1M)],
                   parent_panel, by = c("sig_date", "Ticker"))
inh_corrs <- inh_panel[, .(
  cor_alpha_S1 = cor(alpha, parent_alpha, method = "spearman", use = "complete.obs"),
  cor_alpha_S2 = cor(alpha_S2_PS, parent_alpha, method = "spearman", use = "complete.obs"),
  cor_alpha_S3 = cor(alpha_S3_PG, parent_alpha, method = "spearman", use = "complete.obs")
), by = sig_date]
cat(sprintf("  -> mean spearman cor MAQGC vs Q08_Composite: S1=%.3f, S2=%.3f, S3=%.3f\n",
            mean(inh_corrs$cor_alpha_S1, na.rm = TRUE),
            mean(inh_corrs$cor_alpha_S2, na.rm = TRUE),
            mean(inh_corrs$cor_alpha_S3, na.rm = TRUE)))

inh_cors$vs_Q08_parent_proxy_meanSpearman <- round(mean(inh_corrs$cor_alpha_S1, na.rm = TRUE), 4)

# ---- Save results ----
cat("[8/8] Saving artifacts...\n")
results <- list(
  meta = list(
    task_id = "WT-D20260428_003",
    iter = 10,
    iter_track = "B",
    iter_name = "MAQGC_Multi_Axis_Growth_Quality_Composite",
    family = "quality_multi_axis × growth",
    family_orthogonal_to = c("FIAPAS investor_flow", "FIAPAS liquidity_diffusion", "FIAPAS accrual"),
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  ),
  spec_diagnostics = spec_diag,
  subperiod_stability = list(
    table = sub_stab,
    pct_positive = sub_pos_S1
  ),
  monotonicity = list(
    decile_returns = dec_ret,
    rank_correlation = mono_cor
  ),
  inheritance = inh_cors,
  n_months_evaluated = nrow(ic_dt)
)

saveRDS(alpha_panel, file.path(WT_DIR, "alpha_panel.rds"))
saveRDS(ic_dt, file.path(WT_DIR, "ic_dt.rds"))
saveRDS(asof_alpha, file.path(WT_DIR, "asof_alpha.rds"))

# Save summary JSON
write_json(results, file.path(WT_DIR, "evaluation_results.json"),
           pretty = TRUE, auto_unbox = TRUE, dataframe = "rows")

cat("\n=== SUMMARY ===\n")
cat(sprintf("S1 ALL_4axes  IC=%.4f  ICIR=%.3f  NW-t=%.2f  Mono=%.3f  Stab=%.2f\n",
            spec_diag$S1_ALL$rank_ic, spec_diag$S1_ALL$icir, spec_diag$S1_ALL$nw_t, mono_cor, sub_pos_S1))
cat(sprintf("S2 Prof+Safe  IC=%.4f  ICIR=%.3f  NW-t=%.2f\n",
            spec_diag$S2_PS$rank_ic, spec_diag$S2_PS$icir, spec_diag$S2_PS$nw_t))
cat(sprintf("S3 Prof+Grow  IC=%.4f  ICIR=%.3f  NW-t=%.2f\n",
            spec_diag$S3_PG$rank_ic, spec_diag$S3_PG$icir, spec_diag$S3_PG$nw_t))
cat(sprintf("Inheritance vs Q08 parent proxy: %.3f\n", inh_cors$vs_Q08_parent_proxy_meanSpearman))
cat(sprintf("As-of (2023-11-30) names: %d\n", nrow(asof_alpha)))
cat(sprintf("Done: %s\n", Sys.time()))
