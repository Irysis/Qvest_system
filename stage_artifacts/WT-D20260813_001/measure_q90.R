## WT-D20260813_001 — q90 상방 분위 표적 성과 측정 + arm A 대비 paired 검정 + F1~F3 반증 + β/vol 틸트
## 사전등록 = PREREG_q90_20260822.md. Python 은 스코어까지, 성과·판정은 여기서(python-policy §4).
## 실행: cd <ROOT> && Rscript -e 'source("stage_artifacts/WT-D20260813_001/measure_q90.R")'
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)
                                library(xts); library(PerformanceAnalytics)})
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

SRC <- "stage_artifacts/fq233_probe0_20260813"
OUT <- "stage_artifacts/WT-D20260813_001"

## ── 공통 입력 (arm A/B 와 동일 경로) ─────────────────────────────────────────
inp <- readRDS(file.path(SRC, "r33_inputs.rds"))
returns_dt <- as.data.table(inp$frd)[, .(Date = as.Date(Date), Ticker = as.character(Ticker),
                                          Ret_1m = as.numeric(Ret_1m))]
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))[, Date := as.Date(Date)]
bm <- bm[is.finite(BM_Ret)]
bmm <- apply.monthly(xts(bm$BM_Ret, order.by = bm$Date), Return.cumulative)
bench_m <- data.table(ym = format(as.Date(index(bmm)), "%Y%m"), BM_Ret = as.numeric(bmm[, 1]))
axis_dt <- unique(returns_dt[, .(Date)])[, ym := format(Date, "%Y%m")]
bench_dt <- merge(axis_dt, bench_m, by = "ym")[, .(Date, BM_Ret)]
stopifnot(nrow(bench_dt) >= 0.95 * uniqueN(returns_dt$Date))

nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; n <- length(x)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) { w <- 1 - l/(lag+1); s <- s + 2*w*sum(e[(l+1):n]*e[1:(n-l)])/n }
  m/sqrt(s/n) }

run_one <- function(scores_file, tag) {
  sc <- as.data.table(read_parquet(file.path(OUT, scores_file)))[, Date := as.Date(Date)]
  s <- sc[, .(Date, Ticker = as.character(Ticker), score = as.numeric(score))]
  r <- canonical_screen_bt(scores_dt = s, returns_dt = returns_dt, bench_dt = bench_dt,
                           top_n = 25L, cost_bps_oneway = 15,
                           strategy_id = paste0("WT_D20260813_001_", tag),
                           run_id = "WT-D20260813_001")
  pr <- as.data.table(r$period_returns)
  px <- xts(pr$ret_net, order.by = as.Date(pr$date))
  list(tag = tag, res = r, pr = pr, scores = sc,
       sr_total = as.numeric(SharpeRatio.annualized(px, Rf = 0, scale = 12, geometric = FALSE)),
       cagr = as.numeric(Return.annualized(px, scale = 12, geometric = TRUE)),
       mdd  = as.numeric(maxDrawdown(px)))
}

cat("=== primary = q90 (사전등록 §3) ===\n")
Q <- run_one("q90_model_scores.parquet", "q90_primary")
cat(sprintf("  total SR %+.4f · PORT_t %+.4f (p %.4f) · active IR %+.4f · CAGR %.2f%% · MDD %.2f%% · Calmar %.3f · TO %.2f · n=%d\n",
            Q$sr_total, as.numeric(Q$res$portfolio_alpha_t_nw_lag3),
            as.numeric(Q$res$portfolio_alpha_t_pvalue), as.numeric(Q$res$net_sr),
            100*Q$cagr, 100*Q$mdd, Q$cagr/Q$mdd, as.numeric(Q$res$turnover_annual),
            as.numeric(Q$res$n_months)))

cat("\n=== 음성 대조 = trim5 (사전등록 §2·§3) ===\n")
Tr <- run_one("trim5_control_scores.parquet", "trim5_control")
cat(sprintf("  total SR %+.4f · PORT_t %+.4f · active IR %+.4f · MDD %.2f%% · n=%d\n",
            Tr$sr_total, as.numeric(Tr$res$portfolio_alpha_t_nw_lag3),
            as.numeric(Tr$res$net_sr), 100*Tr$mdd, as.numeric(Tr$res$n_months)))

