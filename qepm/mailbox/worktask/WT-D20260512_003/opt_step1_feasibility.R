#==============================================================================
# WT-D20260512_003 Optimizer Step 1 — Feasibility Check
#
# 도훈 mandate 2026-05-12 Session 80
# Hard constraints:
#   max_names = 20, weight_bounds = [0, 0.20], long_only, Σw = 1,
#   universe = KOSPI200 ∪ KOSDAQ150, liquidity_min = 5e7 KRW (request.json),
#   cost_model_version = v2.3_kr_retail_15bps, PIT C1~C15
#
# 본 Step:
#   (a) alpha_package + risk_package + request.json 로드
#   (b) sig_dates schedule 268m 정합 확인 (alpha_emission.rds vs risk_package.refs)
#   (c) Universe overlap (alpha 238 ∩ risk 237 ∩ raw eligible) per sig_date
#   (d) Hard constraint pre-feasibility:
#         - min_names_per_sig: 5 (절대 최소 for stable optimization)
#         - max_names: 20 hard
#         - weight_bounds[0, 0.20]: 20 names × 0.20 = 4.0 → feasible (1.0 sum)
#         - liquidity 5e7 KRW 20d avg t-1 → sig_date 별 eligible filter
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(BASE_DIR)

cat("============================================================\n")
cat("[OPT-Step1] Feasibility Check — WT-D20260512_003\n")
cat("============================================================\n\n")

# ─── Load inputs ────────────────────────────────────────────────
WT <- "WT-D20260512_003"
mailbox <- file.path("qepm/mailbox/worktask", WT)
stage <- file.path("stage_artifacts", "WT_D20260512_003")

alpha_pkg <- fromJSON(file.path(mailbox, "alpha_package.json"))
risk_pkg  <- fromJSON(file.path(mailbox, "risk_package.json"))
request   <- fromJSON(file.path(mailbox, "request.json"))

cat(sprintf("alpha as_of: %s | risk as_of: %s | request as_of: %s\n",
            alpha_pkg$as_of_date, risk_pkg$as_of_date, request$as_of_date))

# ─── alpha_emission.rds (panel 268m) ───────────────────────────
ae <- readRDS(file.path(stage, "alpha_emission.rds"))
asc <- ae$alpha_scores  # data.table : 79835 × 11
asc <- asc[!is.na(z_blend_composite)]
cat(sprintf("alpha_scores (z_blend valid): %s rows | %d unique Dates | %d unique Tickers\n",
            format(nrow(asc), big.mark=","),
            length(unique(asc$Date)),
            length(unique(asc$Ticker))))

sig_dates_alpha <- sort(unique(asc$Date))
cat(sprintf("sig_dates range: %s ~ %s (n=%d)\n",
            as.character(min(sig_dates_alpha)),
            as.character(max(sig_dates_alpha)),
            length(sig_dates_alpha)))

# ─── Risk covariance (factor_model_8F) ─────────────────────────
cov_long <- as.data.table(read_parquet(file.path(stage, "covariance.parquet")))
risk_universe <- sort(unique(c(cov_long$i, cov_long$j)))
cat(sprintf("risk universe: %d assets\n", length(risk_universe)))

# Build risk cov matrix (237 × 237)
cov_long_full <- rbind(cov_long, cov_long[i != j, .(i = j, j = i, sigma_ij, estimator)])
cov_long_full <- unique(cov_long_full, by = c("i", "j"))
Sigma <- dcast(cov_long_full, i ~ j, value.var = "sigma_ij", fill = 0)
ix_rn <- Sigma$i
Sigma <- as.matrix(Sigma[, -1])
rownames(Sigma) <- ix_rn
Sigma <- Sigma[risk_universe, risk_universe]
cat(sprintf("Sigma dim: %d × %d | PSD? %s | cond: %.2f\n",
            nrow(Sigma), ncol(Sigma),
            all(eigen(Sigma, symmetric=TRUE, only.values=TRUE)$values > 0),
            kappa(Sigma)))

# ─── Universe overlap per sig_date ──────────────────────────────
universe_overlap <- asc[, .(n_z_valid = .N,
                             n_in_risk = sum(Ticker %in% risk_universe)),
                         by = Date]
cat("\n[Universe overlap per sig_date]\n")
cat(sprintf("  Mean n_z_valid: %.1f | Min: %d | Max: %d\n",
            mean(universe_overlap$n_z_valid),
            min(universe_overlap$n_z_valid),
            max(universe_overlap$n_z_valid)))
cat(sprintf("  Mean n_in_risk: %.1f | Min: %d | Max: %d\n",
            mean(universe_overlap$n_in_risk),
            min(universe_overlap$n_in_risk),
            max(universe_overlap$n_in_risk)))

