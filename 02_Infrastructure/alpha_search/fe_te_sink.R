# =============================================================================
# fe_te_sink.R — Transfer-Entropy 정보전파 그래프 sink 종목 알파 (KR-native)
# =============================================================================
# 가설 (idea bank #3 — 물리 프레임, 미검증 직교축):
#   섹터↔종목 간 정보전파의 *방향성·비선형* lead-lag을 transfer entropy(TE)로 측정.
#   TE(X→Y) = Σ p(y_{t+1},y_t,x_t) log[ p(y_{t+1}|y_t,x_t) / p(y_{t+1}|y_t) ]  (Schreiber 2000).
#   기존 price_delay / CR07 / fe_leadlag_network(선형 corr)와의 차이:
#     - fe_leadlag_network = 선형 corr(r_i[s-1], r_j[s]) — *무방향·선형*.
#     - TE = 조건부 엔트로피 기반 — *방향성*(비대칭) + *비선형* 의존 포착.
#   정보가 늦게 도달하는 sink 종목(net TE 유입 > 유출)은 가격반영 지연 → 예측가능
#   drift → long. (Marschinski-Kantz 2002 / Dimpfl-Peter 금융 TE 맥락. 복제 아닌 KR-native 가설.)
#
# ★ 계산 효율화 (naive pairwise ~600² 불가 → 섹터인덱스↔종목으로 축소):
#   종목 i의 net sink score = Σ_s TE(sector_s→i) − Σ_s TE(i→sector_s)
#     s = { 자기 섹터(Sector_Lv2) 인덱스, 시장(전체 유동성통과 종목 cap-weight) 인덱스 }.
#   섹터 인덱스 = 그 섹터 내 유동성통과 종목의 *시총가중* 일간수익(매 signal date 그 시점 멤버십).
#   O(N×S) (S=2: own-sector + market). N~600·S2·월 → pairwise 대비 ~300배 절감.
#
# TE 추정기 (빠르고 강건):
#   - 일간수익 3-bin 이산화: trailing 252d 창 내 33/67 분위 절단 → {0,1,2}.
#   - lag-1 TE: 결합도수 p(y1,y0,x0) plug-in 추정 (window 252 obs로 충분히 안정).
#   - rolling 252거래일 창, 월말 갱신(t-1까지). full-sample 통계 금지(C1).
#
# ===== PIT (절대) — data_table_shift_convention.md, AX-002, pit.md C1~C15 =====
#   - 섹터 멤버십: RAWDATA$Sector_Lv2 = 시변(time-varying) PIT. signal date t의 그 시점 섹터만.
#   - 섹터 인덱스 cap-weight = Size[t] (signal date 시점 시총, ≤t). 인덱스 수익은 window ≤ t 일간수익.
#   - TE 이산화 분위(33/67)는 *각 종목/인덱스의 trailing 252d 창 내부에서만* 계산 (C1 rolling,
#     full-sample 분위 금지). 모든 입력 r은 데이터 ≤ t (signal date)의 일간수익.
#   - lag-1 결합도수: (y_{s+1}, y_s, x_s)는 모두 s ≤ t-1 구간(window 마지막=t) → forward 누수 없음.
#     TE는 *예측 신호*지 forward label 아님(Cycle50류 무관). 백테 수익률 정합은 sim 표준.
#   - 유동성(LiqPass, t-1 ADV C10), Size, 섹터 모두 ≤ t. C2 no same-day.
#
# 파라미터 (env override; 기본=권장값). sweep 시 n_trials 누적 의무.
# RAWDATA columns 사용: Date, Ticker, Ret(일간수익), Size(시총), Sector_Lv2(string), LiqPass
# =============================================================================
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
stopifnot(all(c("Ret", "Size", "Sector_Lv2", "LiqPass") %in% names(RAWDATA)))
setorder(RAWDATA, Ticker, Date)

# ---- 파라미터 ---------------------------------------------------------------
.TE_WINDOW   <- as.integer(Sys.getenv("TE_WINDOW",  "252"))   # rolling TE 창 (거래일)
.TE_NBIN     <- as.integer(Sys.getenv("TE_NBIN",    "3"))     # 이산화 bin 수 (3-bin 33/67)
.TE_MIN_OBS  <- as.integer(Sys.getenv("TE_MIN_OBS", "200"))   # 창 내 최소 유효 관측치
.TE_MIN_SEC  <- as.integer(Sys.getenv("TE_MIN_SEC", "5"))     # 섹터 인덱스 구성 최소 종목수
.TE_FREQ     <- Sys.getenv("TE_FREQ", "monthly")              # "monthly" | "quarterly"(스모크 시간초과 폴백)

