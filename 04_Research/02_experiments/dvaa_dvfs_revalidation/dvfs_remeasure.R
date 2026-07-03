#=============================================================================#
# Strategy   : VAA-DVFS 재측정 기준선 (dvfs_remeasure)
#
# 출처       : 05_Production/3,Asset_Allocation/3-1.DVAA/DVAA_DVFS_ETF.R (원본 무수정 read-only)
# 설계근거   : 04_Research/asset_allocation/dvaa_dvfs_enhancement_research_2026-06-13.md
# 작성       : 2026-06-13 (Q). 원본은 그대로 보존, 본 사본에 확정 수정만 반영.
#
# 반영된 확정 수정 (도훈 confirm 2026-06-13):
#   [M01] 데이터 무결성 — na.locf0(fromLast=TRUE) 역방향 채움 제거(상장 전 가짜
#         무변동 시계열 차단) + 리밸런스 시점별 가용(eligible) 자산 마스킹 +
#         cov complete.obs + ERC 실패 시 inverse-vol fallback + 가격 스냅샷.
#   [M02] EGARCH 타이밍 정렬(학습창 ep[i-1]→ep[i], 분위수 컷오프 [1:ep[i]]) +
#         fail-unsafe 수리(적합 실패/비정상 예측 시 'Stable' 대신 120일 RV
#         fallback) + fit_status 로깅.
#   [M03] 비용·측정 계약 — fee 레그당 정의 명문화 + 최초 진입비용 보정 +
#         xts::lag.xts 명시 + prod(1+net)-1 → Return.cumulative.
#   [M07] '위기 중 로테이션' 폐기(도훈 mandate) — 안A: 강제 Risk-On 제거,
#         risky_mom_avg>=0이면 VAA 신호(P_wt) 존중. 오버레이·Absolute_Defense 존치.
#   [정본] B=11 유지(디버그 코드 B=10 무시). 허들 정의(상대 허들) 함수형 동결.
#
# 미반영 (confirm 대기 / 별도 ablation arm):
#   M04' breadth 산술위생(best-safe 자기제외 정정) — confirm 대기.
#   M05 graded CF / M06 canary / M10 cov 윈도우 / M11 방어 바스켓 — ablation arm.
#   세후 트랙(양도세 22%) / build_bt_result 브릿지 — M03 후순위 (하단 TODO).
#
# 실행 주의 : yahoo 다운로드 수반. 한글 경로 회피 위해 setwd 제거(QM_ROOT 사용).
#=============================================================================#

#=============================================================================#
# Step 1: Library & GJR/EGARCH Specification Setup
#=============================================================================#
pacman::p_load(
  "quantmod", "PerformanceAnalytics", "tidyverse", "magrittr", "xts",
  "RiskPortfolios", "rugarch", "timeSeries", "TTR", "openxlsx"
)

# EGARCH 스펙 (원본 메인 루프가 실사용하는 모델 — 헤더의 GJR은 미사용 사장코드였음)
egarch_spec <- ugarchspec(
  variance.model = list(model = "eGARCH", garchOrder = c(1, 1)),
  mean.model     = list(armaOrder = c(0, 0))
)

