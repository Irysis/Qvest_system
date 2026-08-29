# S3 — 기전 지문 · 국면 셀-특정 검정 · 무신호 대조 · advisory 배터리 (WT-R20260829_002)
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite); library(sandwich); library(lmtest)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd()
setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/no_signal_control.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_002")
O <- readRDS(file.path(OUT, "s2_objects.rds"))
cells <- O$cells; legs <- O$legs; S <- O$S; R <- O$R; bench <- O$bench; SIZE <- O$SIZE
PPY <- 12L

nw_t1 <- function(x) { x <- x[is.finite(x)]; if (length(x) < 8L) return(NA_real_)
  m <- lm(x ~ 1); as.numeric(coeftest(m, vcov = NeweyWest(m, lag = 3, prewhite = FALSE))[1,3]) }
beta_alpha <- function(x, b) {
  k <- which(is.finite(x) & is.finite(b)); if (length(k) < 12L) return(c(alpha_ann=NA,t_alpha=NA,beta=NA,n=length(k)))
  x <- x[k]; b <- b[k]; f <- lm(x ~ b)
  ct <- coeftest(f, vcov = NeweyWest(f, lag = 3, prewhite = FALSE))
  c(alpha_ann = 12*ct[1,1], t_alpha = ct[1,3], beta = ct[2,1], n = length(x)) }

## ─────────────────────────────────────────────────────────────────────────────
## 1. 국면 라벨 (사후 귀속 진단 — 오버레이 아님. 어떤 셀의 비중에도 쓰이지 않는다)
##    dd_state: 시그널일 d 까지의 벤치 누적 NAV 대비 낙폭(과거만 — PIT-safe)
##    holding-month BM 수익: 실현값 (사후 분류 라벨 — 거래 불가)
## ─────────────────────────────────────────────────────────────────────────────
B <- copy(bench)[order(Date)]
B[, nav := cumprod(1 + BM_Ret)]
B[, runmax := cummax(nav)]
B[, dd_prior := shift(nav/runmax - 1, 1L)]     # 시그널 시점에 알 수 있는 낙폭(직전월까지)
q_lo <- quantile(B$BM_Ret, 0.20, na.rm = TRUE)
B[, regime := fifelse(BM_Ret <= q_lo, "crisis",
              fifelse(is.finite(dd_prior) & dd_prior <= -0.20 & BM_Ret > 0, "recovery",
              fifelse(is.finite(dd_prior) & dd_prior > -0.10 & BM_Ret > 0, "expansion", "neutral")))]
regime_n <- B[, .N, by = regime][order(-N)]

## ─────────────────────────────────────────────────────────────────────────────
## 2. 기전 지문 (a) — 숏 레그 손실의 반등월 집중
##    숏 레그 손실 = 패자 데실 수익 r_lose (숏이므로 −r_lose 가 기여). 국면별 분해.
## ─────────────────────────────────────────────────────────────────────────────
LD <- merge(legs$lose_decile[, .(Date, r_lose = r)], legs$win_decile[, .(Date, r_win = r)], by = "Date")
LD <- merge(LD, B[, .(Date, BM_Ret, regime, dd_prior)], by = "Date")
LD[, short_contrib := -r_lose]        # 숏 레그가 LS 수익에 더하는 몫
LD[, ls_spread := r_win - r_lose]
fp_a <- LD[, .(n = .N,
               r_lose_ann = 12*mean(r_lose), r_win_ann = 12*mean(r_win),
               short_contrib_ann = 12*mean(short_contrib),
               ls_spread_ann = 12*mean(ls_spread),
               bm_ann = 12*mean(BM_Ret)), by = regime][order(-n)]
fp_a_overall <- LD[, .(n = .N, short_contrib_ann = 12*mean(short_contrib),
                       nw_t = nw_t1(short_contrib), ls_spread_ann = 12*mean(ls_spread),
                       ls_nw_t = nw_t1(ls_spread))]
# 반등월 집중도: recovery 국면 더미 회귀 (숏 기여 ~ recovery)
LD[, is_rec := as.integer(regime == "recovery")]
f_rec <- lm(short_contrib ~ is_rec, data = LD)
ct_rec <- coeftest(f_rec, vcov = NeweyWest(f_rec, lag = 3, prewhite = FALSE))
fp_a_test <- list(
  coef_recovery_monthly = as.numeric(ct_rec[2,1]), t_recovery = as.numeric(ct_rec[2,3]),
  base_monthly = as.numeric(ct_rec[1,1]),
  interpretation = "계수<0 & |t|>=2 이면 숏 레그 손실이 반등월에 집중(기전 지문 (a) 성립)")

