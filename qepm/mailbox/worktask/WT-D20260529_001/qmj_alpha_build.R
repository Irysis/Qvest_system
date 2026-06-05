# ============================================================
# WT-D20260529_001 Track QMJ — Quality-Minus-Junk 4th-orthogonal alpha
# Multi-axis composite (Asness-Frazzini-Pedersen 2019 QMJ)
# AX-004 EXCLUSION: multi-axis quality composite (NOT single GP/profitability)
# PIT: lockbox 2023-12-22 strict for discovery diagnostics.
#      Connector enforces Usable_Date <= sig_date (C14) + Z_Score_Aligned (C13)
# ============================================================
suppressMessages({library(arrow); library(data.table); library(jsonlite)})

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(ROOT)
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/factor_db/universe_expanded_v2.R")

LOCKBOX <- as.Date("2023-12-22")    # PIT discovery cutoff (alpha-research lockbox)
OUTDIR  <- "stage_artifacts/WT_D20260529_001_QMJ"
dir.create(OUTDIR, showWarnings = FALSE, recursive = TRUE)

# ---- QMJ multi-axis composite spec (AX-004 EXCLUSION) ----
# 3 axes, equal-axis weight (AFP 2019 structure). Within-axis EW.
AXES <- list(
  Profitability = c("Q01_GPA","Q02_ROE","Q03_ROA","Q35_CashBased_OpProf",
                    "Q10_Gross_Margin","Q11_Net_Margin"),
  Safety        = c("Q13_Fin_Leverage","Q25_Ohlson_O","Q07_Earnings_Stability",
                    "AC18_Accrual_Quality","AC10_Pct_Accruals"),
  Growth        = c("GR04_GPA_Growth","GR01_Revenue_Growth","GR02_Earnings_Growth",
                    "GR07_Composite_Growth")
)
ALL_F <- unlist(AXES, use.names = FALSE)

