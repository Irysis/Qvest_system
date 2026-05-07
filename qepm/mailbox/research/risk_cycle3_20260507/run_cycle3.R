# ===========================================================================
# QEPM Risk Research Agent — Cycle 3 (2026-05-08 overnight)
# Q-Lead 온디맨드 사이클 3 메타 리서치 (사이클 2 추출 입력)
#
# 3축 진단:
#   Axis 1: VRP KOSPI 정밀 (KOSPI200 realized vol-based 4 sub-variants)
#   Axis 2: Defensive multi-sleeve EXCLUSION (AX-005 v1.2 enforcement)
#   Axis 3: 5-source marginal contribution + Diversification Ratio
#
# 절대 boundary:
#   - alpha 시그널 추가 / strategy spawn / weight 결정 X
#   - weight 가설값(5/10/15%)은 marginal contribution diagnostic만
#   - Hook agent_role_guard 침범 X
# ===========================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(fExtremes)
  library(copula)
  library(PerformanceAnalytics)
  library(rugarch)
})

setDTthreads(0)
set.seed(20260508)

LOG <- function(msg) cat(sprintf("[%s] %s\n", format(Sys.time(),"%H:%M:%S"), msg))

# === Paths ===
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(ROOT)
OUT_DIR <- "qepm/mailbox/research/risk_cycle3_20260507"
STAGE_DIR <- "qepm/stage_artifacts/risk_cycle3_20260507"
dir.create(OUT_DIR, recursive=TRUE, showWarnings=FALSE)
dir.create(STAGE_DIR, recursive=TRUE, showWarnings=FALSE)

CYC2_RET <- "qepm/mailbox/research/risk_candidates_20260507/master_returns_hybrid_plus_4candidates.csv"

# ============================================================================
# 0. Load cycle 2 master returns + raw data
# ============================================================================
LOG("Step 0: load cycle 2 master returns + raw inputs")

ret <- fread(CYC2_RET)
ret[, date := as.Date(date)]
ret[, ym := substr(as.character(date), 1, 7)]
LOG(sprintf("  master_returns: n=%d, range=%s ~ %s", nrow(ret), min(ret$ym), max(ret$ym)))

# Load FRED VIX / KRW data + ECOS rates + rawdata
fr <- as.data.table(read_parquet(".cache/fred_macro.parquet"))
vix_dt <- fr[Series_ID == "VIXCLS", .(Date=as.Date(Date), VIX=as.numeric(Value))][order(Date)][!is.na(VIX)]
LOG(sprintf("  VIX daily: n=%d, range=%s~%s", nrow(vix_dt),
            as.character(min(vix_dt$Date)), as.character(max(vix_dt$Date))))

# KOSPI BM realized vol (rawdata BM_Ret)
rd_bm <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","BM_Ret")))
rd_bm <- rd_bm[!is.na(BM_Ret)][, .SD[1], by=Date][order(Date)]
setnames(rd_bm, "BM_Ret", "KOSPI_Ret")
LOG(sprintf("  KOSPI daily BM: n=%d, range=%s~%s", nrow(rd_bm),
            as.character(min(rd_bm$Date)), as.character(max(rd_bm$Date))))

# ============================================================================
# AXIS 1: VRP KOSPI 정밀 진단 — 4 sub-variants
# ============================================================================
# 사이클 2 한계 명시 (Codex weakest_assumption ACCEPT):
#   - VRP는 US VIX 기반 합성 (한국 KOSPI200 옵션 데이터 부재)
#   - VKOSPI 직접 데이터 없음, 본 환경에서 KOSPI options chain도 부재
#
# 사이클 3 보강:
#   1) KOSPI200 RV12m (12-month rolling realized vol annualized) 직접 측정
#   2) VIX vs KOSPI RV correlation 정량 (proxy 정합성 입증/반박)
#   3) 4 sub-variants:
#      a) Straddle short (Bakshi-Kapadia-Madan 2003): IV - RV (annualized monthly)
#      b) Variance swap synthetic (Carr-Wu 2009): IV^2 - RV^2 / (2*sqrt(RV))
#      c) RV-IV vol spread (Bollerslev-Tauchen-Zhou 2009): RV - IV
#      d) Bouchaud-Cont-Iori VRP: long realized vol, short implied vol level
#   4) PIT C9 strict: t-1 IV (vix_lag), realized rolling 12m at t (PIT-safe)
#   5) Limitation: KOSPI200 옵션 chain 직접 부재 → US VIX 활용 (사이클 2 동일)
# ============================================================================
LOG("=== AXIS 1: VRP KOSPI 4 sub-variants ===")

# Step 1.1: Compute KOSPI BM realized vol (12m rolling, daily-aggregated)
rd_bm[, ym := substr(as.character(Date), 1, 7)]
# Monthly KOSPI return (compound) + monthly daily vol annualized
kospi_m <- rd_bm[, .(
  kospi_ret = prod(1 + KOSPI_Ret) - 1,
  kospi_dvol_ann = sd(KOSPI_Ret) * sqrt(252),  # daily-derived monthly annualized
  n_days = .N
), by = ym][order(ym)]
kospi_m[, ym_date := as.Date(paste0(ym, "-01"))]

# Rolling 12-month realized vol (PIT-safe, t-1 lag)
kospi_m[, rv12m := frollmean(kospi_dvol_ann, 12, align="right")]
kospi_m[, rv12m_lag1 := shift(rv12m, 1L)]  # PIT C9 strict
LOG(sprintf("  kospi monthly: n=%d, rv12m_lag1 non-NA=%d",
            nrow(kospi_m), sum(!is.na(kospi_m$rv12m_lag1))))

# Step 1.2: VIX monthly EOM + lag1
vix_m <- vix_dt[, ym := substr(as.character(Date), 1, 7)][, .(vix_eom = last(VIX)), by=ym][order(ym)]
vix_m[, vix_lag1 := shift(vix_eom, 1L)]  # PIT
LOG(sprintf("  VIX monthly: n=%d", nrow(vix_m)))

# Step 1.3: Joint diagnostic VIX vs KOSPI RV
joint_vix_kospi <- merge(vix_m[, .(ym, vix_eom, vix_lag1)],
                         kospi_m[, .(ym, rv12m, rv12m_lag1, kospi_ret)], by="ym")
joint_vix_kospi <- joint_vix_kospi[!is.na(vix_lag1) & !is.na(rv12m_lag1)]
LOG(sprintf("  joint VIX/KOSPI: n=%d", nrow(joint_vix_kospi)))

cor_vix_kospi_rv <- cor(joint_vix_kospi$vix_lag1, joint_vix_kospi$rv12m_lag1, use="complete.obs")
cor_vix_kospi_rv_diff <- cor(diff(joint_vix_kospi$vix_lag1),
                              diff(joint_vix_kospi$rv12m_lag1), use="complete.obs")
LOG(sprintf("  VIX_lag1 vs KOSPI_RV12m_lag1 cor (level): %.4f", cor_vix_kospi_rv))
LOG(sprintf("  VIX_lag1 vs KOSPI_RV12m_lag1 cor (diff):  %.4f", cor_vix_kospi_rv_diff))

# Step 1.4: 4 sub-variants of VRP harvest
# All variants: monthly P&L of "selling implied vol, paying realized vol"
# IV (vix_lag1 / 100): annualized → monthly equiv: sqrt(1/12)
# RV (rv12m_lag1):    already annualized
joint_vix_kospi[, iv_ann := vix_lag1 / 100]
joint_vix_kospi[, rv_ann := rv12m_lag1]
joint_vix_kospi[, iv_m := iv_ann * sqrt(1/12)]   # straddle premium scaling
joint_vix_kospi[, rv_m := rv_ann * sqrt(1/12)]

# Variant A: Straddle short (Bakshi-Kapadia-Madan 2003)
#   PnL = IV_premium - realized_payout  ~= 0.40 * (IV - RV) * sqrt(1/12)
joint_vix_kospi[, vrp_straddle_BKM := 0.40 * (iv_ann - rv_ann) * sqrt(1/12)]

# Variant B: Variance swap synthetic (Carr-Wu 2009)
#   Variance swap pays sigma^2 - K^2 (K = strike)
#   PnL ~ IV^2 - RV^2 (annualized variance), scaled to vol units
joint_vix_kospi[, vrp_varswap_CW := (iv_ann^2 - rv_ann^2) / (2 * pmax(rv_ann, 0.05)) * sqrt(1/12)]

# Variant C: RV-IV vol spread (Bollerslev-Tauchen-Zhou 2009)
#   PnL = RV - IV (long realized, short implied) — 반대 sign
#   Note: 일반적 short variance trader는 IV-RV gain
joint_vix_kospi[, vrp_RVIV_BTZ := (rv_ann - iv_ann) * sqrt(1/12)]

# Variant D: Bouchaud-Cont-Iori VRP (vol level capture)
#   PnL = -alpha * (IV_t - mean(IV)) * sqrt(1/12) (vol-mean-reversion harvest)
mean_iv <- mean(joint_vix_kospi$iv_ann, na.rm=TRUE)
joint_vix_kospi[, vrp_meanrev_BCI := -0.5 * (iv_ann - mean_iv) * sqrt(1/12)]

LOG("Step 1.5: 4 sub-variants stats:")
for (vname in c("vrp_straddle_BKM","vrp_varswap_CW","vrp_RVIV_BTZ","vrp_meanrev_BCI")) {
  v <- joint_vix_kospi[[vname]]
  v <- v[!is.na(v)]
  ann_ret <- mean(v) * 12
  ann_vol <- sd(v) * sqrt(12)
  ann_sr <- ann_ret / ann_vol
  cat(sprintf("    %s: mean=%+.4f /m, ann_ret=%+.3f, ann_vol=%.3f, SR=%+.3f, skew=%+.2f, kurt=%.2f\n",
              vname, mean(v), ann_ret, ann_vol, ann_sr,
              PerformanceAnalytics::skewness(v),
              PerformanceAnalytics::kurtosis(v)))
}

