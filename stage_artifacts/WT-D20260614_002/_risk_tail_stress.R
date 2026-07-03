# ============================================================================
# WT-D20260614_002 RISK — tail / MDD decomposition / stress / incumbent joint-cov
# Uses CORE (RC_16) realized daily net returns -> authoritative tail & MDD.
# ============================================================================
suppressMessages({ library(data.table); library(arrow); library(jsonlite); library(PerformanceAnalytics) })
Sys.setenv(CLAUDE_PROJECT_DIR = getwd(), QM_ROOT = getwd())
source("02_Infrastructure/config.R")
OUT <- "stage_artifacts/WT-D20260614_002"
core <- new.env()

# ---- CORE realized daily net returns (authoritative bt_result) ----
btr <- readRDS("stage_artifacts/alpha_search/20260613_021015_217222/bt_result.rds")
pr <- as.data.table(btr$period_returns)[, .(date, ret_net)]
br <- as.data.table(btr$benchmark_returns)[, .(date, bm = benchmark_ret)]
dd <- merge(pr, br, by = "date"); setorder(dd, date)
dd[, ym := format(date, "%Y%m")]
# monthly compounding (PerformanceAnalytics-consistent: prod within month is the
#   definition of monthly return from daily; not a synthetic blend)
mo <- dd[, .(core = prod(1+ret_net)-1, bm = prod(1+bm)-1), by = ym]
mo[, active := core - bm]
mo[, date := as.Date(paste0(substr(ym,1,4),"-",substr(ym,5,6),"-01"))]
setorder(mo, ym)
cat("[tail] CORE monthly months:", nrow(mo), head(mo$ym,1),"-",tail(mo$ym,1),"\n")

# ---- Tail: empirical CVaR + Cornish-Fisher + EVT-GPD (monthly net) ----
r <- mo$core
VaR95_emp <- as.numeric(quantile(r, 0.05)); VaR99_emp <- as.numeric(quantile(r, 0.01))
CVaR95_emp <- mean(r[r <= VaR95_emp]); CVaR99_emp <- mean(r[r <= VaR99_emp])
# PerformanceAnalytics modified (Cornish-Fisher) ES
rx <- xts::xts(r, order.by = mo$date)
ES95_cf <- tryCatch(as.numeric(ES(rx, p=0.95, method="modified")), error=function(e) NA)
ES99_cf <- tryCatch(as.numeric(ES(rx, p=0.99, method="modified")), error=function(e) NA)
VaR95_cf <- tryCatch(as.numeric(VaR(rx, p=0.95, method="modified")), error=function(e) NA)
# EVT-GPD on losses (POT)
losses <- -r[r < 0]
gpd_fit <- function(x, thr_q = 0.90) {
  u <- as.numeric(quantile(x, thr_q)); exc <- x[x > u] - u
  if (length(exc) < 10) return(NULL)
  # MoM estimates of GPD (xi, beta)
  m <- mean(exc); v <- var(exc)
  xi <- 0.5 * (1 - m^2/v); beta <- 0.5 * m * (m^2/v + 1)
  list(u=u, xi=xi, beta=beta, n_exc=length(exc), p_exc=length(exc)/length(x))
}
gpd <- gpd_fit(losses, 0.85)
# Hill alpha (tail index) on losses
hill_alpha <- function(x, k_frac = 0.15) {
  xs <- sort(x, decreasing = TRUE); k <- max(5, floor(length(xs)*k_frac))
  1 / mean(log(xs[1:k]) - log(xs[k]))
}
hill <- hill_alpha(losses, 0.15)
# EVT VaR/ES at 99 from GPD
evt_var99 <- evt_es99 <- NA
if (!is.null(gpd)) {
  p <- 0.01; Fu <- 1 - gpd$p_exc
  evt_var99 <- gpd$u + (gpd$beta/gpd$xi) * (((p/gpd$p_exc))^(-gpd$xi) - 1)
  evt_es99  <- (evt_var99 + gpd$beta - gpd$xi*gpd$u) / (1 - gpd$xi)
  evt_var99 <- -evt_var99; evt_es99 <- -evt_es99
}

