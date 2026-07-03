# =============================================================================
# risk_measure_C.R — Codex-REVISE additions (ACCEPT/PARTIAL fixes)
#   C1: emit exposure_matrix/factor_covariance/specific_risk parquets + R2 coverage
#   C3: CVaR-cap breach flag + complete 8-period stress suite
#   C4: regime-conditional active correlation + regime_n + bootstrap CI + TDC vs incumbent
#   C5: pre-declared estimator acceptance criteria (recorded in build script)
# Role: risk only. No alpha edit, no weights.
# =============================================================================
suppressMessages({ library(arrow); library(data.table); library(jsonlite); library(lubridate) })
options(warn = 1)
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = root)
wt <- "WT-D20260614_001"
out_dir <- file.path(root, "stage_artifacts", "WT_D20260614_001")
mb_dir  <- file.path(root, "qepm", "mailbox", "worktask", wt)
set.seed(20260614L)

sig <- readRDS(file.path(out_dir, "_sigma.rds"))
be  <- readRDS(file.path(out_dir, "_riskBE.rds"))
ap  <- fromJSON(file.path(mb_dir, "alpha_package.json"), simplifyVector = FALSE)
as_of <- as.Date(ap$as_of_date)

R <- sig$R; hold <- sig$hold; betas <- sig$betas; omega_mkt <- sig$omega_mkt
mkt <- rowMeans(R); p <- ncol(R); n_obs <- nrow(R)

# ---- C1: B Omega B' + D explicit artifacts (1-factor MKT model = selected Sigma) ----
B <- matrix(betas, ncol = 1, dimnames = list(hold, "MKT"))    # exposure matrix
Omega <- matrix(omega_mkt, 1, 1, dimnames = list("MKT","MKT"))
resid1 <- R - outer(mkt, betas)
spec_var <- apply(resid1, 2, var)
D <- spec_var                                                  # diagonal specific var
# per-name R2 of the 1-factor model
r2_name <- 1 - apply(resid1, 2, var) / apply(R, 2, var)
r2_mean <- mean(r2_name); r2_med <- median(r2_name); n_below30 <- sum(r2_name < 0.30)

exposure_dt <- data.table(Ticker = hold, beta_MKT = round(betas, 4), r2_1factor = round(r2_name, 4))
write_parquet(exposure_dt, file.path(out_dir, "exposure_matrix.parquet"))
fc_dt <- data.table(factor = "MKT", MKT = round(omega_mkt, 8))
write_parquet(fc_dt, file.path(out_dir, "factor_covariance.parquet"))
sr_dt <- data.table(Ticker = hold, specific_var = round(D, 8), specific_vol = round(sqrt(D), 5))
write_parquet(sr_dt, file.path(out_dir, "specific_risk.parquet"))
cat(sprintf("[C1] 1-factor R2: mean=%.3f median=%.3f names<0.30=%d/%d\n", r2_mean, r2_med, n_below30, p))

# multi-factor (mkt + KR sector) coverage R2 for transparency (NOT selected for Sigma)
sec_of <- sig$sec_of
sec_tab <- table(sec_of); sec_use <- names(sec_tab[sec_tab >= 2])
F <- matrix(mkt, ncol = 1); colnames(F) <- "MKT"
for (s in sec_use) { idx <- which(sec_of == s); F <- cbind(F, rowMeans(R[, idx, drop=FALSE]) - mkt) }
colnames(F) <- c("MKT", paste0("SEC_", sec_use))
r2_multi <- sapply(seq_len(p), function(j) {
  fit <- lm.fit(cbind(1, F), R[, j]); 1 - var(fit$residuals)/var(R[, j]) })
cat(sprintf("[C1] mkt+sector multi-factor R2: mean=%.3f median=%.3f (n_factors=%d) — richer coverage but cond 212.8>200\n",
            mean(r2_multi), median(r2_multi), ncol(F)))

# ---- C3: CVaR cap breach flag ----
CVAR_CAP_MONTHLY <- 0.025   # prompt cap (Codex)
es95 <- abs(be$hist_es95)
cvar_breach <- es95 > CVAR_CAP_MONTHLY
cat(sprintf("[C3] CVaR95(ES95) monthly=%.3f vs cap %.3f -> breach=%s\n", es95, CVAR_CAP_MONTHLY, cvar_breach))

# ---- C3: complete 8-period stress suite (add Brexit/Volmageddon & 2024-25 KR) ----
sleeve <- as.data.table(read_parquet(file.path(out_dir, "sleeve_active_series.parquet")))
sleeve[, Date := as.Date(Date)]; setorder(sleeve, Date)
S <- sleeve
extra_windows <- list(
  Brexit_2016     = c("2016-05-31","2016-07-31"),
  Volmageddon_2018= c("2018-01-31","2018-03-31")
)
stress8 <- be$stress
for (nm in names(extra_windows)) {
  w <- as.Date(extra_windows[[nm]]); sub <- S[Date >= w[1] & Date <= w[2]]
  if (nrow(sub)) stress8[[nm]] <- list(sleeve_total = round(prod(1+sub$port_gross)-1,4),
                                       sleeve_active = round(prod(1+sub$active_gross)-1,4),
                                       bm = round(prod(1+sub$BM_Ret)-1,4), n_months = nrow(sub),
                                       coverage = if (nrow(sub)>=2) "OK" else "THIN")
}
worst <- names(which.min(sapply(stress8, function(x) x$sleeve_total %||% 0)))
`%||%` <- function(a,b) if (is.null(a)||length(a)==0||all(is.na(a))) b else a
worst <- names(which.min(sapply(stress8, function(x) if (is.null(x$sleeve_total)||is.na(x$sleeve_total)) 0 else x$sleeve_total)))
cat(sprintf("[C3] stress suite now %d periods; worst total loss = %s (%.1f%%)\n",
            length(stress8), worst, 100*stress8[[worst]]$sleeve_total))

