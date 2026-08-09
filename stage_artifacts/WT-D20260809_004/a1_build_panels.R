## WT-D20260809_004 (FQ-173) — A1 패널 빌드 (한 번만, 이후 arm 들이 재사용)
## PIT 규약: 홀딩월 M 의 신호는 sig_date = M-1 월말 거래일 시점 데이터만.
##   - T5YIE : sig_date 이하 마지막 일간 관측
##   - KR_CPI / Copper : 참조월 M-2 (관측된 발표 lag — 아래 실측 근거 기록)
##   - z : expanding window, 최소 36개월 (full-sample z 는 C1 위반)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
say <- function(fmt, ...) cat(sprintf(paste0("[A1] ", fmt, "\n"), ...))
OUT <- "stage_artifacts/WT-D20260809_004"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

## ── vintage 기록 (§7 pinning 정합 — 판정 산출물에 vintage tag 기록) ──────────
vin <- list(
  rawdata = list(path = ".cache/rawdata.parquet",
                 size = file.size(".cache/rawdata.parquet"),
                 mtime = as.character(file.mtime(".cache/rawdata.parquet"))),
  fred = list(path = ".cache/fred_macro.parquet", size = file.size(".cache/fred_macro.parquet"),
              mtime = as.character(file.mtime(".cache/fred_macro.parquet"))),
  ecos = list(path = ".cache/ecos_bond_rates.parquet", size = file.size(".cache/ecos_bond_rates.parquet"),
              mtime = as.character(file.mtime(".cache/ecos_bond_rates.parquet")))
)
say("vintage: rawdata mtime=%s · fred mtime=%s", vin$rawdata$mtime, vin$fred$mtime)

## ── 1. rawdata (필요 컬럼만) ─────────────────────────────────────────────────
RAW <- as.data.table(read_parquet(".cache/rawdata.parquet",
  col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150","Sector",
                 "AdminStock","TradingHalt")))
say("rawdata 원본 %s행 · Date 고유 %d · 관측단위 일간(간격 중앙 %.0f일)",
    format(nrow(RAW), big.mark=","), uniqueN(RAW$Date),
    median(as.numeric(diff(sort(unique(RAW$Date))))))
RAW <- RAW[Date >= as.Date("2002-01-01")]
say("2002-01-01 이후로 절단: %s행 · %s ~ %s", format(nrow(RAW), big.mark=","),
    as.character(min(RAW$Date)), as.character(max(RAW$Date)))

## 월말 거래일
alld <- sort(unique(RAW$Date))
me <- data.table(Date = alld)[, ym := format(Date, "%Y%m")][, .(Date = max(Date)), by = ym]
sig_dates <- me[ym >= "200212"]$Date          # 첫 신호 = 2002-12 월말 → 홀딩월 2003-01
say("월말 거래일 %d개 · 신호일 %d개 (%s ~ %s)", nrow(me), length(sig_dates),
    as.character(min(sig_dates)), as.character(max(sig_dates)))

## ── 2. adv20 (20 거래일 평균 거래대금, sig_date 포함 — C10 t-1 PIT) ─────────
setorder(RAW, Ticker, Date)
RAW[, tv := Close * Vol]
RAW[, adv20 := frollmean(tv, 20, na.rm = TRUE), by = Ticker]
ME <- RAW[Date %in% sig_dates]
say("월말 스냅샷 %s행 · adv20 결측 %.1f%%", format(nrow(ME), big.mark=","),
    100*mean(is.na(ME$adv20)))
say("adv20 >= 2e8 통과율(유니버스 내) %.1f%%",
    100*ME[(K200 == TRUE | KQ150 == TRUE), mean(!is.na(adv20) & adv20 >= 2e8)])

## ── 3. forward returns / benchmark / liq (repo 표준 함수 경유) ──────────────
source("02_Infrastructure/ramp/factor_validation.R")
rawme <- RAW[Date %in% sig_dates, .(Date, Ticker, Close, Vol, Size, K200, KQ150)]
fwd <- build_monthly_forward_returns(rawme, sig_dates)
say("returns_dt %s행 · Date %d · bench_dt %d행",
    format(nrow(fwd$returns_dt), big.mark=","), uniqueN(fwd$returns_dt$Date), nrow(fwd$bench_dt))
say("bench 기간 %s ~ %s · BM_Ret 평균 %.4f/월",
    as.character(min(fwd$bench_dt$Date)), as.character(max(fwd$bench_dt$Date)),
    mean(fwd$bench_dt$BM_Ret))

