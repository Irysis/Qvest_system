# ============================================================================
# Risk Research — WT-D20260822_007 (FQ-246 NP1, argmax hard-selection)
# Σ = BΩB' + D + tail (EVT-GPD) + stress + crowding + style/sector HHI
# PIT: all data strictly < sig_date 2026-07-01. Universe as-of 2026-06-30.
# Role boundary: alpha_vector received unmodified. No weights, no MVO.
# Context: round_verdict = CONFIG_SCOPED_NEGATIVE (Part B emit arm not capital-
#   eligible). Risk diagnostics produced for pipeline completeness only.
# ============================================================================
suppressMessages({library(arrow); library(dplyr); library(data.table); library(jsonlite)})
set.seed(20260822L)
QM   <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(QM)
WTID <- "WT-D20260822_007"
SIG  <- as.Date("2026-07-01")   # decision anchor; use only Date < SIG
OUT  <- file.path("stage_artifacts", WTID)

# ---- 1. alpha_vector (received unmodified) ---------------------------------
ap  <- fromJSON(file.path("qepm/mailbox/worktask", WTID, "alpha_package.json"))
av  <- ap$alpha_vector
tick <- names(av); avec <- as.numeric(unlist(av))
names(avec) <- tick
n_alpha <- length(tick)
cat(sprintf("[1] alpha_vector: %d names\n", n_alpha))

# ---- 2. returns panel (PIT: Date < SIG) ------------------------------------
r  <- open_dataset(".cache/RAWDATA.parquet")
dt <- r %>% filter(Date < SIG, Date >= as.Date("2005-01-01"),
                   Ticker %in% tick) %>%
      select(Date, Ticker, Ret) %>% collect() %>% as.data.table()
setkey(dt, Date, Ticker)
snap <- r %>% filter(Date < SIG) %>%
        select(Date, Ticker, Sector, Size, K200, KQ150) %>%
        filter(Ticker %in% tick) %>% collect() %>% as.data.table()
snap <- snap[, .SD[which.max(Date)], by = Ticker]  # last obs per ticker < SIG
cat(sprintf("[2] returns rows=%d  range=%s..%s  snap names=%d\n",
            nrow(dt), as.character(min(dt$Date)), as.character(max(dt$Date)), nrow(snap)))

# ---- daily wide matrix (last ~756 trading days ≈ 3y for estimation) --------
all_dates <- sort(unique(dt$Date))
est_dates <- tail(all_dates, 756L)
w <- dcast(dt[Date %in% est_dates], Date ~ Ticker, value.var = "Ret")
mat <- as.matrix(w[, -1, drop = FALSE]); rownames(mat) <- as.character(w$Date)
good <- colSums(!is.na(mat)) >= 250L
mat  <- mat[, good, drop = FALSE]
keep_tick <- colnames(mat)
n_keep <- length(keep_tick)
cat(sprintf("[2b] est window=%d days  names w/ >=250 obs=%d (dropped %d)\n",
            length(est_dates), n_keep, n_alpha - n_keep))
mat[is.na(mat)] <- 0
avec_k <- avec[keep_tick]

# ============================================================================
# STEP 1: Exposure matrix B  (Market + Sector + Size + Style)
# ============================================================================
snap_k <- snap[match(keep_tick, Ticker)]
est_min <- min(est_dates)
bm <- r %>% filter(Date < SIG) %>% filter(Date >= est_min) %>%
      select(Date, BM_Ret) %>% distinct() %>% collect() %>% as.data.table()
bm <- bm[match(as.Date(rownames(mat)), Date)]
bm_ret <- bm$BM_Ret; bm_ret[is.na(bm_ret)] <- 0
beta_raw <- apply(mat, 2, function(x) {
  v <- var(bm_ret); if (v <= 0) return(1)
  cov(x, bm_ret) / v
})
beta_blume <- 0.67 * beta_raw + 0.33 * 1.0   # Blume shrink toward 1
sz <- log(pmax(snap_k$Size, 1))
size_z <- as.numeric(scale(sz)); size_z[is.na(size_z)] <- 0
mom_raw <- apply(mat, 2, function(x) { n<-length(x); mean(x[1:max(1,n-21)]) })
mom_z   <- as.numeric(scale(mom_raw)); mom_z[is.na(mom_z)] <- 0
vol_raw <- apply(mat, 2, sd)
lowvol_z <- as.numeric(scale(-vol_raw)); lowvol_z[is.na(lowvol_z)] <- 0
sec <- snap_k$Sector; sec[is.na(sec)] <- "UNKNOWN"
sec_levels <- sort(unique(sec))
Bsec <- model.matrix(~ 0 + factor(sec, levels = sec_levels))
colnames(Bsec) <- paste0("SEC_", seq_along(sec_levels))

