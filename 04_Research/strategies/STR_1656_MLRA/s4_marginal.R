## ============================================================
## STR_1656_MLRA — S4 한계기여(Marginal Contribution) 테스트
## Stage: S4 Integration Test
## Role: Diversifier
## Anchor: STR_1631_PG2_MDD_OPT (VD+)
## Allocation plan: Anchor 70% + MLRA 30%
## ============================================================

cat("=== STR_1656_MLRA: S4 한계기여 테스트 ===\n")
cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

## 핵심아이디어: ML XGBoost 기반 diversifier가 앵커(VD+)에
## 실질적인 리스크-조정 수익률 개선을 제공하는지 검증.
## Diversifier 요건: delta_SR > 0 AND corr < 0.50

## ----------------------------------------------------------
## 0. 경로 설정
## ----------------------------------------------------------
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"

## config.R 소싱 (필수)
tryCatch(
  source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R")),
  error = function(e) cat("config.R 소싱 오류(무시):", e$message, "\n")
)

## 텔레그램 소싱
tryCatch(
  source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R")),
  error = function(e) cat("telegram_notify.R 소싱 오류(무시):", e$message, "\n")
)

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(arrow)
})

## ----------------------------------------------------------
## 1. NAV 데이터 로드
## ----------------------------------------------------------
cat("--- 1. NAV 데이터 로드 ---\n")

## S1-B NAV (STR_1656_MLRA)
path_mlra <- file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1656_MLRA/output/nav_S1_B.csv")
nav_mlra_raw <- fread(path_mlra)
nav_mlra_raw[, Date := as.Date(Date)]
setkey(nav_mlra_raw, Date)
cat(sprintf("  MLRA NAV: %d rows, %s ~ %s\n",
  nrow(nav_mlra_raw), min(nav_mlra_raw$Date), max(nav_mlra_raw$Date)))

## Anchor NAV (STR_1631_PG2_MDD_OPT) — NAV_vdp 컬럼 사용
path_anchor <- file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1631_PG2_MDD_OPT/output/daily_nav_bcde.csv")
nav_anchor_raw <- fread(path_anchor)
nav_anchor_raw[, Date := as.Date(Date)]
setkey(nav_anchor_raw, Date)
cat(sprintf("  Anchor NAV: %d rows, %s ~ %s\n",
  nrow(nav_anchor_raw), min(nav_anchor_raw$Date), max(nav_anchor_raw$Date)))

## Benchmark
path_bm <- file.path(PROJECT_ROOT, ".cache/benchmark.parquet")
bm_raw <- as.data.table(read_parquet(path_bm))
bm_raw[, Date := as.Date(Date)]
setkey(bm_raw, Date)
cat(sprintf("  Benchmark: %d rows, %s ~ %s\n",
  nrow(bm_raw), min(bm_raw$Date), max(bm_raw$Date)))

## ----------------------------------------------------------
## 2. 수익률 계산 및 날짜 정렬
## ----------------------------------------------------------
cat("\n--- 2. 수익률 계산 및 날짜 정렬 ---\n")

## MLRA 수익률 (Strategy_Ret 컬럼 직접 사용)
mlra_ret <- nav_mlra_raw[, .(Date, ret_mlra = Strategy_Ret)]

## Anchor 수익률 — NAV_vdp에서 직접 계산 (PIT 준수: diff/lag)
anchor_sorted <- nav_anchor_raw[order(Date), .(Date, NAV_vdp)]
n_anchor <- nrow(anchor_sorted)
## t-1 lag 방식으로 수익률 계산 (C9 준수)
anchor_ret_vec <- c(NA_real_, diff(anchor_sorted$NAV_vdp) / head(anchor_sorted$NAV_vdp, -1))
anchor_ret <- data.table(Date = anchor_sorted$Date, ret_anchor = anchor_ret_vec)
anchor_ret <- anchor_ret[!is.na(ret_anchor)]
setkey(anchor_ret, Date)

## BM 수익률 컬럼 확인
bm_col <- if ("BM_Ret" %in% names(bm_raw)) "BM_Ret" else names(bm_raw)[2]
bm_ret <- bm_raw[, .(Date, ret_bm = get(bm_col))]
setkey(bm_ret, Date)

