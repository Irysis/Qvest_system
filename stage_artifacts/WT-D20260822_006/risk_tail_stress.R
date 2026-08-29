# ============================================================================
# Risk Research STEP 5 — tail (EVT-GPD/Hill), stress, crowding, style/sector
# WT-D20260822_006. PIT: est window < 2026-07-01.
# ============================================================================
suppressMessages({library(arrow); library(dplyr); library(data.table); library(jsonlite)})
QM <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
WTID <- "WT-D20260822_006"; OUT <- file.path("stage_artifacts", WTID); SIG <- as.Date("2026-07-01")
C <- readRDS(file.path(OUT, "risk_core.rds"))
Sigma <- C$Sigma; keep_tick <- C$keep_tick; avec_k <- C$avec_k; aw <- C$aw
mat <- C$mat; est_dates <- C$est_dates; snap_k <- C$snap_k; beta_blume <- C$beta_blume

# ---- attention-weighted signal series (diagnostic proxy; NOT a portfolio weight) ----
# Long/short signal exposure normalized to |alpha| attention (sign preserved).
sw <- avec_k / sum(abs(avec_k))     # signed, sums(|.|)=1 ; measures co-movement of the SIGNAL
port_daily <- as.numeric(mat %*% sw)     # daily signal-portfolio return (long-short view)
# long-only attention view (what the book would actually hold direction): positive-alpha, |a| weight
long_mask <- avec_k > 0
lw <- ifelse(long_mask, avec_k, 0); lw <- lw / sum(lw)
long_daily <- as.numeric(mat %*% lw)

# ============================================================================
# TAIL RISK — empirical + EVT-GPD (POT) + Hill alpha, on long-only attention series
# ============================================================================
gpd_fit <- function(x, thr_q = 0.95) {
  # losses = negative returns; fit GPD to exceedances over threshold
  loss <- -x
  u <- quantile(loss, thr_q, na.rm = TRUE)
  exc <- loss[loss > u] - u
  n <- length(loss); nu <- length(exc)
  if (nu < 30) return(list(ok = FALSE, n_exc = nu))
  # MoM/PWM estimator for GPD (xi, beta) — robust, no optim dependency
  m1 <- mean(exc); m2 <- mean(exc^2)
  xi   <- 0.5 * (1 - m1^2 / (m2 - m1^2))     # method of moments
  beta <- 0.5 * m1 * (m1^2 / (m2 - m1^2) + 1)
  # tail VaR/ES at level p:  VaR = u + beta/xi*(( (n/nu)*(1-p) )^(-xi) -1)
  qf <- function(p) {
    t <- (n/nu) * (1 - p)
    if (abs(xi) < 1e-6) u + beta * (-log(t)) else u + beta/xi * (t^(-xi) - 1)
  }
  var_p <- function(p) qf(p)
  es_p  <- function(p) { v <- qf(p); (v + beta - xi*u) / (1 - xi) }  # GPD ES for xi<1
  list(ok = TRUE, xi = xi, beta = beta, u = as.numeric(u), n_exc = nu, n = n,
       var95 = var_p(0.95), var99 = var_p(0.99),
       es95  = es_p(0.95),  es99  = es_p(0.99))
}
hill_alpha <- function(x, k_frac = 0.05) {
  loss <- sort(-x, decreasing = TRUE); loss <- loss[loss > 0]
  k <- max(10L, floor(length(loss) * k_frac))
  if (length(loss) < k + 1) return(NA_real_)
  xk <- loss[k+1]
  1 / mean(log(loss[1:k] / xk))     # tail index alpha (>2 = finite variance)
}
emp_var <- function(x, p) -quantile(x, 1 - p, na.rm = TRUE)
emp_es  <- function(x, p) { v <- quantile(x, 1 - p, na.rm = TRUE); -mean(x[x <= v], na.rm = TRUE) }