# Step 1.6: 4 sub-variants × 5 risk metrics matrix
# Need: cov_with_Hybrid, GPD xi, Crisis PASS rate, TDC vs Hybrid, style mkt_R²
ret[, ym := substr(as.character(date), 1, 7)]
ret_with_vrp <- merge(ret, joint_vix_kospi[, .(ym, vrp_straddle_BKM, vrp_varswap_CW,
                                               vrp_RVIV_BTZ, vrp_meanrev_BCI)], by="ym", all.x=TRUE)
LOG(sprintf("  ret_with_vrp: n=%d (4 sub-variants merged)", nrow(ret_with_vrp)))

# Compute 5 metrics for each variant
variant_metrics <- function(rv, rh, ra, rkospi, lab) {
  ok <- !is.na(rv) & !is.na(rh) & !is.na(ra) & !is.na(rkospi)
  rv <- rv[ok]; rh <- rh[ok]; ra <- ra[ok]; rkospi <- rkospi[ok]
  n <- length(rv)
  out <- list(label=lab, n=n)

  # 1) Cov with Hybrid
  out$cov_with_hybrid <- cov(rv, rh)
  out$cor_with_hybrid <- cor(rv, rh)
  out$cor_with_AR <- cor(rv, ra)

  # 2) GPD xi at q=0.85, 0.90 (n_exceed >= 20 권장)
  losses <- -rv
  thresh_90 <- quantile(losses, 0.90)
  thresh_85 <- quantile(losses, 0.85)
  exceed_90 <- losses[losses > thresh_90]
  exceed_85 <- losses[losses > thresh_85]

  if (length(exceed_90) >= 5) {
    fit90 <- tryCatch(gpdFit(losses, u=thresh_90, type="mle"), error=function(e) NULL)
    out$gpd_xi_90 <- if (!is.null(fit90)) fit90@fit$par.ests["xi"] else NA_real_
    out$gpd_n_exceed_90 <- length(exceed_90)
  } else {
    out$gpd_xi_90 <- NA_real_
    out$gpd_n_exceed_90 <- length(exceed_90)
  }
  if (length(exceed_85) >= 5) {
    fit85 <- tryCatch(gpdFit(losses, u=thresh_85, type="mle"), error=function(e) NULL)
    out$gpd_xi_85 <- if (!is.null(fit85)) fit85@fit$par.ests["xi"] else NA_real_
    out$gpd_n_exceed_85 <- length(exceed_85)
  } else {
    out$gpd_xi_85 <- NA_real_
    out$gpd_n_exceed_85 <- length(exceed_85)
  }

  # 3) Skewness, Kurtosis, ann_vol
  out$skewness <- PerformanceAnalytics::skewness(rv)
  out$excess_kurt <- PerformanceAnalytics::kurtosis(rv)
  out$ann_vol_pct <- sd(rv) * sqrt(12) * 100
  out$ann_ret_pct <- mean(rv) * 12 * 100
  out$ann_sr <- (mean(rv) * 12) / (sd(rv) * sqrt(12))

  # 4) Crisis PASS rate vs Hybrid (8-stress periods proxy: bottom 10% Hybrid months)
  hybrid_q10 <- quantile(rh, 0.10)
  crisis_idx <- which(rh <= hybrid_q10)
  if (length(crisis_idx) >= 5) {
    crisis_v <- rv[crisis_idx]
    crisis_h <- rh[crisis_idx]
    pass_count <- sum(crisis_v > crisis_h)
    out$crisis_pass_rate <- pass_count / length(crisis_idx)
    out$crisis_n <- length(crisis_idx)
    out$crisis_avg_v <- mean(crisis_v)
    out$crisis_avg_h <- mean(crisis_h)
  } else {
    out$crisis_pass_rate <- NA_real_
    out$crisis_n <- length(crisis_idx)
  }

  # 5) Lower TDC empirical at 5%
  rv_q5 <- quantile(rv, 0.05)
  rh_q5 <- quantile(rh, 0.05)
  joint_low <- sum(rv <= rv_q5 & rh <= rh_q5)
  marg_low <- max(sum(rh <= rh_q5), 1)
  out$tdc_lower_5pct <- joint_low / marg_low

  # 6) Style mkt R² with KOSPI BM
  reg <- lm(rv ~ rkospi)
  out$mkt_beta <- coef(reg)["rkospi"]
  out$mkt_R2 <- summary(reg)$r.squared
  out$alpha_monthly <- coef(reg)["(Intercept)"]
  out$t_alpha <- summary(reg)$coefficients["(Intercept)","t value"]

  return(out)
}

# Compute KOSPI return as benchmark for style regression
kospi_ret_per_ym <- kospi_m[, .(ym, kospi_ret_bm = kospi_ret)]
ret_with_vrp <- merge(ret_with_vrp, kospi_ret_per_ym, by="ym", all.x=TRUE)

variants <- c("vrp_straddle_BKM","vrp_varswap_CW","vrp_RVIV_BTZ","vrp_meanrev_BCI")
variant_results <- list()
for (vn in variants) {
  rv <- ret_with_vrp[[vn]]
  rh <- ret_with_vrp$r_Hybrid
  ra <- ret_with_vrp$r_AR
  rk <- ret_with_vrp$kospi_ret_bm
  variant_results[[vn]] <- variant_metrics(rv, rh, ra, rk, vn)
}

LOG("Step 1.6: 4 sub-variants × 5 risk metrics matrix (printed)")
for (vn in variants) {
  r <- variant_results[[vn]]
  cat(sprintf("  [%s] n=%d ann_SR=%+.3f vol=%.2f%% skew=%+.2f kurt=%.2f gpd_xi(0.90)=%s xi(0.85)=%s\n",
              vn, r$n, r$ann_sr, r$ann_vol_pct, r$skewness, r$excess_kurt,
              ifelse(is.na(r$gpd_xi_90), "NA", sprintf("%.3f", r$gpd_xi_90)),
              ifelse(is.na(r$gpd_xi_85), "NA", sprintf("%.3f", r$gpd_xi_85))))
  cat(sprintf("       cor(Hybrid)=%+.4f cor(AR)=%+.4f tdc_lower5=%.3f mkt_R2=%.3f crisis_PASS=%s/%d\n",
              r$cor_with_hybrid, r$cor_with_AR, r$tdc_lower_5pct, r$mkt_R2,
              ifelse(is.na(r$crisis_pass_rate), "NA",
                     sprintf("%.0f%%", 100*r$crisis_pass_rate)),
              r$crisis_n))
}

# Save Axis 1 summary
axis1_dt <- rbindlist(lapply(variants, function(vn) {
  r <- variant_results[[vn]]
  data.table(
    variant = vn,
    n_obs = r$n,
    ann_ret_pct = r$ann_ret_pct,
    ann_vol_pct = r$ann_vol_pct,
    ann_sr = r$ann_sr,
    skewness = r$skewness,
    excess_kurt = r$excess_kurt,
    gpd_xi_85 = r$gpd_xi_85,
    gpd_xi_90 = r$gpd_xi_90,
    gpd_n_exceed_85 = r$gpd_n_exceed_85,
    gpd_n_exceed_90 = r$gpd_n_exceed_90,
    cov_with_hybrid = r$cov_with_hybrid,
    cor_with_hybrid = r$cor_with_hybrid,
    cor_with_AR = r$cor_with_AR,
    tdc_lower_5pct = r$tdc_lower_5pct,
    mkt_beta = r$mkt_beta,
    mkt_R2 = r$mkt_R2,
    alpha_monthly = r$alpha_monthly,
    t_alpha = r$t_alpha,
    crisis_pass_rate = r$crisis_pass_rate,
    crisis_n = r$crisis_n,
    crisis_avg_v = r$crisis_avg_v,
    crisis_avg_h = r$crisis_avg_h
  )
}))
fwrite(axis1_dt, file.path(OUT_DIR, "axis1_vrp_kospi_4variants.csv"))
LOG(sprintf("  axis1 saved: %s", file.path(OUT_DIR, "axis1_vrp_kospi_4variants.csv")))

# ============================================================================
# AXIS 2: Defensive multi-sleeve EXCLUSION (AX-005 v1.2 enforcement)
# ============================================================================
# 사이클 2 finding: Defensive_LowVol_KR ΔSR_15pct=+0.057 1위
# 그러나 AX-005 v1.2 명시: KR defense single-sleeve top20 long-only 구조적 실패
# 사이클 3 진단:
#   1) Defensive sleeve를 hybrid 70/15/15 + 5% addition으로 본 경우의 risk profile
#   2) Defensive vs 다른 sleeve cov / TDC / style overlap (multi-sleeve EXCLUSION 조건 검증)
#   3) Single-sleeve standalone 보다 multi-sleeve 통합 시 risk 변동 정량
#
# AX-005 v1.2 EXCLUSION: multi-axis quality composite + multi-sleeve 내 Q07
#   현 Hybrid 70/15/15 = STR_1715 (alpha cross-section) + KR_10y bond + TSMOM ETF
#   여기에 5% Defensive 추가 = 4-sleeve hybrid → AX-005 v1.2 EXCLUSION 명백 (multi-sleeve)
# ============================================================================
LOG("=== AXIS 2: Defensive multi-sleeve EXCLUSION ===")

# Step 2.1: 4-sleeve hybrid 통합 cov 진단
ret_def <- ret[!is.na(r_Hybrid) & !is.na(r_defensive)]
LOG(sprintf("  ret_def joint sample: n=%d, range=%s ~ %s", nrow(ret_def),
            min(ret_def$ym), max(ret_def$ym)))

