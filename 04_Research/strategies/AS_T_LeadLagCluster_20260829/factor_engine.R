# =============================================================================
# factor_engine.R — Lead-Lag Cluster Signal (KR adaptation)
# 출처: "Lead-Lag Relationships in Financial Markets:
#       A Comparison of Multiple Clustering Algorithms"
#       Deng & Zhang (2026), arxiv:2608.24703
#
# 핵심 가설:
#   주식 쌍 간 lag-1 수익률 교차상관 → RowSum 리드스코어가 높은 종목(= 정보
#   선도주)이 횡단면 초과수익. 논문 best result: MiniRocket-KMeans lead 전략,
#   SR=0.866, MDD=-63.9% (679 US 주식, 2000-2019).
#
# 구현 방법 (KR 이식 - 충실한 재구성):
#   - 클러스터링: DTW 생략 → 전체 유니버스 단일 클러스터 (단순화 명시)
#   - 리드스코어: lag-1 교차상관 RowSum (= 논문 핵심 신호 메커니즘)
#   - 리더: 상위 75% (논문 "top 75% as Leader")
#   - 신호: leader EW 평균 수익률 5일 EWMA 부호 (논문 spn∈{1,3,5,7} 중 5)
#   - Lead 전략: 신호 양수 시 상위 leader 매수 (long-only)
#
# PIT 준수:
#   - sig_date = 월말 t. 21일 창 = [t-20 거래일, t 거래일] 종가수익률
#   - 월 t 신호 → 월 t+1 보유 (run_monthly_simulation 내부 lag 적용)
#   - C1: rolling 21일 창만 사용
#   - C2: 당일 circular reference 없음 (수익률은 종가 기준)
#   - C10: LiqPass는 이미 t-1 PIT 적용됨
#
# 구현 충실도 메모 (batch_434):
#   - 논문 신호(RowSum lead-lag) 그대로 복제
#   - 클러스터링 생략 = 단순화(허용). 합성 신호 없음.
#   - L/S → long-only long-leg 사상 (알파서칭 모드 규칙, 허용)
#   - 유니버스: K200∪KQ150 (논문 US CRSP와 다름, 명시)
#   - n_holdings: 25 (논문: 전체 leader EW, 우리 시스템 max 25로 절단)
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- 파라미터 (논문 명시값) ---------------------------------------------------
LOOKBACK_DAYS <- 21L   # 슬라이딩 창 l=21 (Algorithm 1, 논문)
LEADER_FRAC   <- 0.75  # 상위 75% = 리더 (논문 §4.2 "top 75%")
EWMA_SPAN     <- 5L    # EWMA span p=5 (논문 p∈{1,3,5,7})
MIN_STOCKS    <- 20L   # 교차상관 유효 최소 종목수
MIN_DAYS      <- 12L   # 각 종목 최소 유효 관측일

# ---- 전처리: 월말 날짜, 전체 거래일 목록 ------------------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
month_ends <- sort(unique(RAWDATA[, max(Date), by = .ym]$V1))
all_dates  <- sort(unique(RAWDATA$Date))

# ---- 월별 리드스코어 계산 ----------------------------------------------------
scores_list <- vector("list", length(month_ends))

