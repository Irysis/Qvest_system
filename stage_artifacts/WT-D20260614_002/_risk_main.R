# ============================================================================
# WT-D20260614_002 RISK — main: Omega/B/D -> Sigma, tail, MDD decomp, stress,
#   crowding, style, incumbent joint-cov.  Role: risk-research ONLY.
# ============================================================================
suppressMessages({ library(data.table); library(arrow); library(jsonlite); library(PerformanceAnalytics) })
Sys.setenv(CLAUDE_PROJECT_DIR = getwd(), QM_ROOT = getwd())
source("02_Infrastructure/config.R")

FACTORS <- c("D01_IdioVol","D02_Beta","M07_IndMom","M01_Mom_12_1","M05_Trended_Mom",
             "Q01_GPA","Q04_Piotroski_F","Q09_CFOA","Q07_Earnings_Stability","V01_BM")
AXIS <- c(D01_IdioVol="defense", D02_Beta="defense",
          M07_IndMom="momentum", M01_Mom_12_1="momentum", M05_Trended_Mom="momentum",
          Q01_GPA="quality", Q04_Piotroski_F="quality", Q09_CFOA="quality",
          Q07_Earnings_Stability="quality", V01_BM="value")
OUT <- "stage_artifacts/WT-D20260614_002"
RES <- new.env()

# ---------------------------------------------------------------------------
# 0. inputs
# ---------------------------------------------------------------------------
panel <- as.data.table(read_parquet(file.path(OUT, "_factor_return_panel.parquet")))
setorder(panel, ym)
Fret <- as.matrix(panel[, ..FACTORS])           # 256 x 10 factor returns (monthly)
rownames(Fret) <- panel$ym
alpha_pkg <- fromJSON("qepm/mailbox/worktask/WT-D20260614_002/alpha_package.json", simplifyVector = TRUE)
alpha_vec <- unlist(alpha_pkg$alpha_vector)      # 60 names
names_alpha <- names(alpha_vec)

# exposure snapshot (as-of) for the alpha names: wide z-scores
ai <- readRDS(file.path(OUT, "_alpha_intermediate.rds"))
wide <- ai$wide
B_all <- as.matrix(wide[, ..FACTORS]); rownames(B_all) <- wide$Ticker
B <- B_all[names_alpha, , drop = FALSE]          # 60 x 10 exposures
# impute remaining NA exposures with 0 (factor-neutral) — coverage already >=6 of 10
B[!is.finite(B)] <- 0

# ---------------------------------------------------------------------------
# 1. Omega — Ledoit-Wolf shrinkage of factor covariance (method-shopping log)
# ---------------------------------------------------------------------------
# annualize: monthly -> *12
ledoit_wolf <- function(X) {
  # Ledoit-Wolf (2004) shrinkage to constant-correlation target
  n <- nrow(X); p <- ncol(X)
  Xc <- scale(X, center = TRUE, scale = FALSE)
  S <- crossprod(Xc) / n
  s <- sqrt(diag(S))
  R <- S / (s %o% s)
  rbar <- (sum(R) - p) / (p * (p - 1))
  F <- rbar * (s %o% s); diag(F) <- diag(S)       # constant-corr target
  # pi: sum of asymptotic variances of S entries
  Y <- Xc^2
  piMat <- crossprod(Y) / n - S^2
  pihat <- sum(piMat)
  # rho: diag + off-diag covariance of target
  rho_diag <- sum(diag(piMat))
  term <- matrix(0, p, p)
  for (i in 1:p) for (j in 1:p) {
    if (i == j) next
    term[i,j] <- ( (s[j]/s[i]) * (crossprod(Xc[,i]^2, Xc[,j])/n - S[i,i]*S[i,j]) +
                   (s[i]/s[j]) * (crossprod(Xc[,j]^2, Xc[,i])/n - S[j,j]*S[i,j]) ) / 2
  }
  rho_off <- rbar * sum(term)
  rhohat <- rho_diag + rho_off
  # gamma: misfit
  gammahat <- sum((F - S)^2)
  kappa <- (pihat - rhohat) / gammahat
  delta <- max(0, min(1, kappa / n))
  Sig <- delta * F + (1 - delta) * S
  list(S = S, F = F, shrink = delta, Sigma = Sig)
}