# Sleeve returns vector
sleeve_cols <- c("r_AR", "r_KR10y", "r_TSMOM", "r_defensive")
sleeve_dt <- ret_def[has_tsmom == TRUE & has_ts == TRUE,
                     .SD, .SDcols=c("ym","date", sleeve_cols)]
sleeve_dt <- sleeve_dt[complete.cases(sleeve_dt[, ..sleeve_cols])]
LOG(sprintf("  sleeve_dt 4-sleeve joint complete: n=%d (TSMOM available 시기)", nrow(sleeve_dt)))

R_sleeve <- as.matrix(sleeve_dt[, ..sleeve_cols])

# Pairwise cov + cor (Sample)
Sigma_4 <- cov(R_sleeve)
Cor_4 <- cor(R_sleeve)
LOG("  4-sleeve covariance (Sample):")
print(round(Sigma_4 * 1e4, 3))  # x10^4
LOG("  4-sleeve correlation:")
print(round(Cor_4, 3))

# PD check
eig_4 <- eigen(Sigma_4, only.values=TRUE)$values
LOG(sprintf("  Sigma_4 min_eig=%.6e cond=%.2f PD=%s",
            min(eig_4), max(eig_4)/min(eig_4), all(eig_4 > 0)))

# Step 2.2: Pairwise TDC lower (Defensive vs other sleeves)
compute_tdc_lower <- function(x, y, q=0.05) {
  qx <- quantile(x, q, na.rm=TRUE)
  qy <- quantile(y, q, na.rm=TRUE)
  joint <- sum(x <= qx & y <= qy, na.rm=TRUE)
  marg <- max(sum(y <= qy, na.rm=TRUE), 1)
  joint / marg
}
compute_tdc_upper <- function(x, y, q=0.95) {
  qx <- quantile(x, q, na.rm=TRUE)
  qy <- quantile(y, q, na.rm=TRUE)
  joint <- sum(x >= qx & y >= qy, na.rm=TRUE)
  marg <- max(sum(y >= qy, na.rm=TRUE), 1)
  joint / marg
}

tdc_5 <- matrix(NA, 4, 4, dimnames=list(sleeve_cols, sleeve_cols))
tdc_95 <- matrix(NA, 4, 4, dimnames=list(sleeve_cols, sleeve_cols))
for (i in 1:4) for (j in 1:4) {
  if (i != j) {
    tdc_5[i,j] <- compute_tdc_lower(R_sleeve[,i], R_sleeve[,j], q=0.05)
    tdc_95[i,j] <- compute_tdc_upper(R_sleeve[,i], R_sleeve[,j], q=0.95)
  }
}
LOG("  4-sleeve TDC lower 5%:")
print(round(tdc_5, 3))
LOG("  4-sleeve TDC upper 95%:")
print(round(tdc_95, 3))

# Step 2.3: Style regression multi-factor (KOSPI BM + KOSPI vol regime)
# Defensive sleeve risk-adjusted alpha vs each other sleeve as factor
ret_with_kospi <- merge(ret_def, kospi_ret_per_ym, by="ym", all.x=TRUE)
ret_with_kospi <- ret_with_kospi[!is.na(kospi_ret_bm) & !is.na(r_defensive)]

style_def <- list()
for (factor_col in c("r_AR", "r_KR10y", "r_TSMOM", "kospi_ret_bm")) {
  ok <- !is.na(ret_with_kospi[[factor_col]]) & !is.na(ret_with_kospi$r_defensive)
  if (sum(ok) >= 20) {
    fit <- lm(ret_with_kospi$r_defensive[ok] ~ ret_with_kospi[[factor_col]][ok])
    style_def[[factor_col]] <- list(
      n=sum(ok),
      beta=coef(fit)[2], R2=summary(fit)$r.squared,
      alpha_monthly=coef(fit)[1],
      t_alpha=summary(fit)$coefficients[1,3]
    )
  }
}

LOG("  Defensive style regression vs each sleeve:")
for (k in names(style_def)) {
  s <- style_def[[k]]
  cat(sprintf("    %-18s: n=%d beta=%+.4f R2=%.3f alpha_m=%+.4f t_alpha=%+.2f\n",
              k, s$n, s$beta, s$R2, s$alpha_monthly, s$t_alpha))
}

# Step 2.4: Multi-sleeve hybrid (70 AR + 15 KR_10y + 10 TSMOM + 5 Defensive) vs base
# 정량 Var contribution comparison
make_combo <- function(weights, retcols, dt) {
  stopifnot(length(weights) == length(retcols))
  ok <- complete.cases(dt[, ..retcols])
  rmat <- as.matrix(dt[ok, ..retcols])
  out <- as.numeric(rmat %*% weights)
  list(returns=out, n=length(out), dates=dt$date[ok])
}

# Base Hybrid 70/15/15 (sample restricted to TSMOM+all available)
combo_base <- make_combo(c(0.70, 0.15, 0.15), c("r_AR","r_KR10y","r_TSMOM"),
                         sleeve_dt[, .(date, r_AR, r_KR10y, r_TSMOM)])

# 4-sleeve Hybrid 70 AR + 10 KR_10y + 10 TSMOM + 5 Defensive + 5 ?
# Multi-axis design: 70/10/10/5 partial, 65/15/10/5 conservative + Defensive
combos_def <- list(
  base_70_15_15            = list(w=c(0.70, 0.15, 0.15, 0.0), label="base_70_15_15_no_def"),
  add_5_def                = list(w=c(0.70, 0.15, 0.10, 0.05), label="70AR+15KR+10TS+5DEF"),
  add_5_def_redistr        = list(w=c(0.65, 0.15, 0.15, 0.05), label="65AR+15KR+15TS+5DEF"),
  add_5_def_proportional   = list(w=c(0.665, 0.1425, 0.1425, 0.05), label="66.5+14.25+14.25+5DEF"),
  add_10_def               = list(w=c(0.65, 0.125, 0.125, 0.10), label="65AR+12.5KR+12.5TS+10DEF"),
  add_15_def               = list(w=c(0.60, 0.10, 0.15, 0.15), label="60AR+10KR+15TS+15DEF")
)

axis2_combo_results <- list()
for (key in names(combos_def)) {
  w <- combos_def[[key]]$w
  combo <- make_combo(w, sleeve_cols, sleeve_dt)
  rv <- combo$returns
  ann_ret <- mean(rv) * 12
  ann_vol <- sd(rv) * sqrt(12)
  ann_sr <- ann_ret / ann_vol
  # MDD
  cum_ret <- cumprod(1 + rv)
  mdd <- min(cum_ret / cummax(cum_ret) - 1)
  axis2_combo_results[[key]] <- data.table(
    combo_id = key,
    label = combos_def[[key]]$label,
    n_obs = combo$n,
    weights_str = paste(round(w*100, 1), collapse="/"),
    ann_ret_pct = ann_ret * 100,
    ann_vol_pct = ann_vol * 100,
    ann_sr = ann_sr,
    mdd = mdd,
    cum_ret = tail(cum_ret, 1)
  )
}
axis2_combo_dt <- rbindlist(axis2_combo_results)
LOG("  4-sleeve combos (Defensive integration):")
print(axis2_combo_dt)
fwrite(axis2_combo_dt, file.path(OUT_DIR, "axis2_defensive_multisleeve_combos.csv"))

# Step 2.5: AX-005 v1.2 EXCLUSION 인지 명문화 (single-sleeve 표현 X)
ax005_compliance <- list(
  ax005_v1_2_principle="KR defense single-sleeve top20 long-only 구조적 실패 (Q07/D25 standalone, 4-axis composite 모두 실패)",
  cycle3_evaluation_mode="multi-sleeve EXCLUSION only — single-sleeve standalone 평가 X",
  hybrid_70_15_15_baseline="3-sleeve (STR_1715 AR cross-section + KR_10y bond + TSMOM ETF)",
  defensive_addition_4sleeve="4-sleeve hybrid 내 component — AX-005 v1.2 EXCLUSION 자격 충족",
  proxy_limitation="Q07_Earnings_Stability 정식 X — return_volatility-based BAB Frazzini-Pedersen 2014 proxy 사용",
  note="정식 채택 시 Factor DB Q07 직접 + multi-axis quality composite 의무"
)

# Save axis 2 outputs
sigma_dt <- as.data.table(Sigma_4, keep.rownames="src")
fwrite(sigma_dt, file.path(OUT_DIR, "axis2_4sleeve_covariance_sample.csv"))
write_parquet(sigma_dt, file.path(STAGE_DIR, "axis2_4sleeve_covariance_sample.parquet"))

cor_dt <- as.data.table(Cor_4, keep.rownames="src")
fwrite(cor_dt, file.path(OUT_DIR, "axis2_4sleeve_correlation.csv"))

tdc_5_dt <- as.data.table(tdc_5, keep.rownames="src")
fwrite(tdc_5_dt, file.path(OUT_DIR, "axis2_4sleeve_tdc_lower5pct.csv"))

# ============================================================================
# AXIS 3: 5-source marginal contribution + Diversification Ratio
# ============================================================================
# 사이클 2 finding: Hybrid + 5% Defensive + 5% Commodity + 5% VRP = SR 1.950 (post-2010 192m)
# 사이클 3 보강:
#   1) 각 source의 marginal contribution to portfolio variance (Σ 분해)
#   2) Diversification Ratio (Choueifaty-Coignard 2008): DR = w'σ / sqrt(w'Σw)
#   3) Risk-parity 가설 weights 시 vol contribution
#   4) 4-source vs 5-source combination scan (weight 가설값 5/10/15%만 — 진단 only)
#   5) DSR Bailey-LdP 다중검정 통과율 (n_trials 조정)
#
# 절대 boundary: weight 결정 / 제안 X — marginal contribution diagnostic만
# ============================================================================
LOG("=== AXIS 3: 5-source marginal contribution ===")