g_long <- gpd_fit(long_daily)
tail_risk <- list(
  series = "long_only_attention_daily",
  n_days = length(long_daily),
  empirical = list(
    var95 = as.numeric(emp_var(long_daily, .95)), var99 = as.numeric(emp_var(long_daily, .99)),
    es95  = as.numeric(emp_es(long_daily, .95)),  es99  = as.numeric(emp_es(long_daily, .99)),
    skew  = as.numeric(e1071_skew <- (function(z){m<-mean(z);s<-sd(z);mean((z-m)^3)/s^3})(long_daily)),
    kurt  = as.numeric((function(z){m<-mean(z);s<-sd(z);mean((z-m)^4)/s^4})(long_daily))
  ),
  evt_gpd = if (g_long$ok) list(
    threshold_q = 0.95, xi = g_long$xi, beta = g_long$beta, n_exceed = g_long$n_exc,
    var95 = g_long$var95, var99 = g_long$var99, es95 = g_long$es95, es99 = g_long$es99,
    interpretation = if (g_long$xi > 0) "heavy_tail_xi>0" else "light_tail"
  ) else list(ok = FALSE, reason = "insufficient exceedances"),
  hill_alpha_5pct = hill_alpha(long_daily)
)
cat(sprintf("[TAIL] emp VaR99=%.4f ES99=%.4f | GPD xi=%.3f VaR99=%.4f ES99=%.4f | Hill a=%.2f\n",
    tail_risk$empirical$var99, tail_risk$empirical$es99,
    if(g_long$ok)g_long$xi else NA, if(g_long$ok)g_long$var99 else NA,
    if(g_long$ok)g_long$es99 else NA, tail_risk$hill_alpha_5pct))

# ============================================================================
# STRESS TESTS — historical scenario replay on long-only attention portfolio
# Coverage = fraction of alpha names with returns in the scenario window.
# ============================================================================
r <- open_dataset(".cache/RAWDATA.parquet")
scen <- list(
  gfc_2008        = c("2008-09-01","2009-03-31"),
  eudebt_2011     = c("2011-08-01","2011-10-31"),
  china_2015      = c("2015-06-01","2015-09-30"),
  covid_2020      = c("2020-02-19","2020-03-23"),
  ratehike_2022   = c("2022-01-01","2022-10-31"),
  kr_bear_2018    = c("2018-10-01","2018-12-31")
)
# per-scenario: cumulative long-only attention return using CURRENT alpha weights (lw)
stress <- list()
for (nm in names(scen)) {
  d0 <- as.Date(scen[[nm]][1]); d1 <- as.Date(scen[[nm]][2])
  sub <- r %>% filter(Date >= d0) %>% filter(Date <= d1) %>%
         filter(Ticker %in% keep_tick) %>% select(Date, Ticker, Ret) %>% collect() %>% as.data.table()
  if (nrow(sub) == 0) { stress[[nm]] <- list(coverage=0, cum_ret=NA, reliable=FALSE); next }
  ws <- dcast(sub, Date ~ Ticker, value.var = "Ret")
  m2 <- as.matrix(ws[,-1,drop=FALSE])
  present <- colnames(m2)
  cov_frac <- length(present) / length(keep_tick)
  m2[is.na(m2)] <- 0
  lw_s <- lw[present]; lw_s <- lw_s / sum(lw_s)   # renormalize to available names
  pr <- as.numeric(m2 %*% lw_s)
  cum <- prod(1 + pr) - 1
  # benchmark cum for the window
  bmw <- r %>% filter(Date >= d0) %>% filter(Date <= d1) %>% select(Date, BM_Ret) %>%
         distinct() %>% collect() %>% as.data.table()
  bm_cum <- prod(1 + ifelse(is.na(bmw$BM_Ret),0,bmw$BM_Ret)) - 1
  stress[[nm]] <- list(coverage = round(cov_frac,3), cum_ret = round(cum,4),
                       bm_cum = round(bm_cum,4), active = round(cum - bm_cum,4),
                       reliable = cov_frac >= 0.85,
                       note = if (cov_frac < 0.85)
                         sprintf("UNRELIABLE — book coverage %.0f%% < 85%% (partial listing artifact)", cov_frac*100)
                         else "coverage_ok")
}
# instantaneous market shock: portfolio beta * -5%
port_beta <- sum(lw * beta_blume)
stress$market_down_5 <- list(coverage = 1, cum_ret = round(-0.05 * port_beta, 4),
                             method = "portfolio_beta_x_shock", port_beta = round(port_beta,3),
                             reliable = TRUE)
