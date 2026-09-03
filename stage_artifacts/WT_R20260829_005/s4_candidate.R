# S4 — 단일 실투형 후보 1건 (도훈 지시 2026-08-29: arm 배터리 폐지)
#   사양: value(BE/ME, contemporaneous ME) + momentum(6-1) 시장-내 pct-rank 50/50 평균
#         -> 단일 top-25 롱온리 EW · K200 U KQ150 · 15bps · Sw=1 · 월간 리밸 · 유동성 2e8(t-1)
#   측정: canonical_screen_bt (계약 경로) — metric_type="canonical_screen" (판정 권위 아님)
#   병기: beta-통제 alpha (measurement-graduation 2) · Calmar/MDD/CAGR 좌표 · 12-1 지평 민감도
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite); library(sandwich); library(lmtest)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_005")
P <- readRDS(file.path(OUT, "panel.rds"))
MOM <- P$MOM; V01 <- P$V01; mem <- P$mem; fwd <- P$fwd; SIZE <- P$SIZE
R <- fwd$returns_dt; LIQ <- fwd$liq_dt; bench <- fwd$bench_dt
COST_BPS <- 15; PPY <- 12L; TOP_N <- 25L; LIQ_MIN <- 2e8

beta_alpha <- function(x, b) {
  k <- which(is.finite(x) & is.finite(b)); x <- x[k]; b <- b[k]
  f <- lm(x ~ b); ct <- coeftest(f, vcov = NeweyWest(f, lag = 3, prewhite = FALSE))
  list(alpha_ann = 12*ct[1,1], t_alpha = ct[1,3], beta = ct[2,1], t_beta = ct[2,3],
       beta_contrib_ann = (ct[2,1]-1)*12*mean(b), n = length(x)) }
risk_coords <- function(r) {
  nav <- cumprod(1 + r); mdd <- min(nav/cummax(nav) - 1)
  cagr <- nav[length(nav)]^(12/length(r)) - 1
  list(cagr = cagr, mdd = mdd, calmar = cagr/abs(mdd),
       sr_total = mean(r)/sd(r)*sqrt(12), vol_ann = sd(r)*sqrt(12)) }

## ── 정의역 (실투형 envelope) ────────────────────────────────────────────────
liq_ok <- LIQ[is.finite(adv) & adv >= LIQ_MIN, .(Date, Ticker, adv)]
E <- merge(mem, MOM, by = c("Date","Ticker"))
E <- merge(E, V01, by = c("Date","Ticker"))
E <- merge(E, liq_ok, by = c("Date","Ticker"))
E <- E[is.finite(v01) & is.finite(mom61)]
pctr <- function(x) (frank(x, ties.method = "average") - 0.5)/length(x)
E[, `:=`(pv = pctr(v01), pm61 = pctr(mom61)), by = .(Date, mkt)]
E[is.finite(mom121), pm121 := pctr(mom121), by = .(Date, mkt)]
E[, score      := 0.5*pv + 0.5*pm61]                                  # PRODUCTION
E[, score_p121 := fifelse(is.finite(pm121), 0.5*pv + 0.5*pm121, NA_real_)]  # 지평 민감도
cat(sprintf("[S4] domain: %d rows | %d months | median names %.0f (K200 %.0f / KQ150 %.0f)\n",
            nrow(E), uniqueN(E$Date), median(E[, .N, by = Date]$N),
            median(E[mkt=="K200", .N, by = Date]$N), median(E[mkt=="KQ150", .N, by = Date]$N)))

