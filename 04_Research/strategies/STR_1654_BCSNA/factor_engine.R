## ============================================================
## STR_1654 factor_engine.R — Beta-Conditioned Sector-Neutral Accrual
##
## 전제: run_all.R에서 FDB_BULK (AC17/AC21/AC22 전 기간 메모리 적재 완료)
##       RAWDATA, BM_DT, SIGNAL_START_DATE, LIQ_THRESHOLD 이미 정의됨
##
## 역할: FDB_BULK 메모리 조회만 수행 — 파일 I/O 전혀 없음 (OPT-1)
##       lapply 기반 월별 처리 — 루프 내 I/O 없음
##
## PIT:
##   C2:  Beta expanding window → shift(Beta_Raw,1) t-1 lag
##   C9:  DD/VT 없음 (S1 순수 팩터)
##   C10: AvgTV20 t-1 lag (shift 1)
##   C13: Z_Score_Aligned 합산. 수동 방향 반전 금지.
##   C14: FDB_BULK는 Usable_Date 기준 적재 (Factor DB 내부 처리)
## ============================================================

suppressPackageStartupMessages(library(data.table))

cat("[factor_engine] STR_1654 BCSNA — sector-neutral scoring start\n")

# ── 상수 ───────────────────────────────────────────────────────
BETA_WINDOW    <- 252L   # expanding beta 최소 거래일
BETA_CUTOFF    <- 0.40   # 하위 40% 기본
BETA_FALLBACK  <- 0.50   # 유니버스 < 30종목 시 완화
MIN_UNIV_SIZE  <- 30L    # 섹터-뉴트럴 최소 유니버스
N_PER_SECTOR   <- 3L     # 업종당 선택 종목 수 (10 x 3 = 30)
MIN_SECTORS    <- 5L     # 최소 유효 대분류 수
TARGET_HOLD    <- 30L    # 목표 보유 종목 수

# ── WICS 중분류(Sector 26개) → 대분류 10개 매핑 ──────────────
# WICS 10대 섹터: 에너지/소재/산업재/경기소비재/필수소비재/헬스케어/금융/IT/통신/유틸리티
SECTOR_MAP <- c(
  # 에너지
  "\uc5d0\ub108\uc9c0"                         = "Energy",
  # 소재
  "\ud654\ud559"                               = "Materials",
  "\uccca\uac15"                               = "Materials",
  "\ube44\ucca0,\ubaa9\uc7ac\ub4f1"            = "Materials",
  # 산업재
  "\uae30\uacc4"                               = "Industrials",
  "\uc870\uc120"                               = "Industrials",
  "\uac74\uc124,\uac74\ucd95\uad00\ub828"      = "Industrials",
  "\uc0c1\uc0ac,\uc790\ubcf8\uc7ac"            = "Industrials",
  "\uc6b4\uc1a1"                               = "Industrials",
  # 경기소비재
  "\uc790\ub3d9\ucc28"                         = "ConsDisc",
  "\ud654\uc7a5\ud488,\uc758\ub958,\uc644\uad6c" = "ConsDisc",
  "\ud638\ud154,\ub808\uc800\uc11c\ube44\uc2a4" = "ConsDisc",
  "\uc18c\ub9e4(\uc720\ud1b5)"                 = "ConsDisc",
  "\ubbf8\ub514\uc5b4,\uad50\uc721"            = "ConsDisc",
  # 필수소비재
  "\ud544\uc218\uc18c\ube44\uc7ac"             = "ConsStaples",
  # 헬스케어
  "\uac74\uac15\uad00\ub9ac"                   = "Healthcare",
  # 금융
  "\uc740\ud589"                               = "Financials",
  "\ubcf4\ud5d8"                               = "Financials",
  "\uc99d\uad8c"                               = "Financials",
  # IT
  "\uc18c\ud504\ud2b8\uc6e8\uc5b4"             = "IT",
  "\ubc18\ub3c4\uccb4"                         = "IT",
  "\ub514\uc2a4\ud50c\ub808\uc774"             = "IT",
  "\uac00\uc804IT"                             = "IT",
  "\uac00\uc804"                               = "IT",
  "IT\uac00\uc804"                             = "IT",
  "IT\ud558\ub4dc\uc6e8\uc5b4"                = "IT",
  # 통신
  "\ud1b5\uc2e0\uc11c\ube44\uc2a4"             = "Telecom",
  # 유틸리티
  "\uc720\ud2f8\ub9ac\ud2f0"                   = "Utilities"
)