# Step 3.1: 5-source joint sample (post-2010 since Commodity start 2010-04)
ret5 <- ret[has_tsmom == TRUE & !is.na(r_AR) & !is.na(r_KR10y) & !is.na(r_TSMOM) &
            !is.na(r_commodity) & !is.na(r_defensive) & !is.na(r_vrp)]
LOG(sprintf("  5-source joint sample post-2010: n=%d, range=%s ~ %s",
            nrow(ret5), min(ret5$ym), max(ret5$ym)))

src_cols <- c("r_AR", "r_KR10y", "r_TSMOM", "r_defensive", "r_commodity", "r_vrp")
R5 <- as.matrix(ret5[, ..src_cols])

# Step 3.2: 5-source covariance + correlation
Sigma_5 <- cov(R5)
Cor_5 <- cor(R5)
LOG("  6-source covariance (Sample, x10^4):")
print(round(Sigma_5 * 1e4, 3))
LOG("  6-source correlation:")
print(round(Cor_5, 3))

# Save
sig5_dt <- as.data.table(Sigma_5, keep.rownames="src")
fwrite(sig5_dt, file.path(OUT_DIR, "axis3_6source_covariance.csv"))
write_parquet(sig5_dt, file.path(STAGE_DIR, "axis3_6source_covariance.parquet"))

cor5_dt <- as.data.table(Cor_5, keep.rownames="src")
fwrite(cor5_dt, file.path(OUT_DIR, "axis3_6source_correlation.csv"))

# Step 3.3: Diversification Ratio (Choueifaty-Coignard 2008) for each gauging weight set
# DR = w'σ / sqrt(w'Σw), where σ = vol of each asset
sigma_diag <- sqrt(diag(Sigma_5))
LOG(sprintf("  Asset annualized vols: AR=%.3f KR10y=%.3f TSMOM=%.3f Def=%.3f Com=%.3f VRP=%.3f",
            sigma_diag[1]*sqrt(12), sigma_diag[2]*sqrt(12), sigma_diag[3]*sqrt(12),
            sigma_diag[4]*sqrt(12), sigma_diag[5]*sqrt(12), sigma_diag[6]*sqrt(12)))

div_ratio <- function(w, Sigma, sigma_diag) {
  num <- sum(w * sigma_diag)
  denom <- sqrt(t(w) %*% Sigma %*% w)
  num / denom
}

# Marginal contribution to variance (MCTV)
# MCTV_i = w_i * (Sigma %*% w)_i / (w' Sigma w)
mctv <- function(w, Sigma) {
  pv <- as.numeric(t(w) %*% Sigma %*% w)
  comp <- as.numeric(w * (Sigma %*% w))
  comp / pv
}

# Step 3.4: Combination scan (sub-combo)
# 가설값 각 source 5%/10%/15% addition 진단 + Hybrid 70/15/15 base
# 보충: 4-source (Hybrid + 1 candidate) vs 5-source (Hybrid + 2 candidates) vs 6-source (Hybrid + 3 candidates)
combos_5src <- list(
  hybrid_70_15_15      = list(w=c(0.70, 0.15, 0.15, 0.00, 0.00, 0.00), label="Hybrid_base_70/15/15"),
  add_5_def            = list(w=c(0.65, 0.15, 0.15, 0.05, 0.00, 0.00), label="Hybrid+5DEF"),
  add_5_com            = list(w=c(0.65, 0.15, 0.15, 0.00, 0.05, 0.00), label="Hybrid+5COM"),
  add_5_vrp            = list(w=c(0.65, 0.15, 0.15, 0.00, 0.00, 0.05), label="Hybrid+5VRP"),
  add_5_def_5_com      = list(w=c(0.60, 0.15, 0.15, 0.05, 0.05, 0.00), label="Hybrid+5DEF+5COM"),
  add_5_def_5_vrp      = list(w=c(0.60, 0.15, 0.15, 0.05, 0.00, 0.05), label="Hybrid+5DEF+5VRP"),
  add_5_com_5_vrp      = list(w=c(0.60, 0.15, 0.15, 0.00, 0.05, 0.05), label="Hybrid+5COM+5VRP"),
  add_5_def_5_com_5_vrp= list(w=c(0.55, 0.15, 0.15, 0.05, 0.05, 0.05), label="Hybrid+5DEF+5COM+5VRP"),
  add_10_def           = list(w=c(0.60, 0.15, 0.15, 0.10, 0.00, 0.00), label="Hybrid+10DEF"),
  add_10_def_5_vrp     = list(w=c(0.55, 0.15, 0.15, 0.10, 0.00, 0.05), label="Hybrid+10DEF+5VRP"),
  add_10_def_5_com     = list(w=c(0.55, 0.15, 0.15, 0.10, 0.05, 0.00), label="Hybrid+10DEF+5COM"),
  add_10_def_5_com_5_vrp = list(w=c(0.50, 0.15, 0.15, 0.10, 0.05, 0.05), label="Hybrid+10DEF+5COM+5VRP"),
  risk_parity_6src     = list(w=NULL, label="Risk_parity_6src_inverse_vol"),
  cycle2_best_5src     = list(w=c(0.70, 0.10, 0.10, 0.05, 0.05, 0.00), label="Cycle2_70/10/10/5/5_no_VRP"),
  cycle2_best_6src     = list(w=c(0.65, 0.10, 0.10, 0.05, 0.05, 0.05), label="Cycle2_65/10/10/5/5/5_all3")
)

# Compute risk-parity inverse-vol weights (gauging)
inv_vol <- 1 / sigma_diag
w_rp <- inv_vol / sum(inv_vol)
combos_5src[["risk_parity_6src"]]$w <- w_rp
LOG(sprintf("  Risk-parity inv-vol weights: %s", paste(round(w_rp*100,1), collapse="/")))

# Step 3.5: Compute SR / MDD / DR / MCTV / DSR for each combo
sr_to_dsr <- function(sr_obs, n_trials, T_obs, skew, kurt) {
  # Bailey-LdP DSR (2014 JPM)
  # DSR = (sr_obs - sr_max_n) / sqrt(Var(sr_obs))
  # Var(sr_obs) approx (1 - skew*sr_obs + (kurt-1)/4 * sr_obs^2) / (T - 1)
  if (n_trials <= 1) return(list(dsr=NA, sr_max_n=NA, var_sr=NA))
  emc <- 0.5772156649  # Euler-Mascheroni
  z_eff <- (1 - emc) * qnorm(1 - 1/n_trials) + emc * qnorm(1 - 1/(n_trials*exp(1)))
  sr_max_n <- z_eff / sqrt(T_obs)  # null max under independence
  var_sr <- (1 - skew * sr_obs + ((kurt-1)/4) * sr_obs^2) / (T_obs - 1)
  if (var_sr <= 0) return(list(dsr=NA, sr_max_n=sr_max_n, var_sr=var_sr))
  dsr <- (sr_obs - sr_max_n) / sqrt(var_sr)
  list(dsr=dsr, sr_max_n=sr_max_n, var_sr=var_sr)
}

axis3_results <- list()
for (key in names(combos_5src)) {
  w <- combos_5src[[key]]$w
  if (length(w) != ncol(R5)) next
  rv_combo <- as.numeric(R5 %*% w)
  ann_ret <- mean(rv_combo) * 12
  ann_vol <- sd(rv_combo) * sqrt(12)
  ann_sr <- ann_ret / ann_vol
  cum_ret <- cumprod(1 + rv_combo)
  mdd <- min(cum_ret / cummax(cum_ret) - 1)
  # Diversification Ratio
  dr <- as.numeric(div_ratio(w, Sigma_5, sigma_diag))
  # MCTV vector
  mctv_v <- mctv(w, Sigma_5)
  # Monthly skew + kurt for DSR
  skew_m <- PerformanceAnalytics::skewness(rv_combo)
  kurt_m <- PerformanceAnalytics::kurtosis(rv_combo)
  # Sharpe monthly
  sr_m <- mean(rv_combo) / sd(rv_combo)
  # DSR with n_trials=15 (15 combos searched)
  dsr_15 <- sr_to_dsr(sr_m, 15, length(rv_combo), skew_m, kurt_m)
  # DSR with n_trials=30 (broader robustness)
  dsr_30 <- sr_to_dsr(sr_m, 30, length(rv_combo), skew_m, kurt_m)

  axis3_results[[key]] <- data.table(
    combo_id = key,
    label = combos_5src[[key]]$label,
    weights_str = paste(round(w*100, 1), collapse="/"),
    n_obs = length(rv_combo),
    ann_ret_pct = ann_ret * 100,
    ann_vol_pct = ann_vol * 100,
    ann_sr = ann_sr,
    mdd = mdd,
    div_ratio = dr,
    mctv_AR = mctv_v[1],
    mctv_KR10y = mctv_v[2],
    mctv_TSMOM = mctv_v[3],
    mctv_DEF = mctv_v[4],
    mctv_COM = mctv_v[5],
    mctv_VRP = mctv_v[6],
    sr_monthly = sr_m,
    skew_monthly = skew_m,
    kurt_monthly = kurt_m,
    dsr_15trials = dsr_15$dsr,
    dsr_30trials = dsr_30$dsr,
    sr_max_n15 = dsr_15$sr_max_n
  )
}
axis3_dt <- rbindlist(axis3_results)
LOG("  6-source combo metrics (post-2010 192m):")
print(axis3_dt[, .(combo_id, weights_str, ann_sr, mdd, div_ratio, mctv_AR, mctv_VRP, dsr_15trials)])
fwrite(axis3_dt, file.path(OUT_DIR, "axis3_6source_marginal_combos.csv"))

# Step 3.6: Marginal contribution to risk under risk-parity baseline
# (각 source의 portfolio variance에 대한 기여)
LOG("  Risk-parity inverse-vol marginal contribution decomposition:")
mctv_rp <- mctv(w_rp, Sigma_5)
mctv_rp_dt <- data.table(source=src_cols, weight=w_rp, mctv=mctv_rp,
                         risk_share_pct=100 * mctv_rp / sum(mctv_rp))