# [M01] 출력 경로 — setwd 하드코딩 제거, QM_ROOT 환경변수 (없으면 현 머신 기본)
qm_root <- Sys.getenv("QM_ROOT", unset = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
out_dir <- file.path(qm_root, "04_Research", "dvaa_dvfs_revalidation")
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

#=============================================================================#
# Step 2: Data Loading & Preprocessing  ([M01])
#=============================================================================#
symbols_DVFS <- c(
  # US Equities
  'SPY', 'QQQ', 'IWM',
  # Foreign Equities
  'ACWX', 'EFA', 'EEM',
  # Alternative Assets
  'IYR', "GLD", "PDBC",
  # US Bonds
  'IEF', 'TLT', 'LQD', 'HYG', 'TIP', 'AGG', 'EMB',
  # MMF / Cash Equivalent
  "SHV"
)   # 실제 17종 (원본 헤더의 'FYF'/18종 표기는 오기)

# [M01] from='2007-01-01' 명시 — quantmod 기본값 암묵 의존 제거(재현성)
getSymbols(symbols_DVFS, src = 'yahoo', from = '2007-01-01', auto.assign = TRUE)

price_DVFS <- do.call(cbind,
                      lapply(symbols_DVFS, function(x) Ad(get(x)))) %>% setNames(symbols_DVFS)

# [M01] 핵심 수정: 역방향 채움(fromLast=TRUE) 제거.
#   원본 na.locf0(price, fromLast=TRUE)는 상장 전 NA를 '미래 첫 거래가'로 역채움 →
#   PDBC(2014-11 상장) 등에 가짜 무변동(일수익 0) 시계열 생성 → 모멘텀/breadth/ERC/NAV 오염.
#   수정: 상장 전 leading NA는 보존, interior 결측만 전방(과거→미래) 채움.
price_DVFS <- na.locf(price_DVFS)        # fromLast 미지정 → leading NA 보존

# [M01] 재현성 스냅샷 — 1회 저장 후 이 파일을 고정 입력으로 쓰는 것을 권장
write.csv(as.data.frame(price_DVFS), file.path(out_dir, 'dvfs_price_snapshot.csv'))

# [M01] na.omit 제거 — 모든 자산 NA-free 행만 남기면 2014-11(PDBC 상장) 이후로 잘림.
#   leading NA 보존하고 루프에서 eligible 마스킹으로 처리. 첫 행(정의상 전부 NA)만 제거.
rets_DVFS <- Return.calculate(price_DVFS)
rets_DVFS <- rets_DVFS[-1, ]

# ADX용 SPY OHLC + 동적 임계용 SMA200 (SPY는 2007 이전 상장 → NA 없음)
spy_ohlc   <- OHLC(SPY)
spy_sma200 <- SMA(price_DVFS$SPY, n = 200)

#=============================================================================#
# Step 3: Parameter Setting
#=============================================================================#
ep <- endpoints(rets_DVFS, on = 'months')
rebalancing_dates <- index(rets_DVFS)[ep]

safe_assets <- c("GLD", "TIP", "TLT")
cash_asset  <- "SHV"

mom_1 <- 1; mom_3 <- 3; mom_6 <- 6; mom_12 <- 12

# [정본] B=11 (디버그 코드 B=10 무시 — 도훈 mandate 2026-06-13)
B <- 11
garch_window <- 120
bull_market_threshold <- 0.99   # 강세장: 둔감(상위 1%)
bear_market_threshold <- 0.90   # 약세장: 민감(상위 10%)
trend_confirmation_lookback <- 10
adx_period <- 14
adx_threshold <- 20

wts <- list()
wts_sort <- list()

# [M02] signal_history 8컬럼 (Fit_Status 추가)
signal_history <- xts(matrix(NA, nrow = length(rebalancing_dates), ncol = 8),
                      order.by = rebalancing_dates)
colnames(signal_history) <- c("VAA_Signal", "GARCH_Signal", "Final_Decision",
                              "Predicted_Vol", "Vol_Threshold", "Market_Trend",
                              "ADX_Value", "Fit_Status")

#=============================================================================#
# Step 4: 자산 배분 루프
#=============================================================================#
for (i in 13:(length(ep))) {

  current_date <- index(rets_DVFS)[ep[i]]

  # --- 4.1 모멘텀 스코어 ---
  sub_ret_mom_1  <- rets_DVFS[ep[i-mom_1]  : ep[i], ]
  sub_ret_mom_3  <- rets_DVFS[ep[i-mom_3]  : ep[i], ]
  sub_ret_mom_6  <- rets_DVFS[ep[i-mom_6]  : ep[i], ]
  sub_ret_mom_12 <- rets_DVFS[ep[i-mom_12] : ep[i], ]

  cum_1  <- Return.cumulative(sub_ret_mom_1)
  cum_3  <- Return.cumulative(sub_ret_mom_3)
  cum_6  <- Return.cumulative(sub_ret_mom_6)
  cum_12 <- Return.cumulative(sub_ret_mom_12)

  cum_wm <- (cum_1*6 + cum_3*6 + cum_6*6 + cum_12*1) / 19   # 원본 커스텀 가중 유지

  # [M01] 가용 자산: 12개월 모멘텀 윈도우가 완전(NA-free)한 자산만 — 상장 전 가짜 시계열 배제
  mom_window_full <- rets_DVFS[ep[i-mom_12] : ep[i], ]
  eligible <- colnames(mom_window_full)[colSums(is.na(mom_window_full)) == 0]
  # [견고성] cum_wm을 named numeric으로 — 단일원소 부분집합 시 drop으로 이름 소실 방지(crash 회피)
  cw <- setNames(as.numeric(cum_wm), colnames(cum_wm))

  # 로깅 변수 초기화
  predicted_vol  <- NA; vol_threshold <- NA
  market_trend_ret <- NA; current_adx <- NA
  fit_status <- NA

  # --- 4.2 동적 변동성 임계치 ---
  current_spy_price  <- as.numeric(price_DVFS[current_date, "SPY"])
  current_spy_sma200 <- as.numeric(spy_sma200[current_date])
  vol_percentile_threshold <- 0.95
  if (!is.na(current_spy_price) && !is.na(current_spy_sma200)) {
    if (current_spy_price > current_spy_sma200) {
      vol_percentile_threshold <- bull_market_threshold   # 강세장 0.99
    } else {
      vol_percentile_threshold <- bear_market_threshold   # 약세장 0.90
    }
  }

  # --- 4.3 GARCH 필터 ([M02]) ---
  garch_signal <- "Stable"

  if (i > 13) {
    # 직전월 보유 안전자산 식별 (worst-safe fallback — 정본; eligible 한정)
    prev_weights <- wts[[i - 13]]
    safe_held <- names(prev_weights)[prev_weights > 0 & names(prev_weights) %in% safe_assets]
    if (length(safe_held) == 0) {
      safe_elig <- intersect(safe_assets, eligible)
      prev_safe_asset_held <- names(which.min(cw[safe_elig]))
    } else {
      prev_safe_asset_held <- safe_held[1]
    }

    # [M02] 학습창을 ep[i]까지로 당김(의사결정 직전) — 미래참조 아님(이전 데이터만 사용)
    garch_data_window <- rets_DVFS[(ep[i] - garch_window + 1):ep[i], prev_safe_asset_held]

    Garch_fit_attempt <- tryCatch(
      ugarchfit(spec = egarch_spec, data = garch_data_window, solver = 'hybrid'),
      error = function(e) NULL)

    # [M02] fail-unsafe 수리: 실패/비정상 시 'Stable' 대신 120일 RV fallback (like-for-like)
    rv_fallback <- function() {
      sd(as.numeric(tail(rets_DVFS[1:ep[i], prev_safe_asset_held], garch_window)),
         na.rm = TRUE) * sqrt(252)
    }
    if (!is.null(Garch_fit_attempt) && inherits(Garch_fit_attempt, "uGARCHfit")) {
      fc <- ugarchforecast(Garch_fit_attempt, n.ahead = 1)
      predicted_vol <- as.numeric(sigma(fc)) * sqrt(252)
      if (!is.finite(predicted_vol)) {
        predicted_vol <- rv_fallback(); fit_status <- 2L   # 2 = RV fallback
      } else {
        fit_status <- 1L                                   # 1 = EGARCH
      }
    } else {
      predicted_vol <- rv_fallback(); fit_status <- 2L
    }

    # [M02] 분위수 임계 — 컷오프 [1:ep[i]]로 일관화
    historical_vols <- rollapply(rets_DVFS[, prev_safe_asset_held], width = garch_window,
                                 FUN = sd, align = "right") * sqrt(252)
    vol_threshold <- quantile(historical_vols[1:ep[i]], vol_percentile_threshold, na.rm = TRUE)

    if (is.finite(predicted_vol) && predicted_vol > vol_threshold) {
      garch_signal <- "Spike"
    }
  }

  # --- 4.4 최종 의사결정 ---
  # 허들 정의(상대 허들) 함수형 동결 — 도훈 결정 1. eligible 마스킹만 적용(데이터 위생).
  safe_elig <- intersect(safe_assets, eligible)
  cash <- names(which.max(cw[safe_elig]))                        # 최고 모멘텀 안전자산
  b    <- cw[eligible] < cw[cash]
  # [M01] 비례 허들: 전 자산(17) 가용 시 sum(b)/17 > 11/17  ⟺  원 규칙 sum(b) > 11 등가
  P_wt <- ifelse(sum(b, na.rm = TRUE) / length(eligible) > B / length(symbols_DVFS), 1, 0)

  final_decision <- ""
  if (garch_signal == "Stable") {
    final_decision <- ifelse(P_wt == 1, "Risk-Off", "Risk-On")
  } else { # Spike
    # 추세 확인 필터 (Absolute_Defense 발동 조건으로 역할 유지)
    market_trend_ret <- Return.cumulative(
      rets_DVFS[(ep[i] - trend_confirmation_lookback + 1):ep[i], "SPY"])
    is_trend_negative <- as.numeric(market_trend_ret) < 0

    spy_adx <- ADX(spy_ohlc, n = adx_period)
    current_adx <- as.numeric(last(spy_adx[paste0("/", current_date)])$ADX)
    is_trend_strong <- !is.na(current_adx) && current_adx > adx_threshold

    if (is_trend_negative && is_trend_strong) {
      # '진짜 위기' — [M07 안A] 강제 Risk-On 로테이션 제거, VAA 신호 존중
      risky_elig <- intersect(setdiff(symbols_DVFS, cash_asset), eligible)  # 가짜0 배제
      risky_mom_avg <- mean(cw[risky_elig], na.rm = TRUE)
      if (is.na(risky_mom_avg)) risky_mom_avg <- -1
      final_decision <- ifelse(risky_mom_avg < 0, "Absolute_Defense",
                               ifelse(P_wt == 1, "Risk-Off", "Risk-On"))
    } else {
      # '가짜 위기' — VAA 신호 복귀(원본 유지)
      final_decision <- ifelse(P_wt == 1, "Risk-Off", "Risk-On")
    }
  }

  # --- 4.5 포트폴리오 구성 ([M01] cov/ERC 강건화) ---
  wt <- rep(0, length(symbols_DVFS)) %>% setNames(symbols_DVFS)

  if (final_decision == "Risk-On") {
    risky_elig <- intersect(setdiff(symbols_DVFS, cash_asset), eligible)
    top_assets_names <- names(sort(cw[risky_elig], decreasing = TRUE))
    top_assets_names <- top_assets_names[seq_len(min(4, length(top_assets_names)))]
    # [M01] complete.obs(비PSD 방지) + ERC 실패 시 inverse-vol fallback
    covmat <- cov(sub_ret_mom_3[, top_assets_names], use = "complete.obs")
    erc_weights <- tryCatch(
      optimalPortfolio(covmat, control = list(type = 'erc', constraint = 'lo')),
      error = function(e) { iv <- 1 / sqrt(diag(covmat)); iv / sum(iv) })
    wt[top_assets_names] <- erc_weights
  } else if (final_decision == "Risk-Off") {
    wt[cash] <- 1
  } else { # Absolute_Defense
    wt[cash_asset] <- 1
  }

  wts[[i-12]]      <- xts(t(wt), order.by = index(rets_DVFS[ep[i]]))
  wts_sort[[i-12]] <- wts[[i-12]] %>% as.data.frame() %>% relocate(colnames(price_DVFS))

  signal_history[current_date, ] <- c(
    ifelse(P_wt == 1, 1, 0),
    ifelse(garch_signal == "Spike", 1, 0),
    match(final_decision, c("Risk-On", "Risk-Off", "Absolute_Defense")),
    round(predicted_vol * 100, 2),
    round(vol_threshold * 100, 2),
    round(as.numeric(market_trend_ret) * 100, 2),
    round(current_adx, 2),
    ifelse(is.na(fit_status), NA, fit_status)
  )
}

wts_VAA_DVFS <- do.call(rbind, wts_sort)

#=============================================================================#
# Step 5: Performance ([M03] 비용·측정 계약)
#=============================================================================#
# [M01] 회계 레이어: 신호·배분 결정 완료 후, Return.portfolio 입력용으로만 상장 전 NA를 0 치환.
#   해당 자산 비중은 항상 0이므로 NAV 기여 없음(신호 레이어의 NA 보존과 분리).
rets_acct <- rets_DVFS
rets_acct[is.na(rets_acct)] <- 0

VAA_DVFS_ETF <- Return.portfolio(rets_acct, wts_VAA_DVFS, wealth.index = TRUE, verbose = TRUE)

# [M03] Turnover — 양레그 |Δw| 합산. xts::lag.xts 명시(패키지 로드순서 취약성 제거)
to <- rowSums(abs(VAA_DVFS_ETF$BOP.Weight - xts::lag.xts(VAA_DVFS_ETF$EOP.Weight)), na.rm = TRUE)
# [M03] 최초 진입비용 보정 — 첫 리밸런스 100% 진입(원본은 lag NA→0으로 누락)
to[1] <- rowSums(abs(coredata(VAA_DVFS_ETF$BOP.Weight)[1, , drop = FALSE]), na.rm = TRUE)
VAA_DVFS_ETF$turnover <- xts(to, order.by = index(VAA_DVFS_ETF$BOP.Weight))

# [M03] turnover = |BOP - lag(EOP)| 양레그 합산(완전 교체 1회 = 2.0). fee = 레그당(one-way) 20bps.
#   완전 교체 1회 비용 = 2.0 × 0.002 = 0.4%. Risk-On↔Off 왕복(2회 전환) ≈ 0.8%.
#   비용모델 = US ETF 트랙 20bps/leg (KR book v2.4_kr_retail_15bps와 별개). metric_type = 'estimated'.
fee <- 0.002
VAA_DVFS_ETF$net <- VAA_DVFS_ETF$returns - VAA_DVFS_ETF$turnover * fee   # metric_type='estimated'

# [M03] 자체합성 금지(answer-principles) — prod(1+net)-1 대신 표준함수
total_net_cum <- Return.cumulative(VAA_DVFS_ETF$net)

# 벤치마크 = SPY (※ §5-4 한계: 글로벌 멀티에셋을 단일 BM으로 채점 — 자본 게이트 전 BM 재검토 필요)
rets_BM <- rets_acct
check <- cbind(VAA_DVFS_ETF$net, rets_BM$SPY, rets_BM$GLD, rets_BM$TLT) %>% na.omit()
colnames(check) <- c("DVFS_remeasure", "SPY", "GLD", "TLT")

stratStats <- function(x) {
  stats <- rbind(table.AnnualizedReturns(x), maxDrawdown(x))
  stats[5, ] <- stats[1, ] / stats[4, ]
  stats[6, ] <- stats[1, ] / UlcerIndex(x)
  rownames(stats)[4] <- "Maximum Drawdown"
  rownames(stats)[5] <- "Calmar Ratio"
  rownames(stats)[6] <- "Ulcer Performance Index"
  return(stats)
}

cat("\n===== DVFS_remeasure 성과 (net, fee 레그당 20bps) =====\n")
print(stratStats(check))
cat("\n전구간 net 누적수익:", round(as.numeric(total_net_cum) * 100, 2), "%\n")

# 최신 보유 종목·비중 (최근 리밸런스)
cat("\n===== 최신 보유 (최근 리밸런스) =====\n")
latest_wt <- wts_VAA_DVFS[nrow(wts_VAA_DVFS), , drop = FALSE]
latest_held <- latest_wt[, as.numeric(latest_wt[1, ]) > 0, drop = FALSE]
cat("리밸런스일:", rownames(latest_wt), "\n")
print(round(latest_held, 4))
cat("최근 12개월 비중 이력:\n")
print(round(tail(wts_VAA_DVFS, 12), 4))

#=============================================================================#
# Step 6: 오염 실측 진단 (M01 검증) + 저장
#=============================================================================#
# [M01 검증] 가짜 PDBC 보유 제거 확인 — 2014-11-07(상장) 이전에 PDBC 비중>0인 달이 있으면 오염 잔존
#   주의: wts_VAA_DVFS는 data.frame → index()가 정수(1:n) 반환. rownames(날짜) 기준 비교 필수.
.wts_dates <- as.Date(rownames(wts_VAA_DVFS))
pdbc_pre <- sum(wts_VAA_DVFS[.wts_dates < as.Date("2014-11-07"), "PDBC"] > 0, na.rm = TRUE)
cat("\n[M01 검증] 2014-11-07 이전 PDBC 보유월 수 (0 이어야 정상):", pdbc_pre, "\n")

# fit_status 분포 (M02: fail-unsafe 모니터링)
cat("[M02] Fit_Status 분포 (1=EGARCH, 2=RV fallback):\n")
print(table(as.numeric(signal_history[, "Fit_Status"]), useNA = "ifany"))

# 저장 — [F-11] export 슬라이스 13:nrow (첫 의사결정 = ep[13], 1~12행은 NA)
write.xlsx(as.data.frame(wts_VAA_DVFS), file.path(out_dir, "wts_DVFS_remeasure.xlsx"), rowNames = TRUE)
sh_rows <- 13:nrow(signal_history)
write.xlsx(as.data.frame(signal_history[sh_rows, ]),
           file.path(out_dir, "DVFS_remeasure_signal_history.xlsx"), rowNames = TRUE)
write.xlsx(apply.yearly(check, Return.cumulative) %>% as.data.frame(),
           file.path(out_dir, "DVFS_remeasure_yearly.xlsx"), rowNames = TRUE)

cat("\n저장 완료:", out_dir, "\n")

#=============================================================================#
# TODO (후순위 — 보고서 M03 (d)(e)):
#   - 세후 트랙: 해외주식 양도세 22%(기본공제 250만, 당해연도 전량 실현) + 배당
#     원천징수 15% 반영한 after-tax NAV (metric_type='estimated').
#   - build_bt_result() 브릿지: 10-component + audit + metric_type='backtested'.
#   - contaminated 재현 런(원본 역채움 로직) 병행 → 월별 final_decision/비중 diff.
#=============================================================================#