## 겹치는 날짜만 사용 (3-way merge)
dt_merged <- mlra_ret[anchor_ret, on = "Date", nomatch = 0]
dt_merged <- dt_merged[bm_ret, on = "Date", nomatch = 0]
dt_merged <- dt_merged[!is.na(ret_mlra) & !is.na(ret_anchor) & !is.na(ret_bm)]
setkey(dt_merged, Date)

cat(sprintf("  공통 날짜: %d rows, %s ~ %s\n",
  nrow(dt_merged), min(dt_merged$Date), max(dt_merged$Date)))

## ----------------------------------------------------------
## 3. 성과 지표 계산 함수
## ----------------------------------------------------------

calc_perf <- function(ret_vec, label = "") {
  ## 연간 거래일 기준
  n <- length(ret_vec)
  ann_factor <- 252

  ## 연평균 수익률 (CAGR)
  nav_vec <- cumprod(1 + ret_vec)
  years <- n / ann_factor
  cagr <- nav_vec[n]^(1 / years) - 1

  ## 변동성 (연환산)
  vol_ann <- sd(ret_vec, na.rm = TRUE) * sqrt(ann_factor)

  ## Sharpe Ratio (무위험 = 0 가정, 한국 국채 2% 필요 시 조정)
  sr <- if (vol_ann > 0) (cagr / vol_ann) else NA_real_

  ## Sortino Ratio (하방 편차 기준)
  downside_ret <- ret_vec[ret_vec < 0]
  downside_vol <- if (length(downside_ret) > 0) {
    sqrt(sum(downside_ret^2) / n) * sqrt(ann_factor)
  } else { NA_real_ }
  sortino <- if (!is.na(downside_vol) && downside_vol > 0) (cagr / downside_vol) else NA_real_

  ## MDD (Maximum Drawdown)
  nav_curve <- cumprod(1 + ret_vec)
  cum_max <- cummax(nav_curve)
  dd_series <- (nav_curve - cum_max) / cum_max
  mdd <- min(dd_series)

  ## Max DD Duration (일수)
  in_dd <- dd_series < 0
  if (any(in_dd)) {
    rle_dd <- rle(in_dd)
    dd_durations <- rle_dd$lengths[rle_dd$values]
    max_dd_dur <- if (length(dd_durations) > 0) max(dd_durations) else 0L
  } else {
    max_dd_dur <- 0L
  }

  list(
    label    = label,
    n_days   = n,
    cagr     = round(cagr * 100, 2),
    vol_ann  = round(vol_ann * 100, 2),
    sr       = round(sr, 4),
    sortino  = round(sortino, 4),
    mdd      = round(mdd * 100, 2),
    max_dd_dur = max_dd_dur
  )
}

## ----------------------------------------------------------
## 4. Anchor 단독 vs 블렌드 비교 (기본 70/30)
## ----------------------------------------------------------
cat("\n--- 3. Anchor 단독 vs 블렌드 비교 ---\n")

## Anchor 단독
perf_anchor <- calc_perf(dt_merged$ret_anchor, "Anchor_Standalone")
cat(sprintf("  [Anchor 단독] SR=%.4f  CAGR=%.2f%%  MDD=%.2f%%\n",
  perf_anchor$sr, perf_anchor$cagr, perf_anchor$mdd))

## 블렌드 70/30
w_anchor_base <- 0.70
w_mlra_base   <- 0.30
dt_merged[, ret_blend_base := w_anchor_base * ret_anchor + w_mlra_base * ret_mlra]
perf_blend_base <- calc_perf(dt_merged$ret_blend_base, "Blend_70_30")
cat(sprintf("  [Blend 70/30] SR=%.4f  CAGR=%.2f%%  MDD=%.2f%%\n",
  perf_blend_base$sr, perf_blend_base$cagr, perf_blend_base$mdd))

delta_SR_base  <- perf_blend_base$sr  - perf_anchor$sr
delta_MDD_base <- perf_blend_base$mdd - perf_anchor$mdd
corr_base      <- cor(dt_merged$ret_anchor, dt_merged$ret_mlra, use = "complete.obs")

