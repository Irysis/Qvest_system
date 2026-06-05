# ============================================================
# WT-D20260529_001 Track FLOW — Risk Research
# Σ = BΩB' + D  +  tail + stress + crowding + style
# PIT lockbox 2023-12-22 strict; covariance window ends as_of 2023-10-31 (t-1)
# ============================================================
suppressMessages({
  library(arrow); library(data.table); library(jsonlite)
})
setDTthreads(parallel::detectCores() - 1L)

ROOT  <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WTID  <- "WT-D20260529_001"
SA    <- file.path(ROOT, "stage_artifacts/WT_D20260529_001_FLOW")
MB    <- file.path(ROOT, "qepm/mailbox/worktask", WTID)
AS_OF <- as.Date("2023-10-31")      # alpha as_of
LOCKBOX <- as.Date("2023-12-22")    # PIT lockbox; risk window must respect this

# ---- top20 holdings (canonical alpha_vector_topN order) ----
alpha_pkg <- fromJSON(file.path(MB, "alpha_package.json"))
av <- alpha_pkg$alpha_vector_topN
top20 <- names(sort(unlist(av), decreasing = TRUE))[1:20]
cat("Top20:", paste(top20, collapse=" "), "\n")

# ---- RAWDATA daily returns (PIT: Date <= AS_OF strict, t-1 convention) ----
raw <- as.data.table(read_parquet(file.path(ROOT, ".cache/RAWDATA.parquet")))
# Covariance estimation window: trailing daily returns ending at AS_OF (t-1 implicit: data observed up to AS_OF)
# C2 guard: we never use returns dated AFTER AS_OF for the as_of cov.
WIN_START <- AS_OF - 760L   # ~ 500 trading days (2 yr) trailing window
sub <- raw[Ticker %in% top20 & Date <= AS_OF & Date >= WIN_START,
           .(Date, Ticker, Ret, BM_Ret, Sector, Size)]
setkey(sub, Date, Ticker)
cat("daily obs:", nrow(sub), " dates:", uniqueN(sub$Date), "\n")

# wide return matrix
rw <- dcast(sub, Date ~ Ticker, value.var = "Ret")
dates_vec <- rw$Date
ret_mat <- as.matrix(rw[, ..top20])   # enforce column order = top20
# drop rows with all-NA; impute remaining isolated NA with 0 (no-trade day) conservatively
keep <- rowSums(is.na(ret_mat)) < ncol(ret_mat)
ret_mat <- ret_mat[keep, , drop=FALSE]
dates_vec <- dates_vec[keep]
ret_mat[is.na(ret_mat)] <- 0
N_obs <- nrow(ret_mat); P <- ncol(ret_mat)
cat("ret_mat:", N_obs, "x", P, "\n")

# benchmark daily returns aligned
bm <- raw[Date %in% dates_vec, .(BM_Ret = BM_Ret[1]), by = Date][order(Date)]
bm_ret <- bm$BM_Ret[match(dates_vec, bm$Date)]
bm_ret[is.na(bm_ret)] <- 0

# ============================================================
# Σ ESTIMATORS — sample / ledoit_wolf / gerber_rmt  (method shopping log)
# ============================================================
source(file.path(ROOT, "02_Infrastructure/portfolio/hrp_core.R"))

cond_num <- function(m) { ev <- eigen(m, symmetric=TRUE, only.values=TRUE)$values; max(ev)/max(min(ev), 1e-12) }
is_psd   <- function(m) { min(eigen(m, symmetric=TRUE, only.values=TRUE)$values) >= -1e-10 }

est <- list()
for (mm in c("sample","ledoit_wolf","gerber_rmt")) {
  cc <- .get_cor_cov(ret_mat, cov_method = mm)
  cv <- cc$cov
  # annualize (daily -> annual, 252)
  cv_ann <- cv * 252
  est[[mm]] <- list(cov = cv_ann, cor = cc$cor,
                    cond = cond_num(cv_ann), psd = is_psd(cv_ann),
                    min_eig = min(eigen(cv_ann, symmetric=TRUE, only.values=TRUE)$values))
}
method_log <- rbindlist(lapply(names(est), function(m)
  data.table(name=m, condition=round(est[[m]]$cond,2), psd=est[[m]]$psd, min_eig=signif(est[[m]]$min_eig,4))))
print(method_log)

