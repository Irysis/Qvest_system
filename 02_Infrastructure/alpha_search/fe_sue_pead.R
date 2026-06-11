# =============================================================================
# fe_sue_pead.R — Bernard & Thomas (1989) Post-Earnings-Announcement Drift (SUE)
#                 KR 충실 복제 factor engine
# =============================================================================
# 논문: Bernard, V.L. & Thomas, J.K. (1989) "Post-Earnings-Announcement Drift:
#   Delayed Price Response or Risk Premium" J. Accounting Research 27, 1-36
#   (+ Bernard-Thomas 1990 SUE 정의 정밀화).
#
# 핵심 시그널 (seasonal random walk 기대 대비 표준화 어닝 서프라이즈):
#   UE_t  = Q_eps,t − Q_eps,t−4        (계절 랜덤워크 기대오차 = 전년 동분기 대비)
#   드리프트 보정 δ_t = 직전 8분기 (Q − Q_{-4}) 평균
#   σ_t   = 직전 8분기 (Q − Q_{-4}) 표준편차   (추정창 σ — B&T 정의)
#   SUE_t = (UE_t − δ_t) / σ_t
#   → 매월 말 SUE 상위 decile EW long-only (논문: SUE decile, 공시후 60일 drift).
#
# 모드 표준 사상 (paper_spec_notes 명시):
#   - 논문은 'event-time decile + 공시후 60거래일 drift'. 본 alpha-search 모드는
#     월간 리밸 표준 → "매월 말, 최근 6개월(=공시후 ~120거래일) 내 공시된 최신 SUE
#     기준 top decile EW long-only"로 사상. drift window를 월간 캘린더-time decile로 근사.
#   - SUE는 '실적 서프라이즈'(실현 분기 순이익의 계절 RW 대비 표준화). fe_earnrev.R
#     (애널리스트 earnings revision)와 별개 신호 — 본 건은 실제 보고 이익 기반.
#
# ===== PIT self-assert (외부 parquet 의존 — detect_lookahead 정적분석 사각 보강) =====
#   - 접수일 = substr(rcept_no, 1, 8) = YYYYMMDD (공시 실제 접수 = 시장 가관측 시점).
#   - Usable_Date = 접수일 + 1 거래일 (당일 접수분은 익영업일부터 — C2 same-day 금지).
#   - 월말 t 시그널 = Usable_Date <= t 인 ticker별 가장 최근 filing만 사용 (미래 보고서 누설 금지).
#     → fe 내부 시그널일별 max(Usable_Date) <= Date 어서션 내장 (위반 시 stop).
#   - UE/δ/σ = 전부 과거·현재 보고 이익(접수 완료분)으로만 계산. forward label 아님.
#     계절차분 lag(shift 1..8)은 모두 과거 분기. σ 추정창도 당기 포함 과거만.
#   - 회계기준 일관성: CFS(연결) 우선, ticker 내 CFS 부재 분기만 OFS — 혼용 금지 self-assert.
#   - 분기 단일이익: thstrm_amount = 단일분기(3개월) 순이익(반기·3Q는 분기 표시).
#     사업보고서(11011)는 연간 → Q4 = 연간 − YTD(11014 add) 로 분해.
#   - 수동 부호반전(NEGATE/FLIP) 없음. Score = SUE 횡단면 랭크(높을수록 매수).
#   - 데이터 floor: DART 접수일 2015-06~ → 계절차분(lag4)+σ창 충족 후 시그널 가용
#     실효 ~2018~ (2005 mandate 미충족 — 명시 라벨).
# =============================================================================
suppressMessages({ library(data.table); library(arrow) })
stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

# ---- 0. 거래일 캘린더 (Usable_Date = 접수일 + 1 거래일) -------------------------
.TDAYS <- sort(unique(RAWDATA$Date))
.next_tday <- function(d) {
  i   <- findInterval(d, .TDAYS)        # d 이하 마지막 거래일 인덱스
  idx <- pmin(pmax(i + 1L, 1L), length(.TDAYS))   # 항상 d '이후' 첫 거래일(당일 접수=익일)
  .TDAYS[idx]
}

# ---- 1. DART 원천 분기 재무 로드 (factor DB 아님 — C15 대상 아님) ---------------
.dcp <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR",
                  Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")),
                  ".cache", "dart", "dart_raw_quarterly.parquet")
stopifnot(file.exists(.dcp))
.D <- as.data.table(read_parquet(.dcp,
        col_select = c("rcept_no","reprt_code","bsns_year","Ticker",
                       "sj_div","account_id","fs_div","thstrm_amount","thstrm_add_amount")))

