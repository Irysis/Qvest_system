# =============================================================================
# fe_leadlag_network.R — Price Lead-Lag Network Momentum (slow info diffusion)
# =============================================================================
# 가설 (Cohen-Lou 2012 / Hou 2007 / Ali-Hirshleifer 2020): 종목 간 lead-lag 관계가
#   존재한다. leader i의 *어제* 수익이 follower j의 *오늘* 수익을 예측한다 (정보 확산
#   지연). KR은 retail 지배·정보처리 느림 → US보다 lead-lag 강할 구조적 이유.
#   long top-N = leader 신호 상위 종목 EW 매수.
#
# ★ 이 probe의 목적 = 직교성. 선택 기준을 횡단면 factor-score가 아니라 *종목 간 정보
#   확산*으로 바꿔 STR_1715(공분산 1st eigenmode)와 직교한 알파를 노린다.
#
# Edge 정의 (도훈 확정):
#   매 리밸 t에서 trailing 252거래일 일간수익률로 lagged corr:
#     LL[i,j] = corr( r_i[s-1], r_j[s] )   # i가 j를 lead (leader 어제 ~ follower 오늘)
#   follower j의 leaders = LL[,j] 상위 K개 종목 i. weight w_ij = LL[i,j] (양수만, 정규화).
#   신호 S_j = Σ_{i∈leaders(j)} w_ij · mom21_i
#     mom21_i = leader i의 trailing 21거래일 누적수익 (느린 확산 가정, 월간 리밸 정합).
#   long top-N = S_j 상위.
#
# ===== PIT (절대) — 02_Infrastructure/docs/rules/data_table_shift_convention.md =====
#   - lagged corr: 행렬 R(날짜×종목)에서 corr(R[1:(W-1),], R[2:W,]) → [i,j]는
#     "i의 과거(s-1) vs j의 현재(s)". i를 BACKWARD lag(과거)로 둔다 = leader가 과거.
#     ★ forward 누수 없음: 모든 입력 r은 데이터 ≤ t (signal date) 의 일간수익.
#   - mom21, corr window 모두 signal date t까지의 과거 데이터만 (C1 rolling, C2 no same-day).
#   - 신호 자체(예측)지 forward label 아님. 백테 수익률 정합은 run_monthly_simulation 표준.
#   - 유동성 필터는 run_alpha_search가 t-1 ADV(C10)로 이미 적용 (LiqPass).
#
# RAWDATA columns 사용: Date, Ticker, Ret(일간수익), Close, LiqPass
# =============================================================================
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
stopifnot(all(c("Ret", "Close", "LiqPass") %in% names(RAWDATA)))
setorder(RAWDATA, Ticker, Date)

# ---- 파라미터 (논문/도훈 권장값; sweep 시 n_trials 누적 카운트 의무) -----------
.LL_WINDOW   <- 252L   # lead-lag corr trailing window (거래일)
.LL_TOPK     <- 30L    # follower당 leader 수 (상위 K)
.LL_MOM      <- 21L    # leader 최근 수익 = trailing 21거래일 누적 (느린 확산)
.LL_MIN_OBS  <- 200L   # corr 산출 최소 유효 관측치 (window 내 NA 허용 하한)
.LL_MIN_LEAD <- 0.05   # leader 채택 최소 lead-lag corr (노이즈 leader 배제)

# ---- 월말 시그널 날짜 (각 달 마지막 거래일) ---------------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
all_dates   <- sort(unique(RAWDATA$Date))

# ---- 일간수익 wide 행렬 (Date × Ticker) — 한 번만 cast (루프 내 parquet 금지) --
#   각 signal date t에서 trailing window는 행 슬라이스 → 재캐스트 불필요.
.W <- dcast(RAWDATA[, .(Date, Ticker, Ret)], Date ~ Ticker, value.var = "Ret")
.wdates <- .W$Date
.W[, Date := NULL]
.Wmat <- as.matrix(.W)               # rows = all_dates(있는 Ret 날짜), cols = Ticker
.wtk  <- colnames(.Wmat)
rm(.W); gc(verbose = FALSE)

# Close wide (mom21 계산용; signal date 시점 trailing 21d 누적 = Close[t]/Close[t-21]-1)
.C <- dcast(RAWDATA[, .(Date, Ticker, Close)], Date ~ Ticker, value.var = "Close")
.cdates <- .C$Date; .C[, Date := NULL]
.Cmat <- as.matrix(.C); .ctk <- colnames(.Cmat)
rm(.C); gc(verbose = FALSE)

# 유동성 통과 종목 집합 (signal date별) — list lookup
.liq_by_date <- RAWDATA[Date %in% .month_ends & LiqPass == TRUE,
                        .(Ticker = list(unique(Ticker))), by = Date]
