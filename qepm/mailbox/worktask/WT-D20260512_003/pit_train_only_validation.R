# WT-D20260512_003 — REBUTTAL/REVISE evidence: PIT Train-only validation
# Codex Concern #1 (HIGH): Lockbox contamination — full sample 2004-2026 selection
# Train-only window: 2004-01 ~ 2023-12 (240m). Lockbox window: 2024-01 ~ 2026-04 (28m)
# Re-validate: hard constraints + IC/ICIR/Harvey/DSR strictly on Train data; Lockbox = sealed check only

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(sandwich); library(lmtest)
})
setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

panel <- as.data.table(read_parquet("stage_artifacts/WT_D20260512_003/candidate_panel.parquet"))
panel[, Date := as.Date(Date)]
p <- panel[!is.na(score_eff) & !is.na(R05_Tail_Risk) & !is.na(Ret_1m)]

# === Split ===
TRAIN_END <- as.Date("2023-12-01")
p_train <- p[Date <= TRAIN_END]
p_lockbox <- p[Date > TRAIN_END]

cat("[PIT-strict] Train rows:", nrow(p_train), "n_months:", uniqueN(p_train$Date), "\n")
cat("[PIT-strict] Lockbox rows:", nrow(p_lockbox), "n_months:", uniqueN(p_lockbox$Date), "\n")

# === Step 1: Re-run regime grid on TRAIN ONLY ===
test_scheme_train <- function(scheme, p_data) {
  pp <- copy(p_data)
  pp[, w_new := fcase(
    regime_state == "BULL", scheme$BULL,
    regime_state == "NORMAL", scheme$NORMAL,
    regime_state == "CAUTION", scheme$CAUTION,
    regime_state == "CRISIS", scheme$CRISIS,
    default = 0.0
  )]
  pp[, z_blend := (1 - w_new) * score_eff + w_new * R05_Tail_Risk]
  ic_dt <- pp[, .(ic = if (.N >= 5) cor(z_blend, Ret_1m, method="spearman") else NA_real_,
                   n = .N, regime = regime_state[1]),
               by = Date]
  ic_dt <- ic_dt[!is.na(ic)]
  regime_summary <- ic_dt[, .(mean_ic = mean(ic), sd_ic = sd(ic),
                               sr_proxy = mean(ic)/sd(ic)*sqrt(12),
                               n = .N), by = regime]
  overall <- ic_dt[, .(mean_ic = mean(ic), icir = mean(ic)/sd(ic)*sqrt(12), n = .N)]
  list(overall = overall, regime = regime_summary)
}

# Train-only grid search
b_grid <- c(0.05, 0.10)
n_grid <- c(0.05, 0.10)
k_grid <- c(0.30, 0.50, 0.70, 0.80)
c_grid <- c(0.30, 0.50, 0.70, 0.80)

train_grid <- list()
ii <- 0
for (b in b_grid) for (nn in n_grid) for (k in k_grid) for (cc in c_grid) {
  sch <- list(BULL=b, NORMAL=nn, CAUTION=k, CRISIS=cc)
  res <- test_scheme_train(sch, p_train)
  ii <- ii + 1
  train_grid[[ii]] <- data.table(
    BULL=b, NORMAL=nn, CAUTION=k, CRISIS=cc,
    icir = res$overall$icir,
    bull_sr  = res$regime[regime=="BULL", sr_proxy],
    normal_sr = res$regime[regime=="NORMAL", sr_proxy],
    caution_sr = res$regime[regime=="CAUTION", sr_proxy],
    crisis_sr = res$regime[regime=="CRISIS", sr_proxy],
    caution_ic = res$regime[regime=="CAUTION", mean_ic],
    crisis_ic = res$regime[regime=="CRISIS", mean_ic]
  )
}
tg <- rbindlist(train_grid)
tg[, stress_pass := caution_sr > 0 & crisis_sr > 0]
n_pass_train <- sum(tg$stress_pass)
cat("\n[Train-only] Schemes pass CAUTION+CRISIS SR>0:", n_pass_train, "/", nrow(tg), "\n")

setorder(tg, -icir)
cat("\n=== TOP 10 by ICIR (Train-only 2004-01 to 2023-12) ===\n")
print(tg[1:10, .(BULL, NORMAL, CAUTION, CRISIS, icir = round(icir, 3),
                  caution_sr = round(caution_sr, 3),
                  crisis_sr = round(crisis_sr, 3))])

setorder(tg[stress_pass == TRUE], -icir)
cat("\n=== TOP 5 stress-passing (CAUTION+CRISIS SR>0) (Train-only) ===\n")
print(tg[stress_pass == TRUE][1:5, .(BULL, NORMAL, CAUTION, CRISIS,
                                       icir = round(icir, 3),
                                       caution_sr = round(caution_sr, 3),
                                       crisis_sr = round(crisis_sr, 3))])

# === Step 2: Lockbox sealed test ===
# Use BEST Train-only scheme (top by ICIR among stress-passing)
best_train <- tg[stress_pass == TRUE][order(-icir)][1]
SCHEME_TRAIN <- list(BULL = best_train$BULL, NORMAL = best_train$NORMAL,
                      CAUTION = best_train$CAUTION, CRISIS = best_train$CRISIS)
cat("\n=== Best Train-only scheme ===\n")
cat("BULL=", SCHEME_TRAIN$BULL, " NORMAL=", SCHEME_TRAIN$NORMAL,
    " CAUTION=", SCHEME_TRAIN$CAUTION, " CRISIS=", SCHEME_TRAIN$CRISIS, "\n")

