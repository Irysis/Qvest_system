# =============================================================================
# fe_voltrank_mc.R — VoltRank_MC 팩터 엔진 (v3 — Markov 추정 수정)
# 논문: "Are Three Matrices All You Need To Beat the Market?" (Halperin 2026)
#        arxiv:2607.27461
#
# 구현:
#   [MC 모드] Markov transition matrix로 다음 달 변동성 순위 분포 예측
#             → 예측 기대 순위 낮은 종목(저변동 예측) 매수.
#   [Simple 폴백] Markov 추정 데이터 부족 시 trailing 20일 RV 역순 사용.
#
# PIT C1~C15 준수:
#   - rv20[t] = sd(ret[t-19..t]) — 과거만 사용
#   - Markov 전이행렬: rolling 과거 12M 구간의 (t, t+1) 쌍으로 추정
#   - 신호 날짜 t 기준: t 이전 데이터만 사용 (t+1의 bin은 관측 불가 → 전이행렬 추정만)
#
# RAWDATA columns (run_alpha_search.R이 추가): Date, Ticker, Close, Vol,
#   TradingValue, AvgTV20, LiqPass (유동성 ≥ 2억), K200, KQ150
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- 파라미터 ---------------------------------------------------------------
.N_BINS    <- 5L          # 변동성 순위 bin 수 (quintile)
.RV_WINDOW <- 20L         # 실현변동성 계산 윈도우 (거래일)
.MIN_PAIRS <- 30L         # Markov 추정 최소 전이 쌍 수

# ---- Step 1: 일별 수익률 계산 (PIT: past Close만 사용) ---------------------
RAWDATA[, .ret := Close / shift(Close, 1L) - 1, by = Ticker]

# ---- Step 2: 20거래일 rolling 실현변동성 (표준편차) -------------------------
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
# LiqPass는 run_alpha_search.R이 RAWDATA에 추가한 컬럼
.rv_monthly <- RAWDATA[Date %in% .month_ends & LiqPass == TRUE & is.finite(.rv20),
                        .(Date, Ticker, rv20 = .rv20)]

# 정리: RAWDATA 임시 컬럼 제거 (이후 접근 방지)
RAWDATA[, c(".ret", ".rv20", ".ym") := NULL]

cat(sprintf("[VoltRank_MC] rv_monthly: %d rows | %d dates | %d tickers\n",
            nrow(.rv_monthly), uniqueN(.rv_monthly$Date), uniqueN(.rv_monthly$Ticker)))

# ---- Step 5: Cross-sectional vol rank (quintile bin) -----------------------
.rv_monthly[, .rank := frank(rv20, ties.method = "average"), by = Date]
.rv_monthly[, .n_valid := .N, by = Date]
.rv_monthly[, .bin := pmin(.N_BINS, ceiling(.rank / .n_valid * .N_BINS)), by = Date]
.rv_monthly[, .bin := as.integer(.bin)]

# ---- Step 6: 전이 쌍 생성 --------------------------------------------------
# 방법: 월 인덱스 기반으로 연속 월 쌍을 직접 구성 (shift 방향 문제 회피)
# .ym_sorted: 정렬된 고유 월말 날짜
.ym_sorted <- sort(unique(.rv_monthly$Date))
.ym_idx    <- setNames(seq_along(.ym_sorted), as.character(.ym_sorted))

# 각 (날짜, ticker)에 월 인덱스 부여
.rv_monthly[, .ymidx := .ym_idx[as.character(Date)]]

# 자기 자신의 다음 달 bin 찾기: inner join on (Ticker, .ymidx+1)
.rv_t   <- .rv_monthly[, .(Ticker, ymidx_t = .ymidx, bin_t = .bin)]
.rv_tp1 <- .rv_monthly[, .(Ticker, ymidx_t = .ymidx - 1L, bin_tp1 = .bin)]  # shift: ymidx_t = (t+1의 ymidx) - 1

setkey(.rv_t,   Ticker, ymidx_t)
setkey(.rv_tp1, Ticker, ymidx_t)

.pairs_all <- .rv_t[.rv_tp1, nomatch = 0L]  # inner join
# 날짜 복원
.date_map <- data.table(ymidx_t = seq_along(.ym_sorted), Date = .ym_sorted)
setkey(.pairs_all, ymidx_t); setkey(.date_map, ymidx_t)
.pairs_all <- .date_map[.pairs_all, on = "ymidx_t"]

cat(sprintf("[VoltRank_MC] 전이 쌍 수: %d\n", nrow(.pairs_all)))