## 유동성 패널 = 실측 20일 평균 거래대금 (repo 표준 Vol0*Close0 단일일 근사보다 엄격)
liq20 <- ME[, .(Date, Ticker, adv = adv20)]
liq1d <- fwd$liq_dt   # 비교용(표준 근사)

## ── 4. 섹터 / 유니버스 자격 ─────────────────────────────────────────────────
ELIG <- ME[(K200 == TRUE | KQ150 == TRUE) & !is.na(Sector) & Sector != "" &
             (is.na(AdminStock) | AdminStock != TRUE) &
             (is.na(TradingHalt) | TradingHalt != TRUE) &
             !is.na(adv20) & adv20 >= 2e8,
           .(Date, Ticker, Sector, Size, adv20)]
say("자격 패널(K200|KQ150 ∧ Sector ∧ !Admin ∧ !Halt ∧ adv20>=2e8): %s행 · 월평균 %.0f종목",
    format(nrow(ELIG), big.mark=","), nrow(ELIG)/uniqueN(ELIG$Date))
say("Sector 고유 %d", uniqueN(ELIG$Sector))
print(ELIG[, .N, by = Sector][order(-N)][1:10])

## ── 5. 성장 팩터 3종 (load_month_factors 경유 = C15) ────────────────────────
source("02_Infrastructure/factor_db/factor_db_connector.R")
GF <- c("C01_SUE", "C02_EPS_Chg_1m", "M26_Revenue_Mom")
fl <- lapply(sig_dates, function(d) {
  x <- tryCatch(load_month_factors(d, coverage_min = 0.05, factor_names = GF),
                error = function(e) NULL)
  if (is.null(x) || !nrow(x)) return(NULL)
  x <- as.data.table(x)
  keep <- intersect(c("Ticker","Factor_Name","Z_Score","Date"), names(x))
  x <- x[, ..keep]
  x[, sig_date := d][]
})
FAC <- rbindlist(fl, fill = TRUE)
say("팩터 패널 %s행 · sig_date %d · 팩터 %s",
    format(nrow(FAC), big.mark=","), uniqueN(FAC$sig_date), paste(unique(FAC$Factor_Name), collapse=","))
## as-of 정합 확인: 팩터 파일의 Date 가 sig_date 와 같은 달인가
if ("Date" %in% names(FAC)) {
  chk <- unique(FAC[, .(sig_date, asof = as.Date(Date))])
  chk[, same_ym := format(sig_date, "%Y%m") == format(asof, "%Y%m")]
  say("팩터 as-of 와 sig_date 동월 비율 %.1f%% (불일치 %d건)",
      100*mean(chk$same_ym), sum(!chk$same_ym))
  say("as-of − sig_date 일수: 중앙값 %.0f · 범위 [%.0f, %.0f]",
      median(as.numeric(chk$asof - chk$sig_date)),
      min(as.numeric(chk$asof - chk$sig_date)), max(as.numeric(chk$asof - chk$sig_date)))
}

## ── 6. 합성 인플레 지수 infl_t ──────────────────────────────────────────────
FR <- as.data.table(read_parquet(".cache/fred_macro.parquet"))
T5 <- FR[Series == "Breakeven_5Y", .(Date, v = Value)][order(Date)][!is.na(v)]
CU <- FR[Series == "Copper_Price", .(Date, v = Value)][order(Date)][!is.na(v)]
EC <- as.data.table(read_parquet(".cache/ecos_bond_rates.parquet"))
CP <- EC[Series == "KR_CPI", .(Date, v = Value)][order(Date)][!is.na(v)]
say("T5YIE %d행 %s~%s · Copper %d행 %s~%s · KR_CPI %d행 %s~%s",
    nrow(T5), as.character(min(T5$Date)), as.character(max(T5$Date)),
    nrow(CU), as.character(min(CU$Date)), as.character(max(CU$Date)),
    nrow(CP), as.character(min(CP$Date)), as.character(max(CP$Date)))

## 발표 lag 실측 근거: 캐시 refresh 시점(rawdata max Date) 대비 각 월간 계열의 최신 참조월
say("★발표 lag 실측: 캐시 최신 거래일 %s 시점에 Copper 최신 참조월 %s · KR_CPI 최신 참조월 %s",
    as.character(max(alld)), format(max(CU$Date), "%Y-%m"), format(max(CP$Date), "%Y-%m"))

## YoY (월간 계열, 참조월 기준)
CU[, yoy := v / shift(v, 12) - 1]
CP[, yoy := v / shift(v, 12) - 1]