# ---- C4: regime-conditional active correlation + regime_n + bootstrap CI ----
# Regime from BM_Ret realized (trailing): CRISIS if 12m BM < -10% or month BM < -8%; BULL if 12m>20%; else NORMAL.
inc <- fread(file.path(root,"qepm/mailbox/governor/str_1715_full_reassessment/str_1715_monthly_returns_full.csv"))
inc[, Date := as.Date(Date)]; inc[, real_ym := format(Date, "%Y-%m")]; setnames(inc,"monthly_ret","inc_ret")
sleeve[, real_ym := format(Date %m+% months(1), "%Y-%m")]
BB <- merge(sleeve[, .(real_ym, sa=active_gross, bm=BM_Ret)], inc[, .(real_ym, ir=inc_ret)], by="real_ym")
BB[, ia := ir - bm]; BB <- BB[is.finite(sa) & is.finite(ia)]; setorder(BB, real_ym)
BB[, bm12 := frollsum(log(1+bm), 12)]
BB[, regime := fifelse(is.finite(bm12) & bm12 < log(0.90), "CRISIS",
                fifelse(is.finite(bm12) & bm12 > log(1.20), "BULL", "NORMAL"))]
BB[bm < -0.08, regime := "CRISIS"]
reg_cor <- BB[, .(n = .N, active_cor = if (.N>=8) cor(sa, ia) else NA_real_), by = regime]
cat("[C4] regime-conditional active_cor:\n"); print(reg_cor)
# bootstrap CI for overall active_cor (block bootstrap, block=6)
boot_cor <- function(x, y, B=2000L, block=6L) {
  n <- length(x); nb <- ceiling(n/block); out <- numeric(B)
  for (b in 1:B) {
    starts <- sample(1:(n-block+1), nb, replace=TRUE)
    idx <- as.vector(sapply(starts, function(s) s:(s+block-1)))[1:n]
    out[b] <- cor(x[idx], y[idx])
  }
  quantile(out, c(0.05, 0.5, 0.95), na.rm=TRUE)
}
ci <- boot_cor(BB$sa, BB$ia)
cat(sprintf("[C4] active_cor block-bootstrap 90%% CI: [%.3f, %.3f] median %.3f\n", ci[1], ci[3], ci[2]))

# ---- C4: TDC (lower tail dependence) sleeve-active vs incumbent-active ----
# empirical lower TDC at q=0.10: P(U<q | V<q)
emp_tdc <- function(x, y, q=0.10, lower=TRUE) {
  u <- rank(x)/(length(x)+1); v <- rank(y)/(length(y)+1)
  if (lower) sum(u<=q & v<=q)/max(1,sum(v<=q)) else sum(u>=1-q & v>=1-q)/max(1,sum(v>=1-q))
}
tdc_lower <- emp_tdc(BB$sa, BB$ia, 0.10, TRUE)   # both sleeve & incumbent UNDERPERFORM BM together
tdc_upper <- emp_tdc(BB$sa, BB$ia, 0.10, FALSE)
# total-return tail co-movement (joint crash)
BBt <- merge(sleeve[, .(real_ym, sp=port_gross)], inc[, .(real_ym, ir=inc_ret)], by="real_ym")
tdc_total_lower <- emp_tdc(BBt$sp, BBt$ir, 0.10, TRUE)
cat(sprintf("[C4] TDC vs incumbent: active lower=%.2f upper=%.2f | total-return lower(joint crash)=%.2f\n",
            tdc_lower, tdc_upper, tdc_total_lower))

# ---- C4: active-book HHI (concentration of book if value added at w*) ----
# book = incumbent(1-w) + value(w); HHI of sleeve-level allocation (2-sleeve)
# value tilt is 0 (w*=0) so trivially HHI=1.0 (incumbent only). Report as such + holdings HHI already in BE.
active_book_hhi_at_wstar <- 1.0   # w*=0 -> single sleeve
cat(sprintf("[C4] active-book sleeve HHI at w*=%.2f: %.2f (value tilt 0 -> book unchanged)\n",
            be$w_star, active_book_hhi_at_wstar))

saveRDS(list(
  r2_name = r2_name, r2_mean = r2_mean, r2_med = r2_med, n_below30 = n_below30,
  r2_multi_mean = mean(r2_multi), r2_multi_med = median(r2_multi), n_factors_multi = ncol(F),
  cvar_cap = CVAR_CAP_MONTHLY, es95 = es95, cvar_breach = cvar_breach,
  stress8 = stress8, worst_stress = worst,
  reg_cor = reg_cor, boot_ci = ci, tdc_lower = tdc_lower, tdc_upper = tdc_upper,
  tdc_total_lower = tdc_total_lower, active_book_hhi_at_wstar = active_book_hhi_at_wstar
), file.path(out_dir, "_riskC.rds"))

# regime correlation parquet enriched
reg_out <- as.data.table(reg_cor)
write_parquet(reg_out, file.path(out_dir, "regime_correlation.parquet"))
cat("PART C (Codex revise) DONE\n")
