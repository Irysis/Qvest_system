# ============================================================
# WT-D20260529_001 FLOW — Risk Remediation (Codex Round disposition)
# Addresses: C1 (Sigma label) C2 (CVaR horizon/cap) C3 (RF-R4 + 8-period stress)
#            C4 (real PG2 cross-book TDC/style) C5 (estimator: + const-correlation)
# ============================================================
suppressMessages({ library(arrow); library(data.table); library(jsonlite) })
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
SA   <- file.path(ROOT, "stage_artifacts/WT_D20260529_001_FLOW")
AS_OF<- as.Date("2023-10-31"); WIN_START <- AS_OF - 760L
s <- readRDS(file.path(SA,"risk_summary.rds"))
top20 <- s$top20; ew <- rep(1/length(top20), length(top20)); P <- length(top20)

raw <- as.data.table(read_parquet(file.path(ROOT, ".cache/RAWDATA.parquet")))

# ----- FLOW sleeve daily returns (window) -----
sub <- raw[Ticker %in% top20 & Date <= AS_OF & Date >= WIN_START, .(Date,Ticker,Ret)]
rw  <- dcast(sub, Date~Ticker, value.var="Ret"); dts <- rw$Date
rm_ <- as.matrix(rw[, ..top20]); rm_[is.na(rm_)] <- 0
flow_ret <- as.numeric(rm_ %*% ew)
names(flow_ret) <- as.character(dts)

# ============================================================
# C5: + constant-correlation (Ledoit-Wolf 2003 CC target) estimator
# ============================================================
cond_num <- function(m){ev<-eigen(m,symmetric=TRUE,only.values=TRUE)$values; max(ev)/max(min(ev),1e-12)}
S <- cov(rm_)*252
sds <- sqrt(diag(S)); R <- S/outer(sds,sds)
rbar <- mean(R[upper.tri(R)])               # avg pairwise corr
Rcc <- matrix(rbar, P, P); diag(Rcc) <- 1
S_cc_target <- Rcc * outer(sds,sds)
# shrink sample toward CC target at intensity matching LW (0.4711 from codex audit)
alpha_cc <- 0.4711
S_cc <- (1-alpha_cc)*S + alpha_cc*S_cc_target
cat(sprintf("const_correlation cond: %.2f (rbar %.3f)\n", cond_num(S_cc), rbar))

# ============================================================
# C2: CVaR horizon explicit + cap comparison + EVT Hill alpha
# CVaR95 = 0.0343 is DAILY. Monthly-equivalent for cap comparison.
# ============================================================
cvar95_daily <- s$tail_risk$cvar95
# horizon scaling sqrt-time to 1M (21 trading days) for monthly cap comparison
cvar95_monthly <- cvar95_daily * sqrt(21)
cap_monthly <- 0.025*sqrt(21)  # interpret default 0.025 cap context; report both
# Hill estimator on lower tail
losses <- -flow_ret[flow_ret<0]; losses <- sort(losses, decreasing=TRUE)
k <- max(10L, floor(0.1*length(losses)))
hill_alpha <- 1/mean(log(losses[1:k]/losses[k]))
cat(sprintf("CVaR95 daily %.4f -> monthly(sqrt21) %.4f | Hill alpha %.2f\n",
            cvar95_daily, cvar95_monthly, hill_alpha))

# ============================================================
# C3: FULL 8-PERIOD canonical stress (strategy_analyzer def) + RF-R4 flag
# ============================================================
stress8 <- list(
  Terror_9_11    = c("2001-09-01","2001-12-31"),
  GFC            = c("2007-10-01","2009-03-31"),
  Euro_Debt      = c("2011-07-01","2011-12-31"),
  China_Shock    = c("2015-06-01","2016-02-29"),
  US_China_Trade = c("2018-03-01","2018-12-31"),
  COVID          = c("2020-01-01","2020-06-30"),
  Rate_Hike      = c("2022-01-01","2022-12-31"),
  Iran_War       = c("2026-02-01","2026-04-30")
)
st <- list(); rf_r4 <- character(0)
for (nm in names(stress8)) {
  w <- as.Date(stress8[[nm]])
  d <- raw[Ticker %in% top20 & Date>=w[1] & Date<=w[2], .(Date,Ticker,Ret)]
  cn <- uniqueN(d$Ticker); cov <- cn/P
  if (cn==0) { st[[nm]] <- list(sleeve=NA, bm=NA, coverage=0, status="UNRELIABLE_NO_DATA"); next }
  sw <- dcast(d, Date~Ticker, value.var="Ret"); m<-as.matrix(sw[,-1]); m[is.na(m)]<-0
  ewn<-rep(1/ncol(m),ncol(m)); sleeve<-prod(1+as.numeric(m%*%ewn))-1
  bmw<-raw[Date>=w[1]&Date<=w[2], .(BM_Ret=BM_Ret[1]), by=Date][order(Date)]
  bmc<-prod(1+bmw$BM_Ret,na.rm=TRUE)-1
  status<-if(cov<0.85)"UNRELIABLE_PARTIAL_COVERAGE" else "OK"
  st[[nm]]<-list(sleeve=round(sleeve,4),bm=round(bmc,4),coverage=round(cov,3),n=cn,status=status)
  if(!is.na(sleeve) && sleeve < -0.25 && status=="OK")
    rf_r4 <- c(rf_r4, sprintf("%s sleeve %.1f%% < -25%% (vs bm %.1f%%)", nm, 100*sleeve, 100*bmc))
}
cat("\n--- 8-PERIOD STRESS ---\n")
for(nm in names(st)){r<-st[[nm]];cat(sprintf("%-15s sleeve %s bm %s cov %s [%s]\n",nm,
  ifelse(is.na(r$sleeve),"NA",sprintf("%+.3f",r$sleeve)),
  ifelse(is.na(r$bm),"NA",sprintf("%+.3f",r$bm)),r$coverage,r$status))}
