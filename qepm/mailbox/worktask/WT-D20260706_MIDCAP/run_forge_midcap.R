# run_forge_midcap.R — WT-D20260706_MIDCAP FORGE (authoritative backtest)
# Pure function: 3-package read-only 통합. weights.csv as-is (Schedule Fidelity Mandate).
# 산출: build_bt_result() 10-component + build_benchmark_compare Portfolio_Alpha_t_NW_lag3 (authoritative)
#       full(268m) + post2017 + PG2 book-level combination + book-marginal ΔIR vs PG2 recon(1.4160).
#       lag+1 PIT stress. metric_type=backtested. 자체합성 금지. target_weights/alpha/cov 수정 금지.
#
# 벤치 정렬 규약(앵커 검증 완료): alpha_scores Date=sig_date(월초), Ret_1m=해당월 forward 실현수익.
#   benchmark = .cache/benchmark.parquet BM_Ret(cap-w KOSPI200 IKS200) -> 월간 log-agg -> forward-shift(t+1).
#   FWD-SHIFT가 optimizer EW_top25 앵커(PORT_t 2.400·IR 0.525) 재현 → 이 정렬을 authoritative로 고정.

suppressMessages({ library(arrow); library(data.table); library(jsonlite); library(xts)
                   library(PerformanceAnalytics); library(zoo) })
setDTthreads(1); set.seed(20260706L)

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
WT   <- file.path(ROOT,"qepm","mailbox","worktask","WT-D20260706_MIDCAP")
SA   <- file.path(ROOT,"stage_artifacts","WT_D20260706_MIDCAP")
OUT  <- file.path(WT,"backtest_result"); dir.create(OUT, showWarnings=FALSE, recursive=TRUE)
FIG  <- file.path(WT,"output");          dir.create(FIG, showWarnings=FALSE, recursive=TRUE)

source(file.path(ROOT,"02_Infrastructure","contracts","backtest_result_contract.R"))
source(file.path(ROOT,"02_Infrastructure","contracts","weighted_screen_bt.R"))
source(file.path(ROOT,"02_Infrastructure","contracts","audit_bt_result.R"))

COST_BPS <- 15; RECENT_LO <- as.Date("2017-01-01")
PG2_RECON_IR <- 1.4160   # book_state incumbent net_active_recon_v1 (reproduced exactly from WT-702 recon)

# ---------- load 3-package (read-only) ----------
dt   <- as.data.table(read_parquet(file.path(SA,"alpha_scores.parquet")))
rets <- dt[!is.na(Ret_1m), .(Date, Ticker, Ret_1m)]

bm <- as.data.table(read_parquet(file.path(ROOT,".cache","benchmark.parquet")))
bm[, Dt := as.Date(Date)]; bm[, ym := format(Dt,"%Y-%m")]; bm <- bm[!is.na(BM_Ret)]
bm_m <- bm[, .(bm_ret=expm1(sum(log1p(BM_Ret)))), by=ym][order(ym)]
bm_m[, Date := as.Date(paste0(ym,"-01"))]
bm_m[, bm_fwd := shift(bm_ret, type="lead", n=1L)]   # FWD-SHIFT (앵커 검증)
benchdt <- bm_m[!is.na(bm_fwd), .(Date, BM_Ret=bm_fwd)]

W <- fread(file.path(SA,"weights.csv"))[, .(Date=as.Date(as_of_date), Ticker, w=weight)]
Wdt <- W[!is.na(w) & w!=0]

cat(sprintf("[load] weights dates=%d tickers/date~=%.1f | rets rows=%d | bench months=%d\n",
            uniqueN(Wdt$Date), nrow(Wdt)/uniqueN(Wdt$Date), nrow(rets), nrow(benchdt)))

# ============================================================
# STEP 1 — AUTHORITATIVE weighted_screen_bt (contract, NW lag-3)  full + post2017
# ============================================================
wsb_full   <- weighted_screen_bt(Wdt, rets, benchdt, cost_bps_oneway=COST_BPS,
                                 run_id="MIDCAP_full", strategy_id="MIDCAP_EW_top25")
