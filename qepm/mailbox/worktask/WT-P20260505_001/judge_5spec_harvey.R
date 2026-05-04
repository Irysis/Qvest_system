# Judge 5-spec Harvey gate (Charter v1.4 §10 Gate 8)
# Specs: CAPM (forge done) / Carhart-3 (FF3) / Carhart-4 (FF3+WML) / FF5 / FF6
# t_NW (Newey-West lag=3) per Harvey-Liu-Zhu (2016)
# Lockbox harness exception applied — Judge audit role.

suppressMessages({
  library(arrow); library(data.table); library(sandwich); library(lmtest)
})

WT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT_DIR <- file.path(WT, "qepm/mailbox/worktask/WT-P20260505_001")
ff <- as.data.table(read_parquet(file.path(WT, ".cache/kr_factor_returns_v2.parquet")))
ff[, Date := as.Date(Date)]
ff[, ym := format(Date, "%Y-%m")]

# Strategies + period_returns paths
strategies <- c("S0_baseline", "S1_KR10y_only", "S2_TSMOM_only", "S3_Hybrid_70_15_15", "S4_Hybrid_50_25_25")

# Helper: NW t-stat for alpha
nw_t <- function(model, lag=3) {
  tryCatch({
    se <- sqrt(diag(NeweyWest(model, lag=lag, prewhite=FALSE)))
    coefs <- coef(model)
    names(se)[1] <- "Intercept"
    list(alpha_monthly = coefs[1],
         alpha_t_NW = coefs[1] / se[1],
         alpha_t_OLS = summary(model)$coefficients[1,3],
         R2 = summary(model)$r.squared,
         n = nobs(model))
  }, error = function(e) list(alpha_monthly=NA, alpha_t_NW=NA, alpha_t_OLS=NA, R2=NA, n=NA, err=conditionMessage(e)))
}

results <- list()
for (strat in strategies) {
  pr_path <- file.path(OUT_DIR, "output", strat, "03_period_returns.csv")
  if (!file.exists(pr_path)) { results[[strat]] <- list(error="period_returns missing"); next }
  pr <- fread(pr_path)
  pr[, date := as.Date(date)]
  pr[, ym := format(date, "%Y-%m")]

  # Merge ret_net with FF factors by month
  ff_m <- copy(ff)
  ff_m[, ym := format(Date, "%Y-%m")]
  m <- merge(pr[, .(ym, ret_net)], ff_m[, .(ym, MKT, SMB, HML, WML, RMW, CMA, RF)], by="ym")
  m <- m[!is.na(MKT) & !is.na(ret_net)]
  m[, ER := ret_net - RF]  # excess return

  # CAPM: ER ~ MKT
  m_capm <- m[!is.na(MKT)]
  capm <- lm(ER ~ MKT, data=m_capm)
  capm_res <- nw_t(capm, lag=3)

  # Carhart-3 (FF3): ER ~ MKT + SMB + HML
  m_ff3 <- m[!is.na(SMB) & !is.na(HML)]
  ff3 <- lm(ER ~ MKT + SMB + HML, data=m_ff3)
  ff3_res <- nw_t(ff3, lag=3)

  # Carhart-4: ER ~ MKT + SMB + HML + WML
  m_c4 <- m[!is.na(SMB) & !is.na(HML) & !is.na(WML)]
  c4 <- lm(ER ~ MKT + SMB + HML + WML, data=m_c4)
  c4_res <- nw_t(c4, lag=3)

  # FF5: ER ~ MKT + SMB + HML + RMW + CMA
  m_ff5 <- m[!is.na(SMB) & !is.na(HML) & !is.na(RMW) & !is.na(CMA)]
  ff5 <- lm(ER ~ MKT + SMB + HML + RMW + CMA, data=m_ff5)
  ff5_res <- nw_t(ff5, lag=3)

  # FF6: ER ~ MKT + SMB + HML + RMW + CMA + WML
  m_ff6 <- m[!is.na(SMB) & !is.na(HML) & !is.na(RMW) & !is.na(CMA) & !is.na(WML)]
  ff6 <- lm(ER ~ MKT + SMB + HML + RMW + CMA + WML, data=m_ff6)
  ff6_res <- nw_t(ff6, lag=3)

  # Compute α_annualized = (1 + α_monthly)^12 - 1
  ann <- function(am) ifelse(is.na(am), NA, (1 + am)^12 - 1)

  results[[strat]] <- list(
    strategy = strat,
    n_obs_full = nrow(m_capm),
    n_obs_ff3 = nrow(m_ff3),
    n_obs_c4 = nrow(m_c4),
    n_obs_ff5 = nrow(m_ff5),
    n_obs_ff6 = nrow(m_ff6),
    CAPM = list(
      alpha_monthly = round(capm_res$alpha_monthly, 4),
      alpha_annualized = round(ann(capm_res$alpha_monthly), 4),
      alpha_t_OLS = round(capm_res$alpha_t_OLS, 4),
      alpha_t_NW_lag3 = round(capm_res$alpha_t_NW, 4),
      R2 = round(capm_res$R2, 4)
    ),
    Carhart3_FF3 = list(
      alpha_monthly = round(ff3_res$alpha_monthly, 4),
      alpha_annualized = round(ann(ff3_res$alpha_monthly), 4),
      alpha_t_OLS = round(ff3_res$alpha_t_OLS, 4),
      alpha_t_NW_lag3 = round(ff3_res$alpha_t_NW, 4),
      R2 = round(ff3_res$R2, 4)
    ),
    Carhart4 = list(
      alpha_monthly = round(c4_res$alpha_monthly, 4),
      alpha_annualized = round(ann(c4_res$alpha_monthly), 4),
      alpha_t_OLS = round(c4_res$alpha_t_OLS, 4),
      alpha_t_NW_lag3 = round(c4_res$alpha_t_NW, 4),
      R2 = round(c4_res$R2, 4)
    ),
    FF5 = list(
      alpha_monthly = round(ff5_res$alpha_monthly, 4),
      alpha_annualized = round(ann(ff5_res$alpha_monthly), 4),
      alpha_t_OLS = round(ff5_res$alpha_t_OLS, 4),
      alpha_t_NW_lag3 = round(ff5_res$alpha_t_NW, 4),
      R2 = round(ff5_res$R2, 4)
    ),
    FF6 = list(
      alpha_monthly = round(ff6_res$alpha_monthly, 4),
      alpha_annualized = round(ann(ff6_res$alpha_monthly), 4),
      alpha_t_OLS = round(ff6_res$alpha_t_OLS, 4),
      alpha_t_NW_lag3 = round(ff6_res$alpha_t_NW, 4),
      R2 = round(ff6_res$R2, 4)
    )
  )
}