# ---- 시그널 날짜 (월말 또는 분기말 마지막 거래일) ---------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
if (identical(.TE_FREQ, "quarterly")) {
  .mo <- as.integer(format(.month_ends, "%m"))
  .month_ends <- .month_ends[.mo %in% c(3L, 6L, 9L, 12L)]
}

# ---- 일간수익 wide 행렬 (Date × Ticker) — 루프 내 재캐스트 금지 -------------
.W <- dcast(RAWDATA[, .(Date, Ticker, Ret)], Date ~ Ticker, value.var = "Ret")
.wdates <- .W$Date
.W[, Date := NULL]
.Wmat <- as.matrix(.W)
.wtk  <- colnames(.Wmat)
rm(.W); gc(verbose = FALSE)

# ---- signal date별 universe 스냅샷 (PIT: 그 시점 LiqPass + 섹터 + 시총) ------
.snap <- RAWDATA[Date %in% .month_ends & LiqPass == TRUE & is.finite(Size) & Size > 0 &
                   !is.na(Sector_Lv2) & nzchar(Sector_Lv2),
                 .(Date, Ticker, Size, Sector = Sector_Lv2)]
setkey(.snap, Date)

# ---- TE 헬퍼: 연속수익 → trailing-window 분위 절단 3-bin (rolling, C1) -------
.discretize <- function(x, nbin) {
  ok <- is.finite(x)
  if (sum(ok) < 10L) return(rep(NA_integer_, length(x)))
  qs <- quantile(x[ok], probs = seq_len(nbin - 1L) / nbin, na.rm = TRUE, type = 7)
  # 동일값 다수로 분위 붕괴 시(저거래 종목) NA 처리 → TE에서 자연 배제
  if (any(!is.finite(qs)) || length(unique(qs)) < (nbin - 1L)) {
    # 분위가 겹치면 rank-기반 균등 절단으로 폴백 (여전히 window 내부 통계만)
    r <- rank(x, ties.method = "average", na.last = "keep")
    b <- ceiling(r / sum(ok) * nbin)
    b[b < 1L] <- 1L; b[b > nbin] <- nbin
    return(as.integer(b))
  }
  b <- findInterval(x, qs) + 1L   # 1..nbin
  b[!ok] <- NA_integer_
  as.integer(b)
}

# ---- lag-1 transfer entropy TE(X->Y): X가 Y의 다음 상태를 추가로 설명하는 정보량 ----
#   plug-in 추정: p(y1,y0,x0) 결합도수. nats 단위(log). source=X, target=Y.
#   y1 = Y_{s+1}, y0 = Y_s, x0 = X_s.  (모두 window 내부, s+1<=window 끝)
.te_xy <- function(xb, yb, nbin) {
  n <- length(yb)
  if (n < 30L) return(NA_real_)
  y1 <- yb[-1L]; y0 <- yb[-n]; x0 <- xb[-n]   # 길이 n-1, lag-1 정렬
  ok <- is.finite(y1) & is.finite(y0) & is.finite(x0)
  if (sum(ok) < 30L) return(NA_real_)
  y1 <- y1[ok]; y0 <- y0[ok]; x0 <- x0[ok]
  N  <- length(y1)
  # 결합/주변 도수 (nbin^3 셀)
  idx3 <- (y1 - 1L) * nbin * nbin + (y0 - 1L) * nbin + (x0 - 1L) + 1L  # p(y1,y0,x0)
  p3   <- tabulate(idx3, nbins = nbin^3) / N
  idx_y0x0 <- (y0 - 1L) * nbin + (x0 - 1L) + 1L                        # p(y0,x0)
  p_y0x0   <- tabulate(idx_y0x0, nbins = nbin^2) / N
  idx_y1y0 <- (y1 - 1L) * nbin + (y0 - 1L) + 1L                        # p(y1,y0)
  p_y1y0   <- tabulate(idx_y1y0, nbins = nbin^2) / N
  p_y0     <- tabulate(y0, nbins = nbin) / N                           # p(y0)
  te <- 0
  for (a in seq_len(nbin)) for (b in seq_len(nbin)) for (c in seq_len(nbin)) {
    i3 <- (a - 1L) * nbin * nbin + (b - 1L) * nbin + (c - 1L) + 1L
    pj <- p3[i3]
    if (pj <= 0) next
    pyx <- p_y0x0[(b - 1L) * nbin + (c - 1L) + 1L]   # p(y0,x0)
    pyy <- p_y1y0[(a - 1L) * nbin + (b - 1L) + 1L]   # p(y1,y0)
    py  <- p_y0[b]                                    # p(y0)
    if (pyx <= 0 || pyy <= 0 || py <= 0) next
    # p(y1|y0,x0)=pj/pyx ; p(y1|y0)=pyy/py
    te <- te + pj * log((pj / pyx) / (pyy / py))
  }
  if (!is.finite(te) || te < 0) te <- max(te, 0, na.rm = TRUE)  # 추정 음수는 0 클램프
  te
}