B <- cbind(Market = beta_blume, Size = size_z, Mom = mom_z, LowVol = lowvol_z, Bsec)
rownames(B) <- keep_tick
n_fac <- ncol(B)
cat(sprintf("[STEP1] B: %d names x %d factors (Market,Size,Mom,LowVol + %d sectors)\n",
            n_keep, n_fac, length(sec_levels)))

# ============================================================================
# STEP 2: Factor return time series (cross-sectional OLS per day) -> Ω
# ============================================================================
f_ts <- matrix(NA_real_, nrow = nrow(mat), ncol = n_fac)
colnames(f_ts) <- colnames(B)
BtB_inv <- tryCatch(solve(t(B) %*% B + diag(1e-8, n_fac)), error = function(e) MASS::ginv(t(B) %*% B))
hat <- BtB_inv %*% t(B)
resid_mat <- matrix(NA_real_, nrow = nrow(mat), ncol = n_keep)
for (i in seq_len(nrow(mat))) {
  y <- mat[i, ]
  ft <- as.numeric(hat %*% y)
  f_ts[i, ] <- ft
  resid_mat[i, ] <- y - as.numeric(B %*% ft)
}
Omega_sample <- cov(f_ts)
mu_o  <- mean(diag(Omega_sample))
p_o <- n_fac; n_o <- nrow(f_ts)
rho_o <- min(((n_o-2)/n_o*sum(diag(Omega_sample)^2)+sum(Omega_sample)^2) /
             ((n_o+2)*(sum(Omega_sample^2)-sum(diag(Omega_sample)^2)/p_o)), 1)
Omega <- (1 - rho_o) * Omega_sample + rho_o * diag(diag(Omega_sample))  # shrink toward diag
cat(sprintf("[STEP2] Omega %dx%d  LW rho=%.3f\n", n_fac, n_fac, rho_o))

# ============================================================================
# STEP 3: Specific risk D (idiosyncratic variance) + eigen floor
# ============================================================================
spec_var <- apply(resid_mat, 2, var)
spec_floor <- quantile(spec_var[spec_var > 0], 0.05, na.rm = TRUE)
spec_var <- pmax(spec_var, spec_floor)
names(spec_var) <- keep_tick
D <- diag(spec_var)
cat(sprintf("[STEP3] specific var: median=%.2e  floor=%.2e\n", median(spec_var), spec_floor))