run_cand <- function(scol, tag) {
  S <- E[is.finite(get(scol)), .(Date, Ticker, score = get(scol))]
  cs <- canonical_screen_bt(S, R, bench, top_n = TOP_N, cost_bps_oneway = COST_BPS,
                            liq_dt = NULL, run_id = tag, strategy_id = tag,
                            diag_dual_basis = TRUE, size_dt = SIZE)
  pr <- as.data.table(cs$period_returns)
  ba <- beta_alpha(pr$ret_net, pr$benchmark_ret)
  rc <- risk_coords(pr$ret_net)
  rcb <- risk_coords(pr$benchmark_ret)
  act <- pr$ret_net - pr$benchmark_ret
  ## 보유 (n_max 계약 확인)
  SS <- copy(S); setorder(SS, Date, -score)
  W <- SS[, { k <- min(TOP_N, .N); .(Ticker = Ticker[seq_len(k)]) }, by = Date]
  Wm <- merge(W, unique(E[, .(Date, Ticker, mkt)]), by = c("Date","Ticker"), all.x = TRUE)
  list(cs = cs, pr = pr, beta_alpha = ba, risk = rc, bench_risk = rcb,
       n_names_max = max(W[, .N, by = Date]$N), n_names_med = median(W[, .N, by = Date]$N),
       mkt_mix_kq150 = mean(Wm$mkt == "KQ150", na.rm = TRUE),
       active_sr = mean(act)/sd(act)*sqrt(12), mean_active_ann = 12*mean(act), W = W) }

cand  <- run_cand("score", "AMP2013_valmom_rankavg_top25")
sens  <- run_cand("score_p121", "AMP2013_valmom_MOM2_12_top25")

## ── OOS retention 근사 (anchored 3분할 {55/65/75} 중앙값 — 활성 SR OOS/IS) ──
oos_ret <- function(pr) {
  a <- pr$ret_net - pr$benchmark_ret; n <- length(a)
  v <- vapply(c(.55,.65,.75), function(f) { k <- floor(n*f)
    si <- mean(a[1:k])/sd(a[1:k]); so <- mean(a[(k+1):n])/sd(a[(k+1):n])
    if (!is.finite(si) || si <= 0) NA_real_ else so/si }, numeric(1))
  list(splits = v, median = median(v, na.rm = TRUE)) }
oo <- oos_ret(cand$pr)

## ── period_returns 저장 (신호월 라벨 명시 + 벤치마크) ──────────────────────
PRO <- copy(cand$pr)
setnames(PRO, "date", "signal_date")
PRO[, `:=`(signal_ym = format(signal_date, "%Y-%m"),
           holding_ym = format(seq_len(.N), nsmall = 0))]
PRO[, holding_ym := format(as.Date(vapply(signal_date, function(d)
  as.character(seq(as.Date(format(d, "%Y-%m-01")), by = "month", length.out = 2)[2]), character(1))), "%Y-%m")]
PRO[, active_net := ret_net - benchmark_ret]
setcolorder(PRO, c("signal_date","signal_ym","holding_ym","ret_net","benchmark_ret","active_net"))
fwrite(PRO, file.path(OUT, "period_returns_production.csv"))

pack <- function(x, tag) list(
  id = tag, metric_type = "canonical_screen", n_months = x$cs$n_months,
  n_names_max = x$n_names_max, n_names_median = x$n_names_med, kq150_share = x$mkt_mix_kq150,
  portfolio_alpha_t_nw_lag3 = x$cs$portfolio_alpha_t_nw_lag3,
  portfolio_alpha_t_pvalue = x$cs$portfolio_alpha_t_pvalue,
  information_ratio = x$cs$information_ratio, alpha_annualized = x$cs$alpha_annualized,
  net_sr_active = x$cs$net_sr, mean_active_net_ann = x$mean_active_ann,
  turnover_annual = x$cs$turnover_annual, selected_ret_coverage = x$cs$selected_ret_coverage,
  beta_controlled_alpha = x$beta_alpha,
  total_return_coords = x$risk, benchmark_coords = x$bench_risk,
  diag_ew_universe = list(port_t = x$cs$diag_ew_universe$portfolio_alpha_t_nw_lag3,
                          alpha_ann = x$cs$diag_ew_universe$alpha_annualized,
                          ir = x$cs$diag_ew_universe$information_ratio,
                          n_months = x$cs$diag_ew_universe$n_months),
  diag_cap_tier = if (isTRUE(x$cs$diag_cap_tier$available))
    list(weight_share_avg = x$cs$diag_cap_tier$weight_share_avg,
         contrib_gross_annualized = x$cs$diag_cap_tier$contrib_gross_annualized) else list(available = FALSE),
  liq_ruler = x$cs$liq_ruler, liq_ruler_source = x$cs$liq_ruler_source)