## ── arm A 대조군 로드 ────────────────────────────────────────────────────────
A <- readRDS(file.path(SRC, "armA_canonical_result.rds"))
prA <- as.data.table(A$period_returns)[, .(date = as.Date(date), a = ret_net, bm = benchmark_ret)]

paired_vs_A <- function(prX, x_tag) {
  prx <- prX[, .(date = as.Date(date), x = ret_net)]
  j <- merge(prA[, .(date, a, bm)], prx, by = "date")
  d <- j$x - j$a
  t <- nw_t(d)
  list(n = nrow(j), mean_diff_monthly = mean(d), mean_diff_ann_pct = 100*12*mean(d), nw3_t = t, j = j)
}

cat("\n=== primary 검정: q90 − arm A 짝지은 NW lag-3 t (사전등록 §4) ===\n")
PA <- paired_vs_A(Q$pr, "q90")
cat(sprintf("  짝지은 달 %d · 월평균차 %+.4f%%p · 연환산 %+.2f%%p · NW3 t = %+.4f\n",
            PA$n, 100*PA$mean_diff_monthly, PA$mean_diff_ann_pct, PA$nw3_t))
PT <- paired_vs_A(Tr$pr, "trim5")
cat(sprintf("  [대조] trim5 − arm A: NW3 t = %+.4f · 연환산 %+.2f%%p\n", PT$nw3_t, PT$mean_diff_ann_pct))

verdict_perf <- if (PA$nw3_t >= 2.0) "SUPPORTED_PERF" else
                if (PA$nw3_t <= -2.0) "Q90_INFERIOR" else "NOT_SUPPORTED_NO_DIFFERENCE"

## ── β-통제 α (measurement-graduation §2): r_active = α + β·r_bm + ε, NW lag-3 ──
beta_ctrl_alpha <- function(prX) {
  prx <- prX[, .(date = as.Date(date), x = ret_net)]
  j <- merge(prA[, .(date, a, bm)], prx, by = "date")
  ra <- j$x - j$bm          # active net vs BM
  fit <- lm(j$x ~ j$bm)     # port ~ bm : α = 절편, β = 기울기
  al <- coef(fit)[1]; be <- coef(fit)[2]
  resid <- residuals(fit)
  ## NW lag-3 t on residual mean for α
  n <- length(resid); m <- al
  ## α의 t는 회귀 표준오차를 NW로 보정 — 간이: HAC via sandwich 부재 시 resid의 NW-SE로 근사
  e <- resid - mean(resid); s <- sum(e^2)/n
  for (l in 1:3) { w <- 1 - l/4; s <- s + 2*w*sum(e[(l+1):n]*e[1:(n-l)])/n }
  se_alpha <- sqrt(s/n)
  list(alpha_monthly = as.numeric(al), alpha_ann = as.numeric(al*12),
       beta = as.numeric(be), t_alpha_nw = as.numeric(al/se_alpha),
       port_t_meandiff = nw_t(j$x - j$bm))
}
BQ <- beta_ctrl_alpha(Q$pr)
cat(sprintf("\n=== β-통제 α (q90) ===\n  α %+.4f%%/월 (%+.2f%%/yr) · β %.3f · t(α)_NW %+.4f · [참고 PORT_t(mean active) %+.4f]\n",
            100*BQ$alpha_monthly, 100*BQ$alpha_ann, BQ$beta, BQ$t_alpha_nw, BQ$port_t_meandiff))
BA <- beta_ctrl_alpha(data.table(date=prA$date, ret_net=prA$a, benchmark_ret=prA$bm))
cat(sprintf("  [arm A] α %+.2f%%/yr · β %.3f · t(α)_NW %+.4f\n", 100*BA$alpha_ann, BA$beta, BA$t_alpha_nw))