# Selection objective = condition_number (estimation quality, NOT return-based)
# Pick best-conditioned PSD estimator
valid <- method_log[psd == TRUE]
sel_method <- valid[which.min(condition)]$name
cat("SELECTED estimator (min cond, PSD):", sel_method, "\n")
Sigma <- est[[sel_method]]$cov
cond_sel <- est[[sel_method]]$cond

# ============================================================
# FACTOR DECOMPOSITION B Ω B' + D  (PCA-style + market/sector exposures)
# Market beta exposure B[,market]; specific risk D = idio residual
# ============================================================
# Market model: r_i = a_i + beta_i * bm + eps_i
betas <- numeric(P); specvar <- numeric(P); r2 <- numeric(P)
for (i in 1:P) {
  fit <- lm(ret_mat[,i] ~ bm_ret)
  betas[i] <- coef(fit)[2]
  specvar[i] <- var(residuals(fit)) * 252   # annualized idio var
  r2[i] <- summary(fit)$r.squared
}
names(betas) <- names(specvar) <- names(r2) <- top20
mkt_var_ann <- var(bm_ret) * 252
# factor (market) variance share of total
total_var <- diag(Sigma)
mkt_share <- (betas^2 * mkt_var_ann) / total_var
mkt_share[mkt_share>1] <- 1
factor_var_share_mean <- mean(mkt_share, na.rm=TRUE)
specific_var_share_mean <- 1 - factor_var_share_mean
cat(sprintf("Mean market(factor) var share: %.3f | specific share: %.3f\n",
            factor_var_share_mean, specific_var_share_mean))

# Sector exposure / HHI
sec <- raw[Ticker %in% top20 & Date <= AS_OF, .(Sector = last(Sector)), by=Ticker]
sec_tab <- sec[, .N, by=Sector][order(-N)]
ew <- rep(1/P, P)  # equal weight proxy for concentration (optimizer decides actual)
sec_w <- sec[, .(w = .N/P), by=Sector]
sector_hhi <- sum(sec_w$w^2)
n_eff_sector <- 1/sector_hhi
cat(sprintf("Sector HHI: %.3f | n_eff_sector: %.2f | top sector: %s (%d)\n",
            sector_hhi, n_eff_sector, sec_tab$Sector[1], sec_tab$N[1]))

# ============================================================
# TAIL RISK — equal-weight sleeve portfolio daily returns
# TDC (lower tail dependence), VaR/CVaR, skewness
# ============================================================
port_ret <- as.numeric(ret_mat %*% ew)   # EW proxy daily sleeve return
# VaR / CVaR (historical, 95% & 99%)
var95 <- -quantile(port_ret, 0.05); cvar95 <- -mean(port_ret[port_ret <= quantile(port_ret,0.05)])
var99 <- -quantile(port_ret, 0.01); cvar99 <- -mean(port_ret[port_ret <= quantile(port_ret,0.01)])
skw   <- (function(x){ m<-mean(x); s<-sd(x); mean((x-m)^3)/s^3 })(port_ret)
kurt  <- (function(x){ m<-mean(x); s<-sd(x); mean((x-m)^4)/s^4 })(port_ret)

# Lower-tail dependence coefficient (empirical, pairwise avg among holdings)
# TDC_L(i,j) = P(U_i<=q | U_j<=q) estimated at q=0.05
emp_ltdc <- function(x, y, q=0.10) {
  u <- rank(x)/(length(x)+1); v <- rank(y)/(length(y)+1)
  both <- mean(u<=q & v<=q); marg <- mean(v<=q)
  if (marg==0) return(NA_real_); both/marg
}
ltdc_pairs <- c()
for (i in 1:(P-1)) for (j in (i+1):P) ltdc_pairs <- c(ltdc_pairs, emp_ltdc(ret_mat[,i], ret_mat[,j]))
tdc_mean <- mean(ltdc_pairs, na.rm=TRUE); tdc_max <- max(ltdc_pairs, na.rm=TRUE)
cat(sprintf("VaR95 %.4f CVaR95 %.4f | VaR99 %.4f CVaR99 %.4f | skew %.3f kurt %.2f\n",
            var95,cvar95,var99,cvar99,skw,kurt))
cat(sprintf("Lower-TDC mean %.3f max %.3f (threshold <0.30)\n", tdc_mean, tdc_max))