## ─────────────────────────────────────────────────────────────────────────────
## 3. 기전 지문 (b) — 패자 데실의 소형주 편중
##    월별 유니버스 내 Size 백분위(1=최대형). 패자/승자/유니버스 중앙값 비교.
## ─────────────────────────────────────────────────────────────────────────────
SZ <- merge(unique(S[, .(Date, Ticker)]), SIZE, by = c("Date","Ticker"))
setorder(SZ, Date, -Size)
SZ[, size_pct := (seq_len(.N) - 0.5)/.N, by = Date]   # 0=최대형, 1=최소형
w_dec <- cells$cell1_LS_decile$W
w_dec[, leg := fifelse(w > 0, "winner", "loser")]
SZL <- merge(w_dec[, .(Date, Ticker, leg)], SZ[, .(Date, Ticker, size_pct)], by = c("Date","Ticker"))
fp_b <- SZL[, .(n = .N, size_pct_mean = mean(size_pct), size_pct_median = median(size_pct)), by = leg]
fp_b_monthly <- SZL[, .(mp = mean(size_pct)), by = .(Date, leg)]
fp_b_wide <- dcast(fp_b_monthly, Date ~ leg, value.var = "mp")
fp_b_test <- list(
  loser_minus_winner_size_pct = mean(fp_b_wide$loser - fp_b_wide$winner, na.rm = TRUE),
  nw_t = nw_t1(fp_b_wide$loser - fp_b_wide$winner),
  loser_minus_universe = mean(fp_b_wide$loser, na.rm = TRUE) - 0.5,
  nw_t_vs_universe = nw_t1(fp_b_wide$loser - 0.5),
  interpretation = "size_pct 는 0=최대형/1=최소형. 양(+) & |t|>=2 이면 패자 데실 소형 편중(지문 (b) 성립)")

## ─────────────────────────────────────────────────────────────────────────────
## 4. 국면 셀-특정 검정 — 약화가 숏 보유 셀(1·3)에만 나타나는가
## ─────────────────────────────────────────────────────────────────────────────
regime_by_cell <- rbindlist(lapply(names(cells), function(nm) {
  pr <- merge(cells[[nm]]$pr, B[, .(date = Date, regime)], by = "date")
  pr[, act := ret_net - benchmark_ret]
  pr[, .(cell = nm, n = .N, active_ann = 12*mean(act), nw_t = nw_t1(act),
         ret_net_ann = 12*mean(ret_net)), by = regime]
}))
regime_wide <- dcast(regime_by_cell, regime ~ cell, value.var = "active_ann")

## ─────────────────────────────────────────────────────────────────────────────
## 5. 무신호 대조 (롱온리 셀 2·4 의무) — ★홀딩월 라벨 정렬 + 대조군 beta 검증
##    cells$*$pr$date = 시그널 월말 d, Ret_1m = 홀딩월(m+1) 수익 → 라벨은 m+1
## ─────────────────────────────────────────────────────────────────────────────
sig_dates <- cells$cell4_LO_top25$pr$date
hold_ym <- format(as.Date(vapply(sig_dates, function(d) {
  as.character(seq(as.Date(format(d, "%Y-%m-01")), by = "month", length.out = 2)[2]) }, character(1))), "%Y-%m")
ctl_v10 <- build_no_signal_control(months = hold_ym, n_stocks = 25L, cap = 1.0, freq = 1L, bps = 15)
ctl_020 <- build_no_signal_control(months = hold_ym, n_stocks = 25L, cap = 0.20, freq = 1L, bps = 15)
bm_v <- cells$cell4_LO_top25$pr$benchmark_ret
ctl_beta_check <- list(
  v10_cap1_beta = as.numeric(beta_alpha(ctl_v10$ret, bm_v)["beta"]),
  cap020_beta   = as.numeric(beta_alpha(ctl_020$ret, bm_v)["beta"]),
  note = "대조군 beta 가 1 근처가 아니면 홀딩월 라벨 정렬 결함 (1/20 실사고 재발 검사)")
