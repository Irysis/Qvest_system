# =============================================================================
# fe_voltrank_mc.R — VoltRank_MC 팩터 엔진
# 논문: "Are Three Matrices All You Need To Beat the Market?" (Halperin 2026)
#        arxiv:2607.27461
#
# 핵심 발견:
#   변동성 순위(vol rank)는 Markov transition 예측 가능하며,
#   예측 저변동 종목을 long한 포트폴리오가 S&P 500 대비 SR 1.08~1.44 달성.
#
# 구현:
#   [MC 모드] Markov transition matrix로 다음 달 변동성 순위 분포 예측
#             → 예측 기대 순위 낮은 종목(저변동 예측) 매수.
#   [Simple 폴백] Markov 추정 실패 시 trailing 20일 RV 직접 역순 사용.
#
# PIT C1~C15 준수:
#   - 모든 신호는 월말 기준 t-1 이전 정보만 사용 (shift/rolling).
#   - 동일시점 순환참조 없음: rv20 = sd of *past* 20일 수익률.
#   - Markov 전이행렬은 rolling 과거 12M 구간으로 추정.
#   - 당월 수익률은 미사용 (forward label 없음).
#
# RAWDATA columns: Date, Ticker, Close, Vol, TradingValue, AvgTV20, LiqPass
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- 파라미터 ---------------------------------------------------------------
.N_BINS    <- 5L          # 변동성 순위 bin 수 (quintile)
.RV_WINDOW <- 20L         # 실현변동성 계산 윈도우 (거래일)
.MC_MONTHS <- 12L         # Markov 전이행렬 추정 롤링 윈도우 (개월)

# ---- Step 1: 일별 수익률 계산 (PIT: past Close만 사용) ---------------------
RAWDATA[, .ret := Close / shift(Close, 1L) - 1, by = Ticker]

# ---- Step 2: 20거래일 rolling 실현변동성 (표준편차) -------------------------
# rv20[t] = sd(ret[t-19], ..., ret[t]) — 모두 과거, PIT-safe
# 최소 10일치 유효 수익률 필요, 그 미만은 NA
RAWDATA[, .rv20 := frollapply(
  .ret,
  n       = .RV_WINDOW,
  FUN     = function(x) if (sum(is.finite(x)) >= 10L) sd(x, na.rm = TRUE) else NA_real_,
  fill    = NA_real_,
  align   = "right"
), by = Ticker]

# ---- Step 3: 월말 추출 (각 월의 마지막 거래일) ------------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date

# ---- Step 4: 월말 rv20 스냅샷 -----------------------------------------------
.rv_monthly <- RAWDATA[Date %in% .month_ends & LiqPass == TRUE & is.finite(.rv20),
                        .(Date, Ticker, rv20 = .rv20)]

# ---- Step 5: 유니버스 내 Cross-sectional vol rank (quintile bin) ------------
# rank: 1 = 최저변동성(가장 방어적), N = 최고변동성
# bin: 1~5 (quintile)
.rv_monthly[, .rank := frank(rv20, ties.method = "average"), by = Date]
.rv_monthly[, .n_valid := .N, by = Date]
.rv_monthly[, .bin := pmin(.N_BINS, ceiling(.rank / .n_valid * .N_BINS)),
             by = Date]
.rv_monthly[, .bin := as.integer(.bin)]

# ---- Step 6: Markov transition matrix 추정 + 다음 기 예측 순위 계산 ----------
# mc_dates: 월별 정렬
.ym_order <- sort(unique(.rv_monthly$Date))

# 각 날짜 t에서 rolling 과거 12개월 전이 데이터로 T 행렬 추정
# "t → t+1" 전이: (t 시점 bin) → (t+1 시점 bin) 로 카운트
# 예측 대상 = t+1 (다음 달), 신호 계산 시점 = t (현재 월말)