cat("\nRF-R4 (OK-coverage stress loss >25%):\n"); cat(if(length(rf_r4))paste(rf_r4,collapse="\n")else"none","\n")

# ============================================================
# C4: REAL PG2 active-book cross-comparison (STR_1715_AR_on_M4_R05_overlay_PG2)
# Build PG2 daily return from actual holdings, compute cross-book TDC + corr + overlap
# ============================================================
h1715 <- fread(file.path(ROOT,"stage_artifacts/WT_WT-S20260504_005/_logs/str1715_actual_holdings_268m.csv"))
h1715[, Date := as.Date(Date)]
# nearest holdings snapshot <= as_of
snap_dates <- sort(unique(h1715$Date)); snap <- max(snap_dates[snap_dates<=AS_OF])
hold_now <- h1715[Date==snap, .(Ticker, weight)]
cat(sprintf("\nPG2 STR_1715 holdings snapshot %s: %d names\n", as.character(snap), nrow(hold_now)))
# holdings overlap with FLOW top20
overlap_names <- intersect(hold_now$Ticker, top20)
overlap_pct <- length(overlap_names)/P
cat(sprintf("Holdings overlap FLOW top20 vs PG2: %d names (%.0f%%): %s\n",
            length(overlap_names), 100*overlap_pct, paste(overlap_names,collapse=" ")))

# PG2 daily return over window using held names (weights renormalized, fixed snapshot proxy)
pg_tk <- hold_now$Ticker; pg_w <- hold_now$weight/sum(hold_now$weight)
subp <- raw[Ticker %in% pg_tk & Date<=AS_OF & Date>=WIN_START, .(Date,Ticker,Ret)]
rwp <- dcast(subp, Date~Ticker, value.var="Ret")
common_tk <- intersect(pg_tk, names(rwp))
mp <- as.matrix(rwp[, ..common_tk]); mp[is.na(mp)]<-0
wv <- pg_w[match(common_tk, pg_tk)]; wv <- wv/sum(wv)
pg_ret <- as.numeric(mp %*% wv); names(pg_ret) <- as.character(rwp$Date)
# align dates
cd <- intersect(names(flow_ret), names(pg_ret))
f <- flow_ret[cd]; p <- pg_ret[cd]
cross_corr <- cor(f, p)
# cross-book lower-tail dependence
emp_ltdc <- function(x,y,q=0.10){u<-rank(x)/(length(x)+1);v<-rank(y)/(length(y)+1);b<-mean(u<=q&v<=q);mg<-mean(v<=q);if(mg==0)NA else b/mg}
cross_tdc <- emp_ltdc(f, p)
cat(sprintf("Cross-book FLOW vs PG2: return corr %.3f | lower-TDC %.3f | n_days %d\n",
            cross_corr, cross_tdc, length(cd)))

# Combined-book HHI (50/50 illustrative — optimizer decides): union holdings concentration
comb <- rbindlist(list(data.table(Ticker=top20, w=0.5/P), data.table(Ticker=pg_tk, w=0.5*pg_w)))
comb <- comb[, .(w=sum(w)), by=Ticker]
comb_hhi <- sum(comb$w^2); comb_neff <- 1/comb_hhi
cat(sprintf("Combined-book(50/50 illust) HHI %.3f n_eff %.1f n_union %d\n", comb_hhi, comb_neff, nrow(comb)))

# ============================================================
# SAVE remediation results
# ============================================================
remed <- list(
  const_correlation_cond = round(cond_num(S_cc),2), rbar = round(rbar,3), lw_shrinkage_intensity = alpha_cc,
  cvar95_daily = round(cvar95_daily,5), cvar95_monthly_sqrt21 = round(cvar95_monthly,5), hill_alpha = round(hill_alpha,2),
  stress8 = st, rf_r4 = rf_r4,
  pg2_snapshot = as.character(snap), pg2_n = nrow(hold_now),
  holdings_overlap_n = length(overlap_names), holdings_overlap_pct = round(overlap_pct,3), overlap_names = overlap_names,
  cross_book_corr = round(cross_corr,4), cross_book_tdc = round(cross_tdc,4), cross_n_days = length(cd),
  combined_hhi = round(comb_hhi,4), combined_neff = round(comb_neff,2), combined_n_union = nrow(comb)
)
saveRDS(remed, file.path(SA,"risk_remediation.rds"))
write_json(remed, file.path(SA,"risk_remediation.json"), pretty=TRUE, auto_unbox=TRUE)
cat("\n[DONE remediation]\n")