# ---- 핵심 루프: signal date별 섹터인덱스↔종목 net sink score ------------------
.sig_list <- vector("list", length(.month_ends))
.k <- 0L
for (.ti in seq_along(.month_ends)) {
  t  <- .month_ends[.ti]
  ti <- match(t, .wdates)
  if (is.na(ti) || ti < .TE_WINDOW) next
  lo <- ti - .TE_WINDOW + 1L
  Rt <- .Wmat[lo:ti, , drop = FALSE]            # window × all_tickers (일간수익, <=t)

  snap_t <- .snap[.(t)]
  if (nrow(snap_t) < 20L) next
  # 유효 종목: window 내 관측 충분
  cidx <- match(snap_t$Ticker, .wtk)
  snap_t <- snap_t[!is.na(cidx)]; cidx <- cidx[!is.na(cidx)]
  if (length(cidx) < 20L) next
  Rk <- Rt[, cidx, drop = FALSE]
  valid <- colSums(is.finite(Rk)) >= .TE_MIN_OBS
  snap_t <- snap_t[valid]; cidx <- cidx[valid]; Rk <- Rk[, valid, drop = FALSE]
  if (nrow(snap_t) < 20L) next
  tks <- snap_t$Ticker
  Rk[!is.finite(Rk)] <- NA_real_

  # --- 섹터 인덱스 + 시장 인덱스 일간수익 (window, cap-weight by Size[t]) ---
  #   시장 인덱스 = 전체 유효종목 시총가중. 섹터 인덱스 = 각 섹터 내 시총가중(종목수>=MIN_SEC).
  W_ <- nrow(Rk)
  Rk0 <- Rk; Rk0[is.na(Rk0)] <- 0           # 인덱스 합성용(결측=0 일중 무변)
  szv <- snap_t$Size
  mkt_w <- szv / sum(szv)
  mkt_idx <- as.vector(Rk0 %*% mkt_w)        # 시장 인덱스 일간수익 (window)

  sec_levels <- unique(snap_t$Sector)
  sec_idx_map <- list()                      # 섹터명 -> 인덱스 수익 벡터
  sec_of <- snap_t$Sector
  for (sc in sec_levels) {
    sel <- which(sec_of == sc)
    if (length(sel) < .TE_MIN_SEC) next
    w <- szv[sel] / sum(szv[sel])
    sec_idx_map[[sc]] <- as.vector(Rk0[, sel, drop = FALSE] %*% w)
  }

  # --- 이산화 (인덱스들 + 종목들; 각자 window 내부 분위) ---
  mkt_b <- .discretize(mkt_idx, .TE_NBIN)
  sec_b_map <- lapply(sec_idx_map, .discretize, nbin = .TE_NBIN)
  stk_b <- apply(Rk, 2L, .discretize, nbin = .TE_NBIN)   # window × nstk

  # --- net sink score per stock: Σ_s TE(s->i) − Σ_s TE(i->s), s in {own sector, market} ---
  nstk <- length(tks)
  S <- rep(NA_real_, nstk)
  for (j in seq_len(nstk)) {
    yb <- stk_b[, j]
    if (sum(is.finite(yb)) < .TE_MIN_OBS) next
    src_set <- list(market = mkt_b)
    own <- sec_of[j]
    if (!is.null(sec_b_map[[own]])) src_set[["own"]] <- sec_b_map[[own]]
    inflow <- 0; outflow <- 0; cnt <- 0L
    for (sb in src_set) {
      if (is.null(sb) || sum(is.finite(sb)) < .TE_MIN_OBS) next
      te_in  <- .te_xy(sb, yb, .TE_NBIN)   # TE(sector->stock)  = 유입
      te_out <- .te_xy(yb, sb, .TE_NBIN)   # TE(stock->sector)  = 유출
      if (is.finite(te_in) && is.finite(te_out)) {
        inflow  <- inflow  + te_in
        outflow <- outflow + te_out
        cnt <- cnt + 1L
      }
    }
    if (cnt == 0L) next
    S[j] <- inflow - outflow              # net sink: 유입>유출 → 높을수록 sink(매수 우선)
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
rm(.Wmat); gc(verbose = FALSE)

cat(sprintf("[fe_te_sink] TE net-sink (sector/market index -> stock) | window=%d nbin=%d freq=%s | rows=%d dates=%d tickers=%d\n",
            .TE_WINDOW, .TE_NBIN, .TE_FREQ,
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker)))