cat("[STRESS] scenarios:\n")
for (nm in names(stress)) {
  s <- stress[[nm]]
  cat(sprintf("  %-16s cov=%.2f cum=%s active=%s reliable=%s\n", nm,
      ifelse(is.null(s$coverage),1,s$coverage),
      ifelse(is.null(s$cum_ret),"NA",s$cum_ret),
      ifelse(is.null(s$active),"-",s$active), s$reliable))
}

# ============================================================================
# CROWDING per-factor (Acadian 2026) — required field
# alpha_package factors: F1_state_conditional_K5_composite (core), F2 inherited
# Build factor_exposures for crowding_score_per_factor():
#   proxy exposure = signed alpha (F1 core signal), and its magnitude concentration
# ============================================================================
source("02_Infrastructure/factor_db/crowding_score_per_factor.R")
# liquidity/size for concentration axes (20d avg turnover proxy from est window last 20d)
liq_sub <- r %>% filter(Date < SIG) %>% select(Date, Ticker, Vol, Close, Size) %>%
           filter(Ticker %in% keep_tick) %>% collect() %>% as.data.table()
liq_sub <- liq_sub[order(Ticker, -as.integer(Date))]
liq20 <- liq_sub[, .(advt = mean(head(Vol,20)*head(Close,20), na.rm=TRUE),
                     size = head(Size,1)), by = Ticker]
liq20 <- liq20[match(keep_tick, Ticker)]

# ---- contract helper: long-format Ticker/factor_name/exposure + RAWDATA ----
fe_long <- rbindlist(list(
  data.table(Ticker=keep_tick, factor_name="F1_state_conditional_K5_composite",
             exposure=as.numeric(avec_k)),
  data.table(Ticker=keep_tick, factor_name="F2_selection_trajectory_inherited",
             exposure=as.numeric(scale(rank(avec_k))))
))
RD_pit <- r %>% filter(Date < SIG) %>% select(Date,Ticker,Close,Vol,Size) %>%
          filter(Ticker %in% keep_tick) %>% collect() %>% as.data.table()
crowd_contract <- tryCatch(
  crowding_score_per_factor(factor_exposures = fe_long, sig_date = as.Date("2026-06-30"),
                            RAWDATA = RD_pit, top_n = 20L),
  error = function(e) { cat("[crowd] contract helper error:", conditionMessage(e), "\n"); NULL })
if (!is.null(crowd_contract)) { cat("[CROWD] contract helper OK:\n"); print(crowd_contract) }

# manual crowding if helper signature mismatch: HHI of |exposure| + vol concentration
manual_crowd <- function(expo, adv) {
  a <- abs(expo); a[is.na(a)] <- 0
  wtop <- a / sum(a)
  hhi <- sum(wtop^2)                       # exposure concentration (Herfindahl)
  n_eff <- 1 / hhi                         # effective breadth
  # vol concentration = share of |expo| mass in top-decile by adv (illiquid crowding)
  dec <- adv <= quantile(adv, 0.10, na.rm = TRUE)
  vol_conc <- sum(wtop[dec], na.rm = TRUE)
  # passive overlap proxy = share of exposure in large-cap (index) names
  big <- liq20$size >= quantile(liq20$size, 0.80, na.rm = TRUE)
  passive <- sum(wtop[big], na.rm = TRUE)
  list(hhi_top = hhi, n_effective = n_eff, vol_concentration = vol_conc,
       passive_overlap_proxy = passive)
}
mc1 <- manual_crowd(as.numeric(avec_k), liq20$advt)
mc2 <- manual_crowd(as.numeric(scale(rank(avec_k))), liq20$advt)
# crowding_score: composite [0,1] = mean of normalized (hhi_scaled, vol_conc, passive)
cs <- function(m) {
  hhi_scaled <- min(1, m$hhi_top * length(keep_tick) / 3)  # 1 when HHI = 3x uniform
  round(min(1, mean(c(hhi_scaled, m$vol_concentration, m$passive_overlap_proxy))), 3)
}
crowding_per_factor <- list(
  list(factor_name="F1_state_conditional_K5_composite", crowding_score=cs(mc1),
       hhi_top=round(mc1$hhi_top,4), n_effective=round(mc1$n_effective,1),
       vol_concentration=round(mc1$vol_concentration,3),
       passive_overlap_proxy=round(mc1$passive_overlap_proxy,3),
       demand_elasticity_proxy=round(1 - mc1$vol_concentration,3),
       alert = if (cs(mc1) >= 0.75) "LEVEL_HIGH" else "OK"),
  list(factor_name="F2_selection_trajectory_inherited", crowding_score=cs(mc2),
       hhi_top=round(mc2$hhi_top,4), n_effective=round(mc2$n_effective,1),
       vol_concentration=round(mc2$vol_concentration,3),
       passive_overlap_proxy=round(mc2$passive_overlap_proxy,3),
       demand_elasticity_proxy=round(1 - mc2$vol_concentration,3),
       alert = if (cs(mc2) >= 0.75) "LEVEL_HIGH" else "OK")
)
cat(sprintf("[CROWD] F1 score=%.3f (n_eff=%.0f) | F2 score=%.3f (n_eff=%.0f)\n",
    crowding_per_factor[[1]]$crowding_score, crowding_per_factor[[1]]$n_effective,
    crowding_per_factor[[2]]$crowding_score, crowding_per_factor[[2]]$n_effective))