if (nrow(.pairs_all) == 0L) {
  # 전이 쌍이 없으면 단순 저변동성 폴백
  cat("[VoltRank_MC] 전이 쌍 0 — 단순 low-vol 폴백\n")
  FACTORS <- .rv_monthly[is.finite(rv20), .(Date, Ticker, Score = -rv20)]
  FACTORS <- FACTORS[is.finite(Score)]
  cat(sprintf("[VoltRank_MC] FACTORS rows=%d | dates=%d\n", nrow(FACTORS), uniqueN(FACTORS$Date)))
} else {
  # ---- Step 7: Markov transition matrix 추정 + 다음 기 예측 순위 계산 ------
  .compute_mc_score <- function() {
    .result <- vector("list", length(.ym_sorted))

    for (i in seq_along(.ym_sorted)) {
      sig_date  <- .ym_sorted[i]
      sig_ymidx <- .ym_idx[as.character(sig_date)]

      # 과거 12M = 12 월 인덱스 이전까지 (PIT)
      cutoff_lo <- sig_ymidx - 12L
      cutoff_hi <- sig_ymidx - 1L  # 신호 날짜 직전까지

      .sub <- .pairs_all[ymidx_t >= cutoff_lo & ymidx_t <= cutoff_hi]

      .snap_cur <- .rv_monthly[Date == sig_date & is.finite(.bin),
                                .(Ticker, bin_t = .bin, rv20)]
      if (nrow(.snap_cur) == 0L) next

      if (nrow(.sub) < .MIN_PAIRS) {
        # 데이터 부족 → 단순 rv20 역순
        .snap_cur[, Score := -rv20]
        .result[[i]] <- data.table(Date = sig_date, Ticker = .snap_cur$Ticker,
                                   Score = .snap_cur$Score)
        next
      }

      # 전이행렬 T[from, to] 추정 (Laplace 스무딩)
      .counts <- matrix(1L, nrow = .N_BINS, ncol = .N_BINS)
      valid_mask <- is.finite(.sub$bin_t) & is.finite(.sub$bin_tp1) &
                    .sub$bin_t >= 1L & .sub$bin_t <= .N_BINS &
                    .sub$bin_tp1 >= 1L & .sub$bin_tp1 <= .N_BINS
      for (r in which(valid_mask)) {
        .counts[.sub$bin_t[r], .sub$bin_tp1[r]] <- .counts[.sub$bin_t[r], .sub$bin_tp1[r]] + 1L
      }
      .T <- sweep(.counts, 1, rowSums(.counts), "/")

      # 예측 기대 bin (낮을수록 저변동 예측 → Score 높을수록 선택)
      .snap_cur[, pred_bin := {
        vapply(bin_t, function(b) {
          if (is.na(b) || b < 1L || b > .N_BINS) return(NA_real_)
          sum(.T[b, ] * seq_len(.N_BINS))
        }, numeric(1L))
      }]
      .snap_cur[, Score := -pred_bin]

      .result[[i]] <- data.table(Date = sig_date, Ticker = .snap_cur$Ticker,
                                 Score = .snap_cur$Score)
    }

    rbindlist(.result, use.names = TRUE, fill = FALSE)
  }

  cat("[VoltRank_MC] Markov transition matrix 추정 중...\n")
  FACTORS <- tryCatch(
    .compute_mc_score(),
    error = function(e) {
      cat(sprintf("[VoltRank_MC] MC 오류, 단순 low-vol 폴백: %s\n", e$message))
      .rv_monthly[is.finite(rv20), .(Date, Ticker, Score = -rv20)]
    }
  )
}

# ---- 유효성 검증 ------------------------------------------------------------
if (!is.data.table(FACTORS) || nrow(FACTORS) == 0L) {
  stop("[VoltRank_MC] FACTORS 생성 실패 — 행이 없음")
}
FACTORS <- FACTORS[is.finite(Score)]

cat(sprintf("[VoltRank_MC] FACTORS rows=%d | signal dates=%d | tickers=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))
cat(sprintf("[VoltRank_MC] date range: %s ~ %s\n",
            format(min(FACTORS$Date)), format(max(FACTORS$Date))))
cat(sprintf("[VoltRank_MC] score range: %.4f ~ %.4f (mean %.4f)\n",
            min(FACTORS$Score, na.rm = TRUE),
            max(FACTORS$Score, na.rm = TRUE),
            mean(FACTORS$Score, na.rm = TRUE)))