res <- list(
  meta = list(wt_id = "WT-R20260829_005", stage = "single_production_candidate",
    discipline_note = "도훈 지시 2026-08-29 — arm 배터리 폐지. 한 시도 = 실투형 후보 하나.",
    spec = list(value = "V01_BM (BE/ME, contemporaneous ME) via load_month_factors() [C15/C13/C14]",
                momentum_primary = "6-1 (t-2..t-7 로그누적, 기저 fe_jt1993_momentum.R 승계)",
                momentum_paper_fidelity = "MOM2-12 (t-2..t-13) — AMP2013 원문 정의, 지평 민감도로만 병기",
                combination = "시장-내(K200/KQ150) pct-rank 후 고정 50/50 평균 (rank_average · 가중 탐색 0)",
                selection = "pooled top-25", weighting = "EW (Sw=1, 개별 상한 없음 — v10)",
                cost = "15bps one-way delta (v2.4_kr_retail_15bps)", rebalance = "monthly",
                liquidity = "20d avg turnover value (t-1) >= 2e8 KRW, 랭킹 前 적용")),
  candidate = pack(cand, "AMP2013_valmom_rankavg_top25"),
  horizon_sensitivity_preregistered = pack(sens, "AMP2013_valmom_MOM2_12_top25"),
  sign_agreement = list(
    rule = "설계 사전고정: 두 지평 arm 의 부호가 갈리면 '미결(지평 민감)'",
    primary_beta_alpha = cand$beta_alpha$alpha_ann, fidelity_beta_alpha = sens$beta_alpha$alpha_ann,
    signs_agree = sign(cand$beta_alpha$alpha_ann) == sign(sens$beta_alpha$alpha_ann)),
  oos_retention_approx = oo,
  artifacts = list(period_returns_csv = "stage_artifacts/WT_R20260829_005/period_returns_production.csv"))
write_json(res, file.path(OUT, "s4_candidate.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
saveRDS(list(E = E, cand = cand, sens = sens), file.path(OUT, "s4_objects.rds"))

pp <- function(x, nm) { cat(sprintf(
  "%-34s n=%3d nmax=%2d | PORT_t=%+6.3f p=%.4f | a=%+6.2f%%/yr t(a)=%+6.3f b=%.3f(t %.2f) | IR=%+.3f actSR=%+.3f\n",
  nm, x$cs$n_months, x$n_names_max, x$cs$portfolio_alpha_t_nw_lag3, x$cs$portfolio_alpha_t_pvalue,
  100*x$beta_alpha$alpha_ann, x$beta_alpha$t_alpha, x$beta_alpha$beta, x$beta_alpha$t_beta,
  x$cs$information_ratio, x$active_sr))
  cat(sprintf("%-34s CAGR=%.2f%% MDD=%.2f%% Calmar=%.3f SR(total)=%.3f | TO=%.2fx/yr | EWuniv_t=%+6.3f | cap OTHER=%.3f | KQ150=%.1f%%\n",
  "", 100*x$risk$cagr, 100*x$risk$mdd, x$risk$calmar, x$risk$sr_total, x$cs$turnover_annual,
  x$cs$diag_ew_universe$portfolio_alpha_t_nw_lag3,
  if (isTRUE(x$cs$diag_cap_tier$available)) x$cs$diag_cap_tier$weight_share_avg$OTHER else NA_real_,
  100*x$mkt_mix_kq150)) }
cat("\n===== PRODUCTION CANDIDATE (canonical_screen, net 15bps) =====\n")
pp(cand, "combo 50/50 · mom 6-1 [PRIMARY]")
pp(sens, "combo 50/50 · MOM2-12 [fidelity]")
cat(sprintf("\n[BENCH] CAGR=%.2f%% MDD=%.2f%% SR=%.3f\n",
            100*cand$bench_risk$cagr, 100*cand$bench_risk$mdd, cand$bench_risk$sr_total))
cat(sprintf("[OOS] retention splits = %s | median = %.3f\n",
            paste(sprintf("%.3f", oo$splits), collapse = " / "), oo$median))