S_sample <- (crossprod(scale(Fret, scale = FALSE)) / nrow(Fret)) * 12
lw <- ledoit_wolf(Fret)
Omega <- lw$Sigma * 12                            # annualized factor cov (shrunk)
shrink_delta <- lw$shrink

cond_sample <- kappa_num <- function(M) { ev <- eigen(M, symmetric = TRUE, only.values = TRUE)$values; max(ev)/min(ev[ev>0]) }
cn_sample <- kappa_num(S_sample)
cn_omega  <- kappa_num(Omega)

# method shopping log
method_log <- list(
  list(name = "sample",       cond = round(cn_sample, 2), selected = FALSE,
       note = "256 obs x 10 factors; well-posed but noisy off-diagonals"),
  list(name = "ledoit_wolf",  cond = round(cn_omega, 2),  selected = TRUE,
       note = sprintf("constant-corr target, shrink delta=%.3f", shrink_delta))
)

# factor correlation matrix (for crowding/warnings)
Fcorr <- cov2cor(Omega)

# ---------------------------------------------------------------------------
# 2. D — specific (idiosyncratic) variance per name
# ---------------------------------------------------------------------------
# Build per-name monthly total return series (in-sample window) and regress on
# factor returns to get residual variance. Use RAWDATA monthly returns.
rd <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Close")))
rd[, Date := as.Date(Date)]; rd <- rd[Ticker %in% names_alpha & !is.na(Close)]
rd[, ym := format(Date, "%Y%m")]
setorder(rd, Ticker, Date)
mer <- rd[, .SD[.N], by = .(Ticker, ym)]
setorder(mer, Ticker, ym)
mer[, mret := Close/shift(Close) - 1, by = Ticker]
mer <- mer[ym %in% panel$ym & is.finite(mret)]
stock_wide <- dcast(mer, ym ~ Ticker, value.var = "mret")
setkey(stock_wide, ym); stock_wide <- stock_wide[panel$ym]   # align to panel months

# factor-model residual variance per name: r_i,t = B_i . F_t + eps
D_vec <- setNames(rep(NA_real_, length(names_alpha)), names_alpha)
fac_var_explained <- setNames(rep(NA_real_, length(names_alpha)), names_alpha)
for (tk in names_alpha) {
  ri <- stock_wide[[tk]]
  ok <- is.finite(ri)
  if (sum(ok) < 24) {                  # too short: fall back to cross-sec median later
    D_vec[tk] <- NA_real_; next
  }
  pred <- as.numeric(Fret[ok, , drop=FALSE] %*% B[tk, ])    # B fixed (as-of) exposure proxy
  resid <- ri[ok] - pred
  D_vec[tk] <- var(resid) * 12                  # annualized specific var
  fac_var_explained[tk] <- max(0, 1 - var(resid)/var(ri[ok]))
}
# impute missing D with cross-sectional median
med_D <- median(D_vec, na.rm = TRUE)
D_vec[!is.finite(D_vec)] <- med_D
# floor specific risk to avoid degenerate (min 5% annual vol)
D_vec <- pmax(D_vec, 0.05^2)

# ---------------------------------------------------------------------------
# 3. Sigma = B Omega B' + diag(D)
# ---------------------------------------------------------------------------
Sigma <- B %*% Omega %*% t(B) + diag(D_vec)
Sigma <- (Sigma + t(Sigma)) / 2                  # symmetrize
ev <- eigen(Sigma, symmetric = TRUE, only.values = TRUE)$values
psd_ok <- min(ev) > -1e-10
cn_sigma <- max(ev) / min(ev[ev > 0])
# eigen-floor if needed
if (!psd_ok || cn_sigma > 500) {
  evd <- eigen(Sigma, symmetric = TRUE)
  fl <- max(evd$values) / 500
  evals <- pmax(evd$values, fl)
  Sigma <- evd$vectors %*% diag(evals) %*% t(evd$vectors)
  Sigma <- (Sigma + t(Sigma))/2
  ev <- eigen(Sigma, symmetric = TRUE, only.values=TRUE)$values
  cn_sigma <- max(ev)/min(ev[ev>0]); psd_ok <- min(ev) > -1e-10
  sigma_floored <- TRUE
} else sigma_floored <- FALSE