for (mm in seq_along(month_ends)) {
  sig <- month_ends[mm]

  # 이 월말의 sig 인덱스
  d_idx <- which(all_dates == sig)
  if (d_idx < LOOKBACK_DAYS) next

  # 21 거래일 창 (sig_date 포함)
  window_dates <- all_dates[(d_idx - LOOKBACK_DAYS + 1L):d_idx]

  # 유동성 필터: sig_date 기준 LiqPass==TRUE 종목
  liq_tickers <- RAWDATA[Date == sig & LiqPass == TRUE, Ticker]
  if (length(liq_tickers) < MIN_STOCKS) next

  # 해당 창의 일별 수익률 가져오기 (Ret = daily return from RAWDATA)
  win_dt <- RAWDATA[
    Date %in% window_dates & Ticker %in% liq_tickers & is.finite(Ret),
    .(Date, Ticker, Ret)
  ]

  # 유효 관측 충분한 종목만
  tick_cnt     <- win_dt[, .N, by = Ticker]
  valid_tickers <- tick_cnt[N >= MIN_DAYS, Ticker]
  if (length(valid_tickers) < MIN_STOCKS) next

  win_dt <- win_dt[Ticker %in% valid_tickers]

  # 넓은 형식(날짜 × 종목) — 빈 칸은 0으로 채움 (논문: 결측=중립)
  ret_wide <- dcast(win_dt, Date ~ Ticker, value.var = "Ret", fill = 0)
  setorder(ret_wide, Date)
  tickers <- setdiff(names(ret_wide), "Date")
  ret_mat  <- as.matrix(ret_wide[, .SD, .SDcols = tickers])

  n <- nrow(ret_mat)   # = LOOKBACK_DAYS (또는 그 이하)
  if (n < 5L) next

  # ---- 핵심: lag-1 교차상관 행렬 → RowSum lead score -----
  # cc[i,j] = corr(r_i[t-1], r_j[t])  (i가 한 시점 앞선 경우)
  # M[i,j]  = cc[i,j] - cc[j,i]  > 0  → stock i가 j를 선도
  # RowSum(i) = Σ_j M[i,j]         높을수록 리더

  r_lead <- ret_mat[1:(n - 1L), , drop = FALSE]   # (n-1) × p, t-1 시점
  r_lag  <- ret_mat[2:n,        , drop = FALSE]   # (n-1) × p, t   시점

  # 표준화 (scale 후 NaN/NA → 0 처리)
  r1 <- scale(r_lead); r1[!is.finite(r1)] <- 0
  r2 <- scale(r_lag);  r2[!is.finite(r2)] <- 0
  colnames(r1) <- colnames(r2) <- tickers

  # 교차상관 행렬: p × p, cc[i,j] = r1[,i]·r2[,j] / (n-2)
  denom <- max(1L, nrow(r1) - 1L)
  cc    <- crossprod(r1, r2) / denom   # p × p

  # 비대칭 행렬 → RowSum
  M_mat     <- cc - t(cc)
  lead_score <- rowSums(M_mat, na.rm = TRUE)
  names(lead_score) <- tickers

  # ---- 리더 집합 & 모멘텀 방향 신호 ----------------------------------------
  n_leaders      <- max(3L, floor(length(lead_score) * LEADER_FRAC))
  sorted_idx     <- order(lead_score, decreasing = TRUE)
  leader_tickers <- tickers[sorted_idx[seq_len(n_leaders)]]

  # 리더 EW 평균 수익률 시계열 (21일)
  leader_cols <- which(tickers %in% leader_tickers)
  leader_ret_ts <- rowMeans(ret_mat[, leader_cols, drop = FALSE], na.rm = TRUE)

  # 5일 지수가중이동평균 (span=EWMA_SPAN) — 최근 값일수록 가중치 높음
  last_n  <- tail(leader_ret_ts, EWMA_SPAN)
  w       <- 2^(seq_along(last_n) - 1L)   # 지수 가중치
  ewma_val <- if (sum(is.finite(last_n)) >= 2L)
    sum(last_n * w, na.rm = TRUE) / sum(w[is.finite(last_n)])
  else NA_real_

  # 방향 스케일: 신호 양수 → 1.0, 음수 → 0 (long-only)
  direction <- if (is.finite(ewma_val) && ewma_val > 0) 1.0 else 0.0

  # 최종 알파 스코어: lead_score × direction (양수일 때만 매수 후보)
  # run_alpha_search의 top-N 선택이 상위 25종목을 고름
  score_vec <- lead_score * direction

  scores_list[[mm]] <- data.table(
    Date   = sig,
    Ticker = names(score_vec),
    Score  = as.numeric(score_vec)
  )
}

# ---- 결과 집계 ---------------------------------------------------------------
FACTORS <- rbindlist(scores_list[!sapply(scores_list, is.null)])

# 정리 (RAWDATA 임시 컬럼 삭제)
RAWDATA[, .ym := NULL]

cat(sprintf(
  "[fe_LeadLagCluster] FACTORS rows=%d | signal dates=%d | tickers=%d\n",
  nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)
))
