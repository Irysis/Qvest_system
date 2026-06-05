cat("=== STR_1659: RF_UA S4 한계기여 테스트 ===\n")
## 핵심아이디어: Uncertainty-Aware Random Forest의 기존 포트폴리오 한계기여 측정
## 현재 2-sleeve (Anchor 80% + XGB M05 20%, SR 1.193) 대비 RF 추가 효과 분석

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
ARTIFACT_DIR <- file.path(PROJECT_ROOT, "stage_artifacts")

# ─── 1. NAV 데이터 로드 ────────────────────────────────────────────────────────
cat("\n[1/5] NAV 데이터 로드 중...\n")

path_anchor <- file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1631_PG2_MDD_OPT/output/daily_nav_bcde.csv")
path_xgb    <- file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1656_MLRA/output/s5_mutations/M05/nav.csv")
path_rf     <- file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1659_RF_UA/output/nav_S1_B.csv")

anchor_raw <- fread(path_anchor)
xgb_raw    <- fread(path_xgb)
rf_raw     <- fread(path_rf)

# 앵커: NAV_vdp 컬럼 추출
anchor_dt <- anchor_raw[, .(Date = as.Date(Date), NAV_anchor = NAV_vdp)]

# XGB: NAV 컬럼 (3번째)
setnames(xgb_raw, names(xgb_raw), c("Date", "Ret_xgb", "NAV_xgb"))
xgb_dt <- xgb_raw[, .(Date = as.Date(Date), NAV_xgb)]

# RF: NAV_Strategy
setnames(rf_raw, names(rf_raw), c("Date", "NAV_rf"))
rf_dt <- rf_raw[, .(Date = as.Date(Date), NAV_rf)]

# ─── 2. 공통 기간 병합 ────────────────────────────────────────────────────────
cat("[2/5] 공통 기간 병합 중...\n")

merged <- Reduce(function(a, b) merge(a, b, by = "Date", all = FALSE),
                 list(anchor_dt, xgb_dt, rf_dt))

setkey(merged, Date)
n_days <- nrow(merged)
cat(sprintf("  공통 날짜: %s ~ %s (%d일)\n",
            min(merged$Date), max(merged$Date), n_days))

# ─── 3. 수익률 계산 ────────────────────────────────────────────────────────────
cat("[3/5] 수익률 및 성과 지표 계산 중...\n")

# NAV → 수익률 변환
calc_ret <- function(nav) c(NA_real_, diff(nav) / head(nav, -1))

merged[, Ret_anchor := calc_ret(NAV_anchor)]
merged[, Ret_xgb    := calc_ret(NAV_xgb)]
merged[, Ret_rf     := calc_ret(NAV_rf)]
merged <- merged[!is.na(Ret_anchor)]  # 첫 행 제거

# ─── 성과 지표 계산 함수 ──────────────────────────────────────────────────────
calc_perf <- function(rets, ann = 252) {
  mu   <- mean(rets, na.rm = TRUE)
  sd_  <- sd(rets, na.rm = TRUE)
  sr   <- (mu / sd_) * sqrt(ann)
  cagr <- (prod(1 + rets, na.rm = TRUE)^(ann / length(rets)) - 1) * 100

  nav_cum <- cumprod(1 + rets)
  dd      <- nav_cum / cummax(nav_cum) - 1
  mdd     <- min(dd) * 100

  list(sr = round(sr, 4), cagr = round(cagr, 2), mdd = round(mdd, 2))
}

# 기존 2-sleeve 수익률 (Anchor 80% + XGB 20%)
merged[, Ret_2sleeve := 0.80 * Ret_anchor + 0.20 * Ret_xgb]

perf_2sleeve  <- calc_perf(merged$Ret_2sleeve)
perf_anchor_s <- calc_perf(merged$Ret_anchor)
perf_rf_s     <- calc_perf(merged$Ret_rf)

