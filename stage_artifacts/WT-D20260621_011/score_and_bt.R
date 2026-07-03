# WT-D20260621_011 — C29  (STEP 4-11: score, IS grid, decile, ortho, holdout)
suppressMessages({library(arrow); library(data.table)})
arrow::set_cpu_count(1L); setDTthreads(1L)
options(stringsAsFactors=FALSE); set.seed(20260621)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT-D20260621_011")
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
I <- readRDS(file.path(OUT,"intermediate.rds"))
incl_events <- I$incl_events; member_m <- I$member_m; snap <- I$snap
gidx <- I$gidx; returns_dt_all <- I$returns_dt_all; bm_m <- I$bm_m

# ---------- STEP 4: score construction ----------
# For each (ticker, month g) compute age = g - g_incl(most recent inclusion <= g).
# Build a long table of (Ticker, g, ymk) for eligible months: ticker is a member that month.
mem_g <- merge(member_m[,.(Ticker, ymk)], gidx, by="ymk")   # member months with g
# most recent inclusion g per (ticker, current g): join all inclusions <= current g, take max g_incl
ie <- incl_events[, .(Ticker, g_incl)]
setkey(ie, Ticker, g_incl)
# for each member-month, find max g_incl <= g
mem_g <- merge(mem_g, ie, by="Ticker", allow.cartesian=TRUE)
mem_g <- mem_g[g_incl <= g]
recent <- mem_g[, .(g_incl=max(g_incl)), by=.(Ticker, ymk, g)]
recent[, age := g - g_incl]                # age in months since most recent inclusion
cat("recent (ticker-month with a prior inclusion) rows:", nrow(recent), "\n")
cat("age distribution:\n"); print(recent[, .N, by=age][order(age)][1:15])

# attach Size, adv21, eligibility flags from snap (same ymk)
S <- merge(recent, snap[,.(Ticker, ymk, Size, adv21, AdminStock, TradingHalt, UnfaithfulDisc, Sector,
                            K200, KQ150, Close)], by=c("Ticker","ymk"))
S <- S[!is.na(Size) & Size>0]
# eligibility: in K200 or KQ150 this month, not admin/halt/unfaithful
S[, elig_flags := (is.na(AdminStock)|AdminStock==0) & (is.na(TradingHalt)|TradingHalt==0) &
                  (is.na(UnfaithfulDisc)|UnfaithfulDisc==0)]
S[, in_univ := (!is.na(K200)&K200==1)|(!is.na(KQ150)&KQ150==1)]

# footprint: w_idx = Size / sum(Size over members this month); impact = w_idx / adv21; z = xs log z-score
S[, sumSize := sum(Size, na.rm=TRUE), by=ymk]
S[, w_idx := Size / sumSize]
S[, impact := w_idx / pmax(adv21, 1)]
S[, lz := log(impact)]
S[, footprint := (lz - mean(lz, na.rm=TRUE)) / sd(lz, na.rm=TRUE), by=ymk]
S[is.na(footprint), footprint := 0]

# liquidity table (t-1 adv = adv21 at sig month-end, which is realized through sig date)
liq_dt <- S[, .(Date=as.Date(paste0(ymk,"-01")), Ticker, adv=adv21)]

# score function for given config
build_scores <- function(S, A_lag, A_max, tau, lambda){
  d <- S[age >= A_lag & age <= A_max & elig_flags & in_univ]
  d[, decay := exp(-age/tau)]
  d[, score := decay * (1 + lambda*footprint)]
  d[, .(Date=as.Date(paste0(ymk,"-01")), Ticker, score)]
}

# returns / bench in canonical date form (Date = first-of-month key matching score Date)
returns_dt <- returns_dt_all[, .(Date=as.Date(paste0(ymk,"-01")), Ticker, Ret_1m)]
bench_dt   <- bm_m[, .(Date=as.Date(paste0(ymk,"-01")), BM_Ret)]
liq_dt[, Date := as.Date(paste0(format(Date,"%Y-%m"),"-01"))]

run_cfg <- function(A_lag, A_max, tau, lambda, top_n, dmin, dmax){
  sc <- build_scores(S, A_lag, A_max, tau, lambda)
  sc <- sc[Date>=as.Date(dmin) & Date<=as.Date(dmax)]
  r  <- returns_dt[Date>=as.Date(dmin) & Date<=as.Date(dmax)]
  b  <- bench_dt[Date>=as.Date(dmin) & Date<=as.Date(dmax)]
  res <- tryCatch(canonical_screen_bt(sc, r, b, top_n=top_n, cost_bps_oneway=15,
                                      liq_dt=liq_dt, liq_min=2e8),
                  error=function(e) list(portfolio_alpha_t_nw_lag3=NA_real_, note=conditionMessage(e)))
  res
}

# ---------- STEP 7: IS grid (2005-2016, K200 era main) ----------
cat("\n=== STEP 7: IS grid 2005-2016 ===\n")
IS_min <- "2005-01-01"; IS_max <- "2016-12-31"
grid <- CJ(A_lag=c(0L,1L), A_max=c(3L,6L,9L,12L), tau=c(2,4,6), lambda=c(0,0.5,1.0), top_n=c(20L,25L))
gres <- vector("list", nrow(grid))
for(i in seq_len(nrow(grid))){
  g <- grid[i]
  r <- run_cfg(g$A_lag, g$A_max, g$tau, g$lambda, g$top_n, IS_min, IS_max)
  gres[[i]] <- data.table(A_lag=g$A_lag, A_max=g$A_max, tau=g$tau, lambda=g$lambda, top_n=g$top_n,
                          n_months=r$n_months %||% NA, pt=r$portfolio_alpha_t_nw_lag3 %||% NA,
                          net_sr=r$net_sr %||% NA, IR=r$information_ratio %||% NA,
                          turn=r$turnover_annual %||% NA)
}
gridR <- rbindlist(gres, fill=TRUE)
# PIT-valid subset = A_lag>=1 only
gridR_valid <- gridR[A_lag==1L]
setorder(gridR_valid, -pt)
cat("--- IS grid, PIT-valid (A_lag=1), top by pt ---\n")
print(head(gridR_valid, 10))
cat("\n--- IS grid, A_lag=0 (PIT-borderline, sensitivity only) top by pt ---\n")
print(head(gridR[A_lag==0L][order(-pt)], 6))
fwrite(gridR, file.path(OUT,"is_grid.csv"))

# select best PIT-valid IS config (max pt among A_lag=1)
best <- gridR_valid[which.max(pt)]
cat("\n*** BEST PIT-VALID IS CONFIG:\n"); print(best)
saveRDS(list(S=S, returns_dt=returns_dt, bench_dt=bench_dt, liq_dt=liq_dt,
             build_scores=build_scores, run_cfg=run_cfg, best=best, gridR=gridR),
        file.path(OUT,"scored.rds"))
cat("\nSaved scored.rds\n")