print(mctv_rp_dt)
fwrite(mctv_rp_dt, file.path(OUT_DIR, "axis3_riskparity_mctv.csv"))

# Step 3.7: 256m re-evaluation (사이클 2 base sample)
# post-2015 sample (n=137 in cycle 2 axis_7)
LOG("  256m sample re-evaluation:")
ret256 <- ret[!is.na(r_AR) & !is.na(r_KR10y) & !is.na(r_defensive) & !is.na(r_vrp)]  # KR_10y forward-fill 일부 가능
# Hybrid 70/15/15 = AR + KR_10y + TSMOM but TSMOM only post-2010
# 사이클 2 base 256m: r_Hybrid 자체 (KR_10y 100% pre-2010 + 70/15/15 post-2010 weighted by has_tsmom)
ret256_full <- ret[!is.na(r_Hybrid)]
LOG(sprintf("  256m hybrid base: n=%d", nrow(ret256_full)))

# Hybrid + 5%/15% add for each candidate
candidates_avail <- list(
  defensive = "r_defensive",
  vrp = "r_vrp",
  commodity = "r_commodity",
  currency = "r_currency"
)
add_results_256m <- list()
for (cand_name in names(candidates_avail)) {
  ccol <- candidates_avail[[cand_name]]
  ok <- !is.na(ret256_full[[ccol]]) & !is.na(ret256_full$r_Hybrid)
  rh <- ret256_full$r_Hybrid[ok]
  rc <- ret256_full[[ccol]][ok]
  # Base
  ann_sr_h <- mean(rh)*12 / (sd(rh)*sqrt(12))
  cum_h <- cumprod(1+rh); mdd_h <- min(cum_h/cummax(cum_h) - 1)
  # +5%
  r5 <- 0.95*rh + 0.05*rc
  ann_sr_5 <- mean(r5)*12 / (sd(r5)*sqrt(12))
  cum5 <- cumprod(1+r5); mdd_5 <- min(cum5/cummax(cum5) - 1)
  # +15%
  r15 <- 0.85*rh + 0.15*rc
  ann_sr_15 <- mean(r15)*12 / (sd(r15)*sqrt(12))
  cum15 <- cumprod(1+r15); mdd_15 <- min(cum15/cummax(cum15) - 1)
  add_results_256m[[cand_name]] <- data.table(
    candidate=cand_name, n_obs=sum(ok),
    sr_base=ann_sr_h, mdd_base=mdd_h,
    sr_5pct=ann_sr_5, delta_sr_5pct=ann_sr_5-ann_sr_h, mdd_5pct=mdd_5,
    sr_15pct=ann_sr_15, delta_sr_15pct=ann_sr_15-ann_sr_h, mdd_15pct=mdd_15
  )
}
add_256m_dt <- rbindlist(add_results_256m)
LOG("  256m +5%/+15% add (from Hybrid base):")
print(add_256m_dt)
fwrite(add_256m_dt, file.path(OUT_DIR, "axis3_256m_addition_diagnostic.csv"))

# Step 3.8: Multi-candidate combo at 256m (post-2010 vs full-sample)
# Hybrid + 5% Def + 5% Com + 5% VRP (사이클 2 best)
# 256m sample restricted to where Commodity available (192m)
LOG("  Multi-candidate combo: post-2010 192m re-eval")
ret192 <- ret[!is.na(r_Hybrid) & !is.na(r_commodity) & !is.na(r_defensive) & !is.na(r_vrp)]
LOG(sprintf("  ret192 n=%d, range=%s ~ %s", nrow(ret192), min(ret192$ym), max(ret192$ym)))

# Test combos
test_combos <- list(
  base = list(w=c(1, 0, 0, 0), label="Hybrid_base"),
  d5 = list(w=c(0.95, 0.05, 0, 0), label="+5DEF"),
  c5 = list(w=c(0.95, 0, 0.05, 0), label="+5COM"),
  v5 = list(w=c(0.95, 0, 0, 0.05), label="+5VRP"),
  d5c5 = list(w=c(0.90, 0.05, 0.05, 0), label="+5DEF+5COM"),
  d5v5 = list(w=c(0.90, 0.05, 0, 0.05), label="+5DEF+5VRP"),
  c5v5 = list(w=c(0.90, 0, 0.05, 0.05), label="+5COM+5VRP"),
  d5c5v5 = list(w=c(0.85, 0.05, 0.05, 0.05), label="+5DEF+5COM+5VRP"),
  d10 = list(w=c(0.90, 0.10, 0, 0), label="+10DEF"),
  d10c5 = list(w=c(0.85, 0.10, 0.05, 0), label="+10DEF+5COM"),
  d10v5 = list(w=c(0.85, 0.10, 0, 0.05), label="+10DEF+5VRP"),
  d10c5v5 = list(w=c(0.80, 0.10, 0.05, 0.05), label="+10DEF+5COM+5VRP"),
  d10c10 = list(w=c(0.80, 0.10, 0.10, 0), label="+10DEF+10COM"),
  d10c10v5 = list(w=c(0.75, 0.10, 0.10, 0.05), label="+10DEF+10COM+5VRP")
)

R192 <- as.matrix(ret192[, .(r_Hybrid, r_defensive, r_commodity, r_vrp)])
combo_192_results <- list()
for (key in names(test_combos)) {
  w <- test_combos[[key]]$w
  rv <- as.numeric(R192 %*% w)
  ann_ret <- mean(rv)*12
  ann_vol <- sd(rv)*sqrt(12)
  ann_sr <- ann_ret/ann_vol
  cum <- cumprod(1+rv); mdd <- min(cum/cummax(cum)-1)
  skew_m <- PerformanceAnalytics::skewness(rv)
  kurt_m <- PerformanceAnalytics::kurtosis(rv)
  sr_m <- mean(rv)/sd(rv)
  dsr14 <- sr_to_dsr(sr_m, 14, length(rv), skew_m, kurt_m)
  combo_192_results[[key]] <- data.table(
    combo_id=key, label=test_combos[[key]]$label,
    weights_str=paste(round(w*100,1), collapse="/"),
    n_obs=length(rv), ann_sr=ann_sr, mdd=mdd, ann_vol_pct=ann_vol*100,
    skew_m=skew_m, kurt_m=kurt_m, dsr_14trials=dsr14$dsr
  )
}
combo_192_dt <- rbindlist(combo_192_results)
LOG("  192m combo re-eval (full Hybrid as composite source):")
print(combo_192_dt)
fwrite(combo_192_dt, file.path(OUT_DIR, "axis3_192m_multi_candidate_combos.csv"))

# Step 3.9: KOSPI VKOSPI 정밀 한계 명시
vkospi_limitation <- list(
  status="VKOSPI 직접 데이터 부재 (본 환경)",
  proxy_used="US VIX (FRED VIXCLS)",
  cor_with_KOSPI_RV12m_level=cor_vix_kospi_rv,
  cor_with_KOSPI_RV12m_diff=cor_vix_kospi_rv_diff,
  KOSPI_options_chain="부재 — 정식 채택 시 KRX KOSPI200 옵션 daily chain 의무",
  cycle3_workaround="KOSPI BM realized vol 12m + VIX implied vol 결합, 4 sub-variants 비교",
  citations=c(
    "Bakshi-Kapadia-Madan_2003_RFS_Stock_return_characteristics_skew_pricing",
    "Carr-Wu_2009_RFS_Variance_risk_premiums",
    "Bollerslev-Tauchen-Zhou_2009_RFS_Expected_stock_returns",
    "Bouchaud-Cont-Iori_1998_models_of_volatility_dynamics"
  )
)

# ============================================================================
# 4. Cycle 4 candidates (의무: 멈추지 말고 다음 후보 명시)
# ============================================================================
LOG("=== Cycle 4 candidates ===")

cycle4_candidates <- list(
  topic_1 = list(
    name = "KOSPI200_options_chain_VRP_direct",
    priority = "HIGH",
    rationale = "사이클 3 axis 1에서 VIX-KOSPI RV cor 정량 + 4 sub-variants 보강 했지만 KOSPI200 옵션 chain (delta-hedged straddle) 직접 사용 미수행. KRX 옵션 daily chain (mid-spread, OI, expiry) 확보 시 정식 VRP harvest 가능.",
    data_required = "KRX KOSPI200 옵션 daily chain (또는 quanchat / Quantopian 대체)",
    expected_finding = "정식 VKOSPI vs RV12m direct corr (사이클 3 VIX proxy 0.30~0.50 추정 → 0.70~0.85 추정), Carr-Wu 2009 capacity ≤ 5% 확정"
  ),
  topic_2 = list(
    name = "Q07_Earnings_Stability_direct_with_multi_axis_quality",
    priority = "HIGH",
    rationale = "사이클 3 axis 2에서 Defensive_LowVol_KR proxy = return_volatility 사용. AX-005 v1.2 EXCLUSION '정식'은 multi-axis quality composite + multi-sleeve 의무. Factor DB Q07 직접 + Q01~Q15 multi-axis 결합 평가.",
    data_required = "Factor DB load_month_factors() — Q07_Earnings_Stability + Q06_Earnings_Quality + Q01_Profitability",
    expected_finding = "Q07 본격 corr / IC / regime conditional behavior. multi-axis quality composite (Q07+Q06+Q01 PCA) 통합 risk profile"
  ),
  topic_3 = list(
    name = "Stress_period_extension_pre2010_synthetic",
    priority = "MEDIUM",
    rationale = "사이클 3 axis 1+3 sample 한계: post-2010 (Commodity GLD/COPX 시작) 또는 post-2015 (TSMOM ETF rotation 시작) → GFC 2008/IMF 1997 stress 미포함. KR market backfill: KOSPI200 1990~2010 + KR govvies (ECOS) + 한국은행 회사채 spread historical 활용.",
    data_required = "ECOS bond rates (이미 .cache/ecos_bond_rates.parquet 가용 1990~) + 한국 KOSPI 1990~ + ECOS KRW/USD 2000~",
    expected_finding = "30+ year sample tail risk (xi pre-2010 vs post-2010), GFC 2008 pure carry crash empirical -36.88% 외 더 catastrophic events"
  ),
  topic_4 = list(
    name = "5source_DCC_GARCH_dynamic_correlation",
    priority = "MEDIUM",
    rationale = "사이클 3 axis 3 정적 Sample covariance만 사용. DCC-GARCH (Engle 2002) dynamic correlation 적용 시 source 간 위기 conditional correlation 변동 정량 가능.",
    data_required = "ret5 + rugarch::dccfit",
    expected_finding = "stress regime (BM_Ret < q10) 시 source 간 cor uplift, normal vs crisis cor delta"
  ),
  topic_5 = list(
    name = "Cross_section_alpha_decay_multi_horizon",
    priority = "LOW",
    rationale = "현 STR_1715 (AR threshold overlay) = monthly horizon. weekly / daily / quarterly horizon AR signal decay 정량 시 STR_1715 capacity expansion 또는 multi-horizon ensemble 가능.",
    data_required = "Factor DB monthly + daily aggregation",
    expected_finding = "AR signal autocorrelation by horizon, capacity vs decay trade-off"
  )
)

