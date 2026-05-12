#==============================================================================
# WT-D20260511_001 PD35 v4 — Crisis-Robust Lottery + Earnings Persistence
#
# v1 (3-axis EW): IC=0.030 t=4.66 6/8 (fail AX-001 + subperiod_NaN)
# v3 (4-factor lottery): IC=0.034 t=4.97 6/8 (fail AX-001 ratio 0.92, subperiod 0.22)
#
# Diagnosis: M22+D43+L42+D58 all have positive crisis IC (~+0.031) but subperiod
# weak in P1 (2001-08). Q33_Earnings_Persistence is +0.029 crisis robust per
# v2 diagnostic. AC22_Accrual_Volatility +0.011 crisis robust.
#
# v4 spec: 6-factor crisis-robust composite
#   Lottery cluster (4): M22, D43, L42, D58 (Bali 2011 + Boyer 2010 + Ang 2006)
#   Earnings stability cluster (2): Q33_Earnings_Persistence + AC22_Accrual_Volatility
#     (Sloan 1996 + Hirshleifer 2004)
#
# Weights: lottery cluster = 0.70 (4 factors EW within), earnings = 0.30 (2 factors EW)
# Rationale: lottery factors are stronger but P1 weak. Earnings persistence is robust
# across periods. Hybrid 70/30 maintains lottery primacy + crisis robustness.
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJ_ROOT, "qepm/mailbox/worktask/WT-D20260511_001")
STAGE_DIR <- file.path(PROJ_ROOT, "stage_artifacts/WT_D20260511_001")
FUNC_PATH <- file.path(PROJ_ROOT, "02_Infrastructure"); CACHE_DIR <- file.path(PROJ_ROOT, ".cache")
source(file.path(PROJ_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
OUT_PARQUET <- file.path(STAGE_DIR, "alpha_scores_pd35_v4_crisis_robust.parquet")
OUT_JSON <- file.path(WT_DIR, "pd35_v4_crisis_robust_diagnostic.json")

LOTTERY_CLUSTER <- c("M22_Max_Return", "D43_Skewness", "L42_Vol_Skewness", "D58_Vol_Asymmetry")
EARNINGS_CLUSTER <- c("Q33_Earnings_Persistence", "AC22_Accrual_Volatility")
ALL_F <- c(LOTTERY_CLUSTER, EARNINGS_CLUSTER)
W_LOTTERY <- 0.70; W_EARNINGS <- 0.30

sig_dates_all <- seq(as.Date("2001-07-01"), as.Date("2026-04-01"), by = "month")
cat(sprintf("[v4] Building 6-factor composite across %d sig_dates\n", length(sig_dates_all)))

pd27 <- as.data.table(read_parquet(file.path(STAGE_DIR, "alpha_scores_pd27_burn0m.parquet")))
pd27_ret <- pd27[, .(Date, Ticker, Ret_1m)]; setkey(pd27_ret, Date, Ticker)

result_list <- list()
for (i in seq_along(sig_dates_all)) {
  sd <- sig_dates_all[i]
  if (i %% 24 == 0) cat(sprintf("[v4] %s (%d/%d)\n", sd, i, length(sig_dates_all)))
  fdt <- tryCatch(load_month_factors(sd, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) next
  fdt <- fdt[Factor_Name %in% ALL_F]
  if (nrow(fdt) == 0) next
  wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  lot_cols <- intersect(LOTTERY_CLUSTER, names(wide))
  earn_cols <- intersect(EARNINGS_CLUSTER, names(wide))
  if (length(lot_cols) < 2 || length(earn_cols) < 1) next
  wide[, lot_score := rowMeans(.SD, na.rm = TRUE), .SDcols = lot_cols]
  wide[, earn_score := rowMeans(.SD, na.rm = TRUE), .SDcols = earn_cols]
  for (col in c("lot_score","earn_score")) {
    mu <- mean(wide[[col]], na.rm=TRUE); sg <- sd(wide[[col]], na.rm=TRUE)
    if (!is.na(sg) && sg > 1e-9) wide[, (col) := (.SD[[1]] - mu)/sg, .SDcols = col]
  }
  wide[, alpha_v4_raw := W_LOTTERY * lot_score + W_EARNINGS * earn_score]
  mu <- mean(wide$alpha_v4_raw, na.rm=TRUE); sg <- sd(wide$alpha_v4_raw, na.rm=TRUE)
  if (!is.na(sg) && sg > 1e-9) wide[, alpha_v4 := (alpha_v4_raw - mu)/sg]
  result_list[[as.character(sd)]] <- data.table(
    Date = sd, Ticker = wide$Ticker, alpha_v4 = wide$alpha_v4,
    lot_score = wide$lot_score, earn_score = wide$earn_score
  )
}
alpha <- rbindlist(result_list, use.names=TRUE, fill=TRUE)
alpha <- merge(alpha, pd27_ret, by=c("Date","Ticker"), all.x=TRUE)
cat(sprintf("[v4] %d rows, %d dates\n", nrow(alpha), uniqueN(alpha$Date)))

# Diagnostics
ic_pd <- alpha[!is.na(Ret_1m) & !is.na(alpha_v4),
               .(rank_IC = suppressWarnings(cor(alpha_v4, Ret_1m, method="spearman")), N=.N), by=Date]
ic_pd <- ic_pd[!is.na(rank_IC)]
mean_IC <- mean(ic_pd$rank_IC); sd_IC <- sd(ic_pd$rank_IC)
ICIR <- mean_IC/sd_IC; t_naive <- mean_IC/(sd_IC/sqrt(nrow(ic_pd)))
ic_dm <- ic_pd$rank_IC - mean_IC; g0 <- mean(ic_dm^2); L <- 6; ac <- 0
for (h in 1:L) ac <- ac + 2*(1-h/(L+1))*mean(ic_dm[1:(length(ic_dm)-h)] * ic_dm[(h+1):length(ic_dm)])
nw_t <- mean_IC/sqrt((g0+ac)/nrow(ic_pd))
cat(sprintf("[v4] mean_IC=%.4f ICIR=%.4f t_NW=%.4f\n", mean_IC, ICIR, nw_t))

ic_pd[, period := fcase(Date < as.Date("2009-01-01"),"P1", Date < as.Date("2018-01-01"),"P2", default="P3")]
sub <- ic_pd[, .(IC=mean(rank_IC), n=.N), by=period]; print(sub)
min_max <- min(sub$IC)/max(sub$IC); sign_cons <- all(sign(sub$IC) == sign(sub$IC[1]))
cat(sprintf("[v4] Subperiod min_max=%.4f sign_cons=%s\n", min_max, sign_cons))

crisis_ranges <- list(c("2008-09-01","2009-03-01"),c("2011-08-01","2011-12-01"),
                       c("2015-06-01","2016-02-01"),c("2020-02-01","2020-04-01"),c("2022-05-01","2022-10-01"))
ic_pd[, regime := "normal"]
for (r in crisis_ranges) ic_pd[Date >= as.Date(r[1]) & Date <= as.Date(r[2]), regime := "crisis"]
reg <- ic_pd[, .(IC=mean(rank_IC), n=.N), by=regime]; print(reg)
crisis_IC <- reg[regime=="crisis", IC]; normal_IC <- reg[regime=="normal", IC]
ratio_cn <- crisis_IC/normal_IC; ax001 <- crisis_IC > 0 && ratio_cn > 1.0
cat(sprintf("[v4] crisis_IC=%.4f normal_IC=%.4f ratio=%.4f AX001=%s\n", crisis_IC, normal_IC, ratio_cn, ax001))

# Cor vs PD27
pd27_s <- pd27[, .(Date, Ticker, pd27 = score_eff)]
cor_dt <- merge(alpha[, .(Date, Ticker, alpha_v4)], pd27_s, by=c("Date","Ticker"))
cor_pd <- cor_dt[!is.na(alpha_v4) & !is.na(pd27),
                 .(c = suppressWarnings(cor(alpha_v4, pd27, method="spearman")), N=.N), by=Date]
cor_pd <- cor_pd[!is.na(c) & N >= 30]
cor_mean <- mean(cor_pd$c); cor_ov <- with(cor_dt, suppressWarnings(cor(alpha_v4, pd27, method="spearman", use="pairwise.complete.obs")))
cat(sprintf("[v4] cor_overall=%.4f cor_per_date_mean=%.4f\n", cor_ov, cor_mean))

# DSR
N <- nrow(ic_pd)
g3 <- mean(((ic_pd$rank_IC - mean_IC)/sd_IC)^3); g4 <- mean(((ic_pd$rank_IC - mean_IC)/sd_IC)^4) - 3
sigma_sr <- sqrt((1 - g3*ICIR + g4/4*ICIR^2)/(N-1))
N_TRIALS <- 17
em1 <- qnorm(1-1/N_TRIALS); em2 <- qnorm(1-1/(N_TRIALS*exp(1))); ge <- 0.5772156649
E_max <- (em1*(1-ge) + em2*ge) * sigma_sr
DSR_z <- (ICIR - E_max)/sigma_sr
t_hlz <- sqrt(2*log(N_TRIALS)) + 0.55
cat(sprintf("[v4] DSR_z=%.4f HLZ_thr=%.4f\n", DSR_z, t_hlz))

write_parquet(alpha, OUT_PARQUET)
diag <- list(
  pd_phase = "PD35_v4_lottery_70_earnings_30_crisis_robust",
  lottery_cluster = LOTTERY_CLUSTER, earnings_cluster = EARNINGS_CLUSTER,
  weights = list(lottery = W_LOTTERY, earnings = W_EARNINGS),
  n_rows = nrow(alpha), n_dates = uniqueN(alpha$Date),
  diagnostics = list(mean_IC=mean_IC, sd_IC=sd_IC, ICIR=ICIR, t_NW_lag6=nw_t, t_naive=t_naive),
  subperiod = list(P1=sub[period=="P1",IC], P2=sub[period=="P2",IC], P3=sub[period=="P3",IC],
                   min_max_ratio=min_max, sign_consistency=sign_cons),
  ax001_v2 = list(crisis_IC=crisis_IC, normal_IC=normal_IC, ratio=ratio_cn,
                  n_crisis=reg[regime=="crisis",n], n_normal=reg[regime=="normal",n], pass=ax001),
  cor_vs_pd27 = list(cor_overall=cor_ov, cor_per_date_mean=cor_mean, pass_lt_0_30=abs(cor_mean)<0.30),
  dsr = list(method="BLP_2014_IC_based", DSR_z=DSR_z, sigma_sr=sigma_sr, E_max_null=E_max,
             N_TRIALS=N_TRIALS, t_hlz_threshold=t_hlz, pass=DSR_z > 0.5),
  gates_8 = c(rank_IC=mean_IC>0.02, ICIR=ICIR>0.20, t_NW=nw_t>3.0, hlz=nw_t>t_hlz,
              dsr=DSR_z>0.5, subperiod=min_max>0.50 && sign_cons,
              cor_pd27=abs(cor_mean)<0.30, ax001_v2=ax001)
)
writeLines(toJSON(diag, pretty=TRUE, auto_unbox=TRUE, na="string"), OUT_JSON)
cat(sprintf("\n[v4 SUMMARY] gates=%d/8\n", sum(diag$gates_8)))
print(diag$gates_8)
cat("[v4] Complete.\n")
