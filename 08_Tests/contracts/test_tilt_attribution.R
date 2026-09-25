# test_tilt_attribution.R — tilt_attribution.R 양방향 검증 (합성 시장 · tempdir 만 씀 · 운영 무접촉)
#
# 계약 (플랜 P2-02 · 2026-09-25):
#   ① 설정 fail-closed — 설정 부재·고정 축 키 부재·결정일 지연 0·유동성 지연 0 = 멈춤
#   ② 하네스 패리티 — replication_harness.R(close_t1·close_d_legacy)가 낸 ret_gross 를 보유 재구성이 1e-10 로 복원(recon)
#   ③ 항등식 — active = Σ성분 + cost + recon (1e-12)
#   ④ 양성 대조(a) EW 유니버스 복제 → 공통 성분(ew_cw)이 활성 분산의 ≥ 설정값 · 적재 평균 ≈ 1 · 선별 t 비유의
#   ⑤ 양성 대조(b) 주입 — 회계판: 선별만 δ·Σw 만큼(1e-12) · 노출 성분 불변 / 시장 수준: 회수율이 설정 띠 안
#   ⑥ 양성 대조(c) 무작위 25종 → 선별 NW-t 위양성률 ≤ 설정값 · 평균 t ≈ 0
#   ⑦ 판별 — 심어 둔 종목 알파를 고른 전략은 선별 t 가 크고 회수, 소형주 틸트만 한 전략은 ew_cw 가 크고 선별 비유의
#   ⑦-b 적재 보정 표(loading_calibration) — 선별에 남은 요인 노출 · 틸트 전략의 알려진 축소 감쇠를 INFO 로 공개(2026-09-25 적대 검증)
#   ⑧ PIT 탐침 PASS(정상 코드 — 양성 대조)
#   ⑨ 위반 주입·돌연변이 — 당일 멤버십 · 유동성 지연 제거 · 창에 t 포함 · β 전기간 추정 · 비중 당일 수익 반영 ·
#      무신호 대조 당일 Size · 가드 제거+지연 0 · EW_U/무신호 대조 집행일 적격(M9·M11 — 2026-09-25 추가, 초판 탐침 사각) → 탐침 red /
#      시장 성분 −1 누락 → 항등식 red / β_e 횡단 소거(M_flat — 초판 대조 전부 통과) → 보정 표 red
#   ⑩ 패리티 — .ta_nw_t(lag 3) = backtest_result_contract.R::.nw_t_mean · retention = essence 분할 그대로
#   ⑪ 쓰기 — out_dir 없으면 멈춤 · 명시 경로에만 JSON+CSV
# 실행: Rscript 08_Tests/contracts/test_tilt_attribution.R  (빈 Renviron 권장 — 운영 QM_ROOT 역류 방지)
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(xts); library(PerformanceAnalytics); library(arrow) })

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
ROOT <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(ROOT, "02_Infrastructure", "contracts", "tilt_attribution.R")))
  stop("검사 앵커 실패 — 자기 위치에서 계약을 찾지 못했다: ", ROOT)
CONTRACT <- file.path(ROOT, "02_Infrastructure/contracts/tilt_attribution.R")
CFG_SRC  <- file.path(ROOT, "02_Infrastructure/contracts/tilt_attribution_config.json")