cat(sprintf("  delta_SR  = %.4f  (양수 = 개선)\n", delta_SR_base))
cat(sprintf("  delta_MDD = %.2f%%  (음수 = 개선)\n", delta_MDD_base))
cat(sprintf("  Anchor-MLRA corr = %.4f\n", corr_base))

## ----------------------------------------------------------
## 5. 다양한 배분비 테스트 (90/10 ~ 50/50)
## ----------------------------------------------------------
cat("\n--- 4. 배분비 민감도 분석 ---\n")

weight_pairs <- list(
  c(0.90, 0.10),
  c(0.80, 0.20),
  c(0.70, 0.30),
  c(0.60, 0.40),
  c(0.50, 0.50)
)

blend_results <- lapply(weight_pairs, function(wp) {
  wa <- wp[1]; wm <- wp[2]
  ret_blend <- wa * dt_merged$ret_anchor + wm * dt_merged$ret_mlra
  perf <- calc_perf(ret_blend, sprintf("Blend_%d_%d", round(wa*100), round(wm*100)))
  list(
    label        = perf$label,
    w_anchor     = wa,
    w_mlra       = wm,
    sr           = perf$sr,
    cagr         = perf$cagr,
    mdd          = perf$mdd,
    sortino      = perf$sortino,
    max_dd_dur   = perf$max_dd_dur,
    delta_SR     = round(perf$sr  - perf_anchor$sr,  4),
    delta_MDD    = round(perf$mdd - perf_anchor$mdd, 2)
  )
})

## 결과 출력
cat(sprintf("  %-15s  SR      CAGR%%   MDD%%    dSR     dMDD\n", "Label"))
cat(sprintf("  %-15s  -------  ------  ------  ------  ------\n", ""))
for (r in blend_results) {
  cat(sprintf("  %-15s  %7.4f  %6.2f  %6.2f  %+6.4f  %+6.2f\n",
    r$label, r$sr, r$cagr, r$mdd, r$delta_SR, r$delta_MDD))
}

## 최적 비율 (SR 최대화 기준)
best_idx    <- which.max(sapply(blend_results, function(r) r$sr))
best_result <- blend_results[[best_idx]]
cat(sprintf("\n  최적 비율(SR max): %s  SR=%.4f\n",
  best_result$label, best_result$sr))

## ----------------------------------------------------------
## 6. Correlation Contribution 분석
## ----------------------------------------------------------
cat("\n--- 5. Correlation Contribution 분석 ---\n")

## 공분산 분해: Blended portfolio variance = w_a^2*var_a + w_m^2*var_m + 2*w_a*w_m*cov(a,m)
var_anchor <- var(dt_merged$ret_anchor, na.rm = TRUE)
var_mlra   <- var(dt_merged$ret_mlra,   na.rm = TRUE)
cov_am     <- cov(dt_merged$ret_anchor, dt_merged$ret_mlra, use = "complete.obs")

wa_opt <- best_result$w_anchor
wm_opt <- best_result$w_mlra

var_blend <- wa_opt^2 * var_anchor + wm_opt^2 * var_mlra + 2 * wa_opt * wm_opt * cov_am
contribution_diversification <- 1 - var_blend / (wa_opt^2 * var_anchor + wm_opt^2 * var_mlra)

cat(sprintf("  Anchor 분산: %.6f (연환산 vol %.2f%%)\n",
  var_anchor, sqrt(var_anchor * 252) * 100))
cat(sprintf("  MLRA 분산:   %.6f (연환산 vol %.2f%%)\n",
  var_mlra, sqrt(var_mlra * 252) * 100))
cat(sprintf("  공분산(상관): %.6f (corr=%.4f)\n", cov_am, corr_base))
cat(sprintf("  분산 감소 기여율: %.2f%%\n", contribution_diversification * 100))

## Crisis 구간 상관 (하락장)
bm_q25 <- quantile(dt_merged$ret_bm, 0.25, na.rm = TRUE)
dt_crisis <- dt_merged[ret_bm <= bm_q25]
corr_crisis <- if (nrow(dt_crisis) > 30) {
  cor(dt_crisis$ret_anchor, dt_crisis$ret_mlra, use = "complete.obs")
} else { NA_real_ }

