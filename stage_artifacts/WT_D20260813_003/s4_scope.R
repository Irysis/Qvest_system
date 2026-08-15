## s4_scope.R — VT2b_REJECT 의 범위 진단 (판정 확정 후 · 판정 불변)
## 질문: 수확 실패가 (a) 내가 고른 sigma*/바닥 조합의 성질인가 (b) KR 의 sigma_hat->수익 관계 성질인가.
## ★파라미터 격자로 '통과하는 조합 찾기' 를 하지 않는다(= sweep 재분류 유발). 대신 매핑과 무관한
##   sigma_hat -> 다음달 수익 관계 자체를 비모수로 본다. 어떤 단조감소 매핑에도 적용되는 진술.

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
BC <- new.env(parent = globalenv())
sys.source("02_Infrastructure/contracts/backtest_result_contract.R", envir = BC)
nw_t <- function(x, lag = 3L) BC$.nw_t_mean(x, lag = lag)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260813_003")
EV <- as.data.table(readRDS(file.path(OUT, "vt_panel.rds"))); setorder(EV, hold_start)
r <- EV$r; e <- EV$e; n <- nrow(EV); ebar <- mean(e)

## ── 1. sigma_hat 5분위별 다음달 수익·실현vol (매핑 무관) ────────────────────
EV[, sq := cut(frank(sigma_d), breaks = quantile(frank(sigma_d), 0:5/5), include.lowest = TRUE, labels = 1:5)]
tab <- EV[, .(n = .N, sigma_mean = mean(sigma_d), mean_r_pct = 100*mean(r),
              med_r_pct = 100*median(r), sd_r_pct = 100*sd(r),
              realized_vol = mean(realized_vol), mean_e = mean(e)), by = sq][order(sq)]
cat("[분위] sigma_hat 5분위 (1=저변동 ... 5=고변동):\n"); print(tab)

## 단조성 검정 — sigma_hat 과 다음달 수익의 관계
sp <- cor.test(EV$sigma_d, r, method = "spearman", exact = FALSE)
pe <- cor.test(EV$sigma_d, r, method = "pearson")
cat(sprintf("\n[관계] spearman(sigma_hat, r) = %+.4f (p=%.4f)   pearson = %+.4f (p=%.4f)\n",
            sp$estimate, sp$p.value, pe$estimate, pe$p.value))
## 회귀 기울기의 NW t — ★자기적발: 초판이 (x-xbar)*resid 의 NW t 를 썼는데 이는 OLS 1계조건으로
##   평균이 항등적으로 0 -> t = 0.000 이 나온다(고장난 통계량, 데이터 무관). 샌드위치로 정정.
fit <- stats::lm(r ~ sigma_d, data = EV)
xd <- EV$sigma_d - mean(EV$sigma_d); u <- stats::residuals(fit)
Sxx <- sum(xd^2); h <- xd * u
.nw_var <- function(v, lag = 3L) { m <- length(v); s <- sum(v^2)
  for (l in 1:lag) { w <- 1 - l/(lag+1); s <- s + 2*w*sum(v[(l+1):m]*v[1:(m-l)]) }; s }
slope_t_nw <- as.numeric(coef(fit)[2]) / sqrt(.nw_var(h, 3L) / Sxx^2)
cat(sprintf("[관계] OLS 기울기 = %+.4f (sigma_hat 1단위당 월수익)  NW lag-3 t = %+.3f\n",
            coef(fit)[2], slope_t_nw))
## 공분산 계열 자체의 NW t — 단조감소 매핑 비용의 유의성
cov_series <- (frank(EV$sigma_d)/n - mean(frank(EV$sigma_d)/n)) * (r - mean(r))
cov_t_nw <- nw_t(cov_series, 3L)
cat(sprintf("[관계] cov(rank sigma_hat, r) 계열 NW lag-3 t = %+.3f\n", cov_t_nw))
## 분위별 평균/표준편차 비 — vol-managed 전제(고변동 = 낮은 보상)의 직접 대조
tab[, mean_over_sd := mean_r_pct / sd_r_pct]
cat("[분위] 월 평균/표준편차 비:\n"); print(tab[, .(sq, n, mean_r_pct, sd_r_pct, mean_over_sd)])
## 고변동 절반 vs 저변동 절반 평균수익 (기전의 핵심 사실)
hi <- EV$sigma_d > median(EV$sigma_d)
tt <- t.test(r[hi], r[!hi])
cat(sprintf("[관계] 고변동 절반 평균 %+.3f%%/월 vs 저변동 절반 %+.3f%%/월  Welch t=%+.3f p=%.4f\n",
            100*mean(r[hi]), 100*mean(r[!hi]), tt$statistic, tt$p.value))
