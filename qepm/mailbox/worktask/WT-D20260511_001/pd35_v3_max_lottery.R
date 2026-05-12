#==============================================================================
# WT-D20260511_001 PD35 v3 — MAX-Lottery + Skewness-Lottery composite
#
# v1/v2 finding: Q10/Q01/Q17 profit quality is pro-cyclical (crisis IC negative).
# M22_Max_Return is the strongest crisis-positive factor (+0.063 across 5 crisis months).
# D44_Kurtosis (was in v1) underperforms in crisis (-0.046).
#
# Literature: Bali-Cakici-Whitelaw 2011 JFE "Maxing Out: Stocks as Lotteries..."
# Investors over-pay for lottery-like stocks (high MAX return) → underperform.
# Crisis-positive: in stress, lottery premium retreats (risk-off avoidance), so
# low-MAX stocks (alpha after sign flip via IC-aligned direction) outperform.
#
# v3 spec: 4 factors all crisis-hedge candidates per literature
#   - M22_Max_Return (lottery, Bali-Cakici-Whitelaw 2011)
#   - D43_Skewness (ex-ante skewness lottery, Boyer-Mitton-Vorkink 2010)
#   - L42_Vol_Skewness (vol-asymmetry lottery proxy)
#   - D58_Vol_Asymmetry (downside vs upside vol asymmetry, Ang-Chen-Xing 2006)
#
# All factors expected to share lottery-preference penalty mechanism that
# strengthens in crisis (downside risk premium).
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJ_ROOT, "qepm/mailbox/worktask/WT-D20260511_001")
STAGE_DIR <- file.path(PROJ_ROOT, "stage_artifacts/WT_D20260511_001")
FUNC_PATH <- file.path(PROJ_ROOT, "02_Infrastructure"); CACHE_DIR <- file.path(PROJ_ROOT, ".cache")
source(file.path(PROJ_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
OUT_PARQUET <- file.path(STAGE_DIR, "alpha_scores_pd35_v3_lottery.parquet")
OUT_JSON <- file.path(WT_DIR, "pd35_v3_lottery_diagnostic.json")

LOTTERY_FACTORS <- c("M22_Max_Return", "D43_Skewness", "L42_Vol_Skewness", "D58_Vol_Asymmetry")
sig_dates_all <- seq(as.Date("2001-07-01"), as.Date("2026-04-01"), by = "month")

cat(sprintf("[v3] Building lottery composite across %d sig_dates with %d factors\n",
            length(sig_dates_all), length(LOTTERY_FACTORS)))

pd27 <- as.data.table(read_parquet(file.path(STAGE_DIR, "alpha_scores_pd27_burn0m.parquet")))
pd27_ret <- pd27[, .(Date, Ticker, Ret_1m)]
setkey(pd27_ret, Date, Ticker)

result_list <- list()
for (i in seq_along(sig_dates_all)) {
  sd <- sig_dates_all[i]
  if (i %% 24 == 0) cat(sprintf("[v3] sig_date %s (%d/%d)\n", sd, i, length(sig_dates_all)))
  fdt <- tryCatch(load_month_factors(sd, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) next
  fdt <- fdt[Factor_Name %in% LOTTERY_FACTORS]
  if (nrow(fdt) == 0) next
  wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  present <- intersect(names(wide), LOTTERY_FACTORS)
  if (length(present) < 2) next  # need at least 2 factors
  wide[, alpha_lottery_raw := rowMeans(.SD, na.rm = TRUE), .SDcols = present]
  mu <- mean(wide$alpha_lottery_raw, na.rm = TRUE)
  sg <- sd(wide$alpha_lottery_raw, na.rm = TRUE)
  if (!is.na(sg) && sg > 1e-9) wide[, alpha_lottery := (alpha_lottery_raw - mu) / sg]
  result_list[[as.character(sd)]] <- data.table(
    Date = sd, Ticker = wide$Ticker, alpha_lottery = wide$alpha_lottery,
    n_factors_used = length(present)
  )
}

alpha <- rbindlist(result_list, use.names = TRUE, fill = TRUE)
alpha <- merge(alpha, pd27_ret, by = c("Date", "Ticker"), all.x = TRUE)
cat(sprintf("[v3] Built %d rows, %d dates, %d with Ret_1m\n",
            nrow(alpha), uniqueN(alpha$Date), sum(!is.na(alpha$Ret_1m))))

# ---- Diagnostics ----
ic_per_date <- alpha[!is.na(Ret_1m) & !is.na(alpha_lottery),
                     .(rank_IC = suppressWarnings(cor(alpha_lottery, Ret_1m, method = "spearman")),
                       N = .N), by = Date]
ic_per_date <- ic_per_date[!is.na(rank_IC)]
mean_IC <- mean(ic_per_date$rank_IC); sd_IC <- sd(ic_per_date$rank_IC)
ICIR_naive <- mean_IC / sd_IC
t_naive <- mean_IC / (sd_IC / sqrt(nrow(ic_per_date)))

# NW SE lag 6
ic_demean <- ic_per_date$rank_IC - mean_IC
g0 <- mean(ic_demean^2); L <- 6; acov <- 0
for (h in 1:L) {
  w <- 1 - h/(L+1)
  acov <- acov + 2*w*mean(ic_demean[1:(length(ic_demean)-h)] * ic_demean[(h+1):length(ic_demean)])
}
nw_se <- sqrt((g0 + acov)/nrow(ic_per_date))
nw_t <- mean_IC / nw_se

cat(sprintf("[v3] mean_IC=%.4f sd_IC=%.4f ICIR=%.4f t_naive=%.4f t_NW=%.4f\n",
            mean_IC, sd_IC, ICIR_naive, t_naive, nw_t))

# Subperiod
ic_per_date[, period := fcase(
  Date < as.Date("2009-01-01"), "P1",
  Date < as.Date("2018-01-01"), "P2",
  default = "P3"
)]
subper <- ic_per_date[, .(rank_IC = mean(rank_IC, na.rm=TRUE), n=.N), by=period]
print(subper)
min_max_ratio <- min(subper$rank_IC) / max(subper$rank_IC)
sign_cons <- all(sign(subper$rank_IC) == sign(subper$rank_IC[1]))
cat(sprintf("[v3] Subperiod min_max_ratio=%.4f sign_consistency=%s\n", min_max_ratio, sign_cons))

# Crisis IC
crisis_ranges <- list(
  c("2008-09-01","2009-03-01"), c("2011-08-01","2011-12-01"),
  c("2015-06-01","2016-02-01"), c("2020-02-01","2020-04-01"),
  c("2022-05-01","2022-10-01")
)
ic_per_date[, regime := "normal"]
for (r in crisis_ranges) ic_per_date[Date >= as.Date(r[1]) & Date <= as.Date(r[2]), regime := "crisis"]
ic_regime <- ic_per_date[, .(mean_IC = mean(rank_IC), n = .N), by = regime]
print(ic_regime)
crisis_IC <- ic_regime[regime == "crisis", mean_IC]
normal_IC <- ic_regime[regime == "normal", mean_IC]
ratio_cn <- crisis_IC / normal_IC
ax001_pass <- crisis_IC > 0 && ratio_cn > 1.0
cat(sprintf("[v3] crisis_IC=%.4f normal_IC=%.4f ratio=%.4f AX-001-v2-pass=%s\n",
            crisis_IC, normal_IC, ratio_cn, ax001_pass))

# Cor vs PD27
pd27_s <- pd27[, .(Date, Ticker, pd27 = score_eff)]
cor_dt <- merge(alpha[, .(Date, Ticker, alpha_lottery)], pd27_s, by=c("Date","Ticker"))
cor_per_date <- cor_dt[!is.na(alpha_lottery) & !is.na(pd27),
                      .(cor = suppressWarnings(cor(alpha_lottery, pd27, method="spearman")), N=.N), by=Date]
cor_per_date <- cor_per_date[!is.na(cor) & N >= 30]
cor_mean <- mean(cor_per_date$cor); cor_overall <- with(cor_dt, suppressWarnings(cor(alpha_lottery, pd27, method="spearman", use="pairwise.complete.obs")))
cat(sprintf("[v3] cor_overall=%.4f cor_per_date_mean=%.4f\n", cor_overall, cor_mean))

# DSR
N <- nrow(ic_per_date)
g3 <- mean(((ic_per_date$rank_IC - mean_IC)/sd_IC)^3, na.rm=TRUE)
g4 <- mean(((ic_per_date$rank_IC - mean_IC)/sd_IC)^4, na.rm=TRUE) - 3
sigma_sr <- sqrt((1 - g3*ICIR_naive + g4/4 * ICIR_naive^2)/(N-1))
N_TRIALS <- 16  # +1 trial vs v1
em_phi1 <- qnorm(1 - 1/N_TRIALS); em_phi2 <- qnorm(1 - 1/(N_TRIALS * exp(1)))
gamma_em <- 0.5772156649
E_max <- (em_phi1*(1-gamma_em) + em_phi2*gamma_em) * sigma_sr
DSR_z <- (ICIR_naive - E_max) / sigma_sr
t_hlz <- sqrt(2*log(N_TRIALS)) + 0.55
cat(sprintf("[v3] DSR sigma=%.5f E_max=%.4f DSR_z=%.4f HLZ_threshold=%.4f\n",
            sigma_sr, E_max, DSR_z, t_hlz))

# Save
write_parquet(alpha, OUT_PARQUET)
diag <- list(
  pd_phase = "PD35_v3_lottery_M22_D43_L42_D58",
  factors = LOTTERY_FACTORS,
  n_rows = nrow(alpha), n_dates = uniqueN(alpha$Date),
  diagnostics = list(
    mean_IC = mean_IC, sd_IC = sd_IC, ICIR_naive = ICIR_naive,
    t_naive = t_naive, t_NW_lag6 = nw_t, ic_pos_share = mean(ic_per_date$rank_IC > 0)
  ),
  subperiod = list(
    P1 = subper[period=="P1", rank_IC], P2 = subper[period=="P2", rank_IC],
    P3 = subper[period=="P3", rank_IC], min_max_ratio = min_max_ratio,
    sign_consistency = sign_cons
  ),
  ax001_v2_crisis = list(
    crisis_IC = crisis_IC, normal_IC = normal_IC, ratio = ratio_cn,
    n_crisis = ic_regime[regime=="crisis", n], n_normal = ic_regime[regime=="normal", n],
    pass = ax001_pass
  ),
  cor_vs_pd27 = list(
    cor_overall = cor_overall, cor_per_date_mean = cor_mean,
    pass_lt_0_30 = abs(cor_mean) < 0.30
  ),
  dsr = list(method="BLP_2014_closed_form_IC_based", DSR_z = DSR_z,
             sigma_sr = sigma_sr, E_max_null = E_max,
             N_TRIALS = N_TRIALS, t_hlz_threshold = t_hlz, pass = DSR_z > 0.5),
  gates_summary = c(
    rank_IC = mean_IC > 0.02, ICIR = ICIR_naive > 0.20, t_NW = nw_t > 3.0,
    hlz = nw_t > t_hlz, dsr = DSR_z > 0.5,
    subperiod = min_max_ratio > 0.50 && sign_cons,
    cor_pd27 = abs(cor_mean) < 0.30, ax001_v2 = ax001_pass
  )
)
writeLines(toJSON(diag, pretty=TRUE, auto_unbox=TRUE, na="string"), OUT_JSON)
cat(sprintf("[v3] Diagnostic: %s\n", OUT_JSON))
gates <- diag$gates_summary
cat(sprintf("\n[v3 SUMMARY] gates passed: %d/8\n", sum(gates)))
print(gates)
cat("[v3] Complete.\n")