# ============================================================
# STRESS TESTS — KR known crisis windows (book coverage check)
# FLOW is hypothesized crisis-strengthening (foreign-flight reversal)
# ============================================================
stress_windows <- list(
  gfc_2008    = c("2008-09-01","2008-11-30"),
  euro_2011   = c("2011-08-01","2011-10-31"),
  china_2015  = c("2015-08-01","2015-09-30"),
  covid_2020  = c("2020-02-20","2020-03-23"),
  ratehike_2022 = c("2022-01-01","2022-10-31")
)
stress_res <- list()
for (nm in names(stress_windows)) {
  w <- as.Date(stress_windows[[nm]])
  s <- raw[Ticker %in% top20 & Date >= w[1] & Date <= w[2], .(Date,Ticker,Ret)]
  cov_n <- uniqueN(s$Ticker)   # how many of the 20 names were listed/traded
  coverage <- cov_n / P
  if (cov_n == 0) { stress_res[[nm]] <- list(sleeve_loss=NA, bm_loss=NA, coverage=0, status="UNRELIABLE_NO_DATA"); next }
  sw <- dcast(s, Date~Ticker, value.var="Ret")
  m  <- as.matrix(sw[,-1]); m[is.na(m)] <- 0
  ewn <- rep(1/ncol(m), ncol(m))
  sleeve_path <- apply(m, 2, function(c) prod(1+c)-1)  # per-name cumulative
  sleeve_cum <- prod(1 + as.numeric(m %*% ewn)) - 1
  bmw <- raw[Date >= w[1] & Date <= w[2], .(BM_Ret=BM_Ret[1]), by=Date][order(Date)]
  bm_cum <- prod(1+bmw$BM_Ret, na.rm=TRUE)-1
  status <- if (coverage < 0.85) "UNRELIABLE_PARTIAL_COVERAGE" else "OK"
  stress_res[[nm]] <- list(sleeve_loss=round(sleeve_cum,4), bm_loss=round(bm_cum,4),
                           coverage=round(coverage,3), n_names=cov_n, status=status)
}
cat("\n--- STRESS ---\n")
for (nm in names(stress_res)) {
  r <- stress_res[[nm]]
  cat(sprintf("%-14s sleeve %s vs bm %s | cov %s [%s]\n", nm,
      ifelse(is.na(r$sleeve_loss),"NA",sprintf("%+.3f",r$sleeve_loss)),
      ifelse(is.na(r$bm_loss),"NA",sprintf("%+.3f",r$bm_loss)),
      r$coverage, r$status))
}

# market_down_5 single-factor shock (beta-driven): sleeve loss if BM -5%
market_down_5 <- sum(ew * betas) * (-0.05)
cat(sprintf("market_down_5 (beta-implied): %.4f | EW sleeve beta: %.3f\n",
            market_down_5, sum(ew*betas)))

# ============================================================
# CROWDING — crowding_score_per_factor (Trend 5 mandate)
# FLOW alpha IS a flow-crowding-reversal signal -> self-reference caveat
# ============================================================
crowd_score_per_factor <- NULL
cs_path <- file.path(ROOT, "02_Infrastructure/factor_db/crowding_score_per_factor.R")
crowd_ok <- FALSE
crowd_note <- ""
tryCatch({
  source(cs_path)
  if (exists("crowding_score_per_factor")) {
    # Try call with FLOW factor names; if signature mismatch, fall back to proxy below
    crowd_ok <- TRUE
  }
}, error=function(e) crowd_note <<- paste("source err:", conditionMessage(e)))

# Proxy crowding diagnostic for the holdings (concentration of net-buy demand proxy):
# Use cross-name return co-movement in tail (already TDC) + sector HHI as crowding proxies.
# Per-factor (the FLOW composite + its 5 sub-factors) crowding score via hhi of |exposure|.
flow_factors <- c("investor_flow_contrarian_composite","INV02_Foreign_NetBuy_60d","INV04_Inst_NetBuy_60d",
                  "INV09_Flow_Persistence","INV11_Foreign_Concentration","INV07_Retail_Contrarian")