cat(sprintf("  앵커 단독:    SR=%.4f, CAGR=%.2f%%, MDD=%.2f%%\n",
            perf_anchor_s$sr, perf_anchor_s$cagr, perf_anchor_s$mdd))
cat(sprintf("  기존 2-sleeve: SR=%.4f, CAGR=%.2f%%, MDD=%.2f%%\n",
            perf_2sleeve$sr, perf_2sleeve$cagr, perf_2sleeve$mdd))
cat(sprintf("  RF 단독:      SR=%.4f, CAGR=%.2f%%, MDD=%.2f%%\n",
            perf_rf_s$sr, perf_rf_s$cagr, perf_rf_s$mdd))

# ─── 4. 블렌드 시나리오 계산 ─────────────────────────────────────────────────
cat("[4/5] 블렌드 시나리오 계산 중...\n")

# 상관관계 계산
corr_rf_anchor  <- cor(merged$Ret_rf, merged$Ret_anchor,  use = "complete.obs")
corr_rf_2sleeve <- cor(merged$Ret_rf, merged$Ret_2sleeve, use = "complete.obs")

# 위기 구간 상관 (MDD 상위 10% 날짜)
nav_2sleeve <- cumprod(1 + merged$Ret_2sleeve)
dd_2sleeve  <- nav_2sleeve / cummax(nav_2sleeve) - 1
crisis_idx  <- which(dd_2sleeve <= quantile(dd_2sleeve, 0.10))
corr_crisis <- if (length(crisis_idx) > 20) {
  cor(merged$Ret_rf[crisis_idx], merged$Ret_2sleeve[crisis_idx], use = "complete.obs")
} else NA_real_

# 강세 구간 상관
bull_idx    <- which(dd_2sleeve >= quantile(dd_2sleeve, 0.75))
corr_bull   <- if (length(bull_idx) > 20) {
  cor(merged$Ret_rf[bull_idx], merged$Ret_2sleeve[bull_idx], use = "complete.obs")
} else NA_real_

# Rolling 12M 상관 (252거래일)
roll_n <- 252
if (nrow(merged) >= roll_n + 10) {
  roll_corr <- sapply((roll_n + 1):nrow(merged), function(i) {
    idx <- (i - roll_n):(i - 1)
    cor(merged$Ret_rf[idx], merged$Ret_2sleeve[idx], use = "complete.obs")
  })
  roll_corr_mean   <- round(mean(roll_corr,   na.rm = TRUE), 4)
  roll_corr_sd     <- round(sd(roll_corr,     na.rm = TRUE), 4)
  roll_corr_max    <- round(max(roll_corr,    na.rm = TRUE), 4)
  roll_corr_min    <- round(min(roll_corr,    na.rm = TRUE), 4)
} else {
  roll_corr_mean <- roll_corr_sd <- roll_corr_max <- roll_corr_min <- NA_real_
}

cat(sprintf("  RF↔앵커 상관: %.4f\n",  corr_rf_anchor))
cat(sprintf("  RF↔2sleeve 상관: %.4f (위기: %.4f, 강세: %.4f)\n",
            corr_rf_2sleeve,
            ifelse(is.na(corr_crisis), NA_real_, corr_crisis),
            ifelse(is.na(corr_bull),   NA_real_, corr_bull)))
cat(sprintf("  Rolling 12M 상관: 평균=%.4f, SD=%.4f, 범위=[%.4f, %.4f]\n",
            roll_corr_mean, roll_corr_sd, roll_corr_min, roll_corr_max))

# ─── 블렌드 조합 ──────────────────────────────────────────────────────────────
# 시나리오 A: 3-sleeve (Anchor 70% + XGB 15% + RF 15%)
# 시나리오 B-E: RF 비중 민감도 (5/10/15/20%, Anchor+XGB 나머지)
# 시나리오 F: 2-sleeve 대체 (Anchor 80% + RF 20%)