# Summary table
summary_dt <- rbindlist(lapply(strategies, function(s) {
  r <- results[[s]]
  data.table(
    strategy = s,
    n = r$n_obs_full,
    CAPM_alpha_ann = r$CAPM$alpha_annualized,
    CAPM_t_NW = r$CAPM$alpha_t_NW_lag3,
    Carhart3_alpha_ann = r$Carhart3_FF3$alpha_annualized,
    Carhart3_t_NW = r$Carhart3_FF3$alpha_t_NW_lag3,
    Carhart4_alpha_ann = r$Carhart4$alpha_annualized,
    Carhart4_t_NW = r$Carhart4$alpha_t_NW_lag3,
    FF5_alpha_ann = r$FF5$alpha_annualized,
    FF5_t_NW = r$FF5$alpha_t_NW_lag3,
    FF6_alpha_ann = r$FF6$alpha_annualized,
    FF6_t_NW = r$FF6$alpha_t_NW_lag3
  )
}))
fwrite(summary_dt, file.path(OUT_DIR, "judge_5spec_summary.csv"))

# Harvey gate decision
# Harvey-Liu-Zhu (2016) t > 3.0 hurdle for KR equity
HARVEY_T_FLOOR <- 3.0
gate_pass <- function(spec) {
  s3 <- results[["S3_Hybrid_70_15_15"]]
  t_val <- s3[[spec]]$alpha_t_NW_lag3
  ifelse(is.na(t_val), FALSE, abs(t_val) > HARVEY_T_FLOOR)
}
gate <- list(
  CAPM = gate_pass("CAPM"),
  Carhart3 = gate_pass("Carhart3_FF3"),
  Carhart4 = gate_pass("Carhart4"),
  FF5 = gate_pass("FF5"),
  FF6 = gate_pass("FF6")
)
gate$all_5_pass <- all(unlist(gate))
gate$pass_count <- sum(unlist(gate[1:5]))
gate$harvey_t_floor <- HARVEY_T_FLOOR

out <- list(
  task_id = "WT-P20260505_001",
  scope = "Judge 5-spec Harvey gate (Charter v1.4 §10 Gate 8)",
  reference = "Harvey-Liu-Zhu (2016 RFS) t > 3.0 multi-testing hurdle",
  primary_strategy = "S3_Hybrid_70_15_15",
  per_strategy = results,
  summary_csv = "judge_5spec_summary.csv",
  harvey_gate_S3 = gate,
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  generated_by = "Judge (lockbox harness exception)"
)

jsonlite::write_json(out, file.path(OUT_DIR, "judge_5spec_harvey.json"),
                     auto_unbox=TRUE, pretty=TRUE, na="null")

cat("=== Judge 5-spec Harvey Summary ===\n")
print(summary_dt)
cat("\n=== S3 Harvey Gate ===\n")
str(gate)
cat("\nWritten:", file.path(OUT_DIR, "judge_5spec_harvey.json"), "\n")