bm_q75 <- quantile(dt_merged$ret_bm, 0.75, na.rm = TRUE)
dt_bull <- dt_merged[ret_bm >= bm_q75]
corr_bull <- if (nrow(dt_bull) > 30) {
  cor(dt_bull$ret_anchor, dt_bull$ret_mlra, use = "complete.obs")
} else { NA_real_ }

cat(sprintf("  전체 상관: %.4f\n", corr_base))
cat(sprintf("  위기 상관(BM 하위 25%%): %.4f\n", corr_crisis))
cat(sprintf("  호황 상관(BM 상위 25%%): %.4f\n", corr_bull))

## ----------------------------------------------------------
## 7. Role Admission 판정 (Diversifier)
## ----------------------------------------------------------
cat("\n--- 6. Role Admission 판정 ---\n")

## Diversifier 요건: delta_SR > 0 AND corr < 0.50
## S2 결과 참고: anchor corr 0.486, crisis corr 0.330

delta_SR_optimal  <- best_result$delta_SR
delta_MDD_optimal <- best_result$delta_MDD

cond_delta_sr  <- delta_SR_optimal > 0
cond_corr      <- corr_base < 0.50
admission_pass <- cond_delta_sr && cond_corr

cat(sprintf("  요건 1 — delta_SR > 0: %.4f  %s\n",
  delta_SR_optimal, ifelse(cond_delta_sr, "PASS", "FAIL")))
cat(sprintf("  요건 2 — corr < 0.50:  %.4f  %s\n",
  corr_base, ifelse(cond_corr, "PASS", "FAIL")))
cat(sprintf("  종합 판정: %s\n", ifelse(admission_pass, "PASS (Diversifier 인정)", "FAIL")))

## ----------------------------------------------------------
## 8. Artifact 저장
## ----------------------------------------------------------
cat("\n--- 7. Artifact 저장 ---\n")

artifact <- list(
  strategy_id     = "STR_1656_MLRA",
  stage           = "S4",
  timestamp       = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  anchor_id       = "STR_1631_PG2_MDD_OPT",
  role            = "Diversifier",
  sample_period   = list(
    start = as.character(min(dt_merged$Date)),
    end   = as.character(max(dt_merged$Date)),
    n_days = nrow(dt_merged)
  ),
  anchor_standalone = list(
    sr      = perf_anchor$sr,
    cagr    = perf_anchor$cagr,
    mdd     = perf_anchor$mdd,
    sortino = perf_anchor$sortino
  ),
  blend_optimal = list(
    label      = best_result$label,
    w_anchor   = best_result$w_anchor,
    w_mlra     = best_result$w_mlra,
    sr         = best_result$sr,
    cagr       = best_result$cagr,
    mdd        = best_result$mdd,
    sortino    = best_result$sortino,
    max_dd_dur = best_result$max_dd_dur
  ),
  delta_SR        = delta_SR_optimal,
  delta_MDD       = delta_MDD_optimal,
  optimal_weight  = best_result$w_mlra,
  corr_full       = round(corr_base, 4),
  corr_crisis     = round(corr_crisis, 4),
  corr_bull       = round(corr_bull, 4),
  diversification_contribution = round(contribution_diversification * 100, 2),
  blend_sensitivity = lapply(blend_results, function(r) {
    list(label=r$label, w_anchor=r$w_anchor, w_mlra=r$w_mlra,
         sr=r$sr, cagr=r$cagr, mdd=r$mdd, delta_SR=r$delta_SR, delta_MDD=r$delta_MDD)
  }),
  admission_pass    = admission_pass,
  admission_reason  = ifelse(admission_pass,
    "delta_SR > 0 AND corr < 0.50: Diversifier 요건 충족",
    paste0(
      ifelse(!cond_delta_sr, "delta_SR <= 0 (SR 개선 없음); ", ""),
      ifelse(!cond_corr,     "corr >= 0.50 (분산화 효과 미흡); ", "")
    )
  )
)

## stage_artifacts/ 디렉토리 확인
artifact_dir <- file.path(PROJECT_ROOT, "stage_artifacts")
if (!dir.exists(artifact_dir)) dir.create(artifact_dir, recursive = TRUE)

artifact_path <- file.path(artifact_dir, "s4_marginal_STR_1656_MLRA.json")
write_json(artifact, artifact_path, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("  Artifact 저장 완료: %s\n", artifact_path))