make_blend <- function(w_a, w_x, w_r, label) {
  ret_blend <- w_a * merged$Ret_anchor +
               w_x * merged$Ret_xgb   +
               w_r * merged$Ret_rf
  p <- calc_perf(ret_blend)
  list(
    label     = label,
    w_anchor  = w_a, w_xgb = w_x, w_rf = w_r,
    sr        = p$sr,
    cagr      = p$cagr,
    mdd       = p$mdd,
    delta_SR  = round(p$sr  - perf_2sleeve$sr,  4),
    delta_MDD = round(p$mdd - perf_2sleeve$mdd, 2)
  )
}

scenarios <- list(
  # 기준선
  make_blend(0.80, 0.20, 0.00, "Baseline_2sleeve"),
  # A: 3-sleeve
  make_blend(0.70, 0.15, 0.15, "3sleeve_70_15_15"),
  # B: RF 비중 민감도 (Anchor+XGB 잔여 = 나머지, XGB 고정 20%)
  make_blend(0.75, 0.20, 0.05, "RF05_Anc75_XGB20"),
  make_blend(0.70, 0.20, 0.10, "RF10_Anc70_XGB20"),
  make_blend(0.65, 0.20, 0.15, "RF15_Anc65_XGB20"),
  make_blend(0.60, 0.20, 0.20, "RF20_Anc60_XGB20"),
  # C: 2-sleeve 대체 (XGB 없이)
  make_blend(0.80, 0.00, 0.20, "Alt2sleeve_Anc80_RF20")
)

# 결과 출력
cat("\n  --- 블렌드 시나리오 결과 ---\n")
cat(sprintf("  %-30s  SR     CAGR   MDD    dSR    dMDD\n", "라벨"))
cat(sprintf("  %s\n", paste(rep("-", 75), collapse = "")))
for (s in scenarios) {
  cat(sprintf("  %-30s  %.4f  %5.2f%%  %6.2f%%  %+.4f  %+.2f%%\n",
              s$label, s$sr, s$cagr, s$mdd, s$delta_SR, s$delta_MDD))
}

# ─── 5. Role Admission 판정 ───────────────────────────────────────────────────
cat("\n[5/5] Role Admission 판정 중...\n")

# 최적 3-sleeve 시나리오 선택 (delta_SR 최대)
three_sleeve_candidates <- scenarios[sapply(scenarios, function(s)
  grepl("3sleeve|RF", s$label) & s$label != "Baseline_2sleeve")]
best_idx <- which.max(sapply(three_sleeve_candidates, function(s) s$delta_SR))
best     <- three_sleeve_candidates[[best_idx]]

# 2-sleeve 대체 시나리오
alt2s <- scenarios[[which(sapply(scenarios, function(s) s$label == "Alt2sleeve_Anc80_RF20"))]]

delta_SR_best  <- best$delta_SR
delta_SR_alt2s <- alt2s$delta_SR
corr_check     <- abs(corr_rf_2sleeve) < 0.50

admission_pass <- (delta_SR_best > 0) && corr_check
admission_reason <- if (admission_pass) {
  sprintf("delta_SR=%.4f > 0 AND |corr|=%.4f < 0.50: Diversifier 요건 충족",
          delta_SR_best, corr_rf_2sleeve)
} else {
  reason <- c()
  if (delta_SR_best <= 0)   reason <- c(reason, sprintf("delta_SR=%.4f <= 0", delta_SR_best))
  if (!corr_check)          reason <- c(reason, sprintf("|corr|=%.4f >= 0.50", corr_rf_2sleeve))
  paste(reason, collapse = "; ")
}

cat(sprintf("  최적 시나리오: %s\n",  best$label))
cat(sprintf("  delta_SR:     %+.4f\n", delta_SR_best))
cat(sprintf("  상관계수:      %.4f (기준 < 0.50)\n", corr_rf_2sleeve))
cat(sprintf("  Admission:     %s\n",   if (admission_pass) "PASS" else "FAIL"))
cat(sprintf("  사유:          %s\n",   admission_reason))

