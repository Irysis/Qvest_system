# =============================================================================
# Value Sleeve Combination A/B — Stage 1 sleeve-level blend (Forge measurement)
# Pre-registered grid w_value in {0.05,0.10,0.15,0.20,0.30}. selection_type=sweep.
# Reconstructs value sleeve net series (read-only) + loads book ret_L5_V2.
# Blend via PerformanceAnalytics::Return.portfolio (NO hand synthesis).
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(xts); library(PerformanceAnalytics)
})
setDTthreads(1)  # avoid segfault on this shell

PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CACHE  <- file.path(PROJECT_ROOT, ".cache")
VS_DIR <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_WT-D20260611_001_value_sleeve")
BOOK_CSV <- file.path(PROJECT_ROOT,
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv")
OUTDIR <- file.path(PROJECT_ROOT, "04_Research/composition_search/value_sleeve_combination")

source(file.path(PROJECT_ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))

TOP_N <- 20L; COST_BPS <- 15; LIQ_MIN <- 2e8
VALUE_FACTORS <- c("V02_EP","V14_EBIT_EV","V07_EV_EBITDA","V20_SP","V13_EV_Sales","V01_BM")

# =============================================================================
# 1. Reconstruct value sleeve monthly net return series (read-only re-run of
#    run_alpha.R build_sleeve_series logic). Keyed by realized_ym.
# =============================================================================
cat("[1] Reconstructing value sleeve net series...\n")
scores <- as.data.table(read_parquet(file.path(VS_DIR, "scores_cache.parquet")))

raw <- as.data.table(read_parquet(file.path(CACHE, "rawdata.parquet"),
  col_select = c("Date","Ticker","Close","Vol","Ret","AdminStock","TradingHalt","UnfaithfulDisc")))
raw[, Date := as.Date(Date)]
raw <- raw[Date >= as.Date("2005-01-01") & Date <= as.Date("2026-06-30")]
raw[, ym := format(Date, "%Y%m")]
setorder(raw, Ticker, Date)
me_dates <- raw[, .(eom = max(Date)), by = ym]; setorder(me_dates, ym)

mret <- raw[!is.na(Ret), .(mret = prod(1 + Ret) - 1, ndays = .N), by = .(Ticker, ym)]
mret <- mret[ndays >= 5]

raw[, tv := Vol * Close]
setorder(raw, Ticker, Date)
raw[, adv20 := frollmean(tv, 20, align = "right"), by = Ticker]
me_liq <- raw[Date %in% me_dates$eom,
  .(Ticker, ym, adv20, bad = (AdminStock %in% 1)|(TradingHalt %in% 1)|(UnfaithfulDisc %in% 1))]
me_liq[is.na(bad), bad := FALSE]

ym_sorted <- sort(unique(me_dates$ym))
next_map <- data.table(ym = ym_sorted[-length(ym_sorted)], ym_next = ym_sorted[-1])
fwd <- merge(next_map, mret[, .(Ticker, ym_next = ym, Ret_1m = mret)], by = "ym_next", allow.cartesian = TRUE)
fwd <- fwd[, .(ym, Ticker, Ret_1m)]
ym2date <- me_dates[, .(ym, Date = eom)]

scores_dt <- merge(scores[, .(ym, Ticker, score)], ym2date, by = "ym")[, .(Date, Ticker, score)]
returns_dt <- merge(fwd, ym2date, by = "ym")[, .(Date, Ticker, Ret_1m)]
liq_dt <- merge(me_liq[bad == FALSE, .(ym, Ticker, adv = adv20)], ym2date, by = "ym")[, .(Date, Ticker, adv)]
valid_dates <- intersect(unique(returns_dt$Date), unique(scores_dt$Date))
scores_dt <- scores_dt[Date %in% valid_dates]; returns_dt <- returns_dt[Date %in% valid_dates]
liq_dt <- liq_dt[Date %in% valid_dates]

# identical build_sleeve_series logic
S <- copy(scores_dt)[!is.na(score)]
S <- merge(S, liq_dt[, .(Date, Ticker, adv)], by = c("Date","Ticker"), all.x = TRUE)
S <- S[is.na(adv) | adv >= LIQ_MIN]; S[, adv := NULL]
setorder(S, Date, -score)
W <- S[, { n <- min(TOP_N, .N); .(Ticker = Ticker[seq_len(n)], w = rep(1/n, n)) }, by = Date]
R <- returns_dt[!is.na(Ret_1m)]
WR <- merge(W, R, by = c("Date","Ticker"), all.x = TRUE); WR[is.na(Ret_1m), Ret_1m := 0]
port <- WR[, .(port_gross = sum(w * Ret_1m)), by = Date]
dts <- sort(unique(W$Date)); traded <- numeric(length(dts)); names(traded) <- as.character(dts)
prev <- data.table(Ticker = character(0), w = numeric(0))
for (i in seq_along(dts)) {
  cur <- W[Date == dts[i], .(Ticker, w)]
  m <- merge(cur, prev, by = "Ticker", all = TRUE)
  m[is.na(w.x), `:=`(w.x = 0)]; m[is.na(w.y), `:=`(w.y = 0)]
  traded[i] <- sum(abs(m$w.x - m$w.y)); prev <- cur
}
port[, cost := traded[as.character(Date)] * COST_BPS / 1e4]
port[, ret_net := port_gross - cost]
sleeve <- port[, .(Date, sleeve_ret = ret_net)]
# map sig Date -> realized_ym (next month)
sleeve <- merge(sleeve, me_dates[, .(Date = eom, sig_ym = ym)], by = "Date")
sleeve <- merge(sleeve, next_map[, .(sig_ym = ym, rym = ym_next)], by = "sig_ym")
sleeve[, realized_ym := paste0(substr(rym,1,4),"-",substr(rym,5,6))]
sleeve_v <- sleeve[, .(realized_ym, value_ret = sleeve_ret)]
cat(sprintf("   value sleeve months=%d range %s..%s\n", nrow(sleeve_v),
            min(sleeve_v$realized_ym), max(sleeve_v$realized_ym)))

# standalone sanity (PerformanceAnalytics)
v_xts <- xts(sleeve_v$value_ret, order.by = as.Date(paste0(sleeve_v$realized_ym,"-01")))
vs_sr <- as.numeric(SharpeRatio.annualized(v_xts, Rf = 0))
cat(sprintf("   value standalone SR (PerfA annualized)=%.4f  TO_annual=%.1f%%\n",
            vs_sr, mean(traded)*12*100))

# =============================================================================
# 2. Load book ret_L5_V2 (read-only) + benchmark monthly. Keyed by realized_ym.
# =============================================================================
cat("[2] Loading book ret_L5_V2 + benchmark...\n")
book <- fread(BOOK_CSV)
book_v <- book[, .(realized_ym, book_ret = ret_L5_V2)]
book_v <- book_v[!is.na(book_ret)]
b_xts <- xts(book_v$book_ret, order.by = as.Date(paste0(book_v$realized_ym,"-01")))
book_sr <- as.numeric(SharpeRatio.annualized(b_xts, Rf=0))
cat(sprintf("   book months=%d  SR(PerfA)=%.4f  (expect ~1.886 @267m)\n", nrow(book_v), book_sr))

bm <- as.data.table(read_parquet(file.path(CACHE, "benchmark.parquet")))
bm[, Date := as.Date(Date)]; bm[, ym := format(Date, "%Y%m")]
bmret <- bm[!is.na(BM_Ret), .(bm_mret = prod(1 + BM_Ret) - 1), by = ym]
bmret[, realized_ym := paste0(substr(ym,1,4),"-",substr(ym,5,6))]
bench_v <- bmret[, .(realized_ym, bench_ret = bm_mret)]

# =============================================================================
# 3. Intersect common months
# =============================================================================
cat("[3] Intersecting...\n")
M <- Reduce(function(a,b) merge(a,b,by="realized_ym"),
            list(book_v, sleeve_v, bench_v))
setorder(M, realized_ym)
M <- M[!is.na(book_ret) & !is.na(value_ret) & !is.na(bench_ret)]
cat(sprintf("   common months=%d  range %s..%s\n", nrow(M), M$realized_ym[1], M$realized_ym[nrow(M)]))
n_overlap <- nrow(M)

cor_vb <- cor(M$value_ret, M$book_ret)
cat(sprintf("   cor(value, book)=%.4f  (anchor expect ~ -0.042)\n", cor_vb))

dates <- as.Date(paste0(M$realized_ym, "-01"))
ret_mat <- xts(cbind(book = M$book_ret, value = M$value_ret), order.by = dates)
bench_xts <- xts(M$bench_ret, order.by = dates)

# =============================================================================
# 4. metric helpers (PerformanceAnalytics + contract build_benchmark_compare)
# =============================================================================
metric_block <- function(ret_xts, tag) {
  # PerformanceAnalytics standard funcs only
  sr   <- as.numeric(SharpeRatio.annualized(ret_xts, Rf = 0))
  ann  <- table.AnnualizedReturns(ret_xts, Rf = 0, scale = 12)
  cagr <- as.numeric(ann["Annualized Return", 1])
  mdd  <- as.numeric(maxDrawdown(ret_xts))   # positive number
  calmar <- if (mdd > 0) cagr / mdd else NA_real_
  # contract benchmark compare (IR / PORT_t / alpha / beta / cor)
  pr <- data.table(date = index(ret_xts), ret_net = as.numeric(ret_xts), frequency = "monthly")
  bdt <- data.table(date = index(bench_xts), benchmark_ret = as.numeric(bench_xts),
                    benchmark_id = "KOSPI200_KQ150_BM")
  bc <- build_benchmark_compare(pr, bdt, run_id = tag, strategy_id = tag, annualization_factor = 12)
  getv <- function(nm) bc[metric_name == nm, active_value][1]
  list(tag = tag, n_months = nrow(pr), SR = sr, CAGR = cagr, MDD = mdd, Calmar = calmar,
       IR = getv("Information_Ratio"), TE = getv("Tracking_Error"),
       PORT_t = getv("Portfolio_Alpha_t_NW_lag3"),
       alpha_ann = getv("Alpha_Annualized"),
       beta = bc[metric_name=="Beta_to_Benchmark", strategy_value][1],
       cor_bm = bc[metric_name=="Correlation", strategy_value][1])
}

# baseline book-only
bk <- metric_block(ret_mat[, "book"], "book_only")
cat(sprintf("[4] book-only: SR=%.4f CAGR=%.4f MDD=%.4f Calmar=%.4f IR=%.4f PORT_t=%.3f\n",
            bk$SR, bk$CAGR, bk$MDD, bk$Calmar, bk$IR, bk$PORT_t))

# =============================================================================
# 5. Blend grid via Return.portfolio (monthly rebalance) + honest blend cost
# =============================================================================
cat("[5] Blend grid (Return.portfolio, monthly rebal)...\n")
W_GRID <- c(0.05, 0.10, 0.15, 0.20, 0.30)
BLEND_REBAL_BPS <- 15  # one-way, applied to sleeve-level monthly rebal turnover

blend_one <- function(wv) {
  wts <- c(book = 1 - wv, value = wv)
  # Return.portfolio: monthly rebalance to target -> exact weight drift handling
  rp <- Return.portfolio(ret_mat, weights = wts, rebalance_on = "months",
                         verbose = TRUE)
  gross <- rp$returns
  # honest blend-level cost: sleeve-to-sleeve rebalance turnover.
  # rp$BOP.Weight = begin-of-period (post-rebalance target) weights;
  # rp$EOP.Weight = end-of-period (drifted) weights. Turnover at each rebalance =
  # sum |BOP_t - EOP_{t-1}| across the 2 sleeves. (sleeve-internal TO already in net series.)
  bop <- rp$BOP.Weight; eop <- rp$EOP.Weight
  to <- rep(0, nrow(bop))
  for (i in 2:nrow(bop)) to[i] <- sum(abs(as.numeric(bop[i,]) - as.numeric(eop[i-1,])))
  cost_x <- xts(to * BLEND_REBAL_BPS / 1e4, order.by = index(gross))
  net <- gross - cost_x
  list(net = net, mean_blend_to_annual = mean(to) * 12)
}

results <- list()
for (wv in W_GRID) {
  bl <- blend_one(wv)
  mb <- metric_block(bl$net, sprintf("blend_w%02d", round(wv*100)))
  mb$w_value <- wv
  mb$blend_to_annual <- bl$mean_blend_to_annual
  results[[as.character(wv)]] <- mb
  cat(sprintf("   w=%.2f: SR=%.4f dSR=%+.4f CAGR=%.4f MDD=%.4f Calmar=%.4f dCalmar=%+.4f IR=%.4f dIR=%+.4f PORT_t=%.3f blend_TO=%.1f%%\n",
              wv, mb$SR, mb$SR-bk$SR, mb$CAGR, mb$MDD, mb$Calmar, mb$Calmar-bk$Calmar,
              mb$IR, mb$IR-bk$IR, mb$PORT_t, mb$blend_to_annual*100))
}

# =============================================================================
# 6. DSR (sweep, n_trials=5) — diagnostic. Deflated Sharpe over the 5 blend SRs.
#    Bailey-Lopez de Prado: SR0 = sqrt((1-gamma)*qnorm(1-1/N) + gamma*qnorm(1-1/(N*e)))/sqrt(n)...
#    use standard DSR vs benchmark SR* from trial dispersion.
# =============================================================================
cat("[6] DSR (n_trials=5, sweep)...\n")
trial_srs <- sapply(results, function(x) x$SR)
n_obs <- n_overlap
N_trials <- length(trial_srs)
# best blend (by IR, the selection metric) — but DSR uses its SR
sel_metric <- sapply(results, function(x) x$IR)
best_key <- names(which.max(sel_metric))
best <- results[[best_key]]
# Bailey-LdP expected max SR under null (annualized SRs -> convert to per-period not needed for E[max])
sr_var <- var(trial_srs)
emc <- 0.5772156649
e <- exp(1)
exp_max <- sqrt(sr_var) * ((1-emc)*qnorm(1 - 1/N_trials) + emc*qnorm(1 - 1/(N_trials*e)))
# moments of best net series (monthly) for DSR
best_net <- blend_one(best$w_value)$net
r <- as.numeric(best_net)
sr_monthly <- mean(r)/sd(r)
g3 <- mean(((r-mean(r))/sd(r))^3); g4 <- mean(((r-mean(r))/sd(r))^4)
sr_star_annual <- exp_max          # annualized benchmark
sr_star_monthly <- sr_star_annual / sqrt(12)
dsr_z <- (sr_monthly - sr_star_monthly) * sqrt(n_obs - 1) /
         sqrt(1 - g3*sr_monthly + (g4-1)/4*sr_monthly^2)
DSR <- pnorm(dsr_z)
cat(sprintf("   best by IR = %s (w=%.2f) SR=%.4f  E[maxSR null]=%.4f  DSR=%.4f\n",
            best_key, best$w_value, best$SR, exp_max, DSR))

# =============================================================================
# 7. Combined holdings count (union of book + value top-20 latest month)
# =============================================================================
cat("[7] Combined holdings count (latest month union)...\n")
last_date <- max(W$Date)
val_last <- W[Date == last_date, Ticker]
book_w_path <- file.path(PROJECT_ROOT,
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/weights_267m_timeseries.csv")
book_holdings_n <- NA_integer_; union_n <- NA_integer_
if (file.exists(book_w_path)) {
  bw <- tryCatch(fread(book_w_path), error=function(e) NULL)
  if (!is.null(bw)) {
    cat(sprintf("   book weights file cols: %s\n", paste(head(names(bw),8),collapse=",")))
  }
}
cat(sprintf("   value sleeve latest holdings n=%d (book top-N ~ up to 25; union > 25 expected)\n",
            length(val_last)))

# =============================================================================
# 8. Emit results.csv + blend_result.json
# =============================================================================
cat("[8] Writing outputs...\n")
rows <- rbindlist(lapply(c(list(bk), results), function(x) {
  data.table(
    label = x$tag,
    w_value = if (is.null(x$w_value)) 0 else x$w_value,
    n_months = x$n_months,
    SR = round(x$SR,4), CAGR = round(x$CAGR,4), MDD = round(x$MDD,4), Calmar = round(x$Calmar,4),
    IR = round(x$IR,4), TE = round(x$TE,4), PORT_t = round(x$PORT_t,3),
    alpha_ann = round(x$alpha_ann,4), beta = round(x$beta,3), cor_bm = round(x$cor_bm,3),
    dSR = round(x$SR - bk$SR,4), dMDD = round(x$MDD - bk$MDD,4),
    dCalmar = round(x$Calmar - bk$Calmar,4), dIR = round(x$IR - bk$IR,4),
    blend_to_annual = if (is.null(x$blend_to_annual)) NA_real_ else round(x$blend_to_annual,4),
    metric_type = "backtested"
  )
}), fill = TRUE)
fwrite(rows, file.path(OUTDIR, "results.csv"))

out <- list(
  meta = list(
    task = "value_sleeve_combination_stage1",
    as_of = "2026-06-11", agent = "forge",
    selection_type = "sweep", n_trials = N_trials,
    grid = W_GRID, n_overlap_months = n_overlap,
    book_series = list(
      source = "05_Production/.../period_returns_layer5.csv col ret_L5_V2",
      variant = "L5_V2_aggressive_regime", admit_sr_255m = 1.9536,
      cost_model = "v2.3_kr_retail_15bps_flat_per_rebalance"),
    value_series = list(
      source = "04_Research/strategies/STR_WT-D20260611_001_value_sleeve/scores_cache.parquet -> build_sleeve_series",
      standalone_sr_perfa = round(vs_sr,4), cost_model = "delta_based_15bps_oneway",
      turnover_annual = round(mean(traded)*12,4)),
    benchmark = ".cache/benchmark.parquet BM_Ret monthly",
    blend_method = "PerformanceAnalytics::Return.portfolio rebalance_on=months",
    blend_cost = "sleeve-level rebal turnover x 15bps one-way (sleeve-internal cost already in net series)",
    ir_substitution_note = "book_optimizer book_information_ratio requires cross-WT packages; series-level analog = build_benchmark_compare Information_Ratio (active/TE)",
    metric_type = "backtested"
  ),
  cor_value_book = round(cor_vb,4),
  book_only = list(SR=round(bk$SR,4), CAGR=round(bk$CAGR,4), MDD=round(bk$MDD,4),
                   Calmar=round(bk$Calmar,4), IR=round(bk$IR,4), PORT_t=round(bk$PORT_t,3)),
  blends = lapply(results, function(x) list(
    w_value = x$w_value, SR=round(x$SR,4), CAGR=round(x$CAGR,4), MDD=round(x$MDD,4),
    Calmar=round(x$Calmar,4), IR=round(x$IR,4), PORT_t=round(x$PORT_t,3),
    dSR=round(x$SR-bk$SR,4), dMDD=round(x$MDD-bk$MDD,4), dCalmar=round(x$Calmar-bk$Calmar,4),
    dIR=round(x$IR-bk$IR,4), blend_to_annual=round(x$blend_to_annual,4))),
  selection = list(best_by_IR = best_key, best_w_value = best$w_value,
                   best_SR = round(best$SR,4), best_dIR = round(best$IR-bk$IR,4)),
  dsr = list(n_trials = N_trials, exp_max_sr_null = round(exp_max,4), DSR = round(DSR,4),
             skew = round(g3,4), kurt = round(g4,4)),
  gate_reference = list(
    dIR_hurdle = 0.05, dIR_best = round(best$IR-bk$IR,4),
    cor_hurdle = 0.30, cor_actual = round(cor_vb,4),
    dsr_hurdle = 0.5, dsr_actual = round(DSR,4),
    combined_holdings_note = "two-sleeve top-20 union > 25 (admission max 25) — research-stage report only")
)
write_json(out, file.path(OUTDIR, "blend_result.json"), pretty = TRUE, auto_unbox = TRUE, digits = 6)
saveRDS(M, file.path(OUTDIR, "aligned_series.rds"))

cat("\n========== DONE ==========\n")
cat(sprintf("overlap=%d months  cor(v,b)=%.4f\n", n_overlap, cor_vb))
cat(sprintf("book SR=%.4f Calmar=%.4f IR=%.4f\n", bk$SR, bk$Calmar, bk$IR))
cat("best blend by IR:", best_key, sprintf("dIR=%+.4f dSR=%+.4f dCalmar=%+.4f DSR=%.4f\n",
    best$IR-bk$IR, best$SR-bk$SR, best$Calmar-bk$Calmar, DSR))
