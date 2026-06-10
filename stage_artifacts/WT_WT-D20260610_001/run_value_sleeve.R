# ============================================================================
# WT-D20260610_001 — Full-universe VALUE sleeve (alpha-research)
# risk-aware value composite: EP + EBIT/EV + EV/EBITDA + SP + EV/Sales + BM
#   (equal-weight Z-composite) + 0.5 * Tail_Risk(R05) tilt
# monthly, top-25 EW long-only, universe = KR_ALL_LIQ2E8 (전종목 LIQ>=2e8)
#
# 실측-only: canonical_screen_bt() 경유 (proxy 손계산 금지). metric_type=canonical_screen.
# PIT: C13 Z_Score_Aligned only / C14 IC Usable_Date<=sig_date / C15 load_month_factors() 경유.
#   재무 lag는 factor DB 빌드 시 이미 반영(quarterly 45d / annual May). forward 1M return은 t+1 실현.
# ============================================================================
suppressMessages({
  library(data.table); library(arrow); library(jsonlite)
})
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = root)
setwd(root)

source(file.path(root, "02_Infrastructure/factor_db/factor_db_connector.R"))
source(file.path(root, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(root, "02_Infrastructure/contracts/canonical_screen_bt.R"))

OUT <- file.path(root, "stage_artifacts/WT_WT-D20260610_001")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

VALUE_FACTORS <- c("V02_EP", "V14_EBIT_EV", "V07_EV_EBITDA", "V20_SP", "V13_EV_Sales", "V01_BM")
TILT_FACTOR   <- "R05_Tail_Risk"
TILT_WEIGHT   <- 0.5
LIQ_MIN       <- 2e8
TOP_N         <- 25L
COST_BPS      <- 15

# ---- 1. month-ends 2005-01 .. 2026-05 (factor DB available) ----
fdb_files <- list.files(file.path(root, ".cache/factor_db"),
                        pattern = "^factor_db_\\d{6}\\.parquet$")
ym_all <- sort(gsub("factor_db_(\\d{6})\\.parquet", "\\1", fdb_files))
ym_use <- ym_all[ym_all >= "200501" & ym_all <= "202605"]
sig_months <- as.Date(paste0(substr(ym_use, 1, 4), "-", substr(ym_use, 5, 6), "-01"))
cat(sprintf("[setup] %d sig months: %s .. %s\n", length(sig_months),
            as.character(min(sig_months)), as.character(max(sig_months))))

# ---- 2. RAWDATA: month-end Close + 20d ADV (t-1 PIT) + forward 1M return ----
raw <- as.data.table(read_parquet(file.path(root, ".cache/rawdata.parquet"),
                                  col_select = c("Date","Ticker","Close","Vol","Ret","BM_Ret"),
                                  as_data_frame = TRUE))
raw[, Date := as.Date(Date)]
setorder(raw, Ticker, Date)
raw <- raw[!is.na(Close) & Close > 0]
raw[, ym := format(Date, "%Y%m")]

# month-end last trading day per (Ticker, ym)
me <- raw[, .SD[.N], by = .(Ticker, ym)]
setorder(me, Ticker, Date)
# 20d avg trading value (Close*Vol) rolling, t (month-end) — used as liq filter at sig_date.
# We compute on daily then take month-end value. ADV at t reflects past 20 trading days (PIT-safe: uses data up to t).
raw[, dollar_vol := Close * Vol]
raw[, adv20 := frollmean(dollar_vol, 20, align = "right"), by = Ticker]
adv_me <- raw[, .SD[.N], by = .(Ticker, ym), .SDcols = c("Date","adv20")]
setnames(adv_me, "Date", "me_date")

# forward 1M return: month-end close to next month-end close (geometric via daily Ret would be ideal;
# use month-end-to-month-end simple return of Close as the realized forward 1M return per ticker).
setorder(me, Ticker, Date)
me[, Close_next := shift(Close, type = "lead"), by = Ticker]
me[, ym_next := shift(ym, type = "lead"), by = Ticker]
me[, fwd_ret_1m := Close_next / Close - 1]
# only keep contiguous month transitions (no gap) to avoid stale-price returns across delistings/halts
me[, ym_int := as.integer(ym)]
me[, ym_next_int := as.integer(ym_next)]
# month diff = 1 (within year) or 89 (Dec->Jan) handled by date difference instead
me[, gap_ok := !is.na(ym_next) & {
  d1 <- as.integer(substr(ym,1,4))*12 + as.integer(substr(ym,5,6))
  d2 <- as.integer(substr(ym_next,1,4))*12 + as.integer(substr(ym_next,5,6))
  (d2 - d1) == 1L
}]
me <- me[gap_ok == TRUE]

# benchmark: KOSPI200 total return per month (BM_Ret is daily; compound to monthly)
bm_daily <- raw[!is.na(BM_Ret), .(Date, ym, BM_Ret)]
bm_daily <- unique(bm_daily, by = c("Date"))  # BM_Ret market-wide identical per date
bm_m <- bm_daily[, .(BM_Ret_m = prod(1 + BM_Ret) - 1), by = ym]

# ---- 3. Build scores per sig month ----
build_scores_for_month <- function(sig_d) {
  fdt <- tryCatch(load_month_factors(sig_d, coverage_min = 0.05),
                  error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) return(NULL)
  fdt <- fdt[Factor_Name %in% c(VALUE_FACTORS, TILT_FACTOR)]
  if (nrow(fdt) == 0) return(NULL)
  # wide: one column per factor (Z_Score_Aligned, higher=better)
  w <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned",
             fun.aggregate = function(x) mean(x, na.rm = TRUE))
  present_val <- intersect(VALUE_FACTORS, names(w))
  if (length(present_val) < 4L) return(NULL)  # require >=4 of 6 value legs
  # equal-weight value composite = row-mean of available aligned value z (na.rm)
  vmat <- as.matrix(w[, ..present_val])
  w[, value_z := rowMeans(vmat, na.rm = TRUE)]
  # require at least 3 non-NA value legs per ticker
  w[, n_val := rowSums(!is.na(vmat))]
  w <- w[n_val >= 3L]
  # tilt: 0.5 * R05 aligned (if present)
  if (TILT_FACTOR %in% names(w)) {
    w[, tilt_z := get(TILT_FACTOR)]
    w[is.na(tilt_z), tilt_z := 0]
  } else {
    w[, tilt_z := 0]
  }
  w[, score := value_z + TILT_WEIGHT * tilt_z]
  w <- w[is.finite(score)]
  if (nrow(w) == 0) return(NULL)
  data.table(Date = sig_d, Ticker = w$Ticker, score = w$score)
}