# ============================================================================
# STYLE / SECTOR HHI + concentration + cap-tier decomposition
# ============================================================================
sec <- snap_k$Sector; sec[is.na(sec)] <- "UNKNOWN"
# long-only attention exposure by sector
sec_w <- tapply(lw, sec, sum); sec_w <- sec_w[!is.na(sec_w)]
sector_hhi <- sum((sec_w/sum(sec_w))^2)
sector_n_eff <- 1/sector_hhi
# name concentration
name_hhi <- sum((lw)^2); name_n_eff <- 1/name_hhi
# cap-tier: MEGA/MID/SMALL by Size terciles of the alpha universe
sz <- snap_k$Size
brk <- quantile(sz, c(1/3, 2/3), na.rm = TRUE)
tier <- ifelse(sz >= brk[2], "MEGA", ifelse(sz >= brk[1], "MID", "SMALL"))
tier_risk_share <- tapply(lw, tier, sum)      # active risk proxy = holding weight share
tier_alpha_share <- tapply(abs(avec_k), tier, sum) / sum(abs(avec_k))
cat(sprintf("[STYLE] sector HHI=%.3f (n_eff=%.1f) | name HHI=%.4f (n_eff=%.1f)\n",
    sector_hhi, sector_n_eff, name_hhi, name_n_eff))

# prefer contract helper values when available (overwrite manual score/components)
if (!is.null(crowd_contract) && is.data.frame(crowd_contract) && nrow(crowd_contract) >= 1) {
  cc <- as.data.table(crowd_contract)
  for (i in seq_along(crowding_per_factor)) {
    fn <- crowding_per_factor[[i]]$factor_name
    row <- cc[factor_name == fn]
    if (nrow(row) == 1 && !is.na(row$crowding_score)) {
      crowding_per_factor[[i]]$crowding_score_contract <- round(as.numeric(row$crowding_score),3)
      if (!is.null(row$hhi_top) && !is.na(row$hhi_top))
        crowding_per_factor[[i]]$hhi_top_contract <- round(as.numeric(row$hhi_top),4)
      if (!is.null(row$vol_concentration) && !is.na(row$vol_concentration))
        crowding_per_factor[[i]]$vol_concentration_contract <- round(as.numeric(row$vol_concentration),3)
      if (!is.null(row$passive_overlap_proxy) && !is.na(row$passive_overlap_proxy))
        crowding_per_factor[[i]]$passive_overlap_proxy_contract <- round(as.numeric(row$passive_overlap_proxy),3)
      crowding_per_factor[[i]]$source <- "contract_helper+manual"
    } else {
      crowding_per_factor[[i]]$source <- "manual_fallback"
    }
  }
} else {
  for (i in seq_along(crowding_per_factor)) crowding_per_factor[[i]]$source <- "manual_fallback"
}

saveRDS(list(tail_risk=tail_risk, stress=stress, crowding_per_factor=crowding_per_factor,
             sector_hhi=sector_hhi, sector_n_eff=sector_n_eff, name_hhi=name_hhi,
             name_n_eff=name_n_eff, port_beta=port_beta, sec_w=sec_w,
             tier_risk_share=tier_risk_share, tier_alpha_share=tier_alpha_share,
             lw=lw, long_daily=long_daily),
        file.path(OUT, "risk_tail.rds"))
cat("[SAVE] risk_tail.rds\n")
