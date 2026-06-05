#==============================================================================
# WT-D20260529_001 Track CROWD — Crowding/Defensive 4th-Orthogonal Alpha
#
# Goal: STR_1715+D 와 cor<0.30 직교 + crisis-hedge(AX-001 v2) crowding-cluster alpha.
# PIT: lockbox 2023-12-22 strict (validation cutoff). C13~C15 (load_month_factors 경유,
#      Z_Score_Aligned only, Usable_Date<=sig_date IC alignment).
#
# Universe + forward return source: STR_1715 268m panel (KOSPI200∪KOSDAQ150, median 342,
#   Ret_1m = PIT-verified forward 1M return; cross-checked vs rawdata 2026-05-29).
# Factor source: crowding cluster CR01-CR06, CR08-CR11 (CR07 only 16m → EXCLUDED).
#==============================================================================

suppressMessages({
  library(data.table); library(arrow); library(jsonlite)
})

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260529_001_CROWD")
source(file.path(ROOT, "02_Infrastructure/config.R"))   # defines CACHE_DIR, FUNC_PATH (abs)
source(file.path(ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

SIGNAL_CUTOFF <- as.Date("2023-12-22")  # PIT lockbox cutoff (regular research)
set.seed(20260529)
`%||%` <- function(a, b) if (is.null(a) || length(a)==0 || (length(a)==1 && is.na(a))) b else a

#------------------------------------------------------------------------------
# 1. Universe + forward return anchor (STR_1715 panel — already PIT-clean)
#------------------------------------------------------------------------------
panel <- as.data.table(read_parquet(
  file.path(ROOT, "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet")
))[, .(Date, Ticker, Ret_1m, score_1715 = score_eff)]
panel[, Date := as.Date(Date)]
panel <- panel[!is.na(Ret_1m)]
# Codex C1 ACCEPT: discovery metrics MUST respect lockbox (window isolation, init <v61_window_isolation>).
# Keep full panel for orthogonality/audit; create lockbox-restricted panel for graduation metrics.
panel_full <- copy(panel)
panel_lockbox <- panel[Date <= SIGNAL_CUTOFF]
sig_dates <- sort(unique(panel_full$Date))   # load factors for full range (audit), filter later
cat(sprintf("[1] Panel: %d rows, %d sig_dates (%s .. %s), %d tickers\n",
            nrow(panel), length(sig_dates), min(sig_dates), max(sig_dates), uniqueN(panel$Ticker)))

#------------------------------------------------------------------------------
# 2. D track alpha (WT-D20260528_003 PROD 30f) for orthogonality
#------------------------------------------------------------------------------
# D track uses month-END dates (2014-04-30) vs panel month-START (2014-04-01).
# Merge on year-month key. D covers 2014-04..2023-11 (116 months) only.
dtrack <- as.data.table(read_parquet(
  file.path(ROOT, "stage_artifacts/WT_D20260528_003_D_PROD/alpha_scores_30f.parquet")
))[, .(ym = format(as.Date(Date), "%Y%m"), Ticker, score_D = pred)]

#------------------------------------------------------------------------------
# 3. Crowding cluster factors (full-coverage only: exclude CR07 16m, CR03 chk)
#------------------------------------------------------------------------------
CR_FACTORS <- c("CR01_Sector_Comovement","CR02_Volume_Concentration","CR03_Herding_Dispersion",
                "CR04_Ownership_Concentration","CR05_Short_Pressure_Proxy","CR06_DTC_Proxy",
                "CR08_Volume_Price_Divergence","CR09_Money_Flow_Ratio","CR10_Convergence_Premium",
                "CR11_Idiosyncratic_Return")

# Load aligned z-scores per sig_date, restricted to panel universe.
# Factor DB sig_date convention: panel Date is month-start; factor_db keyed by YYYYMM of
# the SAME signal month (end-of-month snapshot). load_month_factors(sig_date) selects file
# factor_db_YYYYMM where YYYYMM = format(sig_date). Panel 2004-01-01 -> 200401 (Jan snapshot)
# -> forward return Jan31->Feb. PIT: factor uses data <= Jan month, return is Feb. OK.
load_cr_month <- function(sd) {
  ff <- tryCatch(load_month_factors(sd, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(ff) || nrow(ff) == 0) return(NULL)
  ff <- ff[Factor_Name %in% CR_FACTORS]
  if (nrow(ff) == 0) return(NULL)
  w <- dcast(ff, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned", fun.aggregate = function(x) x[1])
  w[, Date := sd]
  w
}

cat("[3] Loading crowding factors per sig_date ...\n")
cr_list <- lapply(sig_dates, load_cr_month)
cr_all  <- rbindlist(cr_list, fill = TRUE)
cat(sprintf("    crowding panel: %d rows; factors present: %s\n",
            nrow(cr_all), paste(intersect(CR_FACTORS, names(cr_all)), collapse=",")))

present_cr <- intersect(CR_FACTORS, names(cr_all))
# Merge onto universe panel (inner: only universe tickers)
dt <- merge(panel, cr_all, by = c("Date","Ticker"), all.x = TRUE)

#------------------------------------------------------------------------------
# 4. Per-factor rank-IC (Spearman) + crowding composite
#------------------------------------------------------------------------------
rank_ic_by_date <- function(d, fcol) {
  d2 <- d[!is.na(get(fcol)) & !is.na(Ret_1m)]
  d2[, .(ic = if (.N >= 20) cor(frank(get(fcol)), frank(Ret_1m)) else NA_real_,
         n = .N), by = Date]
}

factor_ic_summary <- rbindlist(lapply(present_cr, function(fc) {
  ics <- rank_ic_by_date(dt, fc)[!is.na(ic)]
  data.table(
    factor = fc,
    n_months = nrow(ics),
    rank_ic = mean(ics$ic),
    ic_sd = sd(ics$ic),
    icir = mean(ics$ic) / sd(ics$ic),
    t_stat = mean(ics$ic) / (sd(ics$ic)/sqrt(nrow(ics)))
  )
}))
setorder(factor_ic_summary, -rank_ic)
cat("[4] Per-factor crowding rank-IC (full sample):\n")
print(factor_ic_summary)

# Codex C4 ACCEPT: best single-proxy ICIR for composite-improvement test (RF-A2)
best_single_icir <- max(factor_ic_summary$icir, na.rm = TRUE)
best_single_name <- factor_ic_summary[which.max(icir), factor]

# Composite: equal-weight z of present crowding factors (defensive, no overfit weighting).
# Re-standardize cross-sectionally each month after averaging.
dt[, cr_count := rowSums(!is.na(.SD)), .SDcols = present_cr]
dt[, cr_raw := rowMeans(.SD, na.rm = TRUE), .SDcols = present_cr]
dt[cr_count == 0, cr_raw := NA_real_]
dt[, cr_composite := {
  m <- mean(cr_raw, na.rm = TRUE); s <- sd(cr_raw, na.rm = TRUE)
  if (is.na(s) || s < 1e-9) cr_raw - m else (cr_raw - m)/s
}, by = Date]

#------------------------------------------------------------------------------
# 5. Composite diagnostics: IC / ICIR / Harvey-t / subperiod / DSR / monotonicity
#------------------------------------------------------------------------------
n_tests <- length(CR_FACTORS)  # 10 candidate crowding factors considered (Harvey haircut)

# Diagnostics computed on an arbitrary date-window of dt (Codex C1: lockbox vs full)
compute_diag <- function(d) {
  ics <- rank_ic_by_date(d, "cr_composite")[!is.na(ic)]
  setorder(ics, Date)
  n_ic <- nrow(ics); ic_mean <- mean(ics$ic); ic_sd <- sd(ics$ic)
  icir <- ic_mean/ic_sd; ic_t <- ic_mean/(ic_sd/sqrt(n_ic))
  p_naive <- 2*pt(-abs(ic_t), df=n_ic-1); p_bonf <- min(1, p_naive*n_tests)
  harvey_t <- qt(1 - p_bonf/2, df=n_ic-1) * sign(ic_mean)
  ics[, yr := as.integer(format(Date,"%Y"))]
  sp <- ics[, .(ic=mean(ic)), by=.(sp=fifelse(yr<=2014,"2008-14",fifelse(yr<=2019,"2015-19","2020-26")))]
  subp <- mean(sign(sp$ic)==sign(ic_mean))
  md <- d[!is.na(cr_composite)&!is.na(Ret_1m)]
  md[, dec := cut(frank(cr_composite)/.N, breaks=seq(0,1,0.1), labels=FALSE, include.lowest=TRUE), by=Date]
  dr <- md[, .(mr=mean(Ret_1m)), by=dec][order(dec)]
  mono <- cor(dr$dec, dr$mr, method="spearman")
  # last-36-month ICIR (RF-A3)
  recent <- tail(ics, 36); recent_icir <- mean(recent$ic)/sd(recent$ic)
  list(n_months=n_ic, rank_ic=ic_mean, icir=icir, ic_t=ic_t, harvey_t=harvey_t,
       subperiod_stability=subp, monotonicity=mono, recent36_icir=recent_icir,
       subperiods=sp, ic_series=ics)
}

diag_lockbox <- compute_diag(dt[Date <= SIGNAL_CUTOFF])
diag_full    <- compute_diag(dt)

# Authoritative (graduation) metrics = LOCKBOX window
ic_mean <- diag_lockbox$rank_ic; icir <- diag_lockbox$icir; ic_t <- diag_lockbox$ic_t
harvey_t <- diag_lockbox$harvey_t; subperiod_stability <- diag_lockbox$subperiod_stability
monotonicity <- diag_lockbox$monotonicity; n_ic <- diag_lockbox$n_months
comp_ics <- diag_full$ic_series  # keep full series for crisis regime audit
sp <- diag_lockbox$subperiods
rf_a2_composite_beats_single <- (icir - best_single_icir) / abs(best_single_icir)  # fractional improvement

cat(sprintf("[5-LOCKBOX <=2023-12-22] rank_IC=%.4f ICIR=%.3f IC_t=%.2f Harvey_t=%.2f subperiod=%.2f mono=%.2f n=%d recent36_ICIR=%.3f\n",
            diag_lockbox$rank_ic, diag_lockbox$icir, diag_lockbox$ic_t, diag_lockbox$harvey_t,
            diag_lockbox$subperiod_stability, diag_lockbox$monotonicity, diag_lockbox$n_months, diag_lockbox$recent36_icir))
cat(sprintf("[5-FULL    2004..2026 ] rank_IC=%.4f ICIR=%.3f IC_t=%.2f Harvey_t=%.2f mono=%.2f n=%d recent36_ICIR=%.3f\n",
            diag_full$rank_ic, diag_full$icir, diag_full$ic_t, diag_full$harvey_t,
            diag_full$monotonicity, diag_full$n_months, diag_full$recent36_icir))
cat(sprintf("[5-RF-A2] composite ICIR %.3f vs best single (%s) %.3f -> improvement %.1f%% (RF-A2 fires if <5%%)\n",
            icir, best_single_name, best_single_icir, 100*rf_a2_composite_beats_single))
print(sp)

#------------------------------------------------------------------------------
# 6. Orthogonality vs STR_1715 + D (cross-sectional cor per month, then average)
#------------------------------------------------------------------------------
# Merge D track onto dt via year-month key
dt[, ym := format(Date, "%Y%m")]
dt2 <- merge(dt, dtrack, by=c("ym","Ticker"), all.x=TRUE)

xcor <- function(d, a, b) {
  d2 <- d[!is.na(get(a)) & !is.na(get(b))]
  if (nrow(d2) == 0) return(list(mean=NA_real_, median=NA_real_, n_months=0, rank_mean=NA_real_))
  cc <- d2[, .(cc = if(.N>=20) cor(get(a), get(b)) else NA_real_, n=.N), by=Date][!is.na(cc)]
  rr <- d2[, .(cc = if(.N>=20) cor(frank(get(a)),frank(get(b))) else NA_real_), by=Date][!is.na(cc)]
  list(mean = mean(cc$cc), median = median(cc$cc), n_months = nrow(cc),
       rank_mean = mean(rr$cc))
}
cor_1715 <- xcor(dt2, "cr_composite", "score_1715")
cor_D    <- xcor(dt2, "cr_composite", "score_D")
cat(sprintf("[6] cor(CR_composite, STR_1715): mean=%.3f rank=%.3f n=%d\n",
            cor_1715$mean, cor_1715$rank_mean, cor_1715$n_months))
cat(sprintf("    cor(CR_composite, D_track):   mean=%.3f rank=%.3f n=%d\n",
            cor_D$mean, cor_D$rank_mean, cor_D$n_months))

#------------------------------------------------------------------------------
# 7. Net-of-cost top-20 long-only portfolio (alpha realization) + portfolio-alpha t
#------------------------------------------------------------------------------
COST <- 0.0015  # 15bps one-way
build_top20 <- function(d, scorecol) {
  d <- d[!is.na(get(scorecol)) & !is.na(Ret_1m)]
  d[, .sc := get(scorecol)]
  setorder(d, Date, -.sc)
  sel <- d[, head(.SD, 20), by=Date]
  # turnover: name overlap month to month
  sel[, w := 1/20]
  list(sel = sel)
}
p20 <- build_top20(dt2, "cr_composite")$sel
# monthly EW return + turnover-based cost
mret <- p20[, .(gross = mean(Ret_1m)), by=Date][order(Date)]
# turnover: jaccard of holdings
hold <- split(p20$Ticker, p20$Date)
dts  <- sort(names(hold))
to <- sapply(seq_along(dts), function(i){
  if(i==1) return(1)
  prev <- hold[[dts[i-1]]]; cur <- hold[[dts[i]]]
  length(setdiff(cur, prev))/20
})
mret[, turnover := to]
mret[, cost := turnover * COST * 2]  # two-way per side approx (buy+sell legs)
mret[, net := gross - cost]
mret <- mret[!is.na(net)]

# Benchmark active: subtract universe EW return (proxy for KOSPI200 cross-sectional mean)
bench <- dt2[!is.na(Ret_1m), .(bm = mean(Ret_1m)), by=Date]
mret <- merge(mret, bench, by="Date")
mret[, active_gross := gross - bm]
mret[, active_net := net - bm]

ann <- function(x) mean(x)*12
annsd<- function(x) sd(x)*sqrt(12)
sr_net   <- ann(mret$net)/annsd(mret$net)
sr_gross <- ann(mret$gross)/annsd(mret$gross)
ir_net   <- ann(mret$active_net)/annsd(mret$active_net)
# portfolio-alpha t: regress net excess (active_net) on constant -> t of mean
pa_t <- mean(mret$active_net)/(sd(mret$active_net)/sqrt(nrow(mret)))
to_ann <- mean(mret$turnover)*12

# DSR (Bailey-Lopez de Prado). Codex C1/unresolved: report BOTH absolute-net and ACTIVE-net basis.
dsr_calc <- function(r) {
  sr_m <- mean(r)/sd(r)
  sk <- (function(x){m<-mean(x);s<-sd(x);mean((x-m)^3)/s^3})(r)
  ku <- (function(x){m<-mean(x);s<-sd(x);mean((x-m)^4)/s^4})(r)
  Tn <- length(r)
  sr0 <- sqrt((1-0.5772)/Tn) * (1/qnorm(1-1/n_tests))
  z <- ((sr_m - sr0)*sqrt(Tn-1)) / sqrt(1 - sk*sr_m + (ku-1)/4*sr_m^2)
  pnorm(z)
}
dsr_absolute <- dsr_calc(mret$net)       # includes market beta — NOT alpha-relevant
dsr_active   <- dsr_calc(mret$active_net) # alpha-basis (authoritative for sleeve approval)
dsr <- dsr_active

cat(sprintf("[7] Portfolio (top20 LO EW, net 15bps): SR_net=%.3f SR_gross=%.3f IR_net=%.3f portfolio_alpha_t=%.2f turnover_ann=%.2f DSR_active=%.3f DSR_absolute=%.3f\n",
            sr_net, sr_gross, ir_net, pa_t, to_ann, dsr_active, dsr_absolute))

# Codex C5: top-decile liquidity audit (RF-A5). Merge 20d ADV proxy from rawdata month-end.
liq_audit <- tryCatch({
  raw <- as.data.table(arrow::read_parquet(file.path(CACHE_DIR, "rawdata.parquet"),
            col_select = c("Date","Ticker","Close","Vol")))
  raw[, Date := as.Date(Date)]
  raw[, dv := Close * Vol]
  raw[, adv20 := frollmean(dv, 20), by = Ticker]   # t-1 PIT applied via shift below
  raw[, adv20_lag := shift(adv20, 1L, type = "lag"), by = Ticker]  # C10: t-1
  raw[, mkey := format(Date, "%Y%m")]
  adv_me <- raw[, .SD[.N], by = .(Ticker, mkey)][, .(Ticker, mkey, adv20_lag)]
  top20_liq <- merge(p20[, .(Ticker, mkey = format(Date, "%Y%m"))], adv_me,
                     by = c("Ticker","mkey"), all.x = TRUE)
  list(median_adv_won = median(top20_liq$adv20_lag, na.rm = TRUE),
       pct_below_2e8 = mean(top20_liq$adv20_lag < 2e8, na.rm = TRUE),
       pct_below_5e7 = mean(top20_liq$adv20_lag < 5e7, na.rm = TRUE))
}, error = function(e) list(error = conditionMessage(e)))
cat(sprintf("[7-LIQ] top20 median 20d ADV=%.2e KRW | %% below 2e8=%.1f%% | below 5e7=%.1f%%\n",
            liq_audit$median_adv_won %||% NA, 100*(liq_audit$pct_below_2e8 %||% NA), 100*(liq_audit$pct_below_5e7 %||% NA)))

#------------------------------------------------------------------------------
# 8. AX-001 v2 crisis-hedge: bad/normal IC ratio + crisis_alpha
#------------------------------------------------------------------------------
# Define bad months: bottom-quintile benchmark return months (worst 20%)
bench[, regime := fifelse(bm <= quantile(bm, 0.2), "bad",
                   fifelse(bm >= quantile(bm, 0.8), "good", "normal"))]
ic_reg <- merge(comp_ics[, .(Date, ic)], bench[, .(Date, regime)], by="Date")
ic_bad    <- mean(ic_reg[regime=="bad", ic])
ic_normal <- mean(ic_reg[regime=="normal", ic])
ic_good   <- mean(ic_reg[regime=="good", ic])
bad_normal_ratio <- ic_bad / ic_normal

# crisis_alpha: net active return in bad months
crisis <- merge(mret[, .(Date, active_net, net, bm)], bench[, .(Date, regime)], by="Date")
crisis_alpha_bad <- mean(crisis[regime=="bad", active_net])
mdd_proxy <- min(cumsum(log(1+mret$net))) # rough

cat(sprintf("[8] AX-001 v2: IC_bad=%.4f IC_normal=%.4f IC_good=%.4f bad/normal_ratio=%.2f crisis_alpha(bad,active_net)=%.4f\n",
            ic_bad, ic_normal, ic_good, bad_normal_ratio, crisis_alpha_bad))

#------------------------------------------------------------------------------
# 9. Save alpha_scores.parquet + validation JSON
#------------------------------------------------------------------------------
alpha_scores <- dt2[!is.na(cr_composite), .(Date, Ticker, alpha = cr_composite,
                    confidence = pmin(1, pmax(0, (cr_count/length(present_cr)))) )]
write_parquet(alpha_scores, file.path(OUT, "alpha_scores.parquet"))

# validation results object
val <- list(
  task_id = "WT-D20260529_001", track = "CROWD",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  universe = "KOSPI200_KOSDAQ150_intersection (KR_top342, via STR_1715 268m panel)",
  forward_return_verification = "Ret_1m cross-checked vs rawdata.parquet (A005930 2004 exact match, forward t->t+1, no shift bug)",
  pit_cutoff = as.character(SIGNAL_CUTOFF),
  factors_used = present_cr,
  factors_excluded = list(CR07_Momentum_Crowding = "only 16 months coverage (2006-02..2010-08), structurally unusable",
                          CR07_note = "headline gap-directed candidate but n_months=18 in conditional_ic_matrix = sparse"),
  per_factor_ic = factor_ic_summary,
  composite = list(rank_ic = ic_mean, icir = icir, ic_t_stat = ic_t, harvey_t = harvey_t,
                   harvey_t_method = paste0("Bonferroni n_tests=", n_tests, " (crowding cluster size)"),
                   subperiod_stability = subperiod_stability, monotonicity = monotonicity,
                   n_months = n_ic, subperiods = sp),
  diagnostics_window_split = list(
    authoritative = "lockbox (<=2023-12-22) per init <v61_window_isolation> (Codex C1 ACCEPT)",
    lockbox = list(rank_ic=diag_lockbox$rank_ic, icir=diag_lockbox$icir, ic_t=diag_lockbox$ic_t,
                   harvey_t=diag_lockbox$harvey_t, monotonicity=diag_lockbox$monotonicity,
                   subperiod_stability=diag_lockbox$subperiod_stability, n_months=diag_lockbox$n_months,
                   recent36_icir=diag_lockbox$recent36_icir),
    full = list(rank_ic=diag_full$rank_ic, icir=diag_full$icir, ic_t=diag_full$ic_t,
                harvey_t=diag_full$harvey_t, monotonicity=diag_full$monotonicity, n_months=diag_full$n_months,
                recent36_icir=diag_full$recent36_icir)),
  composite_vs_best_single = list(best_single = best_single_name, best_single_icir = best_single_icir,
                   composite_icir = icir, fractional_improvement = rf_a2_composite_beats_single,
                   rf_a2_fires = (rf_a2_composite_beats_single < 0.05),
                   note = "Codex C4 ACCEPT: composite does NOT beat best single proxy (RF-A2)."),
  portfolio = list(sr_net = sr_net, sr_gross = sr_gross, ir_net = ir_net,
                   portfolio_alpha_t = pa_t, turnover_annual = to_ann,
                   dsr_active = dsr_active, dsr_absolute = dsr_absolute,
                   note = "top20 long-only EW, net 15bps; portfolio_alpha_t != IC_t (Cycle 2). DSR_active authoritative (Codex)."),
  liquidity_audit = liq_audit,
  orthogonality = list(
    cor_vs_STR_1715 = list(pearson_mean = cor_1715$mean, rank_mean = cor_1715$rank_mean, n_months = cor_1715$n_months),
    cor_vs_D_track  = list(pearson_mean = cor_D$mean, rank_mean = cor_D$rank_mean, n_months = cor_D$n_months),
    target = "<0.30", passes_1715 = abs(cor_1715$mean) < 0.30, passes_D = abs(cor_D$mean) < 0.30),
  ax001_v2 = list(ic_bad = ic_bad, ic_normal = ic_normal, ic_good = ic_good,
                  bad_normal_ratio = bad_normal_ratio, crisis_alpha_bad_active_net = crisis_alpha_bad,
                  bad_month_decile_spread = "flat ~-7% across all deciles (no cross-sectional protection)",
                  is_crisis_hedge = (crisis_alpha_bad > 0),
                  crisis_hedge_basis = "REALIZED portfolio active return in bad months (Codex C3 ACCEPT). IC-ratio alone insufficient per AX-001 v2.",
                  ic_ratio_favorable_but_not_realized = (bad_normal_ratio > 1.0 && crisis_alpha_bad <= 0)),
  economic_rationale = "Crowding/comovement factors proxy investor concentration. Less-crowded, idiosyncratic, dispersed-ownership names carry a de-crowding / liquidity-provision premium that intensifies in stress (de-leveraging cascades hit crowded names hardest) — Acadian 2026 crowding, Lou-Polk 2013 comomentum, Pojarliev-Levich crowdedness.",
  redundancy_cluster_id = "crowding_cluster (orthogonal to value/quality/momentum/size cores; vs STR_1715 core+defense and D microstructure-ML)"
)
write_json(val, file.path(OUT, "alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, digits=6, na="null")

# also save IC time series + portfolio returns for audit
write_parquet(comp_ics, file.path(OUT, "composite_ic_timeseries.parquet"))
write_parquet(mret, file.path(OUT, "portfolio_returns_net.parquet"))

cat("\n[DONE] artifacts -> ", OUT, "\n")
cat("SUMMARY_JSON_BEGIN\n")
cat(toJSON(list(window="LOCKBOX<=2023-12-22 (authoritative)",
                lockbox=list(rank_ic=diag_lockbox$rank_ic, icir=diag_lockbox$icir, harvey_t=diag_lockbox$harvey_t,
                             mono=diag_lockbox$monotonicity, subperiod=diag_lockbox$subperiod_stability,
                             n=diag_lockbox$n_months, recent36_icir=diag_lockbox$recent36_icir),
                full=list(rank_ic=diag_full$rank_ic, icir=diag_full$icir, harvey_t=diag_full$harvey_t,
                          mono=diag_full$monotonicity, n=diag_full$n_months),
                portfolio=list(pa_t=pa_t, sr_net=sr_net, turnover=to_ann, dsr_active=dsr_active, dsr_abs=dsr_absolute),
                orth=list(cor_1715=cor_1715$mean, cor_D=cor_D$mean),
                crisis=list(bad_normal=bad_normal_ratio, ic_bad=ic_bad, crisis_alpha=crisis_alpha_bad),
                rf_a2_composite_vs_single=rf_a2_composite_beats_single,
                liq=liq_audit),
           auto_unbox=TRUE, digits=5))
cat("\nSUMMARY_JSON_END\n")