cat("[scores] building monthly composite scores...\n")
score_list <- lapply(sig_months, function(sd) {
  s <- build_scores_for_month(sd)
  if (!is.null(s)) cat(sprintf("  %s: %d tickers scored\n", format(sd,"%Y-%m"), nrow(s)))
  s
})
scores_dt <- rbindlist(score_list)
scores_dt[, ym := format(Date, "%Y%m")]
cat(sprintf("[scores] total %d ticker-months across %d months\n",
            nrow(scores_dt), uniqueN(scores_dt$ym)))

# ---- 4. Join forward returns + liquidity + benchmark by ym ----
# scores at sig month ym -> forward return realized over ym->ym_next (me table keyed by ym)
mejoin <- me[, .(Ticker, ym, fwd_ret_1m)]
advjoin <- adv_me[, .(Ticker, ym, adv20)]
S <- merge(scores_dt[, .(Date, Ticker, score, ym)], advjoin, by = c("Ticker","ym"), all.x = TRUE)
S <- merge(S, mejoin, by = c("Ticker","ym"), all.x = TRUE)
S <- S[!is.na(fwd_ret_1m)]                     # need realized forward return
# liquidity filter t-PIT: adv20 >= 2e8 (NA -> drop, conservative since universe is "liquid names")
S_liq <- S[!is.na(adv20) & adv20 >= LIQ_MIN]
cat(sprintf("[join] pre-liq ticker-months=%d, post-liq(>=2e8)=%d, distinct tickers post=%d\n",
            nrow(S), nrow(S_liq), uniqueN(S_liq$Ticker)))
# universe size per month (post-liq)
uni_sz <- S_liq[, .(n_uni = .N), by = ym]
cat(sprintf("[universe] mean monthly liquid names=%.0f (min=%d, max=%d)\n",
            mean(uni_sz$n_uni), min(uni_sz$n_uni), max(uni_sz$n_uni)))

# ---- 5. canonical_screen_bt inputs ----
scores_in  <- S_liq[, .(Date, Ticker, score)]
returns_in <- S_liq[, .(Date, Ticker, Ret_1m = fwd_ret_1m)]
bench_in   <- merge(unique(S_liq[, .(Date, ym)]), bm_m, by = "ym")[, .(Date, BM_Ret = BM_Ret_m)]
bench_in   <- bench_in[!is.na(BM_Ret)]

