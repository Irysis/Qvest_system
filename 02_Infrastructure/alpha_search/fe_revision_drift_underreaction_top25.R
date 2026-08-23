# =============================================================================
# fe_revision_drift_underreaction_top25.R — [배포형태 변형] "Analyst Underreaction and the Post-Forecast Revision Drift"
#   (JBFA 47(9-10), 2020) 의 KR 복제 (pg2 큐 title:analystunderreactionandthepostforecastrevisiondrift)
# =============================================================================
# 논문 핵심(pg2 기록): 리비전 후 드리프트(PFRD)는 애널리스트가 정보에 **과소반응**해 후속 리비전이
#   같은 방향으로 이어질 때 발생 — 현재 리비전 정보로 '후속 리비전 연쇄' 가 예측 가능하면 드리프트가 크다.
# KR 재구성 (pg2 implementation_sketch Phase 1 — 집계 컨센서스만, 애널리스트별 복제는 2단계):
#   - 피처(월말 d, factor DB 정렬 z): C02_EPS_Chg_1m · C03_EPS_Chg_3m · C04_ESBR · C05_ESCR · C16_EPS_Acceleration.
#   - 라벨 y_j = 1{ z(C03, j+3) > 0 } = 3개월 뒤 컨센서스가 상향돼 있는가(후속 리비전 연쇄).
#   - 학습: 월 i 에서 j ∈ [i−36, i−3] (라벨 창이 **완결된** 달만) 로지스틱 회귀 rolling IS-only(C1) →
#     월 i 의 P(후속 상향) 예측 → 상위 decile(ceiling(n/10), ≥5) EW. 월간 리밸(3M 신호를 월 단위로 굴림).
#   - 종목수·비중 논문 미명시 → 시스템 표준(명시 보충). 유니버스 K200∪KQ150 ∧ 유동성 2e8. 기간 2005~.
# ===== PIT (C1~C15) =====
#   - 월 i 의 학습 표본은 라벨 시점 j+3 ≤ i 인 달만(미래 라벨 사용 없음, C2). 피처·라벨 모두 PIT z
#     (Usable_Date ≤ sig_date, C14/C15). NEGATE 없음(C13). 예측 모델은 rolling 재적합(C1).
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))
setorder(RAWDATA, Ticker, Date)

local({
  conn <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", getwd()),
                    "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function")) source(conn)
})

F_FEAT <- c("C02_EPS_Chg_1m", "C03_EPS_Chg_3m", "C04_ESBR", "C05_ESCR", "C16_EPS_Acceleration")
F_LAB  <- "C03_EPS_Chg_3m"
H_LAB  <- 3L      # 라벨 지평(개월)
W_TR   <- 36L     # 학습 창(개월)

RAWDATA[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(RAWDATA[, .(Date = max(Date)), by = .ym]$Date)
RAWDATA[, .ym := NULL]
.month_ends <- .month_ends[.month_ends >= as.Date("2001-06-01")]

RAWDATA[, .TV := Close * Vol]
RAWDATA[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]
.mem <- RAWDATA[Date %in% .month_ends & (K200 == TRUE | KQ150 == TRUE) &
                  !is.na(.AvgTV20) & .AvgTV20 >= 2e8, .(Date, Ticker)]
setkey(.mem, Date, Ticker)
RAWDATA[, c(".TV", ".AvgTV20") := NULL]

# 월별 피처 테이블 캐시(달마다 1회 적재)
.ztab <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05, factor_names = F_FEAT), error = function(e) NULL)
  if (is.null(fdt) || !nrow(fdt)) next
  w <- dcast(fdt[Factor_Name %in% F_FEAT & is.finite(Z_Score_Aligned)],
             Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  for (f in F_FEAT) if (!(f %in% names(w))) w[, (f) := NA_real_]
  .ztab[[i]] <- w[, c("Ticker", F_FEAT), with = FALSE]
}

.factor_list <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  if (d < as.Date("2004-06-01")) next
  if (i <= W_TR + H_LAB || is.null(.ztab[[i]])) next
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  if (length(uni_tk) < 30L) next

  # 학습 표본: j ∈ [i−W_TR, i−H_LAB], 라벨 = z(C03, j+H_LAB) > 0 (j+H_LAB ≤ i 이므로 완결)
  tr <- rbindlist(lapply(seq(i - W_TR, i - H_LAB), function(j) {
    xj <- .ztab[[j]]; lj <- .ztab[[j + H_LAB]]
    if (is.null(xj) || is.null(lj)) return(NULL)
    m <- merge(xj, lj[, .(Ticker, y = as.integer(get(F_LAB) > 0))], by = "Ticker")
    m[complete.cases(m)]
  }), use.names = TRUE)
  if (is.null(tr) || nrow(tr) < 500L || uniqueN(tr$y) < 2L) next
  fml <- as.formula(paste("y ~", paste(F_FEAT, collapse = " + ")))
  fit <- tryCatch(suppressWarnings(glm(fml, data = tr, family = binomial())), error = function(e) NULL)
  if (is.null(fit)) next

  xi <- .ztab[[i]][Ticker %in% uni_tk]
  xi <- xi[complete.cases(xi)]
  if (nrow(xi) < 30L) next
  xi[, p := as.numeric(predict(fit, newdata = xi, type = "response"))]
  out <- xi[is.finite(p), .(Date = d, Ticker, Score = p)]
  out[, N := min(.N, 25L)]   # 배포 형태: 상위 25종
  .factor_list[[i]] <- out
}

FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)
if (!nrow(FACTORS)) stop("[fe_revision_drift_underreaction_top25] FACTORS 0 rows")

cat(sprintf("[fe_revision_drift_underreaction_top25] PFRD-underreaction KR: rolling 36M 로지스틱 P(후속 3M 상향) 상위 25종 EW 월간 | FACTORS rows=%d | signal months=%d | N median=%d\n",
            nrow(FACTORS), uniqueN(FACTORS$Date), as.integer(median(FACTORS$N))))