# ============================================================================
# STEP 4: Security covariance Σ = BΩB' + D   (daily), annualize x252
# ============================================================================
Sigma_d <- B %*% Omega %*% t(B) + D
Sigma_d <- (Sigma_d + t(Sigma_d)) / 2
# SA-fix: cross-sectional factor model over-attributes total variance. Anchor
# variance LEVEL to empirical while preserving factor-implied CORRELATION.
ev_precal <- eigen(Sigma_d, symmetric=TRUE, only.values=TRUE)$values
cond_precal_raw <- max(ev_precal)/min(ev_precal[ev_precal>0])
raw_var_d <- apply(mat, 2, var)
mod_var_d <- diag(Sigma_d)
scale_i   <- sqrt(pmax(raw_var_d, 1e-12) / pmax(mod_var_d, 1e-12))
Sigma_d   <- diag(scale_i) %*% Sigma_d %*% diag(scale_i)
Sigma_d   <- (Sigma_d + t(Sigma_d)) / 2
Sigma   <- Sigma_d * 252
ev <- eigen(Sigma, symmetric = TRUE, only.values = TRUE)$values
cond_before <- max(ev) / min(ev[ev > 0])
psd_min_ev  <- min(ev)
COND_TARGET <- 400   # target < 500 so RF-R2 is cleared, not just met
cond_precal_note <- cond_precal_raw
cond_before <- max(ev) / min(ev[ev > 0])
psd_before  <- min(ev) > -1e-10
E <- eigen(Sigma, symmetric = TRUE)
fl <- max(E$values) / COND_TARGET
Ev_reg <- pmax(E$values, fl)
Sigma <- E$vectors %*% diag(Ev_reg) %*% t(E$vectors); Sigma <- (Sigma + t(Sigma))/2
E2 <- eigen(Sigma, symmetric = TRUE, only.values = TRUE)$values
cond_after <- max(E2) / min(E2[E2 > 0])
psd_ok <- min(E2) > -1e-10
Sigma_reg <- Sigma
cond_reg  <- cond_after
shrink_used   <- TRUE
shrink_method <- "eigen_floor_cond400 (RF-R2 response, applied AFTER diagonal variance calibration)"
vol_raw_ann <- apply(mat, 2, sd) * sqrt(252)
vol_mod_ann <- sqrt(diag(Sigma))
vol_inflation_median <- median(vol_mod_ann / vol_raw_ann)
vol_inflation_reg <- vol_inflation_median
cat(sprintf("[STEP4] cond precal(BΩB'+D)=%.0f  postcal=%.0f  after_floor=%.0f  PSD=%s\n",
            cond_precal_note, cond_before, cond_after, psd_ok))
cat(sprintf("[STEP4-SA] vol-level preservation (post-cal+floor): median(model/raw)=%.3f (1.0=faithful)\n",
            vol_inflation_median))

# factor vs specific variance share on the CALIBRATED Σ
aw <- abs(avec_k); aw <- aw / sum(aw)
BOB_d <- B %*% Omega %*% t(B)
scale_i2 <- sqrt(pmax(apply(mat,2,var),1e-12) / pmax(diag(BOB_d + D),1e-12))
BOB_cal <- (diag(scale_i2) %*% BOB_d %*% diag(scale_i2)) * 252
D_cal   <- (diag(scale_i2) %*% D %*% diag(scale_i2)) * 252
var_total    <- as.numeric(t(aw) %*% Sigma %*% aw)
var_factor   <- as.numeric(t(aw) %*% BOB_cal %*% aw)
var_specific <- as.numeric(t(aw) %*% D_cal %*% aw)
factor_share   <- var_factor / (var_factor + var_specific)
specific_share <- var_specific / (var_factor + var_specific)
cat(sprintf("[STEP4b] factor var share=%.3f  specific=%.3f\n", factor_share, specific_share))

Bcal <- diag(scale_i2) %*% B
xB <- as.numeric(t(aw) %*% Bcal)
fexp_contrib <- (xB * as.numeric(Omega %*% xB)) * 252
names(fexp_contrib) <- colnames(B)
sec_idx <- grep("^SEC_", names(fexp_contrib))
top_risks <- c(fexp_contrib[c("Market","Size","Mom","LowVol")],
               Sector = sum(fexp_contrib[sec_idx]),
               Specific = var_specific)
top_risks_pct <- top_risks / sum(abs(top_risks))
top_risks_pct <- sort(top_risks_pct, decreasing = TRUE)
cat("[STEP4c] top common risks (%):\n"); print(round(top_risks_pct*100,1))

saveRDS(list(Sigma=Sigma, Sigma_reg=Sigma_reg, B=B, Omega=Omega, spec_var=spec_var, keep_tick=keep_tick,
             avec_k=avec_k, aw=aw, resid_mat=resid_mat, mat=mat, est_dates=est_dates,
             bm_ret=bm_ret, snap_k=snap_k, top_risks_pct=top_risks_pct,
             factor_share=factor_share, specific_share=specific_share,
             cond_before=cond_before, cond_after=cond_after, cond_reg=cond_reg, psd_ok=psd_ok,
             cond_precal=cond_precal_note, psd_before=psd_before,
             shrink_used=shrink_used, shrink_method=shrink_method,
             vol_inflation_median=vol_inflation_median, vol_inflation_reg=vol_inflation_reg,
             cond_target=COND_TARGET,
             beta_blume=beta_blume, vol_raw=vol_raw),
        file.path(OUT, "risk_core.rds"))
cat("[SAVE] risk_core.rds\n")