# ---- sig_date grid: month-end 2008-01 .. lockbox ----
# Use STR_1715 panel dates as canonical monthly grid (forward Ret_1m available)
str1715 <- as.data.table(read_parquet(
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet"))
str1715[, Date := as.Date(Date)]
grid <- sort(unique(str1715$Date))
grid <- grid[grid >= as.Date("2008-01-01") & grid <= LOCKBOX]
cat("[grid] n sig_dates:", length(grid), " range:", as.character(range(grid)), "\n")

# returns map: Date,Ticker -> forward 1M return (from str1715 panel; PIT forward label)
retmap <- str1715[, .(Date, Ticker, Ret_1m)]
setkey(retmap, Date, Ticker)

# universe membership cache (PIT) — KR_top342 default
build_uni <- function(sig_date, label) {
  u <- tryCatch(build_universe_v2(sig_date, label = label), error = function(e) NULL)
  if (is.null(u) || !nrow(u)) return(character(0))
  u$Ticker
}

# ---- core: compute QMJ composite score for a sig_date ----
compute_qmj <- function(sig_date, universe_label = "KR_top342") {
  uni <- build_uni(sig_date, universe_label)
  if (!length(uni)) return(NULL)
  f <- tryCatch(load_month_factors(sig_date), error = function(e) NULL)
  if (is.null(f) || !nrow(f)) return(NULL)
  f <- f[Ticker %in% uni & Factor_Name %in% ALL_F]
  if (!nrow(f)) return(NULL)
  # wide
  w <- dcast(f, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned",
             fun.aggregate = function(x) mean(x, na.rm = TRUE))
  # per-axis composite = mean of available aligned-z within axis (require >=2 of axis present)
  axis_score <- function(cols) {
    cols <- intersect(cols, names(w))
    if (length(cols) < 2) return(rep(NA_real_, nrow(w)))
    m <- as.matrix(w[, ..cols])
    navail <- rowSums(!is.na(m))
    s <- rowMeans(m, na.rm = TRUE)
    s[navail < 2] <- NA_real_      # require >=2 proxies per axis (composite, not single)
    s
  }
  w[, prof  := axis_score(AXES$Profitability)]
  w[, safe  := axis_score(AXES$Safety)]
  w[, grow  := axis_score(AXES$Growth)]
  # re-standardize each axis cross-sectionally so axes are comparable
  zstd <- function(x){ m<-mean(x,na.rm=T); s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) return(x*0); (x-m)/s }
  w[, `:=`(prof_z=zstd(prof), safe_z=zstd(safe), grow_z=zstd(grow))]
  # require all 3 axes present (true multi-axis composite per name)
  w <- w[!is.na(prof_z) & !is.na(safe_z) & !is.na(grow_z)]
  if (!nrow(w)) return(NULL)
  # QMJ = equal-axis average (AFP 2019)
  w[, qmj := (prof_z + safe_z + grow_z)/3]
  w[, qmj_z := zstd(qmj)]
  data.table(Date = sig_date, Ticker = w$Ticker,
             qmj_z = w$qmj_z, prof_z = w$prof_z, safe_z = w$safe_z, grow_z = w$grow_z)
}

# ---- build panel across grid (universe = KR_top342) ----
cat("[build] KR_top342 ...\n")
panel <- rbindlist(lapply(seq_along(grid), function(i){
  d <- grid[i]; if(i %% 24 == 0) cat("  ", as.character(d), "\n")
  tryCatch(compute_qmj(d, "KR_top342"), error=function(e) NULL)
}), fill = TRUE)
cat("[build] panel rows:", nrow(panel), " dates:", uniqueN(panel$Date), "\n")

# merge forward return
panel <- merge(panel, retmap, by = c("Date","Ticker"), all.x = TRUE)
panel <- panel[!is.na(Ret_1m)]
cat("[build] with returns:", nrow(panel), "\n")

saveRDS(panel, file.path(OUTDIR, "qmj_panel.rds"))

# ============================================================
# DIAGNOSTICS
# ============================================================
# Rank IC (Spearman) per date
ic_dt <- panel[, .(ic = if(.N>=10) cor(qmj_z, Ret_1m, method="spearman", use="complete.obs") else NA_real_,
                   n = .N), by = Date][!is.na(ic)]
rank_ic <- mean(ic_dt$ic)
icir    <- rank_ic / sd(ic_dt$ic)
nm      <- nrow(ic_dt)
# Newey-West t on monthly IC series (lag 3) — Harvey-style
nw_t <- function(x, lag=3){
  x <- x[!is.na(x)]; n <- length(x); mu <- mean(x); e <- x-mu
  g0 <- sum(e^2)/n
  s <- g0
  for(l in 1:lag){ w<-1-l/(lag+1); g<-sum(e[(l+1):n]*e[1:(n-l)])/n; s<-s+2*w*g }
  se <- sqrt(s/n); mu/se
}
harvey_t <- nw_t(ic_dt$ic, lag=3)

# Subperiod stability (sign-consistency of IC mean across 3 windows)
sp <- function(d0,d1) { x<-ic_dt[Date>=d0 & Date<=d1]$ic; if(length(x)<6) NA else mean(x) }
sp1 <- sp(as.Date("2008-01-01"), as.Date("2014-12-31"))
sp2 <- sp(as.Date("2015-01-01"), as.Date("2019-12-31"))
sp3 <- sp(as.Date("2020-01-01"), LOCKBOX)
sp_vals <- c(sp1,sp2,sp3)
# stability = fraction of subperiods with same sign as overall AND |IC|>0.5*overall
subperiod_stability <- mean(sign(sp_vals)==sign(rank_ic) & abs(sp_vals) >= 0.5*abs(rank_ic), na.rm=TRUE)

# Monotonicity: quintile mean forward return ordering
mono_dt <- panel[, {
  q <- cut(frank(qmj_z, ties.method="first"), 5, labels=FALSE)
  .(q=q, r=Ret_1m)
}, by=Date]
quint <- mono_dt[, .(mr=mean(r,na.rm=TRUE)), by=q][order(q)]
# Spearman of quintile index vs mean return
monotonicity <- cor(quint$q, quint$mr, method="spearman")

# Turnover proxy: average name turnover of top-quintile selection month over month
topq <- panel[, {
  thr <- quantile(qmj_z, 0.8, na.rm=TRUE)
  .(Ticker = Ticker[qmj_z >= thr])
}, by=Date]
dates_o <- sort(unique(topq$Date))
to_vec <- sapply(2:length(dates_o), function(i){
  a <- topq[Date==dates_o[i-1]]$Ticker; b <- topq[Date==dates_o[i]]$Ticker
  if(!length(a)||!length(b)) return(NA_real_)
  length(setdiff(b,a))/length(b)
})
turnover_proxy_monthly <- mean(to_vec, na.rm=TRUE)
turnover_annual <- turnover_proxy_monthly * 12

# ---- Portfolio-alpha t (DISTINCT from IC t) ----
# top-quintile EW long portfolio, monthly active return vs cross-sectional mean (universe EW)
port <- panel[, {
  thr <- quantile(qmj_z, 0.8, na.rm=TRUE)
  sel <- qmj_z >= thr
  uni_ret <- mean(Ret_1m, na.rm=TRUE)
  port_ret <- mean(Ret_1m[sel], na.rm=TRUE)
  .(active = port_ret - uni_ret, port_ret=port_ret, uni_ret=uni_ret, nsel=sum(sel))
}, by=Date][!is.na(active)]
# net-of-cost: subtract turnover*15bps*2 (round trip approximated one-way 15bps on changed names)
cost_monthly <- turnover_proxy_monthly * 0.0015
port[, active_net := active - cost_monthly]
# portfolio alpha t = NW t-stat of net active monthly series
port_alpha_t_gross <- nw_t(port$active, lag=3)
port_alpha_t_net   <- nw_t(port$active_net, lag=3)
mean_active_net    <- mean(port$active_net)
# net-of-cost SR (annualized, monthly active series as the alpha sleeve return)
sr_net <- mean(port$active_net)/sd(port$active_net) * sqrt(12)
sr_gross <- mean(port$active)/sd(port$active) * sqrt(12)

# ---- DSR (Bailey-Lopez de Prado) on the net active series ----
# Deflated Sharpe with N_trials = candidate axes tested (3 axes) + composite = 4 effective
N_trials <- 4
T_n <- nrow(port)
sr_obs <- mean(port$active_net)/sd(port$active_net)   # monthly SR (non-annualized)
sk <- (function(x){m<-mean(x);s<-sd(x);mean((x-m)^3)/s^3})(port$active_net)
ku <- (function(x){m<-mean(x);s<-sd(x);mean((x-m)^4)/s^4})(port$active_net)
# expected max SR under N trials (BLdP)
emc <- 0.5772156649
sr_var <- 1/sqrt(T_n)  # SR sampling sd under null ~ 1/sqrt(T) (BLdP closed form)
z <- qnorm(1-1/N_trials); z2 <- qnorm(1-1/(N_trials*exp(1)))
sr0 <- sr_var * ((1-emc)*z + emc*z2)
# DSR
dsr_den <- sqrt((1 - sk*sr_obs + (ku-1)/4*sr_obs^2)/(T_n-1))
dsr <- pnorm((sr_obs - sr0)/dsr_den)

# ============================================================
# AX-001 v2 ratio (defensive conditional eval) — bad/normal IC ratio
# ============================================================
# bad regime = bottom-decile universe-return months ("crisis"), normal = rest
mret <- panel[, .(uni_ret = mean(Ret_1m,na.rm=TRUE)), by=Date]
mret <- merge(ic_dt, mret, by="Date")
thr_bad <- quantile(mret$uni_ret, 0.15, na.rm=TRUE)
ic_bad  <- mean(mret[uni_ret <= thr_bad]$ic, na.rm=TRUE)
ic_norm <- mean(mret[uni_ret >  thr_bad]$ic, na.rm=TRUE)
ax001_ratio <- ic_bad / ic_norm
# crisis alpha: net active in bad months
crisis_active_net <- mean(port[uni_ret <= thr_bad]$active_net, na.rm=TRUE)

# ============================================================
# ORTHOGONALITY vs STR_1715 (score_eff) and D ML (alpha_z)
# ============================================================
# 1715: score_eff per Date,Ticker — correlate cross-sectionally per date, avg
s15 <- str1715[, .(Date, Ticker, s15 = score_eff)]
m15 <- merge(panel[,.(Date,Ticker,qmj_z)], s15, by=c("Date","Ticker"))
m15 <- m15[!is.na(qmj_z) & !is.na(s15)]
cor15_xs <- m15[, .(c = if(.N>=10) cor(qmj_z, s15, method="spearman") else NA_real_), by=Date]
cor_vs_1715 <- mean(cor15_xs$c, na.rm=TRUE)

# D ML alpha
dml <- as.data.table(read_parquet("stage_artifacts/WT_D20260528_003_overnight_D_ML/alpha_scores.parquet"))
dml[, Date := as.Date(Date)]
dml <- dml[, .(Date, Ticker, dz = alpha_z)]
mD <- merge(panel[,.(Date,Ticker,qmj_z)], dml, by=c("Date","Ticker"))
mD <- mD[!is.na(qmj_z) & !is.na(dz)]
corD_xs <- mD[, .(c = if(.N>=10) cor(qmj_z, dz, method="spearman") else NA_real_), by=Date]
cor_vs_D <- mean(corD_xs$c, na.rm=TRUE)

# ============================================================
# v2 universe comparison (L-227 mandate): KR_TOP500_FREEFLOAT
# ============================================================
cat("[build] KR_TOP500_FREEFLOAT (v2 comparison) ...\n")
panel_v2 <- rbindlist(lapply(grid, function(d){
  tryCatch(compute_qmj(d, "KR_TOP500_FREEFLOAT"), error=function(e) NULL)
}), fill = TRUE)
v2_ok <- !is.null(panel_v2) && nrow(panel_v2)>0
if(v2_ok){
  panel_v2 <- merge(panel_v2, retmap, by=c("Date","Ticker"), all.x=TRUE)[!is.na(Ret_1m)]
  ic2 <- panel_v2[, .(ic=if(.N>=10) cor(qmj_z,Ret_1m,method="spearman",use="complete.obs") else NA_real_), by=Date][!is.na(ic)]
  rank_ic_v2 <- mean(ic2$ic); icir_v2 <- rank_ic_v2/sd(ic2$ic); harvey_t_v2 <- nw_t(ic2$ic,3)
} else { rank_ic_v2<-NA; icir_v2<-NA; harvey_t_v2<-NA }

# ============================================================
# OUTPUT
# ============================================================
diag <- list(
  n_months = nm,
  rank_ic = round(rank_ic,4),
  icir = round(icir,4),
  harvey_t_rank_ic = round(harvey_t,4),
  harvey_t_method = "Newey-West lag=3 on monthly rank-IC series",
  portfolio_alpha_t_gross = round(port_alpha_t_gross,4),
  portfolio_alpha_t_net = round(port_alpha_t_net,4),
  portfolio_alpha_t_note = "DISTINCT from rank-IC t. NW lag=3 on top-quintile EW net active monthly series.",
  monotonicity = round(monotonicity,4),
  subperiod_stability = round(subperiod_stability,4),
  subperiod_ic = list(p2008_14=round(sp1,4), p2015_19=round(sp2,4), p2020_lockbox=round(sp3,4)),
  turnover_proxy_monthly = round(turnover_proxy_monthly,4),
  turnover_annual = round(turnover_annual,4),
  sr_net_of_cost_annual = round(sr_net,4),
  sr_gross_annual = round(sr_gross,4),
  mean_active_net_monthly = round(mean_active_net,5),
  dsr = round(dsr,4),
  dsr_N_trials = N_trials,
  ax001_v2 = list(ic_bad=round(ic_bad,4), ic_normal=round(ic_norm,4),
                  bad_normal_ratio=round(ax001_ratio,4),
                  crisis_active_net_monthly=round(crisis_active_net,5)),
  quintile_returns = setNames(round(quint$mr,5), paste0("Q",quint$q))
)
ortho <- list(cor_vs_STR_1715_score_eff = round(cor_vs_1715,4),
              cor_vs_D_ML_alpha_z = round(cor_vs_D,4),
              n_overlap_1715 = nrow(m15), n_overlap_D = nrow(mD),
              threshold = 0.30,
              pass_1715 = abs(cor_vs_1715) < 0.30,
              pass_D = abs(cor_vs_D) < 0.30)
univ_cmp <- list(KR_top342=list(rank_ic=round(rank_ic,4), icir=round(icir,4), harvey_t=round(harvey_t,4), n=nm),
                 KR_TOP500_FREEFLOAT=list(rank_ic=round(rank_ic_v2,4), icir=round(icir_v2,4),
                                          harvey_t=round(harvey_t_v2,4), n=if(v2_ok) nrow(ic2) else 0))

validation <- list(
  task_id="WT-D20260529_001", track="QMJ", as_of_date="2026-05-29",
  lockbox=as.character(LOCKBOX), universe_default="KR_top342", cost_model="v2.3_kr_retail_15bps",
  diagnostics=diag, orthogonality=ortho, universe_comparison=univ_cmp,
  ax004_exclusion=list(structure="multi-axis quality composite",
    axes=names(AXES), n_factors=length(ALL_F),
    profitability=AXES$Profitability, safety=AXES$Safety, growth=AXES$Growth,
    single_signal_avoided=TRUE,
    note="AFP 2019 QMJ 3-axis. require >=2 proxies/axis AND all 3 axes present per name. NOT single GP/profitability."))

write_json(validation, file.path(OUTDIR,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, digits=6)

# alpha scores parquet (lockbox + carry latest sig_date scores as alpha_vector reference)
alpha_scores <- panel[, .(Date, Ticker, alpha_z=qmj_z, prof_z, safe_z, grow_z,
                          confidence = pmin(1, pmax(0, 0.5 + 0.5*scale(qmj_z)[,1]/3)))]
write_parquet(alpha_scores, file.path(OUTDIR,"alpha_scores.parquet"))

cat("\n================ SUMMARY ================\n")
cat(sprintf("rank_IC=%.4f  ICIR=%.4f  harvey_t(IC)=%.2f  port_alpha_t_net=%.2f\n",
            rank_ic, icir, harvey_t, port_alpha_t_net))
cat(sprintf("SR_net=%.3f  SR_gross=%.3f  DSR=%.3f  mono=%.3f  subperiod=%.2f\n",
            sr_net, sr_gross, dsr, monotonicity, subperiod_stability))
cat(sprintf("TO_ann=%.2f  AX001_v2 ratio=%.3f (bad=%.4f norm=%.4f) crisis_net=%.4f\n",
            turnover_annual, ax001_ratio, ic_bad, ic_norm, crisis_active_net))
cat(sprintf("cor_vs_1715=%.4f  cor_vs_D=%.4f  (thr 0.30)\n", cor_vs_1715, cor_vs_D))
cat(sprintf("v2 FREEFLOAT: rank_IC=%.4f ICIR=%.4f harvey_t=%.2f\n", rank_ic_v2, icir_v2, harvey_t_v2))
cat("=========================================\n")
