# WT-D20260822_005 · confirm phase: redundancy(④) + selected combo full/clean/OOS + dual-basis(②) + KQ150(③) + regime arm(⑤)
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT = root)
`%||%` <- function(a,b) if (is.null(a) || length(a)==0 || (length(a)==1 && is.na(a))) b else a
source(file.path(root, "02_Infrastructure/config.R"))
source(file.path(root, "02_Infrastructure/factor_db/factor_db_connector.R"))
source(file.path(root, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(root, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(root, "02_Infrastructure/ramp/factor_validation.R"))
scratch <- file.path(root, "qepm/mailbox/worktask/WT-D20260822_005/scratch")
stage   <- file.path(root, "stage_artifacts/WT-D20260822_005")

# ── 재사용: 패널 재구성 (run_ablation 과 동일 규약) ──────────────────────────
raw <- as.data.table(read_parquet(RAWDATA_CACHE,
        col_select = c("Date","Ticker","K200","KQ150","Close","Vol","Size")))
raw[, Date := as.Date(Date)]
udates <- sort(unique(raw$Date))
me <- data.table(Date = udates)[, ym := format(Date, "%Y-%m")][, .(Date = max(Date)), by = ym]
sig_dates <- sort(me$Date); sig_dates <- sig_dates[sig_dates >= as.Date("2004-12-01") & sig_dates <= as.Date("2026-07-31")]
bmf <- build_monthly_forward_returns(raw, sig_dates, liq_daily = NULL)
returns_dt <- bmf$returns_dt; liq_dt <- bmf$liq_dt

bmc <- as.data.table(read_parquet(BM_CACHE)); bmc[, Date := as.Date(Date)]
asof_bmclose <- function(d) { s <- bmc[Date <= d]; if (!nrow(s)) return(NA_real_); s[Date == max(Date), BM_Close][1] }
bl <- list()
for (i in seq_len(length(sig_dates) - 1L)) {
  d0 <- sig_dates[i]; d1 <- sig_dates[i+1L]; c0 <- asof_bmclose(d0); c1 <- asof_bmclose(d1)
  if (is.na(c0) || is.na(c1) || c0 <= 0) next
  bl[[length(bl)+1L]] <- data.table(Date = d0, BM_Ret = c1/c0 - 1)
}
bench_dt <- rbindlist(bl)

FAC <- c("M08_Residual_Mom","M07_IndMom","M01_Mom_12_1","Q01_GPA","C03_EPS_Chg_3m")
uni_keys <- unique(raw[(K200==TRUE|KQ150==TRUE), .(Date, Ticker)])
load_scores <- function(sig_date) {
  fm <- tryCatch(load_month_factors(sig_date, factor_names = FAC, coverage_min = 0.03), error=function(e) NULL)
  if (is.null(fm) || !nrow(fm)) return(NULL)
  w <- dcast(fm, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned",
             fun.aggregate = function(x) mean(x, na.rm=TRUE)); w[, Date := as.Date(sig_date)]; w
}
score_panel <- rbindlist(lapply(sig_dates, load_scores), fill = TRUE)
score_panel <- merge(score_panel, uni_keys, by = c("Date","Ticker"))
size_panel <- unique(raw[(K200==TRUE|KQ150==TRUE), .(Date, Ticker, Size)])

# ── ④ redundancy: M08 vs M01 횡단면 상관 (월별 pooled) ───────────────────────
cat("\n[④] M08 vs M01 redundancy (횡단면 Z 상관)\n")
red <- score_panel[!is.na(M08_Residual_Mom) & !is.na(M01_Mom_12_1)]
cor_m08_m01 <- red[, .(cc = cor(M08_Residual_Mom, M01_Mom_12_1)), by = Date][, mean(cc, na.rm=TRUE)]
cor_m08_m07 <- score_panel[!is.na(M08_Residual_Mom)&!is.na(M07_IndMom)][, .(cc=cor(M08_Residual_Mom,M07_IndMom)), by=Date][, mean(cc,na.rm=TRUE)]
cor_m08_q01 <- score_panel[!is.na(M08_Residual_Mom)&!is.na(Q01_GPA)][, .(cc=cor(M08_Residual_Mom,Q01_GPA)), by=Date][, mean(cc,na.rm=TRUE)]
cat(sprintf("  mean xsec cor: M08~M01=%.3f  M08~M07=%.3f  M08~Q01=%.3f\n", cor_m08_m01, cor_m08_m07, cor_m08_q01))

build_combo_scores <- function(cols) {
  present <- intersect(cols, names(score_panel)); if (!length(present)) return(NULL)
  M <- as.matrix(score_panel[, ..present]); s <- rowMeans(M, na.rm=TRUE); n_ok <- rowSums(!is.na(M))
  dt <- data.table(Date=score_panel$Date, Ticker=score_panel$Ticker, score=s, n_ok=n_ok)
  dt[n_ok>=1 & is.finite(score), .(Date, Ticker, score)]
}
measure_combo <- function(label, cols, dfrom, dto, top_n=25L, diag=TRUE) {
  sc <- build_combo_scores(cols); if (is.null(sc)) return(list(error="no scores"))
  sc <- sc[Date>=as.Date(dfrom)&Date<=as.Date(dto)]
  rr <- returns_dt[Date>=as.Date(dfrom)&Date<=as.Date(dto)]
  bb <- bench_dt[Date>=as.Date(dfrom)&Date<=as.Date(dto)]
  ll <- liq_dt[Date>=as.Date(dfrom)&Date<=as.Date(dto)]
  data.table::setattr(ll,"liq_ruler",attr(liq_dt,"liq_ruler",exact=TRUE))
  data.table::setattr(ll,"liq_ruler_source",attr(liq_dt,"liq_ruler_source",exact=TRUE))
  ss <- size_panel[Date>=as.Date(dfrom)&Date<=as.Date(dto)]
  tryCatch(canonical_screen_bt(sc, rr, bb, top_n=top_n, cost_bps_oneway=15, liq_dt=ll, liq_min=2e8,
     run_id=paste0("WT005_",label), strategy_id=label, periods_per_year=12L,
     diag_dual_basis=diag, size_dt=ss), error=function(e) list(error=conditionMessage(e)))
}
pick <- function(r) {
  if (!is.null(r$error)) return(list(error=r$error))
  d <- r$diag_ew_universe
  list(n_months=r$n_months, top_n=r$top_n, port_t=r$portfolio_alpha_t_nw_lag3,
    p_value=r$portfolio_alpha_t_pvalue, net_ir=r$information_ratio, alpha_ann=r$alpha_annualized,
    net_sr=r$net_sr, mean_active_net=r$mean_active_net, turnover_ann=r$turnover_annual,
    sel_cov=r$selected_ret_coverage, liq_ruler=r$liq_ruler,
    diag_ew_port_t=if(is.list(d)) d$portfolio_alpha_t_nw_lag3 else NA_real_,
    diag_ew_ir=if(is.list(d)) d$information_ratio else NA_real_,
    diag_ew_post2017_t=if(is.list(d)) d$post2017_t_nw_lag3 else NA_real_,
    diag_ew_oos_approx=if(is.list(d)) d$oos_retention_approx else NA_real_,
    diag_ew_alpha_ann=if(is.list(d)) d$alpha_annualized else NA_real_)
}

# selected combo = B (M08 + Q01 + C03) — 3축 hypothesis form. H(=+M01) 은 redundant 로 배제.
SEL <- c("M08_Residual_Mom","Q01_GPA","C03_EPS_Chg_3m")
IS_TO <- "2018-12-31"; OOS_FROM <- "2019-01-01"; FULL_FROM <- "2004-12-01"; FULL_TO <- "2026-07-31"; CLEAN_FROM <- "2015-07-01"

cat("\n[B selected = M08+Q01+C03] 다중 창 측정\n")
out <- list()
out$full   <- pick(measure_combo("B_full",   SEL, FULL_FROM, FULL_TO))
out$is     <- pick(measure_combo("B_is",     SEL, FULL_FROM, IS_TO))
out$oos    <- pick(measure_combo("B_oos",    SEL, OOS_FROM,  FULL_TO))
out$clean  <- pick(measure_combo("B_clean",  SEL, CLEAN_FROM,FULL_TO))
for (w in names(out)) cat(sprintf("  %-6s port_t=%6.3f net_ir=%6.3f net_sr=%6.3f a_ann=%6.3f TO=%5.0f%% n=%d | EW-diag port_t=%6.3f post2017_t=%6.3f oos~=%5.2f\n",
   w, out[[w]]$port_t%||%NA, out[[w]]$net_ir%||%NA, out[[w]]$net_sr%||%NA, out[[w]]$alpha_ann%||%NA,
   (out[[w]]$turnover_ann%||%NA)*100, out[[w]]$n_months%||%0,
   out[[w]]$diag_ew_port_t%||%NA, out[[w]]$diag_ew_post2017_t%||%NA, out[[w]]$diag_ew_oos_approx%||%NA))

# oos_retention (active-SR OOS/IS) — canonical basis
is_sr  <- out$is$net_sr;  oos_sr <- out$oos$net_sr
oos_retention_capw <- if (is.finite(is_sr) && is_sr>0) oos_sr/is_sr else NA_real_
cat(sprintf("  oos_retention(capw, IS→OOS split 2019) = %.3f  (IS_sr=%.3f OOS_sr=%.3f)\n", oos_retention_capw, is_sr, oos_sr))

# ── 창-도달가능성 상한 (positive control): 완전예지 top-25 (perfect foresight) full window ──
cat("\n[⑥ 창-도달가능성 상한] perfect-foresight top-25 (동일 유니버스·비용·벤치)\n")
pf_scores <- merge(uni_keys, returns_dt[, .(Date, Ticker, fwd = Ret_1m)], by=c("Date","Ticker"))
pf_scores <- pf_scores[Date>=as.Date(FULL_FROM)&Date<=as.Date(FULL_TO), .(Date, Ticker, score = fwd)]
pf <- tryCatch(canonical_screen_bt(pf_scores, returns_dt, bench_dt, top_n=25L, cost_bps_oneway=15,
   liq_dt=liq_dt, liq_min=2e8, run_id="WT005_pf", strategy_id="perfect_foresight",
   periods_per_year=12L, diag_dual_basis=FALSE), error=function(e) list(error=conditionMessage(e)))
pf_pick <- pick(pf)
cat(sprintf("  perfect-foresight top-25: port_t=%.2f net_sr=%.2f alpha_ann=%.3f n=%d\n",
   pf_pick$port_t%||%NA, pf_pick$net_sr%||%NA, pf_pick$alpha_ann%||%NA, pf_pick$n_months%||%0))

# ── ⑤ regime-conditional decay arm (advisory) — Date < holding_start 만, 동월 look-ahead 회피 ──
cat("\n[⑤ regime arm] macro_regime RISK 라벨 (PIT: Date < holding_start)\n")
reg <- tryCatch(as.data.table(read_parquet(file.path(CACHE_DIR,"macro_regime.parquet"))), error=function(e) NULL)
regime_arm <- list(available = FALSE)
if (!is.null(reg) && "Date" %in% names(reg)) {
  reg[, Date := as.Date(Date)]
  # Macro_Risk_Score: 높을수록 위험. RISK_ON = 하위 절반, CRISIS/CAUTION = 상위. Fin_Stress_Regime 병용.
  # PIT: 신호월 t 의 holding 은 t+1 시작. regime 신호는 t 이전 마지막 스탬프 (Date <= sig_date, 진행중월 배제).
  sel_sc <- build_combo_scores(SEL)[Date>=as.Date(FULL_FROM)&Date<=as.Date(FULL_TO)]
  # 각 sig_date 에 대해 Date <= sig_date 인 regime 마지막 행
  reg_valid <- reg[!is.na(Macro_Risk_Score)]
  sd_u <- sort(unique(sel_sc$Date))
  lab <- vapply(sd_u, function(d) {
    v <- reg_valid[Date <= d]; if (!nrow(v)) return(NA_real_); v[Date==max(Date), Macro_Risk_Score][1]
  }, numeric(1))
  labdt <- data.table(Date = sd_u, mrs = lab)
  med_mrs <- median(labdt$mrs, na.rm=TRUE)
  labdt[, regime := fifelse(is.na(mrs), NA_character_, fifelse(mrs <= med_mrs, "RISK_ON", "RISK_OFF"))]
  # active net 월별 (full 창 canonical period_returns 재사용 위해 재측정)
  bres <- measure_combo("B_regime", SEL, FULL_FROM, FULL_TO)
  if (is.null(bres$error)) {
    pr <- bres$period_returns  # date, ret_net, benchmark_ret
    pr <- merge(pr, labdt[, .(date=Date, regime)], by="date")
    pr[, active := ret_net - benchmark_ret]
    ra <- pr[!is.na(regime), .(mean_active_ann = mean(active)*12, n = .N,
             sr = mean(active)/sd(active)*sqrt(12)), by=regime]
    regime_arm <- list(available=TRUE, median_mrs=med_mrs,
        by_regime = setNames(lapply(seq_len(nrow(ra)), function(i) as.list(ra[i])), ra$regime),
        note="Macro_Risk_Score median split (RISK_ON=하위 위험, RISK_OFF=상위). PIT: regime Date<=sig_date(진행중월 배제). advisory.")
    print(ra)
  }
}

saveRDS(list(redundancy=list(m08_m01=cor_m08_m01,m08_m07=cor_m08_m07,m08_q01=cor_m08_q01),
   selected=SEL, windows=out, oos_retention_capw=oos_retention_capw,
   perfect_foresight=pf_pick, regime_arm=regime_arm),
   file.path(scratch, "confirm.rds"))
write_json(list(redundancy=list(m08_m01=cor_m08_m01,m08_m07=cor_m08_m07,m08_q01=cor_m08_q01),
   selected=SEL, windows=out, oos_retention_capw=oos_retention_capw,
   perfect_foresight=pf_pick, regime_arm=regime_arm),
   file.path(scratch, "confirm.json"), auto_unbox=TRUE, na="null", pretty=TRUE)
cat("\n[confirm] 저장 완료\n")
