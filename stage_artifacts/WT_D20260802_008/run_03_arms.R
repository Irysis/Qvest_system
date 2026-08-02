## run_03_arms.R — NP-2 커버리지 게이트 A/B + 대조군 canonical 실측
##   WT-002 run_03_arms.R 하네스 재사용 — arm 목록만 교체 (사전등록 preregistration.json).
##   신호 불변(score), 게이트는 유니버스 조건화만. 측정기 = canonical_screen_bt (proxy 손계산 없음).
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
setDTthreads(2); try(arrow::set_io_thread_count(2), silent = TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
TD <- "stage_artifacts/WT_D20260802_008"
source("02_Infrastructure/contracts/canonical_screen_bt.R")

SI   <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
fwd  <- as.data.table(SI$fwd_ret); bench <- as.data.table(SI$bench)
liqf <- as.data.table(SI$liqf);    SIZE  <- as.data.table(SI$SIZE)
BASE <- as.data.table(read_parquet(file.path(TD, "cov_panel.parquet")))
BASE[, Date := as.Date(Date)]
setorder(BASE, Date, Ticker)   # ★정수 동률 분할 결정성 (사전등록 tie_note)
LIQ_MIN <- 2e8; TOPN <- 25L; COST <- 15
cat(sprintf("[BASE] rows=%d months=%d  월평균=%.1f\n",
            nrow(BASE), uniqueN(BASE$Date), nrow(BASE) / uniqueN(BASE$Date)))

## 공통 EW-유니버스 벤치 (BASE 고정)
ewb <- merge(unique(BASE[, .(Date, Ticker)]), fwd[, .(Date, Ticker, Ret_1m)], by = c("Date", "Ticker"))
ew_bench <- ewb[, .(BM_Ret = mean(Ret_1m, na.rm = TRUE)), by = Date]
cat(sprintf("[EW-uni bench] months=%d  ann=%.4f\n", nrow(ew_bench), mean(ew_bench$BM_Ret) * 12))

half <- function(dt, var, desc = TRUE) {
  d <- copy(dt)
  d[, .r := frank(if (desc) -get(var) else get(var), ties.method = "first"), by = Date]
  d[, .n := .N, by = Date]
  out <- d[.r <= ceiling(.n / 2)]
  out[, c(".r", ".n") := NULL][]
}
half_within_size_quintile <- function(dt, var) {
  d <- copy(dt)
  d[, .q := cut(frank(Size, ties.method = "first") / .N, breaks = seq(0, 1, .2),
                labels = FALSE, include.lowest = TRUE), by = Date]
  d[, .r := frank(-get(var), ties.method = "first"), by = .(Date, .q)]
  d[, .n := .N, by = .(Date, .q)]
  out <- d[.r <= ceiling(.n / 2)]
  out[, c(".q", ".r", ".n") := NULL][]
}

arms <- list(
  A_base          = BASE,
  B_cov           = half(BASE, "cov_l0", TRUE),
  B_cov_low       = half(BASE, "cov_l0", FALSE),
  B_cov_lag1      = half(BASE, "cov_l1", TRUE),
  C_liq_matched   = half(BASE[is.finite(adv)], "adv", TRUE),
  D_size_matched  = half(BASE[is.finite(Size)], "Size", TRUE),
  E_cov_sizeneut  = half_within_size_quintile(BASE[is.finite(Size)], "cov_l0")
)

run_arm <- function(nm, dt, bench_dt, tag, size_dt = NULL) {
  sc <- dt[, .(Date, Ticker, score)]
  r <- canonical_screen_bt(sc, fwd, bench_dt, top_n = TOPN, cost_bps_oneway = COST,
                           liq_dt = liqf, liq_min = LIQ_MIN, size_dt = size_dt,
                           run_id = paste0("fq084np2_", nm, "_", tag),
                           strategy_id = paste0("FQ084NP2_", nm, "_", tag),
                           diag_dual_basis = TRUE)
  r$arm <- nm; r$bench_basis <- tag
  r$avg_names <- nrow(dt) / uniqueN(dt$Date)
  r
}

RES <- list()
for (nm in names(arms)) {
  RES[[paste0(nm, "|capw")]]  <- run_arm(nm, arms[[nm]], bench,    "capw",  size_dt = SIZE)
  RES[[paste0(nm, "|ewuni")]] <- run_arm(nm, arms[[nm]], ew_bench, "ewuni", size_dt = NULL)
  cat(sprintf("  [%s] capw PORT_t=%+.3f  ewuni PORT_t=%+.3f  names/mo=%.0f n=%d\n",
              nm, RES[[paste0(nm, "|capw")]]$portfolio_alpha_t_nw_lag3,
              RES[[paste0(nm, "|ewuni")]]$portfolio_alpha_t_nw_lag3,
              RES[[paste0(nm, "|capw")]]$avg_names, RES[[paste0(nm, "|capw")]]$n_months))
}

## placebo: 무작위 50% x 20 seed — WT-002 동일 시드 1001~1020 (cap-w basis)
pl <- numeric(0)
for (sd0 in 1:20) {
  set.seed(1000 + sd0)
  d <- copy(BASE); d[, .u := runif(.N)]
  P <- half(d, ".u", TRUE); P[, .u := NULL]
  rr <- run_arm(sprintf("P_random_%02d", sd0), P, bench, "capw", size_dt = NULL)
  pl <- c(pl, rr$portfolio_alpha_t_nw_lag3)
}
cat(sprintf("[placebo] n=%d  mean=%+.3f sd=%.3f  q05=%+.3f q50=%+.3f q95=%+.3f max=%+.3f\n",
            length(pl), mean(pl), sd(pl), quantile(pl, .05), quantile(pl, .5), quantile(pl, .95), max(pl)))

## paired: arm별 월간 net 수익 − A_base, NW lag-3 t
suppressPackageStartupMessages({library(sandwich); library(lmtest)})
nwt <- function(x) {
  x <- x[is.finite(x)]; if (length(x) < 12) return(NA_real_)
  m <- stats::lm(x ~ 1)
  as.numeric(lmtest::coeftest(m, vcov = sandwich::NeweyWest(m, lag = 3, prewhite = FALSE))[1, 3])
}
prA <- as.data.table(RES[["A_base|capw"]]$period_returns)
paired <- rbindlist(lapply(setdiff(names(arms), "A_base"), function(nm) {
  prX <- as.data.table(RES[[paste0(nm, "|capw")]]$period_returns)
  m <- merge(prA[, .(date, ret_A = ret_net)], prX[, .(date, ret_X = ret_net)], by = "date")
  d <- m$ret_X - m$ret_A
  data.table(arm = nm, n = nrow(m), mean_diff_ann = mean(d) * 12, nw_t_diff = nwt(d))
}))
cat("\n[paired vs A_base — 월간 net 차분 NW lag-3]\n"); print(paired)

## cap-tier 분해
ct <- lapply(c("A_base", "B_cov", "D_size_matched"), function(nm) {
  x <- RES[[paste0(nm, "|capw")]]$diag_cap_tier
  if (!isTRUE(x$available)) return(NULL)
  data.table(arm = nm,
             w_MEGA = x$weight_share_avg$MEGA, w_MID = x$weight_share_avg$MID,
             w_OTHER = x$weight_share_avg$OTHER, w_UNRANKED = x$weight_share_avg$UNRANKED,
             c_MEGA = x$contrib_gross_annualized$MEGA, c_MID = x$contrib_gross_annualized$MID,
             c_OTHER = x$contrib_gross_annualized$OTHER)
})
cap_tier <- rbindlist(Filter(Negate(is.null), ct))
cat("\n[cap-tier 분해]\n"); print(cap_tier)

## 요약 저장
summ <- rbindlist(lapply(names(RES), function(k) {
  r <- RES[[k]]
  ew <- r$diag_ew_universe
  data.table(arm_key = k, arm = r$arm, basis = r$bench_basis, n_months = r$n_months,
             avg_names = r$avg_names,
             port_t = r$portfolio_alpha_t_nw_lag3, p = r$portfolio_alpha_t_pvalue,
             ir = r$information_ratio, alpha_ann = r$alpha_annualized,
             net_sr = r$net_sr, turnover_ann = r$turnover_annual,
             own_ew_port_t = if (is.list(ew)) ew$portfolio_alpha_t_nw_lag3 else NA_real_,
             own_ew_post2017_t = if (is.list(ew)) ew$post2017_t_nw_lag3 else NA_real_,
             own_ew_oos_approx = if (is.list(ew)) ew$oos_retention_approx else NA_real_)
}))
cat("\n[SUMMARY]\n"); print(summ[order(basis, -port_t)])

## 앵커 검증 (사전등록 harness_anchor)
a_t <- summ[arm_key == "A_base|capw", port_t]
cat(sprintf("\n[ANCHOR] A_base capw PORT_t = %.4f  (WT-002 = 3.4781)  일치=%s\n",
            a_t, abs(a_t - 3.47810711240596) < 1e-6))

saveRDS(list(summ = summ, paired = paired, cap_tier = cap_tier, placebo = pl,
             ew_bench = ew_bench, res_keys = names(RES),
             period_returns = lapply(RES[paste0(names(arms), "|capw")], function(r) as.data.table(r$period_returns))),
        file.path(TD, "arms_results.rds"))
fwrite(summ, file.path(TD, "arms_summary.csv"))
write_json(list(summary = summ, paired = paired, cap_tier = cap_tier,
                anchor = list(a_base_capw = a_t, wt002_ref = 3.47810711240596,
                              match = abs(a_t - 3.47810711240596) < 1e-6),
                placebo = list(n = length(pl), mean = mean(pl), sd = sd(pl),
                               q05 = unname(quantile(pl, .05)), q50 = unname(quantile(pl, .5)),
                               q95 = unname(quantile(pl, .95)), max = max(pl), values = pl)),
           file.path(TD, "arms_results.json"), auto_unbox = TRUE, pretty = TRUE, digits = 6)
cat("\n[SAVED] arms_results.rds / arms_summary.csv / arms_results.json\n[DONE]\n")
