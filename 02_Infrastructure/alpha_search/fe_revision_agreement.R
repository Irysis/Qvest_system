# =============================================================================
# fe_revision_agreement.R — Feldman, Livnat & Zhang (2012, JPM 38(3)) "Analysts' Earnings
#   Forecast, Recommendation, and Target Price Revisions" 의 KR 복제 (pg2 큐 doi:10.3905/jpm.2012.38.3.120)
# =============================================================================
# 논문 핵심(abstract 수준 — 본문 paywall, pg2 큐 기록): EPS 추정 리비전 · 목표주가 리비전 · 투자의견
#   변경 3종의 **방향 일치(agreement)** 포트폴리오가 단일 리비전 신호 대비 유의하게 큰 드리프트.
# KR 재구성 (pg2 implementation_sketch Phase 1 — 기존 데이터만):
#   - 투자의견(recommendation) 리비전 데이터 미보유 ⇒ 3종 중 2종(EPS 리비전 · TP 리비전) + 리비전
#     폭(ESBR, 상향 비중)으로 대체한 3-조건 conjunction: z(C03_EPS_Chg_3m)>0 ∧ z(C04_ESBR)>0 ∧
#     z(C07_TP_Mom)>0. (★paper_assumption_broken = 투자의견 축 부재 — 완전 복제 아님, 명시)
#   - z>0 = 횡단면 평균 이상(정렬 z). 스케치의 ESBR>0.5(원값) 는 factor DB 에 원값이 없어 z>0 로 보충.
#   - 포트폴리오: 일치 종목 **전부** EW(논문은 '3종 정보를 모두 쓴 포트폴리오' — 종목수 미명시 ⇒
#     일치 집합 전체, 동적 N). Score = 3축 z 평균(순위용). 월간 리밸(시스템 표준; 논문 보유기간 미확인).
#   - ★일치 집합이 25종을 넘는 달이 많음 — Production 25종 상한과 충돌, 검증 단계는 논문 우선(명시).
#   - 유니버스 K200∪KQ150 ∧ 유동성 2e8 (PIT 시변). 기간 2005~.
# ===== PIT (C1~C15) =====
#   - 세 팩터 모두 load_month_factors(d) PIT z (Usable_Date ≤ sig_date, C14/C15). 월별 횡단면만(C1),
#     미래 정보 없음(C2), NEGATE 없음(C13).
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

local({
  conn <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", getwd()),
                    "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function")) source(conn)
})

F_EPS <- "C03_EPS_Chg_3m"; F_BR <- "C04_ESBR"; F_TP <- "C07_TP_Mom"
F_ALL <- c(F_EPS, F_BR, F_TP)

RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]
.month_ends <- .month_ends[.month_ends >= as.Date("2004-06-01")]

RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]
.mem <- RAWDATA[Date %in% .month_ends & (K200 == TRUE | KQ150 == TRUE) &
                  !is.na(.AvgTV20) & .AvgTV20 >= 2e8, .(Date, Ticker)]
setkey(.mem, Date, Ticker)
RAWDATA[, c(".TV", ".AvgTV20") := NULL]

.factor_list <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  if (length(uni_tk) < 30L) next
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05, factor_names = F_ALL), error = function(e) NULL)
  if (is.null(fdt) || !nrow(fdt)) next
  w <- dcast(fdt[Factor_Name %in% F_ALL & is.finite(Z_Score_Aligned)],
             Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  if (!all(F_ALL %in% names(w))) next
  w <- w[Ticker %in% uni_tk & is.finite(get(F_EPS)) & is.finite(get(F_BR)) & is.finite(get(F_TP))]
  if (nrow(w) < 30L) next
  agree <- w[get(F_EPS) > 0 & get(F_BR) > 0 & get(F_TP) > 0]   # 3-조건 방향 일치
  if (nrow(agree) < 5L) next
  out <- agree[, .(Date = d, Ticker, Score = (get(F_EPS) + get(F_BR) + get(F_TP)) / 3)]
  out[, N := .N]
  .factor_list[[i]] <- out
}

FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)
if (!nrow(FACTORS)) stop("[fe_revision_agreement] FACTORS 0 rows")

cat(sprintf("[fe_revision_agreement] Feldman-Livnat-Zhang(2012) KR: EPS_Chg_3m>0 ∧ ESBR>0 ∧ TP_Mom>0 일치 집합 전체 EW | FACTORS rows=%d | signal months=%d | N range=%d~%d (median %d)\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), min(FACTORS$N), max(FACTORS$N), as.integer(median(FACTORS$N))))
