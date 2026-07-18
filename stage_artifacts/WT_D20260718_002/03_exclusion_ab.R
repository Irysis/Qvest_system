# WT-D20260718_002 — EXCLUSION overlay paired A/B (core measurement)
# A (base)      : mom_12_1 top-25 EW long-only, 2e8 liq (production frame)
# B (treatment) : same base with insider net-SELLER tickers removed from universe pre-selection
# Paired stat   : monthly active(B) - active(A), NW lag-3 t. Isolates exclusion effect.
# Reg: PRIMARY pre-registered = {scope=officer, L=6, P=10% percentile}. Sweep = robustness.
suppressWarnings(suppressMessages({library(arrow); library(data.table); library(jsonlite)}))
setDTthreads(1)
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||is.na(a)) b else a
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT <- file.path(R, "stage_artifacts/WT_D20260718_002")
source(file.path(R, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(R, "02_Infrastructure/validation/overlay_pit_guard.R"))
# NW t helper from contract
if (!exists(".nw_t_mean", mode="function")) source(file.path(R,"02_Infrastructure/contracts/backtest_result_contract.R"))

base <- as.data.table(arrow::read_parquet(file.path(OUT,"base_panel.parquet")))
bench<- as.data.table(arrow::read_parquet(file.path(OUT,"bench_panel.parquet")))
ins  <- as.data.table(arrow::read_parquet(file.path(OUT,"insider_sell_panel.parquet")))

returns_dt <- base[, .(Date, Ticker, Ret_1m)]
bench_dt   <- bench[, .(Date, BM_Ret)]
liq_dt     <- base[, .(Date, Ticker, adv)]
size_dt    <- base[, .(Date, Ticker, Size)]

# join insider cnv to base by (ym,Ticker); missing => 0 (no insider activity = never excluded)
B <- merge(base, ins[, .(ym, Ticker, cnv_off_3,cnv_off_6,cnv_off_12,cnv_all_3,cnv_all_6,cnv_all_12)],
           by=c("ym","Ticker"), all.x=TRUE)
cnvc <- grep("^cnv_", names(B), value=TRUE)
for (c0 in cnvc) B[is.na(get(c0)), (c0):=0]

# sell_intensity_{sc,L} = -cnv/Size  (positive = net selling rel to mcap)
for (sc in c("off","all")) for (L in c(3,6,12)) {
  si <- paste0("si_",sc,"_",L); cv <- paste0("cnv_",sc,"_",L)
  B[, (si) := -get(cv)/Size]
}

# exclusion set builder: exclude in_univ tickers whose sell_intensity>0 AND in top-P% of universe cross-section that month
excl_tickers <- function(dt, si_col, P) {
  # dt: rows for one universe (already in_univ). returns data.table(Date,Ticker) excluded
  x <- dt[, .(Date, Ticker, si = get(si_col))]
  x[, n := .N, by=Date]
  x[, rk := frank(-si, ties.method="min"), by=Date]   # rank 1 = largest seller
  x[, thr := pmax(1L, ceiling(P/100 * n))]
  x[si > 0 & rk <= thr, .(Date, Ticker)]
}

run_arm <- function(scores_dt, rid) {
  canonical_screen_bt(scores_dt, returns_dt, bench_dt, top_n=25L, cost_bps_oneway=15,
                      liq_dt=liq_dt, liq_min=2e8, run_id=rid, strategy_id=rid,
                      periods_per_year=12L, diag_dual_basis=TRUE, size_dt=size_dt)
}

# ---- A (base) : computed once ----
base_scores <- base[, .(Date, Ticker, score=mom_score)]
A <- run_arm(base_scores, "base")
pa <- as.data.table(A$period_returns)[, .(date, ret_net_A=ret_net, bench=benchmark_ret)]
cat(sprintf("[A base] PORT_t(cap-w)=%.3f  net_sr=%.3f  n=%d  turnover=%.2f\n",
            A$portfolio_alpha_t_nw_lag3, A$net_sr, A$n_months, A$turnover_annual))

# ---- paired runner for a treatment spec ----
paired_stat <- function(si_col, P, tag, ex_override=NULL) {
  ex <- if (!is.null(ex_override)) ex_override else excl_tickers(B[in_univ==1L], si_col, P)
  keep <- fsetdiff(base_scores[, .(Date,Ticker)], ex)
  scores_excl <- merge(keep, base_scores, by=c("Date","Ticker"))
  Bt <- run_arm(scores_excl, paste0("excl_",tag))
  pb <- as.data.table(Bt$period_returns)[, .(date, ret_net_B=ret_net)]
  m <- merge(pa, pb, by="date")
  m[, act_A := ret_net_A - bench]
  m[, act_B := ret_net_B - bench]
  m[, diff  := act_B - act_A]
  # exclusion incidence
  exn <- ex[, .N, by=Date]; avg_excl <- if(nrow(exn)) mean(exn$N) else 0
  list(tag=tag, si_col=si_col, P=P,
       port_t_B = Bt$portfolio_alpha_t_nw_lag3, net_sr_B = Bt$net_sr,
       n_months = nrow(m),
       paired_diff_mean_ann = mean(m$diff)*12,
       paired_t_nw3 = .nw_t_mean(m$diff, lag=3),
       diff_series = m,
       Bt = Bt, ex = ex, avg_excl_per_month = avg_excl)
}

# ================= PRIMARY (pre-registered) =================
cat("\n=== PRIMARY: scope=officer L=6 P=10% ===\n")
prim <- paired_stat("si_off_6", 10, "primary_off6_p10")
cat(sprintf("[B primary] PORT_t(cap-w)=%.3f (A=%.3f)  paired_diff_ann=%.4f  paired_t_nw3=%.3f  avg_excl/mo=%.1f  n=%d\n",
            prim$port_t_B, A$portfolio_alpha_t_nw_lag3, prim$paired_diff_mean_ann, prim$paired_t_nw3,
            prim$avg_excl_per_month, prim$n_months))

# PIT assert: exclusion signal cutoff = formation month-end < holding month(t+1) start
# our signal uses rcept_dt month <= formation month t; holding = t+1. Build cutoffs to assert.
form_dates <- sort(unique(base$Date))
ym_of <- base[, .(Date, ym)][!duplicated(Date)]
hold_start <- as.Date(paste0(substr(ym_of$ym,1,7),"-01"))  # first day of formation month
# holding month starts one month AFTER formation month-end; signal cutoff = formation month-end
# used_cutoff (latest filing month used) = formation month-end date; holding_start = first day of NEXT month
nextm_first <- function(ym){ y<-as.integer(substr(ym,1,4)); m<-as.integer(substr(ym,6,7))+1L
  y<-y+(m-1L)%/%12L; m<-((m-1L)%%12L)+1L; as.Date(sprintf("%04d-%02d-01",y,m)) }
holdstart <- sapply(ym_of$ym, nextm_first); holdstart <- as.Date(holdstart, origin="1970-01-01")
assert_overlay_pit(ym_of$Date, holdstart, label="insider_exclusion")  # formation date < holding start
cat("[PIT] assert_overlay_pit PASS (formation month-end < holding month start)\n")

# ================= LAG1 STRESS (primary) =================
# shift insider signal +1 month (use signal as-of t-1 for holding t+1). Genuine lag => graceful, not collapse.
# look-ahead would show current >> lag1. Build lagged exclusion by shifting ins ym +1.
ins_lag <- copy(ins)
ins_lag[, midx := as.integer(substr(ym,1,4))*12L + as.integer(substr(ym,6,7)) + 1L]  # push to next month
ins_lag[, y := (midx-1L)%/%12L]; ins_lag[, mo := ((midx-1L)%%12L)+1L]; ins_lag[, ym := sprintf("%04d-%02d", y, mo)]
Blag <- merge(base, ins_lag[, .(ym,Ticker,cnv_off_6)], by=c("ym","Ticker"), all.x=TRUE)
Blag[is.na(cnv_off_6), cnv_off_6:=0]; Blag[, si_off_6 := -cnv_off_6/Size]
ex_lag <- excl_tickers(Blag[in_univ==1L], "si_off_6", 10)
lag1 <- paired_stat(NULL, 10, "lag1_off6_p10", ex_override=ex_lag)
cat(sprintf("[LAG1] paired_diff_ann=%.4f  paired_t_nw3=%.3f  (primary was diff=%.4f t=%.3f)\n",
            lag1$paired_diff_mean_ann, lag1$paired_t_nw3, prim$paired_diff_mean_ann, prim$paired_t_nw3))
ab <- overlay_lookahead_ab(prim$paired_diff_mean_ann, lag1$paired_diff_mean_ann,
                           "paired_diff_ann", rel_tol=0.05, higher_is_better=TRUE)
cat(ab$message, "\n")

# ================= DUAL-BASIS: excluded-ticker size localization =================
# are excluded names small-cap? rank excluded tickers' size within universe each month.
exd <- prim$ex
exd_sz <- merge(exd, size_dt, by=c("Date","Ticker"))
uni_sz <- size_dt[base[in_univ==1L], on=c("Date","Ticker"), nomatch=0]
uni_sz[, sz_rk := frank(-Size, ties.method="min"), by=Date]  # 1=largest
uni_sz[, n := .N, by=Date]; uni_sz[, sz_pct := sz_rk/n]      # 0=largest, 1=smallest
exd2 <- merge(exd, uni_sz[, .(Date,Ticker,sz_pct,sz_rk,n)], by=c("Date","Ticker"))
cat(sprintf("[DUAL-BASIS] excluded tickers median size-pct(0=big,1=small)=%.3f  mean=%.3f  (n_excl_obs=%d)\n",
            median(exd2$sz_pct), mean(exd2$sz_pct), nrow(exd2)))
# fraction of excluded that are MEGA(top10)/MID(11-30)/OTHER
exd2[, tier := fifelse(sz_rk<=10,"MEGA", fifelse(sz_rk<=30,"MID","OTHER"))]
cat("   excluded tier mix:", paste(names(table(exd2$tier)), table(exd2$tier), sep="=", collapse=" "), "\n")

# primary EW-uni & cap-tier diag from arm B
euw <- prim$Bt$diag_ew_universe
cat(sprintf("[EW-uni B] PORT_t=%.3f  post2017_t=%.3f  oos_approx=%.3f\n",
            euw$portfolio_alpha_t_nw_lag3 %||% NA, euw$post2017_t_nw_lag3 %||% NA,
            euw$oos_retention_approx %||% NA))

# ================= SWEEP (robustness) =================
cat("\n=== SWEEP grid (robustness; DSR-relevant) ===\n")
grid <- CJ(sc=c("off","all"), L=c(3,6,12), P=c(5,10,20))
sw <- rbindlist(lapply(seq_len(nrow(grid)), function(i){
  sc<-grid$sc[i]; L<-grid$L[i]; Pp<-grid$P[i]
  r <- paired_stat(paste0("si_",sc,"_",L), Pp, sprintf("%s_L%d_P%d",sc,L,Pp))
  data.table(scope=sc, L=L, P=Pp, port_t_B=r$port_t_B, port_t_A=A$portfolio_alpha_t_nw_lag3,
             paired_diff_ann=r$paired_diff_mean_ann, paired_t_nw3=r$paired_t_nw3,
             avg_excl=r$avg_excl_per_month, n=r$n_months)
}))
print(sw[order(-paired_t_nw3)])

# IS/OOS split of primary paired diff (IS<=2016, OOS>=2017)
md <- prim$diff_series
md[, era := ifelse(date < as.Date("2017-01-01"),"IS","OOS")]
is_t  <- .nw_t_mean(md[era=="IS", diff], lag=3);  is_m  <- mean(md[era=="IS", diff])*12
oos_t <- .nw_t_mean(md[era=="OOS",diff], lag=3);  oos_m <- mean(md[era=="OOS",diff])*12
cat(sprintf("\n[IS/OOS primary] IS diff_ann=%.4f t=%.3f (n=%d) | OOS diff_ann=%.4f t=%.3f (n=%d)\n",
            is_m, is_t, md[era=="IS",.N], oos_m, oos_t, md[era=="OOS",.N]))

# ================= AX-001 v2: crisis-period paired diff =================
md[, yr := as.integer(substr(date,1,4))]
crisis_yrs <- c(2008, 2011, 2020, 2022)
cr <- md[yr %in% crisis_yrs]; nc <- md[!(yr %in% crisis_yrs)]
cat(sprintf("[AX-001 v2] crisis(%s) diff_ann=%.4f (n=%d) | normal diff_ann=%.4f (n=%d) | ratio=%.2f\n",
            paste(crisis_yrs,collapse=","), mean(cr$diff)*12, nrow(cr),
            mean(nc$diff)*12, nrow(nc), (mean(cr$diff)/ (mean(nc$diff)+1e-12))))

# ---- persist results ----
res <- list(
  pin_tag="wt002_20260718_214215",
  A = list(port_t_capw=A$portfolio_alpha_t_nw_lag3, net_sr=A$net_sr, calmar=NA,
           turnover=A$turnover_annual, n_months=A$n_months,
           ew_uni_port_t = A$diag_ew_universe$portfolio_alpha_t_nw_lag3),
  primary = list(spec="officer_L6_P10", port_t_capw_B=prim$port_t_B, net_sr_B=prim$net_sr_B,
                 paired_diff_ann=prim$paired_diff_mean_ann, paired_t_nw3=prim$paired_t_nw3,
                 avg_excl_per_month=prim$avg_excl_per_month, n_months=prim$n_months,
                 ew_uni_B_port_t = euw$portfolio_alpha_t_nw_lag3,
                 ew_uni_B_post2017_t = euw$post2017_t_nw_lag3),
  lag1 = list(paired_diff_ann=lag1$paired_diff_mean_ann, paired_t_nw3=lag1$paired_t_nw3,
              inflation=ab$inflation, lookahead_suspected=ab$lookahead_suspected),
  dual_basis = list(excl_median_size_pct=median(exd2$sz_pct), excl_mean_size_pct=mean(exd2$sz_pct),
                    excl_tier_mix=as.list(table(exd2$tier)), n_excl_obs=nrow(exd2)),
  is_oos = list(is_diff_ann=is_m, is_t=is_t, oos_diff_ann=oos_m, oos_t=oos_t),
  ax001v2 = list(crisis_diff_ann=mean(cr$diff)*12, normal_diff_ann=mean(nc$diff)*12),
  sweep = sw
)
write_json(res, file.path(OUT,"exclusion_ab_results.json"), pretty=TRUE, auto_unbox=TRUE, digits=6, na="null")
# also save diff series + sweep parquet
arrow::write_parquet(prim$diff_series, file.path(OUT,"primary_diff_series.parquet"))
arrow::write_parquet(sw, file.path(OUT,"sweep_results.parquet"))
cat("\n[DONE] results -> exclusion_ab_results.json\n")
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||is.na(a)) b else a
