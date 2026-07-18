##=============================================================================
## run_break_dating_verify.R — FQ-055 "기저 2016-17" 보정 추론의 적대 검증
## V1: 합성 캘리브레이션 — 알려진 T 단절 → rolling-60m 적합 τ가 T 대비 어디에?
## V2: 원시 월간 active(롤링 無)에 CUSUM argmax 직접 추정 — 창 지연 원천 제거
##=============================================================================
suppressMessages({ library(arrow); library(data.table); library(jsonlite) })
setDTthreads(1)
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT <- "stage_artifacts/decay_fit"
source("04_Research/decay_fit/decay_fit_engine.R")
set.seed(20260718)
wf <- function(fmt, ...) cat(sprintf(fmt, ...), "\n")

## ── V1: 합성 캘리브레이션 ──────────────────────────────────────────────────
## 월간 active: n=257 (2005-01~2026-05 동형), T=진짜 단절 인덱스, pre SR~0.8 → post 0
n <- 257; sig <- 0.025
Ts <- c(120, 144, 168)          # 단절 위치 3종 (2014-12·2016-12·2018-12 상당)
n_sim <- 200
res_v1 <- list()
for (Tt in Ts) {
  tau_roll <- rep(NA_real_, n_sim); tau_cusum <- rep(NA_real_, n_sim)
  for (s in seq_len(n_sim)) {
    mu <- c(rep(0.006, Tt), rep(0.000, n - Tt))
    u <- rnorm(n, mu, sig)
    ## rolling-60m SR 위 M4 적합 (본측정과 동일 엔진)
    rl <- build_roll(u, seq_len(n), 60, 54, "sr")
    if (!is.null(rl) && length(rl$y) >= 96) {
      f <- fit_models(rl$y, rl$tvec)
      if (!is.null(f) && !is.null(f$M4)) {
        ## rl$dates는 원 인덱스(60..n) — τ를 원 시계열 인덱스로 환산
        tau_roll[s] <- rl$dates[f$M4$par$tau]
      }
    }
    ## CUSUM argmax (원시, 롤링 없음)
    cs <- cumsum(u - mean(u)); tau_cusum[s] <- which.max(abs(cs))
  }
  res_v1[[as.character(Tt)]] <- list(
    roll_med = median(tau_roll - Tt, na.rm = TRUE), roll_q = quantile(tau_roll - Tt, c(.25, .75), na.rm = TRUE),
    cusum_med = median(tau_cusum - Tt, na.rm = TRUE), cusum_q = quantile(tau_cusum - Tt, c(.25, .75), na.rm = TRUE))
  wf("[V1 T=%d] rolling-60 적합 τ−T: median=%+.0f개월 IQR[%+.0f,%+.0f] | CUSUM(원시) τ−T: median=%+.0f IQR[%+.0f,%+.0f]",
     Tt, res_v1[[as.character(Tt)]]$roll_med, res_v1[[as.character(Tt)]]$roll_q[1], res_v1[[as.character(Tt)]]$roll_q[2],
     res_v1[[as.character(Tt)]]$cusum_med, res_v1[[as.character(Tt)]]$cusum_q[1], res_v1[[as.character(Tt)]]$cusum_q[2])
}

## ── V2: 실데이터 원시-직접 추정 (C-M capw break 77팩터) ────────────────────
CM <- as.data.table(read_parquet(file.path(OUT, "decay_fit_CM_20260717.parquet")))
bfacs <- CM[basis == "capw" & label == "break_dominated", factor]
r6 <- as.data.table(read_parquet(".cache/pins/decay_fit_20260717/r6_factor_deployzone_active.parquet"))
r6[, signal_date := as.Date(signal_date)]
rows <- list()
for (fc in bfacs) {
  sub <- r6[factor_id == fc][order(signal_date)]
  u <- sub$active_bm; dts <- sub$signal_date
  ok <- !is.na(u); u <- u[ok]; dts <- dts[ok]
  if (length(u) < 120) next
  cs <- cumsum(u - mean(u)); ti <- which.max(abs(cs))
  ## 원시 시계열 위 M4 vs M0 AICc (유의성 참고 — 검정력 낮음 정직 병기)
  m0rss <- sum((u - mean(u))^2)
  n1 <- ti; n2 <- length(u) - ti
  sig_ok <- NA
  if (n1 >= 24 && n2 >= 24) {
    m1 <- mean(u[1:ti]); m2 <- mean(u[(ti + 1):length(u)])
    rss4 <- sum((u[1:ti] - m1)^2) + sum((u[(ti + 1):length(u)] - m2)^2)
    sig_ok <- (AICC(m0rss, length(u), 2) - AICC(rss4, length(u), 4)) >= 2
  }
  rows[[fc]] <- data.table(factor = fc, cusum_date = dts[ti], m4_beats_null = sig_ok)
}
V2 <- rbindlist(rows)
V2[, yr := year(cusum_date)]
wf("[V2] 원시-직접 CUSUM 단절연도 분포 (C-M break 77팩터):")
print(V2[, .N, by = yr][order(yr)])
wf("[V2] 2016~2017 비중=%.2f | 2015~2018 비중=%.2f | M4>null AICc2 유의 비율=%.2f",
   V2[yr %in% 2016:2017, .N] / nrow(V2), V2[yr %in% 2015:2018, .N] / nrow(V2), V2[, mean(m4_beats_null, na.rm = TRUE)])
write_json(list(v1 = res_v1, v2_year_dist = V2[, .N, by = yr][order(yr)],
                v2_share_2016_17 = V2[yr %in% 2016:2017, .N] / nrow(V2),
                v2_share_2015_18 = V2[yr %in% 2015:2018, .N] / nrow(V2),
                generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
           file.path(OUT, "break_dating_verify_20260718.json"), auto_unbox = TRUE, pretty = TRUE, digits = 4)
wf("[verify] done")