# ---------------------------------------------------------------------------
# 4. Common-risk decomposition (EW long portfolio of 60 names as risk reference)
# ---------------------------------------------------------------------------
w_ew <- setNames(rep(1/length(names_alpha), length(names_alpha)), names_alpha)
port_total_var <- as.numeric(t(w_ew) %*% Sigma %*% w_ew)
# factor contribution: w'B Omega B'w ; specific: w'D w
fac_contrib_var <- as.numeric(t(w_ew) %*% (B %*% Omega %*% t(B)) %*% w_ew)
spec_contrib_var <- as.numeric(t(w_ew) %*% diag(D_vec) %*% w_ew)
# per-factor variance share via portfolio factor exposure xp = B' w
xp <- as.numeric(t(B) %*% w_ew); names(xp) <- FACTORS
# marginal factor variance contribution: xp_k * (Omega xp)_k
mfc <- xp * as.numeric(Omega %*% xp)
fac_share <- mfc / sum(mfc)
# axis-level aggregation
axis_share <- tapply(fac_share, AXIS[FACTORS], sum)
# market proxy: regress factor returns on BM to get market beta of EW port
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))[, .(Date=as.Date(Date), BM_Ret)]
bm[, ym := format(Date, "%Y%m")]
bmm <- bm[, .(bm_ret = prod(1+BM_Ret, na.rm=TRUE)-1), by=ym][ym %in% panel$ym]
setkey(bmm, ym); bmm <- bmm[panel$ym]
# EW port monthly return proxy = mean of available stock monthly returns
port_m <- rowMeans(as.matrix(stock_wide[, -1]), na.rm = TRUE)
mreg <- data.table(ym=panel$ym, port=port_m, bm=bmm$bm_ret)
mreg <- mreg[is.finite(port) & is.finite(bm)]
mfit <- lm(port ~ bm, data = mreg)
mkt_beta <- coef(mfit)[2]
mkt_var_share <- (mkt_beta^2 * var(mreg$bm)) / var(mreg$port)

RES$Omega <- Omega; RES$B <- B; RES$D_vec <- D_vec; RES$Sigma <- Sigma
RES$Fcorr <- Fcorr; RES$fac_share <- fac_share; RES$axis_share <- axis_share
RES$cn_sample <- cn_sample; RES$cn_omega <- cn_omega; RES$cn_sigma <- cn_sigma
RES$shrink_delta <- shrink_delta; RES$psd_ok <- psd_ok; RES$sigma_floored <- sigma_floored
RES$method_log <- method_log; RES$fac_contrib_var <- fac_contrib_var
RES$spec_contrib_var <- spec_contrib_var; RES$port_total_var <- port_total_var
RES$mkt_beta <- as.numeric(mkt_beta); RES$mkt_var_share <- as.numeric(mkt_var_share)
RES$fac_var_explained <- fac_var_explained; RES$xp <- xp
saveRDS(as.list(RES), file.path(OUT, "_risk_core.rds"))

cat(sprintf("[risk] cond: sample=%.1f omega=%.1f sigma=%.1f | LW shrink=%.3f | PSD=%s floored=%s\n",
            cn_sample, cn_omega, cn_sigma, shrink_delta, psd_ok, sigma_floored))
cat(sprintf("[risk] EW port: total ann vol=%.3f | factor var share=%.3f specific=%.3f\n",
            sqrt(port_total_var), fac_contrib_var/port_total_var, spec_contrib_var/port_total_var))
cat("[risk] market beta (port vs BM)=", round(mkt_beta,3), " market var share=", round(mkt_var_share,3), "\n")
cat("[risk] axis variance share:\n"); print(round(axis_share,4))
cat("[risk] per-factor variance share:\n"); print(round(sort(fac_share, decreasing=TRUE),4))
cat("[risk] factor corr |>0.7| pairs:\n")
fc <- Fcorr; fc[lower.tri(fc, diag=TRUE)] <- NA
idx <- which(abs(fc) > 0.7, arr.ind = TRUE)
if (nrow(idx)) for (i in seq_len(nrow(idx))) cat("   ", FACTORS[idx[i,1]],"~",FACTORS[idx[i,2]],"=",round(fc[idx[i,1],idx[i,2]],3),"\n") else cat("    none\n")