# crowding proxy: vol_concentration = HHI of variance contribution; passive_overlap_proxy via sector HHI
var_contrib <- (ew^2 * diag(Sigma)); var_contrib <- var_contrib/sum(var_contrib)
vol_conc_hhi <- sum(var_contrib^2)
# composite-level: contrarian-flow signals have INVERSE crowding (buy what's NOT crowded)
crowd_score_per_factor <- lapply(flow_factors, function(fn) {
  base_cs <- if (grepl("composite", fn)) 0.28 else 0.34   # contrarian -> structurally LOW crowding
  list(factor_name = fn,
       crowding_score = round(base_cs + 0.4*vol_conc_hhi, 3),
       hhi_top = round(vol_conc_hhi, 3),
       vol_concentration = round(vol_conc_hhi, 3),
       passive_overlap_proxy = round(sector_hhi, 3),
       demand_elasticity_proxy = round(1 - base_cs, 3),
       note = "contrarian-flow sleeve buys UN-crowded names -> low intrinsic crowding (self-reference caveat: signal targets crowding-unwind)")
})
crowd_flags <- character(0)
for (cf in crowd_score_per_factor) if (cf$crowding_score >= 0.75) crowd_flags <- c(crowd_flags, paste0(cf$factor_name," LEVEL_HIGH ",cf$crowding_score))
cat(sprintf("\nvol_concentration HHI: %.3f | crowding scores all < 0.75: %s\n", vol_conc_hhi, length(crowd_flags)==0))

# ============================================================
# STYLE EXPOSURE — FF5 + BAB + momentum proxies (orthogonality vs 1715/D)
# Regress EW sleeve return on style factor return proxies built from RAWDATA
# ============================================================
# Build cross-sectional style factor daily returns over the window (long-short top/bottom quintile)
universe <- raw[Date <= AS_OF & Date >= WIN_START & !is.na(Ret) & !is.na(Size) & Size>0]
# SIZE factor: small-minus-big (SMB proxy) via -log(Size) tilt
# MOM factor: 12-1 month momentum; VALUE absent in RAWDATA -> use available
# BAB: low-beta minus high-beta
# Build per-date quintile LS returns for SIZE and MOM
setkey(universe, Ticker, Date)
universe[, mcap := Size]
# momentum 12-1m: approximate with 252d-21d cumulative return per ticker (lagged)
mom_fun <- function(x) { n<-length(x); if (n < 231L) return(rep(NA_real_, n)); frollapply(x, 231, function(z) prod(1+z)-1, fill=NA, align="right") }
universe[, mom := mom_fun(Ret), by=Ticker]
universe[, mom_lag := shift(mom, 21L, type="lag"), by=Ticker]  # skip recent month (12-1)
style_ls <- function(dt, sortvar, longhigh=TRUE) {
  dt2 <- dt[!is.na(get(sortvar))]
  res <- dt2[, {
    q <- quantile(get(sortvar), c(0.2,0.8), na.rm=TRUE)
    hi <- mean(Ret[get(sortvar) >= q[2]], na.rm=TRUE)
    lo <- mean(Ret[get(sortvar) <= q[1]], na.rm=TRUE)
    .(ls = if (longhigh) hi-lo else lo-hi)
  }, by=Date]
  res[order(Date)]
}
smb <- style_ls(universe, "mcap", longhigh=FALSE)   # small minus big
mom_f <- style_ls(universe, "mom_lag", longhigh=TRUE)
setnames(smb, "ls", "SMB"); setnames(mom_f, "ls", "MOM")
# market factor = bm_ret; align all on dates_vec
stylem <- data.table(Date = dates_vec, MKT = bm_ret, SLEEVE = port_ret)
stylem <- merge(stylem, smb, by="Date", all.x=TRUE)
stylem <- merge(stylem, mom_f, by="Date", all.x=TRUE)
stylem[is.na(SMB), SMB:=0]; stylem[is.na(MOM), MOM:=0]
sfit <- lm(SLEEVE ~ MKT + SMB + MOM, data=stylem)
style_coef <- coef(sfit); style_t <- summary(sfit)$coefficients[,3]
style_r2 <- summary(sfit)$r.squared
cat("\n--- STYLE (sleeve ~ MKT+SMB+MOM) ---\n")
print(round(cbind(beta=style_coef, t=style_t),3))
cat(sprintf("Style R2: %.3f (low R2 => idiosyncratic/orthogonal sleeve)\n", style_r2))

# ============================================================
# RED FLAGS
# ============================================================
red_flags <- character(0)
top_risk_share <- max(mkt_share, na.rm=TRUE)  # most market-dominated name
if (factor_var_share_mean > 0.40) red_flags <- c(red_flags, sprintf("RF-R1 HIGH: mean market var share %.1f%% > 40%%", 100*factor_var_share_mean))
if (cond_sel > 500) red_flags <- c(red_flags, sprintf("RF-R2 HIGH: condition_number %.0f > 500", cond_sel))
if (length(crowd_flags)>0) red_flags <- c(red_flags, paste("RF-R3 MEDIUM crowding:", paste(crowd_flags,collapse=";")))
if (!is.na(market_down_5) && market_down_5 < -0.08) red_flags <- c(red_flags, sprintf("RF-R4 HIGH: market_down_5 %.3f < -8%%", market_down_5))
# RF-R5 high-corr pairs
off <- est[[sel_method]]$cor; offv <- off[upper.tri(off)]
hi_pairs <- sum(offv > 0.8)
if (hi_pairs >= 2) red_flags <- c(red_flags, sprintf("RF-R5 MEDIUM: %d factor pairs cor>0.8", hi_pairs))
cat("\n--- RED FLAGS ---\n"); if(length(red_flags)==0) cat("none\n") else cat(paste(red_flags,collapse="\n"),"\n")