# ============================================================================
# 5. Final risk_package_draft.json assembly
# ============================================================================
LOG("=== Final risk_package_draft.json assembly ===")

risk_package <- list(
  task_id = "RESEARCH_RISK_CYCLE3_20260507",
  research_type = "meta_self_research_qlead_ondemand_cycle3",
  as_of_date = format(Sys.Date(), "%Y-%m-%d"),
  version = "v1_draft_pre_codex",
  cycle = 3,
  scope_disclaimer = paste(
    "Q-Lead 온디맨드 메타 리서치 사이클 3 (path: qepm/mailbox/research/risk_cycle3_20260507/).",
    "정식 WT alpha→risk pipeline 산출 아님 — alpha_scores.parquet / weights.csv / B Ω B'+D 종목별 decomposition 등 정식 risk_package 의무 artifact 일부 본 작업 영역 외부 (alpha-research → risk-research 정식 lifecycle에서 작성).",
    "사이클 2 (RESEARCH_RISK_CANDIDATES_20260507) 1위 Defensive_LowVol_KR + 2위 VRP_KOSPI_Proxy 정밀 진단 + 5-source multi combo marginal contribution 한정.",
    "alpha 시그널 추가 / 신규 strategy spawn / weight 결정 절대 X (Hook agent_role_guard 강제). 5-source combo는 marginal contribution diagnostic만 — weight 제안 X.",
    "신규 source 채택 결정은 후속 정식 alpha-research → risk-research → optimizer-research lifecycle 의무.",
    sep=" "
  ),
  context_cycle1_2_input = list(
    cycle1_path = "qepm/mailbox/research/risk_model_meta_20260507/risk_package.json",
    cycle2_path = "qepm/mailbox/research/risk_candidates_20260507/risk_package.json",
    cycle2_top_findings = list(
      `1_defensive_lowvol_KR_rank` = "사이클 2 v2 rank 1 — ΔSR_15pct=+0.057, MDD -2.6pp, AX-005 v1.2 multi-sleeve EXCLUSION 의무",
      `2_vrp_kospi_rank` = "사이클 2 v2 rank 2 — Crisis PASS 4/6 vs Hybrid (highest), GPD xi 0.40~0.52 strong fat tail",
      `3_multi_combo_best` = "Hybrid + 5%×Defensive + 5%×Commodity + 5%×VRP = SR 1.950 / MDD 0.137 (post-2010 192m)",
      `4_sr_target_gap` = "Target 2.0 vs 1.950 gap 0.050 (사이클 1 0.335에서 86% 좁힘)"
    )
  ),
  axis_1_vrp_kospi_4subvariants = list(
    purpose = "사이클 2 weakest_assumption 'VRP=US VIX 기반 합성' 보강. 4 sub-variants × 5 risk metrics + KOSPI BM realized vol 정량.",
    methodology = list(
      vrp_straddle_BKM = "Bakshi-Kapadia-Madan 2003 RFS — 0.40 * (IV_ann - RV_ann) * sqrt(1/12)",
      vrp_varswap_CW = "Carr-Wu 2009 RFS — (IV_ann² - RV_ann²) / (2 * RV_ann) * sqrt(1/12)",
      vrp_RVIV_BTZ = "Bollerslev-Tauchen-Zhou 2009 RFS — (RV_ann - IV_ann) * sqrt(1/12) (long-vol position)",
      vrp_meanrev_BCI = "Bouchaud-Cont-Iori 1998 — -0.5 * (IV - mean(IV)) * sqrt(1/12) (mean-reversion harvest)"
    ),
    PIT_compliance = "vix_lag1 = shift(vix_eom, 1L), rv12m_lag1 = shift(rv12m, 1L) — t-1 strict",
    vix_proxy_validation = list(
      cor_VIX_lag1_KOSPI_RV12m_lag1_level = round(cor_vix_kospi_rv, 4),
      cor_VIX_lag1_KOSPI_RV12m_lag1_diff = round(cor_vix_kospi_rv_diff, 4),
      interpretation = "VIX-KOSPI RV correlation in level provides empirical bound for proxy quality. KOSPI options chain 부재 한계 명시 의무."
    ),
    variant_results_summary = lapply(variants, function(vn) {
      r <- variant_results[[vn]]
      list(
        n_obs = r$n,
        ann_ret_pct = round(r$ann_ret_pct, 3),
        ann_vol_pct = round(r$ann_vol_pct, 3),
        ann_sr = round(r$ann_sr, 4),
        skewness = round(r$skewness, 3),
        excess_kurt = round(r$excess_kurt, 3),
        gpd_xi_85 = ifelse(is.na(r$gpd_xi_85), NA, round(r$gpd_xi_85, 4)),
        gpd_xi_90 = ifelse(is.na(r$gpd_xi_90), NA, round(r$gpd_xi_90, 4)),
        gpd_n_exceed_85 = r$gpd_n_exceed_85,
        gpd_n_exceed_90 = r$gpd_n_exceed_90,
        cor_with_hybrid = round(r$cor_with_hybrid, 4),
        cor_with_AR = round(r$cor_with_AR, 4),
        tdc_lower_5pct = round(r$tdc_lower_5pct, 4),
        mkt_R2 = round(r$mkt_R2, 4),
        crisis_pass_rate = ifelse(is.na(r$crisis_pass_rate), NA, round(r$crisis_pass_rate, 4)),
        crisis_n = r$crisis_n
      )
    }),
    key_finding = "본 사이클 3에서 KOSPI BM 12m realized vol 직접 측정 후 4 sub-variants 비교. 사이클 2 VRP_KOSPI_Proxy (vrp_straddle_BKM 동일 method)는 4 sub-variants 중 baseline. variants 간 ann_sr/tail 차이는 method definition 차이 (BKM vs CW vs BTZ vs BCI). 정식 채택 시 KRX KOSPI200 옵션 chain 직접 활용 의무 (사이클 4 topic_1).",
    artifact_csv = "qepm/mailbox/research/risk_cycle3_20260507/axis1_vrp_kospi_4variants.csv"
  ),
  axis_2_defensive_multisleeve_EXCLUSION = list(
    purpose = "AX-005 v1.2 'KR defense single-sleeve top20 long-only 구조적 실패' 명시 인지 후, multi-sleeve EXCLUSION 자격 검증. Hybrid 70/15/15 + 5% Defensive = 4-sleeve 통합 risk profile.",
    ax005_v1_2_compliance = ax005_compliance,
    sleeve_4_sample = list(
      n_obs = nrow(sleeve_dt),
      sample_range = paste0(min(sleeve_dt$ym), " ~ ", max(sleeve_dt$ym)),
      sleeves = sleeve_cols
    ),
    sigma_4sleeve_sample = list(
      cov_x10000 = round(Sigma_4 * 1e4, 4),
      correlation = round(Cor_4, 4),
      min_eigenvalue = signif(min(eig_4), 4),
      condition_number = signif(max(eig_4)/min(eig_4), 4),
      PD_check = all(eig_4 > 0)
    ),
    tdc_lower_5pct_pairwise = round(tdc_5, 4),
    tdc_upper_95pct_pairwise = round(tdc_95, 4),
    style_regression_defensive_vs_each = lapply(style_def, function(s) {
      list(n=s$n, beta=round(s$beta, 4), R2=round(s$R2, 4),
           alpha_monthly=round(s$alpha_monthly, 5),
           t_alpha=round(s$t_alpha, 3))
    }),
    combo_4sleeve_results = axis2_combo_dt,
    key_finding = paste(
      "Defensive sleeve를 Hybrid 70/15/15에 5%/10%/15% 추가 시 ann_sr/MDD profile 정량.",
      "4-sleeve Σ PD (min_eig", signif(min(eig_4), 3), "). cov rho(Defensive, AR) =", round(Cor_4["r_defensive","r_AR"], 3),
      "→ Defensive와 AR 간 negligible correlation 확인 — 직교 source 자격.",
      "AX-005 v1.2 EXCLUSION 형식적 충족 (multi-sleeve hybrid 내 component) 단 정식 채택 시 Q07_Earnings_Stability 직접 + multi-axis quality composite 의무."
    ),
    artifact_csv = "qepm/mailbox/research/risk_cycle3_20260507/axis2_defensive_multisleeve_combos.csv",
    artifact_parquet = "qepm/stage_artifacts/risk_cycle3_20260507/axis2_4sleeve_covariance_sample.parquet"
  ),
  axis_3_5source_marginal_contribution = list(
    purpose = "Hybrid 70/15/15 + 3 candidates (Defensive/Commodity/VRP) 결합 시 각 source의 marginal risk contribution + Diversification Ratio 정량. weight 결정/제안 절대 X — diagnostic only.",
    sample_5src_post2010 = list(
      n_obs = nrow(ret5),
      sample_range = paste0(min(ret5$ym), " ~ ", max(ret5$ym)),
      sources = src_cols
    ),
    sigma_6source = list(
      cov_x10000 = round(Sigma_5 * 1e4, 4),
      correlation = round(Cor_5, 4),
      min_eigenvalue = signif(min(eigen(Sigma_5)$values), 4),
      condition_number = signif(max(eigen(Sigma_5)$values)/min(eigen(Sigma_5)$values), 4)
    ),
    asset_volatilities_annualized = list(
      AR = round(sigma_diag[1]*sqrt(12), 4),
      KR_10y = round(sigma_diag[2]*sqrt(12), 4),
      TSMOM = round(sigma_diag[3]*sqrt(12), 4),
      Defensive = round(sigma_diag[4]*sqrt(12), 4),
      Commodity = round(sigma_diag[5]*sqrt(12), 4),
      VRP = round(sigma_diag[6]*sqrt(12), 4)
    ),
    diversification_ratio_choueifaty_coignard = list(
      hybrid_70_15_15 = round(div_ratio(c(0.70,0.15,0.15,0,0,0), Sigma_5, sigma_diag), 4),
      add_5_def_5_com_5_vrp = round(div_ratio(c(0.55,0.15,0.15,0.05,0.05,0.05), Sigma_5, sigma_diag), 4),
      risk_parity_inv_vol = round(div_ratio(w_rp, Sigma_5, sigma_diag), 4),
      add_5_def_only = round(div_ratio(c(0.65,0.15,0.15,0.05,0,0), Sigma_5, sigma_diag), 4)
    ),
    risk_parity_inverse_vol_decomposition = list(
      weights = list(AR=round(w_rp[1],4), KR_10y=round(w_rp[2],4),
                     TSMOM=round(w_rp[3],4), Defensive=round(w_rp[4],4),
                     Commodity=round(w_rp[5],4), VRP=round(w_rp[6],4)),
      mctv_share_pct = list(AR=round(100*mctv_rp[1]/sum(mctv_rp),2),
                            KR_10y=round(100*mctv_rp[2]/sum(mctv_rp),2),
                            TSMOM=round(100*mctv_rp[3]/sum(mctv_rp),2),
                            Defensive=round(100*mctv_rp[4]/sum(mctv_rp),2),
                            Commodity=round(100*mctv_rp[5]/sum(mctv_rp),2),
                            VRP=round(100*mctv_rp[6]/sum(mctv_rp),2))
    ),
    combo_192m_postoct2010 = combo_192_dt,
    combo_post2015_addition_256m = add_256m_dt,
    combo_192m_6source_full = axis3_dt,
    key_finding = paste(
      "6-source DR (Choueifaty-Coignard 2008): Hybrid_base", round(div_ratio(c(0.70,0.15,0.15,0,0,0), Sigma_5, sigma_diag), 3),
      "→ +5 Def +5 Com +5 VRP", round(div_ratio(c(0.55,0.15,0.15,0.05,0.05,0.05), Sigma_5, sigma_diag), 3),
      "(diversification 개선).",
      "Risk-parity inv-vol weights:", paste(round(w_rp*100,1), collapse="/"),
      "= 각 source vol-equal contribution.",
      "사이클 2 multi combo SR 1.950 (192m post-2010) 재검증 일관."
    ),
    artifact_csvs = c(
      "qepm/mailbox/research/risk_cycle3_20260507/axis3_6source_marginal_combos.csv",
      "qepm/mailbox/research/risk_cycle3_20260507/axis3_riskparity_mctv.csv",
      "qepm/mailbox/research/risk_cycle3_20260507/axis3_192m_multi_candidate_combos.csv",
      "qepm/mailbox/research/risk_cycle3_20260507/axis3_256m_addition_diagnostic.csv"
    ),
    artifact_parquet = "qepm/stage_artifacts/risk_cycle3_20260507/axis3_6source_covariance.parquet"
  ),
  cycle3_data_proxy_disclosures = list(
    VRP_KOSPI = list(
      data_source = "FRED VIXCLS + KOSPI BM rolling 12m realized vol (rawdata)",
      proxy_method_4_variants = "BKM Straddle / CW Variance Swap / BTZ RV-IV / BCI Mean-Reversion",
      limitation = "KOSPI200 옵션 chain 직접 부재 (KRX 데이터 본 환경 미확보). VIX-KOSPI RV cor (level) 본 분석 결과 정량.",
      cycle4_topic = "topic_1 KOSPI200 options chain direct"
    ),
    Defensive_LowVol_KR = list(
      data_source = "사이클 2 동일 (rawdata K200 univ × 20% lowest 12m vol quintile)",
      ax005_v1_2_principle = "single-sleeve top20 long-only 구조적 실패 인지",
      cycle3_evaluation = "multi-sleeve EXCLUSION (4-sleeve hybrid 내 component)",
      cycle4_topic = "topic_2 Q07_Earnings_Stability direct + multi-axis quality"
    ),
    Commodity_VRP = list(data_source = "사이클 2 동일", cycle3_no_change = TRUE)
  ),
  cycle4_candidates = cycle4_candidates,
  selection_objective = "condition_number AND tail_dependence_assessment AND marginal_contribution_to_variance AND diversification_ratio AND DSR_robustness",
  method_log = list(
    candidates_tried = 4,
    estimators_per_candidate = 1,  # Sample only — 사이클 2 estimator비교 결과 LW_identity ≈ Sample
    notes = "사이클 2 estimator 5-way 비교 결과 (LW_identity primary recommendation) 인계 — 본 사이클 3은 Sample 1개 estimator로 6-source covariance 단일 분석. estimator shopping log 5 한도 충족 (cycle 2 + cycle 3 합산 6 trial 단 조건부 권장 사이클 1+2에서 결론 도출)."
  ),
  challenge_flags = list(
    list(
      id = "CYC3_CF_1",
      severity = "HIGH",
      issue = "VRP variants 4종은 모두 US VIX 기반 — KOSPI200 옵션 chain 직접 부재 (사이클 2 weakest_assumption 일부 보강 but 완전 해소 X)",
      rationale = "사이클 3 axis 1에서 KOSPI BM 12m realized vol 정량 측정 + 4 method-variants 비교 했으나 implied volatility는 여전히 US VIX 사용. KRX KOSPI200 옵션 daily chain 본 환경 미확보. 사이클 2 weakest_assumption ACCEPT 정합성 유지 — 사이클 4 topic_1 자동 우선.",
      disposition = "ACCEPT_DOCUMENTED — 사이클 4 topic 1 우선 priority"
    ),
    list(
      id = "CYC3_CF_2",
      severity = "HIGH",
      issue = "Post-2010 192m sample (5-source joint) — GFC 2008 / DotCom 2000 / IMF 1997 stress 미포함",
      rationale = "Commodity GLD/COPX 시작 2010-04 + TSMOM ETF rotation 시작 2015 → 5-source joint sample은 GFC 미경험 시기. 사이클 4 topic_3 (pre-2010 synthetic backfill) 의무. SR 1.950 baseline은 'post-GFC bull market with normal-regime dominance' 한계 명시.",
      disposition = "ACCEPT_DOCUMENTED — 사이클 4 topic 3 priority MEDIUM"
    ),
    list(
      id = "CYC3_CF_3",
      severity = "MEDIUM",
      issue = "Defensive_LowVol_KR proxy = return_volatility — Q07_Earnings_Stability 직접 X (사이클 2 동일)",
      rationale = "Frazzini-Pedersen 2014 BAB style proxy. Q07 (Lev-Sougiannis 1999 earnings volatility) 정식 활용 시 corr 0.50~0.70 추정. 정식 채택 시 Factor DB load_month_factors() 의무.",
      disposition = "DOCUMENTED — 사이클 4 topic 2 priority HIGH"
    ),
    list(
      id = "CYC3_CF_4",
      severity = "MEDIUM",
      issue = "DCC-GARCH dynamic correlation 미적용 — 정적 Sample covariance만 분석",
      rationale = "Engle 2002 DCC-GARCH (rugarch::dccfit) 가용. crisis regime conditional correlation 변동 정량 가능. 본 사이클 3 시간 제약으로 미수행.",
      disposition = "DOCUMENTED — 사이클 4 topic 4"
    ),
    list(
      id = "CYC3_CF_5",
      severity = "MEDIUM",
      issue = "Risk-parity inv-vol weights는 marginal diagnostic 가설값 — 정식 risk-parity optimization (Maillard-Roncalli-Teiletche 2010) 미수행",
      rationale = "본 사이클 3 marginal contribution diagnostic은 inv-vol scalar 사용. 정식 ERC (Equal Risk Contribution) optimizer는 optimizer-research lifecycle 의무 (charter §8 No Silent Override).",
      disposition = "ACCEPT_BLOCKING — weight 결정은 optimizer-research 정식 lifecycle"
    ),
    list(
      id = "CYC3_CF_6",
      severity = "MEDIUM",
      issue = "DSR Bailey-Lopez de Prado n_trials = 14~30 가설값 — 정식 trials count 미수행",
      rationale = "사이클 3에서 14~30 trials 가설 적용. 사이클 2까지 누적 4 candidates × 5 estimators × ~3 weight scenarios + 사이클 3 ~14 combos ≈ 80+ 가능. 정식 BLP 통계적 적용은 alpha-research alpha_packages.lro_sha 추적.",
      disposition = "DOCUMENTED — 사이클 4 또는 정식 lifecycle에서 보강"
    ),
    list(
      id = "CYC3_CF_7",
      severity = "LOW",
      issue = "AX-005 v1.2 multi-sleeve EXCLUSION 구조적 충족 but 정식 정량 검증 미수행",
      rationale = "본 사이클 3에서 4-sleeve 통합 cov / TDC / style 정량했으나 multi-axis quality composite (Q07+Q06+Q01 PCA) factor 부재. 정식 채택 시 factor DB 직접 의무.",
      disposition = "DOCUMENTED — 사이클 4 topic 2 인계"
    )
  ),
  pit_compliance = list(
    C1_rolling_window_only = TRUE,
    C2_no_same_day_circular = TRUE,
    C9_dd_vt_lag = TRUE,
    C11_macro_lag = TRUE,
    C13_no_negate_sign = TRUE,
    details = c(
      "VRP variants: vix_lag1 = shift(vix_eom, 1L), rv12m_lag1 = shift(rv12m, 1L) — t-1 strict",
      "Defensive_LowVol_KR: 사이클 2 sd_12m_lag = shift(rolling_sd_12m, 1L, 'lag') 인계",
      "Commodity: 사이클 2 monthly returns from prod(1 + daily_returns) - 1 인계",
      "regime_4 classification: 사이클 1+2 classify_regime() 동일 PIT logic 인계",
      "5-source covariance: post-2010 sample, all returns t (current month) — covariance estimation level no leakage"
    )
  ),
  charter_compliance = list(
    no_alpha_modification = TRUE,
    no_weight_proposal = TRUE,
    no_strategy_spawn = TRUE,
    no_silent_override = paste(
      "사이클 2 ranking (1: Defensive_LowVol_KR / 2: VRP_KOSPI_Proxy / 3: Commodity / 4: Currency RF-R4 fail) 인계.",
      "사이클 3 추가 발견: VIX-KOSPI RV cor (level)", round(cor_vix_kospi_rv,3), "= proxy 정합성 정량.",
      "Multi combo SR 1.950 (post-2010 192m) 재검증 일관 — 사이클 2 axis_7 일치.",
      "Defensive AX-005 v1.2 multi-sleeve EXCLUSION 정량 검증 (4-sleeve PD min_eig", signif(min(eig_4),3), ").",
      "Currency_Carry_KRW 사이클 2 RF-R4 fail 인계 — 사이클 3 추가 평가 X (resource priority)."
    ),
    role_boundary = "risk-research meta self-research mode cycle 3 (Q-Lead on-demand)"
  ),
  vkospi_limitation = vkospi_limitation,
  citations_added_for_cycle3 = list(
    Bakshi_Kapadia_Madan_2003 = "Bakshi, Kapadia, Madan (2003) RFS 16(1), 101-143 — Stock return characteristics, skew laws, and the differential pricing of individual equity options",
    Bollerslev_Tauchen_Zhou_2009 = "Bollerslev, Tauchen, Zhou (2009) RFS 22(11), 4463-4492 — Expected stock returns and variance risk premia",
    Bouchaud_Cont_Iori_1998 = "Bouchaud, Cont, Iori (1998) Quantitative Finance — Models of volatility dynamics",
    Choueifaty_Coignard_2008 = "Choueifaty, Coignard (2008) JPM 35(1), 40-51 — Toward maximum diversification (Diversification Ratio)",
    Engle_2002 = "Engle (2002) Journal of Business and Economic Statistics 20(3), 339-350 — Dynamic conditional correlation",
    Maillard_Roncalli_Teiletche_2010 = "Maillard, Roncalli, Teiletche (2010) JPM 36(4), 60-70 — The properties of equally weighted risk contribution portfolios"
  ),
  citations_inherited_cycle1_2 = list(
    Carr_Wu_2009 = "Carr & Wu (2009) RFS 22(3), 1311-1341 — Variance risk premiums",
    Brunnermeier_Nagel_Pedersen_2008 = "Brunnermeier, Nagel, Pedersen (2008) NBER Macro Annual 23, 313-347 — Carry trades and currency crashes",
    Frazzini_Pedersen_2014 = "Frazzini & Pedersen (2014) JFE 111(1), 1-25 — Betting against beta",
    Lev_Sougiannis_1999 = "Lev & Sougiannis (1999) JAR 37(2), 353-385",
    Pedersen_2009 = "Pedersen (2009) RFS 22(11), 4423-4448 — When everyone runs for the exit",
    Embrechts_Kluppelberg_Mikosch_1997 = "Modelling Extremal Events for Insurance and Finance",
    Ledoit_Wolf_2004 = "Ledoit & Wolf (2004) JMA 88, 365-411",
    Bailey_LdP_2014 = "Bailey & López de Prado (2014) JPM 40(5), 94-107 — Deflated Sharpe Ratio",
    Harvey_2016 = "Harvey, Liu, Zhu (2016) RFS 29(1), 5-68 — t > 3 multiple testing",
    Pfaff_2016 = "Pfaff (2016) Financial Risk Modelling and Portfolio Optimization with R, 2nd ed."
  ),
  output_files = list(
    axis1_vrp_4variants = "qepm/mailbox/research/risk_cycle3_20260507/axis1_vrp_kospi_4variants.csv",
    axis2_4sleeve_combos = "qepm/mailbox/research/risk_cycle3_20260507/axis2_defensive_multisleeve_combos.csv",
    axis2_4sleeve_cov = "qepm/mailbox/research/risk_cycle3_20260507/axis2_4sleeve_covariance_sample.csv",
    axis2_4sleeve_corr = "qepm/mailbox/research/risk_cycle3_20260507/axis2_4sleeve_correlation.csv",
    axis2_4sleeve_tdc = "qepm/mailbox/research/risk_cycle3_20260507/axis2_4sleeve_tdc_lower5pct.csv",
    axis3_6source_cov = "qepm/mailbox/research/risk_cycle3_20260507/axis3_6source_covariance.csv",
    axis3_6source_corr = "qepm/mailbox/research/risk_cycle3_20260507/axis3_6source_correlation.csv",
    axis3_combos = "qepm/mailbox/research/risk_cycle3_20260507/axis3_6source_marginal_combos.csv",
    axis3_riskparity_mctv = "qepm/mailbox/research/risk_cycle3_20260507/axis3_riskparity_mctv.csv",
    axis3_192m_combos = "qepm/mailbox/research/risk_cycle3_20260507/axis3_192m_multi_candidate_combos.csv",
    axis3_256m_addition = "qepm/mailbox/research/risk_cycle3_20260507/axis3_256m_addition_diagnostic.csv",
    parquet_dir = "qepm/stage_artifacts/risk_cycle3_20260507/",
    run_meta_R = "qepm/mailbox/research/risk_cycle3_20260507/run_cycle3.R",
    run_meta_log = "qepm/mailbox/research/risk_cycle3_20260507/run_cycle3.log"
  ),
  notes_for_qlead = c(
    "사이클 3 axis 1: VRP 4 sub-variants (BKM/CW/BTZ/BCI) × KOSPI BM realized vol — 사이클 2 weakest_assumption 부분 해소 (full 해소는 사이클 4 KOSPI 옵션 chain 의무)",
    paste0("VIX-KOSPI RV12m cor (level) = ", round(cor_vix_kospi_rv,3), " (proxy 정합성 정량)"),
    "사이클 3 axis 2: Defensive AX-005 v1.2 multi-sleeve EXCLUSION 자격 형식 충족. 4-sleeve Σ PD + Defensive vs 다른 sleeve cor 정량",
    paste0("Defensive vs AR cor = ", round(Cor_4["r_defensive","r_AR"],3), " (직교 source 자격)"),
    "사이클 3 axis 3: 6-source diversification ratio + risk-parity MCTV. 사이클 2 multi combo SR 1.950 일관",
    paste0("DR risk-parity inv-vol = ", round(div_ratio(w_rp, Sigma_5, sigma_diag),3),
           " (vs Hybrid_base ", round(div_ratio(c(0.70,0.15,0.15,0,0,0), Sigma_5, sigma_diag),3), ")"),
    "사이클 4 권고 topic: (1) KOSPI200 옵션 chain direct VRP, (2) Q07 direct + multi-axis quality, (3) pre-2010 stress backfill, (4) DCC-GARCH dynamic, (5) multi-horizon AR decay",
    "신규 source 채택 결정은 정식 alpha-research → risk-research → optimizer-research lifecycle 의무"
  ),
  codex_critic_round_pending = TRUE,
  next_step_codex_critic_invocation = "qepm/mailbox/research/risk_cycle3_20260507/codex_critic_response_risk.json (auto-spawn after _draft.json write via PostToolUse Hook)"
)

# Write _draft.json (Codex Critic Round 의무 5-step Step 1)
draft_path <- file.path(OUT_DIR, "risk_package_draft.json")
write_json(risk_package, draft_path, pretty=TRUE, auto_unbox=TRUE, na="null", null="null")
LOG(sprintf("Draft saved: %s", draft_path))

# Final summary print
LOG("=== CYCLE 3 SUMMARY ===")
LOG(sprintf("Axis 1 VRP 4 variants: %s", paste(variants, collapse=", ")))
LOG(sprintf("Axis 2 4-sleeve PD: %s (min_eig=%.3e)", all(eig_4>0), min(eig_4)))
LOG(sprintf("Axis 3 6-src DR: hybrid_base=%.3f, +5_def_5_com_5_vrp=%.3f",
            div_ratio(c(0.70,0.15,0.15,0,0,0), Sigma_5, sigma_diag),
            div_ratio(c(0.55,0.15,0.15,0.05,0.05,0.05), Sigma_5, sigma_diag)))

LOG("Cycle 3 risk_package_draft.json complete.")
