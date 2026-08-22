## WT-D20260822_004 · P2 — ★검정력 관문 (MEAN-BLIND). 처치 paired 평균·t 출력 없음.
suppressPackageStartupMessages({library(data.table)})
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/required_effect_size.R")
OUT <- "stage_artifacts/WT-D20260822_004"; B <- readRDS(file.path(OUT,"p1_arms.rds")); BT <- B$BT
ARMS <- names(BT); TRT <- setdiff(ARMS, "C0_zscore_ew")
getact <- function(b) { pr <- as.data.table(b$period_returns)
  pr[, .(Date = as.Date(date), act = ret_net - benchmark_ret)] }
A <- lapply(BT, getact)
for (a in ARMS) stopifnot(identical(A[[a]]$Date, A$C0_zscore_ew$Date))
n <- nrow(A$C0_zscore_ew); cat(sprintf("\n=== 1) 대조군 parity (공표값 재현) === n=%d\n", n))
cat(sprintf("  C0 PORT_t  측정 %.8f  vs FQ-237 공표 0.94741072  Δ=%.2e  %s\n",
    BT$C0_zscore_ew$portfolio_alpha_t_nw_lag3, BT$C0_zscore_ew$portfolio_alpha_t_nw_lag3-0.94741072,
    abs(BT$C0_zscore_ew$portfolio_alpha_t_nw_lag3-0.94741072) < 1e-6, sep=""))
stopifnot(abs(BT$C0_zscore_ew$portfolio_alpha_t_nw_lag3 - 0.94741072) < 1e-6)

cat("\n=== 2) '물질적 효과' 사전 정의 (C0 를 PORT_t 2.95 로 올리는 데 필요한 연 active 증분) ===\n")
c0 <- A$C0_zscore_ew$act; t0 <- .nw_t_mean(c0, lag=3L); m0 <- mean(c0)
se0 <- m0/t0                                     # NW SE (월)
need_m <- 2.95*se0                               # 문턱 도달에 필요한 월평균 active
MATERIAL <- (need_m - m0)*12*100                 # 연 %p 증분
cat(sprintf("  C0 월평균 active %.5f · NW3 SE %.5f · t %.4f\n", m0, se0, t0))
cat(sprintf("  ⇒ MATERIAL_EFFECT_ANNUAL_PCT = %.4f %%p/yr  (이만큼 개선돼야 결합 마디가 벽을 넘긴다)\n", MATERIAL))

cat("\n=== 3) 처치별 paired diff 의 **분산 특성만** (평균·t 미출력) ===\n")
POW <- rbindlist(lapply(TRT, function(a) {
  d <- A[[a]]$act - c0
  sd_own <- sd(d); nw_meas <- nw_inflation_measured(d, lag=3L)
  re_own <- required_effect(n=n, t_threshold=2.0, sd_monthly=sd_own, design="full",
                            nw_inflation=if (is.finite(nw_meas)) nw_meas else NW_INFLATION_DEFAULT)
  re_band<- required_effect(n=n, t_threshold=2.0, sd_monthly=SPREAD_SD_MONTHLY_25EW, design="full",
                            nw_inflation=if (is.finite(nw_meas)) nw_meas else NW_INFLATION_DEFAULT)
  se_nw  <- sd_own/sqrt(n)*(if (is.finite(nw_meas)) nw_meas else NW_INFLATION_DEFAULT)
  data.table(arm=a, sd_monthly_own=sd_own, sd_band_contract=SPREAD_SD_MONTHLY_25EW,
             sd_ratio_own_vs_band=sd_own/SPREAD_SD_MONTHLY_25EW,
             nw_inflation_measured=nw_meas, se_nw_monthly=se_nw,
             mde_own_annual_pct=re_own$required_annual_pct, mde_band_annual_pct=re_band$required_annual_pct,
             implied_t_own=re_own$required_annual_pct/100/12/se_nw,
             implied_t_band=re_band$required_annual_pct/100/12/se_nw,
             material_over_mde_own=MATERIAL/re_own$required_annual_pct)
}))
print(POW[, .(arm, sd_monthly_own=round(sd_monthly_own,5), sd_ratio=round(sd_ratio_own_vs_band,3),
              nw=round(nw_inflation_measured,3), mde_own=round(mde_own_annual_pct,3),
              mde_band=round(mde_band_annual_pct,3), implied_t_own=round(implied_t_own,4),
              implied_t_band=round(implied_t_band,3), material_over_mde=round(material_over_mde_own,2))])
cat("\n  ★퇴화 점검: implied_t_own 이 2.000 이면 자기-diff sd 바는 t 검정의 재진술(단위 번역)이지 독립 바가 아니다.\n")
cat("     ⇒ 독립 바 = implied_t_band (계약 선언 sd 0.0394 기준). 두 값을 모두 사전등록에 고정한다.\n")
saveRDS(list(A=A, POW=POW, MATERIAL=MATERIAL, n=n, m0=m0, se0=se0, t0=t0), file.path(OUT,"p2_power.rds"))
cat("\n[saved] p2_power.rds\n")
