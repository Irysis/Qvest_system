# Independent adversarial re-measurement of drawdown-episode defense
# PIT: factor Z at t-1 selects, fwd_ret_1m is next-month realized (already forward in panel).
# Episode labels are ex-post market NAV (diagnostic conditional crisis-alpha, AX-001 v2).
suppressWarnings(suppressMessages({
  library(data.table); library(arrow)
}))
setDTthreads(1); arrow::set_io_thread_count(1)

root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
dd   <- file.path(root, "stage_artifacts/pg2_defense_drawdown")

# --- candidates + direction ---
master <- fread(file.path(root,"stage_artifacts/pg2_defense_survey/defense_survey_master.csv"), encoding="UTF-8")
cand   <- fread(file.path(root,"stage_artifacts/pg2_defense_survey/step1_defense_candidates.csv"), encoding="UTF-8")
dir_map <- setNames(master$direction, master$code)
codes   <- cand$code

# --- panel load (col_select, single thread) ---
pf   <- file.path(root, ".cache/discovery/explore_panel.parquet")
sch  <- names(read_parquet(pf, as_data_frame=FALSE)$schema)
use_codes <- intersect(codes, sch)
sel  <- c("ym","Ticker","fwd_ret_1m", use_codes)
dt   <- as.data.table(read_parquet(pf, col_select = sel))
cat("panel rows", nrow(dt), "cols", ncol(dt), "candidates used", length(use_codes), "\n")

# --- market_fwd + episodes ---
mkt <- fread(file.path(dd,"market_fwd.csv"))
epi <- fread(file.path(dd,"episodes.csv"))
mkt[, ym := as.character(ym)]
dt[,  ym := as.character(ym)]

# ============ (5-bug) beta-alignment check ============
# EW-all-universe fwd_ret per ym, regress on market_fwd[ym]. beta~1 => aligned.
ewall <- dt[!is.na(fwd_ret_1m), .(ew_fwd = mean(fwd_ret_1m)), by=ym]
chk   <- merge(ewall, mkt[,.(ym, market_fwd)], by="ym")
b_lag0 <- coef(lm(ew_fwd ~ market_fwd, data=chk))[2]
# also test off-by-one (market shifted +1 / -1) to confirm no offset bug
setorder(chk, ym)
chk[, mkt_lag1 := shift(market_fwd, 1)]   # market one month earlier
chk[, mkt_ld1  := shift(market_fwd, -1)]  # market one month later
b_lag1 <- tryCatch(coef(lm(ew_fwd ~ mkt_lag1, data=chk[!is.na(mkt_lag1)]))[2], error=function(e) NA)
b_ld1  <- tryCatch(coef(lm(ew_fwd ~ mkt_ld1 , data=chk[!is.na(mkt_ld1)]))[2],  error=function(e) NA)
cat(sprintf("BETA-CHECK  lag0(aligned)=%.3f  mkt_lag1=%.3f  mkt_lead1=%.3f  (n=%d)\n",
            b_lag0, b_lag1, b_ld1, nrow(chk)))

# ============ episode membership per ym ============
# episodes.csv gives peak_ym..trough_ym; membership = months from (peak+1) .. trough
ymseq <- function(a,b){ # a,b "YYYY-MM"
  ai <- as.integer(substr(a,1,4))*12 + as.integer(substr(a,6,7))
  bi <- as.integer(substr(b,1,4))*12 + as.integer(substr(b,6,7))
  sapply(ai:bi, function(x){ y<-(x-1)%/%12; m<-(x-1)%%12+1; sprintf("%04d-%02d",y,m)})
}
ep_months <- lapply(seq_len(nrow(epi)), function(i){
  # active window = peak+1 .. trough (the decline itself)
  pk <- epi$peak_ym[i]; tr <- epi$trough_ym[i]
  all_m <- ymseq(pk, tr)
  all_m[-1] # drop peak month, keep decline months
})
names(ep_months) <- epi$name