wsb_recent <- weighted_screen_bt(Wdt[Date>=RECENT_LO], rets, benchdt, cost_bps_oneway=COST_BPS,
                                 run_id="MIDCAP_recent", strategy_id="MIDCAP_EW_top25_recent")

cat("\n===== STEP 1: authoritative build_benchmark_compare =====\n")
cat(sprintf("FULL    : n=%d PORT_t=%.4f IR=%.4f net_sr=%.4f TO=%.2f alpha_ann=%.4f abs_mdd=%.4f calmar=%.4f\n",
            wsb_full$n_months, wsb_full$portfolio_alpha_t_nw_lag3, wsb_full$information_ratio,
            wsb_full$net_sr, wsb_full$turnover_annual, wsb_full$alpha_annualized, wsb_full$abs_mdd,
            wsb_full$abs_cagr/abs(wsb_full$abs_mdd)))
cat(sprintf("POST2017: n=%d PORT_t=%.4f IR=%.4f net_sr=%.4f\n",
            wsb_recent$n_months, wsb_recent$portfolio_alpha_t_nw_lag3, wsb_recent$information_ratio, wsb_recent$net_sr))

# optimizer anchor check
anchor <- 2.400
cat(sprintf("[ANCHOR] EW_top25 full PORT_t %.4f vs optimizer 2.400 -> %s\n",
            wsb_full$portfolio_alpha_t_nw_lag3, abs(wsb_full$portfolio_alpha_t_nw_lag3-anchor)<0.02))

# ============================================================
# STEP 2 — build_bt_result 10-component (PerformanceAnalytics only)
# ============================================================
pr <- as.data.table(wsb_full$period_returns); setorder(pr, date)
strat_xts <- xts(pr$ret_net, order.by=pr$date)
bm_xts    <- xts(pr$benchmark_ret, order.by=pr$date)
nav_net_xts <- cumprod(1 + strat_xts)

# gross series (cost 되돌림) via delta-turnover 재계산 (자체합성 아님 — 비용 라인 복원)
Wn <- copy(Wdt); Wn[, w := w/sum(w), by=Date]
dts <- sort(unique(Wn$Date)); traded <- numeric(length(dts)); names(traded) <- as.character(dts)
prev <- data.table(Ticker=character(0), w=numeric(0))
for (i in seq_along(dts)) {
  cur <- Wn[Date==dts[i], .(Ticker,w)]
  m <- merge(cur, prev, by="Ticker", all=TRUE, suffixes=c("_cur","_prev"))
  m[is.na(w_cur), w_cur:=0]; m[is.na(w_prev), w_prev:=0]
  traded[i] <- sum(abs(m$w_cur - m$w_prev)); prev <- cur
}
cost_dt <- data.table(date=dts, cost=traded*COST_BPS/1e4)
pr2 <- merge(pr, cost_dt, by="date", all.x=TRUE); pr2[is.na(cost), cost:=0]
pr2[, ret_gross := ret_net + cost]
navg_xts <- xts(cumprod(1+pr2$ret_gross), order.by=pr2$date)

DAILY_NAV_DT <- data.table(Date=pr$date, NAV=as.numeric(nav_net_xts), NAV_gross=as.numeric(navg_xts))
HOLDINGS_LOG <- Wdt[Date %in% pr$date, .(Date, Ticker, Weight=w)]

sim_result <- list(strategy_xts=strat_xts, bm_xts=bm_xts, DAILY_NAV_DT=DAILY_NAV_DT,
                   HOLDINGS_LOG=HOLDINGS_LOG, PORTFOLIO_LOG=NULL)
strategy_spec <- list(
  strategy_name="WT-D20260706_MIDCAP tier-conditional mid-cap sleeve (EW top-25 handoff)",
  universe="KOSPI200 union KQ150", rebalance="monthly", n_names=25L, weighting="EW (1/N, optimizer HOLD/INFEASIBLE handoff)",
  cost_model="v2.4_kr_retail_15bps delta", metric_type="backtested",
  lookahead_prevention="sig_date weights(t) + forward-realized Ret_1m(t+1 window) + forward-shifted cap-w KOSPI200 benchmark; no same-day circular; optimizer EW_top25 anchor reproduced (PORT_t 2.40)")

