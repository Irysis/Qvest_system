# =============================================================================
# fe_revision_innovation.R — Gleason & Lee (2003, TAR 78(1)) "Analyst Forecast Revisions
#   and Market Price Discovery" 의 KR 복제 (pg2 큐 doi:10.2308/accr.2003.78.1.193)
# =============================================================================
# 논문 핵심: 리비전 후 드리프트는 리비전의 **혁신도(innovation)** 에 달려 있다 — 기존
#   컨센서스에서 *이탈*하는 리비전(high-innovation = 새 정보)은 느리게 반영돼 드리프트가 크고,
#   컨센서스로 *수렴*하는 리비전(herding)은 정보가 적다. 같은 크기의 상향 리비전이라도
#   혁신도가 높을 때만 3개월 드리프트가 유의.
# KR 재구성 (pg2 큐 implementation_sketch 의 aggregate 프록시 — 브로커별 추정치 미가용):
#   - 리비전 크기: C03_EPS_Chg_3m (FY1 컨센서스 3개월 변화율, factor DB 정렬 z).
#   - 혁신도 프록시: 추정치 분산 변화 ΔDisp = z(C12_Estimate_Dispersion_Proxy, d) −
#     z(C12, d−3m). 수렴형(herding) 리비전은 분산이 **감소**, 혁신형은 유지/증가
#     → ΔDisp ≥ 0 이면 high-innovation.
#   - 신호: 상향 리비전(z(C03) > 0) ∧ high-innovation 만 후보, Score = z(C03) (크기 순).
#     후보 부족(<10) 시 그 달 제외. (수렴형 상향 리비전은 논문대로 제외 — 재조합 아님.)
#   - 포트폴리오: 논문은 혁신도×리비전 포트폴리오의 3M 드리프트 — 여기서는 후보 상위
#     decile(ceiling(n/10), ≥5) EW, 월간 리밸(3M 신호를 월 단위로 굴림 = 겹치는 3M 보유의 근사).
#     종목수·비중은 논문 미명시 → 시스템 표준(명시 보충).
#   - 유니버스 K200∪KQ150 ∧ 유동성 2e8 (PIT 시변). 기간 2005~ (C 계열 2005 이전 커버리지 낮음).
# ===== PIT (C1~C15) =====
#   - C03/C12 = load_month_factors(d)/(d−3m) 의 PIT z (Usable_Date ≤ sig_date, C14/C15).
#   - 월별 횡단면만 사용(C1), 미래 정보 없음(C2), NEGATE 없음(C13 — 정렬 z 그대로).
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

local({
  conn <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", getwd()),
                    "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function")) source(conn)
})

F_REV  <- "C03_EPS_Chg_3m"
F_DISP <- "C12_Estimate_Dispersion_Proxy"
LAG_M  <- 3L

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

.get_z <- function(d, fn) {
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05, factor_names = fn), error = function(e) NULL)
  if (is.null(fdt) || !nrow(fdt)) return(NULL)
  fdt[Factor_Name == fn & is.finite(Z_Score_Aligned), .(Ticker, z = Z_Score_Aligned)]
}

.factor_list <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  if (i <= LAG_M) next
  d_lag <- .month_ends[i - LAG_M]
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  if (length(uni_tk) < 30L) next

  rev  <- .get_z(d, F_REV);   if (is.null(rev)) next
  dsp  <- .get_z(d, F_DISP);  if (is.null(dsp)) next
  dsp0 <- .get_z(d_lag, F_DISP); if (is.null(dsp0)) next
  setnames(rev, "z", "Rev"); setnames(dsp, "z", "Disp"); setnames(dsp0, "z", "Disp0")
  x <- merge(merge(rev, dsp, by = "Ticker"), dsp0, by = "Ticker")
  x <- x[Ticker %in% uni_tk]
  if (nrow(x) < 30L) next
  x[, dDisp := Disp - Disp0]
  cand <- x[Rev > 0 & dDisp >= 0]          # 상향 ∧ high-innovation(분산 유지/증가)
  if (nrow(cand) < 10L) next
  out <- cand[, .(Date = d, Ticker, Score = Rev)]
  out[, N := pmax(5L, as.integer(ceiling(.N / 10)))]
  .factor_list[[i]] <- out
}

FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)
if (!nrow(FACTORS)) stop("[fe_revision_innovation] FACTORS 0 rows")

cat(sprintf("[fe_revision_innovation] Gleason-Lee(2003) KR: 상향 리비전(C03>0) ∧ 혁신형(ΔDisp>=0) → decile EW | FACTORS rows=%d | signal months=%d | N median=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), as.integer(median(FACTORS$N))))