setkey(.liq_by_date, Date)

# ---- 핵심 루프: signal date별 lead-lag 네트워크 신호 -------------------------
.sig_list <- vector("list", length(.month_ends))
.k <- 0L
for (.ti_loop in seq_along(.month_ends)) {
  t <- .month_ends[.ti_loop]          # ★ index로 추출 — for(t in DateVec)는 Date class를 numeric으로 벗겨 match 실패
  ti <- match(t, .wdates)
  if (is.na(ti) || ti < .LL_WINDOW) next
  # trailing window 행 슬라이스 (데이터 ≤ t)
  lo <- ti - .LL_WINDOW + 1L
  Rt <- .Wmat[lo:ti, , drop = FALSE]            # W × all_tickers
  # 유동성 통과 종목으로 컬럼 제한 (universe는 run_alpha_search가 추가로 K200∪KQ150 필터)
  liq_tk <- .liq_by_date[.(t), Ticker][[1]]
  if (is.null(liq_tk) || length(liq_tk) < 20L) next
  keep <- which(.wtk %in% liq_tk)
  # window 내 유효 관측 최소 충족 종목만
  valid_obs <- colSums(!is.na(Rt[, keep, drop = FALSE]))
  keep <- keep[valid_obs >= .LL_MIN_OBS]
  if (length(keep) < 20L) next
  Rk <- Rt[, keep, drop = FALSE]
  tks <- .wtk[keep]
  # NA → 0 (수익 결측 = 거래정지 등; corr 산출 위해 0 대체, demean은 cor가 처리)
  Rk[is.na(Rk)] <- 0

  W <- nrow(Rk)
  # lagged cross-corr: leader i(과거 s-1) vs follower j(현재 s)
  #   X = Rk[1:(W-1), ] (leader, lagged) ; Y = Rk[2:W, ] (follower, current)
  X <- Rk[1:(W - 1L), , drop = FALSE]
  Y <- Rk[2:W, , drop = FALSE]
  # cor(X, Y)[i,j] = corr(X[,i], Y[,j]) = corr(r_i[s-1], r_j[s]) — i leads j. 정확히 의도.
  LL <- suppressWarnings(stats::cor(X, Y))       # (n × n) ; rows=leader i, cols=follower j
  LL[is.na(LL)] <- 0
  diag(LL) <- 0                                  # self-lead 제외 (autocorr 배제)

  # mom21: leader 최근 21거래일 누적수익 (signal date t 시점). Close[t]/Close[t-21]-1.
  ci <- match(t, .cdates)
  if (is.na(ci) || ci <= .LL_MOM) next
  cidx <- match(tks, .ctk)
  c_now  <- .Cmat[ci, cidx]
  c_prev <- .Cmat[ci - .LL_MOM, cidx]
  mom21 <- c_now / c_prev - 1                     # leader별 최근 수익 (벡터, length=n)
  ok_mom <- is.finite(mom21)

  # follower j 신호: S_j = Σ_i [i가 top-K leader of j & LL>min] w_ij · mom21_i
  #   각 컬럼 j에 대해 LL[,j] 상위 K (≥min_lead) → 정규화 weight × mom21.
  nstk <- length(tks)
  S <- rep(NA_real_, nstk)
  for (j in seq_len(nstk)) {
    llj <- LL[, j]
    llj[!ok_mom] <- NA_real_                       # mom 없는 leader 배제
    cand <- which(is.finite(llj) & llj >= .LL_MIN_LEAD)
    if (length(cand) == 0L) next
    if (length(cand) > .LL_TOPK)
      cand <- cand[order(llj[cand], decreasing = TRUE)[seq_len(.LL_TOPK)]]
    wij <- llj[cand]; wij <- wij / sum(wij)         # lead-lag corr 정규화 weight
    S[j] <- sum(wij * mom21[cand])
  }
  ok <- is.finite(S)
  if (!any(ok)) next
  .k <- .k + 1L
  .sig_list[[.k]] <- data.table(Date = t, Ticker = tks[ok], Score = S[ok])
}
.sig_list <- .sig_list[seq_len(.k)]

FACTORS <- if (.k > 0L) rbindlist(.sig_list) else
  data.table(Date = as.Date(character(0)), Ticker = character(0), Score = numeric(0))

# 정리
RAWDATA[, .ym := NULL]
rm(.Wmat, .Cmat); gc(verbose = FALSE)

cat(sprintf("[fe_leadlag_network] Cohen-Lou 2012 lead-lag | window=%d topK=%d mom=%d | rows=%d dates=%d tickers=%d\n",
            .LL_WINDOW, .LL_TOPK, .LL_MOM, nrow(FACTORS),
            uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))