# ---- 2. 당기순이익(IS) 행만: ifrs(-full)_ProfitLoss, 손익계산서(sj_div=IS/CIS) -----
.NI_ACC <- c("ifrs-full_ProfitLoss", "ifrs_ProfitLoss")
.D <- .D[account_id %in% .NI_ACC & sj_div %in% c("IS","CIS")]
.D[, thstrm_amount     := suppressWarnings(as.numeric(thstrm_amount))]
.D[, thstrm_add_amount := suppressWarnings(as.numeric(thstrm_add_amount))]
.D <- .D[is.finite(thstrm_amount)]

# 회계기준 일관성: filing(rcept_no)별 CFS 우선. 같은 ticker 내 CFS/OFS 혼용 금지.
.D[, fs_pref := fifelse(fs_div == "CFS", 1L, 2L)]
setorder(.D, Ticker, rcept_no, fs_pref)
# filing당 1행 (account_id·fs 우선순위 첫 행 — 동일 filing 중복 계정 방지)
.D <- .D[, .SD[1L], by = .(rcept_no, reprt_code, bsns_year, Ticker)]
# ticker별 회계기준 결정: CFS 존재하면 CFS-only, 아니면 OFS-only (혼용 차단)
.tk_fs <- .D[, .(has_cfs = any(fs_div == "CFS")), by = Ticker]
.D <- merge(.D, .tk_fs, by = "Ticker")
.D <- .D[(has_cfs & fs_div == "CFS") | (!has_cfs & fs_div == "OFS")]
.D[, has_cfs := NULL]
stopifnot(.D[, uniqueN(fs_div), by = Ticker][, max(V1)] == 1L)  # ticker내 단일 기준 self-assert

# ---- 3. 단일분기 순이익 q_ni 구성 -------------------------------------------------
#   11013(Q1)/11012(반기,Q2)/11014(Q3): thstrm_amount = 단일분기 3개월 이익.
#   11011(사업,Q4): thstrm = 연간 → Q4 = 연간 − YTD(11014 add_amount, 3Q 누적).
.qmap <- c("11013" = 1L, "11012" = 2L, "11014" = 3L, "11011" = 4L)
.D[, fq := .qmap[reprt_code]]
.D <- .D[is.finite(fq)]

# 11014(Q3)의 YTD 누적 = thstrm_add_amount (3Q 누적 순이익). ticker·연도별로 매핑.
#   (정정공시로 11014 중복 가능 → ticker·연도별 첫 접수분만, dup 방지)
.ytd3 <- .D[reprt_code == "11014" & is.finite(thstrm_add_amount)]
setorder(.ytd3, Ticker, bsns_year, rcept_no)
.ytd3 <- .ytd3[, .(ytd3 = thstrm_add_amount[1L]), by = .(Ticker, bsns_year)]
.D <- merge(.D, .ytd3, by = c("Ticker","bsns_year"), all.x = TRUE)
.D[, q_ni := fifelse(reprt_code == "11011",
                     thstrm_amount - ytd3,            # Q4 = 연간 − 3Q YTD
                     thstrm_amount)]                  # Q1/Q2/Q3 = 단일분기
.D <- .D[is.finite(q_ni)]

# ---- 4. 접수일 / Usable_Date -----------------------------------------------------
.D[, rcept_date := as.Date(substr(rcept_no, 1L, 8L), format = "%Y%m%d")]
.D <- .D[!is.na(rcept_date)]
.D[, Usable_Date := .next_tday(rcept_date)]

# ---- 5. 분기 시계열 정렬 (회계연도·분기 = 시간축. shift는 전부 과거) ------------
.D[, qkey := bsns_year * 4L + (fq - 1L)]   # 분기 단조 인덱스 (연속성 위해)
setorder(.D, Ticker, qkey)
# 같은 (Ticker, qkey) 중복(정정공시 등): 가장 이른 접수(최초 공시) 채택 — 미래 정정 누설 금지
.D <- .D[, .SD[which.min(rcept_date)], by = .(Ticker, qkey)]
setorder(.D, Ticker, qkey)