# ─── Hard constraint pre-check ──────────────────────────────────
MAX_NAMES <- 20L
MIN_NAMES <- 5L  # 절대 최소 (Optimizer는 가능하면 20 채움)
UB <- 0.20
LB <- 0.0
TARGET_SUM <- 1.0

# Hard feasibility: MAX_NAMES × UB = 20 × 0.20 = 4.0 >= 1.0 → feasible
# MIN_NAMES × UB = 5 × 0.20 = 1.0 = 1.0 → exact lower bound feasible (요 0.20 cap)
cat(sprintf("\n[Hard constraint pre-check]\n"))
cat(sprintf("  MAX_NAMES × UB = %d × %.2f = %.2f >= TARGET_SUM %.2f → %s\n",
            MAX_NAMES, UB, MAX_NAMES * UB, TARGET_SUM,
            if (MAX_NAMES * UB >= TARGET_SUM) "FEASIBLE" else "INFEASIBLE"))
cat(sprintf("  MIN_NAMES × UB = %d × %.2f = %.2f >= TARGET_SUM %.2f → %s\n",
            MIN_NAMES, UB, MIN_NAMES * UB, TARGET_SUM,
            if (MIN_NAMES * UB >= TARGET_SUM) "FEASIBLE" else "INFEASIBLE"))

# ─── Liquidity pre-filter check (sample 5 sig_dates) ────────────
raw <- as.data.table(read_parquet(".cache/rawdata.parquet",
                                   col_select = c("Date", "Ticker", "Close", "Vol")))
raw[, TradingAmt := Close * Vol]
setkey(raw, Date, Ticker)

# Sample 5 sig_dates
sample_sds <- sig_dates_alpha[c(1L, 67L, 134L, 200L, length(sig_dates_alpha))]
LIQ_THRESHOLD <- 5e7  # request.json universe_definition.liquidity_min_won_20d_avg

cat("\n[Liquidity pre-filter at sample 5 sig_dates]\n")
for (sd in sample_sds) {
  liq_start <- sd - 30L
  liq_data <- raw[Date >= liq_start & Date < sd,
                   .(AvgTA = mean(TradingAmt, na.rm=TRUE)), by = Ticker]
  liquid_tk <- liq_data[AvgTA >= LIQ_THRESHOLD, Ticker]
  panel_t <- asc[Date == sd]
  panel_t_liq <- panel_t[Ticker %in% liquid_tk]
  cat(sprintf("  %s | universe %d → liquid %d → z_valid %d\n",
              as.character(sd),
              nrow(panel_t),
              sum(panel_t$Ticker %in% liquid_tk),
              sum(panel_t_liq$Ticker %in% risk_universe)))
}

# ─── Save feasibility report ────────────────────────────────────
feas <- list(
  task_id = WT,
  agent = "optimizer-research",
  step = 1,
  as_of_date = alpha_pkg$as_of_date,
  hard_constraints = list(
    max_names = MAX_NAMES,
    min_names_optimizer_target = 20L,
    min_names_floor = MIN_NAMES,
    weight_bounds = c(LB, UB),
    target_sum = TARGET_SUM,
    liquidity_threshold_KRW = LIQ_THRESHOLD,
    long_only = TRUE,
    cost_model_version = "v2.3_kr_retail_15bps",
    commission_each_side_bps = 15
  ),
  feasibility = list(
    universe_total_unique = length(unique(asc$Ticker)),
    risk_universe_n = length(risk_universe),
    sig_dates_n = length(sig_dates_alpha),
    sig_dates_first = as.character(min(sig_dates_alpha)),
    sig_dates_last = as.character(max(sig_dates_alpha)),
    mean_n_z_valid = mean(universe_overlap$n_z_valid),
    mean_n_in_risk = mean(universe_overlap$n_in_risk),
    feasibility_pre_check_pass = (MAX_NAMES * UB >= TARGET_SUM) &&
                                  (MIN_NAMES * UB >= TARGET_SUM),
    infeasibility_report = NULL
  ),
  inputs = list(
    alpha_package = file.path(mailbox, "alpha_package.json"),
    risk_package = file.path(mailbox, "risk_package.json"),
    alpha_emission = file.path(stage, "alpha_emission.rds"),
    covariance = file.path(stage, "covariance.parquet"),
    rawdata = ".cache/rawdata.parquet"
  )
)

write_json(feas, file.path(stage, "opt_step1_feasibility.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
cat(sprintf("\n[OPT-Step1] Saved: %s\n", file.path(stage, "opt_step1_feasibility.json")))
cat("[OPT-Step1] DONE\n")