## ── F1: tail-hit rate — 보유 종목이 보유월 횡단면 q90 이상 수익 실현 빈도 ──────
## 월별 횡단면 q90 임계 (returns_dt = 월간 forward 실현수익)
ret_q90 <- returns_dt[, .(q90_thr = quantile(Ret_1m, 0.90, na.rm = TRUE),
                          skew_cs = { x <- Ret_1m[is.finite(Ret_1m)]
                                      if (length(x) < 10) NA_real_ else {
                                        m <- mean(x); s <- sd(x)
                                        if (s == 0) NA_real_ else mean(((x-m)/s)^3) } }), by = Date]

## 보유 종목 재구성: canonical_screen_bt 는 holdings 를 res 에 담는지 확인, 없으면 score 상위 25 재현
get_holdings <- function(RES, SC) {
  h <- RES$res$holdings
  if (!is.null(h) && length(h) > 0) {
    hd <- as.data.table(h)
    if (all(c("Date","Ticker") %in% names(hd))) return(hd[, .(Date = as.Date(Date), Ticker = as.character(Ticker))])
  }
  ## fallback: 스코어 상위 25 (canonical 규격 = top-N EW long-only, 유동성필터는 measure 에선 미적용 근사)
  s <- SC[, .(Date = as.Date(Date), Ticker = as.character(Ticker), score = as.numeric(score))]
  s <- s[is.finite(score)]
  s[order(-score), head(.SD, 25L), by = Date][, .(Date, Ticker)]
}
holdQ <- get_holdings(Q, Q$scores)
scA <- as.data.table(read_parquet(file.path(SRC, "armA_scores.parquet")))[, .(Date, Ticker = as.character(Ticker), score = as.numeric(score))]
holdA <- get_holdings(list(res=list(holdings=NULL)), scA)

tail_hit <- function(hold) {
  hh <- merge(hold, returns_dt, by = c("Date","Ticker"))
  hh <- merge(hh, ret_q90[, .(Date, q90_thr)], by = "Date")
  hh[, hit := as.integer(Ret_1m >= q90_thr)]
  hh[, .(hit_rate = mean(hit)), by = Date]
}
thQ <- tail_hit(holdQ); thA <- tail_hit(holdA)
jh <- merge(thQ[, .(Date, hr_q = hit_rate)], thA[, .(Date, hr_a = hit_rate)], by = "Date")
f1_diff <- jh$hr_q - jh$hr_a
f1_t <- nw_t(f1_diff)
cat(sprintf("\n=== F1 tail-hit (q90 보유 vs arm A 보유, 횡단면 q90 이상 실현 빈도) ===\n"))
cat(sprintf("  q90 평균 hit-rate %.4f · arm A %.4f · 차이 %+.4f · paired NW3 t = %+.4f (문턱 +2.0)\n",
            mean(jh$hr_q), mean(jh$hr_a), mean(f1_diff), f1_t))
f1_verdict <- if (f1_t >= 2.0) "F1_PASS" else "F1_REJECT"

## ── F2: 상위-3 기여 종목 집중도 (포트 월수익 중 top-3 기여 비중) ──────────────
contrib_conc <- function(hold) {
  hh <- merge(hold, returns_dt, by = c("Date","Ticker"))
  hh[, w := 1/.N, by = Date]
  hh[, contrib := w * Ret_1m]
  ## 그 달 양(+) 기여 합 대비 상위-3 기여 비중 (분모 양수 달만)
  hh[, .(top3 = { cs <- sort(contrib, decreasing = TRUE); pos <- sum(contrib[contrib>0])
                  if (pos <= 0) NA_real_ else sum(head(cs,3))/pos }), by = Date][is.finite(top3)]
}
c2Q <- contrib_conc(holdQ); c2A <- contrib_conc(holdA)
jc <- merge(c2Q[, .(Date, cq = top3)], c2A[, .(Date, ca = top3)], by = "Date")
f2_diff <- jc$cq - jc$ca
cat(sprintf("\n=== F2 상위-3 기여 집중도 ===\n  q90 %.4f · arm A %.4f · 차이 %+.4f (기전: q90 이 낮지 않아야)\n",
            mean(jc$cq), mean(jc$ca), mean(f2_diff)))
