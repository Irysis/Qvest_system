# =============================================================================
# risk_measure_B.R — PART B/C/D/E for WT-D20260614_001 VAL_DIVERSIFIER
#   B: AUTHORITATIVE book-marginal (proper covariance, active_cor, ΔIR)
#   C: Sector-neutral residual diversification (does diversification survive?)
#   D: Tail / MDD 64% decomposition + stress (2008/2020/2022)
#   E: Crowding per factor + style
# selection_objective = estimation quality. NO alpha edit, NO weights.
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
ap  <- fromJSON(file.path(mb_dir, "alpha_package.json"), simplifyVector = FALSE)
as_of <- as.Date(ap$as_of_date)

sleeve <- as.data.table(read_parquet(file.path(out_dir, "sleeve_active_series.parquet")))
sleeve[, Date := as.Date(Date)]
scores_dt <- as.data.table(read_parquet(file.path(out_dir, "alpha_scores.parquet")))
scores_dt[, Date := as.Date(Date)]
inc <- fread(file.path(root, "qepm","mailbox","governor","str_1715_full_reassessment",
                       "str_1715_monthly_returns_full.csv"))
inc[, Date := as.Date(Date)]; setnames(inc, "monthly_ret", "inc_ret")
RAW <- as.data.table(read_parquet(file.path(root,".cache","rawdata.parquet"),
  col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150","Sector","BM_Ret")))
RAW[, Date := as.Date(Date)]; setorder(RAW, Ticker, Date)

`%||%` <- function(a,b) if (is.null(a)||length(a)==0||is.na(a)) b else a

# =============================================================================
# PART B. AUTHORITATIVE book-marginal: sleeve_active vs incumbent (proper)
# =============================================================================
# CRITICAL ALIGNMENT (authoritative): sleeve row dated month-end t = forward return realized over
#   (t, t+1] => its REALIZATION month = t + 1 month. Incumbent row dated month-START = realization
#   month = that calendar month. Correct join is on REALIZATION month, NOT signal month.
#   (alpha draft 0.109 used naive sig_ym join = WRONG; alpha realign 0.269 also slightly off.
#    Spot-check 2008-10 GFC: sleeve/inc/BM all crash same month only under realization-align => correct.)
inc[, real_ym := format(Date, "%Y-%m")]
sleeve[, real_ym := format(Date %m+% months(1), "%Y-%m")]   # realization month
bm_m <- sleeve[, .(real_ym, BM_Ret)]                         # bench realized in that month
B <- merge(sleeve[, .(real_ym, sleeve_active = active_gross, sleeve_port = port_gross)],
           inc[, .(real_ym, inc_ret)], by = "real_ym")
B <- merge(B, bm_m, by = "real_ym")
B[, inc_active := inc_ret - BM_Ret]
B <- B[is.finite(sleeve_active) & is.finite(inc_active)]
setorder(B, real_ym)
setnames(B, "real_ym", "ym")
n_ov <- nrow(B)

# --- active correlation (authoritative; matches alpha's 0.269 claim?) ---
active_cor <- cor(B$sleeve_active, B$inc_active)
total_cor  <- cor(B$sleeve_port,  B$inc_ret)

# --- proper covariance-based marginal: does value tilt diversify the book? ---
# Book = incumbent at 100%. Marginal contribution of a value sleeve at small tilt w.
# Use realized active series as the proxy for each sleeve's active return.
mu_inc  <- mean(B$inc_active);    sd_inc  <- sd(B$inc_active)
mu_slv  <- mean(B$sleeve_active);  sd_slv  <- sd(B$sleeve_active)
cov_is  <- cov(B$inc_active, B$sleeve_active)
IR_inc  <- mu_inc / sd_inc * sqrt(12)        # annualized active IR of incumbent (this overlap)
IR_slv  <- mu_slv / sd_slv * sqrt(12)

# Book IR as function of value tilt w in [0, 0.30]: combined active = (1-w)*inc + w*sleeve
book_IR <- function(w) {
  mu <- (1-w)*mu_inc + w*mu_slv
  v  <- (1-w)^2*sd_inc^2 + w^2*sd_slv^2 + 2*(1-w)*w*cov_is
  (mu / sqrt(v)) * sqrt(12)
}
ws <- seq(0, 0.30, by = 0.01)
irs <- sapply(ws, book_IR)
w_star <- ws[which.max(irs)]
IR_book0  <- book_IR(0)
IR_book_wstar <- max(irs)
dIR_wstar <- IR_book_wstar - IR_book0
# marginal ΔIR at first 10% tilt (governor-style read)
dIR_10 <- book_IR(0.10) - IR_book0
# diversification ratio: variance reduction from adding sleeve at w*
var0 <- sd_inc^2
var_wstar <- (1-w_star)^2*sd_inc^2 + w_star^2*sd_slv^2 + 2*(1-w_star)*w_star*cov_is

cat(sprintf("[BookMarg] overlap=%dm | active_cor=%.3f total_cor=%.3f\n", n_ov, active_cor, total_cor))
cat(sprintf("[BookMarg] IR_inc(overlap)=%.3f IR_sleeve=%.3f | book IR@0=%.3f w*=%.2f IR@w*=%.3f dIR=%.4f dIR@10%%=%.4f\n",
            IR_inc, IR_slv, IR_book0, w_star, IR_book_wstar, dIR_wstar, dIR_10))

# rolling 36m active_cor for robustness
roll_cor <- sapply(seq(36, n_ov), function(i) cor(B$sleeve_active[(i-35):i], B$inc_active[(i-35):i]))
cat(sprintf("[BookMarg] rolling36m active_cor: min=%.3f median=%.3f max=%.3f\n",
            min(roll_cor), median(roll_cor), max(roll_cor)))

# =============================================================================
# PART C. Sector-neutral residual diversification
#   Re-screen value-4 with SECTOR-DEMEANED scores -> sector-neutral sleeve.
#   Does the sleeve still diversify the incumbent after removing the sector bet?
# =============================================================================
# attach sector to scores (PIT: latest sector <= score Date)
sec_latest <- RAW[!is.na(Sector), .(Date, Ticker, Sector)]
setkey(sec_latest, Ticker, Date)
sec_of_date <- function(tk, d) {
  s <- sec_latest[Ticker == tk & Date <= d]
  if (nrow(s)) s$Sector[nrow(s)] else NA_character_
}
# faster: merge nearest prior sector via rolling join
sc <- copy(scores_dt); setkey(sc, Ticker, Date)
sc_sec <- sec_latest[sc, on = .(Ticker, Date), roll = TRUE]   # carry last sector <= score date
sc_sec <- sc_sec[, .(Date, Ticker, score, Sector)]
sc_sec[is.na(Sector), Sector := "UNKNOWN"]
# sector-neutral score = score - sector mean (within month)
sc_sec[, score_sn := score - mean(score, na.rm = TRUE), by = .(Date, Sector)]

# Build sector-neutral top-30 sleeve (same recipe as alpha, sector-demeaned scores)
TOP_N <- 30L
month_ends <- sort(unique(scores_dt$Date))
me_close_all <- RAW[Date %in% month_ends, .(Date, Ticker, Close)]
setorder(me_close_all, Ticker, Date)
me_close_all[, ret1m := shift(Close, -1L)/Close - 1, by = Ticker]
ret1m_dt <- me_close_all[is.finite(ret1m), .(Date, Ticker, ret1m)]

build_sleeve <- function(score_col) {
  S <- sc_sec[is.finite(get(score_col)), .(Date, Ticker, sc = get(score_col))]
  setorder(S, Date, -sc)
  W <- S[, { n <- min(TOP_N, .N); .(Ticker = Ticker[seq_len(n)], w = 1/n) }, by = Date]
  RR <- merge(W, ret1m_dt, by = c("Date","Ticker"), all.x = TRUE)
  RR[is.na(ret1m), ret1m := 0]
  RR[, .(port = sum(w*ret1m)), by = Date]
}
sl_raw <- build_sleeve("score")
sl_sn  <- build_sleeve("score_sn")
# bench per month (from sleeve file)
bm_dt <- sleeve[, .(Date, BM_Ret)]
mk_active <- function(sl) {
  m <- merge(sl, bm_dt, by = "Date"); m[, active := port - BM_Ret]; m
}
A_raw <- mk_active(sl_raw); A_sn <- mk_active(sl_sn)
# realization-month alignment (consistent with PART B authoritative join)
A_raw[, ym := format(Date %m+% months(1), "%Y-%m")]; A_sn[, ym := format(Date %m+% months(1), "%Y-%m")]
inc2 <- inc[, .(ym = real_ym, inc_ret)]
bm_m2 <- copy(bm_m); setnames(bm_m2, "real_ym", "ym")
Cr <- merge(A_raw[, .(ym, a_raw = active)], inc2, by="ym")
Cr <- merge(Cr, bm_m2, by="ym"); Cr[, inc_active := inc_ret - BM_Ret]
Cs <- merge(A_sn[, .(ym, a_sn = active)], inc2, by="ym")
Cs <- merge(Cs, bm_m2, by="ym"); Cs[, inc_active := inc_ret - BM_Ret]
cor_raw_inc <- cor(Cr$a_raw, Cr$inc_active)
cor_sn_inc  <- cor(Cs$a_sn,  Cs$inc_active)
# sleeve self-correlation raw vs sector-neutral (how much of the sleeve IS the sector bet)
M <- merge(A_raw[, .(Date, a_raw=active)], A_sn[, .(Date, a_sn=active)], by="Date")
cor_raw_sn <- cor(M$a_raw, M$a_sn)
# diversification (book ΔIR) with sector-neutral sleeve
B_sn <- merge(A_sn[, .(ym, sleeve_active = active)], inc2, by="ym")
B_sn <- merge(B_sn, bm_m2, by="ym"); B_sn[, inc_active := inc_ret - BM_Ret]
B_sn <- B_sn[is.finite(sleeve_active) & is.finite(inc_active)]
mu_sn <- mean(B_sn$sleeve_active); sd_sn <- sd(B_sn$sleeve_active); cov_sn <- cov(B_sn$inc_active, B_sn$sleeve_active)
mu_i2 <- mean(B_sn$inc_active); sd_i2 <- sd(B_sn$inc_active)
book_IR_sn <- function(w){ mu <- (1-w)*mu_i2 + w*mu_sn; v <- (1-w)^2*sd_i2^2 + w^2*sd_sn^2 + 2*(1-w)*w*cov_sn; (mu/sqrt(v))*sqrt(12) }
irs_sn <- sapply(ws, book_IR_sn); w_star_sn <- ws[which.max(irs_sn)]; dIR_sn <- max(irs_sn) - book_IR_sn(0)

cat(sprintf("[SectorNeu] cor(raw_sleeve, sector_neu_sleeve)=%.3f  (1-this = sector-bet share of sleeve)\n", cor_raw_sn))
cat(sprintf("[SectorNeu] active_cor vs incumbent: raw=%.3f  sector_neutral=%.3f\n", cor_raw_inc, cor_sn_inc))
cat(sprintf("[SectorNeu] book dIR: raw w*=%.2f -> use PART B; sector_neutral w*=%.2f dIR=%.4f\n", w_star, w_star_sn, dIR_sn))

# =============================================================================
# PART D. Tail / MDD 64% decomposition + stress
# =============================================================================
# Use the value-4 sleeve TOTAL gross return (port_gross) NAV for drawdown (the 64% carry was total-basis).
S <- copy(sleeve); setorder(S, Date)
nav <- cumprod(1 + S$port_gross)
peak <- cummax(nav); dd <- nav/peak - 1
mdd_total <- min(dd)
mdd_date  <- S$Date[which.min(dd)]
# active-basis NAV drawdown (relevant for diversifier role)
nav_a <- cumprod(1 + S$active_gross); dd_a <- nav_a/cummax(nav_a) - 1; mdd_active <- min(dd_a)
# drawdown episode stats (total basis)
underwater <- dd < -1e-6
# longest underwater run
rl <- rle(underwater); uw_runs <- rl$lengths[rl$values]
longest_uw_m <- if (length(uw_runs)) max(uw_runs) else 0L
# episodes deeper than thresholds (peak-to-trough)
ep <- function(thr) {
  # count distinct drawdown troughs deeper than thr
  inep <- FALSE; cnt <- 0L; cur_min <- 0
  for (i in seq_along(dd)) {
    if (dd[i] < -1e-6) { inep <- TRUE; cur_min <- min(cur_min, dd[i]) }
    else { if (inep && cur_min <= thr) cnt <- cnt + 1L; inep <- FALSE; cur_min <- 0 }
  }
  if (inep && cur_min <= thr) cnt <- cnt + 1L
  cnt
}
ep45 <- ep(-0.45); ep55 <- ep(-0.55); ep30 <- ep(-0.30)
time_underwater_pct <- mean(underwater)
cat(sprintf("[Tail] MDD total=%.1f%% (%s) | MDD active=%.1f%% | longest UW=%dm | timeUW=%.1f%%\n",
            100*mdd_total, mdd_date, 100*mdd_active, longest_uw_m, 100*time_underwater_pct))
cat(sprintf("[Tail] episodes: >=30%%:%d >=45%%:%d >=55%%:%d\n", ep30, ep45, ep55))

# EVT / VaR on total monthly returns. fExtremes unavailable -> self-contained POT-GPD (MoM) + Hill alpha.
r_tot <- S$port_gross
hist_var95 <- as.numeric(quantile(r_tot, 0.05)); hist_es95 <- mean(r_tot[r_tot <= hist_var95])
hist_var99 <- as.numeric(quantile(r_tot, 0.01)); hist_es99 <- mean(r_tot[r_tot <= hist_var99])
# Cornish-Fisher VaR (skew/kurt adjusted, normal expansion)
cf_var <- function(r, p) {
  z <- qnorm(1-p); m <- mean(r); s <- sd(r)
  sk <- mean((r-m)^3)/s^3; ku <- mean((r-m)^4)/s^4 - 3
  zcf <- z + (z^2-1)*sk/6 + (z^3-3*z)*ku/24 - (2*z^3-5*z)*sk^2/36
  m + s*zcf
}
cf_var95 <- cf_var(r_tot, 0.95); cf_var99 <- cf_var(r_tot, 0.99)
# POT-GPD on left tail (losses), MoM fit on exceedances over 90th-pct loss threshold
losses <- -r_tot
u <- as.numeric(quantile(losses, 0.90))
exc <- losses[losses > u] - u
n_exc <- length(exc)
gpd_var <- gpd_es <- xi_hat <- NA_real_
if (n_exc >= 15) {
  mbar <- mean(exc); s2 <- var(exc)
  xi_hat <- 0.5*(1 - mbar^2/s2)            # MoM shape
  beta   <- 0.5*mbar*(mbar^2/s2 + 1)       # MoM scale
  Fu <- mean(losses > u)
  for (pp in c(0.95, 0.99)) {
    q <- u + (beta/xi_hat)*(((1-pp)/Fu)^(-xi_hat) - 1)
    if (pp == 0.99) {
      gpd_var <- -q
      gpd_es  <- -(q/(1-xi_hat) + (beta - xi_hat*u)/(1-xi_hat))
    }
  }
}
# Hill tail index alpha (heaviness) on top-k losses
k <- max(10L, floor(0.1*length(losses)))
sl_loss <- sort(losses, decreasing = TRUE)
hill_alpha <- 1/mean(log(sl_loss[1:k]/sl_loss[k+1]))
evt95 <- list(var = round(hist_var95,4), es = round(hist_es95,4), method="empirical")
evt99 <- list(gpd_var99 = round(gpd_var,4), gpd_es99 = round(gpd_es,4), xi = round(xi_hat,3),
              hill_alpha = round(hill_alpha,2), n_exceedances = n_exc, threshold_u = round(u,4))
cf95 <- list(cf_var95 = round(cf_var95,4), cf_var99 = round(cf_var99,4))
cat(sprintf("[Tail] hist monthly VaR95=%.3f ES95=%.3f VaR99=%.3f ES99=%.3f\n",
            hist_var95, hist_es95, hist_var99, hist_es99))
cat(sprintf("[Tail] CF VaR95=%.3f VaR99=%.3f | GPD VaR99=%.3f ES99=%.3f xi=%.3f Hill_alpha=%.2f (n_exc=%d)\n",
            cf_var95, cf_var99, gpd_var, gpd_es, xi_hat, hill_alpha, n_exc))

# Stress windows (KR calendar) — sleeve total + active realized loss over window
stress_windows <- list(
  GFC_2008      = c("2008-05-31","2009-02-28"),
  EuDebt_2011   = c("2011-05-31","2011-12-31"),
  China_2015    = c("2015-06-30","2016-02-29"),
  COVID_2020    = c("2020-01-31","2020-03-31"),
  RateHike_2022 = c("2021-12-31","2022-10-31"),
  KR_Bear_2018  = c("2018-01-31","2018-12-31")
)
stress <- list()
for (nm in names(stress_windows)) {
  w <- as.Date(stress_windows[[nm]])
  sub <- S[Date >= w[1] & Date <= w[2]]
  cov_m <- nrow(sub)
  if (cov_m == 0) { stress[[nm]] <- list(sleeve_total = NA, sleeve_active = NA, n_months = 0, coverage = "NONE"); next }
  tot <- prod(1 + sub$port_gross) - 1
  act <- prod(1 + sub$active_gross) - 1
  bm  <- prod(1 + sub$BM_Ret) - 1
  # book coverage flag: sleeve series starts 2005-01 so all windows covered; flag short windows
  cvg <- if (cov_m >= 2) "OK" else "THIN"
  stress[[nm]] <- list(sleeve_total = round(tot,4), sleeve_active = round(act,4),
                       bm = round(bm,4), n_months = cov_m, coverage = cvg)
}
cat("[Stress]\n"); for (nm in names(stress)) cat(sprintf("  %-14s total=%s active=%s bm=%s (n=%d)\n",
   nm, stress[[nm]]$sleeve_total, stress[[nm]]$sleeve_active, stress[[nm]]$bm, stress[[nm]]$n_months))

# Single-period shock sensitivities (regression betas of sleeve to BM)
beta_mkt <- cov(S$port_gross, S$BM_Ret)/var(S$BM_Ret)
beta_active_mkt <- cov(S$active_gross, S$BM_Ret)/var(S$BM_Ret)
market_down_5 <- beta_mkt * (-0.05)
cat(sprintf("[Stress] sleeve beta_to_BM(total)=%.3f active=%.3f | market_down_5 implied=%.4f\n",
            beta_mkt, beta_active_mkt, market_down_5))

# =============================================================================
# PART E. Crowding per factor + style
# =============================================================================
source(file.path(root, "02_Infrastructure", "factor_db", "crowding_score_per_factor.R"))
source(file.path(root, "02_Infrastructure", "factor_db", "factor_db_connector.R"))
FACTORS_USE <- c("V01_BM","V03_CFP","V10_FCF_Yield","V11_Shareholder_Yield")
# build factor_exposures (Ticker, factor_name, exposure) for as_of from factor DB
fdt <- tryCatch(load_month_factors(as_of, coverage_min = 0.05, factor_names = FACTORS_USE),
                error=function(e) NULL)
crowd_out <- NULL
if (!is.null(fdt) && nrow(fdt) > 0) {
  fe <- fdt[Factor_Name %in% FACTORS_USE & is.finite(Z_Score_Aligned),
            .(Ticker, factor_name = Factor_Name, exposure = Z_Score_Aligned)]
  bench_tk <- RAW[Date <= as_of & (K200==1|KQ150==1), .SD[.N], by=Ticker][K200==1|KQ150==1, Ticker]
  crowd_out <- tryCatch(crowding_score_per_factor(fe, as_of, RAW, benchmark_tickers = bench_tk, top_n = 20L),
                        error=function(e){cat("[Crowd] err:",conditionMessage(e),"\n"); NULL})
}
if (!is.null(crowd_out)) { cat("[Crowd]\n"); print(crowd_out[, .(factor_name, crowding_score, hhi_top, vol_concentration, passive_overlap_proxy)]) }

# Style / sector HHI of current holdings (concentration)
hold <- sig$hold
sec_of <- sig$sec_of
sec_tab <- table(sec_of); sec_w <- sec_tab/sum(sec_tab)
sector_hhi <- sum(sec_w^2)
n_eff_sec <- 1/sector_hhi
top_sector <- names(which.max(sec_tab)); top_sector_share <- max(sec_w)
cat(sprintf("[Style] holdings sector HHI=%.3f n_eff_sectors=%.1f top=%s(%.1f%%)\n",
            sector_hhi, n_eff_sec, top_sector, 100*top_sector_share))

# Save all PART B-E outputs
saveRDS(list(
  active_cor = active_cor, total_cor = total_cor, n_ov = n_ov,
  IR_inc = IR_inc, IR_slv = IR_slv, IR_book0 = IR_book0, w_star = w_star,
  IR_book_wstar = IR_book_wstar, dIR_wstar = dIR_wstar, dIR_10 = dIR_10,
  cov_is = cov_is, roll_cor = roll_cor,
  cor_raw_sn = cor_raw_sn, cor_raw_inc = cor_raw_inc, cor_sn_inc = cor_sn_inc,
  w_star_sn = w_star_sn, dIR_sn = dIR_sn,
  mdd_total = mdd_total, mdd_active = mdd_active, mdd_date = mdd_date,
  longest_uw_m = longest_uw_m, time_underwater_pct = time_underwater_pct,
  ep30 = ep30, ep45 = ep45, ep55 = ep55,
  hist_var95 = hist_var95, hist_es95 = hist_es95, hist_var99 = hist_var99, hist_es99 = hist_es99,
  evt95 = evt95, evt99 = evt99, cf95 = cf95,
  stress = stress, beta_mkt = beta_mkt, beta_active_mkt = beta_active_mkt, market_down_5 = market_down_5,
  crowd_out = crowd_out, sector_hhi = sector_hhi, n_eff_sec = n_eff_sec,
  top_sector = top_sector, top_sector_share = top_sector_share
), file.path(out_dir, "_riskBE.rds"))
# regime correlation parquet: rolling 36m active_cor sleeve-vs-incumbent
rc_dt <- data.table(window_end = B$ym[36:n_ov], rolling36m_active_cor = roll_cor)
write_parquet(rc_dt, file.path(out_dir, "regime_correlation.parquet"))
cat("PART B-E DONE\n")
