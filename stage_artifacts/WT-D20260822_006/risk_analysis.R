# ============================================================================
# Risk Research — WT-D20260822_006 (FQ-246)
# Σ = BΩB' + D + tail (EVT-GPD) + stress + crowding + style/sector HHI
# PIT: all data strictly < sig_date 2026-07-01. Universe as-of 2026-06-30.
# Role boundary: alpha_vector received unmodified. No weights, no MVO.
# ============================================================================
suppressMessages({library(arrow); library(dplyr); library(data.table); library(jsonlite)})
set.seed(20260822L)
QM   <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(QM)
WTID <- "WT-D20260822_006"
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
# static attrs as-of last pre-SIG trading day
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
# keep names with >=250 valid daily obs in window
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
# Market beta (Blume-adjusted) vs BM_Ret over est window
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
# Size exposure = ln(Size) z-score
sz <- log(pmax(snap_k$Size, 1))
size_z <- as.numeric(scale(sz)); size_z[is.na(size_z)] <- 0
# Style proxies from returns (PIT: within est window)
# Momentum: 12-1m cumret proxy = mean daily ret over window ex last 21d
mom_raw <- apply(mat, 2, function(x) { n<-length(x); mean(x[1:max(1,n-21)]) })
mom_z   <- as.numeric(scale(mom_raw)); mom_z[is.na(mom_z)] <- 0
# LowVol: negative of daily vol
vol_raw <- apply(mat, 2, sd)
lowvol_z <- as.numeric(scale(-vol_raw)); lowvol_z[is.na(lowvol_z)] <- 0
# Sector dummies (27 KR sectors)
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
# STEP 2: Factor return time series (cross-sectional WLS per day) -> Ω
# ============================================================================
# Daily cross-sectional regression r_it = B_i' f_t + e_it  (OLS, no intercept: Market carries level)
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
# Ω: factor covariance (Ledoit-Wolf shrink toward diagonal, since some sector factors sparse)
Omega_sample <- cov(f_ts)
mu_o  <- mean(diag(Omega_sample))
p_o <- n_fac; n_o <- nrow(f_ts)
rho_o <- min(((n_o-2)/n_o*sum(diag(Omega_sample)^2)+sum(Omega_sample)^2) /
             ((n_o+2)*(sum(Omega_sample^2)-sum(diag(Omega_sample)^2)/p_o)), 1)
Omega <- (1 - rho_o) * Omega_sample + rho_o * diag(diag(Omega_sample))  # shrink toward diag (keep factor vols)
cat(sprintf("[STEP2] Omega %dx%d  LW rho=%.3f\n", n_fac, n_fac, rho_o))

# ============================================================================
# STEP 3: Specific risk D (idiosyncratic variance) + eigen floor
# ============================================================================
spec_var <- apply(resid_mat, 2, var)
# floor at 5th pct to avoid degenerate zeros
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
# ★SA-fix (self-adversarial ACCEPT): cross-sectional factor model over-attributes total
# variance (Var(fitted)+Var(resid) = 1.72x Var(raw) — temporal Cov(fitted,resid)≠0 since
# daily OLS orthogonality is cross-sectional not temporal). Barra-style risk models accept
# the CORRELATION structure from the factor model but anchor VARIANCE levels to empirical.
# Diagonal-preserving calibration: rescale each name so diag(Σ)=realized total var, keeping
# the factor-implied correlation matrix intact.
ev_precal <- eigen(Sigma_d, symmetric=TRUE, only.values=TRUE)$values
cond_precal_raw <- max(ev_precal)/min(ev_precal[ev_precal>0])   # BΩB'+D before calibration
raw_var_d <- apply(mat, 2, var)                     # realized daily total var per name
mod_var_d <- diag(Sigma_d)
scale_i   <- sqrt(pmax(raw_var_d, 1e-12) / pmax(mod_var_d, 1e-12))  # per-name vol rescale
Sigma_d   <- diag(scale_i) %*% Sigma_d %*% diag(scale_i)            # preserves corr, fixes var
Sigma_d   <- (Sigma_d + t(Sigma_d)) / 2
Sigma   <- Sigma_d * 252
# condition number
ev <- eigen(Sigma, symmetric = TRUE, only.values = TRUE)$values
cond_before <- max(ev) / min(ev[ev > 0])
psd_min_ev  <- min(ev)
# eigen floor if ill-conditioned or near-singular
# ★SA decision (self-adversarial ACCEPT, two findings):
# (1) The cross-sectional factor model over-attributes variance (Var(fitted)+Var(resid)=
#     1.72x Var(raw)), fixed above by diagonal-preserving calibration (vol level -> 1.00x).
#     Calibration keeps the factor-implied CORRELATION but anchors VARIANCE to empirical.
# (2) Calibration raised cond to ~3640 (>500) -> RF-R2 genuinely fires. Contract mandates
#     shrinkage re-estimation when cond>500. So the PRIMARY Σ IS eigen-floored to cond=500
#     (mild — only touches the smallest, noise-dominated specific directions; vol level
#     preserved at ~1.0 because the floor is far below the dominant Market eigenvalue).
COND_TARGET <- 400   # target < 500 so RF-R2 (cond>500 after shrinkage) is cleared, not just met
cond_precal_note <- cond_precal_raw        # BΩB'+D BEFORE variance calibration
cond_before <- max(ev) / min(ev[ev > 0])   # AFTER calibration, BEFORE floor
psd_before  <- min(ev) > -1e-10
# eigen-floor to cond<=500 (RF-R2 response)
E <- eigen(Sigma, symmetric = TRUE)
fl <- max(E$values) / COND_TARGET
Ev_reg <- pmax(E$values, fl)
Sigma <- E$vectors %*% diag(Ev_reg) %*% t(E$vectors); Sigma <- (Sigma + t(Sigma))/2
E2 <- eigen(Sigma, symmetric = TRUE, only.values = TRUE)$values
cond_after <- max(E2) / min(E2[E2 > 0])
psd_ok <- min(E2) > -1e-10
Sigma_reg <- Sigma   # primary == regularized after RF-R2 response
cond_reg  <- cond_after
shrink_used   <- TRUE
shrink_method <- "eigen_floor_cond500 (RF-R2 response, applied AFTER diagonal variance calibration)"
vol_raw_ann <- apply(mat, 2, sd) * sqrt(252)
vol_mod_ann <- sqrt(diag(Sigma))
vol_inflation_median <- median(vol_mod_ann / vol_raw_ann)
vol_inflation_reg <- vol_inflation_median
cat(sprintf("[STEP4] cond precal(BΩB'+D)=%.0f  postcal=%.0f  after_floor=%.0f  PSD=%s\n",
            cond_precal_note, cond_before, cond_after, psd_ok))
cat(sprintf("[STEP4-SA] vol-level preservation (post-calibration+floor): median(model/raw)=%.3f (1.0=faithful)\n",
            vol_inflation_median))

# factor vs specific variance share on the CALIBRATED Σ (consistent decomposition)
aw <- abs(avec_k); aw <- aw / sum(aw)
# rebuild calibrated factor/specific blocks: apply same per-name scale to BΩB' and D
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

# top common risks: per-factor variance contribution to alpha-weighted portfolio.
# Use calibrated scale: effective exposure = scale_i2 * B, so per-factor contribution
# is computed on the calibrated factor block for consistency with factor_share.
Bcal <- diag(scale_i2) %*% B
xB <- as.numeric(t(aw) %*% Bcal)           # calibrated portfolio factor exposure
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