# ─── 6. Artifact 저장 ─────────────────────────────────────────────────────────
artifact <- list(
  strategy_id   = "STR_1659_RF_UA",
  stage         = "S4",
  timestamp     = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  anchor_id     = "STR_1631_PG2_MDD_OPT",
  xgb_id        = "STR_1656_MLRA_M05",
  role          = "Diversifier",
  sample_period = list(
    start  = as.character(min(merged$Date)),
    end    = as.character(max(merged$Date)),
    n_days = n_days
  ),
  baseline_2sleeve = list(
    sr   = perf_2sleeve$sr,
    cagr = perf_2sleeve$cagr,
    mdd  = perf_2sleeve$mdd
  ),
  rf_standalone = list(
    sr   = perf_rf_s$sr,
    cagr = perf_rf_s$cagr,
    mdd  = perf_rf_s$mdd
  ),
  correlation = list(
    corr_rf_2sleeve   = round(corr_rf_2sleeve, 4),
    corr_rf_anchor    = round(corr_rf_anchor,  4),
    corr_crisis       = round(corr_crisis,     4),
    corr_bull         = round(corr_bull,       4),
    rolling_12m_mean  = roll_corr_mean,
    rolling_12m_sd    = roll_corr_sd,
    rolling_12m_max   = roll_corr_max,
    rolling_12m_min   = roll_corr_min
  ),
  scenarios = scenarios,
  best_3sleeve = best,
  alt_2sleeve  = alt2s,
  delta_SR     = delta_SR_best,
  admission_pass   = admission_pass,
  admission_reason = admission_reason
)

out_path <- file.path(ARTIFACT_DIR, "s4_marginal_STR_1659_RF_UA.json")
write_json(artifact, out_path, auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[Artifact] 저장 완료: %s\n", out_path))

# ─── 7. 텔레그램 발송 ─────────────────────────────────────────────────────────
tryCatch({
  source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

  status_icon <- if (admission_pass) "PASS" else "FAIL"

  msg <- paste0(
    "[Forge] STR_1659_RF_UA S4 한계기여 완료\n\n",
    "[ Baseline 2-sleeve ]\n",
    sprintf("  Anchor 80%% + XGB 20%% => SR %.4f | CAGR %.2f%% | MDD %.2f%%\n\n",
            perf_2sleeve$sr, perf_2sleeve$cagr, perf_2sleeve$mdd),
    "[ RF 단독 성과 ]\n",
    sprintf("  SR %.4f | CAGR %.2f%% | MDD %.2f%%\n\n", perf_rf_s$sr, perf_rf_s$cagr, perf_rf_s$mdd),
    "[ 상관계수 ]\n",
    sprintf("  RF <> 2sleeve: %.4f (위기: %.4f)\n\n",
            corr_rf_2sleeve,
            ifelse(is.na(corr_crisis), NA_real_, corr_crisis)),
    "[ 최적 시나리오: ", best$label, " ]\n",
    sprintf("  SR %.4f | CAGR %.2f%% | MDD %.2f%%\n",
            best$sr, best$cagr, best$mdd),
    sprintf("  dSR %+.4f | dMDD %+.2f%%\n\n",
            best$delta_SR, best$delta_MDD),
    "[ 2-sleeve 대체 (XGB 없이) ]\n",
    sprintf("  Anchor 80%% + RF 20%%: SR %.4f | dSR %+.4f\n\n",
            alt2s$sr, alt2s$delta_SR),
    sprintf("[ Role Admission: %s ]\n", status_icon),
    admission_reason
  )

  tg_send(msg)
  cat("[텔레그램] 발송 완료\n")
}, error = function(e) {
  cat(sprintf("[텔레그램] 발송 실패: %s\n", e$message))
})

cat("\n=== S4 한계기여 테스트 완료 ===\n")