cat("[canonical_screen_bt] running top-25 EW long-only, 15bps...\n")
csb <- canonical_screen_bt(scores_in, returns_in, bench_in,
                           top_n = TOP_N, cost_bps_oneway = COST_BPS,
                           liq_dt = NULL, liq_min = LIQ_MIN,
                           run_id = "WT-D20260610_001_value_sleeve",
                           strategy_id = "value_sleeve_full_universe")

cat("\n==== canonical_screen result ====\n")
cat(sprintf("  metric_type        : %s\n", csb$metric_type))
cat(sprintf("  n_months           : %d\n", csb$n_months))
cat(sprintf("  portfolio_alpha_t  : %.3f (NW lag-3)\n", csb$portfolio_alpha_t_nw_lag3))
cat(sprintf("  alpha_t pvalue     : %.4f\n", csb$portfolio_alpha_t_pvalue))
cat(sprintf("  information_ratio  : %.3f\n", csb$information_ratio))
cat(sprintf("  alpha_annualized   : %.4f\n", csb$alpha_annualized))
cat(sprintf("  net_sr (active)    : %.3f\n", csb$net_sr))
cat(sprintf("  mean_active_net/mo : %.5f\n", csb$mean_active_net))
cat(sprintf("  turnover_annual    : %.3f\n", csb$turnover_annual))

# ---- 6. Reconstruct period series for OOS retention v2 + diagnostics + orthogonality ----
# rebuild port net + bench per month to get active series (same logic as canonical_screen_bt)
S_liq2 <- copy(S_liq)
setorder(S_liq2, Date, -score)
W <- S_liq2[, { n <- min(TOP_N, .N); .(Ticker = Ticker[seq_len(n)], w = rep(1/n, n)) }, by = Date]
WR <- merge(W, returns_in, by = c("Date","Ticker"), all.x = TRUE)
WR[is.na(Ret_1m), Ret_1m := 0]
port <- WR[, .(port_gross = sum(w * Ret_1m)), by = Date]
dts <- sort(unique(W$Date))
traded <- numeric(length(dts)); names(traded) <- as.character(dts)
prev <- data.table(Ticker = character(0), w = numeric(0))
for (i in seq_along(dts)) {
  cur <- W[Date == dts[i], .(Ticker, w)]
  m <- merge(cur, prev, by = "Ticker", all = TRUE, suffixes = c("_cur","_prev"))
  m[is.na(w_cur), w_cur := 0]; m[is.na(w_prev), w_prev := 0]
  traded[i] <- sum(abs(m$w_cur - m$w_prev)); prev <- cur
}
port[, cost := traded[as.character(Date)] * COST_BPS / 1e4]
port[, ret_net := port_gross - cost]
port <- merge(port, bench_in, by = "Date")
port[, active := ret_net - BM_Ret]
setorder(port, Date)
af <- 12

# OOS retention v2 (essence_score replication): anchored splits {55/65/75} median of active-IR OOS/IS
a <- port$active; a <- a[is.finite(a)]; n <- length(a)
splits <- c(0.55, 0.65, 0.75)
rets <- vapply(splits, function(fr) {
  k <- floor(n * fr); if (k < 6 || (n-k) < 6) return(NA_real_)
  ia <- a[1:k]; oa <- a[(k+1):n]
  is_ir  <- if (sd(ia) > 0) mean(ia)/sd(ia)*sqrt(af) else NA_real_
  oos_ir <- if (sd(oa) > 0) mean(oa)/sd(oa)*sqrt(af) else NA_real_
  if (is.finite(is_ir) && is_ir > 0.05 && is.finite(oos_ir)) oos_ir/is_ir else NA_real_
}, numeric(1))
oos_retention <- if (any(is.finite(rets))) median(rets[is.finite(rets)]) else NA_real_
cat(sprintf("\n[oos_v2] splits IR-ratio = [%s], median = %.3f\n",
            paste(sprintf("%.3f", rets), collapse=", "), oos_retention))