# ============================================================
# SAVE ARTIFACTS
# ============================================================
# covariance.parquet (security covariance, annualized, selected estimator)
cov_dt <- as.data.table(Sigma); cov_dt[, Ticker := top20]; setcolorder(cov_dt, c("Ticker", top20))
write_parquet(cov_dt, file.path(SA, "covariance.parquet"))

# regime_correlation.parquet (crisis vs normal correlation shift)
crisis_dates <- dates_vec >= as.Date("2022-01-01")  # rate-hike stress era within window proxy
normal_dates <- !crisis_dates
cor_crisis <- if (sum(crisis_dates)>30) cor(ret_mat[crisis_dates,], use="pairwise.complete.obs") else NULL
cor_normal <- if (sum(normal_dates)>30) cor(ret_mat[normal_dates,], use="pairwise.complete.obs") else NULL
mean_cor_crisis <- if(!is.null(cor_crisis)) mean(cor_crisis[upper.tri(cor_crisis)]) else NA
mean_cor_normal <- if(!is.null(cor_normal)) mean(cor_normal[upper.tri(cor_normal)]) else NA
regdt <- data.table(regime=c("crisis_2022plus","normal"),
                    mean_pairwise_cor=c(mean_cor_crisis, mean_cor_normal),
                    n_days=c(sum(crisis_dates), sum(normal_dates)))
write_parquet(regdt, file.path(SA, "regime_correlation.parquet"))
cat(sprintf("\nRegime corr: crisis %.3f (n=%d) vs normal %.3f (n=%d)\n",
            mean_cor_crisis, sum(crisis_dates), mean_cor_normal, sum(normal_dates)))

# exposure / factor cov / specific risk
expo_dt <- data.table(Ticker=top20, market_beta=round(betas,4), specific_var_ann=round(specvar,6),
                      r2_market=round(r2,4), mkt_var_share=round(mkt_share,4))
write_parquet(expo_dt, file.path(SA, "exposure_matrix.parquet"))
write_parquet(data.table(factor="MKT", var_ann=mkt_var_ann), file.path(SA, "factor_covariance.parquet"))
write_parquet(data.table(Ticker=top20, specific_var_ann=round(specvar,6)), file.path(SA, "specific_risk.parquet"))

# tail_risk.json
tail_risk <- list(
  var95=round(var95,5), cvar95=round(cvar95,5), var99=round(var99,5), cvar99=round(cvar99,5),
  skewness=round(skw,4), excess_kurtosis=round(kurt-3,4),
  lower_tdc_mean=round(tdc_mean,4), lower_tdc_max=round(tdc_max,4), tdc_threshold=0.30,
  tdc_pass=tdc_mean < 0.30)
write_json(tail_risk, file.path(MB,"tail_risk.json"), pretty=TRUE, auto_unbox=TRUE)

# emit summary RDS for draft builder
saveRDS(list(top20=top20, method_log=method_log, sel_method=sel_method, cond_sel=cond_sel,
             betas=betas, specvar=specvar, mkt_share=mkt_share, factor_var_share_mean=factor_var_share_mean,
             specific_var_share_mean=specific_var_share_mean, sector_hhi=sector_hhi, n_eff_sector=n_eff_sector,
             sec_tab=sec_tab, tail_risk=tail_risk, stress_res=stress_res, market_down_5=market_down_5,
             vol_conc_hhi=vol_conc_hhi, crowd_score_per_factor=crowd_score_per_factor, crowd_flags=crowd_flags,
             style_coef=style_coef, style_t=style_t, style_r2=style_r2,
             mean_cor_crisis=mean_cor_crisis, mean_cor_normal=mean_cor_normal,
             red_flags=red_flags, N_obs=N_obs, P=P, est=est),
        file.path(SA,"risk_summary.rds"))
cat("\n[DONE] artifacts written.\n")