ns_gate <- lapply(c("cell2_LO_decile","cell4_LO_top25"), function(nm) {
  g1 <- no_signal_gate(cells[[nm]]$pr$ret_net, ctl_v10$ret, bm_v)
  g2 <- no_signal_gate(cells[[nm]]$pr$ret_net, ctl_020$ret, bm_v)
  list(cell = nm,
       vs_cap1_00 = list(n = g1$n, diff_ann = g1$diff_ann, diff_nw_t = g1$diff_nw_t,
                         corr = g1$corr, verdict = g1$verdict,
                         strategy = as.list(g1$strategy), control = as.list(g1$control)),
       vs_cap0_20 = list(n = g2$n, diff_ann = g2$diff_ann, diff_nw_t = g2$diff_nw_t,
                         corr = g2$corr, verdict = g2$verdict))
})
names(ns_gate) <- c("cell2_LO_decile","cell4_LO_top25")

## ─────────────────────────────────────────────────────────────────────────────
## 6. Advisory 배터리 — rank IC / ICIR / monotonicity / subperiod / turnover / DSR
## ─────────────────────────────────────────────────────────────────────────────
SR_ <- merge(S, R[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
ic <- SR_[, .(ic = suppressWarnings(cor(score, Ret_1m, method = "spearman")), n = .N), by = Date][is.finite(ic)]
rank_ic <- mean(ic$ic); icir <- rank_ic/sd(ic$ic)
ic_t_nw <- nw_t1(ic$ic)
# 데실 단조성: 월별 10분위 평균 수익 → 분위 순위와 평균수익의 Spearman
SR_[, dq := as.integer(cut(frank(score, ties.method = "average")/.N, breaks = seq(0,1,0.1),
                           include.lowest = TRUE)), by = Date]
dprof <- SR_[, .(r = mean(Ret_1m)), by = .(Date, dq)][, .(r_ann = 12*mean(r)), by = dq][order(dq)]
monotonicity <- suppressWarnings(cor(dprof$dq, dprof$r_ann, method = "spearman"))
# subperiod (cell4 활성수익)
pr4 <- copy(cells$cell4_LO_top25$pr); pr4[, act := ret_net - benchmark_ret]
pr4[, sub := fifelse(date < as.Date("2013-01-01"), "P1_2005_2012",
             fifelse(date < as.Date("2020-01-01"), "P2_2013_2019", "P3_2020_2026"))]
subper <- pr4[, .(n = .N, active_ann = 12*mean(act), nw_t = nw_t1(act),
                  sr = mean(act)/sd(act)*sqrt(12)), by = sub][order(sub)]
subperiod_stability <- mean(subper$active_ann > 0)
# OOS retention 근사 (anchored 3분할 중앙값) — 진단
oos_rough <- function(a, frac = c(0.55,0.65,0.75)) {
  n <- length(a); sr1 <- function(x) if (length(x)<6) NA_real_ else mean(x)/sd(x)*sqrt(12)
  median(vapply(frac, function(f){k<-floor(n*f); i<-sr1(a[1:k]); o<-sr1(a[(k+1):n])
    if (!is.finite(i)||i<=0||!is.finite(o)) NA_real_ else o/i}, numeric(1)), na.rm = TRUE) }
# DSR (Bailey-Lopez de Prado) — 진단 전용. selection_type="chain" 이라 게이트 아님
dsr <- function(a, n_trials) {
  sr <- mean(a)/sd(a); n <- length(a)
  g3 <- mean(((a-mean(a))/sd(a))^3); g4 <- mean(((a-mean(a))/sd(a))^4)
  em <- 0.5772156649
  sr0 <- sqrt(1/n)*((1-em)*qnorm(1-1/n_trials) + em*qnorm(1-1/(n_trials*exp(1))))
  pnorm(((sr - sr0)*sqrt(n-1))/sqrt(1 - g3*sr + (g4-1)/4*sr^2)) }
adv <- list(
  rank_ic = rank_ic, icir = icir, rank_ic_t_nw_lag3 = ic_t_nw, n_ic_months = nrow(ic),
  harvey_hurdle_note = "rank-IC t 는 advisory. 판정 권위 = portfolio-alpha t (measurement-graduation §3)",
  monotonicity_spearman = monotonicity,
  decile_profile_ann = as.list(setNames(dprof$r_ann, paste0("D", dprof$dq))),
  subperiod = subper, subperiod_stability = subperiod_stability,
  oos_retention_approx = list(
    cell4 = oos_rough(pr4$act),
    cell2 = { p <- copy(cells$cell2_LO_decile$pr); oos_rough(p$ret_net - p$benchmark_ret) }),
  dsr_diagnostic = list(
    cell4 = dsr(pr4$act, n_trials = 4L),
    n_trials = 4L, selection_type = "chain",
    note = "사전등록 4셀 직교 설계 — argmax/threshold-pick 아님. DSR 게이트 부적용(measurement-graduation §3)"),
  turnover_annual = setNames(lapply(names(cells), function(nm) cells[[nm]]$turnover_annual), names(cells)))

out <- list(
  regime_definition = list(
    method = "사후 귀속 라벨 — 벤치 실현수익 + 시그널시점 낙폭(dd_prior, 과거만). 오버레이 미적용(S0/S1 금지 준수). 어떤 셀의 비중도 이 라벨을 쓰지 않는다.",
    crisis = "홀딩월 BM 수익 하위 20%", recovery = "dd_prior <= -20% & BM 수익 > 0",
    expansion = "dd_prior > -10% & BM 수익 > 0", neutral = "그 외",
    counts = regime_n),
  fingerprint_a_short_leg_rebound = list(by_regime = fp_a, overall = fp_a_overall, test = fp_a_test),
  fingerprint_b_loser_small_tilt = list(by_leg = fp_b, test = fp_b_test),
  regime_cell_specific = list(long = regime_by_cell, wide = regime_wide),
  no_signal_control = list(control_beta_check = ctl_beta_check,
                           control_spec_v10 = ctl_v10$spec, gates = ns_gate),
  advisory_battery = adv)
write_json(out, file.path(OUT, "s3_diag.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
saveRDS(list(B=B, LD=LD, fp_b_wide=fp_b_wide, ctl_v10=ctl_v10, ic=ic, dprof=dprof), file.path(OUT,"s3_objects.rds"))

cat("\n=== REGIME COUNTS ===\n"); print(regime_n)
cat("\n=== FP(a) 숏 레그 국면별 (연환산) ===\n"); print(fp_a)
cat("\n=== FP(a) overall ===\n"); print(fp_a_overall)
cat(sprintf("\nFP(a) recovery 더미: coef=%+.5f/월 t=%+.3f (base %+.5f)\n",
            fp_a_test$coef_recovery_monthly, fp_a_test$t_recovery, fp_a_test$base_monthly))
cat("\n=== FP(b) size_pct (0=최대형,1=최소형) ===\n"); print(fp_b)
cat(sprintf("loser-winner=%+.4f (NW-t %+.3f) | loser-universe=%+.4f (NW-t %+.3f)\n",
            fp_b_test$loser_minus_winner_size_pct, fp_b_test$nw_t,
            fp_b_test$loser_minus_universe, fp_b_test$nw_t_vs_universe))
cat("\n=== REGIME x CELL (active_ann) ===\n"); print(regime_wide)
cat(sprintf("\n=== 무신호 대조군 beta: cap1.00=%.3f · cap0.20=%.3f (1 근처여야 정상) ===\n",
            ctl_beta_check$v10_cap1_beta, ctl_beta_check$cap020_beta))
for (nm in names(ns_gate)) cat(sprintf("%-16s vs cap1.00: diff=%+.2f%%/yr NW-t=%+.3f cor=%.3f -> %s\n",
  nm, 100*ns_gate[[nm]]$vs_cap1_00$diff_ann, ns_gate[[nm]]$vs_cap1_00$diff_nw_t,
  ns_gate[[nm]]$vs_cap1_00$corr, ns_gate[[nm]]$vs_cap1_00$verdict))
cat(sprintf("\n=== ADVISORY: rank_ic=%.4f icir=%.3f ic_t_nw=%.3f mono=%.3f subper_stab=%.2f oos4=%.3f dsr4=%.3f\n",
  rank_ic, icir, ic_t_nw, monotonicity, subperiod_stability, adv$oos_retention_approx$cell4, adv$dsr_diagnostic$cell4))
cat("\n=== decile profile (ann) ===\n"); print(dprof)
cat("\n=== subperiod (cell4 active) ===\n"); print(subper)