# ---- MDD + drawdown decomposition (PIT-safe: DD lag c(0, dd[-n])) ----
nav <- cumprod(1 + r)
peak <- cummax(nav); dd_path <- nav/peak - 1
mdd <- min(dd_path)
mdd_idx <- which.min(dd_path)
# identify drawdown episodes >= 20%
ddt <- data.table(ym = mo$ym, date = mo$date, nav, dd = dd_path, core = r,
                  bm = mo$bm, active = mo$active)
# deepest episode window: from prior peak to trough to recovery
trough_i <- mdd_idx
peak_i <- max(which(ddt$dd[1:trough_i] == 0))
# recovery
rec_after <- which(ddt$dd[trough_i:nrow(ddt)] >= -1e-9)
rec_i <- if (length(rec_after)) trough_i + rec_after[1] - 1 else nrow(ddt)
mdd_window <- ddt[peak_i:trough_i]
cat(sprintf("[mdd] MDD=%.3f peak=%s trough=%s (%d months) recov=%s\n",
            mdd, ddt$ym[peak_i], ddt$ym[trough_i], trough_i-peak_i+1,
            if(rec_i<=nrow(ddt)) ddt$ym[rec_i] else "NOT_RECOVERED"))

# ---- MDD axis/factor attribution via factor-return panel during DD window ----
panel <- as.data.table(read_parquet(file.path(OUT, "_factor_return_panel.parquet")))
FACTORS <- c("D01_IdioVol","D02_Beta","M07_IndMom","M01_Mom_12_1","M05_Trended_Mom",
             "Q01_GPA","Q04_Piotroski_F","Q09_CFOA","Q07_Earnings_Stability","V01_BM")
AXIS <- c(D01_IdioVol="defense", D02_Beta="defense",
          M07_IndMom="momentum", M01_Mom_12_1="momentum", M05_Trended_Mom="momentum",
          Q01_GPA="quality", Q04_Piotroski_F="quality", Q09_CFOA="quality",
          Q07_Earnings_Stability="quality", V01_BM="value")
dd_yms <- mdd_window$ym
pdd <- panel[ym %in% dd_yms]
# cumulative factor long-spread return contribution during MDD window
fac_cum_dd <- sapply(FACTORS, function(f) prod(1+pdd[[f]], na.rm=TRUE)-1)
axis_cum_dd <- tapply(fac_cum_dd, AXIS[FACTORS], function(x) sum(x))
# market contribution during MDD: BM cum return
bm_cum_dd <- prod(1 + mdd_window$bm) - 1
core_cum_dd <- prod(1 + mdd_window$core) - 1
cat(sprintf("[mdd] during deepest DD: core cum=%.3f bm cum=%.3f\n", core_cum_dd, bm_cum_dd))

# ---- Stress scenarios: KR crisis windows (book coverage check) ----
stress_windows <- list(
  gfc_2008      = c("200806","200902"),
  euro_2011     = c("201105","201109"),
  china_2015    = c("201506","201601"),
  covid_2020    = c("202001","202003"),
  ratehike_2022 = c("202201","202210"),
  kr_bear_2024h2= c("202407","202412")
)
stress_res <- lapply(names(stress_windows), function(nm) {
  w <- stress_windows[[nm]]
  sub <- mo[ym >= w[1] & ym <= w[2]]
  cov_frac <- nrow(sub) / (as.numeric(substr(w[2],1,4))*12+as.numeric(substr(w[2],5,6)) -
                           (as.numeric(substr(w[1],1,4))*12+as.numeric(substr(w[1],5,6))) + 1)
  if (!nrow(sub)) return(data.table(scenario=nm, core=NA, bm=NA, active=NA, n=0, coverage=0, reliable=FALSE))
  data.table(scenario=nm,
             core = prod(1+sub$core)-1, bm = prod(1+sub$bm)-1, active = prod(1+sub$core)/prod(1+sub$bm)-1,
             n = nrow(sub), coverage = round(cov_frac,2), reliable = cov_frac >= 0.85)
})
stress_dt <- rbindlist(stress_res)
# instantaneous market shock: market_down_5 -> beta * -5%
mkt_beta_daily <- as.numeric(coef(lm(ret_net ~ bm, data = dd))[2])
market_down_5 <- mkt_beta_daily * -0.05

cat("[stress]\n"); print(stress_dt)
cat(sprintf("[stress] daily mkt beta=%.3f -> market_down_5=%.4f\n", mkt_beta_daily, market_down_5))

