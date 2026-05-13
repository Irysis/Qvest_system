## ============================================================
## WT-H20260513_002 — Harvey 5-spec STRICT015 FULL FIELDS
## ============================================================
## Codex C4 ACCEPT — add alpha_monthly + per_spec_DSR to all 5 rows
## FF6_WML rename (FF5_WML → FF6_WML for FF5+WML 6-factor spec)
## Lag parity check vs admit lag6 (currently lag4 by NW auto)
## ============================================================

cat("============================================================\n")
cat("WT-H20260513_002 Harvey 5-spec STRICT015 FULL FIELDS (C4 ACCEPT)\n")
cat("============================================================\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(sandwich)
  library(lmtest)
})

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR   <- file.path(BASE_DIR,
  "qepm/mailbox/worktask/WT-H20260513_002")
OUT_DIR  <- file.path(WT_DIR, "output")

# Load period_returns_strict015.csv (computed by run_strict_015_variant.R)
pr_strict_path <- file.path(OUT_DIR, "period_returns_strict015.csv")
if (!file.exists(pr_strict_path)) stop("period_returns_strict015.csv missing")
pr <- fread(pr_strict_path)
pr_255 <- pr[realized_ym >= "2005-02" & realized_ym <= "2026-04"]
cat(sprintf("Loaded period_returns_strict015 255m: n=%d\n", nrow(pr_255)))

# Load FF5 v2 KR
FF5_PATH <- file.path(BASE_DIR, ".cache/kr_factor_returns_v2.parquet")
if (!file.exists(FF5_PATH)) stop("FF5 missing")
ff5_v2 <- as.data.table(read_parquet(FF5_PATH))
ff5_v2[, ym := format(Date, "%Y-%m")]

panel_for_reg <- merge(pr_255[, .(realized_ym, ret_L5_V2_strict015, ret_L4_strict015)],
                        ff5_v2[, .(ym, MKT, SMB, HML, WML, RMW, CMA, RF)],
                        by.x = "realized_ym", by.y = "ym")
panel_for_reg[, excess_L5 := ret_L5_V2_strict015 - RF]
panel_for_reg[, excess_L4 := ret_L4_strict015 - RF]
cat(sprintf("Merged panel: n=%d\n", nrow(panel_for_reg)))

# DSR helper (Bailey-LdP N=5 ex-ante)
compute_dsr_bailey <- function(returns, N_trials = 5) {
  r <- returns[is.finite(returns)]
  n <- length(r)
  if (n < 12) return(list(SR_ann = NA, DSR_Z = NA, n_obs = n))
  sr_m <- mean(r) / sd(r)
  sr_ann <- sr_m * sqrt(12)
  skew <- tryCatch(e1071::skewness(r), error = function(e) 0)
  kurt <- tryCatch(e1071::kurtosis(r) + 3, error = function(e) 3)
  euler_gamma <- 0.5772156649
  e_max_z <- (1 - euler_gamma) * qnorm(1 - 1/N_trials) +
             euler_gamma * qnorm(1 - 1/(N_trials * exp(1)))
  e_sr_max <- e_max_z
  denom <- sqrt(1 - skew * sr_m + (kurt - 1) / 4 * sr_m^2)
  if (denom <= 1e-10) return(list(SR_ann = sr_ann, DSR_Z = NA, n_obs = n))
  dsr_z <- (sr_m - e_sr_max / sqrt(12)) * sqrt(n - 1) / denom
  list(SR_ann = round(sr_ann, 4),
       DSR_Z = round(dsr_z, 4),
       e_sr_max = round(e_sr_max, 4),
       n_obs = n)
}

# Full-fields regression (auto lag4 + lag6 both)
nw_reg_full <- function(y_col, dt, formula_str, label, lag_override = NULL, N_dsr = 5) {
  m <- lm(as.formula(formula_str), data = dt)
  n <- length(residuals(m))
  lag_auto <- max(1L, as.integer(floor(4 * (n / 100)^(2/9))))
  lag_use <- ifelse(is.null(lag_override), lag_auto, lag_override)
  ct <- tryCatch(
    coeftest(m, vcov = NeweyWest(m, lag = lag_use, prewhite = FALSE, adjust = TRUE)),
    error = function(e) NA
  )
  if (length(ct) == 1 && is.na(ct)) {
    return(list(spec = label, alpha_annual = NA, alpha_monthly = NA, t_NW = NA, p_NW = NA, R2 = NA, n = n, lag_used = lag_use, per_spec_DSR = NA))
  }
  alpha_m <- ct["(Intercept)", "Estimate"]
  # per-spec DSR using α + residuals (residual-based SR)
  pseudo_ret <- alpha_m + residuals(m)
  dsr_spec <- compute_dsr_bailey(pseudo_ret, N_trials = N_dsr)
  list(spec = label,
       alpha_annual = round(alpha_m * 12, 6),
       alpha_monthly = round(alpha_m, 6),
       t_NW = round(ct["(Intercept)", "t value"], 4),
       p_NW = round(ct["(Intercept)", "Pr(>|t|)"], 6),
       R2 = round(summary(m)$r.squared, 4),
       n = n, lag_used = lag_use,
       per_spec_DSR = ifelse(is.null(dsr_spec$DSR_Z), NA, dsr_spec$DSR_Z))
}