f2_verdict <- if (mean(f2_diff) >= 0) "F2_PASS" else "F2_REJECT"

## ── F3: 왜도 연결 — 횡단면 왜도 상위/하위 국면별 q90−arm A 우위 ────────────────
jd <- merge(PA$j[, .(date, d = x - a)], ret_q90[, .(date = Date, skew_cs)], by = "date")
jd <- jd[is.finite(skew_cs)]
skew_med <- median(jd$skew_cs, na.rm = TRUE)
hi <- jd[skew_cs >= skew_med]; lo <- jd[skew_cs < skew_med]
cat(sprintf("\n=== F3 왜도 연결 (횡단면 왜도 상위 vs 하위 국면의 q90−armA 월평균차) ===\n"))
cat(sprintf("  왜도 상위: %+.4f%%p/월 (n=%d) · 왜도 하위: %+.4f%%p/월 (n=%d) · 차이 %+.4f%%p\n",
            100*mean(hi$d), nrow(hi), 100*mean(lo$d), nrow(lo), 100*(mean(hi$d)-mean(lo$d))))
f3_verdict <- if (mean(hi$d) > mean(lo$d)) "F3_PASS" else "F3_REJECT"

## ── β/vol 틸트: 선택 종목 D03_RealVol 분위 분포 (q90 vs arm A) ─────────────────
pan <- as.data.table(read_parquet(file.path(SRC, "lane_a_feature_panel.parquet")))
pan[, `:=`(Date = as.Date(anchor), Ticker = as.character(Ticker))]
vol_dt <- pan[, .(Date, Ticker, D03_RealVol)]
## 월별 횡단면 vol 분위(0~1) → 선택 종목의 평균 vol-percentile
vol_dt[, vol_pct := frank(D03_RealVol, na.last = "keep")/.N, by = Date]
volsel <- function(hold) {
  merge(hold, vol_dt[, .(Date, Ticker, vol_pct)], by = c("Date","Ticker"))[is.finite(vol_pct), mean(vol_pct)]
}
vpQ <- volsel(holdQ); vpA <- volsel(holdA)
cat(sprintf("\n=== β/vol 틸트: 선택 종목 평균 D03_RealVol 횡단면 분위 ===\n  q90 %.4f · arm A %.4f · 차이 %+.4f (0.5=중립)\n",
            vpQ, vpA, vpQ - vpA))

## ── 저장 ─────────────────────────────────────────────────────────────────────
saveRDS(list(Q=Q, Tr=Tr, PA=PA, PT=PT, BQ=BQ, BA=BA,
             F1=list(t=f1_t, diff=f1_diff, jh=jh), F2=list(diff=f2_diff, jc=jc),
             F3=list(hi=hi, lo=lo, skew_med=skew_med),
             voltilt=list(q90=vpQ, armA=vpA)),
        file.path(OUT, "measure_q90_full.rds"))