## sig_date 별 원자료 4성분 (PIT 정렬)
sig_tbl <- data.table(sig_date = sig_dates)
sig_tbl[, hold_ym := format(as.Date(format(sig_date, "%Y-%m-01")) + 40, "%Y-%m")]  # 홀딩월 M
sig_tbl[, hold_first := as.Date(paste0(hold_ym, "-01"))]
## T5YIE: sig_date 이하 마지막 관측 + 60거래일 전 관측
T5s <- T5[, .(Date, v)]
setkey(T5s, Date)
sig_tbl[, t5_lvl := T5s[.(sig_tbl$sig_date), v, roll = TRUE]]
## 60 거래일 모멘텀: T5 시계열 내부 index 사용
T5s[, v60 := shift(v, 60)]
sig_tbl[, t5_mom := T5s[.(sig_tbl$sig_date), v - v60, roll = TRUE]]
## KR_CPI / Copper: 참조월 M-2 (홀딩월 M 기준)
ref_m2 <- function(hold_first) as.Date(format(seq(hold_first, by = "-2 months", length.out = 2)[2], "%Y-%m-01"))
sig_tbl[, ref_ym2 := as.Date(sapply(hold_first, function(d) as.character(ref_m2(d))))]
CPk <- CP[, .(ref = Date, cpi_yoy = yoy)]; setkey(CPk, ref)
CUk <- CU[, .(ref = Date, cu_yoy = yoy)]; setkey(CUk, ref)
sig_tbl[, cpi_yoy := CPk[.(sig_tbl$ref_ym2), cpi_yoy]]
sig_tbl[, cu_yoy  := CUk[.(sig_tbl$ref_ym2), cu_yoy]]
say("성분 결측: t5_lvl %d · t5_mom %d · cpi_yoy %d · cu_yoy %d (총 %d 신호월)",
    sum(is.na(sig_tbl$t5_lvl)), sum(is.na(sig_tbl$t5_mom)),
    sum(is.na(sig_tbl$cpi_yoy)), sum(is.na(sig_tbl$cu_yoy)), nrow(sig_tbl))

## expanding z (최소 36개월) — 각 시점까지의 과거+현재만 사용
exp_z <- function(x, min_n = 36L) {
  n <- length(x); out <- rep(NA_real_, n)
  cs <- cumsum(ifelse(is.na(x), 0, x)); cn <- cumsum(!is.na(x))
  cs2 <- cumsum(ifelse(is.na(x), 0, x^2))
  for (i in seq_len(n)) {
    if (is.na(x[i]) || cn[i] < min_n) next
    m <- cs[i]/cn[i]; vv <- cs2[i]/cn[i] - m^2
    s <- if (vv > 0) sqrt(vv * cn[i]/(cn[i]-1)) else NA_real_
    if (is.finite(s) && s > 0) out[i] <- (x[i] - m)/s
  }
  out
}
setorder(sig_tbl, sig_date)
sig_tbl[, z1 := exp_z(t5_lvl - 2.0)]
sig_tbl[, z2 := exp_z(t5_mom)]
sig_tbl[, z3 := exp_z(cpi_yoy)]
sig_tbl[, z4 := exp_z(cu_yoy)]
sig_tbl[, n_z := (!is.na(z1)) + (!is.na(z2)) + (!is.na(z3)) + (!is.na(z4))]
sig_tbl[, infl := fifelse(n_z == 4L,
                          (fcoalesce(z1,0)+fcoalesce(z2,0)+fcoalesce(z3,0)+fcoalesce(z4,0))/4,
                          NA_real_)]
say("infl_t 산출 %d개월 (4성분 전부 가용) · %s ~ %s",
    sum(!is.na(sig_tbl$infl)),
    as.character(min(sig_tbl[!is.na(infl)]$sig_date)), as.character(max(sig_tbl[!is.na(infl)]$sig_date)))
say("infl 분포: 평균 %.3f · sd %.3f · [%.2f, %.2f]",
    mean(sig_tbl$infl, na.rm=TRUE), sd(sig_tbl$infl, na.rm=TRUE),
    min(sig_tbl$infl, na.rm=TRUE), max(sig_tbl$infl, na.rm=TRUE))
say("infl 자기상관 ACF lag1~6: %s",
    paste(sprintf("%.2f", acf(sig_tbl[!is.na(infl)]$infl, lag.max=6, plot=FALSE)$acf[2:7]), collapse=" "))

saveRDS(list(vintage = vin, sig_dates = sig_dates, ME = ME, ELIG = ELIG,
             fwd = fwd, liq20 = liq20, liq1d = liq1d, FAC = FAC, sig_tbl = sig_tbl),
        file.path(OUT, "panels.rds"))
say("저장: %s/panels.rds", OUT)