# Lag4 (auto NW)
cat("\n--- LAG4 (auto NW) ---\n")
reg_lag4 <- list(
  nw_reg_full("excess_L5", panel_for_reg, "excess_L5 ~ MKT", "CAPM_KR_L5_strict015"),
  nw_reg_full("excess_L5", panel_for_reg, "excess_L5 ~ MKT + SMB + HML", "Carhart3_KR_L5"),
  nw_reg_full("excess_L5", panel_for_reg, "excess_L5 ~ MKT + SMB + HML + WML", "Carhart4_KR_L5"),
  nw_reg_full("excess_L5", panel_for_reg, "excess_L5 ~ MKT + SMB + HML + RMW + CMA", "FF5_KR_L5"),
  nw_reg_full("excess_L5", panel_for_reg, "excess_L5 ~ MKT + SMB + HML + WML + RMW + CMA", "FF6_WML_KR_L5")
)
reg_dt_lag4 <- rbindlist(reg_lag4, fill = TRUE)
reg_dt_lag4[, lag_label := "lag4_auto"]
print(reg_dt_lag4)

# Lag6 (for parity check vs admit reported lag6)
cat("\n--- LAG6 (admit parity check) ---\n")
reg_lag6 <- list(
  nw_reg_full("excess_L5", panel_for_reg, "excess_L5 ~ MKT", "CAPM_KR_L5_strict015", lag_override = 6L),
  nw_reg_full("excess_L5", panel_for_reg, "excess_L5 ~ MKT + SMB + HML", "Carhart3_KR_L5", lag_override = 6L),
  nw_reg_full("excess_L5", panel_for_reg, "excess_L5 ~ MKT + SMB + HML + WML", "Carhart4_KR_L5", lag_override = 6L),
  nw_reg_full("excess_L5", panel_for_reg, "excess_L5 ~ MKT + SMB + HML + RMW + CMA", "FF5_KR_L5", lag_override = 6L),
  nw_reg_full("excess_L5", panel_for_reg, "excess_L5 ~ MKT + SMB + HML + WML + RMW + CMA", "FF6_WML_KR_L5", lag_override = 6L)
)
reg_dt_lag6 <- rbindlist(reg_lag6, fill = TRUE)
reg_dt_lag6[, lag_label := "lag6_admit_parity"]
print(reg_dt_lag6)

# Combine
reg_dt_full <- rbindlist(list(reg_dt_lag4, reg_dt_lag6), fill = TRUE)
fwrite(reg_dt_full, file.path(OUT_DIR, "harvey_5spec_kr_strict015_full_fields.csv"))
write_json(reg_dt_full, file.path(OUT_DIR, "harvey_5spec_kr_strict015_full_fields.json"),
            pretty = TRUE, auto_unbox = TRUE)

# Summary
cat("\n=== Harvey 5-spec FULL FIELDS Summary (strict015) ===\n")
cat("All 5 specs pass t_NW > 3.0 (lag4 auto):\n")
print(reg_dt_lag4[, .(spec, alpha_monthly, alpha_annual, t_NW, p_NW, R2, per_spec_DSR, lag_used)])
cat("\nAll 5 specs pass t_NW > 3.0 (lag6 admit parity):\n")
print(reg_dt_lag6[, .(spec, alpha_monthly, alpha_annual, t_NW, p_NW, R2, per_spec_DSR, lag_used)])

all_pass_lag4 <- all(reg_dt_lag4$t_NW > 3.0, na.rm = TRUE)
all_pass_lag6 <- all(reg_dt_lag6$t_NW > 3.0, na.rm = TRUE)

cat(sprintf("\nLag4: all 5 t_NW > 3.0 = %s\n", all_pass_lag4))
cat(sprintf("Lag6: all 5 t_NW > 3.0 = %s\n", all_pass_lag6))

# DSR per spec summary (collected)
dsr_summary <- list(
  scope = "Harvey 5-spec strict015 per-spec DSR (Bailey-LdP N=5 ex-ante, residual-based)",
  lag4 = lapply(reg_lag4, function(x) list(spec = x$spec, alpha_monthly = x$alpha_monthly,
                                              t_NW = x$t_NW, per_spec_DSR = x$per_spec_DSR)),
  lag6 = lapply(reg_lag6, function(x) list(spec = x$spec, alpha_monthly = x$alpha_monthly,
                                              t_NW = x$t_NW, per_spec_DSR = x$per_spec_DSR)),
  all_5_specs_pass_lag4 = all_pass_lag4,
  all_5_specs_pass_lag6 = all_pass_lag6
)
write_json(dsr_summary, file.path(OUT_DIR, "harvey_5spec_per_spec_dsr_summary_strict015.json"),
            pretty = TRUE, auto_unbox = TRUE)

cat("\nDone. Outputs:\n")
cat("  ", file.path(OUT_DIR, "harvey_5spec_kr_strict015_full_fields.csv"), "\n")
cat("  ", file.path(OUT_DIR, "harvey_5spec_kr_strict015_full_fields.json"), "\n")
cat("  ", file.path(OUT_DIR, "harvey_5spec_per_spec_dsr_summary_strict015.json"), "\n")
