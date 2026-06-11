# =============================================================================
# fe_disclosure_meta.R — DART 공시 메타데이터 알파 (KR-native 가설, 미테스트 직교축)
# =============================================================================
# 가설: 공시의 *내용이 아닌 메타데이터*(적시성)가 횡단면 수익을 예측한다.
#   법정 마감 대비 조기 공시(earliness 높음) = 우량 신호 → long.
#   (문헌 맥락: deHaan-Shevlin-Thornock 2017 악재 타이밍 / You-Zhang 2009 복잡도 /
#    Cohen-Malloy-Nguyen 2020 Lazy Prices. 단 본 건은 KR-native 가설 검증이지 특정 논문 복제 아님.)
#
# 산출: FACTORS(Date, Ticker, Score, N)  — P1(primary) earliness 횡단면 랭크, 상위 decile EW.
#   진단(게이트 미사용): SIG에 dlate(P2 Δlateness), dstruct(P3 line-item 구조변화) 동봉 → 러너가 IC 계산.
#
# ===== PIT self-assert (외부 parquet 의존 — detect_lookahead 정적분석 사각 보강) =====
#   - 접수일 = substr(rcept_no, 1, 8) = YYYYMMDD (공시 실제 접수 시점, 시장 가관측 시점).
#   - Usable_Date = 접수일 + 1 거래일 (당일 접수분은 익영업일부터 사용 — C2 same-day 금지).
#   - 월말 t 시그널 = Usable_Date <= t 인 가장 최근 filing만 사용 (미래 보고서 절대 누설 금지).
#     → fe 내부에 시그널일별 max(Usable_Date) <= Date 어서션 내장 (위반 시 stop).
#   - earliness = 법정마감 - 접수일 (모두 과거/현재 관측치, forward label 아님).
#   - 횡단면 랭크 = 같은 시그널일 내 횡단면(C1 full-sample 통계 아님 — 시점별 독립 랭크).
#   - 수동 부호반전(NEGATE/FLIP) 없음. Score = earliness 랭크(높을수록 조기 = 매수).
#   - 데이터 floor: DART 캐시 접수일 2015-06~ → 시그널 가용 2016~ (2005 mandate 미충족, 명시 라벨).
#
# 법정마감 (Dec-FYE 가정 — KR 상장사 절대다수. 비-12월 결산은 소수, 본 가정 명시 라벨):
#   11013(Q1) 기말 3/31 +45일 / 11012(반기) 기말 6/30 +45일 /
#   11014(Q3) 기말 9/30 +45일 / 11011(사업) 기말 12/31 +90일.
# =============================================================================
suppressMessages({ library(data.table); library(arrow) })
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- 0. 거래일 캘린더 (Usable_Date = 접수일 + 1 거래일 계산용) ----------------
.TDAYS <- sort(unique(RAWDATA$Date))
# 접수일 d 에 대해, d 보다 '이후'인 가장 빠른 거래일 = 익영업일(당일 접수 = 익일 사용, C2)
.next_tday <- function(d) {
  i <- findInterval(d, .TDAYS)          # d 이하의 마지막 거래일 인덱스
  # d 가 거래일이면 그 다음 거래일, 비거래일이면 d 이후 첫 거래일
  idx <- fifelse(i >= 1L & i <= length(.TDAYS) & .TDAYS[pmax(i,1L)] == d, i + 1L, i + 1L)
  idx <- pmin(pmax(idx, 1L), length(.TDAYS))
  .TDAYS[idx]
}

# ---- 1. DART 공시 메타데이터 로드 (원천 공시 캐시 — factor DB 아님) ------------
.dcp <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR",
                  Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")),
                  ".cache", "dart", "dart_raw_quarterly.parquet")
stopifnot(file.exists(.dcp))
.D <- as.data.table(read_parquet(.dcp,
        col_select = c("rcept_no","reprt_code","bsns_year","Ticker","fs_div","account_id")))

# filing 단위(rcept_no)로 축약 + P3용 account row 수(fs_div=CFS 우선, 없으면 OFS)
.D[, fs_pref := fifelse(fs_div == "CFS", 1L, 2L)]                  # CFS 우선
.acc <- .D[, .(n_acc = uniqueN(account_id), fs_min = min(fs_pref)),
           by = .(rcept_no, reprt_code, bsns_year, Ticker)]
# 같은 filing 안에 CFS/OFS 둘 다 있으면 CFS 기준 account 수만 채택
.accCFS <- .D[fs_div == "CFS", .(n_acc = uniqueN(account_id)),
              by = .(rcept_no, reprt_code, bsns_year, Ticker)]
.accOFS <- .D[fs_div == "OFS", .(n_acc = uniqueN(account_id)),
              by = .(rcept_no, reprt_code, bsns_year, Ticker)]
FIL <- unique(.D[, .(rcept_no, reprt_code, bsns_year, Ticker)])
FIL <- merge(FIL, .accCFS, by = c("rcept_no","reprt_code","bsns_year","Ticker"), all.x = TRUE)
FIL[is.na(n_acc), n_acc := .accOFS[.SD, n_acc, on = c("rcept_no","reprt_code","bsns_year","Ticker")]]
FIL[is.na(n_acc), n_acc := 0L]

# ---- 2. 접수일 / 법정마감 / earliness ----------------------------------------
FIL[, rcept_date := as.Date(substr(rcept_no, 1L, 8L), format = "%Y%m%d")]
FIL <- FIL[!is.na(rcept_date)]
.period_end <- function(yr, rc)
  fcase(rc == "11013", as.Date(sprintf("%d-03-31", yr)),
        rc == "11012", as.Date(sprintf("%d-06-30", yr)),
        rc == "11014", as.Date(sprintf("%d-09-30", yr)),
        rc == "11011", as.Date(sprintf("%d-12-31", yr)),
        default = as.Date(NA))