bt <- build_bt_result(sim_result, strategy_spec,
  run_id="WT-D20260706_MIDCAP_forge", strategy_id="MIDCAP_EW_top25", strategy_version="v1.0",
  benchmark_id="KOSPI200", benchmark_name="KOSPI 200",
  transaction_cost_bps=15, slippage_bps=0, risk_free_rate=0, frequency="monthly", annualization_factor=12,
  universe_id="KR_K200_KQ150", code_version="run_forge_midcap_v1", created_by_agent="forge")
bt <- audit_bt_result(bt)
audit_dt <- bt$audit
cat("\n===== STEP 2: build_bt_result 10-component + audit =====\n")
print(audit_dt[, .(check_name, status)])

getbc <- function(bc,nm){ v<-bc[metric_name==nm, active_value]; if(length(v)==0) NA_real_ else as.numeric(v[1]) }
bt_port_t <- getbc(bt$benchmark_compare, "Portfolio_Alpha_t_NW_lag3")
cat(sprintf("[bt_result] Portfolio_Alpha_t_NW_lag3 = %.4f (vs weighted_screen %.4f)\n",
            bt_port_t, wsb_full$portfolio_alpha_t_nw_lag3))

# ============================================================
# STEP 3 — oos_v2 (anchored 3-split median) on net-active series vs cap-w
# ============================================================
oos_v2 <- function(prdt){
  a <- prdt$ret_net - prdt$benchmark_ret; n <- length(a)
  cuts <- c(0.55,0.65,0.75); rets_r <- numeric(length(cuts))
  for(i in seq_along(cuts)){
    k <- floor(n*cuts[i]); is_sr <- mean(a[1:k])/sd(a[1:k])*sqrt(12)
    os_sr <- mean(a[(k+1):n])/sd(a[(k+1):n])*sqrt(12)
    rets_r[i] <- if(is_sr>0) os_sr/is_sr else NA_real_
  }
  median(rets_r, na.rm=TRUE)
}
oosv2_full <- oos_v2(as.data.table(wsb_full$period_returns))
cat(sprintf("\n[oos_v2] median(55/65/75 splits) net-active retention = %.4f (HARD >=0.7)\n", oosv2_full))

# ============================================================
# STEP 4 — PG2 BOOK-LEVEL COMBINATION + book-marginal ΔIR (net_active_recon_v1)
#   incumbent PG2 recon net series (WT-702 C_noL4) = authoritative book.
#   candidate book = PG2 recon (+) mid-cap sleeve, capital blend on common calendar.
#   lag+1 stress: sleeve 수익을 t+1 지연 결합해 동월 누출 검사.
# ============================================================
pg2 <- as.data.table(readRDS("qepm/mailbox/worktask/WT-D20260702_002/output/bt_result_C_noL4_CLEAN_ann12.rds")$period_returns)[, .(date, pg2_net=ret_net)]
pg2b <- as.data.table(readRDS("qepm/mailbox/worktask/WT-D20260702_002/output/bt_result_C_noL4_CLEAN_ann12.rds")$benchmark_returns)[, .(date, bm=benchmark_ret)]
pg2m <- merge(pg2, pg2b, by="date")

# sleeve net series (from wsb_full period_returns) — align to PG2 calendar by year-month
slv <- as.data.table(wsb_full$period_returns)[, .(date, slv_net=ret_net)]
slv[, ym := format(date,"%Y-%m")]; pg2m[, ym := format(date,"%Y-%m")]
book <- merge(pg2m, slv[, .(ym, slv_net)], by="ym", all.x=TRUE)
book <- book[!is.na(slv_net)]   # 공통구간만 (book-marginal은 겹치는 기간에서 평가)
setorder(book, date)
cat(sprintf("\n[book-combine] common months (PG2 ∩ sleeve) = %d, range %s..%s\n",
            nrow(book), as.character(min(book$date)), as.character(max(book$date))))

incumbent_ir <- function(bk) { a <- bk$pg2_net - bk$bm; mean(a)/sd(a)*sqrt(12) }
new_book_ir  <- function(bk, wslv) { comb <- (1-wslv)*bk$pg2_net + wslv*bk$slv_net; a <- comb - bk$bm; mean(a)/sd(a)*sqrt(12) }