# ── Step A: Expanding beta 사전 계산 (C2 — t-1 lag) ────────────
cat("[factor_engine] Step A: Expanding-window CAPM beta 계산...\n")

setorder(RAWDATA, Ticker, Date)

if (!"BM_Ret" %in% names(RAWDATA)) {
  bm_sub  <- BM_DT[, .(Date, BM_Ret)]
  RAWDATA <- merge(RAWDATA, bm_sub, by = "Date", all.x = TRUE)
}

# Expanding OLS beta via cumsum (벡터화, O(N) per ticker)
RAWDATA[, xy := Ret * BM_Ret]
RAWDATA[, x2 := BM_Ret^2]
RAWDATA[, `:=`(
  cum_x  = cumsum(replace(BM_Ret, is.na(BM_Ret), 0)),
  cum_y  = cumsum(replace(Ret,    is.na(Ret),    0)),
  cum_xy = cumsum(replace(xy,     is.na(xy),     0)),
  cum_x2 = cumsum(replace(x2,     is.na(x2),     0)),
  cum_n  = cumsum(as.integer(!is.na(BM_Ret) & !is.na(Ret)))
), by = Ticker]

RAWDATA[, Beta_Raw := {
  n      <- cum_n
  mx     <- cum_x / pmax(n, 1L)
  my     <- cum_y / pmax(n, 1L)
  cov_xy <- (cum_xy - n * mx * my) / pmax(n - 1L, 1L)
  var_x  <- (cum_x2 - n * mx^2)   / pmax(n - 1L, 1L)
  ifelse(n >= BETA_WINDOW & var_x > 1e-10, cov_xy / var_x, NA_real_)
}, by = Ticker]

# C2: t-1 lag — 당일 신호에 전일까지의 beta 사용
RAWDATA[, Beta_Lag := shift(Beta_Raw, 1L, type = "lag"), by = Ticker]
RAWDATA[, c("xy","x2","cum_x","cum_y","cum_xy","cum_x2","cum_n","Beta_Raw") := NULL]

# ── Step B: 유동성 사전 계산 (C10 — t-1 lag) ──────────────────
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, 20L, align = "right"), 1L, type = "lag"),
        by = Ticker]

cat("[factor_engine] Step A/B 완료: Beta_Lag + AvgTV20 계산됨.\n")

# ── Step C: 월 시그널 날짜 목록 ───────────────────────────────
RAWDATA[, YM := format(Date, "%Y-%m")]
signal_dates <- RAWDATA[, .(Signal_Date = max(Date)), by = YM][, sort(Signal_Date)]
signal_dates <- signal_dates[signal_dates >= SIGNAL_START_DATE]
cat(sprintf("[factor_engine] 시그널 날짜: %d개 (%s ~ %s)\n",
            length(signal_dates), min(signal_dates), max(signal_dates)))

# FDB_BULK에서 사용 가능한 날짜 목록 (메모리 조회용)
fdb_avail_dates <- sort(unique(FDB_BULK$Date))

# ── Step D: 월별 Sector-Neutral 점수 — lapply 기반 (OPT-1: 파일 I/O 없음) ──
cat("[factor_engine] Step D: 월별 Sector-Neutral 점수 계산 (lapply)...\n")

