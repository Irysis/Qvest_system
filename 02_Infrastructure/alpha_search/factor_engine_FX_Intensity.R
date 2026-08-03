# =============================================================================
# factor_engine_FX_Intensity.R — FX 노출 강도 지수 (FQ-149)
# =============================================================================
# 가설: AWARE-FX 논문(arXiv:2607.27611) FX exposure baseline 직접 대응
#   신호: (|외화환산이익| + |외화환산손실|) / TotalAssets — FX 노출 강도
#   방향: 높은 FX 노출 기업이 적극 헤징 → 불확실성 감소 → 리스크 프리미엄 감소 → 초과수익 (long)
#
# 데이터 원천:
#   - .cache/dart/dart_raw_financials.parquet
#     account_nm = '외화환산이익' 또는 '외화환산손실', reprt_code=11011(사업보고서)
#   - .cache/fundamental_dart.parquet → TotalAssets
#     Factor_Date = bsns_year+1년 3/31 (PIT C4 준수)
#
# PIT 준수:
#   C4: annual report → 익년 3/31 이후 공개. Factor_Date 컨벤션 그대로 사용.
#   동일시점 참조 없음. 월간 보간 없음(연간 신호 동결).
#
# 차별점 vs STR_AS_FX_HEDGING_PROXY:
#   - 기존(FQ-147): 파생상품 보유액/총자산 — 헤징 '활동' 측정 → IC 음수
#   - 이번(FQ-149): 외화환산손익 절댓값/총자산 — FX '노출 크기' 측정
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ----- Step 1: dart_raw_financials에서 외화환산이익/손실 추출 -----------------
.dart_path <- file.path(PROJECT_ROOT, ".cache/dart/dart_raw_financials.parquet")
.fund_path <- file.path(PROJECT_ROOT, ".cache/fundamental_dart.parquet")

stopifnot(file.exists(.dart_path), file.exists(.fund_path))

suppressPackageStartupMessages(library(arrow))

.dart_raw <- as.data.table(read_parquet(.dart_path))

# 사업보고서(reprt_code=11011)의 연결재무제표(CFS) 우선, 없으면 OFS
# 외화환산이익 / 외화환산손실만 추출 (thstrm_amount = 당기 값)
.fx_rows <- .dart_raw[
  account_nm %in% c("외화환산이익", "외화환산손실") &
    reprt_code == "11011",
  .(Ticker, bsns_year, account_nm, thstrm_amount, fs_div)
]

# thstrm_amount가 character인 경우 numeric으로 변환 (쉼표 제거 후)
.fx_rows[, thstrm_amount := as.numeric(gsub(",", "", as.character(thstrm_amount)))]
.fx_rows <- .fx_rows[!is.na(thstrm_amount)]

# CFS/OFS 중복 시 CFS 우선 선택
.fx_rows[, fs_priority := ifelse(fs_div == "CFS", 1L, 2L)]
setorder(.fx_rows, Ticker, bsns_year, account_nm, fs_priority)
.fx_rows <- .fx_rows[, .SD[1L], by = .(Ticker, bsns_year, account_nm)]

# 절댓값 합산 (외화환산이익 + |외화환산손실|)
.fx_wide <- dcast(
  .fx_rows,
  Ticker + bsns_year ~ account_nm,
  value.var = "thstrm_amount",
  fun.aggregate = sum,
  fill = NA_real_
)

# 컬럼명 정리 (빈 경우 0으로)
if (!"외화환산이익" %in% names(.fx_wide)) .fx_wide[, `외화환산이익` := 0]
if (!"외화환산손실" %in% names(.fx_wide)) .fx_wide[, `외화환산손실` := 0]
.fx_wide[is.na(`외화환산이익`), `외화환산이익` := 0]
.fx_wide[is.na(`외화환산손실`), `외화환산손실` := 0]

.fx_wide[, FX_raw := abs(`외화환산이익`) + abs(`외화환산손실`)]

# ----- Step 2: TotalAssets 조인 -----------------------------------------------
.fund <- as.data.table(read_parquet(.fund_path))
# fundamental_dart Factor_Date = bsns_year+1년 3/31 (PIT C4 준수)
.fund_ta <- .fund[!is.na(TotalAssets) & TotalAssets > 0,
                  .(Ticker, bsns_year, TotalAssets, Factor_Date)]

# dart_raw bsns_year는 character가 아닌 integer 확인 후 조인
.fx_wide[, bsns_year := as.integer(bsns_year)]
.fund_ta[, bsns_year := as.integer(bsns_year)]