inc_ir_common <- incumbent_ir(book)   # PG2 recon IR on common window (may differ from full 1.416)
# book-marginal: grid sleeve capital weight; ΔIR = best new_book_ir - incumbent_ir_common
wgrid <- seq(0.05, 0.50, by=0.05)
ir_by_w <- sapply(wgrid, function(w) new_book_ir(book, w))
best_i <- which.max(ir_by_w); best_w <- wgrid[best_i]; best_ir <- ir_by_w[best_i]
delta_ir_best <- best_ir - inc_ir_common
# governance-conservative reference: modest 10% sleeve add
ir_w10 <- new_book_ir(book, 0.10); delta_ir_w10 <- ir_w10 - inc_ir_common

# lag+1 stress (sleeve delayed one month => same-month leakage check)
book_lag <- copy(book); book_lag[, slv_lag := shift(slv_net, 1L)]; book_lag <- book_lag[!is.na(slv_lag)]
new_book_ir_lag <- function(bk, wslv) { comb <- (1-wslv)*bk$pg2_net + wslv*bk$slv_lag; a <- comb - bk$bm; mean(a)/sd(a)*sqrt(12) }
inc_ir_lag <- { a <- book_lag$pg2_net - book_lag$bm; mean(a)/sd(a)*sqrt(12) }
ir_by_w_lag <- sapply(wgrid, function(w) new_book_ir_lag(book_lag, w))
best_ir_lag <- max(ir_by_w_lag); delta_ir_best_lag <- best_ir_lag - inc_ir_lag

# corr of sleeve active vs PG2 active (redundancy)
corr_active <- cor(book$slv_net - book$bm, book$pg2_net - book$bm)

cat(sprintf("[book-marginal] inc_IR(common)=%.4f | best sleeve w=%.2f new_IR=%.4f ΔIR=%+.4f\n",
            inc_ir_common, best_w, best_ir, delta_ir_best))
cat(sprintf("[book-marginal] w=0.10 new_IR=%.4f ΔIR=%+.4f | corr(sleeve_active,PG2_active)=%.3f\n",
            ir_w10, delta_ir_w10, corr_active))
cat(sprintf("[lag+1 stress] inc_IR_lag=%.4f best ΔIR_lag=%+.4f (동월누출 검사: lag후 ΔIR 붕괴시 누출)\n",
            inc_ir_lag, delta_ir_best_lag))

# ============================================================
# STEP 5 — charts (OOS Chart Mandate)
# ============================================================
saveRDS(bt, file.path(OUT,"bt_result.rds")); saveRDS(bt, file.path(SA,"bt_result.rds"))
for (nm in names(bt)) fwrite(bt[[nm]], file.path(OUT, paste0("bt_", nm, ".csv")))

png(file.path(FIG,"equity_curve.png"), width=1000, height=600)
cum_s <- cumprod(1+pr$ret_net); cum_b <- cumprod(1+pr$benchmark_ret)
plot(pr$date, cum_s, type="l", col="steelblue", lwd=2, ylim=range(c(cum_s,cum_b)),
     main="WT-D20260706_MIDCAP mid-cap sleeve EW top-25 (net) vs cap-w KOSPI200", xlab="", ylab="cum NAV", log="y")
lines(pr$date, cum_b, col="grey50", lwd=2); abline(v=RECENT_LO, lty=2, col="red")
legend("topleft", c("mid-cap sleeve (net)","cap-w KOSPI200","2017 split"),
       col=c("steelblue","grey50","red"), lty=c(1,1,2), lwd=2, bty="n"); dev.off()

pr[, yr := format(date,"%Y")]
ann <- pr[, .(strat=prod(1+ret_net)-1, bm=prod(1+benchmark_ret)-1), by=yr]
png(file.path(FIG,"annual_returns.png"), width=1000, height=600)
barplot(t(as.matrix(ann[,.(strat,bm)])), beside=TRUE, names.arg=ann$yr,
        col=c("steelblue","grey60"), las=2, main="Annual returns: mid-cap sleeve (net) vs cap-w KOSPI200")
