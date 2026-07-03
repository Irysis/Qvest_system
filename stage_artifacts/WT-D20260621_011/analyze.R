# WT-D20260621_011 — C29  STEP 8-10: decile term-structure, breadth, era, orthogonality
suppressMessages({library(arrow); library(data.table)})
arrow::set_cpu_count(1L); setDTthreads(1L)
options(stringsAsFactors=FALSE); set.seed(20260621)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT-D20260621_011")
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a

X <- readRDS(file.path(OUT,"scored.rds"))
S <- X$S; returns_dt <- X$returns_dt; bench_dt <- X$bench_dt; liq_dt <- X$liq_dt; best <- X$best
build_scores <- X$build_scores
nw_t <- function(x, lag=3){
  x <- x[is.finite(x)]; n <- length(x); if(n<6) return(NA_real_)
  m <- mean(x); e <- x-m; g0 <- sum(e^2)/n; v <- g0
  for(l in 1:lag){ w <- 1-l/(lag+1); v <- v + 2*w*sum(e[(l+1):n]*e[1:(n-l)])/n }
  m / sqrt(v/n)
}

# ---------- COHORT BREADTH / LUMPINESS (using best PIT-valid config) ----------
cat("=== COHORT BREADTH / LUMPINESS ===\n")
bc <- build_scores(S, best$A_lag, best$A_max, best$tau, best$lambda)
setkey(bc, NULL); bc <- bc[Date>=as.Date("2005-01-01")]
brd <- bc[, .(n_eligible=.N), by="Date"][order(Date)]
cat("config A_lag=",best$A_lag," A_max=",best$A_max,"\n")
cat("eligible names/month: mean=",round(mean(brd$n_eligible),1),
    " median=",median(brd$n_eligible)," min=",min(brd$n_eligible)," max=",max(brd$n_eligible),"\n")
cat("months with <25 eligible:", nrow(brd[n_eligible<25]),"/",nrow(brd),
    " (",round(100*nrow(brd[n_eligible<25])/nrow(brd)),"%)\n")
cat("months with <10 eligible:", nrow(brd[n_eligible<10]),"/",nrow(brd),"\n")
# A_max=3 (shortest, purest catalyst) breadth
bc3 <- build_scores(S, 1L, 3L, 4, 0); setkey(bc3,NULL); bc3 <- bc3[Date>=as.Date("2005-01-01")]
brd3 <- bc3[, .N, by="Date"]
cat("A_max=3 (purest): mean eligible/month=",round(mean(brd3$N),1)," #months<25=",nrow(brd3[N<25]),"/",nrow(brd3),"\n")
fwrite(brd, file.path(OUT,"cohort_breadth.csv"))

# ---------- DECILE TERM-STRUCTURE: age-conditional active return ----------
cat("\n=== AGE-CONDITIONAL active return (drift term structure) ===\n")
# For each (ticker,month) with an inclusion age, compute its forward 1M active return vs BM
S[, Date := as.Date(paste0(ymk,"-01"))]
agetab <- merge(S[in_univ & elig_flags & age<=12, .(Date,Ticker,age,footprint)],
                returns_dt, by=c("Date","Ticker"))
agetab <- merge(agetab, bench_dt, by="Date")
agetab[, active := Ret_1m - BM_Ret]
ages <- agetab[Date>=as.Date("2005-01-01"), .(mean_active=mean(active), n=.N,
              t_nw=nw_t(active)), by=age][order(age)]
cat("age (months since inclusion) -> mean fwd-1M active return (net of nothing; gross active):\n")
print(ages)
fwrite(ages, file.path(OUT,"age_term_structure.csv"))

# ---------- DECILE PROFILING: full-universe 10-decile by score ----------
cat("\n=== DECILE PROFILING (full K200uKQ150 universe, score deciles) ===\n")
# universe = all members each month; score = best config score (0 for non-eligible)
allmem <- S[in_univ==TRUE, .(Date, Ticker)]  # all member-months
sc_best <- build_scores(S, best$A_lag, best$A_max, best$tau, best$lambda)
duniv <- merge(allmem, sc_best, by=c("Date","Ticker"), all.x=TRUE)
duniv[is.na(score), score := 0]
duniv <- merge(duniv, returns_dt, by=c("Date","Ticker"))
duniv <- merge(duniv, bench_dt, by="Date")
duniv[, active := Ret_1m - BM_Ret]
setkey(duniv, NULL)
duniv <- duniv[Date>=as.Date("2005-01-01")]
duniv[, dec := { r <- frank(score, ties.method="first"); as.integer(ceiling(10*r/.N)) }, by="Date"]
dec_act <- duniv[, .(mean_active=mean(active), n=.N), by=c("Date","dec")]
dec_ts  <- dec_act[, .(mean_active=mean(mean_active), t_nw=nw_t(mean_active)), by="dec"][order(dec)]
cat("decile (10=highest score=freshest/highest-footprint inclusion):\n")
print(dec_ts)
# D10-D9 gap
g10 <- dec_act[dec==10, .(Date, a10=mean_active)]
g9  <- dec_act[dec==9,  .(Date, a9=mean_active)]
gap <- merge(g10,g9,by="Date"); gap[, d:=a10-a9]
cat("D10-D9 gap: mean=",round(mean(gap$d),5)," t_nw=",round(nw_t(gap$d),3),"\n")
fwrite(dec_ts, file.path(OUT,"decile_profile.csv"))