# DSR (chain => diagnostic only, not a gate). n_trials=1 (single-spec re-construction).
# Bailey-Lopez de Prado deflated SR with n_trials=1 reduces to PSR vs 0; report informational.
sr_active <- mean(a)/sd(a)*sqrt(af)
mu <- mean(a); s <- sd(a)
sk <- mean(((a-mu)/s)^3); ku <- mean(((a-mu)/s)^4)
# expected max SR for n_trials trials (here n=1 -> deflation negligible). Use BLdP formula.
dsr_chain <- {
  n_trials <- 1
  sr0 <- 0  # single trial: no selection inflation benchmark
  sr_se <- sqrt((1 - sk*(sr_active/sqrt(af)) + ((ku-1)/4)*(sr_active/sqrt(af))^2) / (n - 1))
  pnorm(((sr_active/sqrt(af)) - sr0) / sr_se)
}
cat(sprintf("[dsr] net active SR(ann)=%.3f, DSR(chain,n_trials=1,diagnostic)=%.3f\n", sr_active, dsr_chain))

# ---- 7. Rank-IC / ICIR / Harvey-t (advisory diagnostics) ----
# monthly cross-sectional Spearman(score, fwd_ret) over full liquid universe
ic_by_m <- S_liq[, .(ic = if (.N >= 10) suppressWarnings(cor(score, fwd_ret_1m, method="spearman")) else NA_real_), by = ym]
ic_by_m <- ic_by_m[is.finite(ic)]
rank_ic <- mean(ic_by_m$ic)
icir <- rank_ic / sd(ic_by_m$ic)
n_ic <- nrow(ic_by_m)
# Harvey-t on rank-IC (Newey-West not applied here; simple t = mean/se*sqrt(n)) — advisory
ic_t <- rank_ic / (sd(ic_by_m$ic)/sqrt(n_ic))
cat(sprintf("\n[rank-IC] mean=%.4f, ICIR=%.3f, n=%d, IC t-stat=%.3f (ADVISORY — portfolio-alpha t is authoritative)\n",
            rank_ic, icir, n_ic, ic_t))

# monotonicity: decile (use quintile due to wide universe) mean fwd return monotonic increase
S_liq[, q5 := cut(score, breaks = quantile(score, probs = seq(0,1,0.2), na.rm=TRUE),
                  include.lowest=TRUE, labels=FALSE), by = ym]
qret <- S_liq[!is.na(q5), .(mr = mean(fwd_ret_1m)), by = q5][order(q5)]
mono <- suppressWarnings(cor(qret$q5, qret$mr, method="spearman"))
cat(sprintf("[monotonicity] quintile spearman = %.3f | quintile mean fwd ret: %s\n",
            mono, paste(sprintf("Q%d=%.4f", qret$q5, qret$mr), collapse=", ")))

# subperiod stability: IC sign-consistency across 3 eras
ic_by_m[, yr := as.integer(substr(ym,1,4))]
era <- function(y) ifelse(y<=2014,"2005-2014", ifelse(y<=2019,"2015-2019","2020-2026"))
ic_by_m[, era := era(yr)]
sub <- ic_by_m[, .(mic = mean(ic), n=.N), by = era][order(era)]
subperiod_stability <- mean(sign(sub$mic) == sign(rank_ic))
cat(sprintf("[subperiod] %s | stability(sign-consistency)=%.2f\n",
            paste(sprintf("%s: IC=%.4f(n=%d)", sub$era, sub$mic, sub$n), collapse=" | "),
            subperiod_stability))

# 2017+ portfolio-alpha t (selection-restricted comparison vs prior record)
port17 <- port[Date >= as.Date("2017-01-01")]
a17 <- port17$active; a17 <- a17[is.finite(a17)]
t17 <- if (length(a17) >= 6) mean(a17)/(sd(a17)/sqrt(length(a17))) else NA_real_
cat(sprintf("[2017+] portfolio active t (simple, n=%d) = %.3f\n", length(a17), t17))