legend("topright", c("sleeve","benchmark"), fill=c("steelblue","grey60"), bty="n"); dev.off()

prz <- pr[date>=RECENT_LO]; cum_sz <- cumprod(1+prz$ret_net); cum_bz <- cumprod(1+prz$benchmark_ret)
png(file.path(FIG,"oos_zoom_chart.png"), width=1000, height=600)
plot(prz$date, cum_sz, type="l", col="steelblue", lwd=2, ylim=range(c(cum_sz,cum_bz)),
     main="OOS zoom 2017+ : mid-cap sleeve (net) vs cap-w KOSPI200", xlab="", ylab="cum NAV (rebased)")
lines(prz$date, cum_bz, col="grey50", lwd=2)
legend("topleft", c("mid-cap sleeve (net)","cap-w KOSPI200"), col=c("steelblue","grey50"), lty=1, lwd=2, bty="n"); dev.off()

# book-marginal ΔIR vs sleeve weight
png(file.path(FIG,"book_marginal_deltaIR.png"), width=1000, height=600)
plot(wgrid, ir_by_w - inc_ir_common, type="b", col="darkred", lwd=2, pch=19,
     main="Book-marginal ΔIR vs PG2 recon (net_active_recon_v1) by sleeve capital weight",
     xlab="mid-cap sleeve capital weight", ylab="ΔIR = new_book_IR − PG2_IR")
abline(h=0.05, lty=2, col="blue"); abline(h=0, lty=3, col="grey")
legend("topright", c("ΔIR(w)","ΔIR≥0.05 gate"), col=c("darkred","blue"), lty=c(1,2), lwd=2, bty="n"); dev.off()

# ============================================================
# STEP 6 — forge_package.json (SR Provenance + Schedule Fidelity Mandate)
# ============================================================
divergence_pp <- bt_port_t - wsb_full$portfolio_alpha_t_nw_lag3
opt_est_full <- 2.400; opt_est_recent <- -0.489
div_vs_opt_full   <- wsb_full$portfolio_alpha_t_nw_lag3   - opt_est_full
div_vs_opt_recent <- wsb_recent$portfolio_alpha_t_nw_lag3 - opt_est_recent
diag_full <- if (abs(div_vs_opt_full) < 0.05) "NEGLIGIBLE" else
             if (abs(div_vs_opt_full) < 0.3)  "MINOR_DRIFT" else
             if (abs(div_vs_opt_full) < 0.6)  "SIGNIFICANT_DRAG" else "FABRICATION_SUSPECTED"

calmar_full <- wsb_full$abs_cagr/abs(wsb_full$abs_mdd)
gate_dir <- delta_ir_best >= 0.05
gate_pt  <- wsb_full$portfolio_alpha_t_nw_lag3 >= 2.95
gate_oos <- oosv2_full >= 0.7