cat(sprintf("[관계] 실현vol 은 정합 (고 %.4f > 저 %.4f) — 분산 예측은 살아있고 평균 방향만 반대\n",
            mean(EV$realized_vol[hi]), mean(EV$realized_vol[!hi])))

## ── 2. 어떤 단조감소 매핑도 지불하는 비용 — 부호 진술 ───────────────────────
## e = g(sigma_hat), g 단조감소 => cov(e, r) 의 부호 = -sign(cov(sigma_hat 순위, r))
## 비모수 확인: sigma_hat 순위와 r 의 관계가 양이면 모든 단조감소 매핑에서 cov(e,r) < 0.
rk <- frank(EV$sigma_d) / n
cov_rank_r <- mean((rk - mean(rk)) * (r - mean(r)))
cat(sprintf("\n[일반성] cov(rank(sigma_hat), r) = %+.6f -> 단조감소 매핑 전부에서 cov(e,r) 부호 = %s\n",
            cov_rank_r, ifelse(cov_rank_r > 0, "음(수익 희생)", "양")))
## 통제: 승계 예측기 4종 각각으로 같은 부호 확인 (VOL 만의 성질인가)
P2 <- as.data.table(arrow::read_parquet("stage_artifacts/WT_D20260813_002/alpha_scores.parquet"))
M <- merge(EV[, .(ym, r)], P2[, .(ym, TAIL, TAIL_SHAPE, VOL, MSM, BEAR)], by = "ym")
gen <- rbindlist(lapply(c("TAIL","TAIL_SHAPE","VOL","MSM","BEAR"), function(p) {
  rr <- frank(M[[p]]) / nrow(M)
  data.table(predictor = p, cov_rank_r = mean((rr - mean(rr)) * (M$r - mean(M$r))),
             spearman = cor(M[[p]], M$r, method = "spearman"))
}))
cat("[일반성] 승계 예측기 5종 — 순위-수익 공분산 (양수 = 단조감소 매핑이 수익 희생):\n"); print(gen)

## ── 3. 필요조건 역산 — 순효과 양수가 되려면 ─────────────────────────────────
x <- e*r; cc <- ebar*r
drag <- ((stats::var(cc) - stats::var(x))/2) * 12
mean_ch <- mean((e - ebar)*r) * 12
cat(sprintf("\n[역산] 분산드래그 이득 = %+.3f%%/yr. 순효과>0 이려면 평균채널 > %+.3f%%/yr 필요. 실측 %+.3f%%/yr (부족 %.3f%%p)\n",
            100*drag, -100*drag, 100*mean_ch, 100*(-drag - mean_ch)))

write_json(list(
  wt_id = "WT-D20260813_003", stage = "VT_scope", metric_type = "mechanism_observation_posthoc",
  note = "판정(VT2b_REJECT) 확정 후 범위 진단. 파라미터 격자 탐색 0회 — selection_type=chain 불변.",
  sigma_quintiles = tab,
  relation = list(spearman = as.numeric(sp$estimate), spearman_p = sp$p.value,
                  pearson = as.numeric(pe$estimate), pearson_p = pe$p.value,
                  ols_slope = as.numeric(coef(fit)[2]), slope_nw_lag3_t = slope_t_nw,
                  cov_rank_series_nw_lag3_t = cov_t_nw,
                  hi_half_mean_pct = 100*mean(r[hi]), lo_half_mean_pct = 100*mean(r[!hi]),
                  welch_t = as.numeric(tt$statistic), welch_p = tt$p.value,
                  realized_vol_hi = mean(EV$realized_vol[hi]), realized_vol_lo = mean(EV$realized_vol[!hi])),
  generality = list(cov_rank_r_VOL = cov_rank_r, by_predictor = gen,
    statement = "e=g(sigma_hat) 가 단조감소이면 cov(e,r) 부호 = -sign(cov(rank sigma_hat, r)). 실측 cov>0 이므로 sigma*/바닥 값과 무관하게 모든 단조감소 vol-target 매핑이 평균수익을 희생한다. 즉 기각의 범위는 내 파라미터가 아니라 KR 의 sigma->수익 관계."),
  required_mean_channel = list(drag_gain_annual_pct = 100*drag,
    required_mean_channel_annual_pct = -100*drag, observed_mean_channel_annual_pct = 100*mean_ch,
    shortfall_pp = 100*(-drag - mean_ch))
), file.path(OUT, "vt_scope.json"), pretty = TRUE, auto_unbox = TRUE, digits = 6)
cat("\n[done] vt_scope.json written\n")