# ---- 6. SUE 구성: 계절차분 UE = q_ni − q_ni(lag4), δ/σ = 직전 8분기 차분 -------
#   shift(1..8) by Ticker over qkey-ordered series — 전부 과거 분기. forward 없음.
.D[, ni_l4 := shift(q_ni, 4L), by = Ticker]
.D[, ue := q_ni - ni_l4]                              # 계절 RW 기대오차
# 직전 8분기 (당기 제외 과거) UE의 평균(δ)·표준편차(σ) — 추정창
for (k in 1:8) .D[, paste0("ue_l", k) := shift(ue, k), by = Ticker]
.uecols <- paste0("ue_l", 1:8)
.D[, n_ue := rowSums(!is.na(.SD)), .SDcols = .uecols]
.D[, delta := rowMeans(.SD, na.rm = TRUE), .SDcols = .uecols]
.D[, sigma := apply(.SD, 1L, function(v) { v <- v[is.finite(v)];
                    if (length(v) >= 4L) sd(v) else NA_real_ }), .SDcols = .uecols]
# σ 충족 최소 4분기(논문 8분기 — KR 데이터 floor로 4분기 완화, 명시 라벨)
.D[, SUE := fifelse(is.finite(sigma) & sigma > 0 & is.finite(ue),
                    (ue - delta) / sigma, NA_real_)]
SUEDT <- .D[is.finite(SUE), .(Ticker, qkey, rcept_date, Usable_Date, SUE, q_ni, ue, n_ue)]
setorder(SUEDT, Ticker, rcept_date)

# ---- 7. 월말 시그널 날짜 그리드 -------------------------------------------------
RAWDATA[, .ym := format(Date, "%Y-%m")]
.MEND <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)

# ---- 8. 각 시그널일 t: Usable_Date <= t & 최근 6개월 내 공시된 ticker별 최신 SUE ----
#   논문 'event-time 공시후 drift'를 월간 캘린더 decile로 사상: 최근 6개월(126거래일~) 공시분만.
.SIX_M <- 183L   # 달력 6개월(일). 공시후 ~120거래일 drift window 근사.
.build_signal <- function(t) {
  cand <- SUEDT[Usable_Date <= t & rcept_date > (t - .SIX_M)]
  if (!nrow(cand)) return(NULL)
  setorder(cand, Ticker, rcept_date)
  latest <- cand[, .SD[.N], by = Ticker, .SDcols = c("SUE","Usable_Date","rcept_date")]
  latest[, Date := t]
  latest
}
SIGL <- rbindlist(lapply(.MEND, .build_signal), use.names = TRUE, fill = TRUE)
SIGL <- SIGL[is.finite(SUE)]

# ---- 8b. ★ PIT self-assert: 시그널일별 max(Usable_Date) <= 시그널일 -------------
.maxuse <- SIGL[, .(mx = max(Usable_Date)), by = Date]
if (nrow(.maxuse[mx > Date]) > 0L)
  stop(sprintf("[fe_sue_pead][PIT-FAIL] 미래 filing 누설: %d 시그널일 Usable_Date > 시그널일",
               nrow(.maxuse[mx > Date])))
cat("[fe_sue_pead][PIT-OK] 시그널일별 max(Usable_Date) <= 시그널일 — 미래참조 없음 검증 통과\n")

# ---- 9. 유동성 통과 결합 → SUE 횡단면 랭크 --------------------------------------
.LP <- RAWDATA[Date %in% .MEND, .(Date, Ticker, LiqPass)]
SIG <- merge(SIGL, .LP, by = c("Date","Ticker"))
SIG <- SIG[LiqPass == TRUE & is.finite(SUE)]
# Score = 같은 시그널일 횡단면 SUE 랭크 [0,1] (높을수록 good news = 매수)
SIG[, Score := frank(SUE, ties.method = "average") / .N, by = Date]

# ---- 10. decile N (각 시그널일 상위 10%, EW) — 종목수 임의 제한 안 함 -----------
.NDT <- SIG[, .(N = as.integer(pmax(1L, round(.N / 10)))), by = Date]
FACTORS <- merge(SIG[, .(Date, Ticker, Score, SUE)], .NDT, by = "Date")
setorder(FACTORS, Date, -Score)

cat(sprintf("[fe_sue_pead] FACTORS rows=%d | dates=%d | tickers=%d | decile N=%d~%d med=%d | cand/mo med=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker),
            min(.NDT$N), max(.NDT$N), as.integer(median(.NDT$N)),
            as.integer(median(SIG[, .N, by = Date]$N))))
cat(sprintf("[fe_sue_pead] 데이터 floor: 시그널 최초 %s (DART 접수일 2015-06~, σ창 충족 후. 2005 mandate 미충족 명시)\n",
            as.character(min(FACTORS$Date))))

# 정리
RAWDATA[, c(".ym") := NULL]
rm(.D, .ytd3, .tk_fs, SUEDT, SIGL, SIG, .LP, .NDT, .MEND, .maxuse); gc(verbose = FALSE)