# ---- 8. Orthogonality vs production book base (ret_orig) ----
pb <- fread(file.path(root,
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv"))
pb[, ym := gsub("-", "", realized_ym)]
pb_m <- pb[, .(ym, ret_orig)]
port[, ym := format(Date, "%Y%m")]
oc <- merge(port[, .(ym, ret_net, active)], pb_m, by = "ym")
cor_book_net    <- suppressWarnings(cor(oc$ret_net, oc$ret_orig))
cor_book_active <- suppressWarnings(cor(oc$active, oc$ret_orig))
cat(sprintf("\n[orthogonality] n_overlap=%d | cor(sleeve_net, book_ret_orig)=%.3f | cor(sleeve_active, book_ret_orig)=%.3f\n",
            nrow(oc), cor_book_net, cor_book_active))

# book-marginal escalation evidence (for [0.5,0.7) band if applicable)
# trailing 36m portfolio active t
tail36 <- tail(port[is.finite(active)], 36)
trailing_port_t <- mean(tail36$active)/(sd(tail36$active)/sqrt(nrow(tail36)))

# ---- 9. Build alpha_vector + confidence_vector from LATEST sig month ----
last_ym <- max(scores_dt$ym)
last_d  <- max(scores_dt[ym==last_ym, Date])
last_scores <- S_liq[ym == last_ym]
if (nrow(last_scores) == 0) {  # latest month may lack fwd return; use scores without fwd filter
  last_scores <- merge(scores_dt[ym==last_ym, .(Date,Ticker,score,ym)], advjoin, by=c("Ticker","ym"), all.x=TRUE)
  last_scores <- last_scores[is.na(adv20) | adv20 >= LIQ_MIN]
}
setorder(last_scores, -score)
# alpha_vector: map composite z-score to expected active return via realized IC slope (alpha_annualized scaling)
# scale: expected monthly active = score_z * (mean_active_net / sd(score among top)) — simple linear proxy
# Use cross-sectional: alpha_i = rank_ic * sd_fwd * z_i (Grinold), monthly horizon
sd_fwd <- sd(S_liq$fwd_ret_1m, na.rm=TRUE)
last_scores[, z_norm := (score - mean(score))/sd(score)]
last_scores[, alpha_hat := rank_ic * sd_fwd * z_norm]   # expected 1M active return (decimal)
# confidence: based on coverage (n_val legs) proxy via z stability — use rank percentile distance + global subperiod stability
last_scores[, conf := pmin(1, pmax(0, 0.4 + 0.4*subperiod_stability + 0.2*(abs(z_norm)/max(abs(z_norm)))))]

alpha_vec <- setNames(round(last_scores$alpha_hat, 6), last_scores$Ticker)
conf_vec  <- setNames(round(last_scores$conf, 4), last_scores$Ticker)
cat(sprintf("\n[alpha_vector] %d tickers @ %s | top5: %s\n",
            length(alpha_vec), last_ym, paste(head(names(alpha_vec),5), collapse=", ")))

# ---- 10. Save alpha_scores.parquet (all ticker-months) ----
scores_out <- S_liq[, .(sig_date = Date, ym, Ticker, score, fwd_ret_1m, adv20)]
write_parquet(scores_out, file.path(OUT, "alpha_scores.parquet"))

# ---- 11. Persist computed metrics to JSON for downstream package build ----
res <- list(
  n_months = csb$n_months,
  portfolio_alpha_t_nw_lag3 = csb$portfolio_alpha_t_nw_lag3,
  portfolio_alpha_t_pvalue = csb$portfolio_alpha_t_pvalue,
  information_ratio = csb$information_ratio,
  alpha_annualized = csb$alpha_annualized,
  net_sr = csb$net_sr,
  mean_active_net = csb$mean_active_net,
  turnover_annual = csb$turnover_annual,
  oos_retention_v2 = oos_retention,
  oos_splits = rets,
  dsr_chain_diagnostic = dsr_chain,
  sr_active_ann = sr_active,
  rank_ic = rank_ic,
  icir = icir,
  ic_t_stat = ic_t,
  n_ic_months = n_ic,
  monotonicity = mono,
  quintile_mean_fwd = setNames(qret$mr, paste0("Q", qret$q5)),
  subperiod_stability = subperiod_stability,
  subperiod_ic = setNames(sub$mic, sub$era),
  port_alpha_t_2017plus = t17,
  n_2017plus = length(a17),
  cor_book_net = cor_book_net,
  cor_book_active = cor_book_active,
  n_book_overlap = nrow(oc),
  trailing36_port_t = trailing_port_t,
  mean_monthly_universe = mean(uni_sz$n_uni),
  last_sig_ym = last_ym,
  n_alpha_tickers = length(alpha_vec),
  alpha_vector = as.list(alpha_vec),
  confidence_vector = as.list(conf_vec),
  date_start = as.character(min(port$Date)),
  date_end = as.character(max(port$Date))
)
write_json(res, file.path(OUT, "_computed_metrics.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8)

# period returns for audit
write.csv(port[, .(Date, ym, port_gross, ret_net, BM_Ret, active)],
          file.path(OUT, "period_returns_sleeve.csv"), row.names = FALSE)

cat("\n[done] artifacts written to", OUT, "\n")
