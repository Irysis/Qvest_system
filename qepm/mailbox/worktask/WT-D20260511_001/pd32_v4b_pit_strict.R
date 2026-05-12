#==============================================================================
# WT-D20260511_001 PD32 v4b — PIT-strict (debug: progress per N)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})

cat("PD32 v4b PIT-strict start:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJ_ROOT, "qepm/mailbox/worktask/WT-D20260511_001")
STAGE_DIR <- file.path(PROJ_ROOT, "stage_artifacts/WT_D20260511_001")
CACHE_DIR <- file.path(PROJ_ROOT, ".cache")
FACTOR_DB_DIR <- file.path(CACHE_DIR, "factor_db")

PD27_ALPHA <- file.path(STAGE_DIR, "alpha_scores_pd27_burn0m.parquet")
PD32_V4_OUT <- file.path(STAGE_DIR, "alpha_scores_pd32_v4_pit_strict.parquet")
PD32_V4_LOG <- file.path(WT_DIR, "pd32_v4b_log.json")

SIG_DATE_CUTOFF_LOCKBOX <- as.Date("2024-01-22")
UNIVERSE_LABEL <- "KR_top342"
COMPOSITE_FACTORS <- c("CR11_Idiosyncratic_Return","INV10_Smart_Money_Flow","INV09_Flow_Persistence")

source(file.path(PROJ_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
source(file.path(PROJ_ROOT, "02_Infrastructure/factor_db/universe_expanded_v2.R"))

pd27 <- as.data.table(read_parquet(PD27_ALPHA))
sig_dates <- sort(unique(pd27$Date))
sig_dates_pre <- sig_dates[sig_dates <= SIG_DATE_CUTOFF_LOCKBOX]
sig_dates_lockbox <- sig_dates[sig_dates > SIG_DATE_CUTOFF_LOCKBOX & sig_dates <= as.Date("2026-01-23")]
sig_dates_post <- sig_dates[sig_dates > as.Date("2026-01-23")]
fwd_ret <- pd27[, .(sig_date = Date, Ticker, Ret_1m)]; setkey(fwd_ret, sig_date, Ticker)
pd27_key <- pd27[, .(sig_date = Date, Ticker, score_pd27 = score_eff)]; setkey(pd27_key, sig_date, Ticker)
cat("Sig dates: pre=", length(sig_dates_pre), "lockbox=", length(sig_dates_lockbox),
    "post=", length(sig_dates_post), "\n")

# Inline loop with progress every 25
t0 <- Sys.time()
rows <- vector("list", length(sig_dates))
n_uni_per_date <- numeric(length(sig_dates))
n_err <- 0
for(i in seq_along(sig_dates)) {
  sig_d <- sig_dates[i]
  ok <- tryCatch({
    fdt <- load_month_factors(sig_d, coverage_min = 0.05)
    setDT(fdt)
    fsub <- fdt[Factor_Name %in% COMPOSITE_FACTORS, .(Ticker, Factor_Name, Z_Score_Aligned)]
    if(nrow(fsub) == 0) stop("empty factors")
    fwide <- dcast(fsub, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
    uni <- build_universe_v2(sig_d, label = UNIVERSE_LABEL)
    fwide_uni <- fwide[Ticker %in% uni$Ticker]
    if(nrow(fwide_uni) == 0) stop("no universe overlap")
    avail <- intersect(COMPOSITE_FACTORS, names(fwide_uni))
    for(f in avail) {
      v <- fwide_uni[[f]]
      mu <- mean(v, na.rm=TRUE); sg <- sd(v, na.rm=TRUE)
      if(!is.na(sg) && sg > 1e-10) fwide_uni[[f]] <- (v - mu)/sg
      else fwide_uni[[f]] <- NA_real_
    }
    mat <- as.matrix(fwide_uni[, ..avail])
    comp_raw <- rowMeans(mat, na.rm=TRUE)
    comp_raw[is.nan(comp_raw)] <- NA
    mu <- mean(comp_raw, na.rm=TRUE); sg <- sd(comp_raw, na.rm=TRUE)
    comp_z <- if(!is.na(sg) && sg > 1e-10) (comp_raw - mu)/sg else NA_real_
    rows[[i]] <<- data.table(sig_date = sig_d, Ticker = fwide_uni$Ticker,
                              composite_z = comp_z, n_universe = nrow(fwide_uni))
    n_uni_per_date[i] <<- nrow(fwide_uni)
    TRUE
  }, error = function(e) { cat(sprintf("  ERR sig=%s: %s\n", as.character(sig_d), conditionMessage(e))); FALSE })
  if(!ok) n_err <- n_err + 1L
  if(i %% 25 == 0) cat(sprintf("  progress i=%d / %d (%.1f min elapsed) ok=%d err=%d\n",
                                i, length(sig_dates),
                                as.numeric(difftime(Sys.time(), t0, units="mins")),
                                i - n_err, n_err))
}
cat(sprintf("Loop done. err=%d ok=%d\n", n_err, length(sig_dates) - n_err))

all_comp <- rbindlist(rows[!sapply(rows, is.null)], fill=TRUE)
all_comp <- all_comp[!is.na(composite_z)]
cat(sprintf("Composite rows: %d unique sig_dates: %d tickers: %d\n",
            nrow(all_comp), uniqueN(all_comp$sig_date), uniqueN(all_comp$Ticker)))
avg_uni <- mean(n_uni_per_date[n_uni_per_date > 0])
cat(sprintf("Avg universe size per date: %.0f\n", avg_uni))

# ---- Diagnostics ----
nw_t <- function(x) {
  n <- length(x); if(n < 12) return(NA_real_)
  mu <- mean(x); e <- x - mu; L <- 6L
  g0 <- sum(e^2)/n; s <- g0
  for(l in seq_len(L)) {
    w <- 1 - l/(L+1)
    gl <- sum(e[(l+1):n] * e[1:(n-l)])/n
    s <- s + 2*w*gl
  }
  if(s <= 0) return(NA_real_)
  mu / sqrt(s/n)
}

compute_window_stats <- function(comp_dt, window_dates, window_label) {
  sub <- comp_dt[sig_date %in% window_dates]
  if(nrow(sub) == 0) return(list(label=window_label, n_months=0))
  setkey(sub, sig_date, Ticker)
  m <- merge(sub, fwd_ret, by=c("sig_date","Ticker"))[!is.na(composite_z) & !is.na(Ret_1m)]
  ic_per <- m[, .(ic = if(.N >= 20) cor(composite_z, Ret_1m, method="spearman") else NA_real_),
              by=sig_date][!is.na(ic)]
  list(label=window_label, n_months=nrow(ic_per),
       mean_IC=mean(ic_per$ic), sd_IC=sd(ic_per$ic),
       ICIR=mean(ic_per$ic)/sd(ic_per$ic), t_NW_lag6=nw_t(ic_per$ic),
       pos_share=mean(ic_per$ic > 0))
}

cat("\n[Window diagnostics]\n")
ws_pre  <- compute_window_stats(all_comp, sig_dates_pre, "pre_lockbox_DECISION")
ws_lb   <- compute_window_stats(all_comp, sig_dates_lockbox, "lockbox_AUDIT")
ws_post <- compute_window_stats(all_comp, sig_dates_post, "post_lockbox_AUDIT")
ws_full <- compute_window_stats(all_comp, sig_dates, "full_FORGE_INPUT")

print_ws <- function(w) {
  if(w$n_months == 0) { cat(sprintf("  %s: NO DATA\n", w$label)); return() }
  cat(sprintf("  %s: n=%d IC=%.4f ICIR=%.3f t_NW=%.2f pos=%.2f\n",
              w$label, w$n_months, w$mean_IC, w$ICIR, w$t_NW_lag6, w$pos_share))
}
print_ws(ws_pre); print_ws(ws_lb); print_ws(ws_post); print_ws(ws_full)

# cor vs PD27 pre-lockbox
cat("\n[cor vs PD27 pre-lockbox]\n")
sub_pre <- all_comp[sig_date %in% sig_dates_pre]
setkey(sub_pre, sig_date, Ticker)
m_pd <- merge(sub_pre[, .(sig_date, Ticker, composite_z)], pd27_key,
              by=c("sig_date","Ticker"))[!is.na(composite_z) & !is.na(score_pd27)]
c_per <- m_pd[, .(c = if(.N >= 20) cor(composite_z, score_pd27, method="spearman") else NA_real_),
              by=sig_date][!is.na(c)]
cor_pre_mean <- mean(c_per$c)
cor_pre_overall <- cor(m_pd$composite_z, m_pd$score_pd27, method="spearman")
cat(sprintf("  pre-lockbox: cor_overall=%.4f cor_per_mean=%.4f sd=%.4f n=%d | <0.30:%s\n",
            cor_pre_overall, cor_pre_mean, sd(c_per$c), nrow(c_per), abs(cor_pre_mean) < 0.30))

# Monotonicity decile (pre-lockbox)
cat("\n[Monotonicity decile pre-lockbox]\n")
m_pre <- merge(sub_pre, fwd_ret, by=c("sig_date","Ticker"))[!is.na(composite_z) & !is.na(Ret_1m)]
m_pre[, decile := cut(rank(composite_z) / .N, breaks=seq(0,1,0.1), labels=1:10,
                      include.lowest=TRUE), by=sig_date]
dec_ret <- m_pre[, .(mean_ret = mean(Ret_1m, na.rm=TRUE), N=.N), by=decile]
dec_ret <- dec_ret[!is.na(decile)][order(as.integer(decile))]
print(dec_ret)
mono_up <- sum(diff(dec_ret$mean_ret) > 0)
spread <- dec_ret[decile == 10, mean_ret] - dec_ret[decile == 1, mean_ret]
top_better <- m_pre[!is.na(decile), .(better = mean(Ret_1m[decile==10], na.rm=TRUE) >
                                                  mean(Ret_1m[decile==1], na.rm=TRUE)),
                    by=sig_date][, mean(better, na.rm=TRUE)]
cat(sprintf("  mono steps up: %d/9 (%.3f) | spread top-bot: %.4f | top>bot share: %.3f\n",
            mono_up, mono_up/9, spread, top_better))

# Crisis hedge (pre-lockbox)
crisis_windows <- list(c("2008-09-01","2009-03-31"), c("2011-08-01","2011-12-31"),
                       c("2015-06-01","2016-02-29"), c("2020-02-01","2020-04-30"),
                       c("2022-05-01","2022-10-31"))
is_crisis <- function(d) { out <- rep(FALSE,length(d))
  for(w in crisis_windows) out <- out | (d >= as.Date(w[1]) & d <= as.Date(w[2])); out }
m_pre[, regime := ifelse(is_crisis(sig_date), "crisis", "normal")]
ic_r <- m_pre[, .(ic = if(.N >= 20) cor(composite_z, Ret_1m, method="spearman") else NA_real_),
              by=.(sig_date, regime)][!is.na(ic)]
cris_ic <- ic_r[regime=="crisis", mean(ic)]
norm_ic <- ic_r[regime=="normal", mean(ic)]
cat(sprintf("\n[Crisis hedge pre-lockbox] crisis_IC=%.4f normal_IC=%.4f ratio=%.2f AX-001 v2 pass=%s\n",
            cris_ic, norm_ic, cris_ic/norm_ic, cris_ic > 0))

# Subperiod 3-window pre-lockbox
windows <- list(P1=c("2001-07-01","2008-08-31"), P2=c("2009-04-01","2017-12-31"),
                P3=c("2018-01-01","2024-01-22"))
sp_ic <- sapply(windows, function(w) {
  sub <- m_pre[sig_date >= as.Date(w[1]) & sig_date <= as.Date(w[2])]
  if(nrow(sub) < 200) return(NA)
  sub[, .(ic = if(.N >= 20) cor(composite_z, Ret_1m, method="spearman") else NA_real_),
      by=sig_date][!is.na(ic), mean(ic)]
})
mmr <- if(all(!is.na(sp_ic)) && max(abs(sp_ic)) > 1e-6) min(sp_ic)/max(sp_ic) else NA
cat(sprintf("\n[Subperiod 3-window pre-lockbox] P1=%.4f P2=%.4f P3=%.4f mmr=%.3f pass=%s\n",
            sp_ic[1], sp_ic[2], sp_ic[3], mmr, !is.na(mmr) && mmr >= 0.50))

# Save
all_comp[, sleeve_label := "KR_Behavioral_Flow_Sentiment_PIT_strict_v4"]
write_parquet(all_comp, PD32_V4_OUT)
cat("Parquet:", PD32_V4_OUT, "\n")

log_obj <- list(
  task_id = "WT-D20260511_001",
  pd_phase = "PD32_v4b_PIT_strict",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  composite_factors = COMPOSITE_FACTORS,
  pit_methodology = list(
    factor_load_method = "load_month_factors() — Z_Score_Aligned only",
    sign_alignment = "align_factor_direction PIT-mode expanding 36m IC inference",
    no_manual_sign_flip = TRUE,
    universe_filter = UNIVERSE_LABEL,
    universe_method = "build_universe_v2(KR_top342) per sig_date"
  ),
  windows = list(
    pre_lockbox_DECISION = ws_pre,
    lockbox_AUDIT = ws_lb,
    post_lockbox_AUDIT = ws_post,
    full_FORGE_INPUT = ws_full
  ),
  cor_vs_pd27_pre_lockbox = list(
    cor_overall = cor_pre_overall, cor_per_date_mean = cor_pre_mean,
    cor_per_date_sd = sd(c_per$c), n_dates = nrow(c_per),
    pass_lt_0_30 = abs(cor_pre_mean) < 0.30
  ),
  monotonicity_pre_lockbox = list(
    decile_table = as.list(dec_ret),
    mono_steps_up = mono_up, mono_ratio = mono_up/9,
    pass_0_80 = mono_up >= 0.80,
    top10_minus_bot1 = spread,
    top_better_share_per_date = top_better,
    pass_top_better_0_60 = top_better >= 0.60
  ),
  crisis_hedge_pre_lockbox = list(
    crisis_IC = cris_ic, normal_IC = norm_ic,
    ratio = cris_ic/norm_ic, ax001_v2_pass = cris_ic > 0,
    n_crisis_months = nrow(ic_r[regime=="crisis"]),
    n_normal_months = nrow(ic_r[regime=="normal"])
  ),
  subperiod_3_window_pre_lockbox = list(
    P1 = sp_ic[1], P2 = sp_ic[2], P3 = sp_ic[3],
    min_max_ratio = mmr, pass = !is.na(mmr) && mmr >= 0.50
  ),
  avg_universe_size_per_date = avg_uni,
  output_parquet = PD32_V4_OUT
)
write_json(log_obj, PD32_V4_LOG, pretty=TRUE, auto_unbox=TRUE)
cat("Log:", PD32_V4_LOG, "\n")

cat("\nPD32 v4b done:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