## STR_1656 strategy-local artifacts 디렉토리에도 저장
local_artifact_dir <- file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1656_MLRA/stage_artifacts")
if (!dir.exists(local_artifact_dir)) dir.create(local_artifact_dir, recursive = TRUE)
local_artifact_path <- file.path(local_artifact_dir, "s4_marginal_STR_1656_MLRA.json")
write_json(artifact, local_artifact_path, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("  로컬 Artifact 저장 완료: %s\n", local_artifact_path))

## ----------------------------------------------------------
## 9. 텔레그램 발송
## ----------------------------------------------------------
cat("\n--- 8. 텔레그램 발송 ---\n")

verdict_emoji <- if (admission_pass) "[PASS]" else "[FAIL]"
delta_sr_str  <- sprintf("%+.4f", delta_SR_optimal)
delta_mdd_str <- sprintf("%+.2f%%", delta_MDD_optimal)

tg_msg <- paste0(
  "[Forge] STR_1656_MLRA S4 한계기여 테스트\n\n",
  "=== S4 Marginal Contribution ===\n",
  "Anchor: STR_1631 VD+ | Role: Diversifier\n",
  "기간: ", min(dt_merged$Date), " ~ ", max(dt_merged$Date),
  " (", nrow(dt_merged), "일)\n\n",
  "--- Anchor 단독 ---\n",
  "SR=", perf_anchor$sr, "  CAGR=", perf_anchor$cagr, "%  MDD=", perf_anchor$mdd, "%\n\n",
  "--- 최적 블렌드 (", best_result$label, ") ---\n",
  "SR=", best_result$sr, "  CAGR=", best_result$cagr, "%  MDD=", best_result$mdd, "%\n\n",
  "--- 한계기여 ---\n",
  "delta_SR  = ", delta_sr_str, "\n",
  "delta_MDD = ", delta_mdd_str, "\n",
  "Anchor-MLRA corr = ", round(corr_base, 4), "\n",
  "위기 corr = ", round(corr_crisis, 4), "\n",
  "분산화 기여율 = ", round(contribution_diversification*100, 2), "%\n\n",
  "--- Diversifier 판정 ---\n",
  "  delta_SR > 0: ", ifelse(cond_delta_sr, "PASS", "FAIL"), "\n",
  "  corr < 0.50: ", ifelse(cond_corr, "PASS", "FAIL"), "\n",
  "  종합: ", verdict_emoji, "\n\n",
  "--- 배분 민감도 ---\n",
  paste(sapply(blend_results, function(r) {
    sprintf("  %s: SR=%.4f CAGR=%.2f%% MDD=%.2f%%",
      r$label, r$sr, r$cagr, r$mdd)
  }), collapse="\n")
)

tryCatch({
  if (exists("tg_send")) {
    tg_send(tg_msg)
    cat("  텔레그램 발송 완료\n")
  } else {
    cat("  tg_send 미정의 — 텔레그램 발송 건너뜀\n")
    cat("  [메시지 내용]\n")
    cat(tg_msg, "\n")
  }
}, error = function(e) {
  cat("  텔레그램 발송 오류:", e$message, "\n")
  cat("  [메시지 내용]\n")
  cat(tg_msg, "\n")
})

## ----------------------------------------------------------
## 10. 최종 요약
## ----------------------------------------------------------
cat("\n============================================================\n")
cat("STR_1656_MLRA S4 한계기여 테스트 완료\n")
cat("============================================================\n")
cat(sprintf("  Anchor SR:       %.4f\n", perf_anchor$sr))
cat(sprintf("  Blend SR(opt):   %.4f  (%s)\n", best_result$sr, best_result$label))
cat(sprintf("  delta_SR:        %+.4f\n", delta_SR_optimal))
cat(sprintf("  delta_MDD:       %+.2f%%\n", delta_MDD_optimal))
cat(sprintf("  Anchor-MLRA corr: %.4f\n", corr_base))
cat(sprintf("  Admission:       %s\n", ifelse(admission_pass, "PASS", "FAIL")))
cat(sprintf("  Artifact:        %s\n", artifact_path))
cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "완료\n")