# ============ portfolio builder ============
# orient factor, top-N EW, active vs market_fwd same ym
build_active_by_ym <- function(code, topn=25){
  d <- dt[!is.na(get(code)) & !is.na(fwd_ret_1m), .(ym, Ticker, z=get(code), r=fwd_ret_1m)]
  sgn <- if (identical(dir_map[[code]], "lower_better")) -1 else 1
  d[, z := z*sgn]
  # top-N per ym
  d <- d[order(ym, -z)]
  port <- d[, .(port_ret = mean(head(r, topn))), by=ym]
  m <- merge(port, mkt[,.(ym,market_fwd)], by="ym")
  m[, active := port_ret - market_fwd]
  m[]
}
build_active_quintile <- function(code){
  d <- dt[!is.na(get(code)) & !is.na(fwd_ret_1m), .(ym, Ticker, z=get(code), r=fwd_ret_1m)]
  sgn <- if (identical(dir_map[[code]], "lower_better")) -1 else 1
  d[, z := z*sgn]
  d <- d[order(ym, -z)]
  port <- d[, {n<-.N; k<-max(1,floor(n/5)); .(port_ret=mean(head(r,k)))}, by=ym]
  m <- merge(port, mkt[,.(ym,market_fwd)], by="ym")
  m[, active := port_ret - market_fwd]
  m[]
}

# episode aggregation: per episode, mean active over its months (arithmetic mean of monthly active)
episode_stats <- function(actdt){
  setkey(actdt, ym)
  ep_vals <- sapply(ep_months, function(ms){
    v <- actdt[ym %in% ms, active]
    if(length(v)==0) NA_real_ else mean(v)  # mean monthly active within episode
  })
  ep_vals <- ep_vals[!is.na(ep_vals)]
  list(median=median(ep_vals), mean=mean(ep_vals),
       hit=mean(ep_vals>0), worst=min(ep_vals), n=length(ep_vals),
       vals=ep_vals)
}

# ============ run all candidates (top-25) ============
res <- rbindlist(lapply(use_codes, function(c){
  a <- build_active_by_ym(c, 25)
  s <- episode_stats(a)
  data.table(code=c, defclass=cand$defclass[cand$code==c][1],
             median_active=s$median, mean_active=s$mean, hit=s$hit, worst=s$worst, n=s$n)
}))
setorder(res, -median_active)
res[, rank := .I]
fwrite(res, file.path(dd,"verify_remeasure_top25.csv"))
cat("\n=== TOP 15 (independent top-25) ===\n")
print(res[1:15])

# book-3 positions
cat("\n=== BOOK-3 ranks ===\n")
print(res[code %in% c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O")])

# ============ top-quintile robustness on top10 ============
top10 <- res$code[1:10]
resq <- rbindlist(lapply(top10, function(c){
  s <- episode_stats(build_active_quintile(c))
  data.table(code=c, median_active_Q=s$median, hit_Q=s$hit)
}))
cat("\n=== TOP-QUINTILE variant for top10 (top-25) ===\n")
print(resq)

# ============ cash comparison: absolute episode return of best factors ============
# absolute = port_ret (not active). Is any positive during deep episodes?
cat("\n=== ABSOLUTE episode return (port_ret) for top5 + deep episodes ===\n")
deep <- c("GFC_2008_2009-01","Bear_2021_22","Q4_2018","COVID_2020","DD_2026-02")
for(c in res$code[1:5]){
  a <- build_active_by_ym(c,25); setkey(a,ym)
  absv <- sapply(ep_months[deep], function(ms){ v<-a[ym%in%ms,port_ret]; if(length(v)) mean(v) else NA})
  cat(sprintf("%-22s ", c)); cat(sprintf("%s=%.3f ", deep, absv)); cat("\n")
}

# market absolute in those episodes for reference
cat("\n=== MARKET absolute (market_fwd) same episodes ===\n")
mk <- setNames(mkt$market_fwd, mkt$ym)
for(e in deep){ ms<-ep_months[[e]]; cat(sprintf("%-20s mkt_mean=%.3f\n", e, mean(mk[ms], na.rm=TRUE))) }

# ============ threshold sensitivity: named-crisis-only (deep>=20%) vs all ============
deep_eps <- epi$name[abs(epi$depth_pct) >= 20]  # >=20% drawdowns
shallow_eps <- epi$name[abs(epi$depth_pct) < 20]
cat("\n=== THRESHOLD: deep(>=20%) episodes:", paste(deep_eps,collapse=","), "\n")
sens <- rbindlist(lapply(res$code[1:12], function(c){
  a <- build_active_by_ym(c,25); setkey(a,ym)
  dv <- sapply(ep_months[deep_eps], function(ms){v<-a[ym%in%ms,active];if(length(v))mean(v) else NA})
  dv <- dv[!is.na(dv)]
  data.table(code=c, median_deep=median(dv), hit_deep=mean(dv>0), n_deep=length(dv))
}))
print(sens)

cat("\nDONE\n")