pass <- 0L; fail <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { pass <<- pass + 1L; cat(sprintf("  [PASS] %s %s\n", name, detail)) }
  else { fail <<- fail + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
expect_stop <- function(name, expr, pat = NULL) {
  e <- tryCatch({ force(expr); NULL }, error = function(e) conditionMessage(e))
  chk(name, !is.null(e) && (is.null(pat) || grepl(pat, e)), if (is.null(e)) "(멈추지 않음)" else sprintf("(%s)", substr(e, 1, 90)))
}

TMP <- file.path(tempdir(), paste0("ta_test_", Sys.getpid()))
dir.create(TMP, recursive = TRUE, showWarnings = FALSE)
TROOT <- file.path(TMP, "root")
for (d in c("06_Registry", "02_Infrastructure/contracts", ".cache", "04_Research", "stage_artifacts"))
  dir.create(file.path(TROOT, d), recursive = TRUE, showWarnings = FALSE)
FA <- list(fixed_axes = list(long_only = TRUE, n_max = 25L, universe = "K200_KQ150", start_date = "2013-07-01",
                             commission_bps = 15, liq_adv20_min = 2e8, weight_cap = NULL))
writeLines(toJSON(FA, auto_unbox = TRUE, null = "null", pretty = TRUE), file.path(TROOT, "06_Registry/reinforce_program.json"))
cfg0 <- fromJSON(CFG_SRC, simplifyVector = FALSE)
cfg0$loadings$window_market_days <- 126L; cfg0$loadings$min_obs <- 60L       # 합성 표본 길이에 맞춘 창(정의 불변)
wcfg <- function(x, name) { p <- file.path(TMP, name); writeLines(toJSON(x, auto_unbox = TRUE, pretty = TRUE, digits = NA), p); p }
TCFG <- wcfg(cfg0, "cfg.json")

source(CONTRACT)
# 하네스(패리티용) — 실제 t+1 규약과 동일(backtest_harness.R::get_execution_date)
get_execution_date <- function(signal_date, all_dates) {
  ym <- format(signal_date, "%Y-%m"); yr <- as.integer(substr(ym, 1, 4)); mo <- as.integer(substr(ym, 6, 7))
  if (mo == 12) { yr <- yr + 1; mo <- 1 } else { mo <- mo + 1 }
  cands <- all_dates[all_dates >= as.Date(sprintf("%04d-%02d-01", yr, mo))]
  if (length(cands) > 0) min(cands) else NA
}
suppressMessages(source(file.path(ROOT, "02_Infrastructure/replication/replication_harness.R")))

# ── 합성 시장 ──────────────────────────────────────────────────────────────────
#   r_i,t = β_i m_t + γ_i,t g_t + α_i + ε_i,t · g = 소형주 요인(국면에 따라 평균 부호 반전 — EW−CW 벽의 합성판)
#   γ_i,t = −k · z(log Size_i,t−1) — 사이즈 노출은 **전일 시총**의 함수(초판은 최초 시총에 고정해 시총이 흩어지면 벤치의
#   사이즈 노출이 사라졌다 — 비현실 · 교정). 모수 = 실측 목표(2026-09-25 샌드박스 실데이터 상태 · 사전 고정)에 맞춘 값:
#   sd(K200) 1.47% · sd(EW_U−K200) 0.85% · 종목 특이 sd 중앙 2.4%(대형 10종 1.2%) · 무신호 대조 1위 비중 ≈ 0.3.
#   격자 보정 결과(work/calib.R · 목표 거리 최소): sd_m 0.009 · sd_g 0.009 · 상위 2종 log 시총 +2.2/+1.2
#   → 실현 sd(K200) 1.473% · sd(f_e) 0.837% · 대조 1위 비중 중앙 0.336.
#   수락 기준은 보정 전후 불변. 초판 합성(노출 = 최초 시총 고정)에서 나온 EW 복제 β_e 0.74 는 시총이 흩어지며 벤치의 사이즈
#   노출이 사라진 합성 결함이었다 — 저-SNR 세계를 정보 줄로 남겨 그것이 계기의 감쇠가 아님을 보인다(판정 아님).
#   심은 알파 α = 0.0008/일(40종 · 중형) · 메가캡 2종은 후반부 특이 상승 · 결측 0.1%
#   멤버십 = 월초 첫 시장일에 전일 시총 순위로 재편(K200 상위 120 · KQ150 다음 80) · 15% 비유동(거래대금 5e7 < 2e8)
mk_market <- function(seed = 20260925L, n = 260L, start = "2012-01-02", end = "2016-12-30",
                      sd_m = 0.009, sd_g = 0.009, k_g = 0.6, idio_top = 0.012, idio = 0.024,
                      top_logcap_boost = c(2.2, 1.2)) {
  set.seed(seed)
  dates <- seq(as.Date(start), as.Date(end), by = "day"); dates <- dates[!format(dates, "%u") %in% c("6", "7")]
  D <- length(dates); tk <- sprintf("A%06d", seq_len(n))
  logcap0 <- sort(rnorm(n, 0, 1.2), decreasing = TRUE) + log(1e12)
  nb <- length(top_logcap_boost); logcap0[seq_len(nb)] <- logcap0[seq_len(nb)] + top_logcap_boost
  beta <- runif(n, 0.6, 1.4)
  sd_e <- ifelse(seq_len(n) <= 10L, idio_top, idio)
  alpha <- rep(0, n); skilled <- sample(61:200, 40); alpha[skilled] <- 0.0008
  regime <- ifelse(seq_len(D) < D / 2, 1, -1)
  m <- rnorm(D, 0.0003, sd_m); g <- rnorm(D, 0.0004 * regime, sd_g)
  E <- matrix(rnorm(D * n), D, n) * matrix(sd_e, D, n, byrow = TRUE)
  R <- matrix(NA_real_, D, n); Size <- matrix(NA_real_, D, n)
  Size[1, ] <- exp(logcap0); R[1, ] <- 0
  for (t in 2:D) {
    lz <- log(Size[t - 1, ]); z <- (lz - mean(lz)) / stats::sd(lz)
    R[t, ] <- beta * m[t] - k_g * z * g[t] + alpha + E[t, ] + (if (regime[t] < 0) c(0.001, 0.001, rep(0, n - 2)) else 0)
    Size[t, ] <- Size[t - 1, ] * (1 + R[t, ])
  }
  Close <- 10000 * apply(1 + R, 2, cumprod)
  miss <- sample(length(R), round(0.001 * length(R))); R[miss] <- NA
  ym <- format(dates, "%Y-%m"); first <- !duplicated(ym)
  K <- matrix(0, D, n); Q <- matrix(0, D, n); rk <- rank(-Size[1, ])
  for (t in seq_len(D)) { if (t > 1 && first[t]) rk <- rank(-Size[t - 1, ]); K[t, ] <- as.numeric(rk <= 120); Q[t, ] <- as.numeric(rk > 120 & rk <= 200) }
  illiq <- sample(11:n, round(0.15 * n))
  TV <- matrix(ifelse(seq_len(n) %in% illiq, 5e7, 1e9), D, n, byrow = TRUE) * exp(matrix(rnorm(D * n, 0, 0.3), D, n))
  Vol <- TV / Close
  rb <- numeric(D)
  for (t in 2:D) { w <- Size[t - 1, ] * K[t - 1, ]; ok <- w > 0 & is.finite(R[t, ]); rb[t] <- sum(w[ok] * R[t, ok]) / sum(w[ok]) }
  P <- data.table(Date = rep(dates, n), Ticker = rep(tk, each = D), Ret = as.vector(R), Size = as.vector(Size),
                  Close = as.vector(Close), Vol = as.vector(Vol), K200 = as.vector(K), KQ150 = as.vector(Q))
  list(P = P, BM = data.table(Date = dates, BM_Ret = rb), skilled = tk[skilled], illiq = tk[illiq], tk = tk, dates = dates)
}
SYN <- mk_market()
arrow::write_parquet(SYN$P, file.path(TROOT, ".cache/RAWDATA.parquet"))
arrow::write_parquet(SYN$BM, file.path(TROOT, ".cache/benchmark.parquet"))

cat("=== ① 설정 fail-closed ===\n")
expect_stop("설정 부재 → 멈춤", ta_config(TROOT, file.path(TMP, "nope.json")), "설정 부재")
c_bad <- cfg0; c_bad$universe$decision_lag_market_days <- 0L
expect_stop("결정일 지연 0(당일 멤버십) → 멈춤", ta_config(TROOT, wcfg(c_bad, "bad1.json")), "decision_lag")
c_bad <- cfg0; c_bad$universe$liq_lag_rows <- 0L
expect_stop("유동성 지연 0(C10) → 멈춤", ta_config(TROOT, wcfg(c_bad, "bad2.json")), "liq_lag")
c_bad <- cfg0; c_bad$fixed_axes_keys$liq_min <- "no_such_key"
expect_stop("고정 축 키 부재 → 멈춤", ta_config(TROOT, wcfg(c_bad, "bad3.json")), "고정 축 키")
c_bad <- cfg0; c_bad$loadings$window_market_days <- 30L
expect_stop("창 < 최소 관측 → 멈춤", ta_config(TROOT, wcfg(c_bad, "bad4.json")), "min_obs")
cfg <- ta_config(TROOT, TCFG)
chk("고정 축을 원천에서 읽는다(n_max·LIQ·상한 null=없음)", cfg$.fa$n_max == 25L && cfg$.fa$liq_min == 2e8 && is.infinite(cfg$.fa$weight_cap))

mkt <- ta_load_market(TROOT, cfg, from = SYN$dates[1], to = max(SYN$dates))
st <- ta_build_state(mkt, cfg)
chk("비유동 종목은 U 에 들지 않는다(LIQ)", !any(st$U[, st$tickers %in% SYN$illiq]))
chk("U_t = 결정일 t-1 적격(한 시장일 지연)", identical(st$U[-1, ], st$ELIG[-st$D, ]))
kk <- st$cal >= cfg$.fa$start_date
cat(sprintf("  [INFO] 합성 모멘트: sd(K200) %.4f · sd(f_e) %.4f · sd(f_n⊥) %.4f · corr(f_e,f_n⊥) %.3f · 대조 1위 비중 %.2f\n",
            sd(st$rb[kk]), sd(st$fe[kk], na.rm = TRUE), sd(st$fn[kk], na.rm = TRUE), cor(st$fe[kk], st$fn[kk], use = "complete"),
            max(st$NSC_H$Weight)))
chk("무신호 대조 요인이 f_e 와 사전 직교(|corr| < 0.2)", abs(cor(st$fe[kk], st$fn[kk], use = "complete")) < 0.2)
fp <- ta_factor_periods(st, cfg)
chk("요인 구간 요약 — 창 안 구간 × 3요인 유한", nrow(fp) >= 3L && all(is.finite(fp$ann_mean)) && setequal(unique(fp$factor), c("f_m", "f_e", "f_n")))

# ── 전략 보유 생성(시그널일 비중 → 하네스) ────────────────────────────────────
start <- cfg$.fa$start_date
sig_grid <- .ta_month_grid(st$cal, 1L)[st$cal[sig_idx] >= start]
mk_weights <- function(pick, seed) {
  set.seed(seed)
  rbindlist(lapply(seq_len(nrow(sig_grid)), function(k) {
    s <- sig_grid$sig_idx[k]; cand <- which(st$ELIG[s, ]); sel <- pick(cand, s)
    if (!length(sel)) return(NULL)
    data.table(Date = st$cal[s], Ticker = st$tickers[sel], Weight = 1 / length(sel))
  }))
}
W_skill <- mk_weights(function(cand, s) head(cand[st$tickers[cand] %in% SYN$skilled], 25), 1)
W_tilt  <- mk_weights(function(cand, s) { sz <- st$SIZE_L[s, cand]; cand[order(sz)][1:25] }, 2)
W_rand  <- mk_weights(function(cand, s) cand[sample.int(length(cand), 25)], 3)
RAWH <- copy(SYN$P); BMH <- copy(SYN$BM)
write_cell <- function(W, name, exec_price, commission = 0.0015) {
  sim <- run_replication_simulation(copy(RAWH), copy(BMH), W, commission = commission, start_date = start, exec_price = exec_price)
  d <- file.path(TMP, "cells", name); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  pr <- data.table(date = as.Date(index(sim$strategy_xts)), ret_net = as.numeric(sim$strategy_xts),
                   ret_gross = as.numeric(sim$strategy_gross_xts[index(sim$strategy_xts)]))
  fwrite(pr[, .(date, ret_gross, ret_net)], file.path(d, "03_period_returns.csv"))
  h <- sim$HOLDINGS_LOG
  fwrite(h[, .(date = Date, ticker = Ticker, actual_weight = Weight)], file.path(d, "04_holdings.csv"))
  fwrite(data.table(date = as.Date(index(sim$bm_xts)), benchmark_ret = as.numeric(sim$bm_xts)), file.path(d, "05_benchmark_returns.csv"))
  cmv <- sim$cost_model_version
  writeLines(toJSON(list(strategy_id = name, transaction_cost_bps = commission * 1e4, cost_model_version = cmv), auto_unbox = TRUE),
             file.path(d, "00_manifest.json"))
  d
}
cell_skill <- write_cell(W_skill, "skill", "close_t1")
cell_tilt  <- write_cell(W_tilt, "tilt", "close_t1")
cell_rand  <- write_cell(W_rand, "rand", "close_t1")
cell_leg   <- write_cell(W_skill, "skill_legacy", "close_d_legacy")

cat("=== ② 하네스 패리티 · ③ 항등식 ===\n")
r_skill <- ta_attribute(cell_skill, st, cfg)
r_tilt  <- ta_attribute(cell_tilt, st, cfg)
r_leg   <- ta_attribute(cell_leg, st, cfg)
chk("close_t1 보유 재구성 = 하네스 ret_gross", r_skill$parity$recon_abs_max < 1e-10, sprintf("(max|recon| %.2e)", r_skill$parity$recon_abs_max))
chk("close_d_legacy 보유 재구성 = 하네스 ret_gross", r_leg$parity$recon_abs_max < 1e-10, sprintf("(max|recon| %.2e)", r_leg$parity$recon_abs_max))
chk("항등식 active = Σ성분+cost+recon", r_skill$parity$identity_resid_max < 1e-12 && r_tilt$parity$identity_resid_max < 1e-12,
    sprintf("(%.1e)", r_skill$parity$identity_resid_max))
chk("비용 성분 ≤ 0 · 비용일 외 0", all(r_skill$daily$cost <= 1e-15) && sum(r_skill$daily$cost < 0) <= nrow(sig_grid) + 1L)
chk("라벨 = 진단 — 등급 대체 아님", identical(r_skill$label, "진단 — 등급 대체 아님"))

cat("=== ⑦ 판별 — 선별 대 틸트 ===\n")
sk <- r_skill$full$selection; tl <- r_tilt$full
chk("심은 알파 전략: 선별 NW-t > 4", sk$nw_t > 4, sprintf("(t %.2f · 연 %.3f)", sk$nw_t, sk$ann_mean))
chk("심은 알파 전략: 선별 연수익이 심은 값(0.0008×252=0.2016)의 0.75~1.25", sk$ann_mean > 0.75 * 0.2016 && sk$ann_mean < 1.25 * 0.2016)
chk("소형주 틸트 전략: 선별 비유의(|t| < 1.96)", abs(tl$selection$nw_t) < 1.96, sprintf("(t %.2f)", tl$selection$nw_t))
chk("소형주 틸트 전략: ew_cw 가 활성 분산의 최대 몫", tl$ew_cw$var_share > max(tl$selection$var_share, tl$market_beta$var_share, tl$tilt_nsc$var_share),
    sprintf("(ew_cw %.2f · sel %.2f)", tl$ew_cw$var_share, tl$selection$var_share))
chk("소형주 틸트 전략: β_e 사전 적재 > 1(소형주 노출)", r_tilt$loadings$beta_e_mean > 1, sprintf("(%.2f)", r_tilt$loadings$beta_e_mean))
# ⑦-b 적재 보정 진단(2026-09-25 적대 검증 추가) — 위 판별 기준은 β_e 횡단 정보를 통째로 지운 돌연변이(M_flat)도 통과했다
#   (EW 복제·무작위 대조는 OLS 선형성상 평균 적재만 보므로 횡단 정보 소거에 눈이 멀다). 보정 표는 선별에 남은 요인 노출을 잰다.
cal_t <- r_tilt$loading_calibration[period == "full"]; cal_s <- r_skill$loading_calibration[period == "full"]
chk("적재 보정 표 — full 행 + 구간 행 · 기울기·절편 유한", is.data.table(r_tilt$loading_calibration) && nrow(cal_t) == 1L &&
      all(is.finite(c(cal_t$slope_m, cal_t$slope_e, cal_t$slope_n, cal_t$intercept_ann))))
chk("심은 알파 전략: 요인 중립 선별(사후 절편)도 심은 값의 0.75~1.25", cal_s$intercept_ann > 0.75 * 0.2016 && cal_s$intercept_ann < 1.25 * 0.2016,
    sprintf("(%.3f)", cal_s$intercept_ann))
local({
  h <- r_tilt$daily; mid <- h$date[floor(nrow(h) / 2)]; a <- h[date <= mid]$selection; b <- h[date > mid]$selection
  lg <- .ta_nw_lag(length(a), cfg$nw$lag_rule)
  cat(sprintf(paste0("  [INFO] 틸트 전략 사전 적재 감쇠(판정 아님 · 알려진 편의): 선별의 f_e 기울기 %.3f (OLS t %.1f) — 전반 선별 연 %.3f (NW t %.2f) · ",
                     "후반 연 %.3f (NW t %.2f). 합성 f_e 평균이 작아(국면 ±) 누출은 선별 평균이 아니라 기울기로만 보인다 — ",
                     "Vasicek 축소가 무조건 횡단 평균(≈1)으로 당겨 특성 정렬 포트의 노출을 깎는다. 실데이터에선 loading_calibration 을 먼저 읽을 것\n"),
              cal_t$slope_e, cal_t$t_e, mean(a) * 252, .ta_nw_t(a, lg), mean(b) * 252, .ta_nw_t(b, lg)))
})

cat("=== ④ 양성 대조(a) EW 유니버스 복제 ===\n")
ew <- ta_control_ew_replica(st, cfg, start)
chk("EW 복제 — ew_cw 분산 몫·적재·선별 t 기준 통과", isTRUE(ew$pass),
    sprintf("(share %.3f · β_m %.3f · β_e %.3f · sel t %.2f)", ew$ewcw_var_share, ew$beta_m_mean, ew$beta_e_mean, ew$sel_nw_t))

lo <- mk_market(sd_g = 0.002, sd_m = 0.011, idio_top = 0.015, idio = 0.015, top_logcap_boost = c(0, 0))
m_lo <- list(P = lo$P, BM = lo$BM, cal = lo$dates, fp = list())
ew_lo <- ta_control_ew_replica(ta_build_state(m_lo, cfg), cfg, start)
cat(sprintf("  [INFO] 저-SNR 세계(sd(f_e) ≈ 실측의 1/4): EW 복제 β_e %.3f · ew_cw 분산 몫 %.3f — 초판 합성의 감쇠(β_e 0.74)는 노출을 최초 시총에 고정한 합성 결함이었다(판정 아님)\n",
            ew_lo$beta_e_mean, ew_lo$ewcw_var_share))

cat("=== ⑤ 양성 대조(b) 주입 ===\n")
r_inj <- ta_attribute(cell_skill, st, cfg, inject_alpha_ann = cfg$controls$inject_alpha_ann)
dS <- r_inj$daily$selection - r_skill$daily$selection
expS <- cfg$controls$inject_alpha_ann / 252 * r_skill$daily$GL
chk("회계판: 선별 증분 = δ·Σw (1e-12)", max(abs(dS - expS)) < 1e-12, sprintf("(%.1e)", max(abs(dS - expS))))
chk("회계판: 노출 성분 불변", max(abs(r_inj$daily$market_beta - r_skill$daily$market_beta)) == 0 &&
      max(abs(r_inj$daily$ew_cw - r_skill$daily$ew_cw)) == 0 && max(abs(r_inj$daily$tilt_nsc - r_skill$daily$tilt_nsc)) == 0)
Hs <- ta_read_holdings(cell_skill)
mkt_inj <- ta_inject_market(mkt, st, Hs, "close_t1", cfg$controls$inject_alpha_ann)
st_inj <- ta_build_state(mkt_inj, cfg)
C0 <- ta_decompose(.ta_daily_weights(Hs, st, "close_t1"), st)
C1 <- ta_decompose(.ta_daily_weights(Hs, st_inj, "close_t1"), st_inj)
rec <- (mean(C1$selection) - mean(C0$selection)) / (cfg$controls$inject_alpha_ann / 252 * mean(C0$GL))
band <- unlist(cfg$controls$inject_recovery_band)
chk("시장 수준: 회수율이 설정 띠 안", rec >= band[1] && rec <= band[2], sprintf("(회수율 %.3f · 띠 %.2f~%.2f)", rec, band[1], band[2]))

cat("=== ⑥ 양성 대조(c) 무작위 25종 위양성률 ===\n")
rnd <- ta_control_random(st, cfg, start)
chk("무작위 25종 — FPR·평균 t 기준 통과", isTRUE(rnd$pass), sprintf("(R %d · FPR %.2f · 평균 t %.2f · sd %.2f)", rnd$R, rnd$fpr, rnd$mean_t, rnd$sd_t))
# 사이즈 버킷 무신호 대조(2026-09-25 적대 검증 추가) — U 전체 무작위는 평균 특성 = EW_U 라 퇴화 대조다. 버킷 배관 양성 대조:
#   상위 버킷은 대형주라 β_e 중앙 < 1, 하위 버킷은 > 1 이어야 한다(판정은 실데이터 보고용 — 여기선 배관만 잰다).
rb_top <- ta_control_random(st, cfg, start, R = 20L, size_rank = c(1, 60))
rb_bot <- ta_control_random(st, cfg, start, R = 20L, size_rank = c(121, 220))
chk("사이즈 버킷 대조 — 상위 β_e < 1 < 하위 β_e · 결과 유한", is.finite(rb_top$mean_t) && is.finite(rb_bot$mean_t) &&
      rb_top$beta_e_median < 1 && rb_bot$beta_e_median > 1,
    sprintf("(상위 β_e %.2f · FPR %.2f · 평균 t %.2f | 하위 β_e %.2f · FPR %.2f · 평균 t %.2f)", rb_top$beta_e_median, rb_top$fpr, rb_top$mean_t,
            rb_bot$beta_e_median, rb_bot$fpr, rb_bot$mean_t))
expect_stop("size_rank 역순 → 멈춤", ta_control_random(st, cfg, start, R = 2L, size_rank = c(5, 2)), "size_rank")

cat("=== ⑩ 정본 패리티 ===\n")
bc <- new.env(); suppressMessages(sys.source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"), envir = bc))
set.seed(5); xx <- rnorm(500, 0.001, 0.01)
chk(".ta_nw_t(lag 3) = .nw_t_mean(lag 3) 정본", abs(.ta_nw_t(xx, 3) - bc$.nw_t_mean(xx, 3)) < 1e-12)
chk("총 활성 lag-3 t = 같은 CSV 의 PORT_t 식", abs(r_skill$full$active$nw_t_house -
      bc$.nw_t_mean(r_skill$daily$ret_net - r_skill$daily$benchmark_ret, 3)) < 1e-12)
ess <- new.env(); invisible(utils::capture.output(sys.source(file.path(ROOT, "02_Infrastructure/contracts/essence_score.R"), envir = ess)))
er <- ess$.essence_split_components(r_skill$daily$active, ess$.essence_oos_splits("v2"), 252)
er <- stats::median(vapply(er, function(z) as.numeric(z$retention), numeric(1)), na.rm = TRUE)
chk("retention = essence 분할 그대로", isTRUE(all.equal(er, r_skill$retention$active$retention)))

cat("=== ⑧ PIT 탐침 — 정상 코드(양성 대조) ===\n")
H_list <- list(list(H = Hs, exec_price = "close_t1"), list(H = ta_read_holdings(cell_leg), exec_price = "close_d_legacy"))
pr <- ta_pit_probe(mkt, cfg, st, H_list)
chk("탐침 PASS(A 미래참조 · B C10 · B C2 · B 격자 결정일)", identical(pr$status, "PASS") && pr$n_checks >= 30L &&
      all(c("A_lookahead", "B_c10_liquidity", "B_c2_size", "B_grid_decision") %in% pr$rows$tier),
    sprintf("(%d 검사 · 실패 %d · 층 %s)", pr$n_checks, pr$n_fail, paste(unique(pr$rows$tier), collapse = "/")))

cat("=== ⑨ 위반 주입·돌연변이 → red ===\n")
SRC <- paste(readLines(CONTRACT, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
mutate <- function(tag, pairs) {
  s <- SRC
  for (p in pairs) {
    n <- lengths(regmatches(s, gregexpr(p[1], s, fixed = TRUE)))
    if (n != 1L) stop(sprintf("[%s] 치환 표적 %d회(1회여야): %s", tag, n, substr(p[1], 1, 70)))
    s <- sub(p[1], p[2], s, fixed = TRUE)
  }
  d <- file.path(TMP, "mut", tag); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  for (f in c("essence_score.R", "beta_controlled_alpha.R")) file.copy(file.path(ROOT, "02_Infrastructure/contracts", f), d, overwrite = TRUE)
  f <- file.path(d, "tilt_attribution.R"); con <- file(f, "w", encoding = "UTF-8"); writeLines(s, con); close(con)
  e <- new.env(parent = globalenv()); utils::capture.output(sys.source(f, envir = e, keep.source = FALSE)); e
}
probe_mut <- function(tag, pairs, cfg_use = cfg) {
  e <- tryCatch(mutate(tag, pairs), error = function(err) { chk(paste0(tag, " 돌연변이 적용"), FALSE, conditionMessage(err)); NULL })
  if (is.null(e)) return(invisible(NULL))
  r <- tryCatch({ s2 <- e$ta_build_state(mkt, cfg_use); e$ta_pit_probe(mkt, cfg_use, s2, H_list) },
                error = function(err) list(status = paste0("ERROR:", conditionMessage(err))))
  bad <- if (is.data.table(r$rows)) paste(unique(r$rows[pass == FALSE]$item), collapse = ",") else ""
  chk(sprintf("%s → 탐침 red", tag), identical(r$status, "FAIL"), sprintf("(%s · 발화 %s)", substr(r$status, 1, 60), bad))
}
probe_mut("M1_당일멤버십", list(c("if (D > dlag) U[(dlag + 1L):D, ] <- ELIG[1:(D - dlag), , drop = FALSE]", "U <- ELIG")))
probe_mut("M2_유동성지연제거", list(c('P[, .adv := shift(frollmean(.tv, L, align = "right"), llag), by = Ticker]',
                                     'P[, .adv := frollmean(.tv, L, align = "right"), by = Ticker]')))
probe_mut("M3_창에t포함", list(c(".ta_window_index <- function(D, W) list(hi = seq_len(D), lo = pmax(1L, seq_len(D) - W))",
                                 ".ta_window_index <- function(D, W) list(hi = seq_len(D) + 1L, lo = pmax(1L, seq_len(D) + 1L - W))")))
probe_mut("M4_β전기간", list(c(".ta_window_index <- function(D, W) list(hi = seq_len(D), lo = pmax(1L, seq_len(D) - W))",
                               ".ta_window_index <- function(D, W) list(hi = rep(D + 1L, D), lo = rep(1L, D))")))
probe_mut("M5_비중당일수익", list(c("Gb <- rbind(rep(1, ncol(G)), G[-nrow(G), , drop = FALSE])", "Gb <- G")))
probe_mut("M6_대조당일Size", list(c("P[, .size_l := shift(Size, slag), by = Ticker]", "P[, .size_l := Size, by = Ticker]")))
c_lag0 <- cfg; c_lag0$universe$decision_lag_market_days <- 0L
probe_mut("M7_가드제거+지연0", list(
  c('if (dlag < 1L || llag < 1L || slag < 1L) stop("[tilt] PIT 가드: 지연 < 1")', "invisible(NULL)"),
  c("if (D > dlag) U[(dlag + 1L):D, ] <- ELIG[1:(D - dlag), , drop = FALSE]", "if (dlag == 0L) U <- ELIG else if (D > dlag) U[(dlag + 1L):D, ] <- ELIG[1:(D - dlag), , drop = FALSE]")),
  cfg_use = c_lag0)
e8 <- tryCatch(mutate("M8_시장성분", list(c("A[, `:=`(market_beta = (beta_m - 1) * rb,", "A[, `:=`(market_beta = beta_m * rb,"))),
               error = function(err) NULL)
r8 <- if (is.null(e8)) NULL else tryCatch(e8$ta_attribute(cell_skill, st, cfg), error = function(err) NULL)
chk("M8_시장성분(−1 누락) → 항등식 red", !is.null(r8) && r8$parity$identity_resid_max > 1e-6,
    if (is.null(r8)) "(실행 실패)" else sprintf("(max resid %.2e)", r8$parity$identity_resid_max))
# 2026-09-25 적대 검증 추가 — 초판 탐침의 사각(A층은 c 이후만 교란): 격자 요인의 적격을 시그널일이 아닌 집행일 상태로 바꿔도 초판은 PASS 였다.
probe_mut("M9_EWU_집행일적격", list(c("s <- g$sig_idx[k]; cand <- which(st$ELIG[s, ])", "s <- g$sig_idx[k]; cand <- which(st$ELIG[g$exec_idx[k], ])")))
probe_mut("M11_대조_집행일적격", list(c("cand <- which(st_core$ELIG[s, ] & is.finite(sz) & sz > 0)",
                                       "cand <- which(st_core$ELIG[g$exec_idx[k], ] & is.finite(sz) & sz > 0)")))
# M_flat — β_e 횡단 정보 소거(모든 종목 = 그날 U 평균). 초판에선 EW 복제·무작위 대조·⑦ 판별이 전부 통과했다 → 보정 표가 잡아야 한다.
#   기준: 틸트 전략의 선별 f_e 기울기가 기준판보다 설정 ew_replica_beta_band 반폭(적재 허용 오차) 이상 커진다.
eF <- tryCatch(mutate("M_flat", list(c("B2 <- .ta_shrink(L2$B, U, wts, mpn)",
  "B2 <- .ta_shrink(L2$B, U, wts, mpn); B2[[2]][] <- matrix(attr(B2[[2]], 'prior'), nrow(B2[[2]]), ncol(B2[[2]]))"))), error = function(err) NULL)
rF <- if (is.null(eF)) NULL else tryCatch(eF$ta_attribute(cell_tilt, eF$ta_build_state(mkt, cfg), cfg), error = function(err) NULL)
bw <- diff(unlist(cfg$controls$ew_replica_beta_band)) / 2
sF <- if (is.null(rF)) NA_real_ else rF$loading_calibration[period == "full"]$slope_e
chk("M_flat(β_e 횡단 소거) → 보정 표 red", is.finite(sF) && abs(sF) > abs(cal_t$slope_e) + bw,
    sprintf("(선별 f_e 기울기 기준 %.3f → 돌연변이 %.3f · 허용 %.2f)", cal_t$slope_e, sF, bw))

cat("=== ⑪ 쓰기 ===\n")
expect_stop("out_dir 없으면 멈춤", ta_write(r_skill, ""), "out_dir")
od <- file.path(TMP, "out"); ta_write(r_skill, od, "skill")
chk("명시 경로에만 JSON+CSV", file.exists(file.path(od, "skill.json")) && file.exists(file.path(od, "skill_daily.csv")) &&
      length(list.files(od, all.files = TRUE, no.. = TRUE)) == 2L)
js <- fromJSON(file.path(od, "skill.json"))
chk("JSON 라벨·일간 제외", identical(js$label, TA_LABEL) && is.null(js$daily))

cat(sprintf("\n결과: PASS %d · FAIL %d\n", pass, fail))
## ★러너 요약 계약 — run_all_hooks.sh 는 이 JSON 줄로만 집계한다(없으면 UNMEASURED → 배터리 status FAIL).
cat(sprintf('{"test":"tilt_attribution","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', pass, fail, pass + fail))
unlink(TMP, recursive = TRUE)
if (fail > 0L) quit(status = 1L)