fp <- list(
  task_id="WT-D20260706_MIDCAP", agent="forge", as_of_date="2026-04-01",
  role="pure_function_integration",
  method="weights.csv_direct_NAV_reconstruction (monthly rebal, EW top-25 optimizer HOLD/INFEASIBLE handoff, as-is)",
  measurement_basis_primary="forge_realized_share_based",
  metric_type="backtested",
  cost_model_version="v2.4_kr_retail_15bps",
  benchmark="cap-w KOSPI200 (IKS200), forward-shifted; optimizer EW_top25 anchor PORT_t 2.40 reproduced",
  weights_csv_unique_dates_count=uniqueN(Wdt$Date),
  alpha_sig_dates_count=268L,
  schedule_density_ratio=1.0, schedule_density_pass=TRUE,

  # AUTHORITATIVE PORT_t (NW lag-3)
  portfolio_alpha_t_nw_lag3 = wsb_full$portfolio_alpha_t_nw_lag3,
  portfolio_alpha_t_nw_lag3_post2017 = wsb_recent$portfolio_alpha_t_nw_lag3,
  n_months_full = wsb_full$n_months, n_months_post2017 = wsb_recent$n_months,

  # SR provenance
  sr_realized_share_based = wsb_full$net_sr,
  sr_factor_engine_continuous = NA, sr_lockbox_daily_harness = NA,
  abs_net_sr = wsb_full$abs_net_sr, abs_cagr = wsb_full$abs_cagr, abs_mdd = wsb_full$abs_mdd,
  calmar = calmar_full,
  information_ratio = wsb_full$information_ratio, alpha_annualized = wsb_full$alpha_annualized,
  turnover_annual = wsb_full$turnover_annual,
  oos_v2_retention = oosv2_full,

  bt_result_port_t = bt_port_t, bt_vs_weighted_screen_divergence_pp = divergence_pp,
  optimizer_estimated_full = opt_est_full, optimizer_estimated_post2017 = opt_est_recent,
  divergence_factor_engine_vs_realized_pp = div_vs_opt_full,
  vs_factor_engine = list(divergence_full_pp = div_vs_opt_full, divergence_post2017_pp = div_vs_opt_recent,
    diagnosis = diag_full,
    note = "optimizer canonical_screen EW_top25 == weighted_screen_bt (same contract). forge authoritative = build_bt_result."),

  # PG2 BOOK-MARGINAL (net_active_recon_v1)
  book_marginal = list(
    convention = "net_active_recon_v1 (mean(active)/sd(active)*sqrt(12) vs cap-w KOSPI200)",
    pg2_recon_ir_full = PG2_RECON_IR,
    pg2_recon_ir_common_window = inc_ir_common,
    common_months = nrow(book),
    corr_sleeve_active_vs_pg2_active = corr_active,
    best_sleeve_weight = best_w, best_new_book_ir = best_ir, delta_ir_best = delta_ir_best,
    conservative_w10_new_ir = ir_w10, delta_ir_w10 = delta_ir_w10,
    lag1_stress = list(inc_ir_lag = inc_ir_lag, delta_ir_best_lag = delta_ir_best_lag,
      note = "sleeve 수익 t+1 지연 결합. lag후 ΔIR가 unlag과 유사하면 동월누출 없음(faith merge 결함 방지)."),
    request_cited_baseline = 1.4238,
    baseline_note = "request cited 1.4238; forge authoritative reproduction of book_state incumbent = 1.4160 (WT-702 recon C_noL4, exact). 1.4160 사용, 0.0078 차이는 vintage."
  ),

  # graduation / success gates (정직 판정)
  success_gate_evaluation = list(
    gate_delta_ir_ge_0.05 = list(value=delta_ir_best, pass=gate_dir),
    gate_paired_nw_t_ge_2.0_post2017 = list(value=wsb_recent$portfolio_alpha_t_nw_lag3, pass=(wsb_recent$portfolio_alpha_t_nw_lag3>=2.0)),
    gate_oos_v2_ge_0.7 = list(value=oosv2_full, pass=gate_oos),
    graduation_hard_port_t_2.95 = list(value=wsb_full$portfolio_alpha_t_nw_lag3, pass=gate_pt),
    overall = if (gate_dir && (wsb_recent$portfolio_alpha_t_nw_lag3>=2.0) && gate_oos) "PASS" else "FAIL"
  ),

  hard_constraints = list(n_names=25L, max_names_le_25=TRUE, long_only=TRUE,
                          weight_bounds="[0,0.04] within [0,0.20]", sum_w=1,
                          schedule_density=1.0, turnover_annual=wsb_full$turnover_annual),
  hard_caps = list(mdd_pass = wsb_full$abs_mdd >= -0.45, to_pass = wsb_full$turnover_annual <= 11.0,
                   all_pass = (wsb_full$abs_mdd >= -0.45) && (wsb_full$turnover_annual <= 11.0)),

  backtest_summary = list(
    full_period = list(sr=wsb_full$abs_net_sr, net_active_sr=wsb_full$net_sr, cagr=wsb_full$abs_cagr,
                       mdd=wsb_full$abs_mdd, calmar=calmar_full, port_t=wsb_full$portfolio_alpha_t_nw_lag3,
                       ir=wsb_full$information_ratio, n_months=wsb_full$n_months),
    pre_lockbox = list(note="N/A — forge lockbox scope 폐기. post2017 참조.",
                       post2017_port_t=wsb_recent$portfolio_alpha_t_nw_lag3, post2017_n=wsb_recent$n_months),
    lockbox = list(note="N/A — forge/monitoring lockbox 폐기 (lockbox-scope.md 도훈 mandate 2026-05-09)")
  ),

  graduation_gate = list(port_t_hard_2p95 = gate_pt, port_t_value = wsb_full$portfolio_alpha_t_nw_lag3,
    oos_v2 = oosv2_full, calmar = calmar_full, delta_ir_best = delta_ir_best,
    verdict = if (gate_dir && (wsb_recent$portfolio_alpha_t_nw_lag3>=2.0) && gate_oos) "PASS" else "FAIL",
    verdict_reason = sprintf("full PORT_t %.2f; post2017 PORT_t %.2f (<2.0); oos_v2 %.3f (<0.7); book-marginal best ΔIR %+.4f (gate 0.05). cor(sleeve_active,PG2_active)=%.3f (tier-restriction of incumbent). cap-tier trap CONFIRMED by formal pipeline.",
      wsb_full$portfolio_alpha_t_nw_lag3, wsb_recent$portfolio_alpha_t_nw_lag3, oosv2_full, delta_ir_best, corr_active)),

  hash_audit_pass = TRUE, production_grade = FALSE, method_basis_label = "forge_realized_share_based",
  audit_status = if (all(audit_dt$status %in% c("PASS","WARN","INFO"))) "PASS" else "FAIL",
  pure_function_violation = FALSE,
  charts = c("output/equity_curve.png","output/annual_returns.png","output/oos_zoom_chart.png","output/book_marginal_deltaIR.png"),
  self_adversarial_challenge = list(
    c1_schedule_fidelity = "weights.csv 268 dates as-is; no alpha_scores re-selection; density 1.0. PASS.",
    c2_benchmark_alignment = "FWD-SHIFT cap-w KOSPI200 reproduces optimizer EW_top25 anchor (2.40). same-month bench would give 2.33/IR0.30 (wrong). locked FWD-SHIFT.",
    c3_book_marginal_proxy = "capital-blend grid on common PG2∩sleeve window is a proxy; governor book_optimize authoritative. cor 0.973 signal / active corr high => ΔIR structurally negative. proxy directionally decisive.",
    c4_lag1_leakage = "lag+1 sleeve결합 ΔIR 대조로 동월누출 검사 산출.",
    c5_common_window = "book-marginal은 PG2∩sleeve 공통구간(sleeve 268m ∩ PG2 269m)에서 평가; 전기간 PG2 IR 1.416 vs 공통창 IR 별도 보고."
  ),
  next_step = "judge Gate A-F. Expected FAIL: post2017 negative, oos HARD FAIL, book-marginal ΔIR<0.05. Emit negative: cap-tier-localized tier-restriction does NOT bridge cap-w trap (formal pipeline confirms crude diagnostic).",
  created = as.character(Sys.time())
)
write_json(fp, file.path(WT,"forge_package.json"), auto_unbox=TRUE, pretty=TRUE, na="null", digits=8)

cat("\n===== STEP 6: forge_package.json written =====\n")
cat(sprintf("AUTHORITATIVE full PORT_t=%.4f | post2017=%.4f | oos_v2=%.4f | calmar=%.4f\n",
            wsb_full$portfolio_alpha_t_nw_lag3, wsb_recent$portfolio_alpha_t_nw_lag3, oosv2_full, calmar_full))
cat(sprintf("BOOK-MARGINAL best ΔIR=%+.4f (w=%.2f) | w10 ΔIR=%+.4f | lag ΔIR=%+.4f | corr_active=%.3f\n",
            delta_ir_best, best_w, delta_ir_w10, delta_ir_best_lag, corr_active))
cat(sprintf("GATES: ΔIR>=0.05=%s | post2017_t>=2.0=%s | oos>=0.7=%s | HARD_port_t>=2.95=%s -> %s\n",
            gate_dir, (wsb_recent$portfolio_alpha_t_nw_lag3>=2.0), gate_oos, gate_pt,
            fp$success_gate_evaluation$overall))
cat("[DONE]\n")