## q90 canonical result
write_json(Q$res, file.path(OUT, "q90_canonical_result.json"),
           auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")

## paired verdict
overall <- if (verdict_perf == "SUPPORTED_PERF" && f1_verdict == "F1_PASS") "SUPPORTED" else
           if (verdict_perf == "SUPPORTED_PERF" && f1_verdict == "F1_REJECT") "UNEXPLAINED_POSITIVE" else
           if (verdict_perf == "Q90_INFERIOR") "Q90_INFERIOR" else "NOT_SUPPORTED"
write_json(list(
  round_id = "WT-D20260813_001_Q90", prereg = "PREREG_q90_20260822.md",
  metric_type = "canonical_screen", selection_type = "chain",
  primary = "q90_pinball_lgbm",
  q90_result = list(total_sr = Q$sr_total, port_t = as.numeric(Q$res$portfolio_alpha_t_nw_lag3),
    port_t_p = as.numeric(Q$res$portfolio_alpha_t_pvalue), active_ir = as.numeric(Q$res$net_sr),
    cagr = Q$cagr, mdd = Q$mdd, calmar = Q$cagr/Q$mdd,
    turnover = as.numeric(Q$res$turnover_annual), n_months = as.numeric(Q$res$n_months)),
  armA_result = list(total_sr = readRDS(file.path(SRC,"armA_basis.rds"))$sr_total,
    port_t = as.numeric(A$portfolio_alpha_t_nw_lag3), n_months = as.numeric(A$n_months)),
  paired_vs_armA = list(n_months = PA$n, mean_diff_monthly = PA$mean_diff_monthly,
    mean_diff_ann_pct = PA$mean_diff_ann_pct, nw3_t = PA$nw3_t, threshold = 2.0),
  trim5_control = list(total_sr = Tr$sr_total, port_t = as.numeric(Tr$res$portfolio_alpha_t_nw_lag3),
    paired_vs_armA_nw3_t = PT$nw3_t, mean_diff_ann_pct = PT$mean_diff_ann_pct,
    interpretation = "기전 참이면 trim5(꼬리제거 평균)는 arm A 대비 개선 없어야 함 (paired t < +2.0)"),
  beta_controlled_alpha = list(q90 = list(alpha_ann = BQ$alpha_ann, beta = BQ$beta,
    t_alpha_nw = BQ$t_alpha_nw, port_t_mean_active = BQ$port_t_meandiff),
    armA = list(alpha_ann = BA$alpha_ann, beta = BA$beta, t_alpha_nw = BA$t_alpha_nw)),
  verdict_perf = verdict_perf, verdict_overall = overall),
  file.path(OUT, "q90_paired_verdict.json"), auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")

## falsification
write_json(list(
  round_id = "WT-D20260813_001_Q90",
  F1_tail_hit = list(q90_mean_hit_rate = mean(jh$hr_q), armA_mean_hit_rate = mean(jh$hr_a),
    mean_diff = mean(f1_diff), paired_nw3_t = f1_t, threshold = 2.0, verdict = f1_verdict,
    note = "보유 종목이 보유월 횡단면 q90 이상 수익 실현 빈도. F1 = 기전 주 기각축."),
  F2_contrib_concentration = list(q90_top3_share = mean(jc$cq), armA_top3_share = mean(jc$ca),
    mean_diff = mean(f2_diff), verdict = f2_verdict,
    note = "포트 월수익의 상위-3 기여 종목 집중도. q90 이 낮지 않아야(평균은 꼬리가 견인)."),
  F3_skew_link = list(hi_skew_mean_diff_monthly = mean(hi$d), lo_skew_mean_diff_monthly = mean(lo$d),
    hi_minus_lo = mean(hi$d) - mean(lo$d), n_hi = nrow(hi), n_lo = nrow(lo),
    skew_median = skew_med, verdict = f3_verdict,
    note = "횡단면 왜도 상위 국면에서 q90 우위가 집중되어야."),
  combined = list(f1 = f1_verdict, f2 = f2_verdict, f3 = f3_verdict)),
  file.path(OUT, "q90_falsification.json"), auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")

## beta/vol tilt
write_json(list(round_id = "WT-D20260813_001_Q90",
  vol_percentile_selected = list(q90 = vpQ, armA = vpA, diff = vpQ - vpA,
    note = "선택 종목의 D03_RealVol 월별 횡단면 분위 평균. 0.5=중립. q90 > arm A 이면 고변동 틸트."),
  beta = list(q90_beta_to_bm = BQ$beta, armA_beta_to_bm = BA$beta),
  interpretation = "q90 total SR 우위가 vol/β 틸트 아티팩트인지 진단. t(α) 병기로 부분 통제."),
  file.path(OUT, "q90_beta_tilt.json"), auto_unbox = TRUE, pretty = TRUE, digits = 8, na = "null")

cat(sprintf("\n★판정: 성과 %s · F1 %s · F2 %s · F3 %s → **%s**\n",
            verdict_perf, f1_verdict, f2_verdict, f3_verdict, overall))
cat("저장: q90_canonical_result.json · q90_paired_verdict.json · q90_falsification.json · q90_beta_tilt.json · measure_q90_full.rds\n")