res_train <- test_scheme_train(SCHEME_TRAIN, p_train)
res_lockbox <- test_scheme_train(SCHEME_TRAIN, p_lockbox)

# Newey-West Train
ic_train <- p_train[, ic := NULL]  # dummy line; correct below

compute_nw <- function(p_data, scheme) {
  pp <- copy(p_data)
  pp[, w_new := fcase(
    regime_state == "BULL", scheme$BULL,
    regime_state == "NORMAL", scheme$NORMAL,
    regime_state == "CAUTION", scheme$CAUTION,
    regime_state == "CRISIS", scheme$CRISIS,
    default = 0.0
  )]
  pp[, z_blend := (1 - w_new) * score_eff + w_new * R05_Tail_Risk]
  ic_dt <- pp[, .(ic = if (.N >= 5) cor(z_blend, Ret_1m, method="spearman") else NA_real_),
               by = Date]
  ic_dt <- ic_dt[!is.na(ic)]
  T_ic <- nrow(ic_dt)
  if (T_ic < 20) return(list(T=T_ic, ic_mean=NA, ic_sd=NA, icir=NA, nw_t=NA, plain_t=NA))
  ic_mean <- mean(ic_dt$ic); ic_sd <- sd(ic_dt$ic)
  nw_lag <- floor(4 * (T_ic/100)^(2/9))
  fit <- lm(ic ~ 1, data = ic_dt)
  nw_se <- sqrt(NeweyWest(fit, lag = nw_lag, prewhite = FALSE)[1,1])
  nw_t <- coef(fit)[1] / nw_se
  plain_t <- ic_mean / (ic_sd / sqrt(T_ic))
  list(T=T_ic, ic_mean=ic_mean, ic_sd=ic_sd,
        icir=ic_mean/ic_sd*sqrt(12), nw_t=nw_t, plain_t=plain_t)
}

nw_train <- compute_nw(p_train, SCHEME_TRAIN)
nw_lockbox <- compute_nw(p_lockbox, SCHEME_TRAIN)

cat("\n=== Train period stats ===\n")
cat("T_ic:", nw_train$T, "IC mean:", round(nw_train$ic_mean, 5),
    "ICIR:", round(nw_train$icir, 3),
    "plain_t:", round(nw_train$plain_t, 3),
    "NW_t:", round(nw_train$nw_t, 3), "\n")
cat("\n=== Lockbox period stats (sealed) ===\n")
cat("T_ic:", nw_lockbox$T, "IC mean:", round(nw_lockbox$ic_mean, 5),
    "ICIR:", round(nw_lockbox$icir, 3),
    "plain_t:", round(nw_lockbox$plain_t, 3),
    "NW_t:", round(nw_lockbox$nw_t, 3), "\n")

cat("\n=== Regime summary on Train ===\n")
print(res_train$regime[order(regime)])
cat("\n=== Regime summary on Lockbox (sealed) ===\n")
print(res_lockbox$regime[order(regime)])

# === Step 3: HLZ deflation with FULL search space count ===
# True search count: 20 candidates + 256 grid combos + 5 buffer variants + 5 specs
# Use combined effective N
N_FULL <- 20 + 256 + 5 + 5  # = 286 trials
hlz_full_bonf <- qnorm(1 - 0.05 / (2 * N_FULL))
hlz_full_holm <- 3.0 + 0.5 * log(N_FULL)
cat("\n=== HLZ deflation with FULL search count ===\n")
cat("N_full:", N_FULL, "HLZ Bonf threshold:", round(hlz_full_bonf, 3),
    "Holm-like:", round(hlz_full_holm, 3), "\n")
cat("Train NW_t pass Bonf:", nw_train$nw_t > hlz_full_bonf, "\n")
cat("Train NW_t pass Holm:", nw_train$nw_t > hlz_full_holm, "\n")
cat("Lockbox NW_t pass Bonf:", abs(nw_lockbox$nw_t) > hlz_full_bonf, "\n")

# === Step 4: Effective search counted DSR ===
SR_threshold_full <- sqrt(2 * log(N_FULL)) / sqrt(nw_train$T)
SR_obs <- nw_train$ic_mean / nw_train$ic_sd
SR_var_proxy <- (1 - SR_obs * nw_train$ic_mean) / (nw_train$T - 1)
SR_var_proxy <- max(SR_var_proxy, 1e-6)
DSR_z_full <- (SR_obs - SR_threshold_full) / sqrt(SR_var_proxy)
cat("\n=== DSR with N_full=", N_FULL, "===\n")
cat("SR_obs:", round(SR_obs, 4), "SR_threshold (N=", N_FULL, "):", round(SR_threshold_full, 4), "\n")
cat("DSR-z:", round(DSR_z_full, 3), "DSR_pass:", DSR_z_full > 0, "\n")

saveRDS(list(
  scheme_train_best = SCHEME_TRAIN,
  train_grid = tg, n_pass_train = n_pass_train,
  train_stats = nw_train, lockbox_stats = nw_lockbox,
  train_regime = res_train$regime, lockbox_regime = res_lockbox$regime,
  N_full = N_FULL,
  hlz_full_bonf = hlz_full_bonf,
  DSR_z_full = DSR_z_full
), "stage_artifacts/WT_D20260512_003/pit_train_only.rds")
fwrite(tg, "stage_artifacts/WT_D20260512_003/train_only_grid.csv")
cat("\n[saved] pit_train_only.rds + train_only_grid.csv\n")
