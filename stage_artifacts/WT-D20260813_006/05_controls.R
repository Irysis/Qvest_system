## WT-D20260813_006 / FQ-234 Lane B — 사전등록 통제군 + 분해 진단
##  A. AR(1)-정합 placebo 밴드 (rho=0.8315, 200 draw)
##  B. 양성 대조 PC1 = 반-오라클(실현 rank-IC 0.04) — '조작이 먹는다' 실증
##  C. cap-tier 분해 (CH5 상속 리스크 확인)
##  D. 분위 프로파일 + 평균 vs 중앙값 (IC->PORT_t 전이 진단)
##  E. NW 팽창 실측 + 검정력 재산출 / F. screening 게이트 / G. 역방향 사후 진단(라벨)
suppressMessages({ library(data.table); library(arrow) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260813_006")
if (!exists("build_benchmark_compare")) source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/required_effect_size.R")
set.seed(20260822)
J <- list(); TOPN <- 25L; NDRAW <- 200L; RHO <- 0.8315

P <- as.data.table(read_parquet(file.path(OUT, "absorb_panel.parquet"))); P[, Date := as.Date(Date)]
fwd <- readRDS(file.path(OUT, "fwd.rds"))
RET <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
BEN <- fwd$bench_dt[, .(Date = as.Date(Date), BM_Ret)]
LIQ <- fwd$liq_dt[, .(Date = as.Date(Date), Ticker, adv)]
setattr(LIQ, "liq_ruler", attr(fwd$liq_dt,"liq_ruler",exact=TRUE))
setattr(LIQ, "liq_ruler_source", attr(fwd$liq_dt,"liq_ruler_source",exact=TRUE))
SIZE <- P[, .(Date, Ticker, Size)]
valid_sig <- sort(unique(RET$Date)); valid_sig <- valid_sig[valid_sig < as.Date("2026-06-01")]
P <- P[Date %in% valid_sig]; RET <- RET[Date %in% valid_sig]; BEN <- BEN[Date %in% valid_sig]
LIQ <- LIQ[Date %in% valid_sig]; SIZE <- SIZE[Date %in% valid_sig]
ALPHA <- readRDS(file.path(OUT, "alpha_variants.rds"))
WIN <- list(long = as.Date(c("2000-01-01","2026-06-01")), clean = as.Date(c("2015-07-01","2026-06-01")))
in_win <- function(d, w) d >= WIN[[w]][1] & d < WIN[[w]][2]
ELIG <- merge(P[, .(Date, Ticker)], LIQ, by = c("Date","Ticker"), all.x = TRUE)[is.na(adv) | adv >= 2e8][, .(Date, Ticker)]

run_screen <- function(S, w, tag, diag = FALSE) {
  s <- S[in_win(Date, w)]; r <- RET[in_win(Date, w)]; b <- BEN[in_win(Date, w)]
  l <- LIQ[in_win(Date, w)]; setattr(l,"liq_ruler",attr(LIQ,"liq_ruler",exact=TRUE))
  setattr(l,"liq_ruler_source",attr(LIQ,"liq_ruler_source",exact=TRUE))
  suppressWarnings(canonical_screen_bt(s, r, b, top_n = TOPN, cost_bps_oneway = 15,
    liq_dt = l, liq_min = 2e8, size_dt = if (diag) SIZE[in_win(Date, w)] else NULL,
    run_id = paste0("FQ234_", tag), strategy_id = paste0("FQ234_", tag), diag_dual_basis = diag))
}

## ══════ A. AR(1)-정합 placebo ══════════════════════════════════════════════
mk_ar1_placebo <- function(w) {
  U <- ELIG[in_win(Date, w)]
  dts <- sort(unique(U$Date)); tk <- sort(unique(U$Ticker))
  nt <- length(tk); z <- rnorm(nt); sd_e <- sqrt(1 - RHO^2)
  Zl <- vector("list", length(dts))
  for (i in seq_along(dts)) { z <- RHO * z + sd_e * rnorm(nt); Zl[[i]] <- data.table(Date = dts[i], Ticker = tk, score = z) }
  merge(rbindlist(Zl), U, by = c("Date","Ticker"))
}
J$placebo <- list()
for (w in c("long","clean")) {
  ts <- numeric(NDRAW)
  for (k in seq_len(NDRAW)) {
    cs <- run_screen(mk_ar1_placebo(w), w, paste0("plc", k))
    ts[k] <- if (is.null(cs$portfolio_alpha_t_nw_lag3)) NA_real_ else cs$portfolio_alpha_t_nw_lag3
  }
  ts <- ts[is.finite(ts)]
  obs <- if (w == "long") -0.318002 else -2.185049
  J$placebo[[w]] <- list(rho_used = RHO, n_draw = length(ts),
    mean = mean(ts), sd = sd(ts),
    q025 = as.numeric(quantile(ts,.025)), q05 = as.numeric(quantile(ts,.05)),
    q50 = as.numeric(quantile(ts,.50)),
    q95 = as.numeric(quantile(ts,.95)), q975 = as.numeric(quantile(ts,.975)),
    abs_q95 = as.numeric(quantile(abs(ts),.95)),
    observed_primary_port_t = obs,
    p_two_sided = mean(abs(ts) >= abs(obs)),
    verdict = if (mean(abs(ts) >= abs(obs)) < 0.05) "OUTSIDE_NULL_BAND" else "INSIDE_NULL_BAND")
  cat("[placebo]", w, "done\n")
}

## ══════ B. 양성 대조 PC1 — 반-오라클 (실현 rank-IC 를 목표치로 보정) ═══════
mk_semi_oracle <- function(w, target_ic = 0.04) {
  M <- merge(ELIG[in_win(Date, w)], RET, by = c("Date","Ticker"))
  M[, rk := (frank(Ret_1m) - 0.5)/.N, by = Date]
  M[, rk := qnorm(pmin(pmax(rk, 1e-6), 1-1e-6))]
  ## score = a*rk + sqrt(1-a^2)*noise ; spearman(score, ret) ~ a (근사) -> a 이분탐색
  lo <- 0; hi <- 1
  for (it in 1:22) {
    a <- (lo + hi)/2
    M[, sc := a * rk + sqrt(1 - a^2) * rnorm(.N)]
    ic <- M[, if (.N >= 20) .(ic = cor(sc, Ret_1m, method="spearman")) else .(ic=NA_real_), by = Date]
    m <- mean(ic$ic, na.rm = TRUE)
    if (m < target_ic) lo <- a else hi <- a
  }
  list(S = M[, .(Date, Ticker, score = sc)], a = a, realized_ic = m)
}
J$positive_control <- list()
for (w in c("long","clean")) {
  so <- mk_semi_oracle(w, 0.04)
  cs <- run_screen(so$S, w, paste0("PC1_", w))
  J$positive_control[[w]] <- list(target_rank_ic = 0.04, realized_rank_ic = so$realized_ic,
    loading_a = so$a, port_t = cs$portfolio_alpha_t_nw_lag3, IR = cs$information_ratio,
    alpha_ann = cs$alpha_annualized, net_sr = cs$net_sr,
    exceeds_placebo_q95 = cs$portfolio_alpha_t_nw_lag3 > J$placebo[[w]]$q95,
    note = "rank-IC 0.04(저장소 advisory 하한) 강도의 신호가 이 창/파이프라인에서 검출되는가 = 검정력 실증")
  cat("[PC1]", w, "port_t", cs$portfolio_alpha_t_nw_lag3, "\n")
}

## ══════ C. cap-tier 분해 (CH5) ═════════════════════════════════════════════
J$cap_tier <- list()
for (w in c("long","clean")) {
  cs <- run_screen(ALPHA$primary, w, paste0("primary_capdiag_", w), diag = TRUE)
  J$cap_tier[[w]] <- cs$diag_cap_tier
}

## ══════ D. 분위 프로파일 + 평균 vs 중앙값 ═════════════════════════════════
qprof <- function(w) {
  M <- merge(ALPHA$primary[in_win(Date, w)], RET, by = c("Date","Ticker"))
  Q <- M[, { g <- cut(frank(score), breaks = 5, labels = FALSE)
             as.list(setNames(vapply(1:5, function(i) mean(Ret_1m[g==i], na.rm=TRUE), 0), paste0("q",1:5))) }, by = Date]
  prof_mean <- vapply(paste0("q",1:5), function(c) mean(Q[[c]], na.rm=TRUE), 0)
  prof_med  <- vapply(paste0("q",1:5), function(c) median(Q[[c]], na.rm=TRUE), 0)
  sp <- Q$q5 - Q$q1
  ## 스피어만 IC 의 월별 계열 (score vs fwd)
  ic <- M[, if (.N>=20 && sd(score)>0) .(ic = cor(score, Ret_1m, method="spearman")) else .(ic=NA_real_), by=Date]
  list(profile_mean_monthly = as.list(prof_mean), profile_median_monthly = as.list(prof_med),
       spread_mean = mean(sp, na.rm=TRUE), spread_median = median(sp, na.rm=TRUE),
       spread_frac_pos = mean(sp > 0, na.rm=TRUE),
       monotone_mean = all(diff(prof_mean) > 0) || all(diff(prof_mean) < 0),
       monotone_median = all(diff(prof_med) > 0) || all(diff(prof_med) < 0),
       rank_ic_mean = mean(ic$ic, na.rm=TRUE), rank_ic_median = median(ic$ic, na.rm=TRUE),
       note = "score = z(-absorb). q5 = absorb 최저. 평균과 중앙값 부호가 갈리면 = 랭크 정보가 평균 소비로 전이되지 않는 구조")
}
J$quintile_profile <- list()
for (w in c("long","clean")) J$quintile_profile[[w]] <- qprof(w)

## ══════ E. NW 팽창 실측 + 검정력 재산출 ═══════════════════════════════════
active_series <- function(S, w) {
  cs <- run_screen(S, w, "aser")
  bc <- cs$benchmark_compare
  NULL
}
## 실계열: primary top-25 월 active(net) — canonical 내부와 동일 규칙 재구성 대신
## 무작위 바스켓 계열로 NW 팽창을 실측(외부 기준 유지)
rand_active <- function(w, n_draw = 60L) {
  U <- merge(ELIG[in_win(Date, w)], RET, by = c("Date","Ticker")); U <- merge(U, BEN, by = "Date")
  infl <- numeric(n_draw)
  for (k in seq_len(n_draw)) {
    pk <- U[, .(r = mean(Ret_1m[sample.int(.N, min(TOPN,.N))]), b = BM_Ret[1]), by = Date]
    infl[k] <- nw_inflation_measured(pk$r - pk$b, lag = 3L)
  }
  infl[is.finite(infl)]
}
J$nw_inflation <- list()
for (w in c("long","clean")) {
  z <- rand_active(w)
  n <- if (w=="long") 315L else 131L
  sdm <- if (w=="long") 0.045296 else 0.048478
  re <- required_effect(n = n, t_threshold = 2.95, sd_monthly = sdm, nw_inflation = median(z))
  re2 <- required_effect(n = n, t_threshold = 2.0, sd_monthly = sdm, nw_inflation = median(z))
  J$nw_inflation[[w]] <- list(measured_median = median(z), measured_q05 = as.numeric(quantile(z,.05)),
    measured_q95 = as.numeric(quantile(z,.95)), contract_assumed_default = NW_INFLATION_DEFAULT,
    required_annual_t295_remeasured = re$required_annual,
    required_annual_t2_remeasured = re2$required_annual)
}

## ══════ F. screening 게이트 (transition_gates cond2) ══════════════════════
J$screen_gate <- list()
for (w in c("long","clean")) {
  cs <- run_screen(ALPHA$primary, w, paste0("gate_", w))
  J$screen_gate[[w]] <- list(net_sr = cs$net_sr, alpha_ann = cs$alpha_annualized,
    port_t = cs$portfolio_alpha_t_nw_lag3,
    screen_pass_sr_branch = isTRUE(cs$net_sr >= 0.7),
    note = "screen_pass = no-PIT AND ([SR>=0.7 AND CAGR>=12%] OR [score>=40 AND SR>=0.5]). net_sr 음수 => 두 분기 모두 미충족")
}

## ══════ G. 역방향 사후 진단 (★사전등록 아님 — 주장 금지, 라벨 필수) ═══════
J$posthoc_reverse <- list(
  label = "POSTHOC_NOT_PREREGISTERED — C13(FLIP_SIGN 금지)/INV-7 상 본 라운드의 결론 아님. 다음 라운드 사전등록 재료로만.",
  result = list())
for (w in c("long","clean")) {
  Arev <- copy(ALPHA$primary)[, score := -score]
  cs <- run_screen(Arev, w, paste0("rev_", w), diag = TRUE)
  J$posthoc_reverse$result[[w]] <- list(port_t = cs$portfolio_alpha_t_nw_lag3,
    IR = cs$information_ratio, alpha_ann = cs$alpha_annualized, net_sr = cs$net_sr,
    turnover_annual = cs$turnover_annual,
    ew_t = tryCatch(cs$diag_ew_universe$portfolio_alpha_t_nw_lag3, error=function(e) NA),
    placebo_q95 = J$placebo[[w]]$q95)
}

writeLines(jsonlite::toJSON(J, auto_unbox = TRUE, pretty = TRUE, digits = 6, null = "null"),
           file.path(OUT, "05_controls.json"))
cat("[done] 05_controls.json\n")