.fx_fund <- merge(.fx_wide[, .(Ticker, bsns_year, FX_raw)],
                  .fund_ta[, .(Ticker, bsns_year, TotalAssets, Factor_Date)],
                  by = c("Ticker", "bsns_year"), all = FALSE)

# ----- Step 3: FX_Intensity 계산 (FX 노출 강도 = FX_raw / TotalAssets) --------
.fx_fund[, FX_Intensity := FX_raw / TotalAssets]
.fx_fund <- .fx_fund[is.finite(FX_Intensity) & FX_Intensity >= 0]

# Factor_Date를 Date 형식으로
.fx_fund[, Factor_Date := as.Date(Factor_Date)]

cat(sprintf("[FX_Intensity] 신호 집계: %d행, %d종목, bsns_year %d~%d\n",
            nrow(.fx_fund),
            uniqueN(.fx_fund$Ticker),
            min(.fx_fund$bsns_year),
            max(.fx_fund$bsns_year)))

# ----- Step 4: RAWDATA 월말 날짜와 매핑 ----------------------------------------
# 연간 신호를 월별 RAWDATA 달력에 매핑
# PIT: 각 Factor_Date 이후 다음 Factor_Date 전까지 동결 (연간 1회 업데이트)
# shift 없음 — Factor_Date 자체가 익년 3/31로 PIT 안전

RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date
.me_dt <- data.table(Date = sort(.month_ends))

# 각 월말 날짜에 대해 가장 최근의 Factor_Date 신호를 찾는다 (rolling join)
# (Factor_Date <= 월말 중 최대 = "그 시점까지 공개된 최신 연간 신호")
.fx_signal <- unique(.fx_fund[, .(Ticker, Factor_Date, FX_Intensity)])

# rolling join: 각 월말 날짜에 대해 Factor_Date <= Date 중 최신 신호 할당
# data.table rolling join 사용 (cartesian 방지)
setorder(.fx_signal, Ticker, Factor_Date)
setorder(.me_dt, Date)

# RAWDATA의 유니버스 종목만
.tickers_univ <- unique(RAWDATA[LiqPass == TRUE, Ticker])
.fx_signal_univ <- .fx_signal[Ticker %in% .tickers_univ]

# 각 종목별로 Factor_Date를 기준으로 rolling join
# 방법: month_end 테이블을 종목별로 cross, 그 후 PIT 필터
# 종목이 많으므로 per-ticker loop 대신 data.table roll=TRUE join 사용
setkey(.fx_signal_univ, Ticker, Factor_Date)
.me_grid <- CJ(Ticker = .tickers_univ, Factor_Date = .me_dt$Date, sorted = FALSE)
setnames(.me_grid, "Factor_Date", "Date")
setkey(.me_grid, Ticker, Date)

# rolling join: Date에 대해 Factor_Date <= Date 최신 매칭
.signal_panel <- .fx_signal_univ[.me_grid, roll = TRUE, rollends = c(FALSE, TRUE),
                                  on = .(Ticker, Factor_Date = Date)]
setnames(.signal_panel, "Factor_Date", "Date")
.signal_panel <- .signal_panel[!is.na(FX_Intensity)]

cat(sprintf("[FX_Intensity] 신호 패널: %d행, 월말 %d개, 종목 %d개\n",
            nrow(.signal_panel),
            uniqueN(.signal_panel$Date),
            uniqueN(.signal_panel$Ticker)))

# ----- Step 5: 월별 횡단면 Z-score 정규화 ------------------------------------
.signal_panel[, Score := {
  mu <- mean(FX_Intensity, na.rm = TRUE)
  sg <- sd(FX_Intensity, na.rm = TRUE)
  if (is.na(sg) || sg == 0) NA_real_ else (FX_Intensity - mu) / sg
}, by = Date]

# ----- Step 6: FACTORS 산출 --------------------------------------------------
FACTORS <- .signal_panel[is.finite(Score),
                          .(Date, Ticker, Score)]

# 커버리지 요약
.cov_summary <- FACTORS[, .N, by = Date]
cat(sprintf("[FX_Intensity] FACTORS rows=%d | 월 평균 커버리지 %.1f종목 | 신호 날짜 %d개\n",
            nrow(FACTORS),
            mean(.cov_summary$N),
            uniqueN(FACTORS$Date)))
cat(sprintf("[FX_Intensity] 커버리지 범위: 최소 %d ~ 최대 %d 종목/월\n",
            min(.cov_summary$N), max(.cov_summary$N)))

# 임시 객체 정리
rm(.dart_raw, .fx_rows, .fx_wide, .fx_fund, .fund, .fund_ta,
   .fx_signal, .grid, .signal_panel, .cov_summary, .me_dt, .tickers_univ)
RAWDATA[, .ym := NULL]