FIL[, pe := .period_end(bsns_year, reprt_code)]
FIL[, deadline := fifelse(reprt_code == "11011", pe + 90L, pe + 45L)]   # 사업 90일 / 분기·반기 45일
FIL[, earliness := as.integer(deadline - rcept_date)]                   # +면 마감 전(조기), -면 지연
FIL <- FIL[is.finite(earliness)]

# Usable_Date = 접수일 + 1 거래일 (PIT: 당일 접수분도 익영업일부터)
FIL[, Usable_Date := .next_tday(rcept_date)]
setorder(FIL, Ticker, rcept_date)

# ---- 3. P2 진단: Δlateness = 당기 earliness - 직전 4개 filing 평균 earliness ----
#   (rcept_date 순. shift(lag) — 전부 과거 filing. forward 없음.)
FIL[, e_l1 := shift(earliness, 1L), by = Ticker]
FIL[, e_l2 := shift(earliness, 2L), by = Ticker]
FIL[, e_l3 := shift(earliness, 3L), by = Ticker]
FIL[, e_l4 := shift(earliness, 4L), by = Ticker]
FIL[, prev4_mean := rowMeans(.SD, na.rm = FALSE), .SDcols = c("e_l1","e_l2","e_l3","e_l4")]
FIL[, dlate := earliness - prev4_mean]                                  # 적시성 변화(악화 탐지)

# ---- 4. P3 진단: line-item 구조변화 = n_acc 전기 대비 변화율 -------------------
FIL[, n_acc_l1 := shift(n_acc, 1L), by = Ticker]
FIL[, dstruct := fifelse(is.finite(n_acc_l1) & n_acc_l1 > 0,
                         (n_acc - n_acc_l1) / n_acc_l1, NA_real_)]       # account row 수 변화율

# ---- 5. 월말 시그널 날짜 그리드 (유니버스 canonical 월말 거래일) ---------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.MEND <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date                  # 각 달 마지막 거래일
.MEND <- sort(.MEND)

# ---- 6. 각 시그널일 t: Usable_Date <= t 인 ticker별 '가장 최근' filing 선택 ----
#   PIT 핵심: t 시점에 가관측인 filing만. 미래 보고서 절대 차단.
.build_signal <- function(t) {
  cand <- FIL[Usable_Date <= t]
  if (!nrow(cand)) return(NULL)
  setorder(cand, Ticker, rcept_date)
  latest <- cand[, .SD[.N], by = Ticker,
                 .SDcols = c("earliness","dlate","dstruct","Usable_Date","rcept_date")]
  latest[, Date := t]
  latest
}
SIGL <- rbindlist(lapply(.MEND, .build_signal), use.names = TRUE, fill = TRUE)
SIGL <- SIGL[is.finite(earliness)]

# ---- 6b. ★ PIT self-assert: 시그널일별 사용 filing 의 Usable_Date <= 시그널일 ---
.maxuse <- SIGL[, .(mx = max(Usable_Date)), by = Date]
if (nrow(.maxuse[mx > Date]) > 0L)
  stop(sprintf("[fe_disclosure_meta][PIT-FAIL] 미래 filing 누설: %d 시그널일에서 Usable_Date > 시그널일",
               nrow(.maxuse[mx > Date])))
cat("[fe_disclosure_meta][PIT-OK] 시그널일별 max(Usable_Date) <= 시그널일 — 미래참조 없음 검증 통과\n")

# ---- 7. 유동성 통과 + (현 시그널일 시점) 결합 → P1 earliness 횡단면 랭크 -------
.LP <- RAWDATA[Date %in% .MEND, .(Date, Ticker, LiqPass)]
SIG <- merge(SIGL, .LP, by = c("Date","Ticker"))
SIG <- SIG[LiqPass == TRUE & is.finite(earliness)]

# P1 Score = 같은 시그널일 횡단면 earliness 랭크 (heavy tail robust, rank-invariant).
#   높을수록 조기 공시 = 매수. [0,1] 정규화 랭크.
SIG[, Score := frank(earliness, ties.method = "average") / .N, by = Date]

# ---- 8. decile N (각 시그널일 상위 10%, EW) — 종목수 임의 제한 안 함 -----------
.NDT <- SIG[, .(N = as.integer(pmax(1L, round(.N / 10)))), by = Date]
FACTORS <- merge(SIG[, .(Date, Ticker, Score, earliness, dlate, dstruct)], .NDT, by = "Date")
setorder(FACTORS, Date, -Score)

cat(sprintf("[fe_disclosure_meta] FACTORS rows=%d | dates=%d | tickers=%d | decile N=%d~%d med=%d | cand/mo med=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker),
            min(.NDT$N), max(.NDT$N), as.integer(median(.NDT$N)),
            as.integer(median(SIG[, .N, by = Date]$N))))
cat(sprintf("[fe_disclosure_meta] 데이터 floor: 시그널 최초 %s (DART 접수일 2015-06~ → 2016 가용. 2005 mandate 미충족 명시)\n",
            as.character(min(FACTORS$Date))))

# 정리 (RAWDATA 임시컬럼 제거)
RAWDATA[, c(".ym") := NULL]
rm(.D, .acc, .accCFS, .accOFS, FIL, SIGL, SIG, .LP, .NDT, .MEND, .maxuse); gc(verbose = FALSE)
