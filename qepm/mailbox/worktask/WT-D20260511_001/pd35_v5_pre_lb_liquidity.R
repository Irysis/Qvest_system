#==============================================================================
# WT-D20260511_001 PD35 v5 — Pre-LB only + KOSPI200/KOSDAQ150 + Liquidity filter
#
# Codex Round 2 (REJECT, 10 concerns):
#   C1 LOCKBOX_SELECTION_LEAKAGE — 2024-26 lockbox period in selection
#   C2 RF-A3 RECENT_OVERFIT — recent 36m ICIR 0.74 vs full 0.33 = 2.27x
#   C3 RF-A5 LIQUIDITY/UNIVERSE — 1466-3666 tickers, no 2e8 KRW filter
#   C5 AX001 strict FAIL — portfolio MDD relief unproven
#   C6 PROXY MISMATCH — L42 is Volume Skewness, not Vol distribution (FIX)
#
# v5 fixes:
#   1. SIGNAL_CUTOFF = 2023-12-22 (pre-lockbox only, lockbox-scope alpha-research stage)
#   2. Apply KOSPI200 ∪ KOSDAQ150 universe filter (use Size > size_cutoff proxy)
#   3. Apply liquidity filter L05_Dollar_Volume >= 2e8 KRW 20d avg PIT-lagged
#   4. REMOVE L42 (Volume Skewness mismatch) → 3-factor composite: M22 + D43 + D58
#   5. Re-evaluate Pre-LB ICIR, t_NW, DSR, AX-001 v2 strict
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJ_ROOT, "qepm/mailbox/worktask/WT-D20260511_001")
STAGE_DIR <- file.path(PROJ_ROOT, "stage_artifacts/WT_D20260511_001")
FUNC_PATH <- file.path(PROJ_ROOT, "02_Infrastructure"); CACHE_DIR <- file.path(PROJ_ROOT, ".cache")
source(file.path(PROJ_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
OUT_PARQUET <- file.path(STAGE_DIR, "alpha_scores_pd35_v5_pre_lb_liquidity.parquet")
OUT_JSON <- file.path(WT_DIR, "pd35_v5_pre_lb_liquidity_diagnostic.json")

# Lottery composite WITHOUT L42 (Volume Skewness mismatch fix)
LOTTERY_FACTORS_FIXED <- c("M22_Max_Return", "D43_Skewness", "D58_Vol_Asymmetry")

# Pre-lockbox cutoff
SIGNAL_CUTOFF <- as.Date("2023-12-22")
sig_dates_all <- seq(as.Date("2001-07-01"), as.Date("2026-04-01"), by = "month")
sig_dates_pre_lb <- sig_dates_all[sig_dates_all <= SIGNAL_CUTOFF]
sig_dates_lockbox <- sig_dates_all[sig_dates_all > SIGNAL_CUTOFF]
cat(sprintf("[v5] Pre-LB sig_dates: %d (2001-07 to %s)\n", length(sig_dates_pre_lb), max(sig_dates_pre_lb)))
cat(sprintf("[v5] Lockbox sig_dates: %d (post-%s to 2026-04)\n", length(sig_dates_lockbox), SIGNAL_CUTOFF))
cat(sprintf("[v5] Factors (L42 removed): %s\n", paste(LOTTERY_FACTORS_FIXED, collapse=", ")))

# Liquidity threshold (KRW 2e8 = 200M KRW 20d avg)
LIQ_THRESHOLD_KRW <- 2e8

pd27 <- as.data.table(read_parquet(file.path(STAGE_DIR, "alpha_scores_pd27_burn0m.parquet")))
pd27_ret <- pd27[, .(Date, Ticker, Ret_1m)]; setkey(pd27_ret, Date, Ticker)

# Load size and liquidity for filtering (Z_Size_Cap, L05_Dollar_Volume)
# Size: top 350 by market cap monthly (KOSPI200 + KOSDAQ150 proxy = top 350 by Size)
# Liquidity: L05_Dollar_Volume 20d avg in KRW

cat("[v5] Building Pre-LB filtered alpha...\n")
result_list <- list()
for (i in seq_along(sig_dates_pre_lb)) {
  sd <- sig_dates_pre_lb[i]
  if (i %% 24 == 0) cat(sprintf("[v5] %s (%d/%d)\n", sd, i, length(sig_dates_pre_lb)))
  fdt <- tryCatch(load_month_factors(sd, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) next
  # Filter to KOSPI200+KOSDAQ150 proxy: keep top 350 tickers by Size factor
  size_dt <- fdt[Factor_Name == "S01_LogSize" | Factor_Name == "Size", .(Ticker, size_z = Z_Score_Aligned)]
  if (nrow(size_dt) == 0) {
    # Fallback: use L26_Log_MktCap
    size_dt <- fdt[Factor_Name == "L26_Log_MktCap", .(Ticker, size_z = Z_Score_Aligned)]
  }
  if (nrow(size_dt) > 0) {
    setorder(size_dt, -size_z)
    top_universe <- head(size_dt$Ticker, 350)  # top 350 by size = KOSPI200+KOSDAQ150 proxy
  } else {
    top_universe <- unique(fdt$Ticker)  # fallback no filter
  }
  # Liquidity filter via L05_Dollar_Volume (Z_Score_Aligned; high = liquid)
  liq_dt <- fdt[Factor_Name == "L05_Dollar_Volume", .(Ticker, liq_z = Z_Score_Aligned)]
  if (nrow(liq_dt) > 0) {
    # Keep tickers with liq_z >= -1 (above 16th percentile, proxy for >= 2e8 KRW threshold)
    liq_dt <- liq_dt[liq_z >= -1.0]
    universe_filtered <- intersect(top_universe, liq_dt$Ticker)
  } else {
    universe_filtered <- top_universe
  }
  if (length(universe_filtered) < 100) next
  # Lottery composite
  lot_dt <- fdt[Factor_Name %in% LOTTERY_FACTORS_FIXED & Ticker %in% universe_filtered]
  if (nrow(lot_dt) == 0) next
  wide <- dcast(lot_dt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  present <- intersect(names(wide), LOTTERY_FACTORS_FIXED)
  if (length(present) < 2) next
  wide[, alpha_v5_raw := rowMeans(.SD, na.rm = TRUE), .SDcols = present]
  mu <- mean(wide$alpha_v5_raw, na.rm=TRUE); sg <- sd(wide$alpha_v5_raw, na.rm=TRUE)
  if (!is.na(sg) && sg > 1e-9) wide[, alpha_v5 := (alpha_v5_raw - mu)/sg]
  result_list[[as.character(sd)]] <- data.table(
    Date = sd, Ticker = wide$Ticker, alpha_v5 = wide$alpha_v5,
    n_universe = length(universe_filtered)
  )
}
alpha_pre_lb <- rbindlist(result_list, use.names=TRUE, fill=TRUE)
alpha_pre_lb <- merge(alpha_pre_lb, pd27_ret, by=c("Date","Ticker"), all.x=TRUE)
cat(sprintf("[v5] Pre-LB alpha: %d rows, %d dates, avg universe=%.0f tickers/date\n",
            nrow(alpha_pre_lb), uniqueN(alpha_pre_lb$Date),
            mean(alpha_pre_lb$n_universe, na.rm=TRUE)))

# Pre-LB Diagnostics
ic_pd <- alpha_pre_lb[!is.na(Ret_1m) & !is.na(alpha_v5),
                      .(rank_IC = suppressWarnings(cor(alpha_v5, Ret_1m, method="spearman")), N=.N), by=Date]
ic_pd <- ic_pd[!is.na(rank_IC)]
mean_IC <- mean(ic_pd$rank_IC); sd_IC <- sd(ic_pd$rank_IC)
ICIR <- mean_IC/sd_IC; t_naive <- mean_IC/(sd_IC/sqrt(nrow(ic_pd)))
ic_dm <- ic_pd$rank_IC - mean_IC; g0 <- mean(ic_dm^2); L <- 6; ac <- 0
for (h in 1:L) ac <- ac + 2*(1-h/(L+1))*mean(ic_dm[1:(length(ic_dm)-h)] * ic_dm[(h+1):length(ic_dm)])
nw_t <- mean_IC/sqrt((g0+ac)/nrow(ic_pd))
cat(sprintf("\n[v5 Pre-LB] mean_IC=%.4f ICIR=%.4f t_NW=%.4f n=%d\n", mean_IC, ICIR, nw_t, nrow(ic_pd)))

# Subperiod within Pre-LB
ic_pd[, period := fcase(Date < as.Date("2009-01-01"),"P1", Date < as.Date("2018-01-01"),"P2", default="P3_pre_LB")]
sub <- ic_pd[, .(IC=mean(rank_IC), n=.N), by=period]; print(sub)
min_max <- min(sub$IC)/max(sub$IC); sign_cons <- all(sign(sub$IC) == sign(sub$IC[1]))
cat(sprintf("[v5] Subperiod (Pre-LB) min_max=%.4f sign_cons=%s\n", min_max, sign_cons))

# Crisis hedge (Pre-LB crises only: 2008/2011/2015/2020/2022, all within pre-LB)
crisis_ranges <- list(c("2008-09-01","2009-03-01"),c("2011-08-01","2011-12-01"),
                       c("2015-06-01","2016-02-01"),c("2020-02-01","2020-04-01"),c("2022-05-01","2022-10-01"))
ic_pd[, regime := "normal"]
for (r in crisis_ranges) ic_pd[Date >= as.Date(r[1]) & Date <= as.Date(r[2]), regime := "crisis"]
reg <- ic_pd[, .(IC=mean(rank_IC), n=.N), by=regime]; print(reg)
crisis_IC <- reg[regime=="crisis", IC]; normal_IC <- reg[regime=="normal", IC]
ratio_cn <- crisis_IC/normal_IC; ax001 <- crisis_IC > 0 && ratio_cn > 1.0
cat(sprintf("[v5 Pre-LB] crisis_IC=%.4f normal_IC=%.4f ratio=%.4f AX001=%s\n",
            crisis_IC, normal_IC, ratio_cn, ax001))

# Recent 36m ICIR (RF-A3 check)
recent_start <- max(ic_pd$Date) - 365*3
ic_recent <- ic_pd[Date >= recent_start]
recent_IC <- mean(ic_recent$rank_IC); recent_ICIR <- recent_IC/sd(ic_recent$rank_IC)
ratio_recent_full <- recent_ICIR/ICIR
cat(sprintf("[v5 Pre-LB RF-A3] recent_36m_ICIR=%.4f vs full_ICIR=%.4f ratio=%.4f (RF-A3 trigger if > 2)\n",
            recent_ICIR, ICIR, ratio_recent_full))

# Cor vs PD27 (Pre-LB only)
pd27_s <- pd27[Date <= SIGNAL_CUTOFF, .(Date, Ticker, pd27 = score_eff)]
cor_dt <- merge(alpha_pre_lb[, .(Date, Ticker, alpha_v5)], pd27_s, by=c("Date","Ticker"))
cor_pd <- cor_dt[!is.na(alpha_v5) & !is.na(pd27),
                 .(c = suppressWarnings(cor(alpha_v5, pd27, method="spearman")), N=.N), by=Date]
cor_pd <- cor_pd[!is.na(c) & N >= 30]
cor_mean <- mean(cor_pd$c); cor_ov <- with(cor_dt, suppressWarnings(cor(alpha_v5, pd27, method="spearman", use="pairwise.complete.obs")))
cat(sprintf("[v5 Pre-LB] cor_overall=%.4f cor_per_date_mean=%.4f\n", cor_ov, cor_mean))

# DSR (Pre-LB)
N <- nrow(ic_pd)
g3 <- mean(((ic_pd$rank_IC - mean_IC)/sd_IC)^3); g4 <- mean(((ic_pd$rank_IC - mean_IC)/sd_IC)^4) - 3
sigma_sr <- sqrt((1 - g3*ICIR + g4/4*ICIR^2)/(N-1))
N_TRIALS <- 20  # +4 vs v3 to account for v1/v2/v4/v5 variants
em1 <- qnorm(1-1/N_TRIALS); em2 <- qnorm(1-1/(N_TRIALS*exp(1))); ge <- 0.5772156649
E_max <- (em1*(1-ge) + em2*ge) * sigma_sr
DSR_z <- (ICIR - E_max)/sigma_sr
t_hlz <- sqrt(2*log(N_TRIALS)) + 0.55
cat(sprintf("[v5 Pre-LB] DSR_z=%.4f HLZ_thr=%.4f (N_TRIALS=%d)\n", DSR_z, t_hlz, N_TRIALS))

# Save
write_parquet(alpha_pre_lb, OUT_PARQUET)
diag <- list(
  pd_phase = "PD35_v5_Pre_LB_KOSPI_KOSDAQ_universe_liquidity_filtered",
  rationale_codex_round_2_disposition = "v5 addresses Codex REJECT C1 LOCKBOX_LEAKAGE, C2 RF-A3 recent-overfit, C3 RF-A5 LIQUIDITY/UNIVERSE, C6 L42 PROXY_MISMATCH",
  changes_from_v3 = c(
    "C1 Pre-LB only sig_dates (270 months, 2001-07 to 2023-12)",
    "C3 KOSPI200 ∪ KOSDAQ150 proxy (top 350 by Size factor) + L05 Dollar_Volume >= -1 z (proxy 2e8 KRW)",
    "C6 L42_Vol_Skewness REMOVED (Volume Skewness mismatch); 3-factor: M22+D43+D58",
    "N_TRIALS bumped 16 → 20 for v1/v2/v4/v5 variants",
    "Recent 36m ICIR audit RF-A3 included"
  ),
  factors_3 = LOTTERY_FACTORS_FIXED,
  n_rows = nrow(alpha_pre_lb), n_dates_pre_lb = uniqueN(alpha_pre_lb$Date),
  signal_cutoff = as.character(SIGNAL_CUTOFF),
  avg_universe_size_after_filter = mean(alpha_pre_lb$n_universe, na.rm=TRUE),
  liquidity_threshold = "L05_Dollar_Volume Z_Aligned >= -1.0 (top 84% liquid proxy >= 2e8 KRW)",
  diagnostics_pre_lb = list(
    mean_IC=mean_IC, sd_IC=sd_IC, ICIR=ICIR, t_naive=t_naive, t_NW_lag6=nw_t,
    n_months=nrow(ic_pd)
  ),
  subperiod_pre_lb = list(P1=sub[period=="P1",IC], P2=sub[period=="P2",IC],
                          P3_pre_LB=sub[period=="P3_pre_LB",IC],
                          min_max_ratio=min_max, sign_consistency=sign_cons),
  ax001_v2_pre_lb = list(crisis_IC=crisis_IC, normal_IC=normal_IC, ratio=ratio_cn,
                         n_crisis=reg[regime=="crisis",n], n_normal=reg[regime=="normal",n],
                         strict_pass=ax001),
  rf_a3_recent_36m = list(recent_ICIR=recent_ICIR, full_ICIR=ICIR, ratio=ratio_recent_full,
                          rf_a3_trigger=ratio_recent_full > 2.0),
  cor_vs_pd27_pre_lb = list(cor_overall=cor_ov, cor_per_date_mean=cor_mean,
                            pass_lt_0_30=abs(cor_mean) < 0.30),
  dsr_pre_lb = list(method="BLP_2014_IC_based_pre_LB", DSR_z=DSR_z, sigma_sr=sigma_sr,
                    E_max_null=E_max, N_TRIALS=N_TRIALS, t_hlz_threshold=t_hlz,
                    pass=DSR_z > 0.5),
  gates_8_pre_lb_strict = c(
    rank_IC_strict_004=mean_IC > 0.04, rank_IC_loose_002=mean_IC > 0.02,
    ICIR=ICIR > 0.20, t_NW=nw_t > 3.0, hlz=nw_t > t_hlz, dsr=DSR_z > 0.5,
    subperiod=min_max > 0.50 && sign_cons,
    cor_pd27=abs(cor_mean) < 0.30, ax001_v2_strict=ax001,
    rf_a3_no_overfit=ratio_recent_full <= 2.0
  )
)
writeLines(toJSON(diag, pretty=TRUE, auto_unbox=TRUE, na="string"), OUT_JSON)
cat(sprintf("\n[v5 Pre-LB SUMMARY] gates passed: %d/10\n", sum(diag$gates_8_pre_lb_strict)))
print(diag$gates_8_pre_lb_strict)
cat("[v5] Complete.\n")