# ---------- ERA STABILITY ----------
cat("\n=== ERA STABILITY (best PIT-valid config) ===\n")
era_run <- function(d0,d1){
  sc <- build_scores(S, best$A_lag, best$A_max, best$tau, best$lambda)
  sc <- sc[Date>=as.Date(d0)&Date<=as.Date(d1)]
  r <- returns_dt[Date>=as.Date(d0)&Date<=as.Date(d1)]
  b <- bench_dt[Date>=as.Date(d0)&Date<=as.Date(d1)]
  res <- canonical_screen_bt(sc,r,b,top_n=best$top_n,cost_bps_oneway=15,liq_dt=liq_dt,liq_min=2e8)
  data.table(era=paste0(substr(d0,1,4),"-",substr(d1,1,4)),
             n=res$n_months, pt=round(res$portfolio_alpha_t_nw_lag3,3),
             net_sr=round(res$net_sr,3), turn=round(res$turnover_annual,2))
}
eras <- rbind(era_run("2005-01-01","2014-12-31"), era_run("2015-01-01","2026-06-30"))
print(eras)
fwrite(eras, file.path(OUT,"era_stability.csv"))

# ---------- ORTHOGONALITY (active basis) vs momentum/size/reversal proxies ----------
cat("\n=== ORTHOGONALITY (active-basis corr vs proxy factor canonical sleeves) ===\n")
# Build proxy factors from RAWDATA-derived signals. Simplest: momentum (12-1), size, ST-reversal.
# We need per-month per-ticker proxy scores; use snap-level Close from S? We only have month-end Size.
# Build from raw monthly returns: load mret-like from returns? We have returns_dt = forward; need trailing.
# Reload trailing monthly returns to build momentum.
ds <- arrow::open_dataset(file.path(ROOT,".cache/RAWDATA.parquet"))
suppressMessages(library(dplyr))
rr <- ds %>% select(Date,Ticker,Ret,Size,Close) %>% filter(Date>=as.Date("2003-06-01")) %>% collect() %>% as.data.table()
rr[, ymk := format(Date,"%Y-%m")]
mr <- rr[!is.na(Ret), .(mret=prod(1+Ret)-1, Size=last(Size)), by=.(Ticker,ymk)]
setorder(mr, Ticker, ymk)
mr[, mom12 := frollapply(log(1+mret), 11, sum, align="right"), by=Ticker]   # 12-1 ~ sum of t-12..t-2 ~ approx
mr[, mom := shift(mom12,1L), by=Ticker]                                     # exclude most recent month (12-1)
mr[, strev := -mret]                                                        # short-term reversal = -last month
mr[, sizef := -log(Size)]                                                   # small-cap tilt = -logSize (SMB)
mr[, Date := as.Date(paste0(ymk,"-01"))]
# canonical sleeve active series for each proxy at top_n=25
proxy_active <- function(scorecol){
  sc <- mr[is.finite(get(scorecol)), .(Date,Ticker,score=get(scorecol))]
  sc <- sc[Date>=as.Date("2005-01-01")]
  res <- canonical_screen_bt(sc, returns_dt, bench_dt, top_n=25L, cost_bps_oneway=15, liq_dt=liq_dt, liq_min=2e8)
  res$benchmark_compare  # not the series; need net active series
}
# Instead extract net active series directly via a helper replicating canonical EW
active_series <- function(scoredt){
  sc <- as.data.table(scoredt); setkey(sc, NULL)
  sc <- sc[Date>=as.Date("2005-01-01")]
  setorder(sc, Date, -score)
  W <- sc[, { n<-min(25,.N); .(Ticker=Ticker[seq_len(n)], w=1/n) }, by="Date"]
  W <- merge(W, liq_dt[,.(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
  W <- W[is.na(adv) | adv>=2e8]
  WR <- merge(W, returns_dt, by=c("Date","Ticker"), all.x=TRUE)
  WR[is.na(Ret_1m), Ret_1m:=0]
  p <- WR[, .(pg=sum(w*Ret_1m)), by="Date"]
  p <- merge(p, bench_dt, by="Date")
  p[, active := pg - BM_Ret]
  p[, .(Date, active)]
}
mine <- active_series(build_scores(S, best$A_lag, best$A_max, best$tau, best$lambda))
mom_s  <- active_series(mr[is.finite(mom),  .(Date,Ticker,score=mom)])
size_s <- active_series(mr[is.finite(sizef),.(Date,Ticker,score=sizef)])
rev_s  <- active_series(mr[is.finite(strev),.(Date,Ticker,score=strev)])
corr_with <- function(other){ m<-merge(mine,other,by="Date"); cor(m$active.x, m$active.y) }
cat("corr_active vs momentum(12-1):", round(corr_with(mom_s),3)," (target<0.35)\n")
cat("corr_active vs size(SMB=-logSize):", round(corr_with(size_s),3)," (target<0.30)\n")
cat("corr_active vs ST-reversal(-1M):", round(corr_with(rev_s),3)," (target<0.30)\n")
ortho <- data.table(factor=c("momentum_12_1","size_SMB","st_reversal"),
                    corr_active=c(corr_with(mom_s),corr_with(size_s),corr_with(rev_s)),
                    target=c(0.35,0.30,0.30))
ortho[, pass := abs(corr_active)<target]
fwrite(ortho, file.path(OUT,"orthogonality.csv"))
print(ortho)

saveRDS(list(ages=ages, dec_ts=dec_ts, gap=gap, eras=eras, ortho=ortho, brd=brd, mine=mine),
        file.path(OUT,"analysis.rds"))
cat("\nDONE analyze.R\n")
