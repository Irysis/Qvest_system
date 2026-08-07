# =============================================================================
# fe_spectral_persistence_hurst.R — SpectralPersistence (Hurst R/S) 팩터 엔진
# =============================================================================
# 논문: "The Science and Practice of Trend-Following Systems"
#        Sepp & Lucic (2026) arXiv:2607.19497
#
# 팩터 아이디어:
#   추세추종 알파는 저주파 스펙트럼 질량 초과에서 발생한다.
#   Hurst 지수 H = log(R/S) / log(N/2), R/S = R/S 통계량 (rolling 252일)
#     H > 0.5 → 지속성/추세 (long 후보)
#     H < 0.5 → 평균회귀
#
# PIT 체크리스트:
#   [C1] rolling 252일 window만 — 전체표본 통계 없음
#   [C2] 월말 스냅샷 후 t+1월 수익률 평가 — 동일시점 순환참조 없음
#   [C3] 동기간 집계-적용 없음
#   [C5] 홀딩월 시작 전 데이터만 사용
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))

# ---- Hurst R/S 계산 함수 ------------------------------------------------
hurst_rs <- function(x) {
  x <- x[!is.na(x)]
  n <- length(x)
  if (n < 60L) return(NA_real_)
  m <- mean(x)
  dev <- cumsum(x - m)
  R_stat <- max(dev) - min(dev)
  S_stat <- sd(x)
  if (S_stat <= 0 || !is.finite(S_stat)) return(NA_real_)
  H_val <- log(R_stat / S_stat) / log(n / 2.0)
  if (!is.finite(H_val) || H_val < 0 || H_val > 1.5) return(NA_real_)
  H_val
}

WIN <- 252L

# ---- 데이터 정렬 및 월말 날짜 추출 ----------------------------------------
setorder(RAWDATA, Ticker, Date)
RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends_dt <- RAWDATA[, .(me_Date = max(Date)), by = .ym]
.month_end_set <- .month_ends_dt[["me_Date"]]

cat(sprintf("[fe_hurst] 월말 거래일 %d개 | 데이터 %s ~ %s\n",
            length(.month_end_set),
            format(min(RAWDATA$Date)),
            format(max(RAWDATA$Date))))

# ---- 종목별 거래일 순번 부여 -----------------------------------------------
RAWDATA[, .tidx := seq_len(.N), by = Ticker]

# ---- 월말 인덱스 조회 -------------------------------------------------------
.me_panel <- RAWDATA[Date %in% .month_end_set,
                     .(Ticker, Date, .tidx, LiqPass)]

cat(sprintf("[fe_hurst] 월말 패널: %d행, 종목 %d개\n",
            nrow(.me_panel), uniqueN(.me_panel$Ticker)))

# ---- 티커 목록으로 순차 처리 (메모리 안전) ----------------------------------
.tickers <- unique(.me_panel$Ticker)
cat(sprintf("[fe_hurst] 종목 %d개 Hurst 연산 시작...\n", length(.tickers)))

# Ret 벡터와 tidx를 티커별로 미리 추출 (list 방식 — split() 회피)
RAWDATA_KEY <- RAWDATA[, .(Ticker, .tidx, Ret)]
setkey(RAWDATA_KEY, Ticker, .tidx)

.res_list <- vector("list", length(.tickers))

for (i in seq_along(.tickers)) {
  tk <- .tickers[i]
  # 해당 티커 일간 데이터
  dk <- RAWDATA_KEY[.(tk), nomatch = 0L]
  rets_vec <- dk$Ret
  idxs_vec <- dk$.tidx

  # 해당 티커의 월말 행
  me_tk <- .me_panel[Ticker == tk]

  rows <- vector("list", nrow(me_tk))
  for (j in seq_len(nrow(me_tk))) {
    end_idx   <- me_tk$.tidx[j]
    start_idx <- end_idx - WIN + 1L
    if (start_idx < 1L) {
      rows[[j]] <- list(Ticker = tk, Date = me_tk$Date[j],
                        Score  = NA_real_, LiqPass = me_tk$LiqPass[j])
      next
    }
    mask      <- idxs_vec >= start_idx & idxs_vec <= end_idx
    H_val     <- hurst_rs(rets_vec[mask])
    rows[[j]] <- list(Ticker = tk, Date = me_tk$Date[j],
                      Score  = H_val, LiqPass = me_tk$LiqPass[j])
  }
  .res_list[[i]] <- rbindlist(rows)

  if (i %% 100L == 0L)
    cat(sprintf("  [fe_hurst] %d / %d 종목 완료\n", i, length(.tickers)))
}

FACTORS_RAW <- rbindlist(.res_list, fill = TRUE)
rm(.res_list, dk, rows); gc(verbose = FALSE)

# ---- 유동성 필터 + 유효 스코어만 추출 -------------------------------------
FACTORS <- FACTORS_RAW[LiqPass == TRUE & is.finite(Score),
                        .(Date, Ticker, Score)]

cat(sprintf("[fe_hurst] FACTORS: %d행 | 유효 날짜 %d개\n",
            nrow(FACTORS), uniqueN(FACTORS$Date)))
cat(sprintf("[fe_hurst] H 범위: %.4f ~ %.4f (중앙값 %.4f)\n",
            min(FACTORS$Score, na.rm = TRUE),
            max(FACTORS$Score, na.rm = TRUE),
            median(FACTORS$Score, na.rm = TRUE)))

# ---- RAWDATA 임시 컬럼 정리 ------------------------------------------------
RAWDATA[, c(".ym", ".tidx") := NULL]
rm(RAWDATA_KEY, FACTORS_RAW, .me_panel, .month_end_set, .month_ends_dt)
gc(verbose = FALSE)
