## s5_rf.R — rf=0 사전등록 가정의 보수성 정량화 (판정 불변 · 감도 보고)
## ★구조 사실 먼저: exposure-matched 통제도 (1-ebar) 만큼 현금을 든다. 따라서 **상수 rf 는
##   처치-통제 간 정확히 상쇄되어 VT2b 에 영향 0**. 효과는 오직 cov(e_m, rf_m) 에서만 나온다.
##   즉 "고변동월에 금리가 높았는가" 만이 문제. ECOS CD91 은 2005-08~ 만 커버 -> 부분표본 A/B.
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/validation/overlay_pit_guard.R")
BC <- new.env(parent = globalenv()); sys.source("02_Infrastructure/contracts/backtest_result_contract.R", envir = BC)
nw_t <- function(x, lag = 3L) BC$.nw_t_mean(x, lag = lag)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260813_003")
EV <- as.data.table(readRDS(file.path(OUT, "vt_panel.rds"))); setorder(EV, hold_start)

CD <- as.data.table(read_parquet(".cache/ecos_bond_rates.parquet"))[Series == "KR_CD91" & is.finite(Value)][order(Date)]
cat(sprintf("[rf] KR_CD91 일별 n=%d  %s ~ %s\n", nrow(CD), min(CD$Date), max(CD$Date)))
## PIT: 홀딩월 시작 전 마지막 관측
idx <- findInterval(EV$hold_start - 1, CD$Date)
EV[, rf_ann := ifelse(idx >= 1, CD$Value[pmax(idx,1)] / 100, NA_real_)]
EV[idx < 1, rf_ann := NA_real_]
asof <- rep(as.Date(NA), nrow(EV)); asof[idx >= 1] <- CD$Date[idx[idx >= 1]]
assert_overlay_pit(asof[!is.na(asof)], EV$hold_start[!is.na(asof)], label = "rf_asof")
EV[, rf_m := (1 + rf_ann)^(1/12) - 1]
SS <- EV[is.finite(rf_m)]
cat(sprintf("[rf] 커버 부분표본 n=%d  %s ~ %s  (전표본 %d 중 %.1f%%)  평균 rf=%.2f%%/yr\n",
            nrow(SS), SS$ym[1], SS$ym[nrow(SS)], nrow(EV), 100*nrow(SS)/nrow(EV), 100*mean(SS$rf_ann)))

## ── 부분표본 A/B: rf=0 vs rf=CD91 ───────────────────────────────────────────
run_vt2b <- function(e, r, rf) {
  eb <- mean(e)
  x  <- e * r + (1 - e) * rf
  cc <- eb * r + (1 - eb) * rf
  d  <- x - cc
  list(mean_d_ann = mean(d)*12, t = nw_t(d, 3L),
       drag_ann = ((stats::var(cc) - stats::var(x))/2)*12,
       net_ann = (mean(d) + (stats::var(cc) - stats::var(x))/2)*12,
       G = 1 - stats::sd(x)/stats::sd(cc))
}
a0 <- run_vt2b(SS$e, SS$r, rep(0, nrow(SS)))
a1 <- run_vt2b(SS$e, SS$r, SS$rf_m)
cat(sprintf("\n[A/B 부분표본 %s~%s]\n", SS$ym[1], SS$ym[nrow(SS)]))
cat(sprintf("  rf=0    : mean(d)=%+.3f%%/yr  t=%+.3f  drag=%+.3f%%/yr  net=%+.3f%%/yr  G=%.4f\n",
            100*a0$mean_d_ann, a0$t, 100*a0$drag_ann, 100*a0$net_ann, a0$G))
cat(sprintf("  rf=CD91 : mean(d)=%+.3f%%/yr  t=%+.3f  drag=%+.3f%%/yr  net=%+.3f%%/yr  G=%.4f\n",
            100*a1$mean_d_ann, a1$t, 100*a1$drag_ann, 100*a1$net_ann, a1$G))
cat(sprintf("  rf 도입 순효과 변화 = %+.3f%%p  (구조상 cov(e, rf) 항만 기여)\n",
            100*(a1$net_ann - a0$net_ann)))
cov_e_rf <- cov(SS$e, SS$rf_m) * 12
cat(sprintf("  cov(e, rf_m)*12 = %+.5f  -> -cov 기여 = %+.4f%%/yr | cor(e, rf)=%+.4f | cor(sigma_hat, rf)=%+.4f\n",
            cov_e_rf, -100*cov_e_rf, cor(SS$e, SS$rf_m), cor(SS$sigma_d, SS$rf_m)))

## 전표본 필요 rf-공분산 역산: 순효과 0 이 되려면
full_gap <- 0.00691   # s3 실측 순효과 -0.691%/yr
cat(sprintf("\n[역산] 전표본 순효과 부족분 %.3f%%/yr 을 rf 채널로 메우려면 -cov(e, rf_ann) >= %.5f 필요.\n",
            100*full_gap, full_gap))
cat(sprintf("       부분표본 실측 -cov(e, rf_ann) = %+.5f (%.1f%% 충당)\n",
            -cov_e_rf, 100*(-cov_e_rf)/full_gap))

write_json(list(
  wt_id = "WT-D20260813_003", stage = "VT_rf_sensitivity", metric_type = "mechanism_observation_posthoc",
  structural_note = "exposure-matched 통제도 (1-ebar) 현금을 보유하므로 **상수 rf 는 처치-통제 간 정확히 상쇄**. rf 효과는 cov(e_m, rf_m) 에서만 발생.",
  coverage = list(source = ".cache/ecos_bond_rates.parquet::KR_CD91",
    n_covered = nrow(SS), n_full = nrow(EV), window = c(SS$ym[1], SS$ym[nrow(SS)]),
    mean_rf_annual = mean(SS$rf_ann), pit_asof_rule = "Date < first-day-of-holding-month (assert PASS)",
    limitation = "1996-02~2005-07 미커버. 그 구간이 KR 고금리·고변동(1997-98 위기) 이라 rf 채널이 가장 클 곳인데 관측 부재 — 방향(처치군 유리)은 알지만 크기는 미측정. 정직 라벨."),
  subsample_ab = list(rf_zero = a0, rf_cd91 = a1,
    net_change_pp = 100*(a1$net_ann - a0$net_ann),
    cov_e_rf_annual = cov_e_rf, cor_e_rf = cor(SS$e, SS$rf_m), cor_sigma_rf = cor(SS$sigma_d, SS$rf_m)),
  required_rf_channel = list(full_sample_net_shortfall_annual = full_gap,
    observed_neg_cov_subsample = -cov_e_rf, coverage_ratio = (-cov_e_rf)/full_gap),
  verdict_impact = "판정 불변 — prereg 는 rf=0 을 고정했고 구조상 상수 rf 는 상쇄. 부분표본 실측 rf 채널 크기를 감도로 병기."
), file.path(OUT, "vt_rf_sensitivity.json"), pretty = TRUE, auto_unbox = TRUE, digits = 6)
cat("\n[done] vt_rf_sensitivity.json written\n")