# ---- Incumbent joint covariance / active correlation / blend diversification ----
inc <- fread("qepm/mailbox/governor/str_1715_full_reassessment/str_1715_monthly_returns_full.csv")
inc[, ym := format(as.Date(Date), "%Y%m")]
setnames(inc, "monthly_ret", "inc_ret")
J <- merge(mo[, .(ym, core, bm, active_core = active)], inc[, .(ym, inc_ret)], by = "ym")
# incumbent active vs SAME bm
J[, inc_active := inc_ret - bm]
J <- J[is.finite(core) & is.finite(inc_ret) & is.finite(bm)]
cat("[joint] common months:", nrow(J), head(J$ym,1),"-",tail(J$ym,1),"\n")
# total-net correlation
cor_total <- cor(J$core, J$inc_ret)
# active correlation (both vs BM) — the book-marginal relevant one
cor_active <- cor(J$active_core, J$inc_active)
# proper joint covariance matrix (total net)
cov_tot <- cov(J[, .(core, inc_ret)]) * 12
cov_act <- cov(J[, .(active_core, inc_active)]) * 12
# blend diversification: variance of w*core + (1-w)*inc on ACTIVE basis, scan w
blend_div <- function(wc) {
  va <- cov_act[1,1]; vi <- cov_act[2,2]; cab <- cov_act[1,2]
  v <- wc^2*va + (1-wc)^2*vi + 2*wc*(1-wc)*cab
  v
}
ws <- seq(0,1,0.05)
blend_vol <- sapply(ws, function(w) sqrt(blend_div(w)))
inc_active_vol <- sqrt(cov_act[2,2]); core_active_vol <- sqrt(cov_act[1,1])
# diversification ratio at small core tilt (e.g. 10%)
div_at_10 <- 1 - blend_div(0.10)/((0.10^2)*cov_act[1,1] + (0.90^2)*cov_act[2,2])
# variance reduction vs weighted-avg-of-vols (diversification benefit)
wavg_vol_10 <- 0.10*core_active_vol + 0.90*inc_active_vol
realized_vol_10 <- sqrt(blend_div(0.10))
div_benefit_10 <- 1 - realized_vol_10/wavg_vol_10

cat(sprintf("[joint] cor_total=%.4f cor_active=%.4f\n", cor_total, cor_active))
cat(sprintf("[joint] core active vol=%.4f inc active vol=%.4f\n", core_active_vol, inc_active_vol))
cat(sprintf("[joint] blend@10%% core: active vol=%.4f vs wavg=%.4f -> div benefit=%.4f\n",
            realized_vol_10, wavg_vol_10, div_benefit_10))

saveRDS(list(mo=mo, ddt=ddt, mdd=mdd, mdd_window_ym=range(dd_yms),
             VaR95_emp=VaR95_emp, VaR99_emp=VaR99_emp, CVaR95_emp=CVaR95_emp, CVaR99_emp=CVaR99_emp,
             ES95_cf=ES95_cf, ES99_cf=ES99_cf, VaR95_cf=VaR95_cf,
             gpd=gpd, hill=hill, evt_var99=evt_var99, evt_es99=evt_es99,
             fac_cum_dd=fac_cum_dd, axis_cum_dd=axis_cum_dd, bm_cum_dd=bm_cum_dd, core_cum_dd=core_cum_dd,
             stress_dt=stress_dt, market_down_5=market_down_5, mkt_beta_daily=mkt_beta_daily,
             cor_total=cor_total, cor_active=cor_active, cov_tot=cov_tot, cov_act=cov_act,
             core_active_vol=core_active_vol, inc_active_vol=inc_active_vol,
             div_benefit_10=div_benefit_10, ws=ws, blend_vol=blend_vol,
             peak_i=peak_i, trough_i=trough_i, rec_i=rec_i,
             mdd_peak_ym=ddt$ym[peak_i], mdd_trough_ym=ddt$ym[trough_i],
             mdd_recov_ym=if(rec_i<=nrow(ddt)) ddt$ym[rec_i] else NA),
        file.path(OUT, "_risk_tail.rds"))
cat("\n[tail] empirical CVaR95=", round(CVaR95_emp,4), " CVaR99=", round(CVaR99_emp,4),
    " | EVT VaR99=", round(evt_var99,4), " ES99=", round(evt_es99,4), " Hill alpha=", round(hill,2), "\n")
