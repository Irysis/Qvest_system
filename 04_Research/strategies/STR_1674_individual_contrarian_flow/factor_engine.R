#==============================================================================
# STR_1674 Individual Contrarian Flow — Factor Engine
# 개인투자자 월간 순매도(=개인 순매수의 역부호) contrarian alpha
#
# 설계 원칙:
#   - C1: 크로스섹션 Z-score → expanding window (full-sample 금지)
#   - C2: 월별 신호는 month-end t에 확정, t+1 첫 거래일에 체결 (PIT 준수)
#   - C3: 동기간 집계→적용 금지. 시그널 월 = 집계 기준월, 포트폴리오 실행 = 다음 달
#   - C13: Z_Score_Aligned 방향 반전 금지 (contrarian = 음수 순매수 방향)
#
# 출력: FACTORS data.table (Date=시그널월말, Ticker, Score)
#==============================================================================

build_individual_contrarian_signal <- function(RAWDATA,
                                                investor_dt  = NULL,
                                                ma_months    = 3L,
                                                min_history  = 6L) {
  cat("[factor_engine] Building Individual Contrarian Flow signal...\n")

  # ── 1. 투자자 데이터 로드 (1회) ────────────────────────────────────────────
  if (is.null(investor_dt)) {
    cat("  [1] Loading investor_wide.parquet...\n")
    investor_dt <- as.data.table(arrow::read_parquet(INVESTOR_WIDE_CACHE))
    investor_dt[, Date := as.Date(Date)]
  }
  setDT(investor_dt)
  cat(sprintf("  Investor rows: %s | %s ~ %s\n",
              format(nrow(investor_dt), big.mark = ","),
              min(investor_dt$Date), max(investor_dt$Date)))

  # ── 2. 월별 개인 순매수 집계 ────────────────────────────────────────────────
  # C3 준수: 집계 기준 = 해당 월 (month-end에 관찰 가능한 데이터만)
  # 각 거래일의 날짜를 "해당 월의 마지막 날" 기준으로 묶음
  investor_dt[, YearMonth := format(Date, "%Y-%m")]

  # 월간 Individual 순매수 합계 (원 단위)
  monthly_flow <- investor_dt[, .(
    IndividualNetBuy_Sum = sum(Individual, na.rm = TRUE)
  ), by = .(YearMonth, Ticker)]

  # 월말 날짜 파생 (시그널 날짜 = 해당 월의 마지막 영업일)
  # RAWDATA에서 각 YearMonth의 마지막 거래일을 가져옴
  setDT(RAWDATA)
  rawdata_dates <- unique(RAWDATA[, .(Date)])
  rawdata_dates[, YearMonth := format(Date, "%Y-%m")]
  month_end_dates <- rawdata_dates[, .(SignalDate = max(Date)), by = YearMonth]

  monthly_flow <- merge(monthly_flow, month_end_dates,
                        by = "YearMonth", all.x = TRUE)
  monthly_flow <- monthly_flow[!is.na(SignalDate)]
  setorder(monthly_flow, Ticker, SignalDate)

  cat(sprintf("  Monthly flow rows: %s | %d tickers\n",
              format(nrow(monthly_flow), big.mark = ","),
              uniqueN(monthly_flow$Ticker)))

  # ── 3. Contrarian 방향 전환: 개인 순매도 = -IndividualNetBuy ────────────────
  # 개인이 팔수록 신호 값이 높아짐 (contrarian alpha: 개인 매도 종목 매수)
  # C13: 수동 flip이 아닌, 신호 자체의 경제적 부호 설정
  monthly_flow[, ContrarianRaw := -IndividualNetBuy_Sum]

  # ── 4. 3개월 이동평균 평활 (turnover 감소) ──────────────────────────────────
  # C1 준수: 이동평균은 과거 데이터만 사용 (align="right")
  setorder(monthly_flow, Ticker, SignalDate)
  monthly_flow[, Contrarian_3MA := frollmean(ContrarianRaw,
                                              n     = ma_months,
                                              align = "right",
                                              na.rm = TRUE),
               by = Ticker]

  # 3MA 구성에 필요한 최소 관측치 부족 → NA 처리
  monthly_flow[, obs_count := frollsum(!is.na(ContrarianRaw),
                                        n     = ma_months,
                                        align = "right"),
               by = Ticker]
  monthly_flow[obs_count < 2L, Contrarian_3MA := NA_real_]

  cat(sprintf("  After 3MA: %d non-NA signals\n",
              sum(!is.na(monthly_flow$Contrarian_3MA))))

  # ── 5. 시가총액 추출 (Size 중립화를 위한 log(Mktcap)) ──────────────────────
  # Size 컬럼 = 시가총액 (RAWDATA에서 월말 값 사용)
  mktcap_dt <- RAWDATA[, .(Size = last(Size)), by = .(YearMonth = format(Date, "%Y-%m"), Ticker)]
  mktcap_dt <- merge(mktcap_dt, month_end_dates, by = "YearMonth", all.x = TRUE)
  mktcap_dt[, LogMktcap := log(pmax(Size, 1e6))]  # log(시가총액), 0 방지

  monthly_flow <- merge(monthly_flow,
                        mktcap_dt[, .(SignalDate, Ticker, LogMktcap)],
                        by = c("SignalDate", "Ticker"), all.x = TRUE)

  # ── 6. 크로스섹션 Size 중립화 (잔차 신호) ──────────────────────────────────
  # 각 월 단면 OLS: Contrarian_3MA ~ LogMktcap → 잔차가 size-neutral 신호
  # C1 준수: expanding Z-score (full-sample 통계 금지)
  signal_dates_ordered <- sort(unique(monthly_flow$SignalDate))

  size_neutral_list <- lapply(signal_dates_ordered, function(m) {
    sub <- monthly_flow[SignalDate == m & !is.na(Contrarian_3MA) & !is.na(LogMktcap)]
    if (nrow(sub) < 20L) return(NULL)

    # Cross-sectional OLS residual (size neutralization)
    # sub 이미 !is.na(Contrarian_3MA) & !is.na(LogMktcap) 필터 통과
    tryCatch({
      fit        <- lm(Contrarian_3MA ~ LogMktcap, data = sub, na.action = na.omit)
      # lm na.omit 후 실제 사용된 행 복원 (na.action 속성 활용)
      used_idx   <- as.integer(rownames(model.frame(fit)))
      sub_used   <- sub[used_idx]
      sub_used[, Residual := residuals(fit)]
      sub_used[, .(SignalDate, Ticker, Residual)]
    }, error = function(e) {
      # OLS 실패 시 원 신호 그대로 (fallback)
      sub_fb <- copy(sub)
      sub_fb[, Residual := Contrarian_3MA]
      sub_fb[, .(SignalDate, Ticker, Residual)]
    })
  })
  size_neutral_list <- size_neutral_list[!sapply(size_neutral_list, is.null)]
  size_neutral <- rbindlist(size_neutral_list)
  setorder(size_neutral, SignalDate, Ticker)

  cat(sprintf("  Size-neutral signals: %d rows | %d months\n",
              nrow(size_neutral), uniqueN(size_neutral$SignalDate)))

  # ── 7. Expanding-window 크로스섹션 Z-score (C1 엄격 준수) ──────────────────
  # 각 날짜(t)에서 expanding window: t 이전 모든 크로스섹션 잔차의 평균/표준편차
  # 단, 같은 날짜 내의 크로스섹션 z-score는 허용 (표준화 목적)
  # 방법: 크로스섹션 rank → Z-score (order-based, 전 구간 분포 불필요)
  #        expanding mean/sd를 사용해 시계열 방향 표준화는 크로스섹션 내에서만

  # 접근: 각 월 내 크로스섹션 rank-Z (표준 정규 변환)
  # 이후 expanding 히스토리로 보정할 필요 없음 (rank 기반 = 비모수적으로 PIT 안전)
  size_neutral[, XS_Rank := frankv(Residual, ties.method = "average",
                                    na.last = "keep") / (.N + 1),
               by = SignalDate]
  # Probit 변환 → 표준 정규 (expanding 통계량 불필요, 당월 크로스섹션만 사용)
  size_neutral[, Score := qnorm(XS_Rank)]

  # 유효 범위 clip
  size_neutral[Score > 4,  Score :=  4]
  size_neutral[Score < -4, Score := -4]
  size_neutral <- size_neutral[!is.na(Score)]

  # ── 8. 출력 FACTORS 테이블 ──────────────────────────────────────────────────
  FACTORS <- size_neutral[, .(Date = SignalDate, Ticker, Score)]
  setkey(FACTORS, Date, Ticker)

  cat(sprintf("[factor_engine] Done. %d signals | %d months | %d tickers\n",
              nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))
  FACTORS
}
