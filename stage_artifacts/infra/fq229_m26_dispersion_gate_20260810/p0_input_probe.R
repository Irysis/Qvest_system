## =============================================================================
## FQ-229 P0 — 입력 실측 (판정량 아님)
## 목적: (a) 패널 관측단위·범위 (b) disp_t 계열의 lag1 지속성 = 게이트 설계 가능성
##       (c) 계수-분산 항등식 성분의 존재 확인 (성분 존재만, 판정 아님)
## ★첫 출력은 입력 실측 (feedback-assert-input-shape-before-measuring)
## metric_type: input_probe. 자본 주장 없음.
## =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/fq229_m26_dispersion_gate_20260810")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
SRC <- file.path(ROOT, "stage_artifacts/WT_D20260808_002")
say <- function(fmt, ...) { cat(sprintf(paste0("[p0] ", fmt, "\n"), ...)); flush.console() }

## ---------------------------------------------------------------- [1] 패널
say("================ [1] 패널 입력 실측 ================")
D <- as.data.table(read_parquet(file.path(SRC, "alpha_scores.parquet")))
D[, Date := as.Date(Date)]
say("행수 %d · 열 %s", nrow(D), paste(names(D), collapse = ", "))
say("관측단위 = (signal_ym x Ticker)? 중복 %d", sum(duplicated(D[, .(signal_ym, Ticker)])))
say("개월 %d · %s ~ %s · Ticker %d", uniqueN(D$signal_ym), min(D$signal_ym), max(D$signal_ym), uniqueN(D$Ticker))
say("월당 종목수 min %d / 중앙 %.0f / max %d",
    min(D[, .N, by = signal_ym]$N), median(D[, .N, by = signal_ym]$N), max(D[, .N, by = signal_ym]$N))
nmiss <- sapply(D, function(x) sum(!is.finite(suppressWarnings(as.numeric(x)))))
say("비유한 셀: %s", paste(sprintf("%s=%d", names(nmiss), nmiss), collapse = " · "))

## ---------------------------------------------------------------- [2] disp_t
say("================ [2] disp_t (횡단면 Ret_1m sd) 계열 ================")
MV <- D[, .(N_t = .N, disp_t = sd(Ret_1m), mkt_t = mean(Ret_1m),
            sd_z_t = sd(M26_Revenue_Mom)), by = signal_ym][order(signal_ym)]
say("disp_t n=%d · min %.4f / q25 %.4f / 중앙 %.4f / q75 %.4f / max %.4f · 평균 %.4f",
    nrow(MV), min(MV$disp_t), quantile(MV$disp_t, .25), median(MV$disp_t),
    quantile(MV$disp_t, .75), max(MV$disp_t), mean(MV$disp_t))

## ★lag1 지속성 — 게이트가 성립하려면 disp_{t-1} 이 disp_t 를 예측해야 한다 (설계 입력)
MV[, disp_lag1 := shift(disp_t, 1L)]
ac1 <- cor(MV$disp_t, MV$disp_lag1, use = "complete.obs")
say("★lag1 자기상관 rho = %.4f (n=%d)", ac1, sum(is.finite(MV$disp_lag1)))
for (k in 1:6) say("   lag%d 자기상관 %.4f", k, cor(MV$disp_t, shift(MV$disp_t, k), use = "complete.obs"))

## 로그 변환 계열 (분산은 우편향)
MV[, ldisp := log(disp_t)]; MV[, ldisp_lag1 := shift(ldisp, 1L)]
say("log(disp) lag1 자기상관 %.4f", cor(MV$ldisp, MV$ldisp_lag1, use = "complete.obs"))

## 게이트 발화 표본 (설계 입력 — 문턱별 n)
for (q in c(0.70, 0.60, 0.50)) {
  thr_n <- sum(MV$disp_lag1 >= quantile(MV$disp_lag1, q, na.rm = TRUE), na.rm = TRUE)
  say("   상위 %.0f%% 게이트(전표본 분위 기준) 발화 월수 = %d", (1-q)*100, thr_n)
}
## ★확장 창 분위 (PIT-safe 문턱: t 시점까지의 자료만) — 발화 월수
MV[, exp_q70 := {
  v <- rep(NA_real_, .N)
  for (i in seq_len(.N)) if (i >= 25L) v[i] <- quantile(disp_lag1[1:i], 0.70, na.rm = TRUE)
  v }]
say("★확장창 상위30%% 게이트 발화 월수 = %d (유효 %d개월)",
    sum(MV$disp_lag1 >= MV$exp_q70, na.rm = TRUE), sum(is.finite(MV$exp_q70)))

## ---------------------------------------------------------------- [3] 항등식 성분
say("================ [3] 계수-분산 항등식 성분 (존재 확인만) ================")
say("FMB 단순회귀에서 b_t = cor(z, ret)_t * sd(ret)_t / sd(z)_t 이므로")
say("  disp_t 의존은 (i) 기계적 스케일 (ii) 국면조건부 skill(IC 자체 상승) 둘 다일 수 있다.")
say("  본 P0 는 성분이 산출 가능한지만 확인하고 분해 판정은 PREREG 후 수행한다.")
ic <- D[, .(ic_t = cor(M26_Revenue_Mom, Ret_1m, use = "complete.obs")), by = signal_ym]
say("횡단면 피어슨 cor(z(M26), Ret_1m) 산출 가능: n=%d · 중앙 %.4f", nrow(ic), median(ic$ic_t))
say("sd_z_t 범위 %.4f ~ %.4f (z 정규화 계열이므로 1 근방이어야 함)", min(MV$sd_z_t), max(MV$sd_z_t))

## ---------------------------------------------------------------- [4] 저장
fwrite(MV, file.path(OUT, "p0_monthly_covariates.csv"))
saveRDS(list(n_rows = nrow(D), n_months = uniqueN(D$signal_ym), ac1 = ac1,
             MV = MV, ic_median = median(ic$ic_t)), file.path(OUT, "p0_probe.rds"))
say("저장 완료 -> %s", OUT)