.compute_mc_score <- function() {
  # 전이 쌍 생성 (ticker 기준 lag join)
  .rv_with_next <- .rv_monthly[, .(Date, Ticker, bin_t = .bin)]
  .rv_next      <- .rv_monthly[, .(Date, Ticker, bin_tp1 = .bin)]
  setkey(.rv_with_next, Ticker, Date)
  setkey(.rv_next,      Ticker, Date)

  # 다음 달 bin 붙이기 (next Date 기준)
  .pairs <- merge(
    .rv_with_next,
    .rv_next[, .(Ticker, Date_next = Date, bin_tp1)],
    by = "Ticker"
  )
  # Date_next가 Date 직후 월말인 경우만 유효
  # 월말 간격: 정확히 다음 달 말일에 해당하는 쌍만 선택
  .pairs[, .dt := as.numeric(Date_next - Date)]
  .pairs <- .pairs[.dt >= 15L & .dt <= 50L]  # 15~50일 = 한 달 간격

  # 각 신호 날짜 t에 대해 rolling 12개월 이내 (t-12M ~ t-1M) 전이 쌍으로 추정
  .result <- vector("list", length(.ym_order))
  for (i in seq_along(.ym_order)) {
    sig_date  <- .ym_order[i]
    cutoff_lo <- sig_date - 375L  # 약 12.5개월 전 (보수적)
    cutoff_hi <- sig_date - 1L    # 신호 날짜 직전까지만

    .sub <- .pairs[Date >= cutoff_lo & Date <= cutoff_hi]

    if (nrow(.sub) < 50L) {
      # 전이 데이터 부족 → 단순 rv20 역순 폴백
      .snap <- .rv_monthly[Date == sig_date, .(Date, Ticker, Score = -.rv20)]
      if (nrow(.snap) > 0L) {
        .result[[i]] <- .snap
        cat(sprintf("[VoltRank_MC] %s: MC 폴백(단순 low-vol) n_pairs=%d\n",
                    format(sig_date), nrow(.sub)))
      }
      next
    }

    # 전이행렬 T[from, to] 추정 (Laplace 스무딩 +1)
    .counts <- matrix(1L, nrow = .N_BINS, ncol = .N_BINS)  # Laplace smoothing
    for (r in seq_len(nrow(.sub))) {
      f <- .sub$bin_t[r]
      t_to <- .sub$bin_tp1[r]
      if (is.finite(f) && is.finite(t_to) &&
          f >= 1L && f <= .N_BINS && t_to >= 1L && t_to <= .N_BINS) {
        .counts[f, t_to] <- .counts[f, t_to] + 1L
      }
    }
    .row_sums <- rowSums(.counts)
    .T <- sweep(.counts, 1, .row_sums, "/")  # row 정규화 → 전이확률

    # 현재 날짜의 각 종목 bin → 다음 달 예측 기대 순위
    .snap_cur <- .rv_monthly[Date == sig_date & is.finite(.bin),
                              .(Date, Ticker, bin_t = .bin)]
    if (nrow(.snap_cur) == 0L) next

    .snap_cur[, .pred_rank := {
      prob_next <- .T[bin_t, ]                     # 전이확률 행벡터
      sum(prob_next * seq_len(.N_BINS))            # 기대 bin
    }, by = seq_len(nrow(.snap_cur))]

    # Score = 음의 예측 기대 순위 (낮을수록 저변동 예측 → 매수 우선)
    .snap_cur[, Score := -.pred_rank]
    .snap_cur[, Date := sig_date]
    .result[[i]] <- .snap_cur[, .(Date, Ticker, Score)]
  }
  rbindlist(.result, use.names = TRUE, fill = FALSE)
}

cat("[VoltRank_MC] Markov transition matrix 추정 중...\n")
FACTORS <- tryCatch(
  .compute_mc_score(),
  error = function(e) {
    cat(sprintf("[VoltRank_MC] MC 오류, 단순 low-vol 폴백: %s\n", e$message))
    .rv_monthly[is.finite(.rv20), .(Date, Ticker, Score = -.rv20)]
  }
)

# ---- 유효성 검증 ------------------------------------------------------------
if (!is.data.table(FACTORS) || nrow(FACTORS) == 0L) {
  stop("[VoltRank_MC] FACTORS 생성 실패 — 행이 없음")
}
FACTORS <- FACTORS[is.finite(Score)]

# ---- 정리 -------------------------------------------------------------------
RAWDATA[, c(".ret", ".rv20", ".ym") := NULL]

cat(sprintf("[VoltRank_MC] FACTORS rows=%d | signal dates=%d | tickers=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))

# 점검: 최초 신호 날짜 및 최근 5개 점수 분포 출력
cat(sprintf("[VoltRank_MC] date range: %s ~ %s\n",
            min(FACTORS$Date), max(FACTORS$Date)))
cat(sprintf("[VoltRank_MC] score range: %.4f ~ %.4f (mean %.4f)\n",
            min(FACTORS$Score, na.rm=TRUE),
            max(FACTORS$Score, na.rm=TRUE),
            mean(FACTORS$Score, na.rm=TRUE)))