.score_one_month <- function(sig_d) {
  sig_d <- as.Date(sig_d)

  # 유동성 + Beta 스냅샷
  snap <- RAWDATA[Date == sig_d, .(Ticker, Close, AvgTV20, Beta_Lag, Sector)]
  snap <- snap[!is.na(Close) & Close > 0 &
               !is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(snap) < 30L) return(NULL)

  # Beta 하위 40% 필터 (cross-sectional percentile, t-1 lag)
  snap_beta <- snap[!is.na(Beta_Lag)]
  if (nrow(snap_beta) < 30L) return(NULL)

  snap_beta[, Beta_Pctile := rank(Beta_Lag, ties.method = "average") / .N]
  n40 <- sum(snap_beta$Beta_Pctile <= BETA_CUTOFF)
  n50 <- sum(snap_beta$Beta_Pctile <= BETA_FALLBACK)

  if (n40 >= MIN_UNIV_SIZE) {
    univ_beta <- snap_beta[Beta_Pctile <= BETA_CUTOFF, .(Ticker)]
  } else if (n50 >= MIN_UNIV_SIZE) {
    univ_beta <- snap_beta[Beta_Pctile <= BETA_FALLBACK, .(Ticker)]
  } else {
    return(NULL)
  }
  snap <- merge(univ_beta, snap, by = "Ticker")
  if (nrow(snap) < N_PER_SECTOR * MIN_SECTORS) return(NULL)

  # FDB_BULK 메모리 조회 (C14: Usable_Date <= sig_date)
  fdb_d <- suppressWarnings(max(fdb_avail_dates[fdb_avail_dates <= sig_d]))
  if (is.na(fdb_d) || is.infinite(fdb_d)) return(NULL)

  fdt <- FDB_BULK[Date == fdb_d & Ticker %in% snap$Ticker]
  if (nrow(fdt) == 0L) return(NULL)

  # Wide 변환 + 유니버스+Sector join
  fdt_wide <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned",
                    fill = NA_real_)
  dt <- merge(snap[, .(Ticker, Sector)], fdt_wide, by = "Ticker")

  # C13: Z_Score_Aligned 합산 (rowMeans — 추가 정규화 금지)
  fcols <- intersect(c("AC17_Accrual_Reversal",
                       "AC21_CF_to_Accrual_Ratio",
                       "AC22_Accrual_Volatility"), names(dt))
  if (length(fcols) == 0L) return(NULL)

  dt[, n_fac := rowSums(!is.na(.SD)), .SDcols = fcols]
  dt[, Score := rowMeans(.SD, na.rm = TRUE), .SDcols = fcols]
  dt <- dt[!is.na(Score) & n_fac >= 2L]
  if (nrow(dt) < N_PER_SECTOR * MIN_SECTORS) return(NULL)

  # Sector 중분류 → 대분류(10개) 매핑 적용
  dt[, Sector10 := SECTOR_MAP[Sector]]
  dt[is.na(Sector10), Sector10 := "Other"]

  # 대분류별 Score 상위 N_PER_SECTOR (최대 30종목)
  setorder(dt, Sector10, -Score)
  top <- dt[, head(.SD, N_PER_SECTOR), by = Sector10]

  if (uniqueN(top$Sector10) < MIN_SECTORS) return(NULL)

  top[, Date := sig_d]
  top[, .(Date, Ticker, Score, Sector10, n_fac)]
}

factor_list <- lapply(signal_dates, .score_one_month)

FACTORS <- rbindlist(factor_list[!vapply(factor_list, is.null, logical(1L))])
setorder(FACTORS, Date, -Score)

# ── 진단 출력 ─────────────────────────────────────────────────
n_done <- uniqueN(FACTORS$Date)
n_skip <- length(signal_dates) - n_done

cat("\n======== BCSNA 진단 ========\n")
cat(sprintf("  완료: %d개월 | 스킵: %d개월\n", n_done, n_skip))
if (nrow(FACTORS) > 0) {
  cnt_by_date <- FACTORS[, .N, by = Date]
  cat(sprintf("  선택 종목수: 평균=%.1f 최소=%d 최대=%d\n",
              mean(cnt_by_date$N), min(cnt_by_date$N), max(cnt_by_date$N)))
  sec_by_date <- FACTORS[, uniqueN(Sector10), by = Date]
  cat(sprintf("  대분류 수: 평균=%.1f 최소=%d 최대=%d\n",
              mean(sec_by_date$V1), min(sec_by_date$V1), max(sec_by_date$V1)))
}
cat("============================\n\n")

# 임시 컬럼 정리
cols_rm <- intersect(c("YM","TradingValue","AvgTV20","Beta_Lag"), names(RAWDATA))
if (length(cols_rm)) RAWDATA[, (cols_rm) := NULL]
gc(verbose = FALSE)

cat(sprintf("[factor_engine] FACTORS: %s rows | %d dates\n",
            format(nrow(FACTORS), big.mark = ","),
            uniqueN(FACTORS$Date)))
